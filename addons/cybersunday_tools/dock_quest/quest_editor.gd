@tool
extends VBoxContainer

## QUEST EDIT dock (the "Quests" tool of the CYBER SUNDAY panel's Create group; the Control `name` stays "Quest Edit"
## because tests and cyber_panel's registry key on it — the panel sets the display title). It edits an authored
## Quest's headline fields, reward money/XP, the item rewards[] list, prereq + next-quest chaining, the auto-complete /
## expire-on-flag flow flags, and its ordered objectives list (each with its optional world marker) WITHOUT the raw
## inspector. A picker (scans resources/quests/) loads a Quest .tres into plain widgets; an objectives ItemList +
## Add/Remove/Up/Down + a per-objective editor (type dropdown, target id + stamp, required count, objective text,
## optional, marker + XYZ) edits the list; a parallel rewards ItemList + item picker + count edits rewards[]; Save
## Quest writes the .tres back (ContentSaveGuard.save_with_backup + FileSystem.update_file) so it persists.
##
## LAYOUT, top to bottom: ONE head bar (the quest picker, Refresh, Save Quest, Check Reach) and ONE status Label sit
## OUTSIDE the ScrollContainer so the open quest and Save never scroll away; every form row lives INSIDE it in `_body`.
## HEIGHT CONTRACT: a TabContainer's minimum is the CURRENT tab's minimum, and the editor's bottom splitter keeps the
## height it grew to — so the scroll carries a small floor (90 px) and every growing row goes inside it; this plugin
## has twice shipped a tab that grew past the panel. The status clamps to two lines and mirrors its full text on its
## tooltip, so a long save report can never push the form off a short panel.
##
## HOST SEAMS (core/host.gd -> cyber_panel.gd): `select_path(path)` lets the panel hand a quest file to this tab
## (Browse / Refs / New double-click) — it rescans, finds the path in the parallel `_quest_paths`, and opens it through
## the same dirty guard a picker click takes; Check Reach asks the host for the "Reach" tab and re-runs its report.
## The editor's filesystem_changed only raises `_fs_dirty`; the rescan waits for the NEXT reveal of the tab (never
## under the designer's hands) and keeps the open quest BY PATH, never by row index. Off-tree (GUT and the headless
## probe construct this bare) every editor call stays in a button handler, the first-reveal latch, or behind
## Engine.is_editor_hint(), so _init never touches EditorInterface.
##
## DIRTY STATE: every write-through handler and every add/remove/move op calls `_mark_dirty()`; a successful Save and
## every load clear it. It renders as a "*" on the Save button and "(unsaved changes)" on the status. Each chokepoint
## that would swap the open quest (picker change, Refresh when the open file left the folder, select_path) runs through
## `_guard_dirty`, which pops "Save changes to <file> first?" (Save / Discard / Cancel). Discard reloads the SAME
## cached instance from disk with CACHE_MODE_REPLACE — the text loader reuses the cached main resource and its
## sub-resources and re-assigns every field the file carries — after `_reset_to_defaults` has put every script field
## back to its default, because a .tres OMITS default-valued fields (see recover_the_package.tres: no description, no
## required_count) and the loader therefore never touches an edit that filled one in.
##
## THREE authored fields are deliberately left to the raw inspector, and not one of them is an oversight:
##   * `Quest.reward_reputation` — a Dictionary of faction id -> delta, which needs a key/value editor this thin
##     panel doesn't offer.
##   * `Quest.id` — the quest's PRIMARY KEY, shown read-only on the Id row. A save keys its quests_active /
##     quests_completed / quests_failed sections by String(quest.id) (QuestTracker.save_into), and dialogue's start /
##     complete / advance quest ids plus another quest's `prereq_quest_id` all match it BY VALUE — so re-keying it in a
##     passing "tidy-up" edit silently orphans every one of them. QuestOps.normalize leaves it alone for exactly that
##     reason, and tests/test_devtools_quest_editor.gd pins the omission as intended rather than missing.
##   * `QuestObjective.id` — the same argument one level down: QuestTracker.start_quest seeds the progress
##     Dictionary as `progress[String(obj.id)]`, so re-keying a LIVE objective strands the player's progress under a
##     key nothing looks up again. New rows get a unique `obj_N` from QuestOps.add_objective instead. (Worth knowing
##     when a quest reads perfectly here and does nothing in game: an objective authored ELSEWHERE with a BLANK id
##     gets no progress entry at all, so it can never advance — and this tab neither shows nor repairs that.)
## Every OTHER field Quest and QuestObjective export is reachable in this tab.
##
## ROUND-TRIP RULE (the reason this file is shaped the way it is): every widget must touch THREE sites, or adding it
## DESTROYS authored data. `_show_quest` / `_load_obj_editor` / `_load_reward_row` PUSH the model into the widget
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
## routed through PlayerText. They are read by a designer who does not read code: file NAMES in prose, paths on
## tooltips, error_string() for a failed save, capitals only for the verdict tokens.

const QuestOps := preload("res://addons/cybersunday_tools/dock_quest/quest_edit_ops.gd")
const ContentSaveGuard := preload("res://addons/cybersunday_tools/core/content_save_guard.gd")
## The shared picker model: "(none)"-at-0 rows, the transient row for a value the scan can't represent, the
## index -> intent decision that REFUSES to mutate when a pick can't be represented, and the OptionButton WIDTH
## GUARDS — which this tab needs badly, because its form sits in a ScrollContainer with horizontal scrolling
## DISABLED (see `_init`), so any dropdown that sizes itself to its longest item widens the whole bottom panel.
const PickerRows := preload("res://addons/cybersunday_tools/core/picker_rows.gd")
## The ONE shared items-folder scan (the Items placer, the Audit and the File -> Run validator read it too), so a
## folder rule lands in one place. `ItemDb` is a non-@tool autoload and therefore empty inside the editor.
const ItemScan := preload("res://addons/cybersunday_tools/core/item_scan.gd")
## The Loot tab's item LABEL, borrowed rather than re-copied: a pure static (no editor API, no state), so an Item
## reads identically in both tabs. Deliberately NOT reaching for anything else in that file — a static-function
## borrow, not a base class.
const LootEditor := preload("res://addons/cybersunday_tools/dock_loot/loot_editor.gd")
## The item-id registry behind the objective target_id STAMP picker. A plain `extends RefCounted` folder scanner with
## no class_name and no autoload access, which is why const-preloading it from a @tool script is safe — quest_objective.gd
## itself preloads it for the raw inspector's PROPERTY_HINT_ENUM_SUGGESTION on this very field, and dialogue_editor.gd
## does the same for its stamps. Do NOT extend this list to anything reaching ItemDb / GameSettings (the
## scripts/tools/validate_all.gd compile-order trap).
const ItemIds := preload("res://scripts/items/item_ids.gd")
## The panel lookup for the two handoffs (Check Reach; the panel's own select_path into this tab). Null off-tree.
const Host := preload("res://addons/cybersunday_tools/core/host.gd")
## The Refs tab's back-reference walk, run ONCE per root after every Save to answer "does anything start this quest?"
## — the question every other check stays green on (a perfectly-authored quest nothing starts passes the Audit).
const RefScan := preload("res://addons/cybersunday_tools/dock_refs/ref_scan.gd")

const QUESTS_DIR := "res://resources/quests/"

## Where a quest can be STARTED from: a QuestStarter / TriggerVolume in a scene, or a conversation choice's Start
## quest. Only these two roots are walked after a Save — the whole project would also match this tab's own .bak and
## another quest's next_quest chain, neither of which is a start site.
const START_SITE_ROOTS: Array[String] = ["res://scenes", "res://resources/dialogue"]

## The QuestObjective.Type enum, in ENUM ORDER, three ways. The type dropdown's item INDEX is the enum int (KILL=0 ..
## FLAG=5), so selecting item i sets type = i directly. TYPE_TITLES is what the designer reads (the dropdown rows and
## the objective list); TYPE_LABELS is the Inspector's spelling, kept on each row's tooltip so the two surfaces can be
## matched up; TYPE_TARGET_HELP says what the target id means for that type. Keep all three in sync with
## quest_objective.gd's `enum Type { KILL, TALK, PICKUP, ENTER_AREA, USE_ITEM, FLAG }` (a test pins the sizes).
const TYPE_TITLES: Array[String] = ["Kill", "Talk to", "Pick up", "Enter area", "Use item", "Story flag"]
const TYPE_LABELS: Array[String] = ["KILL", "TALK", "PICKUP", "ENTER_AREA", "USE_ITEM", "FLAG"]
const TYPE_TARGET_HELP: Array[String] = [
	"Target id is the id of the NPC that must die (its display name also matches, for older quests).",
	"Target id is the id of the NPC the player must talk to (its display name also matches, for older quests).",
	"Target id is the id of the item the player must pick up.",
	"Target id is the area or group name the player must walk into.",
	"Target id is the id of the item the player must use.",
	"Target id is the name of the story flag that must be set.",
]

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
const MARKER_TOOLTIP := "Shows a compass chevron and a minimap dot at Marker pos while this objective is active. Only levels started from the level template carry the marker node, so on an older level it draws nothing."

# --- guard + status sentences, shared by a button's disabled tooltip AND the post-click status ---------------------
# (a double-click or a keyboard press can reach a handler the greyed button was guarding, so the click must never
# be silent). Sharing the literal keeps the two in step.
const MSG_NO_QUEST := "Pick a quest first."
const MSG_NO_OBJ := "Pick an objective in the list first."
const MSG_NO_REWARD := "Pick a reward row in the list first."
const MSG_NOTHING_TO_SAVE := "Nothing is open to save"
const MSG_NO_HOST := "Check Reach needs the CYBER SUNDAY panel."
const MSG_NO_QUESTS := "No quests found -- create one in the New tab first."
const MSG_IDLE := "Pick a quest, then edit -- Save Quest writes it to disk."
## Shown on the Id row when the quest's id is blank: QuestTracker.start_quest returns SILENTLY on a blank id, so a
## quest that reads perfectly here would start nothing. The Inspector is the only place the id is set (see the header).
const ID_BLANK_TEXT := "(blank -- set an id in the Inspector or nothing can start this quest)"

const PICKER_TIP := "The open quest. Rows read id (file name); the file path is on each row's tooltip."
const REFRESH_TIP := "Refresh the quest list from disk (keeps the open quest). Read-only."
const CHECK_REACH_TIP := "Opens the Reach tab and re-runs its report, so you can see whether a player can actually start this quest. Read-only."
const ID_TIP := "The quest's id -- saves, conversations and prerequisites match it by this exact value, so it is changed in the Inspector only, never here."

## Status colour for a finding the designer should act on (a failed load or save, a quest nothing starts). Every
## plain write restores the label's default colour.
const WARN_COLOR := Color(1.0, 0.85, 0.4)

var _quest: Quest = null
var _quest_path: String = ""

var _picker: OptionButton = null
var _save_btn: Button = null
var _check_reach_btn: Button = null
var _id_label: Label = null
var _title_edit: LineEdit = null
var _desc_edit: TextEdit = null
var _money_spin: SpinBox = null
var _xp_spin: SpinBox = null
var _auto_complete_chk: CheckBox = null
var _prereq_edit: LineEdit = null
var _next_quest_pick: OptionButton = null
var _expire_edit: LineEdit = null

var _reward_list: ItemList = null
var _reward_add_btn: Button = null
## Remove / Up / Down for the reward list — greyed together with "Pick a reward row in the list first."
var _reward_row_btns: Array[Button] = []
var _reward_item_pick: OptionButton = null
var _reward_count: SpinBox = null

var _obj_list: ItemList = null
var _obj_add_btn: Button = null
## Remove / Up / Down for the objective list — greyed together with "Pick an objective in the list first."
var _obj_row_btns: Array[Button] = []
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
## The last status sentence and its colour, kept apart from the rendered text so "(unsaved changes)" can be appended
## or dropped without re-deriving the message (see _render_status).
var _status_msg: String = ""
var _status_warn := false

## Scrollable form body — every field / objective / reward row lives here so the ~30-row editor scrolls inside the
## short bottom panel instead of clipping its lower rows off the bottom edge unreachably. The head bar and the status
## stay above it, always visible. Every NEW row goes INSIDE this body (see the HEIGHT CONTRACT in the header).
var _body: VBoxContainer = null

## Parallel arrays behind the quest picker: row i of `_picker` shows `_quest_labels[i]` ("<id>  (<file>)") and opens
## `_quest_paths[i]`. Refilled together on every rescan; a selection survives a rescan BY PATH (see _rescan_quests).
var _quest_paths: PackedStringArray = PackedStringArray()
var _quest_labels: PackedStringArray = PackedStringArray()

## Parallel to the _next_quest_pick items: the res:// path each entry maps to. Index 0 is the "(none)" entry ("" =
## clear next_quest). Entries 1..N mirror _quest_paths (refilled with it on every rescan). A loaded quest whose
## next_quest lives OUTSIDE resources/quests/ (or is unsaved) gets a transient entry appended so it round-trips
## instead of silently reading as (none) — same dangling-preservation idea as dialogue_editor._select_target.
var _next_quest_paths: PackedStringArray = PackedStringArray()

# --- cached resources/items/ scan (filled on first reveal + on Refresh, never at construction) -------------------
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

## Unsaved edits on the open quest. Set by every write-through handler and list op (`_mark_dirty`), cleared by a
## successful Save and by every load. Read by the Save button ("Save Quest*"), the status ("(unsaved changes)") and
## `_guard_dirty` before anything swaps the open quest.
var _dirty: bool = false
## The "Save changes to <file> first?" dialog, built on first need (in-tree only) and reused. `_pending` is what to
## run once the designer answers Save or Discard; `_pending_prev` is the picker row to restore on Cancel (or a failed
## save); `_confirm_answered` makes the three answers exclusive — hiding the dialog after Discard may or may not fire
## `canceled` depending on the engine version, so the first answer wins and the rest are ignored.
var _confirm: ConfirmationDialog = null
var _pending: Callable = Callable()
var _pending_prev: int = -1
var _confirm_answered := false

## Raised by the editor's filesystem_changed (connected in _init, editor only). A rescan while the tab is showing
## would swap the rows under the designer's pick, so it waits for the next reveal; Refresh is the explicit fallback.
var _fs_dirty := false

## PL6: lazy first-reveal latch — the resources/quests + resources/items scans run on first reveal, not at panel
## construction.
var _revealed := false


func _init() -> void:
	name = "Quest Edit"
	add_theme_constant_override("separation", 4)
	# A floor, NOT a ceiling: custom_minimum_size can only RAISE a container's minimum, never let it shrink below
	# what its children already demand (head bar + status + the scroll's own 90 px floor already exceed this). It is
	# here so the tab still has a sane height in the seconds before its children report theirs.
	custom_minimum_size = Vector2(0, 110)

	# --- head bar: OUTSIDE the scroll, so the open quest and Save never scroll out from under the designer ---------
	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 4)
	add_child(bar)
	_picker = OptionButton.new()
	_picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# Width guards (the PickerRows.apply idiom, applied by hand because this picker has no "(none)" row): without
	# them the bar's minimum width grows to the longest "<id>  (<file>)" row and widens the whole bottom panel.
	_picker.fit_to_longest_item = false
	_picker.clip_text = true
	_picker.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_picker.custom_minimum_size = Vector2(PickerRows.PICKER_MIN_WIDTH, 0)
	_picker.tooltip_text = PICKER_TIP
	_picker.item_selected.connect(_on_pick)
	bar.add_child(_picker)
	bar.add_child(_btn("Refresh", _on_refresh, REFRESH_TIP))
	_save_btn = _btn("Save Quest", _on_save, MSG_NOTHING_TO_SAVE)
	bar.add_child(_save_btn)
	_check_reach_btn = _btn("Check Reach", _on_check_reach, CHECK_REACH_TIP)
	bar.add_child(_check_reach_btn)

	# --- status: ONE label, directly under the bar, clamped to two lines with the full text on its tooltip ---------
	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.max_lines_visible = 2
	_status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_status.modulate = Color(1, 1, 1, 0.75)
	_status.mouse_filter = Control.MOUSE_FILTER_PASS  # a Label ignores the mouse by default, which also hides its tooltip
	add_child(_status)

	# --- body: the whole form in a ScrollContainer, so it can NEVER overflow the short bottom panel ---------------
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

	# --- id (read-only) + headline fields ----------------------------------------------------------------------
	# Each headline widget writes through to the live Quest on change (mirroring the objective widgets below), so
	# switching quests in the picker can't silently DISCARD an unsaved headline edit — the dirty guard asks first.
	# Save then just persists the already-applied in-memory state.
	_id_label = Label.new()
	_id_label.tooltip_text = ID_TIP
	_id_label.mouse_filter = Control.MOUSE_FILTER_PASS
	_id_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_body.add_child(_pair("Id", _id_label))

	_title_edit = _labeled_line("Title")
	_title_edit.tooltip_text = "The quest's name as the journal shows it."
	_title_edit.text_changed.connect(_on_title_changed)
	_body.add_child(_field_label("Description"))
	_desc_edit = TextEdit.new()
	_desc_edit.custom_minimum_size = Vector2(0, 40)
	_desc_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_desc_edit.tooltip_text = "The journal's summary of the quest."
	_desc_edit.text_changed.connect(_on_desc_changed)
	_body.add_child(_desc_edit)

	# `allow_greater` is DATA SAFETY, not permissiveness, and the reason is the same one _marker_spin spells out for
	# its step: a Range CLAMPS whatever it is handed to [min, max], and _on_save re-reads BOTH of these spins onto the
	# Quest unconditionally. Without it, a reward authored past the max in the raw inspector would be pushed in
	# clamped, then written back at the next Save the designer pressed for some unrelated edit — a silent rewrite of a
	# field nobody touched. The max stays as the arrow/typing hint; the floor of 0 is deliberate (a negative payout is
	# an authoring mistake, not an authored value, so clamping it up is the repair rather than the loss).
	#
	# `step` stays 1.0: both fields are whole-number payouts by tab convention (every shipped quest authors whole
	# zorkmids / whole XP), and a Range snaps to its step. RESIDUAL, and it is real: a FRACTIONAL value authored
	# elsewhere — 150.5 — would be snapped on the push and persisted rounded by the next Save. Do not lower the step
	# to hide that without also giving the arrows a whole-number stride, or the spinner becomes unusable for money.
	_money_spin = _labeled_spin("Reward money", 0.0, 1000000.0, 1.0)
	_money_spin.allow_greater = true
	_money_spin.tooltip_text = "Zorkmids added to the player's wallet when the quest completes."
	_money_spin.value_changed.connect(_on_money_changed)
	_xp_spin = _labeled_spin("Reward XP", 0.0, 1000000.0, 1.0)
	_xp_spin.allow_greater = true
	_xp_spin.tooltip_text = "XP granted when the quest completes -- 0 for none."
	_xp_spin.value_changed.connect(_on_xp_changed)

	# Quest.auto_complete DEFAULTS TRUE (quest.gd:27), which is why its absence here was a real authoring hole and not
	# a cosmetic one: with no widget, a turn-in quest (auto_complete = false, as recover_the_package.tres authors) was
	# simply not expressible in this tab. A CheckBox is a Button, so it uses toggled / disabled / set_pressed_no_signal
	# (NOT the editable / value / value_changed the SpinBoxes above use).
	_auto_complete_chk = CheckBox.new()
	_auto_complete_chk.tooltip_text = "On: the quest finishes and pays out as soon as every required objective is done. Off: it stays open until something turns it in, such as a conversation choice's Complete quest."
	_auto_complete_chk.toggled.connect(_on_auto_complete_changed)
	_body.add_child(_pair("Auto-complete", _auto_complete_chk))

	_prereq_edit = _labeled_line("Prereq quest id")
	_prereq_edit.tooltip_text = "A quest id that must be completed before this one can start -- otherwise the start is silently refused. Blank means no prerequisite."
	_prereq_edit.text_changed.connect(_on_prereq_changed)
	# Forward chaining: next_quest is a full Quest resource (not a StringName id like prereq), so it's a picker of
	# the scanned resources/quests/ .tres, not a LineEdit. Item 0 = (none); the rest mirror _quest_paths. Writes
	# through to the live Quest on select, like every other headline widget above. Width guards as on `_picker`.
	_next_quest_pick = OptionButton.new()
	_next_quest_pick.fit_to_longest_item = false
	_next_quest_pick.clip_text = true
	_next_quest_pick.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_next_quest_pick.custom_minimum_size = Vector2(PickerRows.PICKER_MIN_WIDTH, 0)
	_next_quest_pick.tooltip_text = "A quest that starts by itself when this one completes -- chains a storyline. (none) means the chain ends here."
	_next_quest_pick.item_selected.connect(_on_next_quest_changed)
	_body.add_child(_pair("Next quest", _next_quest_pick))

	# WR-6 fail window. Ordered LAST of the flow fields to mirror quest.gd's @export_group("Flow") on disk
	# (auto_complete, prereq_quest_id, next_quest, expire_on_flag) — the tab reads in resource order, so a designer
	# comparing the two surfaces never has to hunt.
	_expire_edit = _labeled_line("Expire on flag")
	_expire_edit.tooltip_text = "While this quest is active, setting this story flag fails it -- the \"you missed the window\" trigger. Blank means it never expires."
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
	_reward_add_btn = _btn("Add", _on_reward_add, "Adds an empty reward row to the open quest. Writes nothing until Save Quest.")
	reward_btns.add_child(_reward_add_btn)
	_reward_row_btns.append(_btn("Remove", _on_reward_remove, "Removes the picked reward row. Writes nothing until Save Quest."))
	_reward_row_btns.append(_btn("Up", _on_reward_up, "Moves the picked reward row one step earlier -- earlier rows are handed over first when the bag is nearly full. Writes nothing until Save Quest."))
	_reward_row_btns.append(_btn("Down", _on_reward_down, "Moves the picked reward row one step later. Writes nothing until Save Quest."))
	for b in _reward_row_btns:
		reward_btns.add_child(b)
	_body.add_child(reward_btns)

	# ItemStack.item is a RESOURCE REFERENCE, so this is a real dropdown (there is no id string a LineEdit could
	# hold) — and it therefore goes through PickerRows rather than the hand-rolled "find() the Item in the folder
	# scan, else select(0)" shape this dock and the Loot tab both used to carry. That shape renders an ItemStack
	# pointing at an inline sub-resource, or at a .tres in another folder, as "(none)" while the field is SET — and
	# the next pick clobbers it. PickerRows surfaces both cases as their own rows and refuses to write through them.
	_reward_item_pick = OptionButton.new()
	_reward_item_pick.fit_to_longest_item = false  # PickerRows.apply re-applies these on every fill; set here too so
	_reward_item_pick.clip_text = true  # the empty dropdown can't widen the panel before the first load
	_reward_item_pick.tooltip_text = "The item this reward row hands over -- (none) clears it. A row whose item lives outside the items folder shows greyed; change that one in the Inspector."
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
	_reward_count.tooltip_text = "How many of the item to hand over. 0 skips the row, and the list marks it (skipped)."
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
	_obj_add_btn = _btn("Add", _on_add, "Adds a story-flag objective with a fresh id to the end of the list. Writes nothing until Save Quest.")
	btn_row.add_child(_obj_add_btn)
	_obj_row_btns.append(_btn("Remove", _on_remove, "Removes the picked objective. Writes nothing until Save Quest."))
	_obj_row_btns.append(_btn("Up", _on_up, "Moves the picked objective one step earlier -- the journal lists objectives in this order. Writes nothing until Save Quest."))
	_obj_row_btns.append(_btn("Down", _on_down, "Moves the picked objective one step later. Writes nothing until Save Quest."))
	for b in _obj_row_btns:
		btn_row.add_child(b)
	_body.add_child(btn_row)

	# --- selected-objective editor ----------------------------------------------------------------------------
	# Rows carry the designer title; each row's tooltip keeps the Inspector's spelling and says what the target id
	# means for that type, so a quest authored in the Inspector and one authored here can be matched up by eye.
	_obj_type = OptionButton.new()
	_obj_type.fit_to_longest_item = false
	_obj_type.clip_text = true
	_obj_type.custom_minimum_size = Vector2(PickerRows.PICKER_MIN_WIDTH, 0)
	_obj_type.tooltip_text = "What completes this objective. Each row's tooltip says what the target id means for it."
	for i in range(TYPE_TITLES.size()):
		_obj_type.add_item(TYPE_TITLES[i], i)
		_obj_type.set_item_tooltip(i, "%s -- %s in the Inspector. %s" % [TYPE_TITLES[i], TYPE_LABELS[i], TYPE_TARGET_HELP[i]])
	_obj_type.item_selected.connect(_on_obj_type_changed)
	_body.add_child(_pair("Type", _obj_type))

	# target_id stays a LineEdit with a narrow STAMP picker beside it — never a closed dropdown. Same authoring rule
	# (and the same reason) as dialogue_editor's five stamps: quest_objective.gd:46-49 chose a SUGGESTION hint over a
	# real enum precisely so a designer can author an id for content that does not exist on disk yet. The FIELD is the
	# source of truth; the stamp is a typo-avoider, and it only has something to offer for the types that HAVE an
	# on-disk registry (see _fill_target_stamp, which also keeps the field's tooltip equal to the stamp's).
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
	_obj_count.tooltip_text = "How many times the target must happen before the objective is done -- kill 5, pick up 3. Never below 1."
	_obj_count.value_changed.connect(_on_obj_count_changed)
	_body.add_child(_pair("Required count", _obj_count))

	_obj_desc = LineEdit.new()
	_obj_desc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_obj_desc.tooltip_text = "The line the journal shows for this objective."
	_obj_desc.text_changed.connect(_on_obj_desc_changed)
	_body.add_child(_pair("Objective text", _obj_desc))

	# QuestObjective.optional — a bonus objective that doesn't gate quest completion. A CheckBox is a Button, so it
	# uses toggled / disabled / set_pressed_no_signal (NOT the editable / value / value_changed the SpinBox above uses).
	_obj_optional = CheckBox.new()
	_obj_optional.tooltip_text = "A bonus objective: the quest can complete without it. The journal tags it (optional)."
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

	# Nothing is open yet: grey the form, the list buttons and Save (each says what is missing) and post the next step.
	_set_form_enabled(false)
	_load_reward_row(null)
	_load_obj_editor(null)
	_update_save_state()
	_set_status(MSG_IDLE)

	if Engine.is_editor_hint():
		# Editor only (EditorInterface does not exist headless). The connection dies with this Control — Godot
		# disconnects every signal aimed at an Object when that Object is freed — so a plugin reload leaves nothing
		# dangling on the editor's filesystem scanner.
		var fs := EditorInterface.get_resource_filesystem()
		if fs != null:
			fs.filesystem_changed.connect(_on_filesystem_changed)

	visibility_changed.connect(_on_visibility_changed)
	_on_visibility_changed()  # lazy: scan resources/items + resources/quests on first reveal, not at panel construction (mirrors content_browser)


## Lazy first-reveal: scan the item + quest folders and open the first quest ONCE, the first time the tab is shown,
## and grey Check Reach when there is no panel to hand off to (the bare-constructed case). Later reveals rescan only
## when the editor's filesystem changed while the tab was hidden — keeping the open quest by path (see _rescan_quests).
func _on_visibility_changed() -> void:
	if is_visible_in_tree() and not _revealed:
		_revealed = true
		_rescan_all()
		if _check_reach_btn != null and Host.find(self) == null:
			_check_reach_btn.disabled = true
			_check_reach_btn.tooltip_text = MSG_NO_HOST
	elif is_visible_in_tree() and _fs_dirty:
		_rescan_all()


## The editor's FileSystem scanner noticed a change (a new / saved / deleted file anywhere — including this tab's own
## Save). Only flag it: the rescan runs on the next reveal, never under the designer's hands while the tab is showing.
func _on_filesystem_changed() -> void:
	_fs_dirty = true


## Both disk scans, IN THIS ORDER, and the order is a correctness fix rather than tidiness (the same ordering trap
## the Loot tab hit): _rescan_quests() may open a quest, which selects reward row 0, which pushes that row's Item into
## _reward_item_pick. With an UNSCANNED item list the picker's rows would collapse to just "(none)", so a real reward
## would render as unset — on every plugin load, against clear_the_block.tres, which ships with one. Shared by the
## first reveal, the filesystem-dirty reveal, Refresh and select_path so none of them can drift apart.
func _rescan_all() -> void:
	_fs_dirty = false
	_rescan_items()
	_rescan_quests()


# --- widget builders (pure UI) ---------------------------------------------------------------------------------

func _field_label(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.modulate = Color(1, 1, 1, 0.7)  # dim, not tiny: a 10 px override made section headers unreadable
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

## An action button. `tip` is the button's tooltip while it can act; it is ALSO parked on the button's metadata so
## `_set_buttons_enabled` can restore it after a "what is missing" tooltip has replaced it.
func _btn(text: String, handler: Callable, tip: String = "") -> Button:
	var b := Button.new()
	b.text = text
	b.tooltip_text = tip
	b.set_meta("tip", tip)
	b.pressed.connect(handler)
	return b

## Grey (or restore) a group of action buttons together. A greyed button's tooltip names what is missing; a live one
## gets its own action tooltip back. `btns` is a plain Array (callers hand in a literal), each entry cast on the way in.
func _set_buttons_enabled(btns: Array, on: bool, missing: String) -> void:
	for entry in btns:
		var b: Button = entry as Button
		if b == null:
			continue
		b.disabled = not on
		b.tooltip_text = String(b.get_meta("tip", "")) if on else missing

## Plain-words count: "1 objective" / "3 objectives".
static func _count(n: int, one: String, many: String) -> String:
	return "%d %s" % [n, one if n == 1 else many]

## True when `t` is a QuestObjective.Type this build knows, i.e. an index TYPE_TITLES and the type dropdown both
## have a row for. Stored ints are NOT enum-safe: a .tres carries `type = 2` as a plain integer, so a file authored
## by a build with more types (or hand-edited) loads a value this one has no row for — and OptionButton.select()
## on an out-of-range index is an ENGINE ERROR, which is a red line in the designer's Output for a data problem the
## list can simply name instead (see _obj_summary).
static func _known_type(t: int) -> bool:
	return t >= 0 and t < TYPE_TITLES.size()


# --- picker / load ---------------------------------------------------------------------------------------------

## Scan resources/quests/ for quest files and refill the picker (and the next-quest rows that mirror it), KEEPING the
## open quest: its row is re-selected BY PATH and it is never reloaded, so unsaved edits survive a Refresh. Only when
## the open file is gone from the folder (or nothing was open yet) does the first quest open instead — and even then
## an open quest with unsaved edits is kept, orphaned, with a warning, rather than swapped out from under the
## designer. Safe when the folder doesn't exist yet (a fresh project) — the picker just shows an empty hint.
func _rescan_quests() -> void:
	var keep := _quest_path
	_quest_paths = _scan_quest_paths()
	_quest_labels = _labels_for(_quest_paths)
	_refresh_next_quest_options()  # the next_quest picker lists the same scanned files; refill it before (re)opening a quest
	_picker.clear()
	if _quest_paths.is_empty():
		_picker.add_item("(no quests)")
		_picker.disabled = true
		_picker.tooltip_text = MSG_NO_QUESTS  # a greyed control says what is missing, like every disabled button here
		if _dirty and _quest != null:
			# The open quest is KEPT (its edits are the only copy), so its next-quest row must be re-pointed too:
			# _refresh_next_quest_options() above just rebuilt that dropdown down to a bare "(none)", and leaving it
			# reading "(none)" while the quest really HAS a next_quest is the mis-read that invites a clobber —
			# OptionButton emits item_selected even when the picked row is already the selected one, so one click on
			# the row that looks like a no-op would clear the reference. _select_next_quest re-adds it as a transient.
			_select_next_quest()
			_set_status("%s is no longer in the quests folder -- Save Quest writes it back." % keep.get_file(), true)
			return
		_clear_loaded()
		_set_status(MSG_NO_QUESTS, true)
		return
	_picker.disabled = false
	_picker.tooltip_text = PICKER_TIP
	for i in range(_quest_paths.size()):
		_picker.add_item(_quest_labels[i])
		_picker.set_item_tooltip(i, _quest_paths[i])  # the file path lives on the row's tooltip, never in the row text
	var idx := _quest_paths.find(keep) if not keep.is_empty() else -1
	if idx >= 0:
		_picker.select(idx)  # select() doesn't emit item_selected, so the open quest is NOT reloaded
		_select_next_quest()  # the next-quest rows were just rebuilt; re-point them at the open quest's next_quest
		return
	if _dirty and _quest != null:
		_picker.select(-1)
		_select_next_quest()  # same re-point as the empty-folder branch above: the open quest is kept, so its row must be too
		_set_status("%s is no longer in the quests folder -- Save Quest writes it back, or pick another quest." % keep.get_file(), true)
		return
	_picker.select(0)
	_load_quest(_quest_paths[0])

## The sorted list of quest file paths under QUESTS_DIR (res:// path, files only). Empty if the dir is absent.
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

## The picker label for each scanned path: "<id>  (<file>)". Rows are labelled by Quest.id, never the filename alone —
## recover_the_package.tres carries id "recover_package", and every other surface (conversations, prerequisites,
## saves) keys on the id. A blank id or a file that won't load is said so in the id slot rather than hidden.
func _labels_for(paths: PackedStringArray) -> PackedStringArray:
	var out := PackedStringArray()
	for p in paths:
		var res: Resource = load(p)
		var head := "(won't load)"
		if is_instance_valid(res) and res is Quest:
			var id := String((res as Quest).id)
			head = id if not id.is_empty() else "(no id)"
		out.append("%s  (%s)" % [head, p.get_file()])
	return out


## Re-read resources/items/ into the two sources this tab offers: the parallel path/label arrays behind the reward-row
## item dropdown, and the id list behind the objective target_id stamp. Nothing here touches the loaded quest.
##
## Two passes over one small folder on purpose: `ItemScan.scan()` yields Item RESOURCES (the reward picker assigns a
## reference and needs each one's resource_path + display label), while `ItemIds.ids()` yields the id STRINGS that
## quest_objective.gd's own inspector hint is built from — using the same registry keeps this tab's stamp and the raw
## inspector's suggestion list identical by construction rather than by coincidence.
func _rescan_items() -> void:
	_item_paths = PackedStringArray()
	_item_labels = PackedStringArray()
	for it: Item in ItemScan.scan():
		if it == null or it.resource_path.is_empty():
			continue  # nothing a path row could carry; the picker's transient row covers a pathless item on a LOADED stack
		_item_paths.append(it.resource_path)
		_item_labels.append(LootEditor._item_label(it))
	_item_ids = ItemIds.ids()
	_fill_target_stamp(_current_obj())  # a re-scan must reach a stamp that is already on screen


## A picker click. Re-picking the open quest is a no-op (never reload under edits); anything else goes through the
## dirty guard, which restores the previous row on Cancel.
func _on_pick(idx: int) -> void:
	if idx < 0 or idx >= _quest_paths.size():
		return
	if _quest_paths[idx] == _quest_path:
		return
	_open_index(idx)


## Open the quest at picker row `idx` through the dirty guard. true when it opened now or the designer is being asked;
## false when the guard refused (off-tree with unsaved edits — there is nobody to ask).
func _open_index(idx: int) -> bool:
	var path := _quest_paths[idx]
	var prev := _quest_paths.find(_quest_path) if not _quest_path.is_empty() else -1
	var then := func() -> void:
		_picker.select(idx)
		_load_quest(path)
	return _guard_dirty(then, prev)


## Host seam (cyber_panel.open_in_editor): find + open the quest saved at `path` in this tab's own picker. Marks the
## tab revealed and rescans when it has never scanned, the folder changed since, or the path is not in the list yet
## (a file the New tab just wrote); then finds the row in the parallel `_quest_paths` and opens it through the dirty
## guard. true when the file is in the quests folder and the tab has it in hand (opened, or the designer is being
## asked about unsaved edits); false for a blank path, a file outside the folder, or a refused swap.
func select_path(path: String) -> bool:
	if path.is_empty():
		return false
	if not _revealed or _fs_dirty or not _quest_paths.has(path):
		_revealed = true
		_rescan_all()
	var idx := _quest_paths.find(path)
	if idx < 0:
		_set_status("Couldn't open %s: it isn't in the quests folder." % path.get_file(), true)
		return false
	if path == _quest_path:
		_picker.select(idx)
		return true
	return _open_index(idx)


## The explicit Refresh command: re-read the folder, keeping the open quest. The ONE case a refresh would have to swap
## the open quest — its file left the folder while it carries unsaved edits — asks first, like a picker change.
func _on_refresh() -> void:
	var fresh := _scan_quest_paths()
	if _dirty and _quest != null and not _quest_path.is_empty() and not fresh.has(_quest_path):
		_guard_dirty(_rescan_all, _quest_paths.find(_quest_path))
		return
	_rescan_all()
	if not _quest_paths.is_empty() and _quest != null:
		_set_status("Refreshed the quest list -- %s; the open quest is unchanged." % _count(_quest_paths.size(), "quest", "quests"))


## Read the quest at `path` off disk and show it. `replace` re-reads INTO the cached instance (CACHE_MODE_REPLACE) —
## the Discard path, after `_reset_to_defaults` — so every other holder of that resource (the Inspector, a conversation
## editor's start-quest reference) sees the reverted data too. A failed load (mid-reimport, a broken script, a file
## that vanished) clears the form, greys it and Save, and says so — never an editor error.
func _load_quest(path: String, replace: bool = false) -> void:
	var mode := ResourceLoader.CACHE_MODE_REPLACE if replace else ResourceLoader.CACHE_MODE_REUSE
	var res: Resource = ResourceLoader.load(path, "", mode)
	if not is_instance_valid(res) or not (res is Quest):
		_clear_loaded()
		# Refused grammar: "Couldn't <verb> <Name>: <plain reason>." — and the reason stays in plain words, because the
		# usual cause is the editor still re-importing the file a moment after it changed on disk.
		_set_status("Couldn't open %s: the editor may still be reading it -- press Refresh." % path.get_file(), true)
		return
	_show_quest(res as Quest, path)


## Model -> widgets for the whole quest. PUSH SITE 1 of the three-site rule: every widget this tab writes back must be
## pushed here, or the first keystroke/tick in any OTHER field persists this one's construction default. The spins use
## set_value_no_signal and the CheckBoxes set_pressed_no_signal so opening a quest doesn't fire the write-through
## handlers (LineEdit/TextEdit .text assignment doesn't emit, so those are inert already). Pure widget pushes — no
## disk, no editor — so a test can hand it an in-memory Quest. Clears the dirty flag LAST, after every push.
func _show_quest(q: Quest, path: String) -> void:
	_quest = q
	_quest_path = path
	var id := String(q.id)
	_id_label.text = id if not id.is_empty() else ID_BLANK_TEXT
	_title_edit.text = q.title
	_desc_edit.text = q.description
	_money_spin.set_value_no_signal(q.reward_money)
	_xp_spin.set_value_no_signal(q.reward_xp)
	_auto_complete_chk.set_pressed_no_signal(q.auto_complete)
	_prereq_edit.text = String(q.prereq_quest_id)
	_select_next_quest()
	_expire_edit.text = String(q.expire_on_flag)
	_set_form_enabled(true)
	_refresh_reward_list()
	_select_reward(0 if q.rewards.size() > 0 else -1)
	_refresh_obj_list()
	_select_obj(0 if q.objectives.size() > 0 else -1)
	_dirty = false
	_update_save_state()
	_set_status("Opened %s -- %s, %s." % [path.get_file(), _count(q.objectives.size(), "objective", "objectives"), _count(q.rewards.size(), "reward row", "reward rows")])


## RESET SITE of the three-site rule: back to each field's RESOURCE default, not to the widget's, with the form, the
## list buttons and Save greyed because nothing is open. Also drops the dirty flag — nothing open, nothing unsaved.
##
## `auto_complete` resets to TRUE because that is quest.gd:27's default — a CheckBox's own default is false, and
## resetting to it would make a failed load (or an empty folder) silently display "this quest needs a manual turn-in"
## for every quest that follows. The reward row widgets are reset through _load_reward_row(null) for the sharper
## version of the same bug: leaving the previous quest's rows on screen would point the item dropdown and the count
## spin at a FOREIGN ItemStack, so the next pick would edit a resource the designer is no longer looking at.
func _clear_loaded() -> void:
	_quest = null
	_quest_path = ""
	_dirty = false
	if _id_label != null:
		_id_label.text = ""
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
	_set_form_enabled(false)
	_update_save_state()
	# Re-render (not re-write) the status: `_dirty` just went false, and the "(unsaved changes)" suffix is composed at
	# RENDER time. Without this, a caller that clears without following up with its own _set_status — _discard_changes
	# on a quest with no path — would leave the last message still advertising unsaved edits that no longer exist.
	_render_status()


## Grey or wake the headline widgets and the two Add buttons together. With nothing open, typing into a live-looking
## form would go nowhere (every handler guards on `_quest == null`), which reads as a broken tab — so the form says so.
func _set_form_enabled(on: bool) -> void:
	_title_edit.editable = on
	_desc_edit.editable = on
	_money_spin.editable = on
	_xp_spin.editable = on
	_auto_complete_chk.disabled = not on  # CheckBox / OptionButton are Buttons -> disabled, not editable
	_prereq_edit.editable = on
	_next_quest_pick.disabled = not on
	_expire_edit.editable = on
	_set_buttons_enabled([_reward_add_btn], on, MSG_NO_QUEST)
	_set_buttons_enabled([_obj_add_btn], on, MSG_NO_QUEST)


# --- dirty state + the unsaved-changes guard ------------------------------------------------------------------

## Called by every write-through handler and list op. Flips the flag once and re-renders the two places it shows
## (the Save button's "*", the status's "(unsaved changes)"); a no-op with nothing open.
func _mark_dirty() -> void:
	if _quest == null:
		return
	if _dirty:
		return
	_dirty = true
	_update_save_state()
	_render_status()


## Save Quest's enabled state, text and tooltip, derived from what is open and whether it has unsaved edits.
func _update_save_state() -> void:
	if _save_btn == null:
		return
	var open := _quest != null and not _quest_path.is_empty()
	_save_btn.disabled = not open
	_save_btn.text = "Save Quest*" if open and _dirty else "Save Quest"
	if open:
		var file := _quest_path.get_file()
		_save_btn.tooltip_text = "Tidies stray spaces in ids, then writes the open quest to its file. Writes %s -- the previous bytes are kept as %s." % [file, ContentSaveGuard.backup_path(_quest_path).get_file()]
	else:
		_save_btn.tooltip_text = MSG_NOTHING_TO_SAVE


## Run `then` now when nothing is unsaved; otherwise ask "Save changes to <file> first?" and run it after Save or
## Discard, restoring picker row `prev_idx` on Cancel. Off-tree there is no editor to ask in, so the swap is REFUSED
## (the only answer that can't lose the edits) and the status says why. true = ran now, or the designer is being
## asked; false = refused.
func _guard_dirty(then: Callable, prev_idx: int) -> bool:
	if not _dirty or _quest == null:
		then.call()
		return true
	if not is_inside_tree():
		_restore_pick(prev_idx)
		_set_status("Couldn't switch: %s has unsaved changes -- Save Quest first." % _quest_path.get_file(), true)
		return false
	_ask_unsaved(then, prev_idx)
	return true


## Build the dialog on first need (in-tree only — a popup needs a viewport) and show it for the open quest.
func _ask_unsaved(then: Callable, prev_idx: int) -> void:
	if _confirm == null:
		_confirm = ConfirmationDialog.new()
		_confirm.title = "Unsaved changes"
		_confirm.ok_button_text = "Save"
		_confirm.cancel_button_text = "Cancel"
		_confirm.add_button("Discard", true, "discard")
		_confirm.confirmed.connect(_on_confirm_save)
		_confirm.custom_action.connect(_on_confirm_custom)
		_confirm.canceled.connect(_on_confirm_cancel)
		add_child(_confirm)
	_confirm.dialog_text = "Save changes to %s first?" % _quest_path.get_file()
	_pending = then
	_pending_prev = prev_idx
	_confirm_answered = false
	_confirm.popup_centered()


## Save: write the open quest, then carry on — unless the save failed (still dirty; its status says why), in which case
## the open quest stays put.
func _on_confirm_save() -> void:
	if _confirm_answered:
		return
	_confirm_answered = true
	_on_save()
	if _dirty:
		_restore_pick(_pending_prev)
		_pending = Callable()
		return
	_run_pending()


## Discard: put the cached instance back to what the file says, then carry on. A custom-action button does not close
## the dialog by itself, hence the hide().
func _on_confirm_custom(action: StringName) -> void:
	if _confirm_answered or action != &"discard":
		return
	_confirm_answered = true
	_confirm.hide()
	_discard_changes()
	_run_pending()


## Cancel (the button, the X, Escape): keep the open quest and its edits, and put the picker back on its row.
func _on_confirm_cancel() -> void:
	if _confirm_answered:
		return
	_confirm_answered = true
	_restore_pick(_pending_prev)
	_pending = Callable()
	_set_status("Kept %s open -- Save Quest when you're ready." % _quest_path.get_file())


func _run_pending() -> void:
	var p := _pending
	_pending = Callable()
	if p.is_valid():
		p.call()


## Put the picker back on `idx` (-1 = no row) without emitting.
func _restore_pick(idx: int) -> void:
	if _picker == null:
		return
	_picker.select(idx if idx < _picker.item_count else -1)


## Throw away the open quest's unsaved edits by re-reading its file INTO the cached instance. Two steps, and the
## order is the point: (1) every script field on the quest and on the rows it currently holds goes back to its script
## default, because a .tres OMITS default-valued fields and the loader therefore never touches an edit that filled one
## in (type a flag into a blank Expire on flag, Discard: without this step it would survive); (2) the CACHE_MODE_REPLACE
## load re-assigns every field the file carries into the same instances, so the Inspector and any other tab holding
## this quest see the reverted data too. Rows first, then the quest — resetting the quest empties its lists.
func _discard_changes() -> void:
	var path := _quest_path
	if _quest != null:
		for o: QuestObjective in _quest.objectives:
			if o != null:
				_reset_to_defaults(o)
		for s: ItemStack in _quest.rewards:
			if s != null:
				_reset_to_defaults(s)
		_reset_to_defaults(_quest)
	_dirty = false
	if path.is_empty():
		_clear_loaded()
		return
	_load_quest(path, true)


## Put every stored script field of `obj` back to the value a fresh instance of its script would carry. Returns how
## many fields changed. Pure Object API (no disk, no editor), so a test can run it on a throwaway Quest. Only
## SCRIPT-declared, STORED fields are touched — never `resource_path`, `resource_name` or the script itself.
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


# --- status ----------------------------------------------------------------------------------------------------

## Every status write. The label clamps to two lines, so the tooltip mirrors the whole message; `warn` tints the text
## (a failed load or save, a quest nothing starts), and a plain write restores the default colour.
func _set_status(msg: String, warn: bool = false) -> void:
	_status_msg = msg
	_status_warn = warn
	_render_status()


## Compose the shown text from the last message plus the dirty marker, and mirror it onto the tooltip.
func _render_status() -> void:
	if _status == null:
		return
	var text := _status_msg + (" (unsaved changes)" if _dirty else "")
	_status.text = text
	_status.tooltip_text = text
	if _status_warn:
		_status.add_theme_color_override("font_color", WARN_COLOR)
	else:
		_status.remove_theme_color_override("font_color")


# --- headline edit handlers (write back to the live Quest, like the objective handlers) ------------------------
# Guard on _quest == null so a clear/load that touches a widget is a no-op when nothing is loaded, and only mark
# dirty on a REAL change so a push that happens to echo the widget back leaves the flag alone.

func _on_title_changed(text: String) -> void:
	if _quest == null or _quest.title == text:
		return
	_quest.title = text
	_mark_dirty()

func _on_desc_changed() -> void:  # TextEdit.text_changed has no argument
	if _quest == null or _quest.description == _desc_edit.text:
		return
	_quest.description = _desc_edit.text
	_mark_dirty()

func _on_money_changed(value: float) -> void:
	if _quest == null:
		return
	_quest.reward_money = value
	_mark_dirty()

func _on_xp_changed(value: float) -> void:
	if _quest == null:
		return
	_quest.reward_xp = value
	_mark_dirty()

func _on_auto_complete_changed(pressed: bool) -> void:  # CheckBox.toggled -> bool
	if _quest == null:
		return
	_quest.auto_complete = pressed
	_mark_dirty()

func _on_prereq_changed(text: String) -> void:
	if _quest == null:
		return
	_quest.prereq_quest_id = StringName(text.strip_edges())
	_mark_dirty()

## strip_edges for the same reason as _on_prereq_changed: QuestTracker._expire_quests_on_flag compares
## `q.expire_on_flag == flag` by EXACT StringName equality, so one trailing space makes the fail window dead content
## that looks perfectly authored. QuestOps.normalize repairs values authored outside this dock; this stops us minting
## a drifted one in the first place.
func _on_expire_changed(text: String) -> void:
	if _quest == null:
		return
	_quest.expire_on_flag = StringName(text.strip_edges())
	_mark_dirty()

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
		if idx == 0 and _quest.next_quest != null:
			_quest.next_quest = null
			_mark_dirty()
		return
	var res: Resource = load(path)
	if not is_instance_valid(res) or not (res is Quest):
		_set_status("Couldn't set the next quest: %s isn't a quest." % path.get_file(), true)
		return
	if _quest.next_quest == res:
		return
	_quest.next_quest = res
	_mark_dirty()

## Rebuild the next_quest picker items to "(none)" + every scanned quest (same "<id>  (<file>)" labels as the main
## picker), mirroring _quest_paths into _next_quest_paths (offset by the (none) entry at index 0). Called on every
## rescan, before a quest is opened.
func _refresh_next_quest_options() -> void:
	if _next_quest_pick == null:
		return
	_next_quest_pick.clear()
	_next_quest_paths = PackedStringArray()
	_next_quest_pick.add_item(PickerRows.NONE_LABEL)
	_next_quest_paths.append("")
	for i in range(_quest_paths.size()):
		_next_quest_pick.add_item(_quest_labels[i] if i < _quest_labels.size() else _quest_paths[i].get_file())
		_next_quest_pick.set_item_tooltip(i + 1, _quest_paths[i])
		_next_quest_paths.append(_quest_paths[i])

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
## A missing row (a null hole in the array, authored elsewhere) reads "(missing)".
func _reward_summary(i: int, s: ItemStack) -> String:
	if s == null:
		return "%d. (missing)" % (i + 1)
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


## Mirror one ItemStack into the reward-row widgets (or blank + disable on null), and grey Remove/Up/Down with it.
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
	_set_buttons_enabled(_reward_row_btns, has, MSG_NO_REWARD)
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
		if s.item != null:
			s.item = null
			_mark_dirty()
		_refresh_reward_summary_for_selected()
		_set_status("Cleared the reward item -- the row hands over nothing until you pick one.")
		return
	var path := String(pick.get("value", ""))
	var res: Resource = load(path)
	if not is_instance_valid(res) or not (res is Item):
		_set_status("Couldn't use %s: it isn't an item -- the reward row is unchanged." % path.get_file(), true)
		return
	if s.item == res:
		return
	s.item = res
	_mark_dirty()
	_refresh_reward_summary_for_selected()

func _on_reward_count_changed(value: float) -> void:
	var s := _current_reward()
	if s == null:
		return
	s.count = int(value)
	_mark_dirty()
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
		_set_status(MSG_NO_QUEST)
		return
	if QuestOps.add_reward(_quest):
		_mark_dirty()
		_refresh_reward_list()
		_select_reward(_quest.rewards.size() - 1)
		_set_status("Added reward row %d -- pick an item for it." % _quest.rewards.size())

func _on_reward_remove() -> void:
	if _quest == null:
		_set_status(MSG_NO_QUEST)
		return
	var i := _selected_reward_index()
	if i < 0:
		_set_status(MSG_NO_REWARD)
		return
	if QuestOps.remove_reward(_quest, i):
		_mark_dirty()
		_refresh_reward_list()
		_select_reward(mini(i, _quest.rewards.size() - 1))
		_set_status("Removed reward row %d." % (i + 1))

func _on_reward_up() -> void:
	_move_reward(-1)

func _on_reward_down() -> void:
	_move_reward(1)

func _move_reward(dir: int) -> void:
	if _quest == null:
		_set_status(MSG_NO_QUEST)
		return
	var i := _selected_reward_index()
	if i < 0:
		_set_status(MSG_NO_REWARD)
		return
	if QuestOps.move_reward(_quest, i, dir):
		_mark_dirty()
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

## One objective's list text: "1. Kill raider x3 (optional) ◆". The type is its designer title (TYPE_TITLES); a
## missing row (a null hole in the array, authored elsewhere) reads "(missing)", and a type this build's enum no
## longer has — a hand-edited file, or one saved by an older build — reads "(unknown type)" rather than a bare "?".
func _obj_summary(i: int, o: QuestObjective) -> String:
	if o == null:
		return "%d. (missing)" % (i + 1)
	var type_name: String = TYPE_TITLES[o.type] if _known_type(o.type) else "(unknown type)"
	var tgt := String(o.target_id)
	var suffix := " (optional)" if o.optional else ""  # parity with the quest journal's "(optional)" tag
	var marker := " ◆" if o.show_marker else ""  # at-a-glance: this step places a compass chevron / minimap dot
	return "%d. %s %s x%d%s%s" % [i + 1, type_name, tgt if not tgt.is_empty() else "(no target)", o.required_count, suffix, marker]


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


## Mirror an objective's fields into the per-objective editor widgets (or blank + disable on null), and grey
## Remove/Up/Down with it.
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
	_set_buttons_enabled(_obj_row_btns, has, MSG_NO_OBJ)
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
	# -1 (deselected), never a raw out-of-range index: select() on one is an engine error in the designer's Output.
	# The list row already says "(unknown type)" for that objective, so a blank dropdown reads as "this is not one of
	# my types" — and the write-through only fires on a real pick, so nothing is stamped by leaving it blank.
	var type_row := int(o.type) if _known_type(o.type) else -1
	_obj_type.select(type_row)
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
	if o == null or idx < 0 or idx >= TYPE_TITLES.size():
		return
	o.type = idx
	_mark_dirty()
	_fill_target_stamp(o)  # Pick up / Use item have an id registry to offer; the other four types don't
	_refresh_summary_for_selected()

## strip_edges here, not just in QuestOps.normalize: QuestTracker._advance_objectives_matching compares
## `obj.target_id == target` by EXACT StringName equality, so a padded id never matches any kill/pickup/talk event and
## the objective sits at 0/N forever with no error anywhere. Matches _on_prereq_changed / _on_expire_changed.
func _on_obj_target_changed(text: String) -> void:
	var o := _current_obj()
	if o == null:
		return
	o.target_id = StringName(text.strip_edges())
	_mark_dirty()
	_refresh_summary_for_selected()

func _on_obj_count_changed(value: float) -> void:
	var o := _current_obj()
	if o == null:
		return
	o.required_count = int(value)
	_mark_dirty()
	_refresh_summary_for_selected()

func _on_obj_desc_changed(text: String) -> void:
	var o := _current_obj()
	if o == null:
		return
	o.description = text
	_mark_dirty()

func _on_obj_optional_changed(pressed: bool) -> void:  # CheckBox.toggled -> bool
	var o := _current_obj()
	if o == null:
		return
	o.optional = pressed
	_mark_dirty()
	_refresh_summary_for_selected()  # live-refresh the row's "(optional)" tag

func _on_obj_show_marker_changed(pressed: bool) -> void:  # CheckBox.toggled -> bool
	var o := _current_obj()
	if o == null:
		return
	o.show_marker = pressed
	_mark_dirty()
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
	_mark_dirty()

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
## type. The LineEdit stays fully typable in every case — that is the authoring rule — and it carries the SAME tooltip
## as the stamp (what the target id means for this type, and whether there is a list to pick from).
func _fill_target_stamp(o: QuestObjective) -> void:
	if _obj_target_stamp == null:
		return
	var typed_ids := PackedStringArray()
	var tip := MSG_NO_OBJ
	if o != null:
		var t := int(o.type)
		# The per-type sentence, plus a trailing space, ONLY when this build knows the type — an unknown type (a
		# hand-edited or older file, the case _obj_summary names "(unknown type)") would otherwise prefix the tooltip
		# with a stray leading space.
		var help := ""
		if _known_type(t):
			help = TYPE_TARGET_HELP[t] + " "
		if t == QuestObjective.Type.PICKUP or t == QuestObjective.Type.USE_ITEM:
			typed_ids = _item_ids
			tip = "%sPick one from the list to stamp it in, or type an id for an item you haven't made yet." % help
		else:
			tip = "%sType it by hand -- there is no list for this kind of target, and the match is exact (capitals count)." % help
	_obj_target_stamp.tooltip_text = tip
	if _obj_target != null:
		_obj_target.tooltip_text = tip
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
		_set_status(MSG_NO_QUEST)
		return
	if QuestOps.add_objective(_quest):
		_mark_dirty()
		_refresh_obj_list()
		_select_obj(_quest.objectives.size() - 1)
		_set_status("Added objective %d -- set its type and target." % _quest.objectives.size())

func _on_remove() -> void:
	if _quest == null:
		_set_status(MSG_NO_QUEST)
		return
	var i := _selected_index()
	if i < 0:
		_set_status(MSG_NO_OBJ)
		return
	if QuestOps.remove_objective(_quest, i):
		_mark_dirty()
		_refresh_obj_list()
		_select_obj(mini(i, _quest.objectives.size() - 1))
		_set_status("Removed objective %d." % (i + 1))

func _on_up() -> void:
	_move(-1)

func _on_down() -> void:
	_move(1)

func _move(dir: int) -> void:
	if _quest == null:
		_set_status(MSG_NO_QUEST)
		return
	var i := _selected_index()
	if i < 0:
		_set_status(MSG_NO_OBJ)
		return
	if QuestOps.move_objective(_quest, i, dir):
		_mark_dirty()
		_refresh_obj_list()
		_select_obj(i + dir)


# --- save ------------------------------------------------------------------------------------------------------

## Re-sync the HEADLINE widgets onto the Quest, repair the drift-prone ids, write the .tres through ContentSaveGuard,
## tell the FileSystem it changed, then report the file, its .bak, and whether anything in the project STARTS this
## quest. A save failure is REPORTED (error_string, never a bare code) and leaves the dirty flag set.
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
## reported because "silently tidied 2 fields" is information a designer needs. Everything is then re-pushed
## model->widget, because normalize may have just changed text the designer is looking at.
func _on_save() -> void:
	if _quest == null or _quest_path.is_empty():
		_set_status("%s -- %s" % [MSG_NOTHING_TO_SAVE, MSG_NO_QUEST.to_lower()])
		return
	_quest.title = _title_edit.text
	_quest.description = _desc_edit.text
	_quest.reward_money = _money_spin.value
	_quest.reward_xp = _xp_spin.value
	_quest.auto_complete = _auto_complete_chk.button_pressed
	_quest.prereq_quest_id = StringName(_prereq_edit.text.strip_edges())
	_quest.expire_on_flag = StringName(_expire_edit.text.strip_edges())
	var fixed := QuestOps.normalize(_quest)
	var file := _quest_path.get_file()
	var err := ContentSaveGuard.save_with_backup(_quest, _quest_path)  # PL5: prior bytes -> .tres.bak first, so a mis-save is recoverable
	if err != OK:
		_set_status("Couldn't save %s: %s -- the change is not on disk." % [file, error_string(err)], true)
		return
	if Engine.is_editor_hint():
		# Null-guarded like the _init connection: the FileSystem singleton is the editor's, and a hard crash here —
		# right after a save that DID land — would read to a designer as "the save broke the editor".
		var fs := EditorInterface.get_resource_filesystem()
		if fs != null:
			fs.update_file(_quest_path)
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
	_dirty = false
	_update_save_state()
	var bak := ContentSaveGuard.backup_path(_quest_path)
	var msg := "Saved %s" % file
	msg += (" -- backup %s." % bak.get_file()) if FileAccess.file_exists(bak) else "."
	if fixed > 0:
		msg += " Tidied %s (stray spaces, or a count below 1)." % _count(fixed, "field", "fields")
	var sites := _start_sites(_quest_path)
	_set_status(msg + "\n" + _start_site_line(sites), sites.is_empty())


## Every file under START_SITE_ROOTS that references the quest at `path` (by path or uid), as sorted file names with
## duplicates dropped. One RefScan walk per root; the two results are merged here.
func _start_sites(path: String) -> PackedStringArray:
	var seen := {}
	for root in START_SITE_ROOTS:
		for hit in RefScan.find_referencers(path, root):
			var h: Dictionary = hit if hit is Dictionary else {}
			var f := String(h.get("file", ""))
			if not f.is_empty():
				seen[f.get_file()] = true
	var files := PackedStringArray()
	for f in seen.keys():
		files.append(String(f))
	files.sort()
	return files


## The after-save line about start sites. Pure, so a test can pin both shapes. With no site the line names the three
## things that can start a quest and the verdict Reach will give — the case every other check stays green on.
static func _start_site_line(files: PackedStringArray) -> String:
	if files.is_empty():
		# Same three sites, in the same words, as the Reach tab's own MSG_NO_START_HINT -- one vocabulary, so a designer
		# reading both surfaces is told to wire the same three things ("start_quest" is the property NAME, and the
		# Inspector shows it as "Start Quest", so that is what this says).
		return "Nothing starts this quest yet -- a QuestStarter, a TriggerVolume's Start Quest, or a conversation choice's Start quest must point at it; Reach will report NO START SITE."
	return "Started by %s: %s" % [_count(files.size(), "site", "sites"), ", ".join(files)]


# --- handoff: Check Reach --------------------------------------------------------------------------------------

## Switch the panel to the Reach tab and re-run its report there (duck-typed `rescan`, when the tab offers one), so the
## designer sees at once whether a player can actually start the quest they are editing. Off-tree, or outside the
## CYBER SUNDAY panel, there is no host to switch — the status says so instead of erroring.
func _on_check_reach() -> void:
	var reach := Host.show_tab(self, "Reach")
	if reach == null:
		_set_status(MSG_NO_HOST, true)
		return
	if reach.has_method("rescan"):
		reach.call("rescan")
	var what := _quest_path.get_file() if not _quest_path.is_empty() else "your quest"
	_set_status("Opened Reach -- look for %s in its report." % what)
