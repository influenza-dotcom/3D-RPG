extends Node

# AudioManager — central helper for one-shot sound effects.
#
# Use this for free-standing one-shot sounds that do not need a persistent scene
# node. Keep authored/looping/animation-owned AudioStreamPlayer nodes when their
# position, lifetime, fade, or editor wiring is part of the feature.

const DEFAULT_3D_MAX_DISTANCE: float = 30.0
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
func play_sfx(pos: Vector3, stream: AudioStream, volume_db: float = 0.0, pitch_scale: float = 1.0, bus: StringName = &"sfx") -> void:
	if stream == null:
		return
	var player := AudioStreamPlayer3D.new()
	player.stream = stream
	player.volume_db = volume_db
	player.pitch_scale = pitch_scale
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
