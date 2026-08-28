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
## ⭐The bare `.new()` is off-tree, so `_draw` never runs — every stamp below is moved by calling the widget's
## own accessors, never by rendering. That is deliberate: it proves the GATE, which is the part that decides
## whether a render ever happens.

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


func test_the_channel_is_part_of_the_repaint_decision() -> void:
	var mm = _widget()
	mm._deck_dirty = false
	mm._painted = false
	mm._drawn_waypoint_rev = GameState.waypoints_rev
	mm._drawn_waypoint_sel = mm.selected_waypoint
	var quiet: bool = mm._needs_repaint(false)
	mm.selected_waypoint = 1
	assert_true(mm._needs_repaint(false),
		"_needs_repaint must actually CONSULT the waypoint stamp — a term computed but never wired in is a no-op (was quiet: %s)" % quiet)


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


func test_point_to_world_puts_a_pin_on_the_drawn_floor() -> void:
	var mm = _widget()
	assert_almost_eq(mm.point_to_world(mm.size * 0.5).y, mm.active_band_floor(), 0.001,
		"before a grounded sample the pin lands on the band being DRAWN, never at world zero")


func test_waypoint_at_point_hits_a_pin_and_misses_empty_map() -> void:
	var mm = _widget()
	var centre: Vector2 = mm.size * 0.5
	assert_eq(mm.waypoint_at_point(centre), -1, "an empty ledger answers -1 — the click becomes a NEW pin")
	# Place a pin exactly under the box centre by asking the widget where that is.
	var here: Vector3 = mm.point_to_world(centre)
	GameState.add_waypoint(LEVEL, here, "under the cursor", "", 0, 0)
	assert_eq(mm.waypoint_at_point(centre), 0, "a click on a pin's glyph SELECTS it rather than stacking a second pin on it")


func test_waypoint_at_point_misses_a_pin_far_away() -> void:
	var mm = _widget()
	var centre: Vector2 = mm.size * 0.5
	GameState.add_waypoint(LEVEL, mm.point_to_world(centre) + Vector3(50, 0, 50), "far", "", 0, 0)
	assert_eq(mm.waypoint_at_point(centre), -1,
		"the hit tolerance is the glyph's own drawn size, not the whole map — a click on empty floor places a pin")


## The tolerance is a PIXEL radius converted through the live scale, so it stays a constant on-screen target
## at every zoom — which is what the player is actually aiming at.
func test_the_hit_tolerance_tracks_zoom() -> void:
	var mm = _widget()
	var centre: Vector2 = mm.size * 0.5
	mm.zoom_override = 1.0
	var reach_at_1x: float = mm.point_to_world(centre + Vector2(1.0, 0.0)).x
	mm.zoom_override = 4.0
	var reach_at_4x: float = mm.point_to_world(centre + Vector2(1.0, 0.0)).x
	assert_lt(reach_at_4x, reach_at_1x,
		"zoomed IN, one pixel is fewer metres — so the same pixel tolerance covers a smaller patch of world")


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
	assert_almost_eq(mm._waypoint_pad(skin, false),
		float(skin.minimap_waypoint_glyph_px) + maxf(0.0, skin.minimap_waypoint_selected_gap_px), 0.0001,
		"the plain inset is unchanged: the glyph plus the selection ring's gap, reserved for every pin")


func test_a_distance_culled_pin_is_not_clickable() -> void:
	var mm = _widget()
	mm.waypoint_pin_offscreen = true  # prove the CULL, not the rim rule
	mm.max_marker_distance = 10.0
	var far: Vector3 = mm.point_to_world(mm.size * 0.5) + Vector3(500, 0, 0)
	GameState.add_waypoint(LEVEL, far, "culled", "", 0, 0)
	assert_eq(_pin_point(mm, GameState.waypoint_at(LEVEL, 0)), Vector2.INF,
		"the cull really removes it from the paint")
	assert_eq(mm.waypoint_at_point(mm.size * 0.5), -1,
		"...and what is not drawn is not clickable — the hit test honours the same cull")


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


## Seeded to a value no finite pan can equal, so the FIRST compare mismatches. ZERO would have been wrong:
## that is the shipped HUD box's REAL offset, so a widget would have started life claiming its stamp was current.
func test_the_pan_stamp_is_seeded_unreachable() -> void:
	var mm = _widget()
	assert_eq(mm._drawn_view_offset, Vector2.INF,
		"the pan stamp seeds to INF — ZERO is a legitimate live value and could not serve as the sentinel")


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
