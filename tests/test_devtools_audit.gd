extends GutTest

## The project-audit panel (step 5) -- panel constructs (compile-check), and the pure scanners flag the silent
## breakage they're meant to. scan_disk.run() over the whole project is NOT exercised here (it loads resources);
## the text scanners + scan_scene over a built tree cover the logic.

const ScanScene := preload("res://addons/cybersunday_tools/panel_audit/scan_scene.gd")
const ScanDisk := preload("res://addons/cybersunday_tools/panel_audit/scan_disk.gd")
const AuditPanel := preload("res://addons/cybersunday_tools/panel_audit/audit_panel.gd")
const FixOps := preload("res://addons/cybersunday_tools/panel_audit/fix_ops.gd")
const CustomRules := preload("res://addons/cybersunday_tools/panel_audit/custom_rules.gd")
const AuditRule := preload("res://addons/cybersunday_tools/panel_audit/audit_rule.gd")


func _count(findings: Array, severity: String) -> int:
	var c := 0
	for f in findings:
		if f["severity"] == severity:
			c += 1
	return c


func test_audit_panel_constructs() -> void:
	var p = AuditPanel.new()
	assert_not_null(p, "audit panel should construct (compiles + _init builds UI off-tree)")
	assert_eq(p.name, "Audit")
	p.free()


## The auto-rescan debounce helper collapses a burst of triggers into ONE pending fire. We drive the pure
## static debounce_restart() with our own one-shot Timer (no EditorInterface) and assert that after N rapid
## restarts there is still exactly one timer counting down (not N independent scans).
func test_debounce_restart_coalesces_rapid_requests() -> void:
	var t := Timer.new()
	t.one_shot = true
	t.wait_time = 0.75
	add_child_autofree(t)  # a Timer must be in-tree to actually run
	# Simulate a burst of editor signals (saves/reimports) hitting the trigger back-to-back.
	for i in 5:
		AuditPanel.debounce_restart(t)
	# One restart leaves the (single) timer armed and counting; the burst did NOT spawn 5 timers/scans.
	assert_false(t.is_stopped(), "after a burst of restarts the single debounce timer is still counting toward ONE fire")
	assert_gt(t.time_left, 0.0, "the timer is mid-countdown (the burst coalesced into one pending fire)")
	# A null timer is a tolerated no-op (the panel may not have built its timer yet).
	AuditPanel.debounce_restart(null)
	assert_true(true, "debounce_restart(null) is a safe no-op")


func test_scan_gd_flags_dead_player_and_unregistered_but_allows_registered() -> void:
	var allowed := {StringName("Player"): true, StringName("npc"): true}
	var text := "func x():\n\tget_first_node_in_group(\"player\")\n\tis_in_group(\"bogusgrp\")\n\tadd_to_group(\"Player\")\n"
	var found := ScanDisk.scan_gd_text(text, "res://x.gd", allowed)
	assert_eq(_count(found, "ERROR"), 1, "lowercase \"player\" is the dead-group ERROR")
	assert_eq(_count(found, "WARN"), 1, "\"bogusgrp\" is an unregistered WARN; \"Player\" is allowed (no finding)")


func test_scan_ref_flags_missing_ext_resource() -> void:
	var text := "[ext_resource type=\"Script\" path=\"res://does/not/exist_zzz_qq.gd\" id=\"1\"]"
	var found := ScanDisk.scan_ref_text(text, "res://x.tscn")
	assert_eq(found.size(), 1, "the missing path is one finding")
	assert_eq(found[0]["severity"], "ERROR")


func test_scan_ref_passes_a_real_ext_resource() -> void:
	var text := "[ext_resource type=\"Script\" path=\"res://scripts/world/groups.gd\" id=\"1\"]"
	var found := ScanDisk.scan_ref_text(text, "res://x.tscn")
	assert_eq(found.size(), 0, "an existing path produces no finding")


func test_scan_scene_flags_unbaked_navmesh_and_duplicate_spawn() -> void:
	var root := Node3D.new()
	var region := NavigationRegion3D.new()  # no navigation_mesh -> unbaked ERROR
	root.add_child(region)
	var s1 := PlayerSpawn.new()
	s1.entry_id = &"door_a"
	var s2 := PlayerSpawn.new()
	s2.entry_id = &"door_a"  # duplicate -> WARN
	root.add_child(s1)
	root.add_child(s2)
	var found := ScanScene.run(root)
	assert_gte(_count(found, "ERROR"), 1, "the unbaked region is an ERROR")
	assert_gte(_count(found, "WARN"), 1, "the duplicate entry_id is a WARN")
	for f in found:
		assert_true(f.get("node") is Node, "each scene finding carries the offending node ref (for click-to-jump)")
	root.free()


# --- batch auto-fix engine (FixOps) -----------------------------------------------------------------------------

func test_dead_player_finding_is_tagged_fixable() -> void:
	# The audit batch-fix relies on scan_disk tagging the unambiguous dead-"player" ERROR with a fix descriptor.
	var allowed := {StringName("Player"): true}
	var found := ScanDisk.scan_gd_text("func x():\n\tadd_to_group(\"player\")\n", "res://x.gd", allowed)
	assert_eq(found.size(), 1, "one dead-player finding")
	assert_true(found[0].get("fix") is Dictionary, "the dead-player ERROR carries a fix descriptor")
	assert_eq(found[0]["fix"]["kind"], "player_group", "tagged as a player_group fix")
	# An unregistered typo is flagged but NOT auto-fixable (no single right answer).
	var typo := ScanDisk.scan_gd_text("func x():\n\tis_in_group(\"bogusgrp\")\n", "res://x.gd", allowed)
	assert_false(typo[0].get("fix") is Dictionary, "an unregistered-group typo is NOT tagged fixable")


func test_rewrite_player_group_replaces_only_group_calls() -> void:
	var text := "func x():\n\tadd_to_group(\"player\")\n\tget_first_node_in_group(&\"player\")\n\tvar d = {\"player\": 1}\n\tadd_to_group(Groups.PLAYER)\n"
	var res := FixOps.rewrite_player_group_text(text)
	assert_eq(int(res["count"]), 2, "both group-call literals (plain + &-sigil) are rewritten")
	var out := String(res["text"])
	assert_false("add_to_group(\"player\")" in out, "the plain group-call literal is gone")
	assert_false("&\"player\"" in out, "the &-sigil group-call literal is gone")
	assert_true("{\"player\": 1}" in out, "a non-group-call \"player\" (dict key) is left untouched")
	assert_eq(out.count("Groups.PLAYER"), 3, "two rewrites + the one that was already Groups.PLAYER")


func test_rewrite_player_group_noop_when_clean() -> void:
	var text := "func x():\n\tadd_to_group(Groups.PLAYER)\n"
	var res := FixOps.rewrite_player_group_text(text)
	assert_eq(int(res["count"]), 0, "nothing to rewrite")
	assert_eq(String(res["text"]), text, "clean text is returned unchanged")


func test_clamp_loot_entries_raises_max_to_min_only_when_inverted() -> void:
	var table := LootTable.new()
	var bad := LootEntry.new()
	bad.min_count = 3
	bad.max_count = 1  # inverted
	var ok := LootEntry.new()
	ok.min_count = 1
	ok.max_count = 2  # valid
	table.entries = [bad, ok]
	var fixed := FixOps.clamp_loot_entries(table)
	assert_eq(fixed, 1, "only the inverted entry is fixed")
	assert_eq(bad.max_count, 3, "max is raised up to min (matches roll()'s maxi clamp)")
	assert_eq(ok.max_count, 2, "the valid entry is untouched")
	table = null
	bad = null
	ok = null


func test_build_plan_dedupes_by_source_and_kind() -> void:
	var findings := [
		{"severity": "ERROR", "source": "res://a.gd", "fix": {"kind": "player_group", "source": "res://a.gd"}},
		{"severity": "ERROR", "source": "res://a.gd", "fix": {"kind": "player_group", "source": "res://a.gd"}},  # same file, second literal
		{"severity": "WARN", "source": "res://b.tres", "fix": {"kind": "loot_clamp", "source": "res://b.tres"}},
		{"severity": "WARN", "source": "res://c.tres", "message": "no fix here"},  # unfixable -> excluded
	]
	var plan := FixOps.build_plan(findings)
	assert_eq(plan.size(), 2, "two files' worth of work: a.gd collapses to ONE rewrite, b.tres is one clamp, c is excluded")
	var kinds := []
	for row in plan:
		kinds.append(row["kind"])
		assert_true(String(row["label"]) != "", "each plan row has a human label for the preview dialog")
	assert_true("player_group" in kinds and "loot_clamp" in kinds, "both fix kinds present, deduped")


func test_build_plan_ignores_unknown_fix_kind() -> void:
	# A custom audit rule could tag a finding with a fix kind apply_plan can't execute — it must NOT enter the plan.
	var findings := [{"severity": "WARN", "source": "res://x.tres", "fix": {"kind": "frobnicate", "source": "res://x.tres"}}]
	assert_eq(FixOps.build_plan(findings).size(), 0, "an unrecognized fix kind is treated as flagged-only")


# --- custom audit rule framework (CustomRules / CyberAuditRule) -------------------------------------------------

func _rule_script(body: String) -> GDScript:
	# Build a rule Script at runtime so the test needs no real file in res://audit_rules/ (which would run on every scan).
	var s := GDScript.new()
	s.source_code = "extends RefCounted\n" + body
	s.reload()
	return s


func test_custom_rules_merge_good_rules_and_skip_malformed() -> void:
	var good := _rule_script("func run_audit(_root):\n\treturn [{\"severity\": \"WARN\", \"source\": \"res://x\", \"message\": \"custom\"}]\n")
	var no_method := _rule_script("func other():\n\tpass\n")
	var bad_return := _rule_script("func run_audit(_root):\n\treturn 42\n")
	var out := CustomRules.run_rules([good, no_method, bad_return, null], null)
	assert_eq(out.size(), 1, "only the well-formed rule contributes — missing run_audit / non-Array / null are skipped")
	assert_eq(out[0]["message"], "custom", "the good rule's finding flows through unchanged")


func test_custom_rule_finding_helper_shape() -> void:
	var f := AuditRule.finding("ERROR", "res://a.tscn", "broke")
	assert_eq(f["severity"], "ERROR")
	assert_false(f.has("node"), "no node key when none is passed")
	var n := Node.new()
	var f2 := AuditRule.finding("WARN", "res://a.tscn", "look here", n)
	assert_eq(f2["node"], n, "the node is carried for click-to-jump")
	n.free()
