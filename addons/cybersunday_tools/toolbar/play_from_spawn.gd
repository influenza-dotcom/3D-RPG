@tool
extends HBoxContainer

## Play-from-spawn toolbar: launch the game from the editor. "Play" runs the main scene (game.tscn). "Spawn" writes
## the SELECTED PlayerSpawn's entry_id to GameRoot.DEV_START_FILE (GameRoot consumes it once on start) and runs the
## main scene -- so you start the player at that spawn instead of the level's default arrival, for fast iteration
## on a specific area. Select a PlayerSpawn in the level first.


func _init() -> void:
	name = "PlayFromSpawn"
	var play := Button.new()
	play.text = "▶ Play"
	play.tooltip_text = "Play the main scene (game.tscn)"
	play.pressed.connect(func() -> void: EditorInterface.play_main_scene())
	add_child(play)

	var spawn := Button.new()
	spawn.text = "▶ Spawn"
	spawn.tooltip_text = "Play, starting the player at the SELECTED PlayerSpawn (select one in the level first)"
	spawn.pressed.connect(_play_from_spawn)
	add_child(spawn)


func _play_from_spawn() -> void:
	var spawn := _selected_spawn()
	if spawn == null:
		push_warning("Play From Spawn: select a PlayerSpawn node in the level first.")
		return
	var f := FileAccess.open(GameRoot.DEV_START_FILE, FileAccess.WRITE)
	if f != null:
		f.store_string(String(spawn.entry_id))
		f = null
	EditorInterface.play_main_scene()


func _selected_spawn() -> PlayerSpawn:
	for n in EditorInterface.get_selection().get_selected_nodes():
		if n is PlayerSpawn:
			return n as PlayerSpawn
	return null
