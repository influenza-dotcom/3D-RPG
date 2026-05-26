extends Decal

const TARGET_SIZE: Vector3 = Vector3(4.0, 0.15, 4.0)
const GROW_TIME: float = 1.25

var begin_fade_out: bool = false

func _ready() -> void:
	var tween := create_tween()
	tween.set_trans(Tween.TRANS_QUINT)
	tween.set_ease(Tween.EASE_OUT)
	tween.tween_property(self, "size", TARGET_SIZE, GROW_TIME)

func _process(delta: float) -> void:
	if begin_fade_out:
		modulate.a = lerpf(modulate.a, 0.0, 1.0 - exp(-GameTuning.DECAL_FADE_RATE * delta))
		if modulate.a < GameTuning.DECAL_FADE_MIN_ALPHA:
			queue_free()

func _on_time_til_fadeout_timeout() -> void:
	begin_fade_out = true
