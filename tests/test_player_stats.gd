extends GutTest

## CharacterStats — the RPG stat sheet (carried by EVERY Character, player and NPC) and its effect formulas,
## plus the seams that consume them. The load-bearing contract: a BASELINE sheet is perfectly NEUTRAL (all
## multipliers 1.0, all bonuses 0), so the stat system changed nothing until a stat is authored off baseline.
##
## The overhauls this pins: strength absorbed the old ENDURANCE (it now drives max HP + carry + melee),
## streetwise absorbed the old PERSUASION (prices + reputation), and the 2026-07-16 merge folded the old STEALTH +
## PICKPOCKET into ONE stat, LARCENY (detection + takedown + pickpocket catch/value). Every derived effect is a
## STRAIGHT LINE — there is NO soft cap: each point gives the same marginal effect forever, and the only clamp is
## the physical floor at 0 (no damage, frozen, undetectable) where a negative value is meaningless. The spawn
## effects (_apply_stats) live on Character, so the player and NPCs share one code path.

const PLAYER_PATH := "res://scripts/player/player.gd"
const NPC_PATH := "res://scripts/npc/npc.gd"
const MERCHANT_PATH := "res://scripts/components/merchant.gd"


## Bare host for CharacterStats.restamp_derived — the SAME minimal shape as PassiveItemBuffs' stub: max_hp/hp/
## carry_capacity fields, NO `damaged` signal and NO apply_stamina_max_delta method, so the chokepoint's HUD emit +
## stamina re-seed both no-op off-tree (proving the has_signal / has_method guards are load-bearing).
class _RestampHost:
	extends Node
	var max_hp: float = 10.0
	var hp: float = 10.0
	var carry_capacity: float = 5.0


## Build a sheet by stat. `lar` is the merged LARCENY stat (old stealth + pickpocket); `end_v` is endurance.
func _sheet(str_v := 0, gun := 0, agi := 0, street := 0, lar := 0, end_v := 0) -> CharacterStats:
	var s := CharacterStats.new()
	s.strength = str_v
	s.gunplay = gun
	s.agility = agi
	s.streetwise = street
	s.larceny = lar
	s.endurance = end_v
	return s


func test_baseline_sheet_is_perfectly_neutral() -> void:
	var s := CharacterStats.new()
	assert_almost_eq(s.carry_bonus(), 0.0, 0.0001, "baseline strength adds no capacity")
	assert_almost_eq(s.max_hp_bonus(), 0.0, 0.0001, "baseline strength adds no HP")
	assert_almost_eq(s.melee_damage_mult(), 1.0, 0.0001, "baseline strength changes no melee damage")
	assert_almost_eq(s.stamina_bonus(), 0.0, 0.0001, "baseline endurance adds no stamina")
	assert_almost_eq(s.hp_regen_mult(), 1.0, 0.0001, "baseline endurance changes no health regen — a baseline character still regenerates, at exactly the authored base rate")
	assert_almost_eq(s.weapon_damage_mult(), 1.0, 0.0001, "baseline gunplay changes no gun damage")
	assert_almost_eq(s.headshot_damage_bonus(), 1.0, 0.0001, "baseline gunplay changes no headshot bonus")
	assert_almost_eq(s.sway_mult(), 1.0, 0.0001, "baseline gunplay changes no aim sway")
	assert_almost_eq(s.buy_price_mult(), 1.0, 0.0001, "baseline streetwise changes no buy price")
	assert_almost_eq(s.sell_price_mult(), 1.0, 0.0001, "baseline streetwise changes no sell price")
	assert_almost_eq(s.rep_gain_mult(), 1.0, 0.0001, "baseline streetwise changes no rep gain")
	assert_almost_eq(s.rep_loss_mult(), 1.0, 0.0001, "baseline streetwise changes no rep loss")
	assert_almost_eq(s.move_speed_mult(), 1.0, 0.0001, "baseline agility changes no move speed")
	assert_almost_eq(s.jump_mult(), 1.0, 0.0001, "baseline agility changes no jump")
	assert_almost_eq(s.landing_mult(), 1.0, 0.0001, "baseline agility changes no fall-damage curve — a baseline landing is scored by exactly the authored fall_damage_* exports")
	assert_almost_eq(s.stamina_regen_mult(), 1.0, 0.0001, "baseline agility changes no stamina recovery — a baseline character still recovers, at exactly the authored tier rates")
	assert_almost_eq(s.melee_time_mult(), 1.0, 0.0001, "baseline agility changes no melee cadence — a baseline character swings at exactly the authored attack_speed and wind-up")
	assert_almost_eq(s.reload_time_mult(), 1.0, 0.0001, "baseline agility changes no reload time — a baseline character reloads in exactly the authored reload_time")
	assert_almost_eq(s.detection_rate_mult(), 1.0, 0.0001, "baseline larceny changes no detection rate")
	assert_almost_eq(s.pickpocket_catch_chance(0.35, 0.03), 0.35, 0.0001, "baseline larceny leaves the base catch chance")
	assert_almost_eq(s.pickpocket_value_allowance(10.0, 5.0), 10.0, 0.0001, "baseline larceny leaves the base value allowance")
	s = null


func test_strength_drives_hp_carry_and_melee() -> void:
	# STRENGTH merged in the old Endurance: it now drives max HP AND carry AND melee damage.
	var s := _sheet(5)  # strength 5
	assert_almost_eq(s.carry_bonus(), 10.0, 0.0001, "strength 5 -> +10 carry capacity (2.0/pt)")
	assert_almost_eq(s.max_hp_bonus(), 7.5, 0.0001, "strength 5 -> +7.5 max HP (1.5/pt; strength absorbed Endurance)")
	assert_almost_eq(s.melee_damage_mult(), 1.25, 0.0001, "strength 5 -> +25% melee damage (5%/pt)")
	var weak := _sheet(-100)
	assert_almost_eq(weak.melee_damage_mult(), 0.0, 0.0001, "worse forever: a deeply negative strength floors melee at 0, never negative (no heal-the-target)")
	s = null
	weak = null


func test_endurance_drives_stamina_capacity() -> void:
	var s := _sheet(0, 0, 0, 0, 0, 5)  # endurance 5
	assert_almost_eq(s.stamina_bonus(), 50.0, 0.0001, "endurance 5 -> +50 max stamina (10/pt)")
	var tired := _sheet(0, 0, 0, 0, 0, -3)
	assert_almost_eq(tired.stamina_bonus(), -30.0, 0.0001, "negative endurance lowers max stamina linearly")
	s = null
	tired = null


func test_endurance_drives_health_regen_rate() -> void:
	# Endurance's SECOND derived effect (2026-08-18): the out-of-combat health-regen rate, as a multiplier on the
	# authored base rate — so it reads as a percentage in the stat tooltip, like every other live-seam stat.
	var s := _sheet(0, 0, 0, 0, 0, 5)  # endurance 5
	assert_almost_eq(s.hp_regen_mult(), 1.5, 0.0001, "endurance 5 -> +50% out-of-combat regen rate (10%/pt)")
	var frail := _sheet(0, 0, 0, 0, 0, -3)
	assert_almost_eq(frail.hp_regen_mult(), 0.7, 0.0001, "worse forever going down: negative endurance heals slower, linearly")
	var brittle := _sheet(0, 0, 0, 0, 0, -9)
	assert_almost_eq(brittle.hp_regen_mult(), 0.1, 0.0001, "still STRICTLY positive just above the floor — no interior plateau (NO SOFT CAP)")
	var dead_inside := _sheet(0, 0, 0, 0, 0, -20)
	assert_almost_eq(dead_inside.hp_regen_mult(), 0.0, 0.0001, "the physical floor: a deeply negative endurance stops regen at 0 and NEVER goes negative — a negative rate would reach Character.heal() and silently drain hp with no death check")
	s = null
	frail = null
	brittle = null
	dead_inside = null


func test_gunplay_drives_gun_damage_and_aim() -> void:
	# GUNPLAY is the shooter stat. The per-point rates are designer tuning, so this checks the RELATIONS the stat
	# promises, then drives the two real consumers: ShotResolver (gun damage) and AimSway (the player's aim wander).
	var base := CharacterStats.new()
	var gunner := _sheet(0, 5)
	var poor := _sheet(0, -3)
	var hopeless := _sheet(0, -1000)
	# Better above baseline, worse below, on all three axes.
	assert_gt(gunner.weapon_damage_mult(), base.weapon_damage_mult(), "a gunner's guns hit harder than a baseline shooter's")
	assert_lt(poor.weapon_damage_mult(), base.weapon_damage_mult(), "a negative gunplay hits softer")
	assert_gt(gunner.headshot_damage_bonus(), base.headshot_damage_bonus(), "a gunner's headshots punch harder")
	assert_lt(poor.headshot_damage_bonus(), base.headshot_damage_bonus(), "a negative gunplay punches softer on a headshot")
	assert_lt(gunner.sway_mult(), base.sway_mult(), "a gunner's aim wanders less")
	assert_gt(poor.sway_mult(), base.sway_mult(), "a negative gunplay wanders more")
	# NO SOFT CAP: a straight line, so a point far from baseline buys exactly what the first point did.
	assert_almost_eq(_sheet(0, 51).weapon_damage_mult() - _sheet(0, 50).weapon_damage_mult(),
		_sheet(0, 1).weapon_damage_mult() - base.weapon_damage_mult(), 0.0001,
		"the 51st point of gunplay adds exactly as much gun damage as the 1st (better forever, no plateau)")
	assert_almost_eq(_sheet(0, 51).headshot_damage_bonus() - _sheet(0, 50).headshot_damage_bonus(),
		_sheet(0, 1).headshot_damage_bonus() - base.headshot_damage_bonus(), 0.0001,
		"the 51st point adds exactly as much headshot punch as the 1st")
	assert_almost_eq(_sheet(0, -51).sway_mult() - _sheet(0, -50).sway_mult(),
		_sheet(0, -1).sway_mult() - base.sway_mult(), 0.0001,
		"worse forever: the 51st point BELOW baseline widens the wander exactly as much as the 1st")
	# The physical floor: a multiplier below 0 would HEAL the target, so damage stops at exactly 0.
	assert_almost_eq(hopeless.weapon_damage_mult(), 0.0, 0.0001, "a deeply negative gunplay floors gun damage at 0, never negative")
	assert_almost_eq(hopeless.headshot_damage_bonus(), 0.0, 0.0001, "...and the headshot bonus at 0 too")

	# Consumer 1 — ShotResolver.scaled_damage, a RANGED hit (is_melee false) from a 10-damage gun with a x2 crit.
	var body_base := ShotResolver.scaled_damage(10.0, 2.0, 1.0, false, false, 1.0, false, base)
	var body_gunner := ShotResolver.scaled_damage(10.0, 2.0, 1.0, false, false, 1.0, false, gunner)
	var crit_base := ShotResolver.scaled_damage(10.0, 2.0, 1.0, true, false, 1.0, false, base)
	var crit_gunner := ShotResolver.scaled_damage(10.0, 2.0, 1.0, true, false, 1.0, false, gunner)
	assert_almost_eq(body_base, 10.0, 0.0001, "a baseline shooter's body shot deals exactly the gun's damage")
	assert_gt(body_gunner, body_base, "a gunner's body shot deals more than a baseline shooter's")
	assert_lt(ShotResolver.scaled_damage(10.0, 2.0, 1.0, false, false, 1.0, false, poor), body_base,
		"a negative-gunplay shooter's body shot deals less")
	assert_almost_eq(ShotResolver.scaled_damage(10.0, 2.0, 1.0, false, false, 1.0, false, hopeless), 0.0, 0.0001,
		"a hopeless shooter deals no damage, never negative damage")
	assert_gt(crit_gunner / crit_base, body_gunner / body_base,
		"a gunner's edge is BIGGER on a headshot than on a body shot: the extra headshot punch rides crits only")

	# Consumer 2 — AimSway, ticked once from the same clock and stance for three shooters that differ ONLY in gunplay.
	var wander_base := _aim_wander_after_one_tick(base)
	assert_gt(wander_base, 0.0, "precondition: a baseline shooter standing still still wanders a little")
	assert_lt(_aim_wander_after_one_tick(gunner), wander_base, "a gunner's aim wanders less than a baseline shooter's")
	assert_gt(_aim_wander_after_one_tick(poor), wander_base, "a negative-gunplay shooter's aim wanders more")


## A duck-typed AimSway host: standing still, no crouch component, no weapon hub, carrying `stats`.
class _AimHost:
	extends Node
	var velocity := Vector3.ZERO
	var crouch = null
	var weapon_system = null
	var stats: CharacterStats = null
	func stats_or_default() -> CharacterStats:
		return stats


## The size of the aim wander (radians) after one physics tick on a fixed clock, for a shooter carrying `sheet`.
func _aim_wander_after_one_tick(sheet: CharacterStats) -> float:
	var host := _AimHost.new()
	host.stats = sheet
	var sway := AimSway.new()
	sway.host = host
	sway._t = 1.0  # the same starting phase for every shooter, clear of a zero crossing
	sway._physics_process(1.0 / 60.0)
	var size: float = sway._offset.length()
	sway.free()
	host.free()
	return size


func test_agility_speeds_movement_and_jump() -> void:
	var fast := _sheet(0, 0, 4)  # agility 4
	assert_almost_eq(fast.move_speed_mult(), 1.2, 0.0001, "agility 4 -> +20% move speed")
	assert_almost_eq(fast.jump_mult(), 1.2, 0.0001, "agility 4 -> +20% jump velocity")
	var slow := _sheet(0, 0, -2)
	assert_almost_eq(slow.move_speed_mult(), 0.9, 0.0001, "agility -2 -> 10% slower")
	var frozen := _sheet(0, 0, -100)
	assert_almost_eq(frozen.move_speed_mult(), 0.0, 0.0001, "worse forever: a deeply negative agility floors at 0 (the old 0.2 soft floor is gone)")
	fast = null
	slow = null
	frozen = null


func test_agility_speeds_stamina_recovery() -> void:
	# AGILITY's third effect: how fast the stamina pool comes BACK (endurance still buys its SIZE). Consumed at
	# StaminaManager.recovery_rate_for, which multiplies whichever tier rate it picked by this — see
	# tests/test_player_core.gd for the wiring half.
	var quick := _sheet(0, 0, 4)  # agility 4
	assert_almost_eq(quick.stamina_regen_mult(), 1.2, 0.0001, "agility 4 -> stamina recovers 20% faster (5%/pt)")
	var sluggish := _sheet(0, 0, -2)
	assert_almost_eq(sluggish.stamina_regen_mult(), 0.9, 0.0001, "worse forever going down: a negative agility recovers slower, linearly")
	var nearly_still := _sheet(0, 0, -19)
	assert_almost_eq(nearly_still.stamina_regen_mult(), 0.05, 0.0001, "still STRICTLY positive just above the floor — no interior plateau (NO SOFT CAP)")
	var spent := _sheet(0, 0, -100)
	assert_almost_eq(spent.stamina_regen_mult(), 0.0, 0.0001, "the physical floor: a deeply negative agility stops recovery at 0 and NEVER goes negative — a negative rate would reach _set_stamina and silently drain a standing player's pool")
	quick = null
	sluggish = null
	nearly_still = null
	spent = null


func test_agility_quickens_melee_swings_and_reloads() -> void:
	# AGILITY's fourth and fifth effects, and the two that make it a FIGHTING stat rather than a purely
	# traversal one: how long a melee swing takes (cadence AND wind-up, Attack.effective_attack_speed /
	# effective_attack_windup) and how long a reload takes (Attack.effective_reload_time).
	# Both are TIME multipliers in the takedown_time_mult voice — LESS is better — so every assertion below
	# reads "the clock got shorter", and a NEGATIVE agility runs them past 1.0 without limit.
	# ⭐ The two ride the SAME per-point rate on purpose: the Stats screen prints ONE percentage for both
	# (tests/test_stats_screen.gd::test_agility_effect_names_all_three_speeds pins that wording), which is only
	# honest while these stay equal. If they ever diverge, that readout needs a fourth clause.
	var quick := _sheet(0, 0, 4)  # agility 4
	assert_almost_eq(quick.melee_time_mult(), 0.8, 0.0001, "agility 4 -> a melee swing takes 20% less time (5%/pt)")
	assert_almost_eq(quick.reload_time_mult(), 0.8, 0.0001, "agility 4 -> a reload takes 20% less time (5%/pt)")
	assert_almost_eq(quick.melee_time_mult(), quick.reload_time_mult(), 0.0001,
		"the melee and reload clocks share one per-point rate — the single 'attack & reload speed' readout depends on it")
	var clumsy := _sheet(0, 0, -3)
	assert_almost_eq(clumsy.melee_time_mult(), 1.15, 0.0001, "worse forever going up: a negative agility drags every swing out, linearly")
	assert_almost_eq(clumsy.reload_time_mult(), 1.15, 0.0001, "and leaves a clumsy character exposed 15% longer on every magazine change")
	var nearly_instant := _sheet(0, 0, 19)
	assert_almost_eq(nearly_instant.melee_time_mult(), 0.05, 0.0001, "still STRICTLY positive just above the floor — no interior plateau (NO SOFT CAP)")
	var beyond := _sheet(0, 0, 25)
	assert_almost_eq(beyond.melee_time_mult(), 0.0, 0.0001, "the multiplier's own floor is 0 and it NEVER goes negative")
	assert_almost_eq(beyond.reload_time_mult(), 0.0, 0.0001, "same for the reload clock")
	# ⭐ 0 is REACHABLE (agility 20), and a Timer.wait_time of 0 is an engine error — so unlike every other
	# derived multiplier, the floor that actually protects the game is the CONSUMER's, not this one.
	# Attack holds the product to GameSettings.weapon_general.min_melee_attack_speed / min_reload_time; see
	# tests/test_combat_systems.gd for that half and tests/test_managers_tuning.gd for the knobs themselves.
	assert_almost_eq(_sheet(0, 0, 20).melee_time_mult(), 0.0, 0.0001,
		"agility 20 drives the multiplier to EXACTLY 0 — the level-up station has no cap, so this is reachable in play")
	quick = null
	clumsy = null
	nearly_instant = null
	beyond = null


func test_streetwise_drives_prices_and_reputation() -> void:
	# STREETWISE merged in the old Persuasion: it now drives BOTH shop prices AND reputation scaling.
	var s := _sheet(0, 0, 0, 5)  # streetwise 5
	assert_almost_eq(s.buy_price_mult(), 0.8, 0.0001, "streetwise 5 -> buys 20% cheaper")
	assert_almost_eq(s.sell_price_mult(), 1.2, 0.0001, "streetwise 5 -> sells 20% higher")
	assert_almost_eq(s.rep_gain_mult(), 1.4, 0.0001, "streetwise 5 -> positive rep 40% bigger")
	assert_almost_eq(s.rep_loss_mult(), 0.6, 0.0001, "streetwise 5 -> negative rep 40% smaller")
	var naive := _sheet(0, 0, 0, -1)
	assert_gt(naive.rep_loss_mult(), 1.0, "a NEGATIVE streetwise makes scandals cost MORE")
	s = null
	naive = null


func test_larceny_slows_detection() -> void:
	var sneaky := _sheet(0, 0, 0, 0, 5)  # larceny 5
	assert_almost_eq(sneaky.detection_rate_mult(), 0.75, 0.0001, "larceny 5 -> enemy meter fills 25% slower (5%/pt)")
	var clumsy := _sheet(0, 0, 0, 0, -4)
	assert_almost_eq(clumsy.detection_rate_mult(), 1.2, 0.0001, "larceny -4 -> spotted 20% FASTER (worse forever)")
	var ghost := _sheet(0, 0, 0, 0, 25)
	assert_almost_eq(ghost.detection_rate_mult(), 0.0, 0.0001, "very high larceny floors the rate at 0 — effectively undetectable (reaches 0, no plateau)")
	sneaky = null
	clumsy = null
	ghost = null


func test_larceny_drives_pickpocket_catch_and_allowance() -> void:
	# The merged larceny stat also drives the pickpocket odds (it absorbed the old PICKPOCKET stat).
	var thief := _sheet(0, 0, 0, 0, 5)  # larceny 5
	assert_almost_eq(thief.pickpocket_catch_chance(0.35, 0.03), 0.20, 0.0001, "larceny 5 -> catch chance 0.35 - 5*0.03 = 0.20")
	assert_almost_eq(thief.pickpocket_value_allowance(10.0, 5.0), 35.0, 0.0001, "larceny 5 -> lift value up to 10 + 5*5 = 35")
	var master := _sheet(0, 0, 0, 0, 20)
	assert_almost_eq(master.pickpocket_catch_chance(0.35, 0.03), 0.0, 0.0001, "a master thief's catch chance clamps at 0 (never negative)")
	var oaf := _sheet(0, 0, 0, 0, -3)
	assert_almost_eq(oaf.pickpocket_value_allowance(10.0, 5.0), 0.0, 0.0001, "a negative larceny floors the value allowance at 0")
	assert_gt(oaf.pickpocket_catch_chance(0.35, 0.03), 0.35, "a negative larceny RAISES the catch risk past the base")
	thief = null
	master = null
	oaf = null


func test_no_soft_cap_prices_and_sway() -> void:
	# The headline of the overhaul: each point keeps giving the same effect PAST where the old floors/caps plateaued.
	assert_almost_eq(_sheet(0, 0, 0, 20).buy_price_mult(), 0.2, 0.0001, "streetwise 20 -> buys at 20% (below the OLD 0.5 half-price floor)")
	assert_almost_eq(_sheet(0, 0, 0, 25).buy_price_mult(), 0.0, 0.0001, "streetwise 25 -> buys for FREE (linear all the way down)")
	assert_almost_eq(_sheet(0, 0, 0, 20).sell_price_mult(), 1.8, 0.0001, "streetwise 20 -> sells at 180% (past the OLD 1.5 cap — better forever)")
	assert_almost_eq(_sheet(0, 15).sway_mult(), 0.0, 0.0001, "gunplay 15 -> perfectly steady (0 sway; the OLD 0.2 floor is gone)")


func test_get_stat_by_name_for_dialogue_checks() -> void:
	var s := _sheet(7, 6, 5, 4, 3)  # strength 7, gunplay 6, agility 5, streetwise 4, larceny 3
	assert_eq(s.get_stat(&"strength"), 7, "get_stat resolves strength by name (dialogue checks)")
	s.endurance = 8
	assert_eq(s.get_stat(&"endurance"), 8, "get_stat resolves endurance by name")
	assert_eq(s.get_stat(&"streetwise"), 4, "get_stat resolves streetwise by name")
	assert_eq(s.get_stat(&"larceny"), 3, "get_stat resolves the merged larceny stat by name")
	assert_eq(s.get_stat(&"no_such_stat"), CharacterStats.BASELINE,
		"an unknown stat name reads BASELINE — a typo'd dialogue check is neutral, not a crash or freebie")
	assert_eq(s.get_stat(&"stealth"), CharacterStats.BASELINE,
		"the retired 'stealth' key now reads BASELINE — it was merged into larceny (no lingering ghost stat)")
	assert_eq(s.get_stat(&"pickpocket"), CharacterStats.BASELINE,
		"the retired 'pickpocket' key now reads BASELINE — it was merged into larceny")
	s = null


func test_stat_names_round_trip_through_get_stat() -> void:
	# CharacterStats.stat_names() is the single source for the required_stat dropdown + the stat-iterating UIs.
	# Round-trip every name through get_stat so a renamed/added stat that forgets to update the other fails HERE.
	var names := CharacterStats.stat_names()
	assert_eq(names.size(), 6, "six authored attributes -> six stat names (stealth + pickpocket merged into larceny)")
	var v := 1
	for n in names:
		var s := CharacterStats.new()
		s.set(n, v)  # set the @export attribute by name
		assert_eq(s.get_stat(StringName(n)), v, "stat_names() entry '%s' must be a real attribute get_stat resolves" % n)
		s = null
		v += 1


func test_stat_name_mirrors_share_one_source() -> void:
	# CP1: the stat-name list lives ONCE on CharacterStats.STAT_NAMES; every other list is `= CharacterStats.STAT_NAMES`
	# (a compile-time fold), so a name added there reaches the save columns, the level-up sum AND the character builder
	# at once. A hand-mirrored copy that forgot a name used to drop that stat from every save — deriving makes it impossible.
	assert_eq(GameState.STAT_NAMES, CharacterStats.STAT_NAMES,
		"GameState's [stats] save columns must derive from the CharacterStats.STAT_NAMES master")
	assert_eq(LevelUp.STAT_NAMES, CharacterStats.STAT_NAMES,
		"LevelUp's total-level sum must derive from the CharacterStats.STAT_NAMES master")
	# character_creation.gd has no class_name — load the script to read its STATS const off the GDScript object.
	var creation: GDScript = load("res://scripts/ui/character_creation.gd")
	assert_eq(creation.STATS, CharacterStats.STAT_NAMES,
		"the character builder's STATS list must derive from the CharacterStats.STAT_NAMES master")


func test_restamp_derived_floors_heals_and_returns_applied_delta() -> void:
	# C61: restamp_derived is the ONE chokepoint LevelUp / PerkManager / PassiveItemBuffs share. A POSITIVE delta
	# raises the max, heals hp up by the same, and returns the applied delta unchanged (the stub has no stamina, so
	# old_stamina_max defaults to -1 = leave it alone).
	var host := _RestampHost.new()
	var applied := CharacterStats.restamp_derived(host, 3.0, 4.0)
	assert_almost_eq(host.max_hp, 13.0, 0.0001, "positive hp_delta raises max HP by the delta")
	assert_almost_eq(host.hp, 13.0, 0.0001, "...and heals current hp up by the same delta (Dark-Souls heal on gain)")
	assert_almost_eq(host.carry_capacity, 9.0, 0.0001, "positive carry_delta raises carry capacity by the delta")
	assert_almost_eq(applied.x, 3.0, 0.0001, "returns the applied hp delta")
	assert_almost_eq(applied.y, 4.0, 0.0001, "returns the applied carry delta")
	# A NEGATIVE delta that drives max HP below its 1.0 floor (and carry below 0) returns the REAL post-floor delta,
	# NOT the ideal -20 — so a running-total caller (PassiveItemBuffs) telescopes back EXACTLY on removal.
	var floored := CharacterStats.restamp_derived(host, -20.0, -20.0)
	assert_almost_eq(host.max_hp, 1.0, 0.0001, "max HP floors at 1, never below")
	assert_almost_eq(host.carry_capacity, 0.0, 0.0001, "carry capacity floors at 0")
	assert_almost_eq(floored.x, -12.0, 0.0001, "returns the REAL post-floor hp delta (13 -> 1 = -12), not the ideal -20")
	assert_almost_eq(floored.y, -9.0, 0.0001, "returns the REAL post-floor carry delta (9 -> 0 = -9), not the ideal -20")
	host.free()


func test_dialogue_skill_check_is_met_at_exactly_the_required_value() -> void:
	# Driven through the real DialogueView filter. No Player is in this bare tree, so the effective stat reads
	# CharacterStats.BASELINE — which makes the boundary exact: a check AT baseline is met, one point over is not.
	var view := DialogueView.new()
	add_child_autofree(view)
	view.open()
	var plain := DialogueChoice.new()  # authored with no gate at all
	plain.text = "Ask politely"
	var at_value := DialogueChoice.new()
	at_value.text = "Talk shop"
	at_value.required_stat = &"streetwise"
	at_value.required_value = CharacterStats.BASELINE
	var above := DialogueChoice.new()
	above.text = "Talk your way in"
	above.required_stat = &"streetwise"
	above.required_value = CharacterStats.BASELINE + 1
	view.set_choices([plain, at_value, above], func(_choice: DialogueChoice, _passed: bool = true) -> void: pass)
	var shown: PackedStringArray = []
	for b in view._choices_box.get_children():
		shown.append((b as Button).text)
	assert_eq(shown.size(), 2,
		"exactly the ungated choice and the one whose requirement is MET are offered (got %s)" % str(shown))
	assert_true(shown.size() > 0 and shown[0] == "Ask politely",
		"a fresh DialogueChoice carries no skill check — existing dialogue renders untouched and first (got %s)" % str(shown))
	assert_true(shown.size() > 1 and shown[1].ends_with("Talk shop"),
		"a check is met at EXACTLY required_value (>=, not >) — a player who has the listed score must see the option (got %s)" % str(shown))
	for t in shown:
		assert_false(t.ends_with("Talk your way in"),
			"one point short of the requirement hides the option (got %s)" % str(shown))


func test_apply_stats_stamps_hp_and_carry() -> void:
	var p = load(PLAYER_PATH).new()
	p.max_hp = 100.0
	p.carry_capacity = 10.0
	p.stats = _sheet(3)  # strength 3 drives BOTH max HP and carry now
	p._apply_stats()
	assert_almost_eq(p.max_hp, 104.5, 0.0001, "strength 3 -> +4.5 max HP (1.5/pt), stamped before hp seeds")
	assert_almost_eq(p.carry_capacity, 16.0, 0.0001, "strength 3 -> +6 carry capacity (2.0/pt)")
	p.free()


func test_npc_applies_stats_too() -> void:
	# Stats live on Character, so an NPC stamps strength exactly like the player. _apply_stats is pure, safe off-tree.
	var n = load(NPC_PATH).new()
	n.max_hp = 100.0
	n.carry_capacity = 10.0
	n.stats = _sheet(3)  # strength 3
	n._apply_stats()
	assert_almost_eq(n.max_hp, 104.5, 0.0001, "an NPC's strength stamps its max_hp (shared Character path)")
	assert_almost_eq(n.carry_capacity, 16.0, 0.0001, "an NPC's strength stamps its carry_capacity")
	n.free()


func test_merchant_prices_respect_streetwise() -> void:
	var m = load(MERCHANT_PATH).new()
	m.buy_mult = 1.0
	# ⭐KEEP THE REAL MARKDOWN (0.5). This case used to neutralise it (sell_mult 1.0) so the streetwise curve
	# could be read straight off the item value -- but a vendor that pays exactly what it charges is a ZERO
	# spread, and streetwise on top of that INVERTS it, which sell_price now refuses (the arbitrage floor).
	# With a real markdown the floor stays slack, so what's measured here is still purely the streetwise curve.
	# tests/test_merchant.gd's sibling case carries the same note.
	m.sell_mult = 0.5
	var it := Item.new()
	it.value = 100
	assert_eq(m.buy_price(it), 100, "no buyer -> the bare markup price (NPCs / tests unchanged)")
	var p = load(PLAYER_PATH).new()
	p.stats = _sheet(0, 0, 0, 5)  # streetwise 5
	assert_eq(m.buy_price(it, p), 80, "streetwise 5 buys at 80%")
	assert_eq(m.sell_price(it, p), 60, "streetwise 5 sells at 120% of the 0.5 markdown")
	p.free()
	m.free()
	it = null


func test_status_bonus_folds_into_multiplier_stats() -> void:
	# StatusEffect.stat_modifiers fold via the optional `bonus` arg (fed at each seam by Character.status_stat_modifier).
	# A +2 bonus shifts the curve exactly as if the stat were raised, and 0.0 (the default) leaves every existing call
	# untouched. strength's carry/max_hp are spawn-stamped (no bonus arg) but its melee_damage_mult IS live.
	var base := CharacterStats.new()
	assert_almost_eq(base.melee_damage_mult(2.0), _sheet(2).melee_damage_mult(), 0.0001, "strength bonus folds into melee damage")
	assert_almost_eq(base.stamina_bonus(2.0), _sheet(0, 0, 0, 0, 0, 2).stamina_bonus(), 0.0001, "endurance bonus folds into stamina capacity")
	assert_almost_eq(base.hp_regen_mult(2.0), _sheet(0, 0, 0, 0, 0, 2).hp_regen_mult(), 0.0001, "endurance bonus folds into the out-of-combat health-regen rate")
	assert_almost_eq(base.weapon_damage_mult(2.0), _sheet(0, 2).weapon_damage_mult(), 0.0001, "gunplay bonus folds into gun damage")
	assert_almost_eq(base.headshot_damage_bonus(2.0), _sheet(0, 2).headshot_damage_bonus(), 0.0001, "gunplay bonus folds into headshot punch")
	assert_almost_eq(base.sway_mult(2.0), _sheet(0, 2).sway_mult(), 0.0001, "gunplay bonus folds into aim sway")
	assert_almost_eq(base.move_speed_mult(2.0), _sheet(0, 0, 2).move_speed_mult(), 0.0001, "agility bonus folds into move speed")
	assert_almost_eq(base.jump_mult(2.0), _sheet(0, 0, 2).jump_mult(), 0.0001, "agility bonus folds into jump")
	assert_almost_eq(base.landing_mult(2.0), _sheet(0, 0, 2).landing_mult(), 0.0001, "agility bonus folds into the fall-damage stretch — a stim that raises your jump must soften its landing too")
	assert_almost_eq(base.stamina_regen_mult(2.0), _sheet(0, 0, 2).stamina_regen_mult(), 0.0001, "agility bonus folds into the stamina recovery rate")
	assert_almost_eq(base.melee_time_mult(2.0), _sheet(0, 0, 2).melee_time_mult(), 0.0001, "agility bonus folds into the melee swing clock — a kickstart stim really does swing faster, not just print faster")
	assert_almost_eq(base.reload_time_mult(2.0), _sheet(0, 0, 2).reload_time_mult(), 0.0001, "agility bonus folds into the reload clock — Attack._agility_bonus exists for exactly this")
	assert_almost_eq(base.buy_price_mult(2.0), _sheet(0, 0, 0, 2).buy_price_mult(), 0.0001, "streetwise bonus folds into buy price")
	assert_almost_eq(base.sell_price_mult(2.0), _sheet(0, 0, 0, 2).sell_price_mult(), 0.0001, "streetwise bonus folds into sell price")
	assert_almost_eq(base.rep_gain_mult(2.0), _sheet(0, 0, 0, 2).rep_gain_mult(), 0.0001, "streetwise bonus folds into rep gain")
	assert_almost_eq(base.detection_rate_mult(2.0), _sheet(0, 0, 0, 0, 2).detection_rate_mult(), 0.0001, "larceny bonus folds into detection rate")
	assert_almost_eq(base.pickpocket_catch_chance(0.35, 0.03, 2.0), _sheet(0, 0, 0, 0, 2).pickpocket_catch_chance(0.35, 0.03), 0.0001, "larceny bonus folds into catch chance")
	assert_almost_eq(base.move_speed_mult(), 1.0, 0.0001, "no bonus at baseline = 1.0 (existing no-arg calls unchanged)")
	base = null
