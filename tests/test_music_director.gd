extends GutTest

## MusicDirector: the dynamic-music drop-in (constant playback, fade in for combat/dialogue, fade out after).
## Tested in-tree under a bare AudioStreamPlayer (volume_db works with no stream); combat is forced through
## the private flag with the poll pushed out, so no NPCs are needed. The real combat scan + dialogue trigger
## are in-tree behaviour (playtested).

const DIRECTOR_PATH := "res://scripts/components/music_director.gd"


## A minimal stand-in for a playing in-world Radio: a Node3D in the MUSIC group that reports is_playing() and
## carries an audible_radius — exactly the surface MusicDirector._radio_audible_to_player duck-types over. Avoids
## pulling in radio.gd, whose _ready builds a look-at outline / touches global_transform off the rig (GUT 9.6).
class StubRadio extends Node3D:
	var audible_radius: float = 12.0
	var on: bool = true
	func is_playing() -> bool:
		return on


func _make_rig() -> Array:
	var music := AudioStreamPlayer.new()
	music.volume_db = -6.0  # an authored, non-default level — the capture must use THIS as the audible target
	add_child_autofree(music)
	var d = load(DIRECTOR_PATH).new()
	music.add_child(d)  # freed with music via autofree
	return [music, d]


func test_ready_captures_authored_volume_and_silences() -> void:
	var rig := _make_rig()
	var music: AudioStreamPlayer = rig[0]
	var d = rig[1]
	assert_almost_eq(d._audible_db, -6.0, 0.0001, "the parent's authored volume is captured as the fade-in target")
	assert_almost_eq(music.volume_db, d.silent_db, 0.0001, "the track starts SILENT (still playing underneath)")


func test_combat_fades_in_toward_authored_level() -> void:
	var rig := _make_rig()
	var music: AudioStreamPlayer = rig[0]
	var d = rig[1]
	d._poll_t = 999.0     # hold the combat scan off so the forced flag below sticks
	d._in_combat = true
	var before := music.volume_db
	d._process(0.1)
	assert_gt(music.volume_db, before, "combat moves the volume UP toward the audible level")
	for i in 200:
		d._process(0.1)
	assert_almost_eq(music.volume_db, -6.0, 0.0001, "the fade-in settles exactly at the authored level")


func test_leaving_combat_lingers_then_fades_out() -> void:
	var rig := _make_rig()
	var music: AudioStreamPlayer = rig[0]
	var d = rig[1]
	d._poll_t = 999.0
	d._in_combat = true
	for i in 200:
		d._process(0.1)  # fully in
	d._in_combat = false
	d._process(0.1)  # linger window: still holding
	assert_almost_eq(music.volume_db, -6.0, 0.0001, "music HOLDS through the combat linger (no flap at a fight's edge)")
	for i in 200:
		d._process(0.1)  # burn the linger + fade out
	assert_almost_eq(music.volume_db, d.silent_db, 0.0001, "after the linger the music fades back to the silent floor")


func test_degenerate_authored_volume_keeps_fade_meaningful() -> void:
	# A music node authored AT (or below) the silent floor would make "fading in" a no-op or a fade DOWN —
	# the guard warns and drops the floor under the authored level so the feature still works.
	var music := AudioStreamPlayer.new()
	music.volume_db = -60.0  # authored exactly at the default silent_db
	add_child_autofree(music)
	var d = load(DIRECTOR_PATH).new()
	music.add_child(d)
	assert_lt(d.silent_db, d._audible_db, "the silent floor is pushed BELOW the authored level (fade stays meaningful)")
	assert_almost_eq(music.volume_db, d.silent_db, 0.0001, "starts at the adjusted floor")


## --- Radio precedence (yield_to_radio): a diegetic radio the player can hear mutes the combat bed ---

## Build a human player (a bare Node3D in the PLAYER group — not an NPC) and a playing StubRadio in the MUSIC
## group at `radio_pos`, both under the test so the director's get_tree() sees them.
func _add_player_and_radio(radio_pos: Vector3, radius: float = 12.0) -> StubRadio:
	var player := Node3D.new()
	add_child_autofree(player)
	player.add_to_group(Groups.PLAYER)
	player.global_position = Vector3.ZERO
	var radio := StubRadio.new()
	add_child_autofree(radio)
	radio.add_to_group(Groups.MUSIC)
	radio.global_position = radio_pos
	radio.audible_radius = radius
	return radio


func test_audible_radio_holds_combat_bed_silent() -> void:
	var rig := _make_rig()
	var music: AudioStreamPlayer = rig[0]
	var d = rig[1]
	_add_player_and_radio(Vector3(0, 0, 5))  # 5 m away, audible_radius 12 -> within earshot
	d._poll_t = 999.0
	d._in_combat = true
	for i in 50:
		d._process(0.1)
	assert_almost_eq(music.volume_db, d.silent_db, 0.0001, "a playing radio the player can hear keeps the combat bed at the silent floor")


func test_distant_radio_does_not_suppress_combat() -> void:
	var rig := _make_rig()
	var music: AudioStreamPlayer = rig[0]
	var d = rig[1]
	_add_player_and_radio(Vector3(0, 0, 100))  # 100 m away, well outside audible_radius 12
	d._poll_t = 999.0
	d._in_combat = true
	for i in 50:
		d._process(0.1)
	assert_almost_eq(music.volume_db, -6.0, 0.0001, "a radio out of earshot must NOT mute the combat bed (no dead silence for a far fight)")


func test_silent_radio_does_not_suppress_combat() -> void:
	var rig := _make_rig()
	var music: AudioStreamPlayer = rig[0]
	var d = rig[1]
	var radio := _add_player_and_radio(Vector3(0, 0, 5))
	radio.on = false  # switched-off radio in range -> not is_playing() -> no precedence
	d._poll_t = 999.0
	d._in_combat = true
	for i in 50:
		d._process(0.1)
	assert_almost_eq(music.volume_db, -6.0, 0.0001, "only a PLAYING radio claims the soundscape; a switched-off one is ignored")


func test_yield_to_radio_off_ignores_radio() -> void:
	var rig := _make_rig()
	var music: AudioStreamPlayer = rig[0]
	var d = rig[1]
	d.yield_to_radio = false  # opt back into the old behaviour
	_add_player_and_radio(Vector3(0, 0, 5))
	d._poll_t = 999.0
	d._in_combat = true
	for i in 50:
		d._process(0.1)
	assert_almost_eq(music.volume_db, -6.0, 0.0001, "with yield_to_radio off, combat music fades in despite an audible radio")


func test_non_audio_parent_is_inert() -> void:
	var holder := Node.new()
	add_child_autofree(holder)
	var d = load(DIRECTOR_PATH).new()
	holder.add_child(d)  # wrong parent type -> warned + inert
	d._process(0.1)  # must not crash with no captured player
	assert_null(d._music, "a non-audio parent leaves the director inert (warned, no crash)")


## --- Dialogue precedence: an audible radio owns dialogue too (score yields); else the score swells for the talk ---

## A director whose dialogue signal is forced on, so we can test the dialogue fade-in / radio-yield without driving
## a live DialogueManager conversation in a headless run (mirrors test_radio.gd's _FrozenRadio test double).
class DialogueDirector extends MusicDirector:
	var dialogue_on: bool = true
	func _dialogue_active() -> bool:
		return dialogue_on


func _make_dialogue_rig() -> Array:
	var music := AudioStreamPlayer.new()
	music.volume_db = -6.0
	add_child_autofree(music)
	var d := DialogueDirector.new()
	music.add_child(d)  # freed with music via autofree
	return [music, d]


func test_dialogue_bed_fades_in_without_radio() -> void:
	# Base dialogue behaviour is preserved: with no audible radio, an open conversation swells the dynamic score.
	var rig := _make_dialogue_rig()
	var music: AudioStreamPlayer = rig[0]
	var d: DialogueDirector = rig[1]
	for i in 200:
		d._process(0.1)
	assert_almost_eq(music.volume_db, -6.0, 0.0001, "an open conversation fades the dynamic score in to the authored level (no radio to yield to)")


func test_audible_radio_holds_dialogue_bed_silent() -> void:
	# The "radio owns dialogue" choice: an audible radio makes the dynamic score YIELD during a conversation too
	# (not just combat), so the diegetic radio carries the moment instead of two music layers clashing.
	var rig := _make_dialogue_rig()
	var music: AudioStreamPlayer = rig[0]
	var d: DialogueDirector = rig[1]
	_add_player_and_radio(Vector3(0, 0, 5))  # within earshot
	for i in 50:
		d._process(0.1)
	assert_almost_eq(music.volume_db, d.silent_db, 0.0001, "an audible radio makes the dynamic score yield during dialogue too (radio owns the soundscape)")
