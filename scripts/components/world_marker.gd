class_name WorldMarker
extends Node3D

## A drop-in point-of-interest beacon: drop it in the world and it shows as a chevron on the Compass (screen
## edge) and a dot on the Minimap — it joins the "compass" and "minimap" groups on _ready so both HUD channels
## pick it up with no wiring. A QuestMarkerSync spawns these for active quest objectives; place them by hand for
## fixed landmarks (a vendor, an exit, a stash). (Not @tool: a plain Node3D never runs _ready in the editor.)

## Show on the screen-edge compass.
@export var on_compass: bool = true
## Show on the minimap.
@export var on_minimap: bool = true
## Marker tint — the Compass chevron uses it (the Minimap draws its own marker texture).
@export var color: Color = Color(1.0, 0.85, 0.3)

func _ready() -> void:
	if on_compass:
		add_to_group(Groups.COMPASS)
	if on_minimap:
		add_to_group(Groups.MINIMAP)
