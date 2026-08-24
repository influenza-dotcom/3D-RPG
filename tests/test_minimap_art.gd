extends GutTest

## MinimapArt (scripts/ui/minimap_art.gd) — the pure brain behind the minimap's drop-in marker art: which
## texture wins, which slot a station kind reads, and how big a delivered PNG is allowed to draw.
##
## Every rule here is provable with a bare HudSkin.new() and no tree, which is the whole reason the skin
## arrives as a PARAMETER rather than being read off MenuStyle.hud inside these functions (the
## FloorplanSection / MapGlyph promise). Loaded BY PATH, not by class_name, so the suite survives a stale
## global class cache (the ui.gd STAMINA_RING_SCRIPT idiom — and MinimapArt is a NEW class_name, so this is
## not hypothetical).

const ART := "res://scripts/ui/minimap_art.gd"
const SKIN := "res://scripts/ui/hud_skin.gd"


func _skin() -> Resource:
	return load(SKIN).new()


func _tex() -> Texture2D:
	# A real, distinguishable Texture2D with no disk asset behind it.
	var img := Image.create(4, 4, false, Image.FORMAT_RGBA8)
	img.fill(Color.WHITE)
	return ImageTexture.create_from_image(img)


## THE PRECEDENCE RULE: a level's authored MapData art beats the global skin slot, which beats "draw the
## primitive". Per-level wins so a set-piece level can override the look the rest of the game wears.
func test_pick_prefers_the_per_level_art() -> void:
	var a := _tex()
	var b := _tex()
	assert_eq(load(ART).pick(a, b), a, "a level's authored MapData art wins over the skin slot")
	assert_eq(load(ART).pick(null, b), b, "with no level art the skin slot is used")
	assert_null(load(ART).pick(null, null), "with neither, null means draw the code-drawn primitive")


func test_station_texture_reads_each_kinds_own_slot() -> void:
	# One slot at a time, so a mis-wired match arm (SHOP reading the BANK slot) fails on the pair it broke
	# rather than hiding behind the family fallback.
	var pairs := {
		StationMarker.Kind.SHOP: &"minimap_station_shop_texture",
		StationMarker.Kind.BANK: &"minimap_station_bank_texture",
		StationMarker.Kind.HEAL: &"minimap_station_heal_texture",
		StationMarker.Kind.TRAIN: &"minimap_station_train_texture",
		StationMarker.Kind.TECH: &"minimap_station_tech_texture",
		StationMarker.Kind.LEISURE: &"minimap_station_leisure_texture",
		StationMarker.Kind.EXIT: &"minimap_station_exit_texture",
	}
	for kind in pairs:
		var skin := _skin()
		var t := _tex()
		skin.set(pairs[kind], t)
		assert_eq(load(ART).station_texture(skin, kind), t,
			"Kind %d reads %s" % [kind, pairs[kind]])
		# ...and no OTHER kind picked it up.
		for other in pairs:
			if other == kind:
				continue
			assert_null(load(ART).station_texture(skin, other),
				"Kind %d does not read Kind %d's slot" % [other, kind])


## The family badge is the fallback for every kind, which is what lets an artist collapse the alphabet to one
## shape deliberately (and is the honest way to say so).
func test_station_texture_falls_back_to_the_family_badge() -> void:
	var skin := _skin()
	var family := _tex()
	skin.minimap_station_texture = family
	for kind in [StationMarker.Kind.SHOP, StationMarker.Kind.BANK, StationMarker.Kind.HEAL,
			StationMarker.Kind.TRAIN, StationMarker.Kind.TECH, StationMarker.Kind.LEISURE,
			StationMarker.Kind.EXIT]:
		assert_eq(load(ART).station_texture(skin, kind), family,
			"Kind %d with no slot of its own wears the family badge" % kind)
	# A per-kind slot still wins over the family badge.
	var own := _tex()
	skin.minimap_station_exit_texture = own
	assert_eq(load(ART).station_texture(skin, StationMarker.Kind.EXIT), own,
		"a kind's own slot beats the family badge")
	assert_eq(load(ART).station_texture(skin, StationMarker.Kind.SHOP), family,
		"...without disturbing the kinds that have none")


func test_station_texture_ships_null_and_degrades() -> void:
	assert_null(load(ART).station_texture(_skin(), StationMarker.Kind.SHOP),
		"an untouched skin draws the stroked glyph — the shipped look")
	assert_null(load(ART).station_texture(null, StationMarker.Kind.SHOP), "a null skin is not a crash")
	# A future Kind whose slot has not been added here yet falls through to the family badge, mirroring
	# StationMarker.glyph_shape's own CIRCLE degrade rather than vanishing.
	var skin := _skin()
	var family := _tex()
	skin.minimap_station_texture = family
	assert_eq(load(ART).station_texture(skin, 99), family, "an unrecognised Kind still gets the family badge")
	assert_null(load(ART).station_texture(_skin(), 99), "...and nothing when there is no family badge either")


## THE SIZING RULE: art fills the same square the drawn glyph occupied — centred on the marker point, side
## 2x the radius — so a delivered PNG can never set its own footprint on a 108 px box.
func test_glyph_rect_is_the_drawn_glyphs_own_square() -> void:
	var r: Rect2 = load(ART).glyph_rect(Vector2(50.0, 20.0), 4.0)
	assert_eq(r, Rect2(46.0, 16.0, 8.0, 8.0), "centred on the point, side 2x the radius")
	assert_eq(r.get_center(), Vector2(50.0, 20.0), "the marker point stays the centre")


func test_glyph_rect_degrades_on_a_zeroed_radius() -> void:
	# A knob zeroed to switch a channel off must switch its ART off too, not blit at native size.
	assert_eq(load(ART).glyph_rect(Vector2(10.0, 10.0), 0.0), Rect2(), "radius 0 draws nothing")
	assert_eq(load(ART).glyph_rect(Vector2(10.0, 10.0), -3.0), Rect2(), "a negative radius draws nothing")
