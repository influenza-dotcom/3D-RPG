class_name Lean
extends Node

## @system Player Movement
## @seam THE contextual-key arbiter for the lean keys: owns_action() is what SilentTakedown / PetInteraction ask before charging, and Player.pending_verb_actions() is what this asks before claiming a press.
## @risk Drop the owns_action() gate in a verb driver (SilentTakedown / PetInteraction _can_run) and a lean that sweeps an eligible target into the crosshair silently charges that verb UNDER the peek — no error, just a kill you didn't ask for.
## @risk Move the lean onto the player's CollisionShape3D instead of the head rig: every movement system assumes the capsule is where the body is, and a peeking capsule clips cover / desyncs what NPCs shoot at.
## @test res://tests/test_lean.gd
## The LEAN verb — the Deus Ex / Cruelty Squad corner-peek. HOLD LeanLeft / LeanRight (defaults Q / E on the
## keyboard, L1 / R1 on a pad) to slide the camera rig sideways and roll it into the lean, so you can look —
## and shoot, since Player.get_aim_origin() starts at the camera — round a corner.
##
## COSMETIC BODY, REAL VIEW. This moves the HEAD RIG (`head`), never the CharacterBody3D capsule. A lean can't
## push you through geometry, desync the navmesh, or change the shape an NPC's fire has to hit: you expose your
## VIEW, not your hitbox. It DOES move the camera, so the shot origin, the flashlight, and the interaction ray
## all lean with you — that IS the mechanic. See PlayerLeanSettings for why this is deliberate.
##
## ⭐THE CONTEXTUAL-KEY RULE — the whole reason this component is shaped like this.
## Q and E were both taken when the lean was added: E was Interact (`PickUp`) and Q is the Takedown/Pet verb.
## So lean is the FALLBACK on a shared key. (⭐Interact has since moved to F, so TODAY only the Q side actually
## shares — E just peeks. The arbitration below is unchanged and still runs every press: it reads the LIVE
## InputMap, finds nothing sharing E, and leans.) At the instant a lean action is PRESSED we ask the Player whether any contextual verb has a
## live target on an action that SHARES this key's binding (Player.pending_verb_actions() +
## InputManager.actions_share_binding). If one does, the press belongs to the verb and we never lean; if none
## does, we CLAIM the key for the rest of the hold and the verb drivers stand down (they ask owns_action()).
##   * Deciding ONCE, on the press — not every frame — is what stops a lean collapsing the moment you peek an
##     interactable or an unaware NPC into your crosshair, which is exactly when you're leaning.
##   * The claim is what stops the OTHER half of that: without it, a lean that swept an eligible NPC into view
##     mid-hold would quietly start charging a silent takedown under the peek.
##   * NOTHING here hard-codes "Q" or "E". Rebind a lean side to its own key in Options → Controls and
##     actions_share_binding() finds no shared event, so that side simply leans unconditionally, forever —
##     which is exactly what moving Interact off E did to the right side.
##
## Designer surface: GameSettings.player_lean (PlayerLeanSettings.tres) — enabled / max_offset / max_roll_deg /
## lerp_speed / the wall-probe group / allow_airborne. Wire `player` + `head` in the inspector (Player.tscn does,
## and Player._enter_tree re-injects them so an extraction that clears the exports still works — the Crouch idiom).

## The player CharacterBody3D this lean belongs to — its transform gives the sideways direction, its RID is excluded from the clearance probe, and its state (dying / climbing / sliding / airborne) gates the lean. Wire to the player root.
@export var player: CharacterBody3D
## The camera-rig root that actually leans: its local X slides and its local Z rolls. Wire to the player's Head. (Crouch drives the SAME node's local Y — the two never touch the same component of the transform.)
@export var head: Node3D

## The APPLIED lean blend: -1 = full left, 0 = upright, +1 = full right. Eased toward the (wall-clamped) target
## every physics frame. Read by anything that wants to know how far out the player is peeking.
var lean_t: float = 0.0

## The head's AUTHORED local X, captured in _ready — the rest position every lean is measured from. Captured
## rather than assumed 0.0 because Player.tscn nudges the whole rig off-centre by a few millimetres; writing an
## absolute offset instead would silently discard that authored nudge (the same trap the flashlight's
## LightPosition marker hit in 2026-08-19).
var _base_x: float = 0.0
## Per-side key CLAIMS — true while THIS lean owns that key for the current hold. Set on the press (once), cleared
## on the release. See the contextual-key rule in the header; owns_action() is the read side the verbs use.
var _owned_left: bool = false
var _owned_right: bool = false
## Seconds since the wielder was last standing on the floor — the coyote-time counter behind
## PlayerLeanSettings.ground_grace. See _posture_allows for why a lean must tolerate a moment of air.
var _airborne_t: float = 0.0
## The sideways clearance probe's shape, built once. Its radius is refreshed from settings per probe so a designer
## dragging probe_radius sees it live.
var _probe_shape: SphereShape3D = null


func _ready() -> void:
	if head != null:
		_base_x = head.position.x
	_probe_shape = SphereShape3D.new()
	_probe_shape.radius = _settings_radius()
	# Run AFTER the default-priority nodes in the same physics frame — specifically after PickupRay,
	# SilentTakedown and PetInteraction have refreshed their targets — so a press claim reads THIS frame's verb
	# state, not last frame's. Without it, pressing the key on the exact frame a target came into view could
	# claim a lean the verb had already taken.
	process_physics_priority = 1


func _physics_process(delta: float) -> void:
	var s: PlayerLeanSettings = GameSettings.player_lean
	if s == null or head == null:
		return
	_track_airborne(delta)
	var target := _wanted_side(s)
	if target != 0.0 and s.max_offset > 0.0:
		# Clamp the DESTINATION by the wall, not the current pose: the probe always fires from the upright rest
		# position, so the available room is the same number whether we're mid-lean or standing straight — no
		# feedback loop where leaning shortens the next frame's allowance.
		target *= _clearance(signf(target), s)
	lean_t = move_toward(lean_t, target, maxf(0.0, s.lerp_speed) * delta)
	_apply(lean_t, s)


## The side the player is ASKING for this frame: -1 left, +1 right, 0 upright. Runs the two gates in the order
## that matters (see below), applies the contextual-key rule, and leaves the wall clamp to the caller.
##
## ⭐THE TWO GATES ARE NOT THE SAME KIND OF GATE, and collapsing them back into one is the bug this shape exists
## to prevent (2026-08-20, "i cant shoot and lean at the same time"):
##   * A HARD gate (_input_is_ours) means the key press is not ours AT ALL — the player is dead, mid-conversation,
##     or a menu owns the keyboard. Drop the claims so the verbs get their key back, and swallow the press.
##   * A POSTURE gate (_posture_allows) means "not right now, but the key is still YOURS" — you left the floor,
##     you are climbing, you are sliding. It must ONLY zero the lean target. Releasing the claim here strands a
##     HELD key: the claim is re-decided on `just_pressed` alone, so once dropped mid-hold nothing re-arms it and
##     the lean is dead until you physically let go. Every weapon's `self_knockback` un-grounds you for a few
##     frames on EVERY shot, so a hard posture gate meant one trigger pull permanently killed the peek.
## Polling both sides ABOVE the posture gate matters for the same reason: it keeps the claim alive (and keeps the
## takedown/pet verbs standing down) across the airborne blip, so the lean eases back the instant you land.
func _wanted_side(s: PlayerLeanSettings) -> float:
	if not s.enabled or not _input_is_ours():
		_release_claims()
		return 0.0
	var left := _side_held(InputManager.action_lean_left, true)
	var right := _side_held(InputManager.action_lean_right, false)
	if not _posture_allows(s):
		return 0.0  # claims deliberately KEPT — ease out, and ease straight back when the posture clears
	if left == right:
		return 0.0  # neither, or BOTH (holding the two together stands you straight — the WASD opposing-input rule)
	return -1.0 if left else 1.0


## HARD gate — is this key press ours to answer at all? Never mid-dialogue or with a modal/menu up (those own the
## keyboard, and E in particular advances/closes them), never while dead or mid-death-cinematic. A bare/AI body
## (no Player cast) has none of that state and simply leans.
func _input_is_ours() -> bool:
	if DialogueManager.is_active() or InputManager.gameplay_suppressed():
		return false
	var p := player as Player
	if p == null:
		return true
	return not p.get(&"_dying") and p.is_alive()


## SOFT gate — may we be leaning right now, given the body's posture? A wall climb rides the wall and a slide is
## its own pose, so neither composes with a peek. Airborne is a designer choice (allow_airborne, off by default)
## softened by a coyote-style grace window, so a weapon's recoil hop or a stair seam doesn't even dip the lean.
func _posture_allows(s: PlayerLeanSettings) -> bool:
	var p := player as Player
	if p == null:
		return true
	if p.is_climbing() or p.is_sliding():
		return false
	return s.allow_airborne or _airborne_t <= maxf(0.0, s.ground_grace)


## Advance the coyote counter behind ground_grace. Only a real Player has a floor state; a bare/AI body stays at
## 0 (grounded), which is what keeps an off-tree unit rig leaning.
func _track_airborne(delta: float) -> void:
	var p := player as Player
	if p == null or p.is_on_floor():
		_airborne_t = 0.0
	else:
		_airborne_t += delta


## Poll one side, maintaining its claim. The claim is decided ONCE on the press (a contextual verb waiting on a
## key that shares this binding wins the press outright) and dropped on the release. Returns whether this side is
## currently leaning.
func _side_held(action: StringName, is_left: bool) -> bool:
	if InputManager.is_action_just_pressed(action):
		_set_claim(is_left, not _verb_wins(action))
	if not InputManager.is_action_pressed(action):
		_set_claim(is_left, false)  # also catches a press+release inside ONE physics frame: claimed, then dropped
	return _owned_left if is_left else _owned_right


func _set_claim(is_left: bool, owned: bool) -> void:
	if is_left:
		_owned_left = owned
	else:
		_owned_right = owned


func _release_claims() -> void:
	_owned_left = false
	_owned_right = false


## True when pressing `lean_action` right now would ALSO fire a contextual verb — i.e. some driver on the Player
## is holding a live target for an action that shares a physical binding with this one. That is the whole
## E-is-Interact / Q-is-Takedown case. Bound to its own key, a lean action shares no event with any verb and this
## is false forever, so lean stops being contextual (see the header).
func _verb_wins(lean_action: StringName) -> bool:
	var p := player as Player
	if p == null:
		return false  # a bare/AI test body has no verb drivers — nothing can out-rank the lean
	for verb in p.pending_verb_actions():
		if InputManager.actions_share_binding(lean_action, verb):
			return true
	return false


## THE read side of the claim, asked by the verb drivers that share a lean key (SilentTakedown / PetInteraction
## in _can_run). True while the current lean is holding a key that also binds `action` — the verb then stands
## down for the rest of the hold, so a peek can never charge a takedown underneath itself.
func owns_action(action: StringName) -> bool:
	if _owned_left and InputManager.actions_share_binding(InputManager.action_lean_left, action):
		return true
	return _owned_right and InputManager.actions_share_binding(InputManager.action_lean_right, action)


## The fraction of max_offset actually available toward `side` (-1 left / +1 right), in [0, 1]. A sideways sphere
## shape-cast from the UPRIGHT head position measures the room; the head stops probe_margin short of whatever it
## hits. Returns 1.0 (full lean) when there's nothing to probe against — off-tree, no space state, or a zero-size
## probe. A probe that starts already overlapping (the player crammed into a corner) yields 0, i.e. no lean, which
## is the safe answer.
func _clearance(side: float, s: PlayerLeanSettings) -> float:
	if player == null or not player.is_inside_tree() or head == null or _probe_shape == null:
		return 1.0  # _probe_shape is built in _ready, so a bare .new() driven by hand simply skips the probe
	var reach := s.max_offset + maxf(0.0, s.probe_margin)
	if reach <= 0.0001:
		return 1.0
	var space := player.get_world_3d().direct_space_state
	if space == null:
		return 1.0
	var parent := head.get_parent_node_3d()
	if parent == null:
		return 1.0
	var rest_local := head.position
	rest_local.x = _base_x
	var q := PhysicsShapeQueryParameters3D.new()
	_probe_shape.radius = _settings_radius()
	q.shape = _probe_shape
	q.transform = Transform3D(Basis(), parent.global_transform * rest_local)
	q.motion = parent.global_basis.x.normalized() * (side * reach)
	q.exclude = [player.get_rid()]
	q.collision_mask = s.probe_collision_mask
	# cast_motion returns [safe_fraction, unsafe_fraction]; the SAFE one is how far the sphere can travel before
	# touching anything. Spend the margin out of that budget first, so the head rests a hand's width off the wall.
	var hit := space.cast_motion(q)
	if hit.size() < 1:
		return 1.0
	return clampf((hit[0] * reach - s.probe_margin) / s.max_offset, 0.0, 1.0)


## Write the pose: slide the rig off its authored rest X, and roll it INTO the lean. The roll sign matches the
## strafe tilt CameraEffects already applies (strafing right rolls negative), so the two compose instead of
## fighting each other's convention — and it rides the SAME accessibility toggle, so "Camera Tilt" off leaves
## you the positional peek with a level horizon.
##
## ⭐Writing head.rotation.z is safe next to Head's own pitch math ONLY because the Head never yaws (yaw lives on
## the Player body). With rotation.y pinned at 0 the basis is Rx(pitch) * Rz(roll), which `rotate_x` pre-multiplies
## into Rx(pitch+d) * Rz(roll) and the YXZ euler read-back recovers exactly — so Head's `rotation.x = clamp(...)`
## keeps working and never eats the roll. Put a yaw on the Head and that stops being true.
func _apply(t: float, s: PlayerLeanSettings) -> void:
	head.position.x = _base_x + t * s.max_offset
	var roll := deg_to_rad(s.max_roll_deg) if Settings.camera_tilt_enabled else 0.0
	head.rotation.z = -t * roll


## Snap fully upright THIS FRAME and drop any key claims. Called on BOTH ends of a death, and it must be:
##   * Player.die(), immediately BEFORE it freezes this node's _physics_process — freezing alone latches the
##     death frame's lean_t, so a death taken mid-peek would play the whole keel-over cinematic from a camera
##     shifted max_offset sideways and rolled max_roll_deg over.
##   * Player._respawn_at_checkpoint, immediately BEFORE it re-enables that process — so the fresh life starts
##     level even if something moved the rig while it was frozen, and so the verb drivers aren't left standing
##     down for a hold that ended with the last life.
## Mirrors Crouch.reset().
func reset() -> void:
	lean_t = 0.0
	_airborne_t = 0.0
	_release_claims()
	if head != null:
		head.position.x = _base_x
		head.rotation.z = 0.0


func _settings_radius() -> float:
	var s: PlayerLeanSettings = GameSettings.player_lean
	return maxf(0.01, s.probe_radius) if s != null else 0.22
