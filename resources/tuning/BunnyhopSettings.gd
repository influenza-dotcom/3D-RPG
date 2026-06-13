class_name BunnyhopSettings
extends Resource

## Tuning for the bunnyhop chain (Bunnyhop) and the speed-based mouse-sensitivity
## falloff (MouseInput). boost_per_hop / max_speed / land_window drive the chain; the
## sens_* pair lowers look sensitivity as horizontal speed climbs, keeping fast bhop
## runs controllable.

@export_group("Bunnyhop Chain")
## Speed (m/s) each chained hop adds on top of base run speed — higher = the chain ramps up faster.
@export var boost_per_hop: float = 1.2
## Hard ceiling (m/s) the bhop chain can reach no matter how long it runs — caps the boost stack.
@export var max_speed: float = 12.0
## Grace window (s) after landing in which the next jump still EXTENDS the chain — the skill timing gate. Smaller = harder to keep a chain alive.
@export var land_window: float = 0.4
## Legacy timing window (s) from the old crouch-gated bhop engage; the current chain ignores it (kept so saved .tres still load).
@export var input_window: float = 0.15
@export_group("Sensitivity Falloff")
## Horizontal speed (m/s) at which look sensitivity STARTS being scaled down — below this, sensitivity is unchanged.
@export var sens_reduction_threshold: float = 6.5
## Sensitivity multiplier reached at max bhop speed (0.5 = half sens) so fast runs aren't twitchy — the floor of the speed-based falloff.
@export var sens_min_multiplier: float = 0.5
