extends GutTest

## Minimap (scripts/ui/minimap.gd) — the top-right procedural floorplan Control. Its PAINTING is
## playtest-verified and its geometry maths lives in FloorplanSection (pinned in test_floorplan_section.gd);
## what is pinned HERE is the part that can silently rot: the off-tree construction contract, the
## marker_color fallback that test_hud_skin.gd also leans on, the component defaults a designer sees in the
## inspector, the deck cache's LRU bound, the level-swap drop (BOTH halves of rebake — the deck cache AND
## the FloorplanSource wall gather — plus the region-instance-id check that is its only shipped trigger),
## and the LevelData.map_data underlay stamp (rebake pulls the active level's authored map off
## Groups.GAME_ROOT — the consumption seam that makes the Content dock's Maps scaffolds reachable).
##
## Loaded BY PATH, not by class_name, so the suite survives a stale global class cache (the ui.gd
## STAMINA_RING_SCRIPT idiom).
##
## THE BARE `.new()` IS DELIBERATE AND LOAD-BEARING, not a shortcut. The widget SHIPS as an authored scene
## (scenes/ui/hud_minimap.tscn — see tests/test_minimap_scene.gd for that half), but the whole point of how
## that conversion was done is that the script still paints correctly with ZERO authored children: the plan
## was NOT moved into a child node, so the scene only wraps the same single _draw in two empty art slots.
## Every `.new()` here is what pins that. The two `mm.size = GameSettings.hud.minimap_size` writes below are
## the same story from the other side: that knob is now the FALLBACK box and the number the scene was authored
## from — tied by test_minimap_scene.gd — so stamping it on a bare instance still describes the shipped box.

const MINIMAP_SCRIPT := "res://scripts/ui/minimap.gd"
## The wall layer's gather (RefCounted). Only ever constructed here to SEED a fake "level A already
## gathered" state on the widget's _source — loaded by path for the same cache reason as above.
const FLOORPLAN_SOURCE_SCRIPT := "res://scripts/ui/floorplan_source.gd"


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
	# rebake also resolves the level underlay, which needs a tree to find the GameRoot — off-tree it must
	# degrade to "no underlay", never touch get_tree().
	assert_null(mm.active_map_data(), "off-tree there is no level, so there is no underlay either")


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
## per-instance OVERRIDE half of the underlay seam: the normal authoring surface is LevelData.map_data
## (stamped by rebake — see the underlay section below), and this export wins over it only when a designer
## sets it on a specific widget.
func test_component_defaults() -> void:
	var mm = load(MINIMAP_SCRIPT).new()
	autofree(mm)
	# The MARKER SIZES are deliberately NOT here any more — marker_radius / arrow_size moved onto the skin as
	# minimap_poi_glyph_px / minimap_caret_px so all four marker sizes sit beside their colours in one
	# resource (test_hud_skin.gd pins their defaults). What remains on the widget is what it DOES, not how it
	# looks, which is the whole split: paint on hud_skin.tres, behaviour here and on GameSettings.hud.
	assert_false(&"marker_radius" in mm,
			"marker_radius moved to MenuStyle.hud.minimap_poi_glyph_px — two sources of truth would drift")
	assert_false(&"arrow_size" in mm,
			"arrow_size moved to MenuStyle.hud.minimap_caret_px, beside every other marker size")
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


## rebake() must drop BOTH caches, or a LevelDoor transition would keep drawing the previous level's
## geometry in the new level's world space — the failure this widget's instance-id staleness check exists
## to prevent. The two halves rot independently: the deck dictionary is the loud one, but the
## FloorplanSource wall gather holds the old level's solids in WORLD space too, and if it survived the
## swap every FRESH deck would re-CUT the old level's walls into the new level's plan ("re-gather, never
## re-cut" — the comment on the line this pins). Before this test only the deck half was pinned, so
## deleting the _source null left the whole suite green.
func test_rebake_drops_every_deck_and_the_wall_source() -> void:
	var mm = load(MINIMAP_SCRIPT).new()
	autofree(mm)
	var band: float = GameSettings.hud.minimap_band_height
	mm._ensure_deck(null, 0.5)
	mm._ensure_deck(null, band + 0.5)
	mm._source = load(FLOORPLAN_SOURCE_SCRIPT).new()   # stands in for a completed level-A wall gather
	assert_gt(mm.deck_count(), 0, "decks exist before the swap")
	mm.rebake()
	assert_eq(mm.deck_count(), 0, "a level swap drops every deck")
	assert_null(mm._source, "and the wall gather with them — old-level solids must never be re-cut")
	assert_almost_eq(mm.active_band_floor(), 0.0, 0.0001, "and clears the active band")


## THE TRIGGER for the drop above, with real regions: in the shipped game nothing calls rebake() on a swap
## except _process noticing the Groups.NAVMESH region's INSTANCE ID changed (deliberately no GameRoot
## signal — a freed region leaves the group by itself, the self-healing claim in the widget's header).
## Three ticks pin the three behaviours: the boot frame trips the seeded -1 check, the SAME region across
## frames must NOT re-trip it (or every frame would throw away every deck), and a DIFFERENT region — level
## B's, after level A's is freed exactly as a LevelDoor swap frees it — must drop the decks AND the wall
## source. No player is in the tree, so every tick stops at the bake-delay gate directly after the
## staleness check — which is precisely the code under test and nothing more.
func test_a_new_region_instance_id_triggers_the_swap_drop() -> void:
	var mm = load(MINIMAP_SCRIPT).new()
	add_child_autofree(mm)
	var region_a := NavigationRegion3D.new()
	region_a.add_to_group(Groups.NAVMESH)
	add_child_autofree(region_a)
	mm._process(0.016)                                 # boot: -1 -> region A trips the check once
	mm._ensure_deck(null, 0.5)                         # level A's deck...
	mm._source = load(FLOORPLAN_SOURCE_SCRIPT).new()   # ...and its wall gather
	mm._process(0.016)
	assert_gt(mm.deck_count(), 0, "the SAME region across frames must not re-trip the swap drop")
	assert_not_null(mm._source, "...nor re-gather the walls every frame")
	region_a.free()                                    # the LevelDoor case: the old level, region included, is freed
	var region_b := NavigationRegion3D.new()
	region_b.add_to_group(Groups.NAVMESH)
	add_child_autofree(region_b)
	mm._process(0.016)
	assert_eq(mm.deck_count(), 0, "a new region identity is a level swap: every deck drops")
	assert_null(mm._source, "and the wall source drops with them — level B re-gathers, never re-cuts")


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


# --- the authored level underlay (LevelData.map_data -> the widget) ---------------------------------------

## THE CONSUMPTION SEAM (2026-08-11): a designer authors a MapData .tres (the Content dock's New Map row),
## assigns it to a LevelData's map_data, and the code-built HUD minimap picks it up on level load — rebake()
## pulls Groups.GAME_ROOT's `level` and stamps its map_data. Driven here through rebake() directly, exactly
## the call the region-instance-id staleness check makes on a swap. The stub stands in for GameRoot (whose
## _ready would resolve boot levels off the live GameState); the `level` property name it mirrors is pinned
## on the REAL GameRoot by test_level_data.gd's load_level assertions.
func test_rebake_stamps_the_active_levels_authored_underlay() -> void:
	var mm = load(MINIMAP_SCRIPT).new()
	add_child_autofree(mm)
	var root := GameRootStub.new()
	add_child_autofree(root)
	var map := MapData.new()
	root.level = LevelData.new()
	root.level.map_data = map
	mm.rebake()
	assert_eq(mm.active_map_data(), map, "rebake stamps the active level's authored MapData onto the widget")
	map = null


## The regression this seam must never grow: a swap into a level WITHOUT an authored map has to CLEAR the
## previous level's art, or the old image keeps drawing in the new level's world space (the exact failure
## the deck cache's drop-on-swap exists to prevent, underlay edition).
func test_rebake_clears_the_underlay_when_the_next_level_has_none() -> void:
	var mm = load(MINIMAP_SCRIPT).new()
	add_child_autofree(mm)
	var root := GameRootStub.new()
	add_child_autofree(root)
	root.level = LevelData.new()
	root.level.map_data = MapData.new()
	mm.rebake()
	assert_not_null(mm.active_map_data(), "the first level's map is up")
	root.level = LevelData.new()  # the next level ships no authored map
	mm.rebake()
	assert_null(mm.active_map_data(), "a level without an authored map CLEARS the previous level's art")


## Precedence: a map_data authored ON a widget instance pins that widget's underlay regardless of level —
## the level's map fills the (shipped) null case only. This is what keeps the export test-pinned above from
## being clobbered into meaninglessness by every level swap.
func test_widget_authored_map_data_wins_over_the_levels() -> void:
	var mm = load(MINIMAP_SCRIPT).new()
	add_child_autofree(mm)
	var own := MapData.new()
	mm.map_data = own
	var root := GameRootStub.new()
	add_child_autofree(root)
	root.level = LevelData.new()
	root.level.map_data = MapData.new()
	mm.rebake()
	assert_eq(mm.active_map_data(), own, "the widget's own authored export wins over the level's map")
	own = null


## No GameRoot in the tree (a bare level scene, a test harness): the resolve degrades to "no underlay"
## rather than crashing — the same soft-fail rule every other lookup in this widget follows.
func test_underlay_resolves_null_with_no_game_root() -> void:
	var mm = load(MINIMAP_SCRIPT).new()
	add_child_autofree(mm)
	mm.rebake()
	assert_null(mm.active_map_data(), "no GameRoot in the tree -> no underlay, no crash")


## THE DELIVERY PATH: in the shipped game nothing calls rebake() but _process's region-staleness check, so
## that branch — not just the resolver it calls — must be pinned. _source_region_id is seeded -1 (an id
## neither a region nor the ABSENCE of one can produce) precisely so the FIRST processed frame trips the
## check even when the level has NO NavigationRegion3D (rid 0): without the seed a region-less boot would
## compare 0 == 0 forever and an authored underlay would silently never stamp. This drives the real
## _process branch — in-tree, visible, no region in Groups.NAVMESH, a stubbed GameRoot — and one tick must
## resolve the underlay.
func test_first_process_frame_stamps_the_underlay_without_a_region() -> void:
	var mm = load(MINIMAP_SCRIPT).new()
	add_child_autofree(mm)
	var root := GameRootStub.new()
	add_child_autofree(root)
	var map := MapData.new()
	root.level = LevelData.new()
	root.level.map_data = map
	mm._process(0.016)
	assert_eq(mm.active_map_data(), map,
			"the first frame's staleness check fires even with no region — a region-less boot still stamps")
	map = null


## Minimal stand-in for GameRoot: the widget only reads `level` (duck-typed .get) off the Groups.GAME_ROOT
## member, so a test needs none of game_root.gd's _ready (which resolves boot levels off the live GameState).
class GameRootStub extends Node:
	var level: LevelData = null
	func _ready() -> void:
		add_to_group(Groups.GAME_ROOT)


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
	assert_eq(mm.npc_dot_color(npc), MenuStyle.hud.minimap_neutral_color,
			"a neutral falls to the skin's NEUTRAL tint — not minimap_npc_color, which is a salmon RED that was indistinguishable from CBPalette.hostile() at a 4 px glyph and told the player every civilian was a threat")
	assert_ne(MenuStyle.hud.minimap_neutral_color, MenuStyle.hud.minimap_npc_color,
			"...and the two slots must stay DIFFERENT colours, or the split bought nothing")

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
	assert_eq(mm.npc_dot_color(plain), MenuStyle.hud.minimap_neutral_color, "no disposition -> the neutral tint")

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


# --- the hostile alert ring -----------------------------------------------------------------------------

## THE GATE THAT MAKES THE RING MEAN SOMETHING. suspicion_of() answers for ANY NPC carrying a Perception, so
## without the hostile check a shopkeeper glancing your way — or a companion whose follow target is you, which
## is permanently ALERTED by construction — would wear the same amber threat halo as a guard drawing a bead.
## The ring would degrade from "danger" to "someone looked at you", which is worse than no ring.
func test_only_a_hostile_wears_the_alert_ring() -> void:
	var mm = load(MINIMAP_SCRIPT).new()
	autofree(mm)
	var me := Node3D.new()
	autofree(me)
	var npc := AwareNpcStub.new()
	autofree(npc)
	npc.tier = 3                                   # ALERTED on me, in every case below
	npc.disposition = Disposition.Kind.HOSTILE
	assert_eq(mm.alert_tier(npc, me), 3, "a hostile that has locked on reports its tier")
	npc.disposition = Disposition.Kind.NEUTRAL
	assert_eq(mm.alert_tier(npc, me), 0, "a neutral looking right at you is not a threat")
	npc.disposition = Disposition.Kind.FRIENDLY
	assert_eq(mm.alert_tier(npc, me), 0, "and neither is a friendly")
	npc.disposition = Disposition.Kind.HOSTILE
	npc.following = true
	assert_eq(mm.alert_tier(npc, me), 0,
			"a recruited COMPANION never rings — it tracks you as its follow target, so it is always alerted ON you")

## The ring is TARGET-GATED through NPC.suspicion_of, which returns CALM unless the asker is what the NPC is
## actually tracking. A guard trading fire with a stray dog must not read as "they are onto you".
func test_the_ring_is_silent_when_the_npc_is_watching_someone_else() -> void:
	var mm = load(MINIMAP_SCRIPT).new()
	autofree(mm)
	var me := Node3D.new()
	autofree(me)
	var npc := AwareNpcStub.new()
	autofree(npc)
	npc.disposition = Disposition.Kind.HOSTILE
	npc.tier = 3
	npc.watching = Node3D.new()   # a different target entirely
	autofree(npc.watching)
	assert_eq(mm.alert_tier(npc, me), 0, "fighting something else is not the same as hunting you")

## Degrades over a whole group every frame, so every soft input must be answered rather than crash: no player
## resolved yet (a boot frame), a plain prop that answers nothing, a null.
func test_alert_tier_degrades_for_anything_that_cannot_answer() -> void:
	var mm = load(MINIMAP_SCRIPT).new()
	autofree(mm)
	var me := Node3D.new()
	autofree(me)
	var plain := Node3D.new()
	autofree(plain)
	assert_eq(mm.alert_tier(plain, me), 0, "a prop with no suspicion_of never rings")
	assert_eq(mm.alert_tier(null, me), 0, "nor does a null body")
	var npc := AwareNpcStub.new()
	autofree(npc)
	npc.disposition = Disposition.Kind.HOSTILE
	npc.tier = 3
	assert_eq(mm.alert_tier(npc, null), 0, "and with no player resolved there is nobody to be alerted ON")


## An NPC stub that also answers the awareness surface. Mirrors NPC.suspicion_of's TARGET GATE — it reports its
## tier only for the node it is actually watching — so the test exercises the same shape the real facade has,
## without npc.gd's _ready or a live Perception child.
class AwareNpcStub extends Node3D:
	var disposition: int = Disposition.Kind.NEUTRAL
	var following: bool = false
	var alive: bool = true
	var tier: int = 0
	var watching: Node = null   ## null = "watching whoever asks" (the common test case)
	func resolved_disposition() -> int:
		return disposition
	func is_following() -> bool:
		return following
	func is_alive() -> bool:
		return alive
	func suspicion_of(who: Node) -> int:
		return tier if watching == null or watching == who else 0


# --- the idle gate --------------------------------------------------------------------------------------

## THE COST BUG THIS FIXED. The liveness probe read the DESIGNER switch (dot_npcs) but not the PLAYER's row
## (Settings.minimap_show_npcs), so switching NPC dots off in Options still forced a full repaint every single
## frame for bodies that were never drawn — the exact cost the row exists to remove. Both owners now gate it,
## matching the paint site exactly.
func test_the_idle_gate_asks_the_same_question_the_paint_site_does() -> void:
	var mm = load(MINIMAP_SCRIPT).new()
	add_child_autofree(mm)
	var npc := NpcStub.new()
	add_child_autofree(npc)
	npc.add_to_group(Groups.NPC)
	var was_npcs: bool = Settings.minimap_show_npcs
	var was_stations: bool = Settings.minimap_show_stations
	Settings.minimap_show_npcs = true
	assert_true(mm._has_live_markers(), "with dots ON a living body keeps the map repainting — it moves")
	Settings.minimap_show_npcs = false
	Settings.minimap_show_stations = false
	assert_false(mm._has_live_markers(),
			"with BOTH body channels off the same body must cost NOTHING — nothing drawn from it can move")
	Settings.minimap_show_npcs = was_npcs
	Settings.minimap_show_stations = was_stations

## THE MOVING-STATION HOLE. 7 of the 8 stations placed in this project ride a dialogue NPC, so their glyphs walk
## around with the body. Gating the NPC-group probe on the NPC toggle ALONE froze a walking shopkeeper's glyph
## mid-stride for any player who turned body dots off — the station channel was still painting, but nothing was
## asking for a repaint.
func test_a_walking_station_still_repaints_with_body_dots_off() -> void:
	var mm = load(MINIMAP_SCRIPT).new()
	add_child_autofree(mm)
	var vendor := NpcStub.new()
	add_child_autofree(vendor)
	vendor.add_to_group(Groups.NPC)             # the body the shop rides
	vendor.add_to_group(Groups.MINIMAP_STATION) # and the shop glyph on it
	var was_npcs: bool = Settings.minimap_show_npcs
	var was_stations: bool = Settings.minimap_show_stations
	Settings.minimap_show_npcs = false
	Settings.minimap_show_stations = true
	assert_true(mm._has_live_markers(),
			"a station glyph riding a walking body must keep the map repainting even with body dots off")
	Settings.minimap_show_npcs = was_npcs
	Settings.minimap_show_stations = was_stations

## Stations are static, so Groups.MINIMAP_STATION is deliberately NOT scanned: a level with one shop in it must
## not pin the gate open forever. With no BODIES anywhere, a station alone costs nothing.
func test_a_station_with_no_bodies_does_not_defeat_the_idle_gate() -> void:
	var mm = load(MINIMAP_SCRIPT).new()
	add_child_autofree(mm)
	var pin := StationMarker.new()
	add_child_autofree(pin)
	pin.add_to_group(Groups.MINIMAP_STATION)
	assert_false(mm._has_live_markers(),
			"a fixed station never moves, so its presence alone must not force a repaint every frame")


# --- the stale-paint edge (a CanvasItem repaints ONLY on queue_redraw) -----------------------------------
#
# THE BUG THIS SECTION PINS, and it is the minimap's copy of the stuck aim arc in aim_indicators.gd. The idle
# gate above asks "is anything live NOW", which is the wrong tense for a Control: _draw() runs only when
# something calls queue_redraw(), so the frame a fact STOPS being true is the frame that most needs a repaint —
# and it is exactly the frame the gate goes quiet. For a standing, still player nothing ever queues another
# one, so the last painted frame stays on the map indefinitely: the dot of a body that is gone, the beacon of
# a quest already handed in, the glyphs the player just switched off in Options.
#
# HOW THESE DRIVE IT. One test runs the whole shipped _process path (see HumanPlayerStub — reaching the gate
# for real needs a live human player in the tree, because Groups.human_player positively identifies the Player
# CLASS). The rest split what _process does into its two observable halves and drive them by hand: they ASSERT
# _needs_repaint's answer, then paint via _repaint(), which is the queue_redraw half only. That split is what
# lets them cover states a headless run cannot otherwise reach, and it is why the assertions come in pairs —
# the gate must open on the frame the fact changes, and shut again on the frame after. Everything they read is
# set inside _draw() itself, which the headless renderer really does dispatch (the same thing
# test_camera_input_ui.gd's _painted tests rely on).


## An in-tree, PAINTING minimap in the state the bug lives in: a settled level and a standing player. A Control
## runs _draw() only once it is in the tree, and only then does _painted describe anything real.
##
## The two seeds are what _process would have consumed on its own during a normal boot: _source_region_id is
## seeded -1 in the widget so that even a region-less level rebakes once, and rebake() raises _deck_dirty —
## which would hold the repaint gate open for the whole test and hide everything under it. Pre-seeding the id
## this tree actually reports (no NavigationRegion3D == 0) starts the widget where a settled level leaves it.
func _idle_minimap():
	var mm = load(MINIMAP_SCRIPT).new()
	mm._source_region_id = 0
	mm._deck_dirty = false
	add_child_autofree(mm)
	mm.size = GameSettings.hud.minimap_size  # the shipped box, so a marker at the origin lands inside it
	return mm


## One painted frame. Two process frames like the aim-arc tests: a queued redraw lands at the end of the frame.
func _repaint(mm) -> void:
	mm.queue_redraw()
	await get_tree().process_frame
	await get_tree().process_frame


## THE ONE THING Groups.human_player ACCEPTS. That lookup is a positive `is Player` TYPE test, not a group
## membership test (test_groups.gd pins that a non-Player member yields null), so nothing short of a subclass
## gets _process past minimap.gd's player bail and down to the idle gate.
##
## The empty overrides are what keeps CLAUDE.md's "never run a Player's _ready in a unit test" rule intact:
## GDScript dispatches only the most-derived virtual when super() is not called, so neither Player._ready (which
## builds the whole actor — weapon scene, abilities, HUD, gore, audio, shared statics) nor Player._enter_tree
## (which hard-derefs @export slots a bare .new() leaves null) ever runs. This is a POSITION and a TYPE, nothing
## more; anything that needs a real Player still belongs in a playtest.
class HumanPlayerStub extends Player:
	func _enter_tree() -> void: pass
	func _ready() -> void: pass
	func _physics_process(_delta: float) -> void: pass


## Build that stub, wired enough to enter a tree quietly. The Head chain is NOT decoration: Player carries
## `@onready var white_flash: Sprite3D = $"Head/ScreenShake/Camera3D/white flash"`, and @onready assignments run
## from the implicit ready of every script in the chain whether or not _ready is overridden — a missing node
## there is a get_node ENGINE error, and GUT 9.6 fails a test on any engine error even with every assert green.
func _human_player() -> Node3D:
	var p := HumanPlayerStub.new()
	var head := Node3D.new()
	head.name = "Head"
	var shake := Node3D.new()
	shake.name = "ScreenShake"
	# Deliberately a Node3D and NOT a Camera3D: the first Camera3D to enter a viewport makes itself CURRENT,
	# and Minimap._camera_yaw would then take the map's bearing off this stub instead of off the player.
	var cam := Node3D.new()
	cam.name = "Camera3D"
	var flash := Sprite3D.new()  # the @onready is TYPED Sprite3D, so the leaf's class matters as well as its name
	flash.name = "white flash"   # the authored name, space included
	cam.add_child(flash)
	shake.add_child(cam)
	head.add_child(shake)
	p.add_child(head)            # children FIRST: @onready resolves when the Player itself enters the tree
	add_child_autofree(p)
	p.add_to_group(Groups.PLAYER)
	return p


## THE SHIPPED PATH, END TO END — no hand-stepped gate, just _process doing what it does every frame with a
## human player standing still in the tree. The other tests in this section step the gate themselves (that is the
## only way to reach the cases a headless run cannot otherwise set up), which means every one of them would stay
## green if _process were rewired to stop asking _needs_repaint at all. This is the one that would not.
func test_process_itself_clears_a_beacon_that_vanished_while_you_stand_still() -> void:
	var mm = load(MINIMAP_SCRIPT).new()
	add_child_autofree(mm)
	mm.size = GameSettings.hud.minimap_size
	# Per-instance only: the shipped 0.2 s would park every tick at the bake-delay gate above the idle gate, and
	# test_component_defaults pins the EXPORT default as > 0 (a gather on frame one can see a half-built level).
	mm.bake_delay = 0.0
	_human_player()
	var beacon := Node3D.new()
	add_child_autofree(beacon)
	beacon.add_to_group(Groups.MINIMAP)
	await get_tree().process_frame
	await get_tree().process_frame
	assert_true(mm._painted, "precondition: _process really did reach the gate and paint the beacon")
	beacon.queue_free()  # the quest ends: QuestMarkerSync drops the marker it spawned
	await get_tree().process_frame
	await get_tree().process_frame
	assert_false(mm._painted,
			"_process itself must queue the ONE repaint that takes a vanished beacon off the canvas — the player is standing still, so no movement will ever ask for one and a CanvasItem repaints only when asked")


## THE FREED BEACON. Hand in the quest that owns the last Groups.MINIMAP marker while standing still and its
## dot stayed painted on the map: the group emptied, so _has_live_markers() went false the same frame, and the
## gate that would have repainted it away shut in the same breath. _painted is the trailing edge that closes
## it — and it must be worth exactly ONE repaint, or a map with nothing on it would repaint forever.
func test_a_freed_beacon_is_repainted_away_while_you_stand_still() -> void:
	var mm = _idle_minimap()
	var beacon := Node3D.new()
	add_child_autofree(beacon)
	beacon.add_to_group(Groups.MINIMAP)
	await _repaint(mm)
	assert_true(mm._painted,
			"a live beacon must actually PAINT — otherwise this test cannot tell a clear from a no-op")
	beacon.queue_free()  # the quest ends: QuestMarkerSync drops the marker it spawned
	await get_tree().process_frame
	assert_false(mm._has_live_markers(), "precondition: the channel really is empty now")
	assert_true(mm._needs_repaint(false),
			"the frame the last beacon vanishes must still ask for a repaint: a CanvasItem repaints only on queue_redraw, so without one the dot of a marker that no longer exists stays on the map for as long as the player stands still")
	await _repaint(mm)
	assert_false(mm._painted,
			"...and that repaint must CLEAR it — _painted drops because _draw found the channel empty")
	assert_false(mm._needs_repaint(false),
			"...exactly ONE repaint, though: the latch is re-stamped by the draw it asked for, so an empty map goes back to costing nothing")


## THE LAST BODY LEAVING. Same trailing edge, the other channel it watches: kill the last NPC in a quiet area
## while standing still and its dot stayed painted where it fell. Driven through the POOLED death path, which is
## the harsher timing of the two — NpcPool.reclaim does a SYNCHRONOUS remove_child, so the body leaves the group
## mid-frame rather than at the end of it (the authored path's queue_free defers by a frame, which paints the
## doomed body once more and then strands exactly the same way).
func test_the_last_body_leaving_is_repainted_away_while_you_stand_still() -> void:
	var was_npcs: bool = Settings.minimap_show_npcs
	var was_stations: bool = Settings.minimap_show_stations
	Settings.minimap_show_npcs = true
	Settings.minimap_show_stations = false  # else the station clause answers for the body group as well
	var mm = _idle_minimap()
	var npc := NpcStub.new()
	add_child_autofree(npc)
	npc.add_to_group(Groups.NPC)
	await _repaint(mm)
	assert_true(mm._painted, "precondition: a living body must actually PAINT a dot")
	npc.get_parent().remove_child(npc)  # NpcPool.reclaim's own move
	assert_false(mm._has_live_markers(), "precondition: the body channel really is empty now")
	assert_true(mm._needs_repaint(false),
			"the frame the last body leaves must still ask for a repaint, or its dot sits on the map exactly where it fell for as long as the player stands still")
	await _repaint(mm)
	assert_false(mm._painted, "...and that repaint clears it")
	assert_false(mm._needs_repaint(false), "...once — an emptied map goes back to costing nothing")
	Settings.minimap_show_npcs = was_npcs
	Settings.minimap_show_stations = was_stations


## THE RISING EDGE, which is the half that must NOT be traded away for the trailing one. A body APPEARING is
## caught by _has_live_markers() and by nothing else: _painted is false (nothing was on the canvas last paint)
## and no Options row moved, so dropping that term — which now looks redundant, because a live body keeps it
## true every frame afterwards — would leave a spawned NPC invisible until the player walked.
func test_a_body_appearing_repaints_a_map_that_had_gone_idle() -> void:
	var was_npcs: bool = Settings.minimap_show_npcs
	Settings.minimap_show_npcs = true
	var mm = _idle_minimap()
	await _repaint(mm)
	assert_false(mm._needs_repaint(false), "precondition: an empty map under a standing player is idle")
	var npc := NpcStub.new()
	add_child_autofree(npc)
	npc.add_to_group(Groups.NPC)  # an EncounterSpawner drops a body in
	assert_true(mm._needs_repaint(false),
			"a body arriving must repaint too — the trailing edges cannot see it, so this is the liveness probe's own job")
	await _repaint(mm)
	assert_true(mm._needs_repaint(false),
			"...and it keeps repainting while that body is there, because a body is the thing on this map that moves")
	Settings.minimap_show_npcs = was_npcs


## THE OPTIONS ROW, BODY DOTS. Settings.set_minimap_show_npcs carries no apply step — "Minimap reads it live in
## _draw" — which assumed a repaint would be along shortly. Switch dots off while standing still in a room with
## a body in it and none ever is: _has_live_markers() answers the new setting immediately, so the gate shuts on
## the very frame the dots needed taking off the canvas.
func test_switching_body_dots_off_repaints_the_map_that_frame() -> void:
	var was_npcs: bool = Settings.minimap_show_npcs
	var was_stations: bool = Settings.minimap_show_stations
	Settings.minimap_show_npcs = true
	Settings.minimap_show_stations = false  # else the station clause keeps the gate open on the same body
	var mm = _idle_minimap()
	var npc := NpcStub.new()
	add_child_autofree(npc)
	npc.add_to_group(Groups.NPC)
	await _repaint(mm)
	assert_true(mm._painted, "precondition: a body dot is on the canvas")
	Settings.minimap_show_npcs = false  # Options -> Accessibility -> "NPCs On Minimap"
	assert_false(mm._has_live_markers(), "precondition: the row that shut the dots off also shut the gate")
	assert_true(mm._needs_repaint(false),
			"switching body dots off must repaint the map that frame; nothing else will, so the dots the player just turned off would stay painted")
	await _repaint(mm)
	assert_false(mm._painted, "the dots are off the canvas")
	assert_false(mm._drawn_show_npcs, "...and the paint now matches the setting it was made from")
	assert_false(mm._needs_repaint(false), "...and the gate shuts again — one repaint, not a permanent one")
	Settings.minimap_show_npcs = was_npcs
	Settings.minimap_show_stations = was_stations


## THE OPTIONS ROW, STATION GLYPHS — the half _painted deliberately cannot cover. Stations are excluded from
## _has_live_markers() on purpose (a fixed shop must not pin the gate open), so a station-only map is the case
## where the gate is genuinely, correctly shut every frame — and switching the glyphs off is then a change with
## nothing at all asking to repaint it. Only the drawn-options stamp catches this one.
func test_switching_station_glyphs_off_repaints_the_map_that_frame() -> void:
	var was_stations: bool = Settings.minimap_show_stations
	Settings.minimap_show_stations = true
	var mm = _idle_minimap()
	var pin := StationMarker.new()
	add_child_autofree(pin)
	pin.add_to_group(Groups.MINIMAP_STATION)
	await _repaint(mm)
	assert_true(mm._drawn_show_stations, "precondition: _draw really ran, and ran with the station row ON")
	assert_false(mm._needs_repaint(false),
			"precondition, and the point of the test: a fixed station with no bodies leaves the gate SHUT, so nothing here repaints on its own")
	Settings.minimap_show_stations = false  # Options -> Accessibility -> "Stations On Minimap"
	assert_true(mm._needs_repaint(false),
			"switching station glyphs off must repaint the map that frame — the station channel has no liveness probe by design, so the drawn-options stamp is the ONLY thing that can ask")
	await _repaint(mm)
	assert_false(mm._drawn_show_stations, "the paint matches the setting it was made from again")
	assert_false(mm._needs_repaint(false), "...and the gate shuts: a static station still costs nothing")
	Settings.minimap_show_stations = was_stations


## THE ZOOM AND THE HEADING, same defect one layer down: these two do not add or remove anything, they change
## the VIEW MATRIX every metre on the map goes through. Both are reachable with the map completely empty — the
## Options sliders, and the M zoom key, which writes through the same Settings setter — so "press zoom, nothing
## happens until you walk" was the shipped behaviour for a standing player in an empty room.
func test_a_zoom_or_heading_change_repaints_an_otherwise_idle_map() -> void:
	var was_zoom: float = Settings.minimap_zoom
	var was_rotates: bool = Settings.minimap_rotates
	var mm = _idle_minimap()
	await _repaint(mm)
	assert_false(mm._needs_repaint(false), "precondition: an empty map under a standing player is idle")
	Settings.minimap_zoom = was_zoom + 0.5
	assert_true(mm._needs_repaint(false), "a zoom change must repaint the map it rescales")
	await _repaint(mm)
	assert_false(mm._needs_repaint(false), "...once")
	Settings.minimap_rotates = not was_rotates
	assert_true(mm._needs_repaint(false), "and flipping heading-up/north-up must repaint the plan it turns")
	await _repaint(mm)
	assert_false(mm._needs_repaint(false), "...once")
	Settings.minimap_zoom = was_zoom
	Settings.minimap_rotates = was_rotates


# --- the station channel --------------------------------------------------------------------------------

## The two-owner idiom, copied verbatim from the NPC dots: the designer switch AND the player's Options row
## both ship ON, and either one off means no glyphs.
func test_station_glyphs_ship_on_for_both_owners() -> void:
	var mm = load(MINIMAP_SCRIPT).new()
	autofree(mm)
	assert_true(mm.dot_stations, "the designer switch ships on")
	var fresh = load("res://managers/Settings.gd").new()
	assert_true(fresh.minimap_show_stations, "and so does the player-facing row")
	fresh.free()

## A station riding a dialogue NPC must get BOTH marks — the shop glyph AND its body's allegiance dot. The old
## de-dupe (skip any Groups.NPC member already in Groups.MINIMAP) is exactly why stations went into their own
## group: joining Groups.MINIMAP would have suppressed the dot, trading "who is hostile" for "who is a shop" on
## the 7-of-8 placed stations that ride NPCs.
func test_a_station_group_membership_does_not_suppress_the_bodys_dot() -> void:
	var npc := NpcStub.new()
	add_child_autofree(npc)
	npc.add_to_group(Groups.NPC)
	npc.add_to_group(Groups.MINIMAP_STATION)
	assert_false(npc.is_in_group(Groups.MINIMAP),
			"the station channel must never be Groups.MINIMAP — that group is what the NPC loop skips")


# --- the zoom cycle key ---------------------------------------------------------------------------------

## The key advances from whatever the map is ACTUALLY showing, not from a remembered index — the Options
## slider can move the value out from under it between presses, and an index would then jump somewhere
## unrelated. Pure, so it needs no InputMap and no autoload.
func test_the_zoom_key_walks_from_the_nearest_authored_step() -> void:
	var mm = load(MINIMAP_SCRIPT).new()
	autofree(mm)
	var steps := PackedFloat32Array([1.0, 1.5, 2.25])
	assert_eq(mm._nearest_zoom_step(steps, 1.0), 0, "an exact match picks its own step")
	assert_eq(mm._nearest_zoom_step(steps, 1.45), 1, "a slider-set value snaps to the closest step")
	assert_eq(mm._nearest_zoom_step(steps, 9.0), 2, "...and one past the end snaps to the last")
	assert_eq(mm._nearest_zoom_step(steps, 0.1), 0, "...or the first")

## The walk WRAPS, so the key is a cycle rather than a ramp that sticks at maximum zoom.
func test_the_zoom_cycle_wraps_at_the_end() -> void:
	var mm = load(MINIMAP_SCRIPT).new()
	autofree(mm)
	var steps: PackedFloat32Array = GameSettings.hud.minimap_zoom_steps
	assert_gt(steps.size(), 1, "the shipped step list must hold more than one value or the key does nothing")
	var last: int = steps.size() - 1
	assert_eq((mm._nearest_zoom_step(steps, steps[last]) + 1) % steps.size(), 0,
			"stepping off the end returns to the first zoom, never past the array")

## Every authored step has to be reachable through the setter, or the key would silently clamp two steps onto
## the same value and the cycle would stutter.
func test_every_authored_zoom_step_is_inside_the_settings_clamp() -> void:
	var s = load("res://managers/Settings.gd")
	for z in GameSettings.hud.minimap_zoom_steps:
		assert_between(z, s.MINIMAP_ZOOM_MIN, s.MINIMAP_ZOOM_MAX,
				"authored zoom step %s must survive set_minimap_zoom's clamp" % z)


## THE ARTIST'S ROW, and the sixth idle-gate term. MenuStyle.set_hud_skin() swaps the resource and calls
## rebuild(); it emits nothing and touches no HUD widget, so before _skin_changed() existed an artist could hand
## the game a second hud_skin.tres — or Godot's Remote inspector could recolour the live one — and a player
## standing still in an empty room kept looking at the old backing, walls, rim and caret indefinitely. Exactly
## the defect the four drawn-options stamps above fix for the PLAYER's rows, one owner across.
func test_a_skin_swap_repaints_an_otherwise_idle_map() -> void:
	var original: Resource = MenuStyle.hud
	var mm = _idle_minimap()
	await _repaint(mm)
	assert_false(mm._needs_repaint(false), "precondition: an empty map under a standing player is idle")
	MenuStyle.set_hud_skin(load("res://scripts/ui/hud_skin.gd").new())
	assert_true(mm._needs_repaint(false),
			"a skin swap must repaint the map it repaints — nothing else on this widget will ever ask")
	await _repaint(mm)
	assert_false(mm._needs_repaint(false),
			"...and exactly ONCE: the stamp is re-taken by the very _draw it triggered, so the gate shuts again")
	MenuStyle.set_hud_skin(original)


## The live-edit half: an artist nudging a colour on the SAME .tres (the Remote-inspector loop) emits
## Resource.changed, which is wired straight to queue_redraw. Pinned as a CONNECTION rather than by driving a
## paint, because `changed` is emitted by the engine on a property write and a unit test asserting the repaint
## would really be asserting Godot's own emit.
func test_the_live_skin_is_wired_for_remote_edits() -> void:
	var mm = _idle_minimap()
	await _repaint(mm)
	assert_true(MenuStyle.hud.changed.is_connected(mm.queue_redraw),
			"the widget listens to the live skin, so editing a slot in the Remote inspector repaints the map")
	# Idempotent: _draw re-runs _sync_skin_signal every paint, and a DUPLICATE connect is an engine error that
	# would take this whole suite down (GUT 9.6 fails on one).
	await _repaint(mm)
	assert_eq(MenuStyle.hud.changed.get_connections().filter(
			func(c): return c["callable"] == Callable(mm, "queue_redraw")).size(), 1,
			"...exactly once, however many times it repaints")
