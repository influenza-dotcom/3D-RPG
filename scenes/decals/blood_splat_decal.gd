extends Decal

var begin_fade_out: bool = false
var _original_size: Vector3

func _ready() -> void:
	# Store the original size set in the inspector
	var intended_size = Vector3.ONE * 8

	# Quickly grow to full size (0.1 seconds)
	var tween = create_tween()
	tween.set_trans(Tween.TRANS_QUINT)
	tween.set_ease(Tween.EASE_OUT)
	tween.tween_property(self, "size", intended_size, 1.25)

func _process(delta: float) -> void:
	if begin_fade_out:
		modulate.a = lerpf(modulate.a, 0.0, 1.0 - exp(-GameTuning.DECAL_FADE_RATE * delta))
		if modulate.a < GameTuning.DECAL_FADE_MIN_ALPHA:
			queue_free()

func _on_time_til_fadeout_timeout() -> void:
	begin_fade_out = true
