class_name BunnyhopSettings
extends Resource

## Tuning for the bunnyhop chain (Bunnyhop) and the speed-based mouse-sensitivity
## falloff (MouseInput). boost_per_hop / max_speed / land_window drive the chain; the
## sens_* pair lowers look sensitivity as horizontal speed climbs, keeping fast bhop
## runs controllable.

@export var boost_per_hop: float = 1.2
@export var max_speed: float = 12.0
@export var land_window: float = 0.4
@export var input_window: float = 0.15
@export var sens_reduction_threshold: float = 6.5
@export var sens_min_multiplier: float = 0.5
