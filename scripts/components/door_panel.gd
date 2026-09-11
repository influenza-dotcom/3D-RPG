extends StaticBody3D

## The Door prefab's BLOCKER body (Door/DoorPivot/DoorBody): the StaticBody3D that physically fills the doorway
## while the panel is closed. This script is what lets a shot HURT the door. Both hit paths — the hitscan pellet
## trace (damage_trace.gd, via DamageApplier.apply) and a flying round (projectile.gd) — plus an ExplosionArea blast
## all call take_damage() on whatever BODY they hit, and that body is this node, not the Door (the Door root is an
## Area3D on the talk layer, which a world raycast never sees). So the panel forwards every hit up to its owning
## Door (Door.of_collider walks the parent chain), where the HP, the break, the break noise and the HUD push live.
##
## No class_name on purpose: nothing references this type by name (the prefab binds it by path and the Door resolves
## itself through of_collider), and a new global class would sit unregistered in the class cache until the editor
## rescans. Deliberately NOT a CanDestroy: that frees ITSELF at 0 HP, while a door's break must run through the Door
## (persist the "destroyed" bit, clear the interaction prompt, pulse the noise).

## Forward a landed hit to the owning Door. Signature mirrors CanDestroy / Character.take_damage so the same dynamic
## 3-arg (DamageApplier / ExplosionArea) and 4-arg calls land unchanged. A panel with no Door above it (a designer
## dropped the body somewhere loose) swallows the hit: nothing to damage.
func take_damage(amount: float, was_crit: bool = false, attacker: Node = null, hit_pos: Vector3 = Vector3.INF) -> void:
	var door := Door.of_collider(self)
	if door != null:
		door.take_damage(amount, was_crit, attacker, hit_pos)

## The MELEE gate the hitscan trace consults (DamageApplier.blocks_melee -> damage_trace.run_pellet) BEFORE it
## applies a melee swing's damage: true = a blade / fist / bat just thuds off this panel. Reads the owning Door's
## `melee_can_damage` knob, so a designer flips it per door; a panel with no Door never blocks (it can't be hurt anyway).
func blocks_melee_damage() -> bool:
	var door := Door.of_collider(self)
	return door != null and not door.melee_can_damage
