@tool
extends VBoxContainer

## CYBER SUNDAY -> Stats (Check group): a READ-ONLY content dashboard. Two things from ONE project walk:
##   1. CONTENT COUNTS -- how many files sit in each content folder, under the SAME group names the Browse tab uses
##      ("Loot Tables", "Status Effects", ...; COUNT_DIRS below, pinned to Browse's ROOTS by the GUT test), so a
##      designer reads one vocabulary across the two tabs.
##   2. UNUSED CONTENT -- files in the REFERENCE-used folders that no other file points at (a weapon no item uses, a
##      loot table no NPC carries, a conversation no NPC speaks, a quest nothing starts). These are delete
##      CANDIDATES, never a verdict: the section header says so, and a double-click hands the file to the Refs tab,
##      which lists everything that points at it, so the designer checks before deleting.
## It never saves a resource and never opens a file for writing -- counts + rows only.
##
## THE SPLIT: content_stats.gd is PURE (the reference regexes, the membership test, the walk policy -- all
## GUT-driven); this file is editor glue -- the recursive res:// walk, the Tree render, the status line, the handoff.
## Same split as reach_scan.gd + reach_view.gd.
##
## THE WALK skips addons/ entirely and any file over content_stats.MAX_FILE_BYTES (the size is read off the open
## handle BEFORE the file is read). Both are the fix for a real editor FREEZE: the walk used to read every .res under
## addons/, and addons/text_to_speech/voices/ alone is ~59 MB of binary voice blobs -- read as Godot Strings on the
## editor's main thread, that stalled the editor for the whole scan. Project content never lives under addons/, so
## THAT skip loses no reference; the SIZE cap can, so it is set above the biggest authored scene on disk rather than
## at a round number (see content_stats.gd -- a file the walk never reads makes this tab's unused list LONGER, and a
## wrongly-listed file is a resource the designer is invited to delete).
##
## Folder-scanned types are DELIBERATELY left out of the unused check: ItemDb scans resources/items/ and the
## factions are scanned too, so those are USED with no explicit reference -- listing them would be noise. The check
## is scoped to types that are reached by an explicit reference (ORPHAN_DIRS). The status line says so.
##
## WHO READS IT: a designer who builds the game in the editor and does not read GDScript. Rows name a file by its
## FILE NAME (the res:// path rides on the row tooltip with the double-click hint), and capitals are kept for verdict
## tokens.
##
## HEIGHT + WIDTH CONTRACT: the Scan button and ONE status Label sit OUTSIDE a ScrollContainer that fences the Tree
## at a small floor (BODY_MIN_HEIGHT). A TabContainer's minimum is the CURRENT tab's minimum, and the editor's bottom
## splitter keeps whatever height it grew to -- so a tall tab, once shown, leaves the panel tall for every tab after
## it. The status is clamped to two lines with the full text mirrored on its tooltip; horizontal scrolling is off so
## a long path can never widen the panel. No heading Label repeats the tab name.
##
## OFF-TREE CONTRACT: GUT and the headless probe construct this tab bare (.new(), no parent, no tree). _init builds
## widgets only -- no EditorInterface, no get_tree(), no await. The walk runs on the FIRST REVEAL (the
## visibility_changed latch) or on Scan, both in-tree, where a one-frame yield lets "Scanning..." paint before the
## synchronous walk holds the main thread.
##
## HANDOFF: double-click an unused-content row -> Host.show_tab(self, "Refs"); when that tab offers select_path the
## file is handed over so Refs lists what points at it. Otherwise (no host off-tree, or a Refs tab without the seam)
## the file opens in the Inspector and is selected in the FileSystem dock -- the older behaviour, kept as the
## fallback. Those are the only editor mutations in this file, and they write nothing.

const Stats := preload("res://addons/cybersunday_tools/dock_stats/content_stats.gd")
const RefScan := preload("res://addons/cybersunday_tools/dock_refs/ref_scan.gd")
## The ONLY way this tab reaches the CYBER SUNDAY panel (the Refs handoff). Off-tree the lookup returns null and the
## double-click falls back to the Inspector, which keeps the handler harmless under test.
const Host := preload("res://addons/cybersunday_tools/core/host.gd")

## Every content folder to COUNT (group label -> folder), in the Browse tab's order and with the Browse tab's exact
## spellings (dock_browser/content_browser.gd ROOTS) -- the GUT test pins both label and folder against it. Browse
## lists a few more groups (Throwables, Abilities, Parts, Levels, Stat Text, Tuning) whose folders are either nested
## or not content a designer counts; this list is the flat gameplay-content set, counted non-recursively.
## Kept a DICTIONARY const on purpose: reach_scan.folder_scan_roots must never read a directory literal out of this
## file (a plain `const X := "res://..."` fed to DirAccess.open would), and tests/test_devtools_reach.gd pins the
## shape. Keep the folders in this table and the loop variable in _tres_in.
const COUNT_DIRS := {
	"Quests": "res://resources/quests/", "NPCs": "res://resources/characters/", "Weapons": "res://resources/weapons/",
	"Items": "res://resources/items/", "Factions": "res://resources/factions/", "Dialogue": "res://resources/dialogue/",
	"Loot Tables": "res://resources/loot/", "Perks": "res://resources/perks/", "Status Effects": "res://resources/status/",
	"Encounters": "res://resources/encounters/", "Schedules": "res://resources/schedules/", "Cutscenes": "res://resources/cutscenes/",
	"Barks": "res://resources/barks/", "Loadouts": "res://resources/loadouts/", "Maps": "res://resources/maps/",
}
## Folders whose resources are used via an explicit reference (so "unused" is meaningful). Excludes items/factions
## (folder-scanned) and characters/encounters/loadouts (profile-export / WIP-archetype noise).
##
## `quests/` was MISSING from this list, which is why an orphaned quest could never surface here: every quest is
## reached by an explicit Resource reference (`QuestStarter.quest`, `TriggerVolume.start_quest`,
## `DialogueChoice.start_quest_on_choice`), so it belongs exactly as much as `dialogue/` does. Its absence is how
## `clear_the_block.tres` -- referenced by NOTHING project-wide -- sat unnoticed while this tab reported clean.
## NOTE this answers a narrower question than the Reach tab: "is it referenced by anything at all?", not "can a
## PLAYER get to it from the boot scene". A quest wired only into a level nothing links to passes HERE and still
## fails there, which is why both checks exist.
const ORPHAN_DIRS: Array[String] = [
	"res://resources/weapons/", "res://resources/loot/", "res://resources/dialogue/", "res://resources/status/",
	"res://resources/cutscenes/", "res://resources/maps/", "res://resources/schedules/", "res://resources/barks/",
	"res://resources/perks/", "res://resources/quests/",
]

## Height floor for the scrolled body -- see the HEIGHT + WIDTH CONTRACT in the header. The Tree inside carries its
## own scrollbars, so this ScrollContainer is the height FENCE, not a second scroller.
const BODY_MIN_HEIGHT := 110.0
const TREE_MIN_HEIGHT := 90.0

const COLOR_HEAD := Color(0.6, 0.85, 1.0)
const COLOR_WARN := Color(1.0, 0.82, 0.3)
const COLOR_DIM := Color(0.72, 0.72, 0.72)
## Sentinel for _row: "leave the theme's text colour alone" (a count row reads in the editor's own text colour).
const NO_COLOR := Color(0, 0, 0, 0)

## Designer-facing strings. The one verb for this tab is Scan (a read-only report) -- never Refresh / Reload, which
## mean other things elsewhere in the panel (Refresh = re-read a list, Reload = replace an open document).
const SCAN_TIP := "Counts every content file and lists the ones no other file points at. Read-only."
const MSG_IDLE := "Press Scan to count content and list files nothing points at."
const MSG_SCANNING := "Scanning..."
## A walk that read nothing is a scan problem, not a clean project -- the Reach tab's lesson, applied here.
const MSG_SUSPECT := "Scan incomplete -- no file could be read; the editor may still be importing. Press Scan again."
const COUNTS_LABEL := "Content counts"
const UNUSED_LABEL := "Unused content (candidates -- check with Refs before deleting)"
const ROW_TIP_HINT := "Double-click to check it in Refs -- it lists every file that points at this one."
const COUNT_TIP_HINT := "Files counted directly in this folder."

var _tree: Tree = null
var _status: Label = null
var _scan_btn: Button = null

## Lazy first-reveal latch: the project walk runs the first time the tab is actually SHOWN, not at panel
## construction. cyber_panel builds every tab eagerly on each plugin reload, so without this a plugin toggle would
## fan out a full res:// walk for a tab nobody clicked. Scan re-runs it on demand after that.
var _revealed := false

## True from the moment a scan is requested (Scan or the first reveal) until the Tree is repainted. It spans the
## one-frame yield that lets "Scanning..." paint; a second request landing inside that frame is dropped, because the
## walk reads disk AFTER the yield and is just as fresh.
var _scanning := false


func _init() -> void:
	name = "Stats"
	add_theme_constant_override("separation", 4)

	# --- head: OUTSIDE the scroll, so the button never scrolls out from under the designer --------------------
	var bar := HBoxContainer.new()
	_scan_btn = Button.new()
	_scan_btn.text = "Scan"
	_scan_btn.tooltip_text = SCAN_TIP
	_scan_btn.pressed.connect(_scan)
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

	# --- body: bounded + scrolled -----------------------------------------------------------------------------
	# The ScrollContainer's custom_minimum_size is the only vertical minimum this tab contributes to the TabContainer,
	# no matter how many rows the Tree holds. The Tree keeps SIZE_EXPAND_FILL, which a Godot 4 ScrollContainer honours
	# by stretching an expanding child to the container's size -- so the Tree fills the panel and the outer scroll
	# never engages. Horizontal scrolling is DISABLED so a long row can never widen the bottom panel; the Tree elides
	# and scrolls those rows internally, and every file row carries its full path as a tooltip.
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
	_tree.custom_minimum_size = Vector2(0, TREE_MIN_HEIGHT)
	_tree.item_activated.connect(_on_activated)  # double-click / Enter
	scroll.add_child(_tree)

	_set_status(MSG_IDLE)

	visibility_changed.connect(_on_visibility_changed)
	_on_visibility_changed()  # no-op off-tree (not visible); in the editor the real reveal fires the signal


## Lazy first-reveal: run the project walk ONCE, the first time the tab is actually shown in the tree. In-tree by
## definition, so _scan()'s one-frame yield applies here too and "Scanning..." paints before the walk.
func _on_visibility_changed() -> void:
	if is_visible_in_tree() and not _revealed:
		_revealed = true
		_scan()


# ================================================================================================================
# THE SCAN
# ================================================================================================================

## Scan (the button) and the first reveal both land here. Says "Scanning..." and greys the button first, then yields
## ONE frame so the editor paints that before the synchronous project walk holds the main thread. The yield is
## in-tree only -- a bare (GUT / headless) construction never awaits, which keeps _init await-free.
func _scan() -> void:
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


## One pass: walk the project for references, count each content folder, list the unused candidates, paint.
func _run_scan() -> void:
	var ref_paths := {}
	var ref_uids := {}
	var walked := _collect("res://", ref_paths, ref_uids)

	_tree.clear()
	var root := _tree.create_item()
	var counts := _row(root, COUNTS_LABEL, COLOR_HEAD)
	var total := 0
	for label in COUNT_DIRS:
		var dir := String(COUNT_DIRS[label])
		var c := _count_tres(dir)
		total += c
		var it := _row(counts, "%s: %d" % [String(label), c], COLOR_DIM if c == 0 else NO_COLOR)
		it.set_tooltip_text(0, "%s\n%s" % [dir, COUNT_TIP_HINT])  # the folder rides on the tooltip, never in the row

	var unused: Array = []
	for d in ORPHAN_DIRS:
		for path in _tres_in(d):
			var p := String(path)
			if not Stats.is_referenced(p, RefScan.uid_for(p), ref_paths, ref_uids):
				unused.append(p)
	unused.sort()
	var head := _row(root, "%s: %d" % [UNUSED_LABEL, unused.size()], COLOR_WARN if not unused.is_empty() else COLOR_HEAD)
	for u in unused:
		var path := String(u)
		_row(head, path.get_file(), COLOR_WARN, path)

	# The suspect case leads with the warning ahead of the counts: the Label is clamped to two lines, and "this is
	# evidence of a broken scan" is the one sentence that must never be squeezed off.
	var suspect := _is_suspect(walked)
	var line := _status_text(total, unused.size(), walked)
	_set_status((MSG_SUSPECT + " " + line) if suspect else line, suspect)


## Walk every project file once, unioning collect_referenced() into the path/uid lookup sets. Returns how many files
## were actually READ -- the denominator the status line prints, so "nothing unused" over a walk that read nothing
## can never pass for a clean project. The walk policy (which folders, which formats, the size cap) is
## content_stats.gd's; this only applies it.
func _collect(dir: String, ref_paths: Dictionary, ref_uids: Dictionary) -> int:
	var read := 0
	var d := DirAccess.open(dir)
	if d == null:
		return 0
	d.list_dir_begin()
	var e := d.get_next()
	while e != "":
		if not e.begins_with("."):
			var full := dir.path_join(e)
			if d.current_is_dir():
				if not Stats.skips_dir(e):
					read += _collect(full, ref_paths, ref_uids)
			else:
				var text := _read_if_scannable(full)
				if not text.is_empty():
					read += 1
					var refs := Stats.collect_referenced(text)
					for p in refs["paths"]:
						ref_paths[p] = true
					for u in refs["uids"]:
						ref_uids[u] = true
		e = d.get_next()
	d.list_dir_end()
	return read


## The text of `path` when the walk policy admits it, else "". The extension is tested BEFORE the open (a .png or a
## .gd.uid sidecar costs nothing) and the SIZE is read off the open handle BEFORE any read -- so a 20 MB voice blob
## costs one open() and nothing more. Reading it into a String first and discarding it is exactly the stall this
## guards against.
func _read_if_scannable(path: String) -> String:
	if not Stats.scans_ext(path):
		return ""
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return ""
	if not Stats.fits_size(int(f.get_length())):
		return ""
	return f.get_as_text()


func _count_tres(dir: String) -> int:
	return _tres_in(dir).size()


## The .tres paths directly under `dir` (non-recursive; content folders are flat). [] when the folder is absent.
func _tres_in(dir: String) -> Array:
	var out: Array = []
	var d := DirAccess.open(dir)
	if d == null:
		return out
	for f in d.get_files():
		var fn := String(f).trim_suffix(".remap")
		if fn.get_extension() == "tres":
			out.append(dir.path_join(fn))
	return out


# ================================================================================================================
# STATUS + ROWS
# ================================================================================================================

## The done line: what was scanned (the denominator) first, then the counts, then the one next step. "Scanned 0
## files -- ... nothing unused" must never read like a clean result, which is why the files-read count leads.
func _status_text(total: int, unused_n: int, walked: int) -> String:
	var head := "Scanned %s -- %s in %d groups, " % [_count(walked, "file", "files"), _count(total, "content file", "content files"), COUNT_DIRS.size()]
	if unused_n > 0:
		return head + "%s. Double-click one to check it in Refs before deleting." % _count(unused_n, "unused candidate", "unused candidates")
	return head + "nothing unused. Items and factions are never listed here (they load by folder)."


## Did the walk read nothing? Then the counts are not evidence of anything -- the editor was probably still
## importing -- and the status must say so instead of reporting a clean project.
func _is_suspect(walked: int) -> bool:
	return walked == 0


## Write the status line and mirror it onto the tooltip (the Label is clamped to two lines, so the tooltip is where a
## long line stays readable in full). `warn` tints the text through a theme colour override -- the modulate alpha
## stays the panel-wide 0.75 either way.
func _set_status(msg: String, warn: bool = false) -> void:
	_status.text = msg
	_status.tooltip_text = msg
	if warn:
		_status.add_theme_color_override("font_color", COLOR_WARN)
	else:
		_status.remove_theme_color_override("font_color")


## One Tree row. `color` NO_COLOR leaves the theme's text colour alone. `meta` is the res:// path the double-click
## hands to Refs (null for a row that names no single file). The tooltip carries the full row text -- horizontal
## scrolling is disabled and a long row elides -- plus, for a file row, the path itself and the double-click hint, so
## the res:// path is always one hover away without ever being in the row text a designer reads.
func _row(parent: TreeItem, text: String, color: Color = NO_COLOR, meta: Variant = null) -> TreeItem:
	var it := _tree.create_item(parent)
	it.set_text(0, text)
	if color.a > 0.0:
		it.set_custom_color(0, color)
	var tip := text
	if meta != null:
		it.set_metadata(0, meta)
		if meta is String and not str(meta).is_empty():
			tip += "\n%s\n%s" % [str(meta), ROW_TIP_HINT]
	it.set_tooltip_text(0, tip)
	return it


## "1 file" / "2 files" -- a real plural, never a hand-rolled "(s)", in every count a designer reads.
static func _count(n: int, one: String, many: String) -> String:
	return "%d %s" % [n, one if n == 1 else many]


# ================================================================================================================
# THE HANDOFF
# ================================================================================================================

## Double-click an unused-content row: switch to the Refs tab and hand it the file, so the designer sees every file
## that points at it BEFORE deleting. Count rows and section headers carry no path and no-op. The Refs seam is
## duck-typed (has_method("select_path")) so a Refs tab without it -- or no host at all, off-tree -- degrades to the
## older behaviour: open the file in the Inspector and select it in the FileSystem dock. Writes nothing either way.
##
## ONE jump per double-click. Once the panel has switched to Refs, this handler is done: a Refs tab that ACCEPTED
## the file and a Refs tab that refused it (a reimport in flight, a search already running) both leave the designer
## looking at Refs, and Refs has already written its own reason there. Falling through to the Inspector after that
## would be a second, unasked-for jump -- and the status line it wrote would land on the Stats tab, which is no
## longer the tab on screen. So the Inspector fallback belongs to the no-seam case only.
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
	var refs := Host.show_tab(self, "Refs")
	if refs != null and refs.has_method("select_path"):
		var taken: Variant = refs.call("select_path", path)
		if taken is bool and taken:
			_set_status("Opened %s in Refs -- it lists every file that points at this one." % path.get_file())
		else:
			_set_status("Couldn't check %s in Refs yet: the Refs tab says why on its own line -- fix that and press Find Refs there." % path.get_file(), true)
		return
	# Fallback (no host off-tree, or a Refs tab without the seam): the Inspector + FileSystem dock, as before.
	var res := load(path)
	if res != null:
		EditorInterface.edit_resource(res)  # a mid-reimport load can return null; revealing it is still useful
	EditorInterface.select_file(path)
	_set_status("Opened %s in the Inspector -- also selected in the FileSystem dock." % path.get_file())
