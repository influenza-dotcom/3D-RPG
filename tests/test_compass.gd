extends GutTest

## Rank 30: Compass.project_to_edge (the pure screen-edge projection) + WorldMarker channel membership +
## QuestObjective marker fields + QuestMarkerSync.wants_marker. The compass DRAWING is playtest-verified; the edge
## math + wiring are unit-tested here, and QuestMarkerSync's in-tree rebuild (including the WR-6 "a failed quest
## drops its markers" contract) is pinned in test_quests.gd.

const CompassScript = preload("res://scripts/ui/compass.gd")
const WorldMarkerScript = preload("res://scripts/components/world_marker.gd")
const QuestMarkerSyncScript = preload("res://scripts/components/quest_marker_sync.gd")

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
	assert_true(m.is_in_group("compass"), "WorldMarker joins the compass channel")
	assert_true(m.is_in_group("minimap"), "WorldMarker joins the minimap channel")

func test_world_marker_channel_opt_out() -> void:
	var m = WorldMarkerScript.new()
	m.on_compass = false
	add_child_autofree(m)
	assert_false(m.is_in_group("compass"), "on_compass off -> not on the compass channel")
	assert_true(m.is_in_group("minimap"), "still on the minimap channel")

func test_marker_color_prefers_markers_own_then_skin_fallback() -> void:
	var c = CompassScript.new()
	autofree(c)
	var m = WorldMarkerScript.new()  # off-tree: no _ready, marker_color only .get()s the export
	autofree(m)
	m.color = Color(0.1, 0.2, 0.3)
	assert_eq(c.marker_color(m), Color(0.1, 0.2, 0.3), "a marker's own color wins")
	var bare := Node3D.new()  # no `color` property at all -> the artist skin's fallback gold
	autofree(bare)
	assert_eq(c.marker_color(bare), MenuStyle.hud.compass_fallback_color,
			"colourless marker falls back to MenuStyle.hud.compass_fallback_color")
	assert_eq(MenuStyle.hud.compass_fallback_color, Color(1.0, 0.85, 0.3),
			"...which ships as the former hardcoded gold")

func test_quest_objective_marker_defaults() -> void:
	var o := QuestObjective.new()
	assert_false(o.show_marker, "show_marker defaults off")
	assert_eq(o.marker_position, Vector3.ZERO, "marker_position defaults zero")
	o = null

func test_wants_marker_pure() -> void:
	assert_false(QuestMarkerSyncScript.wants_marker(null), "null objective wants no marker")
	var o := QuestObjective.new()
	assert_false(QuestMarkerSyncScript.wants_marker(o), "show_marker off -> no marker")
	o.show_marker = true
	assert_true(QuestMarkerSyncScript.wants_marker(o), "show_marker on -> wants a marker")
	o = null
