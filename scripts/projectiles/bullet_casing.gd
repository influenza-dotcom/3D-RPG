extends RigidBody3D

## A spent shell casing — a bare physics body that bounces/rolls after ejection. The in-game eject is
## normally the ShellDrop particle burst (see Attack.shell_particle); this RigidBody scene is the
## physical-casing variant.
##
## ⭐ OUTLINE (2026-08-27): the casing wears InkOutline's screen-space ring at the prop id, plus the
## actor-mask bit that keeps the world's ink off it — the two halves of the one contract every outlined
## thing in this project obeys. Before that it carried an authored `outline_black.tres` inverted-hull
## overlay in bullet_casing.tscn and NO mask bit, so a casing quietly wore TWO lines at once (its own
## shell plus the world's edge detect) for as long as it was on screen. Stamped here rather than authored
## in the scene because the ring is a runtime node, not a material.


func _ready() -> void:
	for m in TalkHelpers.collect_meshes(self, null, true):
		m.layers |= InkOutline.ACTOR_INK_MASK_LAYER
		InkOutline.apply_tint_mesh(m, InkOutline.TINT_ID_PROP_REST)
