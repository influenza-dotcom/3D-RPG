extends GutTest

## The aim-down-sights KICK ATTENUATION (EffectsSettings.view_model_kick_ads_mult, applied in GunMesh.fire()
## through GunPose.kick_scale_for_aim).
##
## ⭐WHY THIS FILE EXISTS. Scoped, the view model sits centred a hand's width from the lens under a ~2x
## narrower FOV, and the per-shot kick (view_model_kick_position, 40 cm back at the hip) drove the muzzle —
## and the muzzle-flash sphere riding it — to within centimetres of the camera. Captured on the SMG
## (2026-09-16, scripts/tools/probes/__smg_ads_strobe_probe.gd): the flash grew from a ~10% disc to ~80% of
## the screen and back EIGHT times a second — a full-screen white strobe, "seizure inducing" in the user's
## words. The kick is deliberate hip tuning, so the fix is a scale while aiming, not a revert; these tests pin
## the scale's contract so a retune can't quietly bring the strobe back.


func test_hip_shots_keep_the_full_kick() -> void:
	assert_almost_eq(GunPose.kick_scale_for_aim(0.0, 0.25), 1.0, 0.0001,
		"at ADS blend 0 (hip) the kick must be untouched whatever the ADS multiplier is")


func test_aimed_shots_get_only_the_ads_fraction() -> void:
	assert_almost_eq(GunPose.kick_scale_for_aim(1.0, 0.25), 0.25, 0.0001,
		"fully on the sights the kick must be exactly view_model_kick_ads_mult of the hip kick")
	assert_almost_eq(GunPose.kick_scale_for_aim(0.5, 0.25), 0.625, 0.0001,
		"half-way onto the sights the kick must be the linear blend, so it shrinks with the ADS ease, not a step")


func test_overshoot_never_enlarges_the_kick() -> void:
	assert_almost_eq(GunPose.kick_scale_for_aim(1.2, 0.25), 0.25, 0.0001,
		"an eased blend that overshoots 1 must clamp — a kick BIGGER than the sights' share is the strobe again")
	assert_almost_eq(GunPose.kick_scale_for_aim(-0.2, 0.25), 1.0, 0.0001,
		"a blend under 0 must clamp to the hip kick, never a kick LARGER than the hip's")


func test_shipped_ads_multiplier_is_a_real_shrink() -> void:
	var fx := EffectsSettings.new()
	assert_true(fx.view_model_kick_ads_mult <= 0.35,
		"view_model_kick_ads_mult ships at %.2f — above ~0.35 the SMG's flash sphere reaches the lens again " 		% fx.view_model_kick_ads_mult + "(0.35 of a 0.4 m kick is the 14 cm where the disc passes ~25% of the frame)")
	assert_true(fx.view_model_kick_ads_mult > 0.0,
		"a 0 multiplier deletes all recoil feedback while aiming; ship a small non-zero value")
	var peak_back := fx.view_model_kick_position.z * fx.view_model_kick_ads_mult
	assert_true(peak_back <= 0.14,
		"the aimed kick drives the muzzle %.3f m toward the lens — past 0.14 m the flash sphere fills the frame" % peak_back)


func test_gun_pose_reports_its_eased_blend() -> void:
	var pose := GunPose.new()
	pose._aim_t = 0.6
	assert_almost_eq(pose.aim_blend(), 0.6, 0.0001, "aim_blend() must hand GunMesh.fire() the live eased ADS t")
	pose.free()
