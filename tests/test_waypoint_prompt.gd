extends GutTest

## WaypointPrompt (scripts/ui/waypoint_prompt.gd) — the pin editor card. Code-built chrome, so its wiring has
## no .tscn contract test; what is pinned here instead is the open/commit/close CONTRACT its host leans on
## (map_screen holds an is_open() guard on every verb), the clamp passthrough, the focus fence's boundary
## wiring, and the chip plate that makes a mark/colour chip a readable preview of the real marker. Loaded BY
## PATH — the file deliberately carries no class_name.
##
## The card is EDIT-ONLY: the map tab pins instantly on a click and the in-world Mark key pins and tracks in
## one press, so this is only ever opened on a pin that already exists. That makes RE-OPENING the contract
## that matters most — one long-lived card is walked across many different pins, and a field that failed to
## reseed would write the previous pin's icon or colour onto this one.
##
## The card is added to the GUT tree (add_child_autofree) because open() grabs focus, and grab_focus on an
## off-tree Control pushes an engine error that GUT 9.6 fails a whole suite on.

const PROMPT_SCRIPT := "res://scripts/ui/waypoint_prompt.gd"

func _card():
	var p = load(PROMPT_SCRIPT).new()
	add_child_autofree(p)
	return p


func test_open_close_contract() -> void:
	var p = _card()
	assert_false(p.is_open(), "built shut")
	p.open("Title", "Seed", "note", 1, 2, Callable())
	assert_true(p.is_open(), "open() opens")
	assert_true(p.visible, "...visibly")
	p.close()
	assert_false(p.is_open(), "close() shuts it")
	assert_false(p.visible, "...and hides it — the host calls this from ITS close(), so a card must never survive the screen")


func test_open_seeds_and_clamps_the_fields() -> void:
	var p = _card()
	p.open("Title", "bad\tname", "x".repeat(999), 99, 3, Callable())
	assert_eq(p.entered_name(), "bad name", "the seed goes through the record clamp on the way IN, not just out")
	var wb = load("res://scripts/world/waypoint_book.gd")
	assert_eq(p.entered_note().length(), int(wb.NOTE_MAX), "an oversized note seed is clamped")
	assert_eq(p.entered_icon(), wb.wrap_icon(99), "a junk icon ordinal wraps into the vocabulary")
	assert_eq(p.entered_tint(), 3, "the tint index survives")
	p.close()


## ⭐ONE CARD, MANY PINS. The host keeps a single instance for the life of the screen and re-opens it on
## whichever pin is selected, so every field must be re-seeded from the NEW pin — a leaked `_icon` or `_tint`
## would silently re-mark the pin the player only meant to rename.
func test_reopening_reseeds_every_field_from_the_new_pin() -> void:
	var p = _card()
	p.open("Title", "First", "first note", 3, 2, Callable())
	p.close()
	p.open("Title", "Second", "", 0, 0, Callable())
	assert_eq(p.entered_name(), "Second", "the name follows the new pin")
	assert_eq(p.entered_note(), "", "...and so does an EMPTY note (the leak that would look most like a bug)")
	assert_eq(p.entered_icon(), 0, "...and the mark")
	assert_eq(p.entered_tint(), 0, "...and the colour")
	p.close()


## An emptied name commits as "" ON PURPOSE. A default is player COPY and owes PlayerText, which this widget
## may not read — so the host substitutes its own (MapScreen._pin_seed_name, the same ordinal a placement
## seeds). A card that invented a name here would put an untranslated literal into a saved profile.
func test_a_cleared_name_commits_empty_so_the_caller_can_default() -> void:
	var p = _card()
	var got := []
	p.open("Title", "Was Named", "", 0, 0, func(n: String, _note: String, _i: int, _t: int) -> void:
		got.append(n))
	p._name.text = "   "  # whitespace only — clean_name collapses it to nothing
	p._on_save_pressed()
	assert_eq(got, [""], "the card reports the empty answer rather than inventing copy for it")


func test_commit_fires_with_clamped_values_and_closes_first() -> void:
	var p = _card()
	var got := []
	# APPEND, never rebind: a GDScript lambda captures by value, so `got = [...]` inside it would rebind a
	# local copy and the outer array would stay empty — mutation is the only write that crosses the capture.
	p.open("Title", "My Pin", "my note", 2, 1, func(n: String, note: String, icon: int, tint: int) -> void:
		got.append_array([n, note, icon, tint, p.is_open()]))
	p._on_save_pressed()
	assert_eq(got.size(), 5, "the commit Callable fired exactly once")
	assert_eq(got[0], "My Pin", "with the entered name")
	assert_eq(got[2], 2, "...the entered icon")
	assert_eq(got[4], false, "and the card closed BEFORE the callback ran — the callback repaints the host over us")
	assert_false(p.is_open(), "still shut afterwards")


func test_cancel_never_calls_back() -> void:
	var p = _card()
	var fired := [false]
	p.open("Title", "Seed", "", 0, 0, func(_n: String, _note: String, _i: int, _t: int) -> void:
		fired[0] = true)
	watch_signals(p)
	p._on_cancel_pressed()
	assert_false(fired[0], "cancel closes without committing")
	assert_false(p.is_open(), "...and the card is shut")
	assert_signal_emitted(p, "cancelled", "the host hangs its focus-restore off this signal")


## THE FOCUS FENCE's boundary wiring: the scrim stops the mouse but not focus navigation, so the card's edge
## controls must clamp/wrap or a pad walks out under the scrim onto the host's live buttons.
func test_focus_fence_boundaries() -> void:
	var p = _card()
	assert_eq(p._name.focus_neighbor_top, p._name.get_path(), "the name field's top edge clamps to itself")
	assert_eq(p._save_btn.focus_neighbor_bottom, p._save_btn.get_path(), "the Save row's bottom edge clamps")
	var icons: Array = p._icon_chips
	assert_gt(icons.size(), 1, "the icon row built")
	assert_eq((icons[0] as Button).focus_neighbor_left, (icons[icons.size() - 1] as Button).get_path(),
		"the chip rows WRAP left-to-last...")
	assert_eq((icons[icons.size() - 1] as Button).focus_neighbor_right, (icons[0] as Button).get_path(),
		"...and last-to-first — the fence doubles as cyclic browsing")
	assert_eq(p._note.focus_mode, Control.FOCUS_CLICK,
		"the note TextEdit is click-focus only — focus navigation must never be able to walk INTO a control that consumes every arrow key")


## ⭐A CHIP PREVIEWS THE MARKER IN THE CONTEXT IT WILL REALLY APPEAR IN. Marker colours are authored to read on
## the minimap's near-black field, and the chips painted them straight onto this card's CREAM parchment button
## face: the QA shot (wp_shots7/04) caught the white entry all but vanishing and the yellow and light-green
## entries washed out, so the player was choosing from a palette they could not see. The plate is the map's own
## backing colour rather than a dark grey picked for this card, which is what makes the chip an honest preview.
##
## The SIZE half matters just as much and is the easy thing to get wrong later: the swatch is FULL_RECT over the
## whole Button, so a plate grown to fill it would paint over the frame — and with it the hover / pressed /
## focus art that is the only thing saying WHICH chip is chosen.
func test_every_chip_backs_its_glyph_with_the_maps_own_dark_plate() -> void:
	var p = _card()
	var chip := p._icon_chips[0] as Button
	var sw = chip.get_child(0)
	assert_not_null(sw, "the chip carries its GlyphSwatch")
	var backing: Color = MenuStyle.hud.minimap_backing_color  # a duck-typed autoload read is a Variant, never `:=`
	var plate: Color = sw.plate_color()
	assert_eq(Color(plate.r, plate.g, plate.b), Color(backing.r, backing.g, backing.b),
		"the plate is the MINIMAP's backing colour — the chip previews the marker on the field it will really be drawn on")
	assert_gt(plate.a, 0.5,
		"...at an alpha that can actually cover a cream button face: the map widget has a %MapUnder art slot to fall back on if an artist zeroes this, and a chip has nothing behind it but the bug")
	# THE GEOMETRY IS CHECKED ON A BARE SWATCH, not on the one in the card. plate_rect() is a pure function of
	# `size` and `radius`, and headless GUT lays nothing out — but writing `size` onto the CARD's swatch is
	# writing it onto a FULL_RECT-anchored Control, which pushes the engine's "non-equal opposite anchors will
	# have their size overridden" error, and GUT 9.6 fails a whole suite on one of those. An unparented
	# instance has no anchors fighting it and answers the same question.
	var probe = load(PROMPT_SCRIPT).GlyphSwatch.new()
	probe.radius = sw.radius
	probe.size = Vector2(60.0, 28.0)
	autofree(probe)
	var rad: float = probe.radius
	var box: Rect2 = probe.plate_rect()  # explicitly typed: a duck-typed read off an untyped node is a Variant
	assert_gt(box.size.x, rad * 2.0, "the plate clears the glyph it backs")
	assert_lt(box.size.x, 28.0, "...and stays inside the chip, so the button's own selection art still shows around it")
	assert_almost_eq(box.size.x, box.size.y, 0.001, "it is square — a plate as wide as the row would just be a repaint of the face")
	assert_almost_eq(box.get_center().x, 30.0, 0.001, "centred on the swatch (X), where the glyph is")
	assert_almost_eq(box.get_center().y, 14.0, 0.001, "...and on Y")


func test_the_chip_rows_follow_their_vocabularies() -> void:
	var p = _card()
	var wb = load("res://scripts/world/waypoint_book.gd")
	assert_eq(p._icon_chips.size(), int(wb.Icon.size()), "one chip per icon — the row is built from the enum")
	var palette: PackedColorArray = MenuStyle.hud.minimap_waypoint_palette
	assert_eq(p._tint_chips.size(), maxi(1, palette.size()),
		"one chip per palette entry — an artist adding a seventh colour grows the row with no code change")
