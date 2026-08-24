@tool
extends VBoxContainer

## Level-tools dock: one-click Audit Navmesh / Bake + Audit / Validate Level / Validate Content / New Level, with
## results in a panel. It REUSES the existing tooling rather than duplicating it -- NavMeshAudit.analyze, the
## LevelRoot validator (via the node's get_configuration_warnings), ContentValidator.run, and the new_level flow.
## Everything targets EditorInterface.get_edited_scene_root(); the region/LevelRoot are found by an explicit walk
## (SceneWalk), never get_tree() group queries (which at edit time span the whole open editor scene).

const SceneWalk := preload("res://addons/cybersunday_tools/core/scene_walk.gd")
## The shared name-normalisation seam every other generator routes designer-typed names through (id == filename).
const Scaffold := preload("res://addons/cybersunday_tools/dock_content/content_scaffold.gd")
const TEMPLATE_SCENE := "res://scenes/levels/LevelTemplate.tscn"

var _out: RichTextLabel = null
var _name_edit: LineEdit = null


func _init() -> void:
	name = "Level"
	add_theme_constant_override("separation", 4)

	var title := Label.new()
	title.text = "Level Tools"
	add_child(title)

	_add_button("Audit Navmesh", _on_audit)
	_add_button("Bake + Audit", _on_bake_audit)
	_add_button("Validate Level", _on_validate_level)
	_add_button("Validate Content", _on_validate_content)

	add_child(HSeparator.new())
	var row := HBoxContainer.new()
	_name_edit = LineEdit.new()
	_name_edit.placeholder_text = "NewLevelName"
	_name_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(_name_edit)
	var make := Button.new()
	make.text = "New Level"
	make.pressed.connect(_on_new_level)
	row.add_child(make)
	add_child(row)

	_out = RichTextLabel.new()
	_out.bbcode_enabled = true
	_out.scroll_active = true
	_out.selection_enabled = true
	_out.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_out.custom_minimum_size = Vector2(0, 90)  # small floor so the dock can shrink on a short display
	_out.text = "[i]Open a level scene, then run a check.[/i]"
	add_child(_out)


func _add_button(text: String, handler: Callable) -> void:
	var b := Button.new()
	b.text = text
	b.pressed.connect(handler)
	add_child(b)


# --- targets ---------------------------------------------------------------------------------------------------

func _edited_root() -> Node:
	return EditorInterface.get_edited_scene_root()

func _region() -> NavigationRegion3D:
	var root := _edited_root()
	if root == null:
		return null
	for n in SceneWalk.collect_all(root):
		if n is NavigationRegion3D:
			return n as NavigationRegion3D
	return null

func _level_root() -> Node:
	var root := _edited_root()
	if root == null:
		return null
	for n in SceneWalk.collect_all(root):
		if n is LevelRoot:
			return n
	return null


# --- actions ---------------------------------------------------------------------------------------------------

func _on_audit() -> void:
	var region := _region()
	if region == null:
		_warn("No NavigationRegion3D in the edited scene. Open a level (or add a region) first.")
		return
	_render_audit(NavMeshAudit.analyze(region.navigation_mesh))

func _on_bake_audit() -> void:
	var region := _region()
	if region == null:
		_warn("No NavigationRegion3D in the edited scene.")
		return
	if region.navigation_mesh == null:
		_warn("The NavigationRegion3D has no NavigationMesh resource — add one, then bake.")
		return
	if region.has_method("bake_navigation_mesh"):
		region.bake_navigation_mesh(false)  # on_thread = false: synchronous, so the audit sees the fresh mesh
	_render_audit(NavMeshAudit.analyze(region.navigation_mesh))

func _render_audit(rep: Dictionary) -> void:
	var settings: Dictionary = rep.get("settings", {})
	var ok: bool = rep.get("ok", false)
	var islands: Array = rep.get("islands", [])
	var elevated: Array = rep.get("elevated", [])
	var lines := PackedStringArray()
	lines.append("%s — %d polys, %d island(s), %d elevated, climb %.2f" % [
		"[color=lime]CLEAN[/color]" if ok else "[color=#ffd24d]ISSUES[/color]",
		int(rep.get("poly_count", 0)), islands.size(), elevated.size(),
		float(settings.get("agent_max_climb", 0.0))])
	for w in rep.get("warnings", []):
		lines.append("  • " + str(w))
	_set_out("\n".join(lines))

func _on_validate_content() -> void:
	var problems = ContentValidator.run()
	if problems.is_empty():
		_set_out("[color=lime]Content: PASS[/color] — no problems found.")
		return
	var lines := PackedStringArray(["[color=#ffd24d]Content: %d problem(s)[/color]" % problems.size()])
	for p in problems:
		lines.append("  • " + str(p))
	_set_out("\n".join(lines))

func _on_validate_level() -> void:
	var lr := _level_root()
	if lr == null:
		_warn("No LevelRoot in this scene. Attach scripts/world/level_root.gd to the level root for full validation (or use the Audit panel).")
		return
	var w := SceneWalk.config_warnings(lr)
	if w.is_empty():
		_set_out("[color=lime]Level: PASS[/color] — LevelRoot reports no problems.")
		return
	var lines := PackedStringArray(["[color=#ffd24d]Level: %d issue(s)[/color]" % w.size()])
	for s in w:
		lines.append("  • " + str(s))
	_set_out("\n".join(lines))

func _on_new_level() -> void:
	var raw := _name_edit.text.strip_edges()
	if raw.is_empty():
		_warn("Type a level name first.")
		return
	# SLUGIFY like every other generator: the raw text goes straight into a res:// path, so a "/" would silently write
	# into another folder and a ":"/"?" would fail the save with only a generic message. The typed text is kept as the
	# LevelData display_name, so "Raider Camp" -> raider_camp.tscn / raider_camp.tres shown as "Raider Camp".
	var nm := Scaffold.slugify(raw)
	if nm.is_empty():
		_warn("'%s' has no usable letters or digits — pick a name like \"raider_camp\"." % raw)
		return
	_set_out(_make_level(nm, raw))

## Port of new_level.gd: clone LevelTemplate.tscn into scenes/levels/<name>.tscn (re-packed for a fresh uid) and
## write a matching LevelData at resources/levels/<name>.tres. Returns a bbcode result line. Refuses to overwrite.
func _make_level(nm: String, display: String) -> String:
	var scene_path := "res://scenes/levels/%s.tscn" % nm
	var data_path := "res://resources/levels/%s.tres" % nm
	if FileAccess.file_exists(scene_path) or FileAccess.file_exists(data_path):
		return "[color=#ffd24d]'%s' already exists[/color] (scene or .tres) — pick another name." % nm
	var template := load(TEMPLATE_SCENE) as PackedScene
	if template == null:
		return "[color=#ff6b6b]Couldn't load the template[/color] at %s" % TEMPLATE_SCENE
	var inst := template.instantiate()
	var packed := PackedScene.new()
	var err := packed.pack(inst)
	inst.free()
	if err != OK:
		return "[color=#ff6b6b]Failed to pack the template copy[/color] (err %d)." % err
	if ResourceSaver.save(packed, scene_path) != OK:
		return "[color=#ff6b6b]Failed to save %s[/color]" % scene_path
	var data := LevelData.new()
	data.scene = load(scene_path)
	data.display_name = display.strip_edges() if not display.strip_edges().is_empty() else nm
	if ResourceSaver.save(data, data_path) != OK:
		return "[color=#ff6b6b]Failed to save %s[/color]" % data_path
	EditorInterface.get_resource_filesystem().scan()  # so the new files show up in the FileSystem dock immediately
	return "[color=lime]Created[/color] %s + %s\nOpen it, build geometry under Geometry, Bake the NavigationRegion3D, then point a LevelDoor / GameRoot.level at the .tres." % [scene_path, data_path]


# --- output ----------------------------------------------------------------------------------------------------

func _set_out(bb: String) -> void:
	if _out != null:
		_out.text = bb

func _warn(msg: String) -> void:
	_set_out("[color=#ffd24d]" + msg + "[/color]")
