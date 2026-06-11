class_name GameRoot
extends Node3D

## The root script for game.tscn — decouples "which level" from a hardcoded Level child so a second level is
## one LevelData assignment (review #4, the level-loading seam). Assign `level` and GameRoot instantiates its
## scene as the "Level" child at _ready; load_level() swaps it at runtime while the Player (and its Music /
## Ambience nodes) live on.
##
## SAFE TO ADOPT INCREMENTALLY: with no `level` assigned it's a NO-OP, so you can attach it to game.tscn's
## root before migrating the hardcoded Level child — nothing changes until a LevelData is set. And RESPAWN is
## preserved: death still calls reload_current_scene(), which reloads game.tscn and re-runs this _ready, so the
## level re-instantiates from `level` exactly as the hardcoded child used to re-instantiate on a reload.

@export var level: LevelData = null


func _ready() -> void:
	if level != null:
		load_level(level)


## Swap to `data`'s level scene: free any current "Level" child, instantiate the new one as "Level", and apply
## its optional music / ambience overrides to the Player's audio nodes. The Player itself is untouched, so a
## runtime swap (vs a full reload-current-scene respawn) keeps the player alive. No-op without a packed scene.
func load_level(data: LevelData) -> void:
	if data == null or data.scene == null:
		return
	level = data
	var existing := get_node_or_null(^"Level")
	if existing != null:
		existing.free()
	var inst := data.scene.instantiate()
	inst.name = &"Level"
	add_child(inst)
	_apply_audio(data)


## Apply a level's optional music / ambience to the Player's AudioStreamPlayer3D children, when present + set.
## Left as null on the LevelData -> the scene's own autoplay streams are kept.
func _apply_audio(data: LevelData) -> void:
	if data.music != null:
		var m := get_node_or_null(^"Player/Music") as AudioStreamPlayer3D
		if m != null:
			m.stream = data.music
			m.play()
	if data.ambience != null:
		var a := get_node_or_null(^"Player/Ambience") as AudioStreamPlayer3D
		if a != null:
			a.stream = data.ambience
			a.play()
