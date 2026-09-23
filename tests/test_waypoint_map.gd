extends GutTest

## The WAYPOINT PAINT CHANNEL on the minimap widget (scripts/ui/minimap.gd) — the fourth marker channel, and
## the two query seams the Map tab clicks through. The painting itself is playtest-verified; what is pinned
## here is what would rot silently:
##   * the idle-gate stamp pair, without which a pin added while the player stands still never appears;
##   * the palette wrap, so a saved index from a longer palette still resolves to a real colour;
##   * the view matrix's INVERSE, which is what makes a click land on the metre the player pointed at;
##   * THE PIN/HIT AGREEMENT, per record — the rim rule, the tracked exception and the rim inset are decisions
##     the paint and the hit test must take through the SAME functions, because a rim-pinned glyph sits at a
##     screen point that corresponds to no world point at all. The day they forked, the map grew glyphs you
##     could see and could not click, and the miss fell through to "place a new pin" right under them;
##   * the PAN (view_offset) as a VIEW term: one matrix, so the picture and the click move together, plus the
##     idle-gate stamp without which a drag made while standing still moves nothing;
##   * the label DECLUTTER rule, which is pure geometry and therefore provable with no font and no tree.
##
## Loaded BY PATH and constructed bare, the test_minimap.gd contract: this widget must stay fully functional
## as a `.new()` with no scene, no children and no tree.
##
## ⭐The bare `.new()` is off-tree, so `_draw` never runs on it — most stamps below are moved by calling the
## widget's own accessors, never by rendering, which proves the GATE, the part that decides whether a render ever
## happens. The ONE exception is the wiring test (test_the_channel_is_part_of_the_repaint_decision): _needs_repaint's
## last term scans node groups, so it takes an IN-TREE widget that really paints (the tests/test_minimap.gd
## _idle_minimap idiom) — which is also what proves _draw re-stamps the channel rather than pinning the gate open.

const MINIMAP_SCRIPT := "res://scripts/ui/minimap.gd"
const WAYPOINT_BOOK := "res://scripts/world/waypoint_book.gd"
const LEVEL := "res://tests/_fake_level_wp.tscn"  ## never loaded — the ledger keys on the PATH STRING alone

var _saved_level: String = ""

func before_each() -> void:
	_saved_level = GameState.current_level_path
	GameState.waypoints.clear()
	GameState.current_level_path = LEVEL  # written directly: set_current_level() has side effects

func after_each() -> void:
	GameState.waypoints.clear()
	GameState.current_level_path = _saved_level

func _widget():
	var mm = load(MINIMAP_SCRIPT).new()
	autofree(mm)
	mm.size = GameSettings.hud.minimap_size  # the FALLBACK box — the number the shipped scene was authored from
	return mm


## WHERE THE PAINT WOULD INK THIS RECORD, taken through the widget's own shared decisions rather than through
## a second copy of them. A test that recomputed the rim rule or the pad by hand would happily agree with a
## broken hit test — the whole defect being pinned here is two sites answering the same question differently.
func _pin_point(mm, rec: Dictionary) -> Vector2:
	var skin = MenuStyle.hud
	# Explicitly typed, never `:=` — every read off the untyped widget is a Variant and GDScript refuses to
	# infer from one (the house rule, and a parse error takes the whole file down with it).
	var q: Vector2 = mm._marker_point(rec.get("pos"), mm.view_matrix(), skin,
			mm.waypoint_pins_offscreen(rec), mm._waypoint_pad(skin, mm.waypoint_is_tracked(rec)))
	return q


## Flag a record as the profile's tracked pin. Written STRAIGHT ONTO THE RECORD rather than through
## GameState.set_tracked_waypoint on purpose: what this file pins is how the WIDGET reads the flag, and going
## through the ledger API would make every assertion below fail for two possible reasons instead of one.
## waypoints_for() hands back the live Array, and a Dictionary in it is a reference, so this IS the ledger.
func _track(index: int) -> void:
	var rec: Dictionary = GameState.waypoints_for(LEVEL)[index]
	rec["tracked"] = true


func test_the_channel_ships_on_with_labels_off() -> void:
	var mm = _widget()
	assert_true(mm.dot_waypoints, "the player's own pins draw by default — they are on the map because the player put them there")
	assert_false(mm.waypoint_labels,
		"...but LABELS ship OFF: at ~108 px a caption is most of the HUD box. Only the Map tab turns them on")
	assert_eq(mm.selected_waypoint, -1, "nothing is selected until a host says so (the HUD box never does)")


## The two "Instance view" knobs this channel gained, both INERT on a bare widget — the ~39 `.new()` sites in
## tests/test_minimap.gd and the shipped HUD corner box must behave byte-identically to the day before they landed.
func test_the_pan_and_the_rim_rule_ship_inert() -> void:
	var mm = _widget()
	assert_eq(mm.view_offset, Vector2.ZERO,
		"the HUD corner box is player-centred and owns no gesture that could pan it — only the Map tab writes this")
	assert_false(mm.waypoint_pin_offscreen,
		"...and it DROPS an off-box pin rather than crowding six 5.5 px glyph stacks onto a 108 px rim (the shipped bug)")


# --- The idle gate -------------------------------------------------------------------------------------
## A CanvasItem repaints ONLY on queue_redraw, and this widget's gate deliberately withholds that from a
## player who is standing still. Every fact it paints therefore owes the gate a trailing edge.

func test_the_gate_asks_for_a_repaint_when_a_pin_is_added() -> void:
	var mm = _widget()
	mm._drawn_waypoint_rev = GameState.waypoints_rev
	mm._drawn_waypoint_sel = mm.selected_waypoint
	assert_false(mm._waypoints_changed(), "a settled widget asks for nothing")
	GameState.add_waypoint(LEVEL, Vector3.ZERO, "a", "", 0, 0)
	assert_true(mm._waypoints_changed(),
		"a pin placed while the player stands still MUST ask for the one repaint that puts it on the map")


func test_the_gate_asks_for_a_repaint_when_a_pin_is_deleted() -> void:
	var mm = _widget()
	GameState.add_waypoint(LEVEL, Vector3.ZERO, "a", "", 0, 0)
	mm._drawn_waypoint_rev = GameState.waypoints_rev
	mm._drawn_waypoint_sel = mm.selected_waypoint
	GameState.remove_waypoint(LEVEL, 0)
	assert_true(mm._waypoints_changed(),
		"...and a DELETE most of all: without this the glyph is simply left on the canvas forever")


## The selection ring changes with no ledger mutation at all, so it is the second half of the stamp.
func test_the_gate_asks_for_a_repaint_when_the_selection_moves() -> void:
	var mm = _widget()
	mm._drawn_waypoint_rev = GameState.waypoints_rev
	mm._drawn_waypoint_sel = mm.selected_waypoint
	mm.selected_waypoint = 2
	assert_true(mm._waypoints_changed(), "moving the selection must repaint, or the ring strands on the old pin")


## Seeded to values no live state can reach, so the FIRST compare mismatches and the first paint is honest.
func test_the_stamps_are_seeded_unreachable() -> void:
	var mm = _widget()
	assert_true(mm._waypoints_changed(),
		"a fresh widget asks for its first paint — the stamps seed to values no revision (>= 0) or selection (>= -1) can equal")


## An in-tree, PAINTING widget in the state the idle gate exists for: a settled level and nobody walking. The two
## seeds are what _process would have consumed during a normal boot (tests/test_minimap.gd's _idle_minimap, whose
## note has the full argument): _source_region_id matches this tree's region-less answer so no rebake re-raises
## _deck_dirty, and _deck_dirty itself starts clear so it cannot hold the gate open over everything under it.
## _process then bails at the missing human player, so nothing but _draw ever moves a stamp.
func _idle_widget():
	var mm = load(MINIMAP_SCRIPT).new()
	mm._source_region_id = 0
	mm._deck_dirty = false
	add_child_autofree(mm)
	mm.size = GameSettings.hud.minimap_size
	return mm


## One painted frame: a queued redraw lands at the end of the frame (tests/test_minimap.gd's _repaint).
func _repaint(mm) -> void:
	mm.queue_redraw()
	await get_tree().process_frame
	await get_tree().process_frame


## THE CHANNEL IS WIRED INTO THE GATE, driven through the real paint. The tests above prove the stamp pair
## MOVES; this one proves _needs_repaint actually ASKS it (a term computed but never wired in is a no-op, and the
## pin you just placed never appears) and that _draw re-stamps it (a stamp nothing re-takes pins the gate open at
## full frame rate forever). Both edges, for both halves of the stamp, starting from a gate proven quiet.
func test_the_channel_is_part_of_the_repaint_decision() -> void:
	var mm = _idle_widget()
	await _repaint(mm)
	assert_false(mm._needs_repaint(false), "precondition: an empty map under a standing player is idle")
	mm.selected_waypoint = 1
	assert_true(mm._needs_repaint(false),
		"moving the selection on an otherwise idle map must open the gate — nothing else on the map asks, so the ring would strand on the old pin")
	await _repaint(mm)
	assert_false(mm._needs_repaint(false),
		"...for exactly ONE repaint: the paint re-stamps the selection it drew and the gate shuts again")
	GameState.add_waypoint(LEVEL, mm.point_to_world(mm.size * 0.5), "placed while standing still", "", 0, 0)
	assert_true(mm._needs_repaint(false),
		"a pin placed while the player stands still must open the gate, or it never appears on the map")
	await _repaint(mm)
	assert_false(mm._needs_repaint(false),
		"...and the paint that inks it re-stamps the ledger revision, so a pin on the map costs nothing once drawn")


## The stamp is taken in _draw, NOT inside _paint_waypoints, because that function early-outs on a switched-off
## channel: a stamp taken past the early-out would never move, and a widget with dot_waypoints off would repaint
## at full frame rate for a channel that draws nothing.
func test_a_switched_off_channel_does_not_hold_the_gate_open() -> void:
	var mm = _idle_widget()
	mm.dot_waypoints = false
	await _repaint(mm)
	GameState.add_waypoint(LEVEL, Vector3.ZERO, "hidden", "", 0, 0)
	assert_true(mm._needs_repaint(false), "precondition: the ledger moved, so the gate is open for one paint")
	await _repaint(mm)
	assert_false(mm._needs_repaint(false),
		"with the channel switched off a pin in the ledger must still let the gate shut after one paint — the stamp cannot live behind the channel's early-out")


# --- Tints ---------------------------------------------------------------------------------------------

func test_waypoint_color_reads_the_skin_palette() -> void:
	var mm = _widget()
	var palette: PackedColorArray = MenuStyle.hud.minimap_waypoint_palette
	assert_gt(palette.size(), 0, "the shipped skin authors a palette")
	assert_eq(mm.waypoint_color(0), palette[0], "index 0 is the first authored tint")


## A save written against a longer palette — or a hand-edited index — must still resolve to a REAL colour.
## Wrapping rather than clamping is what keeps every out-of-range pin from collapsing onto the last entry.
func test_waypoint_color_wraps_an_out_of_range_index() -> void:
	var mm = _widget()
	var palette: PackedColorArray = MenuStyle.hud.minimap_waypoint_palette
	var n: int = palette.size()
	assert_eq(mm.waypoint_color(n), palette[0], "one past the end wraps to the start")
	assert_eq(mm.waypoint_color(-1), palette[n - 1], "...and a negative index wraps the other way")


# --- The query seams the Map tab clicks through --------------------------------------------------------

## point_to_world inverts the SAME matrix _draw paints through (view_matrix is the one construction site), so
## a click and the picture it lands on can never drift apart.
func test_point_to_world_inverts_the_view_matrix() -> void:
	var mm = _widget()
	var centre: Vector2 = mm.size * 0.5
	var w: Vector3 = mm.point_to_world(centre)
	assert_almost_eq(w.x, 0.0, 0.001, "the box centre is the player's own position, which a bare widget seeds at the origin")
	assert_almost_eq(w.z, 0.0, 0.001, "...on both axes")
	# ...and a point one px right maps to a point further along +X, at the widget's live scale.
	var ppm: float = mm.pixels_per_metre()
	assert_gt(ppm, 0.0, "a sized widget has a real px-per-metre")
	var off: Vector3 = mm.point_to_world(centre + Vector2(ppm, 0.0))
	assert_almost_eq(off.x, 1.0, 0.001, "one metre's worth of pixels to the right is exactly one world metre east")


## A click-placed pin sits on a STOREY, not at world zero. Before the first grounded sample _ground_y is a
## meaningless 0.0, so the floor of the band being DRAWN is the honest answer; once the player has stood
## somewhere, the floor they stand on wins. Driven two storeys up on purpose: on the ground floor both answers
## ARE world zero and the branch between them is invisible.
func test_point_to_world_puts_a_pin_on_the_drawn_floor() -> void:
	var mm = _widget()
	var band: float = GameSettings.hud.minimap_band_height
	assert_gt(band, 0.0, "precondition: the shipped tuning slices real floor bands")
	var standing_y: float = band * 2.5
	mm._ensure_deck(null, standing_y)  # the deck _process builds for a player at that height (null = no navmesh region)
	var floor_y: float = mm.active_band_floor()
	assert_gt(floor_y, 0.0, "precondition: the drawn deck is off the ground floor, so its floor is not world zero")
	assert_true(floor_y <= standing_y and standing_y < floor_y + band,
		"precondition: the drawn deck is the band the player is standing in")
	var centre: Vector2 = mm.size * 0.5
	assert_almost_eq(mm.point_to_world(centre).y, floor_y, 0.001,
		"before a grounded sample a pin lands on the floor of the band being DRAWN, never at world zero")
	var body := Node3D.new()
	add_child_autofree(body)  # global_position on an off-tree Node3D is an engine error
	body.global_position = Vector3(0.0, floor_y + 1.25, 0.0)  # no is_on_floor(): tracks live Y, the documented degrade
	mm._update_ground_reference(body)
	assert_almost_eq(mm.point_to_world(centre).y, floor_y + 1.25, 0.001,
		"once the player has a grounded floor a pin lands on THAT floor — the one they stand on, not the band's lower edge")


func test_waypoint_at_point_hits_a_pin_and_misses_empty_map() -> void:
	var mm = _widget()
	var centre: Vector2 = mm.size * 0.5
	assert_eq(mm.waypoint_at_point(centre), -1, "an empty ledger answers -1 — the click becomes a NEW pin")
	# Place a pin exactly under the box centre by asking the widget where that is.
	var here: Vector3 = mm.point_to_world(centre)
	GameState.add_waypoint(LEVEL, here, "under the cursor", "", 0, 0)
	assert_eq(mm.waypoint_at_point(centre), 0, "a click on a pin's glyph SELECTS it rather than stacking a second pin on it")


## THE TARGET IS THE GLYPH, NOT THE NEIGHBOURHOOD. The pin is drawn ON the box (no cull, no rim rule in play), so the
## only thing that can turn a click beside it into a miss is the hit tolerance itself. The control clicks the glyph's
## own rim and selects it; the miss lands one whole glyph width of empty map past that rim, still on the box. A
## tolerance measured in metres, or widened to "the nearest pin anywhere near", would select the pin from there.
func test_waypoint_at_point_misses_a_pin_just_beside_its_glyph() -> void:
	var mm = _widget()
	mm.zoom_override = 1.0
	var centre: Vector2 = mm.size * 0.5
	var reach: float = MenuStyle.hud.minimap_waypoint_glyph_px
	assert_gt(reach, 0.0, "precondition: the shipped skin draws a real glyph")
	GameState.add_waypoint(LEVEL, mm.point_to_world(centre), "here", "", 0, 0)
	var q: Vector2 = _pin_point(mm, GameState.waypoint_at(LEVEL, 0))
	var box := Rect2(Vector2.ZERO, mm.size)
	assert_true(box.has_point(q), "precondition: the pin is drawn inside the box, not culled or rim-pinned")
	assert_eq(mm.waypoint_at_point(q + Vector2(0.0, reach)), 0,
		"control: a click on the glyph's own rim selects the pin")
	var beside: Vector2 = q + Vector2(0.0, reach * 3.0)
	assert_true(box.has_point(beside), "precondition: the click beside the glyph is still on the box, on empty map")
	assert_eq(mm.waypoint_at_point(beside), -1,
		"a click one glyph width clear of the pin's rim is empty floor and must place a NEW pin — the hit target is the glyph's own drawn radius plus a few px of slop, not a wider neighbourhood around it")


## ZOOM MOVES THE GLYPH, AND THE CLICK TARGET MOVES WITH IT AT A CONSTANT PIXEL SIZE. The tolerance is the glyph's
## drawn radius in real pixels — what the player is actually aiming at — so zooming must neither shrink it (a
## zoomed-in pin you cannot hit) nor grow it with the metres (a click where the glyph USED to be still selecting it,
## instead of placing a new pin on the empty floor under the cursor).
func test_the_hit_target_follows_the_zoom_at_a_constant_pixel_size() -> void:
	var mm = _widget()
	var centre: Vector2 = mm.size * 0.5
	var reach: float = MenuStyle.hud.minimap_waypoint_glyph_px
	assert_gt(reach, 0.0, "precondition: the shipped skin draws a real glyph")
	mm.zoom_override = 1.0
	# One glyph radius east of the player: four times that is still well inside the box, and the 3x gap zooming
	# opens between the old spot and the new one is wider than any click target sized off the glyph itself.
	GameState.add_waypoint(LEVEL, mm.point_to_world(centre + Vector2(reach, 0.0)), "east", "", 0, 0)
	var rec: Dictionary = GameState.waypoint_at(LEVEL, 0)
	var at_1x: Vector2 = _pin_point(mm, rec)
	assert_eq(mm.waypoint_at_point(at_1x + Vector2(0.0, reach)), 0, "at 1x a click on the glyph's rim selects it")
	mm.zoom_override = 4.0
	var at_4x: Vector2 = _pin_point(mm, rec)
	assert_true(Rect2(Vector2.ZERO, mm.size).has_point(at_4x), "precondition: the zoomed glyph is still on the box, not culled")
	assert_almost_eq(at_4x.distance_to(centre), 4.0 * at_1x.distance_to(centre), 0.01,
		"zooming 4x magnifies the map around the player, so the glyph is painted four times as far from the centre")
	assert_eq(mm.waypoint_at_point(at_4x + Vector2(0.0, reach)), 0,
		"...and a click the SAME number of pixels off the zoomed glyph still selects it — the target never shrinks with zoom")
	assert_eq(mm.waypoint_at_point(at_1x), -1,
		"...while a click where the glyph WAS at 1x misses — the target follows the paint and does not swell with the metres")


## THE RIM-CLICK AGREEMENT: on a host that pins (the MAP TAB — the editing surface, where a pin you cannot see
## is a pin you cannot select) an off-view pin is drawn PINNED to the rim, and clicking that visible glyph must
## select it — not fall through to "place a new pin here" (the defect the first, world-space hit test shipped).
## The rim point comes from the widget's own shared projection, which is exactly the contract: hit and paint
## share one answer and cannot disagree.
func test_a_rim_pinned_glyph_is_clickable() -> void:
	var mm = _widget()
	mm.waypoint_pin_offscreen = true  # what map_screen.gd pushes from _bind_ui
	var far: Vector3 = mm.point_to_world(mm.size * 0.5) + Vector3(500, 0, 0)  # well past the view at any shipped span
	GameState.add_waypoint(LEVEL, far, "far away", "", 0, 0)
	var q: Vector2 = _pin_point(mm, GameState.waypoint_at(LEVEL, 0))
	assert_ne(q, Vector2.INF, "the far pin rim-pins rather than culling on a host that asked for it")
	assert_eq(mm.waypoint_at_point(q), 0,
		"clicking the rim-pinned glyph selects the pin it draws — visible must mean clickable")


## ...AND THE SAME AGREEMENT FROM THE OTHER SIDE, which is the half the HUD box needs. With the rim rule OFF an
## off-box pin is not drawn at all, so the rim point it WOULD have pinned to must be empty map. A hit test that
## kept the old hardcoded `true` would answer "pin 0" for a click on a bare rim — selecting something invisible.
func test_the_hud_box_drops_an_off_box_pin_from_the_paint_and_the_hit_test_alike() -> void:
	var mm = _widget()  # waypoint_pin_offscreen FALSE: the shipped corner box
	var far: Vector3 = mm.point_to_world(mm.size * 0.5) + Vector3(500, 0, 0)
	GameState.add_waypoint(LEVEL, far, "over there", "", 0, 0)
	var rec: Dictionary = GameState.waypoint_at(LEVEL, 0)
	assert_false(mm.waypoint_pins_offscreen(rec), "an ordinary pin obeys the host's rim rule")
	assert_eq(_pin_point(mm, rec), Vector2.INF, "so it is not inked at all")
	var skin = MenuStyle.hud
	var rim: Vector2 = mm._marker_point(far, mm.view_matrix(), skin, true, mm._waypoint_pad(skin, false))
	assert_ne(rim, Vector2.INF, "precondition: it WOULD have pinned there on a host that pins")
	assert_eq(mm.waypoint_at_point(rim), -1,
		"...and that rim point is empty map — a click there places a NEW pin, because nothing is drawn under it")


## THE TRACKED PIN IS THE STANDING EXCEPTION: one pin per profile is the player's declared destination, and
## pointing at it from the rim IS the navigation loop. It overrides the host's rim rule on the HUD box, where
## every other off-box pin is dropped — and it must stay clickable there, by the same agreement.
func test_the_tracked_pin_always_pins_even_on_the_hud_box() -> void:
	var mm = _widget()  # waypoint_pin_offscreen FALSE
	var far: Vector3 = mm.point_to_world(mm.size * 0.5) + Vector3(500, 0, 0)
	GameState.add_waypoint(LEVEL, far, "the objective", "", 0, 0)
	_track(0)
	var rec: Dictionary = GameState.waypoint_at(LEVEL, 0)
	assert_true(mm.waypoint_is_tracked(rec), "precondition: the record carries the flag")
	assert_true(mm.waypoint_pins_offscreen(rec), "the tracked pin overrides the host's rim rule")
	var q: Vector2 = _pin_point(mm, rec)
	assert_ne(q, Vector2.INF, "so it rim-pins on a box that drops every other off-box pin")
	assert_eq(mm.waypoint_at_point(q), 0, "and clicking that glyph selects it")


## An UNTRACKED record must not read as tracked through a missing key, a legacy save or a junk value — the flag
## is optional on the record (WaypointBook.make() stays five fields) and absent means false.
##
## ⭐The numeric case is the one that proves the WIDGET DELEGATES rather than keeping its own copy of the rule.
## A hand-edited profile can hold `tracked=1` where ConfigFile writes `tracked=true`, and WaypointBook.is_tracked
## — the one definition, shared with the ledger's load fold — counts it. A private `== true` here would read that
## same pin as untracked, so the map would drop the very pin the compass was pointing at.
func test_an_ordinary_record_is_not_tracked() -> void:
	var mm = _widget()
	GameState.add_waypoint(LEVEL, Vector3.ZERO, "plain", "", 0, 0)
	assert_false(mm.waypoint_is_tracked(GameState.waypoint_at(LEVEL, 0)),
		"a record with no `tracked` key — every pin saved before the feature existed — is not the tracked pin")
	assert_false(mm.waypoint_is_tracked({}), "...and neither is a missing record")
	assert_false(mm.waypoint_is_tracked({"tracked": "yes"}),
		"...nor a junk STRING value, which must degrade rather than hard-error (there is no bool(String) in GDScript 4)")
	assert_true(mm.waypoint_is_tracked({"tracked": 1}),
		"but a hand-edited numeric flag counts — the widget asks WaypointBook.is_tracked, it does not re-decide")


## The tracked ring sits one selected-gap OUTSIDE the selection ring, so a pin wearing both reads as two rings
## instead of one painted twice — and the rim inset has to reserve room for the outer one or clip_contents
## slices it. Both sites derive the inset from this one function, so the pinned glyph's screen point moves with it.
func test_the_tracked_pin_reserves_room_for_its_outer_ring() -> void:
	var mm = _widget()
	var skin = MenuStyle.hud
	assert_gt(mm._waypoint_pad(skin, true), mm._waypoint_pad(skin, false),
		"a tracked pin needs one more gap of rim inset than a plain one — its ring is one gap further out")
	# ...and the inset really keeps the rings ON the box. Two far pins pinned into the same corner — one plain, one
	# tracked — measured against the ring radii _paint_waypoints inks around them: the selection ring every pin
	# may wear, and the tracked ring one gap outside it. A ring crossing the box edge is sliced by clip_contents.
	var r: float = skin.minimap_waypoint_glyph_px
	var gap: float = maxf(0.0, skin.minimap_waypoint_selected_gap_px)
	mm.waypoint_pin_offscreen = true
	var far: Vector3 = mm.point_to_world(mm.size * 0.5) + Vector3(500, 0, 500)  # off the box's corner
	GameState.add_waypoint(LEVEL, far, "plain", "", 0, 0)
	GameState.add_waypoint(LEVEL, far, "the objective", "", 0, 0)
	_track(1)
	for probe in [[0, r + gap, "a plain pin's selection ring"], [1, r + gap * 2.0, "the tracked pin's outer ring"]]:
		var ring: float = probe[1]
		var q: Vector2 = _pin_point(mm, GameState.waypoint_at(LEVEL, probe[0]))
		assert_ne(q, Vector2.INF, "precondition: pin %d rim-pins" % probe[0])
		assert_true(q.x - ring >= 0.0 and q.y - ring >= 0.0 and q.x + ring <= mm.size.x and q.y + ring <= mm.size.y,
			"%s must sit wholly inside the %s box at its rim point %s (radius %.1f) — the rim inset exists so clip_contents never slices it" % [probe[2], mm.size, q, ring])


## THE DISTANCE CULL, clicked exactly where the glyph would be. A pin 15 m out sits inside the box at 1x, so with no
## cull it is drawn and clickable at one known point (the control). Switching a 10 m cull on must take it out of the
## paint AND out of the hit test AT THAT SAME POINT — the click lands on the very pixel the glyph used to occupy, so
## a hit test that ignored max_marker_distance is the only thing that could still answer 0 there.
func test_a_distance_culled_pin_is_not_clickable() -> void:
	var mm = _widget()
	mm.zoom_override = 1.0
	var here: Vector3 = mm.point_to_world(mm.size * 0.5)
	GameState.add_waypoint(LEVEL, here + Vector3(15.0, 0.0, 0.0), "culled", "", 0, 0)
	var rec: Dictionary = GameState.waypoint_at(LEVEL, 0)
	var would: Vector2 = _pin_point(mm, rec)
	assert_true(Rect2(Vector2.ZERO, mm.size).has_point(would),
		"precondition: with no cull the 15 m pin is drawn inside the box, so neither the rim rule nor the off-box drop is in play")
	assert_eq(mm.waypoint_at_point(would), 0, "control: with no cull a click on that glyph selects the pin")
	mm.max_marker_distance = 10.0
	assert_eq(_pin_point(mm, rec), Vector2.INF, "a 10 m cull removes the 15 m pin from the paint")
	assert_eq(mm.waypoint_at_point(would), -1,
		"...and what is not drawn is not clickable — a click on the spot the glyph used to occupy is empty map, because the hit test honours the same cull")


func test_the_channel_reads_the_current_level_only() -> void:
	var mm = _widget()
	GameState.add_waypoint(LEVEL, mm.point_to_world(mm.size * 0.5), "here", "", 0, 0)
	GameState.current_level_path = "res://tests/_fake_level_elsewhere.tscn"
	assert_eq(mm.waypoint_at_point(mm.size * 0.5), -1,
		"pins are per-level: walking into another district must not leave the last one's pins clickable")


# --- The pan (view_offset) -------------------------------------------------------------------------------
## The map is player-CENTRED by construction, which capped the reachable world at the zoom floor's ~240 m
## around the player — a plaza on a district map. view_offset is the drag, and it is a VIEW term: applied
## inside view_matrix(), the single construction site, so the picture and every query move as one.

func test_the_pan_moves_the_whole_view_through_the_one_matrix() -> void:
	var mm = _widget()
	var centre: Vector2 = mm.size * 0.5
	var before: Vector3 = mm.point_to_world(centre)
	mm.view_offset = Vector2(25.0, -10.0)
	var after: Vector3 = mm.point_to_world(centre)
	assert_almost_eq(after.x - before.x, 25.0, 0.001,
		"panning +x moves the metre under the box centre east by exactly that many metres")
	assert_almost_eq(after.z - before.z, -10.0, 0.001,
		"...and +y is world +Z, the north-up handedness the map tab reads in")


## The hit test inverts the SAME matrix, so a pin stays clickable exactly where the pan put it. If the offset
## were applied at a paint site instead, the picture would move and the click would not (or the reverse).
func test_a_pin_stays_clickable_after_a_pan() -> void:
	var mm = _widget()
	mm.waypoint_pin_offscreen = true
	var centre: Vector2 = mm.size * 0.5
	var here: Vector3 = mm.point_to_world(centre)
	GameState.add_waypoint(LEVEL, here, "under the cursor", "", 0, 0)
	assert_eq(mm.waypoint_at_point(centre), 0, "precondition: it is under the centre before the pan")
	mm.view_offset = Vector2(30.0, 0.0)
	assert_eq(mm.waypoint_at_point(centre), -1, "the pan slid it off the centre — the click follows the picture")
	assert_eq(mm.waypoint_at_point(_pin_point(mm, GameState.waypoint_at(LEVEL, 0))), 0,
		"...and it is still clickable at the point the paint now inks it")


## A widget that has never painted must ask for its first paint on the pan term's account too — even when its pan
## sits at ZERO, the shipped HUD box's REAL offset. A stamp seeded to a value live state can hold would start life
## claiming a paint that never happened. Every OTHER view term is settled first, so the pan is the only one left
## that could be asking; the control at the end proves it was.
func test_the_pan_stamp_is_seeded_unreachable() -> void:
	var mm = _widget()
	mm._drawn_zoom = mm.effective_zoom()
	mm._drawn_span = mm.effective_world_span()
	mm._drawn_rotates = mm.effective_rotates()
	mm._drawn_show_npcs = Settings.minimap_show_npcs
	mm._drawn_show_stations = Settings.minimap_show_stations
	assert_eq(mm.view_offset, Vector2.ZERO, "precondition: an un-panned widget, exactly the HUD corner box's live state")
	assert_true(mm._options_changed(),
		"a never-painted widget with its pan at ZERO must still ask for the first paint — ZERO is a legitimate live pan, so it cannot be what the stamp seeds to")
	mm._drawn_view_offset = mm.view_offset
	assert_false(mm._options_changed(),
		"control: once the pan is stamped the view terms go quiet, so the pan stamp alone was what asked")


## ⭐THE TERM THE WHOLE FEATURE HANGS ON. Dragging the map is the exact case the idle gate withholds repaints
## from: nothing on the map moved, nobody walked, no Options row changed. Without this stamp the mouse would
## slide and the picture would sit still.
##
## Asked through _options_changed() rather than _needs_repaint(), and deliberately: that gate's last term
## scans two node groups, which needs a tree this bare `.new()` does not have (get_tree() on an off-tree Node
## is an ENGINE ERROR, and GUT 9.6 fails a whole suite on one). _needs_repaint already consults
## _options_changed() — tests/test_minimap.gd pins that wiring against the other five terms in the same family.
func test_the_gate_asks_for_a_repaint_when_the_view_is_panned() -> void:
	var mm = _widget()
	mm._drawn_zoom = mm.effective_zoom()
	mm._drawn_span = mm.effective_world_span()
	mm._drawn_rotates = mm.effective_rotates()
	mm._drawn_view_offset = mm.view_offset
	mm._drawn_show_npcs = Settings.minimap_show_npcs
	mm._drawn_show_stations = Settings.minimap_show_stations
	assert_false(mm._options_changed(), "precondition: a settled widget asks for nothing")
	mm.view_offset = Vector2(12.0, 0.0)
	assert_true(mm._options_changed(),
		"a drag made while the player stands still MUST ask for the one repaint that moves the map")


# --- Label declutter -------------------------------------------------------------------------------------
## Pure geometry, so it is provable with no font, no theme and no tree. Four pins in one building put four
## captions on the same dozen pixels; the result was ink rather than names.

func test_overlapping_captions_are_dropped_rather_than_overprinted() -> void:
	var mm = _widget()
	var rects: Array[Rect2] = [
		Rect2(0.0, 0.0, 40.0, 10.0),
		Rect2(5.0, 2.0, 40.0, 10.0),    # lands on top of the first
		Rect2(100.0, 0.0, 40.0, 10.0),  # clear of both
	]
	assert_eq(Array(mm.declutter_labels(rects, -1)), [0, 2],
		"first come, first served: the collider is dropped whole rather than half-drawn over its neighbour")


## Adjacency is not collision — two captions that merely touch are both readable, and dropping one of them
## would thin the map for nothing.
func test_captions_that_only_touch_both_survive() -> void:
	var mm = _widget()
	var rects: Array[Rect2] = [Rect2(0.0, 0.0, 40.0, 10.0), Rect2(40.0, 0.0, 40.0, 10.0)]
	assert_eq(Array(mm.declutter_labels(rects, -1)).size(), 2, "shared edges are not an overlap")


## THE SELECTED PIN'S CAPTION IS NEVER THE ONE THAT LOSES. It is reserved before the greedy walk (so a
## neighbour yields to it rather than the other way round) and painted LAST, on top of anything that got
## through — the pin the player is working on must always be named.
func test_the_selected_caption_wins_its_collisions_and_paints_last() -> void:
	var mm = _widget()
	var stacked: Array[Rect2] = [Rect2(0.0, 0.0, 40.0, 10.0), Rect2(2.0, 1.0, 40.0, 10.0)]
	assert_eq(Array(mm.declutter_labels(stacked, 1)), [1],
		"the selected caption is reserved first, so the pin that arrived earlier is the one that yields")
	var spread: Array[Rect2] = [Rect2(0.0, 0.0, 10.0, 10.0), Rect2(100.0, 0.0, 10.0, 10.0)]
	assert_eq(Array(mm.declutter_labels(spread, 0)), [1, 0],
		"...and it is drawn LAST even when nothing collides, so it lands on top of the whole channel")


func test_declutter_survives_an_out_of_range_selection() -> void:
	var mm = _widget()
	var rects: Array[Rect2] = [Rect2(0.0, 0.0, 10.0, 10.0)]
	assert_eq(Array(mm.declutter_labels(rects, 4)), [0],
		"a selection that names no queued caption (off-box, or blank) is simply no reservation")
	var empty: Array[Rect2] = []
	assert_eq(Array(mm.declutter_labels(empty, 0)), [],
		"...and an empty queue draws nothing rather than indexing into it")
