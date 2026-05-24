extends Decal

var begin_fade_out: bool = false

func _process(delta: float) -> void:
	if begin_fade_out:
		modulate.a = lerpf(modulate.a, 0.0, 1.0 - exp(-GameTuning.DECAL_FADE_RATE * delta))
		if modulate.a < GameTuning.DECAL_FADE_MIN_ALPHA:
			queue_free()

func _on_time_til_fadeout_timeout() -> void:
	begin_fade_out = true
