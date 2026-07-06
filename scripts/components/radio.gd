@tool
class_name Radio
extends LookAtInteractable

## Drop-in in-world RADIO. Aim + Interact toggles it on/off. By DEFAULT the radio TAKES PRECEDENCE over the dynamic
## combat score: it plays straight through a firefight while MusicDirector holds the combat bed silent for anyone
## within earshot (the radio you can hear owns the soundscape). During DIALOGUE it KEEPS PLAYING and only dips with
## the rest of the music bus (the cinematic MusicDucker quieting — the &"radio" bus sends into &"music", so a
## conversation lowers it a few dB but never hides it). Set `duck_for_dialogue` to restore the old behaviour (the
## radio ducks fully OUT for the conversation and breathes back in when it ends). Set `duck_for_combat` to flip
## combat back too: the radio ducks for combat (same poll/linger as MusicDirector — any "npc" hunting) and the
## combat bed plays over it. Like MusicDirector this node runs PROCESS_MODE_ALWAYS so its ducks (the opt-in
## dialogue/combat ones) keep moving through a pausing menu.
## ONLY the audio duck runs through a pause, though: the note particles and the bounce (visual offset + rigid-body
## impulse) FREEZE with the world while the tree is paused. Emitting notes through a pause looked like a bug, and
## — worse — pumping upward impulses into a RigidBody the physics server has frozen makes them PILE UP in its
## linear_velocity and fire all at once on unpause (a radio you stood on during dialogue launches you on exit).
##
## SOURCE precedence (highest first): a single pinned `track` (a SPECIFIC song for THIS radio — plays it on
## loop and ignores everything below, INCLUDING the player's own-music override) -> the FOLDER of tracks
## (`music_folder`) -> the single shipped `fallback_audio`. The folder cycles through a child AudioStreamPlayer3D
## on the &"radio" bus — spatial, in-engine, diegetic, classic-radio style: auto-advances on track end and loops
## the folder (optional per-radio shuffle). (A later Options setting lets the player point ALL radios at their OWN
## folder, overriding music_folder — but NOT a pinned `track`.)
## The radio joins the &"music" group while on, so nearby NPCs notice + react (gated by GameSettings.npc_ai.music_reactions).
##
## SETUP: drop it under a radio prop (or set highlight_target), size its CollisionShape3D to the body you aim
## at, then pick a source — assign `track` for ONE specific song, point music_folder at a folder of tracks, or
## set fallback_audio for a single track — and name it.

@export_group("Radio")
## Hover/label name; blank -> "radio".
@export var radio_name: String = ""
## A single pinned song for THIS radio. When set, the radio plays EXACTLY this track on loop and IGNORES
## `music_folder`, `shuffle`, AND the player's own-music Options override (`Settings.music_folder`) — a SPECIFIC
## song for a specific radio (a story beat, a location theme). Leave null to use the folder/fallback below instead.
@export var track: AudioStream:
	set(value):
		track = value
		update_configuration_warnings()
## Folder of audio tracks (mp3/ogg/wav) this radio cycles through — auto-advance + loop, classic-radio style.
## Default: the shipped music folder. Empty / no audio files inside -> the single `fallback_audio` track instead.
## (A later Options setting lets the player override this with their OWN folder, for all radios.)
@export_dir var music_folder: String = "res://assets/audio/music":
	set(value):
		music_folder = value
		update_configuration_warnings()
## true -> play the folder in a per-radio-deterministic shuffled order; false -> on-disk (alphabetical) order.
@export var shuffle: bool = false
## A single shipped, royalty-free track, used when `music_folder` has no audio files. Null + empty folder -> silent.
@export var fallback_audio: AudioStream:
	set(value):
		fallback_audio = value
		update_configuration_warnings()
## The spatial player the audio comes out of. Leave unset to auto-create a child AudioStreamPlayer3D on the music bus.
@export var audio_player: AudioStreamPlayer3D

@export_group("Combat duck")
## false (default) -> the radio TAKES PRECEDENCE over the combat score: it plays through the fight and never ducks
## for combat (MusicDirector.yield_to_radio silences the combat bed instead). true -> the old behaviour: the radio
## ducks OUT for combat and the combat bed plays over it. Dialogue ducking is independent of this (`duck_for_dialogue`).
@export var duck_for_combat: bool = false
## Only matters when `duck_for_combat` is on: false -> duck through the whole hunt (matches the music system);
## true -> only duck in an active firefight.
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

@export_group("Dialogue duck")
## false (default) -> the radio KEEPS PLAYING through a conversation, only dipping with the music bus (the cinematic
## MusicDucker on the &"music" bus, which the &"radio" bus sends into) — audible, not hidden. true -> the old
## behaviour: the radio ducks fully OUT to `silent_db` while a dialogue/menu is up and eases back in when it closes,
## reusing the same `fade_pause_time` / `fade_resume_time` as the combat duck above. Independent of `duck_for_combat`.
@export var duck_for_dialogue: bool = false

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

@export_group("Note particles")
## While the radio has an actual track playing, launch Minecraft-style note particles that float up and disappear.
@export var show_music_note: bool = true
## Glyph drawn in the world-space Label3D. The engine default font includes this monochrome music note.
@export var note_glyph: String = "♪"
## Base tint when `note_rainbow` is off.
@export var note_color: Color = Color(0.45, 0.9, 1.0)
## Cycle through bright note colors like note-block particles.
@export var note_rainbow: bool = true
## Height above the radio component origin (m) where notes spawn. Raise it for tall props, lower it for table radios.
@export var note_height: float = 1.35
## How far each note floats upward before fading.
@export var note_rise: float = 0.85
## Random horizontal spread while a note rises.
@export var note_spread: float = 0.28
## Seconds between launched note particles while music is playing.
@export_range(0.05, 2.0, 0.01) var note_emit_interval: float = 0.35
## How long each launched note lives before it frees itself.
@export_range(0.05, 3.0, 0.01) var note_lifetime: float = 0.9
## Music-note glyph size (Label3D font size, scaled to world metres by note_pixel_size).
@export var note_font_size: int = 180
## World metres per font pixel. Default gives a readable cue without swallowing the prop.
@export var note_pixel_size: float = 0.004
## Seconds at the end of a note's life spent fading out.
@export_range(0.0, 1.0, 0.01) var note_fade_time: float = 0.35

@export_group("Bounce")
## While music is playing, bounce the radio itself. RigidBody3D targets get real impulses; non-physics
## targets get a visual-only local offset that is removed cleanly when playback stops.
@export var vibration_enabled: bool = true
## Optional node to vibrate. Null => `highlight_target` if set, else the parent prop, else this Radio node.
@export var vibration_target: Node3D
## Visual-only bounce amplitude for non-RigidBody targets (m).
@export_range(0.0, 0.2, 0.001) var vibration_visual_bounce: float = 0.055
## Side-to-side visual wobble as a fraction of `vibration_visual_bounce` for non-RigidBody targets.
@export_range(0.0, 1.0, 0.01) var vibration_visual_side: float = 0.14
## Bounce cycles per second.
@export_range(0.1, 20.0, 0.1) var vibration_rate: float = 3.0
## Upward impulse applied once per vibration cycle when the target is a RigidBody3D — a real little HOP off the
## ground (per unit body mass ≈ the launch speed in m/s: 2.0 on a ~1 kg prop ≈ a 20 cm hop). It only fires while the
## body is RESTING on something (see _target_grounded), so it bounces in place and gravity brings each hop back —
## it never gets shoved around mid-air or builds up. Raise for a livelier bounce; a tiny value reads as speaker shake.
@export_range(0.0, 8.0, 0.01) var vibration_impulse: float = 2.0
## Tiny sideways impulse mixed into the rigid-body pulse so a loose prop jitters instead of pogoing perfectly upward.
@export_range(0.0, 0.2, 0.001) var vibration_side_impulse: float = 0.02

var _state := RadioPlaybackState.new()
var _playlist := MusicPlaylist.new()
var _poll_t: float = 0.0
var _combat_now: bool = false
var _note_emit_t: float = 0.0
var _note_color_phase: float = 0.0
var _visual_vibration_target: Node3D = null
var _visual_vibration_offset: Vector3 = Vector3.ZERO
var _visual_vibration_phase: float = 0.0
var _physics_vibration_phase: float = 0.0
var _physics_vibration_wave: float = 0.0

## Editor warning: a radio with no pinned track, no folder of tracks, AND no fallback is silent. Surface it at edit time.
func _get_configuration_warnings() -> PackedStringArray:
	if track == null and fallback_audio == null and _scan_audio_folder(music_folder).is_empty():
		return PackedStringArray([
			"No tracks — `track` is unset, `music_folder` has no audio files, and `fallback_audio` is unset, so this "
			+ "radio is silent. Pin a single `track`, point `music_folder` at mp3/ogg/wav files, or assign `fallback_audio`.",
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
	# Keep ducking through a pausing menu / dialogue tree-pause, exactly like MusicDirector (music_director.gd:43).
	process_mode = Node.PROCESS_MODE_ALWAYS
	if audio_player == null:
		audio_player = AudioStreamPlayer3D.new()
		# The dedicated &"radio" bus carries a tinny "real radio" effect chain (high-pass + light drive +
		# low-pass) and SENDS into &"music" — so the radio still rides the Music volume slider and the
		# dialogue/combat duck, but ONLY the radio is band-limited (the MusicDirector score stays clean).
		audio_player.bus = &"radio"
		add_child(audio_player)
	# A SEPARATE, non-looping player for the on/off click on the SFX bus (the music player loops the track and is
	# volume-driven every frame, so a click must never share it).
	if click_player == null:
		click_player = AudioStreamPlayer3D.new()
		click_player.bus = &"sfx"
		add_child(click_player)
	# Auto-advance the playlist when a track ends (looping the folder); a lone fallback track just repeats.
	if not audio_player.finished.is_connected(_on_track_finished):
		audio_player.finished.connect(_on_track_finished)
	audio_player.stream = fallback_audio
	_state.configure(fallback_volume_db, silent_db, fade_pause_time, fade_resume_time, settle_cooldown)
	audio_player.volume_db = silent_db

func _exit_tree() -> void:
	_clear_visual_vibration()

func _process(delta: float) -> void:
	if Engine.is_editor_hint():
		return  # @tool: _state + the autoloads (DialogueManager, ...) don't exist in-editor; the duck brain is runtime-only
	# Combat scan on an interval (mirrors music_director.gd), then drive the duck/settle brain. When the radio
	# takes precedence (duck_for_combat off, the default), we skip the scan and never feed combat into the state
	# machine — the radio plays through the fight; the combat bed yields instead (MusicDirector.yield_to_radio).
	if duck_for_combat:
		_poll_t -= delta
		if _poll_t <= 0.0:
			_poll_t = poll_interval
			_combat_now = _any_npc_fighting()
	else:
		_combat_now = false
	# Dialogue duck is OPT-IN (duck_for_dialogue): by default the radio plays THROUGH a conversation and only dips
	# with the music bus (MusicDucker), so it never abruptly vanishes. Opt in to restore the old full duck-out.
	var dialogue_active: bool = _dialogue_suppresses(DialogueManager.is_active())
	_state.tick(delta, _combat_now, dialogue_active, false)
	if audio_player != null:
		audio_player.volume_db = _state.current_db
		# Fully stop a switched-off radio once it's faded down, so "off" isn't a silent running stream.
		if not _state.is_playing() and _state.at_silent() and audio_player.playing:
			audio_player.stop()
	# The audio duck above rides through a pause (PROCESS_MODE_ALWAYS); the COSMETIC layers must not. While the
	# world is frozen (dialogue tree-pause / a pausing menu / a freeze-frame) hold the note particles and the
	# visual bounce in place — spawning notes through a pause reads as a bug. Already-launched note tweens live on
	# pausable nodes, so they freeze with the world too; we just stop launching new ones.
	if not _effects_frozen():
		_update_music_notes(delta)
		_update_visual_vibration(delta)

func _physics_process(delta: float) -> void:
	if Engine.is_editor_hint():
		return
	# NEVER pump rigid-body impulses while the world is paused: the physics server has frozen the body, so each
	# apply_central_impulse accumulates into its linear_velocity instead of being spent on motion + shed by gravity,
	# then launches the prop (and anything standing on it) the instant we unpause. Freeze the bounce with the world.
	if _effects_frozen():
		return
	_update_physics_vibration(delta)

## True while the world is frozen (a dialogue tree-pause, a pausing NPC-transaction menu, or a freeze-frame). We
## run _process / _physics_process THROUGH a pause (PROCESS_MODE_ALWAYS) only for the audio duck; the note particles
## and the bounce (visual offset + rigid-body impulse) gate on this so they freeze with the world. is_inside_tree()
## FIRST: off-tree unit tests drive _process/_physics_process directly, and there is no tree to be paused there
## (get_tree() would be null) — so this reads false and the effects run exactly as before.
func _effects_frozen() -> bool:
	return is_inside_tree() and get_tree().paused

## Active music means "switched on AND an AudioStreamPlayer3D is actually playing a stream." Dialogue/combat ducking
## may make it quiet, but the stream still runs underneath, so the note bursts and bounce continue through duck fades.
func is_playing_music() -> bool:
	return _state.is_playing() and audio_player != null and audio_player.playing

func _update_music_notes(delta: float) -> void:
	if not show_music_note or not is_playing_music():
		_note_emit_t = 0.0
		return
	_note_emit_t -= delta
	while _note_emit_t <= 0.0:
		_spawn_music_note()
		_note_emit_t += maxf(note_emit_interval, 0.01)

func _spawn_music_note() -> void:
	if not is_inside_tree():
		return
	var note := Label3D.new()
	note.text = note_glyph
	note.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	note.no_depth_test = true
	note.shaded = false
	note.modulate = _next_note_color()
	note.font_size = note_font_size
	note.pixel_size = note_pixel_size
	note.outline_size = 20
	note.outline_modulate = Color(0.0, 0.0, 0.0, 0.72)
	note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	note.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	note.scale = Vector3.ONE * randf_range(0.72, 0.9)

	var start := Vector3(
		randf_range(-note_spread * 0.2, note_spread * 0.2),
		note_height,
		randf_range(-note_spread * 0.2, note_spread * 0.2)
	)
	var end := start + Vector3(
		randf_range(-note_spread, note_spread),
		note_rise,
		randf_range(-note_spread, note_spread)
	)
	var note_parent := get_tree().current_scene if get_tree().current_scene != null else self
	note_parent.add_child(note)
	note.global_position = global_position + start

	var fade_time := minf(note_fade_time, note_lifetime)
	var fade_delay := maxf(0.0, note_lifetime - fade_time)
	var tween := note.create_tween().set_parallel(true)
	tween.tween_property(note, "global_position", global_position + end, note_lifetime).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tween.tween_property(note, "scale", Vector3.ONE, minf(note_lifetime * 0.3, 0.22)).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(note, "modulate:a", 0.0, fade_time).set_delay(fade_delay)
	tween.tween_property(note, "outline_modulate:a", 0.0, fade_time).set_delay(fade_delay)
	tween.chain().tween_callback(note.queue_free)

func _next_note_color() -> Color:
	if not note_rainbow:
		return note_color
	_note_color_phase = fposmod(_note_color_phase + randf_range(0.13, 0.23), 1.0)
	return Color.from_hsv(_note_color_phase, 0.82, 1.0, note_color.a)

func _update_visual_vibration(delta: float) -> void:
	var target := _resolved_vibration_target()
	if not vibration_enabled or not is_playing_music() or target == null or target is RigidBody3D:
		_clear_visual_vibration()
		return
	_visual_vibration_phase = fposmod(_visual_vibration_phase + TAU * vibration_rate * delta, TAU)
	var vertical := absf(sin(_visual_vibration_phase)) * vibration_visual_bounce
	var side := vibration_visual_bounce * vibration_visual_side
	var offset := Vector3(
		sin(_visual_vibration_phase * 1.7) * side,
		vertical,
		cos(_visual_vibration_phase * 1.3) * side
	)
	_apply_visual_vibration(target, offset)

func _apply_visual_vibration(target: Node3D, offset: Vector3) -> void:
	if _visual_vibration_target != null and _visual_vibration_target != target and is_instance_valid(_visual_vibration_target):
		_visual_vibration_target.position -= _visual_vibration_offset
		_visual_vibration_offset = Vector3.ZERO
	if is_instance_valid(target):
		if _visual_vibration_target == target:
			target.position -= _visual_vibration_offset
		target.position += offset
		_visual_vibration_target = target
		_visual_vibration_offset = offset

func _clear_visual_vibration() -> void:
	if _visual_vibration_target != null and is_instance_valid(_visual_vibration_target):
		_visual_vibration_target.position -= _visual_vibration_offset
	_visual_vibration_target = null
	_visual_vibration_offset = Vector3.ZERO

func _update_physics_vibration(delta: float) -> void:
	if not vibration_enabled or not is_playing_music():
		_physics_vibration_wave = 0.0
		return
	var target := _resolved_vibration_target()
	if not (target is RigidBody3D):
		_physics_vibration_wave = 0.0
		return
	var rb := target as RigidBody3D
	if rb.freeze or vibration_impulse <= 0.0:
		return
	_physics_vibration_phase = fposmod(_physics_vibration_phase + TAU * vibration_rate * delta, TAU)
	var wave := sin(_physics_vibration_phase)
	# Kick once per rising half-cycle, but ONLY while the body is resting on something: a grounded prop HOPS off the
	# floor and arcs back down; an airborne one (mid-hop) is left alone. Pushing a bigger impulse into an already-
	# rising body would just shove it around erratically (jitter, not a bounce) — gating on the ground turns it into
	# clean discrete hops. Missing a beat while airborne is fine; the next up-beat after it lands kicks again.
	if _physics_vibration_wave <= 0.0 and wave > 0.0 and _target_grounded(rb):
		rb.sleeping = false
		var impulse := Vector3.UP * vibration_impulse
		if vibration_side_impulse > 0.0:
			impulse += Vector3(cos(_physics_vibration_phase * 0.73), 0.0, sin(_physics_vibration_phase * 1.11)) * vibration_side_impulse
		rb.apply_central_impulse(impulse)
	_physics_vibration_wave = wave

## True while the vibration target is resting against something (the floor / a shelf) — the bounce impulse only fires
## from a contact, so the prop hops off the ground instead of being pushed while airborne. A SLEEPING body is grounded
## by definition (a RigidBody only sleeps once it has settled onto a support, never mid-air), which also covers the
## case where a fully-settled body stops reporting contacts. Otherwise it consults the body's contact monitor
## (RigidBody Throwables enable it in _ready); a body WITHOUT a monitor falls back to "vertically near-still" (an
## airborne hop moves fast in Y). Off-tree -> false (unit tests drive the vibration without a physics world).
func _target_grounded(rb: RigidBody3D) -> bool:
	if not rb.is_inside_tree():
		return false
	if rb.sleeping:
		return true
	if rb.contact_monitor and rb.max_contacts_reported > 0:
		return not rb.get_colliding_bodies().is_empty()
	return absf(rb.linear_velocity.y) <= 0.75

func _resolved_vibration_target() -> Node3D:
	if vibration_target != null and is_instance_valid(vibration_target):
		return vibration_target
	if highlight_target != null and is_instance_valid(highlight_target):
		return highlight_target
	var parent := get_parent()
	if parent is Node3D:
		return parent as Node3D
	return self

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

## True when an open conversation should duck THIS radio fully OUT — only when the designer opted in via
## `duck_for_dialogue`. Off (the default) the radio keeps playing and just rides the music bus's gentle
## MusicDucker dip, so talking to someone never hides it. Pure + param-driven so it's unit-testable without
## the DialogueManager autoload.
func _dialogue_suppresses(dialogue_open: bool) -> bool:
	return duck_for_dialogue and dialogue_open


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
	_load_playlist()
	_play_current()
	_toast(player, "on")

func _turn_off(player: Node) -> void:
	_play_click(click_off)
	_state.set_playing(false)  # _process stops the stream once it's faded to silent
	remove_from_group(&"music")  # off -> NPCs stop hearing it
	_toast(player, "off")

## Build the playlist from the effective folder (scan -> audio paths -> seeded order). An empty/unset folder
## leaves the playlist empty, so _play_current falls back to the single `fallback_audio` track. Re-scanned on
## every turn-on so dropping new files into the folder (or the player changing Settings.music_folder) is picked up.
## A pinned `track` wins outright: skip the folder scan (even the player's own Settings.music_folder) and leave
## the playlist empty, routing _resolve_stream / _on_track_finished through the single-track (loop) path.
func _load_playlist() -> void:
	if track != null:
		_playlist.set_tracks(PackedStringArray(), false, 0, true)
		return
	_playlist.set_tracks(_scan_audio_folder(_effective_folder()), shuffle, radio_name.hash(), true)

## The folder this radio actually scans: the player's OWN folder (Settings.music_folder) when they've set one,
## else this radio's curated `music_folder` export. Runtime-only (reads the Settings autoload, absent in-editor).
func _effective_folder() -> String:
	return _resolve_folder(Settings.music_folder, music_folder)

## Pure precedence: a non-blank player override wins, else the radio's own folder. Split out so it's unit-testable
## without the autoload.
func _resolve_folder(override_dir: String, fallback: String) -> String:
	return override_dir if not override_dir.strip_edges().is_empty() else fallback

## Start the current track: the playlist's current track if the folder has any, else the single fallback. No-op
## off-tree (audio_player is null until _ready), so a bare test instance never sounds.
func _play_current() -> void:
	if audio_player == null:
		return
	var stream := _resolve_stream()
	if stream == null:
		return
	audio_player.stream = stream
	audio_player.play()

## A track ended: while the radio is ON, roll to the next folder track (looping) — the lone fallback just
## repeats. Ignored when off (turn-off stop()s the player, and stop() doesn't emit `finished` anyway).
## We SKIP tracks that fail to decode so one bad file in the player's own folder doesn't freeze the loop
## (a non-playing player never re-emits `finished`). Bounded by size() so an all-undecodable folder gives up
## after one pass instead of spinning within a frame.
func _on_track_finished() -> void:
	if not _state.is_playing():
		return
	if not _playlist.has_tracks():
		_play_current()  # no folder -> the pinned `track` / lone fallback just repeats
		return
	var attempts: int = _playlist.size()
	while attempts > 0:
		_playlist.advance()  # wraps back to the first past the end (loop)
		var stream := _load_stream(_playlist.current())
		if stream == null and fallback_audio != null:
			stream = fallback_audio
		if stream != null and audio_player != null:
			audio_player.stream = stream
			audio_player.play()
			return
		attempts -= 1
	# Nothing playable this whole pass: fall back if we have one (its `finished` re-tries the folder next beat).
	if fallback_audio != null:
		_play_current()

## The AudioStream to play right now: the pinned `track` if set (highest precedence — beats the folder AND the
## player's own-music override), else the playlist's current folder track (loaded from disk) if available, else
## the designer's single fallback_audio. A folder track that fails to load drops to the fallback for that beat.
func _resolve_stream() -> AudioStream:
	if track != null:
		return track
	if _playlist.has_tracks():
		var s := _load_stream(_playlist.current())
		if s != null:
			return s
	return fallback_audio

## Load a track by path. A res:// path is an imported asset -> load() returns the ready stream. A path OUTSIDE
## res:// (the player's own folder — user:// or an OS path) has no import pipeline, so it's decoded from raw
## bytes by extension. Undecodable / unreadable -> null (that track is skipped for this beat).
func _load_stream(path: String) -> AudioStream:
	if path.is_empty():
		return null
	if path.begins_with("res://"):
		return load(path) as AudioStream
	return _load_external_stream(path)

## Decode an audio file from outside res:// from raw bytes by extension (mp3 via AudioStreamMP3.data; ogg/wav
## via their load_from_file). Returns null for an unreadable file or an unsupported/undecodable codec.
func _load_external_stream(path: String) -> AudioStream:
	if not FileAccess.file_exists(path):
		return null  # guard FIRST: load_from_file / get_file_as_bytes on a missing file logs a tracked engine error
	var ext := path.get_extension().to_lower()
	if ext == "ogg":
		return AudioStreamOggVorbis.load_from_file(path)
	if ext == "wav":
		return AudioStreamWAV.load_from_file(path)
	if ext == "mp3":
		var bytes := FileAccess.get_file_as_bytes(path)
		if bytes.is_empty():
			return null
		var s := AudioStreamMP3.new()
		s.data = bytes
		return s
	return null

## Scan `folder` for audio files (mp3/ogg/wav), returning their full paths sorted by name. The extension
## whitelist skips Godot's `.import`/`.remap` sidecars. Returns empty for a blank/unopenable folder. NOTE: a
## res:// scan sees the SOURCE files when running from the editor (the user's workflow); the player's own
## folder (Slice C, user:// or an OS path) is always real files.
func _scan_audio_folder(folder: String) -> PackedStringArray:
	var out := PackedStringArray()
	if folder.is_empty():
		return out
	var dir := DirAccess.open(folder)
	if dir == null:
		return out
	var base := folder.trim_suffix("/")
	for f in dir.get_files():
		var ext := f.get_extension().to_lower()
		if ext == "mp3" or ext == "ogg" or ext == "wav":
			out.append(base + "/" + f)
	out.sort()
	return out

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

## The text the song-quality scorer reads for THIS radio (the NPC music-reaction scan): the pinned `track`'s
## filename when one is set, else the current folder track's filename when a playlist is active (so an NPC scores
## the actual SONG), else the radio name. The same string always scores the same, so reactions are stable per track.
func quality_text() -> String:
	if track != null:
		var p := track.resource_path
		return p.get_file() if not p.is_empty() else radio_name
	if _playlist.has_tracks():
		var n := _playlist.current_name()
		if not n.is_empty():
			return n
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
