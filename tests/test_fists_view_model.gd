extends GutTest

## Contract tests for the UNARMED first-person visual (resources/weapons/fists.tres).
##
## Unarmed is not a special case in the weapon system — fists.tres is a normal WeaponData that every
## empty-handed fallback equips (Player.FISTS). What makes it read as "unarmed" is that it has NO view model
## at all: the bare fists are the Player's OWN first-person arms rig, the same hands you see when carrying a
## prop, which lives under the camera rather than under the gun rig.
##
## That placement is the whole design, and it is what fixes three things a mounted view-model copy got wrong:
## the hands keep the character's arm colour, they sit centred on the camera instead of offset to the gun's
## side, and they do not tip 45 degrees into the gun's holster park.
##
## The failure modes are silent, so they are pinned here:
##   1. Give fists a `view_model` again and the player holds an object while "unarmed".
##   2. Let a null `view_model` reveal the gun rig's PLACEHOLDER and the player holds a silenced pistol —
##      strictly worse than the claw hammer this replaced.
##   3. Drop the Player-side wiring and the fists never appear, or never punch, with no error anywhere.
##
## Pure Resource + source reads (plus off-tree first_person_body.gd instances — the fists live on the Player's
## FirstPersonBody component now — and, for the weapon-state gate, a bare host player.gd wired on by hand; the
## test_player_core idiom, _ready never runs on either) — no scene instantiation, no audio device.

const FISTS_PATH := "res://resources/weapons/fists.tres"
const WEAPONS_DIR := "res://resources/weapons/"
const PLAYER_SOURCE := "res://scripts/player/player.gd"
const FP_BODY_SOURCE := "res://scripts/player/first_person_body.gd"
const SWAPPER_SOURCE := "res://scripts/effects/weapon_model_swapper.gd"

func _fists() -> WeaponData:
	return load(FISTS_PATH) as WeaponData

# --- The unarmed resource ---------------------------------------------------------------------------

func test_unarmed_mounts_no_weapon_model_at_all() -> void:
	var fists := _fists()
	assert_not_null(fists, "resources/weapons/fists.tres must load as a WeaponData")
	assert_null(fists.view_model,
		"unarmed must mount NO view model — the fists are the Player's own first-person arms rig")
	fists = null

func test_unarmed_declares_that_its_visual_is_first_person_only() -> void:
	# Suppresses the swapper's "you forgot a model" warning (having none is the point here) and makes
	# held_view_model() null so an NPC hand / ground drop / grid tile show nothing.
	var fists := _fists()
	assert_true(fists.view_model_is_first_person_only,
		"fists.tres must declare its visual is first-person-only, or it reads as an un-authored weapon")
	assert_null(fists.held_view_model(),
		"held_view_model() must be null — an NPC hand, a ground drop and a grid tile show NOTHING")
	fists = null

func test_fists_is_flagged_as_a_punch() -> void:
	var fists := _fists()
	assert_true(fists.view_model_punch, "fists.tres must be flagged view_model_punch — its swing is a punch")
	fists = null

func test_a_punch_never_shows_the_fullscreen_hit_flash() -> void:
	# Fists are hitscan, so without this exemption every swing popped the camera's white hit-flash — a per-punch
	# screen strobe. The gate must stay VISIBILITY-only ("_show_flash"), never around the whole flash block: the
	# 85ms await + abort window is combat timing, and gating it once made a settings toggle change damage
	# outcomes (see the comment at the site in attack.gd).
	var src := FileAccess.get_file_as_string("res://scripts/combat/attack.gd")
	assert_true(src.contains("Settings.screen_flash_enabled and not current_weapon.view_model_punch"),
		"a view_model_punch swing must be exempt from the hitscan white-flash, on the visibility gate only")

# --- The placeholder trap ---------------------------------------------------------------------------

func test_a_missing_view_model_never_reveals_the_placeholder_pistol() -> void:
	# THE regression that makes "unarmed" hand you a gun. The rig's built-in Sketchfab_Scene is an instance of
	# silenced.tscn, so the old fall-back-to-placeholder behaviour is unsafe now that a real weapon (fists)
	# ships with no view model.
	var src := FileAccess.get_file_as_string(SWAPPER_SOURCE)
	assert_false(src.contains("_set_placeholder_hidden(false)"),
		"the swapper must never REVEAL the placeholder — it is a silenced pistol, and unarmed has no view model")

# --- The Player-side wiring, pinned by source --------------------------------------------------------

func test_the_player_shows_and_punches_with_its_own_hands() -> void:
	# In-tree behaviour a unit test must not run (building the Player runs weapons, nav and audio), so the
	# wiring is pinned by source — the tests/test_npc_home_return.gd idiom. Split across two files since the
	# FirstPersonBody extraction: the COMPONENT owns the fists (the decision + the strike), the PLAYER keeps
	# the host-side wiring that drives them.
	var body_src := FileAccess.get_file_as_string(FP_BODY_SOURCE)
	assert_true(body_src.contains("func _unarmed_hands_wanted()"),
		"the FirstPersonBody decides when the bare fists are up in one place")
	assert_true(body_src.contains("func refresh_unarmed_hands"),
		"and exposes the public refresh the host drives off holster / weapon-swap / carry changes")
	assert_true(body_src.contains("_fp_arms.strike("),
		"punching must drive the hands' own strike — without it the swing has no animation at all")
	var src := FileAccess.get_file_as_string(PLAYER_SOURCE)
	assert_true(src.contains("fp_body.refresh_unarmed_hands"),
		"the Player must actually CALL that refresh from its holster/swap wiring — drop it and the fists never move")
	assert_true(src.contains("weapon_system.attack.play_animation.connect(fp_body.on_attack_play_animation)"),
		"the punch must hang off Attack.play_animation, the one per-swing signal")

func test_the_fists_rest_closer_to_the_camera_than_the_carry_hold() -> void:
	# The GUARD geometry, pinned because it is counter-intuitive and was tuned by rendering it (the fists-frame
	# probe, 2026-08-05): the shoulders DROP while a STEEP rig tilt swings the arms up, so the fists rise into
	# the lower third FORESHORTENED — that foreshortening is what reads as "fists close". A shallow tilt with a
	# raised rest is the regression this replaces: fully extended arms reaching to a far point near screen
	# centre. Off-tree FirstPersonBody instance — _ready never runs; every helper here is pure math over
	# exports + the latch, no host needed.
	var p = load(FP_BODY_SOURCE).new()
	var carry: Vector3 = p._fp_arm_rest()
	assert_eq(carry, p.fp_arm_offset,
		"with the fists down the hands must rest at the carry hold (fp_arm_offset), unchanged")
	assert_eq(p._fp_arm_rest_tilt(), 0.0,
		"and rest FLAT — the carry hold reaches for a prop, it doesn't guard")
	assert_eq(p._fp_arm_rest_scale(), p.fp_arm_scale,
		"and at the authored carry scale — the hold must stay sized to the props it reaches for")
	assert_eq(p._fp_arm_rest_spread(), p.fp_arm_spread,
		"and at the authored carry spread — the hold's hands sit where the held prop is")
	p._unarmed_hands_up = true
	var guard: Vector3 = p._fp_arm_rest()
	assert_eq(guard, p.fp_arm_offset + p.fp_arm_unarmed_nudge,
		"with the fists up the rest must be the carry hold + fp_arm_unarmed_nudge — one relative knob, no second rig")
	assert_gt(guard.z, carry.z,
		"the guard must sit NEARER the lens (+Z is toward the camera) than the carry hold")
	assert_gte(p._fp_arm_rest_tilt(), 30.0,
		"the guard tilt must stay STEEP — the foreshortening IS what reads as close; shallow tilt = arms reaching to a far point (the exact regression the render probe caught)")
	assert_gt(p._fp_arm_rest_scale(), p.fp_arm_scale,
		"the guard must scale the fists UP (fp_arm_unarmed_scale_mult > 1) — the size boost on top of the foreshortening")
	assert_gt(p._fp_arm_rest_spread(), p.fp_arm_spread,
		"the guard must spread WIDER than the carry hold, so the two fists read distinct and never cover the crosshair")
	assert_gt(p.fp_arm_unarmed_bob_pos, 0.0,
		"the fists must ship with a walk-bob (fp_arm_unarmed_bob_pos > 0) — like every mounted weapon's GunPose bob")
	assert_gt(p.fp_arm_unarmed_breath_pos, 0.0,
		"and with an idle breath (fp_arm_unarmed_breath_pos > 0) — standing guard must read alive, not statue hands")
	assert_gt(p.fp_arm_unarmed_stride_deg, 0.0,
		"and with a walking arm-pump (fp_arm_unarmed_stride_deg > 0) — the fists alternate, not bob in lockstep")
	var swap_src := FileAccess.get_file_as_string("res://scripts/components/body_model_swap.gd")
	assert_true(swap_src.contains("-arm_stride_deg"),
		"the RIGHT arm must take the NEGATED stride — without the sign flip the 'stride' is just more symmetric bob")
	p.free()

func test_the_stow_sinks_straight_down_from_whatever_pose_it_leaves() -> void:
	# The 2026-08-09 report: "when holstering my unarmed fists it doesn't go down — they extend outward first
	# and then disappear." The stow target was hardcoded to `fp_arm_offset - fp_arm_draw_rise`, anchored to the
	# CARRY rest on the (once true) reasoning that it was the lower of the two rests. The guard nudge is
	# negative in Y and large in +Z, so at the AUTHORED pose that anchor sat ABOVE the guard and 1.49 m toward
	# the lens: holstering RAISED the fists and threw them a metre and a half forward, then blinked them off at
	# peak size — a reach, not a stow. Render-proven.
	#
	# ⭐This is why the pin drives an ARBITRARY pose rather than the script defaults: at the DEFAULT nudge the
	# carry anchor really is below the guard, so the bug was invisible off-tree and only ever showed against
	# Player.tscn's authored numbers (on the FirstPersonBody child, since the extraction). Anything that
	# re-anchors the stow to a named rest must fail here.
	var script := load(FP_BODY_SOURCE)
	var rise := 0.35
	for pose in [Vector3(0, -1.83, 1.745), Vector3(0, -1.125, 0.255), Vector3(0.4, 2.0, -3.0), Vector3.ZERO]:
		var target: Vector3 = script.fp_arm_stow_target(pose, rise)
		assert_almost_eq(target.x, pose.x, 0.00001,
			"a stow must not travel SIDEWAYS — x is the pose's, whatever rest it leaves from")
		assert_almost_eq(target.z, pose.z, 0.00001,
			"and must not travel in DEPTH — a z shift is the fists reaching outward / away, the reported bug")
		assert_almost_eq(target.y, pose.y - rise, 0.00001,
			"it must drop exactly fp_arm_draw_rise BELOW where the hands actually are")
		assert_lt(target.y, pose.y,
			"and always downward — a stow that ends ABOVE its start is a draw with the frames reversed")

# --- The walk-bob anti-jitter contract ---------------------------------------------------------------

func test_the_bob_phase_only_advances_and_stays_bounded() -> void:
	# This is the 2026-08-08 "the fists jitter while walking" regression, pinned.
	#
	# The phase used to be EASED TOWARD ZERO on any frame that wasn't "grounded and moving". A phase grows
	# without bound while you walk, so that lerp moved it TENS OF RADIANS in a single frame — whole bob cycles.
	# And `is_on_floor()` blips false for single frames constantly while genuinely walking (brush seams, the
	# 0.5 m stair risers, any bump), so every blip teleported the hands to an unrelated point in the walk cycle.
	# Measured on the shipped rig that was a 6.3 deg one-frame stride snap = 0.32 m of fist travel; the fix
	# brings the worst single-frame step to 0.42 deg = 0.021 m, i.e. the normal walk cadence.
	var script := load(FP_BODY_SOURCE)
	var dt := 1.0 / 60.0
	var speed := 8.0  # GameSettings.camera.bob_speed default
	# 60 s of walking — the phase must stay small, not drift into the hundreds.
	var phase := 0.0
	for i in 3600:
		phase = script.advance_bob_phase(phase, speed, dt, true)
	assert_between(phase, 0.0, TAU * 2.0,
		"the walk-bob phase must stay WRAPPED inside one half-rate period (TAU*2), however long you walk")
	# The load-bearing one: a non-advancing frame must HOLD the phase, never ease it toward zero.
	var held: float = script.advance_bob_phase(phase, speed, dt, false)
	assert_eq(held, phase,
		"a non-advancing frame must HOLD the phase — easing a PHASE toward zero is what made a one-frame is_on_floor() blip teleport the fists mid-stride")
	# And an advancing frame moves it by exactly one step (never backwards by a jump).
	var stepped: float = script.advance_bob_phase(phase, speed, dt, true)
	assert_almost_eq(absf(wrapf(stepped - phase, -PI, PI)), dt * speed, 0.0001,
		"an advancing frame must move the phase by exactly delta * bob_speed")

func test_the_bob_cadence_scales_with_speed_and_has_a_true_off_position() -> void:
	# "I want the fists bobbing to actually scale with how fast the player moves" (2026-08-09). Amplitude
	# already scaled; the CADENCE was flat, so a walk and a sprint traced the same figure-eight at the same
	# footstep rate — one gait at two volumes.
	var script := load(FP_BODY_SOURCE)
	var base := 8.0  # GameSettings.camera.bob_speed default
	# gain 0 is a TRUE off switch: the flat rate at every speed, i.e. the behaviour this replaced, bit for bit.
	for ratio in [0.0, 0.5, 1.0, 3.0]:
		assert_almost_eq(script.bob_cadence(base, ratio, 0.0), base, 0.00001,
			"gain 0 must return the flat authored rate at EVERY speed — the knob's off position must not drift")
	# Monotone in speed, and a walk must be visibly slower than a run (that gap IS the feature).
	var walk: float = script.bob_cadence(base, 0.7, 0.7)   # walk_speed_mult
	var run: float = script.bob_cadence(base, 1.0, 0.7)
	assert_lt(walk, run, "a walk must pump SLOWER than a run")
	assert_almost_eq(run, base, 0.00001,
		"the run tier must land on the authored rate exactly — the knob retimes the tiers around it, not past it")
	# A boost stack speeds it up but can never strobe: the ceiling only opens as far as the designer's gain.
	var bhop: float = script.bob_cadence(base, 12.0, 0.7)
	assert_gt(bhop, run, "a bhop-boosted sprint must pump faster than the run tier")
	assert_lte(bhop, base * (1.0 + 0.7 * 2.0) + 0.00001,
		"...but stay under the gain-proportional ceiling — an unclamped rate blurs the arms")

func test_the_bob_leans_against_the_direction_of_travel() -> void:
	# The other half of the same ask ("...which direction"). Inertia: the pair drifts AGAINST the move, the
	# same sign rule HudSway.velocity_target uses for the corner HUD.
	var script := load(FP_BODY_SOURCE)
	var travel := 0.127  # Player.tscn's FirstPersonBody fp_arm_unarmed_bob_pos — the authored value, not the script default
	var mult := Vector2(0.6, 0.4)
	assert_lt(script.bob_lean(1.0, 0.0, travel, mult).x, 0.0,
		"strafing RIGHT must drift the fists LEFT — leaning INTO the move reads as the hands leading the body")
	assert_gt(script.bob_lean(-1.0, 0.0, travel, mult).x, 0.0, "and strafing left, right — the read is symmetric")
	assert_gt(script.bob_lean(0.0, 1.0, travel, mult).z, 0.0,
		"running FORWARD must trail the fists back toward the lens (+Z is behind the camera)")
	assert_lt(script.bob_lean(0.0, -1.0, travel, mult).z, 0.0, "and backpedalling must press them away from it")
	assert_eq(script.bob_lean(0.0, 0.0, travel, mult), Vector3.ZERO, "standing still must not lean at all")
	assert_eq(script.bob_lean(1.0, 1.0, travel, Vector2.ZERO), Vector3.ZERO,
		"and a zeroed multiplier must be direction-blind — the knob needs an off position too")
	# The lean is a MULTIPLE of the bob travel on purpose: absolute metres would stop reading the next time
	# the guard pose (and with it every depth-coupled travel knob) is retuned.
	var doubled: Vector3 = script.bob_lean(1.0, 1.0, travel * 2.0, mult)
	assert_almost_eq(doubled.x, script.bob_lean(1.0, 1.0, travel, mult).x * 2.0, 0.00001,
		"the lean must scale with fp_arm_unarmed_bob_pos — it is expressed relative to the bob travel")
	# Ratios clamp at the run tier: a boost buys cadence, never more reach on a ~2.9 m lever.
	assert_eq(script.bob_lean(9.0, 9.0, travel, mult), script.bob_lean(1.0, 1.0, travel, mult),
		"a bhop-boosted ratio must clamp to the run tier's lean — unclamped travel is how the 08-08 stride popped")

func test_the_walk_bob_amplitude_is_eased_not_stepped() -> void:
	# The phase fix above is only half of it: the AMPLITUDE must ease too. Taking the raw
	# grounded-and-moving gate as the amplitude meant one blip frame drove the arm-pump to zero and the next
	# drove it back to full — a ±fp_arm_unarmed_stride_deg snap on a ~2.9 m lever. The stride write is
	# smoothed for the same reason (it drives a lever, so degrees here are decimetres of fist on screen).
	var src := FileAccess.get_file_as_string(FP_BODY_SOURCE)
	assert_true(src.contains("_fp_bob_amp = lerpf("),
		"the walk-bob amplitude must be EASED into _fp_bob_amp, never assigned straight from the grounded/moving gate")
	assert_false(src.contains("_fp_bob_time = lerpf("),
		"the bob PHASE must never be lerped — that is the jitter bug; ease the amplitude instead (see advance_bob_phase)")
	assert_true(src.contains("_fp_arms.arm_stride_deg = lerpf("),
		"the arm-pump must be written SMOOTHED — a raw write pops the whole pair on any single-frame amplitude change")

func test_the_fists_stay_down_while_a_real_weapon_is_mid_draw() -> void:
	# The bare-fist FLASH fix (the H toggle's put-back): between the carry release and the rewield landing, the
	# combat inventory still reads FISTS + unholstered — exactly the state that raises the fists — so
	# _unarmed_hands_wanted() must refuse while either suppressor is up: the player's _rewield_in_flight latch
	# (stash_held_item's synchronous release→equip span) or the BACKPACK's optimistic equipped_item (a
	# real-weapon draw QUEUED behind a mid-flight swap lands frames later). Off-tree: the FirstPersonBody with
	# a bare host Player + Weapon hub + BodyModelSwap wired by hand, _ready never runs on any of them (the
	# test_player_core idiom) — the component READS the suppressors off its host, it holds none itself.
	var p = load(PLAYER_SOURCE).new()
	var body = load(FP_BODY_SOURCE).new()
	body.host = p
	var ws := Weapon.new()
	var hub := Inventory.new()
	ws.inventory = hub
	p.weapon_system = ws
	var arms := BodyModelSwap.new()
	body._fp_arms = arms
	hub.equipped_weapon = _fists()
	assert_true(body._unarmed_hands_wanted(),
		"baseline: FISTS equipped, unholstered, empty-handed — the fists are wanted")
	p._rewield_in_flight = true
	assert_false(body._unarmed_hands_wanted(),
		"the put-back's release→equip window must suppress the fists — this IS the flash fix")
	p._rewield_in_flight = false
	var bag := CharacterInventory.new()
	p.inventory = bag
	assert_true(body._unarmed_hands_wanted(),
		"an empty backpack equipped-marker changes nothing — genuine unarmed still raises the fists")
	var knife := Item.new()
	knife.category = Item.Category.WEAPON
	knife.weapon = WeaponData.new()
	bag.equipped_item = knife  # the optimistic marker a queued draw leaves while equipped_weapon still reads FISTS
	assert_false(body._unarmed_hands_wanted(),
		"a bag weapon MID-DRAW (equipped_item set, combat hub still FISTS) must suppress the fists too")
	body.free()  # component first, host after — neither is in-tree, so the order is hygiene, not load-bearing
	p.free()
	ws.free()
	hub.free()
	arms.free()
	bag.free()

func test_a_stow_freezes_the_guard_pose() -> void:
	# Holstering the fists used to morph them into the flat carry reach WHILE they sank out of frame — the
	# latch flips to carry-mode at stow start, and the per-frame pose ease chased it on screen (the reported
	# "holding-items arm flash" on holster). A stow must FREEZE the pose (sink AS fists); the next draw's
	# hidden-reset re-poses from scratch, so nothing is lost.
	var src := FileAccess.get_file_as_string(FP_BODY_SOURCE)
	assert_true(src.contains("_fp_arm_stowing = true"),
		"the stow branch must raise the pose-freeze latch")
	assert_true(src.contains("and not _fp_arm_stowing"),
		"and the per-frame pose ease must skip while it is up, or the sinking fists morph into the carry reach")

func test_the_fists_wear_the_weapon_look() -> void:
	# The gun view model's dress pass (GunVisuals: rim light + black inverted-hull outline, shadows off) is
	# stamped onto the FP arms rig too, so bare fists read as first-class view-model gear beside an outlined
	# gun rather than raw skin.
	var src := FileAccess.get_file_as_string(FP_BODY_SOURCE)
	assert_true(src.contains("GunVisuals.new()"),
		"the arms rig must build a GunVisuals dress child — the same look pass as every weapon view model")
	var gv := FileAccess.get_file_as_string("res://scripts/effects/gun_visuals.gd")
	assert_true(gv.contains("mi.material_override = dup"),
		"the rim must chain onto a mesh's material_override when one exists — BodyModelSwap tints arms via override, and a customized arm colour would otherwise silently lose the rim")

func test_the_unarmed_hands_are_the_carry_hands() -> void:
	# The reuse IS the fix: a separate rig under the gun would lose the arm tint, sit off-centre and inherit
	# the holster tip. If someone re-introduces a second rig, this is the assertion that should stop them.
	var src := FileAccess.get_file_as_string(FP_BODY_SOURCE)
	assert_true(src.contains("_fp_arms.arm_strike_pitch") or src.contains("arms.arm_strike_pitch"),
		"the punch knobs must be stamped onto the SAME _fp_arms rig the carry hands use")

# --- Every OTHER weapon must be unaffected ----------------------------------------------------------

func test_real_weapons_still_mount_their_own_model() -> void:
	var dir := DirAccess.open(WEAPONS_DIR)
	assert_not_null(dir, "resources/weapons/ must exist")
	var checked := 0
	dir.list_dir_begin()
	var name := dir.get_next()
	while name != "":
		if not dir.current_is_dir() and name.ends_with(".tres"):
			var path := WEAPONS_DIR + name
			if path != FISTS_PATH:
				var wd := load(path) as WeaponData
				if wd != null:
					checked += 1
					assert_not_null(wd.view_model,
						"%s is a real weapon and must mount a view model — a null one now shows nothing at all" % name)
					assert_false(wd.view_model_is_first_person_only,
						"%s must NOT be first-person-only — it would vanish from NPC hands and the ground" % name)
					assert_false(wd.view_model_punch,
						"%s is not a punch — flagging it would kick the gun FORWARD instead of recoiling" % name)
					assert_eq(wd.held_view_model(), wd.view_model,
						"%s must hand out its normal view model to NPCs / drops / the grid" % name)
					wd = null
		name = dir.get_next()
	dir.list_dir_end()
	assert_gt(checked, 0, "the sweep must actually find the other weapon resources")
