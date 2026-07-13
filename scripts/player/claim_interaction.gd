class_name ClaimInteraction
extends Node


## The player-side CLAIM verb — the ownership twin of the pet/takedown verbs. PRESS the Claim key (default T) while
## aimed at a Claimable object to adopt it: name it and make it follow you. Built by Player._ready (.new() + host)
## alongside the takedown / pet nodes, and runs its OWN _physics_process with the same dialogue / menu / death guards.
##
## Unlike pet (HOLD Q) and takedown (HOLD Q), claim is a single TAP on its own key — it's a one-time, deliberate
## act, not a sustained one, and it opens a text box, so a hold would fight the typing. The same object can be BOTH
## pettable and claimable (the dog is): the two verbs own separate keys + separate HUD cues, so both prompts can show
## ("[T] Befriend Dog" above "[Q] Pet Dog") until the dog is claimed, after which it reads "[T] Hold to Release Dog".
##
## Naming: on the Claim key we open the real-time NameEntryDialog (mouse freed, world keeps running) seeded with the
## object's current name; on confirm it calls Claimable.claim(host, typed_name). While the dialog is up,
## InputManager.gameplay_suppressed() is true (the dialog registers there), so _can_run() goes false — this node
## stops polling and the cue hides, so the Claim key can't re-fire under the open dialog. If the Claimable opts out of
## naming (ask_for_name = false) we claim instantly with its default name, no dialog.
##
## The aim ray hits BODIES (for wall occlusion — you can't claim through a wall) AND areas (so a collider-less
## decorative mesh is claimable via the Claimable's own area shape), and masks out BOTH the talk layer AND the
## held-prop layer, so neither an NPC / station talk hitbox nor a carried prop shadows a claim target behind it.
## Mirrors PetInteraction's (now two-layer) ray.

const RAY_REACH: float = 8.0  ## probe depth = Claimable.max_range's @export_range max (8.0) so an authored max_range up to the slider ceiling is reachable; the per-object max_range is still the real gate

var host: Player = null  ## the owning Player, set right after .new()

var _target: Claimable = null  ## the Claimable currently under the crosshair (claim- OR unclaim-eligible); null = none
var _hold_t: float = 0.0        ## seconds the Claim key has been HELD over a CLAIMED target — drives the unclaim hold
var _unclaim_armed: bool = false  ## the Claim key must be seen RELEASED once while aimed at a claimed object before an unclaim HOLD may begin — stops the key you held to open the name box from rolling straight into an unclaim


func _physics_process(delta: float) -> void:
	if not _can_run():
		_reset()
		return
	var claimable := _aimed_claimable()
	if claimable == null:
		_reset()
		return
	if claimable != _target:
		# Crosshair moved to a DIFFERENT object — clear any hold/arming carried over, so a hold meant for one prop
		# (or a key held while sweeping between two claimed props) can't apply to the new target.
		_hold_t = 0.0
		_unclaim_armed = false
	_target = claimable
	if claimable.can_claim():
		# UNCLAIMED: a single TAP claims it (opens the name box). No hold bar.
		_hold_t = 0.0
		_cue_claim(claimable)
		if InputManager.is_action_just_pressed(InputManager.action_claim):
			_begin_claim(claimable)
	elif claimable.can_unclaim():
		# CLAIMED: HOLD the Claim key to release it. Require a FRESH press first — the key must be seen UP once while
		# aimed here — so the key you held to open the name box can't roll straight into an unclaim after you confirm.
		# Then accumulate while held; fire once full. Same deliberate-hold feel as the pet/takedown verbs.
		var pressed := InputManager.is_action_pressed(InputManager.action_claim)
		if not pressed:
			_unclaim_armed = true   # key released (or never held) -> a hold from here is a deliberate unclaim gesture
			_hold_t = 0.0
		elif _unclaim_armed:
			_hold_t += delta
			if _hold_t >= maxf(0.01, claimable.unclaim_hold_time):
				_unclaim(claimable)
				return
		# else: key still held from before it became releasable (e.g. across the name box) -> wait for a release
		# The release prompt is HIDDEN by default (Claimable.show_release_prompt) — the gesture still works, it's just
		# not advertised — so we hide the cue rather than show "Hold to Release" unless the designer opts the prompt in.
		if claimable.show_release_prompt:
			_cue_unclaim(claimable)
		else:
			_hide_cue()
	else:
		_reset()


## Shared gate with the player's polled input + the pet/takedown verbs: in the live tree with a valid host, not
## mid-death, not mid-dialogue, no modal/menu (incl. our own NameEntryDialog) up. A bare .new() unit stub has no host
## -> safely inert.
func _can_run() -> bool:
	if host == null or not is_instance_valid(host) or not host.is_inside_tree():
		return false
	if host.get(&"_dying"):
		return false
	if DialogueManager.is_active() or InputManager.gameplay_suppressed():
		return false
	return true


## Open the name box (real-time modal) seeded with the object's current name; on confirm, claim with the typed name.
## If the Claimable opts out of naming, claim instantly with its default. The dialog autoload is referenced lazily
## (only here, never off-tree in a unit test) so a bare .new() stub never touches it.
func _begin_claim(claimable: Claimable) -> void:
	if not claimable.ask_for_name:
		claimable.claim(host, claimable.default_name)
		_reset()
		return
	var seed_name := claimable.default_name.strip_edges()
	if seed_name.is_empty():
		seed_name = claimable.claim_name()
	# Capture the Claimable weakly via is_instance_valid in the callback: the object could be freed (shot, despawned)
	# while the box is open, in which case the confirm is a harmless no-op.
	NameEntryDialog.open(PlayerText.claim_name_dialog(claimable.claim_name()), seed_name, func(typed: String) -> void:
		if is_instance_valid(claimable) and is_instance_valid(host):
			claimable.claim(host, typed))
	_reset()  # hide the cue while the box is up; polling resumes (and re-shows it) only if the claim is cancelled


## The Claimable under the crosshair that can be claimed right now, or null. Casts the player's aim ray (like
## PetInteraction), resolves the hit to a Claimable (the collider itself, or one in its immediate family so an object
## whose SOLID body the ray hit still resolves to its Claimable child/sibling/parent), then applies the live
## can_claim() + per-object range gate. Refuses a target you're carrying (it's at arm's length under the crosshair).
func _aimed_claimable() -> Claimable:
	var from: Vector3 = host.get_aim_origin()
	var to: Vector3 = from + host.get_aim_direction() * RAY_REACH
	var params := PhysicsRayQueryParameters3D.create(from, to)
	params.exclude = [host.get_rid()]
	params.collide_with_areas = true
	# Mask out the talk layer (so a talk hitbox never shadows a claim target behind it) AND the held-prop layer
	# (so a prop you're carrying in front of your face can't block claiming an object behind it).
	params.collision_mask = 0xFFFFFFFF & ~TalkHelpers.TALK_LAYER & ~TalkHelpers.held_prop_collision_layer()
	var hit := host.get_world_3d().direct_space_state.intersect_ray(params)
	if hit.is_empty():
		return null
	var claimable := _resolve_claimable(hit.get("collider"))
	# Relevant if it can be claimed (tap) OR released (hold). A permanently-claimed object (allow_unclaim off) is
	# neither, so it resolves to null and shows no prompt.
	if claimable == null or not (claimable.can_claim() or claimable.can_unclaim()):
		return null
	if PetInteraction.held_blocks(claimable, _held_prop()):
		return null
	var dist: float = from.distance_to(hit["position"])
	return claimable if dist <= claimable.max_range else null


## The physics prop the player is currently carrying, or null. Duck-typed through Player.held_prop() so a bare .new()
## unit stub (no host / no such method) is safely empty-handed. Mirrors PetInteraction._held_prop.
func _held_prop() -> Node:
	if host != null and host.has_method(&"held_prop"):
		var held: Variant = host.call(&"held_prop")
		if held is Node:
			return held as Node
	return null


## Walk the hit collider's immediate family (itself, its children, its parent, the parent's children — bounded) for a
## Claimable, so an object that exposes a StaticBody/RigidBody to the ray still resolves to a Claimable authored as
## its child / sibling / parent. Bounded depth so a stray hit never matches an unrelated Claimable far up the tree.
## Mirrors PetInteraction._resolve_pettable.
func _resolve_claimable(collider: Object) -> Claimable:
	var n := collider as Node
	var depth := 0
	while n != null and depth < 4:
		if n is Claimable:
			return n as Claimable
		for c in n.get_children():
			if c is Claimable:
				return c as Claimable
		n = n.get_parent()
		depth += 1
	return null


## Release a claimed object once the unclaim HOLD completes. is_instance_valid guards a target freed mid-hold.
func _unclaim(claimable: Claimable) -> void:
	if is_instance_valid(claimable):
		claimable.unclaim(host)
	_reset()


## CLAIM prompt (tap verb): "[T] Befriend <name>" (from claimable.prompt_verb) with NO hold bar (progress 0).
func _cue_claim(claimable: Claimable) -> void:
	if not host.has_method(&"set_claim_cue"):
		return
	var nm := claimable.claim_name()
	var key := InputManager.display_key(InputManager.action_claim)
	var text := ("[%s] %s %s" % [key, claimable.prompt_verb, nm]) if nm != "" else ("[%s] %s" % [key, claimable.prompt_verb])
	host.set_claim_cue(true, text, 0.0)


## UNCLAIM prompt (hold verb): "[T] Hold to Release <name>" plus the hold-progress fill (the bar appears once the
## hold starts), so releasing reads like a deliberate hold, mirroring the pet/takedown cue.
func _cue_unclaim(claimable: Claimable) -> void:
	if not host.has_method(&"set_claim_cue"):
		return
	var nm := claimable.claim_name()
	var key := InputManager.display_key(InputManager.action_claim)
	var text := PlayerText.hold_to_release(key, nm)
	host.set_claim_cue(true, text, clampf(_hold_t / maxf(0.01, claimable.unclaim_hold_time), 0.0, 1.0))


## Hide just the HUD cue WITHOUT touching the hold/arm state (used for the hidden-release path while still aiming at a
## befriended object — the hold keeps accumulating, it's just not shown). _reset() is the full clear for look-away.
func _hide_cue() -> void:
	if host != null and is_instance_valid(host) and host.has_method(&"set_claim_cue"):
		host.set_claim_cue(false, "", 0.0)


func _reset() -> void:
	_target = null
	_hold_t = 0.0
	_unclaim_armed = false  # leaving the target re-requires a fresh press before the next unclaim hold
	if host != null and is_instance_valid(host) and host.has_method(&"set_claim_cue"):
		host.set_claim_cue(false, "", 0.0)
