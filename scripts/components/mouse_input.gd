class_name MouseInput
extends Node3D

## Mouse-look + fire input source. Captures the cursor and turns motion into a
## `rotate` signal; emits `attack` continuously while the fire button is held.
##
## UNITS: mouse look is radians per SCREEN pixel — the motion read is InputEventMouseMotion.screen_relative
## (raw OS pixels), NEVER `relative`. Under the project's `viewport` stretch mode the engine pre-scales
## `relative` by canvas/window width (792/1920 = 0.41 in 1080p fullscreen, 792/1600 = 0.50 in the 1600x900
## window, 792/1280 = 0.62 at 720p, 792/3840 = 0.21 at 4K), so the same hand motion used to turn the view
## 1.2-1.5x further the moment the game went windowed and half as far on a 4K screen. screen_relative is
## window/resolution independent; GameSettings.camera.mouse_sensitivity (+ Settings.SENS_MIN/MAX and the
## Options slider) are tuned in that unit — 0.002 canvas-px x 792/1920 = 0.000825, so 1080p fullscreen
## feels exactly as it did. tests/test_camera_input_ui.gd pins the read; a legacy settings.cfg value is
## rescaled once by Settings.read_mouse_sensitivity.
##
## OS-FOCUS RULES (2026-08-18, found while making windowed mode focusable):
##   • Nothing steers or fires while the game window is UNFOCUSED — and that is the ENGINE's job, not a gate
##     here. The OS stops routing keyboard and clicks to an unfocused window, and Godot itself releases held
##     keys and every pressed ACTION on focus loss (Input.release_pressed_events, from SceneTree's
##     APPLICATION_FOCUS_OUT handler and again from the display server's deactivate path). The pad — which SDL
##     keeps reporting through an alt-tab, while Input.mouse_mode still reads CAPTURED — is silenced by
##     project.godot `input_devices/joypads/ignore_joypad_on_unfocused_application = true`: Input drops joypad
##     events and releases held joy buttons / axes / actions the moment the app loses focus, so the fire polls,
##     the right-stick look and the Player's movement read all poll zero. Keep that flag ON
##     (tests/test_focus_input_lock.gd pins it) instead of adding focus checks to input readers. (Known residual:
##     the mouse WHEEL is the one input Windows' hover-scroll delivers to an unfocused window and Godot doesn't
##     filter it, so Hotbar Next/Prev can cycle a weapon in the background — cosmetic, accepted.)
##   • The click that RE-FOCUSES the window must not fire — the one thing that flag can't cover. Windows
##     activates an unfocused window on the click AND delivers that same click as a real LMB press, so the
##     frame after refocus the drawn gun / fists fired at whatever sat under the crosshair (wasted ammo; in
##     stealth a NoiseSource alert). ONE LATCH PER FIRE BUTTON (Attack, and alt_attack_action), both armed on
##     every focus transition (see _notification); each holds its button until THAT button is released (its
##     release event in _input, or the next poll reading it up) — the activating click has to be let go before
##     that button fires again, and a fresh click after that fires normally. Per-button on purpose: a right-click
##     activation must not eat the next left punch, and holding ADS (Zoom = the alt button on a gun) after a
##     left-click activation must not eat the next shot.
##     Deliberately NOT part of the menu/modal path (gameplay_suppressed already owns clicks on menus): this is
##     only about the OS focus edge. Scope: it is about the activating MOUSE click. A pad trigger held across the
##     edge reads released after refocus (the engine flag released it and only re-reports the axis when its value
##     next CHANGES), so there is nothing to latch and its next movement is a fresh pull that fires — accepted.
##     tests/test_focus_input_lock.gd pins the latch; the manual check is: draw a gun, alt-tab out, click the game
##     window to come back — no shot.

## Look delta, ALREADY scaled by sensitivity. NOTE the axis mapping: .x = PITCH delta
## (from vertical mouse motion), .y = YAW delta (from horizontal) — swapped vs the
## usual (x,y). Consumed by Head (pitch), the Player body (yaw), and GunMesh (sway).
signal rotate(_amt: Vector2)
## Emitted EVERY frame the "Attack" action is held (the full-auto driver). Per-click /
## semi-auto behaviour is enforced downstream in attack.gd via WeaponData.auto_fire.
## Carries the active viewport camera so the hitscan/aim origin is correct.
signal attack(_camera: Camera3D)
## Emitted EVERY frame the ALT fire action is held — the second attack button. Only weapons that opt in react
## (Attack gates it on WeaponData.view_model_punch): unarmed throws the RIGHT fist with it, while for a gun the
## same button is ADS and this is ignored. Same cadence rules as `attack`; carries the same camera.
signal alt_attack(_camera: Camera3D)

## The player body this look-input drives — its horizontal speed scales look sensitivity down at bhop
## speeds (see speed_sensitivity_multiplier). Wire to the Player; null = no speed-based falloff.
@export var player: CharacterBody3D
## The SECOND attack button, for weapons that punch with either hand. Defaults to the ADS button, which is free
## exactly when it matters: a punching weapon sets no_ads, so ScopeIn already refuses to scope with it out.
@export var alt_attack_action: StringName = &"Zoom"

## The refocus fire latches — one per fire button (Attack / alt_attack_action). Both armed on every OS focus
## transition; while a latch is armed its button's signal is NOT emitted. Each clears in tick_refocus_latches()
## the first frame ITS button reads released. Read-only from outside (fire_blocked_by_refocus /
## alt_fire_blocked_by_refocus); tests drive them through notification() + tick_refocus_latches().
var _attack_latch: bool = false
var _alt_latch: bool = false

func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

## Arm both refocus latches on BOTH focus edges. FOCUS_IN is the one that matters — on Windows it is dispatched
## synchronously from WM_ACTIVATEAPP, which the OS sends BEFORE the button-down of the activating click (verified
## in Godot 4.7.1's display_server_windows.cpp: the notification runs inside WndProc, the click is buffered and only
## flushed at the end of process_events), so the latch is up when that click first reads as pressed. Arming on
## FOCUS_OUT too costs nothing (Godot releases every pressed action on focus-out, so the latch clears on the next
## tick anyway) and keeps the rule simple: a MOUSE button held across a focus change never fires — its action was
## released on the way out and the OS won't re-press it without a new click, which the latch then eats. App-level,
## NOT NOTIFICATION_WM_WINDOW_FOCUS_IN/OUT, for the timing above and because DisplayServerWindows timer-defers the
## window-level DEACTIVATE half. (Both pairs flap when the Options music-folder picker opens — it is a NATIVE dialog
## on Godot's file-dialog thread — which is harmless: Options is a modal, so gameplay_suppressed already owns those
## clicks, and the latches clear on the next tick with nothing held.)
func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_IN or what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		_attack_latch = true
		_alt_latch = true

## Clear a latch the moment ITS button's RELEASE EVENT arrives, not only when the next per-frame poll reads it up:
## a release and a fresh press can land in the same input flush (a quick re-click on a slow frame), and the poll
## alone would read that as one continuous hold — eating the fresh click, and PickupRay's throw with it (its
## _unhandled_input runs before this frame's tick). Event order is preserved, so the release clears BEFORE anyone
## sees the re-press. The poll in _process stays the primary clear (it needs no event and covers a pad).
func _input(event: InputEvent) -> void:
	if _attack_latch and event.is_action_released("Attack"):
		_attack_latch = false
	if _alt_latch and event.is_action_released(alt_attack_action):
		_alt_latch = false

## One latch as pure state math, so it can be pinned off-tree: given the latch state and whether ITS button is held
## THIS frame, return the latch state after this frame — which is ALSO whether that button is blocked this frame.
## Armed + held → stays armed, blocked. Armed + released → clears NOW (the same frame counts as the "read released
## at least once", so a fresh click one frame later fires with no lost input). Not armed → a held button is an
## ordinary press and fires. The FIRST frame after refocus is the whole point: the activating click reads held →
## blocked; it stays blocked until the player lets go.
static func refocus_latch_holds(armed: bool, fire_held: bool) -> bool:
	return armed and fire_held

## Advance both latches one frame with the polled button states. Called at the top of _process, BEFORE the fire
## polls are acted on, with both buttons — a right-click can activate the window just like a left-click, and for
## fists it is the right punch. Each button clears only its own latch (see the header for why they are separate).
func tick_refocus_latches(attack_held: bool, alt_held: bool) -> void:
	_attack_latch = refocus_latch_holds(_attack_latch, attack_held)
	_alt_latch = refocus_latch_holds(_alt_latch, alt_held)

## True while the PRIMARY fire button's latch is holding (the activating left click hasn't been released yet).
## PickupRay's left-click alternate throw reads this — it stands in for the same button.
func fire_blocked_by_refocus() -> bool:
	return _attack_latch

## True while the ALT fire button's latch is holding (the activating right click hasn't been released yet).
func alt_fire_blocked_by_refocus() -> bool:
	return _alt_latch

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var mm := event as InputEventMouseMotion
		var sensitivity := GameSettings.camera.mouse_sensitivity * speed_sensitivity_multiplier()
		# screen_relative (unscaled OS pixels), not `relative` — see the header: `relative` rides the window size.
		var pitch := -mm.screen_relative.y * sensitivity
		if Settings.invert_look_y:
			pitch = -pitch
		rotate.emit(Vector2(pitch, -mm.screen_relative.x * sensitivity))

func _process(delta: float) -> void:
	# Poll both fire buttons once, feed the latches FIRST (so a release this frame clears this frame), then gate
	# each emit on its OWN latch.
	var attack_held := Input.is_action_pressed("Attack")
	var alt_held := Input.is_action_pressed(alt_attack_action)
	tick_refocus_latches(attack_held, alt_held)
	if not InputManager.gameplay_suppressed():
		var _camera: Camera3D = get_viewport().get_camera_3d()
		if attack_held and not _attack_latch:
			attack.emit(_camera)
		if alt_held and not _alt_latch:
			alt_attack.emit(_camera)
	_controller_look(delta)

## Right-stick look: read the look_* action set (bound to the right stick by InputManager) and feed the
## same `rotate` signal as the mouse. Scaled by delta (per-frame, unlike mouse relative motion) and the
## same speed-sensitivity falloff. Honors the invert-Y option. Only while the cursor is captured. (No focus
## check on purpose: Input.mouse_mode still reads CAPTURED while alt-tabbed and SDL keeps reporting the stick,
## but the engine flag `ignore_joypad_on_unfocused_application` — see the header — zeroes look_* while the
## app is unfocused, so this reads (0,0) and returns below.)
func _controller_look(delta: float) -> void:
	if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		return
	var look := Input.get_vector(&"look_left", &"look_right", &"look_up", &"look_down")
	if look.length_squared() < 0.0001:
		return
	var sens := Settings.controller_look_sensitivity * speed_sensitivity_multiplier() * delta
	var pitch := -look.y * sens
	if Settings.invert_look_y:
		pitch = -pitch
	rotate.emit(Vector2(pitch, -look.x * sens))

## Scale look sensitivity DOWN as horizontal speed rises (toward sens_min_multiplier
## at bhop max_speed) so high-speed bunnyhop runs don't feel twitchy. Reuses the
## bunnyhop speed thresholds; returns 1.0 (no change) below the threshold.
func speed_sensitivity_multiplier() -> float:
	if not player:
		return 1.0
	var hspeed := Vector2(player.velocity.x, player.velocity.z).length()
	var thr := GameSettings.bunnyhop.sens_reduction_threshold
	var cap := GameSettings.bunnyhop.max_speed
	if hspeed <= thr or cap <= thr:
		return 1.0
	var t := clampf((hspeed - thr) / (cap - thr), 0.0, 1.0)
	return lerpf(1.0, GameSettings.bunnyhop.sens_min_multiplier, t)
