extends Node

## @system Effect And Audio Seams
## @seam One-shot SFX seam: play_sfx/play_2d_sfx spawn self-freeing players on the sfx bus (default) so volume sliders apply; play_applause is the shared kill+pet cheer; stop_sfx cuts all sfx-bus players, freeing only ONE_SHOT_META ones.
## @risk A sound spawned bare (not via play_sfx) lands on Master and silently ignores the SFX volume slider AND the death cinematic's world duck (so it blares under the death card) — no error; the bus=&"sfx" default guards the code side, tests/test_audio_bus_hygiene.gd guards the authored-scene side.
## @risk Re-adding a local applause copy in death.gd/pettable.gd instead of calling play_applause drifts the kill vs pet cheer apart, and no test asserts they delegate.
## @test res://tests/test_audio_manager_spawn.gd
## @test res://tests/test_autoload_order.gd

# AudioManager — central helper for one-shot sound effects.
#
# Use this for free-standing one-shot sounds that do not need a persistent scene
# node. Keep authored/looping/animation-owned AudioStreamPlayer nodes when their
# position, lifetime, fade, or editor wiring is part of the feature.

const DEFAULT_3D_MAX_DISTANCE: float = 30.0
## AudioStreamPlayer3D's OWN default ceiling, mirrored here so the spawned one-shot keeps behaving exactly as it
## did before `max_db` became a parameter. NOT a tuning knob — a caller that wants a different ceiling passes one.
const DEFAULT_MAX_DB: float = 3.0
const SFX_BUS: StringName = &"sfx"
const ONE_SHOT_META: StringName = &"_audio_manager_one_shot"

## The crowd-applause cheer clip + its brief-beat/fade timing. THE single source for "the applause" reward, shared
## by the all-headshots kill (scenes/enemies/death.gd) AND petting a Pettable (scripts/components/pettable.gd) so the
## cheer never drifts between the two. See play_applause.
const APPLAUSE := preload("uid://ccuwf868b4w2j")
const APPLAUSE_HOLD: float = 0.88     ## seconds at full volume before the fade starts
const APPLAUSE_FADE: float = 0.8      ## seconds the fade-out runs
const APPLAUSE_FADE_TO_DB: float = -40.0  ## near-silence target the fade eases to


## One-shot positional SFX. Routed to the `bus` (default "sfx") so the audio-options sliders actually
## affect it — a bare AudioStreamPlayer3D.new() lands on Master and ignores the SFX volume setting.
##
## ⭐`max_db` IS the audible loudness for this project's authored idiom, and callers that modulate volume have to
## pass it. AudioStreamPlayer3D outputs `min(volume_db + distance_attenuation, max_db)`, and the attenuation is
## POSITIVE inside `unit_size` (~+20 dB at 1 m with the default 10). At the volume_db ≈ 80 this project authors
## everywhere (weapon.tscn / enemy.tscn / the Player's audio exports), the sum is ~100 dB at any playable range —
## permanently pinned to the ceiling — so a caller that cuts only `volume_db` cuts NOTHING you can hear. Carrying
## the ceiling is the same discipline weapon_audio.gd / projectile.gd already follow when they copy an authored
## node's max_db onto their spawned one-shot.
func play_sfx(pos: Vector3, stream: AudioStream, volume_db: float = 0.0, pitch_scale: float = 1.0, bus: StringName = &"sfx", max_db: float = DEFAULT_MAX_DB) -> void:
	if stream == null:
		return
	var player := AudioStreamPlayer3D.new()
	player.stream = stream
	player.volume_db = volume_db
	player.pitch_scale = pitch_scale
	player.max_db = max_db
	player.max_distance = DEFAULT_3D_MAX_DISTANCE
	player.bus = bus
	player.set_meta(ONE_SHOT_META, true)
	player.finished.connect(player.queue_free)
	get_tree().root.add_child(player)
	player.global_position = pos
	player.play()


## One-shot 2D (in-your-ear) SFX. Routed to the `bus` (default "sfx") — see play_sfx.
func play_2d_sfx(stream: AudioStream, volume_db: float = 0.0, pitch_scale: float = 1.0, bus: StringName = &"sfx") -> void:
	if stream == null:
		return
	var player := AudioStreamPlayer.new()
	player.stream = stream
	player.volume_db = volume_db
	player.pitch_scale = pitch_scale
	player.bus = bus
	player.set_meta(ONE_SHOT_META, true)
	player.finished.connect(player.queue_free)
	get_tree().root.add_child(player)
	player.play()


## Play the crowd-applause cheer (2D, in-your-ear): a short beat at full volume then a quick fade, so the whole
## cheer lands in ~1.7s instead of dragging out the full crowd clip. Uses its OWN player + tween (NOT play_2d_sfx,
## whose auto-free-on-finish fights an early fade). The reward for an all-headshots kill (death.gd) AND for petting
## a Pettable both call this, so the cheer is defined in exactly one place.
func play_applause() -> void:
	var applause := AudioStreamPlayer.new()
	applause.stream = APPLAUSE
	applause.bus = &"sfx"  # respect the SFX volume slider (a bare player lands on Master and ignores it)
	applause.set_meta(ONE_SHOT_META, true)
	get_tree().root.add_child(applause)
	applause.play()
	var tw := applause.create_tween()
	tw.tween_interval(APPLAUSE_HOLD)
	tw.tween_property(applause, "volume_db", APPLAUSE_FADE_TO_DB, APPLAUSE_FADE)
	tw.tween_callback(applause.queue_free)


## Immediately cut any currently-playing SFX-bus players in the live tree.
## Persistent authored players are stopped in place; AudioManager one-shots are freed so stopping them does not leak.
func stop_sfx() -> void:
	var tree := get_tree()
	if tree == null:
		return
	_stop_sfx_under(tree.root)


func _stop_sfx_under(node: Node) -> void:
	if node is AudioStreamPlayer or node is AudioStreamPlayer2D or node is AudioStreamPlayer3D:
		if node.get(&"bus") == SFX_BUS and bool(node.get(&"playing")):
			node.call(&"stop")
			if node.has_meta(ONE_SHOT_META):
				node.queue_free()
	for child in node.get_children():
		_stop_sfx_under(child)
