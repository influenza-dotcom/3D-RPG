extends GutTest

## The project-audit panel (step 5) -- panel constructs (compile-check), and the pure scanners flag the silent
## breakage they're meant to. scan_disk.run() over the whole project is NOT exercised here (it loads resources);
## the text scanners + scan_scene over a built tree cover the logic.

const ScanScene := preload("res://addons/cybersunday_tools/panel_audit/scan_scene.gd")
const ScanDisk := preload("res://addons/cybersunday_tools/panel_audit/scan_disk.gd")
const AuditPanel := preload("res://addons/cybersunday_tools/panel_audit/audit_panel.gd")


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
	root.free()
