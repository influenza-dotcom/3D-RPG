class_name SilentTakedown
extends Node

## Slice 6b — the silent-takedown VERB. HOLD the Takedown key (default Q) while looking at an UNAWARE NPC from a
## short rear arc to instantly + QUIETLY kill it. Reuses the shipped backstab geometry (DamageApplier.is_behind)
## and the off-guard gate (NPC.is_off_guard()), routes the kill through Character.take_damage CREDITED to the
## player (so XP / bounty / kill-quest all land), and flips NPC.mark_silent_takedown() FIRST so _on_died suppresses
## the witness bark — the Slice 5 body-discovery corpse marker becomes the DELAYED cost instead (silent now, found
## later). The takedown key is its OWN action, never overloaded onto Interact (which already pickpockets).
##
## Designer surface: GameSettings.takedown (SilentTakedownSettings.tres) — enabled / hold_time / max_range /
## behind_arc_degrees / require_behind / require_crouch. Built by Player._ready (.new() + host) and runs its own
## _physics_process with the same dialogue/menu guards the player's polled input uses.

var host: Player = null  ## the owning Player, set right after .new()

var _hold_t: float = 0.0   ## seconds the Takedown key has been held over the current eligible target
var _eligible: NPC = null  ## the NPC currently under the crosshair AND eligible (null = nothing to take down)


func _physics_process(delta: float) -> void:
	if not _can_run():
		_reset()
		return
	var s: SilentTakedownSettings = GameSettings.takedown
	if s == null or not s.enabled:
		_reset()
		return
	var npc := _aimed_eligible_npc(s)
	if npc == null:
		_reset()
		return
	_eligible = npc
	# Hold-to-confirm: accumulate while the key is down, fire once full, reset on release.
	if InputManager.is_action_pressed(InputManager.action_takedown):
		_hold_t += delta
		if _hold_t >= maxf(0.01, s.hold_time):
			_execute(npc)
			return
	else:
		_hold_t = 0.0
	_cue(npc, s)


## Shared with the player's own polled input: never mid-dialogue or with a modal/menu up, and only while in the
## live tree with a valid host (a bare .new() unit stub has no host -> safely inert).
func _can_run() -> bool:
	if host == null or not is_instance_valid(host) or not host.is_inside_tree():
		return false
	if host.get(&"_dying"):
		return false  # no takedowns during the player's death cinematic — a dead player must not score the kill / XP / a post-mortem autosave
	if DialogueManager.is_active() or InputManager.gameplay_suppressed():
		return false
	return true


## The NPC under the crosshair eligible for a takedown, or null. Casts the player's aim ray (copying
## Player._check_aim_remark), then applies the pure eligibility gate so the decision is unit-testable.
func _aimed_eligible_npc(s: SilentTakedownSettings) -> NPC:
	var from: Vector3 = host.get_aim_origin()
	var to: Vector3 = from + host.get_aim_direction() * s.max_range
	var params := PhysicsRayQueryParameters3D.create(from, to)
	params.exclude = [host.get_rid()]
	var hit := host.get_world_3d().direct_space_state.intersect_ray(params)
	if hit.is_empty():
		return null
	var npc := hit.get("collider") as NPC
	if npc == null:
		return null
	var dist: float = from.distance_to(hit["position"])
	# REUSE the shipped backstab arc (basis.z = the model's facing, the same convention damage_trace/Perception use).
	var behind := DamageApplier.is_behind(host.global_position, npc.global_position, npc.global_transform.basis.z, s.behind_arc_degrees)
	if eligible(npc.is_off_guard(), host.is_crouching(), s.require_crouch, behind, s.require_behind, dist, s.max_range):
		return npc
	return null


## Pure eligibility predicate (no tree / nodes) — unit-tested. `behind` is precomputed via DamageApplier.is_behind.
## A takedown needs an off-guard (not-yet-ALERTED) target, optionally crouched, optionally within the rear arc,
## within reach.
static func eligible(off_guard: bool, crouching: bool, require_crouch: bool, behind: bool, require_behind: bool, dist: float, max_range: float) -> bool:
	if not off_guard:
		return false
	if require_crouch and not crouching:
		return false
	if require_behind and not behind:
		return false
	return dist <= max_range


## Commit the kill: mark it silent (NPC._on_died then skips the witness bark), then apply lethal damage CREDITED to
## the player so XP / bounty / kill-quest land. take_damage's _dead latch makes a double-fire a no-op; a large
## sentinel (not raw hp) outruns any armor/DR applied before the hp subtract.
func _execute(npc: NPC) -> void:
	if is_instance_valid(npc):
		if npc.has_method(&"mark_silent_takedown"):
			npc.mark_silent_takedown()
		npc.take_damage(1.0e9, false, host)
		if host.has_method(&"notify_toast"):
			host.notify_toast("Takedown", Color(0.72, 0.86, 0.92))
	_reset()


## Drive the HUD prompt + hold fill via the Player facade (forwards to PlayerHud.set_takedown_cue).
func _cue(npc: NPC, s: SilentTakedownSettings) -> void:
	if not host.has_method(&"set_takedown_cue"):
		return
	var nm := ""
	var raw: Variant = npc.get(&"display_name")
	if raw is String:
		nm = raw
	var key := InputManager.display_key(InputManager.action_takedown)
	var text := ("[%s] Take Down %s" % [key, nm]) if nm != "" else ("[%s] Take Down" % key)
	host.set_takedown_cue(true, text, clampf(_hold_t / maxf(0.01, s.hold_time), 0.0, 1.0))


func _reset() -> void:
	_hold_t = 0.0
	_eligible = null
	if host != null and is_instance_valid(host) and host.has_method(&"set_takedown_cue"):
		host.set_takedown_cue(false, "", 0.0)
