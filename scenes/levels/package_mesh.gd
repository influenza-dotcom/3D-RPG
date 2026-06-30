extends Node3D
## Makes a 3D object rotate endlessly while bobbing vertically with a sine motion.

# Rotation speed in radians per second.
@export var rotation_speed: float = 2.0

# Maximum vertical displacement from the original position.
@export var bobbing_amplitude: float = 0.5

# How many full bobs (up‑down cycles) per second.
@export var bobbing_frequency: float = 1.5

# Internal timer for the sine wave, frame‑rate independent.
var _time: float = 0.0

# Original local position (used as the reference for bobbing).
var _original_position: Vector3


func _ready() -> void:
	# Store the starting local position so we can restore it each frame.
	_original_position = position


func _process(delta: float) -> void:
	# --- Rotation ---
	# Rotate around the object's own Y axis (up).
	rotate_y(rotation_speed * delta)

	# --- Bobbing ---
	# Advance the timer.
	_time += delta
	
	# Compute the vertical offset using a sine wave.
	var offset: float = sin(_time * bobbing_frequency * TAU) * bobbing_amplitude
	
	# Apply the offset to the Y coordinate while keeping X and Z unchanged.
	position = Vector3(_original_position.x, _original_position.y + offset, _original_position.z)
