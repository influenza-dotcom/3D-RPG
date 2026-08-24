extends RefCounted

## CYBER CMDS — the pure VERB LAYER behind the headless `cyber` CLI (scripts/tools/cyber.gd) and, through it, the
## MCP server (tools/mcp/cyber_mcp.py). ONE entry point — run(verb, args) — returns ONE plain Dictionary shape that
## survives JSON.stringify end to end, so an external agent can ask this project questions ("what components exist?",
## "what references this .tres?", "what does this weapon actually do?") instead of guessing from a grep.
##
## THE RETURN CONTRACT (exact, every verb, always):
##   { "ok": bool, "verb": String, "data": Variant, "error": String, "warnings": Array[String] }
## `ok` false + a human-readable `error` for an unknown verb or a bad argument — this file NEVER push_errors and
## NEVER crashes the caller. `data` is the verb's payload; it is passed through _json_safe() on the way out, so a
## StringName / Vector3 / PackedStringArray / Resource that leaks in from a scanner or an authored .tres can never
## break the JSON framing the CLI depends on.
##
## NO class_name ON PURPOSE — the Factions / Calibers / InspectorCalc idiom. There is nothing here for the global
## script class cache to miss, so a fresh clone (or a cache rebuild mid-session) can still run the CLI.
##
## THE AUTOLOAD COMPILE-ORDER TRAP is why every module below is a `const *_PATH := "res://…"` string load()ed at
## call time instead of a preload: a `godot --headless -s` script's compile chain runs BEFORE the autoloads are
## registered, and several of these modules transitively reach GameSettings / ItemDb (scan_disk -> loot_table ->
## GameSettings is the known one). cyber.gd itself load()s THIS file on its first _process frame for the same
## reason — by then the autoloads are up. Do not "tidy" these into preloads. (validate_all.gd:31-39 documents the
## same fix; text_debt.gd uses it too.)
##
## PURITY: DirAccess / FileAccess / load() are allowed (these are READ commands). There is NO EditorInterface and
## NO scene-tree access anywhere in this file, so every verb runs headless and the GUT test can call run() directly.
## ZERO WRITES: no ResourceSaver, no FileAccess.WRITE, no DirAccess.make_dir/remove/rename. A read tool that can
## write is a read tool nobody can trust with a project the user has open in the editor.
##
## REUSE, NEVER REIMPLEMENT: every verb is a thin adapter over a module that already exists and is already tested
## (the catalog, the audit scanners, the refs finder, the graph builder, the inspector calcs, the browser scan).
## When one of those grows a check, this CLI gets it for free. If you find yourself writing analysis HERE, it
## belongs in the module instead.

# ──────────────────────────────────────────────────────────────────────────────────────────────────────────────
# Module paths — runtime-load targets (see the autoload trap in the header). Never preload these.
# ──────────────────────────────────────────────────────────────────────────────────────────────────────────────

const CATALOG_PATH := "res://addons/cybersunday_tools/core/catalog.gd"
const SCAN_DISK_PATH := "res://addons/cybersunday_tools/panel_audit/scan_disk.gd"
const SCAN_TEXT_PATH := "res://addons/cybersunday_tools/panel_audit/scan_text.gd"
const SCAN_MENU_SOUND_PATH := "res://addons/cybersunday_tools/panel_audit/scan_menu_sound.gd"
const SCAN_CACHE_PATH := "res://addons/cybersunday_tools/panel_audit/scan_cache.gd"
const REF_SCAN_PATH := "res://addons/cybersunday_tools/dock_refs/ref_scan.gd"
const GRAPH_DATA_PATH := "res://addons/cybersunday_tools/panel_graph/graph_data.gd"
const INSPECTOR_CALC_PATH := "res://addons/cybersunday_tools/inspectors/inspector_calc.gd"
const LOOTTABLE_INSPECTOR_PATH := "res://addons/cybersunday_tools/inspectors/loottable_inspector.gd"
const BROWSE_SCAN_PATH := "res://addons/cybersunday_tools/dock_browser/browse_scan.gd"
## The Content Browser owns the ONE list of content folders (its ROOTS const). `list` reads that const off the
## script rather than copying the table here — a duplicated folder map is exactly the drift this tool exists to
## catch in other people's data.
const CONTENT_BROWSER_PATH := "res://addons/cybersunday_tools/dock_browser/content_browser.gd"
const CALIBERS_PATH := "res://scripts/items/calibers.gd"

## The scripts `balance` type-tests against BY PATH rather than with `is WeaponData` / `is LootTable`.
##
## THIS IS NOT STYLE — it is the autoload trap again, one level deeper than the header describes. Naming a
## class_name in code makes that class's script a COMPILE-TIME dependency of this file, and loot_table.gd reads
## GameSettings (an autoload) at compile time. With `is LootTable` in here, `godot --check-only -s cyber_cmds.gd`
## fails with "Identifier not found: GameSettings" and the file only compiles when it happens to be loaded after
## the autoloads exist. Comparing the script chain's FILE NAMES keeps this file dependency-free, so it compiles
## in ANY context — a --check-only gate, a future preload, a File→Run tool.
const WEAPON_DATA_SCRIPT := "res://scripts/combat/weapon_data.gd"
const LOOT_TABLE_SCRIPT := "res://scripts/items/loot_table.gd"

## Content folders the `balance` and `graph` verbs scan when no explicit `path` is given.
const WEAPONS_DIR := "res://resources/weapons"
const LOOT_DIR := "res://resources/loot"
const DIALOGUE_DIR := "res://resources/dialogue"
const QUESTS_DIR := "res://resources/quests"

## Monte-Carlo defaults for `balance` on a LootTable — the same 1000 / 12345 the LootTable inspector card uses, so
## the CLI and the in-editor "Roll 1000×" button report the SAME numbers. Overridable via the `rolls` / `seed` args.
const DEFAULT_ROLLS := 1000
const DEFAULT_SEED := 12345

## The reimport-in-flight warning text. The user keeps the editor open all day; a .tres being re-imported right now
## load()s as null (or a PackedScene instantiates with 0 nodes). Reporting THAT as a clean pass is the trap this
## project has hit before — a green result over a file nobody actually read. Every verb that meets one adds this
## warning, sets data.skipped_reimport_in_flight, and refuses to claim success for the unread file.
const REIMPORT_WARNING := "reimport in flight? (a resource load returned null / an empty scene — re-run in a few seconds)"

## Every verb run() answers. Also the unknown-verb error's suggestion list, so a caller that typos gets the menu.
const VERBS: Array[String] = ["catalog", "audit", "refs", "graph", "balance", "list", "describe"]

## Guard for the recursive JSON converter: a self-referential Array/Dictionary would otherwise spin forever.
## Authored .tres data never nests this deep, so hitting the cap means something is cyclic — degrade to a string.
const MAX_JSON_DEPTH := 12

## Severities the audit domains emit (scan_disk / scan_wiring / scan_text / scan_menu_sound). Used to validate the
## `severity` filter and to fix the grouping order (errors first) in the payload.
const SEVERITIES: Array[String] = ["ERROR", "WARN"]


# ──────────────────────────────────────────────────────────────────────────────────────────────────────────────
# THE ENTRY POINT
# ──────────────────────────────────────────────────────────────────────────────────────────────────────────────

## Run ONE command. `verb` is one of VERBS; `args` is a flat Dictionary of String keys (the CLI hands every value
## through as a String — `--arg:limit=20` — so numeric args accept "20" as readily as 20).
##
## The result is re-assembled here in a FIXED key order and passed through _json_safe(), so the shape a caller
## parses is identical for a success, a failure, and a crash-adjacent degrade. Nothing below this line may throw.
static func run(verb: String, args: Dictionary = {}) -> Dictionary:
	var res: Dictionary
	match verb:
		"catalog": res = _catalog(args)
		"audit": res = _audit(args)
		"refs": res = _refs(args)
		"graph": res = _graph(args)
		"balance": res = _balance(args)
		"list": res = _list(args)
		"describe": res = _describe(args)
		_:
			res = _fail("unknown verb '%s' — known verbs: %s" % [verb, ", ".join(PackedStringArray(VERBS))])
	return {
		"ok": bool(res.get("ok", false)),
		"verb": verb,
		"data": _json_safe(res.get("data", null)),
		"error": String(res.get("error", "")),
		"warnings": _string_array(res.get("warnings", [])),
	}


# ──────────────────────────────────────────────────────────────────────────────────────────────────────────────
# VERB: catalog — the droppable-component catalog
# ──────────────────────────────────────────────────────────────────────────────────────────────────────────────

## The drop-in component catalog (addons/cybersunday_tools/core/catalog.gd COMPONENTS), optionally filtered by a
## case-insensitive substring over each row's class name / category.
##
## WHY IT EXISTS: this is the answer to "which components can I attach?", and its whole job is to stop an agent
## INVENTING a component that does not exist. The rows carry script_path / scene_path / add_mode / key_exports, so
## the caller can go straight to the real file instead of guessing a name that sounds plausible.
static func _catalog(args: Dictionary) -> Dictionary:
	var warnings: Array = []
	_warn_unknown_args(args, ["filter"], warnings)
	var errors: Array = []
	var needle := _str_arg(args, "filter", "", errors).strip_edges().to_lower()
	if not errors.is_empty():
		return _fail(String(errors[0]), warnings)

	var script := load(CATALOG_PATH) as GDScript
	if script == null:
		return _fail("could not load the component catalog at %s (missing, or it failed to compile)" % CATALOG_PATH, warnings)
	# COMPONENTS is a script CONSTANT, not a property — get_script_constant_map() is the engine-native way to read
	# one off a load()ed GDScript (Object.get() does not see constants). A GDScript that failed to PARSE still loads
	# non-null but reports an EMPTY constant map, so the has() below is the guard for that half, not a formality.
	var consts: Dictionary = script.get_script_constant_map()
	if not consts.has("COMPONENTS"):
		return _fail("%s has no COMPONENTS const — the catalog module changed shape" % CATALOG_PATH, warnings)
	var rows: Array = consts["COMPONENTS"]

	var kept: Array = []
	for row: Dictionary in rows:
		if needle == "" or _catalog_row_matches(row, needle):
			kept.append(row)
	if needle != "" and kept.is_empty():
		warnings.append("filter '%s' matched none of the %d catalog rows" % [needle, rows.size()])
	return _ok({
		"total": rows.size(),
		"count": kept.size(),
		"filter": needle,
		"components": kept,
	}, warnings)


## Case-insensitive substring test over the fields a designer would search by: the component's class name and its
## palette category. (Description is deliberately NOT matched — a prose grep makes the filter unpredictable.)
static func _catalog_row_matches(row: Dictionary, needle: String) -> bool:
	if String(row.get("class_name", "")).to_lower().contains(needle):
		return true
	return String(row.get("category", "")).to_lower().contains(needle)


# ──────────────────────────────────────────────────────────────────────────────────────────────────────────────
# VERB: audit — the full project audit (the Audit panel's domains, headless)
# ──────────────────────────────────────────────────────────────────────────────────────────────────────────────

## The whole audit in one call: ScanDisk.run() (Domain B — group typos, broken ext_resource, LootTable/Dialogue
## breakage — and it already CHAINS ScanWiring.run() for Domain C: dead story flags, dangling quest/objective/
## faction ids), plus ScanText.run() (Domain D — hardcoded player-facing strings) and ScanMenuSound.run()
## (Domain E — silent refusal paths). Each finding is tagged with the `domain` that produced it.
##
## Args: `severity` ("ERROR" / "WARN") narrows the payload; `limit` caps rows PER SEVERITY GROUP (not overall) so a
## flood of WARNs can never push the ERRORs out of a truncated answer — the whole point of asking is to see those.
##
## The three scanners each read the same .gd files, so the run is wrapped in the shared ScanCache window
## (one read per file for the whole audit). The window is ALWAYS closed, even when a scanner fails to load.
static func _audit(args: Dictionary) -> Dictionary:
	var warnings: Array = []
	_warn_unknown_args(args, ["severity", "limit"], warnings)
	var errors: Array = []
	var severity := _str_arg(args, "severity", "", errors).strip_edges().to_upper()
	var limit := _int_arg(args, "limit", 0, errors)
	if not errors.is_empty():
		return _fail(String(errors[0]), warnings)
	if severity != "" and not SEVERITIES.has(severity):
		return _fail("arg 'severity' must be one of %s (got '%s')" % [", ".join(PackedStringArray(SEVERITIES)), severity], warnings)
	if limit < 0:
		return _fail("arg 'limit' must be 0 (no cap) or a positive number of rows", warnings)

	var findings: Array = []
	var by_domain: Dictionary = {}
	var incomplete := false

	var cache: Variant = _module(SCAN_CACHE_PATH, &"begin")
	if cache != null:
		cache.begin()
	for pair in [["disk", SCAN_DISK_PATH], ["text", SCAN_TEXT_PATH], ["menu_sound", SCAN_MENU_SOUND_PATH]]:
		var domain := String(pair[0])
		var path := String(pair[1])
		var scanner: Variant = _module(path, &"run")
		if scanner == null:
			# A scanner that won't load (or that no longer exposes run()) means this domain was NOT checked — say so
			# loudly rather than reporting a clean audit over a file nobody read.
			incomplete = true
			warnings.append("audit domain '%s' skipped: could not load %s — %s" % [domain, path, REIMPORT_WARNING])
			by_domain[domain] = -1
			continue
		var rows: Array = scanner.run()
		by_domain[domain] = rows.size()
		for row: Dictionary in rows:
			var tagged := row.duplicate()  # never mutate a scanner's own dict — it may be reused / cached
			tagged["domain"] = domain
			findings.append(tagged)
	if cache != null:
		cache.end()

	# Group by severity (errors first), then apply the per-group cap.
	var grouped: Dictionary = {}
	var totals: Dictionary = {}
	for sev in SEVERITIES:
		grouped[sev] = []
		totals[sev] = 0
	for f: Dictionary in findings:
		var sev := String(f.get("severity", "WARN"))
		if not grouped.has(sev):  # a future domain could add a severity — keep it rather than dropping the row
			grouped[sev] = []
			totals[sev] = 0
		grouped[sev].append(f)
		totals[sev] = int(totals[sev]) + 1
	totals["all"] = findings.size()

	var out_groups: Dictionary = {}
	var truncated := false
	var returned := 0
	for sev in grouped:
		if severity != "" and String(sev) != severity:
			continue
		var rows: Array = grouped[sev]
		if limit > 0 and rows.size() > limit:
			rows = rows.slice(0, limit)
			truncated = true
		out_groups[sev] = rows
		returned += rows.size()

	var data := {
		"totals": totals,
		"by_domain": by_domain,
		"severity_filter": severity,
		"limit": limit,
		"limit_is_per_severity": true,
		"truncated": truncated,
		"returned": returned,
		"findings": out_groups,
	}
	if incomplete:
		data["skipped_reimport_in_flight"] = true
		return _fail("the audit is INCOMPLETE — at least one domain scanner could not be loaded (see warnings)", warnings, data)
	return _ok(data, warnings)


# ──────────────────────────────────────────────────────────────────────────────────────────────────────────────
# VERB: refs — back-references (who points at this file?)
# ──────────────────────────────────────────────────────────────────────────────────────────────────────────────

## Every project file that references `path`, by res:// PATH **or by uid://** — which is the whole value over a
## plain grep: a .tscn/.tres normally stores an ext_resource by uid, so grepping the path alone misses real owners
## and you delete something that was still wired up. Each row is {file, lines} — the referring lines give the
## caller the context (an ext_resource row, a load() call) without a second read.
static func _refs(args: Dictionary) -> Dictionary:
	var warnings: Array = []
	_warn_unknown_args(args, ["path"], warnings)
	var errors: Array = []
	var path := _str_arg(args, "path", "", errors).strip_edges()
	if not errors.is_empty():
		return _fail(String(errors[0]), warnings)
	if path.is_empty():
		return _fail("refs requires arg 'path' — the res:// file to find back-references for", warnings)
	if not path.begins_with("res://"):
		return _fail("arg 'path' must be a res:// path (got '%s')" % path, warnings)
	# A missing target is still a legitimate question ("what USED to point here?"), so this warns instead of
	# failing — but the uid half of the search is unavailable, which materially weakens the answer.
	if not FileAccess.file_exists(path):
		warnings.append("no file at %s — searching by path only (its uid can't be read, so uid-only references are missed)" % path)

	var scan: Variant = _module(REF_SCAN_PATH, &"find_referencers")
	if scan == null:
		return _fail("could not load the reference scanner at %s (missing, or it failed to compile)" % REF_SCAN_PATH, warnings)
	var uid: String = scan.uid_for(path)
	var rows: Array = scan.find_referencers(path)
	return _ok({
		"path": path,
		"uid": uid,
		"count": rows.size(),
		"referencers": rows,
	}, warnings)


# ──────────────────────────────────────────────────────────────────────────────────────────────────────────────
# VERB: graph — dialogue / quest graphs + dangling-target detection
# ──────────────────────────────────────────────────────────────────────────────────────────────────────────────

## Build the node/edge graph for dialogue or quests via the shared pure builder (panel_graph/graph_data.gd — the
## same one the in-editor viewers render), and surface its `problems` array: an out-of-range dialogue target or a
## prereq_quest_id naming no quest is a dead end a player can walk into, and it is invisible in the inspector.
##
## `kind` = "dialogue" (default) | "quests". For dialogue, `path` picks ONE resource, else every dialogue resource
## under resources/dialogue/ is built. For quests the SET is always the unit (prereq/next links only resolve
## against the other quests in the folder), so `path` selects that quest's FOLDER.
static func _graph(args: Dictionary) -> Dictionary:
	var warnings: Array = []
	_warn_unknown_args(args, ["kind", "path"], warnings)
	var errors: Array = []
	var kind := _str_arg(args, "kind", "", errors).strip_edges().to_lower()
	var path := _str_arg(args, "path", "", errors).strip_edges()
	if not errors.is_empty():
		return _fail(String(errors[0]), warnings)
	if kind == "":
		kind = "dialogue"
		warnings.append("no 'kind' given — defaulting to \"dialogue\" (the other choice is \"quests\")")
	if kind != "dialogue" and kind != "quests":
		return _fail("arg 'kind' must be \"dialogue\" or \"quests\" (got '%s')" % kind, warnings)
	if path != "" and not path.begins_with("res://"):
		return _fail("arg 'path' must be a res:// path (got '%s')" % path, warnings)

	var builder: Variant = _module(GRAPH_DATA_PATH, &"build_dialogue")
	if builder == null:
		return _fail("could not load the graph builder at %s (missing, or it failed to compile)" % GRAPH_DATA_PATH, warnings)
	if kind == "quests":
		return _graph_quests(builder, path, warnings)
	return _graph_dialogue(builder, path, warnings)


static func _graph_dialogue(builder: Variant, path: String, warnings: Array) -> Dictionary:
	var paths: Array = []
	if path != "":
		# A named resource that does not exist is a TYPO, not a reimport. Without this the load()-returned-null branch
		# below answers "reimport in flight? — re-run in a few seconds", and a machine caller retries that forever.
		# (Only the DIALOGUE half checks this: for quests `path` selects a FOLDER, which is not a loadable resource.)
		if not ResourceLoader.exists(path):
			return _fail("no resource at %s" % path, warnings)
		paths.append(path)
	else:
		paths = _resource_paths_in(DIALOGUE_DIR, warnings)

	var graphs: Array = []
	var problems: Array = []
	var skipped := false
	for p in paths:
		var res: Resource = load(String(p))
		if res == null:
			skipped = true
			warnings.append("%s loaded as null — %s" % [p, REIMPORT_WARNING])
			continue
		# Duck-typed: a DialogueResource carries a `lines` Array. resources/dialogue/ also holds voice profiles and
		# other siblings, so an explicit type test here is what keeps them out of the payload silently.
		if not (res.get("lines") is Array):
			if path != "":
				return _fail("%s is not a DialogueResource (no `lines` array) — nothing to graph" % p, warnings)
			continue
		var g: Dictionary = builder.build_dialogue(res)
		var probs: Array = g.get("problems", [])
		var g_nodes: Array = g.get("nodes", [])
		var g_edges: Array = g.get("edges", [])
		for pr: Dictionary in probs:
			var tagged := pr.duplicate()
			tagged["path"] = String(p)
			problems.append(tagged)
		graphs.append({
			"path": String(p),
			"node_count": g_nodes.size(),
			"edge_count": g_edges.size(),
			"problem_count": probs.size(),
			"nodes": g_nodes,
			"edges": g_edges,
			"problems": probs,
		})

	var data := {
		"kind": "dialogue",
		"scanned": paths.size(),
		"graphed": graphs.size(),
		"problem_count": problems.size(),
		"problems": problems,
		"graphs": graphs,
	}
	if skipped:
		data["skipped_reimport_in_flight"] = true
		return _fail("at least one dialogue resource could not be read (see warnings) — this graph is INCOMPLETE", warnings, data)
	if graphs.is_empty():
		warnings.append("no DialogueResource found under %s" % (path if path != "" else DIALOGUE_DIR))
	return _ok(data, warnings)


static func _graph_quests(builder: Variant, path: String, warnings: Array) -> Dictionary:
	# A quest graph is only meaningful over a SET: prereq_quest_id / next_quest resolve against sibling quests, so
	# a single-file graph would report every link as dangling. `path` therefore selects a FOLDER, not one quest.
	var folder := QUESTS_DIR
	if path != "":
		folder = path.get_base_dir() if path.get_extension() != "" else path
		warnings.append("quest graphs are built over a whole folder (prereq/next links resolve against siblings) — using %s" % folder)

	var quests: Array = []
	var loaded_paths: Array = []
	var skipped := false
	for p in _resource_paths_in(folder, warnings):
		var res: Resource = load(String(p))
		if res == null:
			skipped = true
			warnings.append("%s loaded as null — %s" % [p, REIMPORT_WARNING])
			continue
		# Duck-typed Quest test, mirroring dialogue_graph.gd's _load_quest_set: a Quest has both `id` and
		# `objectives`. Non-quest resources sharing the folder are skipped rather than graphed as blank nodes.
		if res.get("objectives") == null or res.get("id") == null:
			continue
		quests.append(res)
		loaded_paths.append(String(p))

	var g: Dictionary = builder.build_quests(quests)
	var probs: Array = g.get("problems", [])
	var g_nodes: Array = g.get("nodes", [])
	var g_edges: Array = g.get("edges", [])
	var data := {
		"kind": "quests",
		"folder": folder,
		"quest_count": quests.size(),
		"quest_paths": loaded_paths,
		"node_count": g_nodes.size(),
		"edge_count": g_edges.size(),
		"problem_count": probs.size(),
		"problems": probs,
		"nodes": g_nodes,
		"edges": g_edges,
	}
	if skipped:
		data["skipped_reimport_in_flight"] = true
		return _fail("at least one quest resource could not be read (see warnings) — this graph is INCOMPLETE", warnings, data)
	if quests.is_empty():
		warnings.append("no Quest resources found under %s" % folder)
	return _ok(data, warnings)


# ──────────────────────────────────────────────────────────────────────────────────────────────────────────────
# VERB: balance — derived weapon numbers + seeded loot-table tallies
# ──────────────────────────────────────────────────────────────────────────────────────────────────────────────

## The numbers a designer can't read off the inspector: DPS / burst / shots-and-seconds-to-kill per multiplier
## stack, clip sustain and recoil (InspectorCalc.weapon_lines), the half-configured-knob warnings
## (InspectorCalc.weapon_warnings, fed the real caliber set from Calibers.ids() so "caliber with no ammo" is
## caught — `data.caliber_check` reports false when that set was unreadable and the check was suppressed), and a
## seeded Monte-Carlo of every LootTable (LootTableInspector.tally — the same rolls the inspector card runs, so the
## CLI and the editor agree).
##
## `path` audits one resource; otherwise resources/weapons/ + resources/loot/ are scanned. `rolls` / `seed`
## override the tally defaults (a different seed is how you check a result isn't a fluke of one RNG stream).
static func _balance(args: Dictionary) -> Dictionary:
	var warnings: Array = []
	_warn_unknown_args(args, ["path", "rolls", "seed"], warnings)
	var errors: Array = []
	var path := _str_arg(args, "path", "", errors).strip_edges()
	var rolls := _int_arg(args, "rolls", DEFAULT_ROLLS, errors)
	var rng_seed := _int_arg(args, "seed", DEFAULT_SEED, errors)
	if not errors.is_empty():
		return _fail(String(errors[0]), warnings)
	if rolls <= 0:
		return _fail("arg 'rolls' must be a positive number of Monte-Carlo rolls (got %d)" % rolls, warnings)
	if path != "" and not path.begins_with("res://"):
		return _fail("arg 'path' must be a res:// path (got '%s')" % path, warnings)
	# A named resource that does not exist is a TYPO, not a reimport — without this the null-load branch below would
	# answer "reimport in flight? — re-run in a few seconds" and a machine caller would retry that forever.
	if path != "" and not ResourceLoader.exists(path):
		return _fail("no resource at %s" % path, warnings)

	var calc: Variant = _module(INSPECTOR_CALC_PATH, &"weapon_lines")
	if calc == null:
		return _fail("could not load the weapon calc at %s (missing, or it failed to compile)" % INSPECTOR_CALC_PATH, warnings)
	var loot_calc: Variant = _module(LOOTTABLE_INSPECTOR_PATH, &"tally")
	if loot_calc == null:
		return _fail("could not load the loot tally at %s (missing, or it failed to compile)" % LOOTTABLE_INSPECTOR_PATH, warnings)

	# THE CALIBER SET IS NOT OPTIONAL DATA — it is the ENABLE BIT for one of weapon_warnings' checks, and handing that
	# static an EMPTY set does the OPPOSITE of disabling it: `not known_calibers.has(cal)` is true for every caliber,
	# so EVERY armed weapon comes back flagged "could never reload". A red gauge over an unread folder is the same lie
	# as a green one. So the emptiness is tracked explicitly and _weapon_block genuinely suppresses the check.
	var calibers := PackedStringArray()
	var caliber_check := true
	var caliber_reg: Variant = _module(CALIBERS_PATH, &"ids")
	if caliber_reg == null:
		caliber_check = false
		warnings.append("could not load %s — the 'caliber matches no ammo' check is DISABLED for this run" % CALIBERS_PATH)
	else:
		calibers = caliber_reg.ids()
		if calibers.is_empty():
			# resources/items/ unreadable or mid-reimport. Every ammo caliber vanishing at once is a READ failure,
			# not a content finding; reporting it as one would condemn the whole armoury on no evidence.
			caliber_check = false
			warnings.append("%s found no ammo calibers on disk — the 'caliber matches no ammo' check is DISABLED for this run (%s)" % [CALIBERS_PATH, REIMPORT_WARNING])

	var paths: Array = []
	if path != "":
		paths.append(path)
	else:
		paths.append_array(_resource_paths_in(WEAPONS_DIR, warnings))
		paths.append_array(_resource_paths_in(LOOT_DIR, warnings))

	var weapons: Array = []
	var loot: Array = []
	var warning_count := 0
	var skipped := false
	var matched := false
	for p in paths:
		var res: Resource = load(String(p))
		if res == null:
			skipped = true
			warnings.append("%s loaded as null — %s" % [p, REIMPORT_WARNING])
			continue
		# The type test MUST happen here: weapon_lines(wd: WeaponData) / tally(lt: LootTable) are typed statics
		# that reject anything else AT THE CALL (a runtime error that would abort the whole verb), and these
		# folders hold textures, audio and the odd non-weapon .tres. _script_is() is the dependency-free test —
		# see the WEAPON_DATA_SCRIPT comment for why this is not `is WeaponData`.
		if _script_is(res, WEAPON_DATA_SCRIPT):
			matched = true
			var block := _weapon_block(String(p), res, calc, calibers, caliber_check)
			var block_warns: PackedStringArray = block["warnings"]
			warning_count += block_warns.size()
			weapons.append(block)
		elif _script_is(res, LOOT_TABLE_SCRIPT):
			matched = true
			loot.append(_loot_block(String(p), res, loot_calc, rolls, rng_seed))
	if path != "" and not matched and not skipped:
		return _fail("%s is neither a WeaponData nor a LootTable — nothing to balance" % path, warnings)

	var data := {
		"rolls": rolls,
		"seed": rng_seed,
		"caliber_check": caliber_check,
		"weapon_count": weapons.size(),
		"loot_count": loot.size(),
		"warning_count": warning_count,
		"weapons": weapons,
		"loot": loot,
	}
	if skipped:
		data["skipped_reimport_in_flight"] = true
		return _fail("at least one resource could not be read (see warnings) — these numbers are INCOMPLETE", warnings, data)
	# Only the FULL scan can reach here unmatched (an explicit `path` that matched nothing already failed above), and
	# an empty report reads exactly like a clean bill of health. It means the content folders moved or hold no weapons
	# and no tables — not that the balance is fine — so name the folders that were actually walked.
	if not matched:
		warnings.append("no WeaponData or LootTable found under %s or %s" % [WEAPONS_DIR, LOOT_DIR])
	return _ok(data, warnings)


## `wd` is typed Resource (not WeaponData) on purpose — see WEAPON_DATA_SCRIPT. The caller has already confirmed
## the script, and the typed statics inside inspector_calc check the VALUE's real type, which is a WeaponData.
##
## `caliber_check` false = the ammo registry was unreadable, so the "caliber matches no ammo" verdict has no evidence
## behind it. weapon_warnings has no off switch for that one check, but `known_calibers` is its ONLY input: feeding it
## a set that already contains this weapon's own caliber satisfies the test and leaves the other four checks (pellet
## spread, recoil recovery, bloom cap, infinite-ammo) running exactly as before. Passing an EMPTY set instead would
## FIRE the check on every weapon — the failure mode this parameter exists to prevent.
static func _weapon_block(path: String, wd: Resource, calc: Variant, calibers: PackedStringArray, caliber_check: bool) -> Dictionary:
	var cal: Variant = wd.get("caliber")  # duck-typed read: a typed Resource has no static `caliber` member
	var known := calibers
	if not caliber_check:
		known = PackedStringArray()
		if cal != null:
			known.append(String(cal))
	var lines: PackedStringArray = calc.weapon_lines(wd)
	var warns: PackedStringArray = calc.weapon_warnings(wd, known)
	return {
		"path": path,
		"name": _resource_label(wd, path),
		"caliber": "" if cal == null else String(cal),
		"lines": lines,
		"warnings": warns,
	}


## `lt` is typed Resource for the same reason as _weapon_block's `wd`.
static func _loot_block(path: String, lt: Resource, loot_calc: Variant, rolls: int, rng_seed: int) -> Dictionary:
	# tally() keys its result by the Item OBJECT — never JSON-safe — so each row is re-keyed to a label + the
	# item's res:// path here, and the derived percentages the inspector card prints are computed alongside.
	var tallied: Dictionary = loot_calc.tally(lt, rolls, rng_seed)
	var rows: Array = []
	for item in tallied:
		var t: Dictionary = tallied[item]
		var hits := int(t.get("hits", 0))
		var total := int(t.get("total", 0))
		rows.append({
			"item": _object_label(item),
			"item_path": _object_ref(item),
			"hits": hits,
			"count_total": total,
			"pct_of_rolls": 100.0 * float(hits) / float(rolls),
			"avg_per_roll": float(total) / float(rolls),
		})
	# The AUTHORED side of the table, compactly. It belongs here and not in `describe` because LootEntry rows are
	# EMBEDDED sub-resources with no res:// path of their own — describe can only report them as opaque handles.
	var src: Variant = lt.get("entries")  # duck-typed read (lt is typed Resource); a mid-edit resource may have none
	var rows_in: Array = src if src is Array else []
	var entries: Array = []
	var i := 0
	for e in rows_in:
		if e == null:
			entries.append({"index": i, "item": null, "note": "null entry — drops nothing"})
		else:
			entries.append({
				"index": i,
				"item": _object_label(e.item),
				"item_path": _object_ref(e.item),
				"min_count": e.min_count,
				"max_count": e.max_count,
				"chance": e.chance,
			})
		i += 1
	return {
		"path": path,
		"name": _resource_label(lt, path),
		"entry_count": rows_in.size(),
		"entries": entries,
		"drops": rows,
	}


# ──────────────────────────────────────────────────────────────────────────────────────────────────────────────
# VERB: list — content inventory by type
# ──────────────────────────────────────────────────────────────────────────────────────────────────────────────

## What content actually exists, grouped by designer-facing type (Quests / NPCs / Weapons / Items / …), via the
## Content Browser's own pure scan. The folder table is READ OFF content_browser.gd's ROOTS const rather than
## copied, so this can never drift from the browser the user clicks in the editor.
##
## `type` narrows to one group (case-insensitive); `filter` is a case-insensitive substring over the basename or
## the full path. NOTE the filter DROPS groups that end up empty (browse_scan.filter_grouped's documented
## behaviour) while an unfiltered scan keeps every group so "Quests (0)" is still visible.
static func _list(args: Dictionary) -> Dictionary:
	var warnings: Array = []
	_warn_unknown_args(args, ["type", "filter"], warnings)
	var errors: Array = []
	var type_arg := _str_arg(args, "type", "", errors).strip_edges()
	var needle := _str_arg(args, "filter", "", errors).strip_edges()
	if not errors.is_empty():
		return _fail(String(errors[0]), warnings)

	var browser := load(CONTENT_BROWSER_PATH) as GDScript
	if browser == null:
		return _fail("could not load the content browser at %s (its ROOTS const is the folder source of truth)" % CONTENT_BROWSER_PATH, warnings)
	var consts: Dictionary = browser.get_script_constant_map()
	if not consts.has("ROOTS"):
		return _fail("%s has no ROOTS const — the content browser changed shape" % CONTENT_BROWSER_PATH, warnings)
	var all_roots: Dictionary = consts["ROOTS"]

	var roots := all_roots
	if type_arg != "":
		roots = {}
		for label in all_roots:
			if String(label).to_lower() == type_arg.to_lower():
				roots[String(label)] = String(all_roots[label])
		if roots.is_empty():
			return _fail("unknown type '%s' — known types: %s" % [type_arg, ", ".join(PackedStringArray(all_roots.keys()))], warnings)

	var scan: Variant = _module(BROWSE_SCAN_PATH, &"scan_grouped")
	if scan == null:
		return _fail("could not load the content scanner at %s (missing, or it failed to compile)" % BROWSE_SCAN_PATH, warnings)
	var grouped: Dictionary = scan.scan_grouped(roots)
	if needle != "":
		grouped = scan.filter_grouped(grouped, needle)

	var counts: Dictionary = {}
	var total := 0
	for label in grouped:
		var group_paths: Array = grouped[label]
		counts[String(label)] = group_paths.size()
		total += group_paths.size()
	# An empty inventory is never good news. Unfiltered it means the content folders moved out from under ROOTS —
	# a caller reading a bare `total: 0` would conclude the project has no content, so name which case this is.
	if total == 0:
		if needle != "":
			warnings.append("filter '%s' matched no resources" % needle)
		else:
			warnings.append("no resources found in any of the %d scanned folder(s) — has the content tree moved out from under content_browser.ROOTS?" % roots.size())
	return _ok({
		"types": all_roots.keys(),
		"type_filter": type_arg,
		"filter": needle,
		"total": total,
		"counts": counts,
		"groups": grouped,
	}, warnings)


# ──────────────────────────────────────────────────────────────────────────────────────────────────────────────
# VERB: describe — one resource's AUTHORED fields
# ──────────────────────────────────────────────────────────────────────────────────────────────────────────────

## What a designer actually authored into one .tres/.tscn. Only SCRIPT-DECLARED, PROPERTY_USAGE_STORAGE properties
## are emitted — never the whole engine property set, which would bury the six fields that matter under fifty
## inherited Resource/Node knobs. The script chain is walked (get_base_script) so a resource extending another
## custom resource still reports its inherited @exports.
##
## Values are JSON-safe by construction: a nested Resource becomes its res:// path (or an opaque "<script>" handle
## when it is an embedded sub-resource with no path of its own).
static func _describe(args: Dictionary) -> Dictionary:
	var warnings: Array = []
	_warn_unknown_args(args, ["path"], warnings)
	var errors: Array = []
	var path := _str_arg(args, "path", "", errors).strip_edges()
	if not errors.is_empty():
		return _fail(String(errors[0]), warnings)
	if path.is_empty():
		return _fail("describe requires arg 'path' — the res:// resource to describe", warnings)
	if not path.begins_with("res://"):
		return _fail("arg 'path' must be a res:// path (got '%s')" % path, warnings)
	if not ResourceLoader.exists(path):
		return _fail("no resource at %s" % path, warnings)

	var res: Resource = load(path)
	if res == null:
		# A null load is NOT a clean "nothing to report" — refuse to claim success over a file we never read.
		warnings.append("%s loaded as null — %s" % [path, REIMPORT_WARNING])
		return _fail("could not load %s" % path, warnings, {"path": path, "skipped_reimport_in_flight": true})

	if res is PackedScene:
		return _describe_packed_scene(path, res as PackedScene, warnings)

	var declared := _script_declared_names(res)
	var props: Array = []
	for p: Dictionary in res.get_property_list():
		var pname := String(p.get("name", ""))
		var usage := int(p.get("usage", 0))
		if not declared.has(pname):
			continue
		if (usage & PROPERTY_USAGE_STORAGE) == 0:
			continue
		props.append({
			"name": pname,
			"type": type_string(int(p.get("type", TYPE_NIL))),
			"value": res.get(pname),
		})
	if props.is_empty():
		warnings.append("%s has no script-declared storage properties (is it a plain engine resource, or a .gd script?)" % path)
	return _ok({
		"path": path,
		"class": res.get_class(),
		"script": _object_ref(res.get_script()),
		"resource_name": res.resource_name,
		"property_count": props.size(),
		"properties": props,
	}, warnings)


## A .tscn has no authored property set of its own — what a caller wants is "is this scene real, and what is its
## root?". Node COUNT is read off the packed state instead of instantiating: instantiating runs scene-construction
## work this read-only tool has no business doing, and 0 nodes is exactly the mid-reimport signature we must
## refuse to report as success.
static func _describe_packed_scene(path: String, ps: PackedScene, warnings: Array) -> Dictionary:
	var state := ps.get_state()
	var count := state.get_node_count() if state != null else 0
	var data := {
		"path": path,
		"class": "PackedScene",
		"node_count": count,
		"root_name": String(state.get_node_name(0)) if count > 0 else "",
		"root_type": String(state.get_node_type(0)) if count > 0 else "",
	}
	if count <= 0:
		data["skipped_reimport_in_flight"] = true
		warnings.append("%s instantiates empty (0 nodes) — %s" % [path, REIMPORT_WARNING])
		return _fail("%s has no nodes — refusing to report it as read" % path, warnings, data)
	return _ok(data, warnings)


## The set of property names DECLARED BY SCRIPT on `obj`, walking the whole script chain (a resource may extend
## another custom resource). Returned as a Dictionary used as a set — Dictionary.has() beats an Array scan when
## the caller checks it once per engine property.
static func _script_declared_names(obj: Object) -> Dictionary:
	var out: Dictionary = {}
	var s: Script = obj.get_script() as Script
	while s != null:
		for p: Dictionary in s.get_script_property_list():
			out[String(p.get("name", ""))] = true
		s = s.get_base_script()
	return out


# ──────────────────────────────────────────────────────────────────────────────────────────────────────────────
# Result builders + argument helpers
# ──────────────────────────────────────────────────────────────────────────────────────────────────────────────

static func _ok(data: Variant, warnings: Array = []) -> Dictionary:
	return {"ok": true, "data": data, "error": "", "warnings": warnings}


## A clean failure. `data` is still carried when there IS a partial payload worth returning (an incomplete audit,
## a half-read graph) — ok:false is the honest verdict, but the caller shouldn't lose what was actually gathered.
static func _fail(message: String, warnings: Array = [], data: Variant = null) -> Dictionary:
	return {"ok": false, "data": data, "error": message, "warnings": warnings}


## Warn (never fail) on an arg key the verb doesn't know. A typo'd key would otherwise be silently ignored and the
## caller would spend a 7.7s headless boot wondering why the filter did nothing.
static func _warn_unknown_args(args: Dictionary, allowed: Array, warnings: Array) -> void:
	for key in args:
		if not allowed.has(String(key)):
			warnings.append("ignored unknown arg '%s' — this verb accepts: %s" % [
				String(key), ", ".join(PackedStringArray(allowed)) if not allowed.is_empty() else "(none)",
			])


## Read a String arg. Accepts String / StringName; anything else appends to `errors` (the caller turns the first
## error into an ok:false result) rather than coercing a number into a path and failing mysteriously later.
static func _str_arg(args: Dictionary, key: String, def: String, errors: Array) -> String:
	if not args.has(key):
		return def
	var v: Variant = args[key]
	if v == null:
		return def
	if typeof(v) == TYPE_STRING or typeof(v) == TYPE_STRING_NAME:
		return String(v)
	errors.append("arg '%s' must be a string (got %s)" % [key, type_string(typeof(v))])
	return def


## Read an int arg. The CLI passes EVERY value as a String (`--arg:limit=20`) while a --batch JSON file yields real
## numbers (and JSON numbers parse as float), so all three forms are accepted here — this is the single place that
## difference is absorbed.
static func _int_arg(args: Dictionary, key: String, def: int, errors: Array) -> int:
	if not args.has(key):
		return def
	var v: Variant = args[key]
	if v == null:
		return def
	match typeof(v):
		TYPE_INT, TYPE_FLOAT:
			return int(v)
		TYPE_STRING, TYPE_STRING_NAME:
			var s := String(v).strip_edges()
			if s.is_valid_int():
				return s.to_int()
			if s.is_valid_float():
				return int(s.to_float())
	errors.append("arg '%s' must be a whole number (got '%s')" % [key, str(v)])
	return def


# ──────────────────────────────────────────────────────────────────────────────────────────────────────────────
# Shared read helpers
# ──────────────────────────────────────────────────────────────────────────────────────────────────────────────

## Runtime-load a module script AND prove it can actually serve the call we are about to make. null means "this
## module cannot answer"; every caller turns that into an ok:false carrying a real message, never a silent skip.
##
## TWO failure modes, ONE guard. load() returns null when the file is missing or moved — but it returns a NON-null,
## BROKEN GDScript when the file is present and failed to PARSE, which is a live hazard here: these are addon scripts
## the user edits with the editor open all day. Calling a static on that object is an "Invalid call" ENGINE error, not
## a value this file can catch, and it takes the whole verb (and then run()'s own return) down with it — exactly the
## "degrade, never throw" clause this file exists to honour. has_method() answers from the script's OWN function table
## and therefore SEES STATICS, which is what makes it the right gate. (`Script.has_static_method` does not exist in
## 4.7.1 — it fails with "Nonexistent function 'has_static_method' in base 'GDScript'"; cyber.gd:170-176 documents the
## same verified finding at the run() seam. Don't "fix" it back.)
##
## Modules we read a CONST off instead of calling (catalog.COMPONENTS, content_browser.ROOTS) do NOT come through
## here: a broken GDScript yields an EMPTY constant map, so their existing `consts.has(...)` check already degrades.
static func _module(path: String, method: StringName) -> Variant:
	var script: Variant = load(path)
	if script is GDScript and (script as GDScript).has_method(method):
		return script
	return null


## Every .tres/.res under `dir`, recursively + sorted — via the Content Browser's pure scanner (browse_scan) so
## there is ONE folder-walk implementation in the project rather than a fourth private copy. A missing folder
## yields [] and a warning, never a crash.
static func _resource_paths_in(dir: String, warnings: Array) -> Array:
	var scan: Variant = _module(BROWSE_SCAN_PATH, &"scan_folder")
	if scan == null:
		warnings.append("could not load %s — folder scan of %s skipped" % [BROWSE_SCAN_PATH, dir])
		return []
	var out: Array = scan.scan_folder(dir)
	if out.is_empty() and DirAccess.open(dir) == null:
		warnings.append("no folder at %s" % dir)
	return out


## Is `res` an instance of the script at `script_path` (or of something that extends it)? The dependency-free
## stand-in for `res is SomeClass` — it walks the base-script chain, so a subclass still matches, and it costs
## this file NO compile-time dependency on the class being tested (the whole point: see WEAPON_DATA_SCRIPT).
static func _script_is(res: Resource, script_path: String) -> bool:
	if res == null:
		return false
	var s: Script = res.get_script() as Script
	while s != null:
		if s.resource_path == script_path:
			return true
		s = s.get_base_script()
	return false


## A human label for a resource: its authored display_name when it has one, else the filename stem. Duck-typed
## (`get`) so this works for a WeaponData, a LootTable, an Item or anything else with the field.
static func _resource_label(res: Resource, path: String) -> String:
	if res != null:
		var dn: Variant = res.get("display_name")
		if dn != null and String(dn) != "":
			return String(dn)
		if res.resource_name != "":
			return res.resource_name
	return path.get_file().get_basename()


## A label for an arbitrary Object value (a loot Item, an entry's item): display_name, else the file stem, else
## the class. Freed-instance safe: typeof() then is_instance_valid() — NEVER `is`, which CRASHES on a freed
## instance, and a resource can absolutely be freed out from under us mid-reimport.
static func _object_label(o: Variant) -> String:
	if typeof(o) != TYPE_OBJECT:
		return "(none)"
	if not is_instance_valid(o):
		return "(freed)"
	var obj: Object = o
	var dn: Variant = obj.get("display_name")
	if dn != null and String(dn) != "":
		return String(dn)
	if obj is Resource and (obj as Resource).resource_path != "":
		return (obj as Resource).resource_path.get_file().get_basename()
	return obj.get_class()


## The JSON-safe stand-in for an Object: its res:// path when it has one, else an opaque "<script-or-class>"
## handle (an embedded sub-resource has no path — saying so is more honest than emitting an instance id).
## Same freed-instance ordering as _object_label: typeof() first, then is_instance_valid(), never `is`.
static func _object_ref(o: Variant) -> Variant:
	if typeof(o) != TYPE_OBJECT:
		return null
	if not is_instance_valid(o):
		return "(freed)"
	var obj: Object = o
	if obj is Resource:
		var r := obj as Resource
		if r.resource_path != "":
			return r.resource_path
		var s: Variant = r.get_script()
		if s is Resource and (s as Resource).resource_path != "":
			return "<%s>" % (s as Resource).resource_path.get_file().get_basename()
	return "<%s>" % obj.get_class()


# ──────────────────────────────────────────────────────────────────────────────────────────────────────────────
# JSON safety — the last gate before the payload leaves this file
# ──────────────────────────────────────────────────────────────────────────────────────────────────────────────

## Recursively convert a value into something JSON.stringify can encode AND JSON.parse_string can read back.
## Applied to every verb's `data` in run(), so a scanner or an authored .tres can never hand a StringName,
## Vector3, PackedStringArray, Object or NAN into the CLI's framed output and corrupt the caller's parse.
##
## Deliberate lossy conversions (documented so nobody "fixes" them): Objects become a path/handle string, exotic
## math types (Transform3D, Basis, AABB, RID, Callable) become str(), and a non-finite float becomes its string
## form — Godot's JSON writes a bare `inf`/`nan`, which is not valid JSON and fails on re-parse.
static func _json_safe(v: Variant, depth: int = 0) -> Variant:
	if depth > MAX_JSON_DEPTH:
		return str(v)
	match typeof(v):
		TYPE_NIL, TYPE_BOOL, TYPE_INT, TYPE_STRING:
			return v
		TYPE_FLOAT:
			return v if is_finite(v) else str(v)
		TYPE_STRING_NAME, TYPE_NODE_PATH:
			return String(v)
		TYPE_VECTOR2, TYPE_VECTOR2I:
			return [v.x, v.y]
		TYPE_VECTOR3, TYPE_VECTOR3I:
			return [v.x, v.y, v.z]
		TYPE_VECTOR4, TYPE_VECTOR4I, TYPE_QUATERNION:
			return [v.x, v.y, v.z, v.w]
		TYPE_COLOR:
			return [v.r, v.g, v.b, v.a]
		TYPE_RECT2, TYPE_RECT2I:
			return [v.position.x, v.position.y, v.size.x, v.size.y]
		TYPE_PLANE:
			return [v.normal.x, v.normal.y, v.normal.z, v.d]
		TYPE_OBJECT:
			return _object_ref(v)
		TYPE_DICTIONARY:
			var in_d: Dictionary = v
			var out_d: Dictionary = {}
			for k in in_d:
				# JSON object keys must be strings; a Dictionary keyed by an Object (LootTableInspector.tally does
				# exactly that) would otherwise stringify into something nothing can parse back.
				out_d[str(_json_safe(k, depth + 1))] = _json_safe(in_d[k], depth + 1)
			return out_d
		TYPE_ARRAY, TYPE_PACKED_BYTE_ARRAY, TYPE_PACKED_INT32_ARRAY, TYPE_PACKED_INT64_ARRAY, \
		TYPE_PACKED_FLOAT32_ARRAY, TYPE_PACKED_FLOAT64_ARRAY, TYPE_PACKED_STRING_ARRAY, \
		TYPE_PACKED_VECTOR2_ARRAY, TYPE_PACKED_VECTOR3_ARRAY, TYPE_PACKED_COLOR_ARRAY:
			var out_a: Array = []
			for e in v:
				out_a.append(_json_safe(e, depth + 1))
			return out_a
	return str(v)


## Warnings are contractually an Array of String — normalise whatever a verb collected (a PackedStringArray, a
## StringName) so the caller never has to type-check a warning row.
static func _string_array(v: Variant) -> Array:
	var out: Array = []
	if v is Array or v is PackedStringArray:
		for e in v:
			out.append(String(e))
	elif v != null:
		out.append(String(v))
	return out
