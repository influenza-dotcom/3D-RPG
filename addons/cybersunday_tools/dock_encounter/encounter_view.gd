@tool
extends VBoxContainer

## Encounter tab (Tune group of the CYBER SUNDAY panel; Control name "Encounter" -- tests pin it, the panel sets the
## display title): a READ-ONLY preview of what an EncounterSpawner would spawn. Select an EncounterSpawner in the
## Scene tree, press Preview Selected, and the list shows one designer-words row per wave ("Wave 1: 3 x NPC,
## scattered within 6 m, 0.5 s apart, archetype: raider, hostile on spawn"), then footer rows with the authored
## total and its Easy / Normal / Hard estimate, the placement rule, and any component every spawn arrives with. It
## spawns nothing and never writes to the scene or to disk. Counts are AUTHORED; runtime multiplies each wave by
## the difficulty enemy-count multiplier, so the footer labels the total an estimate. The summary model lives in
## encounter_preview.gd (pure, tested); this file only renders it, through the pure static row_text /
## footer_text / placement_text builders below so the wording can be pinned off-tree too.
##
## Layout, top to bottom: ONE action row (Preview Selected), the wave Tree, ONE status label. The Tree scrolls
## itself (no ScrollContainer wrap needed -- with both of its own scrollbars enabled its minimum size is zero, so a
## long row can never widen the bottom panel) and carries a small height floor so this tab can never force the
## shared bottom panel taller than the screen: a TabContainer's minimum is the CURRENT tab's minimum, and the
## editor's bottom splitter keeps the height it grew to. The footer rows live in the same Tree (root-level, after
## the waves) so the tab keeps exactly one label outside the list.
##
## Host seams (cyber_panel.gd): on_scene_changed(root) is forwarded from EditorPlugin.scene_changed (and once at
## enable) so Preview Selected greys with "Open a scene first" BEFORE a click; the editor's selection_changed
## (connected on the first in-tree reveal, editor only) greys it with "Select an EncounterSpawner in the scene
## first" until one is selected. The post-click status repeats the same sentences as a fallback. Off-tree (GUT /
## the headless probe construct this bare) every editor call stays inside a button handler, the first-reveal
## latch, or behind Engine.is_editor_hint(), so _init never touches EditorInterface.

const Preview := preload("res://addons/cybersunday_tools/dock_encounter/encounter_preview.gd")
## The difficulty presets the Easy / Hard estimate reads (the same file Settings.set_difficulty copies from). Named
## in a tooltip only -- the footer itself stays in designer words.
const DIFFICULTY_PATH := "res://resources/tuning/DifficultySettings.tres"

## One sentence per guard, shared by Preview Selected's disabled tooltip AND the post-click status, so the two can
## never drift apart. Scene first: with no scene open there is nothing to select in.
const MSG_NO_SCENE := "Open a scene first, then Preview Selected."
const MSG_NO_SPAWNER := "Select an EncounterSpawner in the scene first."
const MSG_IDLE := "Select an EncounterSpawner in the scene, then Preview Selected -- it lists every wave without spawning anything."
const PREVIEW_TIP := "Lists each wave the selected EncounterSpawner would spawn, with an Easy / Normal / Hard estimate. Read-only -- spawns nothing and never touches the scene."

const COLOR_WAVE := Color(0.7, 0.9, 0.7)
const COLOR_TOTAL := Color(0.85, 0.9, 1.0)
const COLOR_DETAIL := Color(1, 1, 1, 0.6)
const COLOR_WARN := Color(1.0, 0.82, 0.3)

var _preview_btn: Button = null
var _tree: Tree = null
var _status: Label = null

## Mirrors the host's on_scene_changed(root) so Preview Selected can grey before a click. The click handler re-reads
## the live edited-scene root (the editor is the source of truth); this flag only drives the button state.
var _scene_open := false
## Whether the editor selection currently holds an EncounterSpawner -- refreshed by the editor's selection_changed
## (editor only) and on every scene change; the second gate on Preview Selected.
var _spawner_selected := false

## Lazy first-reveal latch: the editor selection signal is wired (and the button state first synced from the live
## editor) the first time the tab is actually shown, never at panel construction -- so building the panel headless
## touches no EditorInterface.
var _revealed := false


func _init() -> void:
	name = "Encounter"
	add_theme_constant_override("separation", 4)

	# Action row: the one command, above the list so it stays put while the list fills.
	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 4)
	add_child(bar)

	_preview_btn = Button.new()
	_preview_btn.text = "Preview Selected"
	_preview_btn.tooltip_text = PREVIEW_TIP
	_preview_btn.pressed.connect(_preview)
	bar.add_child(_preview_btn)

	# The waves, one row each, plus the footer rows. Hidden root, self-scrolling, small height floor (see header).
	_tree = Tree.new()
	_tree.hide_root = true
	_tree.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_tree.custom_minimum_size = Vector2(0, 90)
	add_child(_tree)

	# What the tab just DID or REFUSED (or the next step). Clamped to two lines with the full text on its tooltip.
	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.max_lines_visible = 2
	_status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_status.modulate = Color(1, 1, 1, 0.75)
	_status.mouse_filter = Control.MOUSE_FILTER_PASS  # a Label ignores the mouse by default, which also hides its tooltip
	add_child(_status)
	_set_status(MSG_IDLE)
	_update_preview_state()  # no scene known yet -> greyed with "Open a scene first" until the host reports one

	visibility_changed.connect(_on_visibility_changed)
	_on_visibility_changed()  # no-op off-tree (not visible); in the editor the real reveal fires the signal


## Lazy first-reveal: the first time the tab is actually shown, wire the editor's selection signal (guarded: no
## EditorInterface headless) and sync both button gates from the live editor -- the designer may have selected a
## spawner before ever opening this tab. Later reveals do nothing; the signal keeps the state current.
func _on_visibility_changed() -> void:
	if is_visible_in_tree() and not _revealed:
		_revealed = true
		if Engine.is_editor_hint():
			var sel := EditorInterface.get_selection()
			if sel != null and not sel.selection_changed.is_connected(_on_selection_changed):
				sel.selection_changed.connect(_on_selection_changed)
			on_scene_changed(EditorInterface.get_edited_scene_root())  # also re-polls the selection


## Host seam (cyber_panel.on_scene_changed, forwarded from EditorPlugin.scene_changed and once at enable): grey
## Preview Selected while no scene is open, and re-poll the selection (a scene switch usually clears it). `root` may
## be null (every scene closed). is_instance_valid guards a stale root handed over mid-close -- a freed Object
## compares unequal to null in GDScript, so a bare null test is not enough. Safe off-tree: _selected_spawner returns
## null outside the editor, so a headless forward simply reports "nothing selected".
func on_scene_changed(root: Node) -> void:
	_scene_open = is_instance_valid(root)
	_spawner_selected = _selected_spawner() != null
	_update_preview_state()


## The editor selection changed (editor only -- connected on first reveal): re-derive the spawner gate. Cheap (a
## walk over the few selected nodes), so it runs even while the tab is hidden and the button is right on reveal.
func _on_selection_changed() -> void:
	_spawner_selected = _selected_spawner() != null
	_update_preview_state()


## The first EncounterSpawner in the editor selection, or null. Returns null OUTSIDE the editor rather than trusting
## every caller to guard: EditorInterface does not exist headless, and this is reached from a button handler that the
## GUT test drives off-tree to pin the refusal wording. Validity is checked BEFORE the type test: `is` on a freed
## instance hard-crashes, and the selection can still hold a node freed under it (a scene closed between the
## selection_changed signal and this read).
func _selected_spawner() -> EncounterSpawner:
	if not Engine.is_editor_hint():
		return null
	var sel := EditorInterface.get_selection()
	if sel == null:
		return null
	for n in sel.get_selected_nodes():
		if is_instance_valid(n) and n is EncounterSpawner:
			return n as EncounterSpawner
	return null


## Preview Selected's disabled state + tooltip, derived from the two gates. Scene first: with no scene open there
## is nothing to select in, so that is the more useful thing to tell the designer even when nothing is selected
## either. When both gates pass the tooltip is the plain rule-of-the-button text.
func _update_preview_state() -> void:
	if _preview_btn == null:
		return
	if not _scene_open:
		_preview_btn.disabled = true
		_preview_btn.tooltip_text = MSG_NO_SCENE
	elif not _spawner_selected:
		_preview_btn.disabled = true
		_preview_btn.tooltip_text = MSG_NO_SPAWNER
	else:
		_preview_btn.disabled = false
		_preview_btn.tooltip_text = PREVIEW_TIP


## Every status write: the label clamps to two lines, so the tooltip mirrors the whole message. `warn` tints the
## text (a refusal); a plain write restores the label's default colour.
func _set_status(msg: String, warn: bool = false) -> void:
	if _status == null:
		return
	_status.text = msg
	_status.tooltip_text = msg
	if warn:
		_status.add_theme_color_override("font_color", COLOR_WARN)
	else:
		_status.remove_theme_color_override("font_color")


## Read the selected scene node; if it's an EncounterSpawner, render its summary: one row per wave, then the
## total / placement / attached-component footer rows. Read-only -- nothing is spawned, nothing is written. Every
## early return writes its sentence to the status (the same one the disabled button shows), so a click that slips
## past a stale button state is never silent.
func _preview() -> void:
	if Engine.is_editor_hint():
		# Keep the button state honest with what this click just observed. Guarded, not because a handler can run
		# headless in the editor, but so the REFUSAL path stays drivable off-tree: the GUT test presses this with no
		# scene and pins that the status says the same sentence the greyed button's tooltip does.
		on_scene_changed(EditorInterface.get_edited_scene_root())
	_tree.clear()
	var root := _tree.create_item()
	if not _scene_open:
		_set_status(MSG_NO_SCENE)
		return
	var spawner := _selected_spawner()
	if spawner == null:
		_set_status(MSG_NO_SPAWNER)
		return
	var s := Preview.summarize(spawner)
	var rows: Array = s["rows"]
	if rows.is_empty():
		_set_status("Couldn't preview %s: no waves authored yet -- add one under Spawn Definitions in the Inspector." % spawner.name, true)
		return
	var markers := int(s["marker_count"]) > 0
	for r in rows:
		var row: Dictionary = r
		var item := _tree.create_item(root)
		item.set_text(0, row_text(row, markers))
		item.set_autowrap_mode(0, TextServer.AUTOWRAP_WORD_SMART)
		item.set_tooltip_text(0, row_tooltip(row))
		var spawns := bool(row.get("spawns", false))
		item.set_custom_color(0, COLOR_WAVE if spawns and int(row.get("count", 0)) > 0 else COLOR_WARN)
	# Make the difficulty estimate REAL: Normal is the authored total (same per-wave rounding runtime uses, so it
	# matches exactly); Easy / Hard apply the presets from the difficulty tuning file. Without that file the footer
	# says so instead of claiming an estimate it cannot make.
	var normal := Preview.scaled_total(rows, 1.0)
	var diff: DifficultySettings = load(DIFFICULTY_PATH) as DifficultySettings if ResourceLoader.exists(DIFFICULTY_PATH) else null
	var foot := _tree.create_item(root)
	if diff != null:
		var easy := Preview.scaled_total(rows, diff.easy_enemy_count_mult)
		var hard := Preview.scaled_total(rows, diff.hard_enemy_count_mult)
		foot.set_text(0, footer_text(normal, easy, hard, true))
		# The path rides the tooltip, minus the scheme prefix -- that prefix is engine spelling and belongs nowhere a
		# designer reads, tooltip included (the same trim faction_matrix / arch_view make).
		foot.set_tooltip_text(0, "Easy and Hard multiply each wave's count by the presets in %s, rounded per wave the way the game does (a wave never drops below 1). Normal is the authored count." % _difficulty_file())
	else:
		foot.set_text(0, footer_text(normal, 0, 0, false))
		foot.set_tooltip_text(0, "Expected the difficulty presets at %s." % _difficulty_file())
	foot.set_autowrap_mode(0, TextServer.AUTOWRAP_WORD_SMART)
	foot.set_custom_color(0, COLOR_TOTAL)
	var place := _tree.create_item(root)
	place.set_text(0, placement_text(int(s["marker_count"])))
	place.set_autowrap_mode(0, TextServer.AUTOWRAP_WORD_SMART)
	place.set_tooltip_text(0, "Markers come from the spawner's Spawn Points list in the Inspector; with none set, each wave scatters within its own radius.")
	place.set_custom_color(0, COLOR_DETAIL)
	var attach := int(s["attach_count"])
	if attach > 0:
		var extra := _tree.create_item(root)
		extra.set_text(0, "Every spawned NPC also gets %s." % _count(attach, "attached component", "attached components"))
		extra.set_autowrap_mode(0, TextServer.AUTOWRAP_WORD_SMART)
		extra.set_tooltip_text(0, "From the spawner's Attach Scenes list in the Inspector -- a guard duty, a patrol, and so on.")
		extra.set_custom_color(0, COLOR_DETAIL)
	_set_status("Previewed %s -- %s, %s authored. Read-only: nothing was spawned." % [
		spawner.name, _count(rows.size(), "wave", "waves"), _count(normal, "NPC", "NPCs")])


## One wave row in designer words, from a summarize() row: "Wave 1: 3 x NPC, scattered within 6 m, 0.5 s apart,
## archetype: raider, hostile on spawn". Waves are numbered from 1 (the Inspector slot is on the tooltip). A wave
## the game would skip (an empty slot, or no NPC scene picked) says "spawns nothing" instead of pretending. Pure --
## tests can pin the wording off-tree.
static func row_text(r: Dictionary, markers: bool) -> String:
	var wave := int(r.get("index", 0)) + 1
	var npc := str(r.get("npc", ""))
	var count := int(r.get("count", 0))
	if not bool(r.get("spawns", false)):
		if npc.begins_with("(empty"):
			return "Wave %d: empty slot -- spawns nothing." % wave
		# Spelled out rather than interpolating `npc`, so a row that arrived without one still reads as a sentence.
		# It says the same words encounter_preview._scene_name puts in the model -- keep the two in step.
		return "Wave %d: %d x (no NPC scene set) -- spawns nothing." % [wave, count]
	var parts := PackedStringArray()
	parts.append("Wave %d: %d x %s" % [wave, count, _short(npc)])
	parts.append("placed at the markers" if markers else "scattered within %s m" % _num(float(r.get("radius", 0.0))))
	var delay := float(r.get("delay", 0.0))
	parts.append("%s s apart" % _num(delay) if delay > 0.0 else "all at once")
	for key in ["archetype", "faction", "weapon"]:
		var v := str(r.get(key, ""))
		if v != "":
			parts.append("%s: %s" % [key, _short(v)])
	parts.append("hostile on spawn" if bool(r.get("aggro", false)) else "unaware until they spot you")
	return ", ".join(parts)


## The row's tooltip: where to edit it, and why a skipped wave is skipped.
static func row_tooltip(r: Dictionary) -> String:
	var slot := int(r.get("index", 0))
	if not bool(r.get("spawns", false)):
		if str(r.get("npc", "")).begins_with("(empty"):
			return "Slot %d under Spawn Definitions in the Inspector is empty -- give it a Spawn Definition or remove it." % slot
		return "Slot %d under Spawn Definitions in the Inspector has no NPC scene, so the game skips it." % slot
	return "Slot %d under Spawn Definitions in the Inspector. Counts are authored -- difficulty scales them at runtime." % slot


## The footer line: the authored total and, when the presets were readable, the Easy / Normal / Hard estimate.
## Pure -- tests can pin the wording off-tree.
static func footer_text(normal: int, easy: int, hard: int, has_presets: bool) -> String:
	if has_presets:
		return "Authored total %d -- difficulty scales it: Easy / Normal / Hard = %d / %d / %d (estimate)" % [normal, easy, normal, hard]
	return "Authored total %d -- difficulty scales it at runtime; no Easy / Hard estimate because the difficulty presets file wasn't found." % normal


## The placement line: markers in order when the spawner lists any, else the per-wave scatter. Pure.
static func placement_text(marker_count: int) -> String:
	if marker_count > 0:
		return "Placement: at the spawner's %s, in order." % _count(marker_count, "marker", "markers")
	return "Placement: scattered around the spawner, each wave within its own radius."


## A file name from summarize() ("NPC.tscn", "raider.tres") shown without its extension; a bracketed placeholder
## such as "(unsaved scene)" has no extension and passes through unchanged.
static func _short(file_name: String) -> String:
	return file_name.get_basename()


## A number for prose: whole values print bare ("6"), others with up to two decimals and no trailing zeros ("0.5").
## The trailing "." is stripped too: a value smaller than the two decimals shown (a 0.001 s stagger) rounds to
## "0.00", and rstrip("0") alone would leave the bare "0." -- "0. s apart" instead of "0 s apart".
static func _num(v: float) -> String:
	if is_equal_approx(v, roundf(v)):
		return str(roundi(v))
	return ("%.2f" % v).rstrip("0").rstrip(".")


## "1 wave" / "3 waves" for a status line -- designer words, so a real plural rather than a bare "(s)".
static func _count(n: int, one: String, many: String) -> String:
	return "%d %s" % [n, one if n == 1 else many]


## The difficulty tuning file as a designer reads it: the project path without the "res://" scheme prefix. Derived
## from DIFFICULTY_PATH so the tooltip can never name a file this tab does not actually load.
static func _difficulty_file() -> String:
	return DIFFICULTY_PATH.trim_prefix("res://")
