class_name PerkManager
extends Node

## Drop under the player (auto-created on first use) to track UNLOCKED perks and apply their effects: permanent
## stat bonuses (mirroring LevelUp's private-sheet + endurance/strength delta handling) and granted abilities
## (like UpgradePickup). Prerequisites gate which perks can unlock. `host` is the player — Node-typed (a dynamic
## surface) so there's no hard Player class dependency.

signal perk_unlocked(perk: Perk)

var host: Node = null
var _unlocked: Dictionary = {}  ## perk id (StringName) -> Perk (the value carries resource_path for save persistence)

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
			host.grant_ability(node as Ability)
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
		host.set(&"max_hp", float(host.get(&"max_hp")) + hp_delta)
		host.set(&"hp", float(host.get(&"hp")) + hp_delta)
	if host.get(&"carry_capacity") != null:
		host.set(&"carry_capacity", float(host.get(&"carry_capacity")) + (stats.carry_bonus() - old_carry))
