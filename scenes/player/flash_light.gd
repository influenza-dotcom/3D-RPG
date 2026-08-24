extends SpotLight3D

## The player's FLASHLIGHT — a head-height torch toggled by the "Light" action (F OR L by default, left-stick
## click on a pad — F is shared with Interact and defers to it, L never does; see _unhandled_input). EVERY
## player has it from the first frame: it is part of the camera rig, NOT an unlockable Ability, so there is no
## chip to buy and no has_mechanic gate. (This node used to drive the LASER SIGHT, which was an unlockable and
## shared this key; the laser is gone and the key is the torch's alone.)
##
## ⭐IT FOLLOWS YOUR AIM WITH A LAG, ON PURPOSE. `top_level` (set in _ready) detaches it from the parent
## transform, so instead of rigidly welding to the camera it snaps its POSITION to `light_position` each frame
## and eases its ROTATION toward where you are looking at `follow_rate`. That lag is what reads as a torch held
## in a hand rather than a lamp bolted to your skull — a rigid mount looks wrong precisely because it is too
## perfect. The easing is exp-based, so the feel is identical at any frame rate.
##
## ⭐THE BEAM ORIGIN MUST NOT SIT ON THE EYE, OR THE TORCH CASTS NO VISIBLE SHADOWS. This is geometry, not a
## setting: a light exactly at the camera puts every shadow it casts perfectly BEHIND the thing casting it, so
## the caster hides its own shadow and the world reads as flat, shadowless fill — `shadow_enabled` can be on the
## whole time (it is, authored on the node) and you still see nothing. The rig's `LightPosition` marker is
## therefore authored OFF the lens — left of it (mirroring the gun's +0.187 on the right, so the torch reads as
## the off hand) and below it — and that separation is the entire reason shadows appear. Shrink it back toward
## zero and they vanish again. Keep it well inside the player's capsule: an origin further out than the capsule
## can be shoved through a wall the player is leaning on, and the beam would light the far side of it. ⭐The
## capsule is NOT the authored 0.5 m — CapsuleShape3D.height clamps radius to height/2 and never restores it, so
## the first crouch permanently narrows it to 0.4589 m. The test's ceiling is 0.35 to stay clear of both.
## Measured with `scripts/tools/flashlight_qa_shots.gd` — a windowed GPU run, because no unit test can see this.
##
## ⭐THE NODE'S OWN TRANSFORM IS INERT. `top_level` plus the per-frame `global_position` write below mean the
## FlashLight node's authored position never reaches the screen — the rig used to carry a -0.187 X offset there
## that had NEVER been visible. Move `LightPosition` (or repoint `light_position` at another marker) to relocate
## the beam; nudging the light node itself in the inspector does nothing.
##
## ⭐IT MAKES YOU VISIBLE TO ENEMIES WHILE LIT, and that is the whole stealth trade — TWO costs, not one.
## (1) The light meter: PlayerLightLevel auto-collects every Light3D and weighs it by energy and distance, and this
## lamp sits AT the player, so while it burns the meter saturates and Perception sees a fully-lit target — you lose
## the darkness discount. (2) The BEACON penalty: on its own, (1) only ever cancels a discount (light_exposure
## clamps at 1.0, the same as standing under a streetlamp), so a torch would still be free. So this node also joins
## the &"carried_light" group, which PlayerLightLevel reads into player.carried_light — enemies then spot you from
## FURTHER AWAY and lock on FASTER while it is lit (tuned on GameSettings.light_stealth: carried_light_sight_mult /
## carried_light_detect_mult). Crouching does NOT hide it: the crouch range discount and the beacon penalty
## multiply, so sneaking with the torch on is barely sneaking at all. Switch it off and both costs vanish at once —
## the sampler skips INVISIBLE lights, and `visible` is already false whenever the toggle is off or you are dead.
## Set `reveals_you = false` to opt out of both: that joins &"stealth_light_exempt" instead (the group the sampler
## already honours) and skips &"carried_light", so the beam becomes free stealth-wise.
##
## The click is the authored FlashlightClick child (an AudioStreamPlayer3D); delete or mute it for a silent torch.

## How snappily the beam chases where you are looking. Higher = tighter to the aim, lower = a heavier swing.
@export var follow_rate: float = 15.0
## Marker the beam's ORIGIN snaps to each frame (it is top_level, so it does not inherit the camera transform).
## Authored to the rig's LightPosition, held OFF the lens (left and below) so the torch casts visible shadows —
## see the class doc: an origin ON the eye hides every shadow behind its own caster. Move this to throw the beam
## from a different spot; keep it inside the player's capsule and never zero it.
@export var light_position: Marker3D
## Does the torch start switched ON in a fresh game? Off is the honest default: you reach for it when it gets dark.
@export var start_on: bool = false
## While lit, does this beam make the PLAYER easier for enemies to spot (see the class doc)? Off = the torch is
## invisible to BOTH the stealth light meter and the carried-light beacon penalty — kinder, but it removes the
## light-vs-dark decision the day/night cycle creates. To soften the cost instead of deleting it, leave this ON and
## turn the two carried_light_* dials on GameSettings.light_stealth down toward 1.0.
@export var reveals_you: bool = true

## ⭐TINT THE BEAM WITH THE PLAYER'S OWN BODY GLOW, live. The player emits a light whose COLOUR TRACKS HP
## (`PlayerEmittingLight` on Player.tscn: cyan at full health, blending to red as you are hurt — the blend is
## `Player.health_light_color_for`, driven off the `damaged` signal). With this on, the torch is that same
## colour at every instant, so your beam reddens as you bleed out and you read your own health off the wall in
## front of you.
##
## It COPIES the live node rather than re-deriving the blend, which is what makes "the same colour" true by
## construction: there is one blend, in one place, and any future change to how the glow is tinted is inherited
## here for free. The node's `light_color` authored in camera_rig.tscn is the healthy colour too, so switching
## this OFF (or running with no player glow at all) leaves a beam that still matches a healthy player.
##
## ⭐PURELY COSMETIC: PlayerLightLevel weighs lights by ENERGY, range and distance and never reads colour, so
## this cannot change detection, the crouch douse or the light meter.
@export var match_player_light: bool = true

@onready var flashlight_click: AudioStreamPlayer3D = $FlashlightClick

## The player's body-glow light we copy our colour from (match_player_light). Resolved lazily off the wielder
## and re-resolved if it is ever freed, so a respawned / rebuilt player rig re-links itself.
const GLOW_NODE := "PlayerEmittingLight"

var _light_on: bool = false   ## the toggle state, kept separate from `visible` (death also hides the beam)
var _wielder: Node = null     ## the owning Player, found by ancestor walk (duck-typed; null on a bare test rig)
var _glow: Light3D = null     ## the body glow whose colour we track (null = keep the authored beam colour)

func _ready() -> void:
	# Detach from the parent transform so position/rotation are driven manually below (the smoothed follow).
	# Without this the light rigidly snaps with the camera and the hand-held feel is gone.
	top_level = true
	_light_on = start_on
	visible = _light_on
	_wielder = _find_wielder()
	# Both halves of the stealth trade are GROUP memberships the existing sampler already checks, never a new branch
	# in PlayerLightLevel — so "who feeds detection" keeps exactly one home (see _light_contribution_for and
	# _sample_carried there). CARRIED_LIGHT is what makes the torch a liability at RANGE; STEALTH_LIGHT_EXEMPT is
	# the opt-out that also drops us out of the light meter. Membership is static, but the sampler re-reads
	# `visible` every tick, so the toggle (and death) turns the penalty off without touching groups.
	if reveals_you:
		add_to_group(Groups.CARRIED_LIGHT)
	else:
		add_to_group(Groups.STEALTH_LIGHT_EXEMPT)

## The owning Player, located by walking ANCESTORS for the liveness surface rather than by a deep relative path
## (the old `../../../../Weapon/Attack` broke whenever the rig moved). Duck-typed: anything with is_alive() will
## do, and a bare rig in a test finds nothing and is treated as alive.
func _find_wielder() -> Node:
	var n: Node = get_parent()
	while n != null:
		if n.has_method(&"is_alive"):
			return n
		n = n.get_parent()
	return null

func _process(delta: float) -> void:
	# A DEAD player's torch goes out: die() never touches this node and _process keeps running through the whole
	# death cinematic, so without this the corpse would sweep a live beam across the world while the camera rolls.
	# Duck-typed (a rig with no wielder counts as alive), and is_alive() flips back on respawn — so the torch
	# simply comes back on if it was on when you died.
	var alive: bool = _wielder == null or not _wielder.has_method(&"is_alive") or _wielder.is_alive()
	visible = _light_on and alive
	_match_glow_color()

	if light_position != null:
		global_position = light_position.global_position
	# Aim where the camera looks. Our parent IS the camera, so its rotation is the target; the ease below is what
	# makes the beam trail the turn. While off, snap instead of easing — a torch switched on mid-turn must not
	# swing in from wherever it was last pointing.
	var target_rot: Vector3 = get_parent().global_rotation
	if visible:
		var t := 1.0 - exp(-follow_rate * delta)
		global_rotation.x = lerp_angle(global_rotation.x, target_rot.x, t)
		global_rotation.y = lerp_angle(global_rotation.y, target_rot.y, t)
		global_rotation.z = lerp_angle(global_rotation.z, target_rot.z, t)
	else:
		global_rotation = target_rot

## Copy the player's body-glow colour onto the beam (see match_player_light). Written only when it actually
## CHANGED — the glow only moves when HP does, so the common frame costs a comparison instead of a
## RenderingServer write. Degrades to the authored beam colour whenever there is no glow to read (a bare rig in
## a test, a player prefab without the node), so the beam is never left black.
func _match_glow_color() -> void:
	if not match_player_light:
		return
	if not is_instance_valid(_glow):
		_glow = null
		if _wielder != null:
			_glow = _wielder.get_node_or_null(GLOW_NODE) as Light3D
		if _glow == null:
			return
	if light_color != _glow.light_color:
		light_color = _glow.light_color

## Toggle on the "Light" action. Deliberately NOT gated on the weapon: a flashlight is not a gun attachment, so
## it answers unarmed, mid-reload and with your hands full — the things that stop it are being dead (which would
## otherwise flick the beam and click over the death cinematic) and the two gates below.
##
## ⭐F IS A SHARED KEY AND THE TORCH IS ITS FALLBACK — the same contextual-key rule the lean runs on
## (scripts/player/lean.gd). `Light` binds BOTH F and L. F is also Interact (`PickUp`), so a press on it belongs
## to the interact whenever the ray is holding a live target, and only falls through to the torch when it is not.
## L is the torch's ALONE and never defers. That second binding is not a convenience — it is what makes the
## share survivable: `interact_available()` is true for the WHOLE time you are carrying a prop, and for any
## throwable inside the ray's 3 m, so F alone would pin the beam shut in a dark room full of junk, which is
## exactly where you reach for it. Rebinding Flashlight in Options replaces both keys with the one you pick
## (Settings.rebind_action swaps same-device events), and a torch on its own key simply stops deferring.
##
## ⭐THE CONTEXTUAL TEST IS EVENT-LEVEL, NOT `actions_share_binding()`. That helper compares ACTIONS, and this
## action also carries the pad's left-stick click while `PickUp` carries Y — controls that share nothing. An
## action-level test would therefore refuse the PAD toggle whenever an interactable was in the crosshair, on a
## device where the two were never on one button at all. Asking the EVENT which actions it fires keeps each
## device honest, and it subsumes the rebind escape hatch for free: move Flashlight off F and the key event
## stops matching `PickUp`, so the deferral ends with no code change. (⭐The lean still uses the action-level
## helper and has that latent pad bug today — see lean.gd's `_verb_wins`.)
##
## ⭐THE HARD GATE IS OLDER THAN THE SHARED KEY AND WAS MISSING. `PickupRay.interact_available()` deliberately
## does NOT gate on menus or dialogue (see its header — the lean already owned that gate), and this node sits
## LATER in the rig than both the ray and every modal screen. `_unhandled_input` runs in REVERSE tree order, so
## the torch sees the press FIRST and can never wait to learn whether someone else consumed it. Without this the
## key flicks the beam and plays the click on every screen-close and every dialogue advance — and since the
## player menus deliberately do not pause the tree, that was already a live defect on the old dedicated key.
func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed(InputManager.action_light):
		return
	if _wielder != null and _wielder.has_method(&"is_alive") and not _wielder.is_alive():
		return
	if DialogueManager.is_active() or InputManager.gameplay_suppressed():
		return
	if event.is_action_pressed(InputManager.action_pickup) and _interact_pending():
		return
	_light_on = not _light_on
	if is_instance_valid(flashlight_click):
		AudioManager.play_varied(flashlight_click)


## Is a contextual Interact holding a live target this instant? Read through the wielder's duck-typed verb scan —
## the SAME list the lean arbitrates against — so the torch and the interact can never disagree about what one
## press meant, and a future verb driver that shares this key is honoured here for free. A bare rig in a test has
## no wielder and no scan, so the torch stays unconditional there, mirroring Lean._verb_wins().
func _interact_pending() -> bool:
	if _wielder == null or not _wielder.has_method(&"pending_verb_actions"):
		return false
	var pending: Array = _wielder.pending_verb_actions()
	return pending.has(InputManager.action_pickup)
