extends Decal


# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	pass # Replace with function body.

var begin_fade_out: bool = false

const APPROACH_ZERO_RATE: float = .015

# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	if begin_fade_out:
		modulate.a = lerpf(modulate.a, 0.0, APPROACH_ZERO_RATE)
	if is_zero_approx(modulate.a):
		queue_free()


func _on_time_til_fadeout_timeout() -> void:
	begin_fade_out = true
