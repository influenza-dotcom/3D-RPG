@tool
class_name AmbientSound
extends Node3D

## Drop-in looping AMBIENT bed — wind, a machine hum, crowd murmur, a flickering-light buzz. Drop it where the
## sound lives, assign a `stream`, done: it auto-creates a child AudioStreamPlayer3D on the `ambient` bus (so the
## Ambient volume slider governs it, NOT Master — the footgun a bare AudioStreamPlayer3D.new() falls into) and
## loops forever. Positional by default (it fades with distance); flip `loop` off for a one-shot establishing cue.

## The looping sound. Empty = silent (and a configuration warning).
@export var stream: AudioStream:
	set(value):
		stream = value
		if _player != null:
			_player.stream = value
		update_configuration_warnings()
## Volume in dB applied to the player.
@export var volume_db: float = 0.0:
	set(value):
		volume_db = value
		if _player != null:
			_player.volume_db = value
## The audio bus this routes to — keep it on a non-Master bus so its volume slider applies. "ambient" by default.
@export var bus: StringName = &"ambient"
## Loop forever (re-play on finish). Off = play once when the level loads / play() is called.
@export var loop: bool = true
## Start playing as soon as the level loads. Off = call play() from a trigger / cutscene.
@export var autoplay: bool = true
## Max distance (m) the sound carries. 0 = AudioStreamPlayer3D's own default.
@export var max_distance: float = 0.0
## How fast the sound falls off with distance (AudioStreamPlayer3D.unit_size).
@export var unit_size: float = 10.0

var _player: AudioStreamPlayer3D

func _ready() -> void:
	if Engine.is_editor_hint():
		return  # @tool: only the configuration warning runs in-editor; the player is runtime-only
	_player = AudioStreamPlayer3D.new()
	_player.stream = stream
	_player.bus = bus
	_player.volume_db = volume_db
	_player.unit_size = unit_size
	if max_distance > 0.0:
		_player.max_distance = max_distance
	add_child(_player)
	_player.finished.connect(_on_finished)
	if autoplay and stream != null:
		_player.play()

## Re-play on finish so the bed loops regardless of the stream's own loop flag (the designer-friendly default).
func _on_finished() -> void:
	if loop and _player != null:
		_player.play()

## Start (or restart) the bed — for a trigger / cutscene that switches ambience on.
func play() -> void:
	if _player != null and stream != null:
		_player.play()

## Silence the bed.
func stop() -> void:
	if _player != null:
		_player.stop()

func is_playing() -> bool:
	return _player != null and _player.playing

func _get_configuration_warnings() -> PackedStringArray:
	var w := PackedStringArray()
	if stream == null:
		w.append("AmbientSound has no `stream` — it will be silent. Assign an AudioStream.")
	if AudioServer.get_bus_index(bus) < 0:
		w.append("`bus` '%s' isn't in the project's audio bus layout — it would fall back to Master and ignore the volume slider." % str(bus))
	return w
