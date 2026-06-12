extends GutTest

## MusicDirector: the dynamic-music drop-in (constant playback, fade in for combat/dialogue, fade out after).
## Tested in-tree under a bare AudioStreamPlayer (volume_db works with no stream); combat is forced through
## the private flag with the poll pushed out, so no NPCs are needed. The real combat scan + dialogue trigger
## are in-tree behaviour (playtested).

const DIRECTOR_PATH := "res://scripts/components/music_director.gd"


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


func test_non_audio_parent_is_inert() -> void:
	var holder := Node.new()
	add_child_autofree(holder)
	var d = load(DIRECTOR_PATH).new()
	holder.add_child(d)  # wrong parent type -> warned + inert
	d._process(0.1)  # must not crash with no captured player
	assert_null(d._music, "a non-audio parent leaves the director inert (warned, no crash)")
