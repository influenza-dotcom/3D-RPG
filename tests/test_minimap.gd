extends GutTest

## Minimap (scripts/ui/minimap.gd) — the top-right procedural floorplan Control. Its PAINTING is
## playtest-verified and its geometry maths lives in FloorplanSection (pinned in test_floorplan_section.gd);
## what is pinned HERE is the part that can silently rot: the off-tree construction contract, the
## marker_color fallback that test_hud_skin.gd also leans on, the component defaults a designer sees in the
## inspector, and the deck cache's LRU bound.
##
## Loaded BY PATH, not by class_name, so the suite survives a stale global class cache (the ui.gd
## STAMINA_RING_SCRIPT idiom).

const MINIMAP_SCRIPT := "res://scripts/ui/minimap.gd"


## A bare .new() with no tree must be completely safe: test_hud_skin.gd constructs one exactly this way to
## check the skin wiring, so an @onready or a tree-touching _init creeping in here takes THAT suite down
## too, from a file whose author never looked at this one.
func test_new_off_tree_does_not_crash() -> void:
	var mm = load(MINIMAP_SCRIPT).new()
	autofree(mm)
	assert_not_null(mm, "the widget constructs with no tree")
	assert_eq(mm.deck_count(), 0, "no decks are sliced before it ever runs")
	assert_almost_eq(mm.active_band_floor(), 0.0, 0.0001, "no active band either")
	mm._process(0.016)  # must bail on the is_inside_tree guard rather than touching get_tree()
	assert_eq(mm.deck_count(), 0, "a process tick off-tree still slices nothing")
	mm.rebake()
	assert_eq(mm.deck_count(), 0, "rebake is safe with nothing cached")


## THE CONTRACT test_hud_skin.gd:159-174 depends on. Re-asserted locally so a change here fails in the
## file that caused it, not only in a distant skin test.
func test_marker_color_falls_back_to_the_skin_npc_tint() -> void:
	var mm = load(MINIMAP_SCRIPT).new()
	autofree(mm)
	var bare := Node3D.new()  # no `color` property at all
	autofree(bare)
	assert_eq(mm.marker_color(bare), MenuStyle.hud.minimap_npc_color,
			"a colourless marker falls back to MenuStyle.hud.minimap_npc_color")


func test_marker_color_honours_an_authored_color() -> void:
	var mm = load(MINIMAP_SCRIPT).new()
	autofree(mm)
	var marker = load("res://scripts/components/world_marker.gd").new()
	autofree(marker)  # off-tree: no _ready, so marker_color only .get()s the export
	marker.color = Color(0.1, 0.2, 0.3)
	assert_eq(mm.marker_color(marker), Color(0.1, 0.2, 0.3), "a marker's own color wins over the fallback")


## The inspector surface a designer actually sees. map_data staying an @export (and defaulting null) is the
## backward-compatibility promise: the authored MapData path is demoted to an optional underlay, not removed.
func test_component_defaults() -> void:
	var mm = load(MINIMAP_SCRIPT).new()
	autofree(mm)
	assert_almost_eq(mm.marker_radius, 4.0, 0.0001, "marker_radius default preserved from the old widget")
	assert_null(mm.map_data, "the authored underlay is OPTIONAL and off by default")
	assert_true(mm.draw_walkable, "the navmesh fill is the day-one picture, so it ships on")
	assert_true(mm.draw_walls, "the section cut ships on, and is the knob to flip if brushwork cuts to mush")
	assert_false(mm.dot_npcs, "Groups.MINIMAP is the AUTHORED channel — dotting every NPC is opt-in")
	assert_eq(mm.deck_cache_max, 12, "deck cache bound")
	assert_gt(mm.bake_delay, 0.0, "a gather on frame one can see a half-built level, so the delay is real")


## The deck cache must stay BOUNDED. A tower with more storeys than deck_cache_max is a normal level, and an
## unbounded dictionary here would grow for the whole session. Driven directly through the private builder
## so no tree, no navmesh and no player are needed — a null region yields empty decks, which is the point:
## the eviction is what is under test, not the slicing.
func test_deck_cache_is_lru_capped() -> void:
	var mm = load(MINIMAP_SCRIPT).new()
	autofree(mm)
	mm.deck_cache_max = 3
	var band: float = GameSettings.hud.minimap_band_height
	for storey in 10:
		mm._ensure_deck(null, float(storey) * band + 0.5)
	assert_lte(mm.deck_count(), 3, "the cache never grows past deck_cache_max")
	assert_gt(mm.deck_count(), 0, "...but it does keep the recent floors")


## Revisiting a floor inside the same band is a cache HIT — this is what makes walking around one storey
## free. Two positions in the same band must not produce two decks.
func test_walking_one_floor_does_not_re_slice() -> void:
	var mm = load(MINIMAP_SCRIPT).new()
	autofree(mm)
	var band: float = GameSettings.hud.minimap_band_height
	mm._ensure_deck(null, 0.1)
	var after_first: int = mm.deck_count()  # annotated, not := — mm is untyped, so nothing to infer from
	mm._ensure_deck(null, band * 0.5)
	mm._ensure_deck(null, band * 0.9)
	assert_eq(mm.deck_count(), after_first, "three positions on one floor share one deck")
	mm._ensure_deck(null, band * 1.5)
	assert_eq(mm.deck_count(), after_first + 1, "a storey up is a different deck")


## The active band must follow the player DOWN as well as up — a basement floors away from zero, not
## toward it, and getting that wrong draws the ground floor's plan while standing in the cellar.
func test_active_band_follows_the_player_between_storeys() -> void:
	var mm = load(MINIMAP_SCRIPT).new()
	autofree(mm)
	var band: float = GameSettings.hud.minimap_band_height
	mm._ensure_deck(null, 0.5)
	assert_almost_eq(mm.active_band_floor(), 0.0, 0.0001, "standing on the ground floor")
	mm._ensure_deck(null, band + 0.5)
	assert_almost_eq(mm.active_band_floor(), band, 0.0001, "one storey up")
	mm._ensure_deck(null, -0.5)
	assert_almost_eq(mm.active_band_floor(), -band, 0.0001, "a basement floors DOWN, not toward zero")


## rebake() must drop everything, or a LevelDoor transition would keep drawing the previous level's
## geometry in the new level's world space — the failure this widget's instance-id staleness check exists
## to prevent.
func test_rebake_drops_every_deck() -> void:
	var mm = load(MINIMAP_SCRIPT).new()
	autofree(mm)
	var band: float = GameSettings.hud.minimap_band_height
	mm._ensure_deck(null, 0.5)
	mm._ensure_deck(null, band + 0.5)
	assert_gt(mm.deck_count(), 0, "decks exist before the swap")
	mm.rebake()
	assert_eq(mm.deck_count(), 0, "a level swap drops every deck")
	assert_almost_eq(mm.active_band_floor(), 0.0, 0.0001, "and clears the active band")
