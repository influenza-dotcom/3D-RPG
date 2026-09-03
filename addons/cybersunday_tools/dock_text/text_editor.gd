@tool
extends VBoxContainer

## TEXT dock: bulk-edit ALL of the game's player-facing prose — item names/descriptions, stat blurbs, status-effect
## and perk text, quest titles/descriptions, faction + NPC + level names — in ONE searchable, category-grouped
## panel, instead of hunting through two-dozen-plus .tres files in the Inspector. It's driven by text_sources.gd
## (the single registry of where text lives), so every content type shows up here and a future localization export
## can walk the SAME table. "Save Changed Text" writes back ONLY the FIELDS you edited, in ONLY the files you edited,
## each through ContentSaveGuard.save_with_backup (prior bytes -> <file>.tres.bak first, recoverable), then
## FileSystem.update_file so the editor re-reads it.
##
## The .tres stay the SINGLE SOURCE OF TRUTH — this is just a faster editing surface over the same fields, so
## there's no second copy to drift. Follows the Quest/Loot/Dialogue editor contract from
## docs/CYBER_SUNDAY_PLUGIN_QA.md: read-only until Save, backup-before-overwrite, report what changed, lazy first
## reveal. Text nested inside ARRAYS (quest objectives, dialogue lines, bark lists) stays in its own dedicated
## editors — this tab handles the flat, top-level String fields.
##
## PER-FIELD DIRTY (the shared-cache contract): `load(path)` hands every tab the SAME cached Resource, so a quest
## open in Quest Edit and the same quest listed here are ONE object. This tab therefore remembers the text it LOADED
## per field and treats a field as dirty only while its widget differs from that. Save stamps ONLY dirty fields
## (a whole-entry stamp would overwrite the Quest tab's unsaved title with this tab's stale copy), and every later
## reveal re-pushes the CLEAN fields from the live resource so edits made elsewhere show up here. Reload rebuilds
## from the cache too — never CACHE_MODE_REPLACE, which would wipe another tab's unsaved edits on that same object.

const ContentSaveGuard := preload("res://addons/cybersunday_tools/core/content_save_guard.gd")
const TextSources := preload("res://addons/cybersunday_tools/dock_text/text_sources.gd")

const SAVE_TIP := "Write back only the fields you changed, to only the files you changed. Writes those files, keeping each previous copy beside it as .bak."
const SAVE_TIP_CLEAN := "Change some text first."
const RELOAD_TIP := "Reload every text file from disk and rebuild the list -- discards unsaved edits (asks first)."
const SEARCH_TIP := "Type part of an id, file name or the text itself to narrow the list."
const MSG_SCANNING := "Scanning..."
const MSG_EMPTY := "No text found under the content folders -- add an item, quest or faction, then Reload."
const WARN_COLOR := Color(1.0, 0.85, 0.4)

## One editable resource + its field widgets. `block` is the whole per-resource UI group, shown / hidden by the
## search filter; `header` is the id/file line that carries the "* " unsaved marker; `search_key` is the lowercased
## filename + current field text it matches on. Each `fields` row is { "name": property, "edit": LineEdit|TextEdit,
## "loaded": the text this tab last loaded or saved for it } — a field is dirty exactly while edit.text != loaded.
class Entry extends RefCounted:
	var path: String = ""
	var res: Resource = null
	var block: Control = null
	var header: Label = null
	var title: String = ""        # the header line without the "* " marker
	var fields: Array = []        # [{ "name": String, "edit": Control, "loaded": String }]
	var search_key: String = ""

	## The rows whose widget text differs from what was loaded — the ONLY fields Save writes.
	func dirty_fields() -> Array:
		var out: Array = []
		for f in fields:
			var edit: Control = f["edit"]
			if String(edit.text) != String(f["loaded"]):
				out.append(f)
		return out

	func is_dirty() -> bool:
		return not dirty_fields().is_empty()

## One category section: its header Label + the entries under it, so the search filter can hide a header whose
## every entry is filtered out.
class Section extends RefCounted:
	var header: Label = null
	var entries: Array = []       # [Entry]

var _sections: Array = []         # [Section]
var _entries: Array = []          # [Entry] flat, for Save + filter + the reveal re-push
var _list_box: VBoxContainer = null
var _search: LineEdit = null
var _save_btn: Button = null
var _reload_btn: Button = null
var _status: Label = null
var _status_base: String = ""     # the last status message, before the "(unsaved changes)" suffix
var _status_warn := false
var _reload_dialog: ConfirmationDialog = null  # built lazily on the first guarded Reload (in-tree only)

## Lazy first-reveal latch — the folder scans run on first reveal, not at panel construction (mirrors the other
## disk-scanning docks, pinned by tests/test_devtools_lazy_reveal.gd). Later reveals only re-push clean fields.
var _revealed := false


func _init() -> void:
	name = "Text"
	add_theme_constant_override("separation", 4)

	# --- action row: Save (writes ONLY on click), Reload, and a live search filter ----------------------------
	var btn_row := HBoxContainer.new()
	_save_btn = Button.new()
	_save_btn.pressed.connect(_on_save)
	btn_row.add_child(_save_btn)
	_reload_btn = Button.new()
	_reload_btn.text = "Reload"
	_reload_btn.tooltip_text = RELOAD_TIP
	_reload_btn.pressed.connect(_on_reload_pressed)
	btn_row.add_child(_reload_btn)
	_search = LineEdit.new()
	_search.placeholder_text = "Search..."
	_search.tooltip_text = SEARCH_TIP
	_search.clear_button_enabled = true
	_search.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_search.text_changed.connect(_on_search_changed)
	btn_row.add_child(_search)
	add_child(btn_row)

	add_child(HSeparator.new())

	# --- the scrollable, category-grouped editor list ---------------------------------------------------------
	# The scroll floor is the tab's height floor: a TabContainer's minimum is the CURRENT tab's minimum and the
	# editor's bottom splitter keeps whatever height it grew to, so every growing row lives inside this scroller.
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.custom_minimum_size = Vector2(0, 90)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED  # rows fill the width; only scroll vertically
	add_child(scroll)
	_list_box = VBoxContainer.new()
	_list_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list_box.add_theme_constant_override("separation", 6)
	scroll.add_child(_list_box)

	# What the tab just DID or REFUSED (or the next step). Clamped to two lines with the full text on its tooltip,
	# so a long save report can never push the list off a short bottom panel.
	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.max_lines_visible = 2
	_status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_status.modulate = Color(1, 1, 1, 0.75)
	add_child(_status)
	# The pre-reveal line. It is only ever read if the folder scan is still running (the first reveal replaces it),
	# so it says what is happening rather than asking for a step the designer has already taken.
	_set_status(MSG_SCANNING)
	_refresh_dirty_ui()  # Save starts greyed: nothing loaded, nothing changed

	visibility_changed.connect(_on_visibility_changed)
	_on_visibility_changed()  # lazy: scan on first reveal, not now


## Lazy first-reveal: build every section ONCE, the first time the tab is shown. Every LATER reveal re-pushes the
## clean fields from the live (shared, cached) resources so an edit made in Quest Edit / Dialogue Edit shows up
## here without a Reload -- while a field the designer changed HERE keeps their text (see _repush_clean_fields).
func _on_visibility_changed() -> void:
	if is_visible_in_tree() and not _revealed:
		_revealed = true
		_rescan()
	elif is_visible_in_tree() and _revealed:
		_repush_clean_fields()


# --- scan / build ---------------------------------------------------------------------------------------------

## Clear + rebuild every category section from the text_sources registry. Soft-fails per folder/resource: an absent
## folder or a resource missing every declared field just contributes nothing, never an error. Rebuilding drops
## every widget, so any unsaved edit is gone -- the Reload button asks first; this is the raw rebuild.
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
	_refresh_dirty_ui()
	if total == 0:
		_set_status(MSG_EMPTY)
		return
	_set_status("Loaded %s in %s -- change any field, then Save Changed Text." % [
		_count(total, "entry", "entries"), _count(_sections.size(), "category", "categories")])
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
		# The plain cached load on purpose: this object may already be open in Quest Edit / Dialogue Edit, and a
		# CACHE_MODE_REPLACE here would silently reset THEIR unsaved edits (see the header on per-field dirty).
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


## The subset of `fields` (each {name, multiline, label}) that `res` ACTUALLY declares — so a mixed folder only
## shows the fields a given resource really has.
func _present_fields(res: Resource, fields: Array) -> Array:
	var have := {}
	for p in res.get_property_list():
		have[String(p["name"])] = true
	var out: Array = []
	for f in fields:
		if have.has(String(f["name"])):
			out.append(f)
	return out


## Build one resource's editor block: an id/file header, then a label + widget per present field. Each field
## remembers the text it loaded, so editing a widget makes THAT field dirty (the live resource is stamped at Save,
## field by field; Reload rebuilds from the cache).
func _build_entry(path: String, res: Resource, fields: Array) -> Entry:
	var entry := Entry.new()
	entry.path = path
	entry.res = res

	var block := VBoxContainer.new()
	block.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var id_val = res.get("id")
	var id_str: String = String(id_val) if id_val != null and String(id_val) != "" else path.get_file()
	var header := Label.new()
	entry.title = "%s -- %s" % [id_str, path.get_file()]
	header.text = entry.title
	header.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS  # a long id + file name must never widen the dock
	block.add_child(header)
	entry.header = header

	for f in fields:
		var prop: String = f["name"]
		var multiline: bool = bool(f["multiline"])
		var label_text := TextSources.field_label(f)
		var text := _field_text(res, prop)
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
			le.placeholder_text = label_text
			le.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			le.text_changed.connect(_on_line_edited.bind(entry))
			edit = le
		var field_label := Label.new()
		field_label.text = label_text
		field_label.add_theme_color_override("font_color", Color(0.6, 0.6, 0.66))
		block.add_child(field_label)
		block.add_child(edit)
		entry.fields.append({"name": prop, "edit": edit, "loaded": text})

	block.add_child(HSeparator.new())
	_list_box.add_child(block)
	entry.block = block
	entry.search_key = _search_key(entry)
	_entries.append(entry)
	return entry


## The current text of one String property on a resource, "" when unset (a null read must not print "<null>").
func _field_text(res: Resource, prop: String) -> String:
	var cur = res.get(prop)
	return String(cur) if cur != null else ""


# LineEdit.text_changed passes (new_text); TextEdit.text_changed passes nothing. Both re-derive the entry's dirty
# state (a field typed back to its loaded text is clean again) and refresh its search key so freshly typed text
# stays findable by the filter.
func _on_line_edited(_new_text: String, entry: Entry) -> void:
	_mark(entry)

func _on_multiline_edited(entry: Entry) -> void:
	_mark(entry)

func _mark(entry: Entry) -> void:
	entry.search_key = _search_key(entry)
	_render_entry_header(entry)
	_refresh_dirty_ui()


## The "* " unsaved marker on an entry's id/file line, on while any of its fields is dirty.
func _render_entry_header(entry: Entry) -> void:
	if entry.header == null:
		return
	entry.header.text = ("* " + entry.title) if entry.is_dirty() else entry.title


## The lowercased filename + current field text an entry matches the filter on.
func _search_key(entry: Entry) -> String:
	var parts := PackedStringArray([entry.path.get_file()])
	for f in entry.fields:
		var edit: Control = f["edit"]
		parts.append(String(edit.text))
	return " ".join(parts).to_lower()


## Every LATER reveal: copy the live resource's value into every CLEAN field (one whose widget still shows what this
## tab loaded), so a title edited in Quest Edit or a name changed in the Inspector appears here without a Reload.
## A dirty field is left alone -- the designer's unsaved text wins until they Save or Reload.
## The BASELINE moves first, then the widget: `LineEdit.text = ...` is documented not to emit `text_changed`, but
## TextEdit's set_text is a full replace and this must stay correct either way -- with `loaded` already updated, an
## edit handler that DID fire re-derives the field as clean instead of latching a phantom "* " on the header.
func _repush_clean_fields() -> void:
	var updated := 0
	for entry: Entry in _entries:
		if entry.res == null:
			continue
		var touched := false
		for f in entry.fields:
			var edit: Control = f["edit"]
			var loaded: String = String(f["loaded"])
			if String(edit.text) != loaded:
				continue  # dirty here: keep the designer's edit
			var live := _field_text(entry.res, String(f["name"]))
			if live == loaded:
				continue
			f["loaded"] = live
			edit.text = live
			touched = true
			updated += 1
		if touched:
			entry.search_key = _search_key(entry)
			_render_entry_header(entry)
	if updated > 0:
		_apply_filter(_search.text if _search != null else "")
		_refresh_dirty_ui()
		_set_status("Updated %s -- changed in another tab." % _count(updated, "field", "fields"))


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


# --- dirty state ----------------------------------------------------------------------------------------------

## Entries with at least one dirty field -- the number shown on the Save button.
func _dirty_count() -> int:
	var n := 0
	for entry: Entry in _entries:
		if entry.is_dirty():
			n += 1
	return n


## The Save button's text / enabled state and the status suffix, from the dirty count. Save reads
## "Save Changed Text (N)" and is greyed with a "what is missing" tooltip while nothing has changed.
func _refresh_dirty_ui() -> void:
	var n := _dirty_count()
	if _save_btn != null:
		_save_btn.text = ("Save Changed Text (%d)" % n) if n > 0 else "Save Changed Text"
		_save_btn.disabled = n == 0
		_save_btn.tooltip_text = SAVE_TIP if n > 0 else SAVE_TIP_CLEAN
	_render_status()


## The changed file names for the Reload dialog: up to six by name, then "and N more".
func _dirty_names_text() -> String:
	var names := PackedStringArray()
	for entry: Entry in _entries:
		if entry.is_dirty():
			names.append(entry.path.get_file())
	if names.size() <= 6:
		return ", ".join(names)
	var head := PackedStringArray()
	for i in 6:
		head.append(names[i])
	return "%s and %d more" % [", ".join(head), names.size() - 6]


# --- reload ---------------------------------------------------------------------------------------------------

## The Reload command. With unsaved edits it asks first (Save & Reload / Discard / Cancel); otherwise it rescans
## straight away. Cancel leaves everything as it was -- there is no picker here to restore.
func _on_reload_pressed() -> void:
	if _dirty_count() == 0:
		await _reload_now()
		return
	_ask_before_reload()


## Rebuild from the registry, yielding one frame first so "Scanning..." actually paints before the folder walk
## blocks the editor. Handler-only: the await needs the tree (the first-reveal path calls _rescan directly).
func _reload_now() -> void:
	_set_status(MSG_SCANNING)
	_reload_btn.disabled = true
	if is_inside_tree():
		await get_tree().process_frame
	_rescan()
	_reload_btn.disabled = false


## The unsaved-edits guard on Reload, built lazily on first use (a popup needs the tree; _init runs off-tree).
func _ask_before_reload() -> void:
	if _reload_dialog == null:
		_reload_dialog = ConfirmationDialog.new()
		_reload_dialog.title = "Unsaved text"
		_reload_dialog.ok_button_text = "Save & Reload"
		_reload_dialog.cancel_button_text = "Cancel"
		_reload_dialog.add_button("Discard", false, "discard")
		_reload_dialog.confirmed.connect(_on_reload_dialog_save)
		_reload_dialog.custom_action.connect(_on_reload_dialog_action)
		add_child(_reload_dialog)
	_reload_dialog.dialog_text = "Save changes to %s first?" % _dirty_names_text()
	_reload_dialog.popup_centered()


## "Save & Reload": save first; reload only when everything saved, so a failed write never has its edits
## discarded underneath it (the save report stays on the status and the fields stay dirty for a retry).
func _on_reload_dialog_save() -> void:
	_on_save()
	if _dirty_count() > 0:
		# Keeps the save report's file-by-file reasons: the refusal IS "a file wouldn't save", so restating it in
		# other words would hide which one.
		_set_status("Couldn't reload the text -- not everything saved. %s" % _status_base, true)
		return
	await _reload_now()


## "Discard": throw the unsaved edits away and rebuild from the cache.
func _on_reload_dialog_action(action: StringName) -> void:
	if action != &"discard":
		return
	_reload_dialog.hide()
	await _reload_now()


# --- save -----------------------------------------------------------------------------------------------------

## Write back ONLY the dirty fields of ONLY the dirty entries. Each such field is stamped onto the live resource
## (a clean field is never touched, so an edit made to it in another tab survives), then the file persists through
## ContentSaveGuard.save_with_backup (prior bytes -> <path>.tres.bak first), then update_file so the editor re-reads
## it. A saved field's baseline becomes the text that was WRITTEN (so the field reads clean again). Reports the
## saved file names and, per failure, the file name with the plain reason -- never a bare error number, never
## swallowed.
func _on_save() -> void:
	var saved := PackedStringArray()
	var failures := PackedStringArray()
	for entry: Entry in _entries:
		if entry.res == null:
			continue
		var dirty := entry.dirty_fields()
		if dirty.is_empty():
			continue
		# Read each widget ONCE and carry that string through both the stamp and the new baseline. Re-reading
		# `edit.text` after the write would make the "this field is clean now" baseline come from the WIDGET rather
		# than from the value that was actually saved -- the same trap as trusting a widget for a clean baseline
		# anywhere else. (The stamp has to happen before the save: ResourceSaver writes the live object.)
		var staged: Array = []
		for f in dirty:
			var edit: Control = f["edit"]
			var value := String(edit.text)
			staged.append({"field": f, "value": value})
			entry.res.set(String(f["name"]), value)
		var err := ContentSaveGuard.save_with_backup(entry.res, entry.path)
		if err != OK:
			# The live (shared) resource already carries the new text; only the FILE is stale. The fields stay dirty
			# so the reported failure can be retried, and the header keeps its "* ".
			failures.append("%s: %s" % [entry.path.get_file(), error_string(err)])
			push_warning("Text: couldn't save %s: %s" % [entry.path, error_string(err)])
			continue
		if Engine.is_editor_hint():
			EditorInterface.get_resource_filesystem().update_file(entry.path)
		for s in staged:
			var field: Dictionary = s["field"]
			field["loaded"] = String(s["value"])
		_render_entry_header(entry)
		saved.append(entry.path.get_file())
	_refresh_dirty_ui()
	if saved.is_empty() and failures.is_empty():
		_set_status("No changes to save.")
		return
	_set_status(save_report(saved, failures), not failures.is_empty())


## The save status line, pure so it can be pinned headless: "Saved 3 files: a, b, c -- backups .bak." then one
## "Couldn't save <file>: <reason>." per failure (each `failures` row is already "<file>: <reason>").
static func save_report(saved: PackedStringArray, failures: PackedStringArray) -> String:
	var parts := PackedStringArray()
	if not saved.is_empty():
		parts.append("Saved %s: %s -- %s .bak." % [
			_count(saved.size(), "file", "files"), ", ".join(saved), "backup" if saved.size() == 1 else "backups"])
	for row in failures:
		parts.append("Couldn't save %s." % row)
	return " ".join(parts)


## "1 entry" / "3 entries" -- one place for the count wording used across the status lines.
static func _count(n: int, one: String, many: String) -> String:
	return "%d %s" % [n, one if n == 1 else many]


# --- status ---------------------------------------------------------------------------------------------------

## Every status write: the label clamps to two lines, so the tooltip mirrors the whole message. `warn` tints the
## text (a save that failed); a plain write restores the label's default colour. The "(unsaved changes)" suffix
## is re-applied by _render_status from the live dirty count, so it never goes stale under a later message.
func _set_status(msg: String, warn: bool = false) -> void:
	_status_base = msg
	_status_warn = warn
	_render_status()


func _render_status() -> void:
	if _status == null:
		return
	var msg := _status_base
	if _dirty_count() > 0:
		msg += " (unsaved changes)"
	_status.text = msg
	_status.tooltip_text = msg
	if _status_warn:
		_status.add_theme_color_override("font_color", WARN_COLOR)
	else:
		_status.remove_theme_color_override("font_color")
