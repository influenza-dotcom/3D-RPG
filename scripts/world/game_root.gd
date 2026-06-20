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

## The level to load on start: GameRoot instantiates its scene as the "Level" child (and applies its music /
## ambience). Leave unset for a no-op so the existing hardcoded Level child is used unchanged.
@export var level: LevelData = null


func _ready() -> void:
	add_to_group(&"game_root")  # so a LevelDoor / trigger can find us without a hardcoded path
	if level != null:
		load_level(level)


## Swap to `data`'s level scene: free any current "Level" child, instantiate the new one as "Level", and apply
## its optional music / ambience overrides to the Player's audio nodes. The Player itself is untouched, so a
## runtime swap (vs a full reload-current-scene respawn) keeps the player alive. No-op without a packed scene.
func load_level(data: LevelData, entry_id: StringName = &"") -> void:
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
	_place_player_at_entry.call_deferred(entry_id)  # after the new level's PlayerSpawns have entered the tree


## No-arg load of the ASSIGNED `level` — so a TriggerVolume (action = "load_assigned_level") or a cutscene can
## change level with no argument. Set `level` (a LevelData) and point the trigger at us.
func load_assigned_level() -> void:
	load_level(level)


## Teleport the Player (the "Player" child) to the PlayerSpawn matching `entry_id` (or the first, if blank) in the
## freshly-loaded level, and RE-SEED the respawn point there so a later death returns to the new level, not the
## freed old one. No-op without a Player or a matching spawn (the player keeps its authored transform).
func _place_player_at_entry(entry_id: StringName) -> void:
	var player := get_node_or_null(^"Player") as Node3D
	if player == null:
		return
	var spawn := _find_spawn(entry_id)
	if spawn == null:
		return
	spawn.place(player)
	GameState.set_respawn(spawn.global_position, spawn.global_rotation.y)


## The PlayerSpawn whose entry_id matches (or the first one when `entry_id` is blank). Null if the level has none.
func _find_spawn(entry_id: StringName) -> PlayerSpawn:
	for s in get_tree().get_nodes_in_group(&"player_spawn"):
		var ps := s as PlayerSpawn
		if ps != null and (entry_id == &"" or ps.entry_id == entry_id):
			return ps
	return null


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
