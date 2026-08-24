class_name DebugNoclip
extends Node

## Drop-in FREE-FLY (noclip) for the human player — DEBUG BUILDS ONLY. Drop it anywhere that outlives the level
## (the debug console/menu CanvasLayer, game.tscn, an autoload) and either press `toggle_key` or drive it from
## the console's `noclip` command through set_enabled().
##
## ⭐WHY IT FLIES THE REAL BODY INSTEAD OF SPAWNING A FREE CAMERA. A detached Camera3D that steals `current`
## renders the world WRONG twice over: InkOutline is a child of the player's own camera and warns when its parent
## is not a Camera3D (ink_outline.gd:323-327), so a second camera draws the world with no ink outline at all; and
## the first-person view-model is composited by ViewModelCamera parented under that same camera (head.gd:53), so
## it would be drawn from a viewpoint the hands are not at. Moving the BODY keeps the camera, the outline, the
## view-model, the HUD, the crosshair and the stealth light sampling exactly as they are in play — flying here is
## just "the player, with its own physics step switched off".
##
## ⭐HOW THE STEP IS SWITCHED OFF. Player._physics_process (player.gd:2151) is ONE ~175-line function that owns
## gravity, the input read, apply_velocity/move_and_slide and the fall-death timer. It is not delegated, and a
## child node cannot pre-empt it (Godot runs a parent's callback BEFORE its children's), so the only clean
## interception is player.set_physics_process(false) — precisely what die() does (player.gd:2835) and what the
## in-place revive undoes (player.gd:3173). With it off, move_and_slide (player.gd:2091) never runs, so there is
## no collision response and no gravity whatsoever: no collision_mask games are needed, and nothing in the world
## can push the body. This node then writes global_position itself from its own _physics_process.
##
## WHAT DELIBERATELY KEEPS RUNNING. MouseInput owns its own _process/_unhandled_input (mouse_input.gd:39/:30) and
## the body's yaw is applied from a signal callback (player.gd:2418), so LOOKING AROUND still works while flying.
## This node never disables MouseInput (die() does — that is why a corpse cannot look around). Crouch is likewise
## left alone on purpose: it runs its own _physics_process (crouch.gd:40) and the debug console's suspend_player()
## already snapshots that same bit, so a second owner of it would corrupt whichever restore ran last. The only
## symptom is a cosmetic camera dip while you hold the descend key, which reads as a fine "going down" tell.
##
## THE CONTINUOUS-FALL DEATH NEEDS NO TUNING KNOB HERE — BUT IT DOES NEED THE ACCUMULATOR CLEARED.
## _update_continuous_fall_death (player.gd:1201) is called FROM the player's own step (player.gd:2307), so it
## cannot tick while that step is off. The `god` command owns GameSettings.player_movement.max_continuous_fall_time
## — a PRELOADED SHARED .tres on an autoload — and a second snapshot/restore pair from here would corrupt whichever
## one ran last, so this file never touches that knob. What it DOES touch is the player's own `_continuous_fall_time`
## counter, which keeps whatever it had banked when the step stopped: _calm() zeroes it, so a flight always hands
## back a full fall budget instead of a part-spent one. Switching noclip off at altitude therefore drops you
## normally; `snap_to_ground_on_exit` usually turns that into a landing.
##
## This file paints no text: it is a movement driver, not a surface.

## Groups is NOT an autoload — it is a plain RefCounted holding the group-name consts plus the ONE rule for which
## PLAYER-group member is the human (companions join that group too). Preloaded by path, as every non-autoload
## registry in this project is.
const GroupsReg := preload("res://scripts/world/groups.gd")

## Printed on a key-driven toggle only (the console prints its own report for a command-driven one). Composed
## through a const rather than inlined so nothing in this file ever looks like an authored player-facing string.
const TOGGLE_REPORT := "DebugNoclip: %s"
const STATE_ON := "on"
const STATE_OFF := "off"
const REFUSED_NO_PLAYER := "DebugNoclip: no live player to fly"

## ESCAPE HATCH for the debug-build gate below. A release export must carry no cheat surface, so _ready() arms
## nothing unless OS.is_debug_build() — flip this only for a deliberate dev/QA build of the shipping export.
@export var force_in_release: bool = false
## A RAW DEV KEY, deliberately not a rebindable InputManager action (docs/AUTHORING_GUIDE.md:1994) — going the
## ActionCatalog route would drag a debug toggle through the four-surface keybind contract and boot validation.
## ⭐THE F-ROW IS ALMOST FULLY CLAIMED, so verify before moving this. F1 = DebugMenu (debug_menu.gd:67),
## F3 = DebugOverlay (debug_overlay.gd:14), F4 = DebugInspector (debug_inspector.gd:55), backtick = DebugConsole
## (debug_console.gd:64). F5/F9 are bound in project.godot to Quicksave/Quickload — and a quicksave also MOVES the
## player's checkpoint (GameState.gd:1009) and writes disk, so it is the worst key to fire from a toggle. F2 is
## the one free neighbour. F1..F4 carry no [input] binding in project.godot, so nothing else contests it.
@export var toggle_key: Key = KEY_F2
## Resolve the human player from the PLAYER group on demand. Turn off to fly ONLY the body wired below.
@export var find_player_automatically: bool = true
## Optional explicit body to fly, for a scene that wants one particular Player (a test bed, a split rig). Takes
## precedence over the group scan; left empty in the normal case.
@export var player_path: NodePath

@export_group("Flight")
## Metres per second along the camera basis. Multiplied by delta, so it is frame-rate independent.
@export var fly_speed: float = 8.0
## Multiplier applied while `action_boost` is held.
@export var boost_multiplier: float = 4.0
## Metres per second for the world-vertical rise/fall (`action_up` / `action_down`), independent of look pitch.
@export var vertical_speed: float = 6.0

@export_group("Actions")
## The SHIPPED gameplay actions (project.godot [input]) flight reuses, exposed so a designer can retarget them
## without touching code — the mouse_input.gd `alt_attack_action` idiom. Note the case: the movement four are
## lowercase, Crouch/Run are capitalised. Every read is guarded by InputMap.has_action, so a typo degrades to
## "not pressed" instead of pushing an engine error every frame (an engine error also fails GUT 9.6 runs).
@export var action_forward: StringName = &"forward"
@export var action_backward: StringName = &"backward"
@export var action_left: StringName = &"left"
@export var action_right: StringName = &"right"
@export var action_up: StringName = &"jump"
@export var action_down: StringName = &"Crouch"
@export var action_boost: StringName = &"Run"

@export_group("Landing")
## Re-arm the player's spawn ground-snap when flight ends, so switching off over a rooftop PLACES you on it
## instead of starting a fall. _snap_to_ground (player.gd:1983) raycasts down the body's own collision mask and
## only retries from the player's step while its frame budget lasts, so this must be stamped AFTER the physics
## step is handed back. Turn off to always fall from wherever you stopped.
@export var snap_to_ground_on_exit: bool = true
## How long after `off` a LIVE but still-frozen player is watched for and handed its step back. Counted in
## physics frames *in which gameplay holds the cursor* — frames spent under an open debug UI do not spend it, so
## this is "2 s of play at 60 fps", not 2 s of wall clock. See _tick_unfreeze_grace: it heals the ordering hole
## between this node and the console's suspend/restore pair, which no snapshot on either side can close. 0
## disables the heal entirely.
@export var unfreeze_grace_frames: int = 120

## False in a release build (unless force_in_release): every entry point returns early, so a shipped build has no
## fly surface at all.
var _armed: bool = false
var _flying: bool = false
## The body being flown. Typed Player, always paired with is_instance_valid() before use: `is`/`as`/a typed
## assignment all HARD-ERROR on a freed instance. The Player survives a GameRoot level swap (in game.tscn it is a
## SIBLING of GameRoot, not part of the level subtree it frees) but NOT a scene reload — quickload, and the
## RELOAD_LAST_SAVE / RELOAD_CHECKPOINT_FRESH death modes, all replace it with a fresh body.
var _player: Player = null
## The player's OWN physics-process bit as read at enable time, restored verbatim on disable so that flying a
## dead or already-frozen body and stopping again does not resurrect its step.
var _physics_was_on: bool = true
## Captured-cursor physics frames still budgeted to the post-flight self-heal (see _tick_unfreeze_grace). Armed
## by every _stop(), cleared by _start() — a new flight owns the bit itself, so a pending heal is moot.
var _grace_left: int = 0


func _ready() -> void:
	# DEBUG-BUILD GATE. Nothing below arms in a release export.
	_armed = OS.is_debug_build() or force_in_release
	# DialogueManager owns the only gameplay pause in this project; a paused tree would otherwise stop this
	# node's step and its toggle key mid-flight, leaving the player frozen with no way to switch back. Every
	# screen-level node in this project runs ALWAYS for the same reason (ink_outline.gd:348, wait_screen.gd:61).
	process_mode = Node.PROCESS_MODE_ALWAYS
	if not _armed:
		set_physics_process(false)
		set_process_unhandled_input(false)


## Restore the body if this node is torn down mid-flight (the console being freed, the game quitting). Without
## it the player would keep its physics step switched off with nothing left to switch it back on.
func _exit_tree() -> void:
	if _flying:
		_stop()


## The toggle is read from _unhandled_input, not _input: any focused UI — this suite's own console field
## included — gets first refusal on the key, and the event is consumed so it cannot also reach gameplay.
func _unhandled_input(event: InputEvent) -> void:
	if not _armed:
		return
	# KEY_NONE unbinds the dev key (the DebugInspector convention). Checked explicitly rather than left to the
	# comparison below, because KEY_NONE is 0 and plenty of real key events carry keycode 0 — a modifier-only or
	# unicode-only press would otherwise toggle flight on a node a designer deliberately unbound.
	if toggle_key == KEY_NONE:
		return
	if not (event is InputEventKey):
		return
	var key := event as InputEventKey
	if not key.pressed or key.echo or key.keycode != toggle_key:
		return
	get_viewport().set_input_as_handled()
	var want := not _flying
	var landed := set_enabled(want)
	if landed == want:
		print(TOGGLE_REPORT % (STATE_ON if landed else STATE_OFF))
	else:
		print(REFUSED_NO_PLAYER)  # the only way to be refused is "no live player"


## Turn flight on/off. Returns the RESULTING state, which is false — with nothing changed — when there is no
## live player to fly or the build is not armed. Idempotent in both directions.
func set_enabled(on: bool) -> bool:
	if not _armed:
		return false
	if not on:
		if _flying:
			_stop()
		return false
	# Already flying a body that is still alive: nothing to do. If the cached body has since been freed (a scene
	# reload) or died under us, fall through and stand down rather than reporting a flight that is no longer
	# happening.
	if _flying and is_instance_valid(_player) and _is_live(_player):
		return true
	var p: Player = _resolve_player()
	# ⭐NEVER START A FLIGHT ON A CORPSE. die() (player.gd:2835) owns the dead body's physics bit for the whole
	# cinematic and _respawn_at_checkpoint (player.gd:3173) hands it back at the end — a flight begun here would
	# re-assert the freeze every frame (see _physics_process) and stall that revive, leaving the just-respawned
	# player frozen wherever the tween dropped them. Refusing is also what makes this method's contract ("false
	# when there is no LIVE player") literally true instead of merely aspirational.
	if p != null and not _is_live(p):
		p = null
	if p == null:
		if _flying:
			_stop()
		return false
	if _flying:
		_stop()  # hand the OLD body back before adopting a new one
	_start(p)
	return _flying


func is_enabled() -> bool:
	return _flying


# --- internals --------------------------------------------------------------------------------------------


func _start(p: Player) -> void:
	_player = p
	_physics_was_on = p.is_physics_processing()
	p.set_physics_process(false)
	_calm(p)
	_flying = true
	_grace_left = 0


func _stop() -> void:
	# ⭐is_instance_valid() BEFORE the local is typed off the field: a freed instance crashes on the implicit type
	# check, the same trap `is` has (project rule). The Player is freed by a scene reload — a quickload from the
	# console can do exactly that mid-flight.
	var p: Player = null
	if is_instance_valid(_player):
		p = _player
	_player = null
	_flying = false
	if p == null:
		_grace_left = 0  # nothing left to hand back
		return
	_calm(p)
	# ⭐Stamp the ground-snap budget BEFORE handing the step back: the retry loop lives inside the player's own
	# _physics_process (player.gd:2162-2165) and does nothing while that step is off. GROUND_SNAP_RETRY_FRAMES is
	# read off the Player rather than duplicated here so the two budgets can never drift.
	if snap_to_ground_on_exit:
		p.set(&"_ground_snap_frames_left", Player.GROUND_SNAP_RETRY_FRAMES)
	# Restore EXACTLY the bit we snapshotted — except never in the direction that would resurrect a corpse: a
	# player killed mid-flight (an NPC can still shoot a frozen body) is inside die()'s cinematic, which owns
	# that bit, and handing its step back would fight the death tween.
	var resume := _physics_was_on and _is_live(p)
	p.set_physics_process(resume)
	# ⭐ARM THE SELF-HEAL UNCONDITIONALLY — "we resumed correctly" is NOT the end of the story. The console's
	# close() calls DebugActionsPlayer.restore_player() (debug_console.gd:241) AFTER whatever happened in here,
	# stamping the snapshot it took at open() — which reads `false` for any console opened while the flight
	# already had the step switched off. So the sequence `noclip on` (cursor captured) → open console → `noclip
	# off` (we hand the step back, correctly) → close console re-freezes a LIVE player with no owner left to thaw
	# it. Arming the window in every direction is what covers that; see _tick_unfreeze_grace for its semantics.
	_grace_left = maxi(0, unfreeze_grace_frames)


## Zero the velocity pair. ⭐explosion_velocity (character.gd:174) is RE-ADDED to velocity on the next physics
## frame by apply_blast (character.gd:977, called from player.gd:2269), so a blast impulse left standing across a
## flight flings the body the instant the step resumes — the exact bug die() (player.gd:2899) and
## _respawn_at_checkpoint (player.gd:3137) both zero the pair to prevent.
##
## ⭐AND THE FALL-DEATH ACCUMULATOR, which is the residue of the trap this file otherwise sidesteps.
## _update_continuous_fall_death (player.gd:1201) only runs from the player's own step, so it genuinely cannot
## tick while we hold that step off — but `_continuous_fall_time` (player.gd:230) KEEPS whatever it had banked
## when the step stopped. Toggle noclip on 3.5 s into a pit fall and back off in mid-air and the player has half
## a second of GameSettings.player_movement.max_continuous_fall_time left before hp is written to 0 directly
## (player.gd:1223) — a death no armour can stop. Resetting it here (the field die()/_respawn_at_checkpoint and
## DebugActionsPlayer._revive all clear the same way) means a flight always hands back a fresh fall budget, and
## it stays out of the shared GameSettings .tres that `god` snapshots.
func _calm(p: Player) -> void:
	p.velocity = Vector3.ZERO
	p.explosion_velocity = Vector3.ZERO
	p.set(&"_continuous_fall_time", 0.0)


func _physics_process(delta: float) -> void:
	if not _armed:
		return
	if not _flying:
		if _grace_left > 0:
			_tick_unfreeze_grace()
		return
	if not is_instance_valid(_player):
		# The body was freed under us (a scene reload — quickload, or a reload-flavoured death). Stand down
		# quietly instead of erroring once per frame; there is nothing left to restore onto, and the fresh Player
		# comes up with its own physics step already running.
		_player = null
		_flying = false
		_grace_left = 0
		return
	var p: Player = _player
	# ⭐THE BODY DIED UNDER US (an NPC can still shoot a frozen player mid-flight). Stand down NOW rather than
	# keep re-asserting the freeze below: die() switches the step off for its cinematic and _respawn_at_checkpoint
	# switches it back on at the end (player.gd:3173), and a flight that outlives the death would stamp that
	# revive straight back to `false` — leaving the freshly respawned player frozen at the checkpoint. _stop()
	# restores the snapshot gated on liveness, so the corpse is left exactly as die() wants it.
	if not _is_live(p):
		_stop()
		return
	# ⭐Re-assert the freeze every frame. This node is not the only writer of that bit: the debug console's
	# suspend_player()/restore_player() pair snapshots it on open and stamps the snapshot back on close, so a
	# console that opened BEFORE the flight hands the step back the moment it closes. Re-asserting is idempotent
	# and costs a bool compare, and it makes flight immune to any other suspend owner.
	if p.is_physics_processing():
		p.set_physics_process(false)
	if _input_blocked():
		return
	var motion := _fly_motion(p)
	if motion == Vector3.ZERO:
		return
	p.global_position += motion * delta


## Poll gates, both mirroring what the real player already does:
##  1. InputManager.gameplay_suppressed() — the player's own step zeroes input_dir under it (player.gd:2173-2178)
##     so you stand still inside a shop/ATM/heal screen; flight must not be the one way to walk out of a modal.
##  2. A cursor that is not CAPTURED means some UI has the keyboard. ⭐A focused LineEdit stops _unhandled_input
##     consumers but NOT poll-based reads (Input.is_action_pressed every frame), so without this gate typing
##     "forward" into the debug console's own field would fly the body across the map. It is the same gate
##     MouseInput uses to stop look (mouse_input.gd:31, :52), so a controller-only session is unaffected.
func _input_blocked() -> bool:
	if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		return true
	return InputManager.gameplay_suppressed()


## The flight velocity this frame, in metres per second — the caller multiplies by delta, so the feel is
## frame-rate independent and Engine.time_scale (bullet-time, a debug timescale) slows the fly with the world.
func _fly_motion(p: Player) -> Vector3:
	var axes := _move_axes()
	var lift := 0.0
	if _pressed(action_up):
		lift += 1.0
	if _pressed(action_down):
		lift -= 1.0
	if axes == Vector2.ZERO and is_zero_approx(lift):
		return Vector3.ZERO
	var speed := fly_speed
	if _pressed(action_boost):
		speed *= boost_multiplier
	# Fly along the CAMERA basis so flight follows the look direction (pitch included) — the body's own basis is
	# yaw-only, since Head owns pitch. Same axis convention as the player's step (player.gd:2179): basis.z points
	# BACKWARD, and get_vector's y is negative while "forward" is held, so basis.z * y is forward travel.
	var b := _fly_basis(p)
	var motion := (b.x * axes.x + b.z * axes.y) * speed
	# Rise/fall is WORLD vertical, not camera-up: a free-cam that drifts sideways when you look down is useless
	# for lining a shot up.
	motion += Vector3.UP * (lift * vertical_speed)
	return motion


## The camera's world basis if the rig resolves, else the body's own (yaw-only) basis. Read duck-typed: `head`
## is an authored @export (player.gd:171) that a hand-built test Player may legitimately leave null, and
## Head.camera is a property with a getter (head.gd:20). Camera shake/tilt ride along in this basis, which is
## correct — it is the direction you are actually looking.
func _fly_basis(p: Player) -> Basis:
	# Read through Variant + is_instance_valid before any cast: `as` on a freed instance is a hard error, not a
	# quiet null, and this whole rig goes away with the body on a scene reload.
	var head_ref: Variant = p.get(&"head")
	if head_ref != null and is_instance_valid(head_ref):
		var cam_ref: Variant = head_ref.get(&"camera")
		if cam_ref != null and is_instance_valid(cam_ref):
			var cam: Node3D = cam_ref as Node3D
			if cam != null and cam.is_inside_tree():
				return cam.global_transform.basis.orthonormalized()
	return p.global_transform.basis.orthonormalized()


func _move_axes() -> Vector2:
	if not InputMap.has_action(action_left) or not InputMap.has_action(action_right):
		return Vector2.ZERO
	if not InputMap.has_action(action_forward) or not InputMap.has_action(action_backward):
		return Vector2.ZERO
	return Input.get_vector(action_left, action_right, action_forward, action_backward)


func _pressed(action: StringName) -> bool:
	return InputMap.has_action(action) and Input.is_action_pressed(action)


## ⭐The ordering hole no snapshot can close, in BOTH directions. The debug console suspends the player while it
## is open, so the two writers of that one bit interleave badly:
##   • `noclip on` typed INTO the console snapshots a bit that is already `false`; `noclip off` then hands back
##     `false`, and the console's close() stamps its equally-polluted snapshot on top.
##   • `noclip on` with the cursor captured, THEN opening the console: the console snapshots the flight's own
##     `false`; `noclip off` correctly resumes the step, and close() re-freezes it a frame later.
## Either way a LIVE player ends up with its step off and nobody left to thaw it. So for a bounded window after
## flight ends we watch for exactly that state and heal it: alive, not mid-death-cinematic, step still off, and
## the cursor back under gameplay's control. die() is the only non-debug writer of that bit (verified across
## scripts/ and managers/) and it always leaves the player dead or dying, so the liveness test is what keeps this
## from ever thawing a corpse.
##
## ⭐THE BUDGET COUNTS CAPTURED-CURSOR FRAMES, NOT WALL-CLOCK FRAMES, and that distinction is the whole mechanism.
## A free cursor means a debug UI is still up: the player is legitimately suspended by THAT owner and its close()
## is what will (mis)restore the step, so those frames must not burn the window — a console left open for the two
## seconds `unfreeze_grace_frames` buys would otherwise expire the heal before the hole it exists to close is even
## reachable, which is precisely the `noclip off`-typed-into-the-console case. Checking the cursor FIRST also
## makes the wait nearly free: one Input read per frame, no group scan, until gameplay has the cursor back.
## The window likewise is NOT closed by finding the step already running — the stale restore can land a frame
## after we resumed correctly, so we keep watching until the budget is spent.
func _tick_unfreeze_grace() -> void:
	if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		return  # a debug UI still owns the body; wait (without spending the budget) for its close() to land
	_grace_left -= 1
	var p: Player = _resolve_player()
	if p == null:
		_grace_left = 0  # nothing left to heal onto
		return
	if not _is_live(p):
		_grace_left = 0  # a corpse's frozen step belongs to die(); never thaw it
		return
	if p.is_physics_processing():
		return  # healthy this frame — but keep watching, a late restore_player() can still re-freeze it
	p.set_physics_process(true)


## The HUMAN player: the explicit wiring first, else Groups.human_player — the ONE home for the "which PLAYER
## group member is the human" rule (recruited companions are in that group too and must never be flown).
func _resolve_player() -> Player:
	if not player_path.is_empty():
		var explicit: Node = get_node_or_null(player_path)
		if is_instance_valid(explicit) and explicit is Player:
			return explicit as Player
	if not find_player_automatically:
		return null
	if not is_inside_tree():
		return null
	var found: Node = GroupsReg.human_player(get_tree())
	if is_instance_valid(found) and found is Player:
		return found as Player
	return null


## Alive AND not inside the death cinematic. `_dying` (player.gd:2455) is private but is the latch every HUD
## readout in the project gates on; read it duck-typed so an off-tree/hand-built body without it degrades to
## "not dying" rather than erroring.
func _is_live(p: Player) -> bool:
	var dying: Variant = p.get(&"_dying")
	if dying is bool and bool(dying):
		return false
	return p.is_alive()
