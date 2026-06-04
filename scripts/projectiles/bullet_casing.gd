extends RigidBody3D

## A spent shell casing — a bare physics body that bounces/rolls after ejection. The in-game eject is
## normally the ShellDrop particle burst (see Attack.shell_particle); this RigidBody scene is the
## physical-casing variant, kept tunable so a spawner can size it per-weapon.

## Uniformly resize this casing — its visible mesh AND its collision shape — by `factor`. Driven by
## WeaponData.casing_size_scale so a heavier round (e.g. the sniper) drops a bigger shell. 1.0 leaves it
## at the authored size. Self-guards on the known child nodes so it's a no-op if the scene is restructured.
func scale_casing(factor: float) -> void:
	var mesh := get_node_or_null(^"MeshInstance3D")
	if mesh:
		(mesh as Node3D).scale = Vector3.ONE * factor
	var collision := get_node_or_null(^"CollisionShape3D")
	if collision:
		(collision as Node3D).scale = Vector3.ONE * factor
