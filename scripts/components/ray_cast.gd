class_name PickupRay
extends RayCast3D

## Physics-object pickup / carry / throw. A RayCast3D from the camera detects the aimed Throwable.
## TWO-PRESS model (see _grab_or_arm_release / _release_held): press PickUp (E) or Throw (Z) aimed at a
## Throwable to GRAB it and carry it hands-free — the key-up does NOT drop it, so you keep carrying with the
## key released. Press the SAME key AGAIN while carrying to ARM the release; the duration you hold that second
## press decides the outcome on ITS key-up — a long hold THROWS (impulse), a quick tap gently DROPS. The first
## release after a grab is therefore intentionally inert: arming the timer on the grab instead would launch the
## prop the instant you let go, making hands-free carry impossible. SHORTCUT: while carrying, a single Attack
## press (default LEFT-CLICK — the gun is holstered/draw-locked with your hands full, so it can't fire) throws the
## prop straight away at full impulse, bypassing the two-press model. While held the body is frozen kinematic with
## gravity off and chased toward hold_anchor each frame via collision-aware motion. Several robustness fixes are
## documented at their call sites: a grab "grace" ease-in (anti-clip on pickup), stack-wake (stops a stack
## floating when you pull a box out), safe-motion casting (no clipping through walls), character shoving while
## carrying, and a deferred slide-off so a dropped crate can't trap the player.

signal carry_changed(holding: bool)  ## a physics prop was grabbed (true) or dropped/lost (false) -- drives the player's view-model hands

const PICKUP_GRACE_TIME: float = 0.25
const PICKUP_GRACE_STEP_RATIO: float = 0.25
const STACK_WAKE_RADIUS: float = 1.0
const STACK_WAKE_TIME: float = 0.6
const STACK_WAKE_NUDGE: float = 0.05
const TALK_REACH: float = 3.5  ## metres the look-at talk query reaches down the camera ray
const INTERACT_OCCLUSION_SKIP: float = 0.05  ## numerical pullback so a hitbox flush with its own surface isn't read as the wall
const OCCLUSION_SELF_DEPTH: int = 3  ## levels to walk UP from the talk hitbox gathering the target's OWN bodies to exclude from the LOS ray

## The wielding player body, excluded from carry collision and used as the throw velocity source; injected by Head.setup().
@export var player: CharacterBody3D
## The point in front of the camera a carried object is chased toward each frame; move it to change how far ahead props are held.
@export var hold_anchor: Marker3D

var held_object: Throwable = null
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
		# superset), matching every other combat input — pressing E over a menu/cutscene used to leak an interact.
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
			var blocked := is_colliding() and get_collider() is Throwable \
				and global_position.distance_to(get_collision_point()) < _talk_distance \
				and not (get_collider() as Node).is_ancestor_of(_talk_handler)
			if not blocked:
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
		# holding, bypassing the two-press E/Z carry-then-hold-to-release model. The freshly-drawn gun is kept from
		# firing on this SAME held click by Attack.suppress_fire_for_carry_release() (fired from
		# Player._on_carry_changed), mirroring the draw-click rule.
		# Because this branch STANDS IN FOR the fire click while your hands are full, suppress it in exactly the
		# states firing is suppressed: MouseInput gates the shot on InputManager.gameplay_suppressed(), which —
		# unlike any_modal_open() (used by the E/Z grab presses above) — ALSO covers cutscenes and the pet-naming
		# NameEntryDialog, neither of which pauses the tree. Match it, or a left-click / trigger-pull would fling
		# the prop across a cutscene when you can't even shoot. (gameplay_suppressed omits dialogue, so keep that.)
		if DialogueManager.is_active() or InputManager.gameplay_suppressed():
			return
		_release_timer_started_us = -1  # discard any E/Z-armed release timer — this click owns the throw now
		_release(GameSettings.physics_damage.pickup_throw_impulse)
		get_viewport().set_input_as_handled()

## Grab the aimed Throwable (start carrying), or — if already carrying — arm the release timer so the
## key-up becomes a drop/throw by hold time. Shared by the PickUp (E) and Throw (Z) presses.
func _grab_or_arm_release() -> void:
	if held_object:
		_release_timer_started_us = Time.get_ticks_usec()
	elif is_colliding():
		var target := get_collider() as Throwable
		if target:
			_pick_up(target)

## Release the carried object: a long hold throws (impulse), a tap gently drops. Shared by the PickUp (E)
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
	if held_object:
		_release(impulse, false)

## Per-frame carry update: refresh the highlight, run the pending stack-wake, then —
## if holding — chase hold_anchor with a clamped, collision-safe step and shove any
## characters in the path. Drops the object if it strays past the max hold distance
## (e.g. yanked through a wall).
func _physics_process(delta: float) -> void:
	_update_target_outline()
	_update_talk_target()
	if _stack_wake_remaining > 0.0:
		_stack_wake_remaining = maxf(0.0, _stack_wake_remaining - delta)
		_wake_nearby_bodies(_stack_wake_origin)
	if not held_object:
		return
	if not is_instance_valid(held_object):
		held_object = null
		carry_changed.emit(false)
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
	var safe_step := _safe_motion(held_object, step)
	held_object.global_position += safe_step
	_push_characters_in_path(held_object, safe_step, delta)

func _push_characters_in_path(held: Throwable, motion: Vector3, delta: float) -> void:
	if not held.collision_shape or not held.collision_shape.shape:
		return
	if motion.length() < 0.0001 or delta <= 0.0:
		return
	var space_state := get_world_3d().direct_space_state
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = held.collision_shape.shape
	query.transform = held.collision_shape.global_transform
	query.collision_mask = 2
	var exclude: Array[RID] = [held.get_rid()]
	if player:
		exclude.append(player.get_rid())
	query.exclude = exclude
	var overlaps := space_state.intersect_shape(query, 8)
	var motion_velocity := motion / delta
	for o in overlaps:
		var collider = o["collider"]
		if collider is Character:
			var c := collider as Character
			c.explosion_velocity += motion_velocity * GameSettings.physics_damage.pickup_ram_knockback_scale

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
		if handler != null and is_colliding() and get_collider() is Throwable \
				and global_position.distance_to(get_collision_point()) < _talk_distance \
				and not (get_collider() as Node).is_ancestor_of(handler):
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

## Programmatically grab `target` and carry it hands-free, exactly as an aimed E/Z grab would — the entry point
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
	held_object = target
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
		carry_changed.emit(false)
		return
	var dropped := held_object
	held_object = null
	carry_changed.emit(false)
	dropped.freeze = _prior_freeze
	dropped.freeze_mode = _prior_freeze_mode
	dropped.collision_layer = _prior_collision_layer
	dropped.gravity_scale = _prior_gravity_scale
	var release_basis := global_transform.basis if is_inside_tree() else transform.basis
	var forward := -release_basis.z.normalized()
	var lateral := release_basis.x.normalized() * GameSettings.physics_damage.pickup_drop_lateral_nudge if credit_thrower else Vector3.ZERO
	var inherited := player.velocity if player else Vector3.ZERO
	dropped.linear_velocity = forward * impulse + lateral + inherited
	dropped.on_dropped()
	if credit_thrower:
		dropped.mark_thrown_by(player)  # credit the player so a thrown prop that damages an NPC aggros them (counts as an attack)
		# A real THROW (long-hold = high impulse) noses the prop toward its travel direction if it opts in; a
		# tap-DROP (low impulse) and the forced release (credit_thrower false) never do — see Throwable.face_travel_when_thrown.
		if impulse >= GameSettings.physics_damage.pickup_throw_impulse:
			dropped.mark_thrown_for_facing()
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
