@tool
extends VBoxContainer

## World item-placer dock: pick any Item from the database and drop a ready CanPickUp for it into the level at
## the viewport cursor (build_model_from_item auto-fits the visual + collider) -- the "find a stimpak in the
## world like Fallout" workflow, no manual node wiring.
##
## STUB: shows a placeholder. The Item list + raycast drop + undo land in the item-placer build step.


func _init() -> void:
	name = "Items"
	var l := Label.new()
	l.text = "Item Placer — coming soon"
	add_child(l)
