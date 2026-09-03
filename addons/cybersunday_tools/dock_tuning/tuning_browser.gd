@tool
extends VBoxContainer

## Tuning tab (Tune group of the CYBER SUNDAY panel; Control name "Tuning" -- tests pin it, the panel sets the display
## title): ONE place to find + open every global tuning group. These are the GameSettings groups -- the .tres files in
## resources/tuning/ that every system reads its numbers through (GameSettings.economy.*, GameSettings.camera.*, ...).
## A designer hunting "which page holds the kill bounty?" types part of the SETTING's name into the search and the
## group that carries it surfaces, with the matching setting names on its row. A single click reads the group's own
## description (the doc paragraph at the top of its script) into the status; a double-click (or Enter) opens the
## group in the Inspector through EditorInterface.edit_resource -- no FileSystem-dock hunt. Read-only: nothing here
## writes a file; every edit happens in the Inspector.
##
## SOURCE OF TRUTH: the GameSettings autoload binds each group as `var <name>: <Class> = preload(".tres")`, and EVERY
## one of those .tres lives in resources/tuning/ (verified against managers/GameSettings.gd). Reflecting the autoload
## would mean instantiating a non-@tool Node at edit time; the folder IS the same set and is pure to scan, so we scan
## the folder -- the idiom core/item_scan.gd / item_placer_dock use for resources/items/. Anything else saved in that
## folder (today: punch_strike_curve.tres, a bare Curve) is listed too, named from its file, with no settings of its
## own. The scan (_scan_report / _scan_tuning) and every row helper (_display_name, _export_props,
## _summary_from_source, _match_props, _matches_name) are PURE statics -- no EditorInterface -- so the GUT test can
## assert them headless.
##
## Rows read as the group's display name ONCE ("Economy", "Player Movement", "NPC AI"), derived from the FILE name --
## the class name would only repeat it -- with the class name and the file path on the row tooltip. Row order is
## file-name order; `_shown` stays index-parallel with the rows currently on screen (the search narrows both), so a
## row index is always a valid entry index even mid-filter, and every rebuild restores the pick BY PATH, never by
## row index. Files that exist but fail to load are named in the status instead of silently vanishing from the list.
##
## Layout, top to bottom: ONE head row (search + Refresh), the group list, ONE status label. The ItemList scrolls
## itself (no ScrollContainer wrap needed) and carries a small height floor so this tab can never force the shared
## bottom panel taller than the screen: a TabContainer's minimum is the CURRENT tab's minimum, and the editor's
## bottom splitter keeps the height it grew to.
##
## Host seam (cyber_panel.gd): select_path(path) lets the panel hand a specific tuning file to this tab (find + pick
## it, clearing the search if it hid the row). Off-tree (GUT / the headless probe construct this bare) the only editor
## call -- edit_resource -- lives in the double-click handler, so _init never touches EditorInterface.

## Folder holding the GameSettings tuning groups (the .tres each `GameSettings.<group>` preloads).
const TUNING_DIR := "res://resources/tuning"

## Every group script is named "<Thing>Settings.gd"; the suffix is dropped from the display name because every row
## would otherwise end in the same word. A file without it (the punch curve) keeps its whole stem.
const NAME_SUFFIX := "Settings"

## Words the generic PascalCase split can only render as "Npc" / "Ai" / "Hud" / "Xp", spelled the way a designer
## writes them. Keyed by the split word, so "NpcAiSettings" reads "NPC AI". Extend it when a new group needs one.
const ACRONYMS := {"Npc": "NPC", "Ai": "AI", "Hud": "HUD", "Xp": "XP", "Fp": "FP"}

## How many matching setting names a row shows before folding the rest into "+N more" -- the tooltip lists them all.
const ROW_MATCH_LIMIT := 3

## Status sentences. Idle is the next step; the no-pick guard is shared by both click handlers so a stale row index
## (a rebuild in flight) always says the same thing.
const MSG_IDLE := "Search a group or a setting name, then double-click to open it in the Inspector."
const MSG_NO_PICK := "Pick a group in the list first."
const REFRESH_TIP := "Re-reads the tuning folder and rebuilds the list, keeping the picked group. Read-only."
const SEARCH_TIP := "Type part of a group's name or of a setting's name -- bounty finds the group that holds kill_bounty."

## Status colour for a scan that lost files (the label's default colour is restored on every plain write).
const WARN_COLOR := Color(1.0, 0.85, 0.4)

var _search: LineEdit = null
var _list: ItemList = null
var _refresh_btn: Button = null
var _status: Label = null

## The full scan, file-name order. Each row: { path, name (file stem), desc (class name), res, label (display name),
## summary (the script's doc paragraph), props (its setting names) } -- see _scan_report.
var _entries: Array[Dictionary] = []
## Entry indices of the rows currently shown, index-parallel with the ItemList (the search filter narrows both).
var _shown: Array[int] = []
## Tuning files the last scan found but could not load (reimport in progress, broken script...) -- named in the status.
var _failed: PackedStringArray = PackedStringArray()

## PL6: lazy first-reveal latch -- the folder scan runs on first reveal, not at panel construction (mirrors content_browser).
var _revealed := false


func _init() -> void:
	name = "Tuning"
	add_theme_constant_override("separation", 4)

	# Head row: the search filter (grows) and the one command, above the list so they stay put while the list grows.
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 4)
	add_child(head)

	_search = LineEdit.new()
	_search.placeholder_text = "Search..."
	_search.tooltip_text = SEARCH_TIP
	_search.clear_button_enabled = true
	_search.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_search.text_changed.connect(func(_t: String) -> void: _rebuild_rows(_picked_path()))
	head.add_child(_search)

	_refresh_btn = Button.new()
	_refresh_btn.text = "Refresh"
	_refresh_btn.tooltip_text = REFRESH_TIP
	_refresh_btn.pressed.connect(_on_refresh)
	head.add_child(_refresh_btn)

	_list = ItemList.new()
	_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_list.custom_minimum_size = Vector2(0, 110)  # small floor so the tab can shrink on a short display; the list scrolls itself
	_list.item_selected.connect(_on_selected)     # single click = read the group's description into the status
	_list.item_activated.connect(_on_activated)   # double-click / Enter = open it in the Inspector
	_list.empty_clicked.connect(_on_empty_clicked)  # click below the rows = drop the pick, back to the idle next step
	add_child(_list)

	# What the tab just DID or REFUSED (or the picked group's description). Clamped to two lines with the full text on
	# its tooltip, so a long description or a list of failed files can never push the list off a short bottom panel.
	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.max_lines_visible = 2
	_status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_status.modulate = Color(1, 1, 1, 0.75)
	_status.mouse_filter = Control.MOUSE_FILTER_PASS  # a Label ignores the mouse by default, which also hides its tooltip
	add_child(_status)
	_set_status(MSG_IDLE)

	visibility_changed.connect(_on_visibility_changed)
	_on_visibility_changed()  # no-op off-tree (not visible); in the editor the real reveal fires the signal


## Lazy first-reveal: run the folder scan ONCE, the first time the tab is actually shown (not at construction).
func _on_visibility_changed() -> void:
	if is_visible_in_tree() and not _revealed:
		_revealed = true
		_reload()


## Host seam (cyber_panel.open_in_editor): find + pick the tuning file saved at `path` in this tab's own list and read
## its description into the status. Scans first if the tab has never been revealed, and clears the search when it hid
## the row. true when the row is now picked; false when no such file is in the tuning folder.
func select_path(path: String) -> bool:
	if path.is_empty():
		return false
	if not _revealed:
		# LATCH FIRST: a handoff can land before the tab has ever been shown, and this scan IS the first one. Without
		# the latch the reveal that follows runs _reload() a second time, and _reload ends by writing the idle hint --
		# wiping the "Picked <Name> -- ..." description this handoff just put on the status.
		_revealed = true
		_reload()
	if _select_by_path(path):
		return true
	if _search != null and _search.text != "":
		_search.text = ""  # the setter does not emit text_changed, so rebuild by hand
		_rebuild_rows(path)
		return _picked_path() == path
	return false


## Every status write: the label clamps to two lines, so the tooltip mirrors the whole message. `warn` tints the text
## (a scan that lost files, a row that would not open); a plain write restores the label's default colour.
func _set_status(msg: String, warn: bool = false) -> void:
	if _status == null:
		return
	_status.text = msg
	_status.tooltip_text = msg
	if warn:
		_status.add_theme_color_override("font_color", WARN_COLOR)
	else:
		_status.remove_theme_color_override("font_color")


## The explicit Refresh command: re-read the folder (keeping the pick by path) and say so -- unless the scan has
## something to complain about, in which case _reload's own message stays.
func _on_refresh() -> void:
	_reload()
	if _failed.is_empty() and not _entries.is_empty():
		_set_status("Refreshed the tuning list -- %s; search, or double-click a group to open it." % _count(_entries.size(), "group", "groups"))


## Re-read the tuning folder, rebuild the rows through the current search, and restore the previously picked group BY
## PATH (a row index is meaningless after a new file). Writes the scan verdict to the status: the idle next step, or
## the files that failed to load.
func _reload() -> void:
	var keep := _picked_path()
	var rep := _scan_report()
	_entries = []
	for row: Dictionary in rep["rows"]:
		_entries.append(row)
	_failed = rep["failed"]
	_rebuild_rows(keep)
	if not _failed.is_empty():
		var names := PackedStringArray()
		for p: String in _failed:
			names.append(p.get_file())
		_set_status("Couldn't load %s: %s -- still importing? press Refresh." % [_count(_failed.size(), "tuning file", "tuning files"), ", ".join(names)], true)
	elif _entries.is_empty():
		_set_status("No tuning groups found in the tuning folder -- press Refresh once the editor has finished importing.", true)
	else:
		_set_status(MSG_IDLE)


## Rebuild the ItemList rows from `_entries` through the search, keeping `_shown` index-parallel with what is on
## screen, then re-pick `keep_path` if its row survived. A row that the search reached through a SETTING name shows
## the matching names after the group ("Economy -- kill_bounty, headshot_kill_bounty, +2 more"); the tooltip lists
## them all. ItemList.clear() drops the selection silently (no item_selected), so the status is re-derived here: the
## no-match sentence, the restored pick's description, or the idle next step.
func _rebuild_rows(keep_path: String = "") -> void:
	if _list == null:
		return
	_list.clear()
	_shown = []
	var query := _search.text.strip_edges().to_lower() if _search != null else ""
	for i in _entries.size():
		var e: Dictionary = _entries[i]
		var hits := _match_props(e, query)
		if query != "" and hits.is_empty() and not _matches_name(e, query):
			continue
		var text := String(e.get("label", "?"))
		if not hits.is_empty():
			text += " -- " + ", ".join(hits.slice(0, ROW_MATCH_LIMIT))
			if hits.size() > ROW_MATCH_LIMIT:
				text += ", +%d more" % (hits.size() - ROW_MATCH_LIMIT)
		var idx := _list.add_item(text)
		_list.set_item_tooltip(idx, _row_tooltip(e, hits))  # class name + file path live on the tooltip, never in the row text
		_shown.append(i)
	if _select_by_path(keep_path):
		return
	if _shown.is_empty() and query != "":
		_set_status("No group or setting matches '%s' -- clear the search to see every group." % _search.text.strip_edges())
	else:
		_set_status(MSG_IDLE)


## Pick the shown row whose file is `path` (no-op on ""), scrolling it into view and reading its description into the
## status -- ItemList.select() does not emit item_selected, so the handler runs by hand. false when no shown row matches.
func _select_by_path(path: String) -> bool:
	if _list == null or path.is_empty():
		return false
	for row in _shown.size():
		var e: Dictionary = _entries[_shown[row]]
		if String(e.get("path", "")) == path:
			_list.select(row)
			_list.ensure_current_is_visible()
			_on_selected(row)
			return true
	return false


## The entry behind shown row `row`, or {} for a stale index (a rebuild in flight, nothing picked).
func _entry_at(row: int) -> Dictionary:
	if row < 0 or row >= _shown.size():
		return {}
	var i: int = _shown[row]
	if i < 0 or i >= _entries.size():
		return {}
	return _entries[i]


## The picked group's entry, or {} when nothing is picked.
func _picked_entry() -> Dictionary:
	if _list == null:
		return {}
	var sel := _list.get_selected_items()
	if sel.is_empty():
		return {}
	return _entry_at(sel[0])


## The picked group's file path, or "" -- the key every rescan / search rebuild restores the pick by.
func _picked_path() -> String:
	return String(_picked_entry().get("path", ""))


## Single click: read the group's description into the status -- "Picked <Name> -- <N> settings; double-click to
## open it in the Inspector. <doc paragraph>" (the label clamps to two lines; the tooltip carries the rest). Nothing
## opens on a single click: the Inspector jump is the double-click, exactly as the idle status says.
func _on_selected(row: int) -> void:
	var e := _entry_at(row)
	if e.is_empty():
		_set_status(MSG_NO_PICK)
		return
	var props_v: Variant = e.get("props", PackedStringArray())
	var n: int = props_v.size() if props_v is PackedStringArray else 0
	var count := "no settings of its own" if n == 0 else _count(n, "setting", "settings")
	var text := "Picked %s -- %s; double-click to open it in the Inspector." % [String(e.get("label", "?")), count]
	var summary := String(e.get("summary", ""))
	if summary != "":
		text += " " + summary
	_set_status(text)


## Double-click / Enter: open the group in the Inspector. EDITOR-ONLY (EditorInterface) -- not exercised by the test.
## Every early return writes its sentence to the status, because a double-click reaches here with no button to grey.
func _on_activated(row: int) -> void:
	var e := _entry_at(row)
	if e.is_empty():
		_set_status(MSG_NO_PICK)
		return
	var label := String(e.get("label", "?"))
	var res: Resource = e.get("res", null)
	if res == null:
		_set_status("Couldn't open %s: its file did not load -- press Refresh." % label, true)
		return
	EditorInterface.edit_resource(res)
	_set_status("Opened %s in the Inspector -- change its numbers there." % label)


## A click below the last row drops the pick (ItemList leaves the old selection in place by itself) and returns the
## status to the idle next step, so a description never lingers for a row that is no longer highlighted.
func _on_empty_clicked(_at: Vector2, _button: int) -> void:
	if _list != null:
		_list.deselect_all()
	_set_status(MSG_IDLE)


# ──────────────────────────────────────────────────────────────────────────────────────────────────────────
# Pure helpers -- no EditorInterface, no scene tree; the GUT test exercises these headless
# ──────────────────────────────────────────────────────────────────────────────────────────────────────────

## The folder scan every reveal / Refresh runs: { rows: Array[Dictionary], failed: PackedStringArray }. Each row is
## { path, name (file stem), desc (class name), res, label (display name), summary (doc paragraph), props (setting
## names) }, sorted by file stem; `failed` lists the resource files that exist but would not load (a reimport in
## progress, a broken script) so the status can name them instead of letting them vanish from the list.
static func _scan_report() -> Dictionary:
	var rows: Array[Dictionary] = []
	var failed := PackedStringArray()
	var dir := DirAccess.open(TUNING_DIR)
	if dir == null:
		return {"rows": rows, "failed": failed}
	for f in dir.get_files():
		var fname: String = String(f).trim_suffix(".remap")   # exported builds may append .remap to packed resources
		if not (fname.ends_with(".tres") or fname.ends_with(".res")):
			continue
		var path := TUNING_DIR.path_join(fname)
		var res := load(path) as Resource
		if res == null:
			failed.append(path)
			continue
		var stem := fname.get_basename()
		rows.append({
			"path": path,
			"name": stem,
			"desc": _describe(res),
			"res": res,
			"label": _display_name(stem),
			"summary": _summary_from_source(res),
			"props": _export_props(res),
		})
	rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return String(a["name"]) < String(b["name"]))
	return {"rows": rows, "failed": failed}


## The rows of _scan_report alone (the shape the GUT test pins: path / name / desc / res on every row). Files that
## failed to load are dropped here; the tab reads _scan_report directly so it can name them.
static func _scan_tuning() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for row: Dictionary in _scan_report()["rows"]:
		out.append(row)
	return out


## The resource's script class_name (the GameSettings group type), e.g. "EconomySettings" -- the row TOOLTIP, since the
## display name already carries the same word once. Falls back to the base class name (a bare Curve reads "Curve").
static func _describe(res: Resource) -> String:
	if res == null:
		return ""
	var scr: Variant = res.get_script()
	if scr is GDScript:
		var gname := String((scr as GDScript).get_global_name())
		if gname != "":
			return gname
	return res.get_class()


## The row label for a tuning file: the file stem minus the shared "Settings" suffix, split into words, with the few
## acronyms spelled the way a designer writes them -- "EconomySettings" -> "Economy", "PlayerMovementSettings" ->
## "Player Movement", "NpcAiSettings" -> "NPC AI", "punch_strike_curve" -> "Punch Strike Curve". Derived from the
## FILE name, never the class name, so a row never reads the same word twice. Editor tooling only: these labels are
## a developer surface and are never routed through PlayerText.
static func _display_name(stem: String) -> String:
	var base := stem
	if base.length() > NAME_SUFFIX.length() and base.ends_with(NAME_SUFFIX):
		base = base.trim_suffix(NAME_SUFFIX)
	var words := base.capitalize().split(" ", false)
	for i in words.size():
		var w: String = words[i]
		if ACRONYMS.has(w):
			words[i] = String(ACRONYMS[w])
	var out := " ".join(words)
	return out if out != "" else stem


## The names of the group's own @export settings -- the script's exported variables, nothing inherited from Resource
## (resource_name, script, metadata...), no plain (unexported) script variables and no @export_group headers. What
## the search matches on, and the count the status reports. Empty for a scriptless file (a bare Curve).
static func _export_props(res: Resource) -> PackedStringArray:
	var out := PackedStringArray()
	if res == null:
		return out
	for p in res.get_property_list():
		var prop: Dictionary = p
		var usage: int = int(prop.get("usage", 0))
		if (usage & PROPERTY_USAGE_SCRIPT_VARIABLE) == 0 or (usage & PROPERTY_USAGE_EDITOR) == 0:
			continue
		if (usage & (PROPERTY_USAGE_GROUP | PROPERTY_USAGE_SUBGROUP | PROPERTY_USAGE_CATEGORY)) != 0:
			continue
		var pname := String(prop.get("name", ""))
		if pname != "":
			out.append(pname)
	return out


## The group's own description: the FIRST doc paragraph (the run of "##" lines) at the top of its script, before any
## code -- every tuning group opens with one ("The economy's designer knobs -- every bounty..."). A doc line attached
## to the first @export is NOT the group's description, so the scan stops at the first code line; a blank "##" line
## ends the paragraph. "" when the file has no header doc or no script (a bare Curve). Reads the script's source
## text, so it costs one file read per group at scan time and nothing while the tab sits open.
static func _summary_from_source(res: Resource) -> String:
	if res == null:
		return ""
	var scr: Variant = res.get_script()
	if not (scr is Script):
		return ""
	var src_path := String((scr as Script).resource_path)
	if src_path == "" or not FileAccess.file_exists(src_path):
		return ""
	var lines := PackedStringArray()
	for raw in FileAccess.get_file_as_string(src_path).split("\n"):
		var line: String = String(raw).strip_edges()
		if line.begins_with("##"):
			var body := line.trim_prefix("##").strip_edges()
			if body == "" and not lines.is_empty():
				break  # a blank "##" line is a paragraph break -- the description is the first paragraph only
			if body != "":
				lines.append(body)
			continue
		if not lines.is_empty():
			break  # the doc block ended (a blank line, or code)
		if line == "" or line.begins_with("class_name") or line.begins_with("extends") or line.begins_with("@tool") or line.begins_with("@icon") or line.begins_with("#"):
			continue  # the lines a script may open with before its description
		break  # code before any doc block: this script has no header description
	return " ".join(lines)


## The setting names in `entry` that contain `query` -- lower-case, with spaces read as underscores so "kill bounty"
## finds kill_bounty. Empty for a blank query: a blank search matches by NAME only, so rows stay clean.
static func _match_props(entry: Dictionary, query: String) -> PackedStringArray:
	var out := PackedStringArray()
	var q := query.strip_edges().to_lower().replace(" ", "_")
	if q == "":
		return out
	var props_v: Variant = entry.get("props", PackedStringArray())
	if not (props_v is PackedStringArray):
		return out
	for p: String in props_v:
		if p.to_lower().contains(q):
			out.append(p)
	return out


## True when `query` is part of the group's display name, file name or class name -- compared lower-case with spaces
## and underscores dropped, so "player movement", "playermovement" and "PlayerMovementSettings" all find Player
## Movement. A blank query matches every group.
static func _matches_name(entry: Dictionary, query: String) -> bool:
	var q := query.strip_edges().to_lower().replace(" ", "").replace("_", "")
	if q == "":
		return true
	for key in ["label", "name", "desc"]:
		var v := String(entry.get(key, "")).to_lower().replace(" ", "").replace("_", "")
		if v.contains(q):
			return true
	return false


## A row's hover text: the class name and the file path (the two engine-side names the row itself does not show), plus
## every matching setting name when the search reached the row through one -- the row folds those past ROW_MATCH_LIMIT.
static func _row_tooltip(entry: Dictionary, hits: PackedStringArray) -> String:
	var desc := String(entry.get("desc", ""))
	var path := String(entry.get("path", ""))
	var tip := ("%s -- %s" % [desc, path]) if desc != "" else path
	if not hits.is_empty():
		tip += "\nMatching settings: " + ", ".join(hits)
	return tip


## "1 group" / "3 groups" -- editor prose, so a plain pick between the two forms is enough (never PlayerText).
static func _count(n: int, one: String, many: String) -> String:
	return "%d %s" % [n, one if n == 1 else many]
