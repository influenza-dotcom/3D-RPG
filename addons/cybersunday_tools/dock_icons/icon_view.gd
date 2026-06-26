@tool
extends VBoxContainer

## CYBER SUNDAY → Icons: bake clean, consistent inventory icons from item meshes — a fix for the live in-tile mesh
## render reading small / mis-framed. For every Item with a mesh it renders a transparent PNG sized to the item's
## GRID FOOTPRINT (grid_w × grid_h cells) and writes it to res://resources/icons/<item.id>.png. The grid tile then
## loads that icon by id automatically (grid_tile.gd), falling back to the live mesh when no baked icon exists.
##
## CONVENTION over Item.icon ON PURPOSE: writing a PNG + letting the grid load it by id at RUNTIME avoids the
## edit-time "load a just-written, not-yet-imported PNG" race AND never mutates your item .tres files (so a re-bake
## can't clobber a concurrently-edited resource). It ONLY writes PNGs into resources/icons/. Re-runnable any time.
## EDITOR-ONLY: the render needs a real renderer, so this no-ops under headless.

const ItemMeshView := preload("res://scripts/ui/item_mesh_view.gd")
const Baker := preload("res://addons/cybersunday_tools/dock_icons/icon_baker.gd")
const Render := preload("res://addons/cybersunday_tools/dock_icons/icon_render.gd")

const ITEMS_DIR := "res://resources/items/"
const ICONS_DIR := "res://resources/icons/"
const CELL := 96  # icon pixels per grid cell (matches the live tile viewport); a 2×1 item -> a 192×96 icon

var _out: RichTextLabel = null
var _baker := Baker.new()


func _init() -> void:
	name = "Icons"
	add_theme_constant_override("separation", 4)

	var title := Label.new()
	title.text = "Inventory icon baker"
	add_child(title)

	var b := Button.new()
	b.text = "Bake all item icons"
	b.tooltip_text = "Render every item-with-a-mesh to res://resources/icons/<id>.png, sized to its grid footprint. The grid uses them automatically."
	b.pressed.connect(_on_bake_all)
	add_child(b)

	_out = RichTextLabel.new()
	_out.bbcode_enabled = true
	_out.selection_enabled = true
	_out.custom_minimum_size = Vector2(0, 90)
	add_child(_out)
	_out.text = "[i]Bakes a footprint-sized PNG per item mesh into resources/icons/. Writes PNGs only — never touches your item .tres. Re-run any time.[/i]"


func _on_bake_all() -> void:
	if DisplayServer.get_name() == "headless":
		_warn("No renderer (headless) — open this in the editor to bake.")
		return
	var items := _items_with_meshes()
	if items.is_empty():
		_set_out("No items with a mesh found under %s." % ITEMS_DIR)
		return
	var baked := 0
	var failed: Array = []
	for item in items:
		var mesh: PackedScene = ItemMeshView.mesh_scene_for(item)
		var px := Render.pixel_size(item.grid_width, item.grid_height, CELL)
		var img = await _baker.bake(mesh, px, self)  # async: awaits the one-shot render
		if img == null:
			failed.append(String(item.id))
			continue
		if Baker.save_png(img, ICONS_DIR + String(item.id) + ".png") == OK:
			baked += 1
		else:
			failed.append(String(item.id))
	EditorInterface.get_resource_filesystem().scan()  # import the new PNGs so the grid can load them
	var msg := "[color=lime]Baked %d icon(s)[/color] -> %s (footprint-sized). The grid loads them by item id." % [baked, ICONS_DIR]
	# GOTCHA: a game already running picked up its import table at launch and won't see PNGs imported after — so a
	# fresh bake looks like "nothing changed" until you relaunch. Spell that out; it's the #1 confusion with this tab.
	msg += "\n[color=#9fd0ff]Already running the game? Stop + relaunch (F5) to see new icons[/color] — a live instance keeps its startup import table."
	if not failed.is_empty():
		msg += "\n[color=#ffd24d]%d skipped:[/color] %s" % [failed.size(), ", ".join(failed)]
	_set_out(msg)


## Every Item .tres under resources/items/ that has a mesh to render (a weapon view_model or a world_model). Loads
## + type-checks like the loot/content scans (the ItemDb autoload is empty in-editor).
func _items_with_meshes() -> Array:
	var out: Array = []
	var d := DirAccess.open(ITEMS_DIR)
	if d == null:
		return out
	for f in d.get_files():
		var fn := f.trim_suffix(".remap")
		if fn.get_extension() != "tres":
			continue
		var res = load(ITEMS_DIR + fn)
		if res is Item and ItemMeshView.has_mesh(res):
			out.append(res)
	return out


func _set_out(bb: String) -> void:
	if _out != null:
		_out.text = bb


func _warn(msg: String) -> void:
	_set_out("[color=#ffd24d]" + msg + "[/color]")
