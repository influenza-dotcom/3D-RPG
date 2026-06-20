@tool
class_name LevelUp
extends LookAtInteractable

## Drop-in LEVEL-UP station, dual-mode like Merchant / Healer / Bonfire:
##   1. STANDALONE (a shrine, a trainer's counter): leave standalone on — aim + Interact opens the menu.
##   2. ON A DIALOGUE NPC: set standalone = false; the NPC's dialogue offers a "Level Up" option.
##
## Spend zorkmids to raise a CharacterStat by 1; the cost RISES with your total level (Dark Souls) and is the
## same for every stat. Endurance adds max HP and strength adds carry capacity (applied as a DELTA so the
## bonus isn't double-counted); persuasion / gunplay / streetwise are read live at their own seams. Stats
## have no hard cap — the per-effect formulas (prices, sway, rep) plateau on their own.
##
## SETUP: drop it under the shrine / trainer (or assign highlight_target), size its CollisionShape3D, and
## tune base_cost / cost_per_level. (A Dark-Souls bonfire = put a Bonfire AND a LevelUp on the same node.)

const STAT_NAMES: Array[StringName] = [&"strength", &"persuasion", &"gunplay", &"endurance", &"streetwise", &"agility"]

@export var station_name: String = ""             ## hover + screen title; blank -> "Level Up"
@export var base_cost: int = 1                    ## cost to raise from total level 0 (the curve still climbs by cost_per_level)
@export var cost_per_level: float = 1.5              ## added per total level already invested (the rising cost)
## ON = a self-serve station: aim + Interact opens the level-up menu directly. OFF = drive it from a
## dialogue NPC's "Level Up" option instead (the station stops responding to direct interaction).
@export var standalone: bool = true

@export_group("Perks")
## OPTIONAL perks the player may also choose from on level-up. NOTE: the level-up perk-PICKER UI is a follow-up
## (today perks are unlocked at a PerkStation) — this data is authored here so the picker can read it later.
@export var available_perks: Array[Perk] = []
## Perk picks granted per level-up, when available_perks is non-empty.
@export var perk_points_per_level: int = 1

## Editor warning: a standalone LevelUp on a dialogue NPC steals the interaction ray from the NPC's Talkable.
func _get_configuration_warnings() -> PackedStringArray:
	if standalone and _on_dialogue_host():
		return PackedStringArray([
			"`standalone` is on but this LevelUp is a child of a dialogue NPC — its talk-layer hitbox steals the interaction ray from the NPC's Talkable. Set `standalone` = false and open it from the dialogue's \"Level Up\" option.",
		])
	return PackedStringArray()

func _ready() -> void:
	if Engine.is_editor_hint():
		_editor_fit_hitbox()  # preview the auto-fit hitbox in-editor (resizes an existing collider; safe)
		return  # @tool: only _get_configuration_warnings runs in-editor; the hitbox/outline setup is runtime-only
	collision_layer = TalkHelpers.TALK_LAYER if standalone else 0
	collision_mask = 0
	_build_outline()
	if auto_fit_collider:
		_fit_hitbox_to_host()

## The player's total level = the sum of all five stats (= points invested; baseline is 0).
func total_level(player_node: Node) -> int:
	var player := player_node as Player
	if player == null:
		return 0
	var s := player.stats_or_default()
	var total := 0
	for n in STAT_NAMES:
		total += s.get_stat(n)
	return total

## Zorkmids to raise ANY stat by 1 right now — rises with total level (Dark Souls); same for every stat.
func level_up_cost(player_node: Node) -> float:
	return base_cost + (total_level(player_node) * cost_per_level)

## Raise `stat` (&"strength", &"endurance", …) by 1, charging the player. Endurance / strength re-apply their
## max-hp / carry bonus as a DELTA (never the whole bonus again). Returns false (charging nothing) when the
## player can't afford it or the stat name is unknown.
func level_up_stat(player_node: Node, stat: StringName) -> bool:
	var player := player_node as Player
	if player == null or not (stat in STAT_NAMES):
		return false
	var cost := level_up_cost(player)
	if player.money < cost:
		return false
	# Own a PRIVATE stats sheet before mutating — never edit a (possibly shared) assigned .tres in place.
	var stats := player.stats_or_default()
	if not stats.resource_path.is_empty():
		stats = stats.duplicate() as CharacterStats
		player.stats = stats
	# Apply the raise + its derived bonuses FIRST, then charge LAST. add_money's money_changed fires its own
	# autosave synchronously, so charging last means that save already sees the COMPLETE transaction — disk
	# never holds a money-spent-but-stat-unraised snapshot. The explicit autosave below is the authoritative one.
	var old_hp_bonus := stats.max_hp_bonus()
	var old_carry_bonus := stats.carry_bonus()
	stats.set(stat, int(stats.get(stat)) + 1)
	var hp_delta := stats.max_hp_bonus() - old_hp_bonus
	player.max_hp += hp_delta                                  # endurance -> +max HP (delta, not the whole bonus)
	player.hp += hp_delta                                      # heal by the gained max (Dark Souls heals on level)
	player.carry_capacity += stats.carry_bonus() - old_carry_bonus  # strength -> +carry capacity
	player.add_money(-cost)                                    # charge LAST so its money_changed autosave sees the full raise
	GameState.autosave(player)  # a raised stat is a milestone — the authoritative persist of the run
	return true

## Spend ONE skill point (granted by XP level-ups, on the PerkManager) to unlock `perk` — the level-up perk
## picker's seam. Requires an available point + can_unlock (prereqs met, not already owned), then unlocks via
## PerkManager (applying stat bonuses + granting any ability) and decrements the point. Autosaves. Returns false
## (spending nothing) when broke on points or the perk isn't unlockable. The station is NOT consumed — keep
## leveling. available_perks is the picker's data source.
func unlock_perk(player_node: Node, perk: Perk) -> bool:
	var player := player_node as Player
	if player == null or perk == null:
		return false
	var pm := _perk_manager(player)
	if pm == null or pm.skill_points <= 0 or not pm.can_unlock(perk):
		return false
	if not pm.unlock_perk(perk):  # re-checks can_unlock internally — only decrement once it truly unlocked
		return false
	pm.skill_points -= 1
	GameState.autosave(player)
	return true

## Find or create the player's PerkManager child (mirrors PerkStation / Player._perk_manager).
func _perk_manager(player: Node) -> PerkManager:
	for c in player.get_children():
		if c is PerkManager:
			return c as PerkManager
	var mgr := PerkManager.new()
	mgr.name = &"Perks"
	player.add_child(mgr)
	return mgr

# ---------------------------------------------------------------------------
# Behaviour (talk-handler surface — used only when standalone, a direct-interact station)
# ---------------------------------------------------------------------------

func start_talk(player: Node) -> void:
	LevelUpScreen.open_level_up(self, player)

func can_be_talked_to() -> bool:
	return true

func look_name() -> String:
	return "Level Up: %s" % station_name if not station_name.is_empty() else "Level Up"
