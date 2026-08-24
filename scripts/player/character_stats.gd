class_name CharacterStats
extends Resource

## @system Derived Stats
## @seam restamp_derived is the one strength/endurance re-stamp path LevelUp/PerkManager/PassiveItemBuffs funnel through; STAT_NAMES is the master stat-name const.
## @risk Banking the ideal delta, not restamp_derived's returned post-floor delta, over-restores max_hp/carry on reverse once a value hit its floor — silent, permanent inflation.
## @risk A new derived formula omitting baseline-0 neutrality or its maxf(0.0,..) floor slips the hand-listed baseline test and silently shifts balance for all baseline Characters.
## @risk Dropping restamp_derived's guarded `damaged` emit leaves the HP HUD showing a stale max after a level-up/perk/trinket; no test asserts the emit, so it fails silently.
## @test res://tests/test_player_stats.gd
## A character's RPG stat sheet — EVERY Character (player and NPC alike) carries one, set in the inspector
## by a designer. BASELINE (0) is neutral: every derived multiplier is exactly 1.0 and every bonus 0 at
## baseline, so an unsheeted (null) or all-baseline character leaves the game's existing balance untouched;
## builds matter only when a stat moves off baseline. Each effect is a pure, clamped formula consumed at ONE
## seam:
##   strength   -> carry_bonus() + max_hp_bonus()    Character._apply_stats (spawn-stamped, BEFORE hp seeds)
##                 + melee_damage_mult()              ShotResolver.scaled_damage for a MELEE weapon (WeaponData.is_melee)
##   endurance  -> stamina_bonus()                    Player.stamina_max (special-movement stamina capacity)
##                 + hp_regen_mult()                  Player._update_health_regen (out-of-combat health regen rate)
##   gunplay    -> sway_mult() + weapon_damage_mult() + headshot_damage_bonus()  AimSway + ShotResolver (a RANGED weapon)
##   streetwise -> buy/sell_price_mult()              Merchant.buy_price / sell_price (the trading character)
##                 + rep_gain/loss_mult()             Reputation.add_reputation (gains bigger, losses smaller)
##   agility    -> move_speed_mult() + jump_mult()    Player locomotion (faster on foot, higher jump)
##   larceny    -> detection_rate_mult()              Perception.sense (slower to fill an enemy's detection meter)
##                 + takedown_time_mult()             SilentTakedown (a stealthier operator kills quicker)
##                 + pickpocket_catch_chance() + pickpocket_value_allowance()  LootScreen pickpocket (caught roll + lift ceiling)
## Dialogue skill checks (DialogueChoice.required_stat / required_value) read get_stat() by name, then fold in
## Character.status_stat_modifier(stat) so held/timed stat boosts can satisfy conversation checks.
##
## NO SOFT CAP (the design contract). Every derived effect is a STRAIGHT LINE — each point past baseline adds the
## SAME marginal effect forever (better forever going up, worse forever going down; Dark-Souls-flat, no diminishing
## returns and no plateau). The ONLY clamp is the PHYSICAL floor at 0 where a negative value is meaningless: you
## can't deal negative damage (heal the target), move backward, jump down, or be spotted at a negative rate — so
## those bottom out at 0 and stay there. Price multipliers are linear too: the buy multiplier can fall to 0
## (Merchant.buy_price still floors valued goods at one coin quantum) and selling climbs without a ceiling.
## (Older builds floored these at 0.2 / capped sell at 1.5x / floored buy at half price — those interior
## plateaus WERE the soft cap and are gone.)
##
## Active StatusEffect.stat_modifiers fold into the MULTIPLIER derived methods below via an optional additive
## `bonus` arg (0.0 = unbuffed, so every existing call is unchanged): each live seam passes
## Character.status_stat_modifier(<stat>). strength's carry/max_hp are excluded from the live fold HERE — they're
## stamped once into carry_capacity/max_hp at spawn (not read live), so a TIMED StatusEffect can't move them (its
## melee_damage_mult IS live, though, so a timed strength buff still hits harder in melee). A held-item passive
## (PassiveItemBuffs — the Dota-style "carry it, get the buff" system) is the exception: it re-stamps its strength
## total into carry_capacity/max_hp as a running delta (via CARRY_PER_STRENGTH / HP_PER_STRENGTH below), so a
## carried +strength trinket really does raise carry AND max HP. get_stat() stays RAW (the permanent build);
## dialogue checks add live status_stat_modifier themselves. ALL three re-stampers (LevelUp.level_up_stat,
## PerkManager._apply/_reverse_stat_bonuses, PassiveItemBuffs._restamp) funnel through the ONE restamp_derived()
## chokepoint below, so the clamp/floor/heal/HUD-signal semantics can never drift apart again.

const BASELINE := 0

## Per-point derived factors — the SINGLE source for each stat->effect conversion, so the linear "same amount per
## point, forever" contract is legible in one place and the held-item re-stamp (PassiveItemBuffs) can't drift from
## the level-up math. STRENGTH now drives BOTH carry and max HP (it absorbed the old ENDURANCE stat), plus melee.
const CARRY_PER_STRENGTH := 2.0            ## strength -> +carry capacity per point
const HP_PER_STRENGTH := 1.5               ## strength -> +max HP per point (was HP_PER_ENDURANCE before the merge)
const MELEE_DAMAGE_PER_STRENGTH := 0.05    ## strength -> +5% melee weapon damage per point
const STAMINA_PER_ENDURANCE := 10.0        ## endurance -> +max stamina per point
const HP_REGEN_PER_ENDURANCE := 0.10       ## endurance -> +10% out-of-combat health regen rate per point
const WEAPON_DAMAGE_PER_GUNPLAY := 0.05    ## gunplay  -> +5% ranged weapon damage per point
const HEADSHOT_PER_GUNPLAY := 0.05         ## gunplay  -> +5% extra headshot punch per point (ranged crits)
const SWAY_PER_GUNPLAY := 0.08             ## gunplay  -> aim wander 8% steadier per point
const PRICE_PER_STREETWISE := 0.04         ## streetwise -> buys 4% cheaper / sells 4% dearer per point
const REP_PER_STREETWISE := 0.08           ## streetwise -> rep gains 8% bigger / losses 8% smaller per point
const MOVE_PER_AGILITY := 0.05             ## agility  -> +5% move speed per point
const JUMP_PER_AGILITY := 0.05             ## agility  -> +5% jump velocity per point
const DETECTION_PER_LARCENY := 0.05        ## larceny  -> enemy detection meter fills 5% slower per point
const TAKEDOWN_TIME_PER_LARCENY := 0.05    ## larceny  -> silent-takedown wind-up 5% quicker per point

@export_group("Attributes")
## STRENGTH. The physical stat (it merged in the old Endurance). Each point over baseline adds +2.0 carry capacity
## and +1.5 max HP (both stamped at spawn) AND +5% MELEE weapon damage (read live at the swing). 0 = neutral.
@export var strength: int = BASELINE
## ENDURANCE. Each point over baseline adds +10 max stamina for special movement abilities (grapple, climb, dash)
## AND speeds out-of-combat health regen by 10% (read live while you're out of a fight — see hp_regen_mult).
## 0 = neutral; negative lowers the pool until Player.stamina_max hits its physical floor, and slows healing until
## regen stops entirely at endurance -10.
@export var endurance: int = BASELINE
## GUNPLAY. Each point over baseline steadies the aim wander 8% (floored at perfectly still), hits 5% harder with
## RANGED weapons, and adds 5% headshot punch. 0 = neutral; higher = a deadlier, tighter shooter.
@export var gunplay: int = BASELINE
## AGILITY. Each point over baseline makes you move + jump 5% faster/higher. 0 = neutral; negative = slower.
@export var agility: int = BASELINE
## STREETWISE. The social stat (it merged in the old Persuasion). Each point over baseline makes buying 4% cheaper,
## selling 4% dearer, rep gains 8% bigger and rep losses 8% smaller. Also gates dialogue checks. 0 = neutral.
@export var streetwise: int = BASELINE
## LARCENY. The thief's stat — it MERGED the old STEALTH and PICKPOCKET into one. Each point over baseline (a) fills an
## enemy's detection meter 5% slower so you creep closer, longer, before you're spotted (Perception.sense) and shrinks
## the silent-takedown wind-up 5% (SilentTakedown), AND (b) lowers the chance an NPC catches you lifting an item while
## raising how valuable a thing (eventually the weapon in their hands) you can steal unnoticed (LootScreen pickpocket).
## 0 = neutral; deeply negative makes you a clumsy beacon — spotted faster AND caught more.
@export var larceny: int = BASELINE

## Raw stat by name. Dialogue checks add Character.status_stat_modifier() on top; an unknown name reads BASELINE,
## so a typo'd check neither trivially passes nor hard-fails.
func get_stat(stat: StringName) -> int:
	match stat:
		&"strength": return strength
		&"endurance": return endurance
		&"gunplay": return gunplay
		&"agility": return agility
		&"streetwise": return streetwise
		&"larceny": return larceny
	return BASELINE

## The MASTER stat-name list — the ONE true source every other stat-name list derives from (a compile-time const
## fold): GameState.STAT_NAMES (the [stats] save columns), LevelUp.STAT_NAMES (the total-level sum) and
## CharacterCreation.STATS (the builder steppers) are all `= CharacterStats.STAT_NAMES`, so a stat added HERE reaches
## every save + UI at once and NONE can silently drift. (A name missing from a hand-mirrored copy used to drop that
## stat from every save — deriving makes that impossible.) Keep it in lockstep with the @export attributes + get_stat.
const STAT_NAMES: Array[StringName] = [&"strength", &"endurance", &"gunplay", &"agility", &"streetwise", &"larceny"]

## A PackedStringArray VIEW of the STAT_NAMES master (above) — the source for the dialogue skill-check dropdown
## (DialogueChoice.required_stat) and stat_names_csv(). A drift test (test_player_stats.gd) pins that every name
## round-trips through get_stat AND that GameState / LevelUp / CharacterCreation all mirror STAT_NAMES exactly.
static func stat_names() -> PackedStringArray:
	return PackedStringArray(STAT_NAMES)

## Comma-separated stat names for a PROPERTY_HINT_ENUM_SUGGESTION hint_string.
static func stat_names_csv() -> String:
	return ",".join(stat_names())

## STRENGTH: +2.0 carry capacity per point over baseline.
func carry_bonus() -> float:
	return float(strength - BASELINE) * CARRY_PER_STRENGTH

## STRENGTH: +1.5 max HP per point over baseline (the consumer clamps so HP never drops below 1).
func max_hp_bonus() -> float:
	return float(strength - BASELINE) * HP_PER_STRENGTH

## ENDURANCE: +10 max stamina per point over baseline. Player.stamina_max clamps the final cap to >= 1.
## `bonus` folds active/held endurance status modifiers into the live stamina limit.
func stamina_bonus(bonus: float = 0.0) -> float:
	return float(endurance - BASELINE + bonus) * STAMINA_PER_ENDURANCE

## ENDURANCE: the passive out-of-combat health-regen RATE scales +10% per point over baseline. Exactly 1.0 AT
## BASELINE, so a baseline character still regenerates — at precisely the authored base rate. The neutrality
## contract is carried by that 1.0, not by switching the feature off for an unsheeted character.
## A MULTIPLIER rather than a stamina_bonus-shaped ADDITIVE, for two reasons. (1) The rate is authored as a
## fraction of max HP, so an absolute per-point term would be meaningless against a max_hp that starts at 4.0 and
## that strength / perks / held trinkets all move at runtime. (2) An additive term would COUPLE this const to the
## authored base rate — the physical zero floor would sit wherever their ratio put it, so halving the rate in the
## .tres would silently move the "endurance stops helping" cliff. As a multiplier that floor is always at
## endurance -10, whatever the base rate is.
## Floored at 0 like every other multiplier, and here the floor is LOAD-BEARING rather than tidy: a negative rate
## would flow into Character.heal(), which accepts a negative amount and drains hp with no death check and no
## flash — an untracked, unkillable damage source. Straight line all the way down to that floor, no interior
## plateau (the NO SOFT CAP contract). `bonus` folds active/held endurance status modifiers in exactly like
## stamina_bonus, so an adrenaline shot or a carried endurance trinket really does speed recovery.
func hp_regen_mult(bonus: float = 0.0) -> float:
	return maxf(0.0, 1.0 + float(endurance - BASELINE + bonus) * HP_REGEN_PER_ENDURANCE)

## The strength->derived RE-STAMP chokepoint — the SINGLE place a host's strength-driven max_hp / carry_capacity
## (and endurance-driven stamina cap) are re-applied as a DELTA. LevelUp.level_up_stat, PerkManager._apply /
## _reverse_stat_bonuses and PassiveItemBuffs._restamp ALL call this, so the clamp/floor/heal/HUD-signal semantics
## can never drift between them (they HAD: LevelUp used to move hp raw with no clamp/floor/signal). Duck-typed host
## (get/set on max_hp / hp / carry_capacity; OPTIONAL `damaged` signal + OPTIONAL apply_stamina_max_delta), so a
## Player, an NPC, or a bare test stub all work — the has_signal / has_method guards are load-bearing.
##
## `hp_delta` / `carry_delta` are the IDEAL change the caller already computed (a before/after bonus diff).
## `old_stamina_max` is the host's stamina cap captured BEFORE the caller mutated the sheet (endurance reads it) —
## pass -1.0 (the default) to leave stamina untouched (a caller that never moves endurance). Returns the
## ACTUALLY-applied POST-floor deltas as Vector2(hp, carry), so a caller tracking a running total (PassiveItemBuffs)
## telescopes back to zero EXACTLY even when a negative-strength value drives max_hp/carry into its floor (storing the
## ideal instead would over-restore on drop and inflate the value).
static func restamp_derived(host: Object, hp_delta: float, carry_delta: float, old_stamina_max: float = -1.0) -> Vector2:
	if host == null:
		return Vector2.ZERO
	var applied := Vector2.ZERO
	if hp_delta != 0.0 and host.get(&"max_hp") != null:
		var old_max := float(host.get(&"max_hp"))
		var new_max := maxf(1.0, old_max + hp_delta)  # max HP never below 1
		host.set(&"max_hp", new_max)
		# Dark-Souls "heal on gain": move current hp by the REAL max change, clamped to [1, new max] so a wounded host
		# is neither over-healed nor pushed below 1 when the delta is negative.
		host.set(&"hp", clampf(float(host.get(&"hp")) + (new_max - old_max), 1.0, new_max))
		applied.x = new_max - old_max
		# Refresh the HP HUD, matching Character.heal / respawn which emit `damaged` on any hp/max change. Guarded so a
		# host without the signal (an NPC, a test stub) is a no-op.
		if host.has_signal(&"damaged"):
			host.emit_signal(&"damaged", float(host.get(&"hp")), new_max)
	if carry_delta != 0.0 and host.get(&"carry_capacity") != null:
		var old_carry := float(host.get(&"carry_capacity"))
		var new_carry := maxf(0.0, old_carry + carry_delta)  # carry floored at 0, matching Character._apply_stats
		host.set(&"carry_capacity", new_carry)
		applied.y = new_carry - old_carry
	# endurance -> stamina cap: re-seed the capacity + heal by the gained max. -1.0 means the caller left endurance alone.
	if old_stamina_max >= 0.0 and host.has_method(&"apply_stamina_max_delta"):
		host.call(&"apply_stamina_max_delta", old_stamina_max)
	return applied  # the ACTUALLY-applied post-floor deltas (telescopes for a running-total caller)

## STRENGTH: MELEE weapons hit 5% harder per point over baseline — read in ShotResolver.scaled_damage when the
## weapon is flagged WeaponData.is_melee. Floored at 0 (a deeply negative strength deals no damage,
## never heals the target). 1.0 at baseline, so an unsheeted / baseline swing is unchanged. The `bonus` folds in an
## active strength status buff (0 = none). Guns use weapon_damage_mult (gunplay) instead — the two are split.
func melee_damage_mult(bonus: float = 0.0) -> float:
	return maxf(0.0, 1.0 + float(strength - BASELINE + bonus) * MELEE_DAMAGE_PER_STRENGTH)

## GUNPLAY: RANGED weapons hit 5% harder per point over baseline — the shooter's damage scale, read in
## ShotResolver.scaled_damage for a weapon with reach. Floored at 0 (worse forever, down to no damage). This is
## what makes a "gunner build" do visibly more DPS. Melee uses melee_damage_mult (strength) instead.
func weapon_damage_mult(bonus: float = 0.0) -> float:
	return maxf(0.0, 1.0 + float(gunplay - BASELINE + bonus) * WEAPON_DAMAGE_PER_GUNPLAY)

## GUNPLAY: ranged headshots land an extra 5% per point over baseline, multiplied ON TOP of the weapon's headshot
## multiplier and applied only on a crit. Floored at 0. Melee crits keep the weapon's own headshot multiplier but
## skip THIS gunplay bonus (gunplay is guns).
func headshot_damage_bonus(bonus: float = 0.0) -> float:
	return maxf(0.0, 1.0 + float(gunplay - BASELINE + bonus) * HEADSHOT_PER_GUNPLAY)

## GUNPLAY: the aim wander runs 8% steadier per point over baseline, floored at 0 (perfectly still at high gunplay;
## a deeply negative gunplay wanders ever wider, forever).
func sway_mult(bonus: float = 0.0) -> float:
	return maxf(0.0, 1.0 - float(gunplay - BASELINE + bonus) * SWAY_PER_GUNPLAY)

## STREETWISE: buying gets 4% cheaper per point over baseline, down to a zero multiplier. Merchant.buy_price
## still floors a valued item at one coin quantum, so authored goods never become literally free.
func buy_price_mult(bonus: float = 0.0) -> float:
	return maxf(0.0, 1.0 - float(streetwise - BASELINE + bonus) * PRICE_PER_STREETWISE)

## STREETWISE: selling earns 4% more per point over baseline, WITHOUT a ceiling (better forever). Floored at 0 so a
## deeply negative streetwise can't invert into a negative payout.
func sell_price_mult(bonus: float = 0.0) -> float:
	return maxf(0.0, 1.0 + float(streetwise - BASELINE + bonus) * PRICE_PER_STREETWISE)

## STREETWISE: positive reputation lands 8% bigger per point over baseline (better forever)...
func rep_gain_mult(bonus: float = 0.0) -> float:
	return maxf(0.0, 1.0 + float(streetwise - BASELINE + bonus) * REP_PER_STREETWISE)

## ...and negative reputation 8% smaller (floored at 0). A NEGATIVE streetwise runs this past 1.0: a street-naive
## character's mistakes cost MORE, without limit.
func rep_loss_mult(bonus: float = 0.0) -> float:
	return maxf(0.0, 1.0 - float(streetwise - BASELINE + bonus) * REP_PER_STREETWISE)

## AGILITY: +5% move speed per point over baseline, floored at 0 (a deeply negative agility grinds you to a halt).
func move_speed_mult(bonus: float = 0.0) -> float:
	return maxf(0.0, 1.0 + float(agility - BASELINE + bonus) * MOVE_PER_AGILITY)

## AGILITY: +5% jump VELOCITY per point over baseline, floored at 0. Jump HEIGHT scales with velocity squared, so a
## high-agility build springs noticeably higher; a deeply negative agility eventually can't leave the ground.
func jump_mult(bonus: float = 0.0) -> float:
	return maxf(0.0, 1.0 + float(agility - BASELINE + bonus) * JUMP_PER_AGILITY)

## LARCENY: an enemy's detection meter fills 5% slower per point over baseline — multiply the per-frame detection
## rate by this (Perception.sense). Floored at 0 (at very high larceny the meter never fills — you're a ghost); a
## NEGATIVE larceny runs it past 1.0, so a clumsy character is spotted FASTER, without limit. 1.0 at baseline.
func detection_rate_mult(bonus: float = 0.0) -> float:
	return maxf(0.0, 1.0 - float(larceny - BASELINE + bonus) * DETECTION_PER_LARCENY)

## LARCENY: the silent-takedown wind-up (SilentTakedownSettings.hold_time) shrinks 5% per point over baseline —
## multiply the base hold by this (SilentTakedown, which floors the result at SilentTakedownSettings.min_hold_time
## so a very high larceny can't make it a zero-length instant kill). Floored at 0 (a NEGATIVE larceny runs it past
## 1.0, dragging the press out ever longer, without limit — worse forever, matching the no-soft-cap contract).
## 1.0 at baseline, so an unsheeted / baseline character takes the full authored hold_time.
func takedown_time_mult(bonus: float = 0.0) -> float:
	return maxf(0.0, 1.0 - float(larceny - BASELINE + bonus) * TAKEDOWN_TIME_PER_LARCENY)

## LARCENY: the chance an NPC catches you lifting one item, given the encounter's `base_chance` and the per-point
## reduction (both from PickpocketSettings). Each point removes a flat `per_point` of catch chance (linear, no
## diminishing returns); clamped to a real probability [0, 1] (that bound is what a probability IS, not a soft cap).
## A high larceny reaches 0 (a flawless thief); a negative one raises the risk past the base. `bonus` folds an
## active larceny status buff. (Named for the PICKPOCKET mechanic it drives; the STAT behind it is now larceny.)
func pickpocket_catch_chance(base_chance: float, per_point: float, bonus: float = 0.0) -> float:
	return clampf(base_chance - float(larceny - BASELINE + bonus) * per_point, 0.0, 1.0)

## LARCENY: the maximum item VALUE (zorkmids) you can lift unnoticed, given the encounter's `base_value` and the
## per-point raise (both from PickpocketSettings). Linear + unbounded upward (a master thief can lift anything);
## floored at 0 so a negative larceny can only take worthless scraps, never a negative allowance.
func pickpocket_value_allowance(base_value: float, per_point: float, bonus: float = 0.0) -> float:
	return maxf(0.0, base_value + float(larceny - BASELINE + bonus) * per_point)
