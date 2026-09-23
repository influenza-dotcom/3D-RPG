extends GutTest

## The compass marker channel, end to end: Compass.project_to_edge (the pure screen-edge projection), the
## WorldMarker opt-in/out of the compass + minimap channels, Compass.marker_color's colour priority, and
## QuestMarkerSync turning an objective's authored marker fields into a live WorldMarker (placed, tinted,
## removed when the objective is done). The compass DRAWING is playtest-verified; QuestMarkerSync's
## "a failed quest drops its markers" (WR-6) contract is pinned in test_quests.gd.

const CompassScript = preload("res://scripts/ui/compass.gd")
const WorldMarkerScript = preload("res://scripts/components/world_marker.gd")
const QuestMarkerSyncScript = preload("res://scripts/components/quest_marker_sync.gd")

## Set by the QuestMarkerSync tests, which start quests on the shared GameState AUTOLOAD (the sync hard-references
## it — the test_quests.gd idiom); after_each then resets it so no active quest leaks into the next suite.
var _started_quests := false

func after_each() -> void:
	if _started_quests:
		GameState.reset_for_new_game()
		_started_quests = false

func test_project_to_edge_cardinals() -> void:
	var size := Vector2(800, 600)  # center (400, 300)
	var right := CompassScript.project_to_edge(Vector2(1, 0), size, 0.0)
	assert_almost_eq(right.x, 800.0, 0.5, "due-right hits the right edge")
	assert_almost_eq(right.y, 300.0, 0.5, "...at vertical center")
	var down := CompassScript.project_to_edge(Vector2(0, 1), size, 0.0)
	assert_almost_eq(down.y, 600.0, 0.5, "due-down hits the bottom edge")
	assert_almost_eq(down.x, 400.0, 0.5, "...at horizontal center")
	var left := CompassScript.project_to_edge(Vector2(-1, 0), size, 0.0)
	assert_almost_eq(left.x, 0.0, 0.5, "due-left hits the left edge")

func test_project_to_edge_zero_is_center() -> void:
	var c := CompassScript.project_to_edge(Vector2.ZERO, Vector2(800, 600), 0.0)
	assert_almost_eq(c.x, 400.0, 0.5, "zero dir -> center x")
	assert_almost_eq(c.y, 300.0, 0.5, "zero dir -> center y")

func test_project_to_edge_margin_insets() -> void:
	var right := CompassScript.project_to_edge(Vector2(1, 0), Vector2(800, 600), 20.0)
	assert_almost_eq(right.x, 780.0, 0.5, "margin insets the right edge by 20")

func test_project_to_edge_diagonal_stays_in_rect() -> void:
	var size := Vector2(800, 600)
	var d := CompassScript.project_to_edge(Vector2(1, 1), size, 0.0)
	assert_true(d.x <= 800.5 and d.y <= 600.5, "lands within the rect")
	assert_true(d.x >= 400.0 and d.y >= 300.0, "...in the down-right quadrant")
	assert_almost_eq(d.y, 600.0, 0.5, "45deg on a 4:3 rect hits the bottom (height is the limiting half)")

func test_world_marker_joins_channels() -> void:
	var m = WorldMarkerScript.new()
	add_child_autofree(m)  # _ready adds the groups
	# Through the Groups registry, the same names the Compass / HudCompass / Minimap consumers query.
	assert_true(m.is_in_group(Groups.COMPASS), "WorldMarker joins the compass channel")
	assert_true(m.is_in_group(Groups.MINIMAP), "WorldMarker joins the minimap channel")

func test_world_marker_channel_opt_out() -> void:
	var m = WorldMarkerScript.new()
	m.on_compass = false
	add_child_autofree(m)
	assert_false(m.is_in_group(Groups.COMPASS), "on_compass off -> not on the compass channel")
	assert_true(m.is_in_group(Groups.MINIMAP), "still on the minimap channel")

func test_marker_color_prefers_markers_own_then_skin_fallback() -> void:
	var c = CompassScript.new()
	autofree(c)
	var m = WorldMarkerScript.new()  # off-tree: no _ready, marker_color only .get()s the export
	autofree(m)
	var own := Color(0.1, 0.2, 0.3)
	# Precondition: the marker's own tint must differ from the skin fallback, or "own wins" could not be told apart
	# from "always the fallback".
	assert_ne(own, MenuStyle.hud.compass_fallback_color, "precondition: the test tint is not the skin fallback")
	m.color = own
	assert_eq(c.marker_color(m), own, "a marker's own color wins")
	var bare := Node3D.new()  # no `color` property at all -> the artist skin's fallback
	autofree(bare)
	assert_eq(c.marker_color(bare), MenuStyle.hud.compass_fallback_color,
			"colourless marker falls back to MenuStyle.hud.compass_fallback_color")

func test_wants_marker_pure() -> void:
	assert_false(QuestMarkerSyncScript.wants_marker(null), "null objective wants no marker")
	var o := QuestObjective.new()
	assert_false(QuestMarkerSyncScript.wants_marker(o), "show_marker off -> no marker")
	o.show_marker = true
	assert_true(QuestMarkerSyncScript.wants_marker(o), "show_marker on -> wants a marker")
	o = null

# --- QuestMarkerSync: authored marker fields -> a live WorldMarker ------------------------------------------

func _objective(oid: StringName, marked: bool, at: Vector3) -> QuestObjective:
	var o := QuestObjective.new()
	o.id = oid
	o.required_count = 1
	o.show_marker = marked
	o.marker_position = at
	return o

## The sync's LIVE markers: a rebuild queue_free()s the previous set, which only leaves the tree at the next
## frame flush, so a node already queued for deletion is not a marker the player can see.
func _live_markers(sync: Node) -> Array[Node3D]:
	var out: Array[Node3D] = []
	for child in sync.get_children():
		if child is Node3D and not child.is_queued_for_deletion():
			out.append(child as Node3D)
	return out

func test_quest_marker_sync_places_a_tinted_beacon_only_for_a_marked_objective() -> void:
	_started_quests = true
	GameState.reset_for_new_game()
	var sync = QuestMarkerSyncScript.new()
	sync.marker_color = Color(0.2, 0.7, 0.4)
	add_child_autofree(sync)  # _ready connects the QuestTracker signals and does the first (empty) rebuild
	assert_eq(_live_markers(sync).size(), 0, "control: no active quest -> no beacon")
	var q := Quest.new()
	q.id = &"compass_marked"
	# One objective left at its authored defaults (only the fields every objective needs are set, so show_marker is
	# whatever a designer gets from a fresh QuestObjective), one opted in at a real destination.
	var unmarked := QuestObjective.new()
	unmarked.id = &"unmarked"
	unmarked.required_count = 1
	q.objectives.append(unmarked)
	q.objectives.append(_objective(&"marked", true, Vector3(4.0, 1.5, 7.0)))
	GameState.start_quest(q)
	var markers := _live_markers(sync)
	assert_eq(markers.size(), 1,
		"only the objective with show_marker gets a beacon — an objective left at its defaults must not put a chevron on the compass")
	if markers.size() != 1:
		return
	var beacon := markers[0]
	assert_true(beacon is WorldMarker, "the spawned beacon is a real WorldMarker (it is what the HUD channels read)")
	assert_true(beacon.global_position.is_equal_approx(Vector3(4.0, 1.5, 7.0)),
		"the beacon sits at the objective's marker_position (got %s) — anywhere else points the player the wrong way" % beacon.global_position)
	assert_eq(beacon.get(&"color"), Color(0.2, 0.7, 0.4), "the beacon wears the sync's marker_color tint")
	assert_true(beacon.is_in_group(Groups.COMPASS), "the beacon is on the compass channel, so the heading tape shows it")
	q = null

func test_quest_marker_sync_drops_a_done_objectives_beacon_and_keeps_the_rest() -> void:
	_started_quests = true
	GameState.reset_for_new_game()
	var sync = QuestMarkerSyncScript.new()
	add_child_autofree(sync)
	var q := Quest.new()
	q.id = &"compass_two_stops"
	q.objectives.append(_objective(&"first_stop", true, Vector3(1.0, 0.0, 0.0)))
	q.objectives.append(_objective(&"second_stop", true, Vector3(0.0, 0.0, 12.0)))
	GameState.start_quest(q)
	assert_eq(_live_markers(sync).size(), 2, "control: two marked objectives -> two beacons")
	GameState.advance_objective(&"compass_two_stops", &"first_stop")
	assert_true(GameState.is_quest_active(&"compass_two_stops"), "precondition: one stop left, the quest is still running")
	var markers := _live_markers(sync)
	assert_eq(markers.size(), 1, "a finished objective's beacon is removed — it must not keep pointing at a place already visited")
	if markers.size() == 1:
		assert_true(markers[0].global_position.is_equal_approx(Vector3(0.0, 0.0, 12.0)),
			"the surviving beacon is the UNFINISHED objective's (got %s)" % markers[0].global_position)
	q = null
