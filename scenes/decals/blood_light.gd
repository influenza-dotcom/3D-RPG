extends OmniLight3D

@export var time_to_destroy: float

func _ready() -> void:
	await get_tree().create_timer(time_to_destroy).timeout; queue_free()
