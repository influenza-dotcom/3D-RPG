class_name RandomSize
extends Node

const SIZE_META := &"random_size_mult"

## Drop-in "give this prop a random size" component. It rolls once at spawn,
## multiplies the host Node3D's authored scale, optionally scales a
## Throwable-style impact_damage_mult by that size, and pitches vocal sounds
## inversely so smaller props sound higher while bigger props sound lower.

@export var min_scale_mult: float = 0.75
@export var max_scale_mult: float = 1.35
@export var preset_scale_mult: float = 0.0
@export var affects_impact_damage: bool = true
@export var damage_power: float = 1.0
@export var affects_sound_pitch: bool = true
@export var pitch_power: float = 1.0
@export var enabled: bool = true

var rolled_scale_mult: float = 1.0


func _ready() -> void:
	if Engine.is_editor_hint() or not enabled:
		return
	var host := get_parent() as Node3D
	if host == null:
		return
	rolled_scale_mult = maxf(preset_scale_mult, 0.0) if preset_scale_mult > 0.0 else roll_scale(min_scale_mult, max_scale_mult, randf())
	apply_size(host, rolled_scale_mult, affects_impact_damage, damage_power, affects_sound_pitch, pitch_power)


static func roll_scale(min_mult: float, max_mult: float, roll: float) -> float:
	var lo := maxf(minf(min_mult, max_mult), 0.01)
	var hi := maxf(maxf(min_mult, max_mult), lo)
	return lerpf(lo, hi, clampf(roll, 0.0, 1.0))


static func damage_mult_for_size(size_mult: float, power: float = 1.0) -> float:
	return pow(maxf(size_mult, 0.01), maxf(power, 0.0))


static func pitch_mult_for_size(size_mult: float, power: float = 1.0) -> float:
	return pow(1.0 / maxf(size_mult, 0.01), maxf(power, 0.0))


static func apply_size(host: Node3D, size_mult: float, affects_damage: bool = true, power: float = 1.0, affects_pitch: bool = true, pitch_power_value: float = 1.0) -> void:
	if host == null:
		return
	var safe_mult := maxf(size_mult, 0.01)
	host.scale *= safe_mult
	if affects_damage:
		var current_damage_mult: Variant = host.get(&"impact_damage_mult")
		if typeof(current_damage_mult) == TYPE_FLOAT or typeof(current_damage_mult) == TYPE_INT:
			host.set(&"impact_damage_mult", float(current_damage_mult) * damage_mult_for_size(safe_mult, power))
	if affects_pitch:
		var current_pitch_mult: Variant = host.get(&"sound_pitch_mult")
		if typeof(current_pitch_mult) == TYPE_FLOAT or typeof(current_pitch_mult) == TYPE_INT:
			host.set(&"sound_pitch_mult", float(current_pitch_mult) * pitch_mult_for_size(safe_mult, pitch_power_value))
