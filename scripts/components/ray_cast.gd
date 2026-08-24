class_name PickupRay
extends RayCast3D

## @system Interaction
## @seam _query_talk_handler is THE line-of-sight wall-gate for every look-at interactable (pickup/loot/talk/doors): its talk-ray is gated by _interaction_occluded (a second solid-body ray, target's own bodies excluded).
## @risk Broaden the occlusion mask or drop the target-own-body exclusion (_interaction_occluded's collision_mask + _target_body_exclusions): silent interact-through-walls, or a dropped item self-occludes and is unpickable on open floor.
## @seam interact_available()/pending_verb_action() answer "would an F press DO something right now?" — the Interact half of the contextual-key rule for BOTH fallbacks that share a key with it (scripts/player/lean.gd on Q, scenes/player/flash_light.gd on F); it must stay in lockstep with the PickUp branch of _unhandled_input.
## @risk Break the closer-prop block (_closer_prop_blocks — the _talk_distance / is_ancestor_of guard, now shared by the PickUp press, _update_talk_target and interact_available): a covered NPC lights up/reads out through a crate, or a dual item's own body blocks its own stash.
## @risk Add an outcome to the PickUp branch without adding it to interact_available(): a fallback claims that press instead and the new interact silently never fires — the lean swallows it on Q, and on F the FLASHLIGHT toggles over it. The reverse is now just as costly: widen interact_available() and F stops reaching the torch for as long as the new condition holds (this is why carrying a prop, which is true the whole time you carry it, needs L as the torch's second key).
## @risk Remove either liveness bail (the `player as Character` is_alive() gates at the TOP of _unhandled_input AND _physics_process): a mid-death-cinematic F/Z/click grabs/interacts/throws — the prop survives the revive or freezes the cinematic — or the corpse camera keeps painting the hover outlines/readout and greeting NPCs it sweeps across.
## @risk Fold the per-prop throw_impulse_mult multiply INTO the throw test (launch_impulse / is_throw_release read the RAW impulse first): a fast-throw prop's gentle tap-DROP then scales past the throw threshold and silently noses, plays the throw sound, and credits the player with an attack.
## @test res://tests/test_interaction_occlusion.gd
## @test res://tests/test_pickup_ray_liveness.gd
## @test res://tests/test_interact_prompts.gd
## @test res://tests/test_carry_step_over.gd
## @test res://tests/test_throw_release_policy.gd
## Physics-object pickup / carry / throw. A RayCast3D from the camera detects the aimed Throwable.
## TWO-PRESS model (see _grab_or_arm_release / _release_held): press PickUp (F) or Throw (Z) aimed at a
## Throwable to GRAB it and carry it hands-free — the key-up does NOT drop it, so you keep carrying with the
## key released. Press the SAME key AGAIN while carrying to ARM the release; the duration you hold that second
## press decides the outcome on ITS key-up — a long hold THROWS (impulse), a quick tap gently DROPS. The first
## release after a grab is therefore intentionally inert: arming the timer on the grab instead would launch the
## prop the instant you let go, making hands-free carry impossible. SHORTCUT: while carrying, a single Attack
## press (default LEFT-CLICK — the gun is holstered/draw-locked with your hands full, so it can't fire) throws the
## prop straight away at full impulse, bypassing the two-press model. While held the body is frozen kinematic with
## gravity off and chased toward hold_anchor each frame via collision-aware motion. Several robustness fixes are
## documented at their call sites: a grab "grace" ease-in (anti-clip on pickup), stack-wake (stops a stack
## floating when you pull a box out), safe-motion casting (no clipping through walls), and a deferred slide-off
## so a dropped crate can't trap the player. A carried prop is deliberately INERT against characters — walking it
## into an NPC never shoves them (the held prop rides the held-prop collision layer, which no character body
## collides with, so it simply passes through). Line-of-FIRE and a real THROW still hurt/knock back as normal.

signal carry_changed(holding: bool)  ## a physics prop was grabbed (true) or dropped/lost (false) -- drives the player's view-model hands

const PICKUP_GRACE_TIME: float = 0.25
const PICKUP_GRACE_STEP_RATIO: float = 0.25
const STACK_WAKE_RADIUS: float = 1.0
const STACK_WAKE_TIME: float = 0.6
const STACK_WAKE_NUDGE: float = 0.05
const TALK_REACH: float = 3.5  ## metres the look-at talk query reaches down the camera ray
const INTERACT_OCCLUSION_SKIP: float = 0.05  ## numerical pullback so a hitbox flush with its own surface isn't read as the wall
const OCCLUSION_SELF_DEPTH: int = 3  ## levels to walk UP from the talk hitbox gathering the target's OWN bodies to exclude from the LOS ray
## Numerical guards for the carry STEP-OVER (see _advance_held). Not gameplay-feel knobs — the tunable feel knob is the
## pickup_step_up_height @export on PhysicsDamageSettings; these are just epsilons, so they stay consts like PICKUP_GRACE_*.
const STEP_OVER_ENGAGE_EPSILON: float = 0.005  ## how far short (m) the direct cast must fall before a step-over is even attempted — ignores a sub-mm graze on a doorframe
const STEP_OVER_MIN_PROGRESS: float = 0.02  ## extra horizontal (XZ) travel (m) a lift must buy over the direct cast to be kept — a wall yields ~0 here, so it's always rejected (the wall-vs-stair test)
const PICKUP_DEPEN_PUSH: float = 0.03  ## per-frame push-out (m) along the contact normal when a rotated facing prop is found penetrating a step/wall — breaks the cast_motion [0,0] deadlock

## The wielding player body, excluded from carry collision and used as the throw velocity source; injected by Head.setup().
@export var player: CharacterBody3D
## The point in front of the camera a carried object is chased toward each frame; move it to change how far ahead props are held.
@export var hold_anchor: Marker3D

var held_object: Throwable = null
## True from a grab until release/recover. A FREED Object is indistinguishable from null in Godot 4 — `if freed` is
## false, `freed == null` is true, `is_instance_valid(freed)` is false (all verified) — so held_object alone can't tell
## "carrying a prop that just got freed out from under us" (a gib's lifetime fade, an NPC shooting it apart, the gib cap
## reclaiming it) from "carrying nothing". This flag survives the free, so the per-frame recovery can still fire
## carry_changed(false); without it the player is stranded "carrying" a dead reference with the gun holstered + draw-locked.
var _holding: bool = false
var _prior_gravity_scale: float = 1.0
var _prior_collision_layer: int = 1
var _prior_freeze: bool = false
var _prior_freeze_mode: RigidBody3D.FreezeMode = RigidBody3D.FREEZE_MODE_STATIC
var _release_timer_started_us: int = -1
var _last_targeted: Throwable = null
var _pickup_grace_remaining: float = 0.0
var _stack_wake_remaining: float = 0.0
var _stack_wake_origin: Vector3 = Vector3.ZERO
var _talk_handler: Node = null  ## the talk target under the crosshair — drives the NAME readout + the interact (any talkable, even a hostile NPC), or null
var _highlighted: Node = null  ## the talk target currently showing the white look-highlight — INTERACTABLE only, so a hostile NPC reads out its name without a misleading outline
var _talk_distance: float = INF  ## camera→talk-target distance for the active highlight (INF = none)
var _readout_shown: bool = false  ## is the centre look-at name currently displayed? (lets us clear it when
								  ## the target is freed/looked-away even after the handler ref is gone)

func _exit_tree() -> void:
	force_release_held()

func _unhandled_input(event: InputEvent) -> void:
	# T2 liveness bail (FIRST, before any input branch): a DEAD player must not grab a prop, interact, or throw. The
	# player node stays IN-TREE through the whole death cinematic (Character.take_damage sets _dead=true before die()),
	# so raw input would still route here — a prop grabbed mid-keel-over would survive the in-place revive still carried
	# (C9), and an E over shop/heal/chess would freeze the cinematic (C14). is_alive() is `not _dead and hp>0`, false for
	# the entire cinematic. `player as Character` downcasts (Player extends Character) and is null for a bare/AI test body,
	# so this simply never bails there.
	var pl := player as Character
	if pl != null and not pl.is_alive():
		return
	if event.is_action_pressed("PickUp"):
		# A menu, cutscene, or the name-entry dialog is up? Don't start a talk / grab / pickup, and DON'T consume the
		# event — let it propagate so a transaction screen (loot/shop/heal/…) can close on the same key. M5/T2: gate over
		# any menu (any_modal_open) PLUS cutscenes + the pet-naming NameEntryDialog (gameplay_suppressed is the strict
		# superset), matching every other combat input — pressing F over a menu/cutscene used to leak an interact.
		if InputManager.gameplay_suppressed():
			return
		# While a conversation is up, the interact key advances the box (DialogueManager handles
		# it); don't pick up or start another talk, and don't consume it so it still propagates.
		if DialogueManager.is_active():
			return
		# Interact takes priority over a physical grab: aimed at a talk/loot/pickup target (and not already
		# carrying) means E talks / opens loot / ADDS TO INVENTORY instead of grabbing. A dual item — a
		# dropped weapon that's a CanPickUp AND a Throwable — is stashed with E; carrying it to THROW is Z.
		if not held_object and _talk_handler != null and _is_interactable(_talk_handler):
			# ...unless a grabbable prop CLOSER to the camera than the target blocks interacting THROUGH it
			# (grab the prop instead) — UNLESS that prop IS the target's own body (a dual item), where E
			# must still run the interact rather than carry it.
			if not _closer_prop_blocks(_talk_handler):
				_talk_handler.start_talk(player)
				get_viewport().set_input_as_handled()
				return
		_grab_or_arm_release()
	elif event.is_action_released("PickUp"):
		_release_held()
	elif event.is_action_pressed(InputManager.action_throw):
		# Z — grab the aimed throwable to CARRY/THROW, bypassing the talk/inventory interact. Lets you throw
		# a dual item (a dropped weapon) that E would otherwise just stash into the backpack.
		# M5/T2: gate over any menu, a cutscene, or the name-entry dialog (gameplay_suppressed, same as the E press above)
		# — a grab over the open backpack/shop, a cutscene, or the pet-naming prompt was the same leak.
		if DialogueManager.is_active() or InputManager.gameplay_suppressed():
			return
		_grab_or_arm_release()
	elif event.is_action_released(InputManager.action_throw):
		_release_held()
	elif held_object and event.is_action_pressed(InputManager.action_attack):
		# ALTERNATE THROW (default LEFT-CLICK). While you're carrying a prop the gun is holstered AND draw-locked
		# (Player._on_carry_changed — "no gun while your hands are full"), so a fire click can't shoot anyway.
		# Repurpose it as a quick, full-impulse throw straight down the look ray — ONE click launches what you're
		# holding, bypassing the two-press F/Z carry-then-hold-to-release model. The freshly-drawn gun is kept from
		# firing on this SAME held click by Attack.suppress_fire_for_carry_release() (fired from
		# Player._on_carry_changed), mirroring the draw-click rule.
		# Because this branch STANDS IN FOR the fire click while your hands are full, suppress it in exactly the
		# states firing is suppressed: MouseInput gates the shot on InputManager.gameplay_suppressed() — the same gate
		# the F/Z grab presses above now use — which covers any registered modal PLUS cutscenes and the pet-naming
		# NameEntryDialog, neither of which pauses the tree. Match it, or a left-click / trigger-pull would fling
		# the prop across a cutscene when you can't even shoot. (gameplay_suppressed omits dialogue, so keep that.)
		if DialogueManager.is_active() or InputManager.gameplay_suppressed():
			return
		# The click that RE-FOCUSES the game window is not a throw either (2026-08-18). It stands in for the fire click,
		# so it honours MouseInput's refocus latch exactly as the shot does (mouse_input.gd header): Windows delivers
		# the activating click as a real press, and the app-focus notification that arms the latch lands BEFORE this
		# event is flushed, so the latch is already up here. Not consumed — the same click may still close a screen.
		if _refocus_latched():
			return
		_release_timer_started_us = -1  # discard any F/Z-armed release timer — this click owns the throw now
		_release(GameSettings.physics_damage.pickup_throw_impulse)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed(InputManager.action_drop_held):
		# DEDICATED DROP/HOLD (default H): empty your hands one stage at a time — a carried prop goes to the ground
		# WITHOUT a throw, while an empty-handed press takes the WIELDED weapon INTO your hands instead (see
		# _drop_held_in_hand). Same suppression gate as the F/Z/Attack presses above — nothing over a menu / cutscene /
		# name-entry box — and, like them, DON'T consume the event when suppressed so the key can still close a
		# transaction screen.
		if DialogueManager.is_active() or InputManager.gameplay_suppressed():
			return
		_drop_held_in_hand()
		get_viewport().set_input_as_handled()

## The DropHeld / H verb — a TWO-STAGE hand verb, and on your OWN WEAPON a full TOGGLE.
##   * Hands empty: ask the player to take its WIELDED weapon out of the holster and INTO its hands as a carried
##     prop (Player.hold_equipped_weapon), ready to throw.
##   * Carrying THAT weapon: put it straight back — return_held_weapon_to_hands re-bags AND re-wields it, and
##     returns true to say it owned this press. Pressing H twice must leave you exactly where you started, so
##     this branch comes FIRST and never falls through to the drop below (a refused put-back keeps it in hand).
##   * Carrying anything else (a world-grabbed prop, a hotbar-pulled prop — both the SAME _holding carry,
##     distinguished downstream in Player._on_carry_changed): a gentle DROP at the tap-drop impulse, never a throw.
## Throwing the weapon is unchanged and still uses the ordinary carry verbs (left-click, or a Z-hold), and an
## F/Z tap still sets it down — so the toggle costs no way of getting the knife OUT of your hands.
## Gate on `_holding`, NOT `held_object`: a prop freed out from under us leaves held_object falsy while _holding
## stays true (see the _holding docstring), and _release already cleans that freed case up. `player` is exported as
## CharacterBody3D, so both weapon branches downcast `as Player` (the same idiom _drive_readout uses) — the two
## weapon methods live on Player, and the cast is null for a bare/AI test body, where H simply drops as before.
func _drop_held_in_hand() -> void:
	var pl := player as Player
	if _holding:
		if pl != null and pl.return_held_weapon_to_hands():
			return  # H put your own weapon back in your hands — this press was the toggle, not a drop
		_release(GameSettings.physics_damage.pickup_drop_impulse)
		return
	if pl != null:
		pl.hold_equipped_weapon()

## True while the player's MouseInput refocus latch is holding the PRIMARY fire button — i.e. the left click being
## read right now is the click that re-focused the window, not a fresh press. Read through the exported `player`
## (`as Player`, the same idiom as above); null for a bare/AI body, where nothing is latched.
func _refocus_latched() -> bool:
	var pl := player as Player
	return pl != null and is_instance_valid(pl.mouse_input) and pl.mouse_input.fire_blocked_by_refocus()

## Grab the aimed Throwable (start carrying), or — if already carrying — arm the release timer so the
## key-up becomes a drop/throw by hold time. Shared by the PickUp (F) and Throw (Z) presses.
func _grab_or_arm_release() -> void:
	if held_object:
		_release_timer_started_us = Time.get_ticks_usec()
	elif is_colliding():
		var target := get_collider() as Throwable
		if target:
			_pick_up(target)

## Release the carried object: a long hold throws (impulse), a tap gently drops. Shared by the PickUp (F)
## and Throw (Z) releases. The `> 0` gate makes an UN-ARMED release a no-op: the key-up of the GRAB press
## (which never arms the timer) leaves the prop held so you can carry it hands-free — see the class header.
func _release_held() -> void:
	if held_object and _release_timer_started_us > 0:
		var held_for_s := (Time.get_ticks_usec() - _release_timer_started_us) / 1_000_000.0
		var impulse: float = GameSettings.physics_damage.pickup_throw_impulse if held_for_s >= GameSettings.physics_damage.pickup_e_hold_threshold else GameSettings.physics_damage.pickup_drop_impulse
		_release(impulse)
	_release_timer_started_us = -1

## Cleanup path for death / quickload / scene teardown: restore the carried prop's physics state without treating
## it as a deliberate throw. Normal key releases still use _release() and keep throw credit / decoy behavior.
func force_release_held(impulse: float = 0.0) -> void:
	_release_timer_started_us = -1
	if not _holding and held_object == null:
		return
	# Freed-safe: `if held_object` would be falsy for a prop freed while held (see _physics_process), so a death /
	# quickload force-release couldn't restore the gun. _holding preserves that state; a live held_object still
	# cleans up for older/manual callers that populated the ref before the flag existed.
	if not is_instance_valid(held_object):
		held_object = null
		_holding = false
		carry_changed.emit(false)
		return
	_release(impulse, false)

## Per-frame carry update: refresh the highlight, run the pending stack-wake, then —
## if holding — chase hold_anchor with a clamped, collision-safe step. Drops the
## object if it strays past the max hold distance (e.g. yanked through a wall).
func _physics_process(delta: float) -> void:
	# T2 liveness — the per-frame twin of the _unhandled_input bail above: a DEAD player must not keep the hover
	# cues alive. The death cinematic sweeps the camera while PickupRay keeps physics-processing (die() only stops
	# the Player's OWN callback), so without this the corpse still painted the orange throwable outline, the white
	# look-highlight, and the centre name readout — and hover-GREETED NPCs — on whatever crossed the crosshair.
	# Clear once and hold cleared for the whole cinematic; is_alive() flips true again on respawn and the hover
	# updates below simply resume. Everything AFTER this gate still runs while dead: die() already released/stashed
	# the held prop, but the freed-held recovery beneath must stay reachable regardless (same reasoning as ever).
	var pl := player as Character
	if pl != null and not pl.is_alive():
		_clear_look_cues()
	else:
		_update_target_outline()
		_update_talk_target()
	if _stack_wake_remaining > 0.0:
		_stack_wake_remaining = maxf(0.0, _stack_wake_remaining - delta)
		_wake_nearby_bodies(_stack_wake_origin)
	# Recover FIRST (gated on the _holding flag, NOT `if held_object`): a carried prop can be freed out from under us —
	# a gib's lifetime fade/free, an NPC shooting it apart, or the gib cap reclaiming the oldest gib. In Godot 4 a FREED
	# Object is FALSY and compares == null, so the plain `if not held_object` guard below would `return` on the dead
	# reference and NEVER reach this recovery — leaving held_object dangling and carry_changed(false) unfired, so the
	# player stays "carrying" forever with the gun holstered + draw-locked (the reported stuck-until-death). _holding
	# stays true across the free (held_object can't tell us it was ever set), so this branch still catches it.
	if _holding and not is_instance_valid(held_object):
		held_object = null
		_holding = false
		carry_changed.emit(false)
		return
	if not held_object:
		return
	var to_anchor := hold_anchor.global_position - held_object.global_position
	if to_anchor.length() > GameSettings.physics_damage.pickup_max_hold_distance:
		_release(GameSettings.physics_damage.pickup_drop_impulse)
		return
	held_object.linear_velocity = Vector3.ZERO
	held_object.angular_velocity = Vector3.ZERO
	if held_object.faces_carrier_while_held():
		held_object.face_carrier(global_transform)
	var follow_t := 1.0 - exp(-GameSettings.physics_damage.pickup_hold_follow_rate * delta)
	var step := to_anchor * follow_t
	var max_step := GameSettings.physics_damage.pickup_max_step_per_frame
	if _pickup_grace_remaining > 0.0:
		_pickup_grace_remaining = maxf(0.0, _pickup_grace_remaining - delta)
		var grace_t := 1.0 - (_pickup_grace_remaining / PICKUP_GRACE_TIME)
		max_step *= lerpf(PICKUP_GRACE_STEP_RATIO, 1.0, grace_t)
	step = step.limit_length(max_step)
	if step.length() < 0.0001:
		return
	_advance_held(step)

func _safe_motion(body: Throwable, motion: Vector3) -> Vector3:
	if not body.collision_shape or not body.collision_shape.shape:
		return motion
	var space_state := get_world_3d().direct_space_state
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = body.collision_shape.shape
	query.transform = body.collision_shape.global_transform
	query.motion = motion
	query.collision_mask = body.collision_mask
	var exclude: Array[RID] = [body.get_rid()]
	if player:
		exclude.append(player.get_rid())
	query.exclude = exclude
	var result := space_state.cast_motion(query)
	if result.is_empty():
		return motion
	return motion * result[0]

## Move the held prop toward the anchor by `step`, collision-safe, WITH a stair STEP-OVER fallback. The prop is a
## frozen kinematic body we teleport by hand (global_position += ...), so a single _safe_motion cast that clips to
## ~0 — which it does the instant the prop's shape touches a ~0.5 m stair riser — would jam it against the steps
## until the pickup_max_hold_distance auto-drop yanks it away. That's what made props "very hard to bring up stairs"
## once the carry went kinematic: the earlier dynamic (spring-force) hold let the solver slide the prop up over step
## corners; this linear cast-clip can't slide OR step up (only the player body has _try_step_up). Cheapest-first:
##   1. Try the full combined step first — the ORIGINAL path, one cast, ZERO regression. Unobstructed (flat ground,
##      open air, gentle slope, descending stairs) it lands all but a sub-mm graze, so we take it and return.
##   2. Blocked: lift the prop by a step-up budget (pickup_step_up_height, clamped by the normal per-frame cap) and
##      COMMIT that raise to global_position FIRST — mandatory, because _safe_motion re-reads the LIVE
##      collision_shape.global_transform, so the horizontal re-cast only starts "above the lip" if we truly moved up.
##   3. Keep the lift ONLY if it bought real HORIZONTAL (XZ) progress the direct cast couldn't. THIS is the
##      wall-vs-stair discriminator and the whole no-clip guarantee: a flat WALL yields ~0 extra XZ travel at any
##      lift height, so the lift is always rejected and a prop can NEVER ratchet up a wall (even looking straight up
##      at it); a real stair lip opens XZ travel once cleared, so it's accepted and the prop rides the step. On
##      reject we restore the exact pre-lift pose and commit plain `direct`, so nothing drifts upward across frames.
func _advance_held(step: Vector3) -> void:
	var origin := held_object.global_position
	var direct := _safe_motion(held_object, step)
	if direct.length() >= step.length() - STEP_OVER_ENGAGE_EPSILON:
		held_object.global_position = origin + direct  # unobstructed (or a negligible graze) — the original carry path
		return
	# Blocked. Size a step-up lift, capped by the normal per-frame clamp so one frame can't out-climb normal motion.
	var lift_budget := minf(GameSettings.physics_damage.pickup_step_up_height, GameSettings.physics_damage.pickup_max_step_per_frame)
	var lift := _safe_motion(held_object, Vector3(0.0, lift_budget, 0.0)) if lift_budget > 0.0001 else Vector3.ZERO
	# Direct AND straight-up both zeroed => the shape STARTS overlapping geometry. Linear chase is always cast-clipped
	# and never penetrates, so this only happens when a faces_carrier_while_held() yaw (which bypasses _safe_motion,
	# see _physics_process) rotated a corner into a step/wall. Push it back out instead of freezing it against the wall.
	if direct.length() < 0.0001 and lift.y < 0.0001:
		if held_object.faces_carrier_while_held():
			_recover_from_penetration()
		return
	var horizontal := Vector3(step.x, 0.0, step.z)
	if horizontal.length() < 0.0001 or lift.y < 0.0001:
		held_object.global_position = origin + direct  # no lift budget (e.g. step-up disabled) or nowhere to advance
		return
	held_object.global_position = origin + lift  # commit the raise so the horizontal re-cast starts above the lip
	var over := _safe_motion(held_object, horizontal)
	var direct_xz := Vector2(direct.x, direct.z).length()
	var over_xz := Vector2(over.x, over.z).length()
	if step_over_gained_ground(direct_xz, over_xz, STEP_OVER_MIN_PROGRESS):
		held_object.global_position = origin + lift + over  # cleared the step lip — ride up onto the tread
		return
	held_object.global_position = origin + direct  # a wall / dead end: undo the lift, commit plain direct from the ORIGINAL pose

## Pure wall-vs-stair test (static + literal-arg so it's unit-testable, mirroring should_blink / loyal_scale /
## loop_noticed): a lift is a real STEP-OVER only if advancing from the RAISED pose bought meaningfully more
## HORIZONTAL (XZ) travel than the blocked direct cast did. A flat wall gives ~equal (near-zero) XZ both ways, so it
## returns false and the prop can NEVER climb a wall; a stair lip opens XZ travel once cleared, so it returns true and
## the prop rides the step. Caller passes the XZ magnitudes (Vector2(x,z).length()) of the direct and over casts.
static func step_over_gained_ground(direct_xz: float, over_xz: float, min_progress: float) -> bool:
	return over_xz - direct_xz > min_progress

## Pure throw-vs-drop test (static + literal-arg so it's unit-testable, mirroring step_over_gained_ground): a release
## is a real THROW only when it credits a thrower AND its RAW impulse reached the throw threshold. Everything
## throw-only hangs off this one answer — the launch scaling, the throw sound, and the thrown facing.
static func is_throw_release(impulse: float, throw_threshold: float, credit_thrower: bool) -> bool:
	return credit_thrower and impulse >= throw_threshold

## Pure launch-speed policy: a real throw is scaled by the prop's own throw_impulse_mult; a tap-DROP and a forced
## (death / quickload) release are returned UNTOUCHED. THE invariant this exists to pin: the multiplier is applied
## AFTER the throw test reads the RAW impulse, so a prop tuned to fly fast can never have its gentle 1.0 tap-drop
## scaled up past the 12.0 threshold and start nosing / whipping / crediting like a throw.
static func launch_impulse(impulse: float, throw_threshold: float, mult: float, credit_thrower: bool) -> float:
	if not is_throw_release(impulse, throw_threshold, credit_thrower):
		return impulse
	return impulse * mult

## Push a penetrating held prop out along the contact normal. A frozen kinematic body never depenetrates itself, so a
## faces_carrier_while_held() prop whose yaw rotated a corner into a step/wall (face_carrier sets global_transform with
## no collision check) leaves cast_motion returning [0,0] on every axis — _advance_held then makes no progress and the
## prop would hang there until the pickup_max_hold_distance auto-drop. get_rest_info gives the contact normal; nudge the
## body straight out along it so next frame's casts start clear. Masked/excluded exactly like _safe_motion so it only
## reacts to world geometry (never the prop itself or the player).
func _recover_from_penetration() -> void:
	var col := held_object.collision_shape
	if not col or not col.shape:
		return
	var space := get_world_3d().direct_space_state
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = col.shape
	query.transform = col.global_transform
	query.collision_mask = held_object.collision_mask
	var exclude: Array[RID] = [held_object.get_rid()]
	if player:
		exclude.append(player.get_rid())
	query.exclude = exclude
	var info := space.get_rest_info(query)
	if info.is_empty():
		return
	var normal: Vector3 = info["normal"]
	held_object.global_position += normal * PICKUP_DEPEN_PUSH

## Drop every hover cue at once — the orange throwable target outline, the white look-highlight, the talk handler,
## and the centre name readout — for the dead-player gate in _physics_process. It runs every physics frame of the
## death cinematic, so each branch guards on its own state and the call is a no-op once everything is already clear.
func _clear_look_cues() -> void:
	if _last_targeted and is_instance_valid(_last_targeted):
		_last_targeted.set_outline_visible(false)
	_last_targeted = null
	if is_instance_valid(_highlighted) and _highlighted.has_method(&"set_look_highlight"):
		_highlighted.set_look_highlight(false)
	_highlighted = null
	_talk_handler = null
	_talk_distance = INF
	if _readout_shown:
		_drive_readout(null)

func _update_target_outline() -> void:
	var current: Throwable = null
	if not held_object and is_colliding():
		current = get_collider() as Throwable
	if current == _last_targeted:
		return
	if _last_targeted and is_instance_valid(_last_targeted):
		_last_targeted.set_outline_visible(false)
	if current:
		current.set_outline_visible(true)
	_last_targeted = current

## Per-frame look-at talk detection: cast down the camera ray for a talk-layer hitbox and move
## the white highlight to whatever talkable is under the crosshair (mirrors pickup highlighting).
## Suppressed while carrying an object or mid-conversation.
func _update_talk_target() -> void:
	var handler: Node = null
	if not held_object and not DialogueManager.is_active():
		handler = _query_talk_handler()
		# An interactable CLOSER than the target blocks interacting/looking THROUGH it (a covered NPC must
		# never light up or read out through a crate) — UNLESS the prop IS the target's own body (a dual item
		# like a dropped weapon, whose CanPickUp sits on the Throwable). NOTE: a target we CAN'T act on (a
		# hostile / in-combat NPC) is NOT dropped here any more — it still reads out its name (below).
		if _closer_prop_blocks(handler):
			handler = null
		# No talk target under the crosshair: a bare Throwable there becomes the READOUT target instead, so
		# the hover prompt teaches the carry key ("[Z] Pick Up"). Interact behaviour is untouched — a
		# Throwable is never _is_interactable, so PickUp still falls through to the physical grab, and the
		# white talk highlight never applies (the throwable keeps its own orange target outline).
		if handler == null and is_colliding():
			handler = get_collider() as Throwable
	if handler == null:
		_talk_distance = INF
	# Dangling references (a pickup grabbed into the inventory, a looted-empty corpse, a dead NPC) read as
	# "no target" so they can't linger on either the highlight or the readout.
	if _highlighted != null and not is_instance_valid(_highlighted):
		_highlighted = null
	if _talk_handler != null and not is_instance_valid(_talk_handler):
		_talk_handler = null
	# The white "look target" outline shows ONLY for something we can ACT on right now (talk / loot /
	# pickpocket). A hostile / in-combat NPC is therefore NOT outlined — it keeps its red hostility rim — even
	# though its name still reads out below. Recomputed every frame so it tracks state that flips mid-look (the
	# NPC enters combat, or you crouch to pickpocket).
	var to_highlight: Node = handler if (handler != null and _is_interactable(handler)) else null
	if to_highlight != _highlighted:
		if is_instance_valid(_highlighted) and _highlighted.has_method(&"set_look_highlight"):
			_highlighted.set_look_highlight(false)
		if to_highlight != null and to_highlight.has_method(&"set_look_highlight"):
			to_highlight.set_look_highlight(true)
		_highlighted = to_highlight
	# The NAME readout follows ANY talkable under the crosshair — interactable or not — so you can read a
	# hostile / in-combat NPC's name on hover. The LABEL reflects what you can do (Talkable.look_name_for gives
	# "Talk to <name>" / "Pick Pocket <name>" / the bare name).
	if handler == _talk_handler:
		# Same target: clear a stuck readout if it's gone, else refresh the label — it can shift while you keep
		# looking (you crouch to pickpocket, or the NPC drops out of "talkable" by entering combat).
		if handler == null:
			if _readout_shown:
				_drive_readout(null)
		else:
			_refresh_readout(handler)
		return
	_talk_handler = handler
	_drive_readout(handler)

## Drive the FNV-style hover readout (HUD name + the NPC greet) for `handler` (null clears it) and remember
## whether it's currently shown, so a freed/looked-away target can be detected + cleared above even once
## the handler reference is gone.
func _drive_readout(handler: Node) -> void:
	var pl := player as Player
	if pl != null:
		pl.on_look_target_changed(handler)
	_readout_shown = handler != null

## Re-drive the readout LABEL for the still-current target (no greeting), so it tracks state that changes
## without the target changing — e.g. crouching reveals a "Pick Pocket" prompt.
func _refresh_readout(handler: Node) -> void:
	var pl := player as Player
	if pl != null:
		pl.refresh_look_readout(handler)

## THE "interacting THROUGH a prop" block, factored out of the three places that had it inline (the PickUp press,
## the per-frame talk-target update, and interact_available below) — the duplication the class header flags as a
## drift risk. A grabbable prop CLOSER to the camera than `handler` blocks it, so a covered NPC can't be talked to
## or lit up through a crate — UNLESS the prop IS the handler's own body (a dual item, e.g. a dropped weapon whose
## CanPickUp sits on the Throwable), where the interact must still run instead of carrying it. Reads whatever
## `_talk_distance` currently holds, so the press path (last frame's) and the per-frame path (this frame's, set by
## the _query_talk_handler call right above it) keep exactly the freshness each always had.
func _closer_prop_blocks(handler: Node) -> bool:
	if handler == null or not is_colliding():
		return false
	var prop := get_collider() as Throwable
	if prop == null:
		return false
	return global_position.distance_to(get_collision_point()) < _talk_distance and not prop.is_ancestor_of(handler)

## True when an Interact (PickUp / F) press would DO something at this instant — the exact three outcomes the
## PickUp branch of _unhandled_input can produce: arm the release of a carried prop, run a look-at interactable,
## or grab a bare Throwable.
##
## THIS IS THE E HALF OF THE LEAN'S CONTEXTUAL-KEY RULE (scripts/player/lean.gd): the lean claims the Interact key
## only on a press where this is FALSE, so exactly one of the two ever answers a given press. Keep it in lockstep
## with that input branch — an outcome added there but not here becomes an interact that a lean swallows.
## Deliberately does NOT gate on menus / dialogue: E means something in both (advance the box, close the screen),
## but the lean already refuses to run in either, so that gate lives once, in Lean._input_is_ours().
func interact_available() -> bool:
	var pl := player as Character
	if pl != null and not pl.is_alive():
		return false  # mirrors the liveness bail at the top of _unhandled_input — a dead player's E does nothing
	if _holding or held_object != null:
		return true   # E arms the carried prop's release (the two-press carry model)
	if _talk_handler != null and _is_interactable(_talk_handler) and not _closer_prop_blocks(_talk_handler):
		return true   # E talks / loots / stashes
	return is_colliding() and get_collider() is Throwable  # E grabs the aimed prop

## The contextual verb this ray is holding a target for, as an ACTION name (&"" = nothing). Duck-typed by
## Player.pending_verb_actions(), which the lean asks before it claims a key. Only the INTERACT verb is reported:
## Throw (Z) and DropHeld (H) are unconditional verbs on their own keys, not contextual fallbacks.
func pending_verb_action() -> StringName:
	return InputManager.action_pickup if interact_available() else &""

## Whether the look-at `handler` can be acted on right now: TALKED to / looted / picked up (is_talkable_now),
## OR PICKPOCKETED by our player (is_pickpocketable_now — offered even on a hostile NPC, when crouched behind
## an off-guard one). The ray drives the highlight + readout AND allows the interact on this, so the cue and
## what Interact does always agree. A bare Throwable is EXPLICITLY excluded: it can be the readout target
## (the "[Z] Pick Up" hint) but Interact must fall through to the physical grab, not a talk — and
## is_talkable_now defaults TRUE for handlers without can_be_talked_to, which a Throwable is.
func _is_interactable(handler: Node) -> bool:
	if handler is Throwable:
		return false
	return TalkHelpers.is_talkable_now(handler) or TalkHelpers.is_pickpocketable_now(handler, player)

## Cast from the camera along its forward for a talk-layer hitbox (areas only, on the dedicated talk layer so
## nothing else matches), then GATE it on line of sight: solid world geometry between the camera and the hitbox
## means the interactable is behind a wall and must NOT be reachable. Without that gate the talk-layer ray ignored
## bodies entirely, so you could pick up / talk / loot / open doors straight THROUGH walls. This is THE chokepoint
## for every look-at interactable (LookAtInteractable subclasses + Talkable + DialogueNPC), so the one fix here
## covers pickup, loot, containers, corpses, merchants, all stations, doors and NPC talk at once. Returns null
## (and leaves _talk_distance INF) when occluded, so the highlight + readout also drop behind walls.
func _query_talk_handler() -> Node:
	_talk_distance = INF
	var space := get_world_3d().direct_space_state
	var from := global_position
	var to := from - global_basis.z * TALK_REACH
	var q := PhysicsRayQueryParameters3D.create(from, to, TalkHelpers.TALK_LAYER)
	q.collide_with_areas = true
	q.collide_with_bodies = false
	var hit := space.intersect_ray(q)
	if hit.is_empty():
		return null
	var dist: float = from.distance_to(hit["position"])
	if _interaction_occluded(from, to, dist, hit["collider"]):
		return null
	_talk_distance = dist
	return TalkHelpers.resolve_handler(hit["collider"])

## True when a SOLID body sits between the camera and the talk hitbox the look-at ray found at `target_dist` m.
## A SECOND ray (bodies only, every physics layer EXCEPT the talk layer AND the held-prop bit) from `from` toward the
## SAME point, with the target's OWN bodies excluded so it can't self-occlude (a talk hitbox sits right on the body it
## wraps — a dropped item's Throwable, an NPC's CharacterBody, a crate's StaticBody). Any OTHER solid hit before the
## target is a wall in the way. Mirrors PetInteraction / ClaimInteraction's FULL sight mask
## 0xFFFFFFFF & ~TALK_LAYER & ~held_prop_collision_layer() — clearing BOTH the talk layer AND the held-prop bit, so a
## prop carried in front of the camera can never occlude a look-at verb (defense-in-depth: today unreachable while
## carrying, but keeps this chokepoint semantically identical to its five sibling sight/perception rays). Line-of-FIRE
## rays deliberately do NOT clear the held bit — a carried prop stays solid physical cover for bullets. The talk path
## keeps the talk-layer query for handler resolution and adds this on top. areas off => the target's own talk Area3D
## and any trigger/audio zones can never be the occluder.
func _interaction_occluded(from: Vector3, toward: Vector3, target_dist: float, hit_collider: Object) -> bool:
	var reach := target_dist - INTERACT_OCCLUSION_SKIP
	if reach <= 0.0:
		return false  # point-blank target — nothing can fit between
	var dir := (toward - from)
	if dir.length() < 0.0001:
		return false
	var space := get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(from, from + dir.normalized() * reach)
	q.collide_with_areas = false
	q.collide_with_bodies = true
	q.collision_mask = 0xFFFFFFFF & ~TalkHelpers.TALK_LAYER & ~TalkHelpers.held_prop_collision_layer()
	var exclude := _target_body_exclusions(hit_collider)
	if player:
		exclude.append(player.get_rid())  # the camera lives inside the player capsule (layer 2) — never self-block
	q.exclude = exclude
	return not space.intersect_ray(q).is_empty()

## RIDs of the target's OWN physics bodies, so the LOS ray can't mistake the interactable's body for the wall.
## Walks UP the ANCESTOR chain from the talk hitbox, bounded, gathering each CollisionObject3D it passes: the
## hitbox itself, then a dual item's parent Throwable / an NPC's CharacterBody / a crate's StaticBody (the talk
## hitbox is always a child of the body it wraps). A pure pickup (just an Area3D, no body above it) yields only the
## harmless area. CRUCIAL: only the ancestor NODES are collected, never their OTHER children — a wall that is merely
## a SIBLING of the interactable under a shared level root must stay a valid occluder (else a flat level would
## exclude every wall). Bounded depth so a body far up the tree the item happens to sit deep under still blocks.
func _target_body_exclusions(hit_collider: Object) -> Array[RID]:
	var rids: Array[RID] = []
	var n := hit_collider as Node
	var depth := 0
	while n != null and depth < OCCLUSION_SELF_DEPTH:
		if n is CollisionObject3D:
			rids.append((n as CollisionObject3D).get_rid())
		n = n.get_parent()
		depth += 1
	return rids

## Programmatically grab `target` and carry it hands-free, exactly as an aimed F/Z grab would — the entry point
## for the hotbar's "hold from backpack" action (Player.hold_item builds the prop, then hands it here). No-op if
## already carrying or the target isn't a live Throwable, so a double-press can't stack two grabs.
func carry(target: Throwable) -> void:
	if held_object != null or not is_instance_valid(target):
		return
	_pick_up(target)

## Grab: stash the body's prior physics state (so _release can restore it), then make
## it a weightless kinematic frozen body on the pickup collision layer, wake its
## neighbors/stack, and exclude it from player collision. on_picked_up notifies it.
func _pick_up(target: Throwable) -> void:
	# A blade left EMBEDDED by a pin kill is frozen with its collider deliberately buried in the wall. Release it
	# BEFORE the snapshot below, so we stash its free physics state rather than the pinned one (restoring "frozen,
	# no gravity" on a later drop would leave it hanging in mid-air), and so the carry system is never handed a
	# body overlapping static geometry. unpin() also lifts it clear of the surface. No-op on everything else.
	target.unpin()
	held_object = target
	_holding = true  # the sole grab entry (aimed F/Z AND the hotbar carry() both land here); paired with every _release / recovery
	_pickup_grace_remaining = PICKUP_GRACE_TIME
	_stack_wake_origin = target.global_position
	_stack_wake_remaining = STACK_WAKE_TIME
	_wake_neighbors(target)
	_wake_nearby_bodies(_stack_wake_origin)
	_prior_gravity_scale = held_object.gravity_scale
	_prior_collision_layer = held_object.collision_layer
	_prior_freeze = held_object.freeze
	_prior_freeze_mode = held_object.freeze_mode
	held_object.collision_layer = GameSettings.physics_damage.pickup_held_collision_layer
	held_object.gravity_scale = 0.0
	held_object.linear_velocity = Vector3.ZERO
	held_object.angular_velocity = Vector3.ZERO
	held_object.freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
	held_object.freeze = true
	if player:
		player.add_collision_exception_with(held_object)
	held_object.on_picked_up(self)
	if held_object.faces_carrier_while_held():
		held_object.face_carrier(global_transform)
	carry_changed.emit(true)

func _wake_neighbors(target: Throwable) -> void:
	var contacts := target.get_colliding_bodies()
	for c in contacts:
		if c is RigidBody3D:
			(c as RigidBody3D).sleeping = false

func _wake_nearby_bodies(origin: Vector3) -> void:
	# Sphere-cast around the pickup origin and wake every RigidBody3D found,
	# applying a tiny downward nudge so they have non-zero velocity and don't
	# immediately re-sleep before gravity has a chance to take over.
	# This fixes the "stack floats" issue when grabbing a box from a stack.
	var space := get_world_3d().direct_space_state
	var shape := SphereShape3D.new()
	shape.radius = STACK_WAKE_RADIUS
	var t := Transform3D.IDENTITY
	t.origin = origin
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = shape
	query.transform = t
	query.collision_mask = 1
	var exclude: Array[RID] = []
	if held_object:
		exclude.append(held_object.get_rid())
	if player:
		exclude.append(player.get_rid())
	query.exclude = exclude
	for r in space.intersect_shape(query, 16):
		var c = r["collider"]
		if c is RigidBody3D and not (c as RigidBody3D).freeze:
			var rb := c as RigidBody3D
			rb.sleeping = false
			rb.apply_central_impulse(Vector3(0, -STACK_WAKE_NUDGE, 0))

## Drop/throw: restore the saved physics state, then launch along the look direction
## at `impulse`, inheriting the player's velocity (so throwing while running carries).
## The player-collision exception is removed on a delay (and re-checked) so the crate
## can't instantly re-collide with / trap the player on release.
func _release(impulse: float, credit_thrower: bool = true) -> void:
	if not is_instance_valid(held_object):
		held_object = null
		_holding = false
		carry_changed.emit(false)
		return
	var dropped := held_object
	held_object = null
	_holding = false
	carry_changed.emit(false)
	dropped.freeze = _prior_freeze
	dropped.freeze_mode = _prior_freeze_mode
	dropped.collision_layer = _prior_collision_layer
	dropped.gravity_scale = _prior_gravity_scale
	# Is this a real THROW (a charged hold-release or the left-click fling) rather than a tap-drop or the forced
	# death/quickload release? Resolved ONCE here and reused for all three throw-only behaviours below — the launch
	# speed, the throw SOUND, and the thrown facing — so they can never disagree about what just happened.
	var throw_threshold: float = GameSettings.physics_damage.pickup_throw_impulse
	var is_throw := is_throw_release(impulse, throw_threshold, credit_thrower)
	# ...and only THEN scale by the prop's own multiplier (the knife is HURLED, a crate is lobbed).
	impulse = launch_impulse(impulse, throw_threshold, dropped.resolved_throw_impulse_mult(), credit_thrower)
	var release_basis := global_transform.basis if is_inside_tree() else transform.basis
	var forward := -release_basis.z.normalized()
	var lateral := release_basis.x.normalized() * GameSettings.physics_damage.pickup_drop_lateral_nudge if credit_thrower else Vector3.ZERO
	var inherited := player.velocity if player else Vector3.ZERO
	dropped.linear_velocity = forward * impulse + lateral + inherited
	dropped.on_dropped(is_throw)  # a real throw plays the prop's throw_sound (if it authors one) instead of its drop sound
	if credit_thrower:
		dropped.mark_thrown_by(player)  # credit the player so a thrown prop that damages an NPC aggros them (counts as an attack)
		# A real THROW noses the prop toward its travel direction if it opts in, and drags its streak if it
		# carries a ThrowTrail; a tap-DROP (low impulse) and the forced release (credit_thrower false) never do
		# — see Throwable.face_travel_when_thrown / Throwable.mark_thrown_for_trail.
		if is_throw:
			dropped.mark_thrown_for_facing()
			dropped.mark_thrown_for_trail()
	if player:
		var t := get_tree().create_timer(GameSettings.physics_damage.pickup_drop_exception_delay, true, true, true)
		t.timeout.connect(_restore_player_collision.bind(dropped))

## Deferred re-enable of player↔crate collision after a drop. If the crate still
## overlaps the player, nudge it away and re-check later instead — prevents the player
## getting stuck inside a crate dropped on their own head.
func _restore_player_collision(dropped) -> void:
	# `dropped` is intentionally untyped: it's bound onto a delay timer, and if the crate
	# is freed before the timer fires (destroyed / scene reload), a typed param would fail
	# to convert the freed Object *before* this runs. Untyped lets the guard below catch it.
	if not is_instance_valid(player) or not is_instance_valid(dropped):
		return
	if dropped is Throwable and _crate_overlaps_player(dropped as Throwable):
		var rb := dropped as RigidBody3D
		var away := rb.global_position - player.global_position
		away.y = 0.0
		if away.length_squared() < 0.01:
			away = Vector3(randf_range(-1.0, 1.0), 0.0, randf_range(-1.0, 1.0))
		away = away.normalized()
		rb.linear_velocity += away * GameSettings.physics_damage.pickup_slide_off_impulse
		var t := get_tree().create_timer(GameSettings.physics_damage.pickup_safe_recheck_delay, true, true, true)
		t.timeout.connect(_restore_player_collision.bind(dropped))
		return
	player.remove_collision_exception_with(dropped)

func _crate_overlaps_player(crate: Throwable) -> bool:
	if not crate.collision_shape or not crate.collision_shape.shape:
		return false
	if not player:
		return false
	var space_state := get_world_3d().direct_space_state
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = crate.collision_shape.shape
	query.transform = crate.collision_shape.global_transform
	query.collision_mask = player.collision_layer
	var results := space_state.intersect_shape(query, 8)
	for r in results:
		if r["collider"] == player:
			return true
	return false
