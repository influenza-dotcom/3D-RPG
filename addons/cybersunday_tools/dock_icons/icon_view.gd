@tool
extends VBoxContainer

## CYBER SUNDAY → Icons: bake clean, consistent inventory icons for EVERY item. An item with a model (a weapon's
## view_model, a world_model, or a world_prop scene) renders that; an item with none renders a procedural
## primitive stand-in (icon_models.gd — cartridges for ammo, a medkit, keyword trinkets) so no tile is ever a
## letter glyph. Each bake is a transparent, AUTOCROPPED PNG sized to the item's GRID FOOTPRINT (grid_w × grid_h
## cells), written to res://resources/icons/<item.id>.png; the grid tile loads it by id automatically
## (grid_tile.gd). The same bake also runs from the CLI:
## godot --path <project> -s scripts/tools/bake_item_icons.gd (windowed — it needs a renderer).
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
	b.tooltip_text = "Render EVERY item to res://resources/icons/<id>.png (its model, else a primitive stand-in), autocropped + sized to its grid footprint. The grid uses them automatically."
	b.pressed.connect(_on_bake_all)
	add_child(b)

	_out = RichTextLabel.new()
	_out.bbcode_enabled = true
	_out.selection_enabled = true
	_out.custom_minimum_size = Vector2(0, 90)
	add_child(_out)
	_out.text = "[i]Bakes a footprint-sized PNG per item into resources/icons/ (its model, else a primitive stand-in). Writes PNGs only — never touches your item .tres. Re-run any time.[/i]"


func _on_bake_all() -> void:
	if DisplayServer.get_name() == "headless":
		_warn("No renderer (headless) — open this in the editor to bake.")
		return
	var items := _bakeable_items()
	if items.is_empty():
		_set_out("No items found under %s." % ITEMS_DIR)
		return
	var baked := 0
	var failed: Array = []
	for item in items:
		var px := Render.pixel_size(item.grid_width, item.grid_height, Baker.CELL)
		var img = await _baker.bake_item(item, px, self)  # async: authored model, else a primitive stand-in
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


## Every Item .tres under resources/items/ — ALL of them bake now: an authored model (weapon view_model /
## world_model / world_prop scene, scripts stripped) when present, else a procedural primitive stand-in
## (icon_models.gd). Loads + type-checks like the loot/content scans (the ItemDb autoload is empty in-editor).
func _bakeable_items() -> Array:
	var out: Array = []
	var d := DirAccess.open(ITEMS_DIR)
	if d == null:
		return out
	for f in d.get_files():
		var fn := f.trim_suffix(".remap")
		if fn.get_extension() != "tres":
			continue
		var res = load(ITEMS_DIR + fn)
		if res is Item:
			out.append(res)
	return out


func _set_out(bb: String) -> void:
	if _out != null:
		_out.text = bb


func _warn(msg: String) -> void:
	_set_out("[color=#ffd24d]" + msg + "[/color]")
