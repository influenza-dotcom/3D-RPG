@tool
extends VBoxContainer

## Component-palette dock: a searchable, categorized list of every drop-in authoring component, with one-click
## "add to the selected node" (instance a prefab, or build the bare node + script). Kills the discoverability
## problem for the ~67-component catalog and makes the canonical components the path of least resistance.
##
## STUB: shows a placeholder. The catalog-driven Tree + search + undo-aware add land in the palette build step.


func _init() -> void:
	name = "Palette"
	var l := Label.new()
	l.text = "Component Palette — coming soon"
	l.add_theme_constant_override("margin_top", 8)
	add_child(l)
