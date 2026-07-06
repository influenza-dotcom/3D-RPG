extends Control

## One styled inventory TILE (a single stack) for GridInventoryView. Mouse-TRANSPARENT — the grid view owns all
## input; this is pure visual. It draws a category-tinted panel + border (gold when equipped), the item's art —
## an authored Item.icon, else a baked icon PNG, else its LIVE 3D mesh (an ItemMeshView child), else a clean
## category glyph — and a stack-count badge. A stack placed 90°-ROTATED on the grid (swapped w/h) draws its icon
## turned / its mesh viewport rotated to match. The grid reuses tiles across refreshes (keyed by stack), so a
## drag/move repositions the same tile instead of re-instantiating its mesh.

const ItemMeshView := preload("res://scripts/ui/item_mesh_view.gd")
const MESH_INSET := 3.0
## Where the CYBER SUNDAY Icons baker writes per-item icons (res://resources/icons/<item.id>.png). When one exists
## the tile draws it instead of the live mesh — cleaner + consistently framed than the in-tile render.
const ICONS_DIR := "res://resources/icons/"

var _item: Item = null
var _count: int = 0
var _equipped: bool = false
var _locked: bool = false               ## the wielded weapon during a pickpocket: shown as a padlock, un-takeable
var _rotated: bool = false              ## the stack sits 90°-rotated on the grid (its w/h footprint is swapped) —
										## the icon draws turned and the live mesh viewport rotates to match
var _mesh: SubViewportContainer = null  ## an ItemMeshView, present only when the item has a mesh AND no baked icon
var _icon: Texture2D = null             ## an authored/baked icon (preferred over the live mesh), drawn in _draw()

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip_contents = true

func set_data(item: Item, count: int, equipped: bool, locked: bool = false, rotated: bool = false) -> void:
	_item = item
	_count = count
	_equipped = equipped
	_locked = locked
	_rotated = rotated
	# A LOCKED tile (the gun a live NPC is holding) shows a padlock, NOT the item — drop any mesh/icon so nothing
	# draws over the lock (a child SubViewport would render above _draw). Take is refused by the host either way.
	_icon = null if locked else icon_for(item)
	if locked:
		if _mesh != null:
			_mesh.visible = false  # hide NOW — queue_free is deferred and a child SubViewport draws over _draw, so a
			_mesh.queue_free()     # mesh-built tile turning locked mid-session would flash the gun over the padlock for one frame
			_mesh = null
	elif _icon != null:
		# A baked icon wins over the live mesh (it's drawn in _draw); drop any mesh rig we built earlier.
		if _mesh != null:
			_mesh.queue_free()
			_mesh = null
	elif ItemMeshView.has_mesh(item):
		if _mesh == null:
			_mesh = ItemMeshView.new()
			add_child(_mesh)
		_layout_mesh()  # always re-layout: a reused tile's rotation may have flipped since the mesh was built
		_mesh.show_item(item)
	elif _mesh != null:
		_mesh.queue_free()
		_mesh = null
	queue_redraw()


## The icon to draw for `item`: its authored Item.icon when one is set (the designer override for meshless
## items), else the baked res://resources/icons/<id>.png. Null -> fall back to the live mesh, then a glyph.
## STATIC so the grid view's drag preview shows the same art the settled tile will.
static func icon_for(item: Item) -> Texture2D:
	if item == null:
		return null
	if item.icon != null:
		return item.icon
	return _baked_icon(item)

## A baked icon for this item if one exists at res://resources/icons/<id>.png (written by the CYBER SUNDAY Icons
## baker or scripts/tools/bake_item_icons.gd).
static func _baked_icon(item: Item) -> Texture2D:
	if item == null:
		return null
	var p := ICONS_DIR + String(item.id) + ".png"
	return load(p) if ResourceLoader.exists(p) else null

func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		_layout_mesh()

## Place the live-mesh viewport inside the tile. A ROTATED stack turns the whole SubViewportContainer 90° CW
## (Control.rotation about the default top-left pivot — hence the shifted position) with its w/h swapped, so the
## model reads turned on the grid exactly like a rotated baked icon; the container's swapped size also feeds the
## viewport's aspect-fit (_frame) automatically via stretch.
func _layout_mesh() -> void:
	if _mesh == null:
		return
	var w := maxf(0.0, size.x - MESH_INSET * 2.0)
	var h := maxf(0.0, size.y - MESH_INSET * 2.0)
	if _rotated:
		_mesh.rotation = PI * 0.5
		_mesh.position = Vector2(size.x - MESH_INSET, MESH_INSET)  # top-left pivot: shift so the turned rect lands in the inset
		_mesh.size = Vector2(h, w)
	else:
		_mesh.rotation = 0.0
		_mesh.position = Vector2(MESH_INSET, MESH_INSET)
		_mesh.size = Vector2(w, h)

func _draw() -> void:
	var r := Rect2(Vector2.ZERO, size)
	var col := _category_color(_item)
	draw_rect(r, Color(col.r, col.g, col.b, 0.18), true)  # tinted panel
	var border := MenuStyle.gold() if _equipped else Color(col.r, col.g, col.b, 0.75)
	draw_rect(r, border, false, 2.0 if _equipped else 1.0)
	if _locked:
		_draw_lock(r)  # the wielded weapon during a pickpocket: a padlock in place of the item — you can't take it
		return
	if _icon != null:
		var inset := Rect2(MESH_INSET, MESH_INSET, maxf(0.0, size.x - MESH_INSET * 2.0), maxf(0.0, size.y - MESH_INSET * 2.0))
		draw_item_icon(self, _icon, inset, _rotated)  # icon at the footprint aspect -> fills the tile (turned when rotated)
	elif _mesh == null:
		_draw_glyph(r, col)  # no baked icon + no mesh -> a clean category mark instead of a text label
	if _count > 1:
		var font := get_theme_default_font()
		if font != null:
			var fs := get_theme_default_font_size()
			draw_string(font, Vector2(0.0, size.y - 3.0), "x%d" % _count, HORIZONTAL_ALIGNMENT_RIGHT, size.x - 3.0, fs, MenuStyle.text_color())

## Draw `icon` filling `rect`; `rotated` turns it 90° CLOCKWISE (the grid's one rotation — a placement only ever
## swaps w/h, so one direction is enough and drag preview / settled tile / live mesh all agree on it). The icon is
## baked at the UNROTATED footprint's aspect, so the turned draw maps its long side onto the rect's long side —
## no stretching. Shared by the tile and the grid view's drag preview (hence static + an explicit canvas).
static func draw_item_icon(canvas: CanvasItem, icon: Texture2D, rect: Rect2, rotated: bool) -> void:
	if icon == null:
		return
	if not rotated:
		canvas.draw_texture_rect(icon, rect, false)
		return
	# Rotate the canvas 90° CW about the rect's top-RIGHT corner, then draw into a w/h-swapped rect at the new
	# origin: the icon's top edge lands on the rect's right edge. Transform restored — draw state is shared.
	canvas.draw_set_transform(Vector2(rect.position.x + rect.size.x, rect.position.y), PI * 0.5, Vector2.ONE)
	canvas.draw_texture_rect(icon, Rect2(0.0, 0.0, rect.size.y, rect.size.x), false)
	canvas.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

## A centred padlock — drawn instead of the item on a LOCKED tile: the weapon an NPC is actively WIELDING while
## you pickpocket it. Reads as "can't take this" (the host's take-guard refuses it). Composed from primitives
## (an arc shackle + a body rect + a keyhole) so it needs no texture and scales with the cell size.
func _draw_lock(r: Rect2) -> void:
	var c := r.size * 0.5
	var s := minf(r.size.x, r.size.y)
	var bw := s * 0.40   # padlock body width
	var bh := s * 0.32   # padlock body height
	var body := Rect2(c.x - bw * 0.5, c.y - bh * 0.15, bw, bh)
	var col := Color(0.90, 0.90, 0.94, 0.95)
	# Shackle: a half-circle arc rising out of the top of the body.
	draw_arc(Vector2(c.x, body.position.y), bw * 0.30, PI, TAU, 20, col, maxf(1.5, s * 0.055))
	draw_rect(body, col, true)                                                    # body
	draw_circle(Vector2(c.x, body.position.y + bh * 0.5), maxf(1.0, s * 0.045), Color(0.12, 0.12, 0.16, 0.95))  # keyhole

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
