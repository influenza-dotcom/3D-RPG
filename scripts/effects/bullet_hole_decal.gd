extends Decal


# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	pass # Replace with function body.

var begin_fade_out: bool = false

const FADE_RATE: float = 0.9  # alpha per second multiplier

func _process(delta: float) -> void:
	if begin_fade_out:
		modulate.a = lerpf(modulate.a, 0.0, 1.0 - exp(-FADE_RATE * delta))
		if modulate.a < 0.01:
			queue_free()


func _on_time_til_fadeout_timeout() -> void:
	begin_fade_out = true
