class_name ScreenShakeSettings
extends Resource

## Tuning for ScreenShake (trauma decay + intensity) plus the explosion/death shake
## events: death_shake_* feed Player.on_nearby_death; explosion_* feed Explosion and
## its screen_shake_area trigger.

@export var decay_rate: float = 5.0
@export var intensity_multiplier: float = 0.1
@export var death_shake_range: float = 8.0
@export var death_shake_amount: float = 1.6
@export var explosion_max_trauma: float = 1.6
@export var explosion_min_shake_radius: float = 5.0
@export var explosion_shake_mult: float = 1.6
