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
## Pure Resource + source reads (plus ONE off-tree player.gd instance, the test_player_core idiom — _ready never
## runs) — no scene instantiation, no audio device.

const FISTS_PATH := "res://resources/weapons/fists.tres"
const WEAPONS_DIR := "res://resources/weapons/"
const PLAYER_SOURCE := "res://scripts/player/player.gd"
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
	# wiring is pinned by source — the tests/test_npc_home_return.gd idiom.
	var src := FileAccess.get_file_as_string(PLAYER_SOURCE)
	assert_true(src.contains("func _unarmed_hands_wanted()"),
		"the Player decides when the bare fists are up in one place")
	assert_true(src.contains("_refresh_unarmed_hands"),
		"and refreshes them off holster / weapon-swap / carry changes")
	assert_true(src.contains("_fp_arms.strike("),
		"punching must drive the hands' own strike — without it the swing has no animation at all")
	assert_true(src.contains("weapon_system.attack.play_animation.connect(_on_attack_play_animation)"),
		"the punch must hang off Attack.play_animation, the one per-swing signal")

func test_the_fists_rest_closer_to_the_camera_than_the_carry_hold() -> void:
	# The GUARD geometry, pinned because it is counter-intuitive and was tuned by rendering it (the fists-frame
	# probe, 2026-08-05): the shoulders DROP while a STEEP rig tilt swings the arms up, so the fists rise into
	# the lower third FORESHORTENED — that foreshortening is what reads as "fists close". A shallow tilt with a
	# raised rest is the regression this replaces: fully extended arms reaching to a far point near screen
	# centre. Off-tree instance — _ready never runs; every helper here is pure math over exports + the latch.
	var p = load(PLAYER_SOURCE).new()
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

func test_the_fists_stay_down_while_a_real_weapon_is_mid_draw() -> void:
	# The bare-fist FLASH fix (the H toggle's put-back): between the carry release and the rewield landing, the
	# combat inventory still reads FISTS + unholstered — exactly the state that raises the fists — so
	# _unarmed_hands_wanted() must refuse while either suppressor is up: the player's _rewield_in_flight latch
	# (stash_held_item's synchronous release→equip span) or the BACKPACK's optimistic equipped_item (a
	# real-weapon draw QUEUED behind a mid-flight swap lands frames later). Off-tree: a bare Weapon hub +
	# BodyModelSwap wired by hand, _ready never runs (the test_player_core idiom).
	var p = load(PLAYER_SOURCE).new()
	var ws := Weapon.new()
	var hub := Inventory.new()
	ws.inventory = hub
	p.weapon_system = ws
	var arms := BodyModelSwap.new()
	p._fp_arms = arms
	hub.equipped_weapon = _fists()
	assert_true(p._unarmed_hands_wanted(),
		"baseline: FISTS equipped, unholstered, empty-handed — the fists are wanted")
	p._rewield_in_flight = true
	assert_false(p._unarmed_hands_wanted(),
		"the put-back's release→equip window must suppress the fists — this IS the flash fix")
	p._rewield_in_flight = false
	var bag := CharacterInventory.new()
	p.inventory = bag
	assert_true(p._unarmed_hands_wanted(),
		"an empty backpack equipped-marker changes nothing — genuine unarmed still raises the fists")
	var knife := Item.new()
	knife.category = Item.Category.WEAPON
	knife.weapon = WeaponData.new()
	bag.equipped_item = knife  # the optimistic marker a queued draw leaves while equipped_weapon still reads FISTS
	assert_false(p._unarmed_hands_wanted(),
		"a bag weapon MID-DRAW (equipped_item set, combat hub still FISTS) must suppress the fists too")
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
	var src := FileAccess.get_file_as_string(PLAYER_SOURCE)
	assert_true(src.contains("_fp_arm_stowing = true"),
		"the stow branch must raise the pose-freeze latch")
	assert_true(src.contains("and not _fp_arm_stowing"),
		"and the per-frame pose ease must skip while it is up, or the sinking fists morph into the carry reach")

func test_the_fists_wear_the_weapon_look() -> void:
	# The gun view model's dress pass (GunVisuals: rim light + black inverted-hull outline, shadows off) is
	# stamped onto the FP arms rig too, so bare fists read as first-class view-model gear beside an outlined
	# gun rather than raw skin.
	var src := FileAccess.get_file_as_string(PLAYER_SOURCE)
	assert_true(src.contains("GunVisuals.new()"),
		"the arms rig must build a GunVisuals dress child — the same look pass as every weapon view model")
	var gv := FileAccess.get_file_as_string("res://scripts/effects/gun_visuals.gd")
	assert_true(gv.contains("mi.material_override = dup"),
		"the rim must chain onto a mesh's material_override when one exists — BodyModelSwap tints arms via override, and a customized arm colour would otherwise silently lose the rim")

func test_the_unarmed_hands_are_the_carry_hands() -> void:
	# The reuse IS the fix: a separate rig under the gun would lose the arm tint, sit off-centre and inherit
	# the holster tip. If someone re-introduces a second rig, this is the assertion that should stop them.
	var src := FileAccess.get_file_as_string(PLAYER_SOURCE)
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
