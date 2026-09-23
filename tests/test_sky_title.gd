extends GutTest

## SkyTitle (scripts/components/sky_title.gd) — the "CYBER SUNDAY" card drawn in the sky at game start. Its whole
## timeline runs on WALL-CLOCK (Time.get_ticks_usec via _last_usec) so pause / slow-mo can't drift it off the
## song's beat — which also makes it pinnable headless: rewind `_last_usec` by N seconds and call _process once,
## and the node believes N seconds elapsed. Pinned here:
##   * _ready builds a HIDDEN, transparent, depth-tested (occludable) Label3D, joins Groups.SKY_TITLE (how the
##     Player finds it to arm), runs PROCESS_MODE_ALWAYS, and self-arms;
##   * arm() is idempotent — the FIRST arm wins so the cue counts from spawn;
##   * the cue gate (cue_seconds) then fade-in -> hold -> fade-out -> done, in real seconds;
##   * the label parks sky_distance ahead of the camera, clamped inside cam.far, facing the camera with the
##     vertical stretch on its up axis;
##   * with NO camera the overlay idles but the fade clock keeps counting.
## The overlay's font-metric sizing and the invert shader are visual (headless never compiles shaders) — playtested.

const SCRIPT_PATH := "res://scripts/components/sky_title.gd"

var _cam: Camera3D = null


func before_each() -> void:
	_cam = Camera3D.new()
	add_child(_cam)
	_cam.current = true


func after_each() -> void:
	if _cam != null and is_instance_valid(_cam):
		_cam.free()
	_cam = null


func _title(overlay: bool = true, show_now: bool = false):
	var t = load(SCRIPT_PATH).new()
	t.overlay_enabled = overlay
	t.test_show_immediately = show_now
	add_child_autofree(t)
	return t


## Make the title believe `seconds` of wall-clock passed, then tick it once.
func _elapse(t, seconds: float) -> void:
	t._last_usec = Time.get_ticks_usec() - int(seconds * 1_000_000.0)
	t._process(0.0)


const HUD_SCENE := "res://scenes/player/ui.tscn"
const PAUSE_MENU_SCENE := "res://scenes/ui/options_menu.tscn"


## A title exactly as a designer drops it in: NO export touched before _ready.
func _dropped_in_title():
	var t = load(SCRIPT_PATH).new()
	add_child_autofree(t)
	return t


## The CanvasLayer `layer` a scene's ROOT authors, or CanvasLayer's own default when the scene leaves it unset.
func _root_canvas_layer(scene_path: String) -> int:
	var ps := load(scene_path) as PackedScene
	assert_not_null(ps, "%s must load to read its CanvasLayer" % scene_path)
	if ps == null:
		return -1
	var state := ps.get_state()
	for p in range(state.get_node_property_count(0)):
		if state.get_node_property_name(0, p) == "layer":
			return int(state.get_node_property_value(0, p))
	return int(ClassDB.class_get_property_default_value(&"CanvasLayer", &"layer"))


func test_a_dropped_in_title_waits_for_its_cue_instead_of_showing_at_once() -> void:
	# The TESTING shortcut must be OFF out of the box, or a title dropped into a level skips its timed entrance.
	var t = _dropped_in_title()
	_elapse(t, 0.5)
	assert_false(t._revealed, "a title dropped in with its shipped settings must wait for the cue, not reveal on spawn")
	assert_false(t._label.visible, "the sky label stays hidden before the cue")
	# Control: the only difference is the TESTING flag, and that same half second DOES reveal it.
	var preview = _title(false, true)
	_elapse(preview, 0.5)
	assert_true(preview._revealed, "control: with test_show_immediately on, the same elapsed time reveals the title")


func test_a_dropped_in_title_builds_its_on_top_duplicate() -> void:
	var t = _dropped_in_title()
	assert_true(t._overlay_layer != null and t._overlay_label != null,
		"ship decision: the inverted on-top duplicate is ON out of the box, so the title stays legible over the HUD")


func test_the_default_card_spells_the_games_name() -> void:
	var t = _dropped_in_title()
	var game_name := String(ProjectSettings.get_setting("application/config/name", "")).replace(" ", "").to_upper()
	assert_ne(game_name, "", "the project must name the game")
	assert_eq(String(t._label.text).replace(" ", "").to_upper(), game_name,
		"the sky title card is the game's name — a dropped-in title must spell the project's name")


func test_the_default_timeline_fades_up_to_full_holds_then_clears_for_good() -> void:
	# Walk a dropped-in title's shipped timeline in quarter-second wall-clock steps from just before its cue.
	# Whatever the durations are tuned to, the entrance must rise to FULL opacity, never flicker (rise then fall,
	# once), and end hidden with the clock stopped.
	var t = _dropped_in_title()
	t._t = t.cue_seconds - 0.05
	_elapse(t, 0.1)
	assert_true(t._revealed, "crossing the shipped cue reveals the title")
	var peak := 0.0
	var falling := false
	var flickered := false
	var prev := 0.0
	var steps := 0
	while not t._done and steps < 4000:
		_elapse(t, 0.25)
		steps += 1
		var a: float = t._label.modulate.a
		if a < prev - 0.0001:
			falling = true
		elif a > prev + 0.0001 and falling:
			flickered = true
		peak = maxf(peak, a)
		prev = a
	assert_true(t._done, "the shipped timeline must finish (fade in, hold, fade out) rather than hang in the sky forever")
	assert_almost_eq(peak, 1.0, 0.001, "the title must reach full opacity at some point — the HOLD is the beat the player reads it on")
	assert_false(flickered, "alpha must rise to its peak and then fall, once — no second fade-up after it starts clearing")
	assert_false(t._label.visible, "once done the sky label is hidden for good")
	assert_true(t._overlay_bbc == null or t._overlay_bbc.copy_mode == BackBufferCopy.COPY_MODE_DISABLED,
		"once done the full-screen copy is off")


func test_the_overlay_draws_over_the_hud_but_under_the_pause_menu() -> void:
	# The layer ORDER does not depend on whether the overlay ships on (test_a_dropped_in_title_builds_its_on_top_duplicate
	# pins that decision), so build it explicitly rather than crash on a null layer if that default ever flips.
	var t = _title(true)
	var overlay_layer: int = t._overlay_layer.layer
	var hud_layer := _root_canvas_layer(HUD_SCENE)
	var pause_layer := _root_canvas_layer(PAUSE_MENU_SCENE)
	assert_gt(overlay_layer, hud_layer,
		"the on-top duplicate must draw ABOVE the HUD layer (%d) — that is the whole point of the overlay" % hud_layer)
	assert_lt(overlay_layer, pause_layer,
		"the on-top duplicate must draw BELOW the pause/options menu layer (%d), or the title covers the menu" % pause_layer)


func test_ready_builds_a_hidden_occludable_label_and_arms() -> void:
	var t = _title()
	assert_true(t.is_in_group(Groups.SKY_TITLE), "joins Groups.SKY_TITLE — Player._arm_sky_title finds it by group")
	assert_eq(t.process_mode, Node.PROCESS_MODE_ALWAYS, "runs through pause: the timeline must not stall behind a shop menu")
	assert_true(t._armed, "self-arms on spawn so the cue runs however the game started")
	var l: Label3D = t._label
	assert_not_null(l, "a Label3D is built at runtime")
	if l == null:
		return
	assert_eq(l.text, t.text, "the label carries the title text export (the game's name itself is pinned by test_the_default_card_spells_the_games_name)")
	assert_false(l.visible, "hidden until the cue elapses")
	assert_eq(l.modulate.a, 0.0, "starts fully transparent (fades up from nothing)")
	assert_false(l.no_depth_test, "depth test stays ON so the skyline occludes it — the whole point of a sky title")
	assert_eq(l.billboard, BaseMaterial3D.BILLBOARD_DISABLED, "billboard OFF: faced manually so the vertical stretch survives")
	assert_eq(l.font_size, t.font_size, "font size from the export")
	assert_eq(l.pixel_size, t.pixel_size, "pixel size from the export")
	assert_false(l.shaded, "flat full-bright")


func test_overlay_is_built_idle_and_can_be_switched_off() -> void:
	var t = _title(true)
	assert_not_null(t._overlay_layer, "overlay_enabled builds the CanvasLayer")
	assert_eq(t._overlay_layer.layer, t.OVERLAY_LAYER, "on layer 100")
	assert_not_null(t._overlay_bbc, "…with a BackBufferCopy")
	assert_eq(t._overlay_bbc.copy_mode, BackBufferCopy.COPY_MODE_DISABLED, "the back-buffer copy is OFF until the title shows (a full-screen copy per frame is not free)")
	assert_not_null(t._overlay_label, "…and the duplicate Label")
	assert_false(t._overlay_label.visible, "the duplicate is hidden until the title shows")
	assert_eq(t._overlay_label.text, t.text, "the duplicate carries the same text")
	var off = _title(false)
	assert_null(off._overlay_layer, "overlay_enabled = false builds no overlay layer")
	assert_null(off._overlay_label, "…and no duplicate label")


func test_arm_is_idempotent_the_first_arm_wins() -> void:
	var t = _title()
	_elapse(t, 5.0)
	assert_almost_eq(t._t, 5.0, 0.05, "the cue clock counts from the self-arm at spawn")
	t.arm()  # the Player's ping as the spawn fade-in begins
	assert_almost_eq(t._t, 5.0, 0.05, "a second arm() must NOT restart the cue — the first arm wins")


func test_the_cue_gates_the_reveal() -> void:
	var t = _title()
	_elapse(t, 100.0)
	assert_false(t._revealed, "100 s in: under the 168 s cue, still hidden")
	assert_false(t._label.visible, "the label stays hidden before the cue")
	# The tick that CROSSES the cue must be a frame-sized one: _process adds the same wall-clock delta to the cue
	# clock AND (once revealed) to the show clock, so a single 70 s catch-up tick would reveal the title and run
	# the whole 35 s fade-in/hold/fade-out inside that one frame. Park the cue clock just under the cue instead.
	t._t = t.cue_seconds - 0.1
	_elapse(t, 0.2)
	assert_true(t._revealed, "past the cue: revealed")
	assert_true(t._label.visible, "the label shows")
	assert_almost_eq(t._shown_t, 0.2, 0.05, "the show clock starts at the reveal tick, not back at the arm")


func test_test_show_immediately_skips_the_cue() -> void:
	var t = _title(true, true)
	_elapse(t, 0.01)
	assert_true(t._revealed, "the TESTING flag reveals on the first tick")
	assert_true(t._label.visible, "visible at once")


func test_fade_in_hold_fade_out_then_done() -> void:
	var t = _title(true, true)
	_elapse(t, 0.0)  # reveal
	_elapse(t, 1.25)  # half the 2.5 s fade-in
	assert_almost_eq(t._label.modulate.a, 0.5, 0.05, "halfway through the fade-in the label is at half alpha")
	assert_almost_eq(t._overlay_label.modulate.a, 0.5, 0.05, "the overlay duplicate fades in lockstep")
	assert_true(t._overlay_label.visible, "the duplicate is showing while the title is up")
	assert_eq(t._overlay_bbc.copy_mode, BackBufferCopy.COPY_MODE_VIEWPORT, "the back-buffer copy runs while the title is up")
	_elapse(t, 1.25 + 10.0)  # into the hold
	assert_almost_eq(t._label.modulate.a, 1.0, 0.01, "during the hold the label is fully opaque")
	_elapse(t, 20.0 + 1.25)  # 2.5 + 30 + 1.25 = halfway through the fade-out
	assert_almost_eq(t._label.modulate.a, 0.5, 0.05, "halfway through the fade-out: half alpha")
	assert_false(t._done, "not done yet")
	_elapse(t, 1.3)  # past 2.5 + 30 + 2.5
	assert_true(t._done, "fully faded out: done")
	assert_false(t._label.visible, "the label hides for good")
	assert_eq(t._label.modulate.a, 0.0, "alpha lands on 0")
	assert_false(t._overlay_label.visible, "the duplicate hides too")
	assert_eq(t._overlay_bbc.copy_mode, BackBufferCopy.COPY_MODE_DISABLED, "the back-buffer copy is switched off again")
	var shown_before: float = t._shown_t
	_elapse(t, 5.0)
	assert_eq(t._shown_t, shown_before, "once done, _process does no further work (the clock stops)")


func test_label_parks_ahead_of_the_camera_inside_the_far_plane() -> void:
	_cam.far = 100.0
	_cam.global_position = Vector3(10.0, 5.0, 0.0)
	var t = _title(false, true)
	_elapse(t, 0.0)
	var expected := _cam.global_position - _cam.global_transform.basis.z * 90.0
	assert_almost_eq(t._label.global_position, expected, Vector3.ONE * 0.01,
		"sky_distance 350 clamps to 0.9 * far (90 m) so the far plane never clips the title away")
	_cam.far = 4000.0
	_elapse(t, 0.0)
	expected = _cam.global_position - _cam.global_transform.basis.z * 350.0
	assert_almost_eq(t._label.global_position, expected, Vector3.ONE * 0.01,
		"with a deep far plane it sits the full sky_distance out along the camera's -Z")


func test_label_faces_the_camera_with_the_vertical_stretch() -> void:
	_cam.rotation = Vector3(0.2, 1.1, 0.0)
	var t = _title(false, true)
	_elapse(t, 0.0)
	var cb := _cam.global_transform.basis.orthonormalized()
	var lb: Basis = t._label.global_transform.basis
	assert_almost_eq(lb.x, cb.x, Vector3.ONE * 0.001, "the label's X matches the camera's (readable, not mirrored)")
	assert_almost_eq(lb.z, cb.z, Vector3.ONE * 0.001, "the label's Z matches the camera's — +Z points back at the camera")
	assert_almost_eq(lb.y, cb.y * t.vertical_stretch, Vector3.ONE * 0.001, "the UP column carries the vertical stretch (1.5x taller letters)")


func test_no_camera_idles_the_overlay_but_keeps_the_clock() -> void:
	var t = _title(true, true)
	_elapse(t, 1.25)  # showing, half faded in
	assert_true(t._overlay_label.visible, "with a camera the duplicate shows")
	_cam.free()
	_cam = null
	_elapse(t, 1.0)
	assert_false(t._overlay_label.visible, "no camera: the duplicate idles (nothing to project onto)")
	assert_eq(t._overlay_bbc.copy_mode, BackBufferCopy.COPY_MODE_DISABLED, "no camera: the full-screen copy stops")
	assert_almost_eq(t._shown_t, 2.25, 0.1, "the fade clock still advanced through the camera gap — a teardown window must not drift the beat")
