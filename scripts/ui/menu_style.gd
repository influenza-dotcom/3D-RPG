extends Node

## MenuStyle (autoload) — turns the active MenuSkin resource into the live Theme every menu uses, plus
## helpers for backdrops, titles, hints and the palette. Reskin the WHOLE UI by editing
## resources/ui/menu_skin.tres (or MenuStyle.set_skin(other_skin)) — no menu code changes. A menu calls
## MenuStyle.apply(root) once, builds its tree with normal Controls, and uses make_title/make_hint/make_panel
## + the palette accessors; the shared Theme handles button hover/focus/disabled, panels, sliders, tabs and
## tooltips so every screen matches automatically.

var skin: MenuSkin = preload("res://resources/ui/menu_skin.tres")
var theme: Theme
var _title_font: Font

# Custom in-viewport tooltip — a Control in our OWN CanvasLayer so it renders INSIDE the 396x216 scaled
# viewport (pixelated like the game), unlike Godot's native tooltip Popups which draw at desktop res.
var _tip_layer: CanvasLayer
var _tip_panel: PanelContainer
var _tip_label: Label
var _tip_target: Control = null

# UI sound players (PROCESS_MODE_ALWAYS so they play through a paused menu). Every button under a menu root
# auto-plays the skin's hover/click sounds — wired by the node_added hook, no per-button code.
var _hover_player: AudioStreamPlayer
var _click_player: AudioStreamPlayer

func _ready() -> void:
	# Process through a paused tree: the shop / level-up / heal screens pause the world, and _process is what
	# makes the hover tooltip FOLLOW the cursor — without this it freezes at a stale spot in those menus.
	process_mode = Node.PROCESS_MODE_ALWAYS
	rebuild()
	_build_tip()
	_build_sound()
	var tree := get_tree()
	if tree != null:
		tree.node_added.connect(_on_node_added)

## Rebuild the Theme + fonts from the current skin. Call after swapping the skin at runtime.
func rebuild() -> void:
	if skin == null:
		skin = MenuSkin.new()
	_title_font = _make_title_font()
	theme = _build_theme()
	_style_tip()  # no-op until the tip is built; restyles it on a runtime skin swap

## Swap to a different artist skin at runtime and rebuild everything.
func set_skin(new_skin: MenuSkin) -> void:
	if new_skin == null:
		return
	skin = new_skin
	rebuild()

# --- palette accessors (menus read MenuStyle.accent() etc. so colours stay in one place) ---
func accent() -> Color: return skin.accent_color
func gold() -> Color: return skin.gold_color
func text_color() -> Color: return skin.text_color
func dim_color() -> Color: return skin.text_dim_color
func danger() -> Color: return skin.danger_color

## Set `root.theme` to the menu theme so every child inherits the look, and MARK the subtree so every
## button under it auto-gets the hover/click sounds. Call once on a menu's root Control.
func apply(root: Control) -> void:
	if is_instance_valid(root):
		root.theme = theme
		root.set_meta(&"_menu_root", true)

# --- backdrops -------------------------------------------------------------------------------------

## Full-screen menu background (the start menu): the skin's scene > texture > flat colour. Returns a Control
## anchored to fill its parent — add it as the FIRST child so menu content draws on top.
func make_menu_background() -> Control:
	if skin.background_scene != null:
		var inst: Node = skin.background_scene.instantiate()
		# empty-PackedScene reimport transient -> instantiate() can return null; fall through to texture/colour fallback
		if inst != null:
			if inst is Control:
				(inst as Control).set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
			return inst if inst is Control else _wrap_fullrect(inst)
	if skin.background_texture != null:
		var rect := TextureRect.new()
		rect.texture = skin.background_texture
		rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		return rect
	var cr := ColorRect.new()
	cr.color = skin.background_color
	cr.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	cr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return cr

## The dim drawn over the gameplay world behind an in-game modal. Eats clicks (MOUSE_FILTER_STOP).
func make_dim() -> ColorRect:
	var cr := ColorRect.new()
	cr.color = skin.backdrop_dim
	cr.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	cr.mouse_filter = Control.MOUSE_FILTER_STOP
	return cr

## A styled menu panel (PanelContainer using the theme's sleek panel stylebox). Put your content inside it.
func make_panel() -> PanelContainer:
	return PanelContainer.new()  # picks up the theme's "panel" stylebox automatically

# --- text factories --------------------------------------------------------------------------------

## A tracked title Label (uppercased per the skin), centred, in the title font/size/colour.
func make_title(s: String) -> Label:
	var l := Label.new()
	l.text = (s.to_upper() if skin.uppercase_titles else s)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_override(&"font", _title_font)
	l.add_theme_font_size_override(&"font_size", skin.title_size)
	l.add_theme_color_override(&"font_color", skin.text_color)
	return l

## A dim footnote/hint Label, centred, at the hint size. WRAPS: long hint text reflows to the available width
## instead of forcing its single-line width onto the parent — without this, a paragraph-length hint pushes the
## menu's ScrollContainer (horizontal scroll is disabled) and the whole panel super-wide. With autowrap the
## hint's min-width collapses, so the menu keeps its anchored width and the text scales to fit at any res.
func make_hint(s: String) -> Label:
	var l := Label.new()
	l.text = s
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override(&"font_size", skin.hint_size)
	l.add_theme_color_override(&"font_color", skin.text_dim_color)
	return l

## A thin full-width hairline separator (HSeparator styled by the theme).
func make_separator() -> HSeparator:
	return HSeparator.new()

# --- custom tooltip ---------------------------------------------------------------------------------

## Show `text` when the mouse hovers `control` (e.g. an inventory row button or a stat label), in our own
## low-res in-viewport tip panel. Idempotent: call again to UPDATE the text (e.g. a polled stat sheet).
## Attach to the ACTUAL hovered control (the Button, the Label) — not a wrapper that a child Button would
## intercept. Empty text detaches nothing but is simply ignored.
func attach_tip(control: Control, text: String) -> void:
	if not is_instance_valid(control) or text.is_empty():
		return
	control.set_meta(&"_tip_text", text)
	if control.has_meta(&"_tip_wired"):
		return
	control.set_meta(&"_tip_wired", true)
	if control.mouse_filter == Control.MOUSE_FILTER_IGNORE:
		control.mouse_filter = Control.MOUSE_FILTER_STOP  # a Label ignores the mouse by default; let it hover
	control.mouse_entered.connect(_tip_show.bind(control))
	control.mouse_exited.connect(_tip_hide.bind(control))
	control.tree_exiting.connect(_tip_hide.bind(control))  # hide if a row is rebuilt/freed while hovered

func _tip_show(control: Control) -> void:
	if _tip_panel == null or not is_instance_valid(control):
		return
	_tip_target = control
	_tip_label.text = String(control.get_meta(&"_tip_text", ""))
	_tip_panel.reset_size()
	_tip_panel.visible = true

func _tip_hide(control: Control) -> void:
	if _tip_panel == null:
		return
	if control == _tip_target or not is_instance_valid(_tip_target):
		_tip_target = null
		_tip_panel.visible = false

func _process(_delta: float) -> void:
	if _tip_panel == null or not _tip_panel.visible:
		return
	var vp := get_viewport()
	if vp == null:
		return
	var screen: Vector2 = vp.get_visible_rect().size
	var mpos: Vector2 = vp.get_mouse_position()
	var sz: Vector2 = _tip_panel.size
	var pos: Vector2 = mpos + Vector2(8, 8)
	if pos.x + sz.x > screen.x:
		pos.x = mpos.x - sz.x - 8  # flip to the cursor's left near the right edge
	if pos.y + sz.y > screen.y:
		pos.y = mpos.y - sz.y - 8  # flip above near the bottom edge
	pos.x = clampf(pos.x, 0.0, maxf(0.0, screen.x - sz.x))
	pos.y = clampf(pos.y, 0.0, maxf(0.0, screen.y - sz.y))
	_tip_panel.position = pos

func _build_tip() -> void:
	_tip_layer = CanvasLayer.new()
	_tip_layer.layer = 200  # above every menu (modals sit at ~121, options ~128)
	add_child(_tip_layer)
	_tip_panel = PanelContainer.new()
	_tip_panel.visible = false
	_tip_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tip_label = Label.new()
	_tip_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tip_panel.add_child(_tip_label)
	_tip_layer.add_child(_tip_panel)
	_style_tip()

# --- button sounds ----------------------------------------------------------------------------------

func _build_sound() -> void:
	_hover_player = AudioStreamPlayer.new()
	_hover_player.process_mode = Node.PROCESS_MODE_ALWAYS  # play even while a paused menu (shop/heal/level-up) holds the tree
	_hover_player.bus = &"sfx"
	add_child(_hover_player)
	_click_player = AudioStreamPlayer.new()
	_click_player.process_mode = Node.PROCESS_MODE_ALWAYS
	_click_player.bus = &"sfx"
	add_child(_click_player)

## Every node added anywhere: if it's a button inside a menu root, wire its hover/click sounds. The
## BaseButton check is first so this is near-free for the gameplay nodes that dominate node_added.
## NOTE: this is a tree-global SceneTree.node_added listener, so it fires for EVERY node spawned anywhere
## (projectiles, VFX, NPCs). The leading `node is BaseButton` early-out keeps it ~free for that common
## case; only the rare button walks ancestors. Kept global on purpose — buttons are built lazily under
## many menu roots and there's no single parent to scope a local signal to.
func _on_node_added(node: Node) -> void:
	if not (node is BaseButton):
		return
	var p: Node = node
	while p != null:
		if p.has_meta(&"_menu_root"):
			_wire_button(node as BaseButton)
			return
		p = p.get_parent()

func _wire_button(btn: BaseButton) -> void:
	if btn.has_meta(&"_snd_wired"):
		return
	btn.set_meta(&"_snd_wired", true)
	btn.mouse_entered.connect(_play_hover)
	btn.pressed.connect(_play_click)  # a disabled button can't be pressed, so it never click-sounds

func _play_hover() -> void:
	if skin.hover_sound != null and _hover_player != null:
		_hover_player.stream = skin.hover_sound
		_hover_player.volume_db = skin.ui_sound_volume_db
		_hover_player.play()

func _play_click() -> void:
	if skin.click_sound != null and _click_player != null:
		_click_player.stream = skin.click_sound
		_click_player.volume_db = skin.ui_sound_volume_db
		_click_player.play()

## (Re)apply the skin's look to the tip panel — called on build and on set_skin/rebuild.
func _style_tip() -> void:
	if _tip_panel == null:
		return
	_tip_panel.add_theme_stylebox_override(&"panel", _flat(Color(0.04, 0.04, 0.055, 0.98), 1, skin.panel_border_color, skin.panel_corner_radius, 5, 4))
	_tip_label.add_theme_color_override(&"font_color", skin.text_color)
	_tip_label.add_theme_font_size_override(&"font_size", skin.hint_size)

# --- internals -------------------------------------------------------------------------------------

func _make_title_font() -> Font:
	var base: Font = skin.title_font
	if base == null:
		base = skin.body_font
	if base == null:
		base = ThemeDB.fallback_font
	if skin.title_tracking == 0:
		return base
	var fv := FontVariation.new()
	fv.base_font = base
	fv.set_spacing(TextServer.SPACING_GLYPH, skin.title_tracking)
	return fv

## A StyleBoxFlat with the given fill, optional border, and corner radius — the building block of the theme.
func _flat(fill: Color, border_w: int = 0, border_col: Color = Color(0, 0, 0, 0), corner: int = 0, margin_h: int = 0, margin_v: int = 0) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = fill
	if border_w > 0:
		sb.set_border_width_all(border_w)
		sb.border_color = border_col
	if corner > 0:
		sb.set_corner_radius_all(corner)
	sb.content_margin_left = margin_h
	sb.content_margin_right = margin_h
	sb.content_margin_top = margin_v
	sb.content_margin_bottom = margin_v
	return sb

## A row/button selection stylebox: faint accent fill + a 2px accent bar on the left (the sleek "selected" look).
func _accent_bar(fill_alpha: float) -> StyleBoxFlat:
	var a: Color = skin.accent_color
	var sb := _flat(Color(a.r, a.g, a.b, fill_alpha), 0, Color(0, 0, 0, 0), 0, 9, 5)
	sb.border_width_left = 2
	sb.border_color = a
	return sb

func _build_theme() -> Theme:
	var t := Theme.new()
	if skin.body_font != null:
		t.default_font = skin.body_font
	t.default_font_size = skin.body_size

	# Panel / PanelContainer ----------------------------------------------------
	var panel_sb: StyleBox
	if skin.panel_style != null:
		panel_sb = skin.panel_style
	else:
		var m: int = skin.panel_content_margin
		panel_sb = _flat(skin.panel_color, skin.panel_border_width, skin.panel_border_color, skin.panel_corner_radius, m, m)
	t.set_stylebox(&"panel", &"PanelContainer", panel_sb)
	t.set_stylebox(&"panel", &"Panel", panel_sb)

	# Buttons — sleek + borderless: transparent normal, faint hover, accent-bar on hover/focus -----
	var clear := _flat(Color(0, 0, 0, 0), 0, Color(0, 0, 0, 0), 0, 9, 5)
	t.set_stylebox(&"normal", &"Button", clear)
	t.set_stylebox(&"hover", &"Button", _accent_bar(0.0).duplicate())  # bar + no fill on plain hover
	var sel := _accent_bar(0.10)                                       # focus/pressed = bar + faint fill
	t.set_stylebox(&"pressed", &"Button", sel)
	t.set_stylebox(&"focus", &"Button", sel.duplicate())
	t.set_stylebox(&"hover_pressed", &"Button", sel.duplicate())
	t.set_stylebox(&"disabled", &"Button", clear.duplicate())
	t.set_color(&"font_color", &"Button", skin.text_dim_color)
	t.set_color(&"font_hover_color", &"Button", skin.text_color)
	t.set_color(&"font_pressed_color", &"Button", skin.accent_color)
	t.set_color(&"font_focus_color", &"Button", skin.text_color)
	t.set_color(&"font_hover_pressed_color", &"Button", skin.accent_color)
	t.set_color(&"font_disabled_color", &"Button", skin.disabled_text_color)
	t.set_font_size(&"font_size", &"Button", skin.body_size)

	# Labels --------------------------------------------------------------------
	t.set_color(&"font_color", &"Label", skin.text_color)
	t.set_font_size(&"font_size", &"Label", skin.body_size)

	# Separator (hairline) ------------------------------------------------------
	var sep := _flat(Color(0, 0, 0, 0))
	sep.border_width_top = 1
	sep.border_color = Color(skin.text_color.r, skin.text_color.g, skin.text_color.b, 0.08)
	sep.content_margin_top = 1
	t.set_stylebox(&"separator", &"HSeparator", sep)
	t.set_stylebox(&"separator", &"VSeparator", sep.duplicate())

	# Sliders — thin track, accent fill ----------------------------------------
	var track := _flat(Color(skin.text_color.r, skin.text_color.g, skin.text_color.b, 0.12), 0, Color(0, 0, 0, 0), 1)
	track.content_margin_top = 1
	track.content_margin_bottom = 1
	t.set_stylebox(&"slider", &"HSlider", track)
	var fill := _flat(skin.accent_color, 0, Color(0, 0, 0, 0), 1)
	fill.content_margin_top = 1
	fill.content_margin_bottom = 1
	t.set_stylebox(&"grabber_area", &"HSlider", fill)
	t.set_stylebox(&"grabber_area_highlight", &"HSlider", fill.duplicate())
	t.set_icon(&"grabber", &"HSlider", _grabber_tex())
	t.set_icon(&"grabber_highlight", &"HSlider", _grabber_tex())

	# Scrollbars — minimal ------------------------------------------------------
	var sb_bg := _flat(Color(skin.text_color.r, skin.text_color.g, skin.text_color.b, 0.05), 0, Color(0, 0, 0, 0), 2)
	var sb_grab := _flat(Color(skin.text_color.r, skin.text_color.g, skin.text_color.b, 0.22), 0, Color(0, 0, 0, 0), 2)
	for kind in [&"VScrollBar", &"HScrollBar"]:
		t.set_stylebox(&"scroll", kind, sb_bg.duplicate())
		t.set_stylebox(&"grabber", kind, sb_grab.duplicate())
		t.set_stylebox(&"grabber_highlight", kind, sb_grab.duplicate())
		t.set_stylebox(&"grabber_pressed", kind, sb_grab.duplicate())

	# Tabs (options menu) — text-forward, accent underline on the active tab ----
	var tab_clear := _flat(Color(0, 0, 0, 0), 0, Color(0, 0, 0, 0), 0, 8, 4)
	var tab_sel := _flat(Color(0, 0, 0, 0), 0, Color(0, 0, 0, 0), 0, 8, 4)
	tab_sel.border_width_bottom = 2
	tab_sel.border_color = skin.accent_color
	t.set_stylebox(&"tab_selected", &"TabContainer", tab_sel)
	t.set_stylebox(&"tab_unselected", &"TabContainer", tab_clear)
	t.set_stylebox(&"tab_hovered", &"TabContainer", tab_clear.duplicate())
	t.set_stylebox(&"panel", &"TabContainer", _flat(Color(0, 0, 0, 0)))
	t.set_stylebox(&"tabbar_background", &"TabContainer", _flat(Color(0, 0, 0, 0)))
	t.set_color(&"font_selected_color", &"TabContainer", skin.text_color)
	t.set_color(&"font_unselected_color", &"TabContainer", skin.text_dim_color)
	t.set_color(&"font_hovered_color", &"TabContainer", skin.text_color)

	# Tooltips — themed dark panel so hover breakdowns match the menus -----------
	var tip := _flat(Color(0.04, 0.04, 0.055, 0.97), 1, skin.panel_border_color, skin.panel_corner_radius, 8, 6)
	t.set_stylebox(&"panel", &"TooltipPanel", tip)
	t.set_color(&"font_color", &"TooltipLabel", skin.text_color)
	t.set_font_size(&"font_size", &"TooltipLabel", skin.hint_size)

	# CheckButton / CheckBox / OptionButton inherit the Button colours above for free.
	return t

## A tiny accent-coloured slider thumb (a 3x10 bar) generated in code so no thumb asset is needed.
func _grabber_tex() -> ImageTexture:
	var img := Image.create(3, 10, false, Image.FORMAT_RGBA8)
	img.fill(skin.accent_color)
	return ImageTexture.create_from_image(img)

## Bare wrapper so a non-Control background scene still fills the screen.
func _wrap_fullrect(node: Node) -> Control:
	var c := Control.new()
	c.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	c.add_child(node)
	return c
