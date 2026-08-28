class_name WorldMarker
extends Node3D

## A drop-in point-of-interest beacon: drop it in the world and it shows on both compass surfaces AND as a dot
## on the Minimap — it joins the "compass" and "minimap" groups on _ready so every HUD channel picks it up with
## no wiring. A QuestMarkerSync spawns these for active quest objectives; place them by hand for
## fixed landmarks (a vendor, an exit, a stash). (Not @tool: a plain Node3D never runs _ready in the editor.)

## Show on BOTH compass surfaces — they share the "compass" group, on purpose: the screen-edge Compass
## component answers "where on screen is it" and the top-centre HudCompass tape answers "what bearing is it
## on", and a second registry would let the two disagree about one marker.
@export var on_compass: bool = true
## Show on the minimap.
@export var on_minimap: bool = true
## Marker tint — the Compass chevron and the HudCompass tape pip both use it (the Minimap draws its own
## marker texture).
@export var color: Color = Color(1.0, 0.85, 0.3)

func _ready() -> void:
	if on_compass:
		add_to_group(Groups.COMPASS)
	if on_minimap:
		add_to_group(Groups.MINIMAP)
