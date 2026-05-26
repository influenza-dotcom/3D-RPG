extends SpotLight3D

@onready var flashlight_click: AudioStreamPlayer3D = $FlashlightClick

func _ready() -> void:
	top_level = true

func _process(_delta: float) -> void:
	global_position = get_parent().global_position
	if visible:
		var rate: float = .08
		global_rotation.x = lerp_angle(global_rotation.x, get_parent().global_rotation.x, rate)
		global_rotation.y = lerp_angle(global_rotation.y, get_parent().global_rotation.y, rate)
		global_rotation.z = lerp_angle(global_rotation.z, get_parent().global_rotation.z, rate)
	else:
		global_rotation = get_parent().global_rotation

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("Light") and !flashlight_click.playing: 
		visible = !visible
		flashlight_click.play()
