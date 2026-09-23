extends CanvasLayer
## QuestJournal — a read-only QUEST LOG screen, opened with its own key (InputManager.action_journal, default J).
## Registered as an autoload, mirroring StatsScreen / ReputationScreen, and a member of the
## Pip-Boy tab group (Inventory / Stats / Implants / Map / Reputation / Journal). Lists ACTIVE quests (title, the journal
## entry -- the current stage's journal_text, else the quest description -- and each CURRENT objective with a checkbox
## + progress) and COMPLETED / FAILED ones. Like the other player menus it does NOT pause the world; it frees the mouse
## (restored on close). Refreshes live off QuestTracker.quest_started / objective_advanced / quest_stage_changed /
## quest_completed / quest_failed.
##
## AUTHORED SCENE: the layout lives in scenes/ui/quest_journal.tscn (this autoload IS that scene — see
## project.godot [autoload]); this script binds its chrome by %unique name in _bind_ui and applies the
## skin-driven look (MenuStyle style_* adopters + skin reads) on top, so a designer rearranges the panel
## in the editor and the skin keeps owning colours/fonts/separations. NO text is authored in the scene —
## every string is set here from PlayerText (l10n + the text-debt ratchet own strings, never a .tscn).
## The per-quest blocks stay CODE-built into the authored %QuestList (rebuilt per open / live quest change),
## and the PlayerMenus tab strip stays CODE-BUILT into the authored %TabSlot (the strip's one-Button-per-tab
## structure is a cross-screen contract owned by player_menus.gd, not this scene).
## tests/test_quest_journal_scene.gd pins the wiring.

signal opened
signal closed


const PANEL_MARGIN := 0.12  ## same border as the other inventory-style screens — shared chrome (authored on the scene's Panel anchors; tests pin the band)
const PlayerMenus := preload("res://scripts/ui/player_menus.gd")  ## tab-group helper

var _root: Control
var _list: VBoxContainer
var _is_open := false

func _ready() -> void:
	layer = 120                                  # above the HUD, just under OptionsMenu (128)
	process_mode = Node.PROCESS_MODE_ALWAYS      # keep receiving input + rendering; this tab does NOT pause — the world runs real-time beneath it (Pip-Boy tabs are vulnerable by design)
	_bind_ui()
	_root.visible = false

func is_open() -> bool:
	return _is_open

func toggle() -> void:
	if _is_open:
		close()
	else:
		open()

## Open the quest log. Refuses over the non-player modals, mid-death, AND when there is NO human player
## (start menu / character creation) — there's nothing to show then, matching Inventory/Stats' own bail.
func open() -> void:
	# Block only the NON-player modals; the sibling player menus instead SWITCH to us via close_others.
	if _is_open or DialogueManager.is_active() \
			or InputManager.any_tab_blocking_open() \
			or not PlayerMenus.player_alive(get_tree()) \
			or not PlayerMenus.has_player(get_tree()):  # no human player (start menu / char-creation) -> nothing to show, matching Inventory/Stats
		return
	PlayerMenus.enter(self)  # switch off a sibling + free the cursor (preserves cursor position across switches)
	_is_open = true
	if not QuestTracker.quest_started.is_connected(_on_quests_changed):
		QuestTracker.quest_started.connect(_on_quests_changed)
		QuestTracker.objective_advanced.connect(_on_objective_changed)
		QuestTracker.quest_completed.connect(_on_quests_changed)
		QuestTracker.quest_failed.connect(_on_quests_changed)
		QuestTracker.quest_stage_changed.connect(_on_objective_changed)  # (quest, stage): same two-arg repaint
	_rebuild()
	_root.visible = true
	opened.emit()

func close() -> void:
	if not _is_open:
		return
	_is_open = false
	_root.visible = false
	if QuestTracker.quest_started.is_connected(_on_quests_changed):
		QuestTracker.quest_started.disconnect(_on_quests_changed)
		QuestTracker.objective_advanced.disconnect(_on_objective_changed)
		QuestTracker.quest_completed.disconnect(_on_quests_changed)
		QuestTracker.quest_failed.disconnect(_on_quests_changed)
		QuestTracker.quest_stage_changed.disconnect(_on_objective_changed)
	PlayerMenus.leave()
	closed.emit()

func _on_quests_changed(_quest) -> void:
	if _is_open:
		_rebuild()

func _on_objective_changed(_quest, _objective) -> void:
	if _is_open:
		_rebuild()

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(InputManager.action_journal):
		toggle()
		get_viewport().set_input_as_handled()
	elif _is_open and event.is_action_pressed(&"ui_cancel"):
		close()
		get_viewport().set_input_as_handled()

# ---------------------------------------------------------------------------------------------------
# UI binding (the layout is AUTHORED in scenes/ui/quest_journal.tscn — this adopts it)
# ---------------------------------------------------------------------------------------------------

## Bind the authored chrome by %unique name, style it from the skin, and wire behaviour. The scene owns
## STRUCTURE (the full-rect Root/Dim, the PANEL_MARGIN 0.12 anchor band, the tab slot, the quest list's
## scroll slot with horizontal scroll authored OFF, the list's authored 14px quest-block gap); the skin
## keeps owning LOOK — every colour/font/separation below is a MenuStyle/skin read, so reskinning via
## resources/ui/menu_skin.tres restyles this screen with zero scene edits.
func _bind_ui() -> void:
	_root = %Root  # full-rect, MOUSE_FILTER_STOP authored — eats clicks so nothing falls through to gameplay behind
	MenuStyle.apply(_root)  # shared menu Theme (panel/buttons/tooltips/fonts) — reskin via resources/ui/menu_skin.tres
	MenuStyle.style_dim(%Dim)

	(%VBox as VBoxContainer).add_theme_constant_override("separation", MenuStyle.skin.content_separation)  # shared panel-screen rhythm (MenuSkin)
	# The tab strip is the only header (the Inventory convention, adopted across all the tabs so content
	# starts at one height). The strip stays CODE-BUILT by PlayerMenus into the authored %TabSlot: its
	# one-Button-per-tab EXPAND_FILL structure is a cross-screen contract (tests/test_player_menus.gd), so the
	# scene authors only the slot.
	%TabSlot.add_child(PlayerMenus.build_tab_strip(&"journal"))  # routing KEY, not the painted label

	# The quest list scrolls vertically only (horizontal scroll authored OFF on %Scroll, so a long authored
	# quest title WRAPS — see _make_quest_block — instead of widening the panel past its anchors). The
	# per-quest blocks are DYNAMIC content, rebuilt into %QuestList on open / live quest change (_rebuild).
	_list = %QuestList

func _rebuild() -> void:
	for c in _list.get_children():
		c.queue_free()
	var active_ids := GameState.active_quest_ids()
	var completed := GameState.completed_quests()
	var failed := GameState.failed_quests()  # WR-6: blown / expired quests — shown struck-out, not silently dropped
	if active_ids.is_empty() and completed.is_empty() and failed.is_empty():
		_list.add_child(MenuStyle.make_hint(PlayerText.QUEST_JOURNAL_EMPTY))
		return
	for qid in active_ids:
		var quest: Quest = GameState.active_quest(qid)
		if quest != null:
			_list.add_child(_make_quest_block(qid, quest, false))
	for quest in completed:
		_list.add_child(_make_quest_block(quest.id, quest, true))
	for quest in failed:
		_list.add_child(_make_quest_block(quest.id, quest, true, true))

## One quest block: a title header (dimmed when completed), then -- for an ACTIVE quest -- its journal entry and a line
## per objective of the stage it is in. A closed quest shows its title and, when it has no stages, its objectives all
## ticked (a staged quest's past beats are not tracked, so it shows the title alone).
func _make_quest_block(quest_id: StringName, quest: Quest, done: bool, failed := false) -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 3)
	var head := Label.new()
	# The host ScrollContainer disables horizontal scroll, so an un-wrapped long authored title would widen
	# the whole panel past its anchors (and eventually offscreen). Wrap instead of push.
	head.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	head.text = PlayerText.quest_entry_title(quest.title, done, failed)
	head.add_theme_font_size_override(&"font_size", MenuStyle.skin.header_size)
	# Failed reads as a muted danger red (distinct from a dim completed); done dims; active uses the accent.
	var head_color: Color = MenuStyle.skin.accent_color
	if failed:
		head_color = MenuStyle.danger()  # themed danger red (reskinnable via MenuSkin), matching the other danger UI
	elif done:
		head_color = MenuStyle.skin.text_dim_color
	head.add_theme_color_override(&"font_color", head_color)
	box.add_child(head)
	if not done:
		# The authored entry for where the player IS in the quest. Authored RESOURCE prose (a stage's journal_text or
		# the quest's description), so it is set straight onto an auto-translated Label -- the engine translates it and
		# the [PH] scrub applies, exactly as it does for the authored title above. Blank = no line at all.
		var entry_text := summary_text(quest, QuestTracker.current_stage_id(quest_id))
		if entry_text.strip_edges() != "":
			var entry := Label.new()
			entry.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART  # same no-horizontal-scroll rule as the title
			entry.text = entry_text
			entry.add_theme_color_override(&"font_color", MenuStyle.skin.text_dim_color)
			box.add_child(entry)
	var objectives: Array[QuestObjective] = QuestTracker.current_objectives(quest_id) if not done else closed_objectives(quest)
	for obj in objectives:
		if obj == null:
			continue
		var line := Label.new()
		line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART  # same no-horizontal-scroll rule as the title above
		var od := done or GameState.is_objective_done(quest_id, obj.id)
		line.text = objective_line(obj, od, GameState.objective_progress(quest_id, obj.id))
		line.add_theme_color_override(&"font_color", MenuStyle.skin.text_dim_color if od else MenuStyle.skin.text_color)
		box.add_child(line)
	return box

## The journal entry for an active quest in `stage_id` -- the stage's journal_text, else the quest description (the
## rule lives on Quest.journal_text_for; this is the journal's pure, testable entry point).
static func summary_text(quest: Quest, stage_id: StringName) -> String:
	return quest.journal_text_for(stage_id) if quest != null else ""

## The objective lines a CLOSED quest shows: a stage-less quest's objectives (all ticked); nothing for a staged quest,
## whose earlier stages are not tracked once it closes.
static func closed_objectives(quest: Quest) -> Array[QuestObjective]:
	var none: Array[QuestObjective] = []
	if quest == null or quest.has_stages():
		return none
	return quest.objectives

## The display text for one objective — pure (takes done + progress), so it's unit-testable without GameState.
## A thin delegator kept with this signature for the call site + unit-test pins: only the description-or-id
## fallback resolves here; the eight whole templates live in PlayerText.journal_objective (byte-identical
## output). e.g. "[x] Kill the boss" or "[ ] Collect parts (2/5)  (optional)".
func objective_line(obj: QuestObjective, done: bool, progress: int) -> String:
	var desc := obj.description if obj.description != "" else String(obj.id).capitalize()  # blank-description degrade only: never a raw snake_case id on screen
	return PlayerText.journal_objective(desc, done, progress, obj.required_count, obj.optional)
