@tool
class_name AudioZone
extends Area3D

## A drop-in AUDIO ZONE: while the player is inside this volume, a child sound (music, a room tone, a PA loop)
## cross-fades IN; when they leave, it fades back OUT. Drop the area over a region (a bar, a boss arena, a
## reactor room), put an AudioStreamPlayer / AudioStreamPlayer3D child under it set to a non-Master bus, and the
## zone fades that child between `inactive_volume_db` (a near-silent floor) and `active_volume_db` as the player
## crosses the boundary. PROCESS_MODE_ALWAYS so the fade keeps running even while paused (a menu / dialogue
## opened mid-zone). Ref-counts qualifying bodies so overlapping zones / a recruited companion don't double-toggle.

## The group a body must belong to for the zone to count it as "the player". "player" by default.
@export var trigger_group: StringName = &"player"
## Volume (dB) the child player reaches while the player is inside.
@export var active_volume_db: float = 0.0
## Volume (dB) the child player drops to while the player is outside (a low floor = effectively silent).
@export var inactive_volume_db: float = -40.0
## Cross-fade speed in dB per second.
@export var fade_speed: float = 24.0
## Auto-play the child looping player on _ready (so it's already running, just silent, before you ever enter).
@export var autoplay: bool = true

var _inside: int = 0           ## ref-count of qualifying bodies inside (handles overlap / multiple players)
var _player_node: Node = null  ## the child AudioStreamPlayer(3D) to fade

func _ready() -> void:
	if Engine.is_editor_hint():
		return  # @tool: only the configuration warning runs in-editor; the fade is runtime-only
	process_mode = Node.PROCESS_MODE_ALWAYS  # keep fading through a pause (a menu opened mid-zone)
	# Monitor every layer and filter by GROUP, so the zone catches the player whatever physics layer it sits on
	# (matches TriggerVolume) — the designer never matches mask numbers.
	collision_mask = 0xFFFFFFFF
	_player_node = _find_audio_child()
	if _player_node != null:
		_player_node.set(&"volume_db", inactive_volume_db)
		if autoplay and _player_node.get(&"stream") != null:
			_player_node.call(&"play")
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)

func _on_body_entered(body: Node) -> void:
	if body != null and body.is_in_group(trigger_group):
		_inside += 1

func _on_body_exited(body: Node) -> void:
	if body != null and body.is_in_group(trigger_group):
		_inside = maxi(0, _inside - 1)

func _process(delta: float) -> void:
	if _player_node == null:
		return
	var target := active_volume_db if _inside > 0 else inactive_volume_db
	var cur := float(_player_node.get(&"volume_db"))
	if is_equal_approx(cur, target):
		return
	_player_node.set(&"volume_db", move_toward(cur, target, fade_speed * delta))

func is_active() -> bool:
	return _inside > 0

## The first AudioStreamPlayer / AudioStreamPlayer3D child — the sound this zone fades. Split out for the warning + test.
func _find_audio_child() -> Node:
	for c in get_children():
		if c is AudioStreamPlayer or c is AudioStreamPlayer3D:
			return c
	return null

func _get_configuration_warnings() -> PackedStringArray:
	var w := PackedStringArray()
	var has_shape := false
	for c in get_children():
		if c is CollisionShape3D or c is CollisionPolygon3D:
			has_shape = true
			break
	if not has_shape:
		w.append("AudioZone needs a CollisionShape3D child — the volume that detects the player.")
	if _find_audio_child() == null:
		w.append("AudioZone has no AudioStreamPlayer / AudioStreamPlayer3D child — there's nothing to fade.")
	return w
