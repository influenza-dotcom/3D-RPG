class_name MinimapHide
extends Node

## A drop-in "not a wall" tag: child it under any prop whose colliders must NOT be drawn as walls on the HUD
## minimap's floorplan — a chain-link fence, a market awning, a parked car, a decorative pipe run, a railing.
## FloorplanSource.gather skips the whole subtree it marks, so the plan keeps showing the ROOM instead of the
## clutter standing in it.
##
## IT JOINS ITS PARENT, NOT ITSELF (the reason it is a plain Node rather than a Node3D). The floorplan gather
## walks the level and skips any subtree whose root is in the group, so the tag has to land on the node whose
## children carry the colliders — child this under the prop and the prop is what gets marked. A component
## that added ITSELF would mark only itself, which owns no colliders, and would silently do nothing.
##
## SETUP: select the prop, add a child node, set its script to this one. No exports to fill in, no wiring.
## Costs no physics-layer budget and changes no collision — the prop still blocks bullets, footsteps and
## navigation exactly as before; it is invisible to everything except the minimap's wall cut.
##
## Not @tool: a plain Node never runs _ready in the editor, and the group only needs to exist at runtime.

## Off = the prop IS drawn as a wall again, without deleting the node. Read once, in _ready — flipping it at
## runtime does nothing, because the level's solids are gathered once per level (that gather is the whole
## reason the map costs nothing per frame). To re-tag mid-session, call rebake() on the Minimap.
@export var enabled: bool = true


func _ready() -> void:
	if not enabled:
		return
	var host := get_parent()
	if host == null:
		# Parentless: nothing to mark. Warn rather than fail silently — a tag that marks nothing looks
		# identical in the inspector to one that works.
		push_warning("MinimapHide has no parent to mark; child it under the prop you want hidden from the minimap.")
		return
	host.add_to_group(Groups.MINIMAP_HIDE)
