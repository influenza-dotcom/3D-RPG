class_name ParticleTimeBind
extends GPUParticles3D

# Forces the particle system's speed_scale to track Engine.time_scale so the
# effect visibly slows during bullet time / freeze frames instead of finishing
# at full speed while the world is slowed.
#
# Caches the scene-set speed_scale as the "base" at _ready, then multiplies by
# Engine.time_scale each frame. process_mode is set to ALWAYS so freeze-frame
# pauses still update the value (otherwise particles would freeze at the last
# pre-pause scale and pop back to full speed when unpaused).

var _base_speed_scale: float = 1.0

func _ready() -> void:
	_base_speed_scale = speed_scale
	process_mode = Node.PROCESS_MODE_ALWAYS

func _process(_delta: float) -> void:
	speed_scale = _base_speed_scale * Engine.time_scale
