extends GutTest

## VALIDATION INSPECTORS batch (weapon / GOAP profile / perk cards): the PURE compute behind them lives in
## InspectorCalc statics — TTK/DPS/burst + the amber warnings, the GOAP resolved priority/cost table + stale-row
## warnings, and the Perk bad-key + dangling-prereq checks. Those statics are scene-tree-free and unit-tested here.
## EditorInspectorPlugin / EditorInterface can't be instantiated headless, so the cards themselves (_can_handle +
## the injected Controls) are editor-only and user-verified, not tested here. The preloads also compile-check the
## whole inspector scripts.

const Calc := preload("res://addons/cybersunday_tools/inspectors/inspector_calc.gd")
const WeaponInspector := preload("res://addons/cybersunday_tools/inspectors/weapondata_inspector.gd")
const GoapInspector := preload("res://addons/cybersunday_tools/inspectors/goapprofile_inspector.gd")
const PerkInspector := preload("res://addons/cybersunday_tools/inspectors/perk_inspector.gd")
const GoapLibrary := preload("res://scripts/npc/goap/goap_library.gd")


# ── WeaponData: DPS / burst / STK / TTK ────────────────────────────────────────────────────────────────────

func test_weapon_burst_multiplies_damage_by_pellets() -> void:
	var wd := WeaponData.new()
	wd.damage = 2.0
	wd.pellet_count = 5
	assert_eq(Calc.burst_damage(wd, 1.0), 10.0, "burst = damage 2 × 5 pellets = 10 at body multiplier")
	assert_eq(Calc.burst_damage(wd, 2.0), 20.0, "burst scales with the multiplier stack (×2 = 20)")
	wd = null


func test_weapon_shots_to_kill_ceils_against_hp() -> void:
	var wd := WeaponData.new()
	wd.damage = 3.0
	wd.pellet_count = 1
	# 3 dmg vs 4 HP player = ceil(4/3) = 2 shots; vs 10 HP NPC = ceil(10/3) = 4 shots.
	assert_eq(Calc.shots_to_kill(wd, Calc.PLAYER_HP, 1.0), 2, "ceil(4/3) = 2 body shots to drop the player")
	assert_eq(Calc.shots_to_kill(wd, Calc.NPC_HP, 1.0), 4, "ceil(10/3) = 4 body shots to drop a 10 HP NPC")
	wd = null


func test_weapon_zero_damage_never_kills() -> void:
	var wd := WeaponData.new()
	wd.damage = 0.0
	assert_eq(Calc.shots_to_kill(wd, Calc.PLAYER_HP, 1.0), 9999, "a 0-damage weapon reads as 'never' (sentinel 9999)")
	assert_eq(Calc.time_to_kill(wd, Calc.PLAYER_HP, 1.0), -1.0, "a 0-damage weapon has no time-to-kill (-1.0)")
	wd = null


func test_weapon_time_to_kill_counts_intervals_between_shots() -> void:
	var wd := WeaponData.new()
	wd.damage = 1.0
	wd.attack_speed = 0.1
	wd.attack_windup = 0.0
	# 1 dmg vs 4 HP = 4 shots; TTK = (4-1) intervals × 0.1 = 0.3s (first shot at t=0).
	assert_almost_eq(Calc.time_to_kill(wd, Calc.PLAYER_HP, 1.0), 0.3, 0.0001, "TTK = (shots-1) × interval = 3 × 0.1 = 0.3s")
	wd = null


func test_weapon_dps_is_burst_over_interval() -> void:
	var wd := WeaponData.new()
	wd.damage = 2.0
	wd.pellet_count = 1
	wd.attack_speed = 0.5
	wd.attack_windup = 0.0
	# burst 2.0 over a 0.5s interval = 4.0 DPS.
	assert_almost_eq(Calc.dps(wd), 4.0, 0.0001, "DPS = burst 2.0 / interval 0.5s = 4.0")
	wd = null


func test_weapon_stealth_headshot_stacks_both_multipliers() -> void:
	var wd := WeaponData.new()
	wd.headshot_multiplier = 2.0
	wd.sneak_attack_multiplier = 3.0
	assert_eq(Calc.mult_for(wd, "stealth_headshot"), 6.0, "stealth-headshot stacks headshot ×2 and sneak ×3 = ×6")
	assert_eq(Calc.mult_for(wd, "headshot"), 2.0, "headshot multiplier resolves on its own")
	assert_eq(Calc.mult_for(wd, "body"), 1.0, "a body shot is ×1.0")
	wd = null


func test_weapon_lines_are_nonempty_and_mention_hp_anchors() -> void:
	var wd := WeaponData.new()
	wd.damage = 1.0
	var lines := Calc.weapon_lines(wd)
	assert_gte(lines.size(), 6, "the readout has the DPS line, 4 multiplier lines, the clip line + recoil line")
	assert_true(lines[0].contains("DPS"), "the first line is the DPS/burst summary")


# ── WeaponData: amber warnings ─────────────────────────────────────────────────────────────────────────────

func test_weapon_warns_melee_carrying_an_inert_stamina_cost_mult() -> void:
	# stamina_cost_mult only prices RANGED fire — Attack._shot_stamina_cost() returns 0 for a melee weapon, which
	# pays stamina_melee_attack_cost instead. A knife authored with a multiplier is therefore the exact
	# "half-configured knob that silently no-ops" class this warning list exists for.
	var wd := WeaponData.new()
	wd.is_melee = true
	wd.stamina_cost_mult = 2.5
	var w := Calc.weapon_warnings(wd, PackedStringArray())
	assert_true(_any_contains(w, "stamina_cost_mult"), "a melee weapon carrying a non-default stamina_cost_mult is warned as inert")
	wd.stamina_cost_mult = 1.0
	assert_false(_any_contains(Calc.weapon_warnings(wd, PackedStringArray()), "stamina_cost_mult"),
		"a melee weapon left at the 1.0 default must NOT warn — the default is not a half-configured knob")
	wd = null


func test_weapon_warns_shotgun_without_spread() -> void:
	var wd := WeaponData.new()
	wd.pellet_count = 6
	wd.pellet_spread = 0.0
	var w := Calc.weapon_warnings(wd, PackedStringArray())
	assert_true(_any_contains(w, "pellet_spread"), "pellet_count>1 with spread 0 is warned (every pellet lands on one point)")
	wd = null


func test_weapon_warns_recoil_that_never_recovers() -> void:
	var wd := WeaponData.new()
	wd.recoil_kick_deg = 1.5
	wd.recoil_recovery = 0.0
	assert_true(_any_contains(Calc.weapon_warnings(wd, PackedStringArray()), "recoil_recovery"), "recoil kick with 0 recovery is warned")
	wd = null


func test_weapon_warns_bloom_capped_at_zero() -> void:
	var wd := WeaponData.new()
	wd.bloom_per_shot_deg = 0.5
	wd.bloom_max_deg = 0.0
	assert_true(_any_contains(Calc.weapon_warnings(wd, PackedStringArray()), "bloom_max_deg"), "bloom per shot with 0 max is warned (inert)")
	wd = null


# (removed test_weapon_warns_explosion_without_projectile — explosion_radius defaults to 4.0 on every weapon, so
# "explosion_radius set but no projectile_scene" was a false positive on all hitscan guns; the warning was dropped.)


func test_weapon_warns_caliber_with_no_ammo_on_disk() -> void:
	var wd := WeaponData.new()
	wd.caliber = &"made_up_caliber"
	var known := PackedStringArray(["9mm", "rifle"])
	assert_true(_any_contains(Calc.weapon_warnings(wd, known), "could never reload"), "a caliber absent from the disk list is warned")
	# A caliber that IS on the list produces no caliber warning.
	wd.caliber = &"9mm"
	assert_false(_any_contains(Calc.weapon_warnings(wd, known), "could never reload"), "a known caliber is not warned")
	wd = null


func test_weapon_warns_infinite_ammo_with_caliber() -> void:
	var wd := WeaponData.new()
	wd.is_infinite_ammo = true
	wd.caliber = &"9mm"
	assert_true(_any_contains(Calc.weapon_warnings(wd, PackedStringArray(["9mm"])), "is_infinite_ammo"), "infinite ammo + a caliber is warned (caliber ignored)")
	wd = null


func test_weapon_clean_config_has_no_warnings() -> void:
	var wd := WeaponData.new()
	wd.damage = 1.0
	wd.pellet_count = 1
	wd.caliber = &""
	assert_eq(Calc.weapon_warnings(wd, PackedStringArray()).size(), 0, "a default single-pellet no-caliber weapon warns nothing")
	wd = null


# ── Editable-card pickers: folder scan + label (pure helpers behind the NpcData weapon_data dropdown) ────────

func test_picker_label_strips_folder_and_extension() -> void:
	assert_eq(Calc.picker_label_for("res://resources/weapons/pistol.tres"), "pistol", "a .tres path reads as its filename stem")
	assert_eq(Calc.picker_label_for("res://resources/weapons/sniper_wep.res"), "sniper_wep", ".res is stripped just like .tres")
	assert_eq(Calc.picker_label_for(""), "(none)", "an empty path is the '(none)' sentinel label")


func test_resource_paths_in_missing_folder_is_empty() -> void:
	var paths := Calc.resource_paths_in("res://resources/__does_not_exist__/")
	assert_eq(paths.size(), 0, "a missing folder yields an empty path list (no crash)")


func test_resource_paths_in_scans_weapons_folder_sorted() -> void:
	# resources/weapons/ ships several WeaponData .tres — the scan returns full res:// paths, sorted, .tres/.res only.
	var paths := Calc.resource_paths_in("res://resources/weapons/")
	assert_gte(paths.size(), 1, "the weapons folder scan finds at least one resource")
	for p in paths:
		assert_true(p.begins_with("res://resources/weapons/"), "each scanned entry is a full res:// path under the folder: %s" % p)
		assert_true(p.ends_with(".tres") or p.ends_with(".res"), "only .tres/.res resources are listed (no .flac/.avif): %s" % p)
	var sorted_copy := paths.duplicate()
	sorted_copy.sort()
	assert_eq(Array(paths), Array(sorted_copy), "the scan returns its paths sorted")


# ── GoapProfile: resolved table + stale-row warnings ───────────────────────────────────────────────────────

func test_goap_priority_table_resolves_override_and_fallback() -> void:
	var gp := GoapProfile.new()
	var row := GoapGoalPriority.new()
	row.goal = "Survive"
	row.priority = 9.0
	var rows: Array[GoapGoalPriority] = [row]
	gp.goal_priorities = rows
	var lines := Calc.goap_priority_lines(gp, GoapLibrary.goal_names())
	assert_eq(lines.size(), GoapLibrary.goal_names().size(), "one priority line per registered goal")
	assert_true(_any_contains(lines, "Survive] = 9.00"), "the Survive override (9.0) resolves into the table")
	assert_true(_any_contains(lines, "Idle] = 0.00"), "an un-overridden goal reads the 0.0 fallback")
	gp = null


func test_goap_cost_table_resolves_override_and_fallback() -> void:
	var gp := GoapProfile.new()
	var row := GoapActionCost.new()
	row.action = "Flee"
	row.cost = 0.2
	var rows: Array[GoapActionCost] = [row]
	gp.action_cost_overrides = rows
	var lines := Calc.goap_cost_lines(gp, GoapLibrary.action_names())
	assert_eq(lines.size(), GoapLibrary.action_names().size(), "one cost line per registered action")
	assert_true(_any_contains(lines, "Flee] = 0.20"), "the Flee cost override (0.2) resolves into the table")
	assert_true(_any_contains(lines, "Hold] = 1.00"), "an un-overridden action reads the 1.0 fallback")
	gp = null


func test_goap_validate_flags_stale_override_rows() -> void:
	var gp := GoapProfile.new()
	var bad := GoapGoalPriority.new()
	bad.goal = "Frobnicate"  # not a registered goal
	var rows: Array[GoapGoalPriority] = [bad]
	gp.goal_priorities = rows
	# validate() returns false (and push_warns) when a row names no known goal.
	assert_false(gp.validate(GoapLibrary.goal_names(), GoapLibrary.action_names()), "a stale goal override makes validate() fail")
	gp = null


func test_goap_validate_passes_clean_profile() -> void:
	var gp := GoapProfile.new()
	var good := GoapActionCost.new()
	good.action = "Hold"
	var rows: Array[GoapActionCost] = [good]
	gp.action_cost_overrides = rows
	assert_true(gp.validate(GoapLibrary.goal_names(), GoapLibrary.action_names()), "a profile whose override rows are all known passes validate()")
	gp = null


# ── Perk: bad-key + dangling-prereq warnings ───────────────────────────────────────────────────────────────

func test_perk_warns_unknown_stat_bonus_key() -> void:
	var perk := Perk.new()
	perk.stat_bonuses = {"strength": 2, "luck": 3}  # luck is not a CharacterStats attribute
	var w := Calc.perk_warnings(perk, CharacterStats.stat_names(), PackedStringArray(), false)
	assert_true(_any_contains(w, "'luck'"), "a stat_bonuses key that isn't a real stat is warned")
	assert_false(_any_contains(w, "'strength'"), "a real stat key ('strength') is not warned")
	perk = null


func test_perk_warns_combat_bonus_key_outside_damage_crit() -> void:
	var perk := Perk.new()
	perk.combat_bonuses = {"damage": 0.1, "splash": 0.5}  # splash is outside {damage, crit}
	var w := Calc.perk_warnings(perk, CharacterStats.stat_names(), PackedStringArray(), false)
	assert_true(_any_contains(w, "'splash'"), "a combat_bonuses key outside {damage, crit} is warned")
	assert_false(_any_contains(w, "'damage'"), "the 'damage' combat key is allowed (not warned)")
	perk = null


func test_perk_warns_dangling_prereq_when_folder_present() -> void:
	var perk := Perk.new()
	var reqs: Array[StringName] = [&"ghost_perk"]
	perk.requires_perks = reqs
	# folder present, but ghost_perk is not among the known ids -> dangling.
	var w := Calc.perk_warnings(perk, CharacterStats.stat_names(), PackedStringArray(["other_perk"]), true)
	assert_true(_any_contains(w, "ghost_perk"), "a requires_perks id naming no Perk on disk is warned when the folder exists")
	perk = null


func test_perk_skips_prereq_check_when_folder_absent() -> void:
	var perk := Perk.new()
	var reqs: Array[StringName] = [&"ghost_perk"]
	perk.requires_perks = reqs
	# folder ABSENT (perks_folder_present=false) -> prereq check is skipped, so no dangling warning.
	var w := Calc.perk_warnings(perk, CharacterStats.stat_names(), PackedStringArray(), false)
	assert_false(_any_contains(w, "ghost_perk"), "with resources/perks/ absent the prereq check degrades gracefully (no warning)")
	perk = null


func test_perk_clean_config_has_no_warnings() -> void:
	var perk := Perk.new()
	perk.stat_bonuses = {"strength": 1}
	perk.combat_bonuses = {"crit": 0.25}
	var reqs: Array[StringName] = [&"base_perk"]
	perk.requires_perks = reqs
	var w := Calc.perk_warnings(perk, CharacterStats.stat_names(), PackedStringArray(["base_perk"]), true)
	assert_eq(w.size(), 0, "real stat + real combat key + an existing prereq warns nothing")
	perk = null


# ── helper ─────────────────────────────────────────────────────────────────────────────────────────────────

func _any_contains(lines: PackedStringArray, needle: String) -> bool:
	for l in lines:
		if l.find(needle) != -1:
			return true
	return false
