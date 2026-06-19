extends Control

## A single inventory-style TILE for the player's ZORKMIDS — money shown as "its own item with a stack". DISPLAY
## ONLY: the wallet stays a float on the Character (the whole economy reads player.money — merchants, pickups,
## bounties, the save), and this just renders that amount as a gold coin tile with the value as its stack count,
## in the backpack header. Fed live via set_amount(). No class_name — InventoryScreen preloads it (internal UI).

const TILE_PX := 44.0  ## a single grid-cell-ish square

var _amount: float = 0.0

func _ready() -> void:
	custom_minimum_size = Vector2(TILE_PX, TILE_PX)
	size_flags_horizontal = Control.SIZE_SHRINK_CENTER  # a fixed tile, centred — never stretched by its container
	size_flags_vertical = Control.SIZE_SHRINK_CENTER    # ...in EITHER axis (a stretched tile blew the coin up huge)
	mouse_filter = Control.MOUSE_FILTER_STOP            # eat hover so the tooltip shows
	MenuStyle.attach_tip(self, "Zorkmids — your money")

## Update the displayed wallet; redraws only when the value actually changes (polled each frame while open).
func set_amount(v: float) -> void:
	if is_equal_approx(v, _amount):
		return
	_amount = v
	queue_redraw()

func _draw() -> void:
	var r := Rect2(Vector2.ZERO, size)
	var gold := MenuStyle.gold()
	draw_rect(r, Color(gold.r, gold.g, gold.b, 0.14), true)  # faint gold fill, like a tile
	draw_rect(r, gold, false, 1.5)                           # gold border (reads as the "currency" item)
	# The "mesh": a gold coin — a filled disc with a thin dark rim. Radius bound to the SMALLER side so a tile that
	# somehow gets stretched can never blow the coin up to fill the screen.
	var d := minf(size.x, size.y)
	var c := Vector2(size.x * 0.5, size.y * 0.42)
	var rad := d * 0.26
	draw_circle(c, rad, gold)
	draw_arc(c, rad, 0.0, TAU, 24, Color(0.0, 0.0, 0.0, 0.35), 1.5)
	# The "stack count": the formatted zorkmid amount along the bottom.
	var font := get_theme_default_font()
	if font != null:
		var fs := get_theme_default_font_size()
		draw_string(font, Vector2(2.0, size.y - 3.0), Zorkmids.fmt(_amount), HORIZONTAL_ALIGNMENT_CENTER, size.x - 4.0, fs, MenuStyle.text_color())
