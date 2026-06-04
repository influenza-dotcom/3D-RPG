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
##     identity, and that the default target == DialogueLine.END (an unconfigured choice ends).
##   - DialogueResource (class_name, Resource): lines default (empty non-null typed array),
##     typed-element retention, mutation/clear, identity.
##   - DialogueManager (NO class_name -> loaded via load(path).new()): starts idle,
##     start/is_active methods + dialogue_started/dialogue_finished signals exist,
##     the branching entry points (_on_choice_pressed/_jump_to/_clear_choices) exist,
##     _ready sets PROCESS_MODE_ALWAYS, and start(null) / start(empty resource) are
##     guarded no-ops that never pause the tree or grab the mouse.
##   - DialogueNPC (class_name, Node3D): exported dialogue/range_area fields exist and
##     default null; class/Node3D identity.
##   - Talkable (class_name, Area3D): the reusable drop-on-anything talk component -- exported
##     dialogue/highlight_target default null, highlight_color/width have white/1.0 defaults,
##     and class/Area3D identity. Inspected the same null-add_child way as DialogueNPC (its
##     _ready wires its own body signals + _setup_highlight, and _process hits the autoload).
##
## DELIBERATELY SKIPPED (unsafe or untestable as units):
##   - DialogueManager.start() with a VALID non-empty resource: passes the guard then sets
##     get_tree().paused = true, Input.mouse_mode = MOUSE_MODE_VISIBLE, and builds a CanvasLayer.
##     Driving it would corrupt the runner's tree/mouse state. Only start(null)/start(empty) are safe.
##   - DialogueManager._show_line/_advance/_finish/_build_ui: require an active conversation +
##     built UI; _finish recaptures the mouse. Unreachable without the forbidden start().
##   - DialogueManager._jump_to/_on_choice_pressed: the branching jump logic. These read _active
##     and call _show_line()/_finish() (which touch the CanvasLayer + recapture the mouse), and
##     _active is only set by the forbidden start(). So we assert the members EXIST via has_method
##     but never invoke them; branch correctness is verified at the data layer instead -- the
##     END sentinel value, target int range, and has_choices() predicate fully describe the
##     decision _jump_to makes (target == END / <0 / >= size -> finish, else jump).
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
const DIALOGUE_NPC_PATH := "res://scripts/dialogue/dialogue_npc.gd"
const TALKABLE_PATH := "res://scripts/dialogue/talkable.gd"


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
		"DialogueLine.END must be -1: it is the reserved choice target that DialogueManager._jump_to maps to _finish(), and it is also DialogueChoice.target's default")


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


func test_dialogue_choice_target_default_is_end() -> void:
	var c := DialogueChoice.new()
	assert_eq(c.target, DialogueLine.END,
		"DialogueChoice.target must default to DialogueLine.END (-1) so a freshly-made, unconfigured choice safely ENDS the conversation rather than silently jumping to line 0")


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


func test_dialogue_manager_public_api_exists() -> void:
	var m = load(DIALOGUE_MANAGER_PATH).new()
	assert_true(m.has_method("start"),
		"DialogueManager must expose start(dialogue) -- the entry point NPCs call to begin a conversation")
	assert_true(m.has_method("is_active"),
		"DialogueManager must expose is_active() -- NPCs query it to avoid double-starting / double-advancing")
	m.free()


func test_dialogue_manager_branching_api_exists() -> void:
	# Surface-only: these members read _active and call _show_line()/_finish() (CanvasLayer + mouse
	# recapture), so they are NOT invoked here -- _active is only set by the forbidden start(). We
	# assert they EXIST as the branching entry points; their decision is verified at the data layer
	# (DialogueLine.END, DialogueChoice.target range, has_choices()).
	var m = load(DIALOGUE_MANAGER_PATH).new()
	assert_true(m.has_method("_on_choice_pressed"),
		"DialogueManager must expose _on_choice_pressed(target) -- it is bound to each choice Button.pressed in _show_line to drive the jump")
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
	m.free()


func test_dialogue_manager_ready_sets_process_mode_always() -> void:
	# add_child IS safe here: _ready only assigns process_mode (no @onready child grabs,
	# no autoload deref), so adding it to the bare GUT tree has no side effects. The only
	# other lifecycle hook, _unhandled_input, early-returns while inactive (it stays inactive).
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
