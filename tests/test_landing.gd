extends GutTest

## Landing (M13 residual) — the touchdown burst + footstep cadence lifted off Player._physics_process.
##
## Two things are pinned here:
##   1. The PREFAB WIRING. Landing is a scene-wired drop-in (`host = NodePath("..")`, dragged onto Player's
##      `landing` export). Both NodePaths resolve on TREE ENTRY, so a rename/unwire is invisible until you play —
##      exactly the class of bug the project's prefab contract tests exist to catch. Checked against the
##      PackedScene's STATE (never instantiated): a real Player._ready wants the whole prefab, weapon.tscn, nav
##      and audio, and mutates shared statics.
##   2. The two pure curves (impact / interval), which every landing channel and the stride rate read.
##   3. The footstep dB BASE-CAPTURE LATCH, which needs a host to mean anything (see that test) — it is the guard
##      against the loudness ratcheting itself down one step at a time.
##
## Deliberately NOT covered in-tree: the burst's actual FX calls (camera dip, gun dip, shake, HUD dip, dust, land
## SFX) need a live prefab Player; they stay playtest-verified, as the rest of the player-feel surface is.

const PLAYER_SCENE := "res://scenes/player/Player.tscn"
## The Player SCRIPT, for the one test that needs a real host object. Built off-tree (load().new(), never
## instantiated and never added to the tree) — the test_fists_view_model / test_player_core idiom.
const PLAYER_SCRIPT := "res://scripts/player/player.gd"


func _player_state() -> SceneState:
	var ps := load(PLAYER_SCENE) as PackedScene
	assert_not_null(ps, "Player.tscn must load")
	return ps.get_state()


## Find a node by name in a SceneState; -1 when absent.
func _node_index(state: SceneState, node_name: String) -> int:
	for i in range(state.get_node_count()):
		if state.get_node_name(i) == node_name:
			return i
	return -1


## Read a property off a SceneState node by name; null when the node doesn't author it.
func _node_prop(state: SceneState, idx: int, prop: String) -> Variant:
	for p in range(state.get_node_property_count(idx)):
		if state.get_node_property_name(idx, p) == prop:
			return state.get_node_property_value(idx, p)
	return null


func test_player_scene_has_landing_child() -> void:
	var state := _player_state()
	assert_gte(_node_index(state, "Landing"), 0,
		"Player.tscn must contain a Landing child — without it the player lands silently and never takes a footstep")


func test_landing_child_points_host_at_the_player_root() -> void:
	var state := _player_state()
	var idx := _node_index(state, "Landing")
	assert_gte(idx, 0, "Landing node must exist before its host can be checked")
	assert_eq(_node_prop(state, idx, "host"), NodePath(".."),
		"Landing.host must be wired to the Player root (..) — a null host makes every entry point a no-op")


func test_player_root_wires_the_landing_export() -> void:
	var state := _player_state()
	# The root is node 0; its `landing` export must name the child by NodePath, or player.gd's null guard
	# silently skips the touchdown burst AND the footstep cadence for the whole run.
	assert_eq(_node_prop(state, 0, "landing"), NodePath("Landing"),
		"Player.tscn root must wire landing = NodePath(\"Landing\")")


func test_impact_is_zero_when_not_falling() -> void:
	# Rising or level (velocity.y >= 0) is not a landing: the curve must floor at 0 rather than go negative,
	# because a negative impact would invert the gun dip and the SFX pitch lerp.
	assert_eq(Landing.impact_for(0.0), 0.0, "A level touchdown must read zero impact")
	assert_eq(Landing.impact_for(5.0), 0.0, "An upward velocity must clamp to zero impact, never negative")


func test_impact_rises_with_fall_speed_and_clamps_at_one() -> void:
	var divisor: float = GameSettings.player_movement.landing_impact_divisor
	var half := Landing.impact_for(-divisor * 0.5)
	assert_almost_eq(half, 0.5, 0.001, "Falling at half the impact divisor must read ~0.5")
	assert_eq(Landing.impact_for(-divisor), 1.0, "Falling at the impact divisor must read a full 1.0")
	assert_eq(Landing.impact_for(-divisor * 10.0), 1.0,
		"A terminal-velocity fall must CLAMP at 1.0 — every channel scales by this, so an unclamped value would blow out the shake")


func test_footstep_interval_is_inverse_to_target_speed() -> void:
	var base: float = GameSettings.player_movement.footstep_base_interval
	var max_speed: float = GameSettings.player_movement.max_speed
	assert_almost_eq(Landing.interval_for(max_speed), base, 0.001,
		"At max_speed the cadence must equal the authored base interval")
	assert_gt(Landing.interval_for(max_speed * 0.5), Landing.interval_for(max_speed),
		"A slower target speed must LENGTHEN the gap between footsteps")
	assert_lt(Landing.interval_for(max_speed * 2.0), Landing.interval_for(max_speed),
		"Bhop overspeed must SHORTEN the gap between footsteps")


func test_footstep_interval_survives_a_zero_target_speed() -> void:
	# target_speed hits 0 whenever the player is fully stopped/immobilised; the max(…, 0.01) floor is what keeps
	# this from dividing by zero and poisoning the timer with INF.
	var stopped := Landing.interval_for(0.0)
	assert_true(is_finite(stopped), "A zero target speed must not produce INF/NAN — the 0.01 floor guards the divide")
	assert_gt(stopped, 0.0, "A stopped player's interval must stay positive")


## --- footstep VARIETY -------------------------------------------------------------------------------------
## The player's WalkingSFX is ONE node retriggered on a timer, so with a single authored clip at a fixed pitch
## every footfall was byte-identical two or three times a second — a machine gun, not footsteps. Every NPC has
## had a random clip + pitch since LocomotionFx shipped; these pin the same for the player.

func test_step_index_never_repeats_back_to_back() -> void:
	# The whole point of the no-repeat rule: with a 3-clip set a pure roll doubles a third of the time, and a
	# doubled clip is the exact artefact the variety exists to remove — you hear the repeat, not the randomness.
	assert_ne(Landing.next_step_index(1, 1, 3), 1, "a roll matching the last clip must be nudged off it")
	assert_eq(Landing.next_step_index(2, 0, 3), 2, "a roll that already differs is left alone")
	assert_eq(Landing.next_step_index(0, -1, 3), 0, "the FIRST step (last = -1) can use any clip")

func test_step_index_is_always_in_range() -> void:
	# The nudge is a modulo wrap, and the roll is clamped — neither may hand `footstep_sounds` an out-of-bounds
	# index, because that indexes an Array and crashes the physics tick rather than just sounding wrong.
	for last in [-1, 0, 1, 2]:
		for roll in [-5, 0, 1, 2, 99]:
			var i := Landing.next_step_index(roll, last, 3)
			assert_between(i, 0, 2, "index stayed in range for roll=%d last=%d" % [roll, last])
	assert_eq(Landing.next_step_index(0, -1, 1), 0, "a single-clip set always returns that clip, never wraps off it")
	assert_eq(Landing.next_step_index(0, 0, 1), 0, "...even when it repeats — one clip has nothing to alternate with")
	assert_eq(Landing.next_step_index(0, -1, 0), -1, "an EMPTY set reports -1 so the caller leaves the authored stream alone")

func test_vary_step_rotates_clips_and_wobbles_pitch() -> void:
	var landing := Landing.new()
	var sfx := AudioStreamPlayer3D.new()
	var seen := {}
	var prev: AudioStream = null
	var spread: float = GameSettings.audio.footstep_pitch_spread
	for i in 40:
		landing.vary_step(sfx)
		assert_ne(sfx.stream, prev, "step %d replayed the previous clip — the no-repeat rule leaked" % i)
		assert_between(sfx.pitch_scale, 1.0 - spread - 0.001, 1.0 + spread + 0.001,
			"the pitch wobble must stay inside ±footstep_pitch_spread")
		prev = sfx.stream
		seen[sfx.stream] = true
	assert_gt(seen.size(), 1, "40 steps used only one clip — the player is back to a single machine-gunned sample")
	landing.free()
	sfx.free()

func test_vary_step_leaves_an_authored_clip_alone_when_the_set_is_empty() -> void:
	# Clearing footstep_sounds is the supported way for a designer to pin ONE deliberate clip on WalkingSFX; it
	# must not be read as "silence the footsteps" or as licence to null the node's stream.
	var landing := Landing.new()
	landing.footstep_sounds = []
	var sfx := AudioStreamPlayer3D.new()
	var authored: AudioStream = load("res://assets/audio/sfx/Footstep1.mp3")
	sfx.stream = authored
	landing.vary_step(sfx)
	assert_eq(sfx.stream, authored, "an empty set must leave the authored stream untouched")
	assert_ne(sfx.pitch_scale, 0.0, "...while still wobbling the pitch, which needs no clip set")
	landing.free()
	sfx.free()

func test_the_footstep_volume_trim_reaches_both_the_volume_and_the_ceiling() -> void:
	# ⭐The trim has to ride BOTH writes. At WalkingSFX's authored 80 dB base the node outputs its max_db and
	# nothing else, so a trim applied only to volume_db would be inaudible — which is the same dead-knob trap
	# that made someone crank the base to 80 in the first place.
	var original: float = GameSettings.audio.footstep_volume_db
	GameSettings.audio.footstep_volume_db = -5.0
	assert_almost_eq(Landing.step_db(0.0, 0.0, 0.0), -5.0, 0.001, "the trim moves a step's dB on its own")
	assert_almost_eq(Landing.step_db(-7.0, -24.0, -8.0), -44.0, 0.001, "and stacks with the crouch + speed cuts")
	GameSettings.audio.footstep_volume_db = 0.0
	assert_almost_eq(Landing.step_db(-7.0, -24.0, -8.0), -39.0, 0.001,
		"a zero trim must leave the shipped loudness EXACTLY as it was — this knob is opt-in, not a re-mix")
	GameSettings.audio.footstep_volume_db = original  # shared tuning resource; restore for other tests


func test_entry_points_are_null_host_safe() -> void:
	# An off-tree Player built in a unit test has no prefab and no children, so a Landing can legitimately hold a
	# null host. Both entry points must no-op rather than crash.
	var landing := Landing.new()
	landing.on_land(-20.0, Vector3(0, -20, 0))
	landing.tick_footsteps(0.016, 5.0)
	assert_null(landing.host, "This case is only meaningful with a null host")
	assert_eq(landing._footstep_timer, 0.0, "A null-host tick must not advance the footstep timer")
	landing.free()


func test_base_db_capture_latches() -> void:
	# The latch is what stops a re-capture AFTER a crouched step has already cut walking_sfx.volume_db — without
	# it the cut would be baked in as the new base and footsteps would ratchet quieter every step.
	#
	# ⭐IT TAKES A HOST TO TEST THAT AT ALL. _capture_base_db() returns on `host == null` BEFORE it ever reads the
	# latch, so the host-less version of this test stayed green with the latch DELETED — it was pinning the null
	# guard and calling it the ratchet fix. Both directions are asserted below: a first capture must actually
	# happen, and a second must not. Off-tree Player + a hand-wired AudioStreamPlayer3D (the test_fists_view_model
	# idiom): _ready never runs, and an audio node that never play()s touches no device.
	var p = load(PLAYER_SCRIPT).new()
	var sfx := AudioStreamPlayer3D.new()
	sfx.volume_db = -7.0
	sfx.max_db = 3.0
	var landing := Landing.new()
	# Zeroth: a null host must leave the latch DOWN. tick_footsteps re-tries the capture lazily on every tick, and
	# that rescue only works while the latch is down — a null host that latched would pin 0 dB as the base forever.
	landing._capture_base_db()
	assert_false(landing._base_db_captured,
		"a null host must not latch — the lazy re-capture on the first tick is what saves a late-wired host")
	# First capture: the authored volume AND the authored ceiling are both taken, because the per-step cut is
	# written onto both (at WalkingSFX's 80 dB base the ceiling IS the loudness — see tick_footsteps).
	p.walking_sfx = sfx
	landing.host = p
	landing._capture_base_db()
	assert_true(landing._base_db_captured, "a capture with a live host must latch")
	assert_eq(landing._walking_sfx_base_db, -7.0, "...taking the node's authored volume_db as the base")
	assert_eq(landing._walking_sfx_base_max_db, 3.0, "...and its authored max_db as the ceiling base")
	# Second capture, with the live values already cut the way a crouched step cuts them. THIS is the ratchet:
	# re-reading here would make that cut the new base and every following step quieter than the last.
	sfx.volume_db = -21.0
	sfx.max_db = -11.0
	landing._capture_base_db()
	assert_eq(landing._walking_sfx_base_db, -7.0, "a latched base dB must never be re-captured — that is the ratchet")
	assert_eq(landing._walking_sfx_base_max_db, 3.0, "and the latched ceiling must never be re-captured either")
	landing.free()
	sfx.free()
	p.free()
