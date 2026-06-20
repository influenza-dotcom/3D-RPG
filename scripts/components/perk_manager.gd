class_name PerkManager
extends Node

## Drop under the player (auto-created on first use) to track UNLOCKED perks and apply their effects: permanent
## stat bonuses (mirroring LevelUp's private-sheet + endurance/strength delta handling) and granted abilities
## (like UpgradePickup). Prerequisites gate which perks can unlock. `host` is the player — Node-typed (a dynamic
## surface) so there's no hard Player class dependency.

signal perk_unlocked(perk: Perk)

var host: Node = null
var _unlocked: Dictionary = {}  ## perk id (StringName) -> Perk (the value carries resource_path for save persistence)
var skill_points: int = 0  ## unspent perk picks (granted on XP level-up); spent by the level-up picker
var points_earned: int = 0  ## CUMULATIVE picks ever granted by XP — a respec refunds skill_points back UP to this, so free station grants can't farm points
var _granted_abilities: Dictionary = {}  ## perk id -> the ability id (StringName) it granted, for respec revocation; absent = none

func _ready() -> void:
	host = get_parent()

func has_perk(perk_id: StringName) -> bool:
	return _unlocked.has(perk_id)

func unlocked_ids() -> Array:
	return _unlocked.keys()

## The resource_paths of the unlocked perks (skipping any code-built perk with no path) — for save persistence.
func unlocked_paths() -> Array:
	var out: Array = []
	for id in _unlocked:
		var perk = _unlocked[id]
		if perk is Perk and perk.resource_path != "":
			out.append(perk.resource_path)
	return out

## RECORD saved perks (by resource_path) WITHOUT re-applying their effects — a perk's stat bonuses already ride
## in the restored stat sheet and its granted ability in the restored unlocks, so re-applying would DOUBLE-count.
## A path that no longer loads is skipped with a warning (never a crash).
func restore_paths(paths: Array) -> void:
	for p in paths:
		var perk = load(str(p)) as Perk
		if perk != null and perk.id != &"":
			_unlocked[perk.id] = perk
			# Rebuild the granted-ability ledger so a respec AFTER a reload still revokes the perk's ability (the
			# save only stores perk paths; probe the scene for its ability id, then discard the probe).
			if perk.grants_ability != null:
				var probe = perk.grants_ability.instantiate()
				if probe is Ability:
					_granted_abilities[perk.id] = (probe as Ability).ability_id()
				probe.queue_free()
		else:
			push_warning("PerkManager: perk path '%s' didn't load — skipped on restore" % str(p))

## Can this perk be unlocked now — valid, not already owned, and all its prerequisites already unlocked?
func can_unlock(perk: Perk) -> bool:
	if perk == null or perk.id == &"" or has_perk(perk.id):
		return false
	for req in perk.requires_perks:
		if not has_perk(req):
			return false
	return true

## Unlock `perk`: record it, apply its stat bonuses, grant its ability. No-op (false) if it can't be unlocked.
func unlock_perk(perk: Perk) -> bool:
	if not can_unlock(perk):
		return false
	_unlocked[perk.id] = perk
	_apply_stat_bonuses(perk)
	if perk.grants_ability != null and host != null:
		# Route through the player's grant PIPELINE (exactly like UpgradePickup._grant_to) — a raw add_child left the
		# ability unlisted in _abilities, has_mechanic() false, hot-path refs unset, and unsaved (a silently dead grant).
		var node := perk.grants_ability.instantiate()
		if node is Ability and host.has_method(&"grant_ability"):
			var aid: StringName = (node as Ability).ability_id()  # capture BEFORE grant_ability may free the node
			if host.grant_ability(node as Ability):  # TRUE only when it actually added a NEW node (not a dup/re-enable)
				_granted_abilities[perk.id] = aid  # record only what the perk truly introduced -> respec won't delete pre-existing abilities
		else:
			node.queue_free()  # not an ability scene (or host can't grant) -> discard, don't parent a stray node
	perk_unlocked.emit(perk)
	return true

## Apply a perk's permanent stat bonuses to the host's CharacterStats — owning a PRIVATE sheet first (never
## mutate a possibly-shared .tres) and re-applying the endurance->max_hp / strength->carry deltas, exactly as
## LevelUp.level_up_stat does, so a perk's stats behave like a level-up's.
func _apply_stat_bonuses(perk: Perk) -> void:
	if perk.stat_bonuses.is_empty() or host == null:
		return
	perk.validate()  # warn on any unknown stat key (it would be silently skipped by the `in valid` filter below)
	var stats: CharacterStats = host.get(&"stats")  # typed so the max_hp_bonus()/carry_bonus() deltas below infer
	if stats == null:
		stats = CharacterStats.new()
		host.set(&"stats", stats)
	elif not stats.resource_path.is_empty():
		stats = stats.duplicate() as CharacterStats  # don't edit a shared assigned .tres in place
		host.set(&"stats", stats)
	var valid := CharacterStats.stat_names()
	var old_hp := stats.max_hp_bonus()
	var old_carry := stats.carry_bonus()
	for k in perk.stat_bonuses:
		if String(k) in valid:
			stats.set(StringName(k), int(stats.get(StringName(k))) + int(perk.stat_bonuses[k]))
	var hp_delta := stats.max_hp_bonus() - old_hp
	if hp_delta != 0.0 and host.get(&"max_hp") != null:
		# Same maxf/clampf floors as _reverse_stat_bonuses, so apply and reverse are EXACT inverses even for a
		# (hypothetical) negative-endurance perk. No-ops for normal positive bonuses.
		host.set(&"max_hp", maxf(1.0, float(host.get(&"max_hp")) + hp_delta))
		host.set(&"hp", clampf(float(host.get(&"hp")) + hp_delta, 1.0, float(host.get(&"max_hp"))))
	if host.get(&"carry_capacity") != null:
		host.set(&"carry_capacity", float(host.get(&"carry_capacity")) + (stats.carry_bonus() - old_carry))

## Reverse ALL unlocked perks: undo each perk's stat-bonus deltas (and the derived max_hp / carry deltas) and
## revoke each granted ability, then clear the ledger and REFUND skill points back up to points_earned (so free
## station grants can't farm points). Returns the number reversed. Walks perks in REVERSE unlock order so a
## prereq is undone after the perk that needed it (each intermediate sheet stays valid). The stat->derived
## formulas are LINEAR, so the per-perk deltas are order-independent and telescope back to baseline EXACTLY — no
## double-count. Idempotent (0 on empty ledger).
func respec() -> int:
	if _unlocked.is_empty():
		return 0
	var ids: Array = _unlocked.keys()
	ids.reverse()  # undo last-unlocked first (a prereq-child before its prereq)
	var count := 0
	for id in ids:
		var perk: Perk = _unlocked[id]
		if perk is Perk:
			_reverse_stat_bonuses(perk)
			_revoke_ability(id)
			count += 1
	_unlocked.clear()
	_granted_abilities.clear()
	skill_points = points_earned  # all EARNED points return; free station grants never raised points_earned, so they can't be farmed
	return count

## Undo one perk's stat bonuses on the host's CURRENT (already host-owned) sheet — the exact inverse of
## _apply_stat_bonuses: subtract each bonus, then re-apply the endurance->max_hp / strength->carry deltas computed
## from the now-lowered sheet. max_hp/hp drop by the same delta (hp clamped to [1, new max] for the took-damage
## case); carry by the carry-bonus delta. No duplicate needed — a prior unlock with bonuses already host-owned it.
func _reverse_stat_bonuses(perk: Perk) -> void:
	if perk.stat_bonuses.is_empty() or host == null:
		return
	var stats: CharacterStats = host.get(&"stats")
	if stats == null:
		return
	var valid := CharacterStats.stat_names()
	var old_hp := stats.max_hp_bonus()
	var old_carry := stats.carry_bonus()
	for k in perk.stat_bonuses:
		if String(k) in valid:
			stats.set(StringName(k), int(stats.get(StringName(k))) - int(perk.stat_bonuses[k]))
	var hp_delta := stats.max_hp_bonus() - old_hp  # <= 0 (endurance dropped) — the exact inverse delta
	if hp_delta != 0.0 and host.get(&"max_hp") != null:
		host.set(&"max_hp", maxf(1.0, float(host.get(&"max_hp")) + hp_delta))
		host.set(&"hp", clampf(float(host.get(&"hp")) + hp_delta, 1.0, float(host.get(&"max_hp"))))
	if host.get(&"carry_capacity") != null:
		host.set(&"carry_capacity", float(host.get(&"carry_capacity")) + (stats.carry_bonus() - old_carry))

## Revoke the ability a perk granted (by recorded id): the Player frees the node + clears its hot-path refs. No-op
## if the perk granted nothing, or the host has no revoke path.
func _revoke_ability(perk_id: StringName) -> void:
	if not _granted_abilities.has(perk_id):
		return
	if host != null and host.has_method(&"revoke_ability"):
		host.revoke_ability(_granted_abilities[perk_id])
