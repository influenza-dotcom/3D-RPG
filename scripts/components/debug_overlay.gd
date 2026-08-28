class_name DebugOverlay
extends CanvasLayer

## Drop-in RUNTIME debug HUD: live perf + content stats with rolling line graphs (#10 profiler + #12 graphs). Drop
## it into game.tscn (or any scene) and press `toggle_key` (F3 by default) while playing to show/hide it. READ-ONLY:
## it only samples Engine / Performance / group counts and draws an overlay — it never touches gameplay. The graph
## math (push_capped / graph_points) is pure + unit-tested; the live sampling + draw are play-verified.
##
## Below the perf readout it paints three optional blocks, each a sample_state (impure, guarded) -> player_state_text
## (pure, unit-tested) pair: the game-state block (HP / stamina / wallet / clock / disk writes), the STEALTH block
## (show_stealth) and the INPUT / MODAL lines (show_input_state). This file is in ScanText.SKIP_FILES: every string
## it paints is developer copy, so raw literals are legal HERE and nowhere upstream of it.

## Runtime error/warning capture: preloaded (NOT the global ErrorSink class_name) so a not-yet-rescanned editor
## cache can't cascade into "Could not find type ErrorSink". See [[new-classname-not-registered-cascade]].
const ErrorSinkScript := preload("res://scripts/components/error_sink.gd")
const ERROR_LOG_PATH := "user://session_errors.log"
## The stealth block's two readers, preloaded BY PATH for the same stale-global-class-cache reason as ErrorSinkScript
## (debug_actions_world.gd:55-59 reaches Perception.State the same way, and never as `Perception.State` by class_name).
## Their enums are read as the DICTIONARIES they are at runtime (enum_name), so a reordered or renamed state can
## never make the histogram letters lie — the names come from the source enum, not from a table copied here.
const PerceptionScript := preload("res://scripts/npc/perception.gd")
const StealthStatusScript := preload("res://scripts/player/stealth_status.gd")

@export var toggle_key: Key = KEY_F3
@export var start_visible: bool = false
@export var sample_interval: float = 0.25   ## seconds between samples (text + a new graph point)
@export_range(8, 600) var history: int = 120  ## samples kept per graph series (the graph's width in points)
@export var capture_errors: bool = true            ## install a runtime error/warning sink (debug builds only)
@export var write_error_log_on_exit: bool = true   ## dump captured errors to user://session_errors.log on quit
## Append a live game-state block (HP / stamina / wallet / bank / position / clock / level / disk writes) under
## the perf readout. Off-by-default would hide the half of this HUD a designer actually wants, so it ships on;
## turn it off for a pure frame-time capture where the extra sampling would be noise. (The SANDBOX SAVES ON
## warning is exempt from this knob — see _process.)
@export var show_player_state: bool = true
## Append the STEALTH block under the state block: the raw light / carried-light / noise inputs behind the HUD's
## [HIDDEN]/[DANGER] word, the aggregated StealthStatus level + meter + spotter, and a per-Perception.State census
## of the living cast ("aware U3 D1 A0 I2"). The two numbers that decide the HUD word are otherwise invisible in-game
## (memory flashlight-stealth-penalty: light_exposure saturates at 1.0, which is why carried_light is a SECOND field —
## a bug you can only see with both on screen). Sampled at sample_interval, never per frame: it walks Groups.NPC.
@export var show_stealth: bool = true
## Append the INPUT / MODAL lines: who owns the cursor (Input.mouse_mode), the pause, the control gate
## (InputManager.gameplay_suppressed), the cinematic lock (world_frozen), which registered modal screens are open,
## whether a dialogue is active, which debug surface (console / menu) is up, and the GUI focus owner. The recurring
## bug class here is two screens fighting over Escape and the loser restoring a CAPTURED cursor under a menu that is
## still up (InputManager.gd:150-151, atm_screen.gd:18-20) — mouse_mode and gameplay_suppressed() are two independent
## halves (mouse_input.gd:31/39-45) and this is the only place both are visible at once. Lives under
## PROCESS_MODE_ALWAYS, so it stays live through the dialogue pause it exists to diagnose.
@export var show_input_state: bool = true

## The standing sandbox warning, painted as the FIRST line of the state block while GameState.sandbox_active().
## The save sandbox is session-only (a crash or relaunch boots the REAL profile), so a dev who forgets it is on
## loses the run — this line is what stops that. Kept as a const because it is painted from two sites (the state
## block, and _process when show_player_state is off), and both must read identically.
const SANDBOX_LINE := "SANDBOX SAVES ON"

var _text: Label = null
var _graph: _Graph = null
var _t: float = 0.0
var _fps := PackedFloat32Array()
var _frame_ms := PackedFloat32Array()
var _sink = null  ## an ErrorSink while installed (untyped: avoid annotating with the new global class_name)


func _ready() -> void:
	layer = 128  # above the game HUD
	# DialogueManager owns the only gameplay pause in this project, and a paused tree stops _process AND
	# _input — which used to make this HUD impossible to open or read during a conversation, i.e. exactly when
	# you are debugging a stuck one. Every screen autoload runs ALWAYS for the same reason.
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = start_visible
	var panel := PanelContainer.new()
	panel.position = Vector2(8, 8)
	panel.modulate = Color(1, 1, 1, 0.92)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE  # a debug overlay must never eat clicks (project convention, cf. player_hud)
	add_child(panel)
	var box := VBoxContainer.new()
	box.custom_minimum_size = Vector2(190, 0)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(box)
	_text = Label.new()
	_text.add_theme_font_size_override("font_size", 12)
	_text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(_text)
	_graph = _Graph.new()
	_graph.custom_minimum_size = Vector2(190, 80)
	_graph.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(_graph)
	_text.text = "Debug overlay"
	# Runtime error/warning capture: a Logger that counts every push_error/push_warning/engine error this session.
	# Debug-build only, so a release build carries zero logging overhead. Torn down (uninstall) in _exit_tree.
	if capture_errors and OS.is_debug_build():
		_sink = ErrorSinkScript.new()
		_sink.install()


## Toggle on the configured key (a dev key, not a rebindable action). Ignores key echoes.
func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and (event as InputEventKey).keycode == toggle_key:
		visible = not visible
		get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	if not visible:
		return
	_t -= delta
	if _t > 0.0:
		return
	_t = sample_interval
	var fps := Engine.get_frames_per_second()
	var frame_ms := float(Performance.get_monitor(Performance.TIME_PROCESS)) * 1000.0
	var draws := int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
	var mem_mb := float(Performance.get_monitor(Performance.MEMORY_STATIC)) / 1048576.0
	var nodes := int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
	var npcs := get_tree().get_nodes_in_group(Groups.NPC).size() if is_inside_tree() else 0
	var txt := "FPS %d   (%.1f ms)\nDraw calls %d\nStatic mem %.1f MB\nNodes %d\nNPCs %d" % [fps, frame_ms, draws, mem_mb, nodes, npcs]
	if _sink != null:
		txt += "\nErrors %d   Warn %d" % [_sink.error_count, _sink.warning_count]
	if show_player_state:
		txt += "\n" + player_state_text(sample_state(get_tree(), show_stealth, show_input_state))
	elif sandbox_active():
		# A perf-only capture must still shout about the sandbox: the state block is where the warning normally
		# lives, and hiding the block must not hide the one line that protects the real profile.
		txt += "\n" + SANDBOX_LINE
	_text.text = txt
	_fps = push_capped(_fps, float(fps), history)
	_frame_ms = push_capped(_frame_ms, frame_ms, history)
	_graph.fps = _fps
	_graph.frame_ms = _frame_ms
	_graph.queue_redraw()


## Tear down the error sink: deregister BEFORE the object frees (the engine holds a raw pointer to a live logger,
## so freeing an installed one dangles it), optionally leaving a post-mortem log. Logger may be RefCounted
## (auto-freed on ref drop) or a bare Object (must be freed) — handle both. Guarded so a never-installed overlay
## (an off-tree `.new()` in a test, or a release build) is a clean no-op.
func _exit_tree() -> void:
	if _sink == null:
		return
	_sink.uninstall()
	if write_error_log_on_exit and _sink.total() > 0:
		_sink.write_log(ERROR_LOG_PATH)
	if _sink is RefCounted:
		_sink = null
	else:
		_sink.free()
		_sink = null


# --- live game-state block ------------------------------------------------------------------------------------

## Read the live game-state facts the state block shows. IMPURE (walks the tree and reads autoloads) and every
## read is guarded, because each of these can legitimately be absent: the player is freed and rebuilt on death
## and on every level change, and this overlay is also droppable into a menu scene with no player at all.
##
## Reads go through `Object.get(&"prop")` / `has_method` rather than a typed reference, so the overlay stays
## decoupled from Player's class — the project's duck-typed-read convention for host properties.
##
## `want_stealth` / `want_input` gate the two 2026-08-18 blocks (the exports above): both are ADDITIVE trailing
## arguments defaulting to on, so the one-argument call the tests and the older callers use keeps working. The
## stealth block is the only part that walks a group, and it is skipped outright when off — the flag is a cost
## knob, not a display knob.
static func sample_state(tree: SceneTree, want_stealth: bool = true, want_input: bool = true) -> Dictionary:
	var facts := {}
	if tree == null:
		return facts
	# Groups.human_player excludes recruited companions, which share the Player group.
	var player: Node = Groups.human_player(tree)
	if player != null and is_instance_valid(player):
		facts["hp"] = float(player.get(&"hp"))
		facts["max_hp"] = float(player.get(&"max_hp"))
		facts["stamina"] = float(player.get(&"stamina"))
		if player.has_method(&"stamina_max"):
			# Recomputed live from endurance + status modifiers, so it is never cached.
			facts["max_stamina"] = float(player.call(&"stamina_max"))
		facts["money"] = float(player.get(&"money"))
		var body := player as Node3D
		if body != null:
			facts["pos"] = body.global_position
		if want_stealth:
			_sample_stealth(facts, player, tree)
	# Autoloads are up by the time any node in the tree processes, so these are plain reads — but stay null-safe
	# so the same helper can be called from a bare harness that booted without the full autoload set.
	if GameState != null:
		facts["account"] = float(GameState.account)
		facts["level"] = String(GameState.current_level_path).get_file().get_basename()
		# Disk-write telemetry + the sandbox latch are ADDITIVE GameState members (2026-08-18). Read duck-typed —
		# Object.get() -> null, has_method() -> false — so this overlay still boots on a GameState build that
		# predates them (and because a per-frame autoload read is the reimport-transient canary; see
		# per-frame-autoload-read-canary). A missing member simply leaves the fact out, and the block paints no line.
		var raw_saves: Variant = GameState.get(&"save_count")
		if raw_saves is int:
			facts["saves"] = int(raw_saves)
			var raw_msec: Variant = GameState.get(&"last_save_msec")
			var last_msec := int(raw_msec) if raw_msec is int else -1
			# -1 = no write yet this session; otherwise seconds since the last _write_atomic attempt.
			facts["save_age"] = -1.0 if last_msec < 0 else float(Time.get_ticks_msec() - last_msec) / 1000.0
		if GameState.has_method(&"sandbox_active"):
			facts["sandbox"] = bool(GameState.call(&"sandbox_active"))
	if WorldClock != null:
		facts["time"] = float(WorldClock.time_of_day)
	if want_input:
		_sample_input(facts, tree)
	return facts


## The STEALTH facts (2026-08-18). Every read is a bare host FIELD or a duck-typed method: the two light meters and
## the noise radius are plain vars on the Player that the drop-ins WRITE (PlayerLightLevel stamps `light_exposure` +
## `carried_light` every sample_interval, player_light_level.gd:79-80; NoiseEmitter writes `noise_radius` per frame
## from NoiseEmitter.tick — the loudest of footsteps, the gunfire spike, and the jump/landing impact spike) and
## enemy Perception READS the same way — so this shows exactly the numbers the AI sees.
##
## Printed RAW, on purpose: `light_exposure` RESTS at 1.0 when no PlayerLightLevel is present (player.gd:314), so
## "1.00" means "fully lit OR unmeasured", never "measured bright" — the formatter must not dress it up. And a
## non-numeric read (an older Player, a stub host) leaves the fact out rather than painting a zero that reads as
## "pitch dark".
##
## ONE walk over Groups.NPC feeds both aggregates. is_instance_valid FIRST on every member (a queue_free'd body is
## listed for a frame, and `is` / any call on a freed instance crashes — the project rule), then:
##   - the census counts LIVING bodies (is_alive() gate — take_damage early-returns on the dead latch, so hp <= 0 can
##     still be grouped) by their Perception child's OWN `state`, i.e. what each NPC is doing regardless of target;
##   - the StealthStatus aggregate gets the SAME list the HUD passes (player.gd:2358 hands it the whole group, dead
##     included), so the level painted here can never disagree with the [HIDDEN]/[DANGER] word on screen.
static func _sample_stealth(facts: Dictionary, player: Node, tree: SceneTree) -> void:
	var light: Variant = player.get(&"light_exposure")
	if light is float or light is int:
		facts["light"] = float(light)
	var carried: Variant = player.get(&"carried_light")
	if carried is float or carried is int:
		facts["carried"] = float(carried)
	var noise: Variant = player.get(&"noise_radius")
	if noise is float or noise is int:
		facts["noise"] = float(noise)
	if player.has_method(&"is_crouching"):
		facts["crouch"] = bool(player.call(&"is_crouching"))

	# The histogram is keyed by the STATE NAME, in the enum's own declaration order, seeded to zero so every bucket
	# paints even when empty (a missing "A0" would read as "no such state"). The enum is taken into a Variant first:
	# at runtime a named enum IS its {NAME: value} Dictionary, and going through Variant keeps the analyzer out of the
	# "enum meta-type as a value" question entirely (a compile error here would cascade into everything that preloads
	# this file — the console and menu included).
	var states: Variant = PerceptionScript.State
	var census := {}
	if states is Dictionary:
		for key in (states as Dictionary).keys():
			census[String(key)] = 0
	var valid: Array = []
	var alive := 0
	for n in tree.get_nodes_in_group(Groups.NPC):
		if not is_instance_valid(n):
			continue
		valid.append(n)
		if not (n.has_method(&"is_alive") and bool(n.call(&"is_alive"))):
			continue
		alive += 1
		var per: Variant = n.get(&"_perception")
		if per == null or not is_instance_valid(per):
			continue
		var raw_state: Variant = per.get(&"state")
		if not (raw_state is int):
			continue
		var state_name := enum_name(states, int(raw_state))
		if census.has(state_name):
			census[state_name] = int(census[state_name]) + 1
	facts["aware"] = census
	facts["npcs_alive"] = alive

	# {level, meter, spotter} — the pure aggregate the HUD word is derived from (stealth_status.gd:19). The level is
	# stored as its NAME (resolved from StealthStatus.Level here) so the formatter stays pure over strings.
	var snap: Variant = StealthStatusScript.of_player(player, valid)
	if snap is Dictionary:
		var d: Dictionary = snap
		var levels: Variant = StealthStatusScript.Level
		facts["stealth_level"] = enum_name(levels, int(d.get(&"level", 0)))
		facts["stealth_meter"] = float(d.get(&"meter", 0.0))
		var spotter: Variant = d.get(&"spotter")
		var spotter_name := ""
		if spotter != null and is_instance_valid(spotter) and spotter is Node:
			spotter_name = String((spotter as Node).name)
		facts["spotter"] = spotter_name


## The INPUT / MODAL facts (2026-08-18). Every autoload read is guarded twice — `!= null` for a bare harness that
## booted without the full autoload set (the same reason sample_state guards GameState), then has_method / get() so
## an API rename degrades to a missing fact (a dash) instead of an invalid call.
##
## The open-modal NAMES come from InputManager's private `_modal_reg` (rows {screen, blocks_tabs}, InputManager.gd:
## 153-177). It is built LAZILY by the first query, so any_modal_open() is called FIRST — the read alone would see an
## empty list before the first menu ever opened. Read as data only (`get`, `is Array`, `is Dictionary`): this overlay
## must never take a compile-time dependency on the registry's shape.
static func _sample_input(facts: Dictionary, tree: SceneTree) -> void:
	facts["mouse"] = int(Input.mouse_mode)
	facts["paused"] = tree.paused
	if InputManager != null:
		if InputManager.has_method(&"any_modal_open"):
			facts["modal_open"] = bool(InputManager.call(&"any_modal_open"))
		if InputManager.has_method(&"gameplay_suppressed"):
			facts["suppressed"] = bool(InputManager.call(&"gameplay_suppressed"))
		if InputManager.has_method(&"world_frozen"):
			facts["frozen"] = bool(InputManager.call(&"world_frozen"))
		var names := PackedStringArray()
		var reg: Variant = InputManager.get(&"_modal_reg")
		if reg is Array:
			for e in (reg as Array):
				if not (e is Dictionary):
					continue
				var screen: Variant = (e as Dictionary).get("screen")
				if screen == null or not is_instance_valid(screen) or not screen.has_method(&"is_open"):
					continue
				if bool(screen.call(&"is_open")):
					names.append(String((screen as Node).name) if screen is Node else str(screen))
		facts["modals"] = names
	if DialogueManager != null and DialogueManager.has_method(&"is_active"):
		facts["dialogue"] = bool(DialogueManager.call(&"is_active"))
	# Which debug surface (console / menu) is up: the group is joined only past the debug gate, so this walk is 0-2
	# members. Duck-typed on is_open like the surfaces are to each other (debug_console.gd _close_other_surfaces).
	var surface := ""
	for s in tree.get_nodes_in_group(Groups.DEBUG_SURFACE):
		if is_instance_valid(s) and s.has_method(&"is_open") and bool(s.call(&"is_open")):
			surface = String(s.name)
			break
	facts["surface"] = surface
	# The GUI focus owner (the half of the text-entry contract a LineEdit carries; name_entry_dialog.gd:15-19).
	# Class, not name: code-built Controls carry auto names ("@LineEdit@42") that say nothing.
	var focus_text := ""
	if tree.root != null:
		# `focus_owner`, not `owner`: a local named `owner` would shadow Node.owner on this CanvasLayer.
		var focus_owner := tree.root.gui_get_focus_owner()
		if focus_owner != null and is_instance_valid(focus_owner):
			focus_text = focus_owner.get_class()
	facts["focus"] = focus_text


## The NAME of `value` in an enum read as the Dictionary it is at runtime ({NAME: value, ...}); the value as a
## string when nothing matches (drift, or a state this build does not know) or when `enum_dict` is not a Dictionary
## at all. Takes a Variant so a caller can hand it `SomeScript.SomeEnum` straight off a preloaded script (see
## _sample_stealth for why that goes through Variant). Pure.
static func enum_name(enum_dict: Variant, value: int) -> String:
	if not (enum_dict is Dictionary):
		return str(value)
	var d: Dictionary = enum_dict
	for key in d:
		if int(d[key]) == value:
			return String(key)
	return str(value)


## Input.mouse_mode as its bare name (VISIBLE / HIDDEN / CAPTURED / CONFINED / CONFINED_HIDDEN); "?<n>" for a mode
## this build does not know. Pure. A `match` is fine here — the Input.MOUSE_MODE_* constants are constant
## expressions, unlike an enum reached through a preloaded script (see debug_actions_world.gd _perception_state_text).
static func mouse_mode_name(mode: int) -> String:
	match mode:
		Input.MOUSE_MODE_VISIBLE:
			return "VISIBLE"
		Input.MOUSE_MODE_HIDDEN:
			return "HIDDEN"
		Input.MOUSE_MODE_CAPTURED:
			return "CAPTURED"
		Input.MOUSE_MODE_CONFINED:
			return "CONFINED"
		Input.MOUSE_MODE_CONFINED_HIDDEN:
			return "CONFINED_HIDDEN"
	return "?%d" % mode


## "aware U3 D1 A0 I2 · 6 alive" — one letter per state, in the CENSUS's key order (which _sample_stealth seeds from
## the enum's declaration order), so the letters can never disagree with the states they count. `alive` < 0 omits
## the tail. Empty census -> "aware -". Pure.
static func awareness_text(census: Dictionary, alive: int = -1) -> String:
	if census.is_empty():
		return "aware -"
	var bits := PackedStringArray()
	for key in census:
		var state_name := String(key)
		var letter := state_name.substr(0, 1) if state_name != "" else "?"
		bits.append("%s%d" % [letter, int(census[key])])
	var line := "aware " + " ".join(bits)
	if alive >= 0:
		line += " · %d alive" % alive
	return line


## Is the save sandbox on right now? Duck-typed for the same reason as sample_state; false on an older GameState.
static func sandbox_active() -> bool:
	if GameState == null or not GameState.has_method(&"sandbox_active"):
		return false
	return bool(GameState.call(&"sandbox_active"))


## Format the state block from already-gathered `facts`. PURE — no tree, no autoloads — so the layout is
## unit-testable and a missing fact degrades to a dash instead of a crash or a misleading zero.
static func player_state_text(facts: Dictionary) -> String:
	if facts.is_empty():
		return "no player"
	var lines := PackedStringArray()
	# The sandbox warning leads the block: it is the one line that must never scroll under HP/stamina/etc. — a
	# forgotten sandbox costs the whole session's progress on the next relaunch.
	if bool(facts.get("sandbox", false)):
		lines.append(SANDBOX_LINE)
	if facts.has("hp"):
		lines.append("HP %.0f/%.0f" % [float(facts["hp"]), float(facts.get("max_hp", 0.0))])
	if facts.has("stamina"):
		lines.append("Stam %.0f/%.0f" % [float(facts["stamina"]), float(facts.get("max_stamina", 0.0))])
	if facts.has("money") or facts.has("account"):
		lines.append("z %.0f   bank %.0f" % [float(facts.get("money", 0.0)), float(facts.get("account", 0.0))])
	if facts.has("pos"):
		var p: Vector3 = facts["pos"]
		lines.append("@ %.1f %.1f %.1f" % [p.x, p.y, p.z])
	if facts.has("time"):
		lines.append("%s  %s" % [clock_text(float(facts["time"])), String(facts.get("level", "-"))])
	elif facts.has("level"):
		lines.append(String(facts["level"]))
	if facts.has("saves"):
		# The disk-write counter: a number that climbs while you stand still is an autosave storm. A negative age
		# means no write has happened yet this session, which is a different fact from "0 seconds ago".
		var age := float(facts.get("save_age", -1.0))
		if age < 0.0:
			lines.append("saves %d · none yet" % int(facts["saves"]))
		else:
			lines.append("saves %d · %.0fs ago" % [int(facts["saves"]), age])
	# --- stealth (2026-08-18) — the raw inputs behind the HUD's [HIDDEN]/[DANGER] word ---------------------------
	if facts.has("light") or facts.has("carried") or facts.has("noise") or facts.has("crouch"):
		var bits := PackedStringArray()
		if facts.has("light"):
			bits.append("light %.2f" % float(facts["light"]))
		if facts.has("carried"):
			# The carried-light penalty is CONTINUOUS (LightStealthSettings lerps both multipliers from strength 0), so
			# any positive value is already costing sight range + detection speed — flag it, don't threshold it.
			var carried := float(facts["carried"])
			bits.append("carried %.2f%s" % [carried, " PENALTY" if carried > 0.0 else ""])
		if facts.has("noise"):
			bits.append("noise %.1fm" % float(facts["noise"]))
		if bool(facts.get("crouch", false)):
			bits.append("crouch")
		lines.append("  ".join(bits))
	if facts.has("stealth_level"):
		var stealth := "stealth %s %.2f" % [String(facts["stealth_level"]), float(facts.get("stealth_meter", 0.0))]
		var spotter := String(facts.get("spotter", ""))
		if spotter != "":
			stealth += " <- " + spotter
		lines.append(stealth)
	if facts.has("aware"):
		var census: Variant = facts["aware"]
		if census is Dictionary:
			lines.append(awareness_text(census, int(facts.get("npcs_alive", -1))))
	# --- input / modal (2026-08-18) — who owns the cursor, the pause and the player's hands ------------------------
	if facts.has("mouse"):
		lines.append("mouse %s  paused %s  supp %s  frz %s" % [
			mouse_mode_name(int(facts["mouse"])), _yn(facts, "paused"), _yn(facts, "suppressed"), _yn(facts, "frozen")])
		var modal_text := "-"
		var modals: Variant = facts.get("modals")
		if modals is PackedStringArray and not (modals as PackedStringArray).is_empty():
			modal_text = ",".join(modals as PackedStringArray)
		elif modals == null and bool(facts.get("modal_open", false)):
			modal_text = "?"  # any_modal_open() said yes but the registry could not be read — say so, never "-"
		var surface := String(facts.get("surface", ""))
		var focus := String(facts.get("focus", ""))
		lines.append("modal %s  dlg %s  dbg %s  focus %s" % [
			modal_text, _yn(facts, "dialogue"), surface if surface != "" else "-", focus if focus != "" else "-"])
	return "\n".join(lines)


## "Y" / "N" for a bool fact, "-" when it was never gathered (an autoload or method missing) — a missing gate must
## read as unknown, never as a reassuring N. Pure.
static func _yn(facts: Dictionary, key: String) -> String:
	if not facts.has(key):
		return "-"
	return "Y" if bool(facts[key]) else "N"


## A 0..1 time-of-day fraction as 24-hour HH:MM. Wraps rather than clamping, so a fraction that has drifted
## past 1.0 (or below 0) still reads as a real clock face instead of pinning at 23:59. Pure.
static func clock_text(t: float) -> String:
	var frac := fposmod(t, 1.0)
	var minutes := int(round(frac * 1440.0)) % 1440
	return "%02d:%02d" % [minutes / 60, minutes % 60]


# --- pure helpers (unit-tested) --------------------------------------------------------------------------------

## Append `v` to `buf` and keep only the last `cap` samples (a rolling window). Returns the new array (PackedArrays
## are value types, so callers reassign). Pure.
static func push_capped(buf: PackedFloat32Array, v: float, cap: int) -> PackedFloat32Array:
	buf.append(v)
	var n := maxi(1, cap)
	if buf.size() > n:
		buf = buf.slice(buf.size() - n)
	return buf


## Map `samples` to polyline points inside `rect`: x spread left->right across the samples, y mapping the value
## range [vmin, vmax] to bottom->top (a higher value draws higher). Clamped to the rect vertically. Pure.
static func graph_points(samples: PackedFloat32Array, rect: Rect2, vmin: float, vmax: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	var n := samples.size()
	if n == 0:
		return pts
	var span := maxf(0.0001, vmax - vmin)
	var denom := float(maxi(1, n - 1))
	for i in n:
		var x := rect.position.x + rect.size.x * (float(i) / denom)
		var frac := clampf((samples[i] - vmin) / span, 0.0, 1.0)
		var y := rect.position.y + rect.size.y * (1.0 - frac)  # high value -> top of the rect
		pts.append(Vector2(x, y))
	return pts


## The graph surface: two stacked line graphs (FPS on top, frame-time below), redrawn each sample. Inner so the
## overlay is one file; uses DebugOverlay's pure graph_points so the mapping is the tested one.
class _Graph extends Control:
	var fps := PackedFloat32Array()
	var frame_ms := PackedFloat32Array()

	func _draw() -> void:
		var half := size.y * 0.5
		_one(Rect2(0, 0, size.x, half), fps, 0.0, 120.0, Color(0.4, 1.0, 0.5), "FPS")
		_one(Rect2(0, half, size.x, half), frame_ms, 0.0, 33.3, Color(1.0, 0.82, 0.3), "ms")

	func _one(r: Rect2, buf: PackedFloat32Array, vmin: float, vmax: float, col: Color, label: String) -> void:
		draw_rect(r, Color(0, 0, 0, 0.25), true)
		var font := get_theme_default_font()
		if font != null:
			draw_string(font, Vector2(r.position.x + 2.0, r.position.y + 10.0), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(1, 1, 1, 0.5))
		var pts := DebugOverlay.graph_points(buf, r, vmin, vmax)
		for i in range(pts.size() - 1):
			draw_line(pts[i], pts[i + 1], col, 1.0)
