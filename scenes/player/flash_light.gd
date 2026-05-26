extends SpotLight3D

const FOLLOW_RATE: float = 5.0

@export var light_position: Marker3D
@onready var flashlight_click: AudioStreamPlayer3D = $FlashlightClick


func _ready() -> void:
	top_level = true

func _process(delta: float) -> void:
	if light_position:
		global_position = light_position.global_position
	var parent_rot: Vector3 = get_parent().global_rotation
	if visible:
		var t := 1.0 - exp(-FOLLOW_RATE * delta)
		global_rotation.x = lerp_angle(global_rotation.x, parent_rot.x, t)
		global_rotation.y = lerp_angle(global_rotation.y, parent_rot.y, t)
		global_rotation.z = lerp_angle(global_rotation.z, parent_rot.z, t)
	else:
		global_rotation = parent_rot

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("Light") and !flashlight_click.playing:
		visible = !visible
		flashlight_click.play()
