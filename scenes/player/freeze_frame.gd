extends Node

## FreezeFrame (autoload) — hitstop "juice". Briefly slams Engine.time_scale down,
## then eases it back to 1.0, so impacts (enemy hit/death) land with a punchy
## micro-freeze. Gated by GameSettings.allow_timescale_changes (headless/tests off).
##
## INTERACTION: stomps the GLOBAL Engine.time_scale that BulletTime also eases. A
## freeze fired during bullet time overrides the slow-mo and tweens back to full
## speed (1.0), not back to the bullet-time scale.

## The live recovery tween, kept so cancel() can kill it — a tween that has already been handed to the
## SceneTree cannot be reached any other way, and it is the thing that out-writes a later owner.
var _recovery: Tween = null
## Bumped by every freeze() and by cancel(). freeze() straddles an await, so a freeze that was cancelled
## (or superseded) while its hold was still running must NOT come back afterwards and build a recovery
## tween — it compares its captured generation on the far side of the await and bails if it lost.
var _gen: int = 0

func _ready():
	process_mode = Node.PROCESS_MODE_ALWAYS  # operate even while the tree is paused (we toggle it)

## duration = real-time hold at `scale`; recovery_time = ease back to 1.0.
func freeze(duration: float = 0.005, scale: float = 0.1, recovery_time: float = 0.2):
	if not GameSettings.allow_timescale_changes:
		return
	# Accessibility: the player can opt out of the hitstop slow entirely (some find the micro-freeze
	# disorienting). Read live off the Settings autoload so toggling it applies immediately.
	if not Settings.hitstop_enabled:
		return
	_gen += 1
	var my_gen := _gen
	if _recovery != null and _recovery.is_valid():
		_recovery.kill()  # a second hit mid-recovery restarts the freeze; don't leave two tweens writing time_scale
	_recovery = null
	Engine.time_scale = scale
	# create_timer(time, process_always=true, process_in_physics=true,
	# ignore_time_scale=true): the hold MUST be measured in REAL time, else lowering
	# time_scale would stretch it and the freeze would last far longer than `duration`.
	await get_tree().create_timer(duration, true, true, true).timeout
	if _gen != my_gen:
		return  # cancelled or superseded while we were holding — whoever owns time_scale now keeps it
	# Recovery tween also ignores time_scale so it eases back in real time instead of
	# crawling at the very slow-mo it's undoing.
	var tween := create_tween()
	tween.set_ignore_time_scale(true)
	tween.tween_property(Engine, "time_scale", 1.0, recovery_time)
	_recovery = tween

## Abandon any in-flight hitstop and hand Engine.time_scale back to whoever owns it now. Called from
## Player.die().
##
## ⭐The ORDERING is the whole point. A hitstop's recovery tween is created on the far side of freeze()'s
## real-time hold, so a freeze that lands within `duration` of the killing blow builds its tween AFTER the
## death cinematic's own tween. The SceneTree steps tweens in creation order and the last writer of the
## frame wins, so that recovery would drag Engine.time_scale back toward 1.0 for its whole recovery_time,
## THROUGH the death slow-mo, and then hand back with a single-frame snap down to the death ramp — the
## world lurches and stalls under the corpse. Same hazard die() already neutralises for BulletTime.
##
## Deliberately does NOT write Engine.time_scale itself: the death ramp re-stamps it every frame, and
## writing 1.0 here would fight it. Safe to call when nothing is frozen.
func cancel() -> void:
	_gen += 1  # a freeze still inside its hold will bail after the await instead of building a recovery
	if _recovery != null and _recovery.is_valid():
		_recovery.kill()
	_recovery = null

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
