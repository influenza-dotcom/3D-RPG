extends CollisionShape3D

@onready var collision_shape_3d: CollisionShape3D = $"../../CollisionShape3D"

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	(shape as SphereShape3D).radius = (collision_shape_3d.shape as SphereShape3D).radius
