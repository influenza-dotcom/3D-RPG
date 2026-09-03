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
## render, and the double-click handoff. Same split as content_stats.gd + stats_view.gd.
##
## WHO READS IT: a designer who builds the game in the editor and does not read GDScript. So every row names a file
## by its FILE NAME (the res:// path rides on the row's tooltip, with the double-click hint), every finding says what
## to do next in editor words (which tab, which component), and capitals are kept for the verdict tokens.
##
## HANDOFFS. Public `rescan()` is what the Quest / Dialogue tabs' Check Reach buttons call after Host.show_tab
## ("Reach") — the same routine the Scan button and the lazy first reveal run. Double-clicking a row whose file is a
## .tscn opens THAT SCENE in the editor (EditorInterface.open_scene_from_path) so the designer lands in the level that
## holds the starter; any other file opens in the Inspector / script editor (edit_resource); both then reveal the
## file in the FileSystem dock (select_file). Those are the only editor mutations in this file, and they write nothing.
##
## READ-ONLY, and it must stay that way. No ResourceSaver, no FileAccess.WRITE, no ProjectSettings.save anywhere
## below — so the plugin's write contract (preview / confirm / report changed paths) does not apply and cannot be
## got wrong.
##
## The survey is TEXT-ONLY on purpose: the designer usually has the editor open, and a load() during a reimport can
## hand back null or an empty PackedScene ("node count is 0"). A report built over a file nobody could read is the
## exact lie this tab exists to catch, so an unreadable file becomes an "unreadable" row, never a silent clean result.
##
## ------------------------------------------------------------------------------------------------------------
## HOW TO READ AN ALL-GREEN RESULT: with suspicion. This project has a scar precisely here — text_debt.gd once
## printed "TOTAL: 0" while 132 of 267 strings were unauthored placeholders. An empty Reach report is far more
## likely to mean the scan UNDER-fired (the folder-scan guard over-approximated, or the walk surveyed nothing) than
## that the game is fully wired. That is why the status line always prints the DENOMINATORS it scanned — files
## scanned, files walked, boot roots, folders loaded whole, unreadable files, unmatched start sites — beside what it
## found, leads with "Scan incomplete" when a denominator is degenerate, AND repeats that warning as the first row
## INSIDE the scrolled body (the status Label is clamped to two lines, so on a narrow panel it is the one control
## that gets squeezed; the warning must survive that). "0 problems out of 0 things looked at" and "0 problems out of
## 378 things looked at" must never read the same. Never "fix" a suspiciously clean report by widening a guard; go
## find what the scan failed to walk.

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
## unwired level reads as a WARN row instead of quietly vanishing from the report.
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

## Height floor for the scrolled body. A TabContainer's minimum is the CURRENT tab's minimum, and the editor's
## bottom splitter keeps whatever height it grew to — so one tall tab, once shown, leaves the panel tall for every
## tab after it. This plugin has twice shipped a tab that pushed the editor's panel past the screen that way, so the
## body's minimum is small and fixed, and the head + status rows live OUTSIDE the scroll where they are always
## readable.
const BODY_MIN_HEIGHT := 110.0

const COLOR_HEAD := Color(0.6, 0.85, 1.0)
const COLOR_OK := Color(0.55, 0.9, 0.55)
const COLOR_WARN := Color(1.0, 0.82, 0.3)
const COLOR_ERROR := Color(1.0, 0.42, 0.42)
const COLOR_DIM := Color(0.72, 0.72, 0.72)

## Designer-facing strings. Files are named by file name (the res:// path rides on the row tooltip), the next step is
## always stated in editor words, and the one verb for this tab is Scan — never Rescan / Refresh, which mean other
## things elsewhere in the panel (Refresh = re-read a list, Reload = replace an open document).
const SCAN_TIP := "Walks from the boot scene through every level, quest and conversation and reports what a player can actually get to. Read-only."
const MSG_IDLE := "Press Scan to see what a player can reach from the boot scene."
const MSG_SCANNING := "Scanning..."
## The degenerate-scan warning. The FULL wording is the first row inside the scrolled body (where nothing squeezes it);
## the status line carries the short form ahead of the verdict, because the Label is clamped to two lines.
const MSG_SUSPECT := "Scan incomplete -- one of the counts came back empty. That usually means the editor was still importing; press Scan again."
const MSG_SUSPECT_MORE := "If it persists, ask a programmer to check the boot scene and the file walk."
const MSG_STATUS_SUSPECT := "Scan incomplete -- one of the counts came back empty; press Scan again."
## The boot-chain head when NO level is reachable: build_report then aims the chain at the deepest file the walk
## touched, which is not a route into the game and must never be read as one.
const MSG_FALLBACK := "no level is reachable -- this shows how far the walk got, not a route into the game"
const MSG_NOTHING_REACHED := "Nothing reached -- the boot scene resolved to no file. That is a scan problem, not a clean project; press Scan again."
## Under a quest with no start site anywhere: the two ways a designer wires one, in the words of the tabs they use.
const MSG_NO_START_HINT := "Nothing starts this quest yet. Start it from a conversation: Dialogue -> pick the conversation -> pick a choice -> Start quest. Or from the world: select a node in the scene -> Palette -> QuestStarter (aim + E board) or TriggerVolume (walk-in) -> set its quest to this file."

var _tree: Tree = null
var _status: Label = null
var _scan_btn: Button = null

## Start sites whose quest link resolved to no file (a uid-only ext_resource row), as [{text, file}]. Kept so they
## can be SHOWN rather than dropped: a dropped site would silently downgrade a wired quest to "NO START SITE", and an
## invented finding is how a report loses a designer's trust.
var _unresolved_sites: Array = []

## PL6 lazy first-reveal latch: the project walk runs the first time the tab is actually SHOWN, not at panel
## construction. cyber_panel builds every tab eagerly on each plugin reload, so without this a plugin toggle would
## fan out a full res:// walk for a tab nobody clicked. Only the selected tab is visible, so "first reveal" means
## "the first time the designer opens Reach"; Scan re-runs it on demand after that.
var _revealed := false

## True from the moment a scan is requested (Scan, the first reveal, or another tab's Check Reach) until the report
## is painted. It spans the one-frame yield that lets "Scanning..." paint, and a second request landing inside that
## frame is folded into the walk already queued — the walk reads disk AFTER the yield, so it is just as fresh.
var _scanning := false


func _init() -> void:
	name = "Reach"
	add_theme_constant_override("separation", 4)

	# --- head: OUTSIDE the scroll, so the controls never scroll out from under the user -------------------------
	var bar := HBoxContainer.new()
	_scan_btn = Button.new()
	_scan_btn.text = "Scan"
	_scan_btn.tooltip_text = SCAN_TIP
	_scan_btn.pressed.connect(rescan)
	bar.add_child(_scan_btn)
	add_child(bar)

	# The status line is its OWN full-width row (not wedged beside the button), autowraps, and is clamped to TWO
	# lines so a long verdict can never grow the head; the full text is mirrored onto its tooltip on every write.
	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.max_lines_visible = 2
	_status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_status.modulate = Color(1, 1, 1, 0.75)
	_status.mouse_filter = Control.MOUSE_FILTER_PASS  # a Label ignores the mouse by default, which also hides its tooltip
	add_child(_status)

	# --- body: bounded + scrolled -------------------------------------------------------------------------------
	# The Tree carries its own scrollbars, so this ScrollContainer is the HEIGHT FENCE, not a second scroller: its
	# custom_minimum_size is the only vertical minimum this tab contributes to the TabContainer, no matter how many
	# findings the Tree holds. The Tree keeps SIZE_EXPAND_FILL, which a Godot 4 ScrollContainer honours by stretching
	# an expanding child to the container's size — so the Tree fills the panel and the outer scroll never engages.
	# Horizontal scrolling is DISABLED because a long row must never widen the bottom panel; the Tree elides and
	# scrolls those rows internally, and every row carries its full text (plus the file's path) as a tooltip.
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

	_set_status(MSG_IDLE)

	visibility_changed.connect(_on_visibility_changed)
	_on_visibility_changed()  # lazy: scan on first reveal, not at panel construction


## Lazy first-reveal: run the project walk ONCE, the first time the tab is actually shown in the tree. In-tree by
## definition, so rescan()'s one-frame yield applies here too and "Scanning..." paints before the walk.
func _on_visibility_changed() -> void:
	if is_visible_in_tree() and not _revealed:
		_revealed = true
		rescan()


# ================================================================================================================
# THE SCAN
# ================================================================================================================

## PUBLIC. Re-run the whole report. The Scan button, the lazy first reveal, and the Quest / Dialogue tabs' Check
## Reach (Host.show_tab("Reach") then call("rescan")) all land here. Says "Scanning..." and greys the button first,
## then yields ONE frame so the editor paints that before the synchronous project walk holds the main thread (~380
## serialized files read, plus the closure). The yield is in-tree only — a bare (GUT / headless) construction never
## awaits, which keeps _init await-free and editor-call-free. Re-entrant requests during the yield are folded into
## the queued walk (see _scanning).
func rescan() -> void:
	if _scanning:
		return
	_scanning = true
	_scan_btn.disabled = true
	_set_status(MSG_SCANNING)
	if is_inside_tree():
		await get_tree().process_frame
	_run_scan()
	_scan_btn.disabled = false
	_scanning = false


## One pass: read the boot roots, survey the serialized files on disk, run the closure, render the report.
func _run_scan() -> void:
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
##              clean one, and the reason the status line can say "scanned 378 files" beside "0 unreadable"
##   unresolved start sites whose quest link had no resolvable `path=` row, as [{text, file}] ready to render
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
			# Unreadable, or mid-reimport. Surfaced as an "unreadable" row: a file nobody read cannot be evidence of
			# anything, least of all of a clean project.
			skipped.append(path)
			continue
		surveyed += 1

		# Quest START sites, project-wide and INVERTED to {quest: [{file, field, label, node}]}. `file` is what the
		# reachability test keys on — a start site only counts if the file HOLDING it is itself reachable; `node` is
		# the scene node holding it, carried through so the row can name it.
		# PRE-GATED on QUEST_FIELD_SUBSTRING (see that const): an exact skip, not a sampling heuristic, and the
		# difference between a snappy button and a multi-second stall on the editor's main thread.
		var sites: Array = Reach.quest_start_sites(text) if QUEST_FIELD_SUBSTRING in text else []
		for site in sites:
			var sd := site as Dictionary
			var quest_path := str(sd.get("path", ""))
			var label := str(sd.get("label", ""))
			var node := str(sd.get("node", ""))
			if quest_path.is_empty():
				unresolved.append({
					"text": "%s %s -- the quest it points at could not be matched to a file (link \"%s\")" % [
						label, _site_where(node, path), str(sd.get("id", "")),
					],
					"file": path,
				})
				continue
			if not quest_sites.has(quest_path):
				quest_sites[quest_path] = []
			(quest_sites[quest_path] as Array).append({
				"file": path, "field": str(sd.get("field", "")), "label": label, "node": node,
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
## marking one reached would inflate the closure's count and the "loaded whole (N files)" receipt without naming
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

	# The "Scan incomplete" warning is repeated as the FIRST row inside the scrolled body, not left to the status
	# Label alone. The head rows sit OUTSIDE the scroll (so the controls never scroll away), which means the Label is
	# clamped to two lines and is the first thing a narrow bottom panel squeezes. The one sentence that must never be
	# lost is "this is evidence of a broken scan", so it lives here too, where the ScrollContainer bounds it and it
	# reads before every count below it.
	if suspect:
		var banner := _row(root, MSG_SUSPECT, COLOR_ERROR)
		_row(banner, MSG_SUSPECT_MORE, COLOR_ERROR)

	_render_chain(root, report, counts)
	_render_levels(root, report, counts)
	_render_quests(root, report, counts)
	_render_dialogue(root, report, counts)
	_render_folder_roots(root, report, counts)
	_render_skips(root, report, counts)

	_set_status(_status_text(counts, roots_n, surveyed, suspect), suspect)


## The chain the closure actually FOLLOWED, printed. A reachability gauge nobody can audit is a green light nobody
## should trust — so the readable content chain heads the report (under the "Scan incomplete" warning, when there is
## one), and the full chain (including the scripts that carried each edge) hangs underneath it for anyone checking
## the tab's work.
func _render_chain(root: TreeItem, report: Dictionary, counts: Dictionary) -> void:
	var chain: Array = report.get("chain", [])
	var full: Array = report.get("chain_full", [])
	# build_report aims the printed chain at the SHALLOWEST REACHABLE LEVEL, and falls back to the deepest file the
	# walk touched when no level is reachable at all. That fallback is NOT a boot chain and must never be read as
	# one — an unlabelled fallback is precisely the "green gauge nobody should trust" this section exists to prevent.
	var leaf := str(report.get("chain_leaf", ""))
	var fallback := not chain.is_empty() and _int(counts, "levels_reachable") == 0
	# FILES, not hops. `chain` is content_chain(full) — the .gd glue hops have already been ELIDED from it, so its
	# size is neither the number of arrows below it (that is size - 1) nor the depth the level rows print (that one
	# counts the elided script hops too). Counting it as "hops" made the header contradict both. It counts exactly
	# the rows hanging under it, so that is what it says. The level rows keep "hops" for `depth`, which really is one.
	var files := _count(chain.size(), "file", "files")
	var title := "Boot chain: %s" % files
	if fallback:
		title = "Boot chain (%s, ending at %s): %s" % [files, leaf.get_file(), MSG_FALLBACK]
	elif not leaf.is_empty():
		title = "Boot chain to %s: %s" % [leaf.get_file(), files]
	var head_color := COLOR_ERROR
	if not chain.is_empty():
		head_color = COLOR_WARN if fallback else COLOR_HEAD
	var head := _row(root, title, head_color, (leaf if not leaf.is_empty() else null))
	if chain.is_empty():
		_row(head, MSG_NOTHING_REACHED, COLOR_ERROR)
		return
	for i in chain.size():
		var path := str(chain[i])
		var arrow := "" if i == 0 else "-> "
		_row(head, arrow + path.get_file(), COLOR_OK, path)
	head.set_collapsed(false)
	var detail := _row(head, "Full chain (including scripts): %s" % _count(full.size(), "file", "files"), COLOR_DIM)
	detail.set_collapsed(true)
	for p in full:
		_row(detail, str(p).get_file(), COLOR_DIM, str(p))


func _render_levels(root: TreeItem, report: Dictionary, counts: Dictionary) -> void:
	var levels: Array = report.get("levels", [])
	var reachable := _int(counts, "levels_reachable")
	var total := _int(counts, "levels_total")
	var head := _row(root, "Levels: %d of %d are loaded from the boot scene" % [reachable, total], _head_color(total > 0 and reachable > 0))
	for row in levels:
		var r := row as Dictionary
		var path := str(r["path"])
		var ok := bool(r["reachable"])
		# The note names the ACTIONABLE difference: a wired-but-unloaded level needs something to point at its
		# LevelData; an unwired one needs a LevelData at all. Collapsing both to "unreachable" hides the fix.
		var note := "loaded, %s from the boot scene" % _count(int(r["depth"]), "hop", "hops")
		if not ok:
			if bool(r["wired"]):
				note = "has a LevelData, but nothing a player reaches loads it -- point a LevelDoor or the starting level at that LevelData"
			else:
				note = "no LevelData points at this scene -- add one under resources/levels with its Scene set to this file"
		_row(head, "%s  %s -- %s" % ["OK" if ok else "WARN", path.get_file(), note], COLOR_OK if ok else COLOR_WARN, path)


## Quests, the reason the tab exists. TWO axes, three verdicts, and each row carries its start sites so the fix is
## obvious from the report alone: NO START SITE means "wire it" (the hint row says how, in the words of the Dialogue
## and Palette tabs), START SITE NOT REACHABLE means "its HOST is the problem, not the wiring" (the site row names
## the node and the scene, and a double-click opens that scene).
func _render_quests(root: TreeItem, report: Dictionary, counts: Dictionary) -> void:
	var quests: Array = report.get("quests", [])
	var ok := _int(counts, "quests_ok")
	var total := _int(counts, "quests_total")
	var head := _row(root, "Quests: %d of %d can be started by a player (%d with nothing that starts them, %d started only from somewhere a player never reaches)" % [
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
		var item := _row(head, "%s -- %s" % [verdict, path.get_file()], color, path)
		var sites: Array = q.get("sites", [])
		if sites.is_empty():
			_row(item, MSG_NO_START_HINT, COLOR_DIM)
			continue
		for s in sites:
			var sd := s as Dictionary
			var file := str(sd["file"])
			var site_ok := bool(sd["reachable"])
			# 'QuestStarter.quest on node "QuestStarter" in SliceTestLevel.tscn -- not reached, so a player never
			# gets there'. The node name is what the designer types into the scene dock's filter to find it.
			_row(item, "%s %s -- %s" % [
				str(sd["label"]), _site_where(str(sd.get("node", "")), file),
				"reached" if site_ok else "not reached, so a player never gets there",
			], COLOR_OK if site_ok else COLOR_WARN, file)
	if not _unresolved_sites.is_empty():
		# Shown, never dropped: an unresolvable site would otherwise downgrade a wired quest to NO START SITE.
		var un := _row(head, "Start sites that could not be matched to a quest file: %d" % _unresolved_sites.size(), COLOR_WARN)
		for u in _unresolved_sites:
			var ud := u as Dictionary
			_row(un, str(ud.get("text", "")), COLOR_WARN, str(ud.get("file", "")))


func _render_dialogue(root: TreeItem, report: Dictionary, counts: Dictionary) -> void:
	var dialogue: Array = report.get("dialogue", [])
	var reachable := _int(counts, "dialogue_reachable")
	var total := _int(counts, "dialogue_total")
	var head := _row(root, "Conversations: %d of %d reachable" % [reachable, total], _head_color(total > 0 and reachable > 0))
	for row in dialogue:
		var d := row as Dictionary
		var path := str(d["path"])
		var ok := bool(d["reachable"])
		var note := "an NPC or level a player reaches points at it"
		if not ok:
			note = "no NPC, Talkable or level a player can reach points at it -- put it on a Talkable in a reachable level"
		_row(head, "%s  %s -- %s" % ["OK" if ok else "WARN", path.get_file(), note], COLOR_OK if ok else COLOR_WARN, path)


## The folder-scan guard's receipt. Printing which folders were loaded whole — and which script loads each one — is
## what makes the guard auditable: if this section is suspiciously long, the guard over-approximated and swallowed
## real orphans, and THAT is the thing to go fix (never by widening it further).
func _render_folder_roots(root: TreeItem, report: Dictionary, counts: Dictionary) -> void:
	var roots: Array = report.get("folder_roots", [])
	# Amber at ZERO, by the same rule as every other section head: an empty section is a scan smell, not a pass.
	# Here it is provably so — ItemDb is an AUTOLOAD (project.godot [autoload] ItemDb="*res://scripts/items/item_db.gd"),
	# hence a boot root, hence scripts/items/item_db.gd is always popped and its DirAccess.open(ITEMS_DIR) always
	# fires res://resources/items. Zero roots therefore means the walk never reached an autoload, not that the
	# project scans no folders.
	var head := _row(root, "Loaded by folder scan, not checked one by one: %s, %s" % [
		_count(roots.size(), "folder", "folders"), _count(_int(counts, "folder_scan_members"), "file", "files"),
	], _head_color(not roots.is_empty()))
	for row in roots:
		var r := row as Dictionary
		var declared := str(r["declared_by"])
		_row(head, "%s -- every file in it is loaded by %s" % [str(r["dir"]).trim_prefix("res://"), declared.get_file()], COLOR_DIM, declared)


## Files nobody could read. Never silent: a clean report built over an unread file is the failure mode this tab
## exists to catch, and a mid-reimport read returning "" is routine with the editor open (press Scan again).
func _render_skips(root: TreeItem, report: Dictionary, counts: Dictionary) -> void:
	var skipped: Array = report.get("skipped", [])
	var n := _int(counts, "skipped")
	if n == 0:
		return
	var head := _row(root, "Unreadable when scanned: %d -- usually the editor was still importing; press Scan again" % n, COLOR_WARN)
	for p in skipped:
		_row(head, str(p).get_file(), COLOR_WARN, str(p))


# ================================================================================================================
# STATUS — the line that must make an all-green result look SUSPICIOUS
# ================================================================================================================

## The verdict first, then the DENOMINATORS in plain words. "1 of 2 can be started" is meaningless without "scanned
## 378 files, walked 412 from 15 boot roots" — with the denominators, a scan that walked nothing is instantly
## distinguishable from a project that is genuinely wired, and that distinction IS the acceptance bar for this tab.
## The "loaded whole" folder count and the unmatched start sites belong here too: every unmatched site is a start
## site the survey found but could not attribute to a quest file, and each one can silently downgrade a genuinely
## wired quest to NO START SITE — "0 of 2 can be started" next to "3 start sites unmatched" says something completely
## different from the same verdict next to "0 start sites unmatched".
func _status_text(counts: Dictionary, roots_n: int, surveyed: int, suspect: bool) -> String:
	var verdict := "Quests: %d of %d can be started by a player -- Levels: %d of %d are loaded from the boot scene -- Conversations: %d of %d reachable." % [
		_int(counts, "quests_ok"), _int(counts, "quests_total"),
		_int(counts, "levels_reachable"), _int(counts, "levels_total"),
		_int(counts, "dialogue_reachable"), _int(counts, "dialogue_total"),
	]
	var walked := "Scanned %s, walked %d from %s, %s loaded whole (%s), %d unreadable, %s unmatched." % [
		_count(surveyed, "file", "files"), _int(counts, "reached"), _count(roots_n, "boot root", "boot roots"),
		_count(_int(counts, "folder_scan_roots"), "folder", "folders"),
		_count(_int(counts, "folder_scan_members"), "file", "files"),
		_int(counts, "skipped"), _count(_unresolved_sites.size(), "start site", "start sites"),
	]
	var line := verdict + " " + walked
	# The full explanation lives in the warning rows inside the scrolled body (see _render); the status line leads
	# with the short form so the two-line Label still shows the verdict after it.
	return (MSG_STATUS_SUSPECT + " " + line) if suspect else line


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
## would read "Scan incomplete" here. That is the trade this tab is built to make — a false "check your scan" costs a
## minute, and the failure it guards against (a report that is empty because the walk found nothing, presented as a
## clean bill of health) is the one that shipped 132 unauthored strings under a "TOTAL: 0". Do not soften these to
## make the line go green.
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

## One Tree row. `meta` is the res:// path the double-click opens (null for a row that names no single file). The
## tooltip carries the full row text — horizontal scrolling is disabled and a long row elides — plus, for a file row,
## the path itself and the double-click hint, so the res:// path is always one hover away without ever being in the
## row text a designer reads.
func _row(parent: TreeItem, text: String, color: Color, meta: Variant = null) -> TreeItem:
	var it := _tree.create_item(parent)
	it.set_text(0, text)
	it.set_custom_color(0, color)
	var tip := text
	if meta != null:
		it.set_metadata(0, meta)
		if meta is String and not str(meta).is_empty():
			var path := str(meta)
			var opens := "Double-click to open this scene." if path.get_extension() == "tscn" else "Double-click to open it."
			tip += "\n%s\n%s" % [path, opens]
	it.set_tooltip_text(0, tip)
	return it


## Section headers read as a gauge: blue when the section has something reachable, amber when it does not. A total
## of ZERO is amber too — an empty section is a scan smell, not a pass.
func _head_color(healthy: bool) -> Color:
	return COLOR_HEAD if healthy else COLOR_WARN


## Dictionary reads are Variant; this keeps the format calls above honest and tolerates a missing count key.
func _int(d: Dictionary, key: String) -> int:
	return int(d.get(key, 0))


## "1 hop" / "2 hops" — a real plural, never a hand-rolled "(s)", in every count a designer reads.
static func _count(n: int, one: String, many: String) -> String:
	return "%d %s" % [n, one if n == 1 else many]


## Where a start site lives, in designer words: 'on node "QuestStarter" in SliceTestLevel.tscn' when the site is a
## scene node, 'in old_man.tres' when it is a DialogueChoice inside a resource (no node to name).
static func _site_where(node: String, file: String) -> String:
	if node.is_empty():
		return "in %s" % file.get_file()
	return "on node \"%s\" in %s" % [node, file.get_file()]


## Write the status line and mirror it onto the tooltip (the Label is clamped to two lines, so the tooltip is where
## a long verdict stays readable in full). `error` tints the text through a theme colour override — the modulate
## alpha stays the panel-wide 0.75 either way.
func _set_status(msg: String, error: bool = false) -> void:
	_status.text = msg
	_status.tooltip_text = msg
	if error:
		_status.add_theme_color_override("font_color", COLOR_ERROR)
	else:
		_status.remove_theme_color_override("font_color")


## Double-click a row: open the file it names and reveal it in the FileSystem dock. A .tscn opens AS THE EDITED
## SCENE, so a designer who double-clicks 'QuestStarter.quest on node "QuestStarter" in SliceTestLevel.tscn' lands in
## the level holding that starter; anything else opens in the Inspector (a .tres) or the script editor (a .gd). The
## only editor mutations in this file, and they write nothing — mirrors ref_viewer / stats_view.
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
	if not ResourceLoader.exists(path):
		# A row can outlive its file (renamed or deleted since the scan), or the editor may still be importing it.
		_set_status("Couldn't open %s: the file is missing or still importing -- press Scan again." % path.get_file(), true)
		return
	if path.get_extension() == "tscn":
		EditorInterface.open_scene_from_path(path)
	else:
		var res := load(path)
		if res != null:
			EditorInterface.edit_resource(res)  # a mid-reimport load can return null; revealing it is still useful
	EditorInterface.select_file(path)
