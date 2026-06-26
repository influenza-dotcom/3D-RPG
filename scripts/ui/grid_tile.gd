extends Control

## One styled inventory TILE (a single stack) for GridInventoryView. Mouse-TRANSPARENT — the grid view owns all
## input; this is pure visual. It draws a category-tinted panel + border (gold when equipped), the item's LIVE 3D
## mesh (an ItemMeshView child) or a clean category glyph when the item has no mesh, and a stack-count badge. The
## grid reuses tiles across refreshes (keyed by stack), so a drag/move repositions the same tile instead of
## re-instantiating its mesh.

const ItemMeshView := preload("res://scripts/ui/item_mesh_view.gd")
const MESH_INSET := 3.0
## Where the CYBER SUNDAY Icons baker writes per-item icons (res://resources/icons/<item.id>.png). When one exists
## the tile draws it instead of the live mesh — cleaner + consistently framed than the in-tile render.
const ICONS_DIR := "res://resources/icons/"

var _item: Item = null
var _count: int = 0
var _equipped: bool = false
var _mesh: SubViewportContainer = null  ## an ItemMeshView, present only when the item has a mesh AND no baked icon
var _icon: Texture2D = null             ## a baked icon (preferred over the live mesh), drawn in _draw()

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip_contents = true

func set_data(item: Item, count: int, equipped: bool) -> void:
	_item = item
	_count = count
	_equipped = equipped
	_icon = _baked_icon(item)
	if _icon != null:
		# A baked icon wins over the live mesh (it's drawn in _draw); drop any mesh rig we built earlier.
		if _mesh != null:
			_mesh.queue_free()
			_mesh = null
	elif ItemMeshView.has_mesh(item):
		if _mesh == null:
			_mesh = ItemMeshView.new()
			add_child(_mesh)
			_layout_mesh()
		_mesh.show_item(item)
	elif _mesh != null:
		_mesh.queue_free()
		_mesh = null
	queue_redraw()


## A baked icon for this item if one exists at res://resources/icons/<id>.png (written by the CYBER SUNDAY Icons
## baker). Preferred over the live mesh render. Null when there's none -> fall back to the mesh, then a glyph.
func _baked_icon(item: Item) -> Texture2D:
	if item == null:
		return null
	var p := ICONS_DIR + String(item.id) + ".png"
	return load(p) if ResourceLoader.exists(p) else null

func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		_layout_mesh()

func _layout_mesh() -> void:
	if _mesh != null:
		_mesh.position = Vector2(MESH_INSET, MESH_INSET)
		_mesh.size = Vector2(maxf(0.0, size.x - MESH_INSET * 2.0), maxf(0.0, size.y - MESH_INSET * 2.0))

func _draw() -> void:
	var r := Rect2(Vector2.ZERO, size)
	var col := _category_color(_item)
	draw_rect(r, Color(col.r, col.g, col.b, 0.18), true)  # tinted panel
	var border := MenuStyle.gold() if _equipped else Color(col.r, col.g, col.b, 0.75)
	draw_rect(r, border, false, 2.0 if _equipped else 1.0)
	if _icon != null:
		var inset := Rect2(MESH_INSET, MESH_INSET, maxf(0.0, size.x - MESH_INSET * 2.0), maxf(0.0, size.y - MESH_INSET * 2.0))
		draw_texture_rect(_icon, inset, false)  # baked icon, already at the footprint aspect -> fills the tile
	elif _mesh == null:
		_draw_glyph(r, col)  # no baked icon + no mesh -> a clean category mark instead of a text label
	if _count > 1:
		var font := get_theme_default_font()
		if font != null:
			var fs := get_theme_default_font_size()
			draw_string(font, Vector2(0.0, size.y - 3.0), "x%d" % _count, HORIZONTAL_ALIGNMENT_RIGHT, size.x - 3.0, fs, MenuStyle.text_color())

## A simple drawn mark for items with no 3D mesh (ammo / consumable / misc), so the tile never falls back to ugly
## raw text. Ammo = a little clip of rounds, consumable = a medical plus, otherwise the item's initial.
func _draw_glyph(r: Rect2, col: Color) -> void:
	var c := r.size * 0.5
	if _item != null and _item.is_ammo():
		var n := 3
		var w := r.size.x * 0.12
		var h := r.size.y * 0.40
		for i in n:
			var x := c.x + (float(i) - float(n - 1) * 0.5) * (w + 3.0)
			draw_rect(Rect2(x - w * 0.5, c.y - h * 0.5, w, h), col, true)
	elif _item != null and _item.is_consumable():
		var t := r.size.x * 0.16
		var l := r.size.y * 0.46
		draw_rect(Rect2(c.x - t * 0.5, c.y - l * 0.5, t, l), col, true)
		draw_rect(Rect2(c.x - l * 0.5, c.y - t * 0.5, l, t), col, true)
	else:
		var font := get_theme_default_font()
		if font != null and _item != null:
			var fs := int(minf(r.size.x, r.size.y) * 0.5)
			draw_string(font, Vector2(0.0, c.y + float(fs) * 0.35), _item.label().substr(0, 1), HORIZONTAL_ALIGNMENT_CENTER, r.size.x, fs, col)

func _category_color(item: Item) -> Color:
	if item == null:
		return MenuStyle.dim_color()
	if item.is_weapon():
		return MenuStyle.accent()
	if item.is_ammo():
		return MenuStyle.gold()
	if item.is_consumable():
		return Color(0.45, 0.80, 0.52)
	return MenuStyle.dim_color()
