extends Node

## MenuStyle (autoload) — turns the active MenuSkin resource into the live Theme every menu uses, plus
## helpers for backdrops, titles, hints and the palette. Reskin the WHOLE UI by editing
## resources/ui/menu_skin.tres (or MenuStyle.set_skin(other_skin)) — no menu code changes. A menu calls
## MenuStyle.apply(root) once, builds its tree with normal Controls, and uses make_title/make_hint/make_panel
## + the palette accessors; the shared Theme handles button hover/focus/disabled, panels, sliders, tabs and
## tooltips so every screen matches automatically.
##
## TRANSLATION SEAM (invisible, so it's named here): under Godot's automatic Control-text translation (atr),
## every `label.text = PlayerText.X` / `btn.text = ...` assignment anywhere in the UI IS a translation site —
## the assigned string is silently used as a msgid the moment a TranslationServer locale ships. That is why
## (1) title_text() below stays PURE casing with no tr(): most of its call sites pass already-COMPOSED runtime
## strings carrying names (merchant/station/pet names, some player-TYPED), and a tr() here would look those up
## as msgids and double-translate on top of atr; and (2) any Control that paints player-typed text must set
## auto_translate_mode = AUTO_TRANSLATE_MODE_DISABLED (see _build_tip, ui.gd's look/toast labels, the name
## LineEdits) so typed text is never looked up as a msgid.

var skin: MenuSkin = preload("res://resources/ui/menu_skin.tres")
var theme: Theme
var _title_font: Font

# Custom in-viewport tooltip — a Control in our OWN CanvasLayer so it renders INSIDE the scaled
# viewport (pixelated like the game), unlike Godot's native tooltip Popups which draw at desktop res.
# NOTE the real UI canvas is 792x444 at 16:9 (base 396x216 doubled by window/stretch/scale 0.5, then
# aspect="expand" stretches it per monitor shape) — NOT the 396x216 the project settings suggest.
# Menus must lay out against ~792x444 and survive 792x432..792x495+ (16:10, ultrawide).
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

## A centered, FIXED-WIDTH dialog scaffold for the floating transaction / prompt modals (heal / respec /
## name-entry). Adds a full-rect CenterContainer (vertical + horizontal centering at ANY canvas — the reason
## these screens use container-centering rather than an anchor band, which floated the short card off-centre)
## holding a themed PanelContainer, and returns the content VBox to fill. The VBox is PINNED to
## skin.dialog_width, so the card is EXACTLY that wide no matter what strings it holds — the old
## content-hugging panel grew and re-centred with its widest line (a long station name, a big cost). For the
## pin to hold, every child the caller adds must collapse its own min-width: run unbounded single-line Labels
## and dynamic-text Buttons through cap_label()/cap_button() (clip + "…"), let status Labels autowrap, and give
## a button row EXPAND_FILL children. The pin is WIDTH-ONLY — the card's HEIGHT still shrink-wraps and the
## CenterContainer re-centers on any height change, so a child whose LINE COUNT varies at runtime (an optional
## status line appearing/dropping) hops the whole card vertically. Keep every dynamic child's line count
## CONSTANT while the card is visible: pad the composed string to its worst-case line count (heal_screen's
## _refresh idiom) or reserve custom_minimum_size.y. No blanket height pin here — each card's natural height
## differs, so the reservation belongs at the consumer. Parent this under a full-rect root AFTER
## add_child(make_dim()). `extra_sep` adds to the shared content_separation for an airier few-row card.
func make_dialog(root: Control, extra_sep: int = 0) -> VBoxContainer:
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE  # purely positional; the dim beneath eats stray clicks
	root.add_child(center)
	var panel := PanelContainer.new()  # theme "panel" stylebox
	center.add_child(panel)
	var vbox := VBoxContainer.new()
	vbox.custom_minimum_size.x = skin.dialog_width  # PIN the card width — content can never grow it (see above)
	vbox.add_theme_constant_override("separation", skin.content_separation + extra_sep)
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	panel.add_child(vbox)
	return vbox

## Cap a single-line Label so its text can NEVER drive its parent wider: clip_text drops its horizontal
## minimum size to ~0 and the ellipsis overrun trims the glyphs to whatever width the container hands it.
## Use on unbounded runtime Labels (dialog titles, stat/perk column labels) living inside a fixed-width
## parent — WITHOUT this a Label reports its full text width as its min size and pushes the parent out.
func cap_label(l: Label) -> Label:
	l.clip_text = true
	l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	return l

## Cap a Button the same way (Button has its own clip_text) — for buttons whose caption carries an unbounded
## runtime string (a heal/respec cost, a cycling Sort mode) so a long caption clips instead of resizing the
## button and shifting the row.
func cap_button(b: Button) -> Button:
	b.clip_text = true
	return b

# --- text factories --------------------------------------------------------------------------------

## A tracked title Label (uppercased per the skin), centred, in the title font/size/colour.
## Ellipsizes instead of growing: a long runtime title (merchant/station names are designer-authored,
## unbounded) must never drive the hosting panel wider than its anchors — it trims with "…" instead.
func make_title(s: String) -> Label:
	var l := Label.new()
	l.text = title_text(s)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	l.add_theme_font_override(&"font", _title_font)
	l.add_theme_font_size_override(&"font_size", skin.title_size)
	l.add_theme_color_override(&"font_color", skin.text_color)
	return l

## Apply the skin's title casing to runtime text. Screens that RE-title an existing make_title Label
## (shop "TRADE — %s", heal/level-up/respec station names, name-entry prompts) must route the new text
## through this, because make_title only cases its constructor argument.
## This is the ONLY casing site in the UI — never write a bare .to_upper() at a screen (options_menu's
## section headers route here too). It consults skin.uppercase_titles so a per-locale MenuSkin remap can
## flip casing OFF wholesale (CJK/Turkish-style locales have no meaningful uppercase). PURE casing on
## purpose: no tr() here — most callers pass composed runtime strings carrying names (some player-typed),
## which must never be looked up as msgids (see the TRANSLATION SEAM note in the header).
func title_text(s: String) -> String:
	return s.to_upper() if skin.uppercase_titles else s

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

## A FIXED-HEIGHT clipping host for a hover-tooltip footer, with `hint` parented inside it filling the rect.
## The shared construct behind LootScreen's and InventoryScreen's footers, which both need the same two things:
##   * a height that CANNOT change with the text — a Label reports its full wrapped height as its minimum, so a
##     bare Label in a VBox grows and shrinks on hover, which re-lays-out (and juddered) the EXPAND_FILL grid
##     columns above it. An anchored child inside a plain Control feeds nothing back, so the footer is inert.
##   * a height that is an EXACT INTEGER MULTIPLE of the real rendered line height, so when a long tooltip does
##     overflow, the clip lands cleanly BETWEEN lines. The old `lines * (hint_size + 4)` guess didn't divide
##     evenly by the true line height and sliced the last row through the middle of its glyphs — which reads as
##     "the text is falling off the screen" rather than "there is more text". Measured off the live Label
##     (get_line_height folds the theme's line_spacing); falls back to the old estimate if the font isn't
##     resolvable yet. Line COUNT is a designer knob (MenuSkin.footer_hint_lines).
func make_hint_footer(hint: Label) -> Control:
	var footer := Control.new()
	footer.clip_contents = true
	footer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	footer.add_child(hint)
	hint.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	hint.vertical_alignment = VERTICAL_ALIGNMENT_TOP  # short text leaves dead space BELOW, never re-centres
	var line_h: float = hint.get_line_height()
	if line_h <= 0.0:
		line_h = float(skin.hint_size + 4)  # font not resolvable yet — the pre-measurement estimate
	footer.custom_minimum_size.y = float(maxi(skin.footer_hint_lines, 1)) * line_h
	return footer

## A thin full-width hairline separator (HSeparator styled by the theme).
func make_separator() -> HSeparator:
	return HSeparator.new()

## A skin-themed meter (ProgressBar) whose FILL is tinted `col` while the track keeps the theme's
## faint neutral look — use this instead of `bar.modulate = col`, which tints track+border+fill
## alike and destroys the fill/track contrast the meter exists to show (reputation standings).
## With artist fill art on the skin (meter_fill), the tint recolours a COPY of that art instead:
## a StyleBoxFlat by bg_color, a StyleBoxTexture by modulate_color (which is why the skin doc asks
## for white/grey fill art — the modulate multiplies).
func make_meter(col: Color) -> ProgressBar:
	var bar := ProgressBar.new()
	bar.show_percentage = false
	var fill: StyleBox
	if skin.meter_fill != null:
		fill = skin.meter_fill.duplicate()
		if fill is StyleBoxFlat:
			(fill as StyleBoxFlat).bg_color = col
		elif fill is StyleBoxTexture:
			(fill as StyleBoxTexture).modulate_color = col
	else:
		var f := _flat(col, 0, Color(0, 0, 0, 0), 1)
		f.content_margin_top = 1
		f.content_margin_bottom = 1
		fill = f
	bar.add_theme_stylebox_override(&"fill", fill)
	return bar

## The "you are here" stylebox for the player-menu tab strip's active tab: the skin's artist tab art
## when it carries any (tab_selected — the same slot the Options TabContainer wears, so both tab
## systems stay one visual language automatically), else transparent fill with a 2px accent underline.
func make_active_tab_style() -> StyleBox:
	if skin.tab_selected != null:
		return skin.tab_selected.duplicate()
	var sb := _flat(Color(0, 0, 0, 0), 0, Color(0, 0, 0, 0), 0, 9, 5)
	sb.border_width_bottom = 2
	sb.border_color = skin.accent_color
	return sb

## Hover/press stylebox for an INACTIVE tab in that same strip: the skin's tab_hovered art when set,
## else the active underline at 35% — one visual language for the strip, instead of the theme Button's
## LEFT accent bar (list-row language). Margins (9,5) match the Button metrics so captions don't shift
## 1px between states.
func make_hover_tab_style() -> StyleBox:
	if skin.tab_hovered != null:
		return skin.tab_hovered.duplicate()
	var sb := _flat(Color(0, 0, 0, 0), 0, Color(0, 0, 0, 0), 0, 9, 5)
	sb.border_width_bottom = 2
	var a: Color = skin.accent_color
	sb.border_color = Color(a.r, a.g, a.b, 0.35)
	return sb

# --- custom tooltip ---------------------------------------------------------------------------------

## Show `text` when the mouse hovers `control` (e.g. an inventory row button or a stat label), in our own
## low-res in-viewport tip panel. Idempotent: call again to UPDATE the text (e.g. a polled stat sheet) —
## and if the tip is SHOWING this control right now, the visible panel refreshes immediately (a shop row
## re-priced under a stationary cursor), since mouse_entered won't re-fire without mouse movement.
## Attach to the ACTUAL hovered control (the Button, the Label) — not a wrapper that a child Button would
## intercept. Empty text detaches nothing but is simply ignored.
func attach_tip(control: Control, text: String) -> void:
	if not is_instance_valid(control) or text.is_empty():
		return
	control.set_meta(&"_tip_text", text)
	if control == _tip_target and _tip_panel != null and _tip_panel.visible:
		_tip_label.text = text
		_tip_panel.reset_size()
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
	# The tip paints COMPOSED runtime strings — item-info lines lead with item.label(), which can be a
	# player-TYPED pet name (a renamed dog's Item). Typed text must never be looked up as a msgid, so this
	# label opts out of Godot's automatic Control-text translation (see the header's TRANSLATION SEAM note).
	_tip_label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
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
	btn.mouse_entered.connect(_on_button_hovered.bind(btn))  # bound-method Callable (never a capturing lambda)
	btn.pressed.connect(_play_click)  # a disabled button can't be pressed, so it never click-sounds

## Hover sound only while the button can actually respond — a DISABLED button (the greyed Apply, the
## active tab) still fires mouse_entered, and a blip over dead chrome reads as a broken control.
func _on_button_hovered(btn: BaseButton) -> void:
	if is_instance_valid(btn) and not btn.disabled:
		_play_hover()

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
## Padding matches the theme's TooltipPanel (8,6) so the cursor tip and native tooltips read as one system.
func _style_tip() -> void:
	if _tip_panel == null:
		return
	_tip_panel.add_theme_stylebox_override(&"panel",
		_pick(skin.tooltip_panel, _flat(Color(0.04, 0.04, 0.055, 0.98), 1, skin.panel_border_color, skin.panel_corner_radius, 8, 6)))
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

## The artist-art rule in one place: the skin's slot when the artist filled it, else the generated
## fallback. A DUPLICATE of the artist box, never the shared sub-resource — theme consumers (and the
## per-row meter tint) mutate what they're handed, and a shared .tres sub-resource edit would bleed
## across every widget and back into the saved skin file.
func _pick(artist: StyleBox, generated: StyleBox) -> StyleBox:
	return artist.duplicate() if artist != null else generated


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

	# Buttons — artist per-state art when the skin carries it, else the generated sleek/borderless look:
	# transparent normal, faint hover, accent-bar on hover/focus. Every _pick fallback below follows this
	# same rule, so the artist can land one widget's art at a time and the rest keeps the flat look.
	var clear := _flat(Color(0, 0, 0, 0), 0, Color(0, 0, 0, 0), 0, 9, 5)
	var sel := _accent_bar(0.10)                                       # generated focus/pressed = bar + faint fill
	t.set_stylebox(&"normal", &"Button", _pick(skin.button_normal, clear))
	t.set_stylebox(&"hover", &"Button", _pick(skin.button_hover, _accent_bar(0.0)))  # generated: bar + no fill
	t.set_stylebox(&"pressed", &"Button", _pick(skin.button_pressed, sel))
	t.set_stylebox(&"focus", &"Button", _pick(skin.button_focus, sel.duplicate()))
	t.set_stylebox(&"hover_pressed", &"Button", _pick(skin.button_pressed, sel.duplicate()))
	t.set_stylebox(&"disabled", &"Button", _pick(skin.button_disabled, clear.duplicate()))
	t.set_color(&"font_color", &"Button", skin.text_dim_color)
	t.set_color(&"font_hover_color", &"Button", skin.text_color)
	t.set_color(&"font_pressed_color", &"Button", skin.accent_color)
	t.set_color(&"font_focus_color", &"Button", skin.text_color)
	t.set_color(&"font_hover_pressed_color", &"Button", skin.accent_color)
	t.set_color(&"font_disabled_color", &"Button", skin.disabled_text_color)
	t.set_font_size(&"font_size", &"Button", skin.body_size)

	# CheckButton / CheckBox — skin-drawn toggle art (the _grabber_tex idiom): without these icons the
	# ~14 Accessibility rows wore the stock grey/blue engine switch inside the near-black gold-accent
	# skin. Crisp square pixels match the 0.5-scale aesthetic; colours derive from the skin, so
	# rebuild() re-tints them on a reskin.
	# Artist toggle art wins per slot; a missing disabled variant reuses the enabled art (better than
	# flipping back to the generated switch for one state).
	var tog_on: Texture2D = skin.toggle_on_icon if skin.toggle_on_icon != null else _toggle_tex(true)
	var tog_off: Texture2D = skin.toggle_off_icon if skin.toggle_off_icon != null else _toggle_tex(false)
	var tog_on_dis: Texture2D = skin.toggle_on_disabled_icon
	if tog_on_dis == null:
		tog_on_dis = skin.toggle_on_icon if skin.toggle_on_icon != null else _toggle_tex(true, true)
	var tog_off_dis: Texture2D = skin.toggle_off_disabled_icon
	if tog_off_dis == null:
		tog_off_dis = skin.toggle_off_icon if skin.toggle_off_icon != null else _toggle_tex(false, true)
	for kind in [&"CheckButton", &"CheckBox"]:
		t.set_icon(&"checked", kind, tog_on)
		t.set_icon(&"unchecked", kind, tog_off)
		t.set_icon(&"checked_disabled", kind, tog_on_dis)
		t.set_icon(&"unchecked_disabled", kind, tog_off_dis)

	# Labels --------------------------------------------------------------------
	t.set_color(&"font_color", &"Label", skin.text_color)
	t.set_font_size(&"font_size", &"Label", skin.body_size)

	# LineEdit — flat skin chrome (name entry / character creation). Without these entries the two
	# text fields in the game wore the STOCK engine rounded grey box inside our near-black panels.
	var le_normal := _flat(Color(skin.text_color.r, skin.text_color.g, skin.text_color.b, 0.06), 1, skin.panel_border_color, skin.panel_corner_radius, 6, 4)
	var le_focus := le_normal.duplicate() as StyleBoxFlat
	le_focus.border_color = skin.accent_color
	t.set_stylebox(&"normal", &"LineEdit", _pick(skin.line_edit_normal, le_normal))
	t.set_stylebox(&"focus", &"LineEdit", _pick(skin.line_edit_focus, le_focus))
	t.set_stylebox(&"read_only", &"LineEdit", _pick(skin.line_edit_normal, le_normal.duplicate()))
	t.set_color(&"font_color", &"LineEdit", skin.text_color)
	t.set_color(&"font_placeholder_color", &"LineEdit", skin.text_dim_color)
	t.set_color(&"caret_color", &"LineEdit", skin.accent_color)
	t.set_color(&"selection_color", &"LineEdit", Color(skin.accent_color.r, skin.accent_color.g, skin.accent_color.b, 0.35))
	t.set_font_size(&"font_size", &"LineEdit", skin.body_size)

	# ProgressBar — same thin track/fill language as the sliders (reputation meters). Tint a meter
	# via make_meter(col) / a "fill" stylebox override, never via modulate.
	var pb_bg := _flat(Color(skin.text_color.r, skin.text_color.g, skin.text_color.b, 0.12), 0, Color(0, 0, 0, 0), 1)
	var pb_fill := _flat(skin.accent_color, 0, Color(0, 0, 0, 0), 1)
	t.set_stylebox(&"background", &"ProgressBar", _pick(skin.meter_background, pb_bg))
	t.set_stylebox(&"fill", &"ProgressBar", _pick(skin.meter_fill, pb_fill))
	t.set_font_size(&"font_size", &"ProgressBar", skin.hint_size)

	# Separator (hairline) ------------------------------------------------------
	var sep := _flat(Color(0, 0, 0, 0))
	sep.border_width_top = 1
	sep.border_color = Color(skin.text_color.r, skin.text_color.g, skin.text_color.b, 0.08)
	sep.content_margin_top = 1
	t.set_stylebox(&"separator", &"HSeparator", _pick(skin.separator_style, sep))
	t.set_stylebox(&"separator", &"VSeparator", _pick(skin.separator_style, sep.duplicate()))

	# NO PopupMenu block, ON PURPOSE: no SKINNABLE popup consumer remains. With embed_subwindows OFF (the
	# same project setting the tooltip note up top exists for) any popup is a NATIVE OS window that escapes
	# the retro viewport pipeline (desktop-res glyphs, no PS1 warp) — so the Options dropdowns are in-canvas
	# < value > cyclers (options_menu._option_row) and tooltips are the custom in-viewport tip below. The ONE
	# surviving popup is the music-folder FileDialog (options_menu._open_music_folder_dialog) — deliberately
	# NATIVE (an OS filesystem picker) and deliberately outside this theme. (Editor addons build their own
	# dropdowns but never use MenuStyle, so nothing consumes such a block.)

	# Sliders — thin track, accent fill ----------------------------------------
	var track := _flat(Color(skin.text_color.r, skin.text_color.g, skin.text_color.b, 0.12), 0, Color(0, 0, 0, 0), 1)
	track.content_margin_top = 1
	track.content_margin_bottom = 1
	t.set_stylebox(&"slider", &"HSlider", _pick(skin.slider_track, track))
	var fill := _flat(skin.accent_color, 0, Color(0, 0, 0, 0), 1)
	fill.content_margin_top = 1
	fill.content_margin_bottom = 1
	t.set_stylebox(&"grabber_area", &"HSlider", _pick(skin.slider_fill, fill))
	t.set_stylebox(&"grabber_area_highlight", &"HSlider", _pick(skin.slider_fill, fill.duplicate()))
	var thumb: Texture2D = skin.slider_grabber if skin.slider_grabber != null else _grabber_tex()
	t.set_icon(&"grabber", &"HSlider", thumb)
	t.set_icon(&"grabber_highlight", &"HSlider", thumb)

	# Scrollbars — minimal ------------------------------------------------------
	var sb_bg := _flat(Color(skin.text_color.r, skin.text_color.g, skin.text_color.b, 0.05), 0, Color(0, 0, 0, 0), 2)
	var sb_grab := _flat(Color(skin.text_color.r, skin.text_color.g, skin.text_color.b, 0.22), 0, Color(0, 0, 0, 0), 2)
	for kind in [&"VScrollBar", &"HScrollBar"]:
		t.set_stylebox(&"scroll", kind, _pick(skin.scrollbar_track, sb_bg.duplicate()))
		t.set_stylebox(&"grabber", kind, _pick(skin.scrollbar_grabber, sb_grab.duplicate()))
		t.set_stylebox(&"grabber_highlight", kind, _pick(skin.scrollbar_grabber, sb_grab.duplicate()))
		t.set_stylebox(&"grabber_pressed", kind, _pick(skin.scrollbar_grabber, sb_grab.duplicate()))

	# Tabs (options menu) — text-forward, accent underline on the active tab ----
	var tab_clear := _flat(Color(0, 0, 0, 0), 0, Color(0, 0, 0, 0), 0, 8, 4)
	var tab_sel := _flat(Color(0, 0, 0, 0), 0, Color(0, 0, 0, 0), 0, 8, 4)
	tab_sel.border_width_bottom = 2
	tab_sel.border_color = skin.accent_color
	t.set_stylebox(&"tab_selected", &"TabContainer", _pick(skin.tab_selected, tab_sel))
	t.set_stylebox(&"tab_unselected", &"TabContainer", _pick(skin.tab_unselected, tab_clear))
	t.set_stylebox(&"tab_hovered", &"TabContainer", _pick(skin.tab_hovered, tab_clear.duplicate()))
	t.set_stylebox(&"panel", &"TabContainer", _flat(Color(0, 0, 0, 0)))
	t.set_stylebox(&"tabbar_background", &"TabContainer", _flat(Color(0, 0, 0, 0)))
	t.set_color(&"font_selected_color", &"TabContainer", skin.text_color)
	t.set_color(&"font_unselected_color", &"TabContainer", skin.text_dim_color)
	t.set_color(&"font_hovered_color", &"TabContainer", skin.text_color)

	# Tooltips — themed dark panel so hover breakdowns match the menus -----------
	var tip := _flat(Color(0.04, 0.04, 0.055, 0.97), 1, skin.panel_border_color, skin.panel_corner_radius, 8, 6)
	t.set_stylebox(&"panel", &"TooltipPanel", _pick(skin.tooltip_panel, tip))
	t.set_color(&"font_color", &"TooltipLabel", skin.text_color)
	t.set_font_size(&"font_size", &"TooltipLabel", skin.hint_size)

	# CheckButton / CheckBox get their toggle icons beside the Button block.
	return t

## A tiny accent-coloured slider thumb (a 3x10 bar) generated in code so no thumb asset is needed.
func _grabber_tex() -> ImageTexture:
	var img := Image.create(3, 10, false, Image.FORMAT_RGBA8)
	img.fill(skin.accent_color)
	return ImageTexture.create_from_image(img)

## A tiny skin-tinted toggle switch for CheckButton/CheckBox (a 20x10 track + 8px square knob, knob
## left = off / right = on) generated in code like _grabber_tex, so the toggles need no art assets.
func _toggle_tex(on: bool, dim: bool = false) -> ImageTexture:
	var img := Image.create(20, 10, false, Image.FORMAT_RGBA8)
	var a: Color = skin.accent_color
	var tx: Color = skin.text_color
	img.fill(Color(a.r, a.g, a.b, 0.35) if on else Color(tx.r, tx.g, tx.b, 0.10))
	img.fill_rect(Rect2i(11 if on else 1, 1, 8, 8), skin.disabled_text_color if dim else (skin.accent_color if on else skin.text_dim_color))
	return ImageTexture.create_from_image(img)

## Bare wrapper so a non-Control background scene still fills the screen.
func _wrap_fullrect(node: Node) -> Control:
	var c := Control.new()
	c.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	c.add_child(node)
	return c
