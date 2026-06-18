@tool
class_name Radio
extends LookAtInteractable

## Drop-in in-world RADIO. Aim + Interact toggles it on/off; while on it DUCKS OUT during combat (and dialogue),
## breathing back in after a short settle once the fight ends. Combat is detected with the same poll/linger as
## MusicDirector (any "npc" hunting), and like MusicDirector this node runs PROCESS_MODE_ALWAYS so the duck
## keeps moving through a pausing menu instead of freezing.
##
## SOURCE: plays a shipped, royalty-free `fallback_audio` track out of a child AudioStreamPlayer3D on the music
## bus — spatial, in-engine, diegetic. (A later slice generalizes this single track into a folder playlist.) The
## radio joins the &"music" group while on, so nearby NPCs notice + react to it (gated by GameSettings.npc_ai.music_reactions).
##
## SETUP: drop it under a radio prop (or set highlight_target), size its CollisionShape3D to the body you aim
## at, set fallback_audio (a shipped, royalty-free track), and name it.

@export_group("Radio")
## Hover/label name; blank -> "radio".
@export var radio_name: String = ""
## The shipped, royalty-free track this radio plays. Null -> silent.
@export var fallback_audio: AudioStream:
	set(value):
		fallback_audio = value
		update_configuration_warnings()
## The spatial player the audio comes out of. Leave unset to auto-create a child AudioStreamPlayer3D on the music bus.
@export var audio_player: AudioStreamPlayer3D

@export_group("Combat duck")
## false -> duck through the whole hunt (matches the music system); true -> only duck in an active firefight.
@export var combat_strict: bool = false
## Seconds between combat scans of the "npc" group (a per-frame scan would be waste).
@export var poll_interval: float = 0.3
## Seconds the radio stays ducked after the last enemy disengages, so it doesn't flap at a fight's ragged edge.
@export var settle_cooldown: float = 3.0
## Seconds to duck OUT when combat hits (fast).
@export var fade_pause_time: float = 0.4
## Seconds to ease back IN once the coast clears.
@export var fade_resume_time: float = 1.2
## The ducked/off floor (dB) — effectively inaudible while the stream still plays underneath.
@export var silent_db: float = -60.0
## The on/audible volume (dB) for the player.
@export var fallback_volume_db: float = 0.0

@export_group("Click SFX")
## Played once when the radio is switched ON (a physical click / clunk). Null -> silent.
@export var click_on: AudioStream
## Played once when switched OFF. Null -> silent (a designer may reuse click_on for both).
@export var click_off: AudioStream
## Volume (dB) of the on/off click.
@export var click_volume_db: float = 0.0
## The player the click comes out of. Leave unset to auto-create a child AudioStreamPlayer3D on the SFX bus, so the combat music-duck never touches it.
@export var click_player: AudioStreamPlayer3D

@export_group("Music reactions")
## How far (m) a nearby NPC can "hear" this radio and react (turn to face it + comment by quality). Only matters
## when GameSettings.npc_ai.music_reactions is on; otherwise a playing radio is inert to NPCs.
@export var audible_radius: float = 12.0

var _state := RadioPlaybackState.new()
var _poll_t: float = 0.0
var _combat_now: bool = false

## Editor warning: with no fallback_audio this radio has no track and will be silent. Surface that at edit time.
func _get_configuration_warnings() -> PackedStringArray:
	if fallback_audio == null:
		return PackedStringArray([
			"No `fallback_audio` — this radio has no track and will be silent. Assign a royalty-free AudioStream.",
		])
	return PackedStringArray()

func _ready() -> void:
	if Engine.is_editor_hint():
		_editor_fit_hitbox()  # preview the auto-fit hitbox in-editor (resizes an existing collider; safe)
		return  # @tool: only _get_configuration_warnings runs in-editor; the audio/outline setup is runtime-only
	# Look-at hitbox on the talk layer (like the other interactables) + the hover outline.
	collision_layer = TalkHelpers.TALK_LAYER
	collision_mask = 0
	_build_outline()
	if auto_fit_collider:
		_fit_hitbox_to_host()
	# Keep ducking through a pausing menu / dialogue tree-pause, exactly like MusicDirector (music_director.gd:35).
	process_mode = Node.PROCESS_MODE_ALWAYS
	if audio_player == null:
		audio_player = AudioStreamPlayer3D.new()
		audio_player.bus = &"music"
		add_child(audio_player)
	# A SEPARATE, non-looping player for the on/off click on the SFX bus (the music player loops the track and is
	# volume-driven every frame, so a click must never share it).
	if click_player == null:
		click_player = AudioStreamPlayer3D.new()
		click_player.bus = &"sfx"
		add_child(click_player)
	audio_player.stream = fallback_audio
	_state.configure(fallback_volume_db, silent_db, fade_pause_time, fade_resume_time, settle_cooldown)
	audio_player.volume_db = silent_db

func _process(delta: float) -> void:
	if Engine.is_editor_hint():
		return  # @tool: _state + the autoloads (DialogueManager, ...) don't exist in-editor; the duck brain is runtime-only
	# Combat scan on an interval (mirrors music_director.gd:54-79), then drive the duck/settle brain.
	_poll_t -= delta
	if _poll_t <= 0.0:
		_poll_t = poll_interval
		_combat_now = _any_npc_fighting()
	var dialogue_active: bool = DialogueManager.is_active()
	_state.tick(delta, _combat_now, dialogue_active, false)
	if audio_player != null:
		audio_player.volume_db = _state.current_db
		# Fully stop a switched-off radio once it's faded down, so "off" isn't a silent running stream.
		if not _state.is_playing() and _state.at_silent() and audio_player.playing:
			audio_player.stop()

## True while any NPC is fighting — hunting (ALERTED/INVESTIGATING) by default, or only an active firefight
## when combat_strict. Null-guarded for a bare off-tree instance (no tree -> no combat). Mirrors MusicDirector.
func _any_npc_fighting() -> bool:
	# is_inside_tree() FIRST — calling get_tree() while off-tree itself logs a tracked engine error (which
	# fails GUT 9.6), so guard on tree membership rather than get_tree() == null.
	if not is_inside_tree():
		return false
	for n in get_tree().get_nodes_in_group(&"npc"):
		if not (n is NPC):
			continue
		var npc := n as NPC
		var fighting: bool = npc.is_in_combat() if combat_strict else npc.is_hunting()
		if fighting:
			return true
	return false


# ---------------------------------------------------------------------------
# Behaviour (talk-handler surface)
# ---------------------------------------------------------------------------

## Interact pressed while aimed at us: toggle the radio on/off.
func start_talk(player: Node) -> void:
	if _state.is_playing():
		_turn_off(player)
	else:
		_turn_on(player)

func _turn_on(player: Node) -> void:
	_play_click(click_on)
	_state.set_playing(true)
	add_to_group(&"music")  # a playing radio NPCs can hear + react to (gated by GameSettings.npc_ai.music_reactions)
	_play_fallback()
	_toast(player, "on")

func _turn_off(player: Node) -> void:
	_play_click(click_off)
	_state.set_playing(false)  # _process stops the stream once it's faded to silent
	remove_from_group(&"music")  # off -> NPCs stop hearing it
	_toast(player, "off")

## Start the radio's track.
func _play_fallback() -> void:
	if audio_player != null and audio_player.stream != null and not audio_player.playing:
		audio_player.play()

## One-shot on/off click out of the dedicated SFX-bus player (never the looping music player). No-op if unset --
## including off-tree tests, which never run _ready, so click_player stays null.
func _play_click(stream: AudioStream) -> void:
	if stream == null or click_player == null:
		return
	click_player.stream = stream
	click_player.volume_db = click_volume_db
	click_player.play()

## True while the radio is switched on -- read by the NPC music-reaction scan.
func is_playing() -> bool:
	return _state.is_playing()

## The text the song-quality scorer reads for THIS radio (the NPC music-reaction scan): the radio name for now;
## a later slice returns the current track filename.
func quality_text() -> String:
	return radio_name

func _toast(player: Node, state_word: String) -> void:
	if player != null and player.has_method(&"notify_toast"):
		var where: String = radio_name if not radio_name.is_empty() else "Radio"
		player.notify_toast("%s %s" % [where, state_word], Color(0.5, 0.8, 1.0))

## Hover readout reflects the on/off state.
func look_name() -> String:
	var where: String = radio_name if not radio_name.is_empty() else "radio"
	return "Turn off %s" % where if _state.is_playing() else "Turn on %s" % where

## Always interactable (toggling is always allowed; a radio with no source just stays silent).
func can_be_talked_to() -> bool:
	return true
