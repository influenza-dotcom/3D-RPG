extends Node

## FreezeFrame (autoload) — hitstop "juice". Briefly slams Engine.time_scale down,
## then eases it back to 1.0, so impacts (enemy hit/death) land with a punchy
## micro-freeze. Gated by GameSettings.allow_timescale_changes (headless/tests off).
##
## INTERACTION: stomps the GLOBAL Engine.time_scale that BulletTime also eases. A
## freeze fired during bullet time overrides the slow-mo and tweens back to full
## speed (1.0), not back to the bullet-time scale.

## TODO: created in _ready but never used — freeze() spawns a fresh one-shot
## SceneTreeTimer instead. Dead member; left as-is (no behavior change).
var timer: Timer

func _ready():
	timer = Timer.new()
	timer.one_shot = true
	timer.process_mode = Timer.PROCESS_MODE_ALWAYS
	add_child(timer)

## duration = real-time hold at `scale`; recovery_time = ease back to 1.0.
func freeze(duration: float = 0.005, scale: float = 0.1, recovery_time: float = 0.2):
	if not GameSettings.allow_timescale_changes:
		return
	Engine.time_scale = scale
	# create_timer(time, process_always=true, process_in_physics=true,
	# ignore_time_scale=true): the hold MUST be measured in REAL time, else lowering
	# time_scale would stretch it and the freeze would last far longer than `duration`.
	await get_tree().create_timer(duration, true, true, true).timeout
	# Recovery tween also ignores time_scale so it eases back in real time instead of
	# crawling at the very slow-mo it's undoing.
	var tween := create_tween()
	tween.set_ignore_time_scale(true)
	tween.tween_property(Engine, "time_scale", 1.0, recovery_time)
