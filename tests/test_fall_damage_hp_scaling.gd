extends GutTest

## FALL DAMAGE SCALES WITH YOUR MAX HP.
##
## THE BUG THIS FIXES. `fall_damage_per_speed` is a cost in ABSOLUTE whole HP per m/s over the safe speed, so
## every point of max HP the player earns (strength at spawn, level-ups, perks, a passive item, an implant)
## quietly buys fall PROTECTION. The 24 m/s drop that kills the shipped 4-HP player is a 4-point scratch on a
## 20-HP one — the game's single universal terrain threat evaporates exactly as everything else gets harder, and
## by the late game the player can walk off anything. Multiplying the cost by max_hp / the max HP the knob was
## AUTHORED against fixes the FRACTION of the health bar a given drop takes, so height is as dangerous on the
## last night as on the first.
##
## THE SHAPE OF THESE TESTS. Three layers, matching test_fall_grayscale.gd (whose curve this feature moves):
##   1. THE MULTIPLIER — FallDamage.hp_scale, a pure static, and the two invariants it exists to buy: constant
##      fraction of max HP, and a constant lethal speed at full health.
##   2. THE ACTOR SEAM — Character.fall_damage_reference_hp / effective_fall_damage_per_speed on an off-tree
##      Character (load().new(), never added to the tree), including the "changes nothing yet" promise that lets
##      this land on a tuned game: every actor the game ships spawns at a scale of exactly 1.0.
##   3. THE READERS, by source text. The cost and the WARNING must be scored by the same numbers. A reader that
##      reaches for a raw `fall_damage_*` export still compiles, still runs, and silently makes the
##      grayscale warning promise a survivable landing that then kills you — no error anywhere. Same pin shape
##      as test_upgrades.gd's Landing.on_land grep, and for the same reason.

const CHARACTER_PATH := "res://scripts/player/character.gd"
const PLAYER_PATH := "res://scripts/player/player.gd"

## The shipped player's fall profile (character.gd @export defaults; Player.tscn overrides none of them), so the
## numbers below read as the real game. 4 HP, hurt above 16 m/s, 0.5 HP per m/s over — lethal at 24 m/s.
const MIN_SPEED := 16.0
const PER_SPEED := 0.5
const BASE_HP := 4.0
const LETHAL_SPEED := 24.0
## A late-game health bar: five times the shipped one.
const GROWN_HP := 20.0


func _character():
	return autofree(load(CHARACTER_PATH).new())

## A Character carrying the shipped fall profile whose _apply_stats has run (so the authored baseline is
## captured), then grown to `grown_max_hp` the way a level-up / perk / passive item grows it — by writing max_hp.
func _grown_character(grown_max_hp: float):
	var c = _character()
	c.max_hp = BASE_HP
	c.fall_damage_min_speed = MIN_SPEED
	c.fall_damage_per_speed = PER_SPEED
	c._apply_stats()  # snapshots the authored 4.0; a neutral sheet adds nothing to max_hp
	c.max_hp = grown_max_hp
	return c


# =============================================================================================================
# 1. The multiplier, and the two things it exists to keep constant
# =============================================================================================================

func test_the_scale_is_max_hp_against_the_authored_reference() -> void:
	assert_almost_eq(FallDamage.hp_scale(BASE_HP, BASE_HP), 1.0, 0.001,
		"at the reference the curve is untouched — that is what makes this safe to land on an already-tuned game")
	assert_almost_eq(FallDamage.hp_scale(GROWN_HP, BASE_HP), 5.0, 0.001,
		"five times the health bar, five times the cost of the same drop")
	assert_almost_eq(FallDamage.hp_scale(2.0, BASE_HP), 0.5, 0.001,
		"and it runs the other way too: a FRAGILE actor takes proportionally less, so a 2 HP dummy isn't killed by a hop")

## The off switch, plus the guard that keeps a garbage input from producing a garbage curve.
func test_a_non_positive_reference_means_do_not_scale() -> void:
	assert_eq(FallDamage.hp_scale(GROWN_HP, 0.0), 1.0,
		"reference 0 is 'unscaled' — the honest answer when no baseline was ever captured, not a division by zero")
	assert_eq(FallDamage.hp_scale(GROWN_HP, -3.0), 1.0,
		"a negative reference is nonsense and must not invert the curve into a fall that HEALS you")
	assert_eq(FallDamage.hp_scale(-5.0, BASE_HP), 0.0,
		"negative max HP floors at a 0 scale (a free landing), never a negative cost")

## THE HEADLINE. The same drop costs the same share of the health bar however big the bar has grown.
func test_the_same_drop_costs_the_same_fraction_of_your_health_at_any_max_hp() -> void:
	var speed := 20.0  # 4 m/s over the safe speed: half of the shipped player's health
	var small := FallDamage.hp_loss(speed, MIN_SPEED, PER_SPEED * FallDamage.hp_scale(BASE_HP, BASE_HP))
	var big := FallDamage.hp_loss(speed, MIN_SPEED, PER_SPEED * FallDamage.hp_scale(GROWN_HP, BASE_HP))
	assert_eq(small, 2, "20 m/s takes 2 of the shipped player's 4 HP — half the bar")
	assert_eq(big, 10, "the SAME drop takes 10 of a 20 HP player's — still half the bar, which is the whole point")
	assert_almost_eq(float(small) / BASE_HP, float(big) / GROWN_HP, 0.001,
		"the fraction of max HP is the invariant this feature buys; if these ever diverge, height has stopped meaning the same thing at different levels")

## THE OTHER HALF OF THE HEADLINE: the drop that kills a HEALTHY actor is the same drop at every max HP. This is
## the number a player learns with their body — "I can't survive that ledge" — and it must not move as they level.
func test_the_lethal_height_at_full_health_does_not_move_as_you_grow() -> void:
	for m in [BASE_HP, 7.0, GROWN_HP, 100.0]:
		var scaled: float = PER_SPEED * FallDamage.hp_scale(m, BASE_HP)
		assert_almost_eq(FallDamage.lethal_speed(MIN_SPEED, scaled, m), LETHAL_SPEED, 0.001,
			"a full-health actor with %s max HP must still die at %s m/s" % [m, LETHAL_SPEED])

## The regression, stated as the size of the hole that was there (unscaled, a 20 HP player survived to 56 m/s), and
## shut on the ACTOR the game reads: a grown Character's own effective_fall_damage_* curve and its real landing
## (Character._apply_fall_damage), never a cost this test multiplies together itself.
func test_buying_max_hp_no_longer_buys_fall_immunity() -> void:
	assert_almost_eq(FallDamage.lethal_speed(MIN_SPEED, PER_SPEED, GROWN_HP), 56.0, 0.001,
		"the hole, for the record: scored on the flat 0.5-per-m/s export, a full 20 HP bar survived everything under 56 m/s")
	var grown = _grown_character(GROWN_HP)
	grown.hp = GROWN_HP
	var lethal: float = FallDamage.lethal_speed(grown.effective_fall_damage_min_speed(), grown.effective_fall_damage_per_speed(), grown.hp)
	assert_almost_eq(lethal, LETHAL_SPEED, 0.001,
		"a full-health 20 HP actor's own curve must kill at the shipped player's %s m/s, not at 56 — earned health must not retire the level's ledges" % LETHAL_SPEED)
	# Driven through the real landing, a hair under that speed so nothing dies off-tree: the grown body must be left on
	# its LAST point, exactly like the shipped player. Scored on the unscaled export it would walk away with 17 of 20.
	var near_lethal := LETHAL_SPEED - 0.1
	var shipped = _grown_character(BASE_HP)
	shipped.hp = BASE_HP
	shipped._apply_fall_damage(near_lethal)
	assert_almost_eq(shipped.hp, 1.0, 0.001, "control: a %s m/s landing leaves the shipped 4 HP player on its last point" % near_lethal)
	grown._apply_fall_damage(near_lethal)
	assert_almost_eq(grown.hp, 1.0, 0.001,
		"the same landing must leave a grown 20 HP body on its last point too, not on 17 — extra max HP must buy no fall margin")

## Being HURT still greys the screen earlier, because the scale reads max_hp and lethal_speed reads hp. The two
## must not collapse into each other: damage is scored against the bar you OWN, survival against what is LEFT.
func test_the_scale_reads_max_hp_while_survival_still_reads_the_health_you_have_left() -> void:
	var scaled: float = PER_SPEED * FallDamage.hp_scale(GROWN_HP, BASE_HP)  # 2.5 HP per m/s over
	assert_almost_eq(FallDamage.lethal_speed(MIN_SPEED, scaled, GROWN_HP), LETHAL_SPEED, 0.001,
		"at full health, the shipped lethal speed")
	assert_almost_eq(FallDamage.lethal_speed(MIN_SPEED, scaled, 5.0), 18.0, 0.001,
		"down to 5 of 20 HP, 18 m/s is now lethal — a quarter of the bar left means a quarter of the fall kills you")
	assert_lt(FallDamage.lethal_fraction(20.0, MIN_SPEED, scaled, GROWN_HP),
			FallDamage.lethal_fraction(20.0, MIN_SPEED, scaled, 5.0),
		"so the same 20 m/s drop must read greyer when hurt — the warning still moves with remaining HP after scaling")


# =============================================================================================================
# 2. The actor seam
# =============================================================================================================

## THE SAFETY PROMISE that lets this land on a tuned game: a reference of 0 auto-calibrates to the actor's own
## authored max_hp, so on the frame it spawns every character whose stat sheet adds no HP is scored by exactly the
## curve it was tuned with. The loop covers representative authored pools (the shipped player's 4, the 2 HP TestLevel
## dummy, a mid and a huge one) rather than enumerating shipped actors. (A strength sheet DOES scale from frame one,
## deliberately: see the export doc.)
func test_every_actor_spawns_at_a_scale_of_exactly_one() -> void:
	for authored in [BASE_HP, 2.0, 14.0, 100.0]:
		var c = _character()
		c.max_hp = authored
		c.fall_damage_per_speed = PER_SPEED
		c._apply_stats()
		assert_almost_eq(c.fall_damage_reference_hp(), authored, 0.001,
			"with no explicit reference the baseline is the actor's own authored max_hp (%s)" % authored)
		assert_almost_eq(c.effective_fall_damage_per_speed(), PER_SPEED, 0.001,
			"...so a freshly spawned %s HP actor takes precisely its shipped fall damage" % authored)

## An off-tree Character that never ran _apply_stats has no baseline. It must fall back to the live max_hp — a
## scale of 1.0 — rather than to 0 (which would divide) or to a guessed constant (which would silently rescale a
## test fixture or a hand-built Character into damage nobody authored).
func test_an_actor_with_no_captured_baseline_is_left_unscaled() -> void:
	var c = _character()
	c.max_hp = GROWN_HP
	c.fall_damage_per_speed = PER_SPEED
	assert_almost_eq(c.fall_damage_reference_hp(), GROWN_HP, 0.001,
		"no _apply_stats, no baseline — the reference falls back to the live max_hp")
	assert_almost_eq(c.effective_fall_damage_per_speed(), PER_SPEED, 0.001,
		"...which is a scale of 1.0: unknown provenance must mean 'unchanged', never a guess")

## The health you EARN is what moves the curve — the whole feature, at the seam the game actually reads.
func test_earned_max_hp_scales_the_cost() -> void:
	var c = _grown_character(GROWN_HP)
	assert_almost_eq(c.fall_damage_reference_hp(), BASE_HP, 0.001,
		"the baseline is still the AUTHORED 4.0 — growing max_hp must not drag the reference along with it, or the scale would be permanently 1.0 and the feature dead")
	assert_almost_eq(c.effective_fall_damage_per_speed(), 2.5, 0.001,
		"5x the health bar, 5x the cost per m/s")
	assert_eq(FallDamage.hp_loss(20.0, MIN_SPEED, c.effective_fall_damage_per_speed()), 10,
		"the 20 m/s drop that took half the shipped player's bar takes half of this one's")

## Losing max HP (a debuff, dropping a +HP item) has to walk back down the same curve, not latch at the peak.
func test_losing_max_hp_walks_the_cost_back_down() -> void:
	var c = _grown_character(GROWN_HP)
	c.max_hp = BASE_HP
	assert_almost_eq(c.effective_fall_damage_per_speed(), PER_SPEED, 0.001,
		"back at the authored max HP, back to the authored cost — the scale is read live, never banked")

## THE READERS, DRIVEN (the behavioural half of section 3, whose text pins below stay as the spelling guard).
## Character._apply_fall_damage is the shared landing cost for the player and every NPC: drive it on a grown body and
## on a shipped one, and the SAME drop must take the SAME share of each bar. A reader that scored the landing with the
## raw export would take 2 HP off both — half the shipped bar, a tenth of the grown one.
func test_the_shared_landing_reader_takes_the_same_share_of_a_grown_bar() -> void:
	var grown = _grown_character(GROWN_HP)
	grown.hp = GROWN_HP
	grown._apply_fall_damage(20.0)
	var shipped = _grown_character(BASE_HP)
	shipped.hp = BASE_HP
	shipped._apply_fall_damage(20.0)
	assert_almost_eq(GROWN_HP - grown.hp, 10.0, 0.001,
		"a 20 m/s landing must take 10 of a grown 20 HP bar through the real reader — the half-bar the shipped player loses")
	assert_almost_eq(BASE_HP - shipped.hp, 2.0, 0.001, "control: the same landing takes 2 of the shipped 4 HP bar")
	var safe = _grown_character(GROWN_HP)
	safe.hp = GROWN_HP
	safe._apply_fall_damage(MIN_SPEED)
	assert_almost_eq(safe.hp, GROWN_HP, 0.001, "a landing AT the safe speed costs nothing, however big the bar has grown")


## GameSettings.player_feedback is one shared resource and the warning test below writes its fall_grey_max. Snapshot it
## before every test and put it back after, so a test that errors half-way can never leak a raw-drain peak into the suite.
var _saved_grey_peak: float = 0.0

func before_each() -> void:
	_saved_grey_peak = GameSettings.player_feedback.fall_grey_max

func after_each() -> void:
	GameSettings.player_feedback.fall_grey_max = _saved_grey_peak


## ⭐ The headline promise, driven: the grey fall WARNING (Player._fall_grey_target, off-tree) must drain exactly as far as
## the landing will actually cost (Character._apply_fall_damage on a body with the same profile), at every speed, on
## a grown bar. A warning scored on the unscaled curve reads 0.1 at 20 m/s while the ground takes half the bar.
func test_the_warning_drains_exactly_as_far_as_the_landing_will_cost() -> void:
	var p = autofree(load(PLAYER_PATH).new())  # off-tree: no _ready, per the house rule
	p.max_hp = BASE_HP
	p.fall_damage_min_speed = MIN_SPEED
	p.fall_damage_per_speed = PER_SPEED
	p._apply_stats()  # captures the authored 4.0, exactly like _grown_character
	p.max_hp = GROWN_HP
	p.hp = GROWN_HP
	GameSettings.player_feedback.fall_grey_max = 1.0  # read the raw drain, not the designer's peak scaling of it (after_each restores)
	var speeds := [18.0, 20.0, 22.0, LETHAL_SPEED]
	var warnings: Array[float] = []
	for v in speeds:
		p.velocity = Vector3(0.0, -v, 0.0)
		warnings.append(p._fall_grey_target())
	for i in range(3):
		var body = _grown_character(GROWN_HP)
		body.hp = GROWN_HP
		body._apply_fall_damage(speeds[i])
		var cost_share: float = (GROWN_HP - body.hp) / GROWN_HP
		assert_gt(cost_share, 0.0, "control: a %s m/s landing must cost the grown body something" % speeds[i])
		assert_almost_eq(warnings[i], cost_share, 0.001,
			"at %s m/s the warning reads %s grey but the landing takes %s of the bar — the screen must score the fall on the SAME curve that deals the damage" % [speeds[i], warnings[i], cost_share])
	assert_almost_eq(warnings[3], 1.0, 0.001,
		"at the shipped lethal speed a full-health grown player must see a completely grey frame — the whole bar is about to go")

## An off-tree body carrying the shipped fall profile on `sheet` (null = no sheet, which reads as a baseline one), with
## _apply_stats run and a full health bar. `script_path` picks a plain Character or the Player (whose _fall_grey_target
## is the warning reader); neither is ever added to the tree, so no _ready runs.
func _fall_body(script_path: String, sheet: CharacterStats):
	var b = autofree(load(script_path).new())
	b.stats = sheet
	b.max_hp = BASE_HP
	b.fall_damage_min_speed = MIN_SPEED
	b.fall_damage_per_speed = PER_SPEED
	b._apply_stats()
	b.hp = BASE_HP
	return b

## THE READERS, DRIVEN ON THE SAFE-SPEED HALF. Both readers must start the curve at the AGILITY-stretched safe speed
## (effective_fall_damage_min_speed), not at the raw export — at baseline agility the two are the same number, so only an
## agile sheet can tell them apart. A landing over the raw 16 m/s but under the stretched safe speed must cost the agile
## body nothing AND show the agile player no warning; the same landing on a baseline sheet is the control that it is a
## real, damaging landing that only the stretch spared.
func test_both_readers_start_the_curve_at_the_agility_stretched_safe_speed() -> void:
	var agile := CharacterStats.new()
	agile.agility = 10
	var agile_body = _fall_body(CHARACTER_PATH, agile)
	var safe: float = agile_body.effective_fall_damage_min_speed()
	assert_gt(safe, MIN_SPEED + 1.0,
		"sanity: agility 10 must stretch the safe speed well past the raw %s m/s export, or this test cannot tell the two apart (got %s)" % [MIN_SPEED, safe])
	var landing := safe - 0.5  # over the raw export, under the stretched safe speed
	assert_gt(landing, MIN_SPEED, "sanity: the test landing is faster than the raw safe speed")

	var base_body = _fall_body(CHARACTER_PATH, null)
	base_body._apply_fall_damage(landing)
	assert_lt(base_body.hp, BASE_HP, "control: a %s m/s landing on a baseline sheet costs HP" % landing)
	agile_body._apply_fall_damage(landing)
	assert_almost_eq(agile_body.hp, BASE_HP, 0.001,
		"Character._apply_fall_damage: under the agility-stretched safe speed (%s m/s) a %s m/s landing is free" % [safe, landing])

	GameSettings.player_feedback.fall_grey_max = 1.0  # the raw drain, not the designer's peak scaling (after_each restores)
	var base_player = _fall_body(PLAYER_PATH, null)
	base_player.velocity = Vector3(0.0, -landing, 0.0)
	assert_gt(base_player._fall_grey_target(), 0.0, "control: on a baseline sheet the same fall greys the screen")
	var agile_player = _fall_body(PLAYER_PATH, agile)
	agile_player.velocity = Vector3(0.0, -landing, 0.0)
	assert_eq(agile_player._fall_grey_target(), 0.0,
		"Player._fall_grey_target: a landing the agile body takes for free must show no warning — the screen scores the fall on the same stretched curve")

## The explicit knob, for a designer who wants a tougher archetype's extra HP to be real fall protection rather
## than something the scale immediately takes back.
func test_an_explicit_reference_pins_the_curve_against_the_auto_baseline() -> void:
	var c = _grown_character(GROWN_HP)
	c.fall_damage_reference_max_hp = 10.0
	assert_almost_eq(c.fall_damage_reference_hp(), 10.0, 0.001,
		"a positive explicit reference wins over the captured baseline")
	assert_almost_eq(c.effective_fall_damage_per_speed(), 1.0, 0.001,
		"20 HP against a reference of 10 is a 2x scale, so this actor's spare 10 HP really is spare")


# =============================================================================================================
# 3. The readers — the cost and the warning must be scored by the SAME number
# =============================================================================================================

## A FallDamage call that names a RAW export anywhere on its line. `[^_]` is what lets the effective_ seams through
## (their `fall_damage_` is preceded by an underscore); `.*` rather than `[^)]*` because the seams' own `()` would
## otherwise end the scan before it reached a raw export later in the same call.
func _raw_export_in_a_fall_call() -> RegEx:
	return RegEx.create_from_string(r"FallDamage\.(hp_loss|lethal_fraction|lethal_speed)\(.*[^_]fall_damage_(per|min)_speed")

func _read(path: String) -> String:
	var s := FileAccess.get_file_as_string(path)
	assert_false(s.is_empty(), "%s must be readable" % path)
	return s

## Character._apply_fall_damage is the shared cost for the player's landing block AND for NPCs (npc.gd's
## apply_velocity reaches it). If it reads a raw export, nothing scales anywhere. The landing tests above DRIVE this
## reader on both halves of the seam (a grown max HP and an agile sheet); this text pin is the spelling guard beside them.
func test_the_shared_cost_goes_through_the_scaled_seam() -> void:
	var src := _read(CHARACTER_PATH)
	assert_true("FallDamage.hp_loss(fall_speed, effective_fall_damage_min_speed(), effective_fall_damage_per_speed())" in src,
		"Character._apply_fall_damage must score the landing with BOTH effective_fall_damage_* seams (max HP + agility), not the raw exports")
	assert_null(_raw_export_in_a_fall_call().search(src),
		"no FallDamage call in character.gd may pass a raw fall_damage_min_speed / fall_damage_per_speed export")

## ⭐ THE ONE THAT MATTERS MOST. player.gd has TWO readers — the damage and the grayscale fall warning — and they
## must agree. Feed the warning the unscaled export and it drains to full grey at 56 m/s while the ground kills
## you at 24: the screen would promise a survivable landing right up to the frame it kills you, with no error and no
## crash. The WARNING reader is also driven above (test_the_warning_drains_exactly_as_far_as_the_landing_will_cost and
## the agility safe-speed test); the Player's own landing PREVIEW is not driven anywhere in this file, so for that reader
## this pin is the only guard here.
func test_the_damage_and_the_warning_read_the_same_scaled_cost() -> void:
	var src := _read(PLAYER_PATH)
	assert_true("FallDamage.hp_loss(fall_speed, effective_fall_damage_min_speed(), effective_fall_damage_per_speed())" in src,
		"the Player's _apply_fall_damage override previews the cost to arm the fall death card — it must preview the SCALED curve the base will actually deal")
	assert_true("FallDamage.lethal_fraction(-velocity.y, effective_fall_damage_min_speed(), effective_fall_damage_per_speed(), hp)" in src,
		"_fall_grey_target must score the warning with the same scaled curve — a warning drawn from a different curve than the damage is worse than no warning at all")
	assert_null(_raw_export_in_a_fall_call().search(src),
		"no FallDamage call in player.gd may pass a raw fall_damage_min_speed / fall_damage_per_speed export — go through the effective_fall_damage_* seams")
