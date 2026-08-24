@tool
extends VBoxContainer

## QUEST EDIT dock: edit an authored Quest's headline fields, reward money/XP, the item rewards[] list, prereq +
## next-quest chaining, the auto-complete / expire-on-flag flow flags, and its ordered objectives list (each with its
## optional world marker) WITHOUT the raw inspector. A resource picker (scans resources/quests/) loads a Quest .tres
## into a set of plain widgets; an objectives ItemList + Add/Remove/Up/Down + a per-objective editor (type
## OptionButton, target_id, required_count SpinBox, description, optional CheckBox, marker CheckBox + XYZ spins)
## edits the list; a parallel rewards ItemList + item picker + count SpinBox edits rewards[]; Save writes the .tres
## back (ContentSaveGuard.save_with_backup + FileSystem.update_file) so it persists.
##
## THREE authored fields are deliberately left to the raw inspector, and not one of them is an oversight:
##   * `Quest.reward_reputation` — a Dictionary of faction id -> delta, which needs a key/value editor this thin
##     panel doesn't offer.
##   * `Quest.id` — the quest's PRIMARY KEY. A save keys its quests_active / quests_completed / quests_failed
##     sections by String(quest.id) (QuestTracker.save_into), and dialogue's start / complete / advance quest ids
##     plus another quest's `prereq_quest_id` all match it BY VALUE — so re-keying it in a passing "tidy-up" edit
##     silently orphans every one of them. QuestOps.normalize leaves it alone for exactly that reason, and
##     tests/test_devtools_quest_editor.gd pins the omission as intended rather than missing.
##   * `QuestObjective.id` — the same argument one level down: QuestTracker.start_quest seeds the progress
##     Dictionary as `progress[String(obj.id)]`, so re-keying a LIVE objective strands the player's progress under a
##     key nothing looks up again. New rows get a unique `obj_N` from QuestOps.add_objective instead. (Worth knowing
##     when a quest reads perfectly here and does nothing in game: an objective authored ELSEWHERE with a BLANK id
##     gets no progress entry at all, so it can never advance — and this tab neither shows nor repairs that.)
## Every OTHER field Quest and QuestObjective export is reachable in this tab.
##
## ROUND-TRIP RULE (the reason this file is shaped the way it is): every widget must touch THREE sites, or adding it
## DESTROYS authored data. `_load_quest` / `_load_obj_editor` / `_load_reward_row` PUSH the model into the widget
## (with no-signal setters only); `_clear_loaded` / `_load_obj_editor(null)` / `_load_reward_row(null)` RESET it to
## the RESOURCE's default (note `auto_complete` resets to TRUE — quest.gd:27 — not to the widget's `false`); and the
## write-through handlers + `_on_save` push it back. A widget that is written but never pushed persists its
## CONSTRUCTION DEFAULT over the designer's authored value, and ContentSaveGuard keeps only ONE .bak — so a clobber
## plus one more Save loses the original bytes too.
##
## ALL list mutation lives in quest_edit_ops.gd (pure + GUT-tested); this file is THIN editor glue — read a
## widget, call an op, re-render, and on Save push the in-memory edits onto the Quest and persist. Field/method
## names mirror scripts/quests/quest.gd + quest_objective.gd + scripts/items/item_stack.gd EXACTLY.
##
## Every string here is a DEVELOPER surface (editor tooling), so labels/tooltips are literals and must NEVER be
## routed through PlayerText.

const QuestOps := preload("res://addons/cybersunday_tools/dock_quest/quest_edit_ops.gd")
const ContentSaveGuard := preload("res://addons/cybersunday_tools/core/content_save_guard.gd")
## The shared picker model: "(none)"-at-0 rows, the transient row for a value the scan can't represent, the
## index -> intent decision that REFUSES to mutate when a pick can't be represented, and the OptionButton WIDTH
## GUARDS — which this tab needs badly, because its form sits in a ScrollContainer with horizontal scrolling
## DISABLED (see `_init`), so any dropdown that sizes itself to its longest item widens the whole bottom panel.
const PickerRows := preload("res://addons/cybersunday_tools/core/picker_rows.gd")
## The Loot tab's item folder scan + item label, reused rather than re-copied: both statics, no editor API, no state.
## They are the SAME two functions the Loot Edit tab's item dropdown is built from, so an Item reads identically in
## both tabs. (A third copy of "walk resources/items/, load each .tres" is exactly what PickerRows was extracted to
## stop.) Deliberately NOT reaching for anything else in that file — this is a static-function borrow, not a base class.
const LootEditor := preload("res://addons/cybersunday_tools/dock_loot/loot_editor.gd")
## The item-id registry behind the objective target_id STAMP picker. A plain `extends RefCounted` folder scanner with
## no class_name and no autoload access, which is why const-preloading it from a @tool script is safe — quest_objective.gd
## itself preloads it for the raw inspector's PROPERTY_HINT_ENUM_SUGGESTION on this very field, and dialogue_editor.gd
## does the same for its stamps. Do NOT extend this list to anything reaching ItemDb / GameSettings (the
## scripts/tools/validate_all.gd compile-order trap).
const ItemIds := preload("res://scripts/items/item_ids.gd")

const QUESTS_DIR := "res://resources/quests/"

## The QuestObjective.Type enum names, in ENUM ORDER, for the type OptionButton. The OptionButton item INDEX is
## the enum int (KILL=0 .. FLAG=5), so selecting item i sets type = i directly. Keep this in sync with
## quest_objective.gd's `enum Type { KILL, TALK, PICKUP, ENTER_AREA, USE_ITEM, FLAG }`.
const TYPE_LABELS := ["KILL", "TALK", "PICKUP", "ENTER_AREA", "USE_ITEM", "FLAG"]

## Row 0 of the target_id STAMP picker: a permanent prompt, NOT a value. Picking it stamps nothing, and every
## successful stamp re-selects it, so the button always reads as "offer me an id" instead of pretending to be the
## field's current value. Mirrors dialogue_editor.gd's STAMP_PROMPT / STAMP_WIDTH exactly — one stamp idiom, not two.
const STAMP_PROMPT := "▾"
## Minimum width of the stamp picker, in pixels. Deliberately BELOW PickerRows.PICKER_MIN_WIDTH (140): that floor
## sizes a picker that IS the field, while a stamp only ever displays STAMP_PROMPT beside a full-width LineEdit.
const STAMP_WIDTH := 44.0

## One tooltip for the whole per-objective marker group (the CheckBox and all three component spins), because the
## authoring rule is identical on each and the caveat is the part a designer needs.
## VERIFIED, and worth knowing before authoring one: a marker only renders in a level carrying a QuestMarkerSync
## node, and the ONLY scene that has one is scenes/levels/LevelTemplate.tscn — which is why
## recover_the_package.tres's `show_marker = true` draws nothing in the shipped levels today.
const MARKER_TOOLTIP := "Show a Compass chevron + Minimap dot at Marker pos while THIS objective is active (the marker is removed when the objective completes). Renders only in a level carrying a QuestMarkerSync node — today that is scenes/levels/LevelTemplate.tscn alone, so a marker on an older level is silently invisible."

var _quest: Quest = null
var _quest_path: String = ""

var _picker: OptionButton = null
var _title_edit: LineEdit = null
var _desc_edit: TextEdit = null
var _money_spin: SpinBox = null
var _xp_spin: SpinBox = null
var _auto_complete_chk: CheckBox = null
var _prereq_edit: LineEdit = null
var _next_quest_pick: OptionButton = null
var _expire_edit: LineEdit = null

var _reward_list: ItemList = null
var _reward_item_pick: OptionButton = null
var _reward_count: SpinBox = null

var _obj_list: ItemList = null
var _obj_type: OptionButton = null
var _obj_target: LineEdit = null
var _obj_target_stamp: OptionButton = null
var _obj_count: SpinBox = null
var _obj_desc: LineEdit = null
var _obj_optional: CheckBox = null
var _obj_show_marker: CheckBox = null
var _obj_marker_x: SpinBox = null
var _obj_marker_y: SpinBox = null
var _obj_marker_z: SpinBox = null

var _status: Label = null

## Scrollable form body — every field / objective / reward / Save control lives here so the ~30-row editor scrolls
## inside the short bottom panel instead of clipping its lower rows (and the Save button) off the bottom edge
## unreachably (the content_dock.gd pattern). The title stays above the scroll and the status label below, both
## always visible.
##
## HEIGHT POLICY: the bottom-panel TabContainer sizes to its TALLEST tab, so EVERY new row must land INSIDE this
## ScrollContainer. Vertical scrolling means the content height is never propagated to the tab minimum. This plugin
## has twice shipped a tab that made the editor unusable by growing past the panel — do not add a row outside it.
var _body: VBoxContainer = null

var _quest_paths: PackedStringArray = PackedStringArray()

## Parallel to the _next_quest_pick items: the res:// path each entry maps to. Index 0 is the "(none)" entry ("" =
## clear next_quest). Entries 1..N mirror _quest_paths (refilled with it on every rescan). A loaded quest whose
## next_quest lives OUTSIDE resources/quests/ (or is unsaved) gets a transient entry appended so it round-trips
## instead of silently reading as (none) — same dangling-preservation idea as dialogue_editor._select_target.
var _next_quest_paths: PackedStringArray = PackedStringArray()

# --- cached resources/items/ scan (filled on first reveal + on Reload, never at construction) --------------------
## Parallel arrays: `_item_labels[i]` is the display label for the Item .tres at `_item_paths[i]`. They feed
## PickerRows.path_rows for the reward-row item dropdown, which is a picker that IS the field (an ItemStack.item is
## a RESOURCE REFERENCE, not an id string) — so it needs the module's transient rows and its anti-clobber table.
var _item_paths: PackedStringArray = PackedStringArray()
var _item_labels: PackedStringArray = PackedStringArray()
## The Item IDS on disk -> the objective target_id STAMP picker (PICKUP / USE_ITEM only; see _fill_target_stamp).
## The id set, not the path set: target_id stores an Item.id STRING, never a reference.
var _item_ids: PackedStringArray = PackedStringArray()
## The PickerRows rows CURRENTLY in `_reward_item_pick`, kept so _on_reward_item_picked can resolve a picked index
## through PickerRows.resolve_pick (the anti-clobber table) instead of trusting the widget's own metadata.
var _reward_rows: Array = []


## PL6: lazy first-reveal latch — the resources/quests + resources/items scans run on first reveal, not at panel
## construction.
var _revealed := false


func _init() -> void:
	name = "Quest Edit"
	add_theme_constant_override("separation", 4)
	custom_minimum_size = Vector2(0, 110)  # small floor so the panel can shrink on a short display

	var title := Label.new()
	title.text = "Quest Editor"
	add_child(title)

	# The whole form (picker + headline fields + rewards + objectives + Save) lives in a ScrollContainer with the
	# inner VBox `_body`, so the ~30-row editor can NEVER overflow the short bottom panel. Without a scroll the lower
	# objective fields AND the Save button clip off the bottom edge with no way to reach them (the content_dock.gd /
	# text_editor.gd pattern). Title stays above and the status label below, both always visible.
	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED  # rows fill the width; only scroll vertically
	scroll.custom_minimum_size = Vector2(0, 90)
	add_child(scroll)
	_body = VBoxContainer.new()
	_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_body.add_theme_constant_override("separation", 4)
	scroll.add_child(_body)

	# --- picker row -------------------------------------------------------------------------------------------
	var picker_row := HBoxContainer.new()
	_picker = OptionButton.new()
	_picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_picker.item_selected.connect(_on_pick)
	picker_row.add_child(_picker)
	var reload := Button.new()
	reload.text = "Reload"
	# Reload re-scans BOTH folders (see _rescan_all), so an Item authored while the editor is open reaches the reward
	# picker without a plugin reload — not just a newly authored Quest.
	reload.tooltip_text = "Re-scan resources/items/ (the reward item dropdown + target-id stamps) AND resources/quests/, then reload the first quest."
	reload.pressed.connect(_rescan_all)
	picker_row.add_child(reload)
	_body.add_child(picker_row)

	_body.add_child(HSeparator.new())

	# --- headline fields --------------------------------------------------------------------------------------
	# Each headline widget writes through to the live Quest on change (mirroring the objective widgets below), so
	# switching quests in the picker or hitting Reload can't silently DISCARD an unsaved headline edit. Save then
	# just persists the already-applied in-memory state.
	_title_edit = _labeled_line("Title")
	_title_edit.text_changed.connect(_on_title_changed)
	_body.add_child(_field_label("Description"))
	_desc_edit = TextEdit.new()
	_desc_edit.custom_minimum_size = Vector2(0, 40)
	_desc_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_desc_edit.text_changed.connect(_on_desc_changed)
	_body.add_child(_desc_edit)

	_money_spin = _labeled_spin("Reward money", 0.0, 1000000.0, 1.0)
	_money_spin.value_changed.connect(_on_money_changed)
	_xp_spin = _labeled_spin("Reward XP", 0.0, 1000000.0, 1.0)
	_xp_spin.value_changed.connect(_on_xp_changed)

	# Quest.auto_complete DEFAULTS TRUE (quest.gd:27), which is why its absence here was a real authoring hole and not
	# a cosmetic one: with no widget, a turn-in quest (auto_complete = false, as recover_the_package.tres authors) was
	# simply not expressible in this tab. A CheckBox is a Button, so it uses toggled / disabled / set_pressed_no_signal
	# (NOT the editable / value / value_changed the SpinBoxes above use).
	_auto_complete_chk = CheckBox.new()
	_auto_complete_chk.tooltip_text = "ON: the quest finishes and pays out the moment every non-optional objective is done. OFF: it stays active until something explicitly turns it in (a dialogue choice's \"Complete quest id\", QuestTracker.complete_quest). Defaults ON — untick it for a go-back-and-report quest."
	_auto_complete_chk.toggled.connect(_on_auto_complete_changed)
	_body.add_child(_pair("Auto-complete", _auto_complete_chk))

	_prereq_edit = _labeled_line("Prereq quest id")
	_prereq_edit.tooltip_text = "A quest id that must be COMPLETED before this one can start (start_quest refuses, silently, otherwise). Blank = no prerequisite."
	_prereq_edit.text_changed.connect(_on_prereq_changed)
	# Forward chaining: next_quest is a full Quest resource (not a StringName id like prereq), so it's a picker of
	# the scanned resources/quests/ .tres, not a LineEdit. Item 0 = (none); the rest mirror _quest_paths. Writes
	# through to the live Quest on select, like every other headline widget above.
	_next_quest_pick = OptionButton.new()
	_next_quest_pick.item_selected.connect(_on_next_quest_changed)
	_body.add_child(_pair("Next quest", _next_quest_pick))

	# WR-6 fail window. Ordered LAST of the flow fields to mirror quest.gd's @export_group("Flow") on disk
	# (auto_complete, prereq_quest_id, next_quest, expire_on_flag) — the tab reads in resource order, so a designer
	# comparing the two surfaces never has to hunt.
	_expire_edit = _labeled_line("Expire on flag")
	_expire_edit.tooltip_text = "While this quest is ACTIVE, setting this GameState story flag auto-FAILS it — the \"you missed the window\" trigger (the hostage died, the bomb went off). Blank = the quest never expires. A failed quest can't be re-started."
	_expire_edit.text_changed.connect(_on_expire_changed)

	_body.add_child(HSeparator.new())

	# --- item rewards list + reorder ----------------------------------------------------------------------------
	# Quest.rewards is an Array[ItemStack] handed to the player on completion (ItemStack.seed_into, the same seeding
	# the rest of the loot pipeline uses). It sits in its own block rather than beside "Reward money" because it is a
	# LIST — a header + ItemList + button strip + two field rows can't live on the headline stack without burying the
	# flow fields. Laid out like dialogue_editor._build_choices_block; keep the header text SHORT (its minimum width
	# propagates out through the horizontally-disabled scroll).
	_body.add_child(_field_label("Item rewards"))
	_reward_list = ItemList.new()
	_reward_list.custom_minimum_size = Vector2(0, 50)
	_reward_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_reward_list.item_selected.connect(_on_reward_selected)
	_body.add_child(_reward_list)

	var reward_btns := HBoxContainer.new()
	reward_btns.add_child(_btn("Add", _on_reward_add))
	reward_btns.add_child(_btn("Remove", _on_reward_remove))
	reward_btns.add_child(_btn("Up", _on_reward_up))
	reward_btns.add_child(_btn("Down", _on_reward_down))
	_body.add_child(reward_btns)

	# ItemStack.item is a RESOURCE REFERENCE, so this is a real dropdown (there is no id string a LineEdit could
	# hold) — and therefore it goes through PickerRows, NOT loot_editor's own _select_item_in_pick. That function
	# find()s the Item in a resources/items/-only scan and falls back to select(0), so an ItemStack pointing at an
	# inline sub-resource, or at a .tres in another folder, would render "(none)" while the field is SET — and the
	# next pick would clobber it. PickerRows surfaces both cases as their own rows and refuses to write through them.
	_reward_item_pick = OptionButton.new()
	_reward_item_pick.tooltip_text = "The Item this reward row hands over. (none) clears the row's item. A row whose item lives outside resources/items/ shows as a DISABLED row — visible, but re-pick it in the raw inspector."
	_reward_item_pick.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS  # cosmetic; PickerRows.apply owns the width guards
	_reward_item_pick.item_selected.connect(_on_reward_item_picked)
	_body.add_child(_pair("Reward item", _reward_item_pick))

	_reward_count = SpinBox.new()
	# min_value 0, NOT 1: item_stack.gd:13 is @export_range(0, 9999) and documents 0 as "skip the row". A floor of 1
	# would make set_value_no_signal(0) CLAMP an authored 0 up to 1, and the next touch would persist that — merely
	# SELECTING the row would change the data (the same trap dialogue_editor's Give item count names).
	_reward_count.min_value = 0
	_reward_count.max_value = 9999
	_reward_count.step = 1  # whole items only
	_reward_count.tooltip_text = "How many of the item to hand over. A WEAPON becomes one unique instance per count; a stackable stacks to it. 0 SKIPS the row entirely (ItemStack.seed_into ignores it) — the row list says \"(skipped)\" so that reads as deliberate."
	_reward_count.value_changed.connect(_on_reward_count_changed)
	_body.add_child(_pair("Reward count", _reward_count))

	_body.add_child(HSeparator.new())

	# --- objectives list + reorder ----------------------------------------------------------------------------
	_body.add_child(_field_label("Objectives"))
	_obj_list = ItemList.new()
	_obj_list.custom_minimum_size = Vector2(0, 80)
	_obj_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_obj_list.item_selected.connect(_on_obj_selected)
	_body.add_child(_obj_list)

	var btn_row := HBoxContainer.new()
	btn_row.add_child(_btn("Add", _on_add))
	btn_row.add_child(_btn("Remove", _on_remove))
	btn_row.add_child(_btn("Up", _on_up))
	btn_row.add_child(_btn("Down", _on_down))
	_body.add_child(btn_row)

	# --- selected-objective editor ----------------------------------------------------------------------------
	_obj_type = OptionButton.new()
	for i in range(TYPE_LABELS.size()):
		_obj_type.add_item(TYPE_LABELS[i], i)
	_obj_type.item_selected.connect(_on_obj_type_changed)
	_body.add_child(_pair("Type", _obj_type))

	# target_id stays a LineEdit with a narrow STAMP picker beside it — never a closed dropdown. Same authoring rule
	# (and the same reason) as dialogue_editor's five stamps: quest_objective.gd:46-49 chose a SUGGESTION hint over a
	# real enum precisely so a designer can author an id for content that does not exist on disk yet. The FIELD is the
	# source of truth; the stamp is a typo-avoider, and it only has something to offer for the types that HAVE an
	# on-disk registry (see _fill_target_stamp).
	_obj_target = LineEdit.new()
	_obj_target.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_obj_target.text_changed.connect(_on_obj_target_changed)
	_obj_target_stamp = OptionButton.new()
	_obj_target_stamp.item_selected.connect(_on_obj_target_stamp_picked)
	_fill_target_stamp(null)  # prompt-only + disabled until an objective is selected and the registry is scanned
	var target_row := HBoxContainer.new()
	target_row.add_theme_constant_override("separation", 4)
	target_row.add_child(_obj_target)
	target_row.add_child(_obj_target_stamp)
	_body.add_child(_pair("Target id", target_row))

	_obj_count = SpinBox.new()
	_obj_count.min_value = 1
	_obj_count.max_value = 9999
	_obj_count.step = 1
	_obj_count.value_changed.connect(_on_obj_count_changed)
	_body.add_child(_pair("Required count", _obj_count))

	_obj_desc = LineEdit.new()
	_obj_desc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_obj_desc.text_changed.connect(_on_obj_desc_changed)
	_body.add_child(_pair("Obj. description", _obj_desc))

	# QuestObjective.optional — a bonus objective that doesn't gate quest completion. A CheckBox is a Button, so it
	# uses toggled / disabled / set_pressed_no_signal (NOT the editable / value / value_changed the SpinBox above uses).
	_obj_optional = CheckBox.new()
	_obj_optional.toggled.connect(_on_obj_optional_changed)
	_body.add_child(_pair("Optional", _obj_optional))

	# --- per-objective marker (QuestObjective's @export_group("Marker")) ---------------------------------------
	# NOTE the field pair lives on the OBJECTIVE, not on the Quest: each step points somewhere different. See
	# MARKER_TOOLTIP for the caveat that makes an authored marker look broken.
	_obj_show_marker = CheckBox.new()
	_obj_show_marker.tooltip_text = MARKER_TOOLTIP
	_obj_show_marker.toggled.connect(_on_obj_show_marker_changed)
	_body.add_child(_pair("Show marker", _obj_show_marker))

	# The three components get their OWN row (a 96px _pair label + three spins + anything else in one HBox inside a
	# SCROLL_MODE_DISABLED scroll compresses to unreadable with no way to scroll sideways to it). `prefix` labels each
	# spin in-field, which is cheaper in width than three more Labels.
	var marker_row := HBoxContainer.new()
	marker_row.add_theme_constant_override("separation", 4)
	_obj_marker_x = _marker_spin("X")
	_obj_marker_y = _marker_spin("Y")
	_obj_marker_z = _marker_spin("Z")
	marker_row.add_child(_obj_marker_x)
	marker_row.add_child(_obj_marker_y)
	marker_row.add_child(_obj_marker_z)
	_body.add_child(_pair("Marker pos", marker_row))

	# --- save + status ----------------------------------------------------------------------------------------
	_body.add_child(HSeparator.new())
	_body.add_child(_btn("Save Quest", _on_save))

	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.add_theme_font_size_override("font_size", 10)
	add_child(_status)

	visibility_changed.connect(_on_visibility_changed)
	_on_visibility_changed()  # lazy: scan resources/items + resources/quests on first reveal, not at panel construction (mirrors content_browser)


## Lazy first-reveal: scan the item + quest folders and load the first quest ONCE, the first time the tab is shown.
func _on_visibility_changed() -> void:
	if is_visible_in_tree() and not _revealed:
		_revealed = true
		_rescan_all()


## Both disk scans, IN THIS ORDER, and the order is a correctness fix rather than tidiness (the loot_editor.gd:132-137
## trap): _rescan_quests() loads the first quest, which selects reward row 0, which pushes that row's Item into
## _reward_item_pick. With an UNSCANNED item list the picker's rows would collapse to just "(none)", so a real reward
## would render as unset — on every plugin load, against clear_the_block.tres, which ships with one. Shared by the
## first reveal and the Reload button so the two can never drift apart.
func _rescan_all() -> void:
	_rescan_items()
	_rescan_quests()


# --- widget builders (pure UI) ---------------------------------------------------------------------------------

func _field_label(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 10)
	return l

## A "Label: control" row; returns the row so it can be added, but callers needing the control build it inline.
func _pair(label_text: String, control: Control) -> HBoxContainer:
	var row := HBoxContainer.new()
	var l := Label.new()
	l.text = label_text
	l.custom_minimum_size = Vector2(96, 0)
	row.add_child(l)
	control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(control)
	return row

func _labeled_line(label_text: String) -> LineEdit:
	var e := LineEdit.new()
	_body.add_child(_pair(label_text, e))
	return e

func _labeled_spin(label_text: String, min_v: float, max_v: float, step: float) -> SpinBox:
	var s := SpinBox.new()
	s.min_value = min_v
	s.max_value = max_v
	s.step = step
	_body.add_child(_pair(label_text, s))
	return s

## One component spin of QuestObjective.marker_position, labelled in-field by `axis` ("X"/"Y"/"Z").
##
## `step` is 0.01, NOT the 0.1 a world-position nudge would suggest, and that is a DATA-FIDELITY choice: Range snaps
## every value it is given onto its step grid measured from min_value — so with step 0.1 a hand-authored 1.25 lands
## on a neighbouring tenth, and the moment the designer nudged any ONE axis the write-through would persist that
## rounded value on ALL THREE components (they are composed together; see _on_obj_marker_changed). 0.01 keeps every
## centimetre-authored coordinate exact. allow_greater/allow_lesser keep the ±9999 bounds soft, so a far-flung level
## coordinate is still typable.
func _marker_spin(axis: String) -> SpinBox:
	var s := SpinBox.new()
	s.prefix = axis
	s.min_value = -9999.0
	s.max_value = 9999.0
	s.step = 0.01
	s.allow_greater = true
	s.allow_lesser = true
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s.tooltip_text = MARKER_TOOLTIP
	s.value_changed.connect(_on_obj_marker_changed)
	return s

func _btn(text: String, handler: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.pressed.connect(handler)
	return b


# --- picker / load ---------------------------------------------------------------------------------------------

## Scan resources/quests/ for .tres files and refill the picker. Loads the first quest if any. Safe when the
## folder doesn't exist yet (a fresh project) — the picker just shows an empty hint.
func _rescan_quests() -> void:
	_quest_paths = _scan_quest_paths()
	_refresh_next_quest_options()  # the next_quest picker lists the same scanned .tres; refill it before (re)loading a quest
	_picker.clear()
	if _quest_paths.is_empty():
		_picker.add_item("(no quests in %s)" % QUESTS_DIR)
		_picker.disabled = true
		_clear_loaded()
		_set_status("No Quest .tres found. Create one in the Content tab first.")
		return
	_picker.disabled = false
	for p in _quest_paths:
		_picker.add_item(p.get_file())
	_picker.select(0)
	_load_quest(_quest_paths[0])

## The sorted list of .tres paths under QUESTS_DIR (res:// path, files only). Empty if the dir is absent.
func _scan_quest_paths() -> PackedStringArray:
	var out := PackedStringArray()
	if not DirAccess.dir_exists_absolute(QUESTS_DIR):
		return out
	var names := DirAccess.get_files_at(QUESTS_DIR)
	for n in names:
		# Accept BOTH resource extensions (the loot_editor / item_placer_dock idiom): a Quest saved as a binary .res
		# is a real quest, and leaving it out of the picker silently hides it from the editor with no error.
		var fname := n.trim_suffix(".remap")
		var ext := fname.get_extension().to_lower()
		if ext == "tres" or ext == "res":
			out.append(QUESTS_DIR + fname)
	out.sort()
	return out


## Re-read resources/items/ into the two sources this tab offers: the parallel path/label arrays behind the reward-row
## item dropdown, and the id list behind the objective target_id stamp. Nothing here touches the loaded quest.
##
## Two passes over one small folder on purpose: `_scan_items()` yields Item RESOURCES (the reward picker assigns a
## reference and needs each one's resource_path + display label), while `ItemIds.ids()` yields the id STRINGS that
## quest_objective.gd's own inspector hint is built from — using the same registry keeps this tab's stamp and the raw
## inspector's suggestion list identical by construction rather than by coincidence.
func _rescan_items() -> void:
	_item_paths = PackedStringArray()
	_item_labels = PackedStringArray()
	for it: Item in LootEditor._scan_items():
		if it == null or it.resource_path.is_empty():
			continue  # nothing a path row could carry; the picker's transient row covers a pathless item on a LOADED stack
		_item_paths.append(it.resource_path)
		_item_labels.append(LootEditor._item_label(it))
	_item_ids = ItemIds.ids()
	_fill_target_stamp(_current_obj())  # a re-scan must reach a stamp that is already on screen


func _on_pick(idx: int) -> void:
	if idx < 0 or idx >= _quest_paths.size():
		return
	_load_quest(_quest_paths[idx])


## Model -> widgets for the whole quest. PUSH SITE 1 of the three-site rule: every widget this tab writes back must be
## pushed here, or the first keystroke/tick in any OTHER field persists this one's construction default. The spins use
## set_value_no_signal and the CheckBox set_pressed_no_signal so loading a quest doesn't fire the write-through
## handlers (LineEdit/TextEdit .text assignment doesn't emit, so those are inert already).
func _load_quest(path: String) -> void:
	var res := load(path)
	if res == null or not (res is Quest):
		_set_status("Failed to load a Quest from %s" % path)
		_clear_loaded()
		return
	_quest = res
	_quest_path = path
	_title_edit.text = _quest.title
	_desc_edit.text = _quest.description
	_money_spin.set_value_no_signal(_quest.reward_money)
	_xp_spin.set_value_no_signal(_quest.reward_xp)
	_auto_complete_chk.set_pressed_no_signal(_quest.auto_complete)
	_prereq_edit.text = String(_quest.prereq_quest_id)
	_select_next_quest()
	_expire_edit.text = String(_quest.expire_on_flag)
	_refresh_reward_list()
	_select_reward(0 if _quest.rewards.size() > 0 else -1)
	_refresh_obj_list()
	_select_obj(0 if _quest.objectives.size() > 0 else -1)
	_set_status("Loaded %s (%d objective(s), %d reward row(s))." % [path.get_file(), _quest.objectives.size(), _quest.rewards.size()])


## RESET SITE of the three-site rule: back to each field's RESOURCE default, not to the widget's.
##
## `auto_complete` resets to TRUE because that is quest.gd:27's default — a CheckBox's own default is false, and
## resetting to it would make a failed load (or an empty folder) silently display "this quest needs a manual turn-in"
## for every quest that follows. The reward row widgets are reset through _load_reward_row(null) for the sharper
## version of the same bug: leaving the previous quest's rows on screen would point the item dropdown and the count
## spin at a FOREIGN ItemStack, so the next pick would edit a resource the designer is no longer looking at.
func _clear_loaded() -> void:
	_quest = null
	_quest_path = ""
	_title_edit.text = ""
	_desc_edit.text = ""
	_money_spin.set_value_no_signal(0.0)
	_xp_spin.set_value_no_signal(0.0)
	_auto_complete_chk.set_pressed_no_signal(true)  # quest.gd:27 defaults TRUE — do NOT "tidy" this to false
	_prereq_edit.text = ""
	if _next_quest_pick != null and _next_quest_pick.item_count > 0:
		_next_quest_pick.select(0)  # back to (none); select() doesn't emit, so it can't write to a null _quest
	_expire_edit.text = ""
	if _reward_list != null:
		_reward_list.clear()
	_load_reward_row(null)
	if _obj_list != null:
		_obj_list.clear()
	_load_obj_editor(null)


# --- headline edit handlers (write back to the live Quest, like the objective handlers) ------------------------
# Guard on _quest == null so a clear/load that touches a widget is a no-op when nothing is loaded.

func _on_title_changed(text: String) -> void:
	if _quest == null:
		return
	_quest.title = text

func _on_desc_changed() -> void:  # TextEdit.text_changed has no argument
	if _quest == null:
		return
	_quest.description = _desc_edit.text

func _on_money_changed(value: float) -> void:
	if _quest == null:
		return
	_quest.reward_money = value

func _on_xp_changed(value: float) -> void:
	if _quest == null:
		return
	_quest.reward_xp = value

func _on_auto_complete_changed(pressed: bool) -> void:  # CheckBox.toggled -> bool
	if _quest == null:
		return
	_quest.auto_complete = pressed

func _on_prereq_changed(text: String) -> void:
	if _quest == null:
		return
	_quest.prereq_quest_id = StringName(text.strip_edges())

## strip_edges for the same reason as _on_prereq_changed: QuestTracker._expire_quests_on_flag compares
## `q.expire_on_flag == flag` by EXACT StringName equality, so one trailing space makes the fail window dead content
## that looks perfectly authored. QuestOps.normalize repairs values authored outside this dock; this stops us minting
## a drifted one in the first place.
func _on_expire_changed(text: String) -> void:
	if _quest == null:
		return
	_quest.expire_on_flag = StringName(text.strip_edges())

## Selecting an entry writes it through to _quest.next_quest: item 0 -> null (clear), otherwise load the mapped
## .tres. Guarded on _quest == null so a select() during clear/load is a no-op (though select() doesn't emit —
## belt and braces, matching the other headline handlers).
func _on_next_quest_changed(idx: int) -> void:
	if _quest == null or idx < 0 or idx >= _next_quest_paths.size():
		return
	var path := _next_quest_paths[idx]
	if path.is_empty():
		# Index 0 is the "(none)" entry -> clear. A later empty-path entry is the transient placeholder for a
		# next_quest that has no .tres on disk yet; re-picking it must NOT wipe the in-memory reference.
		if idx == 0:
			_quest.next_quest = null
		return
	var res := load(path)
	if res is Quest:
		_quest.next_quest = res
	else:
		_set_status("Not a Quest: %s" % path)

## Rebuild the next_quest picker items to "(none)" + every scanned quest file, mirroring _quest_paths into
## _next_quest_paths (offset by the (none) entry at index 0). Called on every rescan, before a quest is loaded.
func _refresh_next_quest_options() -> void:
	if _next_quest_pick == null:
		return
	_next_quest_pick.clear()
	_next_quest_paths = PackedStringArray()
	_next_quest_pick.add_item("(none)")
	_next_quest_paths.append("")
	for p in _quest_paths:
		_next_quest_pick.add_item(p.get_file())
		_next_quest_paths.append(p)

## Point the picker at the loaded quest's next_quest (matched by resource_path). A next_quest that lives outside
## resources/quests/ (or is unsaved) isn't in the scan, so append a transient entry carrying its path and select
## that — so it displays and round-trips instead of collapsing to (none). Uses set-then-select without a signal.
func _select_next_quest() -> void:
	if _next_quest_pick == null:
		return
	# Rebuild from the canonical scanned list FIRST so a transient (external / unsaved) entry appended for a PRIOR loaded
	# quest doesn't linger as a stale, still-selectable option in THIS quest's dropdown (clicking it would silently set the
	# wrong next_quest). Each load then adds at most ONE transient — this quest's own out-of-folder next_quest. Idempotent.
	_refresh_next_quest_options()
	var nq: Quest = _quest.next_quest if _quest != null else null
	if nq == null:
		_next_quest_pick.select(0)
		return
	var path := nq.resource_path
	var idx := -1
	for i in range(_next_quest_paths.size()):
		if _next_quest_paths[i] == path and not path.is_empty():
			idx = i
			break
	if idx < 0:
		_next_quest_pick.add_item(path.get_file() if not path.is_empty() else "(unsaved next quest)")
		_next_quest_paths.append(path)
		idx = _next_quest_pick.item_count - 1
	_next_quest_pick.select(idx)  # select() doesn't emit item_selected, so this model->widget push won't write back


# --- item rewards list -----------------------------------------------------------------------------------------

func _refresh_reward_list() -> void:
	if _reward_list == null:
		return
	_reward_list.clear()
	if _quest == null:
		return
	for i in range(_quest.rewards.size()):
		_reward_list.add_item(_reward_summary(i, _quest.rewards[i]))

## One reward row's list text. A count of 0 is CALLED OUT rather than merely shown, because item_stack.gd treats it as
## "skip this row" — an authored 0 is legitimate, but a row that silently hands over nothing has to look deliberate.
func _reward_summary(i: int, s: ItemStack) -> String:
	if s == null:
		return "%d: <null>" % i
	var label := LootEditor._item_label(s.item) if s.item != null else "(no item)"
	var skipped := "  (skipped)" if s.count <= 0 else ""
	return "%d. %s ×%d%s" % [i + 1, label, s.count, skipped]

func _selected_reward_index() -> int:
	if _reward_list == null:
		return -1
	var sel := _reward_list.get_selected_items()
	return sel[0] if sel.size() > 0 else -1

func _current_reward() -> ItemStack:
	if _quest == null:
		return null
	var i := _selected_reward_index()
	if i < 0 or i >= _quest.rewards.size():
		return null
	return _quest.rewards[i]

func _select_reward(index: int) -> void:
	if _quest == null or index < 0 or index >= _quest.rewards.size():
		_load_reward_row(null)
		return
	_reward_list.select(index)
	_load_reward_row(_quest.rewards[index])

func _on_reward_selected(index: int) -> void:
	if _quest == null or index < 0 or index >= _quest.rewards.size():
		_load_reward_row(null)
		return
	_load_reward_row(_quest.rewards[index])


## Mirror one ItemStack into the reward-row widgets (or blank + disable on null).
##
## The dropdown's rows are REBUILT from the canonical scan on every call, not just re-selected. PickerRows.path_rows
## appends at most ONE transient row — for an item the scan can't represent — so without the rebuild a transient
## appended for the PREVIOUSLY selected row would linger, still selectable, while a DIFFERENT row is shown, and
## clicking it would assign the wrong Item (the stale-transient clobber _select_next_quest documents above).
func _load_reward_row(s: ItemStack) -> void:
	var has := s != null
	if _reward_item_pick != null:
		_reward_item_pick.disabled = not has  # OptionButton is a Button -> disabled, not editable
	if _reward_count != null:
		_reward_count.editable = has
	var it: Item = s.item if has else null
	var current := it.resource_path if it != null else ""
	_reward_rows = PickerRows.path_rows(_item_paths, _item_labels, current, it != null)
	PickerRows.apply(_reward_item_pick, _reward_rows, current)
	if it != null and current.is_empty() and not _reward_rows.is_empty():
		# An INLINE / unsaved Item sub-resource has no path to match on, so apply() would leave the widget reading
		# "(none)" while a reference really IS assigned — the mis-read that invites an accidental clobber. path_rows
		# appends its "(inline / unsaved)" row LAST for exactly this case; select it by index (the module deliberately
		# never auto-selects a row whose value is ""). Display-only: resolve_pick refuses to write back through it.
		_reward_item_pick.select(_reward_rows.size() - 1)
	if _reward_count != null:
		_reward_count.set_value_no_signal(s.count if has else 1)


## Widget -> model for the reward row's Item. Every branch goes through PickerRows.resolve_pick, the anti-clobber
## table: index 0 -> clear (the one explicit, intended clear), an out-of-range index -> keep (a stale index from a
## dropdown rebuilt under a queued signal is refused, never guessed), an empty-valued row at index > 0 -> keep
## (re-picking the "(inline / unsaved)" row must NOT wipe an in-memory Item). Only a real, representable pick assigns.
func _on_reward_item_picked(idx: int) -> void:
	var s := _current_reward()
	if s == null:
		return
	var pick: Dictionary = PickerRows.resolve_pick(_reward_rows, idx)
	var action := String(pick.get("action", "keep"))
	if action == "keep":
		return
	if action == "clear":
		s.item = null
		_refresh_reward_summary_for_selected()
		_set_status("Reward row item cleared — the row grants nothing until you pick one. Save to persist.")
		return
	var path := String(pick.get("value", ""))
	var res := load(path)
	if not (res is Item):
		_set_status("Not an Item: %s — the reward row was left unchanged." % path)
		return
	s.item = res
	_refresh_reward_summary_for_selected()

func _on_reward_count_changed(value: float) -> void:
	var s := _current_reward()
	if s == null:
		return
	s.count = int(value)
	_refresh_reward_summary_for_selected()

## Update the reward row's text in place (keeps selection / focus stable while editing).
func _refresh_reward_summary_for_selected() -> void:
	var i := _selected_reward_index()
	if _quest == null or i < 0 or i >= _quest.rewards.size():
		return
	_reward_list.set_item_text(i, _reward_summary(i, _quest.rewards[i]))


# --- reward list ops (delegate to the pure ops, then re-render) ------------------------------------------------

func _on_reward_add() -> void:
	if _quest == null:
		_set_status("Load a quest first.")
		return
	if QuestOps.add_reward(_quest):
		_refresh_reward_list()
		_select_reward(_quest.rewards.size() - 1)
		_set_status("Added reward row %d — pick an item, then Save." % _quest.rewards.size())

func _on_reward_remove() -> void:
	if _quest == null:
		return
	var i := _selected_reward_index()
	if QuestOps.remove_reward(_quest, i):
		_refresh_reward_list()
		_select_reward(mini(i, _quest.rewards.size() - 1))
		_set_status("Removed reward row %d." % (i + 1))

func _on_reward_up() -> void:
	_move_reward(-1)

func _on_reward_down() -> void:
	_move_reward(1)

func _move_reward(dir: int) -> void:
	if _quest == null:
		return
	var i := _selected_reward_index()
	if QuestOps.move_reward(_quest, i, dir):
		_refresh_reward_list()
		_select_reward(i + dir)


# --- objectives list -------------------------------------------------------------------------------------------

func _refresh_obj_list() -> void:
	_obj_list.clear()
	if _quest == null:
		return
	for i in range(_quest.objectives.size()):
		var o: QuestObjective = _quest.objectives[i]
		_obj_list.add_item(_obj_summary(i, o))

func _obj_summary(i: int, o: QuestObjective) -> String:
	if o == null:
		return "%d: <null>" % i
	var type_name: String = TYPE_LABELS[o.type] if o.type >= 0 and o.type < TYPE_LABELS.size() else "?"
	var tgt := String(o.target_id)
	var suffix := " (optional)" if o.optional else ""  # parity with the quest journal's "(optional)" tag
	var marker := " ◆" if o.show_marker else ""  # at-a-glance: this step places a compass chevron / minimap dot
	return "%d. [%s] %s x%d%s%s" % [i + 1, type_name, tgt if not tgt.is_empty() else "(no target)", o.required_count, suffix, marker]


func _selected_index() -> int:
	var sel := _obj_list.get_selected_items()
	return sel[0] if sel.size() > 0 else -1

func _select_obj(index: int) -> void:
	if _quest == null or index < 0 or index >= _quest.objectives.size():
		_load_obj_editor(null)
		return
	_obj_list.select(index)
	_load_obj_editor(_quest.objectives[index])


func _on_obj_selected(index: int) -> void:
	if _quest == null or index < 0 or index >= _quest.objectives.size():
		_load_obj_editor(null)
		return
	_load_obj_editor(_quest.objectives[index])


## Mirror an objective's fields into the per-objective editor widgets (or blank + disable on null).
##
## PUSH SITE for every per-objective widget. The marker trio matters most here: three SpinBoxes each write ONE
## component of a single Vector3, so a plain `.value =` push would fire _on_obj_marker_changed three times, and each
## of those reads all three spins — the first two would compose the new component with the two STALE siblings and
## write that hybrid onto the objective. set_value_no_signal is what makes the push inert.
func _load_obj_editor(o: QuestObjective) -> void:
	var has := o != null
	_obj_type.disabled = not has
	_obj_target.editable = has
	_obj_count.editable = has
	_obj_desc.editable = has
	_obj_optional.disabled = not has  # CheckBox is a Button -> disabled, not editable
	_obj_show_marker.disabled = not has
	_obj_marker_x.editable = has
	_obj_marker_y.editable = has
	_obj_marker_z.editable = has
	_fill_target_stamp(o)  # the stamp's offer depends on o.type (and on there being an objective at all)
	if not has:
		_obj_type.select(-1)
		_obj_target.text = ""
		_obj_count.set_value_no_signal(1)
		_obj_desc.text = ""
		_obj_optional.set_pressed_no_signal(false)
		_obj_show_marker.set_pressed_no_signal(false)
		_obj_marker_x.set_value_no_signal(0.0)
		_obj_marker_y.set_value_no_signal(0.0)
		_obj_marker_z.set_value_no_signal(0.0)
		return
	_obj_type.select(o.type)
	_obj_target.text = String(o.target_id)
	_obj_count.set_value_no_signal(o.required_count)
	_obj_desc.text = o.description
	_obj_optional.set_pressed_no_signal(o.optional)
	_obj_show_marker.set_pressed_no_signal(o.show_marker)
	_obj_marker_x.set_value_no_signal(o.marker_position.x)
	_obj_marker_y.set_value_no_signal(o.marker_position.y)
	_obj_marker_z.set_value_no_signal(o.marker_position.z)


# --- objective edit handlers (write back to the live QuestObjective) -------------------------------------------

func _current_obj() -> QuestObjective:
	if _quest == null:
		return null
	var i := _selected_index()
	if i < 0 or i >= _quest.objectives.size():
		return null
	return _quest.objectives[i]

func _on_obj_type_changed(idx: int) -> void:
	var o := _current_obj()
	if o == null or idx < 0 or idx >= TYPE_LABELS.size():
		return
	o.type = idx
	_fill_target_stamp(o)  # PICKUP/USE_ITEM have an id registry to offer; the other four types don't
	_refresh_summary_for_selected()

## strip_edges here, not just in QuestOps.normalize: QuestTracker._advance_objectives_matching compares
## `obj.target_id == target` by EXACT StringName equality, so a padded id never matches any kill/pickup/talk event and
## the objective sits at 0/N forever with no error anywhere. Matches _on_prereq_changed / _on_expire_changed.
func _on_obj_target_changed(text: String) -> void:
	var o := _current_obj()
	if o == null:
		return
	o.target_id = StringName(text.strip_edges())
	_refresh_summary_for_selected()

func _on_obj_count_changed(value: float) -> void:
	var o := _current_obj()
	if o == null:
		return
	o.required_count = int(value)
	_refresh_summary_for_selected()

func _on_obj_desc_changed(text: String) -> void:
	var o := _current_obj()
	if o == null:
		return
	o.description = text

func _on_obj_optional_changed(pressed: bool) -> void:  # CheckBox.toggled -> bool
	var o := _current_obj()
	if o == null:
		return
	o.optional = pressed
	_refresh_summary_for_selected()  # live-refresh the row's "(optional)" tag

func _on_obj_show_marker_changed(pressed: bool) -> void:  # CheckBox.toggled -> bool
	var o := _current_obj()
	if o == null:
		return
	o.show_marker = pressed
	_refresh_summary_for_selected()  # live-refresh the row's "◆" tag

## The ONE writer of marker_position, wired to all THREE component spins. Vector3 is a value type — there is no
## `o.marker_position.x = v` that reaches the resource — so every edit composes the whole vector from all three
## widgets. That is also why _load_obj_editor must push with set_value_no_signal: a signalling push would have this
## handler write two hybrids of new and stale components on its way to the right answer.
func _on_obj_marker_changed(_value: float) -> void:
	var o := _current_obj()
	if o == null:
		return
	o.marker_position = Vector3(_obj_marker_x.value, _obj_marker_y.value, _obj_marker_z.value)

## Update the ItemList row text for the selected objective in place (keeps selection / focus stable while typing).
## Guarded on `_quest` the same way its reward twin (_refresh_reward_summary_for_selected) is. Today every caller has
## already resolved a non-null _current_obj(), so the guard never fires — but the two functions are a matched pair,
## and a null-safe pair is safe BY CONSTRUCTION instead of by call-site discipline that a later handler can forget.
func _refresh_summary_for_selected() -> void:
	var i := _selected_index()
	if _quest == null or i < 0 or i >= _quest.objectives.size():
		return
	_obj_list.set_item_text(i, _obj_summary(i, _quest.objectives[i]))


# --- objective target_id stamp picker --------------------------------------------------------------------------

## Refill the stamp beside the target_id field for `o`'s TYPE, because target_id means a different thing per type and
## only one of those meanings has an on-disk registry:
##   * PICKUP / USE_ITEM -> target_id IS an Item.id, and ItemIds.ids() is the registry. This is exactly what
##     quest_objective.gd:46-49 already feeds the RAW inspector's suggestion hint, so the two surfaces offer one list.
##   * KILL / TALK -> an NPC IDENTITY KEY (NpcData.id, or the NPC's display_name as the documented legacy fallback —
##     QuestTracker._advance_objectives_matching accepts either). There is no registry for it on disk today, and
##     harvesting one from scene display_names would be WRONG rather than merely incomplete: an NPC instance carrying
##     a `profile` overwrites its display_name from that profile before its identity latches, so a harvest would offer
##     ids that can never fire. Left as free text until that pass happens.
##   * ENTER_AREA (an area / group name) and FLAG (a GameState flag name) -> nothing on disk enumerates them at all.
## With nothing to offer the stamp is DISABLED rather than hidden, so the row doesn't reflow as the designer changes
## type, and its tooltip says why. The LineEdit stays fully typable in every case — that is the authoring rule.
func _fill_target_stamp(o: QuestObjective) -> void:
	if _obj_target_stamp == null:
		return
	var typed_ids := PackedStringArray()
	var tip := "This objective type has no id registry on disk — type the target by hand. KILL/TALK match an NPC identity key (NpcData.id, or its display_name as the legacy fallback); ENTER_AREA matches an area/group name; FLAG matches a GameState flag name. All are EXACT, case-sensitive compares."
	if o != null and (o.type == QuestObjective.Type.PICKUP or o.type == QuestObjective.Type.USE_ITEM):
		typed_ids = _item_ids
		tip = "Stamp an Item id from resources/items/ into the field on the left, then snap back to the prompt. The FIELD stays typable and authoritative: pick to avoid a typo, or type an id whose item you haven't authored yet."
	_obj_target_stamp.tooltip_text = tip
	# Routed through PickerRows.apply for its WIDTH GUARDS: fit_to_longest_item defaults TRUE, so a dropdown holding
	# every item id would set a huge minimum width — and this tab's form disables horizontal scrolling, so the panel
	# itself would widen to fit the longest id. STAMP_WIDTH then overrides the module's 140px floor (sized for a picker
	# that IS the field; a stamp only ever shows one glyph), so the override MUST come after apply().
	PickerRows.apply(_obj_target_stamp, _stamp_rows(typed_ids), "")  # "" -> index_of returns 0, i.e. the prompt row
	_obj_target_stamp.custom_minimum_size = Vector2(STAMP_WIDTH, 0)
	_obj_target_stamp.disabled = typed_ids.is_empty()

## The rows for the stamp: the permanent prompt at index 0, then one row per known id. NOT PickerRows.id_rows, for the
## same two reasons dialogue_editor._stamp_rows gives — row 0 reads STAMP_PROMPT rather than "(none)" (a stamp cannot
## clear a field it does not own; the LineEdit is cleared by deleting the text), and there is no "(off-disk)"
## transient (the current value is already visible in the LineEdit beside it, so echoing it back would be noise).
func _stamp_rows(ids: PackedStringArray) -> Array:
	var rows: Array = [{"label": STAMP_PROMPT, "value": ""}]
	for id in ids:
		var sid := String(id)  # keeps rows JSON-safe: JSON.stringify COERCES a StringName instead of failing
		rows.append({"label": sid, "value": sid})
	return rows

## Stamp a picked id into the target_id LineEdit. Applies the same two rules PickerRows.resolve_pick does — row 0 is
## the prompt (stamping nothing is the honest response to it) and a stale index is refused rather than guessed — kept
## inline here because a stamp has no model of its own to clear.
func _on_obj_target_stamp_picked(idx: int) -> void:
	if _obj_target_stamp == null or _obj_target == null:
		return
	# Snap back to the prompt FIRST so the button always reads as an offer, and so a second pick of the same id still
	# emits. select() does not emit item_selected, so this cannot re-enter.
	if _obj_target_stamp.item_count > 0:
		_obj_target_stamp.select(0)
	if idx <= 0 or idx >= _obj_target_stamp.item_count:
		return
	var picked := String(_obj_target_stamp.get_item_metadata(idx))
	if picked.is_empty() or _obj_target.text == picked:
		return
	_obj_target.text = picked
	_on_obj_target_changed(picked)  # `.text =` does NOT emit text_changed, so drive the same write path a keystroke takes


# --- list ops (delegate to the pure ops, then re-render) -------------------------------------------------------

func _on_add() -> void:
	if _quest == null:
		_set_status("Load a quest first.")
		return
	if QuestOps.add_objective(_quest):
		_refresh_obj_list()
		_select_obj(_quest.objectives.size() - 1)
		_set_status("Added objective %d." % _quest.objectives.size())

func _on_remove() -> void:
	if _quest == null:
		return
	var i := _selected_index()
	if QuestOps.remove_objective(_quest, i):
		_refresh_obj_list()
		_select_obj(mini(i, _quest.objectives.size() - 1))
		_set_status("Removed objective %d." % (i + 1))

func _on_up() -> void:
	_move(-1)

func _on_down() -> void:
	_move(1)

func _move(dir: int) -> void:
	if _quest == null:
		return
	var i := _selected_index()
	if QuestOps.move_objective(_quest, i, dir):
		_refresh_obj_list()
		_select_obj(i + dir)


# --- save ------------------------------------------------------------------------------------------------------

## Re-sync the HEADLINE widgets onto the Quest, repair the drift-prone ids, then write the .tres through
## ContentSaveGuard and tell the FileSystem it changed. A save failure is REPORTED, never silently swallowed.
##
## Only the headline is re-synced, and that asymmetry is deliberate. The headline widgets are always showing the
## loaded quest, so a belt-and-suspenders re-read costs nothing. The per-ROW widgets (objective + reward) are showing
## at most ONE row of a list, so re-reading them here would write that row's widgets over whatever the SELECTION now
## points at — and the marker spins would additionally persist their step-snapped display value onto a coordinate the
## designer never touched. Those all write through on change instead, which is the same guarantee without the hazard.
##
## `_next_quest_pick` is the ONE headline widget deliberately NOT re-read here, so don't "finish the job" by adding
## it: its rows can carry a TRANSIENT entry for a next_quest that lives outside resources/quests/ or has no file yet,
## and resolving the selected index back through load() on every Save would turn that display-only row into a WRITE —
## precisely the clobber the transient exists to prevent. `_on_next_quest_changed` stays its only writer (it refuses
## an empty-path row at index > 0), and `_select_next_quest` rebuilds the rows from the scan on every load.
##
## QuestOps.normalize runs BEFORE the write, not after, so the repaired values are what reaches disk; its count is
## reported because "silently fixed 2 fields" is information a designer needs. Everything is then re-pushed
## model->widget, because normalize may have just changed text the designer is looking at.
func _on_save() -> void:
	if _quest == null or _quest_path.is_empty():
		_set_status("Nothing to save — load a quest first.")
		return
	_quest.title = _title_edit.text
	_quest.description = _desc_edit.text
	_quest.reward_money = _money_spin.value
	_quest.reward_xp = _xp_spin.value
	_quest.auto_complete = _auto_complete_chk.button_pressed
	_quest.prereq_quest_id = StringName(_prereq_edit.text.strip_edges())
	_quest.expire_on_flag = StringName(_expire_edit.text.strip_edges())
	var fixed := QuestOps.normalize(_quest)
	var err := ContentSaveGuard.save_with_backup(_quest, _quest_path)  # PL5: prior bytes -> .tres.bak first, so a mis-save is recoverable
	if err != OK:
		_set_status("FAILED to save %s (err %d) — change NOT persisted." % [_quest_path, err])
		return
	if Engine.is_editor_hint():
		EditorInterface.get_resource_filesystem().update_file(_quest_path)
	# Show what was ACTUALLY written. Capture both selections FIRST: _refresh_*_list() calls ItemList.clear(), which
	# drops the selection, so reading the current row after the refresh would find nothing and blank both sub-editors
	# out from under the designer. _select_*(-1) is the honest "nothing selected" path when there was no selection.
	var obj_sel := _selected_index()
	var reward_sel := _selected_reward_index()
	_prereq_edit.text = String(_quest.prereq_quest_id)
	_expire_edit.text = String(_quest.expire_on_flag)
	_refresh_obj_list()
	_select_obj(obj_sel)
	_refresh_reward_list()
	_select_reward(reward_sel)
	_set_status("Saved %s%s" % [_quest_path, "" if fixed == 0 else " (normalized %d drifted field(s))" % fixed])


func _set_status(msg: String) -> void:
	if _status != null:
		_status.text = msg
