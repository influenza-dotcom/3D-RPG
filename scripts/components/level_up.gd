@tool
class_name LevelUp
extends LookAtInteractable

## Drop-in LEVEL-UP station, dual-mode like Merchant / Healer / Bonfire:
##   1. STANDALONE (a shrine, a trainer's counter): leave standalone on — aim + Interact opens the menu.
##   2. ON A DIALOGUE NPC: set standalone = false; the NPC's dialogue offers a "Level Up" option.
##
## Spend zorkmids to raise a CharacterStat by 1; the cost RISES with your total level (Dark Souls) and is the
## SAME FOR EVERY STAT at a given level — no stat is dearer than another, and pushing an already-high stat costs
## no more than a fresh one (the old per-stat opportunity cost is gone). Strength adds max HP + carry capacity
## (applied as a DELTA so the bonus isn't double-counted); gunplay / agility / streetwise / larceny are
## read live at their own seams. Stats have NO cap — every point is the same marginal gain, forever (the per-effect
## formulas on CharacterStats are straight lines now, no plateau).
##
## SETUP: drop it under the shrine / trainer (or assign highlight_target), size its CollisionShape3D, and
## tune base_cost / cost_per_level. (A Dark-Souls bonfire = put a Bonfire AND a LevelUp on the same node.)

# Derived from CharacterStats.STAT_NAMES (the single source; cannot drift) — the total-level sum + the level_up_stat
# guard iterate it. A compile-time const fold (CharacterStats is a pure Resource that references none of this).
const STAT_NAMES: Array[StringName] = CharacterStats.STAT_NAMES

@export var station_name: String = ""             ## hover + screen title; blank -> "Level Up"
@export var base_cost: int = 1                    ## cost to raise from total level 0 (the curve climbs by cost_per_level)
@export var cost_per_level: float = 1.5              ## added per total level already invested (the rising cost, same for every stat)
## ON = a self-serve station: aim + Interact opens the level-up menu directly. OFF = drive it from a
## dialogue NPC's "Level Up" option instead (the station stops responding to direct interaction).
@export var standalone: bool = true

@export_group("Perks")
## OPTIONAL perks the player may also pick on level-up. When this list is non-empty the Level Up screen grows a
## "Perks" section (level_up_screen.gd `_rebuild_perks`) where the player spends an XP-earned skill point on one
## (see `unlock_perk` below). A PerkStation is the other, station-only path — a free grant that costs no skill point.
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
	if standalone:
		StationSpeaker.ensure(self)  # a self-serve terminal answers with the shared panel chirp; a data-only station rides a talking NPC, and people don't beep

## The player's total level = the sum of all stats (= points invested; baseline is 0).
func total_level(player_node: Node) -> int:
	var player := player_node as Player
	if player == null:
		return 0
	var s := player.stats_or_default()
	var total := 0
	for n in STAT_NAMES:
		total += s.get_stat(n)
	return total

## Zorkmids to raise `stat` by 1 right now — the flat total-level curve (Dark Souls): base_cost plus the total
## points invested times cost_per_level. It is the SAME for every stat (the `stat` arg is accepted for API symmetry
## and future gating, but no longer changes the price — raising a maxed stat costs exactly what a fresh one does).
## ⭐FLOORED AT ZERO, and the floor is load-bearing: total_level is the SUM of the six stats, and character
## creation's zero-sum allocator permits a NET-NEGATIVE build (every stat may sit at -5), so the raw curve goes
## NEGATIVE below baseline — at the shipped knobs an all(-5) sheet priced -44, and a negative price inverts the
## whole transaction (the affordability guard passes for a broke player and the charge PAYS them; see
## level_up_stat). Below baseline the curve simply bottoms out: training a sub-baseline character is FREE, never
## profitable. A free raise stays LEGAL — see the cost > 0.0 gate in level_up_stat (the RespecStation convention).
func level_up_cost(player_node: Node, _stat: StringName = &"") -> float:
	return maxf(0.0, base_cost + (total_level(player_node) * cost_per_level))

## Raise `stat` (&"strength", &"gunplay", …) by 1, charging the player. Strength re-applies its max-HP + carry
## bonus as a DELTA (never the whole bonus again). Returns false (charging nothing) when the stat name is unknown
## or the player can't afford a PAID raise; a zero-cost raise (the floored sub-baseline price) succeeds free.
func level_up_stat(player_node: Node, stat: StringName) -> bool:
	var player := player_node as Player
	if player == null or not (stat in STAT_NAMES):
		return false
	var cost := level_up_cost(player, stat)  # flat total-level cost (same for every stat), floored at 0
	# Gate the fee only when there IS one (the RespecStation.do_respec / ChipInstaller convention): a FREE raise
	# (the floored sub-baseline price) must serve even a wallet in DEBT — the New Game implant purchase can
	# legitimately start the run negative, and `money < 0.0` must not lock a debtor out of a free service. The
	# paid path still refuses any wallet below the fee, debtors included.
	if cost > 0.0 and not player.can_pay(cost):
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
	var old_stamina_max := player.stamina_max()               # capture BEFORE the sheet moves — stamina reads endurance
	stats.set(stat, int(stats.get(stat)) + 1)
	# The strength->max_hp + carry re-stamp (heal-on-gain, clamp/floor, HUD signal) + the endurance->stamina re-seed all
	# go through the ONE CharacterStats.restamp_derived chokepoint, so LevelUp / PerkManager / PassiveItemBuffs stay
	# byte-identical. Zero number change for a normal positive raise; it now also clamps/floors/signals like the others.
	CharacterStats.restamp_derived(player, stats.max_hp_bonus() - old_hp_bonus, stats.carry_bonus() - old_carry_bonus, old_stamina_max)
	if cost > 0.0:                                             # > 0, not != 0: belt-and-braces with the cost floor, so no price can ever PAY the player (the RespecStation guard)
		player.charge(cost)                                    # charge LAST so its money_changed autosave sees the full raise
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

# ---------------------------------------------------------------------------
# Dialogue-station contract (drives the "Level Up" option when this rides a dialogue NPC)
# ---------------------------------------------------------------------------

## Sort key for the speaker's station options (Merchant 10 .. Atm 70; see merchant.gd for the full contract
## description). A const, not an @export — the order is a UI contract pinned by tests/test_dialogue_speaker_contracts.gd.
const DIALOGUE_ORDER := 40

## Dialogue-station contract, half 1 — DialogueManager discovers this + open_dialogue_station on the speaker's
## direct children (both methods required) and paints the "Level Up" option. Unconditional, like the rest.
func dialogue_station_option() -> Dictionary:
	return {
		"label": PlayerText.DIALOGUE_OPTION_LEVEL_UP,
		"order": DIALOGUE_ORDER,
		"reason": "level_up",
		"closed": LevelUpScreen.closed,
	}

## Dialogue-station contract, half 2 — the press. DialogueManager suspends the conversation and calls this;
## closing the level-up screen (every refuse path emits `closed`) resumes the dialogue.
func open_dialogue_station(player: Node) -> void:
	LevelUpScreen.open_level_up(self, player)
