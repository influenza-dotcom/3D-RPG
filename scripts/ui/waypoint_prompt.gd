extends Control

## @system Minimap
## @seam The editor card for ONE map pin: its name, its note, its mark and its colour. Opened by the Map tab
## (scripts/ui/map_screen.gd) to RE-AUTHOR a pin that already exists — never to place one. Placement on the map
## tab is instant (a click drops a pin seeded with its ordinal) and the in-world Mark key pins and tracks in one
## press, so nothing reaches this card until the player has decided a particular pin is worth naming. That is
## the whole reason the card can afford four fields: it is opened rarely and deliberately, rather than standing
## between the player and every single mark. The caller supplies the commit Callable and owns what the answer
## means, so this widget never touches GameState itself.
## @seam CODE-BUILT and parented into the host's own root, the AmountPrompt / GridInventoryView idiom: this is
## live runtime chrome bound per-open, not static layout an artist arranges, so it is instantiated into an
## authored scene rather than authored in one. It draws its own full-rect scrim and eats every click that
## misses the card, so the map underneath cannot be clicked "through" an open editor.
## @risk NO class_name — the consumer preloads it BY PATH. A new class_name is not in the editor's global
## script class cache until a rescan, and until then every file that NAMES the type fails to parse. See
## scripts/world/waypoint_book.gd, which carries the same note for the same reason.
## @test res://tests/test_waypoint_prompt.gd
##
## ⭐EVERY FIELD HERE HOLDS PLAYER-TYPED TEXT, which is the one class of string that must never be looked up
## as a translation msgid. Godot auto-translates any Control's `text` the moment a locale ships, so the name
## field, the note field and every Control that echoes them set auto_translate_mode = DISABLED (the seam
## menu_style.gd's header documents). The CAPTIONS around them are normal copy and come from PlayerText.
##
## CONTROLLER PARITY, the atm_screen rule ("a control a pad can never land on is not a path"): the mark and
## colour rows are made of real focusable Buttons rather than a custom click-anywhere strip, so the whole card
## is reachable with a pad. The glyph inside each chip is drawn by the inner GlyphSwatch below — a Button's
## icon slot would need a Texture2D per shape per tint, which is a texture atlas for something that is a few
## lines of draw code. That swatch also lays the MAP's own dark backing under the glyph, so a chip previews the
## marker on the field it will really appear on rather than on this card's cream button face; see its note.

signal cancelled

## The record's own rules — the clamps this card enforces while typing, and the icon vocabulary its chips are
## built from. Preloaded BY PATH, untyped, for the class-cache reason in the @risk above.
const WAYPOINT_BOOK := preload("res://scripts/world/waypoint_book.gd")

## Side of a chip's drawn glyph in px. Big enough that a CROSS and a SQUARE are distinguishable at a glance,
## small enough that six chips plus the row separation still fit MenuSkin.dialog_width.
const CHIP_PX := 18.0

## Rows the note field shows before it scrolls. Three is WaypointBook.NOTE_MAX at a comfortable width, so the
## common case never scrolls — and a FIXED row count is what stops the card hopping vertically as the player
## types (make_dialog's height-shrink-wrap warning).
const NOTE_ROWS := 3

var _card: VBoxContainer
var _title: Label
var _name: LineEdit
var _note: TextEdit
var _icon_chips: Array[Button] = []
var _tint_chips: Array[Button] = []
var _save_btn: Button
var _icon: int = 0
var _tint: int = 0
var _on_commit: Callable = Callable()
var _syncing: bool = false   ## latch: writing .text re-fires text_changed (the AmountPrompt / ATM idiom)


func _init() -> void:
	name = &"WaypointPrompt"
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP  # a click that misses the card must not reach the map behind it
	visible = false


func _ready() -> void:
	add_child(MenuStyle.make_dim())
	_card = MenuStyle.make_dialog(self)
	_title = MenuStyle.cap_label(Label.new())
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	MenuStyle.style_title(_title)
	_card.add_child(_title)

	_card.add_child(_caption(PlayerText.WAYPOINT_NAME_LABEL))
	_name = LineEdit.new()
	_name.max_length = WAYPOINT_BOOK.NAME_MAX  # the engine-side half of the clamp; WaypointBook.make is the other
	_name.context_menu_enabled = false         # its right-click menu is untranslatable engine chrome (chess_screen's note)
	_name.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	_name.text_changed.connect(_on_name_changed)
	_name.text_submitted.connect(_on_name_submitted)
	_card.add_child(_name)

	_card.add_child(_caption(PlayerText.WAYPOINT_NOTE_LABEL))
	_note = TextEdit.new()
	# A TextEdit has no max_length of its own, so the cap is enforced on change below. Wrapping is on because
	# a note is prose; the row count is pinned so the card's height cannot move while it is open.
	_note.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	_note.scroll_fit_content_height = false
	_note.custom_minimum_size.y = MenuStyle.skin.hint_size * NOTE_ROWS * 2.0
	_note.placeholder_text = PlayerText.WAYPOINT_NOTE_PLACEHOLDER
	_note.context_menu_enabled = false
	_note.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	# FOCUS_CLICK, not the default ALL: a TextEdit consumes every arrow key for its caret, so pad/keyboard
	# focus navigation that WALKS into it can never walk out — a soft-lock inside a modal. Click-to-focus
	# keeps it fully usable for the mouse (the only device that can type prose into it anyway).
	_note.focus_mode = Control.FOCUS_CLICK
	_note.text_changed.connect(_on_note_changed)
	_card.add_child(_note)

	_card.add_child(_caption(PlayerText.WAYPOINT_ICON_LABEL))
	_icon_chips = _build_chips(_card, WAYPOINT_BOOK.Icon.size(), _on_icon_picked)
	_card.add_child(_caption(PlayerText.WAYPOINT_TINT_LABEL))
	_tint_chips = _build_chips(_card, _palette_size(), _on_tint_picked)

	var row := HBoxContainer.new()
	MenuStyle.style_button_row(row)
	_card.add_child(row)
	# MUTED (&""): the commit cue belongs to the CALLER — only it knows whether the pin was actually stored
	# (a level at its cap refuses). Leaving the auto-wired click on would sound a success that never happened.
	_save_btn = MenuStyle.cap_button(Button.new())
	_save_btn.text = PlayerText.WAYPOINT_SAVE
	_save_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	MenuStyle.set_button_sound(_save_btn, &"")
	_save_btn.pressed.connect(_on_save_pressed)
	row.add_child(_save_btn)
	var cancel := MenuStyle.cap_button(Button.new())
	cancel.text = PlayerText.CANCEL
	cancel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cancel.pressed.connect(_on_cancel_pressed)
	row.add_child(cancel)
	_fence_focus(cancel)
	set_process_unhandled_input(false)  # only an OPEN card may swallow Esc (see _unhandled_input)


## THE FOCUS FENCE. The scrim stops the MOUSE, but focus navigation is a second input path: without explicit
## neighbours, Godot's geometric search happily carries a pad's ui_down off the Save row onto the host's
## still-focusable buttons BEHIND the scrim — mutating the ledger under an open editor. Boundary controls
## clamp to themselves (top of the name field, bottom of the Save/Cancel row) and each chip row WRAPS
## (last chip's right = first chip), which is both the fence and a nicer way to browse six choices. The host
## adds its own belt-and-braces guard (every verb refuses while this card is open), so even a hole here
## cannot reach the ledger.
func _fence_focus(cancel: Button) -> void:
	if _name != null:
		_name.focus_neighbor_top = _name.get_path()
	if _save_btn != null:
		_save_btn.focus_neighbor_bottom = _save_btn.get_path()
	if cancel != null:
		cancel.focus_neighbor_bottom = cancel.get_path()
	for chips: Array[Button] in [_icon_chips, _tint_chips]:
		if chips.is_empty():
			continue
		var first := chips[0]
		var last := chips[chips.size() - 1]
		first.focus_neighbor_left = last.get_path()
		last.focus_neighbor_right = first.get_path()


func is_open() -> bool:
	return visible


## Open the card over `title`, seeded with the pin's CURRENT fields. On Save, `on_commit` is called with
## (name, note, icon, tint) — already through WaypointBook's clamps, so a caller never re-validates. Esc /
## Cancel closes without calling back.
##
## The seeds are re-clamped ON THE WAY IN as well as out. They come from the ledger, which is already clean —
## but a hand-edited save reaches the ledger through the same door, and a field seeded with a control
## character would paint a box the player cannot see to delete.
func open(title: String, name_seed: String, note_seed: String, icon: int, tint: int,
		on_commit: Callable) -> void:
	_on_commit = on_commit
	_title.text = MenuStyle.title_text(title)
	_icon = WAYPOINT_BOOK.wrap_icon(icon)
	_tint = maxi(0, tint)
	_syncing = true
	_name.text = WAYPOINT_BOOK.clean_name(name_seed)
	_note.text = WAYPOINT_BOOK.clean_note(note_seed)
	_syncing = false
	_refresh_chips()
	visible = true
	set_process_unhandled_input(true)
	MenuStyle.play_open()
	# Focus + select-all so the pin's existing name is replaced by the first keystroke but survives a bare
	# Enter — the NameEntryDialog gesture, which players already have from naming a pet. Renaming is what this
	# card is opened FOR most of the time (the pin arrives auto-named), so typing over the seed is the fast path.
	_name.grab_focus()
	_name.select_all()
	_refresh()


func close() -> void:
	if not visible:
		return
	visible = false
	set_process_unhandled_input(false)
	_on_commit = Callable()


## Esc closes the CARD without closing the Map tab behind it. This runs before the host's own
## _unhandled_input (unhandled input walks the tree bottom-up and we are a descendant of the host's root), so
## marking it handled is what stops one Esc from cancelling the edit AND shutting the map.
func _unhandled_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed(&"ui_cancel"):
		_on_cancel_pressed()
		get_viewport().set_input_as_handled()


## The typed name, clamped — or "" when the player cleared it. The caller substitutes its own default in that
## case (MapScreen._pin_seed_name), because a DEFAULT is player copy and owes PlayerText, which this widget
## must not compose.
func entered_name() -> String:
	return WAYPOINT_BOOK.clean_name(_name.text)


func entered_note() -> String:
	return WAYPOINT_BOOK.clean_note(_note.text)


func entered_icon() -> int:
	return _icon


func entered_tint() -> int:
	return _tint


# ---------------------------------------------------------------------------------------------------
# Chrome
# ---------------------------------------------------------------------------------------------------

## One field caption. Left-aligned rather than style_hint's centred default: these label the row BELOW them,
## and a centred caption over a full-width field reads as a heading for the whole card.
func _caption(text: String) -> Label:
	var l := MenuStyle.cap_label(Label.new())
	l.text = text
	MenuStyle.style_hint(l)
	l.autowrap_mode = TextServer.AUTOWRAP_OFF  # a caption that wraps changes the card's height mid-edit
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	return l


## A row of `count` focusable chips, each carrying a GlyphSwatch. `picked` is called with the chip's index.
## Built from a COUNT rather than a hardcoded list so the icon row follows WaypointBook.Icon and the colour
## row follows the skin's palette length — an artist adding a seventh tint grows the row with no code change.
func _build_chips(parent: VBoxContainer, count: int, picked: Callable) -> Array[Button]:
	var row := HBoxContainer.new()
	MenuStyle.style_button_row(row)
	parent.add_child(row)
	var out: Array[Button] = []
	for i in count:
		var b := Button.new()
		b.toggle_mode = true          # the chip SHOWS the current choice, it does not just fire it
		b.focus_mode = Control.FOCUS_ALL
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.custom_minimum_size = Vector2(CHIP_PX + 10.0, CHIP_PX + 10.0)
		var swatch := GlyphSwatch.new()
		swatch.radius = CHIP_PX * 0.5
		swatch.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		swatch.mouse_filter = Control.MOUSE_FILTER_IGNORE  # the BUTTON takes the click; the art must not eat it
		b.add_child(swatch)
		b.pressed.connect(picked.bind(i))
		row.add_child(b)
		out.append(b)
	return out


func _on_icon_picked(i: int) -> void:
	_icon = WAYPOINT_BOOK.wrap_icon(i)
	MenuStyle.play_select()
	_refresh_chips()


func _on_tint_picked(i: int) -> void:
	_tint = maxi(0, i)
	MenuStyle.play_select()
	_refresh_chips()


## Push the current choice onto every chip: which one reads as pressed, what shape it draws, and in what
## tint. The ICON row previews all six shapes in the CURRENTLY CHOSEN colour (so picking a colour repaints
## the whole icon row and the player sees the combination they are actually going to get), while the COLOUR
## row previews the chosen shape in each palette entry. Between them, every chip on screen is a preview of
## the real marker rather than an abstract swatch.
func _refresh_chips() -> void:
	var tint := _tint_color(_tint)
	for i in _icon_chips.size():
		_icon_chips[i].button_pressed = (i == _icon)
		var sw := _icon_chips[i].get_child(0) as GlyphSwatch
		if sw != null:
			sw.paint(WAYPOINT_BOOK.icon_shape(i), tint)
	var palette_n := _palette_size()
	for i in _tint_chips.size():
		_tint_chips[i].button_pressed = (posmod(_tint, maxi(1, palette_n)) == i)
		var sw2 := _tint_chips[i].get_child(0) as GlyphSwatch
		if sw2 != null:
			sw2.paint(WAYPOINT_BOOK.icon_shape(_icon), _tint_color(i))


func _palette_size() -> int:
	var palette: PackedColorArray = MenuStyle.hud.minimap_waypoint_palette
	return palette.size() if not palette.is_empty() else 1


## The SAME resolution the minimap and the compass use, so a chip previews the colour the pin will actually
## be drawn in rather than an approximation of it.
func _tint_color(i: int) -> Color:
	var palette: PackedColorArray = MenuStyle.hud.minimap_waypoint_palette
	if palette.is_empty():
		return MenuStyle.hud.minimap_waypoint_color
	return palette[posmod(i, palette.size())]


func _on_name_changed(_t: String) -> void:
	if _syncing:
		return
	_refresh()


## Enforce WaypointBook.NOTE_MAX as it is typed, because TextEdit has no max_length. Latched and
## caret-restoring for the reason AmountPrompt's filter is: writing .text re-fires text_changed, and a naive
## rewrite jumps the caret to the end mid-sentence.
func _on_note_changed() -> void:
	if _syncing:
		return
	var raw := _note.text
	if raw.length() <= WAYPOINT_BOOK.NOTE_MAX:
		return
	var line := _note.get_caret_line()
	var col := _note.get_caret_column()
	_syncing = true
	_note.text = raw.substr(0, WAYPOINT_BOOK.NOTE_MAX)
	_note.set_caret_line(mini(line, _note.get_line_count() - 1))
	_note.set_caret_column(mini(col, _note.get_line(_note.get_caret_line()).length()))
	_syncing = false
	MenuStyle.play_denied()  # the cap is a refusal, and a silently-swallowed keystroke reads as a dead field


## Enter in the NAME field commits, like every other prompt in the game. Deliberately NOT wired on the note
## field, where Enter is a line break.
func _on_name_submitted(_t: String) -> void:
	_on_save_pressed()


func _on_save_pressed() -> void:
	var cb := _on_commit
	var n := entered_name()
	var note := entered_note()
	var icon := _icon
	var tint := _tint
	close()  # close FIRST: the callback repaints the host's pin card and may open a toast over us
	if cb.is_valid():
		cb.call(n, note, icon, tint)


func _on_cancel_pressed() -> void:
	if not visible:
		return
	close()
	MenuStyle.play_back()
	cancelled.emit()


## Nothing on this card can be invalid — an empty name is legal (the caller substitutes a default) and an
## empty note is the normal case — so Save is never disabled. Kept as a seam so a future rule has one place
## to live, mirroring AmountPrompt._refresh.
func _refresh() -> void:
	_save_btn.disabled = false


## ONE MARKER GLYPH ON A SCRAP OF THE MAP, drawn at the same size and by the same MapGlyph vocabulary the map
## itself paints — so a chip is a true preview rather than a second drawing of the same idea. Filled AND
## stroked, because that doubled silhouette is exactly what identifies the waypoint family on the map (see
## Minimap._paint_waypoints).
##
## ⭐AND ON THE PLAN'S OWN BACKING, which is the half that was missing. A marker's colours are authored to read
## on the minimap's near-black field; a chip's face is the parchment theme's CREAM Button. The QA shot
## (wp_shots7/04) caught the consequence — the white entry all but disappeared into the button face and the
## yellow and light-green entries were washed out, so the player was choosing from a palette they could not
## see, for marks that would then appear in colours they had not really previewed. The plate under each glyph
## reproduces the field the marker will actually be drawn on, which makes the chip honest as well as legible.
##
## An INNER CLASS rather than its own file: it is a few lines of draw code with no reuse outside this card, and
## a separate script would be another path to keep in step with the family's look.
class GlyphSwatch extends Control:
	## Clear air kept between the glyph's own radius and the edge of its plate. SMALL on purpose: the plate
	## backs the glyph and stops there, leaving the Button's face — and with it the hover / pressed / focus art
	## that says WHICH chip is chosen — visible all the way around. A plate that covered the whole swatch (which
	## is FULL_RECT over the button, frame included) would erase that selection art along with the cream.
	const PLATE_PAD := 2.0
	## Alpha FLOOR for the plate. HudSkin.minimap_backing_color ships translucent, and an artist is explicitly
	## invited to zero it outright — the widget has a %MapUnder art slot to fall back on. A chip has no such
	## slot: behind it is the very cream face this plate exists to cover, so it supplies its own floor rather
	## than silently reverting to the bug. The shipped value is above this, so today the floor changes nothing.
	const PLATE_MIN_ALPHA := 0.55

	var _shape: int = 0
	var _tint: Color = Color.WHITE

	func paint(shape: int, tint: Color) -> void:
		_shape = shape
		_tint = tint
		queue_redraw()  # a Control repaints ONLY on request; without this the chip keeps its first look forever

	## Drawn radius in px, pushed in by the builder. An instance field rather than a const because an inner
	## class cannot reach its OUTER class's consts by bare name, and duplicating CHIP_PX here would be a
	## second number to keep in step with the chip's own minimum size.
	var radius: float = 8.0

	## The plate's colour — the plan's own backing, floored so it can still darken a cream chip face.
	##
	## Its own function (with plate_rect below) because _draw leaves NOTHING behind for a test to read back:
	## the two facts worth pinning here are "the plate is the map's colour, not a colour invented for this card"
	## and "the plate stays inside the chip", and both are answers, not pixels.
	func plate_color() -> Color:
		var c: Color = MenuStyle.hud.minimap_backing_color  # a duck-typed host read is a Variant, never `:=`
		c.a = maxf(c.a, PLATE_MIN_ALPHA)
		return c

	## The plate's rect: a square centred on the swatch, the glyph's diameter plus PLATE_PAD of clear air on
	## each side — and shrunk if that would reach the chip's border art, so a tight row degrades to a plate the
	## size of the glyph rather than to one painted over the frame. Square rather than the swatch's own rect for
	## the reason PLATE_PAD gives.
	func plate_rect() -> Rect2:
		var side := (radius + PLATE_PAD) * 2.0
		if size.y > 0.0:
			side = minf(side, maxf(radius * 2.0, size.y - PLATE_PAD * 2.0))
		var box := Vector2(side, side)
		return Rect2(size * 0.5 - box * 0.5, box)

	func _draw() -> void:
		var pts := MapGlyph.shape_points(_shape, radius)
		if pts.is_empty():
			return  # no shape, nothing to back: an empty vocabulary slot draws no plate either
		# The plate FIRST, then the marker over it — the same order, and the same two coats, the map paints in.
		draw_rect(plate_rect(), plate_color())
		var at := size * 0.5
		var fill := _tint
		fill.a *= clampf(MenuStyle.hud.minimap_waypoint_fill_alpha, 0.0, 1.0)
		draw_colored_polygon(MapGlyph.offset(pts, at), fill)
		draw_polyline(MapGlyph.offset(MapGlyph.closed(pts), at), _tint,
				maxf(1.0, MenuStyle.hud.minimap_glyph_stroke_px))
