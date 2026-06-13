extends OmniLight3D

## Short-lived glow on a fresh blood splat (the "wet" highlight). Self-frees after
## time_to_destroy. Spawners that place many decals at once delete this child first
## (see blood_drop / bloody_mess) so dozens of lights don't stack.

## Seconds the wet-blood glow lingers before it self-frees. Higher = the fresh-splat highlight stays lit longer; keep it short so many splats don't pile up lights.
@export var time_to_destroy: float

func _ready() -> void:
	await get_tree().create_timer(time_to_destroy).timeout; queue_free()
