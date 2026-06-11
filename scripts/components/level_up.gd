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

const STAT_NAMES: Array[StringName] = [&"strength", &"persuasion", &"gunplay", &"endurance", &"streetwise"]

@export var station_name: String = ""             ## hover + screen title; blank -> "Level Up"
@export var base_cost: int = 10                   ## cost to raise from total level 0
@export var cost_per_level: int = 10              ## added per total level already invested (the rising cost)
@export var standalone: bool = true

func _ready() -> void:
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
func level_up_cost(player_node: Node) -> int:
	return base_cost + total_level(player_node) * cost_per_level

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

# ---------------------------------------------------------------------------
# Behaviour (talk-handler surface — used only when standalone, a direct-interact station)
# ---------------------------------------------------------------------------

func start_talk(player: Node) -> void:
	LevelUpScreen.open_level_up(self, player)

func can_be_talked_to() -> bool:
	return true

func look_name() -> String:
	return "Level Up: %s" % station_name if not station_name.is_empty() else "Level Up"
