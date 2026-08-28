class_name SeeThrough
extends Node

## A drop-in "sight and gunfire pass through me" tag: child it under any prop that must NOT hide — or shield —
## what is behind it: a chain-link fence, a wire-mesh gate, a railing, a shop window, a grille. It joins
## `Groups.SEE_THROUGH`, which three systems read: `SightRay` (the caster behind every NPC sight/hearing ray)
## keeps casting past the marked body to whatever is actually blocking the view, `DamageTrace` carries a hitscan
## pellet through it, and `Projectile` excepts it so live rounds fly through.
##
## THE PROP IS STILL SOLID to everything else — you cannot walk through it, thrown props bounce off it, the
## navmesh still carves around it, and the player's look-at ray still stops on it (no looting through the wire).
## Nothing about its collision layer or mask changes; the three systems above opt out by name.
##
## IT JOINS ITS PARENT, NOT ITSELF (the reason it is a plain `Node` rather than a `Node3D`) — the same idiom as
## `MinimapHide`. Rays and rounds resolve to the COLLIDER, so the tag has to reach the collision bodies: this
## marks the parent AND every `CollisionObject3D` in its subtree, so a multi-part fence prop needs one component
## rather than one per panel.
##
## SETUP: select the prop, add a child node, set its script to this one. No exports to fill in, no wiring.
##
## NOT for func_godot brush geometry: a whole TrenchBroom map is ONE StaticBody3D, so tagging it would make the
## entire level see-through. Use `SeeThroughBrushes` for that — it splits the fence brushes into their own body
## first, precisely so they CAN be tagged this way.
##
## Not @tool: a plain Node never runs _ready in the editor, and the group only needs to exist at runtime.

## Off = the prop blocks sight and gunfire again, without deleting the node. Read once, in _ready — flipping it
## at runtime does nothing, because the group membership is stamped at level load.
@export var enabled: bool = true


func _ready() -> void:
	if not enabled:
		return
	var host := get_parent()
	if host == null:
		# Parentless: nothing to mark. Warn rather than fail silently — a tag that marks nothing looks
		# identical in the inspector to one that works.
		push_warning("SeeThrough has no parent to mark; child it under the prop NPCs should see and shoot through.")
		return
	host.add_to_group(Groups.SEE_THROUGH)
	# Mark the bodies too. `host` is usually the prop root with a StaticBody3D/Area3D under it, and it is the
	# COLLIDER a ray reports and a round collides with — marking only the root would tag a node nothing ever hits.
	for body in _bodies(host):
		body.add_to_group(Groups.SEE_THROUGH)


## Every CollisionObject3D at or under `root`. Nested prop scenes are included: `owned` filtering would drop the
## bodies inside an instanced panel, which is exactly the multi-part case this walk exists for.
static func _bodies(root: Node) -> Array[CollisionObject3D]:
	var found: Array[CollisionObject3D] = []
	if root is CollisionObject3D:
		found.append(root as CollisionObject3D)
	for child in root.get_children():
		found.append_array(_bodies(child))
	return found
