extends Decal

@export var target_size: Vector3 = Vector3(4.0, 0.15, 4.0)
@export var grow_time: float = 1.25

var begin_fade_out: bool = false

func _ready() -> void:
	var tween := create_tween()
	tween.set_trans(Tween.TRANS_QUINT)
	tween.set_ease(Tween.EASE_OUT)
	tween.tween_property(self, "size", target_size, grow_time)

func _process(delta: float) -> void:
	if begin_fade_out:
		modulate.a = lerpf(modulate.a, 0.0, 1.0 - exp(-GameSettings.effects.decal_fade_rate * delta))
		if modulate.a < GameSettings.effects.decal_fade_min_alpha:
			queue_free()

func _on_time_til_fadeout_timeout() -> void:
	begin_fade_out = true
