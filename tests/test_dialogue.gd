extends GutTest

## GUT suite for the Dialogue subsystem (scripts/dialogue/*.gd). Each assert message
## states WHY the invariant matters, so this file doubles as executable documentation
## of the dialogue data contract and the DialogueManager safety guards.
##
## COVERS:
##   - DialogueLine (class_name, Resource): text default, type, mutation, identity,
##     and the branching extension -- END sentinel value, choices default (empty non-null typed
##     array), typed-element retention, and the has_choices() linear-vs-branch predicate.
##   - DialogueChoice (class_name, Resource): text/target defaults, types, writability,
##     identity, and that the default target == DialogueLine.CONTINUE (an unconfigured choice carries on).
##   - DialogueResource (class_name, Resource): lines default (empty non-null typed array),
##     typed-element retention, mutation/clear, identity.
##   - DialogueManager (NO class_name -> loaded via load(path).new()): starts idle,
##     start/is_active methods + the four state signals exist with the right arity
##     (dialogue_started(resource) + dialogue_suspended(reason) each carry ONE arg;
##     dialogue_finished / dialogue_resumed carry none) and dialogue_started delivers the resource,
##     the branching entry points (_on_choice_pressed/_jump_to/_clear_choices) exist,
##     _ready sets PROCESS_MODE_ALWAYS, and start(null) / start(empty resource) are
##     guarded no-ops that never pause the tree or grab the mouse.
##   - DialogueNPC (class_name, Node3D): exported dialogue/range_area fields exist and
##     default null; class/Node3D identity.
##   - Talkable (class_name, Area3D): the reusable drop-on-anything talk component -- exported
##     dialogue/highlight_target default null, highlight_color/width have white/1.0 defaults,
##     class/Area3D identity, and the _begin_dialogue dead-host liveness bail (the buffered
##     talk-prompt delivery must not open a conversation on a corpse). Inspected the same
##     null-add_child way as DialogueNPC (its _ready wires its own body signals +
##     _setup_highlight, and _process hits the autoload).
##
## DELIBERATELY SKIPPED (unsafe or untestable as units):
##   - DialogueManager.start() with a VALID non-empty resource: passes the guard then sets
##     get_tree().paused = true, Input.mouse_mode = MOUSE_MODE_HIDDEN (the listen-first intro cursor), and
##     builds a CanvasLayer. Driving it would corrupt the runner's tree/mouse state. Only start(null)/start(empty) are safe.
##   - DialogueManager._show_line/_advance/_finish/_build_ui: require an active conversation +
##     built UI; _finish recaptures the mouse. Unreachable without the forbidden start().
##   - DialogueManager._jump_to/_on_choice_pressed: the branching jump logic. These read _active
##     and call _show_line()/_finish() (which touch the CanvasLayer + recapture the mouse), and
##     _active is only set by the forbidden start(). So we assert the members EXIST via has_method
##     but never invoke them; branch correctness is verified at the data layer instead -- the
##     END / CONTINUE sentinel values, target int range, and has_choices() predicate fully describe the
##     decision _jump_to makes (target == CONTINUE -> advance; == END / <0 / >= size -> finish; else jump).
##   - DialogueManager._unhandled_input: only the inactive early-return branch is reachable
##     safely, and it changes no observable state (nothing to assert). The new choice guard
##     (has_choices() early-return) sits behind the active check, so it is likewise unreachable
##     without start(); it is covered indirectly by the has_choices() data-layer tests.
##   - DialogueNPC._ready/_process/_on_body_entered/_on_body_exited: _ready wires Area3D signals,
##     _process references the global identifier `DialogueManager` (the live autoload singleton --
##     see project.godot [autoload]) and calls into it (is_active/start), which would pause the tree
##     + grab the mouse; the body handlers only flip a private _player_in_range bool. So DialogueNPC
##     is inspected ONLY via load(path).new() WITHOUT add_child (so _ready/_process never run), then .free().
##
## NOTE on instantiation: DialogueManager IS a registered autoload (project.godot [autoload]:
## DialogueManager="*uid://ciodr6civihjs" -> scripts/dialogue/dialogue_manager.gd) but it declares
## NO class_name, so the bare identifier `DialogueManager` resolves to the live singleton Node, not
## a constructible class -- `DialogueManager.new()` would not compile (a Node instance has no .new()).
## We therefore build a throwaway via load("res://scripts/dialogue/dialogue_manager.gd").new(), which
## is a brand-new instance we fully control and which never touches the live autoload singleton.
##
## NOTE on freeing: DialogueLine / DialogueResource extend Resource (RefCounted), so they are
## released automatically when the local var goes out of scope -- calling .free() on a RefCounted
## raises "Attempted to free a RefCounted object" in Godot 4, so these tests deliberately do NOT
## free them. Only the Node-derived DialogueManager / DialogueNPC instances that were NOT added
## to the tree are .free()'d by hand.

const DIALOGUE_MANAGER_PATH := "res://scripts/dialogue/dialogue_manager.gd"
const DIALOGUE_NPC_PATH := "res://scripts/components/dialogue_npc.gd"
const TALKABLE_PATH := "res://scripts/components/talkable.gd"
const SPEECH_TTS_PATH := "res://managers/SpeechTts.gd"

class _ForgiveRecorder extends Node:
	var forgive_count: int = 0

	func forgive_provoke() -> void:
		forgive_count += 1

class _StatBuffPlayerStub extends Node:
	var sheet := CharacterStats.new()
	var mods := {}

	func stats_or_default() -> CharacterStats:
		return sheet

	func status_stat_modifier(stat: StringName) -> float:
		return float(mods.get(String(stat), 0.0))


# ---------------------------------------------------------------------------
# DialogueLine -- pure Resource (no _init/_ready), safe to .new() without the tree.
# RefCounted: no .free() (auto-released at scope exit).
# ---------------------------------------------------------------------------

func test_dialogue_line_text_default_is_empty() -> void:
	var l := DialogueLine.new()
	assert_eq(l.text, "",
		"DialogueLine.text must default to \"\" so an unset line renders blank rather than null-crashing the text label")


func test_dialogue_line_field_types_are_strings() -> void:
	var l := DialogueLine.new()
	assert_eq(typeof(l.text), TYPE_STRING,
		"DialogueLine.text must be a String -- it is assigned directly to Label.text in _show_line")


func test_dialogue_line_fields_are_writable() -> void:
	var l := DialogueLine.new()
	l.text = "Hi"
	assert_eq(l.text, "Hi",
		"DialogueLine.text must be a writable @export so lines built in code hold their value for playback")


func test_dialogue_line_is_resource_and_typed() -> void:
	var l := DialogueLine.new()
	assert_true(l is Resource,
		"DialogueLine must be a Resource so it can be saved as a .tres and packed into DialogueResource.lines")
	assert_true(l is DialogueLine,
		"DialogueLine.new() must produce a DialogueLine (class_name registered) so it can be referenced by type")


# ---------------------------------------------------------------------------
# DialogueLine -- branching extension. choices defaults empty (so EVERY pre-branching line and
# .tres stays linear by construction), has_choices() is the pure linear-vs-branch predicate the
# manager keys on, and END is the reserved finish-target value choices can carry.
# ---------------------------------------------------------------------------

func test_dialogue_line_end_sentinel_is_negative_one() -> void:
	assert_eq(DialogueLine.END, -1,
		"DialogueLine.END must be -1: the reserved choice target that DialogueManager._jump_to maps to _finish()")


func test_dialogue_line_continue_sentinel_is_distinct() -> void:
	assert_eq(DialogueLine.CONTINUE, -2,
		"DialogueLine.CONTINUE must be -2: the DEFAULT choice target, mapped to _advance() so an unconfigured choice carries the conversation on instead of dead-ending")
	assert_ne(DialogueLine.CONTINUE, DialogueLine.END,
		"CONTINUE and END must be different sentinels — one keeps the conversation going, the other stops it")


func test_dialogue_line_choices_default_is_empty_non_null() -> void:
	var l := DialogueLine.new()
	assert_not_null(l.choices,
		"DialogueLine.choices must default to a non-null array so _show_line's line.has_choices() / iteration never null-derefs on an unset line")
	assert_eq(l.choices.size(), 0,
		"DialogueLine.choices must default empty so every existing line and .tres is automatically linear (no choices) -- the MVP is preserved by construction")


func test_dialogue_line_has_choices_false_when_empty() -> void:
	var l := DialogueLine.new()
	assert_false(l.has_choices(),
		"has_choices() must be false on a fresh line so the manager shows the continue hint and runs the linear _advance path, exactly as before branching existed")


func test_dialogue_line_has_choices_true_after_append() -> void:
	var l := DialogueLine.new()
	l.choices.append(DialogueChoice.new())
	assert_true(l.has_choices(),
		"has_choices() must be true once a choice is added so _show_line spawns buttons and _unhandled_input early-returns (input can't skip the menu)")


func test_dialogue_line_choices_retains_dialogue_choice_type() -> void:
	var l := DialogueLine.new()
	l.choices.append(DialogueChoice.new())
	assert_true(l.choices[0] is DialogueChoice,
		"DialogueLine.choices is Array[DialogueChoice]; elements must stay DialogueChoice so _show_line's choice.text / choice.target access is valid")


# ---------------------------------------------------------------------------
# DialogueChoice -- pure Resource (no _init/_ready), safe to .new() without the tree.
# RefCounted: no .free() (auto-released at scope exit). One selectable branch option:
# a button label (text) + an integer target index into DialogueResource.lines (or END to finish).
# ---------------------------------------------------------------------------

func test_dialogue_choice_text_default_is_empty() -> void:
	var c := DialogueChoice.new()
	assert_eq(c.text, "",
		"DialogueChoice.text must default to \"\" so an unconfigured choice renders a blank button rather than null-crashing Button.text")


func test_dialogue_choice_target_default_is_continue() -> void:
	var c := DialogueChoice.new()
	assert_eq(c.target, DialogueLine.CONTINUE,
		"DialogueChoice.target must default to DialogueLine.CONTINUE (-2) so a freshly-made, unconfigured choice CARRIES THE CONVERSATION ON to the next line instead of dead-ending it")


func test_dialogue_choice_field_types() -> void:
	var c := DialogueChoice.new()
	assert_eq(typeof(c.text), TYPE_STRING,
		"DialogueChoice.text must be a String -- it is assigned directly to Button.text in _show_line")
	assert_eq(typeof(c.target), TYPE_INT,
		"DialogueChoice.target must be an int -- it shares DialogueManager._index's integer line-address space and is compared against lines.size() in _jump_to")


func test_dialogue_choice_fields_are_writable() -> void:
	var c := DialogueChoice.new()
	c.text = "Tell me more"
	c.target = 2
	assert_eq(c.text, "Tell me more",
		"DialogueChoice.text must be a writable @export so choices built in code (not just .tres) hold their button label")
	assert_eq(c.target, 2,
		"DialogueChoice.target must be a writable @export so a choice can point at a specific line index for the jump")


func test_dialogue_choice_is_resource_and_typed() -> void:
	var c := DialogueChoice.new()
	assert_true(c is Resource,
		"DialogueChoice must be a Resource so it can be saved/nested as a sub-resource inside DialogueLine.choices in a .tres")
	assert_true(c is DialogueChoice,
		"DialogueChoice.new() must produce a DialogueChoice (class_name registered) so DialogueLine.choices can type its elements")


# DialogueChoice -- consequence block (rank 6b/7): the optional effects a picked choice applies. Pure data
# (defaults / writability / the give_item_id dropdown); the application logic lives in DialogueManager and is
# covered by its has_method surface (it touches the GameState autoload + the live player, not unit-testable here).

func test_dialogue_choice_consequence_defaults() -> void:
	var c := DialogueChoice.new()
	assert_eq(c.set_flag, &"", "set_flag defaults empty -> no flag written")
	assert_eq(c.set_flag_value, true, "set_flag_value defaults true")
	assert_null(c.start_quest_on_choice, "start_quest_on_choice defaults null -> no quest started")
	assert_eq(c.complete_quest_id, &"", "complete_quest_id defaults empty")
	assert_eq(c.advance_quest_id, &"", "advance_quest_id defaults empty")
	assert_eq(c.give_item_id, &"", "give_item_id defaults empty -> no item given")
	assert_eq(c.give_item_count, 1, "give_item_count defaults 1")
	assert_eq(c.give_money, 0.0, "give_money defaults 0 -> no wallet change")

func test_dialogue_choice_consequences_writable() -> void:
	var c := DialogueChoice.new()
	c.set_flag = &"met_fixer"
	c.give_money = 50.0
	c.give_item_id = &"keycard_red"
	c.give_item_count = 2
	assert_eq(c.set_flag, &"met_fixer", "set_flag is a writable @export")
	assert_eq(c.give_money, 50.0, "give_money is writable (negative = a fee)")
	assert_eq(c.give_item_id, &"keycard_red", "give_item_id is writable")
	assert_eq(c.give_item_count, 2, "give_item_count is writable")

func test_dialogue_choice_give_item_id_is_dropdown() -> void:
	var c := DialogueChoice.new()
	for p in c.get_property_list():
		if p.get("name", "") == "give_item_id":
			assert_eq(p.get("hint", -1), PROPERTY_HINT_ENUM_SUGGESTION,
				"give_item_id must be a PROPERTY_HINT_ENUM_SUGGESTION dropdown (set in _validate_property, from the ItemIds registry)")
			return
	assert_true(false, "give_item_id property not found on DialogueChoice")

func test_dialogue_choice_wr_gate_and_write_defaults() -> void:
	# WR-1/WR-3: the new rep/perk/item/quest gates + the rep/aggro writes all default INERT, so a choice with
	# none set behaves exactly as before.
	var c := DialogueChoice.new()
	assert_eq(c.required_faction_id, "", "no reputation gate by default")
	assert_eq(c.required_reputation, 0.0, "rep threshold defaults 0")
	assert_eq(c.required_perk_id, &"", "no perk gate by default")
	assert_eq(c.required_item_id, &"", "no item gate by default")
	assert_eq(c.required_item_count, 1, "item gate count defaults 1")
	assert_eq(c.required_quest_id, &"", "no quest gate by default")
	assert_eq(c.required_quest_state, DialogueChoice.QuestGate.ANY, "quest gate defaults ANY")
	assert_eq(c.reward_reputation_faction_id, "", "no rep reward by default")
	assert_eq(c.reward_reputation, 0.0, "rep reward defaults 0")
	assert_false(c.aggro_speaker, "the speaker isn't aggroed by default")
	c = null

func test_dialogue_choice_faction_and_item_dropdowns_self_populate() -> void:
	var c := DialogueChoice.new()
	var seen := {}
	for prop in c.get_property_list():
		var n: String = prop.get("name", "")
		if n == "required_faction_id" or n == "reward_reputation_faction_id" or n == "required_item_id":
			seen[n] = prop.get("hint", -1)
	assert_eq(seen.get("required_faction_id", -1), PROPERTY_HINT_ENUM_SUGGESTION, "required_faction_id is a faction dropdown")
	assert_eq(seen.get("reward_reputation_faction_id", -1), PROPERTY_HINT_ENUM_SUGGESTION, "reward_reputation_faction_id is a faction dropdown")
	assert_eq(seen.get("required_item_id", -1), PROPERTY_HINT_ENUM_SUGGESTION, "required_item_id is an item dropdown")
	c = null

func test_dialogue_choice_target_on_fail_default_is_end() -> void:
	var c := DialogueChoice.new()
	assert_eq(c.target_on_fail, DialogueLine.END,
		"DialogueChoice.target_on_fail must default to DialogueLine.END (-1) -- a failed gated choice finishes the conversation unless an author points it at a fail line (rank 22)")
	c.target_on_fail = 4
	assert_eq(c.target_on_fail, 4, "target_on_fail is a writable @export so a fail branch can point at a specific line")


func test_required_stat_dropdown_self_populates() -> void:
	# required_stat is @tool + _validate_property, so its inspector dropdown is the LIVE CharacterStats attribute
	# list (PROPERTY_HINT_ENUM_SUGGESTION), not a hand-typed copy -- add/rename a stat and the dropdown follows,
	# making a typo'd check (which silently reads BASELINE) far less likely.
	var c := DialogueChoice.new()
	var p := {}
	for prop in c.get_property_list():
		if prop.get("name", "") == "required_stat":
			p = prop
			break
	assert_false(p.is_empty(), "DialogueChoice must expose a required_stat property")
	assert_eq(p.get("hint", -1), PROPERTY_HINT_ENUM_SUGGESTION,
		"required_stat must be a SUGGESTION dropdown (set in _validate_property) so a blank 'no check' stays valid")
	assert_eq(p.get("hint_string", ""), CharacterStats.stat_names_csv(),
		"required_stat dropdown must self-populate from CharacterStats.stat_names_csv() -- no hand-maintained list")


# ---------------------------------------------------------------------------
# DialogueResource -- pure Resource (no _init/_ready), safe to .new() without the tree.
# RefCounted: no .free() (auto-released at scope exit).
# ---------------------------------------------------------------------------

func test_dialogue_resource_lines_default_is_empty_non_null() -> void:
	var r := DialogueResource.new()
	assert_not_null(r.lines,
		"DialogueResource.lines must default to a non-null array so start()'s dialogue.lines.is_empty() guard never null-derefs")
	assert_eq(r.lines.size(), 0,
		"DialogueResource.lines must default empty so a freshly-made resource is treated as an empty (no-op) conversation")


func test_dialogue_resource_lines_retains_dialogue_line_type() -> void:
	var r := DialogueResource.new()
	var ln := DialogueLine.new()
	r.lines.append(ln)
	assert_eq(r.lines.size(), 1,
		"Appending to DialogueResource.lines must grow the array so a built conversation has playable lines")
	assert_true(r.lines[0] is DialogueLine,
		"DialogueResource.lines is Array[DialogueLine]; elements must stay DialogueLine so _show_line's line.text access is valid")


func test_dialogue_resource_lines_mutation_and_clear() -> void:
	var r := DialogueResource.new()
	r.lines.append(DialogueLine.new())
	r.lines.clear()
	assert_eq(r.lines.size(), 0,
		"Clearing DialogueResource.lines must report size 0 so an emptied resource hits the start() is_empty() no-op guard")


func test_dialogue_resource_is_resource_and_typed() -> void:
	var r := DialogueResource.new()
	assert_true(r is Resource,
		"DialogueResource must be a Resource so it can be an @export on DialogueNPC and saved as a .tres")
	assert_true(r is DialogueResource,
		"DialogueResource.new() must produce a DialogueResource (class_name registered) so it can be typed on NPCs and start()")


# ---------------------------------------------------------------------------
# TalkHelpers.speaker_name -- the dialogue speaker-label name resolver (pure/static),
# used so a DialogueLine with a blank `speaker` falls back to the character's name.
# ---------------------------------------------------------------------------

func test_speaker_name_prefers_explicit_over_node() -> void:
	assert_eq(TalkHelpers.speaker_name("Bob", null), "Bob",
		"An explicit speaker name (set on the Talkable / DialogueNPC) must win, even over a node display_name")

func test_speaker_name_empty_when_nothing_provides_one() -> void:
	assert_eq(TalkHelpers.speaker_name("", null), "",
		"No explicit name + no node must resolve to \"\" so the dialogue speaker label stays hidden")

func test_speaker_name_falls_back_to_node_display_name() -> void:
	var n = load("res://scripts/npc/npc.gd").new()  # NPC exposes display_name; built off-tree (no _ready)
	n.display_name = "Raider"
	assert_eq(TalkHelpers.speaker_name("", n), "Raider",
		"With no explicit name, speaker_name must read the node's display_name (a talkable NPC is named once, on the NPC)")
	n.free()


# ---------------------------------------------------------------------------
# DialogueManager -- NO class_name. Inspect a THROWAWAY instance via load(path).new().
# is_active()/has_method()/has_signal() are safe without _ready (no child/autoload deref).
# Node-derived: instances NOT added to the tree are .free()'d by hand.
# ---------------------------------------------------------------------------

func test_dialogue_manager_starts_inactive() -> void:
	# No add_child: is_active() only reads `_active != null` (defaults null), so it is
	# safe even though _ready never ran.
	var m = load(DIALOGUE_MANAGER_PATH).new()
	assert_false(m.is_active(),
		"DialogueManager must start idle (_active == null) so an NPC is free to begin a conversation")
	m.free()


func test_dialogue_cursor_hidden_while_reading_visible_for_choices() -> void:
	# The cursor follows the dialogue phase: hidden while a line is read (listen-first, nothing to click),
	# shown once the response menu is up so the player can click an option. dialogue_cursor_mode() is pure
	# (reads only _choices_shown), so it pins the contract without driving the live Input singleton.
	var m = load(DIALOGUE_MANAGER_PATH).new()
	m._choices_shown = false
	assert_eq(m.dialogue_cursor_mode(), Input.MOUSE_MODE_HIDDEN,
		"while a line is being read the cursor must be HIDDEN (nothing to click yet)")
	m._choices_shown = true
	assert_eq(m.dialogue_cursor_mode(), Input.MOUSE_MODE_VISIBLE,
		"once the response menu is up the cursor must be VISIBLE so the player can click an option")
	m.free()


func test_dialogue_manager_public_api_exists() -> void:
	var m = load(DIALOGUE_MANAGER_PATH).new()
	assert_true(m.has_method("start"),
		"DialogueManager must expose start(dialogue) -- the entry point NPCs call to begin a conversation")
	assert_true(m.has_method("is_active"),
		"DialogueManager must expose is_active() -- NPCs query it to avoid double-starting / double-advancing")
	m.free()


func test_is_engaged_covers_suspended_conversations_that_is_active_hides() -> void:
	# Regression for "dialog > trade/heal/exchange > death corrupts the menus & UI": while a conversation is
	# SUSPENDED behind a sub-menu (Trade / Heal / Level Up / Install / Exchange Gear), is_active() reads FALSE
	# BY DESIGN (so the sub-menu -- which refuses to open over an ACTIVE dialogue -- is allowed to open). But
	# the conversation still EXISTS. Player.die() gates its abort on is_engaged(), NOT is_active(): the old
	# is_active() gate skipped the abort during a suspension, so die() -> _close_open_modals() then closed the
	# sub-menu, whose `closed` fired _resume_from_menu, re-pausing the tree + re-opening the box over the death
	# cinematic (which freezes the node-bound death tween). Pure predicates (read only _active/_suspended), so
	# no add_child / start() needed -- safe on a bare instance whose _ready never ran.
	var m = load(DIALOGUE_MANAGER_PATH).new()
	assert_true(m.has_method("is_engaged"),
		"DialogueManager must expose is_engaged() -- die() uses it to tear down even a SUSPENDED conversation")
	assert_false(m.is_engaged(),
		"is_engaged() must be FALSE when idle (_active == null) -- nothing to tear down")
	m._active = DialogueResource.new()
	m._suspended = true  # a sub-menu (Trade/Heal/Install/...) is up
	assert_false(m.is_active(),
		"a SUSPENDED conversation must read is_active()==false so the sub-menu can open over it")
	assert_true(m.is_engaged(),
		"a suspended conversation is still ENGAGED -- die() aborts on THIS so a mid-menu death tears the conversation down instead of letting the sub-menu's close re-pause + re-open the box over the death cinematic")
	m.free()


func test_clear_choices_detaches_buttons_synchronously() -> void:
	# LAYOUT regression: "dialog > trade/menu > dialog put the box in the WRONG SPOT" (it jumped up off the
	# bottom of the screen). On RESUME from a sub-menu the response menu was still populated, so _reveal_menu
	# cleared-then-re-added the choices and scheduled _clamp_choices_height() in the SAME frame. clear_choices()
	# only queue_free()'d the outgoing buttons -- which is DEFERRED, so they lingered in _choices_box until
	# end-of-frame and got DOUBLE-counted by get_combined_minimum_size(); the choices scroll locked at ~2x height
	# and the bottom-anchored panel grew UPWARD (verified: panel top 270->196, scroll min 68->142). The fix:
	# clear_choices() remove_child()s each outgoing button BEFORE queue_free, so a same-frame re-measure is honest.
	# This test pins the synchronous detach (the measured 68->68 stability is the runtime QA proof of the effect).
	var view := DialogueView.new()
	add_child_autofree(view)
	view.open()  # lazily builds the box + choices UI
	view.add_extra_choice("A", func() -> void: pass)
	view.add_extra_choice("B", func() -> void: pass)
	assert_eq(view._choices_box.get_child_count(), 2, "two choice buttons were added")
	view.clear_choices()
	assert_eq(view._choices_box.get_child_count(), 0,
		"clear_choices() must DETACH the outgoing buttons synchronously (queue_free alone is deferred) so a same-frame _clamp_choices_height re-measure can't double-count them and shove the resumed dialogue box off the bottom of the screen")


func test_dialogue_view_hides_stat_choices_below_requirement() -> void:
	# No Player is present in this bare view test, so DialogueView._player_stat reads CharacterStats.BASELINE.
	# A choice requiring one point above baseline should disappear entirely; an ungated choice still renders.
	var view := DialogueView.new()
	add_child_autofree(view)
	view.open()
	var gated := DialogueChoice.new()
	gated.text = "Talk your way in"
	gated.required_stat = &"streetwise"
	gated.required_value = CharacterStats.BASELINE + 1
	var plain := DialogueChoice.new()
	plain.text = "Ask politely"
	view.set_choices([gated, plain], func(_choice: DialogueChoice, _passed: bool = true) -> void: pass)
	assert_eq(view._choices_box.get_child_count(), 1,
		"dialogue choices with unmet stat requirements should be hidden, not shown as failed/locked buttons")
	var button := view._choices_box.get_child(0) as Button
	assert_eq(button.text, "Ask politely",
		"the remaining visible choices keep their original order and labels after a stat-gated option is filtered out")

func test_dialogue_stat_checks_include_live_modifiers() -> void:
	var p := _StatBuffPlayerStub.new()
	p.sheet.streetwise = 0
	p.mods["streetwise"] = 3.0
	assert_almost_eq(DialogueView._effective_player_stat(p, &"streetwise"), 3.0, 0.001,
		"a carried +3 streetwise item like Chrome Grin should satisfy a Streetwise 3 dialogue check")
	assert_almost_eq(DialogueView._effective_player_stat(p, &"gunplay"), 0.0, 0.001,
		"unmodified stats still read the raw sheet value")
	p.free()


func test_player_death_tears_down_suspended_conversation_and_closes_install_screen() -> void:
	# Source-string contract (die()'s body drives the live tree, so it can't be unit-invoked). Pins the two
	# halves of the fix in scripts/player/player.gd: (1) die() gates the dialogue abort on is_engaged() so a
	# SUSPENDED conversation is torn down on death; (2) _close_open_modals() now routes through the single
	# registry sweep (InputManager.close_all_modals) instead of a literal ChipInstallScreen.close() -- the sweep
	# closes EVERY modal (incl. the "Install" suspend target, Chess, and the name-entry box), so a newly-added
	# screen can't be forgotten from a hand-list and left open through the death cinematic (T1).
	var src := FileAccess.get_file_as_string("res://scripts/player/player.gd")
	assert_string_contains(src, "DialogueManager.is_engaged()",
		"Player.die() must gate its dialogue abort on DialogueManager.is_engaged() (is_active() reads false during a sub-menu suspension, which skipped the abort)")
	assert_string_contains(src, "close_all_modals()",
		"_close_open_modals() must route through InputManager.close_all_modals() -- the registry sweep closes ChipInstallScreen (and every other modal) on death, so the 'Install' suspend target can't be missed")


func test_speaker_death_teardown_gates_on_engaged_not_active() -> void:
	# Source-string contract -- the MANAGER-side mirror of the Player.die() pin above. _on_speaker_died's
	# teardown runs through _finish() (autoloads + _ready-built children), so it can't be unit-invoked on a
	# bare instance. The gate must be is_engaged(), not is_active(): a speaker dying while the conversation is
	# SUSPENDED behind a sub-menu reads is_active()==false, which would silently drop the teardown and leave
	# the box primed to resume over a corpse (_finish() already drops the pending menu-closed one-shot).
	var src := FileAccess.get_file_as_string(DIALOGUE_MANAGER_PATH)
	assert_string_contains(src, "func _on_speaker_died() -> void:\n\tif is_engaged():",
		"_on_speaker_died must gate its teardown on is_engaged(), not is_active() -- a speaker death during a sub-menu suspension must still end the conversation (mirrors Player.die()'s is_engaged() gate)")


func test_quest_toast_queue_gates_on_engaged_not_active() -> void:
	# Source-string contract -- the HUD-side member of the is_engaged()-not-is_active() family above. UI hides
	# its notices layer for the whole dialogue_started -> dialogue_finished span (nothing listens to
	# suspended/resumed), but is_active() reads FALSE while a sub-menu suspends the conversation -- so a quest
	# toast raised from that sub-menu (e.g. buying a quest-objective item in Trade) would be pushed straight
	# into the invisible layer and burn its fade timer unseen. The queue gate must match the hide span exactly:
	# is_engaged(). (_push_quest_toast reads the DialogueManager autoload, so the branch can't be unit-driven
	# without mutating shared autoload state -- pin the source instead, like the two tests above.)
	var src := FileAccess.get_file_as_string("res://scripts/ui/ui.gd")
	assert_string_contains(src, "func _push_quest_toast(text: String, color: Color) -> void:\n\tif DialogueManager.is_engaged():",
		"UI._push_quest_toast must queue on DialogueManager.is_engaged(), not is_active() -- the notices layer stays hidden through a sub-menu suspension, so a suspension-time quest toast must queue too")


func test_dialogue_manager_branching_api_exists() -> void:
	# Surface-only: these members read _active and call _show_line()/_finish() (CanvasLayer + mouse
	# recapture), so they are NOT invoked here -- _active is only set by the forbidden start(). We
	# assert they EXIST as the branching entry points; their decision is verified at the data layer
	# (DialogueLine.END, DialogueChoice.target range, has_choices()).
	var m = load(DIALOGUE_MANAGER_PATH).new()
	assert_true(m.has_method("_on_choice_pressed"),
		"DialogueManager must expose _on_choice_pressed(choice, passed) -- bound to each choice Button.pressed (via set_choices) to apply consequences + drive the jump")
	assert_true(m.has_method("_apply_choice_effects"),
		"DialogueManager must expose _apply_choice_effects(choice) -- applies a picked choice's flags/quests/give consequences")
	assert_true(m.has_method("_jump_to"),
		"DialogueManager must expose _jump_to(target) -- the choice-jump counterpart to _advance() (sets _index / finishes on END/out-of-range)")
	assert_true(m.has_method("_clear_choices"),
		"DialogueManager must expose _clear_choices() -- it frees the previous line's buttons each line and on finish so choice buttons never stack")
	m.free()


func test_dialogue_manager_signals_exist() -> void:
	var m = load(DIALOGUE_MANAGER_PATH).new()
	assert_true(m.has_signal("dialogue_started"),
		"DialogueManager must declare dialogue_started so HUD/quest hooks can react when a conversation opens")
	assert_true(m.has_signal("dialogue_finished"),
		"DialogueManager must declare dialogue_finished so HUD/quest hooks can react when a conversation ends")
	assert_true(m.has_signal("dialogue_suspended"),
		"DialogueManager must declare dialogue_suspended so UI can react when a sub-menu (Trade/Heal/...) opens over a conversation")
	assert_true(m.has_signal("dialogue_resumed"),
		"DialogueManager must declare dialogue_resumed so UI can react when the conversation returns from a sub-menu")
	m.free()


## Pin the signal ARITY, not just existence: a future refactor that drops dialogue_started's resource arg (or
## dialogue_suspended's reason) would silently break every `.connect` that reads it. get_signal_list() reports the
## declared arg count, so this fails loudly if the contract drifts.
func test_dialogue_manager_signal_arity() -> void:
	var m = load(DIALOGUE_MANAGER_PATH).new()
	assert_eq(_signal_arg_count(m, "dialogue_started"), 1,
		"dialogue_started must carry exactly one arg (the DialogueResource) so listeners know which conversation opened")
	assert_eq(_signal_arg_count(m, "dialogue_suspended"), 1,
		"dialogue_suspended must carry exactly one arg (the reason String) so listeners know which sub-menu opened")
	assert_eq(_signal_arg_count(m, "dialogue_finished"), 0,
		"dialogue_finished carries no args (a bare state notification)")
	assert_eq(_signal_arg_count(m, "dialogue_resumed"), 0,
		"dialogue_resumed carries no args (a bare state notification)")
	m.free()


func test_speech_tts_dialogue_completion_signal_exists() -> void:
	var t = load(SPEECH_TTS_PATH).new()
	assert_true(t.has_signal("dialogue_speech_finished"),
		"SpeechTts must emit when a focused dialogue line's generated audio finishes so auto-advance cannot cut long TTS lines off at the estimate cap")
	assert_eq(_signal_arg_count(t, "dialogue_speech_finished"), 1,
		"dialogue_speech_finished must carry the speech token so stale completions from skipped lines are ignored")
	t.free()


func test_dialogue_auto_advance_waits_for_tts_completion_when_available() -> void:
	var m = load(DIALOGUE_MANAGER_PATH).new()
	assert_true(m.has_method("_auto_advance_from_speech"),
		"DialogueManager needs a token-checked TTS completion path so long spoken lines advance only after the real audio finishes")
	m.free()
	var src := FileAccess.get_file_as_string(DIALOGUE_MANAGER_PATH)
	assert_string_contains(src, "SpeechTts.dialogue_speech_finished.connect",
		"auto-advance must connect to SpeechTts.dialogue_speech_finished when speech_token > 0 instead of relying only on the clamped text estimate")
	assert_string_contains(src, "speech_token > 0",
		"DialogueManager must use TTS completion only when SpeechTts actually started audio; text-only dialogue keeps the estimated timer fallback")


## dialogue_started must actually HAND the resource to a 1-arg listener. Emitting the signal directly needs no live
## conversation (no _ready / _view / paused tree), so this stays a safe unit test while proving the delivery contract
## that ui.gd's crosshair-fold and any future per-dialogue hook depend on.
func test_dialogue_started_delivers_resource() -> void:
	var m = load(DIALOGUE_MANAGER_PATH).new()
	var res := DialogueResource.new()
	var got := {"resource": null}
	m.dialogue_started.connect(func(r: DialogueResource) -> void: got["resource"] = r)
	m.dialogue_started.emit(res)
	assert_eq(got["resource"], res,
		"dialogue_started.emit(resource) must deliver the exact DialogueResource to a 1-arg listener")
	m.free()


## dialogue_suspended must hand the reason String through. Same direct-emit approach — the real _suspend_for_menu
## emit needs a live conversation + _view, verified by playtest; here we pin the signal plumbing/shape.
func test_dialogue_suspended_delivers_reason() -> void:
	var m = load(DIALOGUE_MANAGER_PATH).new()
	var got := {"reason": ""}
	m.dialogue_suspended.connect(func(reason: String) -> void: got["reason"] = reason)
	m.dialogue_suspended.emit("trade")
	assert_eq(got["reason"], "trade",
		"dialogue_suspended.emit(reason) must deliver the menu reason to a 1-arg listener")
	m.free()


## Helper: the declared argument count of a signal on `obj` (from get_signal_list()), or -1 if absent.
func _signal_arg_count(obj: Object, sig_name: String) -> int:
	for s in obj.get_signal_list():
		if s.get("name", "") == sig_name:
			return (s.get("args", []) as Array).size()
	return -1


func test_dialogue_manager_ready_sets_process_mode_always() -> void:
	# add_child IS safe here: _ready sets process_mode and builds two PROCESS_MODE_ALWAYS children
	# (DialogueView + MusicDucker); neither derefs a project autoload or grabs the mouse (MusicDucker only
	# reads an AudioServer bus index), so adding it to the bare GUT tree is side-effect-free for this test.
	# The only other lifecycle hook, _unhandled_input, early-returns while inactive (it stays inactive).
	var m = load(DIALOGUE_MANAGER_PATH).new()
	add_child_autofree(m)
	assert_eq(m.process_mode, Node.PROCESS_MODE_ALWAYS,
		"_ready must set PROCESS_MODE_ALWAYS so the text box keeps advancing while the manager pauses the game tree")


func test_dialogue_manager_start_null_is_guarded_noop() -> void:
	# Must be in the tree so get_tree() is non-null for the paused assert. Safe because
	# the start() guard (`dialogue == null`) returns BEFORE any get_tree()/mouse side effect.
	var m = load(DIALOGUE_MANAGER_PATH).new()
	add_child_autofree(m)
	m.start(null)
	assert_false(m.is_active(),
		"start(null) must be ignored (the dialogue == null guard) so a missing resource never opens a conversation")
	assert_false(get_tree().paused,
		"start(null) must return before get_tree().paused = true so a null resource never freezes the game")


func test_dialogue_manager_start_empty_resource_is_guarded_noop() -> void:
	# Same early-return path: lines.is_empty() is true, so start() returns before get_tree().
	var m = load(DIALOGUE_MANAGER_PATH).new()
	add_child_autofree(m)
	var empty := DialogueResource.new()
	m.start(empty)
	assert_false(m.is_active(),
		"start(empty) must be ignored (the dialogue.lines.is_empty() guard) so an empty conversation never opens")
	assert_false(get_tree().paused,
		"start(empty) must return before get_tree().paused = true so an empty resource never freezes the game")


# ---------------------------------------------------------------------------
# DialogueNPC -- inspect via load(path).new() WITHOUT add_child so _ready (which wires
# Area3D signals) and _process (which references the live `DialogueManager` autoload and
# would pause the tree + grab the mouse) never run. Node-derived but not in the tree, so .free() by hand.
# ---------------------------------------------------------------------------

func test_dialogue_npc_exported_fields_default_null() -> void:
	var npc = load(DIALOGUE_NPC_PATH).new()
	assert_eq(npc.dialogue, null,
		"DialogueNPC.dialogue must default null -- the field exists but stays unset until the scene wires a DialogueResource")
	assert_eq(npc.range_area, null,
		"DialogueNPC.range_area must default null -- the field exists but stays unset until the scene wires its Area3D")
	npc.free()


func test_dialogue_npc_is_node3d_and_typed() -> void:
	var npc = load(DIALOGUE_NPC_PATH).new()
	assert_true(npc is Node3D,
		"DialogueNPC must extend Node3D so it can be placed in the 3D world with a mesh + range Area3D")
	assert_true(npc is DialogueNPC,
		"DialogueNPC.new() must produce a DialogueNPC (class_name registered) so scenes can type it")
	npc.free()

func test_holster_deescalation_ignores_forced_carry_holster() -> void:
	var controller := DialogueController.new()
	var player := Player.new()
	var npc := _ForgiveRecorder.new()
	controller.host = player
	npc.add_to_group(Groups.NPC)
	add_child_autofree(controller)
	add_child_autofree(npc)

	controller.on_weapon_holstered(true)
	assert_eq(npc.forgive_count, 1,
		"a normal empty-handed holster still forgives a provoked NPC")
	player._carrying = true
	controller.on_weapon_holstered(true)
	assert_eq(npc.forgive_count, 1,
		"a forced carry holster must not forgive: the player is holding a throwable threat, not standing down")
	player.free()


# ---------------------------------------------------------------------------
# DialogueSelector / DialogueSelectorRow (rank 8) -- pick a conversation by world state. Pure data + the
# ungated-row / default fallback (a gated matches() reads the GameState autoload, so only the no-gate path is
# unit-tested here, mirroring how the manager's autoload-touching logic is left to playtest).
# ---------------------------------------------------------------------------

func test_dialogue_selector_pick_returns_default_when_no_rows() -> void:
	var sel := DialogueSelector.new()
	var d := DialogueResource.new()
	sel.default_dialogue = d
	assert_eq(sel.pick(), d, "with no rows, pick() returns default_dialogue")

func test_dialogue_selector_first_ungated_row_wins_over_default() -> void:
	var sel := DialogueSelector.new()
	var d0 := DialogueResource.new()
	var d_def := DialogueResource.new()
	var row := DialogueSelectorRow.new()  # no gates -> always matches
	row.dialogue = d0
	sel.rows.append(row)
	sel.default_dialogue = d_def
	assert_eq(sel.pick(), d0, "an ungated row matches and its dialogue wins over the default")

func test_dialogue_selector_row_no_gate_matches() -> void:
	var row := DialogueSelectorRow.new()
	assert_true(row.matches(), "a row with no flag/quest gate always matches")
	assert_null(row.dialogue, "DialogueSelectorRow.dialogue defaults null")
	assert_eq(row.required_quest_state, DialogueSelectorRow.QuestState.ACTIVE, "required_quest_state defaults ACTIVE")


# --- WR-6: a FAILED quest opens its own dialogue gate (the DialogueChoice gate eval is playtest-verified;
# the DialogueSelectorRow.matches() path is pure enough to pin against the GameState autoload + reset) --------

func test_quest_gate_enums_have_failed() -> void:
	assert_true(DialogueChoice.QuestGate.has("FAILED"), "DialogueChoice.QuestGate gained a FAILED state (WR-6)")
	assert_true(DialogueSelectorRow.QuestState.has("FAILED"), "DialogueSelectorRow.QuestState gained a FAILED state (WR-6)")

func test_selector_row_failed_state_tracks_a_failed_quest() -> void:
	# matches() reads the GameState autoload — set up a failed quest, assert the FAILED row matches, then reset.
	GameState.reset_for_new_game()
	var q := Quest.new()
	q.id = &"wr6_sel"  # no objectives needed — fail_quest acts on the active record directly
	GameState.start_quest(q)
	GameState.fail_quest(&"wr6_sel")
	var row := DialogueSelectorRow.new()
	row.required_quest_id = &"wr6_sel"
	row.required_quest_state = DialogueSelectorRow.QuestState.FAILED
	assert_true(row.matches(), "a FAILED selector row matches once the quest has failed")
	row.required_quest_state = DialogueSelectorRow.QuestState.ACTIVE
	assert_false(row.matches(), "the same row gated ACTIVE no longer matches a failed quest")
	row.required_quest_state = DialogueSelectorRow.QuestState.NOT_STARTED
	assert_false(row.matches(), "a failed quest counts as started, so NOT_STARTED no longer matches")
	GameState.reset_for_new_game()  # cleanup the shared autoload
	q = null


# ---------------------------------------------------------------------------
# Talkable -- the reusable talk component (Area3D). Inspect via load(path).new() WITHOUT
# add_child so _ready (wires its own body_entered/exited + _setup_highlight, which walks
# get_parent()) and _process (references the live DialogueManager autoload, which would pause
# the tree + grab the mouse) never run. Area3D is a Node but not in the tree, so .free() by hand.
# ---------------------------------------------------------------------------

func test_talkable_exported_fields_default_null() -> void:
	var t = load(TALKABLE_PATH).new()
	assert_eq(t.dialogue, null,
		"Talkable.dialogue must default null -- the field exists but stays unset until a scene wires a DialogueResource")
	assert_eq(t.highlight_target, null,
		"Talkable.highlight_target must default null so _setup_highlight falls back to the component's parent (the host NPC it sits under)")
	t.free()


func test_talkable_highlight_defaults() -> void:
	var t = load(TALKABLE_PATH).new()
	assert_eq(t.highlight_color, Color(1.0, 1.0, 1.0, 1.0),
		"Talkable.highlight_color must default to opaque white -- the 'this NPC is talkable' cue the player sees on approach")
	assert_eq(t.highlight_width, 1.0,
		"Talkable.highlight_width must default to 1.0 so the outline matches the existing pickup-highlight width")
	t.free()


func test_talkable_is_area3d_and_typed() -> void:
	var t = load(TALKABLE_PATH).new()
	assert_true(t is Area3D,
		"Talkable must extend Area3D so it IS its own proximity trigger -- dropped under any node, it detects the player without a separate range Area3D")
	assert_true(t is Talkable,
		"Talkable.new() must produce a Talkable (class_name registered) so scenes can type it and reference the component")
	t.free()


## Player stand-in for the dead-host bail test below: _begin_dialogue types `player: Node3D` and, once past
## its guards, calls focus_camera_on() BEFORE DialogueManager.start -- so a recorded call is the observable
## that the liveness bail leaked (we never drive the forbidden non-empty start(); see DELIBERATELY SKIPPED).
class _FocusRecorder extends Node3D:
	var focus_calls: int = 0
	func focus_camera_on(_point) -> void:
		focus_calls += 1


func test_talkable_begin_dialogue_refuses_a_dead_host() -> void:
	# The talk-prompt buffer (TalkApproach.prompt_talk's in-range shortcut) arms a TREE-owned SceneTreeTimer
	# whose callback is _begin_dialogue -- so the delivery still lands when the host is KILLED during the beat
	# (the death freeze only disables the body's process_mode, never the timer). Pin the liveness bail: a DEAD
	# Character host must return BEFORE the camera focus + DialogueManager.start (which would fire
	# GameState.notify_talk, letting a TALK quest objective complete on the corpse). The convo is EMPTY on
	# purpose: if the bail regressed, start(empty) stays the documented safe no-op while the recorder catches
	# the leak -- the runner's tree/mouse state is never at risk.
	var t = load(TALKABLE_PATH).new()
	t.dialogue = DialogueResource.new()  # non-null so the convo guard passes and LIVENESS is what returns
	var host = load("res://scripts/npc/npc.gd").new()
	host.hp = 5.0
	host._dead = true  # the latch take_damage sets the moment the kill lands (before the freeze / free)
	var player := _FocusRecorder.new()
	t._begin_dialogue(host, player)
	assert_eq(player.focus_calls, 0,
		"a host that died inside the talk-prompt buffer must not open a conversation -- _begin_dialogue bails before the camera focus / DialogueManager.start, so no notify_talk ever fires on a corpse")
	player.free()
	host.free()
	t.free()
