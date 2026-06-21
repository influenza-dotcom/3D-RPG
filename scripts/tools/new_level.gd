@tool
extends EditorScript

## NEW LEVEL generator. In the Godot editor: set NEW_LEVEL_NAME below, then File -> Run (Ctrl/Cmd+Shift+X).
## It clones LevelTemplate.tscn into scenes/levels/<Name>.tscn and writes a matching LevelData at
## resources/levels/<Name>.tres pointing at it. Afterwards: open the new scene, build geometry under `Geometry`,
## select the NavigationRegion3D and click `Bake NavigationMesh`, then point a LevelDoor (or GameRoot.level) at the
## new .tres. Mirrors the File -> Run idiom of scripts/tools/validate_content.gd — no EditorPlugin needed.

const NEW_LEVEL_NAME := "MyLevel"   ## <- set this (a file-safe name), then File -> Run
const DISPLAY_NAME := ""            ## <- optional; shown on LevelDoor prompts / level select. Blank = the name.

const TEMPLATE_SCENE := "res://scenes/levels/LevelTemplate.tscn"

func _run() -> void:
	var nm := NEW_LEVEL_NAME.strip_edges()
	if nm.is_empty() or nm == "MyLevel":
		push_warning("new_level: set NEW_LEVEL_NAME (not the placeholder 'MyLevel') at the top of the script, then File -> Run.")
		return
	var scene_path := "res://scenes/levels/%s.tscn" % nm
	var data_path := "res://resources/levels/%s.tres" % nm
	if FileAccess.file_exists(scene_path) or FileAccess.file_exists(data_path):
		push_error("new_level: '%s' already exists (scene or .tres) — pick another name." % nm)
		return

	var template := load(TEMPLATE_SCENE) as PackedScene
	if template == null:
		push_error("new_level: couldn't load the template at %s" % TEMPLATE_SCENE)
		return
	# Re-pack a fresh copy so the new .tscn gets its OWN uid (a raw file copy would clash with the template's uid).
	var inst := template.instantiate()
	var packed := PackedScene.new()
	var packed_err := packed.pack(inst)
	inst.free()
	if packed_err != OK:
		push_error("new_level: failed to pack the template copy (err %d)." % packed_err)
		return
	if ResourceSaver.save(packed, scene_path) != OK:
		push_error("new_level: failed to save %s" % scene_path)
		return

	var data := LevelData.new()
	data.scene = load(scene_path)
	data.display_name = DISPLAY_NAME.strip_edges() if not DISPLAY_NAME.strip_edges().is_empty() else nm
	if ResourceSaver.save(data, data_path) != OK:
		push_error("new_level: failed to save %s" % data_path)
		return

	EditorInterface.get_resource_filesystem().scan()  # so the new files show up in the FileSystem dock immediately
	print_rich("[color=lime]new_level:[/color] created [b]%s[/b] + [b]%s[/b]" % [scene_path, data_path])
	print("  Next: open the scene, build geometry under `Geometry`, select NavigationRegion3D -> Bake NavigationMesh,")
	print("  then point a LevelDoor (or GameRoot.level) at %s." % data_path)
