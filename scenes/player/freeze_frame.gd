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
	process_mode = Node.PROCESS_MODE_ALWAYS  # operate even while the tree is paused (we toggle it)
	timer = Timer.new()
	timer.one_shot = true
	timer.process_mode = Timer.PROCESS_MODE_ALWAYS
	add_child(timer)

## duration = real-time hold at `scale`; recovery_time = ease back to 1.0.
func freeze(duration: float = 0.005, scale: float = 0.1, recovery_time: float = 0.2):
	if not GameSettings.allow_timescale_changes:
		return
	# Accessibility: the player can opt out of the hitstop slow entirely (some find the micro-freeze
	# disorienting). Read live off the Settings autoload so toggling it applies immediately.
	if not Settings.hitstop_enabled:
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

## Hard pause-on-kill: fully pause the SceneTree for a real beat, then resume. Runs on this autoload
## (not the dying enemy) so the actor freeing can't strand the unpause. No-ops if the tree is already
## paused (e.g. a conversation) so it doesn't wrongly resume that.
func pause_briefly(duration: float = 0.3) -> void:
	# Same gate as freeze(): tests / headless disable disruptive global time effects. Without this a
	# test that triggers a kill would pause the whole SceneTree and leak that pause into later tests.
	if not GameSettings.allow_timescale_changes:
		return
	if get_tree().paused:
		return
	get_tree().paused = true
	# process_always + ignore_time_scale so this timer still ticks while everything else is paused.
	await get_tree().create_timer(duration, true, true, true).timeout
	get_tree().paused = false
