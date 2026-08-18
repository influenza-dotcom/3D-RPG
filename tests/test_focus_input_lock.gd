extends GutTest
## Contract: an UNFOCUSED game window never steers or fires the character, and the click that RE-FOCUSES the
## window never fires (2026-08-18, found right after windowed mode became focusable). Two seams:
##  1. The ENGINE silences the pad while the app is unfocused — project.godot sets
##     `input_devices/joypads/ignore_joypad_on_unfocused_application = true` (Project Settings → Input Devices →
##     Joypads). SDL keeps reporting the stick through an alt-tab and Input.mouse_mode still reads CAPTURED, so
##     before this a resting stick / held trigger walked and shot the character in the background window; with the
##     flag Input drops joypad events and releases held joy buttons / axes / actions on focus loss. Keyboard and
##     clicks never had the problem: the OS stops routing them to an unfocused window, and Godot itself releases
##     held keys + every pressed action on focus-out (Input.release_pressed_events, from SceneTree's
##     APPLICATION_FOCUS_OUT handler). So NO script gates focus — a designer who unticks the flag re-opens the bug,
##     hence the pin.
##  2. MouseInput's refocus fire latches — the one thing that flag can't cover. Windows activates an unfocused
##     window on the click AND delivers that same click as a real LMB press; one latch per fire button (Attack /
##     alt_attack_action), both armed on every focus edge in _notification, each holding its button until THAT
##     button is released (its release event, or the next poll reading it up) — so the activating click must be
##     let go before that button fires again, a
##     fresh click after that fires normally, and the OTHER button is never eaten (holding ADS after a left-click
##     activation must not swallow the next shot). PickupRay's alternate-throw (left-click throws the carried prop)
##     honours the primary latch.
## Everything here runs headless and OFF-TREE: `Object.notification()` drives MouseInput's _notification directly
## (no window exists, so nothing else ever sends these), the latch math is a static, and tick_refocus_latches takes
## the polled button states as parameters (no Input / viewport read). MouseInput is `.new()` WITHOUT add_child so
## its _ready never captures the cursor and its _process (which derefs get_viewport()) never runs — per CLAUDE.md.
##
## MANUAL CHECK (the seam a headless run cannot see): windowed mode, draw a gun, alt-tab away, then CLICK the game
## window to come back — no shot, no NoiseSource alert; release and click again — it fires. Right-click to come
## back with fists — no right punch, and a fresh LEFT click punches at once. Carrying a crate: the refocus click
## does not throw it. On a pad: hold RT / deflect the right stick while alt-tabbed — nothing fires or turns.
## (Known residual, documented in CURRENT_ARCHITECTURE: a trigger held ACROSS the alt-tab reads released after
## refocus and fires on its next movement — the engine only re-reports the axis on a value change.)


# ---------------------------------------------------------------------------------------------------------------
# Seam 1: the engine flag that silences the pad while unfocused
# ---------------------------------------------------------------------------------------------------------------

func test_project_ignores_joypad_while_unfocused() -> void:
	# ProjectSettings returns the stored value or the fallback; a missing key = the engine default = false.
	var v = ProjectSettings.get_setting("input_devices/joypads/ignore_joypad_on_unfocused_application", false)
	assert_true(v == true,
		"project.godot input_devices/joypads/ignore_joypad_on_unfocused_application must stay ON: SDL keeps reporting "
		+ "the pad through an alt-tab, so without it a resting stick / held trigger steers and fires the character in the "
		+ "background window (Project Settings > Input Devices > Joypads > Ignore Joypad On Unfocused Application).")
	# The live Input singleton reads that setting at boot (GLOBAL_DEF_RST) — pin that it actually reached the engine.
	assert_true(Input.is_ignoring_joypad_on_unfocused_application(),
		"Input.ignore_joypad_on_unfocused_application must be true at runtime — the project.godot key is read once at "
		+ "boot; if this fails while the key is set, the setting name/section drifted")


# ---------------------------------------------------------------------------------------------------------------
# Seam 2a: one latch as pure math (MouseInput.refocus_latch_holds)
# ---------------------------------------------------------------------------------------------------------------

func test_refocus_latch_math_truth_table() -> void:
	# armed + held -> stays armed (blocked); armed + released -> clears; not armed -> never blocks, whatever is held.
	assert_true(MouseInput.refocus_latch_holds(true, true),
		"armed + button held = still armed / blocked: the activating click is being held, it must not fire")
	assert_false(MouseInput.refocus_latch_holds(true, false),
		"armed + button released = clears THIS frame: one released read is the whole condition, so a fresh click a frame later fires with no lost input")
	assert_false(MouseInput.refocus_latch_holds(false, true),
		"not armed + button held = an ordinary press: no focus edge happened, it fires")
	assert_false(MouseInput.refocus_latch_holds(false, false),
		"not armed + nothing held = idle")


# ---------------------------------------------------------------------------------------------------------------
# Seam 2b: MouseInput — the notification arms both, each button clears its own (off-tree, notification() driven)
# ---------------------------------------------------------------------------------------------------------------

func test_refocus_click_is_blocked_until_released_then_next_click_fires() -> void:
	var mi := MouseInput.new()  # .new() WITHOUT add_child: _ready would capture the real cursor
	assert_false(mi.fire_blocked_by_refocus(), "a fresh MouseInput is not latched — nothing has changed focus")
	mi.tick_refocus_latches(true, false)
	assert_false(mi.fire_blocked_by_refocus(), "no focus edge yet: a held fire button is an ordinary press and fires")
	# The player alt-tabs back in by LEFT-clicking the window: Windows dispatches APPLICATION_FOCUS_IN (WM_ACTIVATEAPP)
	# BEFORE the click's button-down, so the latch is armed when that click first reads as pressed.
	mi.notification(NOTIFICATION_APPLICATION_FOCUS_IN)
	assert_true(mi.fire_blocked_by_refocus(), "APPLICATION_FOCUS_IN arms the primary latch")
	assert_true(mi.alt_fire_blocked_by_refocus(), "…and the alt latch")
	mi.tick_refocus_latches(true, false)
	assert_true(mi.fire_blocked_by_refocus(), "frame 1 after refocus, activating click held: BLOCKED (this is the shot that used to fire)")
	assert_false(mi.alt_fire_blocked_by_refocus(), "the alt button was not held, so ITS latch cleared on the same frame")
	mi.tick_refocus_latches(true, false)
	assert_true(mi.fire_blocked_by_refocus(), "still holding the click two frames later: still blocked — a click is 3-6 frames long")
	mi.tick_refocus_latches(false, false)
	assert_false(mi.fire_blocked_by_refocus(), "the click is released: the latch clears the SAME frame")
	mi.tick_refocus_latches(true, false)
	assert_false(mi.fire_blocked_by_refocus(), "a fresh click after the release fires normally — the latch is one-shot")
	mi.free()


func test_latches_are_per_button_so_ads_never_swallows_the_next_shot() -> void:
	# Left-click activation, then the player holds RMB (ADS on a gun / the right fist on hands) while letting go of
	# LMB, then left-clicks again. A single OR-ed latch would stay armed on the held RMB and eat every fresh shot;
	# per-button latches clear the primary the moment LMB reads released.
	var mi := MouseInput.new()
	mi.notification(NOTIFICATION_APPLICATION_FOCUS_IN)
	mi.tick_refocus_latches(true, false)   # activating left click held, RMB up
	assert_false(mi.alt_fire_blocked_by_refocus(), "RMB read released on the first frame: its latch cleared — a later RMB press is a fresh press")
	mi.tick_refocus_latches(true, true)    # RMB pressed while LMB still down: ADS — a fresh press, not latched
	assert_true(mi.fire_blocked_by_refocus(), "LMB is still the activating click: blocked")
	assert_false(mi.alt_fire_blocked_by_refocus(), "the fresh RMB press is not blocked (ADS engages / the right fist punches)")
	mi.tick_refocus_latches(false, true)   # LMB released, RMB (ADS) still held
	assert_false(mi.fire_blocked_by_refocus(), "LMB read released once: the PRIMARY latch clears even though RMB is still held")
	mi.tick_refocus_latches(true, true)    # fresh left click while aiming
	assert_false(mi.fire_blocked_by_refocus(), "a fresh left click while holding ADS FIRES — the held alt button must not gate the primary one")
	mi.free()


func test_right_click_activation_eats_the_right_punch_but_not_a_fresh_left_one() -> void:
	# Any button activates a window. With fists the right button is the right punch: the activating right click must
	# not punch, and a left click a frame later is a fresh press that must.
	var mi := MouseInput.new()
	mi.notification(NOTIFICATION_APPLICATION_FOCUS_IN)
	mi.tick_refocus_latches(false, true)   # activating RIGHT click held
	assert_true(mi.alt_fire_blocked_by_refocus(), "the activating right click is blocked")
	assert_false(mi.fire_blocked_by_refocus(), "the left button read released, so its latch cleared at once")
	mi.tick_refocus_latches(true, true)    # left click while the activating right click is still down
	assert_false(mi.fire_blocked_by_refocus(), "a fresh LEFT punch fires while the activating right click is still held")
	assert_true(mi.alt_fire_blocked_by_refocus(), "…and the right one is still blocked until it is let go")
	mi.free()


func test_alt_tab_back_without_a_click_costs_nothing() -> void:
	# Keyboard alt-tab: FOCUS_IN arrives with no button held, so the first frame clears both latches and the player's
	# first real click fires. The latch must never eat a legitimate shot.
	var mi := MouseInput.new()
	mi.notification(NOTIFICATION_APPLICATION_FOCUS_IN)
	mi.tick_refocus_latches(false, false)
	assert_false(mi.fire_blocked_by_refocus() or mi.alt_fire_blocked_by_refocus(), "no button held on the first frame back: both clear immediately")
	mi.tick_refocus_latches(true, false)
	assert_false(mi.fire_blocked_by_refocus(), "the player's first click after a keyboard alt-tab fires")
	mi.free()


func test_focus_out_arms_too_and_a_held_button_stays_blocked_until_it_reads_released() -> void:
	# Pure latch behaviour across the OUT edge: FOCUS_OUT arms; a button that still reads held is blocked; the first
	# released read clears. (In the live game Godot releases every pressed action on focus-out, so this normally
	# clears on the very next tick — arming on OUT is cheap insurance around that edge, not a separate feature.)
	var mi := MouseInput.new()
	mi.notification(NOTIFICATION_APPLICATION_FOCUS_OUT)
	assert_true(mi.fire_blocked_by_refocus() and mi.alt_fire_blocked_by_refocus(), "APPLICATION_FOCUS_OUT arms both latches too")
	mi.tick_refocus_latches(true, false)
	assert_true(mi.fire_blocked_by_refocus(), "a button that still reads held across the focus-out edge is blocked")
	mi.notification(NOTIFICATION_APPLICATION_FOCUS_IN)
	mi.tick_refocus_latches(true, false)
	assert_true(mi.fire_blocked_by_refocus(), "still reading held on the way back in: still blocked")
	mi.tick_refocus_latches(false, false)
	assert_false(mi.fire_blocked_by_refocus(), "released once: clear")
	mi.free()


func test_release_event_clears_only_its_own_latch_before_the_next_poll() -> void:
	# A release and a fresh press can land in the SAME input flush (a quick re-click on a slow frame); the per-frame
	# poll would read that as one continuous hold and eat the fresh click — and PickupRay's throw, whose
	# _unhandled_input runs before the tick. So the release EVENT clears the latch in _input, in event order.
	var mi := MouseInput.new()
	mi.notification(NOTIFICATION_APPLICATION_FOCUS_IN)
	var rel := InputEventAction.new()
	rel.action = &"Attack"
	rel.pressed = false
	mi._input(rel)
	assert_false(mi.fire_blocked_by_refocus(), "an Attack RELEASE event clears the primary latch immediately")
	assert_true(mi.alt_fire_blocked_by_refocus(), "…and leaves the alt latch alone")
	var press := InputEventAction.new()
	press.action = &"Attack"
	press.pressed = true
	mi._input(press)
	mi.notification(NOTIFICATION_APPLICATION_FOCUS_IN)
	mi._input(press)
	assert_true(mi.fire_blocked_by_refocus(), "a PRESS event never clears (or arms) a latch — only focus edges arm, only releases clear")
	mi.tick_refocus_latches(true, false)
	assert_true(mi.fire_blocked_by_refocus(), "…and the poll agrees: the held activating click stays blocked")
	mi.free()


func test_only_the_app_level_focus_notifications_arm_the_latches() -> void:
	# The WINDOW-level pair is the wrong signal here: on Windows its deactivate half is timer-deferred inside
	# DisplayServerWindows, while the app-level pair is dispatched synchronously from WM_ACTIVATEAPP BEFORE the
	# activating click is flushed — which is what makes the latch land in time. Pin the choice.
	var mi := MouseInput.new()
	mi.notification(NOTIFICATION_WM_WINDOW_FOCUS_IN)
	mi.notification(NOTIFICATION_WM_WINDOW_FOCUS_OUT)
	assert_false(mi.fire_blocked_by_refocus() or mi.alt_fire_blocked_by_refocus(),
		"NOTIFICATION_WM_WINDOW_FOCUS_IN/OUT do NOT arm the refocus latches — app-level only")
	mi.free()


func test_process_feeds_both_latches_before_the_emits_and_gates_each_emit_on_its_own() -> void:
	# _process can't run off-tree (get_viewport() is null), so pin its SHAPE with the exact load-bearing text: the
	# tick sits ABOVE the emits and is fed both buttons, and each emit is gated on ITS latch. A future edit that polls
	# Attack straight into attack.emit, or gates both emits on one latch, re-opens the refocus shot / the ADS swallow.
	var src := FileAccess.get_file_as_string("res://scripts/components/mouse_input.gd")
	var proc_at := src.find("func _process(")
	assert_true(proc_at >= 0, "MouseInput still has _process")
	var proc_end := src.find("\nfunc ", proc_at + 1)
	assert_true(proc_end > proc_at, "_process is followed by another top-level func (delimiter for the pin)")
	var body := src.substr(proc_at, proc_end - proc_at)
	var tick_at := body.find("tick_refocus_latches(attack_held, alt_held)")
	var emit_at := body.find("attack.emit(")
	assert_true(tick_at >= 0 and emit_at >= 0 and tick_at < emit_at,
		"MouseInput._process must call tick_refocus_latches(attack_held, alt_held) BEFORE any attack/alt_attack emit")
	assert_true(body.find("if attack_held and not _attack_latch:") >= 0,
		"the primary emit is gated on the PRIMARY latch (if attack_held and not _attack_latch:)")
	assert_true(body.find("if alt_held and not _alt_latch:") >= 0,
		"the alt emit is gated on the ALT latch (if alt_held and not _alt_latch:) — never on the primary one")


func test_pickup_ray_alternate_throw_honours_the_primary_latch() -> void:
	# PickupRay can't be instantiated bare (RayCast3D + @onready NodePaths + real physics — see test_camera_input_ui's
	# skip list), so pin the source: the left-click alternate throw stands in for the fire click while your hands are
	# full, and the click that re-focuses the window must not fling the carried prop any more than it may fire.
	var src := FileAccess.get_file_as_string("res://scripts/components/ray_cast.gd")
	var branch_at := src.find("event.is_action_pressed(InputManager.action_attack)")
	assert_true(branch_at >= 0, "PickupRay still has the left-click alternate-throw branch")
	var branch_end := src.find("\n\telif ", branch_at + 1)
	assert_true(branch_end > branch_at, "the alternate-throw branch is followed by another elif (delimiter for the pin)")
	var branch := src.substr(branch_at, branch_end - branch_at)
	assert_true(branch.find("if _refocus_latched():") >= 0,
		"the alternate-throw branch must bail while MouseInput's primary refocus latch holds — the activating click is not a throw")
	assert_true(src.find("pl.mouse_input.fire_blocked_by_refocus()") >= 0,
		"_refocus_latched reads MouseInput.fire_blocked_by_refocus() (the PRIMARY-button latch) through the exported player")
