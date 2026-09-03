@tool
extends VBoxContainer

## "Dialogue Edit" bottom-panel tab: author a branching DialogueResource (.tres) WITHOUT the raw inspector.
## Pick a conversation from resources/dialogue/, edit its lines top-to-bottom (the order IS the addressing --
## choices jump to a line by INDEX), edit each line's text and its branch choices (label + target-line & fail-target
## OptionButtons + the FULL gate set [stat / flag / faction+reputation / perk / item / quest-state] + the FULL
## consequence set [set_flag, start/complete/advance quest, give item+count, give money, reward reputation, aggro
## speaker]), reorder/add/remove lines and choices, then Save Conversation.
##
## EVERY field DialogueManager._apply_choice_effects actually applies is authorable HERE -- the raw inspector is no
## longer needed to make a conversation hand out a quest, an item, money or a grudge. Two authoring rules hold that up:
##   * an id field is NEVER a closed dropdown. The FIVE id fields this tab caches a registry for (Needs stat, Needs
##     faction id, Needs item id, Give item id, Reward faction id) are a LineEdit **plus** a narrow STAMP picker; the
##     picker writes a known id INTO the field and snaps back to its prompt row, so you can still type an id for content
##     that does not exist on disk yet -- dialogue_choice.gd:91-95 chose PROPERTY_HINT_ENUM_SUGGESTION for exactly that
##     reason ("blanks stay valid and custom names are still typable"). The LineEdit is the source of truth; the picker
##     is a typo-avoider. Fields with no registry cached here (Needs/Set flag, Needs quest id, Complete/Advance quest
##     id, Advance objective id, Needs perk id) are BARE LineEdits -- same authoring rule, just nothing to offer. Do not
##     read the stamps as a promise that every id field has one.
##   * `start_quest_on_choice` is the ONE real dropdown, because it is a Quest RESOURCE REFERENCE and not an id
##     string. It is owned by _on_start_quest_picked and is deliberately NOT written by _write_choice (see the
##     invariant comment there) -- otherwise a keystroke in any other field could re-resolve or blank it.
##
## DESIGNER SURFACE: every label, tooltip and status line here is read by someone who never opens a script. The gate
## labels read "Needs ..." (not "Req"), list rows use "(missing)" / "(empty)" / "(no text)" rather than angle-bracket
## sentinels, status lines name FILES (old_man.tres) never res:// paths, and a failed write reports error_string(err)
## rather than a number. Paths belong in tooltips only.
##
## DIRTY STATE: `_dirty` is raised by EVERY write-through (each keystroke, each stamp, each add / remove / move) and
## cleared on a successful save and on every load. It renders as a "*" on the Save Conversation button and an
## "(unsaved changes)" suffix on the status line. Every chokepoint that would SWAP the open conversation (a picker
## change, select_path) goes through _request_swap, which -- when dirty -- asks "Save changes to <file> first?"
## (Save / Discard / Cancel). Discard resets every line / choice to its script defaults FIRST and only then reloads
## with CACHE_MODE_REPLACE -- a .tres omits default-valued fields, so the reload alone would keep most of the edits
## (see _discard_changes); Cancel puts the picker back. Refresh is NOT a chokepoint: it re-reads the list and never
## touches what is open (the loaded path is re-pointed BY PATH, and the line / choice selection is restored).
##
## HANDOFF: the panel (core/host.gd) calls select_path(path) to open a conversation the Browse / Refs / Reach tabs
## found; Check Reach hands off the other way (Host.show_tab "Reach"). After a save, the tab scans scenes/ for the
## file's users so the designer learns at once whether the conversation is actually attached to a Talkable.
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
## The ONLY way this tab reaches the CYBER SUNDAY panel (Check Reach -> Host.show_tab). Off-tree the lookup returns
## null, which keeps the handoff button harmless under GUT.
const Host := preload("res://addons/cybersunday_tools/core/host.gd")
## The Refs tab's back-reference walker, borrowed ONCE PER SAVE to answer "which scenes use this conversation?" --
## the question a designer asks the moment a conversation is saved, and the one that used to send them to the Refs
## tab by hand. Pure file reads; it never writes.
const RefScan := preload("res://addons/cybersunday_tools/dock_refs/ref_scan.gd")
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

## Where the after-save "who uses this?" scan looks. Scenes only, on purpose: a conversation reaches the player
## through a Talkable (or DialogueSelector) wired in a scene, so scenes/ is where the answer lives, and a whole-project
## walk would also read the ~59 MB of voice blobs under addons/ for nothing.
const SCENES_DIR := "res://scenes"

## Row 0 of every STAMP picker: a permanent prompt, NOT a value. Picking it stamps nothing (see _on_stamp_picked),
## and every successful stamp re-selects it, so the button always reads as "offer me an id" instead of pretending to
## be the field's current value. A LOCAL const on purpose -- a glyph is not player prose and must never reach
## PlayerText (every string in this file is a DEVELOPER surface).
const STAMP_PROMPT := "▾"

## Minimum width of a stamp picker, in pixels. Deliberately BELOW PickerRows.PICKER_MIN_WIDTH (140): that floor sizes
## a picker that IS the field, while a stamp only ever displays STAMP_PROMPT and sits beside a full-width LineEdit.
const STAMP_WIDTH := 44.0

## One tooltip for all five stamp pickers -- the authoring rule is identical on each.
const STAMP_TOOLTIP := "Puts a known id into the field on the left. You can still type an id for content you haven't made yet (blank = no gate / no effect)."

## Target-OptionButton sentinel ids (kept distinct from any real line index, which is >= 0). These mirror the
## DialogueLine constants without a class_name dependency in this @tool file's const space.
const TARGET_CONTINUE := -2  # DialogueLine.CONTINUE: carry on to the NEXT line (the choice default)
const TARGET_END := -1       # DialogueLine.END: finish the conversation

## How much of a line's text a list row shows (the lines list) and a target row shows (the two Target dropdowns).
## The dropdowns get less because they sit inside a 140 px-floored, clip_text picker: "-> line 3: " already costs
## eleven characters, and the rest has to say which line this is at a glance, not read it.
const PREVIEW_CHARS := 40
const TARGET_CHARS := 24

## The Save button's resting text; "*" is appended while `_dirty` (see _update_button_states).
const SAVE_TEXT := "Save Conversation"
## Appended to the status line while `_dirty`, so any message -- a warning, a pick report -- still says the work is
## not on disk yet. Kept OUT of the individual messages so none of them doubles it.
const DIRTY_SUFFIX := " (unsaved changes)"

## Button tooltips: "<What it does>. <Writes X | Read-only>." -- two sentences at most, per the plugin's word rules.
const SAVE_TIP := "Writes the open conversation back to its file and keeps the previous version as a .bak beside it. Writes that one file."
const REFRESH_TIP := "Re-reads the dialogue folder and the id lists the pickers offer (items, factions, stats, quests). Never touches the open conversation."
const CHECK_REACH_TIP := "Opens the Reach tab and rescans it, to see whether a player can actually get to this conversation. Read-only."

## Status grammar: idle = one next step; guards name what to pick; disabled tooltips name what is missing.
const MSG_IDLE := "Pick a conversation, then a line -- its text and choices edit on the right."
const MSG_NO_CONVERSATION := "Pick a conversation first."
const MSG_NO_LINE := "Pick a line first."
const MSG_NO_CHOICE := "Pick a choice first."
const TIP_NO_CONVERSATION := "Pick a conversation first"
const TIP_NO_LINE := "Pick a line in the list first"
const TIP_NO_CHOICE := "Pick a choice in the list first"
## The after-save verdict when NO scene references the file. Deliberately tells the designer where the wiring lives
## (a Talkable child's Dialogue field) instead of offering an "assign to selected" action -- assigning is the
## Inspector's job, and a one-click assign from here would be a scene write the designer never previewed.
const MSG_NOT_ATTACHED := "Not attached to any Talkable yet -- select the NPC's Talkable child (or Palette -> Talkable on a bare NPC) and set its Dialogue in the Inspector."

## Amber for a refused / warning status (the scene_placer.gd tint), applied through a theme colour override so the
## label's default colour comes back on the next plain write -- never bbcode.
const WARN_COLOR := Color(1.0, 0.82, 0.3)

var _picker: OptionButton = null
var _status: Label = null
var _save_btn: Button = null
var _check_reach_btn: Button = null
var _line_list: ItemList = null
var _line_text: TextEdit = null
var _line_reveals_name: CheckBox = null
var _choice_list: ItemList = null
var _choice_box: VBoxContainer = null
## The Add / Remove / Up / Down rows, in that order, so _update_button_states can grey each with the tooltip that
## names what is missing (index 0 = Add needs the list's parent; 1..3 need a picked row).
var _line_buttons: Array[Button] = []
var _choice_buttons: Array[Button] = []

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

## Parallel to _picker items: the res:// path for each entry. Every re-point of the picker goes BY PATH through this
## array (never by index), so a file added or removed above the open one can't shift the selection onto another.
var _paths: Array[String] = []
## The loaded conversation being edited (null until a pick loads one, and nulled again by a failed load).
var _res: DialogueResource = null
## The res:// path _res was loaded FROM. Save targets this, not the (possibly re-sorted) picker index.
var _loaded_path: String = ""
## True while we are pushing model -> widgets, to suppress the widgets' change signals writing back.
var _syncing := false
## Unsaved edits exist on `_res` (see the DIRTY STATE header note). Only _mark_dirty raises it; _load_index and a
## successful _save clear it.
var _dirty := false
## The status line as last written, WITHOUT the dirty suffix, so _mark_dirty can re-render the same message with the
## suffix added rather than replacing whatever the designer was just told.
var _status_base := ""
var _status_warn := false
## The picker index a dirty-guarded swap is waiting on (-1 = none) and the index to fall back to on Cancel.
var _pending_pick := -1
var _prev_pick := -1
## Built lazily by the first dirty swap (a ConfirmationDialog is a Window; off-tree construction must not make one).
var _save_dialog: ConfirmationDialog = null
## Raised by the editor's filesystem_changed (a file under res:// was added, removed or reimported). The rescan
## waits for the NEXT reveal of the tab, so a designer mid-edit never has the picker rebuilt under the mouse; the
## Refresh button stays the explicit fallback.
var _fs_dirty := false

# --- cached id/registry scans (filled on first reveal + on Refresh, never at construction) ----------------------
## Item ids on disk -> the "Needs item id" / "Give item id" stamps.
var _item_ids := PackedStringArray()
## Faction ids on disk -> the "Needs faction id" / "Reward faction id" stamps.
var _faction_ids := PackedStringArray()
## CharacterStats attribute names -> the "Needs stat" stamp. A closed const list, not a folder scan, but it is stamped
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
	# The ONE status row, outside the scroll so it is always visible: two lines max, the tooltip mirrors the full text
	# on every write (_render_status), default font size, slightly dimmed so it reads as a caption, not a heading.
	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.max_lines_visible = 2
	_status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_status.modulate = Color(1, 1, 1, 0.75)
	add_child(_status)
	_set_status(MSG_IDLE)
	_update_button_states()
	# Editor-only wiring, guarded so the bare off-tree construction (GUT / the headless probe) never touches
	# EditorInterface: the filesystem signal only FLAGS the list stale (see _fs_dirty). The connection dies with this
	# Control -- Godot disconnects every signal aimed at a freed Object -- so a plugin reload leaves nothing dangling.
	if Engine.is_editor_hint():
		var fs := EditorInterface.get_resource_filesystem()
		if fs != null:
			fs.filesystem_changed.connect(_on_filesystem_changed)
	visibility_changed.connect(_on_visibility_changed)
	_on_visibility_changed()  # lazy: scan the dialogue folder on first reveal, not at panel construction (mirrors content_browser)


## Lazy first-reveal: scan the dialogue folder + fill the picker ONCE, the first time the tab is shown (not at construction).
## The id/quest registry scans go FIRST so the reveal is a single disk pass and a first click on a choice already sees
## filled stamp lists + a filled Start quest dropdown. (Unlike loot_editor, ordering is not a correctness fix here:
## _refresh_picker's cascade -> _load_index -> _select_line -> _on_line_selected ends at _rebuild_choice_list, which
## clears the choice list and HIDES _choice_box, so no choice-field widget is touched during load at all.)
## Later reveals rescan only when the editor's filesystem changed while the tab was hidden -- and that rescan keeps
## the open conversation, re-pointing the picker by path and restoring the line / choice selection.
func _on_visibility_changed() -> void:
	if is_visible_in_tree() and not _revealed:
		_revealed = true
		_rescan_registries()
		_refresh_picker()
	elif is_visible_in_tree() and _fs_dirty:
		_rescan_registries()
		_refresh_picker()


## EditorFileSystem.filesystem_changed: something under res:// changed. Only flag it -- the rescan waits for the next
## reveal (never while the designer is mid-edit in this tab). Note our own save trips this too (update_file), which
## is harmless: the next reveal's refresh keeps the open document.
func _on_filesystem_changed() -> void:
	_fs_dirty = true


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


# --- top bar: picker + Refresh + Save Conversation + Check Reach ------------------------------------------------

func _build_top_bar() -> void:
	var bar := HBoxContainer.new()
	_picker = OptionButton.new()
	_picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# Width guards (the PickerRows.apply set, by hand because this picker is filled by _refresh_picker): the
	# dropdown must never size itself to its longest file name, and a long name trims with an ellipsis.
	_picker.fit_to_longest_item = false
	_picker.clip_text = true
	_picker.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_picker.custom_minimum_size = Vector2(PickerRows.PICKER_MIN_WIDTH, 0)
	_picker.tooltip_text = "The conversation to edit. Conversations live in resources/dialogue/ -- Refresh re-reads that folder."
	_picker.item_selected.connect(_on_pick)
	bar.add_child(_picker)

	var refresh := Button.new()
	refresh.text = "Refresh"
	refresh.tooltip_text = REFRESH_TIP
	refresh.pressed.connect(_on_refresh_pressed)
	bar.add_child(refresh)

	_save_btn = Button.new()
	_save_btn.text = SAVE_TEXT
	_save_btn.tooltip_text = SAVE_TIP
	_save_btn.set_meta(&"tip", SAVE_TIP)
	_save_btn.pressed.connect(_save)
	bar.add_child(_save_btn)

	_check_reach_btn = Button.new()
	_check_reach_btn.text = "Check Reach"
	_check_reach_btn.tooltip_text = CHECK_REACH_TIP
	_check_reach_btn.pressed.connect(_on_check_reach_pressed)
	bar.add_child(_check_reach_btn)
	add_child(bar)


# --- body: lines column | (line text + choices) column ---------------------------------------------------------

func _build_body() -> void:
	var split := HBoxContainer.new()
	split.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	# Small floor so the bottom panel stays compact on a short display (see CLAUDE.md panel policy).
	split.custom_minimum_size = Vector2(0, 100)
	add_child(split)

	# Left: the lines list + its Add/Remove/Up/Down.
	var left := VBoxContainer.new()
	left.custom_minimum_size = Vector2(150, 0)
	var lhdr := Label.new()
	lhdr.text = "Lines (numbered from 0 -- targets use these numbers)"
	lhdr.modulate = Color(1, 1, 1, 0.7)  # dim, not tiny: a 10 px override made section headers unreadable
	# Autowrap so the heading wraps inside the 150 px column instead of widening it (an autowrapped Label reports a
	# 1 px minimum width); the tooltip carries the full sentence in case the wrap cuts it short.
	lhdr.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	# CAP the wrap: this heading sits OUTSIDE the scroll, so without a cap its wrapped height IS panel height, and
	# the editor's bottom splitter keeps whatever it grows to. Two rows, full sentence in the tooltip.
	lhdr.max_lines_visible = 2
	lhdr.tooltip_text = "A choice's Target points at a line by this number, so moving or removing a line changes which line later choices land on."
	left.add_child(lhdr)
	_line_list = ItemList.new()
	_line_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_line_list.custom_minimum_size = Vector2(150, 64)
	_line_list.tooltip_text = "Each row: line number, the start of its text, and how many choices it offers."
	_line_list.item_selected.connect(_on_line_selected)
	left.add_child(_line_list)
	left.add_child(_row_buttons(_line_buttons, "line",
		" -- later lines move up one number, so re-check choices that pointed past it",
		" -- targets go by number, so re-check choices that point at it",
		_add_line, _remove_line, _line_up, _line_down))
	split.add_child(left)

	# Right: selected line's text, then its choices sub-editor. The choice editor stacks 28 rows (26 fields plus the two
	# group headers, ~700px), which far exceeds this short bottom panel — so the whole right column lives in a
	# ScrollContainer. Without it the lower
	# choice fields (Fail target, the whole Consequences group) clip off the bottom edge with no way to reach them
	# (the content_dock.gd / scene_placer.gd pattern). The left lines list keeps the split's full height.
	# HEIGHT POLICY: a TabContainer's minimum is the CURRENT tab's minimum, and the editor's bottom splitter keeps the
	# height it grew to -- so one tall tab, once shown, leaves the panel tall for every tab after it. EVERY new choice
	# row must therefore land inside this ScrollContainer: vertical scrolling means the content height is never
	# propagated to the tab minimum; the head bar and the status label stay outside it deliberately. (This plugin has
	# twice shipped a tab that made the editor unusable by growing past the panel — see dock_content/content_dock.gd.)
	var right_scroll := ScrollContainer.new()
	right_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right_scroll.custom_minimum_size = Vector2(0, 100)  # the height floor this column contributes -- never the content
	right_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED  # fields fill the width; only scroll vertically
	split.add_child(right_scroll)
	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right_scroll.add_child(right)
	var thdr := Label.new()
	thdr.text = "Line text"
	thdr.modulate = Color(1, 1, 1, 0.7)  # dim, not tiny: a 10 px override made section headers unreadable
	right.add_child(thdr)
	_line_text = TextEdit.new()
	_line_text.custom_minimum_size = Vector2(0, 44)
	_line_text.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	_line_text.tooltip_text = "What the speaker says on this line. The speaker's name comes from the character you talk to, not from here."
	_line_text.text_changed.connect(_on_line_text_changed)
	right.add_child(_line_text)

	# LEGACY knob: "Stranger" now ends the moment the player talks to someone at all (DialogueManager.start ->
	# GameState.reveal_name), so a character speaker is already named before line 1 paints. Left in place for
	# authored .tres compatibility — see DialogueLine.reveals_name.
	_line_reveals_name = CheckBox.new()
	_line_reveals_name.text = "Reveals the speaker's name (legacy -- talking already does)"
	_line_reveals_name.tooltip_text = "Legacy: talking to someone at all already reveals their name, so this has nothing left to unlock. Harmless to leave on."
	_line_reveals_name.toggled.connect(_on_line_reveals_name_toggled)
	right.add_child(_line_reveals_name)

	right.add_child(_build_choices_block())


func _build_choices_block() -> Control:
	var box := VBoxContainer.new()
	box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var hdr := Label.new()
	hdr.text = "Choices (branch options)"
	hdr.modulate = Color(1, 1, 1, 0.7)  # dim, not tiny: a 10 px override made section headers unreadable
	box.add_child(hdr)

	_choice_list = ItemList.new()
	_choice_list.custom_minimum_size = Vector2(0, 50)
	# The legend for the tag suffix each row carries (built from the SAME consts Ops2.consequence_summary emits, so a
	# renamed tag can never leave the legend describing a glyph that no longer appears).
	_choice_list.tooltip_text = _tag_legend()
	_choice_list.item_selected.connect(_on_choice_selected)
	box.add_child(_choice_list)
	box.add_child(_row_buttons(_choice_buttons, "choice", "", "", _add_choice, _remove_choice, _choice_up, _choice_down))

	# The per-choice field editors, hidden until a choice is selected. 28 direct children in THREE groups, because
	# once the stack is long enough to scroll the headers have to actually mean something:
	#   1. identity      -- Label + Target
	#   2. gates         -- every "Needs *" field, ending on Fail target (where a FAILED gate goes belongs with the gates)
	#   3. consequences  -- everything DialogueManager._apply_choice_effects applies
	# `Set flag` / `Flag becomes true` sit in group 3 even though they shipped years before the rest of it: they ARE
	# consequences, and leaving them where they used to be (above the Needs header) stranded two consequences in
	# the wrong section. That move is WIDGET-ONLY -- _write_choice reads them by member and _on_choice_selected pushes
	# them by member, so no data, signal or handler changed with it.
	_choice_box = VBoxContainer.new()
	_choice_box.visible = false

	# --- 1. identity ------------------------------------------------------------------------------------------
	_c_text = _add_field(_choice_box, "Label", LineEdit.new())
	_c_text.tooltip_text = "What the player reads on this choice's button."
	_c_text.text_changed.connect(func(_t): _write_choice())

	_c_target = OptionButton.new()
	_c_target.tooltip_text = "Where picking this jumps: Continue = the next line, End = finish, or a specific line."
	_guard_dropdown(_c_target)
	_c_target.item_selected.connect(func(_i): _write_choice())
	_labelled(_choice_box, "Target", _c_target)

	# --- 2. requirements (gates) ------------------------------------------------------------------------------
	_choice_box.add_child(_section("Needs (offered only when these pass)"))

	_c_req_flag = _add_field(_choice_box, "Needs flag", LineEdit.new())
	_c_req_flag.tooltip_text = "Locked unless this story flag matches Needs flag value. Blank = no gate."
	_c_req_flag.text_changed.connect(func(_t): _write_choice())
	_c_req_flag_value = _add_field(_choice_box, "Needs flag value", LineEdit.new())
	_c_req_flag_value.tooltip_text = "The value the story flag must hold, written as text -- a flag that was simply set reads \"true\"."
	_c_req_flag_value.text_changed.connect(func(_t): _write_choice())

	_c_req_stat = LineEdit.new()
	_c_req_stat.tooltip_text = "Skill check: locked unless the player's stat is at least Needs stat value. Blank = no check."
	_c_req_stat.text_changed.connect(func(_t): _write_choice())
	_c_req_stat_stamp = _stamped(_choice_box, "Needs stat", _c_req_stat)
	_c_req_value = SpinBox.new()
	_c_req_value.min_value = 0
	_c_req_value.max_value = 999
	_c_req_value.tooltip_text = "The stat score the player needs. Only matters when Needs stat is set."
	_c_req_value.value_changed.connect(func(_v): _write_choice())
	_labelled(_choice_box, "Needs stat value", _c_req_value)

	# The remaining WR-1/WR-3 gates (faction / perk / item / quest) the raw inspector groups under the ungrouped
	# gate exports. Kept contiguous with the flag/stat gates above; the write consequences stay below.
	_c_req_faction = LineEdit.new()
	_c_req_faction.tooltip_text = "Locked unless the player's standing with this faction is at least Needs reputation. Blank = no gate."
	_c_req_faction.text_changed.connect(func(_t): _write_choice())
	_c_req_faction_stamp = _stamped(_choice_box, "Needs faction id", _c_req_faction)
	_c_req_reputation = SpinBox.new()
	_c_req_reputation.min_value = -9999
	_c_req_reputation.max_value = 9999
	_c_req_reputation.step = 0.01  # reputation is a float standing, so allow fractional / negative thresholds
	_c_req_reputation.tooltip_text = "The standing needed with that faction. Only matters when Needs faction id is set."
	_c_req_reputation.value_changed.connect(func(_v): _write_choice())
	_labelled(_choice_box, "Needs reputation", _c_req_reputation)

	# NO stamp on Needs perk id. Several fields here have no stamp (Needs/Set flag, Needs quest id, the Complete/Advance
	# ids), but this is the only one where a registry EXISTS and is still not offered: `Perks.ids()` was added in the
	# same pass as this block, so the RAW inspector finally suggests perk ids (dialogue_choice.gd:106-110). Wiring a
	# stamp is the same three lines as Needs item id below -- const-preload perks.gd, cache the ids in
	# _rescan_registries, call _stamped. Left off deliberately, so the shipped tab and the AUTHORING_GUIDE's field list
	# stay in step; add it WITH that edit.
	_c_req_perk = _add_field(_choice_box, "Needs perk id", LineEdit.new())
	_c_req_perk.tooltip_text = "Locked unless the player has learned this perk. Blank = no gate."
	_c_req_perk.text_changed.connect(func(_t): _write_choice())

	_c_req_item = LineEdit.new()
	_c_req_item.tooltip_text = "Locked unless the player carries at least Needs item count of this item -- a check, nothing is taken. Blank = no gate."
	_c_req_item.text_changed.connect(func(_t): _write_choice())
	_c_req_item_stamp = _stamped(_choice_box, "Needs item id", _c_req_item)
	_c_req_item_count = SpinBox.new()
	_c_req_item_count.min_value = 0
	_c_req_item_count.max_value = 999
	_c_req_item_count.tooltip_text = "How many the player must carry. Only matters when Needs item id is set."
	_c_req_item_count.value_changed.connect(func(_v): _write_choice())
	_labelled(_choice_box, "Needs item count", _c_req_item_count)

	_c_req_quest = _add_field(_choice_box, "Needs quest id", LineEdit.new())
	_c_req_quest.tooltip_text = "Locked unless this quest is in the Needs quest state below. Blank = no gate."
	_c_req_quest.text_changed.connect(func(_t): _write_choice())
	_c_req_quest_state = OptionButton.new()
	_c_req_quest_state.tooltip_text = "Which state the quest must be in: Any (the player knows of it), Active, Completed or Failed."
	_guard_dropdown(_c_req_quest_state)
	# QuestGate enum (ANY, ACTIVE, COMPLETED, FAILED): item ids ARE the enum values, so read/write map by id, not order.
	_c_req_quest_state.add_item("Any (known)", DialogueChoice.QuestGate.ANY)
	_c_req_quest_state.add_item("Active", DialogueChoice.QuestGate.ACTIVE)
	_c_req_quest_state.add_item("Completed", DialogueChoice.QuestGate.COMPLETED)
	_c_req_quest_state.add_item("Failed", DialogueChoice.QuestGate.FAILED)
	_c_req_quest_state.item_selected.connect(func(_i): _write_choice())
	_labelled(_choice_box, "Needs quest state", _c_req_quest_state)

	# A gated choice stays SELECTABLE (FNV-style): a FAILED check branches here. Mirrors `target` exactly
	# (Continue / End sentinels + one entry per line index). Ignored at runtime when the choice has no gate.
	_c_target_on_fail = OptionButton.new()
	_c_target_on_fail.tooltip_text = "Where a failed check leads instead: End = finish, Continue = the next line, or a specific line. Ignored when the choice has no Needs."
	_guard_dropdown(_c_target_on_fail)
	_c_target_on_fail.item_selected.connect(func(_i): _write_choice())
	_labelled(_choice_box, "Fail target", _c_target_on_fail)

	# --- 3. consequences (on pick) ----------------------------------------------------------------------------
	_choice_box.add_child(_section("Consequences (on pick)"))

	_c_set_flag = _add_field(_choice_box, "Set flag", LineEdit.new())
	_c_set_flag.tooltip_text = "Story flag set when this choice is picked. Blank = none."
	_c_set_flag.text_changed.connect(func(_t): _write_choice())
	_c_set_flag_value = CheckBox.new()
	_c_set_flag_value.text = "Flag becomes true"
	_c_set_flag_value.tooltip_text = "Uncheck to clear the flag instead."
	_c_set_flag_value.toggled.connect(func(_b): _write_choice())
	_choice_box.add_child(_c_set_flag_value)

	# The ONE true dropdown in this block: `start_quest_on_choice` is a Quest RESOURCE REFERENCE, so there is no id
	# string a LineEdit could hold. It is written by _on_start_quest_picked ALONE (never by _write_choice), and its
	# rows are rebuilt from the canonical scan on every choice selection -- see _sync_start_quest for why both of
	# those are load-bearing rather than tidiness.
	_c_start_quest = OptionButton.new()
	_c_start_quest.tooltip_text = "The quest that starts when this choice is picked. Rows read \"quest id  (file name)\"; (none) means no quest."
	# Cosmetic (PickerRows leaves it to the caller): a quest label is long, and clip_text alone is a hard cut.
	_c_start_quest.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_c_start_quest.item_selected.connect(_on_start_quest_picked)
	_labelled(_choice_box, "Start quest", _c_start_quest)
	_sync_start_quest(null)  # rows = just "(none)" until the first reveal scans resources/quests/

	_c_complete_quest = _add_field(_choice_box, "Complete quest id", LineEdit.new())
	_c_complete_quest.tooltip_text = "Quest id turned in (completed) when picked. Blank = none."
	_c_complete_quest.text_changed.connect(func(_t): _write_choice())
	_c_advance_quest = _add_field(_choice_box, "Advance quest id", LineEdit.new())
	_c_advance_quest.tooltip_text = "Quest id whose objective moves forward when picked. Needs Advance objective id too."
	_c_advance_quest.text_changed.connect(func(_t): _write_choice())
	_c_advance_objective = _add_field(_choice_box, "Advance objective id", LineEdit.new())
	_c_advance_objective.tooltip_text = "The objective (from that quest) that moves forward by one. Needs Advance quest id too."
	_c_advance_objective.text_changed.connect(func(_t): _write_choice())

	_c_give_item = LineEdit.new()
	_c_give_item.tooltip_text = "Item id given to the player when picked, Give item count of it. Blank = none."
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
	_c_give_count.tooltip_text = "How many of the item to hand over. 0 gives nothing -- clear Give item id to mean \"no item\"."
	_c_give_count.value_changed.connect(func(_v): _write_choice())
	_labelled(_choice_box, "Give item count", _c_give_count)

	_c_give_money = SpinBox.new()
	_c_give_money.min_value = -1000000
	_c_give_money.max_value = 1000000
	# step 0.01 is NOT cosmetic: money is a float, and a SpinBox SNAPS every value it is given onto its step grid --
	# set_value_no_signal(12.50) on a step-1 spin lands on 13 (Range rounds to the nearest step from min_value), which the
	# next _write_choice() would then persist. Merely SELECTING a choice would round an authored fee away.
	_c_give_money.step = 0.01
	_c_give_money.tooltip_text = "Zorkmids added to the player's wallet when picked. Negative = a fee the player pays; 0 = none."
	_c_give_money.value_changed.connect(func(_v): _write_choice())
	_labelled(_choice_box, "Give money", _c_give_money)

	_c_reward_faction = LineEdit.new()
	_c_reward_faction.tooltip_text = "Faction whose standing with the player changes when picked. Needs a non-zero Reward reputation to do anything."
	_c_reward_faction.text_changed.connect(func(_t): _write_choice())
	_c_reward_faction_stamp = _stamped(_choice_box, "Reward faction id", _c_reward_faction)
	_c_reward_rep = SpinBox.new()
	_c_reward_rep.min_value = -9999
	_c_reward_rep.max_value = 9999
	_c_reward_rep.step = 0.01  # a float standing, and the same snap-to-int corruption as Give money above
	_c_reward_rep.tooltip_text = "Standing added with that faction; negative to sour them. 0 = no change."
	_c_reward_rep.value_changed.connect(func(_v): _write_choice())
	_labelled(_choice_box, "Reward reputation", _c_reward_rep)

	# A CheckBox is a Button, so it uses toggled / set_pressed_no_signal — NEVER the value / value_changed the
	# SpinBoxes above use (the trap quest_editor.gd:171-175 calls out).
	_c_aggro = CheckBox.new()
	_c_aggro.text = "Speaker turns hostile when picked"
	_c_aggro.tooltip_text = "The character you are talking to attacks once the conversation ends. For threats and insults."
	_c_aggro.toggled.connect(func(_b): _write_choice())
	_choice_box.add_child(_c_aggro)

	box.add_child(_choice_box)
	return box


# --- small widget helpers --------------------------------------------------------------------------------------

## The legend for the choice rows' tag suffix, built from Ops2's own TAG_* consts so it can never describe a glyph the
## summary stopped emitting. One line: the ItemList tooltip is the only place it fits without costing panel height.
static func _tag_legend() -> String:
	return "Tags after a choice show what it does: %s starts a quest -- %s advances a quest -- %s completes it -- %s gives an item -- %s money -- %s reputation -- %s turns hostile" % [
		Ops2.TAG_START_QUEST, Ops2.TAG_ADVANCE_QUEST, Ops2.TAG_COMPLETE_QUEST, Ops2.TAG_GIVE_ITEM,
		Ops2.TAG_GIVE_MONEY, Ops2.TAG_REWARD_REP, Ops2.TAG_AGGRO]


## The width guards for a dropdown this tab fills BY HAND (the two Target pickers, the quest-state enum) rather than
## through PickerRows.apply: never size to the longest row, trim a long row with an ellipsis, and keep the module's
## floor so the box can't collapse when every row is short. The two Target pickers hold one row per line, each
## carrying the line's opening words, so an unguarded one would widen the whole bottom panel on the first long line.
func _guard_dropdown(btn: OptionButton) -> void:
	btn.fit_to_longest_item = false
	btn.clip_text = true
	btn.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	btn.custom_minimum_size = Vector2(PickerRows.PICKER_MIN_WIDTH, 0)


## A horizontal Add / Remove / Up / Down row for one list (`noun` = "line" / "choice"), wired to the four callables.
## The buttons also land in `out`, in that order, so _update_button_states can grey each one with a tooltip naming
## what is missing; the real tooltip is parked in the "tip" meta (the scene_placer.gd idiom) so the gate can restore
## it. `remove_note` / `move_note` are the line list's renumbering warnings ("" for choices -- reordering a choice
## never shifts any addressed index).
func _row_buttons(out: Array[Button], noun: String, remove_note: String, move_note: String,
		on_add: Callable, on_remove: Callable, on_up: Callable, on_down: Callable) -> Control:
	var row := HBoxContainer.new()
	var specs: Array = [
		["Add", on_add, "Adds a new %s at the end of the list. In memory until Save Conversation." % noun],
		["Remove", on_remove, "Removes the picked %s%s. In memory until Save Conversation." % [noun, remove_note]],
		["Up", on_up, "Moves the picked %s one place up%s. In memory until Save Conversation." % [noun, move_note]],
		["Down", on_down, "Moves the picked %s one place down%s. In memory until Save Conversation." % [noun, move_note]],
	]
	for spec in specs:
		var s: Array = spec
		var b := Button.new()
		b.text = String(s[0])
		b.tooltip_text = String(s[2])
		b.set_meta(&"tip", String(s[2]))
		b.pressed.connect(s[1])
		row.add_child(b)
		out.append(b)
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
	l.modulate = Color(1, 1, 1, 0.7)  # dim, not tiny: a 10 px override made section headers unreadable
	l.custom_minimum_size = Vector2(96, 0)
	row.add_child(l)
	control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(control)
	parent.add_child(row)


## A small group header inside the choice-field stack ("Needs (...)" / "Consequences (on pick)"), at the same font
## size as the three column headers above it. Returned rather than parented so the call site reads as one child
## added in sequence — the group boundaries are then obvious from _build_choices_block alone.
## KEEP THE TEXT SHORT: this Label's minimum width propagates out through a ScrollContainer whose horizontal scrolling
## is DISABLED, so a long header would widen the whole bottom panel (the same reason PickerRows clamps its dropdowns).
func _section(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.modulate = Color(1, 1, 1, 0.7)  # dim, not tiny: a 10 px override made section headers unreadable
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
## conversation list. Never touches the open conversation (Refresh = re-read a list); when nothing is open yet the
## refresh loads the first file and writes its own "Opened ..." line, so the two lines here cover the other cases --
## a click that reports NOTHING reads as a dead button, which is what the empty-folder branch is for.
func _on_refresh_pressed() -> void:
	_rescan_registries()
	_refresh_picker()
	if _res != null:
		_set_status("Refreshed the list -- %d conversation(s); %s stays open." % [_paths.size(), _loaded_path.get_file()])
	elif _paths.is_empty():
		_set_status("Refreshed the list -- there are no conversations in the dialogue folder yet.", true)


## Host seam (cyber_panel.open_in_editor -> here): open the conversation saved at `path` in this tab. Reveals the
## registries if the tab was never shown (a handoff can arrive before the first reveal off-tree), re-reads the folder
## so a freshly written file is listed, then points the picker at the path and opens it THROUGH THE DIRTY GUARD -- an
## unsaved conversation is never silently replaced by a handoff. true when the file is in the list (even if the
## guard is now asking); false when it isn't a conversation in the dialogue folder, so the host falls back to the
## Inspector.
func select_path(path: String) -> bool:
	if path.is_empty():
		return false
	if not _revealed:
		_revealed = true
		_rescan_registries()
	_refresh_picker(path)
	var idx := _paths.find(path)
	if idx < 0:
		_set_status("Couldn't open %s: it isn't a conversation in the dialogue folder." % path.get_file(), true)
		return false
	if _res != null and _loaded_path == path:
		return true  # already open (or _refresh_picker just opened it as the first load)
	_picker.select(idx)  # what the widget does on its own before item_selected fires -- Cancel puts it back
	_request_swap(idx)
	return true


## Re-scan the dialogue folder and rebuild the picker WITHOUT touching the open conversation: the picker is re-pointed
## at `_loaded_path` BY PATH (never by index -- a file added above it must not shift the pick), and the line / choice
## selection is restored. When nothing is open yet (first reveal, a failed load, an empty folder before) it opens
## `want` if that is on disk, else the picker's current row, else the first file. A deleted / renamed open file is
## kept open behind a DISABLED "(missing on disk)" row so the picker never lies about what the editor holds -- Save
## Conversation still writes it back (a first-ever save at that path). Clears _fs_dirty: this IS the rescan the
## filesystem flag asks for.
func _refresh_picker(want: String = "") -> void:
	var keep := _loaded_path if _res != null else _picker_path()
	var li := _selected_line_index()
	var cj := _selected_choice_index()
	_fs_dirty = false
	_picker.clear()
	_paths.clear()
	for p in _scan_resources(DIALOGUE_DIR):
		var r := load(p)
		# Only list actual DialogueResources (the folder may hold other .tres alongside -- a VoiceData, say).
		if r is DialogueResource:
			_picker.add_item(p.get_file())
			_paths.append(p)
	if _res != null and keep != "" and not _paths.has(keep):
		_picker.add_item("%s (missing on disk)" % keep.get_file())
		_picker.set_item_disabled(_picker.item_count - 1, true)
		_paths.append(keep)
	if _paths.is_empty():
		_picker.add_item("(no conversations in the dialogue folder)")
		_picker.set_item_disabled(0, true)
		_update_button_states()
		return
	if _res != null:
		# OptionButton.select() never emits item_selected, so the open document is untouched by design.
		_picker.select(maxi(_paths.find(keep), 0))
		_restore_selection(li, cj)
		return
	var idx := _paths.find(want)
	if idx < 0:
		idx = _paths.find(keep)
	idx = maxi(idx, 0)
	_picker.select(idx)
	_load_index(idx)


## The res:// path the picker currently points at ("" when it shows a placeholder row or nothing).
func _picker_path() -> String:
	var i := _picker.selected if _picker != null else -1
	return _paths[i] if i >= 0 and i < _paths.size() else ""


## Picker change (the widget's item_selected): route the swap through the dirty guard. Re-picking the conversation
## that is already open is a no-op, not a reload -- Reload is the guard's Discard, never a click on the same row.
func _on_pick(idx: int) -> void:
	if idx < 0 or idx >= _paths.size():
		return
	if _res != null and _paths[idx] == _loaded_path:
		return
	_request_swap(idx)


## THE chokepoint for replacing the open conversation. Clean (or nothing open): load at once. Dirty: park the pick and
## ask "Save changes to <file> first?" -- Save writes then swaps, Discard reloads the file from disk (so the resource
## cache holds disk truth again, not the abandoned edits) then swaps, Cancel puts the picker back on the open file.
## Off-tree (GUT / the headless probe) there is no window to ask in, so the swap is REFUSED and the document kept --
## refusing beats guessing, and a test can pin that the picker springs back.
func _request_swap(idx: int) -> void:
	if not _dirty or _res == null:
		_load_index(idx)
		return
	_pending_pick = idx
	_prev_pick = _paths.find(_loaded_path)
	if not is_inside_tree():
		_pending_pick = -1
		_restore_picker(_prev_pick)
		_set_status("Couldn't open %s: %s has unsaved changes -- Save Conversation first." % [_paths[idx].get_file(), _loaded_path.get_file()], true)
		return
	if _save_dialog == null:
		_save_dialog = ConfirmationDialog.new()
		_save_dialog.title = "Unsaved changes"
		_save_dialog.ok_button_text = "Save"
		_save_dialog.add_button("Discard", true, "discard")
		_save_dialog.confirmed.connect(_on_swap_save)
		_save_dialog.custom_action.connect(_on_swap_custom)
		_save_dialog.canceled.connect(_on_swap_cancel)
		add_child(_save_dialog)
	_save_dialog.dialog_text = "Save changes to %s first?" % _loaded_path.get_file()
	_save_dialog.popup_centered()


## Dialog "Save": write the open conversation, then swap only if the write succeeded (a failed save keeps the dirty
## document open and the picker on it -- _save already reported why).
func _on_swap_save() -> void:
	var idx := _pending_pick
	_pending_pick = -1
	_save()
	if _dirty:
		_restore_picker(_prev_pick)
		return
	_load_index(idx)


## Dialog "Discard": throw the in-memory edits away (see _discard_changes for why that is TWO steps, not one),
## then swap. A custom button does not close the dialog by itself, hence the hide().
func _on_swap_custom(action: StringName) -> void:
	if action != &"discard":
		return
	var idx := _pending_pick
	_pending_pick = -1
	if _save_dialog != null:
		_save_dialog.hide()
	_discard_changes()
	_load_index(idx)


## Put the open conversation back to what its file says. TWO steps, and the ORDER is the whole correctness of
## Discard -- a bare CACHE_MODE_REPLACE reload is very nearly a NO-OP on a conversation, which is exactly the bug
## quest_editor.gd:970-976 documents one dock over:
##   1. every script field on the resource, on each of its lines and on each of their choices goes back to the value
##      a fresh instance carries. A .tres OMITS default-valued fields, and old_man.tres shows how far that reaches:
##      on disk it carries `lines` and `choices` and NOTHING else -- no line text, no choice label, no consequence.
##      So a reload alone re-assigns two arrays and leaves every character the designer just typed sitting on the
##      cached sub-resources, with `_dirty` cleared -- Discard would silently KEEP the edits it promised to throw
##      away, the Graphs / Refs tabs and the Inspector would keep showing them, and the next Save would persist them.
##   2. THEN the CACHE_MODE_REPLACE load re-assigns every field the file DOES carry back into those same cached
##      instances (the text loader reuses the cached main resource and its sub-resources), so every other holder of
##      this conversation sees disk truth too.
## Children before parents: resetting a line empties its `choices`, and resetting the resource empties `lines`, so a
## reset parent would strand its rows unreset.
func _discard_changes() -> void:
	if _loaded_path.is_empty() or not ResourceLoader.exists(_loaded_path):
		# Nothing on disk to restore FROM (the file was renamed or deleted -- the picker is showing its disabled
		# "(missing on disk)" row). Resetting here would EMPTY the conversation rather than revert it, and an empty
		# conversation is a worse answer than the edits themselves: they are all that is left of that file. So leave
		# the instance alone -- the caller's swap moves the tab onto the file it was asked for, and the abandoned
		# document keeps its content in the cache rather than being blanked on the way out.
		return
	if _res != null:
		for ln: DialogueLine in _res.lines:
			if ln == null:
				continue
			for ch: DialogueChoice in ln.choices:
				if ch != null:
					_reset_to_defaults(ch)
			_reset_to_defaults(ln)
		_reset_to_defaults(_res)
	_dirty = false
	# The return value is the same cached instance `_res` already holds, now refilled from disk.
	var _fresh: Resource = ResourceLoader.load(_loaded_path, "", ResourceLoader.CACHE_MODE_REPLACE)


## Put every stored script field of `obj` back to the value a fresh instance of its script would carry. Pure Object
## API (no disk, no editor), so a test can run it on a throwaway DialogueChoice. Only SCRIPT-declared, STORED fields
## are touched -- never `resource_path` (clearing that would evict the resource from the cache), `resource_name` or
## the script itself.
##
## DUPLICATED from quest_editor.gd:996 verbatim, and knowingly: both docks need the identical "a .tres omits its
## defaults" fix, and neither may reach into the other's private methods. If a third dock needs it, extract it to
## core/ (beside content_save_guard.gd / picker_rows.gd) and point all three at that -- do not copy it again.
static func _reset_to_defaults(obj: Object) -> int:
	if obj == null:
		return 0
	var script := obj.get_script() as GDScript
	if script == null:
		return 0
	var fresh: Object = script.new()
	if fresh == null:
		return 0
	var n := 0
	for p: Dictionary in obj.get_property_list():
		var usage := int(p.get("usage", 0))
		if (usage & PROPERTY_USAGE_SCRIPT_VARIABLE) == 0 or (usage & PROPERTY_USAGE_STORAGE) == 0:
			continue
		var pname := String(p.get("name", ""))
		if pname.is_empty():
			continue
		var d: Variant = fresh.get(pname)
		if obj.get(pname) != d:
			obj.set(pname, d)
			n += 1
	if not (fresh is RefCounted):
		fresh.free()  # a Resource is RefCounted and releases itself; anything else would leak
	return n


## Dialog "Cancel" (or its close box): keep the dirty document and put the picker back on it. Ignored when no swap is
## pending -- a Save / Discard already consumed the pick.
func _on_swap_cancel() -> void:
	if _pending_pick < 0:
		return
	_pending_pick = -1
	_restore_picker(_prev_pick)
	_set_status("Kept %s open -- its changes are still only in memory." % _loaded_path.get_file())


## Point the picker back at `idx` without emitting (select() never fires item_selected).
func _restore_picker(idx: int) -> void:
	if _picker != null and idx >= 0 and idx < _picker.item_count:
		_picker.select(idx)


## The actual load, past the dirty guard: open `_paths[idx]`, rebuild the line list, pick line 0. A file that fails to
## load (mid-reimport, a broken sub-resource, not a conversation) empties the editor through _clear_loaded rather
## than leaving the PREVIOUS conversation on screen under the new picker row -- that mismatch is how a designer edits
## the wrong file.
func _load_index(idx: int) -> void:
	if idx < 0 or idx >= _paths.size():
		return
	var path := _paths[idx]
	var r := load(path)
	if not (r is DialogueResource):
		_clear_loaded(path)
		return
	_res = r
	_loaded_path = path
	_dirty = false
	_rebuild_line_list()
	_select_line(0 if not _res.lines.is_empty() else -1)
	_set_status("Opened %s -- %d line(s). Pick a line to edit its text and choices." % [path.get_file(), _res.lines.size()])
	_update_button_states()


## The failed-load branch: no document, empty lists, the choice editor hidden, and every write button greyed (Save
## Conversation and the two Add / Remove / Up / Down rows) until a load succeeds. The picker keeps pointing at the
## file so that Refresh -- which reloads the picker's row when nothing is open -- is the retry.
func _clear_loaded(path: String) -> void:
	_res = null
	_loaded_path = ""
	_dirty = false
	_syncing = true
	_line_list.clear()
	_line_text.text = ""
	_line_reveals_name.set_pressed_no_signal(false)
	_syncing = false
	_rebuild_choice_list()  # clears the list and hides the choice box (no line is selected now)
	_set_status("Couldn't load %s -- reimport in progress? press Refresh." % path.get_file(), true)
	_update_button_states()


## Re-select line `li` and choice `cj` after a refresh / reload, when they still exist. Pushes are signal-free, so
## restoring a selection can never write anything back.
func _restore_selection(li: int, cj: int) -> void:
	if _res == null or li < 0 or li >= _res.lines.size():
		return
	_select_line(li)
	var ln := _selected_line()
	if ln != null and cj >= 0 and cj < ln.choices.size():
		_choice_list.select(cj)
		_on_choice_selected(cj)


## Check Reach: switch to the Reach tab (the panel expands the bottom panel as part of show_tab) and ask it to rescan
## when it offers a public rescan, so the report is fresh for the conversation just saved. Read-only either side.
func _on_check_reach_pressed() -> void:
	var reach := Host.show_tab(self, "Reach")
	if reach == null:
		_set_status("Couldn't open Reach: this tab isn't inside the CYBER SUNDAY panel.", true)
		return
	if reach.has_method("rescan"):
		reach.call("rescan")
	_set_status("Opened Reach -- it lists which conversations a player can actually get to.")


# --- lines -----------------------------------------------------------------------------------------------------

func _rebuild_line_list() -> void:
	_line_list.clear()
	if _res != null:
		for i in range(_res.lines.size()):
			var ln: DialogueLine = _res.lines[i]
			_line_list.add_item("%d: %s" % [i, _preview(ln)])
	_update_button_states()


## A one-line preview of a DialogueLine for the list (index, trimmed text, choice count).
func _preview(ln: DialogueLine) -> String:
	if ln == null:
		return "(missing)"
	var t := _short(ln.text, PREVIEW_CHARS)
	if t.is_empty():
		t = "(empty)"
	var nc := ln.choices.size()
	return t + ("  [%d choice(s)]" % nc if nc > 0 else "")


## The first `n` characters of a (possibly multi-line) text on one line, with "..." when it was cut.
static func _short(text: String, n: int) -> String:
	var t := text.replace("\n", " ").strip_edges()
	if t.length() > n:
		t = t.substr(0, n).strip_edges() + "..."
	return t


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
		_syncing = true
		_line_text.text = ""
		_line_reveals_name.set_pressed_no_signal(false)
		_syncing = false
		_rebuild_choice_list()
	_update_button_states()


func _on_line_selected(_i: int) -> void:
	var ln := _selected_line()
	_syncing = true
	_line_text.text = ln.text if ln != null else ""
	_line_reveals_name.set_pressed_no_signal(ln.reveals_name if ln != null else false)
	_syncing = false
	_rebuild_choice_list()
	_update_button_states()


## The line-text write-through. TWO guards, and the second is not redundant: a TextEdit emits text_changed DEFERRED
## (one frame later, and only in-tree), so the model->widget push in _on_line_selected lands here AFTER _syncing is
## already false, indistinguishable from a keystroke. An unchanged text is not an edit -- without that test, merely
## selecting a line would mark the conversation dirty. (A LineEdit's setter never emits, which is why the choice
## fields need no such guard.)
func _on_line_text_changed() -> void:
	if _syncing:
		return
	var ln := _selected_line()
	if ln == null or ln.text == _line_text.text:
		return
	ln.text = _line_text.text
	_mark_dirty()
	# Refresh just this row's preview text without losing the selection.
	var i := _selected_line_index()
	if i >= 0:
		_line_list.set_item_text(i, "%d: %s" % [i, _preview(ln)])


## In-memory only (like the line text); the change reaches disk on Save Conversation. See DialogueLine.reveals_name.
func _on_line_reveals_name_toggled(pressed: bool) -> void:
	if _syncing:
		return
	var ln := _selected_line()
	if ln != null:
		ln.reveals_name = pressed
		_mark_dirty()


func _add_line() -> void:
	if _res == null:
		_set_status(MSG_NO_CONVERSATION, true)
		return
	Ops.add_line(_res)
	_mark_dirty()
	_rebuild_line_list()
	_select_line(_res.lines.size() - 1)


func _remove_line() -> void:
	var i := _selected_line_index()
	if Ops.remove_line(_res, i):
		_mark_dirty()
		_rebuild_line_list()
		_select_line(mini(i, _res.lines.size() - 1))
	else:
		_set_status(MSG_NO_LINE, true)


func _line_up() -> void:
	_move_line(-1)


func _line_down() -> void:
	_move_line(1)


func _move_line(dir: int) -> void:
	var i := _selected_line_index()
	if Ops.move_line(_res, i, dir):
		_mark_dirty()
		_rebuild_line_list()
		_select_line(i + dir)
		return
	# A refused move used to be SILENT: the designer clicks Up on line 0 and the panel says nothing, which reads as a
	# broken button rather than "it is already first". The gate greys the button for "nothing picked", so this is the
	# fallback the click that slips through still lands on.
	if i < 0:
		_set_status(MSG_NO_LINE, true)
	else:
		_set_status("Couldn't move that line: it is already %s the list." % ("first in" if dir < 0 else "last in"), true)


# --- choices ---------------------------------------------------------------------------------------------------

func _rebuild_choice_list() -> void:
	_choice_list.clear()
	_choice_box.visible = false
	var ln := _selected_line()
	if ln != null:
		for j in range(ln.choices.size()):
			_choice_list.add_item(_choice_row_text(j, ln.choices[j]))
	_update_button_states()


## The ONE choice-row format: "<index>: <label>" plus the consequence tag suffix ("2: I'll take the job.  [Q+]").
## Every producer of a choice row goes through here — _rebuild_choice_list, _write_choice's in-place refresh, and
## (via _rebuild_choice_list) add / remove / move — because the format was duplicated in two places and only one of
## them would ever have gained the suffix. With 28 field rows scrolling below, this suffix is the only at-a-glance
## signal that a choice DOES anything; Ops2.consequence_summary returns "" (no separator) when it does not, so an
## effect-free row is byte-identical to the row this tab has always drawn. The ItemList's tooltip is the legend.
func _choice_row_text(j: int, ch: DialogueChoice) -> String:
	if ch == null:
		return "%d: (missing)" % j
	var label := ch.text.strip_edges()
	return "%d: %s%s" % [j, label if not label.is_empty() else "(no text)", Ops2.consequence_summary(ch)]


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
		_update_button_states()
		return
	_choice_box.visible = true
	_populate_target_options(_c_target)
	_populate_target_options(_c_target_on_fail)
	_syncing = true
	_c_text.text = ch.text
	_select_target(_c_target, ch.target)
	_select_target(_c_target_on_fail, ch.target_on_fail)
	_c_set_flag.text = String(ch.set_flag)
	_c_set_flag_value.set_pressed_no_signal(ch.set_flag_value)
	_c_req_flag.text = String(ch.required_flag)
	_c_req_flag_value.text = ch.required_flag_value
	_c_req_stat.text = String(ch.required_stat)
	_c_req_value.set_value_no_signal(ch.required_value)
	_c_req_faction.text = ch.required_faction_id
	_c_req_reputation.set_value_no_signal(ch.required_reputation)
	_c_req_perk.text = String(ch.required_perk_id)
	_c_req_item.text = String(ch.required_item_id)
	_c_req_item_count.set_value_no_signal(ch.required_item_count)
	_c_req_quest.text = String(ch.required_quest_id)
	if not _select_option_by_id(_c_req_quest_state, ch.required_quest_state):
		# The stored state is none of the four (a hand-edited file). The push FAILED, and a failed push is the one
		# thing this block cannot shrug off: the dropdown would keep the PREVIOUSLY selected choice's row, and
		# _write_choice -- which fires on every keystroke and writes EVERY widget -- would stamp THAT state onto THIS
		# choice. Park it on row 0 and say so. Deliberately NOT the transient-row trick _select_target uses: this
		# dropdown is built once in _build_choices_block and never rebuilt, so a transient row would linger on every
		# later choice as a selectable, wrong answer.
		_c_req_quest_state.select(0)
		_set_status("This choice's Needs quest state wasn't one of the four -- showing Any. Set it before you save.", true)
	_c_complete_quest.text = String(ch.complete_quest_id)
	_c_advance_quest.text = String(ch.advance_quest_id)
	_c_advance_objective.text = String(ch.advance_objective_id)
	# The Consequences pushes. These are NOT optional polish: _write_choice is wired to _c_text.text_changed and fires
	# on EVERY KEYSTROKE, writing EVERY widget — so a write-back without a matching push means typing one character
	# into Label stamps the widgets' CONSTRUCTION DEFAULTS (give_money 0, give_item_id "", aggro_speaker false) onto the
	# live DialogueChoice. ContentSaveGuard keeps only ONE .bak, so a clobber plus one more Save loses the original
	# bytes as well. Every push above and below is signal-free (`.text =` / set_value_no_signal / set_pressed_no_signal)
	# on top of the _syncing guard, so nothing can re-enter -- and none of them can raise _dirty.
	_c_give_item.text = String(ch.give_item_id)
	_c_give_count.set_value_no_signal(ch.give_item_count)
	_c_give_money.set_value_no_signal(ch.give_money)
	_c_reward_faction.text = ch.reward_reputation_faction_id
	_c_reward_rep.set_value_no_signal(ch.reward_reputation)
	_c_aggro.set_pressed_no_signal(ch.aggro_speaker)
	_sync_start_quest(ch)
	_syncing = false
	_update_button_states()


## Fill a target OptionButton (`target` or `target_on_fail`): Continue / End sentinels, then one entry per real
## line, "-> line 3: <its opening words>..." so the designer picks by what the line SAYS, not by a bare number.
## Shared by both target dropdowns so the two stay identical.
func _populate_target_options(btn: OptionButton) -> void:
	btn.clear()
	# NEVER pass a sentinel straight to add_item's `id`: OptionButton treats id == -1 as "auto-assign", and
	# DialogueLine.END IS -1. Passing it made the End row carry id 1 (its index) -- so picking "End conversation"
	# wrote target = 1 ("jump to line 1"), and an authored End choice matched no row, so it painted the scary
	# "points at line -1 (missing)" warning instead of selecting End. Add the row, then stamp the id explicitly.
	btn.add_item("Continue (next line)")
	btn.set_item_id(btn.item_count - 1, TARGET_CONTINUE)
	btn.add_item("End conversation")
	btn.set_item_id(btn.item_count - 1, TARGET_END)
	if _res != null:
		for i in range(_res.lines.size()):
			btn.add_item("-> line %d: %s" % [i, _target_label(_res.lines[i])])
			btn.set_item_id(btn.item_count - 1, i)


## The text half of a target row: the line's opening words, or "(empty)" / "(missing)".
func _target_label(ln: DialogueLine) -> String:
	if ln == null:
		return "(missing)"
	var t := _short(ln.text, TARGET_CHARS)
	return t if not t.is_empty() else "(empty)"


## Select `btn`'s entry whose item-id == `target` (ids are the sentinels / line indices).
func _select_target(btn: OptionButton, target: int) -> void:
	if _select_option_by_id(btn, target):
		return
	# Target points past the current line count (dangling). Add a transient item carrying the REAL id so the
	# next _write_choice() round-trips it back unchanged instead of silently rewriting it to Continue.
	var count := _res.lines.size() if _res != null else 0
	# Same add_item id trap as above: stamp the id after adding, never through the `id` argument.
	btn.add_item("-> line %d (missing -- only %d line(s))" % [target, count])
	btn.set_item_id(btn.item_count - 1, target)
	btn.select(btn.item_count - 1)
	_set_status("A choice points at line %d, but there are only %d line(s) -- kept as it is; repoint it with Target." % [target, count], true)


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
		_mark_dirty()
		_refresh_selected_choice_row(ch)  # the [Q+] tag just disappeared
		_set_status("Cleared the start quest -- this choice no longer starts one.")
		return
	var path := String(pick.get("value", ""))
	var res := load(path)
	if not (res is Quest):
		_set_status("Couldn't pick %s: it isn't a quest -- Start quest left as it was." % path.get_file(), true)
		return
	var q: Quest = res
	ch.start_quest_on_choice = q
	_mark_dirty()
	_refresh_selected_choice_row(ch)
	# The feature's own audit. Starting a quest silently does nothing for an idless quest or an unmet prerequisite,
	# so without this the tab's highest-value write would report success for a choice that starts nothing in game.
	var warnings := Ops2.quest_start_warnings(q)
	# An idless quest is one of the two things quest_start_warnings reports, so String(q.id) is "" in exactly the
	# case the warning fires -- name the FILE there, or the line reads "Set the start quest to  -- WARN: ...".
	var shown := String(q.id) if String(q.id) != "" else path.get_file()
	if warnings.is_empty():
		_set_status("Set the start quest to %s (%s)." % [shown, path.get_file()])
	else:
		_set_status("Set the start quest to %s -- WARN: %s" % [shown, " ".join(warnings)], true)


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
## It is also a write-through, so it raises _dirty -- after the null-choice guard, so a stray emit with nothing
## selected (the arity test emits every signal on a bare tab) never marks an empty editor dirty.
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
	_mark_dirty()
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
		_set_status(MSG_NO_LINE, true)
		return
	Ops.add_choice(ln)
	_mark_dirty()
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
		_mark_dirty()
		_rebuild_choice_list()
		var li := _selected_line_index()
		if li >= 0:
			_line_list.set_item_text(li, "%d: %s" % [li, _preview(ln)])
	else:
		_set_status(MSG_NO_CHOICE, true)


func _choice_up() -> void:
	_move_choice(-1)


func _choice_down() -> void:
	_move_choice(1)


func _move_choice(dir: int) -> void:
	var ln := _selected_line()
	var j := _selected_choice_index()
	if Ops.move_choice(ln, j, dir):
		_mark_dirty()
		_rebuild_choice_list()
		_choice_list.select(j + dir)
		_on_choice_selected(j + dir)
		return
	# Same silent-refusal fallback as _move_line: an unmoved row with no message reads as a dead button.
	if ln == null:
		_set_status(MSG_NO_LINE, true)
	elif j < 0:
		_set_status(MSG_NO_CHOICE, true)
	else:
		_set_status("Couldn't move that choice: it is already %s the list." % ("first in" if dir < 0 else "last in"), true)


# --- dirty state + button gates --------------------------------------------------------------------------------

## Raise the unsaved-changes flag (idempotent) and show it: "*" on Save Conversation, the suffix on the status line.
## The status text itself is kept -- the designer's last message stays readable, it just gains the suffix.
func _mark_dirty() -> void:
	if _dirty:
		return
	_dirty = true
	_update_button_states()
	_render_status()


## Every button's enabled state + tooltip, derived from what is open / picked. A button that cannot apply is greyed
## with the tooltip naming what is missing (the "tip" meta holds its real tooltip for when it can); the handlers keep
## their status-line guards as the fallback for a click that slips through.
func _update_button_states() -> void:
	var has_res := _res != null
	var has_line := _selected_line() != null
	var has_choice := _selected_choice() != null
	if _save_btn != null:
		_save_btn.text = SAVE_TEXT + ("*" if _dirty else "")
		_gate(_save_btn, has_res, TIP_NO_CONVERSATION)
	for k in _line_buttons.size():
		# Add needs an open conversation; Remove / Up / Down need a picked line.
		_gate(_line_buttons[k], has_res if k == 0 else has_line, TIP_NO_CONVERSATION if k == 0 else TIP_NO_LINE)
	for k in _choice_buttons.size():
		# Add needs a picked line; Remove / Up / Down need a picked choice.
		_gate(_choice_buttons[k], has_line if k == 0 else has_choice, TIP_NO_LINE if k == 0 else TIP_NO_CHOICE)


## Grey `b` with `missing` as its tooltip, or restore its real tooltip from the "tip" meta.
func _gate(b: Button, ok: bool, missing: String) -> void:
	if b == null:
		return
	b.disabled = not ok
	b.tooltip_text = String(b.get_meta(&"tip", "")) if ok else missing


# --- save ------------------------------------------------------------------------------------------------------

## Persist the edited conversation to its .tres through ContentSaveGuard (the prior bytes go to a .bak beside the file
## first, so a mis-save is recoverable by renaming it back). Save failure is REPORTED on the status label, never
## silently swallowed (mirrors faction_matrix.gd). Then nudge the editor's FileSystem so it re-imports the change, and
## answer the designer's next question -- "is this conversation attached to anything?" -- with a scenes/ scan.
func _save() -> void:
	if _res == null:
		_set_status(MSG_NO_CONVERSATION, true)
		return
	# Save to the path _res was LOADED from, not the picker index -- a Refresh can re-sort _paths
	# without reloading _res, so _picker.selected may now point at a DIFFERENT .tres.
	var path := _loaded_path
	if path.is_empty():
		path = _res.resource_path
	if path.is_empty():
		_set_status("Couldn't save the conversation: it has no file yet.", true)
		return
	var had_prior := FileAccess.file_exists(path)  # only an existing file gets a .bak, so only then is one reported
	var err := ContentSaveGuard.save_with_backup(_res, path)  # PL5: prior bytes -> .tres.bak first, so a mis-save is recoverable
	if err != OK:
		_set_status("Couldn't save %s: %s -- the change is still only in memory." % [path.get_file(), error_string(err)], true)
		return
	_dirty = false
	if Engine.is_editor_hint():
		EditorInterface.get_resource_filesystem().update_file(path)
	var report := "Saved %s" % path.get_file()
	if had_prior:
		report += " -- previous version kept as %s." % ContentSaveGuard.backup_path(path).get_file()
	else:
		report += "."
	_set_status(report + " " + _usage_report(path))
	_update_button_states()


## "Used by N scene(s): a.tscn, b.tscn." for the scenes under SCENES_DIR that reference `path` (by path or uid), or
## the not-attached hint. One RefScan walk per save -- it reads every scene file, so it is never run per keystroke.
func _usage_report(path: String) -> String:
	var refs: Array = RefScan.find_referencers(path, SCENES_DIR)
	if refs.is_empty():
		return MSG_NOT_ATTACHED
	var names := PackedStringArray()
	for entry in refs:
		var row: Dictionary = entry if entry is Dictionary else {}
		var file := String(row.get("file", "")).get_file()
		if file != "":
			names.append(file)
	return "Used by %d scene(s): %s." % [names.size(), ", ".join(names)]


# --- status ----------------------------------------------------------------------------------------------------

## Write the status row: `msg` (kept as the base for the dirty suffix), amber when `warn`.
func _set_status(msg: String, warn: bool = false) -> void:
	_status_base = msg
	_status_warn = warn
	_render_status()


## Paint the status Label from the base message + the dirty suffix. The label clamps to two lines, so the tooltip
## mirrors the whole text; the colour goes through a theme override so a plain write restores the default.
func _render_status() -> void:
	if _status == null:
		return
	var text := _status_base
	if _dirty and _res != null:
		text += DIRTY_SUFFIX
	_status.text = text
	_status.tooltip_text = text
	if _status_warn:
		_status.add_theme_color_override("font_color", WARN_COLOR)
	else:
		_status.remove_theme_color_override("font_color")
