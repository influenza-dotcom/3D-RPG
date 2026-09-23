@tool
extends EditorScript

## NEW WORLDSPACE generator — a streamed, Fallout-style open world. In the Godot editor: set the consts below, then
## File -> Run (Ctrl/Cmd+Shift+X). It writes:
##   scenes/worlds/<Name>/<Name>.tscn           the PERSISTENT layer: LevelTemplate's sky, sun, dust, quest markers and
##                                              PlayerSpawn, plus a ChunkStreamer pointed at the chunks folder
##   scenes/worlds/<Name>/chunks/chunk_X_Z.tscn  one WorldChunk per cell: a ground tile + a navmesh already baked and
##                                              fitted to the cell, so NPCs path across chunk borders
##   resources/levels/<Name>.tres               the LevelData — `warp <Name>` in the debug console, or a LevelDoor
## Then open any chunk and build that cell's content (re-bake with the WorldChunk's `bake_and_audit`), and put
## anything that must exist everywhere — doors' arrival spawns, the sky — in the persistent scene.
## The building happens in scripts/world/worldspace_builder.gd (unit-tested); this file is only the File -> Run shell.

const WORLD_NAME := "MyWorld"            ## <- set this (a file-safe name), then File -> Run
const DISPLAY_NAME := ""                 ## <- optional; shown on LevelDoor prompts. Blank = the name.
const GRID_MIN := Vector2i(-1, -1)       ## lowest cell (x, z) to create
const GRID_MAX := Vector2i(1, 1)         ## highest cell (x, z) to create — the default is a 3x3 world
const CHUNK_SIZE := 64.0                 ## cell width in metres
const SPAWN_CELL := Vector2i(0, 0)       ## where the PlayerSpawn goes
const LANDMARKS := 3                     ## blockout pillars per chunk so you can see the world stream (0 = bare ground)

const Builder = preload("res://scripts/world/worldspace_builder.gd")


func _run() -> void:
	var nm := WORLD_NAME.strip_edges()
	if nm.is_empty() or nm == "MyWorld":
		push_warning("new_worldspace: set WORLD_NAME (not the placeholder 'MyWorld') at the top of the script, then File -> Run.")
		return
	var folder := "res://scenes/worlds/%s" % nm
	var chunk_folder := folder.path_join("chunks")
	var scene_path := folder.path_join("%s.tscn" % nm)
	var data_path := "res://resources/levels/%s.tres" % nm
	if DirAccess.dir_exists_absolute(folder) or FileAccess.file_exists(data_path):
		push_error("new_worldspace: '%s' already exists (folder or .tres) — pick another name." % nm)
		return
	DirAccess.make_dir_recursive_absolute(chunk_folder)

	# Chunks are baked while parked under a throwaway node in the editor tree (static-body parsing needs global
	# transforms); the builder parses each chunk's OWN subtree, so the open scene's geometry never leaks in.
	var holder := Node3D.new()
	EditorInterface.get_base_control().add_child(holder)
	var made := 0
	for x in range(GRID_MIN.x, GRID_MAX.x + 1):
		for z in range(GRID_MIN.y, GRID_MAX.y + 1):
			var cell := Vector2i(x, z)
			var chunk := Builder.build_chunk(cell, CHUNK_SIZE, 2.0, Builder.tint_for(cell))
			Builder.add_landmarks(chunk, LANDMARKS)
			holder.add_child(chunk)
			var polys := Builder.bake_chunk(chunk)
			holder.remove_child(chunk)
			var packed := PackedScene.new()
			if packed.pack(chunk) != OK or ResourceSaver.save(packed, chunk_folder.path_join("chunk_%d_%d.tscn" % [x, z])) != OK:
				push_error("new_worldspace: failed to save chunk %s" % cell)
			else:
				made += 1
				if polys == 0:
					push_warning("new_worldspace: chunk %s baked no navmesh polygons" % cell)
			chunk.free()
	holder.queue_free()

	var world := Builder.build_persistent(chunk_folder, CHUNK_SIZE, SPAWN_CELL)
	if world == null:
		push_error("new_worldspace: couldn't load %s" % Builder.TEMPLATE_SCENE)
		return
	world.name = nm
	var packed_world := PackedScene.new()
	var err := packed_world.pack(world)
	world.free()
	if err != OK or ResourceSaver.save(packed_world, scene_path) != OK:
		push_error("new_worldspace: failed to save %s" % scene_path)
		return

	var data := LevelData.new()
	data.scene = load(scene_path)
	data.display_name = DISPLAY_NAME.strip_edges() if not DISPLAY_NAME.strip_edges().is_empty() else nm
	if ResourceSaver.save(data, data_path) != OK:
		push_error("new_worldspace: failed to save %s" % data_path)
		return

	EditorInterface.get_resource_filesystem().scan()
	print_rich("[color=lime]new_worldspace:[/color] created [b]%s[/b] with %d chunk(s) + [b]%s[/b]" % [scene_path, made, data_path])
	print("  Try it: run the game, open the debug console, `warp %s`." % nm)
	print("  Build a cell: open scenes/worlds/%s/chunks/chunk_X_Z.tscn, add content, tick the root's `bake_and_audit`." % nm)
