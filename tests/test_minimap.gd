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
	# Deliberately flipped ON (user request): NPC dots ship visible. The radar risk that made it opt-in is
	# handled differently now — dots are CLIPPED to the box instead of pinned to its rim, so a dot means
	# "near you" rather than "somewhere on this level" — and the player can still switch them off in Options.
	assert_true(mm.dot_npcs, "NPC dots ship on; the rim-pin exclusion is what keeps them from being a radar")
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
	mm._ensure_deck(null, band * 1.5)
	assert_almost_eq(mm.active_band_floor(), band, 0.0001, "one CLEAR storey up (band+0.5 is inside the sticky margin)")
	mm._ensure_deck(null, -band * 0.5)
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


# --- the "map flips when I jump" fix --------------------------------------------------------------------

## Reported from play: the whole floorplan changed wildly on a small vertical move such as a jump. Cause was
## the deck being keyed off the player's LIVE Y, so a jump taken anywhere near a 2.6 m band boundary swapped
## the storey mid-air and swapped it back on landing. Two independent guards now, and this pins the second:
## once a band is drawn it STICKS until the reference is properly clear of it.
func test_a_small_rise_past_a_boundary_does_not_swap_the_floor() -> void:
	var mm = load(MINIMAP_SCRIPT).new()
	autofree(mm)
	var band: float = GameSettings.hud.minimap_band_height
	mm._ensure_deck(null, band - 0.1)               # standing just under a boundary
	var floor_before: float = mm.active_band_floor()
	var decks_before: int = mm.deck_count()
	mm._ensure_deck(null, band + 0.1)               # a small hop over it
	assert_almost_eq(mm.active_band_floor(), floor_before, 0.0001,
			"a hop across a band boundary must not change the drawn storey")
	assert_eq(mm.deck_count(), decks_before, "...and must not slice a second deck for it either")

## Jitter must never oscillate the map: feeding heights back and forth across a boundary has to settle.
func test_jitter_across_a_boundary_never_oscillates() -> void:
	var mm = load(MINIMAP_SCRIPT).new()
	autofree(mm)
	var band: float = GameSettings.hud.minimap_band_height
	mm._ensure_deck(null, band - 0.05)
	var settled: float = mm.active_band_floor()
	for i in 8:
		mm._ensure_deck(null, band + (0.2 if i % 2 == 0 else -0.2))
		assert_almost_eq(mm.active_band_floor(), settled, 0.0001, "still the same storey on jitter step %s" % i)
	assert_eq(mm.deck_count(), 1, "eight boundary crossings still slice exactly one deck")

## The other half of the fix, and the one that actually addresses JUMPING: the vertical reference is the
## last GROUNDED height, so leaving the floor cannot change which storey is drawn however high the jump.
func test_ground_reference_ignores_airborne_height() -> void:
	var mm = load(MINIMAP_SCRIPT).new()
	autofree(mm)
	var body := AirborneStub.new()
	add_child_autofree(body)  # in-tree: global_position errors and reads zero off-tree
	body.grounded = true
	body.position = Vector3(0, 1.0, 0)
	mm._update_ground_reference(body)
	assert_almost_eq(mm._ground_y, 1.0, 0.0001, "standing on the floor sets the reference")
	body.grounded = false
	body.position = Vector3(0, 9.0, 0)              # mid-jump, two storeys up
	mm._update_ground_reference(body)
	assert_almost_eq(mm._ground_y, 1.0, 0.0001,
			"AIRBORNE height is ignored entirely — this is what stops a jump redrawing the map")
	body.grounded = true
	body.position = Vector3(0, 9.0, 0)              # landed on a balcony
	mm._update_ground_reference(body)
	assert_almost_eq(mm._ground_y, 9.0, 0.0001, "landing somewhere new DOES move the reference")

## A host with no is_on_floor (a test stub, a no-clip debug body) must degrade to tracking live Y rather
## than crashing or freezing the map on frame one's height.
func test_ground_reference_degrades_without_is_on_floor() -> void:
	var mm = load(MINIMAP_SCRIPT).new()
	autofree(mm)
	var plain := Node3D.new()
	add_child_autofree(plain)  # in-tree, same reason
	plain.position = Vector3(0, 4.0, 0)
	mm._update_ground_reference(plain)
	assert_almost_eq(mm._ground_y, 4.0, 0.0001, "a host without the method just tracks live Y")
	plain.position = Vector3(0, 6.0, 0)
	mm._update_ground_reference(plain)
	assert_almost_eq(mm._ground_y, 6.0, 0.0001, "...and keeps following it")


## Minimal stand-in for a CharacterBody3D: the widget only duck-types is_on_floor(), so a test needs no
## physics server, no collider and no gravity to exercise the grounded/airborne contract.
class AirborneStub extends Node3D:
	var grounded: bool = true
	func is_on_floor() -> bool:
		return grounded


# --- NPC dots -------------------------------------------------------------------------------------------

## NPC dots are tinted by ALLEGIANCE, through the same CBPalette.disposition_color the hover name, the
## dialogue speaker name and the enemy health bar use — so the four surfaces can never end up telling
## different stories about the same body. Duck-typed, so this needs no real NPC.
func test_npc_dot_color_follows_disposition() -> void:
	var mm = load(MINIMAP_SCRIPT).new()
	autofree(mm)
	var npc := NpcStub.new()
	autofree(npc)
	npc.disposition = Disposition.Kind.HOSTILE
	assert_eq(mm.npc_dot_color(npc), CBPalette.hostile(), "a hostile reads as hostile")
	npc.disposition = Disposition.Kind.FRIENDLY
	assert_eq(mm.npc_dot_color(npc), CBPalette.friendly(), "a friendly reads as friendly")
	npc.disposition = Disposition.Kind.NEUTRAL
	assert_eq(mm.npc_dot_color(npc), MenuStyle.hud.minimap_npc_color,
			"a neutral falls to the skin's own minimap tint, not to a hardcoded grey")

## A recruited companion WINS over disposition — the same precedence CBPalette documents.
func test_npc_dot_color_marks_a_recruited_companion() -> void:
	var mm = load(MINIMAP_SCRIPT).new()
	autofree(mm)
	var npc := NpcStub.new()
	autofree(npc)
	npc.disposition = Disposition.Kind.HOSTILE   # deliberately the losing branch
	npc.following = true
	assert_eq(mm.npc_dot_color(npc), CBPalette.ally(), "a companion is a companion even mid-grudge")

## Not-an-NPC must degrade, never crash: this runs over a whole group every frame.
func test_npc_dot_color_degrades_for_a_plain_node() -> void:
	var mm = load(MINIMAP_SCRIPT).new()
	autofree(mm)
	var plain := Node3D.new()
	autofree(plain)
	assert_eq(mm.npc_dot_color(plain), MenuStyle.hud.minimap_npc_color, "no disposition -> the neutral tint")

## NPCs are POOLED in this project, so a dead one stays in the group waiting to be reused. Without this
## filter its dot would sit on the map forever, exactly where it fell.
func test_dead_npcs_get_no_dot() -> void:
	var mm = load(MINIMAP_SCRIPT).new()
	autofree(mm)
	var npc := NpcStub.new()
	autofree(npc)
	npc.alive = true
	assert_true(mm._npc_is_live(npc), "a living NPC is dotted")
	npc.alive = false
	assert_false(mm._npc_is_live(npc), "a corpse is not — pooled bodies would otherwise blip forever")
	var plain := Node3D.new()
	autofree(plain)
	assert_true(mm._npc_is_live(plain), "a host with no is_alive() is assumed live rather than silently dropped")

## The designer switch ships ON now (the player asked to see NPCs), but BOTH it and the player's Options row
## must agree — either one off means no dots.
func test_npc_dots_ship_on_for_both_owners() -> void:
	var mm = load(MINIMAP_SCRIPT).new()
	autofree(mm)
	assert_true(mm.dot_npcs, "the designer switch ships on")
	var fresh = load("res://managers/Settings.gd").new()
	assert_true(fresh.minimap_show_npcs, "and so does the player-facing row")
	fresh.free()


## Minimal stand-in for an NPC: the widget duck-types resolved_disposition / is_following / is_alive, so a
## test needs none of npc.gd's _ready (which builds weapons, nav, audio and mutates shared statics).
class NpcStub extends Node3D:
	var disposition: int = Disposition.Kind.NEUTRAL
	var following: bool = false
	var alive: bool = true
	func resolved_disposition() -> int:
		return disposition
	func is_following() -> bool:
		return following
	func is_alive() -> bool:
		return alive
