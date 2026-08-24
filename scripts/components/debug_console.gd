class_name DebugConsole
extends CanvasLayer

## DROP-IN DEVELOPER CONSOLE — the primary surface of the in-game debug suite, and DEBUG BUILDS ONLY (a
## release export must carry no cheat surface, so `_ready` early-outs unless `OS.is_debug_build()`; the
## `force_in_release` escape hatch exists for a profiling build you deliberately want the tools in).
##
## A panel drops over the top of the screen with a scrollback log and a one-line command field:
## `toggle_key` (backtick) opens/closes, Tab completes, Up/Down walks history, Enter runs, Esc closes.
##
## WHERE TO DROP IT: scenes/game.tscn, as a SIBLING of GameRoot and Player. Never inside the Level subtree —
## GameRoot.load_level renames/removes/queue_frees the whole old level, so a console parented in there dies on
## the first `warp`.
##
## WHAT IT OWNS vs WHAT IT DELEGATES — one table, two front-ends (this console and DebugMenu):
##  - DebugCommands (pure, RefCounted): the command table, the tokenizer, arity/enum validation, completion and
##    help rendering. Everything here that could be unit-tested lives THERE, off-tree.
##  - DebugActionsPlayer / DebugActionsWorld: the impure halves. This file dispatches on the row's `mod` and
##    prints whatever comes back; it never pokes gameplay itself except through them.
##  - `&"meta"` rows (help / clear / keys / exec / bind) are handled HERE, because they need the scrollback (or
##    this node's own key bindings and its exec queue), which no pure module can reach.
##
## SCRIPTING — three ways a line reaches run_line() without being typed:
##  - `exec <file>`: a command file (one line each, `#` comments, `wait <frames>`) is queued and stepped ONE LINE
##    PER PHYSICS TICK by _physics_process — never a coroutine that awaits physics_frame. WHY: this node is freed by
##    every reload_current_scene (`reload`, `load`, a death, F9), and a coroutine resumed after its instance is
##    gone pushes "Resumed function after await, but class instance is gone" — an engine error that inflates the
##    F3 ErrorSink for a file that merely ended in `load`. A tick-stepped queue simply stops with the node. A
##    nested `exec` splices its lines in FRONT of the rest of the outer file (sequential, like a shell `source`),
##    capped at `exec_depth_limit` so a file that execs itself terminates.
##  - AUTOEXEC: `autoexec_path` (default user://autoexec.cfg) runs by itself, once per PROCESS (a static latch —
##    the console is rebuilt on every reload and must not re-spawn your repro cast per death), after a readiness
##    poll has seen both the human Player and the level subtree land. `--autoexec=<path>` and `--exec=<l;l>` in
##    OS.get_cmdline_user_args() override the path / append lines. USER args only exist after a bare `--` (or
##    `++`) on the command line, so Project Settings → Editor → Run → Main Run Args needs the separator too:
##    `-- "--exec=god on; noclip on"`. That is what lets F5 drop you straight into a repro state. ALL of it sits
##    behind the debug gate.
##  - `bind <key> "<line>"`: raw dev keys (user://debug_binds.cfg) that run a `;`-chained line from _input while
##    NO debug surface is open and no text field owns focus — the same raw-keycode idiom as `toggle_key`, never an
##    InputMap action (see the note on toggle_key).
## Every line the log paints is also print()ed with a "[console] " prefix (`mirror_to_stdout`), so the editor's
## Output dock and user://logs/godot.log keep the transcript the 200-line scrollback and every reload throw away.
##
## INPUT CONTRACT — why the console can be typed into while the world is live, in two independent halves:
##  1. EVENT-driven consumers (hotbar, the Pip-Boy tabs, the wait screen, OptionsMenu) all read
##     `_unhandled_input`, and a FOCUSED LineEdit marks printable keys handled in `_gui_input` — so the letters
##     and digits you type can never also fire a game verb. Note the word FOCUSED: that guarantee is only as good
##     as the caret staying in the field, which is why `_input` re-grabs it after every mouse press. The
##     non-printable keys the console itself uses (Esc/Tab/Up/Down/the toggle) are consumed in `_input`, which
##     runs before the GUI layer sees them.
##  2. POLL-driven gameplay (move/jump/fire/crouch/interact, all read straight off `Input` every frame) is
##     unaffected by focus. This project has NO generic "suppress gameplay" flag reachable without joining
##     `InputManager._modal_reg` (which would force edits to three hard-pinned assertions in
##     tests/test_modal_registry.gd), so we use the sanctioned by-hand precedent instead — the one Player.die()
##     uses — via DebugActionsPlayer.suspend_player() / restore_player().
##
## DEV-ONLY TEXT: every string painted here is developer copy that must never reach a player or a translation
## catalog. That is precisely why this file is listed in ScanText.SKIP_FILES, and why raw literals at a paint
## site are legal HERE and in debug_menu.gd — and nowhere else under scripts/.

## Brand-new class_names are preloaded BY PATH and never annotated with their type: until the editor rescans
## its global class cache, a typed reference fails the WHOLE file to parse with "Could not find type X" and
## cascades into everything that touches it. Precedent: debug_overlay.gd:11 (ErrorSinkScript).
const DebugCommandsScript := preload("res://scripts/components/debug_commands.gd")
const DebugActionsPlayerScript := preload("res://scripts/components/debug_actions_player.gd")
const DebugActionsWorldScript := preload("res://scripts/components/debug_actions_world.gd")
## Groups is a plain class_name helper, NOT an autoload — there is no `Groups` singleton to reach for.
const GroupsScript := preload("res://scripts/world/groups.gd")

# Developer copy. Kept as consts so the format strings are in one place, not scattered across paint sites.
const BANNER := "debug console — %s toggles · type `help`"
const UNKNOWN_COMMAND := "unknown command: %s"
const DID_YOU_MEAN := "did you mean: %s"
const NO_SUCH_COMMAND := "no such command: %s"
const DANGER_NOTE := "! destructive — this cannot be undone from the console"
const NO_HANDLER := "%s: no handler for module \"%s\" (registry and console disagree)"
const MORE_MATCHES := "   (+%d more)"
const REFUSED_MODAL := "[debug console] refused: another menu owns the cursor (close it first)"
const CONSOLE_KEYS := "%s   console: tab completes · up/down history · enter runs · esc closes"
## The stdout mirror prefix — grep-able in user://logs/godot.log among the engine's own lines.
const MIRROR_PREFIX := "[console] "
## The exec-only word handled BEFORE run_line ever sees it — deliberately not a registry row, so it never shows in
## `help` as something you can type (typed, it would just skip a frame of nothing).
const EXEC_WAIT_WORD := "wait"
const BINDS_SECTION := "binds"
const EXEC_ARG_PREFIX := "--exec="
const AUTOEXEC_ARG_PREFIX := "--autoexec="

@export_group("Keys")
## A RAW dev keycode, deliberately NOT a rebindable InputManager action: an action would drag in the
## four-surface keybind contract (project.godot [input] + the InputManager controller default + an ActionCatalog
## row + boot cross-validation) and auto-generate a player-facing Options → Controls rebind row. Same idiom as
## debug_overlay.gd:14. Backtick/tilde is unclaimed in project.godot's [input].
@export var toggle_key: Key = KEY_QUOTELEFT
## Debug builds get the console for free; a release export must carry NO cheat surface. Tick this only for a
## deliberately-instrumented release (a profiling or QA build).
@export var force_in_release: bool = false

@export_group("Behaviour")
## Log lines retained. The oldest are freed past this — an uncapped log is a slow leak in a long session.
@export var scrollback_lines: int = 200
## Command lines Up/Down can walk back through.
@export var history_lines: int = 50
## How many completion candidates the match line shows before it collapses to "(+N more)". The list is a plain
## in-canvas Label on purpose — see _set_matches.
@export var completion_preview: int = 24
## How many "did you mean" guesses a typo gets.
@export var suggestion_count: int = 3
## Minimum String.similarity() score for a guess to be offered at all.
@export_range(0.0, 1.0, 0.01) var suggestion_threshold: float = 0.35
## Every line the log paints is also print()ed as "[console] <line>" — the editor Output dock and Godot's own
## rotating user://logs/godot.log then carry the whole transcript for free (the scrollback is capped and dies with
## this node on every reload). print(), never push_warning: a warning would inflate the F3 ErrorSink tallies.
@export var mirror_to_stdout: bool = true

@export_group("Scripting")
## Run `autoexec_path` by itself once the level and the human Player have both landed. Once per PROCESS, not per
## console (see _autoexec_ran) — and only ever behind the debug gate; a shipped build must never execute a file a
## player dropped into user://.
@export var run_autoexec: bool = true
## A bare name resolves under user:// (see resolve_exec_path); `--autoexec=<path>` on the command line overrides it.
@export var autoexec_path: String = "user://autoexec.cfg"
## Physics ticks the readiness poll waits AFTER the level and player exist before the first autoexec line runs.
## GameRoot places the player at its PlayerSpawn call_deferred after the level's add_child, and the Player's own
## ground-snap runs over its first physics frames — a `tp` on tick zero would race both. Queued as a visible
## `wait N` so the transcript shows the pause rather than hiding it.
@export_range(0, 120) var autoexec_settle_frames: int = 2
## How often the readiness poll looks (a Timer child, freed the moment it fires — never a per-frame callback that
## stays on). Cheap at 10 Hz; the level lands within the first frames of game.tscn anyway.
@export_range(0.02, 2.0, 0.01) var autoexec_poll_seconds: float = 0.1
## Nesting cap for `exec` inside an exec'd file. A file that execs itself terminates at this depth instead of
## refilling the queue forever; 4 is deep enough for "autoexec → repro → loadout".
@export_range(1, 16) var exec_depth_limit: int = 4
## Where `bind` persists (ConfigFile, [binds] section, key name -> line). user:// only — never a project file.
@export var binds_path: String = "user://debug_binds.cfg"

@export_group("Look")
## WHOLE PIXELS ONLY, every metric on this panel: the 792x444 canvas is nearest-upscaled ~2.4x, so a fractional
## font size or offset rasterizes into a ragged comb (HudSettings.gd:279).
@export var panel_height: int = 220
@export var panel_margin: int = 8
@export var font_size: int = 12
## Pinned minimum for the log's ScrollContainer. A Control that cannot fit its content GROWS past its anchors
## rather than clipping, so every slot on this panel keeps a small, honest minimum.
@export var log_min_height: int = 48
@export var prompt_glyph: String = "> "
## Optional font. Left blank we build a system MONOSPACE, because DebugCommands.help_lines() pads its columns
## with `%-14s` — which only lines up in a fixed-pitch face.
@export var font: Font = null
@export var mono_families: PackedStringArray = PackedStringArray([
	"Consolas", "Cascadia Mono", "DejaVu Sans Mono", "Liberation Mono", "Courier New", "monospace",
])
@export var panel_color: Color = Color(0.04, 0.05, 0.07, 0.93)
@export var field_color: Color = Color(0.10, 0.12, 0.16, 1.0)
@export var accent_color: Color = Color(0.36, 0.93, 0.74, 1.0)
@export var text_color: Color = Color(0.86, 0.90, 0.94, 1.0)
## The echoed copy of the line you typed — distinct from output so a long dump stays readable.
@export var echo_color: Color = Color(0.53, 0.74, 0.96, 1.0)
@export var hint_color: Color = Color(0.60, 0.65, 0.72, 1.0)
@export var warn_color: Color = Color(1.0, 0.78, 0.30, 1.0)
## Failures must be OBVIOUS: this console is where every command's error text surfaces.
@export var error_color: Color = Color(1.0, 0.44, 0.40, 1.0)

var _enabled: bool = false          ## false in a release build — every public entry point no-ops
var _is_open: bool = false
## Per-command scratch owned by the CONSOLE and handed to every action module in ctx[&"state"]. It persists for
## the console's lifetime, which is what lets `god` bank the armour it replaced and `mark`/`back` remember a
## position. Modules namespace their own keys.
var _state: Dictionary = {}
var _history: PackedStringArray = PackedStringArray()
var _history_pos: int = -1          ## -1 = editing a fresh line rather than browsing history
var _draft: String = ""             ## the half-typed line stashed when history browsing started
var _prev_mouse_mode: Input.MouseMode = Input.MOUSE_MODE_CAPTURED
## The exact body suspend_player() froze, plus its snapshot. Held as a pair so close() can restore the SAME
## instance — never a re-resolved one (see close()).
var _suspended_player: Node = null
var _suspend_snapshot: Dictionary = {}

## ⭐PER-PROCESS LATCH — `static`, so it lives on the SCRIPT, not the node. This node is rebuilt by every
## reload_current_scene (a death, `reload`, `load`/F9 quickload, PlayerDebug's End key), and each rebuild would
## otherwise re-run the autoexec: `spawn raider 5` per death, `money 1000` per quickload. Set the moment the poll
## FIRES (not when it is armed), so a reload that lands before the level does still gets exactly one run.
static var _autoexec_ran: bool = false
## The exec QUEUE: {"line": String, "depth": int}, stepped one entry per _physics_process tick (see the header for
## why this is a tick-stepped queue and not a coroutine). `depth` is how many `exec` files deep the line came from
## — 1 for a typed `exec` or the autoexec, 0 never queued — and is what the nesting cap counts.
var _exec_queue: Array[Dictionary] = []
## Ticks left on an in-flight `wait <frames>`; the queue does not advance while it is > 0.
var _exec_wait_left: int = 0
## Depth of the queue entry currently being dispatched (0 while a typed or bound line runs). Read by the `exec`
## meta case so a nested exec knows to splice in FRONT of the outer file and to count one level deeper.
var _exec_current_depth: int = 0
## > 0 while a line runs from the exec queue or a bind — those skip the Up/Down history so a 30-line file does not
## flush the commands you actually typed.
var _scripted: int = 0
## Live key binds: keycode (int) -> line. Loaded from `binds_path` in _ready, written back on every change.
var _binds: Dictionary = {}
## Command-line lines to run after the autoexec (`--exec=`), and the autoexec path override (`--autoexec=`).
var _cmdline_lines: PackedStringArray = PackedStringArray()
var _autoexec_overridden: bool = false
var _autoexec_timer: Timer = null

var _root: Control = null
var _scroll: ScrollContainer = null
var _log_box: VBoxContainer = null
var _field: LineEdit = null
var _matches: Label = null
var _font: Font = null


func _ready() -> void:
	# 129..199 is entirely unoccupied. 128 is DOUBLE-booked (OptionsMenu + the F3 DebugOverlay, and GUT's runner
	# makes three at test time) where ties resolve by unstable tree order, and 200 is MenuStyle's cursor tooltip,
	# which must stay on top of us.
	layer = 150
	# ⭐PROCESS_MODE_ALWAYS or the console dies under DialogueManager's pause (dialogue_manager.gd:214) — which is
	# exactly when you most need it, since a stuck conversation is the single best reason to open it. Every screen
	# autoload does the same, and so does debug_overlay.gd:38 (the survey note calling DebugOverlay
	# PROCESS_MODE_INHERIT is STALE — it sets ALWAYS today; re-verified against source).
	process_mode = Node.PROCESS_MODE_ALWAYS
	# The only per-frame work this node ever does is the cursor re-assert while OPEN (see _process) and the exec
	# queue while it has lines (see _physics_process). Both are armed on demand and disarmed the moment they are
	# idle, so a closed console — and a release build — costs nothing a frame.
	set_process(false)
	set_physics_process(false)
	if not OS.is_debug_build() and not force_in_release:
		# No UI is built and _input is switched off outright, so a shipped build carries no key to find — and no
		# autoexec, no binds file and no command-line lines are ever read.
		visible = false
		set_process_input(false)
		return
	_enabled = true
	# One debug surface at a time: open() closes every other member first (see _close_other_surfaces). Joined
	# only past the debug gate, so a release build never advertises one.
	add_to_group(GroupsScript.DEBUG_SURFACE)
	_build_ui()
	_root.visible = false
	# The BANNER is painted (and mirrored to stdout) only past the gate — a release build prints nothing.
	_add_line(BANNER % OS.get_keycode_string(toggle_key), hint_color)
	_load_binds()
	_arm_autoexec()


# ---------------------------------------------------------------------------------------------------
# Public API (DebugMenu and the action modules call these — keep the signatures)
# ---------------------------------------------------------------------------------------------------

func is_open() -> bool:
	return _is_open


## The per-command scratch Dictionary handed to every action module as ctx[&"state"]. PUBLISHED because DebugMenu
## adopts it: debug_menu.gd:695-702 resolves the shared state duck-typed, preferring exactly this method name and
## falling back to reading the private `_state`. Dictionaries are REFERENCE types, so pointing both surfaces at
## this ONE instance is what stops `god on` clicked in the menu and `god off` typed here from banking two
## different armour snapshots and stranding one of them on the wrong host.
func command_state() -> Dictionary:
	return _state


## The `&"meta"` rows on behalf of ANOTHER front-end. DebugMenu forwards the rows it cannot answer on its own
## strip (`exec`, `bind` — they need this node's exec queue / key table) with an ALREADY-VALIDATED argv and paints
## the lines it gets back; its _print_lines then echoes those same lines into this scrollback, so both transcripts
## read the same. Returns lines rather than routing through run_line because run_line only PRINTS: a menu user (who
## by the one-surface rule has this console CLOSED) would otherwise see nothing but a pointer at a scrollback they
## cannot look at, and `bind` with no arguments — a listing — would land nowhere they can read.
func run_meta(cmd: String, args: PackedStringArray) -> PackedStringArray:
	if not _enabled:
		return PackedStringArray(["%s: the console is disabled in this build" % cmd])
	return _run_meta(cmd, args)


func toggle() -> void:
	if _is_open:
		close()
	else:
		open()


## Open the panel. Refuses in a release build and — the shipped-bug pattern this project already paid for —
## over any registered modal: two screens that both free the cursor fight over Escape, and the loser restores a
## CAPTURED cursor under a menu that is still up, leaving it unclickable (InputManager.gd:150-151,
## atm_screen.gd:18-20).
##
## It deliberately does NOT refuse over DialogueManager. A stuck conversation is the single best reason to open
## a console, and PROCESS_MODE_ALWAYS above is what keeps us alive under the pause dialogue owns.
func open() -> void:
	if not _enabled or _is_open:
		return
	if InputManager.any_modal_open():
		# Reported with print(), not push_warning(): a warning would inflate the F3 overlay's ErrorSink tallies,
		# and a silent refusal reads as a dead key.
		print(REFUSED_MODAL)
		return
	# ⭐ONE DEBUG SURFACE AT A TIME. Each surface holds its own suspend_player snapshot, and two of them nested
	# restore in whatever order they close — the wrong order unfreezes the player under the survivor's free
	# cursor (every click fires the weapon) or re-freezes them with nothing left on screen. Closing the other
	# FIRST means its restore lands before our suspend reads the player, so the snapshots can never interleave.
	_close_other_surfaces()
	# Freeing the cursor is half the job: it kills mouse-look and pad-look for free (both self-gate on
	# MOUSE_MODE_CAPTURED), but left-click still POLLS Attack every frame. suspend_player is what stops that.
	_prev_mouse_mode = Input.mouse_mode
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var player: Node = _player()
	# is_instance_valid, not `!= null`: the group walk can hand back a body that was queue_free'd this frame, and
	# any property read (or `is`) on a freed instance crashes rather than returning null.
	if is_instance_valid(player):
		var snapshot: Dictionary = DebugActionsPlayerScript.suspend_player(player)
		_suspended_player = player
		_suspend_snapshot = snapshot
	_is_open = true
	# ⭐visible FIRST: grab_focus() on a hidden Control silently does nothing (atm_screen.gd:111-113). And the
	# grab is DEFERRED so the keystroke that opened the console has already been delivered — otherwise the
	# backtick types itself into the field. (_input also consumes the toggle key, belt and braces.)
	_root.visible = true
	_field.call_deferred(&"grab_focus")
	_set_matches(PackedStringArray())
	set_process(true)   # arms the cursor re-assert in _process, and only while we are actually up


func close() -> void:
	if not _is_open:
		return
	_is_open = false
	if is_instance_valid(_field):
		_field.release_focus()   # a field that kept focus behind a hidden panel would keep eating keys
		_field.text = ""
	if is_instance_valid(_root):
		_root.visible = false
	_set_matches(PackedStringArray())
	_history_pos = -1
	_draft = ""
	_restore_world()


## Hand back everything open() took from the running game: the player's own process callbacks and the cursor.
## Split out of close() because it is ALSO the teardown path — see _exit_tree, which is the only thing standing
## between a console that is freed while open and a permanently frozen player.
func _restore_world() -> void:
	set_process(false)
	# Restore the EXACT snapshot onto the EXACT body we froze. Re-resolving the player here would be wrong: a
	# level swap or a scene reload can replace it while the console is up, and stamping a stale snapshot onto a
	# fresh Player would re-enable physics on something that never asked for it. is_instance_valid FIRST —
	# `is` (and any method call) crashes on a freed instance.
	if is_instance_valid(_suspended_player) and not _suspend_snapshot.is_empty():
		DebugActionsPlayerScript.restore_player(_suspended_player, _suspend_snapshot)
	_suspended_player = null
	_suspend_snapshot = {}
	Input.mouse_mode = _prev_mouse_mode


## THE TEARDOWN SAFETY NET, two halves.
##
## (1) SHARED TUNING. `_state` is the ONLY record of every authored value a command banked before overriding a
## shared GameSettings .tres field (`speed`'s max_speed, `god`'s continuous-fall timer, `timescale`'s
## allow_timescale_changes). This console dies on EVERY reload_current_scene — not just `reload`/`load` but a
## death reload (player.gd death modes), F9 quickload and PlayerDebug's End key — and the .tres outlives it. So
## without this unwind, `speed 3` + one death leaves the whole session at 3x with the fresh console calling that
## "authored". Both action modules expose an idempotent release; the menu shares this dict and never owns it.
## Runs UNCONDITIONALLY (open or closed) — the overrides do not care whether the panel was up.
##
## (2) THE PLAYER SUSPENSION. On a full scene reload the fresh MouseInput._ready re-captures the cursor
## (mouse_input.gd:27-28) and the old Player dies with the scene, so that case self-heals; the restore below is
## for anything that removes ONLY the console (a designer deleting the node in the remote inspector, a reparent,
## an editor-driven scene swap) while the Player survives beside it.
func _exit_tree() -> void:
	# The exec queue dies with the world it was scripting: a `load` mid-file must not leave the tail of the file
	# waiting for a tick that a re-parented console might one day deliver into a different level.
	_exec_queue.clear()
	_exec_wait_left = 0
	if _enabled and is_inside_tree():
		var ctx := _context()
		DebugActionsWorldScript.release_scene_scoped_state(ctx)
		DebugActionsPlayerScript.release_scene_scoped_state(ctx)
	if not _is_open:
		return
	_is_open = false
	_restore_world()


## Keep the cursor free for as long as the panel is up. The ONE per-frame job this node has.
##
## ⭐DialogueManager rewrites Input.mouse_mode behind our back, three times over: `_sync_dialogue_cursor` sets
## HIDDEN while a line is being read and VISIBLE while the choice menu is up (dialogue_manager.gd:658-665), and
## `_finish` slams CAPTURED when the conversation ends (:652). This console deliberately does NOT refuse to open
## over a conversation (see open() — a stuck one is the reason it exists), so without this re-assert simply
## advancing a line under the open panel leaves it up with a hidden or captured pointer: unclickable, and with no
## visible cursor to aim the click with. Re-asserting is both cheaper and less brittle than latching three
## dialogue signals, and it is armed only between open() and _restore_world().
##
## `_prev_mouse_mode` is deliberately NOT re-read here: it is the mode from BEFORE we opened, and close() still
## owes exactly that value back.
func _process(_delta: float) -> void:
	if _is_open and Input.mouse_mode != Input.MOUSE_MODE_VISIBLE:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


## THE EXEC STEPPER — one queued line per PHYSICS tick, armed only while the queue has entries. Physics, not idle,
## so a `tp` has settled (its re-armed ground snap runs in the Player's _physics_process) before the `spawn` on the
## next line reads the player's position; a whole file's worth of teleports and spawns in ONE frame is exactly the
## unsettled-world bug the seam notes record. Runs under PROCESS_MODE_ALWAYS, so a file keeps stepping through a
## dialogue pause. Stops by itself the moment the node leaves the tree (a `load` mid-file) — no coroutine to
## resume against a freed instance.
func _physics_process(_delta: float) -> void:
	if _exec_wait_left > 0:
		_exec_wait_left -= 1
		return
	if _exec_queue.is_empty():
		set_physics_process(false)
		return
	var entry: Dictionary = _exec_queue.pop_front()
	var line := String(entry.get("line", ""))
	var depth := int(entry.get("depth", 1))
	var tokens: PackedStringArray = DebugCommandsScript.tokenize(line)
	if not tokens.is_empty() and tokens[0].to_lower() == EXEC_WAIT_WORD:
		# `wait [frames]` is exec-only and handled here, before run_line, which would reject it as unknown.
		_add_line(prompt_glyph + line, echo_color)
		var frames := 1
		if tokens.size() > 1:
			if tokens[1].is_valid_int():
				frames = maxi(0, tokens[1].to_int())
			else:
				_add_line("wait: frames must be a whole number, got \"%s\" — not waiting" % tokens[1], error_color)
				frames = 0
		_exec_wait_left = frames
		_finish_output()
	else:
		_exec_current_depth = depth
		_run_scripted(line)
		_exec_current_depth = 0
	if _exec_queue.is_empty() and _exec_wait_left <= 0:
		set_physics_process(false)


## Append developer lines to the scrollback in the neutral colour, capped and auto-scrolled. Safe to call from
## anywhere (the menu echoes its results here too); a no-op in a release build. Appends whether or not the panel
## is VISIBLE — a bind fired while the console is closed, or an autoexec at boot, still leaves its transcript
## behind for the next time you open it.
func echo(lines: PackedStringArray) -> void:
	if not _enabled or not is_instance_valid(_log_box):
		return
	for line in lines:
		_add_line(line, text_color)
	_finish_output()


## Parse, validate and run one typed line, printing everything it produces. The point of a console is to
## SURVIVE, so every failure below degrades to a printed line: an empty line is a no-op, an unknown name gets a
## "did you mean", a bad arity gets the validator's own sentence, and a module that returns something other
## than lines prints nothing rather than taking the console down with it.
func run_line(line: String) -> void:
	if not _enabled or not is_instance_valid(_log_box):
		return
	var text := line.strip_edges()
	if text.is_empty():
		return
	_add_line(prompt_glyph + text, echo_color)
	if _scripted <= 0:
		_remember(text)   # exec'd and bound lines are echoed but never enter the Up/Down history

	var tokens: PackedStringArray = DebugCommandsScript.tokenize(text)
	if tokens.is_empty():
		_finish_output()
		return
	var row: Dictionary = DebugCommandsScript.find(tokens[0])
	if row.is_empty():
		_report_unknown(tokens[0])
		_finish_output()
		return

	var args := PackedStringArray()
	for i in range(1, tokens.size()):
		args.append(tokens[i])
	# Arity and enumerated words are checked HERE, before the action ever runs, so every module can trust argv's
	# length and never has to re-check it.
	var problem: String = DebugCommandsScript.validate(row, args)
	if not problem.is_empty():
		_add_line(problem, error_color)
		_finish_output()
		return

	var cmd: String = row["name"]
	if bool(row["danger"]):
		_add_line(DANGER_NOTE, warn_color)
	var module: StringName = row["mod"]
	match module:
		&"meta":
			_print_lines(_run_meta(cmd, args), text_color)
		&"player":
			_print_lines(DebugActionsPlayerScript.run(cmd, _context(), args), text_color)
		&"world":
			_print_lines(DebugActionsWorldScript.run(cmd, _context(), args), text_color)
		_:
			_add_line(NO_HANDLER % [cmd, String(module)], error_color)
	_finish_output()


# ---------------------------------------------------------------------------------------------------
# Dispatch helpers
# ---------------------------------------------------------------------------------------------------

## The context every action module receives. Rebuilt PER COMMAND on purpose: the player node is freed and
## replaced by a level change, so a cached reference goes stale (and `is_instance_valid` on a stale one is the
## only thing between us and a crash). `state` is the same Dictionary every time — that persistence is the
## contract that lets a toggle bank what it replaced.
func _context() -> Dictionary:
	return {
		&"tree": get_tree(),
		&"player": _player(),
		&"host": self,
		&"state": _state,
	}


## Close every OTHER open member of Groups.DEBUG_SURFACE (the DebugMenu, today) before this one takes the
## cursor and the player. Duck-typed on is_open/close so the two surfaces stay preload-decoupled; the group is
## joined only by nodes that passed the debug gate, so the walk is 0–2 members and free.
func _close_other_surfaces() -> void:
	for surface in get_tree().get_nodes_in_group(GroupsScript.DEBUG_SURFACE):
		if surface == self or not is_instance_valid(surface):
			continue
		if surface.has_method(&"is_open") and surface.has_method(&"close") and bool(surface.call(&"is_open")):
			surface.call(&"close")


## THE human player, never a recruited companion: Groups.PLAYER holds both (companions join it so enemies
## target them), and human_player() is the one home for that rule. Null at the start menu and mid-level-load —
## every caller null-guards.
func _player() -> Node:
	return GroupsScript.human_player(get_tree())


## The `&"meta"` rows. They live in the console rather than an action module because each one needs the
## scrollback (or this node's own key bindings / exec queue), which no pure module can reach. The menu forwards
## any meta row it has no answer for through run_meta() above (debug_menu.gd _run_meta), so `exec`/`bind` work
## from both surfaces. tests/test_debug_console_exec.gd pins that every &"meta" registry row has an arm here.
func _run_meta(cmd: String, args: PackedStringArray) -> PackedStringArray:
	match cmd:
		"help":
			if args.is_empty():
				var listing: PackedStringArray = DebugCommandsScript.help_lines()
				return listing
			var row: Dictionary = DebugCommandsScript.find(args[0])
			if row.is_empty():
				return PackedStringArray([NO_SUCH_COMMAND % args[0]])
			var detail: PackedStringArray = DebugCommandsScript.help_for(row)
			return detail
		"clear":
			_clear_log()
			return PackedStringArray()
		"keys":
			return _key_lines()
		"exec":
			# One level deeper than whatever is running us: 1 for a typed line, N+1 from inside an exec'd file.
			return _exec_file(args[0], _exec_current_depth + 1)
		"bind":
			return _bind_command(args)
	return PackedStringArray([NO_HANDLER % [cmd, "meta"]])


## Every dev key currently bound in the running tree, then this console's own binds. Discovered rather than
## hard-coded: every debug drop-in in this project binds a raw `@export var toggle_key: Key`, so walking for that
## property keeps this honest the moment someone drops another one into the scene.
func _key_lines() -> PackedStringArray:
	var out := PackedStringArray()
	out.append(CONSOLE_KEYS % OS.get_keycode_string(toggle_key))
	for pair in _toggle_key_pairs():
		out.append("%s: %s" % [String(pair[0]), OS.get_keycode_string(int(pair[1]))])
	for keycode in _sorted_bind_keys():
		out.append("bind %s: %s" % [OS.get_keycode_string(int(keycode)), String(_binds[keycode])])
	return out


## [name, keycode] for every OTHER node in the tree carrying a `toggle_key` export, in tree order. Shared by
## `keys` (to print them) and `bind` (to refuse them). is_instance_valid before touching any node — a queue_free'd
## child is still in the list for a frame and crashes on access.
func _toggle_key_pairs() -> Array:
	var out: Array = []
	var tree := get_tree()
	if tree != null and tree.root != null:
		_collect_toggle_keys(tree.root, out)
	return out


func _collect_toggle_keys(node: Node, out: Array) -> void:
	for child in node.get_children():
		if not is_instance_valid(child):
			continue
		if child != self:
			var bound: Variant = child.get(&"toggle_key")
			if typeof(bound) == TYPE_INT:
				out.append([String(child.name), int(bound)])
		_collect_toggle_keys(child, out)


# ---------------------------------------------------------------------------------------------------
# exec / autoexec — a command file, stepped one line per physics tick (see _physics_process)
# ---------------------------------------------------------------------------------------------------

## Queue a command file. Returns the header (or the refusal) for the caller to print; the lines themselves run
## from _physics_process. `depth` is the nesting level this file will run at — a nested exec (depth > 1) splices
## its lines in FRONT of the rest of the outer file so it reads sequentially, like a shell `source`; a top-level
## exec appends, so a file typed while the autoexec is still stepping runs after it rather than interleaved.
func _exec_file(file: String, depth: int) -> PackedStringArray:
	var path := resolve_exec_path(file)
	if path.is_empty():
		return PackedStringArray(["exec: which file? (a bare name resolves under user://)"])
	if depth > maxi(1, exec_depth_limit):
		return PackedStringArray(["exec: refused %s — nested deeper than %d (a file that execs itself?)" % [path, exec_depth_limit]])
	if not FileAccess.file_exists(path):
		return PackedStringArray(["exec: no such file: %s" % path])
	var text := FileAccess.get_file_as_string(path)
	var lines := exec_lines(text)
	if lines.is_empty():
		return PackedStringArray(["exec: %s has no commands (blank and # lines only)" % path])
	_enqueue(lines, depth, depth > 1)
	return PackedStringArray(["exec: %s — %d line%s queued, one per physics tick" % [path, lines.size(), "" if lines.size() == 1 else "s"]])


func _enqueue(lines: PackedStringArray, depth: int, at_front: bool) -> void:
	var entries: Array[Dictionary] = []
	for line in lines:
		entries.append({"line": line, "depth": depth})
	if at_front:
		# The entry that asked for this splice has already been popped, so index 0 IS "right after it".
		var rest := _exec_queue
		_exec_queue = entries
		_exec_queue.append_array(rest)
	else:
		_exec_queue.append_array(entries)
	if not _exec_queue.is_empty():
		set_physics_process(true)


## run_line for a line nobody typed (an exec'd file, a bind): identical dispatch, but kept out of the history.
func _run_scripted(line: String) -> void:
	_scripted += 1
	run_line(line)
	_scripted -= 1


## Arm the autoexec readiness poll — a Timer child, NOT a `_process` that stays on. There is no level-loaded
## signal to latch: GameRoot.load_level is call_deferred from its _ready and the Player is placed deferred again
## after that, so we poll until both the human Player and the level subtree exist, then fire ONCE per process.
func _arm_autoexec() -> void:
	var parsed := parse_cmdline(OS.get_cmdline_user_args())
	_cmdline_lines = parsed["exec"]
	var override := String(parsed["autoexec"])
	if not override.is_empty():
		autoexec_path = override
		_autoexec_overridden = true
	if _autoexec_ran:
		return   # a rebuilt console after a reload: the process already had its run
	if not run_autoexec and _cmdline_lines.is_empty():
		return
	_autoexec_timer = Timer.new()
	_autoexec_timer.wait_time = maxf(0.02, autoexec_poll_seconds)
	_autoexec_timer.one_shot = false
	_autoexec_timer.timeout.connect(_poll_autoexec)
	add_child(_autoexec_timer)
	_autoexec_timer.start()


func _poll_autoexec() -> void:
	if _autoexec_ran:
		_disarm_autoexec()   # another console instance fired first (two in one scene) — stand down
		return
	var tree := get_tree()
	if tree == null:
		return
	if not is_instance_valid(GroupsScript.human_player(tree)) or _level_node(tree) == null:
		return
	_autoexec_ran = true
	_disarm_autoexec()
	_fire_autoexec()


func _disarm_autoexec() -> void:
	if is_instance_valid(_autoexec_timer):
		_autoexec_timer.stop()
		_autoexec_timer.queue_free()
	_autoexec_timer = null


## The one-shot run: the settle wait, then the autoexec file, then any `--exec=` lines — all through the same
## queue, in that order. Only the OVERRIDDEN path complains when missing; no user://autoexec.cfg is the normal state
## and must not paint a line every boot.
func _fire_autoexec() -> void:
	var out := PackedStringArray()
	var have_file := run_autoexec and FileAccess.file_exists(resolve_exec_path(autoexec_path))
	if have_file or not _cmdline_lines.is_empty():
		if autoexec_settle_frames > 0:
			_enqueue(PackedStringArray(["%s %d" % [EXEC_WAIT_WORD, autoexec_settle_frames]]), 1, false)
	if run_autoexec:
		if have_file:
			out.append("autoexec:")
			out.append_array(_exec_file(autoexec_path, 1))
		elif _autoexec_overridden:
			out.append("autoexec: no such file: %s (from %s)" % [resolve_exec_path(autoexec_path), AUTOEXEC_ARG_PREFIX])
	if not _cmdline_lines.is_empty():
		out.append("%s %d line%s queued" % [EXEC_ARG_PREFIX, _cmdline_lines.size(), "" if _cmdline_lines.size() == 1 else "s"])
		_enqueue(_cmdline_lines, 1, false)
	_print_lines(out, hint_color)
	_finish_output()


## The live level subtree ("Level"). GameRoot works in TWO layouts — script on the scene root, or a drop-in child
## with Player/Level as siblings (scenes/game.tscn uses the latter, so the level lands at Game/Level, NOT
## GameRoot/Level; game_root.gd _host). Mirrors DebugActionsWorld._level_node rather than reaching into it.
func _level_node(tree: SceneTree) -> Node:
	var gr := tree.get_first_node_in_group(GroupsScript.GAME_ROOT)
	if gr != null:
		var own := gr.get_node_or_null(^"Level")
		if own != null:
			return own
		var parent := gr.get_parent()
		if parent != null:
			var sibling := parent.get_node_or_null(^"Level")
			if sibling != null:
				return sibling
	if tree.current_scene != null:
		return tree.current_scene.get_node_or_null(^"Level")
	return null


# ---------------------------------------------------------------------------------------------------
# bind — raw dev keys that run a console line (see _input for the firing rules)
# ---------------------------------------------------------------------------------------------------

## `bind` = list · `bind <key>` = clear · `bind <key> "<line>"` = set. The line is one console line, or several
## joined with `;` (split_chain honours quotes). Refuses KEY_NONE and any key a debug drop-in already toggles on
## — two handlers on one raw keycode would race on _input order.
func _bind_command(args: PackedStringArray) -> PackedStringArray:
	if args.is_empty():
		return _bind_lines()
	var word := args[0]
	var keycode := bind_key_from_word(word)
	if keycode == KEY_NONE:
		return PackedStringArray([
			"bind: unknown key \"%s\"" % word,
			"  key names are Godot's: F6, G, 5, Space, PageUp, Kp Add (KP_ADD works too) — no Ctrl/Shift/Alt combos",
		])
	var key_name := OS.get_keycode_string(keycode)
	if args.size() == 1:
		if not _binds.has(keycode):
			return PackedStringArray(["bind: %s is not bound" % key_name])
		_binds.erase(keycode)
		_save_binds()
		return PackedStringArray(["bind: %s cleared" % key_name])
	var line := args[1].strip_edges()
	if line.is_empty():
		return PackedStringArray(["bind: nothing to run — quote the line: bind %s \"god; noclip on\"" % key_name])
	var taken_by := _reserved_key_owner(keycode)
	if not taken_by.is_empty():
		return PackedStringArray(["bind: %s is taken by %s — pick another key" % [key_name, taken_by]])
	_binds[keycode] = line
	_save_binds()
	return PackedStringArray(["bind: %s = %s" % [key_name, line]])


func _bind_lines() -> PackedStringArray:
	if _binds.is_empty():
		return PackedStringArray(["bind: none — bind <key> \"<line>[; <line>]\" (persisted in %s)" % binds_path])
	var out := PackedStringArray(["binds (%s):" % binds_path])
	for keycode in _sorted_bind_keys():
		out.append("  %s = %s" % [OS.get_keycode_string(int(keycode)), String(_binds[keycode])])
	return out


## Bind keycodes ordered by their display name, so `bind` and `keys` list them the same way every time.
func _sorted_bind_keys() -> Array:
	var keys: Array = _binds.keys()
	keys.sort_custom(_bind_key_name_asc)
	return keys


## Comparator for _sorted_bind_keys — display name ascending. A named static, like _score_desc, so it reads at
## the call site and a test can reach it.
static func _bind_key_name_asc(a: Variant, b: Variant) -> bool:
	return OS.get_keycode_string(int(a)) < OS.get_keycode_string(int(b))


## Who already owns this raw keycode, or "" if it is free. This console's toggle first (it is not in the walk),
## then every other `toggle_key` export in the tree — the same discovery `keys` prints.
func _reserved_key_owner(keycode: int) -> String:
	if keycode == toggle_key:
		return "this console's toggle_key"
	for pair in _toggle_key_pairs():
		if int(pair[1]) == keycode:
			return "%s.toggle_key" % String(pair[0])
	return ""


## Fire a bound key: print which bind, then run its chain in order. Called from _input while the console is
## CLOSED — echo/_add_line append regardless of visibility, so the transcript is waiting the next time it opens.
func _fire_bind(keycode: int) -> void:
	var line := String(_binds.get(keycode, ""))
	if line.is_empty():
		return
	_add_line("bind %s:" % OS.get_keycode_string(keycode), hint_color)
	for part in split_chain(line):
		_run_scripted(part)
	_finish_output()


## Binds fire ONLY with no debug surface up (the menu's editors and this console's own field are text entry —
## typing `g` into either must never run a bind) and only when no LineEdit/TextEdit anywhere owns focus (the ATM's
## amount field, the name-entry dialog): _input runs BEFORE _gui_input, so a bound letter would otherwise be
## consumed out from under the caret. Deliberately NOT gated on InputManager.any_modal_open() — a dev key over the
## Options or inventory screen is legitimate, and the focus check already covers the one thing that would break.
func _binds_can_fire() -> bool:
	var tree := get_tree()
	if tree == null:
		return false
	for surface in tree.get_nodes_in_group(GroupsScript.DEBUG_SURFACE):
		if is_instance_valid(surface) and surface.has_method(&"is_open") and bool(surface.call(&"is_open")):
			return false
	var viewport := get_viewport()
	if viewport != null:
		var focus := viewport.gui_get_focus_owner()
		if focus is LineEdit or focus is TextEdit:
			return false
	return true


## Read `binds_path`. Tolerant of a hand-edited file: an unknown key name, a non-String value, a blank line, or a
## key that collides with our own toggle is skipped rather than crashing the boot. Never touches the tree, so an
## off-tree console can round-trip its file (tests/test_debug_console_exec.gd).
## ⭐A file that EXISTS but will not parse is reported, not swallowed: ConfigFile.load stops at the bad line, so
## the binds after it are invisible here — and the next `bind` would then save only what loaded, silently
## dropping the rest. The line names the file so the developer fixes or deletes it before binding again.
func _load_binds() -> void:
	_binds.clear()
	var cfg := ConfigFile.new()
	var err := cfg.load(binds_path)
	if err != OK:
		if FileAccess.file_exists(binds_path):
			_add_line("bind: %s exists but would not load (%s) — its binds are ignored, and the next `bind` overwrites it; fix or delete the file" % [binds_path, error_string(err)], warn_color)
		return   # otherwise no file yet — the normal first-run state
	if not cfg.has_section(BINDS_SECTION):
		return
	for key_name in cfg.get_section_keys(BINDS_SECTION):
		var keycode := bind_key_from_word(String(key_name))
		var value: Variant = cfg.get_value(BINDS_SECTION, key_name, "")
		if keycode == KEY_NONE or keycode == toggle_key or not (value is String):
			continue
		var line := String(value).strip_edges()
		if line.is_empty():
			continue
		_binds[keycode] = line


## Write `binds_path`. ⭐user:// ONLY: `binds_path` is an export a scene could point anywhere, and this console
## must never write a project file (a res:// bind file would be a cheat surface an export ships) — a path outside
## user:// keeps the binds live for the session and says so, rather than writing.
func _save_binds() -> void:
	if not binds_path.begins_with("user://"):
		_add_line("bind: not saved — binds_path must live under user:// (got %s); the bind works until this console is rebuilt" % binds_path, error_color)
		return
	var cfg := ConfigFile.new()
	for keycode in _binds.keys():
		cfg.set_value(BINDS_SECTION, OS.get_keycode_string(int(keycode)), String(_binds[keycode]))
	var err := cfg.save(binds_path)
	if err != OK:
		_add_line("bind: could not write %s (%s)" % [binds_path, error_string(err)], error_color)


# ---------------------------------------------------------------------------------------------------
# Pure helpers (static — covered off-tree by tests/test_debug_console_exec.gd)
# ---------------------------------------------------------------------------------------------------

## A command file's runnable lines: one per line, whitespace-trimmed, blank and `#`-comment lines dropped. CRLF
## tolerant — user:// files get hand-edited in Notepad.
static func exec_lines(text: String) -> PackedStringArray:
	var out := PackedStringArray()
	for raw in text.split("\n"):
		var line := raw.strip_edges()
		if line.is_empty() or line.begins_with("#"):
			continue
		out.append(line)
	return out


## Split a `;`-chained line into its commands, honouring "double quotes" so `give "big ; sword"` survives.
## Segments are trimmed and empty ones dropped (`god;;` is one command). Quotes are KEPT in each part —
## DebugCommands.tokenize strips them later.
static func split_chain(line: String) -> PackedStringArray:
	var out := PackedStringArray()
	var cur := ""
	var in_quote := false
	for i in line.length():
		var ch := line[i]
		if ch == "\"":
			in_quote = not in_quote
		if ch == ";" and not in_quote:
			var part := cur.strip_edges()
			if not part.is_empty():
				out.append(part)
			cur = ""
			continue
		cur += ch
	var last := cur.strip_edges()
	if not last.is_empty():
		out.append(last)
	return out


## Where an exec file lives: a res:// or user:// path is used as-is, anything else is a bare name under user://.
## Blank stays blank (the caller reports it). Read-only for res:// — nothing here ever WRITES a project file.
static func resolve_exec_path(file: String) -> String:
	var n := file.strip_edges()
	if n.is_empty():
		return ""
	if n.begins_with("res://") or n.begins_with("user://"):
		return n
	return "user://" + n


## The two user args this console honours, from OS.get_cmdline_user_args() (the day_night_shots.gd:37 idiom —
## user args are everything AFTER a bare `--`/`++`, so on a real command line or in Main Run Args they read
## `-- "--exec=god on; tp 1 2 3"`; the engine never sees them):
##   --exec=<line;line>   lines to run after the autoexec (split_chain; may repeat, in order)
##   --autoexec=<path>    replaces autoexec_path (resolved like an exec name)
## Returns {"exec": PackedStringArray, "autoexec": String} — "autoexec" is "" when not given.
static func parse_cmdline(args: PackedStringArray) -> Dictionary:
	var lines := PackedStringArray()
	var autoexec := ""
	for raw in args:
		var arg := String(raw)
		if arg.begins_with(EXEC_ARG_PREFIX):
			lines.append_array(split_chain(arg.trim_prefix(EXEC_ARG_PREFIX)))
		elif arg.begins_with(AUTOEXEC_ARG_PREFIX):
			autoexec = resolve_exec_path(arg.trim_prefix(AUTOEXEC_ARG_PREFIX))
	return {"exec": lines, "autoexec": autoexec}


## A typed key word to a raw keycode, KEY_NONE when it is not one. Accepts Godot's own names case-insensitively
## ("F6", "PageUp", "Kp Add"), the enum spelling ("KEY_KP_ADD", "kp_add" — underscores become spaces) and single
## characters ("g", "5"). Modifier combos ("Ctrl+F6") are REFUSED: the fire path compares the bare `keycode`, the
## same as toggle_key, so a masked value could never match.
static func bind_key_from_word(word: String) -> int:
	var w := word.strip_edges()
	if w.is_empty() or w.contains("+"):
		return KEY_NONE
	if w.to_upper().begins_with("KEY_"):
		w = w.substr(4)
	w = w.replace("_", " ")
	var found := int(OS.find_keycode_from_string(w))
	if found == KEY_NONE:
		found = int(OS.find_keycode_from_string(w.capitalize()))   # "kp add" -> "Kp Add"
	if found == KEY_NONE:
		found = int(OS.find_keycode_from_string(w.to_upper()))
	return found


## A mistyped command answers with the nearest names rather than a bare rejection. String.similarity() is a
## bigram score, so a prefix match ("gi" -> "give") can score poorly; a literal prefix is promoted above every
## fuzzy hit because it is the strongest hint there is.
func _report_unknown(word: String) -> void:
	_add_line(UNKNOWN_COMMAND % word, error_color)
	var guesses := _closest(word)
	if not guesses.is_empty():
		_add_line(DID_YOU_MEAN % " ".join(guesses), hint_color)


func _closest(word: String) -> PackedStringArray:
	var probe := word.to_lower()
	var names: PackedStringArray = DebugCommandsScript.names()
	var scored: Array[Array] = []
	for candidate in names:
		var score := probe.similarity(candidate)
		if candidate.begins_with(probe):
			score = maxf(score, 0.99)
		if score >= suggestion_threshold:
			scored.append([score, candidate])
	scored.sort_custom(_score_desc)
	var out := PackedStringArray()
	for entry in scored:
		if out.size() >= maxi(1, suggestion_count):
			break
		out.append(String(entry[1]))
	return out


## Comparator for _closest's [score, name] pairs — highest score first. A named static rather than an inline
## lambda so it is readable at the call site and reachable from a test.
static func _score_desc(a: Array, b: Array) -> bool:
	return float(a[0]) > float(b[0])


## Print whatever a module returned, defensively. The contract says a module returns PackedStringArray and
## never null — this survives it breaking that contract anyway, because a console that crashes on a bad command
## has failed at the one job it has.
func _print_lines(value: Variant, color: Color) -> void:
	if value is PackedStringArray:
		for line in (value as PackedStringArray):
			_add_line(line, color)
	elif value is Array:
		for line in (value as Array):
			_add_line(str(line), color)


# ---------------------------------------------------------------------------------------------------
# Input
# ---------------------------------------------------------------------------------------------------

## _input, NOT _unhandled_input: the field takes focus while the console is open, and a focused LineEdit marks
## printable keys handled in _gui_input — which runs BEFORE _unhandled_input but AFTER _input. Handling the
## toggle here is what makes it work with the caret in the field, and consuming it is what stops the opening
## backtick from typing itself.
func _input(event: InputEvent) -> void:
	if not _enabled:
		return
	# ⭐KEEP THE CARET IN THE FIELD — the other half of the text-entry contract. Nothing about an OPEN console stops
	# a printable key reaching gameplay; the only thing that does is a FOCUSED LineEdit marking it handled in
	# _gui_input, before the _unhandled_input consumers see it. Let focus drift and `1`..`0` swap weapons through
	# hotbar.gd:128, `q`/`v`/`j`/`i`/`c` open Pip-Boy tabs, and `t` opens the wait screen — all while you are
	# typing a command. A click on the log, the margins or the panel background can move focus off the field, so
	# any mouse press while we are up re-grabs it. DEFERRED, so it lands after the GUI layer has finished its own
	# focus bookkeeping for that click; grab_focus on an already-focused control is a no-op, so this never
	# disturbs a click-drag text selection inside the field itself.
	if _is_open and event is InputEventMouseButton and (event as InputEventMouseButton).pressed:
		if is_instance_valid(_field):
			_field.call_deferred(&"grab_focus")
	# Escape via the ACTION so a controller's cancel button works too, and consumed so it cannot ALSO reach
	# OptionsMenu behind us (the house rule on every hotkey branch in this project).
	if _is_open and event.is_action_pressed(&"ui_cancel"):
		close()
		get_viewport().set_input_as_handled()
		return
	if not (event is InputEventKey):
		return
	var key := event as InputEventKey
	if not key.pressed or key.echo:   # ignore auto-repeat, the debug_overlay.gd:67 idiom
		return
	if key.keycode == toggle_key:
		var was := _is_open
		toggle()
		# Consume ONLY if the toggle actually acted. A refused open (another modal owns the cursor) must let the
		# key fall through — it may be a legitimate character in that screen's own text field.
		if _is_open != was:
			get_viewport().set_input_as_handled()
		return
	if not _is_open:
		# BINDS fire only while this console is CLOSED (and no other surface / text field is up — see
		# _binds_can_fire). Same raw-keycode compare as the toggle above, and consumed for the same reason: a bound
		# `g` must not ALSO reach the EVENT-driven consumers behind us (hotbar, Pip-Boy tabs, PlayerDebug's
		# End/Home, an autoload's `_unhandled_input`). Consuming does NOT hide the key from POLLED actions —
		# `Input.is_action_pressed` still sees the physical key, exactly as with the toggle — so binding a movement
		# or fire key runs the line AND the verb. Pick a free key (F5..F12, the keypad).
		if not _binds.is_empty() and _binds.has(key.keycode) and _binds_can_fire():
			_fire_bind(key.keycode)
			get_viewport().set_input_as_handled()
		return
	match key.keycode:
		KEY_TAB:
			# Consumed here or the GUI layer moves focus off the field instead of completing.
			_complete()
			get_viewport().set_input_as_handled()
		KEY_UP:
			_walk_history(-1)
			get_viewport().set_input_as_handled()
		KEY_DOWN:
			_walk_history(1)
			get_viewport().set_input_as_handled()
		KEY_ENTER, KEY_KP_ENTER:
			# The field owns Enter while it has focus (text_submitted). This is only the fallback for focus
			# having drifted — a click on the log steals it — so the key is never dead.
			if is_instance_valid(_field) and not _field.has_focus():
				_on_submitted(_field.text)
				get_viewport().set_input_as_handled()


func _on_submitted(text: String) -> void:
	run_line(text)
	# run_line can reload the scene or warp levels; if that took this node with it, stop touching its children.
	if not is_instance_valid(_field):
		return
	_field.text = ""
	_set_matches(PackedStringArray())
	if _is_open and not _field.has_focus():
		_field.grab_focus()


## Tab completion. The candidate list is drawn as an in-canvas Label — NEVER a PopupMenu: project.godot sets
## embed_subwindows=false, so any native popup opens as its own OS window that escapes the retro viewport
## (desktop-resolution glyphs, no PS1 warp) and in exclusive fullscreen may never show at all.
func _complete() -> void:
	if not is_instance_valid(_field):
		return
	var result: Dictionary = DebugCommandsScript.complete(_field.text, _completion_sources())
	var line: String = result.get("line", _field.text)
	var matches: PackedStringArray = result.get("matches", PackedStringArray())
	_set_field(line)
	if matches.size() > 1:
		_set_matches(matches)
	else:
		_set_matches(PackedStringArray())


## Live completion ids, merged from both action modules plus the command names this console owns. Rebuilt on
## every Tab (the modules cache their own disk scans — that is their contract, not ours) so an id that appeared
## at runtime, like a story flag that was just set, completes without a restart.
func _completion_sources() -> Dictionary:
	var sources: Dictionary = {}
	var from_player: Variant = DebugActionsPlayerScript.sources()
	if from_player is Dictionary:
		sources.merge(from_player as Dictionary)
	var from_world: Variant = DebugActionsWorldScript.sources()
	if from_world is Dictionary:
		sources.merge(from_world as Dictionary)
	var command_key: StringName = DebugCommandsScript.SOURCE_KEYS[DebugCommandsScript.Kind.COMMAND]
	sources[command_key] = DebugCommandsScript.names()
	return sources


func _set_field(line: String) -> void:
	_field.text = line
	_field.caret_column = line.length()


func _remember(line: String) -> void:
	_history_pos = -1
	_draft = ""
	if _history.size() > 0 and _history[_history.size() - 1] == line:
		return   # don't stack a repeated command
	_history.append(line)
	var cap := maxi(1, history_lines)
	while _history.size() > cap:
		_history.remove_at(0)


## Up (step -1) walks toward older commands, Down (+1) back toward the fresh line — which restores the
## half-typed draft that browsing interrupted rather than clearing it.
func _walk_history(step: int) -> void:
	if _history.is_empty() or not is_instance_valid(_field):
		return
	if _history_pos == -1:
		if step > 0:
			return
		_draft = _field.text
		_history_pos = _history.size() - 1
	else:
		var next := _history_pos + step
		if next >= _history.size():
			_history_pos = -1
			_set_field(_draft)
			return
		_history_pos = maxi(0, next)
	_set_field(_history[_history_pos])


# ---------------------------------------------------------------------------------------------------
# The log
# ---------------------------------------------------------------------------------------------------

## THE ONE APPEND PATH — every echo, prompt, result and error lands here (the menu's output reaches it through
## echo()), so this single hook is also the whole stdout mirror. Cheap: one print per line, nothing per frame.
func _add_line(text: String, color: Color) -> void:
	if not is_instance_valid(_log_box):
		return
	if mirror_to_stdout:
		print(MIRROR_PREFIX + text)
	var line := Label.new()
	_style_label(line, color)
	line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	line.text = text
	_log_box.add_child(line)


## Cap the scrollback and pin the view to the newest line. Called once per batch rather than per line so a
## 60-line `help` dump trims and scrolls exactly once.
func _finish_output() -> void:
	_trim_scrollback()
	call_deferred(&"_pin_to_bottom")


func _trim_scrollback() -> void:
	if not is_instance_valid(_log_box):
		return
	var cap := maxi(1, scrollback_lines)
	while _log_box.get_child_count() > cap:
		var oldest := _log_box.get_child(0)
		# remove_child FIRST: queue_free is deferred, so the child would still be counted on the next pass of
		# this loop and we would spin.
		_log_box.remove_child(oldest)
		oldest.queue_free()


func _clear_log() -> void:
	if not is_instance_valid(_log_box):
		return
	for child in _log_box.get_children():
		_log_box.remove_child(child)
		child.queue_free()


## Scroll to the newest line. Driven from TWO places on purpose: the deferred call after a batch, and the log
## box's own `resized` signal. Setting scroll_vertical clamps against the scrollbar's CURRENT max, which has
## not necessarily been recomputed at the moment new lines are added — the resize hook is what catches the
## frame where it has.
func _pin_to_bottom() -> void:
	if not is_instance_valid(_scroll) or not is_instance_valid(_log_box):
		return
	var bottom := _log_box.size.y
	var bar := _scroll.get_v_scroll_bar()
	if bar != null:
		bottom = maxf(bottom, float(bar.max_value))
	_scroll.scroll_vertical = int(bottom)


## The completion candidates, on ONE clipped line. The label keeps its reserved height whether or not it has
## text, so completing never resizes the row stack and makes the log jump under the caret (the house
## "menus don't shift" rule, applied to a dev surface).
func _set_matches(matches: PackedStringArray) -> void:
	if not is_instance_valid(_matches):
		return
	if matches.is_empty():
		_matches.text = ""
		return
	var shown := matches
	var extra := 0
	var cap := maxi(1, completion_preview)
	if matches.size() > cap:
		shown = matches.slice(0, cap)
		extra = matches.size() - cap
	var text := "  ".join(shown)
	if extra > 0:
		text += MORE_MATCHES % extra
	_matches.text = text


# ---------------------------------------------------------------------------------------------------
# UI build (in code, no .tscn — the debug_overlay.gd shape)
# ---------------------------------------------------------------------------------------------------

## Build the whole panel by hand with EXPLICIT theme overrides.
##
## No MenuStyle.apply(): it stamps a `_menu_root` meta that a tree-global node_added hook uses to auto-wire
## hover + click SOUNDS onto every button added under that root, forever — and a debug surface must not blip at
## the player. That means NO theme reaches this CanvasLayer (nothing above it is a Control), so every font,
## colour and box below is an add_theme_*_override.
func _build_ui() -> void:
	_font = font if font != null else _system_mono()

	_root = Control.new()
	# TOP_WIDE: anchored to the top edge, full canvas width, `panel_height` tall. Because it is top-anchored,
	# content that overflows the band grows the panel DOWNWARD (visible) instead of re-centring it off-screen —
	# but every slot still keeps an honest minimum so it cannot eat the screen.
	_root.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	_root.offset_bottom = float(panel_height)
	# ⭐The documented exception to "a debug overlay must never eat clicks": this one is INTERACTIVE, so its root
	# STOPs so a click on the console can never fall through and fire the weapon behind it. Every readout Label
	# inside stays IGNORE.
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_root)

	var background := ColorRect.new()
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.color = panel_color
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(background)

	var edge := ColorRect.new()   # a 1px lip so the panel reads as a surface over the HUD, not a wash
	edge.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	edge.offset_top = -1.0
	edge.color = accent_color
	edge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(edge)

	var margins := MarginContainer.new()
	margins.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margins.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margins.add_theme_constant_override(&"margin_left", panel_margin)
	margins.add_theme_constant_override(&"margin_right", panel_margin)
	margins.add_theme_constant_override(&"margin_top", panel_margin)
	margins.add_theme_constant_override(&"margin_bottom", panel_margin)
	_root.add_child(margins)

	var column := VBoxContainer.new()
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_theme_constant_override(&"separation", 2)
	margins.add_child(column)

	# ⭐THE LOG MUST SCROLL, NOT GROW. A Label reports its full wrapped height as its minimum, so a bare growing
	# log would pump the panel taller with every line. The ScrollContainer takes the leftover height with a
	# pinned minimum and absorbs the rest.
	_scroll = ScrollContainer.new()
	_scroll.custom_minimum_size = Vector2(0.0, float(log_min_height))
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	# SHOW_NEVER, not DISABLED: DISABLED would fold the log's minimum WIDTH back into the container's own, and a
	# single long path would then push the panel wider than the 792px canvas. SHOW_NEVER keeps the axis
	# scrollable (so the minimum is not inherited) while hiding a bar we never want.
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
	_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	_scroll.mouse_filter = Control.MOUSE_FILTER_STOP   # so the wheel scrolls the log
	column.add_child(_scroll)

	_log_box = VBoxContainer.new()
	# ⭐SIZE_EXPAND_FILL is load-bearing: a ScrollContainer lays a child out at its MINIMUM size unless the child
	# carries the expand flag. Without it the log box would be as narrow as its longest word and the autowrap
	# below would wrap in the wrong place.
	_log_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_log_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_log_box.add_theme_constant_override(&"separation", 0)
	_scroll.add_child(_log_box)
	_log_box.resized.connect(_pin_to_bottom)

	_matches = Label.new()
	_style_label(_matches, hint_color)
	# clip_text collapses the label's minimum WIDTH to ~1px. An unclipped Label reports its full text width as
	# its minimum, and this one sits outside the ScrollContainer — it would widen the whole panel.
	_matches.clip_text = true
	_matches.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	column.add_child(_matches)
	# Pin the slot to the RENDERED line height (not font_size + a guess) so the row stack never changes height.
	_matches.custom_minimum_size = Vector2(0.0, float(_matches.get_line_height()))

	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override(&"separation", 2)
	column.add_child(row)

	var prompt := Label.new()
	_style_label(prompt, accent_color)
	prompt.text = prompt_glyph
	row.add_child(prompt)

	_field = LineEdit.new()
	_field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# Two non-obvious project contracts on every LineEdit here: typed text must never be looked up as a
	# translation msgid, and the engine's right-click menu is untranslatable English. Both are pinned by scene
	# tests on the shipped fields; a dev console honours them for consistency.
	_field.auto_translate_mode = Control.AUTO_TRANSLATE_MODE_DISABLED
	_field.context_menu_enabled = false
	_field.caret_blink = true
	_field.add_theme_font_size_override(&"font_size", font_size)
	if _font != null:
		_field.add_theme_font_override(&"font", _font)
	_field.add_theme_color_override(&"font_color", text_color)
	_field.add_theme_color_override(&"caret_color", accent_color)
	var box := _field_box()
	_field.add_theme_stylebox_override(&"normal", box)
	_field.add_theme_stylebox_override(&"focus", box)   # the field is always focused; a focus ring adds nothing
	_field.text_submitted.connect(_on_submitted)
	row.add_child(_field)


func _style_label(label: Label, color: Color) -> void:
	label.add_theme_font_size_override(&"font_size", font_size)
	if _font != null:
		label.add_theme_font_override(&"font", _font)
	label.add_theme_color_override(&"font_color", color)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE


func _field_box() -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = field_color
	box.content_margin_left = 4.0
	box.content_margin_right = 4.0
	box.content_margin_top = 2.0
	box.content_margin_bottom = 2.0
	return box


## A fixed-pitch face by family name, the same idiom as resources/ui/futura_system_font.tres: ask the OS for the
## first family it actually has, ending on the generic "monospace" so a non-Windows box still lands on one.
func _system_mono() -> Font:
	var system := SystemFont.new()
	system.font_names = mono_families
	return system
