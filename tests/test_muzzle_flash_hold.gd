extends GutTest

## MuzzleFlash.hold_seconds — the rule that keeps a RAPID-FIRE automatic weapon's muzzle flash lit from round
## to round instead of blinking it off between them.
##
## ⭐WHY THIS FILE EXISTS. The SMG cycles every 0.125 s against a 0.1 s flash blink, so the flash went dark
## for a frame or two between EVERY round: an 8 Hz on/off of a bright disc dead centre while aiming (captured
## 2026-09-16 by scripts/tools/probes/__smg_ads_strobe_probe.gd — 6 lit frames, 2 dark, repeat). Together
## with the recoil kick driving that disc into the lens (tests/test_view_model_kick_ads.gd) it was the
## "seizure inducing" aim-down-sights the user reported. These tests pin the hold so a retune of the blink or
## the SMG's cadence can't quietly bring the strobe back, and so the pistol's per-shot blink stays a blink.

const BLINK := 0.1
const FRAME := 1.0 / 60.0


func test_semi_auto_always_blinks() -> void:
	assert_almost_eq(MuzzleFlash.hold_seconds(BLINK, false, 0.05, FRAME), BLINK, 0.0001,
		"a semi-auto weapon fires one round per click — it can't strobe, so it keeps the plain blink whatever its cadence")


func test_slow_automatic_keeps_the_per_shot_blink() -> void:
	assert_almost_eq(MuzzleFlash.hold_seconds(BLINK, true, 0.44, FRAME), BLINK, 0.0001,
		"the pistol (0.44 s cadence) leaves a real gap between rounds — its flash must stay a per-shot blink, not a 0.44 s glow")


func test_rapid_automatic_holds_across_the_gap() -> void:
	var hold := MuzzleFlash.hold_seconds(BLINK, true, 0.125, FRAME)
	assert_true(hold > 0.125,
		"an 8 rounds/s weapon must hold its flash LONGER than its 0.125 s cadence so the next round re-lights it before it hides — got %.4f" % hold)
	assert_almost_eq(hold, 0.125 + FRAME, 0.0001,
		"the hold is the cadence plus one frame of slack, no more — a longer tail would smear the flash past the last round")


func test_hold_is_never_shorter_than_the_blink() -> void:
	assert_almost_eq(MuzzleFlash.hold_seconds(BLINK, true, 0.02, FRAME), BLINK, 0.0001,
		"a cadence so fast that cadence + frame is under the blink still gets the full blink — the hold only ever lengthens")


func test_shipped_smg_falls_on_the_hold_side() -> void:
	var smg: WeaponData = load("res://resources/weapons/smg.tres")
	var blink: float = WeaponGeneralSettings.new().muzzle_flash_duration
	var ceiling: float = blink * MuzzleFlash.RAPID_FIRE_HOLD_RATIO
	assert_true(smg.auto_fire, "the SMG must be automatic for the hold to apply at all")
	assert_true(smg.attack_speed < ceiling,
		"the SMG's cadence (%.3f s) must sit under blink x ratio (%.3f s) — otherwise it is back to strobing" % [smg.attack_speed, ceiling])
	var hold := MuzzleFlash.hold_seconds(blink, smg.auto_fire, smg.attack_speed, FRAME)
	assert_true(hold > smg.attack_speed,
		"with the shipped numbers the SMG's flash (%.4f s hold) must outlast its %.3f s cadence" % [hold, smg.attack_speed])


func test_shipped_pistol_still_blinks() -> void:
	var pistol: WeaponData = load("res://resources/weapons/pistol.tres")
	var blink: float = WeaponGeneralSettings.new().muzzle_flash_duration
	assert_almost_eq(MuzzleFlash.hold_seconds(blink, pistol.auto_fire, pistol.attack_speed, FRAME), blink, 0.0001,
		"the pistol's %.2f s cadence must keep the plain per-shot blink — the hold is for rapid fire only" % pistol.attack_speed)
