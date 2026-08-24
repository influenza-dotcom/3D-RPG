@tool
extends VBoxContainer

## TEXT dock: bulk-edit ALL of the game's player-facing prose — item names/descriptions, stat blurbs, status-effect
## and perk text, quest titles/descriptions, faction + NPC + level names — in ONE searchable, category-grouped
## panel, instead of hunting through two-dozen-plus .tres files in the Inspector. It's driven by text_sources.gd
## (the single registry of where text lives), so every content type shows up here and a future localization export
## can walk the SAME table. "Save Changed" writes back ONLY the resources you edited, each through
## ContentSaveGuard.save_with_backup (prior bytes -> <file>.tres.bak first, recoverable), then FileSystem.update_file.
##
## The .tres stay the SINGLE SOURCE OF TRUTH — this is just a faster editing surface over the same fields, so
## there's no second copy to drift. Follows the Quest/Loot/Dialogue editor contract from
## docs/CYBER_SUNDAY_PLUGIN_QA.md: read-only until Save, backup-before-overwrite, report what changed, lazy first
## reveal. Text nested inside ARRAYS (quest objectives, dialogue lines, bark lists) stays in its own dedicated
## editors — this tab handles the flat, top-level String fields.

const ContentSaveGuard := preload("res://addons/cybersunday_tools/core/content_save_guard.gd")
const TextSources := preload("res://addons/cybersunday_tools/dock_text/text_sources.gd")

## One editable resource + its field widgets + a dirty flag. `block` is the whole per-resource UI group, shown /
## hidden by the search filter; `search_key` is the lowercased id + filename + current field text it matches on.
class Entry extends RefCounted:
	var path: String = ""
	var res: Resource = null
	var block: Control = null
	var fields: Array = []       # [{ "name": String, "edit": Control }]  (edit is a LineEdit or a TextEdit)
	var search_key: String = ""
	var dirty: bool = false

## One category section: its header Label + the entries under it, so the search filter can hide a header whose
## every entry is filtered out.
class Section extends RefCounted:
	var header: Label = null
	var entries: Array = []       # [Entry]

var _sections: Array = []         # [Section]
var _entries: Array = []          # [Entry] flat, for Save + filter
var _list_box: VBoxContainer = null
var _search: LineEdit = null
var _status: Label = null

## Lazy first-reveal latch — the folder scans run on first reveal, not at panel construction (mirrors the other
## disk-scanning docks, pinned by tests/test_devtools_lazy_reveal.gd).
var _revealed := false


func _init() -> void:
	name = "Text"
	add_theme_constant_override("separation", 4)
	custom_minimum_size = Vector2(0, 110)  # small floor so the bottom panel can still shrink on a short display

	var title := Label.new()
	title.text = "Text — bulk-edit every bit of game prose (items, stats, perks, status, quests, factions, NPCs, levels)"
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART  # wrap this long sentence on a narrow dock instead of clipping
	add_child(title)

	# --- action row: Save (writes ONLY on click), Reload, and a live search filter ----------------------------
	var btn_row := HBoxContainer.new()
	var save := Button.new()
	save.text = "Save Changed"
	save.tooltip_text = "Write back only the resources you edited (each backed up to <file>.tres.bak first)."
	save.pressed.connect(_on_save)
	btn_row.add_child(save)
	var reload := Button.new()
	reload.text = "Reload"
	reload.tooltip_text = "Re-scan the content folders and reload text from disk (discards unsaved edits)."
	reload.pressed.connect(_rescan)
	btn_row.add_child(reload)
	_search = LineEdit.new()
	_search.placeholder_text = "filter by name / id / text…"
	_search.clear_button_enabled = true
	_search.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_search.text_changed.connect(_on_search_changed)
	btn_row.add_child(_search)
	add_child(btn_row)

	add_child(HSeparator.new())

	# --- the scrollable, category-grouped editor list ---------------------------------------------------------
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.custom_minimum_size = Vector2(0, 60)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED  # rows fill the width; only scroll vertically
	add_child(scroll)
	_list_box = VBoxContainer.new()
	_list_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list_box.add_theme_constant_override("separation", 6)
	scroll.add_child(_list_box)

	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.add_theme_font_size_override("font_size", 10)
	add_child(_status)

	visibility_changed.connect(_on_visibility_changed)
	_on_visibility_changed()  # lazy: scan on first reveal, not now


## Lazy first-reveal: build every section ONCE, the first time the tab is shown.
func _on_visibility_changed() -> void:
	if is_visible_in_tree() and not _revealed:
		_revealed = true
		_rescan()


# --- scan / build ---------------------------------------------------------------------------------------------

## Clear + rebuild every category section from the text_sources registry. Soft-fails per folder/resource: an absent
## folder or a resource missing every declared field just contributes nothing, never an error.
func _rescan() -> void:
	for c in _list_box.get_children():
		c.queue_free()
	_sections.clear()
	_entries.clear()
	var total := 0
	for source in TextSources.SOURCES:
		var section := _build_section(source)
		if section != null:
			_sections.append(section)
			total += section.entries.size()
	if total == 0:
		_set_status("No editable text found under the registered content folders.")
		return
	_set_status("Loaded %d text entr%s across %d categor%s. Edit, then Save Changed." % [
		total, "y" if total == 1 else "ies", _sections.size(), "y" if _sections.size() == 1 else "ies"])
	_apply_filter(_search.text if _search != null else "")


## Build one category: a header + a block per resource that actually carries at least one of the declared fields.
## Returns null (adds nothing) when the folder is absent or holds no matching resource, so an empty category never
## shows a bare header.
func _build_section(source: Dictionary) -> Section:
	var dir: String = source["dir"]
	if not DirAccess.dir_exists_absolute(dir):
		return null
	var fields: Array = source["fields"]
	var section := Section.new()

	var header := Label.new()
	header.text = "  ▸ %s" % source["label"]
	header.add_theme_font_size_override("font_size", 12)
	header.add_theme_color_override("font_color", Color(0.65, 0.78, 1.0))
	_list_box.add_child(header)
	section.header = header

	var names := PackedStringArray(DirAccess.get_files_at(dir))
	names.sort()
	for n in names:
		# Accept BOTH resource extensions, like loot_editor / item_placer_dock / scene_placer / inspector_calc:
		# a binary-saved .res is a real authored resource and its prose must not be silently invisible here.
		var fname := n.trim_suffix(".remap")
		var ext := fname.get_extension().to_lower()
		if ext != "tres" and ext != "res":
			continue
		var path := dir.path_join(fname)
		var res := load(path)
		if res == null or not (res is Resource):
			continue
		var present := _present_fields(res, fields)
		if present.is_empty():
			continue  # this .tres in the folder isn't a text-bearing type (mixed folders) — skip it
		section.entries.append(_build_entry(path, res, present))

	if section.entries.is_empty():
		header.queue_free()  # no rows -> drop the empty header we optimistically added
		return null
	return section


## The subset of `fields` (each {name, multiline}) that `res` ACTUALLY declares — so a mixed folder only shows the
## fields a given resource really has.
func _present_fields(res: Resource, fields: Array) -> Array:
	var have := {}
	for p in res.get_property_list():
		have[String(p["name"])] = true
	var out: Array = []
	for f in fields:
		if have.has(String(f["name"])):
			out.append(f)
	return out


## Build one resource's editor block: an id/file header, then a label + widget per present field. Editing any
## widget flips the entry dirty (the live resource is stamped at Save, so Reload reverts).
func _build_entry(path: String, res: Resource, fields: Array) -> Entry:
	var entry := Entry.new()
	entry.path = path
	entry.res = res

	var block := VBoxContainer.new()
	block.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var id_val = res.get("id")
	var id_str: String = String(id_val) if id_val != null and String(id_val) != "" else path.get_file()
	var header := Label.new()
	header.text = "%s   —   %s" % [id_str, path.get_file()]
	header.add_theme_font_size_override("font_size", 11)
	block.add_child(header)

	for f in fields:
		var prop: String = f["name"]
		var multiline: bool = bool(f["multiline"])
		var cur = res.get(prop)
		var text: String = String(cur) if cur != null else ""
		var edit: Control
		if multiline:
			var te := TextEdit.new()
			te.text = text
			te.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
			te.custom_minimum_size = Vector2(0, 48)
			te.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			te.text_changed.connect(_on_multiline_edited.bind(entry))  # bound Callable, not a lambda (freed-capture-safe)
			edit = te
		else:
			var le := LineEdit.new()
			le.text = text
			le.placeholder_text = prop
			le.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			le.text_changed.connect(_on_line_edited.bind(entry))
			edit = le
		var field_label := Label.new()
		field_label.text = prop
		field_label.add_theme_font_size_override("font_size", 9)
		field_label.add_theme_color_override("font_color", Color(0.6, 0.6, 0.66))
		block.add_child(field_label)
		block.add_child(edit)
		entry.fields.append({"name": prop, "edit": edit})

	block.add_child(HSeparator.new())
	_list_box.add_child(block)
	entry.block = block
	entry.search_key = _search_key(entry)
	_entries.append(entry)
	return entry


# LineEdit.text_changed passes (new_text); TextEdit.text_changed passes nothing. Both just dirty the whole entry
# and refresh its search key (so freshly typed text stays findable by the filter).
func _on_line_edited(_new_text: String, entry: Entry) -> void:
	_mark(entry)

func _on_multiline_edited(entry: Entry) -> void:
	_mark(entry)

func _mark(entry: Entry) -> void:
	entry.dirty = true
	entry.search_key = _search_key(entry)


## The lowercased id + filename + current field text an entry matches the filter on.
func _search_key(entry: Entry) -> String:
	var parts := PackedStringArray([entry.path.get_file()])
	for f in entry.fields:
		parts.append(String(f["edit"].text))
	return " ".join(parts).to_lower()


# --- search filter --------------------------------------------------------------------------------------------

func _on_search_changed(text: String) -> void:
	_apply_filter(text)

## Show only entries whose search key contains the query; hide a category header whose every entry is filtered out.
func _apply_filter(query: String) -> void:
	var q := query.strip_edges().to_lower()
	for section: Section in _sections:
		var any_visible := false
		for entry: Entry in section.entries:
			var vis := q == "" or entry.search_key.contains(q)
			if entry.block != null:
				entry.block.visible = vis
			any_visible = any_visible or vis
		if section.header != null:
			section.header.visible = any_visible


# --- save -----------------------------------------------------------------------------------------------------

## Write back ONLY the edited resources. Each dirty entry stamps its widget text onto the live resource, then
## persists through ContentSaveGuard.save_with_backup (prior bytes -> <path>.tres.bak first), then update_file so
## the editor re-reads it. Reports exactly what saved; a failure is counted + surfaced, never swallowed.
func _on_save() -> void:
	var saved: Array[String] = []
	var failed := 0
	for entry: Entry in _entries:
		if not entry.dirty or entry.res == null:
			continue
		for f in entry.fields:
			entry.res.set(String(f["name"]), String(f["edit"].text))
		var err := ContentSaveGuard.save_with_backup(entry.res, entry.path)
		if err != OK:
			failed += 1
			push_warning("Text: FAILED to save %s (err %d)" % [entry.path, err])
			continue
		if Engine.is_editor_hint():
			EditorInterface.get_resource_filesystem().update_file(entry.path)
		entry.dirty = false
		saved.append(entry.path.get_file())
	if saved.is_empty() and failed == 0:
		_set_status("No changes to save.")
		return
	var msg := "Saved %d file(s): %s" % [saved.size(), ", ".join(saved)]
	if failed > 0:
		msg += "   —   %d FAILED (see Output)." % failed
	_set_status(msg)


func _set_status(msg: String) -> void:
	if _status != null:
		_status.text = msg
