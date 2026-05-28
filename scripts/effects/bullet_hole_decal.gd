extends Decal

## Bullet-hole / scorch decal. Sits until a TimeTilFadeout Timer flips begin_fade_out,
## then fades alpha to near-zero and frees. (No grow tween, unlike blood_splat_decal.)

var begin_fade_out: bool = false

func _process(delta: float) -> void:
	if begin_fade_out:
		modulate.a = lerpf(modulate.a, 0.0, 1.0 - exp(-GameSettings.effects.decal_fade_rate * delta))
		if modulate.a < GameSettings.effects.decal_fade_min_alpha:
			queue_free()

func _on_time_til_fadeout_timeout() -> void:
	begin_fade_out = true
