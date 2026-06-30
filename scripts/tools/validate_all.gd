extends SceneTree

## VALIDATE ALL — the headless, CI-gateable aggregator of the project's ALREADY-pure validators. One command runs
## every static content / wiring / navmesh check that today only fires when a human clicks the editor Audit panel
## or File -> Run, prints ONE grouped report, and exits NON-ZERO on real breakage — so a broken quest chain, an
## orphaned loot item, a dead story flag, a broken ext_resource, or props baked as walkable navmesh can't reach a
## build unnoticed. This is the "give the pure validators a home outside the editor" piece (cf. the soak harness).
##
## It REUSES the existing checks — it does not reinvent any:
##   * ContentValidator.run()  (scripts/tools/content_validator.gd) — item ids/calibers, faction id==filename, Perk/GoapProfile.
##   * ScanDisk.run()          (addons/cybersunday_tools/panel_audit/scan_disk.gd) — group-literal typos, broken
##                             ext_resource, LootTable/Dialogue breakage, AND (it chains ScanWiring.run()) dead
##                             story flags + dangling quest/objective/faction ids.
##   * NavMeshAudit.analyze()  (scripts/tools/navmesh_audit.gd) — disconnected islands + elevated polys, per level scene.
## (Domain A per-scene config-warnings are deliberately skipped here — they're editor-time @tool guidance; the audit
## panel covers them. The high-value content/wiring/navmesh checks are all headless-pure.)
##
## Run it (headless, no editor needed):
##   godot --headless -s scripts/tools/validate_all.gd                       # or: scripts/tools/validate.cmd
##   godot --headless -s scripts/tools/validate_all.gd -- --strict           # also fail on WARNs + navmesh issues
##   godot --headless -s scripts/tools/validate_all.gd -- res://scenes/levels/MyLevel.tscn   # audit specific level(s)
##
## EXIT CODE (the CI gate): 1 if there's any ERROR finding or content problem; WARN findings + navmesh issues are
## REPORTED but don't fail by default (bake health is iterative; some flags are WIP). `--strict` fails on everything.
##
## It reads autoloads (ContentValidator -> ItemDb), so the work runs on the first idle frame — after autoload
## _ready has populated the indexes — then quits with the exit code.

## ContentValidator + ScanDisk are load()ed at RUNTIME (not preloaded) on purpose: they depend on autoload globals
## (ItemDb / GameSettings) that AREN'T registered yet when a `-s` script's compile chain runs at boot — a
## compile-time preload of them fails with "Identifier not found: ItemDb". By the first process frame the autoloads
## are up, so load() compiles them cleanly. NavMeshAudit is pure (no autoloads), so it's safe to use directly.
const CONTENT_VALIDATOR_PATH := "res://scripts/tools/content_validator.gd"
const SCAN_DISK_PATH := "res://addons/cybersunday_tools/panel_audit/scan_disk.gd"
const LEVELS_DIR := "res://scenes/levels"

## Empty starter templates authors INSTANCE new levels from: their NavigationRegion3D carries the required bake
## PARAMETERS but 0 baked polygons (there's no geometry to bake yet) — correct by design, not a regression. Skipped
## in the auto-scan so a clean run is genuinely 0 navmesh issues and `--strict` becomes a usable gate; still audited
## if a template is named EXPLICITLY on the command line. A REAL level shipping unbaked still has geometry, so its
## 0-poly navmesh is NOT on this list and is still flagged.
const NAVMESH_TEMPLATE_SCENES: Array[String] = ["res://scenes/levels/LevelTemplate.tscn"]

var _done := false


func _process(_delta: float) -> bool:
	# One-frame defer: autoloads' _ready (ItemDb building its item index) has run by the first process frame, so
	# ContentValidator sees real content instead of an empty index. quit(code) drives termination with the exit code.
	if not _done:
		_done = true
		quit(_run_all())
	return false


func _run_all() -> int:
	var strict := false
	var explicit_levels: Array[String] = []
	for a in OS.get_cmdline_user_args():
		if a == "--strict":
			strict = true
		elif a.begins_with("res://"):
			explicit_levels.append(a)  # audit just these level scenes instead of scanning scenes/levels/

	print_rich("\n[b]== validate_all ==[/b]")
	var errors := 0
	var warns := 0
	var navmesh_issues := 0

	# --- 1) CONTENT: item ids/calibers, faction id==filename, Perk/GoapProfile authoring ---
	var content_validator := load(CONTENT_VALIDATOR_PATH)  # runtime load: see the const comment (autoload timing)
	var content: PackedStringArray = content_validator.run() if content_validator != null else PackedStringArray()
	print_rich("\n[b]-- content --[/b]  (%d problem(s))" % content.size())
	for p in content:
		print("  ERROR  ", p)
	errors += content.size()  # blank/dup item id, ammo w/o caliber, bad faction id = unambiguous breakage

	# --- 2) DISK + WIRING: group typos, broken ext_resource, loot/dialogue, dead flags, dangling quest/faction ids ---
	# ScanDisk.run() already appends ScanWiring.run(), so this one call covers Domains B and C.
	var scan_disk := load(SCAN_DISK_PATH)  # runtime load (depends on GameSettings via loot_table)
	var disk: Array = scan_disk.run() if scan_disk != null else []
	print_rich("\n[b]-- disk + wiring --[/b]  (%d finding(s))" % disk.size())
	for f in disk:
		var sev := str(f.get("severity", "WARN"))
		print("  %-5s  %s  —  %s" % [sev, str(f.get("source", "?")), str(f.get("message", ""))])
		if sev == "ERROR":
			errors += 1
		else:
			warns += 1

	# --- 3) NAVMESH: disconnected islands + elevated (prop/roof) polys, per level scene ---
	var auditing_explicit := not explicit_levels.is_empty()
	var level_paths := explicit_levels if auditing_explicit else _all_level_scenes()
	print_rich("\n[b]-- navmesh --[/b]  (%d level scene(s))" % level_paths.size())
	for path in level_paths:
		if not auditing_explicit and path in NAVMESH_TEMPLATE_SCENES:
			print("  ", path, " — skipped (empty starter template; 0 polys is expected, nothing to bake)")
			continue
		navmesh_issues += _audit_level(path)

	# --- summary + exit code ---
	var fail := errors > 0
	if strict:
		fail = fail or warns > 0 or navmesh_issues > 0
	print_rich("\n[b]== RESULT: %s ==[/b]  %d error(s), %d warning(s), %d navmesh issue(s)%s" % [
		("[color=red]FAIL[/color]" if fail else "[color=lime]PASS[/color]"),
		errors, warns, navmesh_issues, ("  [strict]" if strict else ""),
	])
	if not strict and (warns > 0 or navmesh_issues > 0):
		print("  (warnings + navmesh issues are reported but don't fail without --strict)")
	return 1 if fail else 0


func _all_level_scenes() -> Array[String]:
	var out: Array[String] = []
	var dir := DirAccess.open(LEVELS_DIR)
	if dir == null:
		return out
	dir.list_dir_begin()
	var f := dir.get_next()
	while f != "":
		if not dir.current_is_dir() and f.ends_with(".tscn"):
			out.append(LEVELS_DIR + "/" + f)
		f = dir.get_next()
	dir.list_dir_end()
	return out


## Analyze every NavigationRegion3D in one level scene; print + return the count of regions with issues. Instantiates
## the scene WITHOUT adding it to the tree (so no _ready runs — same as audit_navmesh.gd), and null-guards the empty
## PackedScene a mid-edit reimport can hand back (see [[dont-import-with-editor-open-empty-packedscene]]).
func _audit_level(path: String) -> int:
	var ps := load(path) as PackedScene
	if ps == null:
		print("  ", path, " — could not load (skipped).")
		return 0
	var root := ps.instantiate()
	if root == null:
		print("  ", path, " — instantiated empty (reimport in flight? skipped).")
		return 0
	var regions: Array[NavigationRegion3D] = []
	_collect_regions(root, regions)
	var issues := 0
	if regions.is_empty():
		print("  ", path, " — (no NavigationRegion3D)")
	for region in regions:
		var rep := NavMeshAudit.analyze(region.navigation_mesh)
		if rep.ok:
			print("  ", path, " / ", region.name, " — OK (%d polys, %d island(s))" % [rep.poly_count, rep.islands.size()])
		else:
			issues += 1
			print("  ", path, " / ", region.name, " — ISSUES:")
			for w in rep.warnings:
				print("      ! ", w)
	root.free()
	return issues


func _collect_regions(node: Node, out: Array[NavigationRegion3D]) -> void:
	if node is NavigationRegion3D:
		out.append(node)
	for c in node.get_children():
		_collect_regions(c, out)
