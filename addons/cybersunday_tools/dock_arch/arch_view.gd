@tool
extends VBoxContainer

## CYBER SUNDAY -> Advanced -> Architecture: a READ-ONLY viewer of the living System Map. It groups the same
## `## @system / @seam / @risk / @test` annotation index that scripts/tools/gen_arch_doc.gd writes to
## docs/SYSTEM_MAP.md, and says whether that committed file still matches the code.
##
## WHO READS IT: this is a DEVELOPER index -- the idle line tells designers they can ignore the tab. Its words are
## still designer-safe, because the designer is the one who will click it by accident: rows name a file by its FILE
## NAME (the path rides on the row's tooltip), and no status line ever prints a shell command. A stale map says
## "ask a programmer" and names the generator script; a designer cannot run a terminal, so a command line on the
## status is a dead end, not an instruction.
##
## READ-ONLY BY DESIGN (docs/CYBER_SUNDAY_PLUGIN_QA.md): this tab never writes a file. Regeneration is the headless
## generator scripts/tools/gen_arch_doc.gd, run by a programmer, so there is no file-write guard to get wrong here.
## Shares the pure ArchScan builder (no editor APIs, no scene tree) with that generator and the drift-guard test
## tests/test_arch_doc_sync.gd.
##
## LAZY: the scan walks ~1000 scripts under scripts/, managers/ + resources/. cyber_panel builds every tab eagerly
## on each plugin reload, so the walk runs on the FIRST REVEAL of this tab (the _revealed latch below), never in
## _init -- a plugin toggle stays instant, and so does the bare GUT / headless construction in
## tests/test_devtools_docks.gd. Scan re-runs the walk on demand after that, so a freshly added annotation shows
## without reopening the panel.
##
## HEIGHT: the head bar + one two-line status Label sit OUTSIDE a ScrollContainer; the Tree lives INSIDE it behind a
## small fixed floor. A TabContainer's minimum is the CURRENT tab's minimum, and the editor's bottom splitter keeps
## whatever height it grew to -- so one tall tab, once shown, leaves the panel tall for every tab after it. This
## tab's whole minimum therefore stays well under ~200 px.

const ArchScan := preload("res://scripts/tools/arch_scan.gd")

## Height floor for the scrolled body (see the HEIGHT note above). The Tree carries its own scrollbars, so the
## ScrollContainer is the height FENCE, not a second scroller: its custom_minimum_size is the only vertical minimum
## this tab contributes to the TabContainer, however many entries the Tree holds. The Tree's own floor matches it --
## never taller (this tab once floored the Tree at 160 px and set the panel height for every tab after it).
const BODY_MIN_HEIGHT := 100.0

const COLOR_WARN := Color(1.0, 0.82, 0.3)

## Designer-facing strings. One verb for this tab: Scan (= run a read-only report; Refresh / Reload mean other
## things elsewhere in the panel). The generator is named by its script file so a programmer knows what to run;
## the command line itself lives in that script's header and in docs/SYSTEM_MAP.md, never here.
const SCAN_TIP := "Re-reads the code's @system annotations and checks the committed System Map against them. Read-only."
const MSG_IDLE := "Developer index of the code's @system annotations -- designers can ignore this tab."
const MSG_SCANNING := "Scanning..."
const MSG_IN_SYNC := "The committed System Map is in sync with the code."
const MSG_STALE := "The committed System Map is out of date. Ask a programmer to regenerate it (scripts/tools/gen_arch_doc.gd)."
const MSG_MISSING := "The System Map has not been generated yet. Ask a programmer to generate it (scripts/tools/gen_arch_doc.gd)."
const MSG_NO_TESTS := "test: none -- playtest-only"

var _status: Label = null
var _tree: Tree = null
var _scan_btn: Button = null

## Lazy first-reveal latch (see the LAZY note in the header). Only the selected tab is visible in the TabContainer,
## so "first reveal" means "the first time the designer opens Architecture"; Scan re-runs the walk after that.
var _revealed := false

## True from a scan request until the tree is painted. It spans the one-frame yield that lets "Scanning..." paint,
## and a second request landing inside that frame is folded into the walk already queued -- the walk reads disk
## AFTER the yield, so it is just as fresh.
var _scanning := false


func _init() -> void:
	name = "Architecture"
	add_theme_constant_override("separation", 4)

	# --- head: OUTSIDE the scroll, so the button never scrolls out from under the user ---------------------------
	var bar := HBoxContainer.new()
	_scan_btn = Button.new()
	_scan_btn.text = "Scan"
	_scan_btn.tooltip_text = SCAN_TIP
	_scan_btn.pressed.connect(scan)
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

	# --- body: bounded + scrolled (see BODY_MIN_HEIGHT) ---------------------------------------------------------
	# The Tree keeps SIZE_EXPAND_FILL, which a Godot 4 ScrollContainer honours by stretching an expanding child to
	# the container's size -- so the Tree fills the panel and the outer scroll never engages. Horizontal scrolling
	# is DISABLED because a long row must never widen the bottom panel; the Tree elides those rows internally, and
	# every row carries its full text (plus the file's path) as a tooltip.
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.custom_minimum_size = Vector2(0, BODY_MIN_HEIGHT)
	add_child(scroll)

	_tree = Tree.new()
	_tree.hide_root = true
	_tree.columns = 1
	_tree.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_tree.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_tree.custom_minimum_size = Vector2(0, BODY_MIN_HEIGHT)
	scroll.add_child(_tree)

	_set_status(MSG_IDLE)

	visibility_changed.connect(_on_visibility_changed)
	_on_visibility_changed()  # lazy: scan on first reveal, not at panel construction (a no-op off-tree)


## Lazy first-reveal: run the walk ONCE, the first time the tab is actually shown in the tree. In-tree by
## definition, so scan()'s one-frame yield applies here too and "Scanning..." paints before the walk.
func _on_visibility_changed() -> void:
	if is_visible_in_tree() and not _revealed:
		_revealed = true
		scan()


## PUBLIC. Re-read the annotations and repaint. The Scan button and the lazy first reveal both land here. Says
## "Scanning..." and greys the button first, then yields ONE frame so the editor paints that before the synchronous
## walk (~1000 scripts read) holds the main thread. The yield is in-tree only -- a bare (GUT / headless)
## construction never awaits, which keeps _init await-free and editor-call-free. A re-entrant request during the
## yield is folded into the queued walk (see _scanning).
func scan() -> void:
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


## One pass: scan the source, compare the render against the committed docs/SYSTEM_MAP.md, rebuild the tree. The
## status leads with the counts ("Scanned 12 systems, 40 entries -- ...") so a walk that read nothing is
## distinguishable from a project with no annotations, then the sync verdict.
func _run_scan() -> void:
	var entries := ArchScan.scan()
	var rendered := ArchScan.render(entries)
	var committed := ArchScan.read_doc()
	var head := "Scanned %s, %s -- " % [
		_count(_system_count(entries), "system", "systems"), _count(entries.size(), "entry", "entries"),
	]
	if committed == "":
		_set_status(head + MSG_MISSING, true)
	elif committed == rendered:
		_set_status(head + MSG_IN_SYNC)
	else:
		_set_status(head + MSG_STALE, true)

	_tree.clear()
	var root := _tree.create_item()
	var current_system := ""
	var sys_item: TreeItem = null
	for e in entries:
		var entry := e as Dictionary
		var s := String(entry.get("system", ""))
		if s != current_system or sys_item == null:
			current_system = s
			sys_item = _row(root, s)
		var file := String(entry.get("file", ""))
		var it := _row(sys_item, "%s -- %s" % [String(entry.get("anchor", "")), file.get_file()], file)
		var seam := String(entry.get("seam", ""))
		if seam != "":
			_row(it, "seam: " + seam)
		for r in _as_array(entry.get("risks")):
			_row(it, "risk: " + String(r))
		var tests := _as_array(entry.get("tests"))
		if tests.is_empty():
			_row(it, MSG_NO_TESTS)
		else:
			for t in tests:
				var test_path := String(t)
				_row(it, "test: " + test_path.get_file(), test_path)


## One Tree row. The tooltip carries the full row text (horizontal scrolling is disabled, so a long row elides)
## plus, for a row that names a file, that file's project path -- so the path is one hover away without ever being
## in the text a designer reads.
func _row(parent: TreeItem, text: String, path: String = "") -> TreeItem:
	var it := _tree.create_item(parent)
	it.set_text(0, text)
	var tip := text
	if path != "":
		tip += "\n" + path.trim_prefix("res://")
	it.set_tooltip_text(0, tip)
	return it


## Write the status line and mirror it onto the tooltip (the Label is clamped to two lines, so the tooltip is where
## a long line stays readable in full). `warn` tints the text through a theme colour override -- the modulate alpha
## stays the panel-wide 0.75 either way.
func _set_status(msg: String, warn: bool = false) -> void:
	_status.text = msg
	_status.tooltip_text = msg
	if warn:
		_status.add_theme_color_override("font_color", COLOR_WARN)
	else:
		_status.remove_theme_color_override("font_color")


## Distinct @system groups over the scanned entries (they arrive sorted by system, so this is the group count the
## status line reports beside the entry count).
static func _system_count(entries: Array) -> int:
	var seen := {}
	for e in entries:
		seen[String(e.get("system", ""))] = true
	return seen.size()


## "1 entry" / "2 entries" -- a real plural, never a hand-rolled "(s)", in every count a designer reads.
static func _count(n: int, one: String, many: String) -> String:
	return "%d %s" % [n, one if n == 1 else many]


static func _as_array(v: Variant) -> Array:
	return v if v is Array else []
