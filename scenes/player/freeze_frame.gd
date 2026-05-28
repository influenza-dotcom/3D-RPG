extends Node

var timer: Timer

func _ready():
	timer = Timer.new()
	timer.one_shot = true
	timer.process_mode = Timer.PROCESS_MODE_ALWAYS
	add_child(timer)

func freeze(duration: float = 0.005, scale: float = 0.1, recovery_time: float = 0.2):
	if not GameSettings.allow_timescale_changes:
		return
	Engine.time_scale = scale
	await get_tree().create_timer(duration, true, true, true).timeout
	var tween := create_tween()
	tween.set_ignore_time_scale(true)
	tween.tween_property(Engine, "time_scale", 1.0, recovery_time)
