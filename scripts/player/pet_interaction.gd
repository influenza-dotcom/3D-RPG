class_name PetInteraction
extends Node

## The player-side PET verb — the friendly twin of SilentTakedown. HOLD the Takedown key (default Q) while aimed at
## a Pettable object to pet it (a ♥ floats up above it). Built by Player._ready (.new() + host) right after the
## takedown node, and runs its OWN _physics_process with the same dialogue / menu / death guards the takedown uses.
##
## Same key as the takedown ON PURPOSE: the two never both qualify (the takedown wants an off-guard NPC body, the pet
## wants a Pettable object), so Q is contextual — pet what's friendly, take down what's not. Each verb owns its OWN
## HUD cue (Player.set_pet_cue vs set_takedown_cue) so neither clobbers the other when you swing the crosshair from
## an NPC to an object and back. Want them on separate keys? Give Pet its own InputManager action + ActionCatalog row
## and read it here instead of action_takedown — nothing else changes.
##
## The aim ray hits BODIES (for wall occlusion — you can't pet through a wall) AND areas (so a collider-less
## decorative mesh is pettable via the Pettable's own area shape), and masks out BOTH the talk layer AND the
## held-prop layer, so neither an NPC / station talk hitbox nor a prop carried in front of the face shadows a pet
## target sitting behind it.

const RAY_REACH: float = 6.0  ## probe depth = Pettable.max_range's @export_range max (6.0) so an authored max_range up to the slider ceiling is reachable; the per-object max_range is still the real gate

var host: Player = null  ## the owning Player, set right after .new()

var _hold_t: float = 0.0       ## seconds the Takedown key has been held over the current target
var _target: Pettable = null   ## the Pettable currently under the crosshair AND pettable (null = nothing to pet)


func _physics_process(delta: float) -> void:
	if not _can_run():
		_reset()
		return
	var pet := _aimed_pettable()
	if pet == null:
		_reset()
		return
	_target = pet
	# Hold-to-confirm: accumulate while the key is down, fire once full, reset on release. Same shape as the takedown.
	if InputManager.is_action_pressed(InputManager.action_takedown):
		_hold_t += delta
		if _hold_t >= maxf(0.01, pet.hold_time):
			_execute(pet)
			return
	else:
		_hold_t = 0.0
	_cue(pet)


## Shared gate with the player's polled input + the takedown: in the live tree with a valid host, not mid-death,
## not mid-dialogue, no modal/menu up (a bare .new() unit stub has no host -> safely inert).
func _can_run() -> bool:
	if host == null or not is_instance_valid(host) or not host.is_inside_tree():
		return false
	# Honour the player's physics suspension (the F1 debug menu's DebugActionsPlayer.suspend_player freezes the
	# Player by hand, OUTSIDE gameplay_suppressed(), but not its self-ticking verb children) — without this,
	# typing the pet key's letter into that menu's search field pets whatever the frozen crosshair rests on.
	# Same guard as WaypointMarker._can_run / SilentTakedown._can_run.
	if not host.is_physics_processing():
		return false
	if host.get(&"_dying"):
		return false
	if DialogueManager.is_active() or InputManager.gameplay_suppressed():
		return false
	# The LEAN has CLAIMED the Takedown key for this hold (Q is shared three ways now — takedown, pet, lean).
	# Stand down until it is released, exactly as SilentTakedown does: a peek must not quietly pet whatever it
	# swings past. See the contextual-key rule in scripts/player/lean.gd.
	if host.lean_owns_action(InputManager.action_takedown):
		return false
	return true


## The contextual verb this driver is holding a target for, as an ACTION name (&"" = nothing pettable). Duck-typed
## by Player.pending_verb_actions(): the LEAN asks it before claiming a shared key, so aiming at a stray dog and
## pressing Q still pets rather than peeking. The pet verb rides the SAME action as the takedown, so both drivers
## report the same name — either one having a target is enough to out-rank the lean.
func pending_verb_action() -> StringName:
	return InputManager.action_takedown if (_target != null and is_instance_valid(_target)) else &""

## The Pettable under the crosshair that can be petted right now, or null. Casts the player's aim ray (like
## SilentTakedown), resolves the hit to a Pettable (the collider itself, or one in its immediate family so an object
## whose SOLID body the ray hit still resolves to its Pettable child/sibling/parent), then applies the live can_pet()
## + per-object range gate.
func _aimed_pettable() -> Pettable:
	var from: Vector3 = host.get_aim_origin()
	var to: Vector3 = from + host.get_aim_direction() * RAY_REACH
	var params := PhysicsRayQueryParameters3D.create(from, to)
	params.exclude = [host.get_rid()]
	params.collide_with_areas = true
	# Mask every layer EXCEPT the talk layer (so a talk hitbox never shadows a pet target behind it) AND the
	# held-prop layer (so a prop you're carrying in front of your face can't block what you aim the pet verb at).
	params.collision_mask = 0xFFFFFFFF & ~TalkHelpers.TALK_LAYER & ~TalkHelpers.held_prop_collision_layer()
	var hit := host.get_world_3d().direct_space_state.intersect_ray(params)
	if hit.is_empty():
		return null
	var pet := _resolve_pettable(hit.get("collider"))
	if pet == null or not pet.can_pet():
		return null
	# Can't pet an object you're carrying: a held prop sits at arm's length right under the crosshair, so the ray
	# would otherwise offer "[Q] Pet <it>" on the very thing in your hands.
	if held_blocks(pet, _held_prop()):
		return null
	var dist: float = from.distance_to(hit["position"])
	return pet if dist <= pet.max_range else null


## The physics prop the player is currently carrying, or null. Duck-typed through Player.held_prop() so a bare
## .new() unit stub (no host / no such method) is safely empty-handed.
func _held_prop() -> Node:
	if host != null and host.has_method(&"held_prop"):
		var held: Variant = host.call(&"held_prop")
		if held is Node:
			return held as Node
	return null


## True when `pet` IS the held prop or a descendant of it — you can't pet an object you're holding. Pure tree-walk
## (static, no host) so it's unit-testable with bare Nodes. held == null (empty-handed) never blocks.
static func held_blocks(pet: Node, held: Node) -> bool:
	if held == null:
		return false
	var n := pet
	while n != null:
		if n == held:
			return true
		n = n.get_parent()
	return false


## Walk the hit collider's immediate family (itself, its children, its parent, the parent's children — bounded) for a
## Pettable, so an object that exposes a StaticBody/RigidBody to the ray still resolves to a Pettable authored as its
## child / sibling / parent. Bounded depth so a stray hit never matches an unrelated Pettable far up the tree.
func _resolve_pettable(collider: Object) -> Pettable:
	var n := collider as Node
	var depth := 0
	while n != null and depth < 4:
		if n is Pettable:
			return n as Pettable
		for c in n.get_children():
			if c is Pettable:
				return c as Pettable
		n = n.get_parent()
		depth += 1
	return null


## Commit the pet (the Pettable floats the heart, fires its signal, starts its cooldown). is_instance_valid guards a
## target freed mid-hold.
func _execute(pet: Pettable) -> void:
	if is_instance_valid(pet):
		pet.pet(host)
	_reset()


## Drive the HUD prompt + hold fill via the Player facade (Player.set_pet_cue -> PlayerHud.set_pet_cue).
func _cue(pet: Pettable) -> void:
	if not host.has_method(&"set_pet_cue"):
		return
	var nm := pet.pet_name()
	var key := InputManager.get_action_binding(InputManager.action_takedown)
	var text := ("[%s] %s %s" % [key, pet.prompt_verb, nm]) if nm != "" else ("[%s] %s" % [key, pet.prompt_verb])
	host.set_pet_cue(true, text, clampf(_hold_t / maxf(0.01, pet.hold_time), 0.0, 1.0))


func _reset() -> void:
	_hold_t = 0.0
	_target = null
	if host != null and is_instance_valid(host) and host.has_method(&"set_pet_cue"):
		host.set_pet_cue(false, "", 0.0)
