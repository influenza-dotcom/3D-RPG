class_name HurtFeedback
extends Node

## Punchy "getting rocked" feedback when the player takes a real hit: a hit hard-dips the global
## time-scale (via FreezeFrame), slaps a low-pass "muffle" on the master bus, punches the camera, and
## drains the screen to a dark red desaturation + tunnel vignette — all eased back together over
## HURT_RECOVERY. Built in code under the Player and given a host ref right after .new().
##
## The HURT_* feel consts + MASTER_BUS stay ON THE PLAYER (a unit test reads them off a bare instance);
## this component references them as Player.HURT_* / Player.MASTER_BUS. The Player keeps thin
## _trigger_hurt / _set_hurt_amount / _setup_hurt_lpf facades that forward here, and clears any
## in-progress hurt on death via clear().

var host: Player

var _hurt_tween: Tween
var _hurt_lpf: AudioEffectLowPassFilter

## Punchy "got hit" feedback: dip the global time-scale (via FreezeFrame), spike the screen-drain +
## audio duck, then ease them all back in REAL time (ignore_time_scale) so they recover in lockstep
## with the slow-mo lift instead of crawling at the slowed rate.
func trigger() -> void:
	if host.screen_shake:
		host.screen_shake.shake(Player.HURT_SHAKE)
	FreezeFrame.freeze(Player.HURT_FREEZE_HOLD, Player.HURT_FREEZE_SCALE, Player.HURT_RECOVERY)
	if _hurt_tween and _hurt_tween.is_valid():
		_hurt_tween.kill()
	set_amount(1.0)
	_hurt_tween = create_tween().set_ignore_time_scale(true)
	_hurt_tween.tween_interval(Player.HURT_FREEZE_HOLD)
	_hurt_tween.tween_method(set_amount, 1.0, 0.0, Player.HURT_RECOVERY)

## Drive both the screen-drain uniform and the master-bus duck from one 0..1 amount.
func set_amount(amount: float) -> void:
	if host._nv_rect:
		var mat := host._nv_rect.material as ShaderMaterial
		if mat:
			mat.set_shader_parameter("hurt", amount)
	if _hurt_lpf:
		# Exponential (log-frequency) sweep so the muffle eases off perceptually evenly.
		_hurt_lpf.cutoff_hz = Player.HURT_LPF_CUTOFF * pow(Player.HURT_LPF_CLEAR / Player.HURT_LPF_CUTOFF, 1.0 - amount)

## Find (or add) a low-pass filter on the master bus for the hurt "muffle". Reused across scene
## reloads (the bus is global) so we don't stack a fresh filter each life; reset to clear on start.
func setup_lpf() -> void:
	for i in AudioServer.get_bus_effect_count(Player.MASTER_BUS):
		var fx := AudioServer.get_bus_effect(Player.MASTER_BUS, i)
		if fx is AudioEffectLowPassFilter:
			_hurt_lpf = fx as AudioEffectLowPassFilter
			break
	if not _hurt_lpf:
		_hurt_lpf = AudioEffectLowPassFilter.new()
		AudioServer.add_bus_effect(Player.MASTER_BUS, _hurt_lpf)
	_hurt_lpf.cutoff_hz = Player.HURT_LPF_CLEAR

## Clear any in-progress hurt feedback (on death) so the ducked master bus doesn't bleed into the
## scene reload — the bus is global, a reload won't reset it, and the next life would read it as base.
func clear() -> void:
	if _hurt_tween and _hurt_tween.is_valid():
		_hurt_tween.kill()
	set_amount(0.0)
