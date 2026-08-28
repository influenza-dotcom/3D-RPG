@tool
extends VBoxContainer

## "Dialogue Edit" bottom-panel tab: author a branching DialogueResource (.tres) WITHOUT the raw inspector.
## Pick a conversation from resources/dialogue/, edit its lines top-to-bottom (the order IS the addressing --
## choices jump to a line by INDEX), edit each line's text and its branch choices (label + target-line & fail-target
## OptionButtons + the FULL gate set [stat / flag / faction+reputation / perk / item / quest-state] + the FULL
## consequence set [set_flag, start/complete/advance quest, give item+count, give money, reward reputation, aggro
## speaker]), reorder/add/remove lines and choices, then Save.
##
## EVERY field DialogueManager._apply_choice_effects actually applies is authorable HERE -- the raw inspector is no
## longer needed to make a conversation hand out a quest, an item, money or a grudge. Two authoring rules hold that up:
##   * an id field is NEVER a closed dropdown. The FIVE id fields this tab caches a registry for (Req stat, Req faction
##     id, Req item id, Give item id, Reward faction id) are a LineEdit **plus** a narrow STAMP picker; the picker writes
##     a known id INTO the field and snaps back to its prompt row, so you can still type an id for content that does not
##     exist on disk yet -- dialogue_choice.gd:91-95 chose PROPERTY_HINT_ENUM_SUGGESTION for exactly that reason ("blanks
##     stay valid and custom names are still typable"). The LineEdit is the source of truth; the picker is a typo-avoider.
##     Fields with no registry cached here (Req/Set flag, Req quest id, Complete/Advance quest id, Advance objective id,
##     Req perk id) are BARE LineEdits -- same authoring rule, just nothing to offer. Do not read the stamps as a
##     promise that every id field has one.
##   * `start_quest_on_choice` is the ONE real dropdown, because it is a Quest RESOURCE REFERENCE and not an id
##     string. It is owned by _on_start_quest_picked and is deliberately NOT written by _write_choice (see the
##     invariant comment there) -- otherwise a keystroke in any other field could re-resolve or blank it.
##
## THIN GLUE by design: all mutation is in the sibling PURE static ops (dialogue_edit_ops.gd) so the logic is
## GUT-tested without any editor API; this file is just widgets + a folder scan + a wrapped ResourceSaver.save
## (mirroring faction_matrix.gd). NO graph-drag -- plain ItemList / LineEdit / OptionButton / SpinBox + buttons.
## The read-only companion (panel_graph/dialogue_graph.gd) visualizes the same .tres; this is the editor for it.
##
## Field/method names verified against scripts/dialogue/{dialogue_resource,dialogue_line,dialogue_choice}.gd.
## A DialogueLine has NO speaker/voice field -- the speaker's name is supplied by the talking character at
## runtime (DialogueManager), so this editor deliberately does not offer one (it would be dead UI).

const Ops := preload("res://addons/cybersunday_tools/dock_dialogue/dialogue_edit_ops.gd")
## The CONSEQUENCES pure ops (quest picker rows / start-quest warnings / the choice-row tag suffix). Second ops
## module rather than more functions on `Ops`: dialogue_edit_ops.gd owns list MUTATION (add/remove/move), this owns
## the consequence READS. Preloaded by path, same as its sibling -- neither carries a class_name.
const Ops2 := preload("res://addons/cybersunday_tools/dock_dialogue/choice_consequence_ops.gd")
const ContentSaveGuard := preload("res://addons/cybersunday_tools/core/content_save_guard.gd")
## The shared picker model: "(none)"-at-0 rows, the transient row for an unrepresentable value, the index -> intent
## decision that REFUSES to mutate when a pick can't be represented, and the OptionButton width guards (which this
## tab needs badly -- its right column is a ScrollContainer with horizontal scrolling DISABLED, so any dropdown that
## sizes itself to its longest item widens the whole bottom panel).
const PickerRows := preload("res://addons/cybersunday_tools/core/picker_rows.gd")
## TWO of the three id registries feeding the STAMP pickers. Both are plain `extends RefCounted` folder scanners with NO
## class_name and NO autoload access, which is why const-preloading them from a @tool script is safe
## (dialogue_choice.gd:15-19 does the same for the raw inspector's suggestion hints). Do NOT extend this list to anything
## that reaches ItemDb / GameSettings: an autoload-touching preload in an addon hits the
## scripts/tools/validate_all.gd:31-39 compile-order trap.
## The THIRD source, the stat names, is NOT preloaded: CharacterStats is a global `class_name` (and a compile-time const
## list, not a folder scan), so _rescan_registries calls CharacterStats.stat_names() directly -- exactly as
## dialogue_choice.gd:99 does. It is already in this file's compile chain via DialogueChoice, so that costs nothing new.
const ItemIds := preload("res://scripts/items/item_ids.gd")
const Factions := preload("res://scripts/faction/factions.gd")

## Where conversations live -- scanned to fill the picker. Matches dialogue_graph.gd's DIALOGUE_DIR exactly.
const DIALOGUE_DIR := "res://resources/dialogue"

## Where quests live -- scanned (and load()ed, to read each `id`) to fill the Start quest dropdown. Trailing slash is
## harmless: Ops2.quest_rows goes through InspectorCalc.resource_paths_in, which path_join()s.
const QUESTS_DIR := "res://resources/quests/"

## Row 0 of every STAMP picker: a permanent prompt, NOT a value. Picking it stamps nothing (see _on_stamp_picked),
## and every successful stamp re-selects it, so the button always reads as "offer me an id" instead of pretending to
## be the field's current value. A LOCAL const on purpose -- a glyph is not player prose and must never reach
## PlayerText (every string in this file is a DEVELOPER surface).
const STAMP_PROMPT := "▾"

## Minimum width of a stamp picker, in pixels. Deliberately BELOW PickerRows.PICKER_MIN_WIDTH (140): that floor sizes
## a picker that IS the field, while a stamp only ever displays STAMP_PROMPT and sits beside a full-width LineEdit.
const STAMP_WIDTH := 44.0

## One tooltip for all five stamp pickers -- the authoring rule is identical on each.
const STAMP_TOOLTIP := "Stamp a known id into the field on the left, then snap back to the prompt. The FIELD stays typable and authoritative: pick to avoid a typo, or type an id whose content you have not authored yet (blank = no gate / no effect)."

## Target-OptionButton sentinel ids (kept distinct from any real line index, which is >= 0). These mirror the
## DialogueLine constants without a class_name dependency in this @tool file's const space.
const TARGET_CONTINUE := -2  # DialogueLine.CONTINUE: carry on to the NEXT line (the choice default)
const TARGET_END := -1       # DialogueLine.END: finish the conversation

var _picker: OptionButton = null
var _status: Label = null
var _line_list: ItemList = null
var _line_text: TextEdit = null
var _line_reveals_name: CheckBox = null
var _choice_list: ItemList = null
var _choice_box: VBoxContainer = null

# choice field widgets
var _c_text: LineEdit = null
var _c_target: OptionButton = null
var _c_target_on_fail: OptionButton = null
var _c_set_flag: LineEdit = null
var _c_set_flag_value: CheckBox = null
var _c_req_flag: LineEdit = null
var _c_req_flag_value: LineEdit = null
var _c_req_stat: LineEdit = null
var _c_req_value: SpinBox = null
# WR-1/WR-3 gate widgets — the same gate set panel_graph/graph_data.gd:_choice_has_gate enumerates.
var _c_req_faction: LineEdit = null
var _c_req_reputation: SpinBox = null
var _c_req_perk: LineEdit = null
var _c_req_item: LineEdit = null
var _c_req_item_count: SpinBox = null
var _c_req_quest: LineEdit = null
var _c_req_quest_state: OptionButton = null
var _c_complete_quest: LineEdit = null
var _c_advance_quest: LineEdit = null
var _c_advance_objective: LineEdit = null
# The remaining @export_group("Consequences") fields (dialogue_choice.gd:66-89) -- the seven
# DialogueManager._apply_choice_effects really applies. `_c_start_quest` is a resource-reference dropdown; every id
# field beside it is a LineEdit + `*_stamp` OptionButton pair (see the header's authoring rules).
var _c_start_quest: OptionButton = null
var _c_give_item: LineEdit = null
var _c_give_count: SpinBox = null
var _c_give_money: SpinBox = null
var _c_reward_faction: LineEdit = null
var _c_reward_rep: SpinBox = null
var _c_aggro: CheckBox = null

# Stamp pickers. They hold NO state the model needs -- each one writes into the LineEdit above and re-selects its
# prompt row -- but they are kept as members so a Refresh can refill them from a re-scanned registry.
var _c_req_stat_stamp: OptionButton = null
var _c_req_faction_stamp: OptionButton = null
var _c_req_item_stamp: OptionButton = null
var _c_give_item_stamp: OptionButton = null
var _c_reward_faction_stamp: OptionButton = null

## Parallel to _picker items: the res:// path for each entry.
var _paths: Array[String] = []
## The loaded conversation being edited (null until a pick loads one).
var _res: DialogueResource = null
## The res:// path _res was loaded FROM. Save targets this, not the (possibly re-sorted) picker index.
var _loaded_path: String = ""
## True while we are pushing model -> widgets, to suppress the widgets' change signals writing back.
var _syncing := false

# --- cached id/registry scans (filled on first reveal + on Refresh, never at construction) ----------------------
## Item ids on disk -> the "Req item id" / "Give item id" stamps.
var _item_ids := PackedStringArray()
## Faction ids on disk -> the "Req faction id" / "Reward faction id" stamps.
var _faction_ids := PackedStringArray()
## CharacterStats attribute names -> the "Req stat" stamp. A closed const list, not a folder scan, but it is stamped
## through the same path so there is ONE pattern for every id field instead of two.
var _stat_names := PackedStringArray()
## Parallel scan of resources/quests/ for the Start quest dropdown: `_quest_labels[i]` is the display label
## ("<quest.id>  (<filename>)") for `_quest_paths[i]`. Labelled by ID because the rows just below this dropdown
## ("Complete quest id" / "Advance quest id") key on Quest.id, and recover_the_package.tres carries id
## &"recover_package" -- a filename label there would teach the wrong key.
var _quest_paths := PackedStringArray()
var _quest_labels := PackedStringArray()
## The PickerRows rows CURRENTLY in `_c_start_quest`, kept so _on_start_quest_picked can resolve a picked index
## through PickerRows.resolve_pick (the anti-clobber table) instead of trusting the widget's own metadata.
var _quest_rows: Array = []


## PL6: lazy first-reveal latch — every disk scan this tab owns (the dialogue folder, and since the Consequences block
## the item / faction / quest registries above) runs on first reveal, not at panel construction.
var _revealed := false


func _init() -> void:
	name = "Dialogue Edit"
	add_theme_constant_override("separation", 4)
	_build_top_bar()
	add_child(HSeparator.new())
	_build_body()
	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.add_theme_font_size_override("font_size", 10)
	add_child(_status)
	_set_status("Pick a conversation to edit.")
	visibility_changed.connect(_on_visibility_changed)
	_on_visibility_changed()  # lazy: scan the dialogue folder on first reveal, not at panel construction (mirrors content_browser)


## Lazy first-reveal: scan the dialogue folder + fill the picker ONCE, the first time the tab is shown (not at construction).
## The id/quest registry scans go FIRST so the reveal is a single disk pass and a first click on a choice already sees
## filled stamp lists + a filled Start quest dropdown. (Unlike loot_editor, ordering is not a correctness fix here:
## _refresh_picker's cascade -> _on_pick -> _select_line -> _on_line_selected ends at _rebuild_choice_list, which
## clears the choice list and HIDES _choice_box, so no choice-field widget is touched during load at all.)
func _on_visibility_changed() -> void:
	if is_visible_in_tree() and not _revealed:
		_revealed = true
		_rescan_registries()
		_refresh_picker()


## Re-read every id source the stamp pickers and the Start quest dropdown offer, and push it into the widgets.
## Called on first reveal and from Refresh, so a quest / item / faction authored while the editor is open shows up
## without a plugin reload. Nothing here mutates the loaded conversation.
func _rescan_registries() -> void:
	_item_ids = ItemIds.ids()
	_faction_ids = Factions.ids()
	_stat_names = CharacterStats.stat_names()
	var rows: Dictionary = Ops2.quest_rows(QUESTS_DIR)
	_quest_paths = rows.get("paths", PackedStringArray())
	_quest_labels = rows.get("labels", PackedStringArray())
	_fill_stamp(_c_req_stat_stamp, _stat_names)
	_fill_stamp(_c_req_faction_stamp, _faction_ids)
	_fill_stamp(_c_req_item_stamp, _item_ids)
	_fill_stamp(_c_give_item_stamp, _item_ids)
	_fill_stamp(_c_reward_faction_stamp, _faction_ids)
	# Re-point the Start quest dropdown at whatever is selected right now (null when nothing is -- rows collapse to
	# "(none)"). Without this a Refresh would leave the PREVIOUS scan's rows in a dropdown the designer can still
	# click, which is the stale-transient-row clobber _sync_start_quest exists to prevent.
	_sync_start_quest(_selected_choice())


# --- top bar: picker + refresh + save --------------------------------------------------------------------------

func _build_top_bar() -> void:
	var bar := HBoxContainer.new()
	_picker = OptionButton.new()
	_picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_picker.tooltip_text = "A DialogueResource .tres to edit. Refresh re-scans %s." % DIALOGUE_DIR
	_picker.item_selected.connect(_on_pick)
	bar.add_child(_picker)

	var refresh := Button.new()
	refresh.text = "Refresh"
	refresh.tooltip_text = "Re-scan the dialogue folder AND the id lists the stamp pickers offer (items / factions / stats / quests)."
	refresh.pressed.connect(_on_refresh_pressed)
	bar.add_child(refresh)

	var save := Button.new()
	save.text = "Save"
	save.tooltip_text = "Write the conversation back to its .tres."
	save.pressed.connect(_save)
	bar.add_child(save)
	add_child(bar)


# --- body: lines column | (line text + choices) column ---------------------------------------------------------

func _build_body() -> void:
	var split := HBoxContainer.new()
	split.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	# Small floor so the bottom panel stays compact on a short display (see CLAUDE.md panel policy).
	split.custom_minimum_size = Vector2(0, 110)
	add_child(split)

	# Left: the lines list + its add/remove/up/down.
	var left := VBoxContainer.new()
	left.custom_minimum_size = Vector2(150, 0)
	var lhdr := Label.new()
	lhdr.text = "Lines (order = index)"
	lhdr.add_theme_font_size_override("font_size", 10)
	left.add_child(lhdr)
	_line_list = ItemList.new()
	_line_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_line_list.custom_minimum_size = Vector2(150, 80)
	_line_list.item_selected.connect(_on_line_selected)
	left.add_child(_line_list)
	left.add_child(_row_buttons(_add_line, _remove_line, _line_up, _line_down))
	split.add_child(left)

	# Right: selected line's text, then its choices sub-editor. The choice editor stacks 28 rows (26 fields plus the two
	# group headers, ~700px), which far exceeds this short bottom panel — so the whole right column lives in a
	# ScrollContainer. Without it the lower
	# choice fields (Fail target, the whole Consequences group) clip off the bottom edge with no way to reach them
	# (the content_dock.gd / scene_placer.gd pattern). The left lines list keeps the split's full height.
	# HEIGHT POLICY: the bottom-panel TabContainer sizes to its TALLEST tab, so EVERY new choice row must land inside
	# this ScrollContainer. Vertical scrolling means the content height is never propagated to the tab minimum; the
	# head bar and the status label stay outside it deliberately. (This plugin has twice shipped a tab that made the
	# editor unusable by growing past the panel — see dock_content/content_dock.gd.)
	var right_scroll := ScrollContainer.new()
	right_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED  # fields fill the width; only scroll vertically
	split.add_child(right_scroll)
	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right_scroll.add_child(right)
	var thdr := Label.new()
	thdr.text = "Line text"
	thdr.add_theme_font_size_override("font_size", 10)
	right.add_child(thdr)
	_line_text = TextEdit.new()
	_line_text.custom_minimum_size = Vector2(0, 44)
	_line_text.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	_line_text.text_changed.connect(_on_line_text_changed)
	right.add_child(_line_text)

	# LEGACY knob: "Stranger" now ends the moment the player talks to someone at all (DialogueManager.start ->
	# GameState.reveal_name), so a character speaker is already named before line 1 paints. Left in place for
	# authored .tres compatibility — see DialogueLine.reveals_name.
	_line_reveals_name = CheckBox.new()
	_line_reveals_name.text = "Reveals speaker's name (legacy — talking already reveals it)"
	_line_reveals_name.tooltip_text = "Legacy: talking to someone at all already reveals their name, so a character speaker is never a \"Stranger\" by the time any line plays. Ticking this still calls reveal_name; it just has nothing left to unlock. No-op on an inanimate speaker."
	_line_reveals_name.toggled.connect(_on_line_reveals_name_toggled)
	right.add_child(_line_reveals_name)

	right.add_child(_build_choices_block())


func _build_choices_block() -> Control:
	var box := VBoxContainer.new()
	box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var hdr := Label.new()
	hdr.text = "Choices (branch options)"
	hdr.add_theme_font_size_override("font_size", 10)
	box.add_child(hdr)

	_choice_list = ItemList.new()
	_choice_list.custom_minimum_size = Vector2(0, 50)
	_choice_list.item_selected.connect(_on_choice_selected)
	box.add_child(_choice_list)
	box.add_child(_row_buttons(_add_choice, _remove_choice, _choice_up, _choice_down))

	# The per-choice field editors, hidden until a choice is selected. 28 direct children in THREE groups, because
	# once the stack is long enough to scroll the headers have to actually mean something:
	#   1. identity      -- Label + Target
	#   2. gates         -- every "Req *" field, ending on Fail target (where a FAILED gate goes belongs with the gates)
	#   3. consequences  -- everything DialogueManager._apply_choice_effects applies
	# `Set flag` / `value = true` sit in group 3 even though they shipped years before the rest of it: they ARE
	# consequences, and leaving them where they used to be (above the Requirements header) stranded two consequences in
	# the wrong section. That move is WIDGET-ONLY -- _write_choice reads them by member and _on_choice_selected pushes
	# them by member, so no data, signal or handler changed with it.
	_choice_box = VBoxContainer.new()
	_choice_box.visible = false

	# --- 1. identity ------------------------------------------------------------------------------------------
	_c_text = _add_field(_choice_box, "Label", LineEdit.new())
	_c_text.text_changed.connect(func(_t): _write_choice())

	_c_target = OptionButton.new()
	_c_target.tooltip_text = "Where picking this jumps. Continue = next line; End = finish; or a specific line."
	_c_target.item_selected.connect(func(_i): _write_choice())
	_labelled(_choice_box, "Target", _c_target)

	# --- 2. requirements (gates) ------------------------------------------------------------------------------
	_choice_box.add_child(_section("Requirements (gates)"))

	_c_req_flag = _add_field(_choice_box, "Req flag", LineEdit.new())
	_c_req_flag.tooltip_text = "Choice is locked unless this GameState flag matches Req flag value (blank = no gate)."
	_c_req_flag.text_changed.connect(func(_t): _write_choice())
	_c_req_flag_value = _add_field(_choice_box, "Req flag value", LineEdit.new())
	_c_req_flag_value.text_changed.connect(func(_t): _write_choice())

	_c_req_stat = LineEdit.new()
	_c_req_stat.tooltip_text = "Skill check: locked unless the player's stat >= Req value (blank = no check)."
	_c_req_stat.text_changed.connect(func(_t): _write_choice())
	_c_req_stat_stamp = _stamped(_choice_box, "Req stat", _c_req_stat)
	_c_req_value = SpinBox.new()
	_c_req_value.min_value = 0
	_c_req_value.max_value = 999
	_c_req_value.value_changed.connect(func(_v): _write_choice())
	_labelled(_choice_box, "Req value", _c_req_value)

	# The remaining WR-1/WR-3 gates (faction / perk / item / quest) the raw inspector groups under the ungrouped
	# gate exports. Kept contiguous with the flag/stat gates above; the write consequences stay below.
	_c_req_faction = LineEdit.new()
	_c_req_faction.tooltip_text = "Reputation gate: locked unless the player's standing with this faction id is >= Req reputation (blank = no gate)."
	_c_req_faction.text_changed.connect(func(_t): _write_choice())
	_c_req_faction_stamp = _stamped(_choice_box, "Req faction id", _c_req_faction)
	_c_req_reputation = SpinBox.new()
	_c_req_reputation.min_value = -9999
	_c_req_reputation.max_value = 9999
	_c_req_reputation.step = 0.01  # reputation is a float standing, so allow fractional / negative thresholds
	_c_req_reputation.value_changed.connect(func(_v): _write_choice())
	_labelled(_choice_box, "Req reputation", _c_req_reputation)

	# NO stamp on Req perk id. Several fields here have no stamp (Req/Set flag, Req quest id, the Complete/Advance ids),
	# but this is the only one where a registry EXISTS and is still not offered: `Perks.ids()` was added in the same pass
	# as this block, so the RAW inspector finally suggests perk ids (dialogue_choice.gd:106-110). Wiring a stamp is the
	# same three lines as Req item id below -- const-preload perks.gd, cache the ids in _rescan_registries, call _stamped.
	# Left off deliberately, so the shipped tab and the AUTHORING_GUIDE's field list stay in step; add it WITH that edit.
	_c_req_perk = _add_field(_choice_box, "Req perk id", LineEdit.new())
	_c_req_perk.tooltip_text = "Perk gate: locked unless the player has LEARNED this perk id (blank = no gate). Ids come from resources/perks/ — the raw inspector suggests them."
	_c_req_perk.text_changed.connect(func(_t): _write_choice())

	_c_req_item = LineEdit.new()
	_c_req_item.tooltip_text = "Item gate: locked unless the player CARRIES >= Req item count of this item id (a check, not consumed). Blank = no gate."
	_c_req_item.text_changed.connect(func(_t): _write_choice())
	_c_req_item_stamp = _stamped(_choice_box, "Req item id", _c_req_item)
	_c_req_item_count = SpinBox.new()
	_c_req_item_count.min_value = 0
	_c_req_item_count.max_value = 999
	_c_req_item_count.value_changed.connect(func(_v): _write_choice())
	_labelled(_choice_box, "Req item count", _c_req_item_count)

	_c_req_quest = _add_field(_choice_box, "Req quest id", LineEdit.new())
	_c_req_quest.tooltip_text = "Quest gate: locked unless quest id is in Req quest state (blank = no gate)."
	_c_req_quest.text_changed.connect(func(_t): _write_choice())
	_c_req_quest_state = OptionButton.new()
	_c_req_quest_state.tooltip_text = "Which tracked state the quest gate checks: Any (merely known) / Active / Completed / Failed."
	# QuestGate enum (ANY, ACTIVE, COMPLETED, FAILED): item ids ARE the enum values, so read/write map by id, not order.
	_c_req_quest_state.add_item("Any (known)", DialogueChoice.QuestGate.ANY)
	_c_req_quest_state.add_item("Active", DialogueChoice.QuestGate.ACTIVE)
	_c_req_quest_state.add_item("Completed", DialogueChoice.QuestGate.COMPLETED)
	_c_req_quest_state.add_item("Failed", DialogueChoice.QuestGate.FAILED)
	_c_req_quest_state.item_selected.connect(func(_i): _write_choice())
	_labelled(_choice_box, "Req quest state", _c_req_quest_state)

	# A gated choice stays SELECTABLE (FNV-style): a FAILED check branches here. Mirrors `target` exactly
	# (Continue / End sentinels + one entry per line index). Ignored at runtime when the choice has no gate.
	_c_target_on_fail = OptionButton.new()
	_c_target_on_fail.tooltip_text = "Where a FAILED gate check leads. End = finish; Continue = next line; or a specific line. Ignored when the choice has no gate."
	_c_target_on_fail.item_selected.connect(func(_i): _write_choice())
	_labelled(_choice_box, "Fail target", _c_target_on_fail)

	# --- 3. consequences (on pick) ----------------------------------------------------------------------------
	_choice_box.add_child(_section("Consequences (on pick)"))

	_c_set_flag = _add_field(_choice_box, "Set flag", LineEdit.new())
	_c_set_flag.tooltip_text = "GameState flag set when picked (blank = none)."
	_c_set_flag.text_changed.connect(func(_t): _write_choice())
	_c_set_flag_value = CheckBox.new()
	_c_set_flag_value.text = "value = true"
	_c_set_flag_value.toggled.connect(func(_b): _write_choice())
	_choice_box.add_child(_c_set_flag_value)

	# The ONE true dropdown in this block: `start_quest_on_choice` is a Quest RESOURCE REFERENCE, so there is no id
	# string a LineEdit could hold. It is written by _on_start_quest_picked ALONE (never by _write_choice), and its
	# rows are rebuilt from the canonical scan on every choice selection -- see _sync_start_quest for why both of
	# those are load-bearing rather than tidiness.
	_c_start_quest = OptionButton.new()
	_c_start_quest.tooltip_text = "Quest STARTED when this choice is picked (QuestTracker.start_quest). Rows read \"<quest id>  (<filename>)\" — the id is the key Complete/Advance quest id use. (none) clears the reference. Picking one reports whether that quest can actually start."
	# Cosmetic (PickerRows leaves it to the caller): a quest label is long, and clip_text alone is a hard cut.
	_c_start_quest.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_c_start_quest.item_selected.connect(_on_start_quest_picked)
	_labelled(_choice_box, "Start quest", _c_start_quest)
	_sync_start_quest(null)  # rows = just "(none)" until the first reveal scans resources/quests/

	_c_complete_quest = _add_field(_choice_box, "Complete quest id", LineEdit.new())
	_c_complete_quest.tooltip_text = "Quest id completed (turned in) when picked (blank = none)."
	_c_complete_quest.text_changed.connect(func(_t): _write_choice())
	_c_advance_quest = _add_field(_choice_box, "Advance quest id", LineEdit.new())
	_c_advance_quest.text_changed.connect(func(_t): _write_choice())
	_c_advance_objective = _add_field(_choice_box, "Advance objective id", LineEdit.new())
	_c_advance_objective.tooltip_text = "Advance objective by one (needs BOTH Advance quest id + objective id)."
	_c_advance_objective.text_changed.connect(func(_t): _write_choice())

	_c_give_item = LineEdit.new()
	_c_give_item.tooltip_text = "Item id GIVEN to the player when picked — Give item count of it (blank = none)."
	_c_give_item.text_changed.connect(func(_t): _write_choice())
	_c_give_item_stamp = _stamped(_choice_box, "Give item id", _c_give_item)
	_c_give_count = SpinBox.new()
	_c_give_count.min_value = 0
	_c_give_count.max_value = 999
	_c_give_count.step = 1  # whole items only
	# The floor stays 0 rather than 1 ON PURPOSE: a min of 1 would make set_value_no_signal(0) CLAMP an authored 0 up to
	# 1, and the next _write_choice() would persist that -- merely selecting the choice would change the data. So 0 is
	# reachable, which makes it a trap worth naming: dialogue_manager.gd:359 requires `give_item_count > 0`, so a set
	# Give item id with a count of 0 hands over NOTHING, silently, while the choice row still shows its [item] tag.
	_c_give_count.tooltip_text = "How many of Give item id to hand over. Only matters when Give item id is set. 0 gives NOTHING (the runtime requires at least 1) -- use a blank Give item id to mean \"no item\"."
	_c_give_count.value_changed.connect(func(_v): _write_choice())
	_labelled(_choice_box, "Give item count", _c_give_count)

	_c_give_money = SpinBox.new()
	_c_give_money.min_value = -1000000
	_c_give_money.max_value = 1000000
	# step 0.01 is NOT cosmetic: money is a float, and a SpinBox SNAPS every value it is given onto its step grid --
	# set_value_no_signal(12.50) on a step-1 spin lands on 13 (Range rounds to the nearest step from min_value), which the
	# next _write_choice() would then persist. Merely SELECTING a choice would round an authored fee away.
	_c_give_money.step = 0.01
	_c_give_money.tooltip_text = "Zorkmids added to the player's wallet when picked. NEGATIVE = a fee the player pays. 0 = none."
	_c_give_money.value_changed.connect(func(_v): _write_choice())
	_labelled(_choice_box, "Give money", _c_give_money)

	_c_reward_faction = LineEdit.new()
	_c_reward_faction.tooltip_text = "Faction whose standing changes when picked. Needs a NON-ZERO Reward reputation to do anything at runtime."
	_c_reward_faction.text_changed.connect(func(_t): _write_choice())
	_c_reward_faction_stamp = _stamped(_choice_box, "Reward faction id", _c_reward_faction)
	_c_reward_rep = SpinBox.new()
	_c_reward_rep.min_value = -9999
	_c_reward_rep.max_value = 9999
	_c_reward_rep.step = 0.01  # a float standing, and the same snap-to-int corruption as Give money above
	_c_reward_rep.tooltip_text = "Reputation added with Reward faction id (NEGATIVE to sour them). 0 = no rep change, whatever the faction id says."
	_c_reward_rep.value_changed.connect(func(_v): _write_choice())
	_labelled(_choice_box, "Reward reputation", _c_reward_rep)

	# A CheckBox is a Button, so it uses toggled / set_pressed_no_signal — NEVER the value / value_changed the
	# SpinBoxes above use (the trap quest_editor.gd:171-175 calls out).
	_c_aggro = CheckBox.new()
	_c_aggro.text = "Aggro speaker (hostile when picked)"
	_c_aggro.tooltip_text = "Turn the SPEAKER hostile: a rude / threatening line provoke()s the NPC you're talking to, so it attacks once the conversation ends."
	_c_aggro.toggled.connect(func(_b): _write_choice())
	_choice_box.add_child(_c_aggro)

	box.add_child(_choice_box)
	return box


# --- small widget helpers --------------------------------------------------------------------------------------

## A horizontal Add / Remove / Up / Down button row wired to the four supplied callables.
func _row_buttons(on_add: Callable, on_remove: Callable, on_up: Callable, on_down: Callable) -> Control:
	var row := HBoxContainer.new()
	for spec in [["+", on_add], ["-", on_remove], ["Up", on_up], ["Dn", on_down]]:
		var b := Button.new()
		b.text = spec[0]
		b.pressed.connect(spec[1])
		row.add_child(b)
	return row


## Add a "Label: <field>" row to `parent` and return the field (a typed LineEdit), for compact field building.
func _add_field(parent: VBoxContainer, label: String, field: LineEdit) -> LineEdit:
	_labelled(parent, label, field)
	return field


## Add a "Label:" + control pair on one line to `parent`.
func _labelled(parent: VBoxContainer, label: String, control: Control) -> void:
	var row := HBoxContainer.new()
	var l := Label.new()
	l.text = label + ":"
	l.add_theme_font_size_override("font_size", 10)
	l.custom_minimum_size = Vector2(96, 0)
	row.add_child(l)
	control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(control)
	parent.add_child(row)


## A small group header inside the choice-field stack ("Requirements (gates)" / "Consequences (on pick)"), at the same
## font size as the three column headers above it. Returned rather than parented so the call site reads as one child
## added in sequence — the group boundaries are then obvious from _build_choices_block alone.
## KEEP THE TEXT SHORT: this Label's minimum width propagates out through a ScrollContainer whose horizontal scrolling
## is DISABLED, so a long header would widen the whole bottom panel (the same reason PickerRows clamps its dropdowns).
func _section(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 10)
	return l


## Add a "Label: <LineEdit> [▾]" row and return the STAMP picker beside the field.
##
## The field STAYS a LineEdit — that is the whole design. A closed dropdown would make it impossible to author an id
## for content that does not exist yet (write the dialogue now, author the item .tres after), which is precisely why
## dialogue_choice.gd:91-95 chose SUGGESTION hints over a real enum. So the picker only ever STAMPS: it writes a known
## id into the field, fires the field's normal write path, and snaps back to its prompt row. Four problems collapse at
## once — typability survives, an off-disk value round-trips for free (the LineEdit is the source of truth), the
## model->widget push stays a plain `.text =` that emits nothing, and no `get_item_metadata(-1)` guard is needed.
## The caller builds and wires the LineEdit itself (tooltip + text_changed), so this helper stays layout-only.
func _stamped(parent: VBoxContainer, label: String, field: LineEdit) -> OptionButton:
	var stamp := OptionButton.new()
	stamp.tooltip_text = STAMP_TOOLTIP
	_fill_stamp(stamp, PackedStringArray())  # prompt-only until the first reveal fills the registry
	# .bind() APPENDS to the signal's own args, so the handler is (idx, btn, field) — Godot 4 does NOT drop surplus
	# args, and a 0-arg handler on item_selected errors at emit time.
	stamp.item_selected.connect(_on_stamp_picked.bind(stamp, field))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(field)
	row.add_child(stamp)
	_labelled(parent, label, row)
	return stamp


## The rows for a stamp picker: the permanent prompt at index 0, then one row per known id.
## NOT PickerRows.id_rows, on purpose, and the difference is deliberate in both directions:
##   * row 0 reads STAMP_PROMPT, never "(none)" — a stamp cannot clear a field it does not own (the LineEdit beside it
##     is cleared by deleting the text), so a row that LOOKED like "clear the field" would lie about what it does.
##   * no "(off-disk)" transient — the current value is already visible in the LineEdit, so a row echoing it back
##     would be noise. That transient exists for pickers that ARE the field; this one never is.
## PickerRows.resolve_pick still governs the write-back, so index 0 and a stale index both refuse to touch the field.
func _stamp_rows(ids: PackedStringArray) -> Array:
	var rows: Array = [{"label": STAMP_PROMPT, "value": ""}]
	for id in ids:
		# Already a String (every registry above hands back a PackedStringArray) -- the cast is belt-and-braces so a
		# future caller passing StringNames still yields JSON-safe rows, since JSON.stringify would silently COERCE a
		# StringName into a quoted string rather than failing (the trap picker_rows.gd:23-26 documents).
		var sid := String(id)
		rows.append({"label": sid, "value": sid})
	return rows


## (Re)fill a stamp picker from `ids`. Routed through PickerRows.apply for its WIDTH GUARDS, which matter more here
## than the row filling does: `fit_to_longest_item` defaults TRUE, so a dropdown holding 35 item ids would set a huge
## minimum width, and this tab's right column disables horizontal scrolling — the panel itself would widen to fit the
## longest item id. STAMP_WIDTH then overrides the module's 140px floor (a floor sized for a picker that IS the field;
## a stamp only ever displays one glyph), so the override MUST come after apply().
func _fill_stamp(btn: OptionButton, ids: PackedStringArray) -> void:
	if btn == null:
		return
	PickerRows.apply(btn, _stamp_rows(ids), "")  # "" -> index_of returns 0, i.e. the prompt row
	btn.custom_minimum_size = Vector2(STAMP_WIDTH, 0)


## Stamp a picked id into the LineEdit beside the picker. `idx` is the signal's own arg; `btn`/`field` are bound.
func _on_stamp_picked(idx: int, btn: OptionButton, field: LineEdit) -> void:
	if btn == null or field == null:
		return
	# Snap back to the prompt FIRST so the button always reads as an offer rather than as the field's value — and so a
	# second pick of the same id still emits. select() does not emit item_selected, so this cannot re-enter.
	if btn.item_count > 0:
		btn.select(0)
	# Row 0 is the prompt (stamping nothing is the honest response to it), and a stale index is refused rather than
	# guessed — the same two rules PickerRows.resolve_pick applies, kept here because a stamp has no model to clear.
	if idx <= 0 or idx >= btn.item_count:
		return
	var picked := String(btn.get_item_metadata(idx))
	if picked == "" or field.text == picked:
		return
	field.text = picked
	# `.text =` does NOT emit text_changed, so drive the SAME write path a keystroke would take. This is why the
	# model->widget sync in _on_choice_selected has to be complete: _write_choice writes EVERY widget, so a stamp on
	# one field would otherwise persist the construction defaults of any field that is never pushed.
	_write_choice()


# --- picker / load ---------------------------------------------------------------------------------------------

## Recursively collect *.tres / *.res under `dir` (absolute res:// paths). Safe when the folder is missing.
## Copied from dialogue_graph.gd's scan so the two panels list the SAME conversations.
static func _scan_resources(dir: String, out: Array[String] = []) -> Array[String]:
	var da := DirAccess.open(dir)
	if da == null:
		return out
	da.list_dir_begin()
	var fname := da.get_next()
	while fname != "":
		if fname == "." or fname == "..":
			fname = da.get_next()
			continue
		var full := dir.path_join(fname)
		if da.current_is_dir():
			_scan_resources(full, out)
		elif fname.ends_with(".tres") or fname.ends_with(".res"):
			out.append(full)
		fname = da.get_next()
	da.list_dir_end()
	out.sort()
	return out


## Refresh button: re-read the id registries AND re-scan the conversation folder, in that order, so a quest / item /
## faction authored while the editor is open reaches the stamps and the Start quest dropdown too — not just the
## conversation list. Takes no argument (pressed has none); kept separate from _refresh_picker so the reveal latch and
## the button can share one order without _refresh_picker growing a scan it doesn't own.
func _on_refresh_pressed() -> void:
	_rescan_registries()
	_refresh_picker()


func _refresh_picker() -> void:
	_picker.clear()
	_paths.clear()
	for p in _scan_resources(DIALOGUE_DIR):
		var r := load(p)
		# Only list actual DialogueResources (the folder may hold other .tres alongside).
		if r is DialogueResource:
			_picker.add_item(p.get_file())
			_paths.append(p)
	if _paths.is_empty():
		_picker.add_item("(no DialogueResource in %s)" % DIALOGUE_DIR)
		_picker.set_item_disabled(0, true)
	else:
		# OptionButton.select() doesn't emit item_selected, so load index 0 ourselves
		# (mirrors quest_editor._rescan_quests / loot_editor._reload_tables). The Refresh button reloads too.
		_picker.select(0)
		_on_pick(0)


func _on_pick(idx: int) -> void:
	if idx < 0 or idx >= _paths.size():
		return
	var r := load(_paths[idx])
	if not (r is DialogueResource):
		_set_status("Not a DialogueResource: %s" % _paths[idx])
		return
	_res = r
	_loaded_path = _paths[idx]
	_rebuild_line_list()
	_select_line(0 if not _res.lines.is_empty() else -1)
	_set_status("Editing %s (%d line(s))." % [_paths[idx], _res.lines.size()])


# --- lines -----------------------------------------------------------------------------------------------------

func _rebuild_line_list() -> void:
	_line_list.clear()
	if _res == null:
		return
	for i in range(_res.lines.size()):
		var ln: DialogueLine = _res.lines[i]
		_line_list.add_item("%d: %s" % [i, _preview(ln)])


## A one-line preview of a DialogueLine for the list (index, trimmed text, choice count).
func _preview(ln: DialogueLine) -> String:
	if ln == null:
		return "<null>"
	var t := ln.text.replace("\n", " ").strip_edges()
	if t.length() > 40:
		t = t.substr(0, 40) + "…"
	if t.is_empty():
		t = "<empty>"
	var nc := ln.choices.size()
	return t + ("  [%d choice(s)]" % nc if nc > 0 else "")


func _selected_line_index() -> int:
	var sel := _line_list.get_selected_items()
	return sel[0] if sel.size() > 0 else -1


func _selected_line() -> DialogueLine:
	var i := _selected_line_index()
	if _res == null or i < 0 or i >= _res.lines.size():
		return null
	return _res.lines[i]


func _select_line(i: int) -> void:
	if _res != null and i >= 0 and i < _res.lines.size():
		_line_list.select(i)
		_on_line_selected(i)
	else:
		_line_text.text = ""
		_line_reveals_name.button_pressed = false
		_rebuild_choice_list()


func _on_line_selected(_i: int) -> void:
	var ln := _selected_line()
	_syncing = true
	_line_text.text = ln.text if ln != null else ""
	_line_reveals_name.button_pressed = ln.reveals_name if ln != null else false
	_syncing = false
	_rebuild_choice_list()


func _on_line_text_changed() -> void:
	if _syncing:
		return
	var ln := _selected_line()
	if ln == null:
		return
	ln.text = _line_text.text
	# Refresh just this row's preview text without losing the selection.
	var i := _selected_line_index()
	if i >= 0:
		_line_list.set_item_text(i, "%d: %s" % [i, _preview(ln)])


## In-memory only (like the line text); the change reaches disk on Save. See DialogueLine.reveals_name.
func _on_line_reveals_name_toggled(pressed: bool) -> void:
	if _syncing:
		return
	var ln := _selected_line()
	if ln != null:
		ln.reveals_name = pressed


func _add_line() -> void:
	if _res == null:
		_set_status("Pick a conversation first.")
		return
	Ops.add_line(_res)
	_rebuild_line_list()
	_select_line(_res.lines.size() - 1)


func _remove_line() -> void:
	var i := _selected_line_index()
	if Ops.remove_line(_res, i):
		_rebuild_line_list()
		_select_line(mini(i, _res.lines.size() - 1))
	else:
		_set_status("Select a line to remove.")


func _line_up() -> void:
	_move_line(-1)


func _line_down() -> void:
	_move_line(1)


func _move_line(dir: int) -> void:
	var i := _selected_line_index()
	if Ops.move_line(_res, i, dir):
		_rebuild_line_list()
		_select_line(i + dir)


# --- choices ---------------------------------------------------------------------------------------------------

func _rebuild_choice_list() -> void:
	_choice_list.clear()
	_choice_box.visible = false
	var ln := _selected_line()
	if ln == null:
		return
	for j in range(ln.choices.size()):
		_choice_list.add_item(_choice_row_text(j, ln.choices[j]))


## The ONE choice-row format: "<index>: <label>" plus the consequence tag suffix ("2: I'll take the job.  [Q+]").
## Every producer of a choice row goes through here — _rebuild_choice_list, _write_choice's in-place refresh, and
## (via _rebuild_choice_list) add / remove / move — because the format was duplicated in two places and only one of
## them would ever have gained the suffix. With 28 field rows scrolling below, this suffix is the only at-a-glance
## signal that a choice DOES anything; Ops2.consequence_summary returns "" (no separator) when it does not, so an
## effect-free row is byte-identical to the row this tab has always drawn.
func _choice_row_text(j: int, ch: DialogueChoice) -> String:
	if ch == null:
		return "%d: <null>" % j
	var label := ch.text.strip_edges()
	return "%d: %s%s" % [j, label if not label.is_empty() else "<no label>", Ops2.consequence_summary(ch)]


## Repaint the SELECTED choice's row in place (its tags just changed), without disturbing the selection the way a
## full _rebuild_choice_list would.
func _refresh_selected_choice_row(ch: DialogueChoice) -> void:
	var j := _selected_choice_index()
	if j >= 0 and j < _choice_list.item_count:
		_choice_list.set_item_text(j, _choice_row_text(j, ch))


func _selected_choice_index() -> int:
	var sel := _choice_list.get_selected_items()
	return sel[0] if sel.size() > 0 else -1


func _selected_choice() -> DialogueChoice:
	var ln := _selected_line()
	var j := _selected_choice_index()
	if ln == null or j < 0 or j >= ln.choices.size():
		return null
	return ln.choices[j]


func _on_choice_selected(_j: int) -> void:
	var ch := _selected_choice()
	if ch == null:
		_choice_box.visible = false
		return
	_choice_box.visible = true
	_populate_target_options(_c_target)
	_populate_target_options(_c_target_on_fail)
	_syncing = true
	_c_text.text = ch.text
	_select_target(_c_target, ch.target)
	_select_target(_c_target_on_fail, ch.target_on_fail)
	_c_set_flag.text = String(ch.set_flag)
	_c_set_flag_value.button_pressed = ch.set_flag_value
	_c_req_flag.text = String(ch.required_flag)
	_c_req_flag_value.text = ch.required_flag_value
	_c_req_stat.text = String(ch.required_stat)
	_c_req_value.value = ch.required_value
	_c_req_faction.text = ch.required_faction_id
	_c_req_reputation.value = ch.required_reputation
	_c_req_perk.text = String(ch.required_perk_id)
	_c_req_item.text = String(ch.required_item_id)
	_c_req_item_count.value = ch.required_item_count
	_c_req_quest.text = String(ch.required_quest_id)
	_select_option_by_id(_c_req_quest_state, ch.required_quest_state)
	_c_complete_quest.text = String(ch.complete_quest_id)
	_c_advance_quest.text = String(ch.advance_quest_id)
	_c_advance_objective.text = String(ch.advance_objective_id)
	# The Consequences pushes. These are NOT optional polish: _write_choice is wired to _c_text.text_changed and fires
	# on EVERY KEYSTROKE, writing EVERY widget — so a write-back without a matching push means typing one character
	# into Label stamps the widgets' CONSTRUCTION DEFAULTS (give_money 0, give_item_id "", aggro_speaker false) onto the
	# live DialogueChoice. ContentSaveGuard keeps only ONE .bak, so a clobber plus one more Save loses the original
	# bytes as well. Every push below is signal-free (`.text =` / set_value_no_signal / set_pressed_no_signal) on top of
	# the _syncing guard, so nothing can re-enter.
	_c_give_item.text = String(ch.give_item_id)
	_c_give_count.set_value_no_signal(ch.give_item_count)
	_c_give_money.set_value_no_signal(ch.give_money)
	_c_reward_faction.text = ch.reward_reputation_faction_id
	_c_reward_rep.set_value_no_signal(ch.reward_reputation)
	_c_aggro.set_pressed_no_signal(ch.aggro_speaker)
	_sync_start_quest(ch)
	_syncing = false


## Fill a target OptionButton (`target` or `target_on_fail`): Continue / End sentinels, then one entry per real
## line index. Shared by both target dropdowns so the two stay identical.
func _populate_target_options(btn: OptionButton) -> void:
	btn.clear()
	btn.add_item("Continue (next line)", TARGET_CONTINUE)
	btn.add_item("End conversation", TARGET_END)
	if _res != null:
		for i in range(_res.lines.size()):
			btn.add_item("-> line %d" % i, i)


## Select `btn`'s entry whose item-id == `target` (ids are the sentinels / line indices).
func _select_target(btn: OptionButton, target: int) -> void:
	if _select_option_by_id(btn, target):
		return
	# Target points past the current line count (dangling). Add a transient item carrying the REAL id so the
	# next _write_choice() round-trips it back unchanged instead of silently rewriting it to Continue.
	btn.add_item("(dangling -> %d)" % target, target)
	btn.select(btn.item_count - 1)
	_set_status("A choice target -> line %d is out of range (only %d line(s)); preserved -- fix or repoint it." % [target, _res.lines.size() if _res != null else 0])


## Select the OptionButton entry whose item-id == `id`; returns false when no entry carries that id (so the
## caller can decide how to handle it). Used for both the target dropdowns and the QuestGate enum dropdown.
func _select_option_by_id(btn: OptionButton, id: int) -> bool:
	for idx in range(btn.item_count):
		if btn.get_item_id(idx) == id:
			btn.select(idx)
			return true
	return false


## Model -> widget for the Start quest dropdown: REBUILD THE ROWS FROM THE CANONICAL SCAN, then point the widget at
## `ch.start_quest_on_choice`. Safe with a null `ch` (rows collapse to "(none)").
##
## The rebuild-first order is the whole point, not tidiness. PickerRows.path_rows appends AT MOST ONE transient row —
## for a quest the scan cannot represent (a .tres outside resources/quests/, or an inline/unsaved sub-resource) — so
## without a rebuild, a transient row appended for the PREVIOUSLY selected choice lingers in the dropdown while a
## DIFFERENT choice is shown, still selectable, and clicking it silently assigns the wrong quest. That is the exact bug
## quest_editor.gd:381-383 documents in prose. Idempotent, and select() never emits item_selected, so this push can
## never write back through _on_start_quest_picked.
func _sync_start_quest(ch: DialogueChoice) -> void:
	if _c_start_quest == null:
		return
	var q: Quest = null
	if ch != null and ch.start_quest_on_choice is Quest:
		q = ch.start_quest_on_choice
	var current := ""
	if q != null:
		current = q.resource_path
	_quest_rows = PickerRows.path_rows(_quest_paths, _quest_labels, current, q != null)
	PickerRows.apply(_c_start_quest, _quest_rows, current)
	if q != null and current == "" and not _quest_rows.is_empty():
		# An INLINE / unsaved Quest sub-resource has no path to match on, so apply() would leave the widget reading
		# "(none)" while a reference really IS assigned — the mis-read that invites an accidental clobber. path_rows
		# appends its "(inline / unsaved)" row LAST for exactly this case; select it by index (the module documents
		# that it deliberately never auto-selects a row whose value is ""). Display-only: resolve_pick refuses to
		# write back through an empty-valued row, so re-picking it keeps the reference.
		_c_start_quest.select(_quest_rows.size() - 1)


## Widget -> model for the Start quest dropdown, and the ONLY writer of `start_quest_on_choice`. Kept out of
## _write_choice deliberately (see the invariant comment there): a Resource reference must never be re-resolved by a
## keystroke in an unrelated field.
##
## Every branch goes through PickerRows.resolve_pick, which is the anti-clobber table: index 0 -> clear (the one
## explicit, intended clear), an out-of-range index -> keep (a stale index from a dropdown rebuilt under a queued
## signal is refused, never guessed), a row whose value is empty at index > 0 -> keep (re-picking the
## "(inline / unsaved)" row must NOT wipe an in-memory quest). Only a real, representable pick assigns.
func _on_start_quest_picked(idx: int) -> void:
	if _syncing:
		return
	var ch := _selected_choice()
	if ch == null:
		return
	var pick: Dictionary = PickerRows.resolve_pick(_quest_rows, idx)
	var action := String(pick.get("action", "keep"))
	if action == "keep":
		return
	if action == "clear":
		ch.start_quest_on_choice = null
		_refresh_selected_choice_row(ch)  # the [Q+] tag just disappeared
		_set_status("Start quest cleared -- this choice no longer starts a quest. Save to persist.")
		return
	var path := String(pick.get("value", ""))
	var res := load(path)
	if not (res is Quest):
		_set_status("Not a Quest: %s -- start_quest_on_choice left unchanged." % path)
		return
	var q: Quest = res
	ch.start_quest_on_choice = q
	_refresh_selected_choice_row(ch)
	# The feature's own audit. QuestTracker.start_quest returns SILENTLY on an idless quest or an unmet prereq, so
	# without this the tab's highest-value write would report success for a choice that starts nothing in game.
	var warnings := Ops2.quest_start_warnings(q)
	if warnings.is_empty():
		_set_status("Start quest = '%s' (%s). Save to persist." % [String(q.id), path])
	else:
		_set_status("Start quest = '%s' -- WARNING: %s" % [String(q.id), " ".join(warnings)])


## Push every choice widget back onto the selected DialogueChoice. Guarded by _syncing so model->widget pushes
## (in _on_choice_selected) don't recurse. Refreshes the choice-row + line-row previews after a label change.
##
## THIS RUNS ON EVERY KEYSTROKE (it is wired to _c_text.text_changed and to every other field's change signal), and it
## writes EVERY widget it knows about. Two invariants follow, and breaking either one destroys authored data:
##   1. every field written here MUST also be pushed model->widget in _on_choice_selected. A field that is written but
##      never pushed persists its widget's CONSTRUCTION DEFAULT the moment the designer types a character.
##   2. `start_quest_on_choice` is deliberately NOT written here. It is a Resource REFERENCE owned by
##      _on_start_quest_picked, so a keystroke in any other field can never re-resolve or blank it. Do NOT "finish"
##      this function by adding it — reading the dropdown's selection here would reintroduce exactly that clobber
##      (a rebuilt/empty dropdown reads as index 0, i.e. "(none)").
func _write_choice() -> void:
	if _syncing:
		return
	var ch := _selected_choice()
	if ch == null:
		return
	ch.text = _c_text.text
	var ti := _c_target.selected
	if ti >= 0:
		ch.target = _c_target.get_item_id(ti)
	var fi := _c_target_on_fail.selected
	if fi >= 0:
		ch.target_on_fail = _c_target_on_fail.get_item_id(fi)
	ch.set_flag = StringName(_c_set_flag.text)
	ch.set_flag_value = _c_set_flag_value.button_pressed
	ch.required_flag = StringName(_c_req_flag.text)
	ch.required_flag_value = _c_req_flag_value.text
	ch.required_stat = StringName(_c_req_stat.text)
	ch.required_value = int(_c_req_value.value)
	ch.required_faction_id = _c_req_faction.text
	ch.required_reputation = _c_req_reputation.value
	ch.required_perk_id = StringName(_c_req_perk.text)
	ch.required_item_id = StringName(_c_req_item.text)
	ch.required_item_count = int(_c_req_item_count.value)
	ch.required_quest_id = StringName(_c_req_quest.text)
	var qi := _c_req_quest_state.selected
	if qi >= 0:
		ch.required_quest_state = _c_req_quest_state.get_item_id(qi)
	ch.complete_quest_id = StringName(_c_complete_quest.text)
	ch.advance_quest_id = StringName(_c_advance_quest.text)
	ch.advance_objective_id = StringName(_c_advance_objective.text)
	ch.give_item_id = StringName(_c_give_item.text)
	ch.give_item_count = int(_c_give_count.value)
	ch.give_money = _c_give_money.value
	ch.reward_reputation_faction_id = _c_reward_faction.text
	ch.reward_reputation = _c_reward_rep.value
	ch.aggro_speaker = _c_aggro.button_pressed
	var j := _selected_choice_index()
	if j >= 0:
		_choice_list.set_item_text(j, _choice_row_text(j, ch))
	# A line's preview shows its choice count, which is unchanged here, but a label edit is worth reflecting.
	var li := _selected_line_index()
	if li >= 0:
		_line_list.set_item_text(li, "%d: %s" % [li, _preview(_selected_line())])


func _add_choice() -> void:
	var ln := _selected_line()
	if ln == null:
		_set_status("Select a line first.")
		return
	Ops.add_choice(ln)
	_rebuild_choice_list()
	_choice_list.select(ln.choices.size() - 1)
	_on_choice_selected(ln.choices.size() - 1)
	# The line preview gained a choice -- refresh its row.
	var li := _selected_line_index()
	if li >= 0:
		_line_list.set_item_text(li, "%d: %s" % [li, _preview(ln)])


func _remove_choice() -> void:
	var ln := _selected_line()
	var j := _selected_choice_index()
	if Ops.remove_choice(ln, j):
		_rebuild_choice_list()
		var li := _selected_line_index()
		if li >= 0:
			_line_list.set_item_text(li, "%d: %s" % [li, _preview(ln)])
	else:
		_set_status("Select a choice to remove.")


func _choice_up() -> void:
	_move_choice(-1)


func _choice_down() -> void:
	_move_choice(1)


func _move_choice(dir: int) -> void:
	var ln := _selected_line()
	var j := _selected_choice_index()
	if Ops.move_choice(ln, j, dir):
		_rebuild_choice_list()
		_choice_list.select(j + dir)
		_on_choice_selected(j + dir)


# --- save ------------------------------------------------------------------------------------------------------

## Persist the edited conversation to its .tres. Save failure is REPORTED on the status label, never silently
## swallowed (mirrors faction_matrix.gd). Then nudge the editor's FileSystem so it re-imports the change.
func _save() -> void:
	if _res == null:
		_set_status("Nothing to save -- pick a conversation first.")
		return
	# Save to the path _res was LOADED from, not the picker index -- a Refresh can re-sort _paths
	# without reloading _res, so _picker.selected may now point at a DIFFERENT .tres.
	var path := _loaded_path
	if path.is_empty():
		path = _res.resource_path
	if path.is_empty():
		_set_status("Cannot save: the resource has no path.")
		return
	var err := ContentSaveGuard.save_with_backup(_res, path)  # PL5: prior bytes -> .tres.bak first, so a mis-save is recoverable
	if err != OK:
		_set_status("FAILED to save %s (err %d) -- change NOT persisted." % [path, err])
		return
	if Engine.is_editor_hint():
		EditorInterface.get_resource_filesystem().update_file(path)
	_set_status("Saved %s" % path)


func _set_status(msg: String) -> void:
	if _status != null:
		_status.text = msg
