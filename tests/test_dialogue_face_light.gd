extends GutTest

## DialogueFaceLight (scripts/dialogue/dialogue_face_light.gd) is the code-built key light DialogueManager keeps on
## the current speaker's face. Its contract, pinned here with in-tree test doubles and a hand-driven _process:
##   - _ready builds ONE hidden, top_level, shadowless SpotLight3D and runs PROCESS_MODE_ALWAYS so the fade keeps
##     going while dialogue PAUSES the world.
##   - begin(speaker) latches the pose ONCE (a STATIC key light): the first frame a head resolves, the spot sits in
##     front of the face (toward the speaker's own +Z when no human Player is in the tree) at
##     face_light_distance / face_light_height from GameSettings.dialogue, aimed back at the head. Moving the head
##     afterwards must NOT move the light (the head-look turns the head mid-talk; a light that rode along read
##     like it was welded to the head).
##   - a speaker with no head_world_position / head_visual (a note / terminal) never latches and never lights;
##     head_visual is the fallback anchor.
##   - end() fades the light out and hides it; begin() on the next speaker re-latches fresh.
##   - face_light_enabled off keeps it dark; the degenerate straight-down pose skips look_at without an error.
## GameSettings.dialogue is a shared .tres: every field a test touches is snapshotted and restored.

## A speaker whose head resolves the NPC way (head_world_position). In-tree so _front_dir can read its basis.
class _HeadSpeaker extends Node3D:
	var head: Vector3 = Vector3(2.0, 1.7, -3.0)
	func head_world_position() -> Vector3:
		return head

## A speaker with only the swapped-head fallback (head_visual -> a Node3D child).
class _VisualHeadSpeaker extends Node3D:
	var head_node: Node3D = null
	func head_visual() -> Node3D:
		return head_node

## A headless speaker (a Readable note / terminal): no anchor at all.
class _Headless extends Node3D:
	pass

const DIALOGUE_MANAGER_PATH := "res://scripts/dialogue/dialogue_manager.gd"

var _saved_enabled: bool
var _saved_distance: float
var _saved_height: float


func before_each() -> void:
	var cfg: DialogueSettings = GameSettings.dialogue
	_saved_enabled = cfg.face_light_enabled
	_saved_distance = cfg.face_light_distance
	_saved_height = cfg.face_light_height
	cfg.face_light_enabled = true


func after_each() -> void:
	var cfg: DialogueSettings = GameSettings.dialogue
	cfg.face_light_enabled = _saved_enabled
	cfg.face_light_distance = _saved_distance
	cfg.face_light_height = _saved_height


func _make_light() -> DialogueFaceLight:
	var light := DialogueFaceLight.new()
	add_child_autofree(light)
	return light


func _make_head_speaker() -> _HeadSpeaker:
	var spk := _HeadSpeaker.new()
	add_child_autofree(spk)
	return spk


## Where the STATIC pose must land for a head at `head` with no human Player in the tree: in front along the
## speaker's own +Z (identity basis -> (0, 0, 1)), distance + height from the live settings.
func _expected_light_pos(head: Vector3) -> Vector3:
	var cfg: DialogueSettings = GameSettings.dialogue
	return head + Vector3(0.0, 0.0, 1.0) * cfg.face_light_distance + Vector3.UP * cfg.face_light_height


func _step(light: DialogueFaceLight, n: int, delta: float = 0.5) -> void:
	for i in n:
		light._process(delta)


# --- construction --------------------------------------------------------------------------------------------

func test_ready_builds_a_hidden_top_level_shadowless_spot_and_runs_always() -> void:
	var light := _make_light()
	assert_eq(light.process_mode, Node.PROCESS_MODE_ALWAYS,
		"the fade must keep running while dialogue pauses the world (same mode as the manager's other presentation children)")
	var spot: SpotLight3D = light._spot
	assert_not_null(spot, "_ready builds the one SpotLight3D the light steers")
	if spot == null:
		return
	assert_eq(spot.get_parent(), light, "the spot is this node's child (owned, freed with it)")
	assert_true(spot.top_level, "top_level: the pose is set in WORLD space, independent of the autoload's transform")
	assert_false(spot.visible, "hidden at rest: nothing lights between conversations")
	assert_eq(spot.light_energy, 0.0, "dark at rest")
	assert_false(spot.shadow_enabled, "a face key/fill must not cast shadows (cheaper, and face shadows look off)")
	assert_null(light._target, "no speaker until begin()")
	assert_false(light._pose_latched, "no pose latched until a head resolves")


# --- begin(): the static latch ---------------------------------------------------------------------------------

func test_begin_latches_the_pose_in_front_of_the_head_and_lights_up() -> void:
	var light := _make_light()
	var spk := _make_head_speaker()
	light.begin(spk)
	assert_eq(light._target, spk, "begin() records the speaker")
	assert_false(light._pose_latched, "begin() only clears the latch; placement waits for the first frame")
	light._process(0.1)
	assert_true(light._pose_latched, "the first frame a head resolves latches the pose")
	var spot: SpotLight3D = light._spot
	assert_true(spot.visible, "the spot shows the moment it starts fading in")
	assert_gt(light._energy, 0.0, "the fade starts climbing on the first frame")
	assert_almost_eq(spot.light_energy, light._energy, 0.0001, "the spot's energy IS the smoothed envelope (real_t: the engine stores it 32-bit)")
	var expected := _expected_light_pos(spk.head)
	assert_true(spot.global_position.is_equal_approx(expected),
		"the spot sits in front of the face along the speaker's +Z at face_light_distance, raised by face_light_height; got %s want %s" % [str(spot.global_position), str(expected)])
	# Aimed back at the head: the spot's -Z must point from the light toward the head.
	var forward := -spot.global_transform.basis.z
	var to_head := (spk.head - spot.global_position).normalized()
	assert_gt(forward.dot(to_head), 0.999, "look_at aims the spot back at the head (got dot %.3f)" % forward.dot(to_head))


func test_fade_in_settles_at_face_light_energy_and_mirrors_the_look_knobs() -> void:
	var light := _make_light()
	var spk := _make_head_speaker()
	light.begin(spk)
	_step(light, 40)
	var cfg: DialogueSettings = GameSettings.dialogue
	assert_almost_eq(light._energy, cfg.face_light_energy, 0.01,
		"the envelope eases up to face_light_energy (peak)")
	var spot: SpotLight3D = light._spot
	assert_eq(spot.light_color, cfg.face_light_color, "the live-tuned colour is written every lit frame")
	assert_almost_eq(spot.spot_range, cfg.face_light_range, 0.0001, "the live-tuned range is written every lit frame")
	assert_almost_eq(spot.spot_angle, cfg.face_light_spot_angle, 0.0001, "the live-tuned cone is written every lit frame")


func test_pose_stays_fixed_after_the_head_moves() -> void:
	var light := _make_light()
	var spk := _make_head_speaker()
	light.begin(spk)
	light._process(0.1)
	var spot: SpotLight3D = light._spot
	var latched_pos := spot.global_position
	var latched_basis := spot.global_transform.basis
	spk.head += Vector3(3.0, 0.5, 2.0)   # the head-look turns / the NPC shifts mid-talk
	spk.position += Vector3(1.0, 0.0, 0.0)
	_step(light, 10)
	assert_true(spot.global_position.is_equal_approx(latched_pos),
		"STATIC light: a head move after the latch must not move the spot (a light riding the head read as welded to it)")
	assert_true(spot.global_transform.basis.is_equal_approx(latched_basis),
		"STATIC light: the aim is latched too")


func test_head_visual_is_the_fallback_anchor() -> void:
	var light := _make_light()
	var spk := _VisualHeadSpeaker.new()
	add_child_autofree(spk)
	var head := Node3D.new()
	head.position = Vector3(0.0, 1.6, 0.0)
	spk.add_child(head)
	spk.head_node = head
	spk.position = Vector3(4.0, 0.0, 4.0)
	light.begin(spk)
	light._process(0.1)
	assert_true(light._pose_latched, "a swapped visible head node resolves the anchor when head_world_position is absent")
	var expected := _expected_light_pos(head.global_position)
	assert_true(light._spot.global_position.is_equal_approx(expected),
		"the fallback anchor is the head node's GLOBAL position; got %s want %s" % [str(light._spot.global_position), str(expected)])


func test_headless_speaker_never_latches_and_never_lights() -> void:
	var light := _make_light()
	var spk := _Headless.new()
	add_child_autofree(spk)
	light.begin(spk)
	_step(light, 20)
	assert_false(light._pose_latched, "no head_world_position / head_visual -> no anchor -> no latch (the note / terminal case)")
	assert_false(light._spot.visible, "a headless speaker gets no light")
	assert_eq(light._energy, 0.0, "the envelope never leaves 0 without a latched pose")


func test_null_or_freed_speaker_is_dark() -> void:
	var light := _make_light()
	light.begin(null)
	_step(light, 5)
	assert_false(light._spot.visible, "begin(null) lights nothing")
	var spk := _HeadSpeaker.new()
	add_child(spk)
	light.begin(spk)
	light._process(0.1)
	assert_true(light._spot.visible, "sanity: a live head lights")
	spk.free()
	_step(light, 40)
	assert_false(light._spot.visible, "a speaker freed mid-talk (death-abort) reads as inactive and the light fades out")
	assert_lt(light._energy, 0.01, "the envelope eases back to ~0 with no valid target")


# --- end(): release ------------------------------------------------------------------------------------------

func test_end_fades_out_hides_and_clears_the_latch() -> void:
	var light := _make_light()
	var spk := _make_head_speaker()
	light.begin(spk)
	_step(light, 10)
	assert_true(light._spot.visible, "sanity: lit before end()")
	light.end()
	assert_null(light._target, "end() drops the speaker")
	assert_false(light._pose_latched, "end() clears the latch so the next conversation re-places from scratch")
	light._process(0.1)
	assert_true(light._spot.visible, "the light stays visible while it is still fading out on the last pose")
	_step(light, 40)
	assert_false(light._spot.visible, "faded out with no target -> hidden (the idle case)")
	assert_lt(light._energy, 0.01, "the envelope eased back to ~0")


func test_next_begin_relatches_on_the_new_speaker() -> void:
	var light := _make_light()
	var a := _make_head_speaker()
	var b := _make_head_speaker()
	b.head = Vector3(-6.0, 1.5, 8.0)
	light.begin(a)
	light._process(0.1)
	light.end()
	_step(light, 40)
	light.begin(b)
	light._process(0.1)
	assert_true(light._pose_latched, "a fresh conversation latches again")
	var expected := _expected_light_pos(b.head)
	assert_true(light._spot.global_position.is_equal_approx(expected),
		"the second conversation places the light on the NEW head, not the previous pose; got %s want %s" % [str(light._spot.global_position), str(expected)])


# --- settings gates ------------------------------------------------------------------------------------------

func test_face_light_enabled_off_keeps_it_dark() -> void:
	GameSettings.dialogue.face_light_enabled = false
	var light := _make_light()
	var spk := _make_head_speaker()
	light.begin(spk)
	_step(light, 10)
	assert_false(light._pose_latched, "disabled: nothing is placed")
	assert_false(light._spot.visible, "disabled: nothing lights")


func test_straight_down_pose_skips_look_at_without_an_error() -> void:
	# distance 0 + height > 0 puts the light directly ABOVE the head: to_head is parallel to UP, which look_at
	# rejects. The guard must skip the aim (GUT fails this test on any engine error) but still place the light.
	var cfg: DialogueSettings = GameSettings.dialogue
	cfg.face_light_distance = 0.0
	cfg.face_light_height = 0.35
	var light := _make_light()
	var spk := _make_head_speaker()
	light.begin(spk)
	light._process(0.1)
	assert_true(light._pose_latched, "the degenerate pose still latches")
	assert_true(light._spot.global_position.is_equal_approx(spk.head + Vector3.UP * 0.35),
		"the light is placed straight above the head; only the look_at is skipped")
	assert_true(light._spot.visible, "and it still lights")


# --- the DialogueManager seam ----------------------------------------------------------------------------------

## Driven for real on a FRESH DialogueManager in the test tree (never the autoload): its _ready builds the view /
## ducker / music bed / face light, start() runs synchronously up to its intro-beat timer (the window the push
## lands in), and abort() is the death-abort path through _finish(). No speaker name is passed, so GameState's
## talk / name-reveal ledgers are never touched; the world pause and the cursor mode _finish() writes are restored.
func test_a_conversation_lights_its_speakers_face_and_the_end_releases_the_light() -> void:
	var prior_paused := get_tree().paused
	var prior_mouse := Input.mouse_mode
	# start() arms the fresh manager's MusicDucker on the SHARED "music" bus and abort() fades it to the Settings
	# level, not to whatever the bus held before this test -- snapshot it so a full run gets its bus back.
	var music_bus := AudioServer.get_bus_index(MusicDucker.MUSIC_BUS)
	var prior_music_db: float = AudioServer.get_bus_volume_db(music_bus) if music_bus >= 0 else 0.0
	var manager = load(DIALOGUE_MANAGER_PATH).new()
	add_child_autofree(manager)
	var lights: Array[DialogueFaceLight] = []
	for child in manager.get_children():
		if child is DialogueFaceLight:
			lights.append(child as DialogueFaceLight)
	assert_eq(lights.size(), 1, "DialogueManager must build exactly ONE face light child (one light retargeted per speaker, never one per conversation)")
	if lights.size() != 1:
		return
	var light: DialogueFaceLight = lights[0]
	_step(light, 5)
	assert_false(light._spot.visible, "control: with no conversation the manager's face light stays dark")

	var spk := _make_head_speaker()
	var line := DialogueLine.new()
	line.text = "..."
	var convo := DialogueResource.new()
	convo.lines = [line]
	manager.start(convo, spk)
	light._process(0.1)
	assert_true(light._pose_latched and light._spot.visible,
		"start() must push the speaker into the face light: a conversation with a headed NPC lights its face")
	var expected := _expected_light_pos(spk.head)
	assert_true(light._spot.global_position.is_equal_approx(expected),
		"the light keys the face of the speaker start() was handed; got %s want %s" % [str(light._spot.global_position), str(expected)])

	manager.abort()
	assert_false(light._pose_latched, "the conversation's end must release the light's latch so the next talk re-places it")
	_step(light, 40)
	assert_false(light._spot.visible,
		"after the conversation ends the face light fades out and hides -- it must not linger on an NPC that is no longer talking")
	assert_lt(light._energy, 0.01, "the envelope eased back to ~0 once released")

	# Outlast start()'s intro timer so its continuation returns on the ended conversation instead of a freed manager.
	await wait_seconds(GameSettings.dialogue.dialogue_intro_delay + 0.15)
	get_tree().paused = prior_paused
	Input.mouse_mode = prior_mouse
	# Restored AFTER the wait so the ducker's restore tween has already landed and cannot overwrite it.
	if music_bus >= 0:
		AudioServer.set_bus_volume_db(music_bus, prior_music_db)
