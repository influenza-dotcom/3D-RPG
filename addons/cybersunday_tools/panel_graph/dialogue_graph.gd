@tool
extends VBoxContainer

## "Graphs" tab (Control name "Graphs" -- the panel sets the display title, tests pin the name): a READ-ONLY drawing
## of one conversation's branches or of the whole quest chain. Pick Dialogue or Quest, pick a file, and the GraphEdit
## fills with one box per dialogue line / quest, arrows for choice targets + prerequisite / next-quest links, and any
## dangling target called out in the status line (and tinted red on its box). View-only: no connecting, no deleting,
## no minimap. Picking a file draws it at once; Show Graph redraws it; Open hands it to its editor tab.
##
## All graph BUILDING lives in graph_data.gd (pure, no editor APIs); this file is the editor glue: the typed folder
## scan behind the picker, GraphNode rendering, layout-to-pixels, and the Open handoff (through core/host.gd -- a tab
## never reaches the panel by get_parent() chains). Both modes share graph_data so there is one source of truth;
## quest_graph.gd is this same Control booted in Quest mode.
##
## TYPED PICKER: resources/dialogue holds VoiceData beside the conversations, and resources/quests may hold whatever a
## designer drops there, so the picker lists ONLY what the active mode can draw -- a file must load as a
## DialogueResource (Dialogue mode) or pass the quest loader's duck-typed test (an `id` plus `objectives`, the same
## test scripts/tools/cyber_cmds.gd applies) -- and the status counts what was skipped. Before this filter a VoiceData
## was offered as a conversation and drew an empty graph with no explanation.
##
## LAYOUT CONTRACT: a TabContainer's minimum is the CURRENT tab's minimum, and the editor's bottom splitter keeps the
## height it grew to -- so a tall tab, once shown, leaves the panel tall for every tab after it. Here the action bar
## and ONE two-line status Label sit above the GraphEdit, whose floor is GRAPH_MIN_HEIGHT (a GraphEdit scrolls itself,
## so it needs no ScrollContainer); the whole tab lands under ~200 px, and a conversation with many dangling targets
## can't grow it because the status clips at two lines (the tooltip carries the full text).
##
## OFF-TREE: GUT and the headless probe construct this bare (.new(), no parent, no tree). _init touches no
## EditorInterface outside the Engine.is_editor_hint() guard; every other editor call lives in a button handler.
## The folder scan waits for the first in-tree reveal (`_revealed`), and a later editor filesystem change only raises
## `_fs_dirty` -- the rescan runs on the NEXT reveal, keeping the picked file BY PATH, never while the tab is showing.
##
## Every string here is a DEVELOPER surface (editor tooling) and never goes through PlayerText.

const GraphData := preload("res://addons/cybersunday_tools/panel_graph/graph_data.gd")
const Host := preload("res://addons/cybersunday_tools/core/host.gd")
const PickerRows := preload("res://addons/cybersunday_tools/core/picker_rows.gd")

## Where authored content lives -- scanned (recursively) to fill the picker. A missing folder scans as empty.
const DIALOGUE_DIR := "res://resources/dialogue"
const QUEST_DIR := "res://resources/quests"

const COL_W := 320.0   # pixels between layout columns
const ROW_H := 150.0   # pixels between rows within a column
const PROBLEM_COLOR := Color(1.0, 0.42, 0.42)
## The GraphEdit's height floor. It EXPANDS to whatever the bottom panel gives it; the floor only sets the tab's
## minimum, which must stay small (see the layout contract above). Never above 120.
const GRAPH_MIN_HEIGHT := 110.0

## Idle hints: the one imperative next step per mode. Quest mode needs no pick -- Show Graph draws the folder.
const MSG_IDLE_DIALOGUE := "Pick a conversation, then Show Graph."
const MSG_IDLE_QUEST := "Show Graph draws every quest in the folder so prerequisite / next links resolve."
## Empty-folder state (status AND the disabled buttons' tooltip); %s is the mode noun ("conversation" / "quest").
const MSG_NONE_FOUND := "No %s files found -- create one in the New tab first."
## Disabled-state tooltip when the list has files but none is picked; %s is the mode noun.
const TIP_PICK_FIRST := "Pick a %s first."
## Enabled-state tooltips: "<What it does>. <Writes X | Read-only>."
const TIP_SHOW_DIALOGUE := "Draw the picked conversation -- one box per line, an arrow per choice. Read-only."
const TIP_SHOW_QUEST := "Draw every quest in the folder, with arrows for prerequisite and next-quest links. Read-only."
const TIP_OPEN := "Open the picked file in its editor tab and select it in the FileSystem dock. Read-only."
const TIP_REFRESH := "Re-read the folder for %s files -- the current pick stays. Read-only."

var _mode: OptionButton = null
var _picker: OptionButton = null
var _refresh_btn: Button = null
var _show_btn: Button = null
var _open_btn: Button = null
var _status: Label = null
var _graph: GraphEdit = null
## The files the last scan KEPT (typed for the active mode), in picker order. The rows model puts "(none)" at row 0,
## so `_rows[i + 1]` carries `_paths[i]` -- but a pick is always resolved through PickerRows, never by index math.
var _paths: Array[String] = []
## The PickerRows rows currently in `_picker`; `_selected_path` resolves the widget's index through them.
var _rows: Array = []
## Files the last scan SKIPPED because they aren't the active mode's type (a VoiceData in the dialogue folder).
var _skipped := 0
## True once a folder scan has run for the active mode. Before that the buttons can only say "pick one first" --
## an empty `_paths` is not yet "no files found".
var _scanned := false


## PL6: lazy first-reveal latch -- the content-folder scan runs on first reveal, not at panel construction.
var _revealed := false
## Raised by the editor's filesystem_changed (a file under res:// was added, removed or reimported). The rescan waits
## for the NEXT reveal of the tab, so the picker is never rebuilt under the designer's mouse; Refresh stays the
## explicit fallback.
var _fs_dirty := false


func _init() -> void:
	name = "Graphs"
	add_theme_constant_override("separation", 4)

	var bar := HBoxContainer.new()
	_mode = OptionButton.new()
	_mode.add_item("Dialogue")
	_mode.add_item("Quest")
	_mode.tooltip_text = "What to draw: one conversation, or the whole quest chain."
	# Width guards (the PickerRows.apply idiom, by hand -- this dropdown is a fixed pair, not a rows model): never let
	# a dropdown's longest item set the bar's minimum width; a floor keeps "Dialogue" readable instead.
	_mode.fit_to_longest_item = false
	_mode.clip_text = true
	_mode.custom_minimum_size = Vector2(100, 0)
	_mode.item_selected.connect(_on_mode_selected)
	bar.add_child(_mode)

	_picker = OptionButton.new()
	_picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_picker.fit_to_longest_item = false  # PickerRows.apply re-applies both width guards on every fill; set here too so
	_picker.clip_text = true             # the empty pre-scan picker can't size the bar either
	_picker.item_selected.connect(_on_picked)
	bar.add_child(_picker)

	_refresh_btn = Button.new()
	_refresh_btn.text = "Refresh"
	_refresh_btn.pressed.connect(_on_refresh_pressed)
	bar.add_child(_refresh_btn)

	_show_btn = Button.new()
	_show_btn.text = "Show Graph"
	_show_btn.pressed.connect(_build)
	bar.add_child(_show_btn)

	_open_btn = Button.new()
	_open_btn.text = "Open"
	_open_btn.pressed.connect(_open_selected)
	bar.add_child(_open_btn)
	add_child(bar)

	# The ONE status row: two lines max, the tooltip mirrors the full text on every write (_set_status), default font
	# size, slightly dimmed so it reads as a caption. A dialogue with many dangling targets lists them all here --
	# the two-line cap is what keeps that from growing the tab.
	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.max_lines_visible = 2
	_status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_status.modulate = Color(1, 1, 1, 0.75)
	_status.mouse_filter = Control.MOUSE_FILTER_PASS  # a Label ignores the mouse by default, which also hides its tooltip
	add_child(_status)

	_graph = GraphEdit.new()
	_graph.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_graph.custom_minimum_size = Vector2(0, GRAPH_MIN_HEIGHT)
	# View-only: no connecting, no right-click disconnect (defaults false; be explicit), and no minimap -- it eats a
	# corner of an already-short panel and this graph is never big enough to need one.
	_graph.right_disconnects = false
	_graph.minimap_enabled = false
	_graph.show_grid = true
	add_child(_graph)

	_set_status(_idle_status())
	_sync_buttons()
	# Editor-only wiring, guarded so the bare off-tree construction (GUT / the headless probe) never touches
	# EditorInterface: the filesystem signal only FLAGS the list stale (see _fs_dirty). The connection dies with this
	# Control -- Godot disconnects every signal aimed at a freed Object -- so a plugin reload leaves nothing dangling.
	if Engine.is_editor_hint():
		var fs := EditorInterface.get_resource_filesystem()
		if fs != null:
			fs.filesystem_changed.connect(_on_filesystem_changed)
	visibility_changed.connect(_on_visibility_changed)
	_on_visibility_changed()  # lazy: scan the content folder on first reveal, not at panel construction (mirrors content_browser)


## Lazy first-reveal: scan the active-mode folder + fill the picker ONCE, the first time the tab is shown (not at
## construction). Later reveals rescan only when the editor's filesystem changed while the tab was hidden -- and that
## rescan keeps the picked file by path and redraws it, so the graph matches the disk again.
func _on_visibility_changed() -> void:
	if is_visible_in_tree() and not _revealed:
		_revealed = true
		_refresh_picker()
	elif is_visible_in_tree() and _fs_dirty:
		_refresh_picker()


## EditorFileSystem.filesystem_changed: something under res:// changed. Only flag it -- the rescan waits for the next
## reveal (never while the designer is looking at this tab).
func _on_filesystem_changed() -> void:
	_fs_dirty = true


## Mode flipped -- the pick belonged to the OTHER folder, so it is dropped (rows cleared, so `_selected_path` reads
## "") before the rescan: the picker lands on "(none)" with the new mode's idle hint, the graph is cleared, and a
## conversation is never redrawn as a quest.
func _on_mode_selected(_idx: int) -> void:
	_rows = []
	_clear_graph()
	_refresh_picker()


## Refresh: re-read the list; the pick (and its drawing) stays. With nothing picked the idle hint alone would look
## like nothing happened, so the done line leads with what the rescan listed.
func _on_refresh_pressed() -> void:
	_refresh_picker()
	if _selected_path() == "" and not _paths.is_empty():
		_set_status("Refreshed -- %s listed. %s%s" % [_count_text(_paths.size(), _noun()), _idle_status(), _skipped_note()])


## A picker click. "(none)" clears the graph back to the idle hint; a file draws at once (Show Graph is the redraw).
func _on_picked(_idx: int) -> void:
	_sync_buttons()
	if _selected_path() == "":
		_clear_graph()
		_set_status(_idle_status() + _skipped_note())
		return
	_build()


func _is_quest_mode() -> bool:
	return _mode != null and _mode.selected == 1


## The designer-facing noun for the active mode -- what the picker lists and the guard tooltips name.
func _noun() -> String:
	return "quest" if _is_quest_mode() else "conversation"


func _idle_status() -> String:
	return MSG_IDLE_QUEST if _is_quest_mode() else MSG_IDLE_DIALOGUE


## " Skipped N file(s) that aren't <noun>s." after a scan that filtered something out, else "". Appended to the idle
## and empty-folder hints so a designer who saved a voice file in the dialogue folder knows why it isn't listed.
func _skipped_note() -> String:
	if _skipped <= 0:
		return ""
	var noun := _noun()
	if _skipped == 1:
		return " Skipped 1 file that isn't a %s." % noun
	return " Skipped %d files that aren't %ss." % [_skipped, noun]


## Re-scan the active mode's folder and rebuild the picker, keeping the pick BY PATH (never by index -- a file added
## above it must not shift the pick). `want` names a path to point at instead (the select_path handoff); "" keeps the
## current pick. A pick that survives is redrawn so the graph matches the disk; a pick that vanished falls back to
## "(none)" and the idle hint. Clears _fs_dirty: this IS the rescan the filesystem flag asks for.
func _refresh_picker(want: String = "") -> void:
	var keep := want if want != "" else _selected_path()
	_fs_dirty = false
	var quest := _is_quest_mode()
	var scan: Dictionary = typed_paths(_scan_resources(QUEST_DIR if quest else DIALOGUE_DIR), quest)
	var paths: Array[String] = scan["paths"]
	var labels: PackedStringArray = scan["labels"]
	_apply_scan(paths, labels, int(scan["skipped"]), keep)
	if _selected_path() != "":
		_build()


## Push a scan result into the picker + buttons + status. Split from _refresh_picker so a test can feed a fixture
## list without a folder on disk. Points the picker at `want` (row 0 "(none)" when it isn't in `paths`); when nothing
## ends up picked the graph is cleared and the status shows the idle hint -- or the empty-folder hint when the scan
## found nothing at all. When a pick survives, the status is left to the caller's redraw.
func _apply_scan(paths: Array[String], labels: PackedStringArray, skipped: int, want: String) -> void:
	_paths = paths
	_skipped = skipped
	_scanned = true
	_rows = PickerRows.path_rows(PackedStringArray(paths), labels, "", false)
	PickerRows.apply(_picker, _rows, want)
	_sync_buttons()
	if _selected_path() == "":
		_clear_graph()
		if _paths.is_empty():
			_set_status((MSG_NONE_FOUND % _noun()) + _skipped_note(), true)
		else:
			_set_status(_idle_status() + _skipped_note())


## Grey the buttons that cannot apply, with a tooltip naming what is missing (the status message after a click stays
## as the fallback). Show Graph needs a pick in Dialogue mode only -- the quest chain draws the whole folder. Also
## re-words the mode-dependent tooltips (Refresh, the picker) so they name conversations or quests.
func _sync_buttons() -> void:
	var quest := _is_quest_mode()
	var noun := _noun()
	_refresh_btn.tooltip_text = TIP_REFRESH % noun
	# The folder rides the tooltip WITHOUT its scheme prefix: "res://" is engine spelling and belongs nowhere a
	# designer reads, tooltip included (the trim faction_matrix / arch_view make for the same reason).
	_picker.tooltip_text = "The %s to draw. Files come from %s." % [noun, (QUEST_DIR if quest else DIALOGUE_DIR).trim_prefix("res://")]
	if _scanned and _paths.is_empty():
		var none_tip := MSG_NONE_FOUND % noun
		_show_btn.disabled = true
		_show_btn.tooltip_text = none_tip
		_open_btn.disabled = true
		_open_btn.tooltip_text = none_tip
		return
	var picked := _selected_path() != ""
	if quest and _scanned:
		_show_btn.disabled = false
		_show_btn.tooltip_text = TIP_SHOW_QUEST
	else:
		_show_btn.disabled = not picked
		_show_btn.tooltip_text = (TIP_SHOW_QUEST if quest else TIP_SHOW_DIALOGUE) if picked else TIP_PICK_FIRST % noun
	_open_btn.disabled = not picked
	_open_btn.tooltip_text = TIP_OPEN if picked else TIP_PICK_FIRST % noun


## Does this loaded resource belong in the picker for the given mode? Dialogue mode wants a real DialogueResource;
## Quest mode uses the quest loader's duck-typed test (an `id` plus `objectives`) so a binary .res quest or a
## subclass still lists. A failed load (null) or a freed object is refused -- validity is tested BEFORE `is`, which
## hard-crashes on a freed instance. Pure (no editor APIs) so a GUT fixture list exercises it headless.
static func accepts(res: Resource, quest_mode: bool) -> bool:
	if not is_instance_valid(res):
		return false
	if quest_mode:
		return res.get("objectives") != null and res.get("id") != null
	return res is DialogueResource


## The picker label for a kept file. Conversations are named by file name (what the Dialogue tab shows too). Quests
## are "<id>  (<file>)", the Quest tab's idiom: recover_the_package.tres carries id "recover_package", and every
## other surface (conversations, prerequisites, saves) keys on the id -- a filename alone would teach the wrong key.
static func label_for(res: Resource, path: String, quest_mode: bool) -> String:
	if quest_mode and is_instance_valid(res):
		var raw_id: Variant = res.get("id")
		var id := String(raw_id) if raw_id != null else ""
		return "%s  (%s)" % [id if id != "" else "(no id)", path.get_file()]
	return path.get_file()


## Load each scanned path and keep only the ones this mode can draw: {"paths": Array[String], "labels":
## PackedStringArray (parallel), "skipped": int}. The skipped count is what the status reports, so a VoiceData sitting
## in the dialogue folder is explained rather than silently hidden. Loads go through the resource cache, so the later
## draw of a kept file costs nothing extra.
static func typed_paths(candidates: Array[String], quest_mode: bool) -> Dictionary:
	var kept: Array[String] = []
	var labels := PackedStringArray()
	var skipped := 0
	for p in candidates:
		var res: Resource = ResourceLoader.load(p) if ResourceLoader.exists(p) else null
		if not accepts(res, quest_mode):
			skipped += 1
			continue
		kept.append(p)
		labels.append(label_for(res, p, quest_mode))
	return {"paths": kept, "labels": labels, "skipped": skipped}


## Recursively collect *.tres / *.res under `dir`. Returns absolute res:// paths, sorted. Safe when the folder
## is missing (returns empty). EditorInterface-free file IO, so the scan runs headless too.
static func _scan_resources(dir: String, out: Array[String] = []) -> Array[String]:
	var da := DirAccess.open(dir)
	if da == null:
		return out
	da.list_dir_begin()
	var name := da.get_next()
	while name != "":
		if name == "." or name == "..":
			name = da.get_next()
			continue
		var full := dir.path_join(name)
		if da.current_is_dir():
			_scan_resources(full, out)
		elif name.ends_with(".tres") or name.ends_with(".res"):
			out.append(full)
		name = da.get_next()
	da.list_dir_end()
	out.sort()
	return out


## The picked file's path, or "" for "(none)" / nothing picked. Resolved through PickerRows.resolve_pick so a stale
## index (the widget rebuilt under a queued signal) reads as "nothing" instead of the wrong file.
func _selected_path() -> String:
	if _picker == null:
		return ""
	var pick: Dictionary = PickerRows.resolve_pick(_rows, _picker.selected)
	if String(pick.get("action", "")) == "set":
		return String(pick.get("value", ""))
	return ""


## Show Graph: draw the picked conversation, or the whole quest chain. Also runs on every pick and after a rescan.
func _build() -> void:
	if _is_quest_mode():
		_build_quests()
	else:
		_build_dialogue()


func _build_dialogue() -> void:
	var path := _selected_path()
	if path == "":
		_set_status(TIP_PICK_FIRST % _noun(), true)
		return
	var res: Resource = load(path) if ResourceLoader.exists(path) else null
	if not accepts(res, false):
		_clear_graph()
		_set_status("Couldn't show %s: it didn't load as a conversation -- reimport in progress? Press Refresh." % path.get_file(), true)
		return
	var graph: Dictionary = GraphData.build_dialogue(res)
	_render(graph)
	var problems: Array = graph.get("problems", [])
	# The skipped note rides every list-describing status, so the designer always sees why a file isn't listed.
	_set_status(_done_text("Showed %s" % path.get_file(), graph, "line") + _skipped_note(), not problems.is_empty())


## Quest mode draws every quest in the picked quest's folder (the whole quest folder when nothing is picked), so
## prerequisite / next links resolve to real boxes instead of dangling.
func _build_quests() -> void:
	var picked := _selected_path()
	var folder := picked.get_base_dir() if picked != "" else QUEST_DIR
	var quests: Array = _load_quest_set(folder)
	if quests.is_empty():
		_clear_graph()
		_set_status("Couldn't show the quest chain: no quest file loaded -- reimport in progress? Press Refresh.", true)
		return
	var graph: Dictionary = GraphData.build_quests(quests)
	_render(graph)
	var problems: Array = graph.get("problems", [])
	_set_status(_done_text("Showed the quest chain in %s" % folder.get_file(), graph, "quest") + _skipped_note(), not problems.is_empty())


## Load every quest under `folder` (the same typed test the picker uses), so prereq_quest_id links resolve.
func _load_quest_set(folder: String) -> Array:
	var quests: Array = []
	for p in _scan_resources(folder):
		var r: Resource = load(p)
		if accepts(r, true):
			quests.append(r)
	return quests


## The done line: "<head> -- N <noun>s, M links[, K problems: <box>: <what>; ...]." Problems are named by the box's
## title (Line 2 / the quest's title) so the designer can find it in the drawing. The whole list goes in -- the status
## Label clips at two lines and its tooltip carries everything.
static func _done_text(head: String, graph: Dictionary, noun: String) -> String:
	var nodes: Array = graph.get("nodes", [])
	var edges: Array = graph.get("edges", [])
	var problems: Array = graph.get("problems", [])
	var msg := "%s -- %s, %s" % [head, _count_text(nodes.size(), noun), _count_text(edges.size(), "link")]
	if problems.is_empty():
		return msg + "."
	var title_for: Dictionary = {}
	for n in nodes:
		title_for[String(n.get("id"))] = String(n.get("title"))
	var parts: Array[String] = []
	for p in problems:
		var nid := String(p.get("node"))
		parts.append("%s: %s" % [String(title_for.get(nid, nid)), String(p.get("message"))])
	return "%s, %s: %s." % [msg, _count_text(problems.size(), "problem"), "; ".join(parts)]


static func _count_text(n: int, noun: String) -> String:
	return "%d %s%s" % [n, noun, "" if n == 1 else "s"]


## Empty the GraphEdit: drop every connection, then every box. Called from a handler or the reveal latch -- never
## from a GraphNode's own signal -- so an immediate free is safe and leaves nothing queued for a test to trip over.
func _clear_graph() -> void:
	_graph.clear_connections()
	for c in _graph.get_children():
		if c is GraphNode:
			_graph.remove_child(c)
			c.free()


## Render a built graph into the GraphEdit: clear, drop one GraphNode per node positioned by the pure layout,
## then connect edges (best-effort -- GraphEdit needs ports, so every node gets one in + one out slot).
func _render(graph: Dictionary) -> void:
	_clear_graph()

	var pos: Dictionary = GraphData.layout(graph)
	var nodes: Array = graph.get("nodes", [])
	var problems: Array = graph.get("problems", [])
	var problem_ids: Dictionary = {}
	for p in problems:
		problem_ids[String(p.get("node"))] = true

	# id -> the GraphNode name we gave it (GraphEdit connects by node NAME).
	var name_for: Dictionary = {}
	for n in nodes:
		var id: String = String(n.get("id"))
		var gn := GraphNode.new()
		gn.title = String(n.get("title"))
		gn.name = _safe_name(id)
		var body := Label.new()
		body.text = _trim(String(n.get("body")), 90)
		body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		body.custom_minimum_size = Vector2(220, 0)
		gn.add_child(body)
		# One in slot (left) + one out slot (right) on the body row so edges have ports. Enabled L/R, type 0.
		gn.set_slot(0, true, 0, Color.WHITE, true, 0, Color.WHITE)
		if problem_ids.has(id):
			gn.modulate = PROBLEM_COLOR
		var grid: Vector2 = pos.get(id, Vector2.ZERO)
		gn.position_offset = Vector2(grid.x * COL_W + 20.0, grid.y * ROW_H + 20.0)
		_graph.add_child(gn)
		# Record the name AFTER add_child: two ids that differ only in the characters _safe_name folds to "_" would
		# collide, and Godot silently renames the second child on insertion. Reading gn.name back is the only way
		# the edge pass below can connect to the name the node ACTUALLY carries (connect_node keys by node name).
		name_for[id] = gn.name

	for e in graph.get("edges", []):
		var from_id: String = String(e.get("from"))
		var to_id: String = String(e.get("to"))
		if name_for.has(from_id) and name_for.has(to_id):
			_graph.connect_node(String(name_for[from_id]), 0, String(name_for[to_id]), 0)


## GraphNode names must be unique + node-name-legal; map an arbitrary id to a safe stable name.
static func _safe_name(id: String) -> String:
	var s := id.replace("/", "_").replace(":", "_").replace(".", "_").replace(" ", "_")
	return s if s != "" else "node"


static func _trim(s: String, n: int) -> String:
	var one := s.replace("\n", " ").strip_edges()
	return one if one.length() <= n else one.substr(0, n) + "…"


## Open: hand the picked file to the tab that edits it (Dialogue / Quests) through the host, and select it in the
## FileSystem dock. With no host (headless) the Inspector is the fallback, and off the editor entirely it just says so.
func _open_selected() -> void:
	var path := _selected_path()
	if path == "":
		_set_status(TIP_PICK_FIRST % _noun(), true)
		return
	var file := path.get_file()
	var host := Host.find(self)
	if host != null:
		# The host opens the Inspector itself when it has no in-plugin editor for the type, so false is not a failure.
		var routed := Host.open_in_editor(self, path)
		if Engine.is_editor_hint():
			EditorInterface.select_file(path)
		var where := ("the %s tab" % ("Quests" if _is_quest_mode() else "Dialogue")) if routed else "the Inspector"
		_set_status("Opened %s in %s -- also selected in the FileSystem dock." % [file, where])
		return
	if Engine.is_editor_hint():
		if ResourceLoader.exists(path):
			EditorInterface.edit_resource(load(path))
		EditorInterface.select_file(path)
		_set_status("Opened %s in the Inspector -- also selected in the FileSystem dock." % file)
		return
	_set_status("Couldn't open %s: there is no editor to open it in." % file, true)


## Host seam (a "show me this as a graph" handoff): switch to the mode that can draw `path`, re-read its folder so a
## freshly written file is listed, point the picker at it and draw it. true when it was found and drawn; false when
## the file is missing, or is neither a conversation nor a quest, so the caller can fall back to the Inspector.
## Latches `_revealed` first: a handoff can land before the first reveal, and the reveal must not rescan on top.
func select_path(path: String) -> bool:
	if path.is_empty() or not ResourceLoader.exists(path):
		return false
	var res: Resource = load(path)
	var quest := accepts(res, true)
	if not quest and not accepts(res, false):
		return false
	_mode.select(1 if quest else 0)  # select() doesn't emit item_selected; the refresh below does the mode's work
	_rows = []
	_revealed = true
	_refresh_picker(path)
	if _selected_path() != path:
		_set_status("Couldn't show %s: it isn't in the %s folder." % [path.get_file(), _noun()], true)
		return false
	return true


## Status contract: two visible lines, the FULL text mirrored into the tooltip on every write, and the problem tint
## applied through a theme override (never bbcode) so the default font size is untouched.
func _set_status(msg: String, warn: bool = false) -> void:
	if _status == null:
		return
	_status.text = msg
	_status.tooltip_text = msg
	if warn:
		_status.add_theme_color_override("font_color", PROBLEM_COLOR)
	else:
		_status.remove_theme_color_override("font_color")
