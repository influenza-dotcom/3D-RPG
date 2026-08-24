@tool
extends VBoxContainer

## Faction matrix dock: an N x N grid of OptionButtons editing who-is-hostile/neutral/friendly to whom.
## Rows = "from" faction, columns = "to" faction; each cell sets the FROM faction's relation toward the TO
## faction. Editing a cell writes the relation onto the Faction resource and saves that .tres (so it persists to
## disk). The save is wrapped: a failure reports on the status Label instead of corrupting.
##
## WRITE CONTRACT: unlike the Dialogue/Quest/Loot/Text editors there is no Save button here — a cell change IS the
## commit, because a 3-way dropdown has no in-progress state worth staging. That makes the write UNDO-able only via
## the on-disk backup, so it goes through ContentSaveGuard.save_with_backup like every other content editor: the
## prior bytes land in <path>.tres.bak first, so a stray click (or an arrow-key scroll over a focused cell) is
## recoverable by renaming the .bak back. The status Label names the exact path written, every time.
##
## Storage matches scripts/faction/faction.gd EXACTLY: Faction.relations is a Dictionary keyed by the OTHER
## faction's `id` (StringName) -> a float relation score (<0 enemies / 0 neutral / >0 allies), read by
## Faction.relation_to(). This dock only edits relations -- it never touches id / display_name /
## default_disposition (deliberately warned-only / save-data-sensitive twins).
##
## The factions are enumerated via scripts/faction/factions.gd (Factions.ids() scans resources/factions/),
## then resolved with Factions.by_id() to get the live Faction resource to edit.

const RELATION_DIR := "res://resources/factions/"
## The faction registry (factions.gd has NO class_name on purpose -> preload it) -- enumerates + resolves the .tres.
const Factions := preload("res://scripts/faction/factions.gd")
## Recoverable saves: prior bytes -> <path>.tres.bak before every overwrite (the same guard the content editors use).
const ContentSaveGuard := preload("res://addons/cybersunday_tools/core/content_save_guard.gd")

## The three discrete relation buckets the matrix offers, mapped to the float score stored in Faction.relations.
## A cell shows the bucket nearest the stored float (see _bucket_for / RELATION_VALUES). Enemy => -1 (NPC.is_hostile
## fires on <0); Neutral => 0 (Faction.relation_to also returns 0 for an UNLISTED faction); Ally => +1.
const RELATION_LABELS := ["Enemy", "Neutral", "Ally"]
const RELATION_VALUES := [-1.0, 0.0, 1.0]

var _grid: GridContainer = null
var _status: Label = null
var _factions: Array = []  ## Array[Faction], parallel to _ids
var _ids: PackedStringArray = PackedStringArray()

## Lazy first-reveal latch — the faction scan (which LOADS every .tres under resources/factions/ and builds an
## N x N OptionButton grid) runs on first reveal, not at panel construction. cyber_panel._init() builds all 22 tabs
## eagerly, and the editor reconstructs the panel on every plugin reload, so an _init-time scan costs a full folder
## load on every editor start even when this tab is never opened. Mirrors content_browser / tuning_browser /
## item_placer_dock (pinned by tests/test_devtools_lazy_reveal.gd).
var _revealed := false


func _init() -> void:
	name = "Factions"
	add_theme_constant_override("separation", 4)

	var title := Label.new()
	title.text = "Faction Relations"
	add_child(title)

	var hint := Label.new()
	hint.text = "Row = from, Col = toward. Editing a cell saves that faction's .tres."
	hint.add_theme_font_size_override("font_size", 10)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART  # wrap on a narrow dock instead of clipping the tail
	add_child(hint)

	var refresh := Button.new()
	refresh.text = "Reload Factions"
	refresh.pressed.connect(_rebuild)
	add_child(refresh)

	add_child(HSeparator.new())

	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.custom_minimum_size = Vector2(0, 120)  # small floor so the dock can shrink on a short display
	add_child(scroll)

	_grid = GridContainer.new()
	_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_grid)

	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.add_theme_font_size_override("font_size", 10)
	add_child(_status)

	visibility_changed.connect(_on_visibility_changed)
	_on_visibility_changed()  # lazy: scan factions on first reveal, not at panel construction


## Lazy first-reveal: load the factions + build the grid ONCE, the first time the tab is actually shown.
func _on_visibility_changed() -> void:
	if is_visible_in_tree() and not _revealed:
		_revealed = true
		_rebuild()


# --- pure relation helpers (testable WITHOUT disk / EditorInterface) ---------------------------------------------

## Set faction `a`'s relation toward faction `b` to `value` (the same write the dock's cell performs, MINUS the
## disk save). Stores under b.id in a.relations -- matching Faction.relation_to(b.id). A neutral (0.0) clears the
## entry so the .tres stays clean (Faction.relation_to returns 0 for an unlisted id anyway). No-ops on nulls / empty
## b.id. Pure + static so the test can round-trip it on throwaway Faction.new()s.
static func set_relation(a: Faction, b: Faction, value: float) -> void:
	if a == null or b == null:
		return
	var key := StringName(b.id)
	if String(key).is_empty():
		return
	if is_equal_approx(value, 0.0):
		a.relations.erase(key)
	else:
		a.relations[key] = value

## Faction `a`'s relation score toward faction `b` (0.0 if unset / nulls), via the SAME read as runtime
## (Faction.relation_to). Pure mirror of set_relation for the round-trip test.
static func get_relation(a: Faction, b: Faction) -> float:
	if a == null or b == null:
		return 0.0
	# Read the relations Dictionary DIRECTLY (mirrors Faction.relation_to) -- a property read works in the editor's
	# tool mode, whereas calling relation_to() (faction.gd isn't @tool) errors on dock init at edit time.
	return float(a.relations.get(StringName(b.id), 0.0))

## The RELATION_VALUES index whose bucket best matches `score` (<0 => Enemy, 0 => Neutral, >0 => Ally).
static func bucket_for(score: float) -> int:
	if score < 0.0:
		return 0
	if score > 0.0:
		return 2
	return 1


# --- build ------------------------------------------------------------------------------------------------------

func _rebuild() -> void:
	# remove_child BEFORE queue_free: a queue_free'd child stays in the tree (and in get_children()) until the end of
	# the frame, so the new header/cells added below would lay out alongside the old grid for a frame.
	for c in _grid.get_children():
		_grid.remove_child(c)
		c.queue_free()
	_factions.clear()
	_ids = Factions.ids()

	var resolved: Array = []
	var resolved_ids := PackedStringArray()
	for fid in _ids:
		var f := Factions.by_id(fid)
		if f != null:
			resolved.append(f)
			resolved_ids.append(fid)
	_factions = resolved
	_ids = resolved_ids

	var n := _factions.size()
	if n == 0:
		_grid.columns = 1
		var empty := Label.new()
		empty.text = "No Faction .tres found under %s" % RELATION_DIR
		_grid.add_child(empty)
		_set_status("")
		return

	_grid.columns = n + 1

	# Header row: empty corner + a column header per faction.
	_grid.add_child(_corner_label())
	for col in range(n):
		_grid.add_child(_header_label(_factions[col]))

	# One body row per "from" faction.
	for row in range(n):
		_grid.add_child(_row_label(_factions[row]))
		for col in range(n):
			_grid.add_child(_make_cell(row, col))

	_set_status("Loaded %d faction(s)." % n)


func _corner_label() -> Control:
	var l := Label.new()
	l.text = "from \\ to"
	l.add_theme_font_size_override("font_size", 10)
	return l

func _header_label(f: Faction) -> Control:
	var l := Label.new()
	l.text = _faction_name(f)
	l.add_theme_font_size_override("font_size", 10)
	l.tooltip_text = String(f.id)
	return l

func _row_label(f: Faction) -> Control:
	var l := Label.new()
	l.text = _faction_name(f)
	l.tooltip_text = String(f.id)
	return l

func _faction_name(f: Faction) -> String:
	var dn := f.display_name.strip_edges()
	return dn if not dn.is_empty() else String(f.id)


func _make_cell(row: int, col: int) -> Control:
	var ob := OptionButton.new()
	for i in range(RELATION_LABELS.size()):
		ob.add_item(RELATION_LABELS[i], i)
	if row == col:
		# A faction's relation to itself is always friendly and not editable.
		ob.select(2)
		ob.disabled = true
		ob.tooltip_text = "Self"
		return ob
	var from_f: Faction = _factions[row]
	var to_f: Faction = _factions[col]
	ob.select(bucket_for(get_relation(from_f, to_f)))
	ob.item_selected.connect(_on_cell_selected.bind(row, col))
	return ob


func _on_cell_selected(idx: int, row: int, col: int) -> void:
	if row == col:
		return
	if row < 0 or row >= _factions.size() or col < 0 or col >= _factions.size():
		return
	if idx < 0 or idx >= RELATION_VALUES.size():
		return
	var from_f: Faction = _factions[row]
	var to_f: Faction = _factions[col]
	set_relation(from_f, to_f, RELATION_VALUES[idx])
	_save_faction(from_f)


## Persist one Faction .tres. Save failure (bad path / locked file) is REPORTED, never silently swallowed, so a
## partial write can't corrupt the resource without the designer seeing it. Saves to its source .tres path, through
## ContentSaveGuard so the PRIOR bytes are copied to <path>.tres.bak first — a cell change commits immediately (there
## is no Save button), so that .bak is the only undo a mis-click has.
func _save_faction(f: Faction) -> void:
	var path := f.resource_path
	if path.is_empty():
		_set_status("Cannot save '%s': it has no resource_path (not an on-disk .tres)." % _faction_name(f))
		return
	var err := ContentSaveGuard.save_with_backup(f, path)
	if err != OK:
		_set_status("FAILED to save %s (err %d) — change NOT persisted." % [path, err])
		return
	if Engine.is_editor_hint():
		EditorInterface.get_resource_filesystem().update_file(path)
	_set_status("Saved %s  (previous bytes -> %s)" % [path, ContentSaveGuard.backup_path(path).get_file()])


func _set_status(msg: String) -> void:
	if _status != null:
		_status.text = msg
