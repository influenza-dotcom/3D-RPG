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
## The IN-GAME HUD's artist skin (the MenuSkin twin for gameplay-time paint: combat indicators,
## compass/minimap tints, crosshair art, HUD label chrome). Consumers read MenuStyle.hud.<field>;
## swap it at runtime via set_hud_skin. Gameplay-TUNING numbers stay on GameSettings.hud — this is
## look only (see hud_skin.gd's scope contract). Preloaded BY PATH + kept untyped so THIS autoload
## parses even before the editor registers the new HudSkin class_name in its global cache (the ui.gd
## STAMINA_RING_SCRIPT idiom — "Could not find type X" cascade guard; typing it broke every headless
## run until the editor's next scan).
const HUD_SKIN_SCRIPT := preload("res://scripts/ui/hud_skin.gd")
var hud: Resource = preload("res://resources/ui/hud_skin.tres")
var theme: Theme
var _title_font: Font

# Custom in-viewport tooltip — a Control in our OWN CanvasLayer so it renders INSIDE the game viewport
# (in RETRO pixelated like the game; in HIGH FIDELITY native-crisp — either way themed and in-frame),
# unlike Godot's native tooltip Popups which draw as separate desktop-res popups.
# NOTE the real UI canvas is 792x444 at 16:9 (base 396x216 doubled by window/stretch/scale 0.5, then
# aspect="expand" stretches it per monitor shape) — NOT the 396x216 the project settings suggest. That
# 792x444 LOGICAL canvas holds in BOTH presentation modes (HIGH FIDELITY keeps Control layout on it via
# canvas_items' size-2d override); only RETRO nearest-upscales it to the window.
# Menus must lay out against ~792x444 and survive 792x432..792x495+ (16:10, ultrawide).
var _tip_layer: CanvasLayer
var _tip_panel: PanelContainer
var _tip_label: Label
var _tip_target: Control = null

# UI sound players (PROCESS_MODE_ALWAYS so they play through a tree-pause — dialogue's, or FreezeFrame's on
# death; the menus themselves are real-time). Every button under a menu root
# auto-plays the skin's hover/click sounds — wired by the node_added hook, no per-button code.
var _hover_player: AudioStreamPlayer
var _click_player: AudioStreamPlayer

func _ready() -> void:
	# Process through a paused tree: a station screen opened FROM a conversation runs under dialogue's pause
	# (the screens themselves are real-time), and _process is what makes the hover tooltip FOLLOW the cursor —
	# without this it freezes at a stale spot in exactly those menus.
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
	if hud == null:
		hud = HUD_SKIN_SCRIPT.new()  # the skin's null-fallback twin: a bare skin is the shipped defaults
	_title_font = _make_title_font()
	theme = _build_theme()
	_style_tip()  # no-op until the tip is built; restyles it on a runtime skin swap

## Swap to a different artist skin at runtime and rebuild everything.
func set_skin(new_skin: MenuSkin) -> void:
	if new_skin == null:
		return
	skin = new_skin
	rebuild()

## Swap to a different HUD skin at runtime (the set_skin twin). The HUD's _draw consumers read
## MenuStyle.hud live each frame, so no Theme rebuild is needed — rebuild() runs anyway for the
## null-fallback and so any future theme-coupled HUD chrome restyles on the same seam.
func set_hud_skin(new_hud: Resource) -> void:
	# Untyped parameter (cache guard, see `hud` above) — so the type check is by script identity.
	if new_hud == null or new_hud.get_script() != HUD_SKIN_SCRIPT:
		return
	hud = new_hud
	rebuild()

# --- palette accessors (menus read MenuStyle.accent() etc. so colours stay in one place) ---
func accent() -> Color: return skin.accent_color
func gold() -> Color: return skin.gold_color
func text_color() -> Color: return skin.text_color
func dim_color() -> Color: return skin.text_dim_color
func danger() -> Color: return skin.danger_color

## The tint a WALLET readout wears for `amount`: gold while solvent, danger the moment the balance is
## NEGATIVE. Implants are bought on credit (the run can start in debt — implant_choice.gd), so every
## menu wallet label routes its colour through this ONE seam (shop / level-up / chip-install headers,
## the implant tally); the HUD's readout mirrors the same rule via HudSettings.money_debt_color.
func wallet_color(amount: float) -> Color: return gold() if amount >= 0.0 else danger()

## Set `root.theme` to the menu theme so every child inherits the look, and MARK the subtree so every
## button under it auto-gets the hover/click sounds. Call once on a menu's root Control.
func apply(root: Control) -> void:
	if is_instance_valid(root):
		root.theme = theme
		root.set_meta(&"_menu_root", true)
		_wire_existing_buttons(root)

## Sound-wire buttons that are ALREADY under `root` when apply() runs, and pin every TabContainer's minimum
## (see _pin_tab_minimum). The node_added hook below only wires a button whose ancestry carries _menu_root at
## the moment it ENTERS the tree — true for every runtime-built row, but an AUTHORED-SCENE screen's buttons
## (heal/respec/name-entry Confirm/Cancel) enter the tree WITH the autoload scene, BEFORE its _ready calls
## apply(), so the hook saw them meta-less and skipped them (silent buttons). One sweep at apply() time closes
## the gap; _wire_button's _snd_wired meta keeps it idempotent with the hook for anything built later.
func _wire_existing_buttons(node: Node) -> void:
	if node is BaseButton:
		_wire_button(node as BaseButton)
	elif node is TabContainer:
		_pin_tab_minimum(node as TabContainer)
	for c in node.get_children():
		_wire_existing_buttons(c)

## MENUS DON'T RESIZE WHEN YOU CHANGE TABS. A TabContainer's minimum size defaults to the CURRENT page's
## minimum (use_hidden_tabs_for_min_size = false), so pages of different sizes hand the container a different
## minimum per tab — and a minimum that beats the panel's anchor band makes Godot GROW the panel (it never
## clips or scrolls), so the card swells and re-centres mid-click. Pinning the flag ON makes the minimum the
## MAX over all pages: one size, whichever tab is up. This is the structural half of the rule; the other half
## is that the biggest page must still FIT (tests/test_menu_layout_stability.gd pins both). Applied here, at
## the one seam every menu already routes through, so a new tabbed screen inherits it without opting in.
func _pin_tab_minimum(tabs: TabContainer) -> void:
	tabs.use_hidden_tabs_for_min_size = true

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

## Give an EMPTY-TEXT row Button the height its own one-line caption WOULD get. The list screens build
## multi-column rows as an empty Button carrying full-rect child Labels inset by the stylebox content
## margins (implant_choice/chip_install _make_row) — but an empty text buffer contributes ZERO height to
## Button.get_minimum_size() (measured under the shipped art skin: 12px = the v-margins alone, vs 28px with
## a caption), so the button's rect ends up half a line ABOVE the glyphs its labels draw: the hover/pressed/
## focus accent bar (the menu "cursor"), the faint selection fill AND the click hitbox all misalign with the
## visible text. Pinning custom_minimum_size.y to a PROBE captioned Button's own get_minimum_size() under
## this theme restores the exact caption-height box (exact by construction — hand-summed font metrics
## undershot the engine's Button layout, see test_menu_row_button), so the selection art wraps the glyphs
## again. Call it on EVERY empty-text Button whose content lives in child Controls; a Button with its own
## `text` never needs it (and a row button also wants style_list_row — see below).
func size_row_button(btn: Button) -> Button:
	var probe := Button.new()
	probe.theme = theme
	# Any single glyph works — it's the line box being measured, never a shown string (the probe is freed
	# unseen). Composed in a local per the text-debt rule for non-prose paints: geometry, not copy.
	var probe_caption := "X"
	probe.text = probe_caption
	# The probe must be IN the tree for its `.theme` to resolve: theme-owner assignment happens on tree
	# entry, so an OFF-tree probe silently measures the ThemeDB fallback theme instead of this skin (the
	# fallback's bigger default font over-reserved by 1-3px and only covered the real box by luck — caught
	# during the 08-12 art landing). Parented here for one synchronous measure; freed before it can render.
	add_child(probe)
	btn.custom_minimum_size.y = ceilf(probe.get_minimum_size().y)
	remove_child(probe)
	probe.free()
	return btn

## Pin a LIST-ROW Button (an empty-text row carrying its own child Labels — the chip-install /
## implant-choice / implants-tab / level-up idiom) to the generated row language: transparent rest,
## accent-bar selection, in EVERY state. The tab-strip rule applied to rows: artist button art in the
## theme is push-button language for CAPTIONED buttons wearing the skin's button inks — a row's child
## Labels keep their own light inks (text/gold/accent on the dark panel), so an opaque art body under
## them buries the text. Every empty-text row Button must route through this beside size_row_button.
func style_list_row(btn: Button) -> Button:
	btn.add_theme_stylebox_override(&"normal", _flat(Color(0, 0, 0, 0), 0, Color(0, 0, 0, 0), 0, 9, 5))
	btn.add_theme_stylebox_override(&"hover", _accent_bar(0.0))
	btn.add_theme_stylebox_override(&"pressed", _accent_bar(0.10))
	btn.add_theme_stylebox_override(&"hover_pressed", _accent_bar(0.10))
	# The focus override must stay translucent — Godot draws `focus` as an OVERLAY on the state box.
	btn.add_theme_stylebox_override(&"focus", _accent_bar(0.10))
	btn.add_theme_stylebox_override(&"disabled", _flat(Color(0, 0, 0, 0), 0, Color(0, 0, 0, 0), 0, 9, 5))
	return btn

# --- adopt helpers (authored-scene screens) --------------------------------------------------------
# The make_* factories above BUILD nodes for the procedural screens; these style nodes a .tscn already
# AUTHORS. A scene-based screen (scenes/ui/*.tscn — see AUTHORING_GUIDE "Menus are scenes") lays out its
# chrome in the editor, then its script calls these in _ready so the skin-driven look (colours, fonts,
# width pins) still comes from menu_skin.tres — the scene owns STRUCTURE, the skin owns LOOK. Each mirrors
# its make_* twin; keep the pairs in sync when a skin knob is added.

## Adopt an authored full-screen dim (the make_dim twin): skin colour + click-eating.
func style_dim(cr: ColorRect) -> void:
	cr.color = skin.backdrop_dim
	cr.mouse_filter = Control.MOUSE_FILTER_STOP

## Adopt an authored dialog-card content VBox (the make_dialog twin): pin it to skin.dialog_width and
## apply the shared separation. The scene supplies CenterContainer > PanelContainer > this VBox; the same
## fixed-width discipline applies — cap_label/cap_button the children, autowrap status lines.
func style_dialog_card(vbox: VBoxContainer, extra_sep: int = 0) -> void:
	vbox.custom_minimum_size.x = skin.dialog_width
	vbox.add_theme_constant_override("separation", skin.content_separation + extra_sep)

## The GENERATED flat panel (skin.panel_color + border + panel_content_margin), built regardless of any
## artist panel_style art. For surfaces the big screen-card art cannot serve: COMPACT utility cards, where
## the art's heavy torn borders (~76px of a ~106px popup's height) drown the content, and solid legibility
## backings (the dialogue choice list). Everything else wears the theme panel.
func make_plain_panel_style() -> StyleBoxFlat:
	var m: int = skin.panel_content_margin
	return _flat(skin.panel_color, skin.panel_border_width, skin.panel_border_color, skin.panel_corner_radius, m, m)

## The DIALOGUE box's own background art (skin.dialogue_panel), or NULL when the skin leaves that slot
## empty OR gates it off (skin.dialogue_panel_enabled — the shipped skin keeps the artist's art in the
## slot but ships the box-LESS look, 2026-08-24). Null is meaningful here — unlike every other art slot
## there is no generated fallback to derive, because "no art" is a real authored look for this surface
## (outlined text straight over the 3D world), so DialogueView reads the null and wears a StyleBoxEmpty
## instead. Duplicated per the _pick rule: the caller overrides a Control with what it's handed, and a
## shared .tres sub-resource must never be mutated.
func make_dialogue_panel_style() -> StyleBox:
	if skin.dialogue_panel == null or not skin.dialogue_panel_enabled:
		return null
	return skin.dialogue_panel.duplicate()

## The dialogue RESPONSE ROW's rest-state bed (skin.dialogue_choice_normal, else generated): a translucent
## near-black plate behind each choice row. Rest-state deliberately — the dialogue camera centres + zooms
## the LIT speaker into the column's region, so bare outlined text would sit on the brightest surface in
## the frame. The 3px left border is RESERVED (transparent) here so hover's gold rule never shifts the text.
## `gutter_px` inset on the left makes room for the row's number/caret label (DialogueView paints it there).
func make_dialogue_choice_normal(gutter_px: int = 0) -> StyleBox:
	if skin.dialogue_choice_normal != null:
		return skin.dialogue_choice_normal.duplicate()
	var sb := _dialogue_choice_bed(Color(0.02, 0.03, 0.05, 0.45), Color(0, 0, 0, 0), gutter_px)
	return sb

## The response row's hover/selected/pressed bed: the rest bed raised, plus the 3px accent-gold left rule.
func make_dialogue_choice_hover(gutter_px: int = 0) -> StyleBox:
	if skin.dialogue_choice_hover != null:
		return skin.dialogue_choice_hover.duplicate()
	return _dialogue_choice_bed(Color(0.02, 0.03, 0.05, 0.66), gold(), gutter_px)

## Shared builder for the two generated row beds above — one shape so rest and hover can never drift
## geometrically (a bed that changes size on hover reads as a broken control, not a highlight).
func _dialogue_choice_bed(bg: Color, rule: Color, gutter_px: int) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_width_left = 3
	sb.border_color = rule
	sb.content_margin_left = 10.0 + float(gutter_px)
	sb.content_margin_right = 10.0
	sb.content_margin_top = 4.0
	sb.content_margin_bottom = 4.0
	return sb

## Adopt a COMPACT confirm card (title + one button row — the quit-confirm / TOS-nag / overwrite-confirm
## popups): style_dialog_card's width pin PLUS the plain generated panel on the card's PanelContainer
## parent. These cards stand ~105-140px — at that scale the artist screen-card art is nearly all torn
## border, so utility popups keep the plain look by design (and stay visually distinct from real screens).
## Structural contract: `card` is the direct VBox child of the card's PanelContainer (the authored
## Root/…/Panel>Card shape all three adopters share).
func style_compact_card(card: VBoxContainer, extra_sep: int = 0) -> void:
	var panel := card.get_parent() as PanelContainer
	if panel != null:
		panel.add_theme_stylebox_override(&"panel", make_plain_panel_style())
	style_dialog_card(card, extra_sep)

## Adopt an authored title Label (the make_title twin): title font/size/colour + ellipsis. Does NOT touch
## the text — the screen sets it (through title_text) from PlayerText, never the scene (l10n owns strings).
func style_title(l: Label) -> void:
	l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	l.add_theme_font_override(&"font", _title_font)
	l.add_theme_font_size_override(&"font_size", skin.title_size)
	l.add_theme_color_override(&"font_color", skin.text_color)

## Adopt an authored hint Label (the make_hint twin): dim wrap-friendly footnote styling.
func style_hint(l: Label) -> void:
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_font_size_override(&"font_size", skin.hint_size)
	l.add_theme_color_override(&"font_color", skin.text_dim_color)

## Adopt an authored button row (spacing from the skin — the button_row_separation every dialog shares).
func style_button_row(row: BoxContainer) -> void:
	row.add_theme_constant_override("separation", skin.button_row_separation)

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
## LEFT accent bar (list-row language). Margins (9,5) match the strip's other states (all three helpers
## use them) so captions don't shift 1px between states.
func make_hover_tab_style() -> StyleBox:
	if skin.tab_hovered != null:
		return skin.tab_hovered.duplicate()
	var sb := _flat(Color(0, 0, 0, 0), 0, Color(0, 0, 0, 0), 0, 9, 5)
	sb.border_width_bottom = 2
	var a: Color = skin.accent_color
	sb.border_color = Color(a.r, a.g, a.b, 0.35)
	return sb

## An inactive strip tab at REST — the third sibling of the two helpers above: the skin's tab_unselected
## art when set, else transparent. Exists so the strip's rest state never falls through to the theme
## Button `normal` box: that was invisible while both defaulted to transparent, but the moment button art
## lands (the parchment frames) an un-overridden strip tab would wear list-row BUTTON chrome mid-strip.
func make_inactive_tab_style() -> StyleBox:
	if skin.tab_unselected != null:
		return skin.tab_unselected.duplicate()
	return _flat(Color(0, 0, 0, 0), 0, Color(0, 0, 0, 0), 0, 9, 5)

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

# --- menu sounds ------------------------------------------------------------------------------------
# The menu's whole audio vocabulary lives here: MenuSkin owns WHICH clip each event plays (and how loud),
# this block owns WHEN and on WHICH voice. Screens never preload a clip or build a player — they call the
# play_* seams below. Three invariants hold the system together:
#
#  1. EVERY player is PROCESS_MODE_ALWAYS and on the "sfx" bus. The station screens are real-time now, but a
#     TREE-PAUSE still happens around them — DialogueManager's (a Trade / Heal / Install screen opened out of a
#     conversation runs under it) and FreezeFrame's on death; a play() on an INHERIT-mode player under a paused
#     tree is silently DROPPED. The "sfx" bus is what makes the SFX volume slider apply — a bare player
#     lands on Master and ignores it. (This is also why AudioManager.play_2d_sfx is unusable here: it
#     parents to the root at the default process mode, so it goes silent in exactly the menus that matter.)
#  2. NOTHING here may fire from a screen's _ready(). Every screen autoload builds at boot and a boot-time
#     open sting would play under the splash. Be honest about what enforces this: MenuStyle is autoload #6,
#     ahead of every screen scene, so the pool ALREADY EXISTS by the time a screen's _ready runs — the
#     is_empty() guard below does NOT cover that case, and boot silence is held by DISCIPLINE, not by
#     construction. What the guard really covers is an off-tree instance: a bare load(...).new() + rebuild()
#     with no _ready (tests/test_menu_skin_art.gd's idiom) and any `-s` tool script. That is also why audio
#     construction must stay in _build_sound() and never move into rebuild(), which those paths DO call.
#  3. Timing uses Time.get_ticks_msec(), never a delta — a paused tree freezes delta, and these throttles
#     have to keep working under a pause (a dialogue-hosted station screen, FreezeFrame on death).

## Semantic voices for open/back/tab/commit/step. FOUR because the realistic worst case overlaps three:
## the 1.7s open sting still ringing while the player tabs (swipe) and then commits — one spare keeps the
## long sting from being stolen mid-ring. Hover, click and DENIED deliberately keep their OWN single voices
## (_hover_player/_click_player/_denied_player): self-cutting is the DESIRED behaviour for a repeated blip,
## and the first two member names are pinned by tests/test_options_menu.gd.
var _ui_players: Array[AudioStreamPlayer] = []
var _ui_next: int = 0  ## round-robin cursor for the steal-oldest fallback when all four are busy

## The refusal voice. Its OWN player rather than a pool slot for one reason: spam-clicking a button the game
## keeps refusing (Buy with an empty wallet) would otherwise stack four overlapping buzzes and then start
## stealing voices from the open sting. A denial is the sound of NOTHING happening — one at a time, always
## restarting, never piling up. It is also the only voice that runs off 1.0 pitch (skin.denied_pitch_scale).
var _denied_player: AudioStreamPlayer

## Throttle state (see _on_button_hovered / play_step). Instance IDs, never node refs — a list screen frees
## its rows constantly and a stale reference to a freed Button is a crash waiting to happen.
var _hover_last_ms: int = 0
var _hover_last_id: int = 0
var _step_last_ms: int = 0
var _click_started_ms: int = -100000  ## when the generic click voice last started (see SAME_PRESS_MS)

## How long after a generic click a semantic cue is still considered part of the SAME press. A press that
## opens/closes/commits fires the auto-wired click first and its meaningful cue a hair later, in the same
## frame — so within this window the specific cue WINS and the click is cut (see play_ui). Two frames at
## 60fps, generous enough for a slow frame and far too short to swallow a genuine second press.
const SAME_PRESS_MS: int = 40

## Re-hover gate for the SAME button. Distinct from skin.hover_min_interval (the designer's sweep-feel
## knob): this is a mechanism guard for rows that are REBUILT under a stationary cursor — a repainted list
## re-fires mouse_entered without the player having moved a pixel, which blips on its own.
const SAME_BUTTON_HOVER_MS: int = 250

var _quiet: bool = false       ## latch: every play_* is a no-op (the death/quickload close-everything sweep)
var _quiet_backs: int = 0      ## pending "eat one back cue" tokens (a commit that closes its own screen)

func _build_sound() -> void:
	_hover_player = AudioStreamPlayer.new()
	_hover_player.process_mode = Node.PROCESS_MODE_ALWAYS  # play even while dialogue (a Trade/Heal screen opened mid-conversation) or FreezeFrame holds the tree
	_hover_player.bus = &"sfx"
	add_child(_hover_player)
	_click_player = AudioStreamPlayer.new()
	_click_player.process_mode = Node.PROCESS_MODE_ALWAYS
	_click_player.bus = &"sfx"
	add_child(_click_player)
	_denied_player = AudioStreamPlayer.new()
	_denied_player.process_mode = Node.PROCESS_MODE_ALWAYS
	_denied_player.bus = &"sfx"
	add_child(_denied_player)
	_ui_players.clear()
	for _i in 4:
		var p := AudioStreamPlayer.new()
		p.process_mode = Node.PROCESS_MODE_ALWAYS
		p.bus = &"sfx"
		add_child(p)
		_ui_players.append(p)

# --- play seams (the API every screen calls) ----------------------------------------------------------

## Play a semantic UI cue. `kind`: &"open" &"back" &"tab" &"select" &"commit" &"denied" &"step_left"
## &"step_right".
## An unknown kind, an unassigned skin slot, or a pool that doesn't exist yet (off-tree / pre-_ready) are
## all SILENT NO-OPS, never errors — so a screen can call this unconditionally.
func play_ui(kind: StringName) -> void:
	if _ui_players.is_empty():
		return  # pre-_ready or off-tree (see invariant 2) — nothing to play on
	if kind == &"back" and _quiet_backs > 0:
		_quiet_backs -= 1  # consumed by quiet_next_back(); see its note
		return
	if _quiet:
		return
	var stream: AudioStream = _stream_for(kind)
	if stream == null:
		return
	# A SEMANTIC CUE SUPERSEDES THE GENERIC CLICK OF THE SAME PRESS. Every standalone modal's Close button
	# (and any button whose handler opens, closes or commits) fires the auto-wired click a hair before its
	# real cue — two sounds for one action. Muting each such button by hand across twenty screens is exactly
	# the kind of list that drifts the moment someone adds a screen, so the rule lives here instead: if the
	# click voice started within this same press, cut it and let the specific cue speak alone.
	# NOTE play_select() calls _play_click directly rather than routing here, so it can never cut itself.
	if _click_player != null and _click_player.playing and Time.get_ticks_msec() - _click_started_ms <= SAME_PRESS_MS:
		_click_player.stop()
	# A denial speaks on its own dedicated, self-cutting voice (see _denied_player); everything else takes a
	# pool slot. pitch_scale is written on EVERY play, never only for the pitched cue — pool voices are reused
	# round-robin, so a detune left behind by a denial would silently transpose the next open sting.
	var p: AudioStreamPlayer = _denied_player if kind == &"denied" else _acquire_ui_player()
	if p == null:
		return
	p.stream = stream
	p.volume_db = skin.ui_sound_volume_db + _volume_for(kind)
	p.pitch_scale = _pitch_for(kind)
	p.play()

## A menu came up COLD. NEVER call this for a tab/page swap inside an already-open group — that's play_tab.
func play_open() -> void: play_ui(&"open")

## Back / close / cancel: the last menu of a group closing, an Esc, a dismissed confirm.
func play_back() -> void: play_ui(&"back")

## The view swapped SIDEWAYS: tab strip, tab bar, sort cycle, payment-rail flip.
func play_tab() -> void: play_ui(&"tab")

## An ordinary confirm on a surface that is NOT a BaseButton (the inventory/loot/shop grid tiles are plain
## Controls, so the auto-wired click never reaches them). Shares the click voice — same clip, same meaning.
func play_select() -> void:
	if _quiet or _click_player == null:
		return
	_play_click()

## A HEAVY commit: money spent, a level taken, a save written, a new run stamped.
func play_commit() -> void: play_ui(&"commit")

## The game REFUSED the action: can't afford it, out of stock, no room in the bag, nothing to withdraw, an
## illegal move, a stat already at its floor. THE COMPANION TO EVERY GATED CUE — the older screens gated
## their commit on a success bool and then said nothing at all on the false branch, which is why a failed
## purchase used to be indistinguishable from a dead button. Pair them: `if act(): play_commit() else:
## play_denied()`. Never for an action the game HONOURED (putting a weapon away, dismissing a confirm) —
## that is play_back.
func play_denied() -> void: play_ui(&"denied")

## Hover blip for a surface that is NOT a BaseButton — a grid tile, a map pin, a custom-drawn row. Buttons
## get this for free from the node_added hook; anything that paints its own hover state has to say so, and
## before this existed the whole Tetris-grid family (backpack / loot / shop) was the one place in the UI
## where moving the cursor over a live target made no sound at all.
##
## `id` identifies WHICH surface is being hovered, so the same-target re-hover gate (SAME_BUTTON_HOVER_MS)
## works for a list that REPAINTS under a stationary cursor — pass something stable per target and unique
## across concurrent views (the grids pass their view's instance id mixed with the stack key; two side-by-side
## loot columns must not share an id or crossing between them eats a blip). 0 = unkeyed: throttled by
## hover_min_interval alone.
func play_hover(id: int = 0) -> void:
	if _quiet or _hover_player == null:
		return
	var now := Time.get_ticks_msec()
	if now - _hover_last_ms < int(skin.hover_min_interval * 1000.0):
		return
	if id != 0 and id == _hover_last_id and now - _hover_last_ms < SAME_BUTTON_HOVER_MS:
		return
	_hover_last_ms = now
	_hover_last_id = id
	_play_hover()

## A value stepped: dir > 0 = up/right, dir < 0 = down/left, 0 = no-op. Throttled by
## skin.step_min_interval, so EVERY entry point (mouse arrows, keyboard auto-repeat, slider drags)
## inherits the same anti-machine-gun rule without repeating it per screen.
func play_step(dir: int) -> void:
	if dir == 0 or _quiet or _ui_players.is_empty():
		return
	var now := Time.get_ticks_msec()
	if now - _step_last_ms < int(skin.step_min_interval * 1000.0):
		return
	_step_last_ms = now
	play_ui(&"step_right" if dir > 0 else &"step_left")

## Tick a slider toward `value`, quantised so a FULL sweep produces ~skin.slider_tick_count ticks whatever
## the slider's own step is (Max FPS has hundreds of steps, an accessibility 0..1 slider has a handful —
## without this one buzzes and the other barely speaks). Direction comes from the previous value stashed on
## the slider itself, since Range.value_changed hands over only the new value.
##
## The FIRST call for a given slider is deliberately SILENT (it only seeds the stash). Menus write .value
## programmatically — loading settings, Revert, rebuilding a tab — and those writes must not sound like the
## player dragged something. Losing the first tick of a real drag is imperceptible; a tick storm on every
## Apply is not.
func play_slider_step(slider: Range, value: float) -> void:
	if not is_instance_valid(slider) or _quiet or _ui_players.is_empty():
		return
	var seeded: bool = slider.has_meta(&"_snd_last")
	var prev: float = float(slider.get_meta(&"_snd_last", value))
	slider.set_meta(&"_snd_last", value)
	if not seeded:
		return
	var span: float = slider.max_value - slider.min_value
	if span <= 0.0:
		return
	var bucket: float = maxf(slider.step, span / float(maxi(1, skin.slider_tick_count)))
	if bucket <= 0.0:
		return
	if floori((value - slider.min_value) / bucket) == floori((prev - slider.min_value) / bucket):
		return  # still inside the same bucket — not a tick yet
	play_step(1 if value > prev else -1)

## Give ONE button a semantic cue INSTEAD of the generic click (hover is untouched). `kind` = &"" MUTES the
## click entirely, for a button whose ENCLOSING seam owns the sound (the player-menu tab strip, whose cue
## comes from PlayerMenus.enter so a switch sounds once rather than click+swipe).
##
## Order-free and idempotent by design: an authored-scene button is already click-wired by apply()'s sweep
## before its screen's _ready runs, while a runtime-built row is wired by the node_added hook AFTER
## construction. This disconnects an already-connected click, and _wire_button skips buttons carrying the
## meta — so it is correct whichever ran first, and calling it again just re-points the kind.
## THE ONLY sanctioned way to put a semantic sound on a BaseButton — never connect a play_* by hand.
func set_button_sound(btn: BaseButton, kind: StringName) -> void:
	if not is_instance_valid(btn):
		return
	btn.set_meta(&"_snd_semantic", kind)
	if btn.pressed.is_connected(_play_click):
		btn.pressed.disconnect(_play_click)
	if not btn.has_meta(&"_snd_semantic_wired"):
		btn.set_meta(&"_snd_semantic_wired", true)
		btn.pressed.connect(_on_semantic_pressed.bind(btn))

## Latch every cue to a no-op. InputManager.close_all_modals closes up to 17 screens in one loop (player
## death, quickload) — without this, dying fires a wall of back cues at once.
## ALWAYS pair the on/off in the same function, so an early return can't strand the UI mute.
func set_quiet(on: bool) -> void:
	_quiet = on

## Eat exactly ONE upcoming back cue. For a commit that immediately closes its own screen (respec confirm,
## a save/load that reloads, pickpocket-caught) — the commit cue is the one that should be heard, and the
## close's back cue would step on it a frame later.
func quiet_next_back() -> void:
	_quiet_backs += 1

# --- internals: wiring + voices ------------------------------------------------------------------------

## Every node added anywhere: if it's a button inside a menu root, wire its hover/click sounds; if it's a
## TabContainer, pin its minimum (one size for every page).
## NOTE: this is a tree-global SceneTree.node_added listener, so it fires for EVERY node spawned anywhere
## (projectiles, VFX, NPCs). The leading two class checks early-out keep it ~free for that common case;
## only a button or a tab block walks ancestors. Kept global on purpose — menu chrome is built lazily under
## many menu roots and there's no single parent to scope a local signal to.
## The listener COUNT is a pinned budget (tests/test_global_node_added_listeners.gd allows exactly two,
## star_sky + this) — extend this hook, never add a third global listener.
func _on_node_added(node: Node) -> void:
	# Same shape for the two things a menu subtree gets for free: buttons get their voice, tab blocks get
	# their one-size-for-every-page minimum (see _pin_tab_minimum — a screen that BUILDS its TabContainer
	# after apply() would otherwise miss the pin and resize its card on a tab click).
	var is_btn := node is BaseButton
	if not is_btn and not (node is TabContainer):
		return
	var p: Node = node
	while p != null:
		if p.has_meta(&"_menu_root"):
			if is_btn:
				_wire_button(node as BaseButton)
			else:
				_pin_tab_minimum(node as TabContainer)
			return
		p = p.get_parent()

func _wire_button(btn: BaseButton) -> void:
	if btn.has_meta(&"_snd_wired"):
		return
	btn.set_meta(&"_snd_wired", true)
	btn.mouse_entered.connect(_on_button_hovered.bind(btn))  # bound-method Callable (never a capturing lambda)
	if btn.has_meta(&"_snd_semantic"):
		return  # set_button_sound already gave this button its own cue — never stack the generic click on top
	btn.pressed.connect(_play_click)  # a disabled button can't be pressed, so it never click-sounds

## Hover sound only while the button can actually respond — a DISABLED button (the greyed Apply, the
## active tab) still fires mouse_entered, and a blip over dead chrome reads as a broken control. That
## disabled check is the ONLY thing this adds over the public play_hover seam (which owns both throttles):
## a custom-drawn surface has no `disabled` to consult, so it decides for itself whether the target is live.
func _on_button_hovered(btn: BaseButton) -> void:
	if not is_instance_valid(btn) or btn.disabled:
		return
	play_hover(btn.get_instance_id())  # the throttles live there, shared with the non-Button surfaces

## Fired by a button that set_button_sound gave its own cue. The kind is read from the meta at PRESS time,
## so re-pointing a button's cue later just works (and &"" resolves to no stream = muted).
func _on_semantic_pressed(btn: BaseButton) -> void:
	if not is_instance_valid(btn):
		return
	play_ui(StringName(btn.get_meta(&"_snd_semantic", &"")))

## First idle voice, else steal the oldest claimed one (round-robin). Overlap is normal — a step tick can
## land while the previous one still rings — so stealing is the graceful degrade, not an error.
func _acquire_ui_player() -> AudioStreamPlayer:
	for p in _ui_players:
		if not p.playing:
			return p
	var oldest := _ui_players[_ui_next]
	_ui_next = (_ui_next + 1) % _ui_players.size()
	return oldest

## The skin slot a cue kind maps to. Unknown kinds (including &"", the muted marker) return null = silent.
##
## &"denied" is the ONE kind with a DERIVED fallback: an unassigned denied_sound resolves to back_sound,
## which _pitch_for then detunes. That is deliberate policy, not a shortcut — a refusal cue that only exists
## once an artist ships a ninth clip is a cue nobody wires, and "the action was refused" is the single most
## common thing the menus needed to say and couldn't. Every OTHER slot stays honestly silent when null, so
## the skin can still land one clip at a time.
func _stream_for(kind: StringName) -> AudioStream:
	match kind:
		&"open": return skin.open_sound
		&"back": return skin.back_sound
		&"tab": return skin.tab_sound
		&"select": return skin.click_sound
		&"commit": return skin.commit_sound
		&"denied": return skin.denied_sound if skin.denied_sound != null else skin.back_sound
		&"step_left": return skin.step_left_sound
		&"step_right": return skin.step_right_sound
	return null

## The per-cue trim a kind carries, ADDED to skin.ui_sound_volume_db by play_ui. The step pair shares one
## trim on purpose so the two directions can never drift apart in loudness.
func _volume_for(kind: StringName) -> float:
	match kind:
		&"open": return skin.open_volume_db
		&"back": return skin.back_volume_db
		&"tab": return skin.tab_volume_db
		&"select": return skin.click_volume_db
		&"commit": return skin.commit_volume_db
		&"denied": return skin.denied_volume_db
		&"step_left", &"step_right": return skin.step_volume_db
	return 0.0

## Playback pitch for a cue kind. Only the denial is transposed — that detune is what keeps a DERIVED
## refusal (back_sound speaking for an unassigned denied_sound) from sounding exactly like a menu closing.
##
## ⭐MENU CUES DELIBERATELY SIT OUT the global per-play pitch variation that every WORLD sound effect gets
## (GameSettings.audio.global_pitch_spread, applied by AudioManager.vary_pitch / play_varied). Menu chrome is
## not diegetic: a click is a piece of UI that should sound like the same button every time, and a randomised
## blip reads as a defect rather than as life. This table is EXACT, and play_ui writes it verbatim.
## tests/test_menu_sound.gd pins the unity-for-everything-but-the-denial contract.
func _pitch_for(kind: StringName) -> float:
	if kind == &"denied":
		return maxf(0.01, skin.denied_pitch_scale)  # 0 would hang the voice forever; the skin range-clamps too
	return 1.0

func _play_hover() -> void:
	if skin.hover_sound != null and _hover_player != null:
		_hover_player.stream = skin.hover_sound
		_hover_player.volume_db = skin.ui_sound_volume_db + skin.hover_volume_db
		_hover_player.play()

func _play_click() -> void:
	if _quiet:
		return
	if skin.click_sound != null and _click_player != null:
		_click_player.stream = skin.click_sound
		_click_player.volume_db = skin.ui_sound_volume_db + skin.click_volume_db
		_click_player.play()
		_click_started_ms = Time.get_ticks_msec()  # lets play_ui recognise (and cut) this click as the same press

## (Re)apply the skin's look to the tip panel — called on build and on set_skin/rebuild.
## Padding matches the theme's TooltipPanel (8,6) so the cursor tip and native tooltips read as one system.
func _style_tip() -> void:
	if _tip_panel == null:
		return
	_tip_panel.add_theme_stylebox_override(&"panel",
		_pick(skin.tooltip_panel, _flat(Color(0.04, 0.04, 0.055, 0.98), 1, skin.panel_border_color, skin.panel_corner_radius, 8, 6)))
	_tip_label.add_theme_color_override(&"font_color", skin.text_color)
	_tip_label.add_theme_font_size_override(&"font_size", skin.hint_size)
	# The tip lives on MenuStyle's OWN CanvasLayer, parented to this autoload Node — nothing above it is a
	# Control, so NO theme reaches it and every look it has must be an explicit override. That is why the
	# text drop shadow _build_theme() stamps on `Label` has to be repeated here by hand; without these three
	# lines the cursor tip is the one menu text surface that silently keeps the old flat look.
	_tip_label.add_theme_color_override(&"font_shadow_color", skin.text_shadow_color)
	_tip_label.add_theme_constant_override(&"shadow_offset_x", skin.text_shadow_offset.x)
	_tip_label.add_theme_constant_override(&"shadow_offset_y", skin.text_shadow_offset.y)

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


## The _pick twin for caption colours: an authored ink (alpha > 0) replaces the palette-derived default.
## Alpha 0 = unset — see the MenuSkin ink knobs for why alpha doubles as the null sentinel.
func _ink(authored: Color, derived: Color) -> Color:
	return authored if authored.a > 0.0 else derived


## ONE scrollbar stylebox: the artist's box when they authored one (the _pick rule), wearing the skin's
## THICKNESS as content margins on the bar's CROSS axis. This is the single place that decides how wide every
## scrollbar in the game is drawn — a ScrollBar measures its cross axis off exactly these margins, which is
## why the pre-2026-08-27 margin-less boxes rendered as nothing at all. Stamped on the ARTIST'S box too, on
## purpose: a delivered StyleBoxTexture carrying no margins of its own would silently reintroduce the 0px bar.
## Only the cross axis is touched, so the bar's minimum LENGTH stays the engine's business.
## Always a DUPLICATE — four theme entries per bar kind and two kinds share these generated boxes, and a
## shared instance would collect both orientations' margins and every later state's edits.
func _scrollbar_box(artist: StyleBox, generated: StyleBox, vertical: bool) -> StyleBox:
	var sb: StyleBox = artist.duplicate() if artist != null else generated.duplicate()
	if skin.scrollbar_width > 0:
		var half := float(skin.scrollbar_width) * 0.5
		if vertical:
			sb.content_margin_left = half
			sb.content_margin_right = half
		else:
			sb.content_margin_top = half
			sb.content_margin_bottom = half
	return sb


## Stamp the skin's text drop shadow onto one theme type. `Label`, `RichTextLabel` and `TooltipLabel` are
## the ONLY types Godot 4.7 gives font-shadow items to (probed against ThemeDB) — Button, TabBar and LineEdit
## never read one, and stamping it on them SUCCEEDS SILENTLY while drawing nothing. See the MenuSkin knob for
## why button captions are left flat rather than re-drawn by hand.
## Always stamped, never branched: skin.text_shadow_color's alpha-0 sentinel already means "draw nothing",
## and a theme entry that exists-but-is-transparent is what lets a live reskin turn the shadow back ON.
func _text_shadow(t: Theme, kind: StringName) -> void:
	t.set_color(&"font_shadow_color", kind, skin.text_shadow_color)
	t.set_constant(&"shadow_offset_x", kind, skin.text_shadow_offset.x)
	t.set_constant(&"shadow_offset_y", kind, skin.text_shadow_offset.y)
	t.set_constant(&"shadow_outline_size", kind, skin.text_shadow_blur)  # TooltipLabel has no such item; harmless there


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
		panel_sb = skin.panel_style.duplicate()  # the _pick rule: the theme never shares the .tres sub-resource
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
	# Disabled follows the TOGGLE-ICON rule (a missing disabled variant reuses the delivered art rather
	# than snapping back to the generated look): with rest art but no disabled art, disabled buttons wear
	# a DIMMED copy of the rest body — an enable/disable flip must grey the same body, never pop it in and
	# out of existence next to its always-bodied siblings. Art-less skins keep the transparent box.
	var disabled_sb: StyleBox
	if skin.button_disabled != null:
		disabled_sb = skin.button_disabled.duplicate()
	elif skin.button_normal != null:
		disabled_sb = skin.button_normal.duplicate()
		if disabled_sb is StyleBoxTexture:
			(disabled_sb as StyleBoxTexture).modulate_color *= Color(0.62, 0.62, 0.60, 0.9)
		elif disabled_sb is StyleBoxFlat:
			(disabled_sb as StyleBoxFlat).bg_color = (disabled_sb as StyleBoxFlat).bg_color.darkened(0.4)
	else:
		disabled_sb = clear.duplicate()
	t.set_stylebox(&"disabled", &"Button", disabled_sb)
	t.set_color(&"font_color", &"Button", _ink(skin.button_font_color, skin.text_dim_color))
	t.set_color(&"font_hover_color", &"Button", _ink(skin.button_font_hover_color, skin.text_color))
	t.set_color(&"font_pressed_color", &"Button", _ink(skin.button_font_pressed_color, skin.accent_color))
	t.set_color(&"font_focus_color", &"Button", _ink(skin.button_font_focus_color, skin.text_color))
	t.set_color(&"font_hover_pressed_color", &"Button", _ink(skin.button_font_pressed_color, skin.accent_color))
	t.set_color(&"font_disabled_color", &"Button", _ink(skin.button_font_disabled_color, skin.disabled_text_color))
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

	# TEXT DROP SHADOW — the type half of the same straight-overhead light the art PNGs are baked with
	# (MenuSkin's "Text drop shadow" group; scripts/tools/bake_ui_shadows.gd owns the art half). Stamped on
	# all three theme types that HAVE a font-shadow item and no others — see _text_shadow. The custom cursor
	# tip is a fourth surface that needs the same shadow but takes it by hand (_style_tip): it hangs off this
	# autoload's own CanvasLayer, so no theme reaches it.
	_text_shadow(t, &"Label")
	_text_shadow(t, &"RichTextLabel")  # the chess move log — its only theme entry
	_text_shadow(t, &"TooltipLabel")   # Godot's NATIVE tooltips; the in-viewport tip is _style_tip's job

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

	# TextEdit — the same flat chrome, same slots. The waypoint editor's note field is the game's first
	# multi-line text input, and without these entries it wore the stock engine box inside a skinned card —
	# the exact bug the LineEdit block above records. It reuses the LineEdit styleboxes (an artist who
	# reskins line_edit_normal/focus reskins both field kinds at once; the two are one input language).
	t.set_stylebox(&"normal", &"TextEdit", _pick(skin.line_edit_normal, le_normal))
	t.set_stylebox(&"focus", &"TextEdit", _pick(skin.line_edit_focus, le_focus))
	t.set_stylebox(&"read_only", &"TextEdit", _pick(skin.line_edit_normal, le_normal.duplicate()))
	t.set_color(&"font_color", &"TextEdit", skin.text_color)
	t.set_color(&"font_placeholder_color", &"TextEdit", skin.text_dim_color)
	t.set_color(&"caret_color", &"TextEdit", skin.accent_color)
	t.set_color(&"selection_color", &"TextEdit", Color(skin.accent_color.r, skin.accent_color.g, skin.accent_color.b, 0.35))
	t.set_font_size(&"font_size", &"TextEdit", skin.body_size)

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

	# Scrollbars — a bar you can SEE and GRAB ------------------------------------
	# NOT "minimal" any more, and the rewrite is worth the paragraph (2026-08-27, screenshot audit). The old
	# block handed both bars margin-less boxes at 5% / 22% of text_color. A ScrollBar sizes its cross axis off
	# its track box's content margins and nothing else, so every scrollbar in the game was drawn ZERO PX WIDE:
	# there was no faint bar to squint at, there was no bar. Four separate HIGH findings turned out to be this
	# one defect — Options→Controls showed 4 of 44 bindings, Accessibility 14 of 33, character creation 4 of 6
	# stats, and the Stats tab cut a sentence mid-word — each of them a page that scrolls with nothing on
	# screen admitting it and no thumb to drag even once the player guessed.
	# Two things fix it and both live on the skin: skin.scrollbar_width (stamped as margins by _scrollbar_box,
	# on the artist's box too, so delivered art can't put the bar back at 0) and inks that read on the SHIPPED
	# palette — a dark panel ink on light parchment, where 22% alpha was hopeless even at a real width.
	# ⚠ The width is a LAYOUT budget, not just paint: ScrollContainer reserves it beside the content. Hosts
	# with no width to spare buy it back from their own gutter (options_menu._add_tab) rather than from rows.
	var sb_track_ink := _ink(skin.scrollbar_track_color,
		Color(skin.text_color.r, skin.text_color.g, skin.text_color.b, 0.18))
	# 0.18 / 0.75 measured against the SHIPPED pairing (dark plum ink on light parchment): the thumb lands
	# around half the panel's own value — a bar you spot without looking for it — while the track stays a
	# quiet gutter. They are alphas of the panel ink rather than fixed colours so a dark reskin flips with
	# the palette instead of leaving a black bar on a black panel.
	var sb_grab_ink := _ink(skin.scrollbar_grabber_color,
		Color(skin.text_color.r, skin.text_color.g, skin.text_color.b, 0.75))
	var sb_bg := _flat(sb_track_ink, 0, Color(0, 0, 0, 0), 2)
	var sb_grab := _flat(sb_grab_ink, 0, Color(0, 0, 0, 0), 2)
	# Hover/drag lights the thumb in the accent — the same "this control is live" signal the focus ring and the
	# active tab give. An artist grabber wins all three states (one delivered thumb, the slider's rule).
	var sb_grab_hot := _flat(Color(skin.accent_color.r, skin.accent_color.g, skin.accent_color.b, 0.9), 0, Color(0, 0, 0, 0), 2)
	for kind in [&"VScrollBar", &"HScrollBar"]:
		var vertical: bool = kind == &"VScrollBar"
		t.set_stylebox(&"scroll", kind, _scrollbar_box(skin.scrollbar_track, sb_bg, vertical))
		t.set_stylebox(&"grabber", kind, _scrollbar_box(skin.scrollbar_grabber, sb_grab, vertical))
		t.set_stylebox(&"grabber_highlight", kind, _scrollbar_box(skin.scrollbar_grabber, sb_grab_hot, vertical))
		t.set_stylebox(&"grabber_pressed", kind, _scrollbar_box(skin.scrollbar_grabber, sb_grab_hot, vertical))

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
