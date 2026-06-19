extends Control

## The TOP layer of GridInventoryView. The item tiles are child nodes (so they draw ON TOP of the view's own
## _draw), which means the drag preview + hover ring have to be painted ABOVE them — so they live on this child,
## kept as the last child of the view. Mouse-transparent; it just delegates its _draw back to the grid view.

var host: GridInventoryView = null

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func _draw() -> void:
	if host != null:
		host.draw_overlay(self)
