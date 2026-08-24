@tool
extends VBoxContainer

## CYBER SUNDAY -> Reach: a READ-ONLY report answering the one question nothing else in this project answers —
## "what can a PLAYER actually reach from the boot scene?"
##
## Stats asks "is X referenced by ANY file?"; Audit resolves quest-id STRINGS. Both report clean on a project whose
## quests are all unreachable: resources/quests/recover_the_package.tres is wired to a QuestStarter inside
## scenes/levels/SliceTestLevel.tscn, and nothing anywhere points at SliceTestLevel.tres — so Stats calls that quest
## healthy forever and no player can ever start it. Reach walks the transitive closure from the BOOT ROOTS
## (project.godot's main_scene + every autoload) and reports what falls OUTSIDE it.
##
## THIS FILE IS THE THIN GLUE — every decision lives in reach_scan.gd, which is PURE (plain RefCounted, statics, no
## EditorInterface, no scene tree, no DirAccess) and GUT-driven on fixture strings. The glue owns exactly four
## editor-shaped things and nothing else: the roots read (ProjectSettings), the recursive res:// walk, the Tree
## render, and the double-click jump. Same split as content_stats.gd + stats_view.gd.
##
## READ-ONLY, and it must stay that way. No ResourceSaver, no FileAccess.WRITE, no ProjectSettings.save anywhere
## below — so the plugin's write contract (preview / confirm / report changed paths) does not apply and cannot be
## got wrong. The single editor mutation in the file is EditorInterface.edit_resource + select_file on a
## double-click, which opens a file in the Inspector and writes nothing.
##
## The survey is TEXT-ONLY on purpose: the designer usually has the editor open, and a load() during a reimport can
## hand back null or an empty PackedScene ("node count is 0"). A report built over a file nobody could read is the
## exact lie this tab exists to catch, so an unreadable file becomes a SKIP row, never a silent clean result.
##
## ------------------------------------------------------------------------------------------------------------
## HOW TO READ AN ALL-GREEN RESULT: with suspicion. This project has a scar precisely here — text_debt.gd once
## printed "TOTAL: 0" while 132 of 267 strings were unauthored placeholders. An empty Reach report is far more
## likely to mean the scan UNDER-fired (the folder-scan guard over-approximated, or the walk surveyed nothing) than
## that the game is fully wired. That is why the status line always prints the DENOMINATORS it scanned — roots,
## files reached, files surveyed, folder-scan roots, unresolved sites — beside what it found, prefixes SUSPECT when
## a denominator is degenerate, AND repeats that verdict as the first row INSIDE the scrolled body (the status Label
## is the one control this tab cannot height-bound, so on a narrow panel it is the one that gets squeezed; the
## warning must survive that). "0 problems out of 0 things looked at" and "0 problems out of 378 things looked at"
## must never read the same. Never "fix" a suspiciously clean report by widening a guard; go find what the scan
## failed to walk.

const Reach := preload("res://addons/cybersunday_tools/dock_reach/reach_scan.gd")
## The audit panel's one-read-per-file cache. Its text_of is passed STRAIGHT into the closure as the injected
## reader, and this tab deliberately does NOT open a begin()/end() window around it: that singleton has exactly ONE
## window, both scans are synchronous on the editor's main thread (so there is no dedupe to win), and a Reach end()
## landing inside an Audit window would wipe the audit's cache mid-scan. Outside a window text_of is a plain
## read-through to disk, which is the correct standalone behaviour here.
const ScanCache := preload("res://addons/cybersunday_tools/panel_audit/scan_cache.gd")

## .godot is derived and .git is history — neither holds authored references. addons/ IS walked, the same judgement
## ref_scan.gd:14 records: an addon scene can legitimately carry a QuestStarter, and a start site the survey never
## reads would report a wired quest as unwired — a false alarm we would rather not manufacture.
const SKIP_DIRS: Array[String] = [".godot", ".git"]

## The survey opens SERIALIZED files only. Every survey question — a `script_class="…"` header, a LevelData.scene,
## a quest start site — is a .tscn/.tres notion; a .gd carries none of them, and skipping ~1000 scripts here is the
## difference between a snappy button and a stall. (The CLOSURE still reads .gd for the paths it actually pops:
## reach_scan.SCANNED_EXTS includes "gd" because scripts/ui/computerroom.gd's bare res:// const is the only link
## out of the boot scene. Different question, different file set.)
const SURVEY_EXTS: Array[String] = ["tscn", "tres"]

## Every .tscn directly under here joins the level roster even when no LevelData points at it, so an authored-but-
## unwired level reads as UNREACHABLE instead of quietly vanishing from the report.
const LEVELS_DIR := "res://scenes/levels"

## PRE-GATE for the quest-start-site pass, and it is EXACT rather than a heuristic: all three start fields
## (QuestStarter.quest / TriggerVolume.start_quest / DialogueChoice.start_quest_on_choice) are matched by
## reach_scan.quest_start_sites anchored at line start in lower case, so a file whose text does not contain this
## substring cannot possibly hold one. Skipping the pass on those files is free correctness-wise and enormous
## performance-wise: quest_start_sites splits the text into `[node]`/`[sub_resource]` blocks and compiles one RegEx
## per block per field, and this project holds ~5000 such blocks across ~380 serialized files (trenchboom_test_level
## .tscn alone is 1129) while only EIGHT of those files mention a quest at all. Performance is a correctness
## constraint on this tab — the whole scan runs synchronously on the editor's main thread off a button press.
const QUEST_FIELD_SUBSTRING := "quest"

## One-line header gates (reach_scan.declares_script_class) — a text test, so identifying a .tres costs one read
## and never a load(). These are the `script_class="…"` values Godot writes for level_data.gd / quest.gd /
## dialogue_resource.gd; they are the SERIALIZED spelling of those class_names, so a rename must update both.
const CLASS_LEVEL_DATA := "LevelData"
const CLASS_QUEST := "Quest"
const CLASS_DIALOGUE := "DialogueResource"

## Height floor for the scrolled body. The bottom-panel TabContainer sizes itself to its TALLEST tab, and this
## plugin has twice shipped a tab that pushed the editor's panel past the screen — so the body's minimum is small
## and fixed, and the head + status rows live OUTSIDE the scroll where they are always readable.
const BODY_MIN_HEIGHT := 110.0

const COLOR_HEAD := Color(0.6, 0.85, 1.0)
const COLOR_OK := Color(0.55, 0.9, 0.55)
const COLOR_WARN := Color(1.0, 0.82, 0.3)
const COLOR_ERROR := Color(1.0, 0.42, 0.42)
const COLOR_DIM := Color(0.72, 0.72, 0.72)

var _tree: Tree = null
var _status: Label = null

## Start sites whose ExtResource id resolved to no `path=` row (a uid-only ext_resource row). Kept so they can be
## SHOWN rather than dropped: a dropped site would silently downgrade a wired quest to "NO START SITE", and an
## invented finding is how a report loses a designer's trust.
var _unresolved_sites: Array = []

## PL6 lazy first-reveal latch: the project walk runs the first time the tab is actually SHOWN, not at panel
## construction. cyber_panel builds every tab eagerly on each plugin reload, so without this a plugin toggle would
## fan out a full res:// walk for a tab nobody clicked. Only the selected tab is visible, so "first reveal" means
## "the first time the designer opens Reach"; Rescan re-runs it on demand after that.
var _revealed := false


func _init() -> void:
	name = "Reach"
	add_theme_constant_override("separation", 4)

	# --- head: OUTSIDE the scroll, so the controls never scroll out from under the user -------------------------
	var bar := HBoxContainer.new()
	var rescan := Button.new()
	rescan.text = "Rescan"
	rescan.tooltip_text = "Trace what the boot scene reaches: main_scene + every autoload, then every res:// reference transitively. Read-only — reports, writes nothing."
	rescan.pressed.connect(_rescan)
	bar.add_child(rescan)
	add_child(bar)

	# The status line is its OWN full-width row (not wedged beside the button) and autowraps, so the long
	# denominators-and-findings sentence wraps across the panel instead of shoving the button off the right edge.
	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_status.modulate = Color(1, 1, 1, 0.75)
	add_child(_status)

	# --- body: bounded + scrolled -------------------------------------------------------------------------------
	# The Tree carries its own scrollbars, so this ScrollContainer is the HEIGHT FENCE, not a second scroller: its
	# custom_minimum_size is the only vertical minimum this tab contributes to the TabContainer, no matter how many
	# findings the Tree holds. The Tree keeps SIZE_EXPAND_FILL, which a Godot 4 ScrollContainer honours by stretching
	# an expanding child to the container's size — so the Tree fills the panel and the outer scroll never engages.
	# Horizontal scrolling is DISABLED because a long res:// path must never widen the bottom panel; the Tree elides
	# and scrolls those rows internally, and every row carries its full text as a tooltip.
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.custom_minimum_size = Vector2(0, BODY_MIN_HEIGHT)
	add_child(scroll)

	_tree = Tree.new()
	_tree.hide_root = true
	_tree.select_mode = Tree.SELECT_ROW
	_tree.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_tree.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_tree.custom_minimum_size = Vector2(0, 90)  # small floor, mirroring stats_view / audit_panel
	_tree.item_activated.connect(_on_activated)  # double-click / Enter
	scroll.add_child(_tree)

	_status.text = "Click Rescan to trace what the boot scene reaches."

	visibility_changed.connect(_on_visibility_changed)
	_on_visibility_changed()  # lazy: scan on first reveal, not at panel construction


## Lazy first-reveal: run the project walk ONCE, the first time the tab is actually shown in the tree.
func _on_visibility_changed() -> void:
	if is_visible_in_tree() and not _revealed:
		_revealed = true
		_rescan()


# ================================================================================================================
# THE SCAN
# ================================================================================================================

## One pass: read the boot roots, survey the serialized files on disk, run the closure, render the report.
func _rescan() -> void:
	var roots := boot_roots()
	var survey := _survey()
	var found: Dictionary = survey["found"]
	_unresolved_sites = survey["unresolved"]

	# text_of is passed STRAIGHT in (no begin()/end() window — see the ScanCache const comment). The closure pulls
	# text only for the paths it POPS, which is why an empty uid_index and a live Callable beat materialising a
	# {path: text} map of the project: addons/text_to_speech/voices/ alone is 59 MB of binary .res.
	# The empty uid_index lets the ENGINE's ResourceUID answer every uid — the two uid-only autoloads included.
	var cl := Reach.closure(roots, ScanCache.text_of, {}, _dir_members)
	var report := Reach.build_report(cl, found)
	_render(report, roots.size(), int(survey["surveyed"]))


## The boot roots: project.godot's main_scene plus EVERY autoload, read through ProjectSettings rather than by
## parsing the INI ourselves. The engine's own reader already handles both spellings this project actually uses —
## the `*res://…` singleton marker and the two uid-ONLY autoloads (FreezeFrame, DialogueManager) — and this project
## rejects custom tooling where Godot ships the built-in. reach_scan.normalize_ref strips the `*` and resolves the
## uid, so the raw setting values are handed over untouched.
static func boot_roots() -> Array:
	var out: Array = []
	var main := str(ProjectSettings.get_setting("application/run/main_scene", ""))
	if not main.is_empty():
		out.append(main)
	for prop in ProjectSettings.get_property_list():
		var prop_name := str((prop as Dictionary).get("name", ""))
		if not prop_name.begins_with("autoload/"):
			continue
		var value := str(ProjectSettings.get_setting(prop_name, ""))
		if not value.is_empty():
			out.append(value)
	return out


## Walk res:// once and answer every question reach_scan needs about what is AUTHORED on disk (as opposed to what
## is REACHED, which is the closure's job). Returns {found, surveyed, unresolved}:
##   found      the bundle build_report consumes (see its docstring for the key contract)
##   surveyed   how many serialized files were actually read — the denominator that tells an empty report from a
##              clean one, and the reason the status line can say "0 problems out of 378 looked at"
##   unresolved start sites whose ExtResource id had no resolvable `path=` row, kept for display
func _survey() -> Dictionary:
	var files: Array = []
	_walk("res://", files)

	var levels_wired: Array = []
	var levels_authored: Array = []
	var quests: Array = []
	var quest_sites := {}
	var quest_next := {}
	var dialogue: Array = []
	var skipped: Array = []
	var unresolved: Array = []
	var surveyed := 0

	for f in files:
		var path := str(f)
		if path.get_extension() == "tscn" and path.get_base_dir() == LEVELS_DIR:
			levels_authored.append(path)
		var text := ScanCache.text_of(path)
		if text.is_empty():
			# Unreadable, or mid-reimport. Surfaced as a SKIP: a file nobody read cannot be evidence of anything,
			# least of all of a clean project.
			skipped.append(path)
			continue
		surveyed += 1

		# Quest START sites, project-wide and INVERTED to {quest: [{file, field, label}]}. `file` is what the
		# reachability test keys on — a start site only counts if the file HOLDING it is itself reachable.
		# PRE-GATED on QUEST_FIELD_SUBSTRING (see that const): an exact skip, not a sampling heuristic, and the
		# difference between a snappy button and a multi-second stall on the editor's main thread.
		var sites: Array = Reach.quest_start_sites(text) if QUEST_FIELD_SUBSTRING in text else []
		for site in sites:
			var sd := site as Dictionary
			var quest_path := str(sd.get("path", ""))
			var label := str(sd.get("label", ""))
			if quest_path.is_empty():
				unresolved.append("%s in %s (ExtResource \"%s\" — no path= row)" % [label, path, str(sd.get("id", ""))])
				continue
			if not quest_sites.has(quest_path):
				quest_sites[quest_path] = []
			(quest_sites[quest_path] as Array).append({
				"file": path, "field": str(sd.get("field", "")), "label": label,
			})

		if path.get_extension() != "tres":
			continue
		if Reach.declares_script_class(text, CLASS_LEVEL_DATA):
			# The .tscn a LevelData points at. The closure follows that ExtResource edge on its own; this only
			# labels the roster row as WIRED, so "authored, never wired" and "wired, never loaded" stay distinct.
			var scene := Reach.resource_field_ref(text, "scene")
			if not scene.is_empty():
				levels_wired.append(scene)
		elif Reach.declares_script_class(text, CLASS_QUEST):
			quests.append(path)
			var chained := Reach.resource_field_ref(text, "next_quest")
			if not chained.is_empty():
				quest_next[path] = chained
		elif Reach.declares_script_class(text, CLASS_DIALOGUE):
			dialogue.append(path)

	return {
		"found": {
			"levels_wired": levels_wired,
			"levels_authored": levels_authored,
			"quests": quests,
			"quest_sites": quest_sites,
			"quest_next": quest_next,
			"dialogue": dialogue,
			"skipped": skipped,
		},
		"surveyed": surveyed,
		"unresolved": unresolved,
	}


## Recursive res:// walk collecting the SURVEY_EXTS files. `.remap` is trimmed (an exported build appends it) so a
## path matches what the serialized references actually spell.
func _walk(dir: String, out_files: Array) -> void:
	var d := DirAccess.open(dir)
	if d == null:
		return
	d.list_dir_begin()
	var entry := d.get_next()
	while entry != "":
		if not entry.begins_with("."):
			var full := dir.path_join(entry)
			if d.current_is_dir():
				if not SKIP_DIRS.has(entry):
					_walk(full, out_files)
			else:
				var trimmed := full.trim_suffix(".remap")
				if SURVEY_EXTS.has(trimmed.get_extension()):
					out_files.append(trimmed)
		entry = d.get_next()
	d.list_dir_end()


## The res:// files DIRECTLY under `dir` (non-recursive — content folders here are flat), injected into the closure
## so a folder-scan root that fired can mark its members reachable. This is the FALSE-POSITIVE guard's disk half:
## without it ItemDb's items, the factions and the filename-resolved abilities would all be condemned, because
## nothing references them by path. [] for a folder that is not on disk.
##
## `.import` and `.uid` sidecars are skipped: both are engine metadata for a file already listed beside them, so
## marking one reached would inflate the closure's count and the "sparing N file(s)" receipt without naming
## anything a designer can act on. (A scanned folder holding .gd files — abilities resolve by filename — is exactly
## where the .gd.uid sidecars would otherwise double the count.)
func _dir_members(dir: String) -> Array:
	var out: Array = []
	var d := DirAccess.open(dir)
	if d == null:
		return out
	for f in d.get_files():
		var fname := str(f).trim_suffix(".remap")
		var ext := fname.get_extension()
		if fname.begins_with(".") or ext == "import" or ext == "uid":
			continue
		out.append(dir.path_join(fname))
	return out


# ================================================================================================================
# THE RENDER
# ================================================================================================================

## Paint one report. Tree.clear() drops every TreeItem the previous run built, so there is no Control container to
## rebuild here (and therefore no remove_child-before-queue_free ordering to get wrong).
func _render(report: Dictionary, roots_n: int, surveyed: int) -> void:
	_tree.clear()
	var root := _tree.create_item()
	var counts: Dictionary = report.get("counts", {})
	var suspect := _is_suspect(counts, roots_n, surveyed)

	# The SUSPECT verdict is repeated as the FIRST row inside the scrolled body, not left to the status Label alone.
	# The head rows sit OUTSIDE the scroll (so the controls never scroll away), which means the Label is the one
	# control this tab cannot height-bound: on a narrow bottom panel it wraps, and it is the first thing a designer
	# squeezes. The one sentence that must never be lost is "this is evidence of a broken scan", so it lives here too,
	# where the ScrollContainer bounds it and it reads before every count below it.
	if suspect:
		var banner := _row(root, "SUSPECT — a denominator below is degenerate: this report is evidence of a broken scan, not of a clean project.", COLOR_ERROR)
		_row(banner, "Check the boot roots and the res:// walk before believing any row. Do NOT widen the folder-scan guard to make it go green — go find what the scan failed to walk.", COLOR_ERROR)

	_render_chain(root, report, counts)
	_render_levels(root, report, counts)
	_render_quests(root, report, counts)
	_render_dialogue(root, report, counts)
	_render_folder_roots(root, report, counts)
	_render_skips(root, report, counts)

	var full_chain: Array = report.get("chain_full", [])
	_status.text = _status_text(counts, roots_n, surveyed, full_chain.size(), suspect)
	# Horizontal scrolling is disabled and the panel can be narrow, so the whole line is also the tooltip — a wrapped
	# or clipped denominator is still readable in full on hover.
	_status.tooltip_text = _status.text
	_status.modulate = Color(1, 0.7, 0.7) if suspect else Color(1, 1, 1, 0.75)


## The chain the closure actually FOLLOWED, printed. A reachability gauge nobody can audit is a green light nobody
## should trust — so the readable content chain heads the report (under the SUSPECT banner, when there is one), and
## the full chain (including the .gd glue scripts that carried each edge) hangs underneath it for anyone checking
## the tab's work.
func _render_chain(root: TreeItem, report: Dictionary, counts: Dictionary) -> void:
	var chain: Array = report.get("chain", [])
	var full: Array = report.get("chain_full", [])
	# build_report aims the printed chain at the SHALLOWEST REACHABLE LEVEL, and falls back to the deepest file the
	# walk touched when no level is reachable at all. That fallback is NOT a boot chain and must never be read as
	# one — an unlabelled fallback is precisely the "green gauge nobody should trust" this section exists to prevent.
	var leaf := str(report.get("chain_leaf", ""))
	var fallback := not chain.is_empty() and _int(counts, "levels_reachable") == 0
	var title := ("Boot chain: %d hop(s)" % chain.size()) if leaf.is_empty() else ("Boot chain to %s: %d hop(s)" % [leaf, chain.size()])
	if fallback:
		title += "  — FALLBACK: no level is reachable, so this is the deepest path the walk followed, NOT a route to a playable level"
	var head_color := COLOR_ERROR
	if not chain.is_empty():
		head_color = COLOR_WARN if fallback else COLOR_HEAD
	var head := _row(root, title, head_color, (leaf if not leaf.is_empty() else null))
	if chain.is_empty():
		_row(head, "NOTHING REACHED — the roots resolved to no file. That is a scan failure, not a clean project.", COLOR_ERROR)
		return
	for i in chain.size():
		var path := str(chain[i])
		var arrow := "" if i == 0 else "-> "
		_row(head, arrow + path, COLOR_OK, path)
	head.set_collapsed(false)
	var detail := _row(head, "full chain incl. .gd glue: %d hop(s)" % full.size(), COLOR_DIM)
	detail.set_collapsed(true)
	for p in full:
		_row(detail, str(p), COLOR_DIM, str(p))


func _render_levels(root: TreeItem, report: Dictionary, counts: Dictionary) -> void:
	var levels: Array = report.get("levels", [])
	var reachable := _int(counts, "levels_reachable")
	var total := _int(counts, "levels_total")
	var head := _row(root, "Levels: %d of %d reachable" % [reachable, total], _head_color(total > 0 and reachable > 0))
	for row in levels:
		var r := row as Dictionary
		var path := str(r["path"])
		var ok := bool(r["reachable"])
		# The note names the ACTIONABLE difference: a wired-but-unloaded level needs something to point at its
		# LevelData; an unwired one needs a LevelData at all. Collapsing both to "unreachable" hides the fix.
		var note := "depth %d, via %s" % [int(r["depth"]), str(r["via"])]
		if not ok:
			note = "wired to a LevelData, but nothing loads that LevelData" if bool(r["wired"]) else "authored, no LevelData points at it"
		_row(head, "%s  %s  (%s)" % ["REACHABLE  " if ok else "UNREACHABLE", path, note], COLOR_OK if ok else COLOR_WARN, path)


## Quests, the reason the tab exists. TWO axes, three verdicts, and each row carries its start sites so the fix is
## obvious from the report alone: NO START SITE means "wire it", START SITE NOT REACHABLE means "its HOST is the
## problem, not the wiring".
func _render_quests(root: TreeItem, report: Dictionary, counts: Dictionary) -> void:
	var quests: Array = report.get("quests", [])
	var ok := _int(counts, "quests_ok")
	var total := _int(counts, "quests_total")
	var head := _row(root, "Quests: %d of %d OK  (%d no start site, %d unreachable start)" % [
		ok, total, _int(counts, "quests_no_start"), _int(counts, "quests_unreachable_start"),
	], _head_color(total > 0 and ok == total))
	for row in quests:
		var q := row as Dictionary
		var verdict := str(q["verdict"])
		var path := str(q["path"])
		var color := COLOR_OK
		if verdict == Reach.VERDICT_NO_START:
			color = COLOR_ERROR
		elif verdict == Reach.VERDICT_UNREACHABLE_START:
			color = COLOR_WARN
		var item := _row(head, "%s — %s" % [verdict, path], color, path)
		var sites: Array = q.get("sites", [])
		if sites.is_empty():
			_row(item, "no %s / %s / %s anywhere in the project — nothing can start it" % [
				Reach.QUEST_START_OWNERS["quest"], Reach.QUEST_START_OWNERS["start_quest"],
				Reach.QUEST_START_OWNERS["start_quest_on_choice"],
			], COLOR_DIM)
			continue
		for s in sites:
			var sd := s as Dictionary
			var file := str(sd["file"])
			var site_ok := bool(sd["reachable"])
			_row(item, "%s in %s — %s" % [str(sd["label"]), file, "REACHED" if site_ok else "NOT REACHED"],
				COLOR_OK if site_ok else COLOR_WARN, file)
	if not _unresolved_sites.is_empty():
		# Shown, never dropped: an unresolvable site would otherwise downgrade a wired quest to NO START SITE.
		var un := _row(head, "Start sites that resolved to no file: %d" % _unresolved_sites.size(), COLOR_WARN)
		for u in _unresolved_sites:
			_row(un, str(u), COLOR_WARN)


func _render_dialogue(root: TreeItem, report: Dictionary, counts: Dictionary) -> void:
	var dialogue: Array = report.get("dialogue", [])
	var reachable := _int(counts, "dialogue_reachable")
	var total := _int(counts, "dialogue_total")
	var head := _row(root, "Dialogue: %d of %d reachable" % [reachable, total], _head_color(total > 0 and reachable > 0))
	for row in dialogue:
		var d := row as Dictionary
		var path := str(d["path"])
		var ok := bool(d["reachable"])
		var note := "via %s" % str(d["via"])
		if not ok:
			note = "no reachable NPC / Talkable / level points at it"
		_row(head, "%s  %s  (%s)" % ["REACHABLE  " if ok else "UNREACHABLE", path, note], COLOR_OK if ok else COLOR_WARN, path)


## The folder-scan guard's receipt. Printing which roots fired — and which file DECLARED each one — is what makes
## the guard auditable: if this section is suspiciously long, the guard over-approximated and swallowed real
## orphans, and THAT is the thing to go fix (never by widening it further).
func _render_folder_roots(root: TreeItem, report: Dictionary, counts: Dictionary) -> void:
	var roots: Array = report.get("folder_roots", [])
	# Amber at ZERO, by the same rule as every other section head: an empty section is a scan smell, not a pass.
	# Here it is provably so — ItemDb is an AUTOLOAD (project.godot [autoload] ItemDb="*res://scripts/items/item_db.gd"),
	# hence a boot root, hence scripts/items/item_db.gd is always popped and its DirAccess.open(ITEMS_DIR) always
	# fires res://resources/items. Zero roots therefore means the walk never reached an autoload, not that the
	# project scans no folders.
	var head := _row(root, "Folder-scan roots that fired: %d  (sparing %d file(s) from the orphan list)" % [
		roots.size(), _int(counts, "folder_scan_members"),
	], _head_color(not roots.is_empty()))
	for row in roots:
		var r := row as Dictionary
		var declared := str(r["declared_by"])
		_row(head, "%s — declared by %s" % [str(r["dir"]), declared], COLOR_DIM, declared)


## Files nobody could read. Never silent: a clean report built over an unread file is the failure mode this tab
## exists to catch, and a mid-reimport read returning "" is routine with the editor open (retry the Rescan).
func _render_skips(root: TreeItem, report: Dictionary, counts: Dictionary) -> void:
	var skipped: Array = report.get("skipped", [])
	var n := _int(counts, "skipped")
	if n == 0:
		return
	var head := _row(root, "Skipped — unreadable when scanned: %d  (usually a reimport in flight; Rescan)" % n, COLOR_WARN)
	for p in skipped:
		_row(head, str(p), COLOR_WARN, str(p))


# ================================================================================================================
# STATUS — the line that must make an all-green result look SUSPICIOUS
# ================================================================================================================

## Always print the DENOMINATORS beside the findings. "0 unreachable quests" is meaningless without "of 2 quests
## found, from 378 files surveyed, 412 files reached from 15 roots" — with the denominators, a scan that walked
## nothing is instantly distinguishable from a project that is genuinely wired, and that distinction IS the
## acceptance bar for this tab.
func _status_text(counts: Dictionary, roots_n: int, surveyed: int, full_chain_hops: int, suspect: bool) -> String:
	var parts := PackedStringArray([
		# "full chain" is the .gd-inclusive hop count deliberately: it is the same number the tree's "full chain incl.
		# .gd glue" detail row prints, so the two surfaces cannot disagree. The shorter CONTENT chain is the one the
		# tree's head row shows, and it drops the glue scripts.
		"%d root(s) -> %d file(s) reached (full chain %d hop(s))" % [roots_n, _int(counts, "reached"), full_chain_hops],
		"surveyed %d serialized file(s) on disk" % surveyed,
		"levels %d/%d reachable" % [_int(counts, "levels_reachable"), _int(counts, "levels_total")],
		"quests %d/%d OK (%d no start site, %d unreachable start)" % [
			_int(counts, "quests_ok"), _int(counts, "quests_total"),
			_int(counts, "quests_no_start"), _int(counts, "quests_unreachable_start"),
		],
		"dialogue %d/%d reachable" % [_int(counts, "dialogue_reachable"), _int(counts, "dialogue_total")],
		"%d folder-scan root(s) sparing %d file(s)" % [
			_int(counts, "folder_scan_roots"), _int(counts, "folder_scan_members"),
		],
		"%d skipped" % _int(counts, "skipped"),
		# Unresolved start sites belong in the DENOMINATORS, not only in the Quests subtree: each one is a start site
		# the survey found but could not attribute to a quest file, and every one of them can silently downgrade a
		# genuinely wired quest to "NO START SITE". A quests row of 0/0 OK next to "3 start site(s) unresolved" says
		# something completely different from the same row next to "0 unresolved".
		"%d start site(s) unresolved" % _unresolved_sites.size(),
	])
	var line := " · ".join(parts) + "."
	# The full explanation of SUSPECT lives in the banner row inside the scrolled body (see _render); the status line
	# carries the marker plus the numbers, so this Label — the one control outside the height fence — stays short.
	return ("SUSPECT — " + line) if suspect else line


## Is this report degenerate enough that it says more about the scan than about the project? Each test names a way
## the walk can silently do nothing: no roots resolved, nothing reached beyond the roots themselves, nothing read
## off disk, a content roster that came back completely empty, or the folder-scan guard never firing. Any of them
## means "go debug the scan", never "ship it, we are clean".
##
## The folder-scan test is not a guess. ItemDb is an AUTOLOAD (project.godot: ItemDb="*res://scripts/items/item_db.gd"),
## so it is a boot ROOT, so scripts/items/item_db.gd is always popped and its DirAccess.open(ITEMS_DIR) always yields
## res://resources/items. Zero folder-scan roots therefore cannot mean "this project scans no folders" — it means the
## walk never got as far as an autoload, and the acceptance row "0 items condemned because the guard fired" is
## unverifiable.
##
## The empty-roster tests are DELIBERATELY loud rather than precise: a project that genuinely holds zero quests
## would read SUSPECT here. That is the trade this tab is built to make — a false "check your scan" costs a minute,
## and the failure it guards against (a report that is empty because the walk found nothing, presented as a clean
## bill of health) is the one that shipped 132 unauthored strings under a "TOTAL: 0". Do not soften these to make
## the line go green.
func _is_suspect(counts: Dictionary, roots_n: int, surveyed: int) -> bool:
	if roots_n == 0 or surveyed == 0:
		return true
	if _int(counts, "reached") <= roots_n:
		return true
	if _int(counts, "folder_scan_roots") == 0:
		return true
	return _int(counts, "levels_total") == 0 or _int(counts, "quests_total") == 0


# ================================================================================================================
# SMALL HELPERS
# ================================================================================================================

## One Tree row. `meta` is the res:// path the double-click jumps to (null for a row that names no single file).
## The full text also becomes the tooltip, because horizontal scrolling is disabled and a long path elides.
func _row(parent: TreeItem, text: String, color: Color, meta: Variant = null) -> TreeItem:
	var it := _tree.create_item(parent)
	it.set_text(0, text)
	it.set_custom_color(0, color)
	it.set_tooltip_text(0, text)
	if meta != null:
		it.set_metadata(0, meta)
	return it


## Section headers read as a gauge: blue when the section has something reachable, amber when it does not. A total
## of ZERO is amber too — an empty section is a scan smell, not a pass.
func _head_color(healthy: bool) -> Color:
	return COLOR_HEAD if healthy else COLOR_WARN


## Dictionary reads are Variant; this keeps the format calls above honest and tolerates a missing count key.
func _int(d: Dictionary, key: String) -> int:
	return int(d.get(key, 0))


## Double-click a row: open the file it names in the Inspector and reveal it in the FileSystem dock. The ONLY
## editor mutation in this file, and it writes nothing — mirrors stats_view / audit_panel.
func _on_activated() -> void:
	var it := _tree.get_selected()
	if it == null:
		return
	var p: Variant = it.get_metadata(0)
	if not (p is String):
		return
	var path := p as String
	if not path.begins_with("res://"):
		return
	if ResourceLoader.exists(path):
		var res := load(path)
		if res != null:
			EditorInterface.edit_resource(res)  # a mid-reimport load can return null; revealing it is still useful
	EditorInterface.select_file(path)
