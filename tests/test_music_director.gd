extends GutTest

## MusicDirector: the dynamic-music drop-in (constant playback, a three-tier FULL / CAUTION / SILENT ladder).
## Tested in-tree under a bare AudioStreamPlayer (volume_db works with no stream); each tier is forced through
## its private flag with the poll pushed out, so no NPCs are needed. The real group scan (_scan_alert_levels,
## which needs live NPCs with a Perception) + the dialogue trigger are in-tree behaviour (playtested).
## The rig authors -6 dB, so with the default caution_duck_db (-6) the CAUTION level is exactly -12 dB.

const DIRECTOR_PATH := "res://scripts/components/music_director.gd"


## A minimal stand-in for a playing in-world Radio: a Node3D in the MUSIC group that reports is_playing() and
## carries an audible_radius — exactly the surface MusicDirector._radio_audible_to_player duck-types over. Avoids
## pulling in radio.gd, whose _ready builds a look-at outline / touches global_transform off the rig (GUT 9.6).
class StubRadio extends Node3D:
	var audible_radius: float = 12.0
	var on: bool = true
	func is_playing() -> bool:
		return on


class RadioDirector extends MusicDirector:
	var player: Node3D = null
	func _real_player() -> Node3D:
		return player


func _make_rig() -> Array:
	var music := AudioStreamPlayer.new()
	music.volume_db = -6.0  # an authored, non-default level — the capture must use THIS as the audible target
	add_child_autofree(music)
	var d := RadioDirector.new()
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
	assert_almost_eq(music.volume_db, d.silent_db, 0.0001, "a fight that ends with nobody left hunting (a clean kill: ALERTED straight to gone) fades to the silent floor, NOT to the caution level")
	assert_lt(music.volume_db, d.caution_db(), "regression guard: silence must still be reachable below the caution tier")


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

## Build a player-position test double and a playing StubRadio in the MUSIC group at `radio_pos`, both under the
## test so the director's get_tree() sees the radio while the test seam supplies the player position.
func _add_player_and_radio(d: RadioDirector, radio_pos: Vector3, radius: float = 12.0) -> StubRadio:
	var player := Node3D.new()
	add_child_autofree(player)
	player.add_to_group(Groups.PLAYER)
	player.global_position = Vector3.ZERO
	d.player = player
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
	_add_player_and_radio(d, Vector3(0, 0, 5))  # 5 m away, audible_radius 12 -> within earshot
	d._poll_t = 999.0
	d._in_combat = true
	for i in 50:
		d._process(0.1)
	assert_almost_eq(music.volume_db, d.silent_db, 0.0001, "a playing radio the player can hear keeps the combat bed at the silent floor")


func test_distant_radio_does_not_suppress_combat() -> void:
	var rig := _make_rig()
	var music: AudioStreamPlayer = rig[0]
	var d = rig[1]
	_add_player_and_radio(d, Vector3(0, 0, 100))  # 100 m away, well outside audible_radius 12
	d._poll_t = 999.0
	d._in_combat = true
	for i in 50:
		d._process(0.1)
	assert_almost_eq(music.volume_db, -6.0, 0.0001, "a radio out of earshot must NOT mute the combat bed (no dead silence for a far fight)")


func test_silent_radio_does_not_suppress_combat() -> void:
	var rig := _make_rig()
	var music: AudioStreamPlayer = rig[0]
	var d = rig[1]
	var radio := _add_player_and_radio(d, Vector3(0, 0, 5))
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
	_add_player_and_radio(d, Vector3(0, 0, 5))
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


## --- Dialogue trigger: OFF by default (dialogue plays with no music bed); opt in via swell_for_dialogue ---

## A director whose dialogue signal is forced on, so we can test the dialogue trigger / radio-yield without driving
## a live DialogueManager conversation in a headless run (mirrors test_radio.gd's _FrozenRadio test double).
class DialogueDirector extends RadioDirector:
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


func test_dialogue_bed_stays_silent_by_default() -> void:
	# "Remove the music from dialog": swell_for_dialogue defaults OFF, so an open conversation does NOT swell the
	# dynamic score — it holds at the silent floor and the talk plays with no music bed.
	var rig := _make_dialogue_rig()
	var music: AudioStreamPlayer = rig[0]
	var d: DialogueDirector = rig[1]
	d._poll_t = 999.0  # don't let the live group scan decide this — no NPC in the GUT tree should be able to
	assert_false(d.swell_for_dialogue, "the dialogue swell is opt-in — off by default")
	for i in 200:
		d._process(0.1)
	assert_almost_eq(music.volume_db, d.silent_db, 0.0001, "with swell_for_dialogue off, a conversation keeps the score at the silent floor (no music bed)")


func test_dialogue_bed_fades_in_when_opted_in() -> void:
	# The opt-in path still works: with swell_for_dialogue on and no audible radio, an open conversation swells the score.
	var rig := _make_dialogue_rig()
	var music: AudioStreamPlayer = rig[0]
	var d: DialogueDirector = rig[1]
	d._poll_t = 999.0
	d.swell_for_dialogue = true
	for i in 200:
		d._process(0.1)
	assert_almost_eq(music.volume_db, -6.0, 0.0001, "swell_for_dialogue on fades the dynamic score in to the authored level (no radio to yield to)")


func test_audible_radio_holds_dialogue_bed_silent_when_opted_in() -> void:
	# The "radio owns dialogue" precedence still applies to the OPT-IN dialogue swell: with swell_for_dialogue on,
	# an audible radio makes the dynamic score YIELD during a conversation, so the diegetic radio carries the moment.
	var rig := _make_dialogue_rig()
	var music: AudioStreamPlayer = rig[0]
	var d: DialogueDirector = rig[1]
	d.swell_for_dialogue = true
	_add_player_and_radio(d, Vector3(0, 0, 5))  # within earshot
	for i in 50:
		d._process(0.1)
	assert_almost_eq(music.volume_db, d.silent_db, 0.0001, "an audible radio makes the opted-in dialogue score yield (radio owns the soundscape)")


## --- CAUTION tier: a searcher SUSTAINS the score, ducked, instead of dropping it to silence ---

func test_caution_level_sits_between_silence_and_the_fight() -> void:
	var rig := _make_rig()
	var d = rig[1]
	assert_lt(d.caution_duck_db, 0.0, "the duck is a NEGATIVE offset (house convention: music_duck_amount_db)")
	assert_almost_eq(d.caution_db(), -12.0, 0.0001, "authored -6 dB ducked by the default -6 -> the search plays at -12 dB")
	assert_lt(d.caution_db(), d._audible_db, "a search must never be as loud as a firefight")
	assert_gt(d.caution_db(), d.silent_db, "a search must be AUDIBLE — that is the whole point of the tier")


func test_caution_alone_fades_the_bed_in_ducked() -> void:
	# A fresh investigation with no prior fight still starts the bed — it just starts it quiet.
	var rig := _make_rig()
	var music: AudioStreamPlayer = rig[0]
	var d = rig[1]
	d._poll_t = 999.0
	d._in_caution = true
	for i in 200:
		d._process(0.1)
	assert_almost_eq(music.volume_db, d.caution_db(), 0.0001, "a hunt with nobody shooting settles at the ducked caution level")


func test_combat_outranks_caution() -> void:
	# Mixed crowd: one NPC shooting, another still sweeping. The firefight owns the mix.
	var rig := _make_rig()
	var music: AudioStreamPlayer = rig[0]
	var d = rig[1]
	d._poll_t = 999.0
	d._in_combat = true
	d._in_caution = true
	for i in 200:
		d._process(0.1)
	assert_almost_eq(music.volume_db, -6.0, 0.0001, "FULL beats CAUTION — a live fight plays at the authored level")


func test_fight_ending_into_a_search_ducks_instead_of_fading_out() -> void:
	# THE headline behaviour: losing you drops the NPC ALERTED -> INVESTIGATING. The music must NOT fade out.
	var rig := _make_rig()
	var music: AudioStreamPlayer = rig[0]
	var d = rig[1]
	d._poll_t = 999.0
	d._in_combat = true
	for i in 200:
		d._process(0.1)  # fully in
	d._in_combat = false
	d._in_caution = true
	d._process(0.1)
	assert_almost_eq(music.volume_db, -6.0, 0.0001, "the combat linger still holds FULL across the handover")
	for i in 200:
		d._process(0.1)
	assert_almost_eq(music.volume_db, d.caution_db(), 0.0001, "once the linger burns, the score DUCKS to the caution level — it does not go silent")
	assert_gt(music.volume_db, d.silent_db, "the search keeps playing (regression guard for the old fade-to-silence)")


func test_search_giving_up_lingers_then_fades_to_silence() -> void:
	var rig := _make_rig()
	var music: AudioStreamPlayer = rig[0]
	var d = rig[1]
	d._poll_t = 999.0
	d._in_caution = true
	for i in 200:
		d._process(0.1)
	d._in_caution = false
	d._process(0.1)
	assert_almost_eq(music.volume_db, d.caution_db(), 0.0001, "the caution linger holds through the tail of a search (no flap on a 0.3 s poll)")
	for i in 200:
		d._process(0.1)
	assert_almost_eq(music.volume_db, d.silent_db, 0.0001, "with nobody hunting any more the bed finally returns to the silent floor")


func test_combat_to_caution_duck_runs_at_the_fade_out_rate() -> void:
	# Direction — not "is anything wanted" — picks the fade time, or this downward step would use fade_in_time.
	var rig := _make_rig()
	var music: AudioStreamPlayer = rig[0]
	var d = rig[1]
	d._poll_t = 999.0
	d._in_combat = true
	for i in 200:
		d._process(0.1)
	d._in_combat = false
	d._linger_t = 0.0     # burn the FULL hold so the very next tick is the duck itself
	d._in_caution = true
	d._process(0.1)
	# span 54 dB over fade_out_time 3.0 s = 18 dB/s; one 0.1 s tick = 1.8 dB below the authored -6.
	assert_almost_eq(music.volume_db, -7.8, 0.0001, "the duck steps at the fade-OUT rate (18 dB/s), not the fade-in rate")


func test_caution_duck_is_clamped_into_the_band() -> void:
	var rig := _make_rig()
	var d = rig[1]
	d.caution_duck_db = 12.0    # a sign slip: a search must not get LOUDER than the fight
	assert_almost_eq(d.caution_db(), d._audible_db, 0.0001, "a positive duck clamps to the authored level")
	d.caution_duck_db = -200.0  # absurdly deep
	assert_almost_eq(d.caution_db(), d.silent_db, 0.0001, "an over-deep duck clamps to the silent floor, never below it")


func test_duck_at_the_floor_restores_silent_searching() -> void:
	# The documented OFF SWITCH: a duck that reaches the floor is the old behaviour, searching in tense silence.
	var rig := _make_rig()
	var music: AudioStreamPlayer = rig[0]
	var d = rig[1]
	d.caution_duck_db = -60.0
	d._poll_t = 999.0
	d._in_caution = true
	for i in 200:
		d._process(0.1)
	assert_almost_eq(music.volume_db, d.silent_db, 0.0001, "caution_duck_db at the floor opts back out of the caution tier entirely")


func test_audible_radio_holds_the_caution_bed_silent_too() -> void:
	# Radio precedence collapses BOTH top tiers, not just combat.
	var rig := _make_rig()
	var music: AudioStreamPlayer = rig[0]
	var d = rig[1]
	_add_player_and_radio(d, Vector3(0, 0, 5))  # within earshot
	d._poll_t = 999.0
	d._in_caution = true
	for i in 200:
		d._process(0.1)
	assert_almost_eq(music.volume_db, d.silent_db, 0.0001, "a radio the player can hear owns the soundscape during a search as well")


func test_distant_radio_does_not_suppress_caution() -> void:
	var rig := _make_rig()
	var music: AudioStreamPlayer = rig[0]
	var d = rig[1]
	_add_player_and_radio(d, Vector3(0, 0, 100))  # well outside audible_radius 12
	d._poll_t = 999.0
	d._in_caution = true
	for i in 200:
		d._process(0.1)
	assert_almost_eq(music.volume_db, d.caution_db(), 0.0001, "a radio out of earshot must not mute the search bed either")


## --- A conversation FREEZES the world, so a polled tier must not latch under the dialogue ---

func test_dialogue_suppresses_a_latched_search() -> void:
	# DialogueManager pauses the tree, so an INVESTIGATING NPC can never finish searching while the box is up.
	# Without the suppression gate the ducked bed would play under every line, stacked on DialogueMusicBed.
	var rig := _make_dialogue_rig()
	var music: AudioStreamPlayer = rig[0]
	var d: DialogueDirector = rig[1]
	d._poll_t = 999.0
	d._in_caution = true       # a searcher frozen mid-hunt by the pause
	for i in 200:
		d._process(0.1)
	assert_almost_eq(music.volume_db, d.silent_db, 0.0001, "an open conversation holds the bed at the silent floor even with a searcher latched outside")


func test_dialogue_suppresses_a_lingering_fight_too() -> void:
	# The same gate closes the older, smaller hole: a combat_linger tail bleeding into a conversation's opening.
	var rig := _make_dialogue_rig()
	var music: AudioStreamPlayer = rig[0]
	var d: DialogueDirector = rig[1]
	d._poll_t = 999.0
	d._in_combat = true
	for i in 200:
		d._process(0.1)
	assert_almost_eq(music.volume_db, d.silent_db, 0.0001, "with swell_for_dialogue off, no tier survives an open conversation")


func test_dialogue_suppression_lifts_when_the_conversation_ends() -> void:
	# The gate must be a gate, not a latch: hanging up hands the hunt its bed straight back.
	var rig := _make_dialogue_rig()
	var music: AudioStreamPlayer = rig[0]
	var d: DialogueDirector = rig[1]
	d._poll_t = 999.0
	d._in_caution = true
	for i in 50:
		d._process(0.1)
	assert_almost_eq(music.volume_db, d.silent_db, 0.0001, "suppressed while talking")
	d.dialogue_on = false
	for i in 200:
		d._process(0.1)
	assert_almost_eq(music.volume_db, d.caution_db(), 0.0001, "conversation over — the still-running search gets its ducked bed back")


func test_opted_in_swell_is_not_suppressed() -> void:
	# swell_for_dialogue is the explicit opt OUT of the gate: the score plays under the conversation on purpose.
	var rig := _make_dialogue_rig()
	var music: AudioStreamPlayer = rig[0]
	var d: DialogueDirector = rig[1]
	d._poll_t = 999.0
	d.swell_for_dialogue = true
	d._in_caution = true
	for i in 200:
		d._process(0.1)
	assert_almost_eq(music.volume_db, -6.0, 0.0001, "opted in, the conversation itself swells the score to FULL regardless of the caution tier underneath")
