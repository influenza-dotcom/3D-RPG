extends GutTest

## The project-audit panel (step 5) -- panel constructs (compile-check), and the pure scanners flag the silent
## breakage they're meant to. scan_disk.run() over the whole project is NOT exercised here (it loads resources);
## the text scanners + scan_scene over a built tree cover the logic. Also pins: the `domain` tag every scanner stamps
## (the panel's Show filter keys on it), the panel's pure row / filter / summary helpers, the content check over a
## TEMPORARY item list, the plain-words Fix labels, and the two file fixers against temp copies under user:// --
## each must leave a .bak of the prior bytes beside the rewritten file (the Fix dialog promises it).

const ScanScene := preload("res://addons/cybersunday_tools/panel_audit/scan_scene.gd")
const ScanDisk := preload("res://addons/cybersunday_tools/panel_audit/scan_disk.gd")
const ScanWiring := preload("res://addons/cybersunday_tools/panel_audit/scan_wiring.gd")
const ScanText := preload("res://addons/cybersunday_tools/panel_audit/scan_text.gd")
const ScanMenuSound := preload("res://addons/cybersunday_tools/panel_audit/scan_menu_sound.gd")
const ScanContent := preload("res://addons/cybersunday_tools/panel_audit/scan_content.gd")
const AuditPanel := preload("res://addons/cybersunday_tools/panel_audit/audit_panel.gd")
const FixOps := preload("res://addons/cybersunday_tools/panel_audit/fix_ops.gd")
const CustomRules := preload("res://addons/cybersunday_tools/panel_audit/custom_rules.gd")
const AuditRule := preload("res://addons/cybersunday_tools/panel_audit/audit_rule.gd")

## Temp files for the fixer tests -- user://, never project content. Removed after each test (and their .bak twins).
const TMP_GD := "user://test_devtools_audit_fix.gd"
const TMP_LOOT := "user://test_devtools_audit_fix_loot.tres"


func after_each() -> void:
	for p in [TMP_GD, TMP_GD + ".bak", TMP_LOOT, TMP_LOOT + ".bak"]:
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(p)


func _count(findings: Array, severity: String) -> int:
	var c := 0
	for f in findings:
		if f["severity"] == severity:
			c += 1
	return c


func _first_with_fix_kind(findings: Array, kind: String) -> Dictionary:
	for f in findings:
		if f.get("fix") is Dictionary and f["fix"].get("kind") == kind:
			return f
	return {}


func _domains(findings: Array) -> Array:
	var out: Array = []
	for f in findings:
		out.append(String(f.get("domain", "<missing>")))
	return out


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


func test_scan_gd_flags_dead_player_unregistered_and_registered_literal() -> void:
	# Three distinct classes: lowercase "player" -> dead-group ERROR; "bogusgrp" -> unregistered WARN; "Player" is a
	# REGISTERED name but still a RAW LITERAL -> a group_literal WARN recommending Groups.PLAYER. That last case is the
	# "non-const group use" this audit now catches (registered literals used to pass silently).
	var allowed := {StringName("Player"): true, StringName("npc"): true}
	var const_names := {StringName("Player"): "PLAYER", StringName("npc"): "NPC"}
	var text := "func x():\n\tget_first_node_in_group(\"player\")\n\tis_in_group(\"bogusgrp\")\n\tadd_to_group(\"Player\")\n"
	var found := ScanDisk.scan_gd_text(text, "res://x.gd", allowed, const_names)
	assert_eq(_count(found, "ERROR"), 1, "lowercase \"player\" is the dead-group ERROR")
	assert_eq(_count(found, "WARN"), 2, "\"bogusgrp\" (unregistered) + \"Player\" (registered-but-literal) = two WARNs")
	var reg := _first_with_fix_kind(found, "group_literal")
	assert_false(reg.is_empty(), "the registered literal carries a group_literal fix descriptor")
	assert_true(String(reg["message"]).contains("Groups.PLAYER"), "the WARN names the exact Groups const to use")


func test_scan_gd_ignores_group_literal_inside_a_comment() -> void:
	# The project documents call idioms in prose (## ... get_nodes_in_group(&"npc")); a literal quoted inside a `#`
	# comment is not a real usage and must never be flagged. The SAME call in code IS flagged.
	var allowed := {StringName("npc"): true}
	var const_names := {StringName("npc"): "NPC"}
	var commented := ScanDisk.scan_gd_text("func x():\n\t# see get_nodes_in_group(&\"npc\")\n\tpass\n", "res://x.gd", allowed, const_names)
	assert_eq(commented.size(), 0, "a group literal inside a comment is not a usage — no finding")
	var code := ScanDisk.scan_gd_text("func x():\n\tget_nodes_in_group(&\"npc\")\n", "res://x.gd", allowed, const_names)
	assert_eq(code.size(), 1, "the same call in real code is one group_literal finding")
	assert_eq(code[0]["fix"]["kind"], "group_literal", "and it's tagged for the batch-fixer")


func test_scan_ref_flags_missing_ext_resource() -> void:
	var text := "[ext_resource type=\"Script\" path=\"res://does/not/exist_zzz_qq.gd\" id=\"1\"]"
	var found := ScanDisk.scan_ref_text(text, "res://x.tscn")
	assert_eq(found.size(), 1, "the missing path is one finding")
	assert_eq(found[0]["severity"], "ERROR")
	assert_true(String(found[0]["message"]).begins_with("Missing file: does/not/exist_zzz_qq.gd -- "),
		"the row leads with 'Missing file: <folders/name>' in designer words -- no res:// prefix, no ext_resource / <null> jargon")
	assert_false(String(found[0]["message"]).contains("res://"), "and it never prints the engine path prefix into a row the designer reads")


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


# --- domain tags (the panel's Show filter keys on them; one case per scanner) ----------------------------------------

func test_scan_disk_rows_are_code_for_scripts_and_content_for_resources() -> void:
	var allowed := {StringName("Player"): true}
	var gd := ScanDisk.scan_gd_text("func x():\n\tadd_to_group(\"player\")\n\tis_in_group(\"bogusgrp\")\n", "res://x.gd", allowed)
	assert_eq(gd.size(), 2, "two group-literal rows to tag")
	for f in gd:
		assert_eq(String(f["domain"]), "code", "a .gd group-literal row is a programmer's tidy-up: domain code -- %s" % [f["message"]])
	var ref := ScanDisk.scan_ref_text("[ext_resource type=\"Script\" path=\"res://nope_zzz.gd\" id=\"1\"]", "res://x.tscn")
	assert_eq(ref.size(), 1, "one missing-file row to tag")
	assert_eq(String(ref[0]["domain"]), "content", "a missing-file row is fixed in a resource field: domain content")


func test_scan_scene_rows_are_domain_scene() -> void:
	var root := Node3D.new()
	root.add_child(NavigationRegion3D.new())  # unbaked -> one ERROR row
	var found := ScanScene.run(root)
	assert_gte(found.size(), 1, "the unbaked region yields a row to tag")
	for f in found:
		assert_eq(String(f["domain"]), "scene", "every scene-walk row is domain scene")
	root.free()


func test_scan_wiring_rows_are_domain_content() -> void:
	var found := ScanWiring.flag_findings({}, {"vault_open": true})  # read, never written -> a dead-gate WARN
	assert_eq(found.size(), 1, "one dead-gate row to tag")
	assert_eq(String(found[0]["domain"]), "content", "a wiring row is fixed in a .tres / .tscn field: domain content")
	assert_eq(String(found[0]["severity"]), "WARN", "the dead-gate severity string is unchanged (validate_all / cyber_cmds print it)")


func test_scan_text_row_is_domain_code() -> void:
	var offenders := ScanText.scan_gd_text("func _ready():\n\tlabel.text = \"Hello\"\n", "res://synthetic.gd")
	assert_eq(offenders.size(), 1, "one paint-site literal to convert")
	assert_false(offenders[0].has("domain"), "the OFFENDER dict (what the ratchet + text_debt.gd read) keeps its shape -- no domain key")
	var row := ScanText.to_finding(offenders[0])
	assert_eq(String(row["severity"]), "WARN", "a text-debt row stays a WARN")
	assert_eq(String(row["source"]), "res://synthetic.gd", "the row carries the offender's source")
	assert_eq(String(row["domain"]), "code", "moving a literal into PlayerText is a programmer's job: domain code")
	assert_true(String(row["message"]).contains("line 2"), "the message still names the line")


func test_scan_menu_sound_row_is_domain_code() -> void:
	var offenders := ScanMenuSound.scan_gd_text("func _buy() -> void:\n\tif merchant.buy(item):\n\t\tMenuStyle.play_commit()\n", "res://synthetic.gd")
	assert_eq(offenders.size(), 1, "one silent-refusal site to convert")
	assert_false(offenders[0].has("domain"), "the OFFENDER dict (what the coverage ratchet reads) keeps its shape -- no domain key")
	var row := ScanMenuSound.to_finding(offenders[0])
	assert_eq(String(row["severity"]), "WARN", "a menu-sound row stays a WARN")
	assert_eq(String(row["domain"]), "code", "pairing a cue is a programmer's edit: domain code")
	assert_true(String(row["message"]).contains("_buy"), "the message still names the function")


func test_custom_rule_finding_defaults_to_domain_custom() -> void:
	var f := AuditRule.finding("WARN", "res://a.tscn", "look here")
	assert_eq(String(f["domain"]), "custom", "the helper stamps domain custom when the rule passes none")
	var coded := AuditRule.finding("WARN", "res://a.gd", "programmer thing", null, "code")
	assert_eq(String(coded["domain"]), "code", "a rule can opt its row into the code domain (hidden by default)")


# --- the content check (scan_content) over a TEMPORARY item list -----------------------------------------------------

func test_scan_content_converts_validator_problems_over_a_temporary_item_list() -> void:
	# Two in-memory items sharing an id: ContentValidator.check_items reports the duplicate; scan_content must hand it
	# back as a content WARN row with the validator's own sentence. (run(items) also walks resources/ for the faction /
	# Perk / GoapProfile checks, so the assertions tolerate other rows -- they look for THIS one.)
	var a := Item.new()
	a.id = &"zz_test_dupe"
	a.display_name = "Dupe A"
	var b := Item.new()
	b.id = &"zz_test_dupe"
	b.display_name = "Dupe B"
	var found := ScanContent.findings_for([a, b])
	var dupe: Dictionary = {}
	for f in found:
		assert_eq(String(f["severity"]), "WARN", "every content-check row uses the panel's WARN severity string")
		assert_eq(String(f["domain"]), "content", "every content-check row is domain content (always in the default view)")
		if String(f["message"]).contains("zz_test_dupe"):
			dupe = f
	assert_false(dupe.is_empty(), "the duplicate-id problem became a finding: %s" % [_domains(found)])
	if not dupe.is_empty():
		assert_true(String(dupe["message"]).begins_with("Duplicate item id"), "the message is the validator's own sentence, unchanged")
		assert_eq(String(dupe["source"]), "content", "an in-memory item has no file, so the source falls back to the bare content marker")
	a = null
	b = null


func test_scan_content_source_and_skipped_row_shapes() -> void:
	# A sentence that names a res:// path sources the row at that file (double-click opens it).
	var perk := ScanContent.finding_from_problem("Perk 'tough' (res://resources/perks/tough.tres) has stat_bonuses keys that aren't CharacterStats attributes.")
	assert_eq(String(perk["source"]), "res://resources/perks/tough.tres", "a path written in the sentence becomes the row's source")
	assert_false(String(perk["message"]).contains("res://"), "but the ROW text drops the engine prefix -- the whole path lives in the row's tooltip")
	assert_true(String(perk["message"]).contains("resources/perks/tough.tres"), "the folders stay, so two same-named perks stay tellable apart")
	# A sentence that quotes an item's id resolves to that item's file when the scanned item carries a path.
	var it := Item.new()
	it.id = &"zz_scanned"
	it.take_over_path("res://resources/items/zz_scanned.tres")
	assert_eq(ScanContent.source_for("Ammo item 'zz_scanned' has no caliber — no weapon can draw from it.", [it]),
		"res://resources/items/zz_scanned.tres", "a quoted item id resolves to the scanned item's file")
	assert_eq(ScanContent.source_for("Something nobody named.", [it]), "content", "no path and no quoted match -> the bare content marker")
	it = null
	# The skipped-files row: ONE row naming every file, sourced at the items folder.
	var row := ScanContent.skipped_finding(PackedStringArray(["res://resources/items/broken.tres", "res://resources/items/half.tres"]))
	assert_eq(String(row["severity"]), "WARN")
	assert_eq(String(row["domain"]), "content")
	assert_eq(String(row["source"]), "res://resources/items", "sourced at the items folder so double-click reveals it")
	assert_true(String(row["message"]).begins_with("2 item files could not be read"), "the row counts the skipped files")
	assert_true(String(row["message"]).contains("broken.tres") and String(row["message"]).contains("half.tres"), "and names each one")
	var one := ScanContent.skipped_finding(PackedStringArray(["res://resources/items/broken.tres"]))
	assert_true(String(one["message"]).begins_with("1 item file could"), "singular when one file was skipped")


# --- the panel's pure row / filter / summary helpers ------------------------------------------------------------------

func test_panel_show_filter_hides_only_code_rows_by_default() -> void:
	assert_true(AuditPanel.row_visible("scene", AuditPanel.SHOW_SCENE_CONTENT), "scene rows show under the default view")
	assert_true(AuditPanel.row_visible("content", AuditPanel.SHOW_SCENE_CONTENT), "content rows show under the default view")
	assert_true(AuditPanel.row_visible("custom", AuditPanel.SHOW_SCENE_CONTENT), "a custom rule's rows show under the default view")
	assert_false(AuditPanel.row_visible("code", AuditPanel.SHOW_SCENE_CONTENT), "code rows are hidden under the default view")
	assert_true(AuditPanel.row_visible("code", AuditPanel.SHOW_ALL), "Everything shows code rows")
	assert_true(AuditPanel.row_visible("scene", AuditPanel.SHOW_ALL), "Everything shows scene rows")
	assert_true(AuditPanel.row_visible("code", AuditPanel.SHOW_CODE), "Code Only shows code rows")
	assert_false(AuditPanel.row_visible("content", AuditPanel.SHOW_CODE), "Code Only hides content rows")
	assert_eq(AuditPanel.domain_of({"severity": "WARN"}), "content", "a finding without a domain key reads as content -- nothing authored can be hidden by accident")


func test_panel_row_text_leads_with_the_message_and_ends_with_the_file_name() -> void:
	var f := {"severity": "WARN", "source": "res://resources/loot/raider_drops.tres", "message": "Loot entry 2: max count is below min count.", "fix": {"kind": "loot_clamp", "source": "res://resources/loot/raider_drops.tres"}}
	assert_eq(AuditPanel.row_text(f), "WARN   Loot entry 2: max count is below min count. -- raider_drops.tres  [fixable]",
		"'<SEV>   <message> -- <file name><tag>': message first, file NAME (not path) last, the fixable tag closing")
	var code := {"severity": "ERROR", "source": "res://scripts/player/player.gd", "message": "Group literal \"player\" is dead.", "domain": "code"}
	assert_true(AuditPanel.row_text(code).begins_with("ERROR   [code] Group literal"), "a code row is prefixed [code] after the severity")
	var scene := {"severity": "WARN", "source": "Geometry/Floor", "message": "Needs a collider.", "domain": "scene"}
	assert_eq(AuditPanel.row_text(scene), "WARN   Needs a collider. -- Geometry/Floor", "a scene row keeps its node path as the source label")
	assert_eq(AuditPanel.source_label("res:// (project-wide)"), "project-wide", "the wiring scan's project-wide marker reads as a plain word")
	assert_eq(AuditPanel.source_label("res://resources/items"), "items", "a folder source shows its folder name")
	assert_eq(AuditPanel.source_label("content"), "content", "the bare content marker passes through")


func test_panel_summary_counts_everything_and_names_hidden_rows() -> void:
	var findings := [
		{"severity": "ERROR", "source": "res://a.gd", "message": "m", "domain": "code"},
		{"severity": "WARN", "source": "res://b.tres", "message": "m", "domain": "content"},
		{"severity": "WARN", "source": "res://c.gd", "message": "m", "domain": "code"},
	]
	var s := AuditPanel.summary_text(findings, 1, 2, AuditPanel.SHOW_SCENE_CONTENT, false)
	assert_true(s.begins_with("Found 3 problems: 1 error, 2 warnings -- 1 auto-fixable."), "the counts are over EVERY finding, filter or not: %s" % s)
	assert_true(s.ends_with("-- 2 code rows hidden"), "the default view says how many code rows it is hiding: %s" % s)
	var code_only := AuditPanel.summary_text(findings, 1, 1, AuditPanel.SHOW_CODE, false)
	assert_true(code_only.ends_with("-- 1 scene + content row hidden"), "Code Only names the other kind of hidden row, singular when one: %s" % code_only)
	var no_scene := AuditPanel.summary_text([], 0, 0, AuditPanel.SHOW_SCENE_CONTENT, true)
	assert_eq(no_scene, "No scene open -- scene checks skipped. No problems found.", "a scan with no scene open says so before the verdict")
	assert_eq(AuditPanel.summary_text([], 0, 0, AuditPanel.SHOW_ALL, false), "No problems found.", "a clean scan with a scene open is just the verdict")
	var shown_all := AuditPanel.summary_text(findings, 0, 0, AuditPanel.SHOW_ALL, false)
	assert_false(shown_all.contains("hidden"), "Everything hides nothing, so nothing is reported hidden: %s" % shown_all)


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


func test_rewrite_group_literals_replaces_registered_and_leaves_others() -> void:
	# The general literal->const rewrite: only REGISTERED group-call literals are converted (to their Groups const);
	# lowercase "player" (the player_group fix's job), an unregistered typo, and a non-group string are all left alone.
	var const_names := {StringName("npc"): "NPC", StringName("Player"): "PLAYER"}
	var text := "func x():\n\tadd_to_group(&\"npc\")\n\tget_nodes_in_group(\"Player\")\n\tadd_to_group(&\"player\")\n\tis_in_group(&\"bogus\")\n\tvar d = {\"npc\": 1}\n"
	var res := FixOps.rewrite_group_literals_text(text, const_names)
	assert_eq(int(res["count"]), 2, "only the two REGISTERED group-call literals are rewritten")
	var out := String(res["text"])
	assert_true("add_to_group(Groups.NPC)" in out, "&\"npc\" -> Groups.NPC")
	assert_true("get_nodes_in_group(Groups.PLAYER)" in out, "sigil-less \"Player\" -> Groups.PLAYER")
	assert_true("add_to_group(&\"player\")" in out, "lowercase \"player\" is left for the player_group fix")
	assert_true("is_in_group(&\"bogus\")" in out, "an unregistered literal is left for a human")
	assert_true("{\"npc\": 1}" in out, "a non-group \"npc\" (dict key) is untouched")


func test_rewrite_group_literals_noop_when_clean() -> void:
	var const_names := {StringName("npc"): "NPC"}
	var text := "func x():\n\tadd_to_group(Groups.NPC)\n"
	var res := FixOps.rewrite_group_literals_text(text, const_names)
	assert_eq(int(res["count"]), 0, "already-const code has nothing to rewrite")
	assert_eq(String(res["text"]), text, "clean text is returned unchanged")


func test_rewrite_group_literals_skips_a_literal_inside_a_comment() -> void:
	# The fixer masks comments the SAME way the detector does (shared mask_comments), so a literal quoted in a `#`
	# comment is neither rewritten nor counted — the Fix touches exactly what the audit flagged, keeping the preview
	# count honest and never corrupting a documented idiom into a stale comment.
	var const_names := {StringName("npc"): "NPC"}
	var text := "func x():\n\tadd_to_group(&\"npc\")  # unlike the old add_to_group(&\"npc\")\n"
	var res := FixOps.rewrite_group_literals_text(text, const_names)
	assert_eq(int(res["count"]), 1, "only the real (code) literal is rewritten; the commented one is left")
	var out := String(res["text"])
	assert_true("add_to_group(Groups.NPC)  # unlike the old add_to_group(&\"npc\")" in out, "code literal -> const, comment verbatim")


func test_build_plan_includes_group_literal_kind() -> void:
	var findings := [{"severity": "WARN", "source": "res://a.gd", "fix": {"kind": "group_literal", "source": "res://a.gd"}}]
	var plan := FixOps.build_plan(findings)
	assert_eq(plan.size(), 1, "a group_literal fix is admitted to the plan")
	assert_eq(plan[0]["kind"], "group_literal")
	assert_true(String(plan[0]["label"]) != "", "it has a human label for the preview dialog")


func test_build_plan_labels_are_plain_words_with_file_names() -> void:
	# The labels are the body of the Fix preview dialog, read by the designer: file NAMES, no paths, no Groups.<CONST>.
	var findings := [
		{"severity": "ERROR", "source": "res://scripts/player/player.gd", "fix": {"kind": "player_group", "source": "res://scripts/player/player.gd"}},
		{"severity": "WARN", "source": "res://scripts/npc/npc.gd", "fix": {"kind": "group_literal", "source": "res://scripts/npc/npc.gd"}},
		{"severity": "WARN", "source": "res://resources/loot/raider_drops.tres", "fix": {"kind": "loot_clamp", "source": "res://resources/loot/raider_drops.tres"}},
	]
	var labels: Array = []
	for row in FixOps.build_plan(findings):
		labels.append(String(row["label"]))
	assert_has(labels, "Use the proper group name for \"player\" in player.gd  (code only, safe)", "the dead-player rewrite names the script by file name and says it is code-only and safe")
	assert_has(labels, "Use the proper group names in npc.gd  (code only, safe)", "the registered-literal rewrite reads the same way")
	assert_has(labels, "Fix loot table raider_drops: max count raised to min count", "the loot clamp names the table and what changes")
	for l in labels:
		assert_false(String(l).contains("res://"), "no path in a preview line (the dialog has no tooltip to hide one in): %s" % l)


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


## The script fixer against a TEMP COPY under user://: the rewrite lands, and the prior bytes sit in <path>.bak beside
## it -- the Fix dialog tells the designer "each gets a .bak copy beside it", so this pins that it is true.
func test_apply_player_group_backs_up_then_rewrites_a_temp_script() -> void:
	var original := "func x():\n\tadd_to_group(\"player\")\n"
	var w := FileAccess.open(TMP_GD, FileAccess.WRITE)
	assert_not_null(w, "the temp script should be writable under user://")
	w.store_string(original)
	w = null
	var r := FixOps._apply_player_group(TMP_GD)
	assert_true(bool(r["ok"]), "the rewrite reports ok: %s" % [r])
	assert_eq(int(r["count"]), 1, "one literal rewritten")
	assert_eq(FileAccess.get_file_as_string(TMP_GD), "func x():\n\tadd_to_group(Groups.PLAYER)\n", "the file on disk carries the fix")
	assert_true(FileAccess.file_exists(TMP_GD + ".bak"), "a .bak sibling was made BEFORE the write")
	assert_eq(FileAccess.get_file_as_string(TMP_GD + ".bak"), original, "and it holds the prior bytes, byte for byte")
	# Idempotent: a second apply changes nothing and (with nothing to write) makes no new backup over the real one.
	var again := FixOps._apply_player_group(TMP_GD)
	assert_eq(int(again["count"]), 0, "running the fixer twice finds nothing left to rewrite")
	assert_eq(FileAccess.get_file_as_string(TMP_GD + ".bak"), original, "the .bak still holds the ORIGINAL bytes -- a no-op apply doesn't overwrite it with the fixed text")


func test_apply_player_group_refuses_a_missing_script_in_plain_words() -> void:
	var r := FixOps._apply_player_group("user://no_such_script_zzz.gd")
	assert_false(bool(r["ok"]), "a script that can't be opened is a soft failure, never a throw")
	assert_eq(String(r["error"]), FixOps.ERR_READ, "the skip reason is the plain-words read failure (no error code)")


## The SHAPE of a skip row, which the panel's result dialog depends on: audit_panel prints "<file name>  (<folder>) --
## <reason>" by reading row["source"] and row["error"] separately. A pre-joined "<path>: <reason>" string would render
## as an EMPTY bullet there, so the two halves must stay apart.
func test_apply_plan_skip_rows_keep_the_path_and_the_reason_apart() -> void:
	var plan := [{"kind": "loot_clamp", "source": "res://resources/loot/no_such_table_zzz.tres", "label": "unused"}]
	var result := FixOps.apply_plan(plan)
	var errs: Array = result["errors"]
	assert_eq(errs.size(), 1, "the missing table is one skip row")
	assert_true(errs[0] is Dictionary, "a skip row is a Dictionary the panel can name its own way, never a pre-joined string")
	if errs[0] is Dictionary:
		var row: Dictionary = errs[0]
		assert_eq(String(row["source"]), "res://resources/loot/no_such_table_zzz.tres", "it keeps the PATH, so the panel can print file name + folder")
		assert_eq(String(row["error"]), FixOps.ERR_MISSING, "and the plain-words reason, apart from the path")
	assert_eq(int(result["files"]), 0, "nothing was written")
	assert_true((result["written"] as Array).is_empty(), "and nothing is reported as changed")


## The loot fixer against a TEMP .tres under user://: the resave goes through ContentSaveGuard, so the prior bytes
## land in <path>.bak and the file on disk carries the clamp.
func test_apply_loot_clamp_backs_up_then_resaves_a_temp_table() -> void:
	var table := LootTable.new()
	var bad := LootEntry.new()
	bad.min_count = 3
	bad.max_count = 1
	table.entries = [bad]
	assert_eq(ResourceSaver.save(table, TMP_LOOT), OK, "the temp loot table should write under user://")
	var before := FileAccess.get_file_as_string(TMP_LOOT)
	var r := FixOps._apply_loot_clamp(TMP_LOOT)
	assert_true(bool(r["ok"]), "the clamp reports ok: %s" % [r])
	assert_eq(int(r["count"]), 1, "one entry clamped")
	assert_true(FileAccess.file_exists(TMP_LOOT + ".bak"), "a .bak sibling was made through ContentSaveGuard")
	assert_eq(FileAccess.get_file_as_string(TMP_LOOT + ".bak"), before, "and it holds the bytes from before the resave")
	var reloaded := ResourceLoader.load(TMP_LOOT, "", ResourceLoader.CACHE_MODE_IGNORE) as LootTable
	assert_not_null(reloaded, "the resaved table reloads from disk")
	if reloaded != null:
		assert_eq(reloaded.entries[0].max_count, 3, "the file on disk carries max raised up to min")
	table = null
	bad = null
	reloaded = null


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


## A rule's Array can hold something that isn't a finding at all (a stray number, a null from a half-written branch).
## Those rows must be DROPPED, not merged: the panel counts every finding in "Found N problems" but can only draw a
## Dictionary, so a junk row would inflate the count with a problem the designer can never find or click.
func test_custom_rule_junk_rows_are_dropped_rather_than_counted() -> void:
	var mixed := _rule_script("func run_audit(_root):\n\treturn [{\"severity\": \"WARN\", \"source\": \"res://x\", \"message\": \"real\"}, 42, null]\n")
	var out := CustomRules.run_rules([mixed], null)
	assert_eq(out.size(), 1, "only the Dictionary finding survives the merge")
	if out.size() == 1:
		assert_eq(String(out[0]["message"]), "real", "and it is the rule's genuine finding")


func test_custom_rule_finding_helper_shape() -> void:
	var f := AuditRule.finding("ERROR", "res://a.tscn", "broke")
	assert_eq(f["severity"], "ERROR")
	assert_false(f.has("node"), "no node key when none is passed")
	var n := Node.new()
	var f2 := AuditRule.finding("WARN", "res://a.tscn", "look here", n)
	assert_eq(f2["node"], n, "the node is carried for click-to-jump")
	n.free()
