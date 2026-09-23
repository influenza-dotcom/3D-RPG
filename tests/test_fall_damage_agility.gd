extends GutTest

## FALL DAMAGE STRETCHES WITH AGILITY.
##
## THE BUG THIS FIXES. Agility multiplies the Player's jump VELOCITY by CharacterStats.jump_mult (+5% a point,
## uncapped), but the safe landing speed (`fall_damage_min_speed`, 16 m/s) never moved. A jump off flat ground lands
## at its launch speed x sqrt(fall_gravity_mult), so past agility ~34 your OWN hop started costing HP, and at agility
## 50 (a 15.75 m/s launch, a 12.7 m apex, a ~20.8 m/s landing) every jump took ~60% of your health bar. That's
## "killed by my own jumps all the time".
##
## THE FIX. The whole fall curve stretches along the speed axis by CharacterStats.landing_mult, which IS jump_mult:
## the safe speed is multiplied by it and the HP-per-m/s cost divided by it (Character.effective_fall_damage_*). A
## landing at v then scores exactly like a baseline landing at v / landing_mult, so a jump and the fall it causes
## scale together and your own jump is as safe at agility 50 as at 0.
##
## Same three layers as test_fall_damage_hp_scaling.gd: the pure multiplier and its invariants, the actor seam on an
## off-tree Character, and a source pin that the jump and the landing read the same agility.

const CHARACTER_PATH := "res://scripts/player/character.gd"
const PLAYER_PATH := "res://scripts/player/player.gd"

## The shipped player's fall profile (character.gd @export defaults, which Player.tscn does not override).
const MIN_SPEED := 16.0
const PER_SPEED := 0.5
const BASE_HP := 4.0
const LETHAL_SPEED := 24.0
## The shipped PlayerMovementSettings jump: launch speed, and the extra gravity applied only while descending.
const JUMP_VELOCITY := 4.5
const FALL_GRAVITY_MULT := 1.75


func _sheet(agility: int) -> CharacterStats:
	var s := CharacterStats.new()
	s.agility = agility
	return s

## Downward speed at touchdown for a jump off flat ground. It rises to v0^2 / 2g and falls that height back under
## g x fall_mult, so it lands at v0 x sqrt(fall_mult) whatever g is.
static func _own_jump_landing_speed(jump_mult: float) -> float:
	return JUMP_VELOCITY * jump_mult * sqrt(FALL_GRAVITY_MULT)

## An off-tree Character with the shipped fall profile, an agility sheet, and _apply_stats run (so the max-HP
## reference is captured), then grown to `max_hp` the way a level-up grows it.
func _agile_character(agility: int, max_hp: float = BASE_HP):
	var c = autofree(load(CHARACTER_PATH).new())
	c.max_hp = BASE_HP
	c.fall_damage_min_speed = MIN_SPEED
	c.fall_damage_per_speed = PER_SPEED
	c.stats = _sheet(agility)
	c._apply_stats()
	c.max_hp = max_hp
	return c


# =============================================================================================================
# 1. The multiplier, and what it keeps constant
# =============================================================================================================

## The pairing IS the fix. If the landing got its own per-point rate, the jump would outgrow the landing again as soon
## as the two numbers drifted apart.
func test_the_landing_stretch_is_the_jump_multiplier() -> void:
	for a in [-10, -3, 0, 1, 4, 10, 34, 50, 100]:
		var s := _sheet(a)
		assert_almost_eq(s.landing_mult(), s.jump_mult(), 0.0001,
			"agility %s: the fall curve must stretch by exactly the factor the jump does" % a)

## jump_mult reaches 0 at agility -20, and the cost DIVIDES by the stretch. The floor keeps the curve finite there
## instead of scoring a landing at INF HP (which int() wraps negative, i.e. a free landing).
func test_the_stretch_never_reaches_zero() -> void:
	for a in [-20, -25, -100]:
		assert_almost_eq(_sheet(a).landing_mult(), CharacterStats.MIN_LANDING_MULT, 0.0001,
			"agility %s: the stretch floors at MIN_LANDING_MULT, never 0" % a)
	var m := _sheet(-100).landing_mult()
	var dmg := FallDamage.hp_loss(5.0, MIN_SPEED * m, PER_SPEED / m)  # ~42: (5 - 0.8) x 10, give or take float error
	assert_gt(dmg, int(BASE_HP),
		"at the floor a 5 m/s landing must be a finite, POSITIVE, lethal cost — never a division blow-up or a free landing")
	assert_lt(dmg, 100, "...and finite: the floor exists so this never scores against an infinite cost")

## THE REGRESSION. Your own jump off flat ground costs nothing and never greys the screen, at any agility.
func test_your_own_jump_never_hurts_at_any_agility() -> void:
	var old_landing := _own_jump_landing_speed(_sheet(50).jump_mult())
	assert_gt(FallDamage.hp_loss(old_landing, MIN_SPEED, PER_SPEED), 0,
		"the old behaviour, for the record: agility 50's own jump (~20.8 m/s) cost HP against the unstretched 16 m/s safe speed")
	for a in [0, 10, 34, 50, 100, 200]:
		var s := _sheet(a)
		var m := s.landing_mult()
		var v := _own_jump_landing_speed(s.jump_mult())
		assert_eq(FallDamage.hp_loss(v, MIN_SPEED * m, PER_SPEED / m), 0,
			"agility %s: landing your own %.1f m/s jump must cost nothing" % [a, v])
		assert_almost_eq(FallDamage.lethal_fraction(v, MIN_SPEED * m, PER_SPEED / m, BASE_HP), 0.0, 0.0001,
			"agility %s: ...and the fall warning must not tint on the way down from it" % a)

## The whole curve stretches, not just its start. A landing at v scores like a baseline landing at v / stretch, in
## whole HP and in the warning's continuous fraction alike.
func test_a_landing_scores_like_a_baseline_landing_at_its_speed_over_the_stretch() -> void:
	# Baseline speeds whose cost lands on a HALF HP, so the int() truncation never sits on a float boundary.
	for a in [-10, 4, 10, 50]:
		var m := _sheet(a).landing_mult()
		for base_speed in [17.0, 21.0, 23.0, 30.5]:
			assert_eq(FallDamage.hp_loss(base_speed * m, MIN_SPEED * m, PER_SPEED / m),
					FallDamage.hp_loss(base_speed, MIN_SPEED, PER_SPEED),
				"agility %s: a %s m/s landing must cost what a baseline %s m/s landing does" % [a, base_speed * m, base_speed])
			assert_almost_eq(FallDamage.lethal_fraction(base_speed * m, MIN_SPEED * m, PER_SPEED / m, BASE_HP),
					FallDamage.lethal_fraction(base_speed, MIN_SPEED, PER_SPEED, BASE_HP), 0.0001,
				"agility %s: ...and read exactly as grey on the way down" % a)

func test_the_lethal_speed_at_full_health_moves_by_exactly_the_stretch() -> void:
	for a in [-10, 0, 10, 50]:
		var m := _sheet(a).landing_mult()
		assert_almost_eq(FallDamage.lethal_speed(MIN_SPEED * m, PER_SPEED / m, BASE_HP), LETHAL_SPEED * m, 0.001,
			"agility %s: a full-health landing kills at %s x the shipped 24 m/s" % [a, m])


# =============================================================================================================
# 2. The actor seam
# =============================================================================================================

## Baseline sheets (every actor the game ships) and unsheeted actors are scored by exactly the authored exports.
func test_a_baseline_actor_is_scored_by_exactly_the_authored_curve() -> void:
	var c = _agile_character(0)
	assert_almost_eq(c.fall_damage_agility_mult(), 1.0, 0.0001, "baseline agility stretches nothing")
	assert_almost_eq(c.effective_fall_damage_min_speed(), MIN_SPEED, 0.0001, "baseline safe speed is the export")
	assert_almost_eq(c.effective_fall_damage_per_speed(), PER_SPEED, 0.0001, "baseline cost is the export")
	var bare = autofree(load(CHARACTER_PATH).new())
	assert_almost_eq(bare.effective_fall_damage_min_speed(), bare.fall_damage_min_speed, 0.0001,
		"an actor with no sheet at all falls back to a baseline sheet, so its curve is untouched too")

## The save that reported the bug: agility 50.
func test_high_agility_stretches_the_actor_curve() -> void:
	var c = _agile_character(50)
	assert_almost_eq(c.fall_damage_agility_mult(), 3.5, 0.0001, "agility 50 is a 3.5x jump, so a 3.5x stretch")
	assert_almost_eq(c.effective_fall_damage_min_speed(), 56.0, 0.001, "safe up to 3.5 x 16 m/s")
	assert_almost_eq(c.effective_fall_damage_per_speed(), PER_SPEED / 3.5, 0.0001, "the cost per m/s shrinks by the same factor")
	assert_almost_eq(FallDamage.lethal_speed(c.effective_fall_damage_min_speed(), c.effective_fall_damage_per_speed(), c.max_hp),
			84.0, 0.001, "a full-health agility-50 actor dies at 3.5 x the shipped 24 m/s")

## Max-HP scaling and the agility stretch must compose, not overwrite each other.
func test_agility_and_max_hp_scaling_compose() -> void:
	var c = _agile_character(10, 20.0)  # a 1.5x stretch on a 5x health bar
	assert_almost_eq(c.effective_fall_damage_per_speed(), PER_SPEED * 5.0 / 1.5, 0.0001,
		"cost = export x max-HP scale / agility stretch")
	assert_almost_eq(FallDamage.lethal_speed(c.effective_fall_damage_min_speed(), c.effective_fall_damage_per_speed(), c.max_hp),
			LETHAL_SPEED * 1.5, 0.001,
		"at full health max HP still moves nothing, and agility moves the lethal speed by exactly its stretch")


# =============================================================================================================
# 3. The jump and the landing read the SAME agility
# =============================================================================================================

## landing_mult == jump_mult only protects you if both seams fold in the same live buffs. A +agility stim that raised
## the jump but not the landing would bring the bug back for as long as the stim lasts.
func test_the_jump_and_the_landing_read_the_same_agility() -> void:
	var player := FileAccess.get_file_as_string(PLAYER_PATH)
	assert_true('stats_or_default().jump_mult(status_stat_modifier(&"agility"))' in player,
		"the Player's jump must scale by jump_mult with the live agility buffs folded in")
	var character := FileAccess.get_file_as_string(CHARACTER_PATH)
	assert_true('stats_or_default().landing_mult(status_stat_modifier(&"agility"))' in character,
		"Character.fall_damage_agility_mult must fold in the SAME live agility buffs the jump does")
