class_name DebugMenu
extends CanvasLayer

## The CLICKABLE half of the in-game debug tools: a drop-in cheat MENU for every row in the DebugCommands
## registry. The console (backtick — debug_console.gd's toggle_key is KEY_QUOTELEFT, not a function key) is the
## fast surface for someone who knows the command; this is the DISCOVERABLE one — nothing to memorise, nothing
## to type for a no-argument command.
##
## DEBUG BUILDS ONLY. `_ready` early-outs unless OS.is_debug_build() (or `force_in_release`), and on that path
## it builds NO UI and stops listening for its key — an exported release carries no cheat surface at all.
##
## ⭐ BUILT ENTIRELY FROM THE REGISTRY. Categories come from DebugCommands.categories(), rows from
## in_category(), the argument widgets from each row's `args` Kinds, the validation from validate(), and the
## dispatch from each row's `mod`. Add a row to debug_commands.gd and it appears here with no edit to this
## file — that is the whole point of the one-table/two-front-ends split. The SEARCH BAR is the same table
## read from the other end: DebugCommands.search() filters all eighty-odd rows at once, so a command is
## findable by a word in its help line without knowing which page it lives on.
##
## WHY NOT A TabContainer: MenuStyle._pin_tab_minimum forces use_hidden_tabs_for_min_size on every TabContainer
## under a menu root, so a tabbed panel's minimum is the MAX over all pages and the biggest page would inflate
## the whole card (tests/test_menu_layout_stability.gd measures exactly that). A left column of category
## buttons + a swapped right pane has no such coupling and cannot pump the panel.
##
## WHY NO MenuStyle.apply(): apply() stamps a `_menu_root` meta that MenuStyle's tree-global node_added hook
## uses to auto-wire hover+click cues onto EVERY BaseButton built under that root, forever — a 40-row cheat
## menu would blip on every hover. So this CanvasLayer is deliberately theme-less (nothing above it is a
## Control, so no theme reaches it either) and every font/colour/box below is an explicit
## add_theme_*_override. Every look knob is an @export so it stays tunable in the Inspector.
##
## WHY NO tooltip_text ANYWHERE: project.godot sets embed_subwindows=false, so Godot's own tooltip — a Popup —
## would open as its OWN OS window outside the 792x444 retro viewport. Help text is painted inline on the row
## instead. Same reason there is no OptionButton: enumerated arguments use the project's in-canvas
## `< value >` CYCLER idiom (the Options menu's _option_row).
##
## INPUT / MOUSE / PLAYER CONTRACT (shared verbatim with DebugConsole):
##  * Toggles on a RAW keycode @export, never a rebindable action — an action would drag in the four
##    keybind name-surfaces and generate a player-facing Options → Controls row for a dev key.
##  * Refuses to open over InputManager.any_modal_open(). Two screens that both free the cursor fight over
##    Escape and the loser restores the CAPTURED cursor under a menu that is still up — unclickable
##    (managers/InputManager.gd:150-151, atm_screen.gd:18-20).
##  * Frees the mouse through ModalMenu with the cues OFF, and restores the mode it found.
##  * Freeing the cursor kills mouse-look for free (mouse_input.gd gates look on MOUSE_MODE_CAPTURED) but NOT
##    firing — Attack is polled every frame and gated only on InputManager.gameplay_suppressed(), which we are
##    deliberately not part of (joining _modal_reg would force edits to three hard-pinned assertions in
##    tests/test_modal_registry.gd). So the player is stopped the way Player.die() does it by hand, through
##    DebugActionsPlayer.suspend_player/restore_player — which SNAPSHOT the live values, so opening this over
##    a dead or already-frozen player and closing it again does not resurrect its physics.
##  * PROCESS_MODE_ALWAYS: DialogueManager owns the only pause in the game, and a conversation you cannot
##    inspect is exactly when you need this. (DebugOverlay's failure to set this is a known defect.)
##
## NOT registered in InputManager._modal_reg, NOT an autoload, and it never connects get_tree().node_added
## (tests/test_global_node_added_listeners.gd pins that exactly two game files do).
##
## DROP SITE: scenes/game.tscn, as a sibling of GameRoot/Player — a CanvasLayer parented INSIDE the level
## subtree is freed by GameRoot.load_level along with the level.

## Brand-new class_names are preloaded BY PATH and left untyped: until the editor rescans, annotating with the
## global name fails this WHOLE file to parse with "Could not find type X" and cascades into everything that
## references it. Precedent: debug_overlay.gd:11 (ErrorSinkScript). Groups is not an autoload either.
const DebugCommandsScript := preload("res://scripts/components/debug_commands.gd")
const DebugActionsPlayerScript := preload("res://scripts/components/debug_actions_player.gd")
const DebugActionsWorldScript := preload("res://scripts/components/debug_actions_world.gd")
const GroupsScript := preload("res://scripts/world/groups.gd")

## Layer 149, one under the console's 150. 129..199 is the only free band: 128 is already double-booked by
## OptionsMenu AND the F3 DebugOverlay, 121 is every modal, and 200 is MenuStyle's cursor tooltip — which must
## stay on top of us, not under us.
const LAYER := 149

@export var toggle_key: Key = KEY_F1
## Escape hatch for profiling a release-ish build. Leave OFF — a shipped build must carry no cheat surface.
@export var force_in_release: bool = false

@export_group("Panel")
## PREFERRED panel size in canvas pixels — an upper bound, never a promise. `_layout_panel` clamps it to the
## LIVE canvas minus `panel_offset` on all four sides and re-runs on every viewport resize, because the canvas
## is not a constant: stretch/aspect is "expand" over a 396x216 base at scale 0.5, so 792x444 at 16:9 becomes
## 792x495 on 16:10 and ~1024x432 on a 21:9 ultrawide — it never gets narrower than 792, and 432 is the
## SHORTEST it ever gets (tests/test_menu_layout_stability.gd:18-19 and docs/CURRENT_ARCHITECTURE.md pin those
## numbers). 432 minus this panel's own margins is under the 412 default below, so the clamp really does bind
## on a wide monitor — a hard-coded height that fitted the author's screen is how a panel walks off the bottom
## edge of someone else's.
## WHOLE PIXELS ONLY — in RETRO presentation the canvas is nearest-upscaled ~2.4x and a fractional metric
## rasterises into a comb (HIGH FIDELITY renders the canvas at native res, but the rule costs nothing there
## and RETRO must stay clean).
@export var panel_size: Vector2i = Vector2i(760, 412)
@export var panel_offset: Vector2i = Vector2i(16, 16)
@export var category_column_width: int = 96
## Height of the output strip at the bottom. It is a ScrollContainer with a PINNED minimum: a growing log
## Label reports its full wrapped height as its minimum and would otherwise pump the whole panel past its
## anchors (a Control that cannot fit its content GROWS — it never clips or scrolls by itself). Sized for
## roughly seven wrapped lines — the readout commands (`me`, `who`, `ledger`) print in that neighbourhood, and
## anything longer is still whole in the console, which every menu run echoes into.
@export var output_height: int = 108
@export var run_button_width: int = 88
@export var editor_width: int = 92
## Width of a cycler's `<` / `>` step button. Must leave room for the glyph INSIDE the button's own content
## margins — see _arrow_button, where pinning this too small used to erase the arrows completely.
@export var arrow_button_width: int = 18

@export_group("Text")
@export var font_size: int = 11
@export var title_font_size: int = 13
@export var title_prefix: String = "DEBUG MENU"
## Caption a `danger` row's button wears while it is armed for the confirming second click.
@export var confirm_caption: String = "confirm?"
## How long an armed danger row stays armed. The timer ignores time_scale, so the `timescale` command cannot
## stretch (or collapse) the confirm window.
@export var confirm_seconds: float = 4.0
## Shown in a cycler when the slot is OPTIONAL and currently unset — the value sent is the empty string, i.e.
## the argument is omitted entirely.
@export var blank_arg_label: String = "(none)"
@export var cycler_prev_glyph: String = "<"
@export var cycler_next_glyph: String = ">"
@export var close_glyph: String = "x"
## Scrollback cap for the output strip. Older lines are freed from the top.
@export_range(8, 2000) var max_output_lines: int = 200

@export_group("Colours")
@export var panel_color: Color = Color(0.05, 0.06, 0.08, 0.94)
@export var border_color: Color = Color(0.35, 0.85, 0.75, 0.55)
## Fill + rim of a text ARGUMENT field. There is no placeholder text in these (the argument's name is painted
## beside the field instead), so the box itself is the only thing telling you the slot is typeable.
@export var field_color: Color = Color(0.10, 0.12, 0.16, 1.0)
@export var field_border_color: Color = Color(0.35, 0.85, 0.75, 0.35)
@export var text_color: Color = Color(0.88, 0.92, 0.95)
@export var help_color: Color = Color(0.62, 0.68, 0.72)
@export var accent_color: Color = Color(0.45, 0.90, 0.80)
@export var danger_color: Color = Color(1.00, 0.55, 0.35)
@export var error_color: Color = Color(1.00, 0.45, 0.40)

@export_group("Search")
## Caption painted beside the search field. There is no placeholder_text on it for the same reason the
## argument fields have none — a placeholder vanishes the moment anything is typed, which is exactly when a
## dev is still working out what to type.
@export var search_caption: String = "find"
## The search field's own clear button. A separate knob from `close_glyph` even though both default to "x":
## they sit two rows apart and one of them throws the panel away.
@export var search_clear_glyph: String = "x"
## Painted in the title bar in place of the category name while a search is up.
@export var search_title_prefix: String = "search: "
## Painted in the empty pane when nothing matches. The query is appended to it.
@export var no_match_text: String = "no command matches "
## Where the caret lands when the panel opens. ON means F1-then-type narrows 88 commands immediately, which
## is the entire point of the field. OFF restores the older landing spot (the first category button).
##
## ⭐The trade-off is a KEYBOARD one, and it is real: while a LineEdit is editing, Up/Down are caret-to-start
## and caret-to-end (`ui_text_caret_up`/`down` are bound to the same physical keys as `ui_up`/`ui_down`), and
## `ui_focus_next`/`ui_focus_prev` are overridden to EMPTY event lists in project.godot — so there is no
## keyboard way out of the field, only the mouse. A CONTROLLER is fine: D-pad and stick up/down are joypad
## events that `ui_text_caret_*` does not carry, so they navigate out and end editing.
@export var focus_search_on_open: bool = true

@export_group("Wiring")
## OPTIONAL direct path to the DebugConsole, so the two surfaces share one transcript without a tree walk.
## Leave empty to auto-discover: the console is found DUCK-TYPED (by its echo/run_line methods), never by
## type, so this menu works fine in a scene that has no console at all.
@export var console_path: NodePath = ^""
## How deep under the SceneTree root the auto-discovery walks. 2 covers root/Game/DebugConsole and every
## autoload; deeper is pointless and would drag the 587-node level subtree into the scan.
@export_range(0, 6) var console_search_depth: int = 2

var _root: Control = null
var _panel: PanelContainer = null
var _title: Label = null
var _cats_box: VBoxContainer = null
var _rows_box: VBoxContainer = null
var _rows_scroll: ScrollContainer = null
var _out_box: VBoxContainer = null
var _out_scroll: ScrollContainer = null
var _cat_buttons: Array[Button] = []
var _first_focus: Control = null
var _search_field: LineEdit = null
## Where Enter in the search field hands the caret: the first result's first text argument, else its run
## button. Re-recorded by every rebuild, and nulled BEFORE one — holding the old handle would point at a
## queue_freed Button (the chip_install_screen.gd:165 rule).
var _first_result: Control = null

var _built := false
var _is_open := false
var _category := ""
## The live filter, already stripped. "" means "not searching" everywhere in this file: the pane shows a
## category page, the title shows its name, and one category button is lit.
var _query := ""
var _prev_mouse_mode: Input.MouseMode = Input.MOUSE_MODE_CAPTURED
var _player: Node = null
## What suspend_player() found BEFORE we froze the player; handed straight back to restore_player() on close.
var _suspend: Dictionary = {}
## The ctx[&"state"] the action modules stash toggle snapshots in (god mode's banked armor, the teleport mark,
## the saved walk speed…). Owned by this host and persisted across commands. See command_state() for how it is
## shared with the console.
var _state: Dictionary = {}
## Merged completion ids from both action modules, refreshed on open (they cache their own disk scans).
var _sources: Dictionary = {}
var _console: Node = null
## Negative cache for the discovery walk: with no console in the scene every command would otherwise re-walk
## the tree two or three times. Cleared on each open(), so a console added later is still found.
var _console_missing := false


func _ready() -> void:
	# The only per-frame work this node ever does is the cursor re-assert while OPEN (see _process). Armed in
	# open(), disarmed on every restore path — so a closed panel, and a release build, cost nothing a frame.
	set_process(false)
	# DEBUG-BUILD GATE. Nothing is built and no key is listened for in a release build, so the exported game
	# has no cheat surface — not even an invisible one that a stray keypress could reveal.
	if not OS.is_debug_build() and not force_in_release:
		set_process_input(false)
		set_process_unhandled_input(false)
		visible = false
		return
	layer = LAYER
	# The tool must survive DialogueManager's pause and FreezeFrame's hitstop — that is precisely when you
	# want to poke at the world. Every screen autoload and debug_overlay.gd do the same.
	process_mode = Node.PROCESS_MODE_ALWAYS
	# One debug surface at a time: open() closes every other member first (see open). Joined only past the
	# debug gate, so a release build never advertises one.
	add_to_group(GroupsScript.DEBUG_SURFACE)
	_build()
	_built = true
	_root.visible = false   # start hidden; the CanvasLayer itself stays visible so grab_focus can resolve


# --- public API -------------------------------------------------------------------------------------------

func is_open() -> bool:
	return _is_open


func toggle() -> void:
	if _is_open:
		close()
	else:
		open()


## Open the panel: refuse over a live modal, rebuild the pages from the registry (and from freshly gathered
## completion ids), free the mouse and freeze the player. Safe to call twice.
func open() -> void:
	if _is_open or not _built:
		return
	# ⭐REFUSE OVER A MODAL. Both screens would free the cursor and then fight over Escape; the loser restores
	# the CAPTURED cursor under a menu that is still up and leaves it unclickable. Deliberately NOT refused
	# over a dialogue: a stuck conversation is exactly what a dev opens this for, and PROCESS_MODE_ALWAYS keeps
	# us alive under its pause — with _process re-asserting the free cursor that DialogueManager keeps taking
	# back (HIDDEN mid-line, CAPTURED on _finish).
	if InputManager.any_modal_open():
		# Reported through _print_lines, NOT _echo_to_console: with no console in the scene the echo goes nowhere
		# and the key reads as dead. The strip is this panel's own scrollback, so the reason is waiting the next
		# time it does open — and _print_lines still forwards to the console when there is one.
		var refusal := "debug menu refused: a modal screen is open"
		_print_lines(PackedStringArray([refusal]))
		return
	# ⭐ONE DEBUG SURFACE AT A TIME. The console holds its own suspend_player snapshot; nesting the two restores
	# them in close order, and the wrong order unfreezes the player under a still-open panel (clicks fire the
	# weapon) or re-freezes them with nothing on screen. Closing it FIRST means its restore lands before our
	# suspend reads the player, so the snapshots can never interleave.
	for surface in get_tree().get_nodes_in_group(GroupsScript.DEBUG_SURFACE):
		if surface != self and is_instance_valid(surface) \
				and surface.has_method(&"is_open") and surface.has_method(&"close") \
				and bool(surface.call(&"is_open")):
			surface.call(&"close")
	_is_open = true
	_console_missing = false
	_sources = _gather_sources()
	if _category == "":
		var cats := DebugCommandsScript.categories()
		_category = String(cats[0]) if cats.size() > 0 else ""
	# NOT _show_category: that CLEARS a live search, and the query is meant to survive a close/open exactly
	# the way the selected category does. The field still shows it, and the title still counts it.
	_refresh_rows()
	_prev_mouse_mode = ModalMenu.grab_mouse(false)   # cues OFF: a dev tool must not fire the menu stings
	# THE PLAYER FREEZE. Freeing the cursor already killed mouse-look and pad-look (both gate on
	# MOUSE_MODE_CAPTURED) but NOT firing: Attack is polled every frame and gated only on
	# gameplay_suppressed(), which we are deliberately outside of. Without this, every click on a button in
	# this panel also pulls the trigger.
	_player = GroupsScript.human_player(get_tree())
	if is_instance_valid(_player):
		_suspend = DebugActionsPlayerScript.suspend_player(_player)
	_root.visible = true
	# grab_focus on a HIDDEN Control silently does nothing, and grabbing in the same frame as the opening
	# keystroke lets that key land in the panel — so seed focus DEFERRED, after the card is visible.
	call_deferred(&"_seed_focus")
	set_process(true)   # arms the cursor re-assert below, and only while we are actually up


func close() -> void:
	if not _is_open:
		return
	_is_open = false
	if is_instance_valid(_root):
		_root.visible = false
	_restore_world()


## Hand back everything open() took from the running game: the player's own process callbacks and the cursor.
## Split out of close() because it is ALSO the teardown path — see _exit_tree, which is the only thing standing
## between a panel freed while open and a permanently frozen player.
func _restore_world() -> void:
	set_process(false)
	# Restore EXACTLY what suspend_player found, onto the EXACT body we froze — never a re-resolved one. The
	# player may have been freed under us by a level swap or a reload command, in which case there is nothing to
	# restore and nothing to leak. is_instance_valid FIRST: any method call on a freed instance crashes.
	if is_instance_valid(_player) and not _suspend.is_empty():
		DebugActionsPlayerScript.restore_player(_player, _suspend)
	_suspend = {}
	_player = null
	ModalMenu.restore_mouse(_prev_mouse_mode, false)


## THE TEARDOWN SAFETY NET (the same one debug_console.gd:253 carries). `reload` and `load` both end in
## get_tree().reload_current_scene(), which frees the whole current scene — this panel with it — so close() is
## never reached and the suspension it owes the player is never paid back. That specific case self-heals (the
## fresh MouseInput._ready re-captures the cursor, mouse_input.gd:27-28, and the old Player dies with the
## scene); this exists for the ones that do NOT, i.e. anything that removes only this node — a designer
## deleting it in the remote inspector, a reparent, an editor-driven swap — while the Player survives beside it.
func _exit_tree() -> void:
	# Unwind every shared-tuning override banked in OUR OWN state dict (speed base, god fall-timer, timescale
	# allow flag) — but only when this menu is the dict's owner, i.e. there is no console in the scene. When a
	# console exists the dict is ITS `_state` and its own _exit_tree does this; both releases are idempotent, so a
	# double call would be harmless, but the ownership rule keeps the reasoning simple. See the console for why
	# a teardown unwind is load-bearing (death reloads / F9 free us without ever passing through close()).
	if _built and is_inside_tree() and _find_console() == null and not _state.is_empty():
		var ctx := {&"tree": get_tree(), &"player": null, &"host": self, &"state": _state}
		DebugActionsWorldScript.release_scene_scoped_state(ctx)
		DebugActionsPlayerScript.release_scene_scoped_state(ctx)
	if not _is_open:
		return
	_is_open = false
	_restore_world()


## Keep the cursor free for as long as the panel is up. The ONE per-frame job this node has.
##
## ⭐DialogueManager rewrites Input.mouse_mode behind our back: `_sync_dialogue_cursor` sets HIDDEN while a line
## is being read and VISIBLE while the choice menu is up (dialogue_manager.gd:658-665), and `_finish` slams
## CAPTURED when the conversation ends (:652). This panel deliberately does NOT refuse to open over a
## conversation (see open()), so without this re-assert simply advancing a line under it leaves the card up with
## a HIDDEN pointer — visible buttons, nothing to aim a click with. Re-asserting beats latching three dialogue
## signals, and it is armed only between open() and _restore_world().
##
## `_prev_mouse_mode` is deliberately NOT re-read here: it is the mode from BEFORE we opened, and close() still
## owes exactly that value back.
func _process(_delta: float) -> void:
	if _is_open and Input.mouse_mode != Input.MOUSE_MODE_VISIBLE:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


## The command state dictionary handed to the action modules as ctx[&"state"]. Exposed so the console and this
## menu can be pointed at the SAME Dictionary (they are reference types) — otherwise `god on` clicked here and
## `god off` typed there would look at two different snapshots and strand the banked armour value. This menu
## adopts the console's dictionary automatically when the console exposes a method of this name, so this
## delegates to the SAME resolver _ctx() uses — publishing our private `_state` here while the actions were
## handed the console's would be a second, silently divergent answer to the same question.
func command_state() -> Dictionary:
	return _shared_state()


# --- input ------------------------------------------------------------------------------------------------

## Toggle on a RAW dev keycode (never a rebindable action — that would drag in the four keybind name-surfaces
## and generate a player-facing Options row). Key echoes are ignored and the press is CONSUMED, so it cannot
## also reach the hotbar, OptionsMenu, or type itself into a field.
func _input(event: InputEvent) -> void:
	if not (event is InputEventKey):
		return
	var key := event as InputEventKey
	if not key.pressed or key.echo:
		return
	if key.keycode == toggle_key:
		toggle()
		get_viewport().set_input_as_handled()
		return
	# ⭐ESCAPE IS HANDLED HERE, IN _input, NOT IN _unhandled_input — the console already learnt this
	# (debug_console.gd:1007). Since Godot 4.4 a LineEdit has an explicit EDITING state and a field that is
	# being typed into CONSUMES ui_cancel to leave it, marking the event handled: an Escape aimed at this
	# panel never reached _unhandled_input at all while the caret sat in an argument field, and with a search
	# bar seeded on open that would have been EVERY first Escape. _input runs ahead of the GUI layer, so
	# consuming it here also means the field never leaves editing — which matters, because a LineEdit that is
	# focused but NOT editing passes printable keys straight through to gameplay.
	# Consumed either way, so OptionsMenu does not open behind us.
	if _is_open and key.is_action_pressed(&"ui_cancel"):
		# A live filter is the first thing Escape takes away, the panel the second — the search-box idiom, and
		# it keeps the one key that gets you out of a wrong filter from also throwing the panel away.
		if _query != "":
			_clear_search()
		else:
			close()
		get_viewport().set_input_as_handled()


# --- construction -----------------------------------------------------------------------------------------

## Build the whole panel in code. Layout: header / [category column | row pane] / output strip.
## Every growable region lives in a ScrollContainer with a pinned minimum and horizontal scrolling DISABLED,
## which is what stops the panel growing past its anchors when a long help string or output line arrives.
##
## ⭐PROSE WRAPS, CHROME CLIPS. Two different Label factories on purpose, and mixing them up is the bug this
## panel shipped with: everything that carries READABLE TEXT (a command's help line, an output line) is a
## `_wrap_label` — autowrapped, never truncated — while fixed chrome whose text is already known short (the
## title, a button caption, a cycler's current value) stays `_label`, i.e. clip_text + ellipsis so it cannot
## widen the layout. Built the other way round, every help string in the registry rendered as
## "Immunity: banks armor_flat AND zeroes the continuous-fall de…" with no wrap, no tooltip and no horizontal
## scrollbar anywhere — the help text was simply unreadable, which is most of what this panel is FOR.
func _build() -> void:
	_root = Control.new()
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# An INTERACTIVE overlay departs from the read-only-overlay convention (every DebugOverlay/player_hud
	# Control is MOUSE_FILTER_IGNORE): STOP on the root so a click on the panel — or beside it — can never
	# fall through to gameplay. Every readout Label below stays IGNORE.
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_root)

	_panel = PanelContainer.new()
	_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	# ⭐THE LAST-RESORT BACKSTOP. Every slot below already keeps an honest minimum, but a Control that cannot
	# fit its content GROWS — it never clips by itself — so one mis-sized child would otherwise paint past the
	# panel and off the canvas with no way to reach it. clip_contents makes "off the panel" impossible by
	# construction; anything that overflows is caught by its own ScrollContainer instead.
	_panel.clip_contents = true
	_panel.add_theme_stylebox_override(&"panel", _panel_style())
	_root.add_child(_panel)
	_layout_panel()
	# The canvas is not a constant (stretch aspect "expand"), and this node lives in game.tscn across every
	# level swap and every windowed/fullscreen toggle — so re-clamp on the viewport's own signal rather than
	# trusting the size that happened to be live when _ready ran.
	var vp := get_viewport()
	if vp != null and not vp.size_changed.is_connected(_layout_panel):
		vp.size_changed.connect(_layout_panel)

	var col := VBoxContainer.new()
	col.add_theme_constant_override(&"separation", 4)
	_panel.add_child(col)

	var head := HBoxContainer.new()
	head.add_theme_constant_override(&"separation", 6)
	col.add_child(head)
	_title = _label("", title_font_size, accent_color)
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(_title)
	var close_btn := _button(close_glyph)
	close_btn.custom_minimum_size = Vector2(18, 0)
	close_btn.pressed.connect(close)
	head.add_child(close_btn)

	# ⭐THE SEARCH BAR, and note WHERE it is: in the panel's own column, ABOVE the body — never inside
	# `_rows_box`. Filtering rebuilds every row, and a field that lived among them would free itself, and the
	# caret with it, on its own first keystroke.
	var find_row := HBoxContainer.new()
	find_row.add_theme_constant_override(&"separation", 4)
	col.add_child(find_row)
	# A caption Label, not placeholder_text: see _make_line_edit for why this panel has no placeholders, and
	# the file header for why it can have no tooltips.
	find_row.add_child(_tag_label(search_caption))
	_search_field = _make_line_edit()
	_search_field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# text_changed, so the pane narrows AS YOU TYPE. The engine emits it deferred and coalesced — several
	# keystrokes in one frame arrive as a single emission carrying the final text — so this is at most one
	# rebuild per frame however fast anyone types.
	_search_field.text_changed.connect(_on_search_changed)
	_search_field.text_submitted.connect(_on_search_submitted)
	find_row.add_child(_search_field)
	# ⭐NOT `_button()`. A glyph-sized plain Button draws NOTHING under the default theme's ~8 px content
	# margins — that is the bug that erased both cycler arrows (see _arrow_button), and _arrow_button is
	# already this panel's answer for a button the size of one character.
	var clear_btn := _arrow_button(search_clear_glyph)
	# ⭐FOCUS_NONE, by this file's own rule (see _make_cycler): a focusable button beside a text field steals
	# the caret on the click. Here that is worse than for a cycler — clicking clear would empty the box AND
	# take the cursor out of it, so the next thing typed goes nowhere, on the one panel whose headline is
	# "F1 and type". Nothing is lost by making it unfocusable: `ui_focus_next` is bound to an EMPTY event list
	# project-wide, so no keyboard route to this button existed anyway, and Escape already clears.
	clear_btn.focus_mode = Control.FOCUS_NONE
	clear_btn.pressed.connect(_clear_search)
	find_row.add_child(clear_btn)

	var body := HBoxContainer.new()
	body.add_theme_constant_override(&"separation", 6)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(body)

	var cats_scroll := ScrollContainer.new()
	cats_scroll.custom_minimum_size = Vector2(category_column_width, 0)
	cats_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	cats_scroll.follow_focus = true
	cats_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(cats_scroll)
	_cats_box = VBoxContainer.new()
	_cats_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_cats_box.add_theme_constant_override(&"separation", 2)
	cats_scroll.add_child(_cats_box)

	_rows_scroll = ScrollContainer.new()
	_rows_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_rows_scroll.follow_focus = true   # pad navigation down the run buttons scrolls the pane with it
	_rows_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_rows_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(_rows_scroll)
	_rows_box = VBoxContainer.new()
	_rows_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_rows_box.add_theme_constant_override(&"separation", 4)
	_rows_scroll.add_child(_rows_box)

	_out_scroll = ScrollContainer.new()
	_out_scroll.custom_minimum_size = Vector2(0, output_height)
	_out_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	col.add_child(_out_scroll)
	_out_box = VBoxContainer.new()
	_out_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_out_box.add_theme_constant_override(&"separation", 0)
	_out_scroll.add_child(_out_box)
	# ⭐PIN ON `resized`, not only on a deferred call. A wrapped Label does not know its own HEIGHT until it has
	# been given a width, so at the end of the frame a command was clicked the scrollbar's max_value is still
	# the pre-print value and a deferred "scroll to the end" lands short — a 15-line `me` dump would show its
	# first six lines and silently hide the rest. `resized` fires once the new rows really have a size.
	# (debug_console.gd wires _log_box.resized to its own _pin_to_bottom for exactly this reason.)
	_out_box.resized.connect(_scroll_output_to_end)

	_build_categories()


## Place the card at `panel_offset` and size it to `panel_size` CLAMPED to what the live canvas actually has
## room for, so the bottom and right edges are always on screen. Re-run on every viewport resize.
##
## `custom_minimum_size` is set alongside `size` because the panel is a free Control (its parent is the plain
## full-rect `_root`, not a container): without a minimum it would shrink to its content, and with a minimum
## LARGER than the clamp it would push its own bottom edge back off the canvas — the clamp has to win both ways.
func _layout_panel() -> void:
	if not is_instance_valid(_panel) or not is_inside_tree():
		return
	var canvas: Vector2 = get_viewport().get_visible_rect().size
	var margin := Vector2(panel_offset)
	# floor()ed to whole pixels: the canvas is nearest-upscaled, and a half-pixel panel edge combs.
	var avail := (canvas - margin * 2.0).floor()
	var want := Vector2(panel_size)
	var chosen := Vector2(minf(want.x, avail.x), minf(want.y, avail.y)).floor()
	# A canvas smaller than the margins themselves (never real, but a 1x1 headless viewport reaches here)
	# must not produce a negative size.
	chosen = chosen.max(Vector2(64.0, 64.0))
	_panel.position = margin
	_panel.custom_minimum_size = chosen
	_panel.size = chosen


## One button per registry category, in the registry's own display order. Built once — the category list is
## stable, only the right pane is swapped.
func _build_categories() -> void:
	for cat in DebugCommandsScript.categories():
		var name_s := String(cat)
		var btn := _button(name_s)
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.pressed.connect(_on_category_pressed.bind(name_s))
		_cats_box.add_child(btn)
		_cat_buttons.append(btn)
		if _first_focus == null:
			# ⭐SEEDED FOCUS OWNER. A screen where nothing grabs focus is entirely unreachable on a controller
			# — this project shipped exactly that bug once (atm_screen.gd:39-43). The first category button is
			# the landing spot; from there ui_right/ui_down reaches every row.
			_first_focus = btn


func _on_category_pressed(cat: String) -> void:
	_show_category(cat)


## Swap the right pane to `cat`. Rows are rebuilt from the registry every time (cheap — tens of rows) so a
## freshly gathered id source is picked up without any invalidation bookkeeping.
##
## Picking a page is also how you LEAVE a search: the pane can only show one of the two, and a category click
## that left the filter running would paint rows the search field claims are hidden.
func _show_category(cat: String) -> void:
	_category = cat
	if _query != "":
		_query = ""
		if is_instance_valid(_search_field):
			# ⭐Assigning `.text` FROM CODE EMITS NOTHING — verified on 4.7.1: only typing emits text_changed,
			# and `clear()` (which does emit) would re-enter the handler synchronously from inside a button
			# press. So the _refresh_rows below is not belt-and-braces: without it the field goes blank while
			# the pane keeps painting the results of the query that is no longer there.
			_search_field.text = ""
	_refresh_rows()


## Repaint the right-hand pane from whichever source is current: the search results while a query is live,
## the selected category otherwise. THE one place rows are built, so the title, the category buttons and the
## pane itself can never disagree about what is on screen.
func _refresh_rows() -> void:
	# A text_changed emission is DEFERRED, and it still arrives after the field has been pulled out of the
	# tree — so this can be reached with nothing left to paint at.
	if not is_instance_valid(_rows_box) or not is_instance_valid(_title):
		return
	var searching := _query != ""
	# Plain `Array`, not `Array[Dictionary]`: the registry is preloaded BY PATH and left untyped (see the
	# consts at the top of this file), so every call through it is a Variant as far as this file is concerned.
	var rows: Array = []
	if searching:
		rows = DebugCommandsScript.search(_query)
	else:
		rows = DebugCommandsScript.in_category(_category)

	_title.text = _heading(searching, rows.size())
	for btn in _cat_buttons:
		if is_instance_valid(btn):
			# While a search is up NO page is current — the rows on screen are drawn from all of them, and a
			# lit button would be claiming otherwise.
			var lit := not searching and btn.text == _category
			btn.add_theme_color_override(&"font_color", accent_color if lit else text_color)

	# ⭐WHO HOLDS FOCUS. Freeing the focus owner leaves the viewport with NO owner and emits no signal at all,
	# so a rebuild that ate the focused row silently kills keyboard and pad navigation for the rest of the
	# session. Read the owner BEFORE the teardown and re-seat after — but ONLY when it was one of the rows
	# about to die (or was already nothing), never when it is the search field someone is mid-word in. That
	# is exactly why the field is built outside `_rows_box`. Same guard as implants_screen.gd:232 and
	# level_up_screen.gd:213.
	var owner_before: Control = null
	if is_inside_tree():
		owner_before = get_viewport().gui_get_focus_owner()
	var rows_had_focus := owner_before != null and _rows_box.is_ancestor_of(owner_before)
	_first_result = null   # re-recorded by _add_row below; the old handle is about to be queue_freed

	# remove_child BEFORE queue_free: queue_free is deferred, so the old rows would still be in the box while
	# the new ones are appended and the pane would show both for a frame.
	for child in _rows_box.get_children():
		_rows_box.remove_child(child)
		child.queue_free()
	for row in rows:
		_add_row(row, searching)
	if searching and rows.is_empty():
		# The pane has to SAY it is empty. A query that matched nothing and a pane that failed to build look
		# identical when both paint no rows, and there is no tooltip on this panel to explain either.
		var none := _wrap_label(no_match_text + _query, font_size, help_color)
		# EXPAND_FILL or the ScrollContainer lays it out at its minimum, i.e. one word per line.
		none.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_rows_box.add_child(none)
	if is_instance_valid(_rows_scroll):
		_rows_scroll.scroll_vertical = 0
	if owner_before == null or rows_had_focus:
		_reseat_focus()


## The title bar: which surface this is, the key that opens it, and what the pane is showing. While a search
## is up the COUNT comes first — it is the only feedback that the query narrowed anything, and this Label is
## a clipped one, so anything at the end can be ellipsised away by a long query.
func _heading(searching: bool, count: int) -> String:
	var head := title_prefix + "  [" + OS.get_keycode_string(toggle_key) + "]  "
	if not searching:
		return head + _category
	return head + "(" + str(count) + ")  " + search_title_prefix + _query


## Put the caret back after a rebuild dropped it — and only then. Called under a guard that already proved
## the rebuild left nobody holding focus, and it re-checks here because grabbing unconditionally would yank
## the caret out of the search field mid-word. The landing spot is the search field when there is one (it is
## the panel's home base now), else the first category button, which is where a controller has always landed.
func _reseat_focus() -> void:
	if not _is_open or not is_inside_tree():
		return
	if get_viewport().gui_get_focus_owner() != null:
		return
	if is_instance_valid(_search_field) and _search_field.is_visible_in_tree():
		_search_field.grab_focus()
	elif is_instance_valid(_first_focus) and _first_focus.is_visible_in_tree():
		_first_focus.grab_focus()


# --- search bar -------------------------------------------------------------------------------------------

func _on_search_changed(new_text: String) -> void:
	_set_query(new_text)


## Enter in the search field hands the caret to the first result rather than RUNNING it. A filtered list is
## exactly where a stray Enter fires the wrong command — `kill` and `killall` sit one row apart in a short
## one — and search() already ranks an exact name match first, so this lands on the row that was meant. It
## lands on that row's first TEXT argument when it has one, because that is where the next keystroke belongs.
func _on_search_submitted(text: String) -> void:
	# ⭐APPLY THE FIELD FIRST, and note that this is not redundant with text_changed. text_submitted is emitted
	# SYNCHRONOUSLY from the LineEdit's gui_input while text_changed is DEFERRED, and the engine dispatches a
	# whole input flush back to back — so when the last character and the Enter arrive in the same flush, THIS
	# runs before that character's own _on_search_changed and `_first_result` still points into the previous
	# query's rows. Rebuilding here means Enter always lands in the list the field is describing; the deferred
	# text_changed then arrives carrying the same text and _set_query early-outs on it.
	_set_query(text)
	if is_instance_valid(_first_result) and _first_result.is_visible_in_tree():
		_first_result.grab_focus()


## THE one place the query changes. The field, the clear button and Escape all route through here, so the
## pane, the title and the category buttons cannot drift from what the field says.
func _set_query(text: String) -> void:
	var trimmed := text.strip_edges()
	if trimmed == _query:
		# A keystroke that only added or removed surrounding whitespace narrows nothing, and rebuilding the
		# pane for it would throw away the scroll position for free.
		return
	_query = trimmed
	_refresh_rows()


## Empty the field and fall back to the current category page. Wired to the clear button AND to Escape.
func _clear_search() -> void:
	if is_instance_valid(_search_field):
		_search_field.text = ""   # emits nothing (see _show_category) — the refresh below is the real work
	if _query == "":
		return
	_query = ""
	_refresh_rows()


## One registry row: a RUN button carrying the command name, its help line, and — when the command takes
## arguments — a second line of inline argument editors.
##
## `show_page` is on for SEARCH RESULTS only: those are drawn from every category at once, so each row has to
## say which page it normally lives on. A category page never needs it — every row on it is from that page.
func _add_row(row: Dictionary, show_page: bool = false) -> void:
	var name_s := String(row["name"])
	var kinds: Array = row["args"]
	var arg_names: Array = row["arg_names"]
	var min_args := int(row["min_args"])
	var danger := bool(row["danger"])

	# Decided BEFORE any widget is built, because it changes the arrow buttons' focus mode for the whole row.
	var has_text_field := false
	for i in kinds.size():
		if _editor_items(int(kinds[i]), row).is_empty():
			has_text_field = true

	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override(&"separation", 2)

	var head := HBoxContainer.new()
	head.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_theme_constant_override(&"separation", 6)
	var run := _button(name_s)
	run.custom_minimum_size = Vector2(run_button_width, 0)
	run.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	if danger:
		run.add_theme_color_override(&"font_color", danger_color)
	run.set_meta(&"debug_caption", name_s)   # the caption to restore after a confirm arm expires
	head.add_child(run)
	if show_page:
		# Unclipped `_tag_label`, never `_label`: clip_text collapses a Label's minimum WIDTH to ~0, and a
		# non-expanding caption in an HBox then gets exactly zero pixels (the ⭐ further down this function).
		var page := _tag_label(String(row["category"]))
		page.add_theme_color_override(&"font_color", accent_color)
		head.add_child(page)
	# The help line is the payload of this whole panel, so it WRAPS: the registry's longest strings run past
	# 200 characters (`brain`, `npc`, `bind`) and a one-line slot could only ever show the first third of them.
	var help := _wrap_label(String(row["help"]), font_size, help_color)
	help.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(help)
	box.add_child(head)

	var editors: Array = []
	if kinds.size() > 0:
		# HFlowContainer, not HBox: a three-argument row (`soak`, `advance`) is wider than the pane on a narrow
		# canvas, and a flow container puts the overflow on a SECOND LINE where an HBox would squeeze every
		# editor toward zero width and shove the last one out of the panel.
		var args_row := HFlowContainer.new()
		args_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		args_row.add_theme_constant_override(&"h_separation", 8)
		args_row.add_theme_constant_override(&"v_separation", 2)
		for i in kinds.size():
			var arg_label := String(arg_names[i]) if i < arg_names.size() else ""
			# Name and widget travel as ONE flow item so a wrap can never leave the caption on the line above
			# its own editor.
			var slot := HBoxContainer.new()
			slot.add_theme_constant_override(&"separation", 4)
			# ⭐NOT _label(): clip_text collapses a Label's minimum width to ~0, and in an HBox that gives a
			# non-expanding caption exactly zero pixels. Every argument name in this panel used to render as
			# nothing at all for that reason — the widgets sat in an unlabelled row.
			slot.add_child(_tag_label(arg_label))
			# `required` decides whether the cycler carries a leading blank entry: an OPTIONAL slot must be
			# able to say "omit me", because validate() rejects an empty word for a TOGGLE/VERB slot.
			var editor := _make_editor(int(kinds[i]), row, i < min_args, not has_text_field)
			editors.append(editor)
			slot.add_child(editor)
			args_row.add_child(slot)
			if editor is LineEdit:
				# Enter in any field runs the row — the console reflex, and the only way to commit without
				# reaching for the mouse while the caret is in a field. `editors` is still being filled here,
				# which is fine: an Array is a REFERENCE type, so the bound handle sees every later slot too.
				(editor as LineEdit).text_submitted.connect(_on_arg_submitted.bind(name_s, editors, run))
		box.add_child(args_row)

	# Bound METHOD Callables, never capturing lambdas: a lambda that captured a freed node errors before any
	# guard inside it can run (the project's lambda-freed-capture rule).
	run.pressed.connect(_on_run_pressed.bind(name_s, editors, run))
	# Where Enter in the search field will hand the caret. The row's first TEXT argument if it has one — the
	# next keystroke belongs in the field, not on the button — else the run button itself. Only the FIRST row
	# of a rebuild records it; `_refresh_rows` nulls it before the rows are torn down.
	if _first_result == null:
		var landing: Control = run
		for editor in editors:
			if editor is LineEdit:
				landing = editor
				break
		_first_result = landing
	_rows_box.add_child(box)


# --- argument editors -------------------------------------------------------------------------------------

## The words a cycler would offer for this argument slot, or EMPTY when the slot has no enumeration and must
## fall back to a free-text LineEdit. One function so the "is this a text field?" pre-pass and the actual
## widget construction can never disagree.
func _editor_items(kind: int, row: Dictionary) -> PackedStringArray:
	if kind == DebugCommandsScript.Kind.TOGGLE:
		return PackedStringArray(DebugCommandsScript.TOGGLE_WORDS)
	if kind == DebugCommandsScript.Kind.VERB:
		return PackedStringArray(row["verbs"])
	# Every id-valued Kind (ITEM/NPC/LEVEL/QUEST/FACTION/PERK/EFFECT/FLAG/STAT/COMMAND) is keyed in
	# SOURCE_KEYS; the live list comes from the action modules' sources(). An EMPTY source is normal — the
	# project authors essentially zero story flags, for instance — and degrades to a LineEdit rather than to a
	# cycler with nothing in it.
	if DebugCommandsScript.SOURCE_KEYS.has(kind):
		var key: StringName = DebugCommandsScript.SOURCE_KEYS[kind]
		if _sources.has(key):
			return PackedStringArray(_sources[key])
	return PackedStringArray()


## The registry's own arg_names entry is NOT passed down here any more: _add_row paints it as a caption Label
## beside whatever this returns (a cycler has no placeholder mechanism, so that caption had to exist for those
## rows regardless), and a LineEdit repeating it printed the same word twice.
func _make_editor(kind: int, row: Dictionary, required: bool, arrows_focusable: bool) -> Control:
	var items := _editor_items(kind, row)
	if items.is_empty():
		return _make_line_edit()
	if not required:
		var with_blank := PackedStringArray([""])
		with_blank.append_array(items)
		items = with_blank
	return _make_cycler(items, arrows_focusable)


## The project's in-canvas `< value >` cycler (options_menu.gd:_option_row), rebuilt here without MenuStyle so
## it carries no auto-wired sound. NO OptionButton: its PopupMenu would be a native OS window.
## `arrows_focusable` is false for a row that also contains a LineEdit — a focusable button beside a text
## field steals the caret on Tab or on a click (name_entry_dialog.gd:138). Rows with no field keep their
## arrows focusable so the values stay reachable on a controller.
func _make_cycler(items: PackedStringArray, arrows_focusable: bool) -> Control:
	var box := HBoxContainer.new()
	box.add_theme_constant_override(&"separation", 2)
	# Annotated with the ENUM type, not int: GDScript will not narrow a plain int back into Control.FocusMode.
	var focus: Control.FocusMode = Control.FOCUS_ALL if arrows_focusable else Control.FOCUS_NONE

	var prev := _arrow_button(cycler_prev_glyph)
	prev.focus_mode = focus
	box.add_child(prev)

	var value := _label("", font_size, text_color)
	value.custom_minimum_size = Vector2(editor_width, 0)
	value.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(value)

	var next := _arrow_button(cycler_next_glyph)
	next.focus_mode = focus
	box.add_child(next)

	# The selection rides in metadata on the row box (the options_menu `cycle_index` idiom) so the whole
	# widget is one Control the collector can read with no extra bookkeeping.
	box.set_meta(&"debug_items", items)
	box.set_meta(&"debug_index", 0)
	box.set_meta(&"debug_value_label", value)
	prev.pressed.connect(_cycle.bind(-1, box))
	next.pressed.connect(_cycle.bind(1, box))
	_paint_cycler(box)
	return box


func _cycle(dir: int, box: Control) -> void:
	if not is_instance_valid(box):
		return
	var items: PackedStringArray = box.get_meta(&"debug_items", PackedStringArray())
	var n := items.size()
	if n == 0:
		return
	var idx: int = (int(box.get_meta(&"debug_index", 0)) + dir + n) % n
	box.set_meta(&"debug_index", idx)
	_paint_cycler(box)


func _paint_cycler(box: Control) -> void:
	var label_v: Variant = box.get_meta(&"debug_value_label", null)
	# is_instance_valid FIRST, always: `is` CRASHES on a freed instance, and a rebuilt page frees these.
	if not is_instance_valid(label_v):
		return
	if not (label_v is Label):
		return
	var items: PackedStringArray = box.get_meta(&"debug_items", PackedStringArray())
	var idx: int = int(box.get_meta(&"debug_index", 0))
	var word := items[idx] if idx >= 0 and idx < items.size() else ""
	# The blank entry MEANS "omit this argument"; it needs a visible caption without becoming one.
	(label_v as Label).text = word if word != "" else blank_arg_label


## No placeholder: _add_row paints the argument's name in a caption Label beside the field, and a placeholder
## repeating it doubled the word on every text row ("amount [amount]"). The caption is also the more honest of
## the two — a placeholder vanishes the moment anything is typed. NO tooltip_text either: see the file header
## (embed_subwindows=false makes every Godot tooltip its own OS window, outside the 792x444 canvas).
func _make_line_edit() -> LineEdit:
	var field := LineEdit.new()
	field.custom_minimum_size = Vector2(editor_width, 0)
	# Two non-obvious project contracts, kept even for a dev field so the scene tests' expectations hold
	# everywhere: typed text must never become a translation msgid, and the engine's right-click context menu
	# is untranslatable English.
	field.auto_translate_mode = Control.AUTO_TRANSLATE_MODE_DISABLED
	field.context_menu_enabled = false
	field.add_theme_font_size_override(&"font_size", font_size)
	field.add_theme_color_override(&"font_color", text_color)
	field.add_theme_color_override(&"caret_color", accent_color)
	# An EMPTY field needs a visible box of its own now that the placeholder is gone — the engine's default
	# LineEdit box is nearly invisible against this panel, and an unstyled empty slot reads as a gap in the row
	# rather than as somewhere to type. Same box on `focus` as on `normal`: a focus ring would fight the
	# caret, which is already the focus tell (debug_console.gd:_field_box does exactly this).
	var box := StyleBoxFlat.new()
	box.bg_color = field_color
	box.border_color = field_border_color
	box.set_border_width_all(1)
	box.content_margin_left = 4.0
	box.content_margin_right = 4.0
	box.content_margin_top = 2.0
	box.content_margin_bottom = 2.0
	field.add_theme_stylebox_override(&"normal", box)
	field.add_theme_stylebox_override(&"focus", box)
	return field


## Read a built editor back as the argument WORD to send. "" means the slot is unset.
##
## Takes the slot UNTYPED on purpose. `editors` is captured in a bound Callable that outlives nothing in
## practice (a category swap frees the run button and its editors together), but the project's hard rule is
## is_instance_valid BEFORE any `is`/`as` — and a cast at the CALL SITE would run before this guard could.
## So the validity test happens here, ahead of the cast, and a freed slot degrades to "unset".
func _widget_value(editor: Variant) -> String:
	if not is_instance_valid(editor):
		return ""
	# Annotated, never `:=` off a Variant — inferring a type from an untyped value is this repo's most common
	# parse failure (cf. debug_actions_player.gd:106-109, which annotates for the same reason).
	var control: Control = editor as Control
	if control == null:
		return ""
	if control is LineEdit:
		return (control as LineEdit).text.strip_edges()
	if control.has_meta(&"debug_items"):
		var items: PackedStringArray = control.get_meta(&"debug_items", PackedStringArray())
		var idx: int = int(control.get_meta(&"debug_index", 0))
		if idx >= 0 and idx < items.size():
			return items[idx]
	return ""


# --- running ----------------------------------------------------------------------------------------------

func _on_arg_submitted(_text: String, cmd_name: String, editors: Array, btn: Button) -> void:
	# text_submitted passes the field's text and .bind() APPENDS our arguments after it. The text itself is
	# ignored: _collect_args re-reads every editor, so there is ONE source of truth for the argv.
	_on_run_pressed(cmd_name, editors, btn)


func _on_run_pressed(cmd_name: String, editors: Array, btn: Button) -> void:
	# `btn` is the row's RUN button, which is the emitter on the click path but only a BOUND reference on the
	# Enter-in-a-field path — so validate it before every meta read below (a freed instance crashes on access).
	if not is_instance_valid(btn):
		return
	var row: Dictionary = DebugCommandsScript.find(cmd_name)
	if row.is_empty():
		return
	# ⭐DESTRUCTIVE ROWS TAKE TWO CLICKS. `danger` marks the commands you cannot walk back from the console
	# (respec, load) — the first click only arms the button, and it disarms itself after confirm_seconds so a
	# forgotten arm can never be triggered by a later stray click.
	if bool(row["danger"]) and not bool(btn.get_meta(&"debug_armed", false)):
		_arm(btn)
		return
	_disarm(btn)
	var collected := _collect_args(row, editors)
	var problem := String(collected["error"])
	if problem != "":
		_print_lines(PackedStringArray([cmd_name + ": " + problem]))
		return
	var args: PackedStringArray = collected["args"]
	_run(row, args)


## Compose the editors into an argv. Arguments are POSITIONAL, so a blank slot can only ever be a TRAILING
## one; a blank with a filled slot after it is reported rather than silently shifting every later argument
## into the wrong position.
func _collect_args(row: Dictionary, editors: Array) -> Dictionary:
	var arg_names: Array = row["arg_names"]
	var raw := PackedStringArray()
	for i in editors.size():
		raw.append(_widget_value(editors[i]))   # untyped on purpose — _widget_value validates before it casts
	var last := -1
	for i in raw.size():
		if raw[i] != "":
			last = i
	var out := PackedStringArray()
	for i in range(last + 1):
		if raw[i] == "":
			var nm := String(arg_names[i]) if i < arg_names.size() else str(i + 1)
			return {"args": out, "error": "argument \"" + nm + "\" is empty but a later one is set"}
		out.append(raw[i])
	return {"args": out, "error": ""}


## Validate, then dispatch on the row's `mod` — the same route the console takes, so a command behaves
## identically whichever surface fired it. Actions are trusted to return their own failure lines rather than
## pushing errors, so there is nothing to catch here.
func _run(row: Dictionary, args: PackedStringArray) -> void:
	var cmd := String(row["name"])
	var echoed := cmd
	if args.size() > 0:
		echoed += " " + " ".join(args)
	var invalid := String(DebugCommandsScript.validate(row, args))
	if invalid != "":
		_print_lines(PackedStringArray(["> " + echoed, "  " + invalid]))
		return
	var mod: StringName = row["mod"]
	var lines := PackedStringArray()
	match mod:
		&"player":
			lines = DebugActionsPlayerScript.run(cmd, _ctx(), args)
		&"world":
			lines = DebugActionsWorldScript.run(cmd, _ctx(), args)
		_:
			lines = _run_meta(cmd, args)
	var out := PackedStringArray(["> " + echoed])
	out.append_array(lines)
	_print_lines(out)


## `meta` rows belong to the console (they need its scrollback), so this menu answers the three it CAN against
## its OWN output strip, and FORWARDS every other meta row (`exec`, `bind`, whatever lands next) to the console —
## those need its exec queue / key table, which only it has. Forwarded duck-typed through _find_console(), so
## with no console in the scene the row still answers with a reason instead of a dead button.
## Preferred route: the console's run_meta(cmd, args) — the argv is already validated by _run, and the LINES come
## back to be painted HERE (this panel's user has the console closed, by the one-surface rule, so a "look at the
## console" pointer would leave a `bind` listing somewhere they cannot see); _print_lines echoes them into the
## console too, so both transcripts agree. Fallback: a console that only exposes run_line — then re-quote the
## tokens back into one line and let it print on its own scrollback.
func _run_meta(cmd: String, args: PackedStringArray) -> PackedStringArray:
	match cmd:
		"help":
			if args.is_empty():
				return DebugCommandsScript.help_lines()
			var row: Dictionary = DebugCommandsScript.find(args[0])
			if row.is_empty():
				return PackedStringArray(["no such command: " + args[0]])
			return DebugCommandsScript.help_for(row)
		"clear":
			_clear_output()
			return PackedStringArray()
		"keys":
			return _key_lines()
	var console := _find_console()
	if console != null and console.has_method(&"run_meta"):
		var answered: Variant = console.call(&"run_meta", cmd, args)
		if answered is PackedStringArray:
			return answered as PackedStringArray
		return PackedStringArray([cmd + ": the console answered with something that is not lines"])
	if console != null and console.has_method(&"run_line"):
		# Re-quote on the way back to a line: the widgets hand us tokens, and a bind line ("god; noclip on") or an
		# exec path with a space must survive the console's tokenizer as ONE argument again.
		var words := PackedStringArray([cmd])
		for a in args:
			words.append(_quote_arg(a))
		console.call(&"run_line", " ".join(words))
		return PackedStringArray([cmd + ": ran on the console — its scrollback has the result"])
	return PackedStringArray([cmd + ": no handler on this surface (needs a DebugConsole in the scene)"])


## Wrap a token in double quotes when the console's tokenizer would otherwise split it (a space or tab, or an
## empty string that must still count as an argument). Inner quotes are dropped — the tokenizer has no escape.
static func _quote_arg(arg: String) -> String:
	var clean := arg.replace("\"", "")
	if clean.is_empty() or clean.contains(" ") or clean.contains("\t"):
		return "\"" + clean + "\""
	return clean


## The dev keys the debug drop-ins bind. Ours is known; the console's is read DUCK-TYPED off whatever node
## answered the discovery walk, so this stays correct without a hard dependency on the console existing.
func _key_lines() -> PackedStringArray:
	var out := PackedStringArray()
	out.append("menu    " + OS.get_keycode_string(toggle_key))
	var console := _find_console()
	if console != null:
		var k: Variant = console.get(&"toggle_key")
		if typeof(k) == TYPE_INT:
			out.append("console " + OS.get_keycode_string(int(k)))
	return out


## The context every action module reads. Rebuilt per command because the player can be freed and respawned
## under an open panel (death, a level warp, a `reload`), and a stale reference would poke a dead node.
func _ctx() -> Dictionary:
	return {
		&"tree": get_tree(),
		&"player": GroupsScript.human_player(get_tree()),
		&"host": self,
		&"state": _shared_state(),
	}


## ⭐ONE STATE DICTIONARY ACROSS BOTH SURFACES. ctx[&"state"] is where a toggle banks what it replaced — god
## mode's original armor_flat, the saved walk speed, the teleport mark. If the menu and the console each held
## their OWN dictionary, `god on` clicked here and `god off` typed there would read two different snapshots
## and strand the banked value on the wrong host. Dictionaries are REFERENCE types, so adopting the console's
## makes both hosts genuinely share one.
## Resolved duck-typed, in preference order: a published command_state() accessor, else the console's private
## `_state` read through Object.get() (the project's idiom for reading a private field for a debug readout —
## cf. the RentCollector dawn counters). Either miss degrades to our own dictionary: the menu stays fully
## usable alone, it just no longer sees toggles the console armed.
func _shared_state() -> Dictionary:
	var console := _find_console()
	if console == null:
		return _state
	if console.has_method(&"command_state"):
		var published: Variant = console.call(&"command_state")
		if published is Dictionary:
			return published
	var private: Variant = console.get(&"_state")
	if private is Dictionary:
		return private
	return _state


## Completion ids for every id-valued argument slot, merged from both action modules (each owns its own keys
## and caches its own disk scan). Gathered on OPEN rather than per row so a page swap costs nothing.
func _gather_sources() -> Dictionary:
	var out: Dictionary = {}
	var from_player: Dictionary = DebugActionsPlayerScript.sources()
	var from_world: Dictionary = DebugActionsWorldScript.sources()
	out.merge(from_player, true)
	out.merge(from_world, true)
	# The COMMAND source is the registry's own name list — the `help [command]` slot's cycler.
	var command_key: StringName = DebugCommandsScript.SOURCE_KEYS[DebugCommandsScript.Kind.COMMAND]
	out[command_key] = DebugCommandsScript.names()
	return out


# --- danger confirm ---------------------------------------------------------------------------------------

func _arm(btn: Button) -> void:
	btn.set_meta(&"debug_armed", true)
	btn.text = confirm_caption
	btn.add_theme_color_override(&"font_color", error_color)
	var caption := String(btn.get_meta(&"debug_caption", ""))
	_print_lines(PackedStringArray([caption + ": destructive — click again to confirm"]))
	# ignore_time_scale = true: the `timescale` command must not be able to stretch or collapse the confirm
	# window. process_always = true so the arm still expires under DialogueManager's pause.
	# The button is bound BY INSTANCE ID, not by reference: a category swap frees these rows, and
	# instance_from_id() on a freed id returns null cleanly instead of handing us a dangling object.
	get_tree().create_timer(confirm_seconds, true, false, true).timeout.connect(_disarm_by_id.bind(btn.get_instance_id()))


func _disarm_by_id(id: int) -> void:
	var obj := instance_from_id(id)
	if obj == null or not is_instance_valid(obj):
		return
	var btn := obj as Button
	if btn != null:
		_disarm(btn)


func _disarm(btn: Button) -> void:
	if not is_instance_valid(btn) or not bool(btn.get_meta(&"debug_armed", false)):
		return
	btn.set_meta(&"debug_armed", false)
	btn.text = String(btn.get_meta(&"debug_caption", ""))
	btn.add_theme_color_override(&"font_color", danger_color)


# --- output -----------------------------------------------------------------------------------------------

## Print to the panel's own strip AND, when a console is in the tree, into its scrollback — so the two
## surfaces share ONE transcript and a command clicked here is visible to someone reading the console.
func _print_lines(lines: PackedStringArray) -> void:
	if lines.is_empty():
		return
	for line in lines:
		# Wrapped, not clipped: half these lines are the multi-column readouts `me`/`who`/`ledger` print, and a
		# clipped strip showed the first forty characters of each with no way to reach the rest. The strip
		# scrolls vertically, so extra wrapped rows cost nothing but scrollback.
		var painted := _wrap_label(line, font_size, text_color)
		painted.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_out_box.add_child(painted)
	while _out_box.get_child_count() > max_output_lines:
		var oldest := _out_box.get_child(0)
		_out_box.remove_child(oldest)
		oldest.free()
	# Deferred: the new Labels have no size until the next layout pass, so the scrollbar's max is stale now.
	call_deferred(&"_scroll_output_to_end")
	_echo_to_console(lines)


func _echo_to_console(lines: PackedStringArray) -> void:
	var console := _find_console()
	if console == null:
		return
	# .call() rather than console.echo(): the node is statically a Node, which has no such method, and this
	# whole relationship is duck-typed on purpose so the menu works with no console present.
	if console.has_method(&"echo"):
		console.call(&"echo", lines)


func _clear_output() -> void:
	for child in _out_box.get_children():
		_out_box.remove_child(child)
		child.queue_free()


func _scroll_output_to_end() -> void:
	if not is_instance_valid(_out_scroll):
		return
	var bar := _out_scroll.get_v_scroll_bar()
	if bar != null:
		_out_scroll.scroll_vertical = int(bar.max_value)


# --- console discovery ------------------------------------------------------------------------------------

## Find the DebugConsole DUCK-TYPED, by the two methods its public API promises. Never by class — this menu
## must not hard-depend on the console being in the scene, and a preloaded type reference would also drag a
## brand-new class_name into this file's parse.
## Deliberately NOT get_tree().node_added: tests/test_global_node_added_listeners.gd asserts exactly two game
## files connect that signal and name-checks both.
func _find_console() -> Node:
	if is_instance_valid(_console) and _console.is_inside_tree():
		return _console
	_console = null
	if _console_missing:
		return null
	if not console_path.is_empty():
		var wired := get_node_or_null(console_path)
		if wired != null and wired.has_method(&"echo"):
			_console = wired
			return _console
	if not is_inside_tree():
		return null
	_console = _search_console(get_tree().root, console_search_depth)
	_console_missing = _console == null
	return _console


func _search_console(node: Node, depth: int) -> Node:
	for child in node.get_children():
		if not is_instance_valid(child):
			continue
		if child != self and child.has_method(&"echo") and child.has_method(&"run_line"):
			return child
		if depth > 0:
			var found := _search_console(child, depth - 1)
			if found != null:
				return found
	return null


# --- chrome helpers ---------------------------------------------------------------------------------------

## A CanvasLayer parented under a non-Control gets NO THEME (menu_style.gd:878-881 records the same trap for
## the tooltip panel), so every font, colour and box in this panel is an explicit override. These three
## factories are the only place that happens.

func _panel_style() -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = panel_color
	box.border_color = border_color
	box.set_border_width_all(1)
	box.set_content_margin_all(6)
	return box


## A CHROME Label: the title, a cycler's current value — text whose content this file controls and already
## knows to be short. Clipped, so a surprise (a 60-character NpcData id in a cycler) trims with an ellipsis
## instead of widening the row. NOT for prose the user has to read: use _wrap_label for that.
func _label(text_value: String, size_px: int, color: Color) -> Label:
	var made := Label.new()
	# clip_text drops the horizontal minimum to ~0. WITHOUT it a long value reports its full text width as the
	# Label's minimum and pushes the panel past its anchors (MenuStyle's cap_label rule, applied by hand
	# because MenuStyle.apply() is off the table here).
	made.clip_text = true
	made.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	made.mouse_filter = Control.MOUSE_FILTER_IGNORE   # readouts stay click-through; only the root STOPs
	made.add_theme_font_size_override(&"font_size", size_px)
	made.add_theme_color_override(&"font_color", color)
	made.text = text_value
	return made


## A Label for text that must be READ IN FULL — a command's help line, an output line. It wraps instead of
## truncating, and its minimum WIDTH collapses to the longest single word rather than the whole string, so it
## cannot push the panel wider (that is what made the clipped version look necessary in the first place).
##
## ⭐The wrap only happens if the Label is actually given the pane's width. That is not automatic inside a
## ScrollContainer, which lays a child out at its MINIMUM unless the child carries SIZE_EXPAND_FILL — hence
## the expand flag on `_rows_box` and `_out_box`, and on every wrapped Label added to them. Drop it and the
## text wraps at the width of one word, one word per line.
func _wrap_label(text_value: String, size_px: int, color: Color) -> Label:
	var made := Label.new()
	made.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	made.mouse_filter = Control.MOUSE_FILTER_IGNORE
	made.add_theme_font_size_override(&"font_size", size_px)
	made.add_theme_color_override(&"font_color", color)
	made.text = text_value
	return made


## An argument NAME beside its editor: short, known-short (the registry's longest is 18 characters), and sized
## to its own text so it is visible at all. Unclipped on purpose — see the ⭐ in _add_row.
func _tag_label(text_value: String) -> Label:
	var made := Label.new()
	made.mouse_filter = Control.MOUSE_FILTER_IGNORE
	made.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	made.add_theme_font_size_override(&"font_size", font_size)
	made.add_theme_color_override(&"font_color", help_color)
	made.text = text_value
	return made


func _button(caption: String) -> Button:
	var made := Button.new()
	made.clip_text = true
	made.add_theme_font_size_override(&"font_size", font_size)
	made.add_theme_color_override(&"font_color", text_color)
	made.add_theme_color_override(&"font_hover_color", accent_color)
	made.add_theme_color_override(&"font_focus_color", accent_color)
	made.text = caption
	return made


## A cycler's `<` / `>` step button.
##
## ⭐NOT `_button()` PINNED TO 14 px. That is what these were, and it drew NOTHING: the engine's default Button
## stylebox carries ~8 px of content margin per side, so a 14 px-wide button has NEGATIVE room for its caption
## and clip_text then trims the glyph away entirely. Every enumerated argument in this panel had two invisible
## arrows around it — the value looked like a dead readout with no way to change it. So: an explicit box with
## 2 px margins, a width that fits the glyph, and no clipping.
func _arrow_button(glyph: String) -> Button:
	var made := Button.new()
	made.text = glyph
	made.custom_minimum_size = Vector2(arrow_button_width, 0)
	made.add_theme_font_size_override(&"font_size", font_size)
	made.add_theme_color_override(&"font_color", accent_color)
	made.add_theme_color_override(&"font_hover_color", text_color)
	made.add_theme_color_override(&"font_focus_color", text_color)
	made.add_theme_color_override(&"font_pressed_color", text_color)
	for state in [&"normal", &"hover", &"pressed", &"focus", &"disabled"]:
		var box := StyleBoxFlat.new()
		box.bg_color = field_color if state != &"hover" else field_color.lightened(0.18)
		box.border_color = field_border_color
		box.set_border_width_all(1)
		box.set_content_margin_all(2.0)
		made.add_theme_stylebox_override(state, box)
	return made


## Where the caret lands after open(). The search field by default — F1 then typing is the whole reason it
## exists — with the first category button as the fallback, which is what a controller has always landed on
## and what `focus_search_on_open = false` restores. See that knob for the keyboard trade-off.
func _seed_focus() -> void:
	if not _is_open:
		return
	if focus_search_on_open and is_instance_valid(_search_field) and _search_field.is_visible_in_tree():
		_search_field.grab_focus()
		return
	if is_instance_valid(_first_focus) and _first_focus.is_visible_in_tree():
		_first_focus.grab_focus()
