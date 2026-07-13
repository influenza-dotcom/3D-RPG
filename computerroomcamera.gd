extends Camera3D

@onready var monitor_glow: OmniLight3D = $"../computer/MonitorGlow"

@export var go_to_light: bool = false

func _process(delta: float) -> void:
	if go_to_light:
		look_at(monitor_glow.position)
		position = lerp(position, monitor_glow.position, 1.0 - exp(-.125 * delta))
