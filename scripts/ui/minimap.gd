class_name Minimap
extends Control

## @system Minimap
## @seam Code-built by ui.gd into the _weighted carrier (top-right corner, shared with the quest tracker). Geometry comes from the level's baked NavigationMesh via FloorplanSection, paint from MenuStyle.hud.minimap_*, layout from GameSettings.hud.minimap_*, and the player's choices are polled LIVE off Settings.minimap_enabled / _rotates / _zoom so an Options change bites the same frame with no rebuild.
## @seam The level swap is detected from the Groups.NAVMESH region's INSTANCE ID, not a GameRoot signal — a freed region leaves the group by itself, so the deck cache self-heals across a LevelDoor transition and this widget needs no new wiring in game_root.gd.
## @risk Renders ONLY the player's own floor band, so a mezzanine or catwalk above the cut is invisible and a staircase reads as a gap between two decks.
## @risk An unbaked level has no walkable fill and a level with no static colliders has no walls; either degrades to a partial map in silence, because both are legitimate states. Minimap.deck_count() is the introspection seam when a level looks blank.
## @test res://tests/test_minimap.gd
##
## The HUD minimap: a procedural VECTOR FLOORPLAN of the floor the player is standing on, drawn straight
## into a Control with no authored texture, no per-level MapData and no second 3D pass.
##
## WHY NOT A RENDERED IMAGE. The box is ~108 px on a 792x444 canvas that is nearest-upscaled ~2.4x to the
## window. A downscaled 3D render of grey brushwork is mush at that size; hairline strokes are crisp. A
## canvas item is also structurally immune to ps1.gdshader's vertex snap — that is a SPATIAL shader and
## cannot reach 2D drawing — so the plan never warps with the world.
##
## THE PICTURE IS TWO LAYERS, both cached per floor band in a "deck":
##   1. the walkable fill, fanned from the level's BAKED NavigationMesh (FloorplanSection.walkable_triangles);
##   2. the wall strokes, a chest-height section cut of the level's STATIC colliders (added by FloorplanSource).
## Layer 1 alone is already a usable map and needs nothing but a baked navmesh, which every level here has.
## Both are baked ONCE per floor band and then drawn under ONE view matrix, so walking around a floor costs
## a single draw call over a cached buffer and no CPU vertex work at all.
##
## MARKERS are the existing POI channel, unchanged: anything in Groups.MINIMAP (a WorldMarker you place, or
## one QuestMarkerSync spawns for a live objective) gets a dot in its own `color`. Off-floor markers FADE
## rather than lying about being in this room, and off-box ones pin to the rim through the compass's own
## project_to_edge — the same pure projection, not a second copy of it.
##
## The optional `map_data` underlay keeps the authored MapData path alive: assign one and its image is drawn
## UNDER the procedural plan, positioned by its own world_bounds through the SAME matrix, so the picture and
## the dots can never fork projections. Leaving it null — the shipped case — just means the plan is the
## whole map.

@export_group("Geometry")
## The dim navmesh floor fill under the strokes. Off = wall strokes only (a pure line drawing).
@export var draw_walkable: bool = true
## The static-collider section cut. Off = the navmesh fill only — the designed fallback if a level's
## brushwork cuts into unreadable speckle rather than rooms.
@export var draw_walls: bool = true
## How many floor decks stay sliced before the least-recently-used one is dropped. A tower with more
## storeys than this still works; it just re-slices when you revisit a floor.
@export var deck_cache_max: int = 12
## Seconds to wait after a level swap before gathering geometry. func_godot brushes and CSG colliders
## settle over the first frames, and a gather on frame one can see a half-built level.
@export var bake_delay: float = 0.2

@export_group("Markers")
## Radius (px) of the drawn dot used when no MapData marker texture is assigned — the shipped case.
@export var marker_radius: float = 4.0
## Half-length (px) of the player caret triangle.
@export var arrow_size: float = 5.0
## Hide markers further than this many metres away (0 = no limit) — the compass.gd idiom.
@export var max_marker_distance: float = 0.0
## Dot every LIVING Groups.NPC body, tinted by allegiance (hostile / friendly / recruited companion) through
## CBPalette, so the colours match the hover name, the dialogue speaker name and the enemy health bar. The
## designer switch; the player's own is Options -> Accessibility -> "NPCs On Minimap", and BOTH must be on.
## Unlike a POI marker an NPC dot is never pinned to the rim — see _paint_one_marker.
@export var dot_npcs: bool = true

## The wall layer's geometry source, gathered ONCE per level. Preloaded BY PATH and kept untyped so this
## file parses before the editor registers the new class_name (the STAMINA_RING_SCRIPT cache guard).
const FLOORPLAN_SOURCE := preload("res://scripts/ui/floorplan_source.gd")

@export_group("Authored underlay (optional)")
## LEGACY / OPTIONAL: an authored top-down MapData drawn UNDER the procedural plan and positioned through
## the same view matrix via its world_bounds. It is also where marker ART comes from (player_marker /
## npc_marker). Null — the shipped HUD case — means the procedural plan is the whole picture.
@export var map_data: MapData

## deck_key -> {fill: PackedVector2Array, idx: PackedInt32Array, walls: PackedVector2Array, y_lo, y_hi}
var _decks: Dictionary = {}
var _deck_lru: Array[int] = []      ## deck keys, least-recently-used first
var _deck: Dictionary = {}          ## the ACTIVE deck (empty until one is built)
var _source_region_id: int = 0      ## instance id of the NavigationRegion3D the decks were sliced from
var _centre_xz: Vector2 = Vector2.ZERO
var _yaw: float = 0.0
## THE FLOOR THE PLAYER IS STANDING ON, not their live altitude — the reference every vertical decision here
## keys off (which deck to draw, where to cut, how far off-floor a marker is). Only updated while the player
## is grounded, so a JUMP cannot change which storey the map shows. See _update_ground_reference.
var _ground_y: float = 0.0
var _ground_primed: bool = false
var _band_key: int = 0              ## the band currently DRAWN — sticky, see FloorplanSection.sticky_band_key
var _band_keyed: bool = false       ## false until the first deck exists (then _band_key is meaningful)
var _prev_centre: Vector2 = Vector2.ZERO
var _prev_yaw: float = 0.0
var _deck_dirty: bool = true        ## force one repaint (fresh deck, level swap, first frame)
var _bake_delay_left: float = 0.0
var _source = null                  ## FloorplanSource — the level's solids, gathered once (untyped: preload-by-path)


func _ready() -> void:
	# The default MOUSE_FILTER_STOP would make this box eat clicks in the corner of the screen — every
	# other HUD element in this project is explicitly IGNORE for exactly that reason.
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip_contents = true          # a marker pinned to the rim must not escape onto the quest tracker
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST


func _process(delta: float) -> void:
	# A HIDDEN MAP COSTS NOTHING. Not a redraw, not a slice, not even the group scan. This one line is what
	# makes the Options toggle, the dialogue hide and the death hide genuinely free rather than a hidden
	# node still doing all its work.
	if not is_inside_tree() or not is_visible_in_tree():
		return
	var region := _find_region()
	var rid: int = region.get_instance_id() if region != null else 0
	if rid != _source_region_id:
		# A different level (or none). Drop every deck — they are sliced in the old level's world space.
		_source_region_id = rid
		rebake()
		_bake_delay_left = bake_delay
	if _bake_delay_left > 0.0:
		_bake_delay_left = maxf(0.0, _bake_delay_left - delta)
		return
	# The HUMAN player, not get_first_node_in_group(PLAYER) — recruited companions join that group too and
	# the map must never re-centre on one.
	var p := Groups.human_player(get_tree())
	if p == null:
		return
	# The wall layer's geometry, gathered ONCE per level (it only changes when the level does). Deferred
	# until after bake_delay for the same reason the deck is: func_godot brushes and CSG colliders settle
	# over the first frames, and a gather on frame one can see a half-built level.
	if _source == null and draw_walls:
		_source = FLOORPLAN_SOURCE.new()
		_source.gather(_level_root_for(region), Groups.MINIMAP_HIDE)
	_centre_xz = Vector2(p.global_position.x, p.global_position.z)
	_update_ground_reference(p)
	_yaw = _camera_yaw(p)
	_ensure_deck(region, _ground_y)
	# The idle gate: a standing, still player never repaints. It keys on the PLAYER, so it has to be
	# overridden whenever something else on the map can move on its own — otherwise a marker (or a dotted
	# NPC) would freeze in place the moment the player stopped walking.
	var moved := FloorplanSection.needs_redraw(_prev_centre, _centre_xz, _prev_yaw, _yaw,
			GameSettings.hud.minimap_redraw_pos_eps, GameSettings.hud.minimap_redraw_yaw_eps)
	if _deck_dirty or moved or _has_live_markers():
		_prev_centre = _centre_xz
		_prev_yaw = _yaw
		_deck_dirty = false
		queue_redraw()


## The level's NavigationRegion3D. Groups.NAVMESH holds the geometry FEEDER nodes as well as the region
## itself (TestLevel.tscn puts both in it), so this must type-filter rather than take the first member.
func _find_region() -> NavigationRegion3D:
	for n in get_tree().get_nodes_in_group(Groups.NAVMESH):
		if n is NavigationRegion3D:
			return n as NavigationRegion3D
	return null


## The bearing the map is drawn along: the ACTIVE camera's, degrading to the player's own rotation when
## there is no camera (the compass.gd idiom). Matches FloorplanSection's convention, where a yaw of t means
## a forward of (-sin t, -cos t) — the same atan2 ui.gd's sway measurement uses.
func _camera_yaw(p: Node3D) -> float:
	var cam := get_viewport().get_camera_3d()
	var src: Node3D = cam if cam != null else p
	var fwd: Vector3 = -src.global_transform.basis.z
	return atan2(-fwd.x, -fwd.z)


## THE FIX FOR "THE MAP CHANGES WILDLY WHEN I JUMP". Every vertical decision this widget makes — which floor
## deck to draw, where to take the section cut, how far off-floor a marker is — keys off the floor the player
## is STANDING ON, never their instantaneous altitude. A jump taken anywhere near a band boundary would
## otherwise swap the entire floorplan mid-air and swap it back on landing.
##
## is_on_floor() is duck-typed: this widget only knows it holds a Node3D, and a host without the method (a
## test stub, a flying/no-clip debug body) degrades to tracking live Y, which is the old behaviour rather
## than a crash. The first sample always takes, so frame one is never stuck at zero.
func _update_ground_reference(p: Node3D) -> void:
	var grounded: Variant = p.call(&"is_on_floor") if p.has_method(&"is_on_floor") else true
	if grounded == true or not _ground_primed:
		_ground_y = p.global_position.y
		_ground_primed = true


## Is there anything on the map that moves independently of the player? Cheap (two group-size reads) and
## it keeps the idle gate honest — see the note at its call site.
func _has_live_markers() -> bool:
	if not get_tree().get_nodes_in_group(Groups.MINIMAP).is_empty():
		return true
	return dot_npcs and not get_tree().get_nodes_in_group(Groups.NPC).is_empty()


## Make sure the deck for the band containing `y` is built and active. A cache hit is free — this is what
## lets a player walk a whole floor without re-slicing anything.
func _ensure_deck(region: NavigationRegion3D, y: float) -> void:
	var band: float = GameSettings.hud.minimap_band_height
	# STICKY, not a raw quantisation: the drawn floor only changes once the player is properly clear of the
	# one on screen. Paired with the grounded-Y reference above, this is what stops a jump (or a stair riser,
	# or a slope) from flipping the whole plan back and forth.
	var key := FloorplanSection.sticky_band_key(_band_key, _band_keyed, y, band,
			GameSettings.hud.minimap_band_hysteresis)
	_band_key = key
	_band_keyed = true
	if _decks.has(key):
		var hit: Dictionary = _decks[key]
		if _deck != hit:
			_deck = hit
			_deck_dirty = true
		_touch_deck(key)
		return
	# The band edges come from the CHOSEN key, never from re-quantising `y` — otherwise a deck kept alive by
	# the hysteresis above would be filled with the geometry of the band the player has drifted into.
	var y_lo := float(key) * band
	var tris := PackedVector2Array()
	if region != null:
		tris = FloorplanSection.walkable_triangles(region.navigation_mesh, region.global_transform,
				y_lo, y_lo + band)
	# canvas_item_add_triangle_array wants an explicit index list; the soup is already whole triangles in
	# order, so it is just 0..n-1 — built once here rather than every frame in _draw.
	var idx := PackedInt32Array()
	idx.resize(tris.size())
	for i in tris.size():
		idx[i] = i
	# The wall layer: cut the level's solids at chest height above THIS band's floor. Note the cut plane is
	# derived from the band, not from the player's exact Y — otherwise every step up a slope would re-cut.
	var walls := PackedVector2Array()
	if _source != null:
		walls = _source.slice(FloorplanSection.cut_plane(y_lo, GameSettings.hud.minimap_cut_height),
				GameSettings.hud.minimap_max_solid_span, GameSettings.hud.minimap_min_solid_span)
	_deck = {"fill": tris, "idx": idx, "walls": walls, "y_lo": y_lo, "y_hi": y_lo + band}
	_decks[key] = _deck
	_touch_deck(key)
	_evict_decks()
	_deck_dirty = true


func _touch_deck(key: int) -> void:
	_deck_lru.erase(key)
	_deck_lru.append(key)   # most-recently-used last, so the ACTIVE deck is never the eviction candidate


func _evict_decks() -> void:
	while _deck_lru.size() > maxi(deck_cache_max, 1):
		_decks.erase(_deck_lru[0])
		_deck_lru.remove_at(0)


func _draw() -> void:
	var hud: HudSettings = GameSettings.hud
	draw_rect(Rect2(Vector2.ZERO, size), MenuStyle.hud.minimap_backing_color, true)
	var ppm := FloorplanSection.px_per_metre(size, hud.minimap_world_span, Settings.minimap_zoom)
	var view := FloorplanSection.view_transform(_centre_xz, _yaw, ppm, size, Settings.minimap_rotates)
	# EVERYTHING below this line that is in WORLD METRES goes through this one matrix. The underlay, the
	# fill, the walls and (via `view` passed down) the markers all share it, which is the whole reason the
	# image and the dots cannot drift apart.
	draw_set_transform_matrix(view)
	if map_data != null and map_data.map_texture != null:
		# world_bounds IS the draw rect under this matrix — it is already in world X/Z metres.
		draw_texture_rect(map_data.map_texture, map_data.world_bounds, false)
	if not _deck.is_empty():
		var fill: PackedVector2Array = _deck["fill"]
		if draw_walkable and not fill.is_empty():
			# A triangle soup has no single-polygon form, so this goes through the RenderingServer rather
			# than draw_colored_polygon (which triangulates ONE polygon) or draw_mesh (which would need a
			# texture and an ArrayMesh for no gain). It honours the transform set above.
			RenderingServer.canvas_item_add_triangle_array(get_canvas_item(), _deck["idx"], fill,
					PackedColorArray([MenuStyle.hud.minimap_walkable_color]))
		var walls: PackedVector2Array = _deck["walls"]
		if draw_walls and not walls.is_empty():
			# ONE call for the whole floorplan. The width goes through stroke_width because draw_multiline's
			# width is in LOCAL units and this matrix scales by ppm — a raw px value would fatten as the
			# player zooms in.
			draw_multiline(walls, MenuStyle.hud.minimap_wall_color,
					FloorplanSection.stroke_width(hud.minimap_wall_width, ppm))
	draw_set_transform_matrix(Transform2D.IDENTITY)
	_paint_markers(view, hud)
	_paint_player_caret()
	_paint_chrome(hud)


## POI dots. Markers are painted in SCREEN space (the matrix is already reset) but positioned through
## `view`, so they sit exactly on the plan they annotate.
func _paint_markers(view: Transform2D, hud: HudSettings) -> void:
	var art: Texture2D = map_data.npc_marker if map_data != null else null
	# POI markers PIN to the rim when off-box: a quest objective's whole job is to point you at something you
	# cannot see yet.
	for n in get_tree().get_nodes_in_group(Groups.MINIMAP):
		_paint_one_marker(n, view, hud, art, true, marker_color(n))
	if not (dot_npcs and Settings.minimap_show_npcs):
		return
	for n in get_tree().get_nodes_in_group(Groups.NPC):
		# An NPC that also carries a WorldMarker is already drawn above; skip it rather than double-painting
		# a dot at half the intended alpha.
		if n.is_in_group(Groups.MINIMAP):
			continue
		if not _npc_is_live(n):
			continue
		# NPC dots deliberately do NOT pin to the rim. A pinned dot would report every body on the level
		# against the box edge — that is a radar, not a floorplan, and it would quietly hand the player
		# through-wall knowledge of the whole map. Clipped to the box, a dot means "actually near you".
		_paint_one_marker(n, view, hud, art, false, npc_dot_color(n))


func _paint_one_marker(n: Node, view: Transform2D, hud: HudSettings, art: Texture2D,
		pin_offscreen: bool, col: Color) -> void:
	if not is_instance_valid(n):
		return
	var n3 := n as Node3D
	if n3 == null:
		return
	var w := n3.global_position
	if max_marker_distance > 0.0 and Vector2(w.x, w.z).distance_to(_centre_xz) > max_marker_distance:
		return
	var q: Vector2 = view * Vector2(w.x, w.z)
	if not Rect2(Vector2.ZERO, size).has_point(q):
		if not pin_offscreen:
			return  # off the box and not worth pointing at — see the radar note at the call site
		# Off the box: pin it to the rim pointing the right way, through the compass's own pure edge
		# projection rather than a second implementation of the same maths.
		q = Compass.project_to_edge(q - size * 0.5, size, hud.minimap_marker_edge_margin)
	# Vertical honesty: a beacon two storeys up fades instead of pretending to be in this room.
	col.a *= FloorplanSection.marker_alpha(w.y - _ground_y, hud.minimap_band_height,
			hud.minimap_marker_floor_alpha)
	if art != null:
		draw_texture(art, q - art.get_size() * 0.5, col)
	else:
		draw_circle(q, marker_radius, col)


## A marker's own color (quest / vendor / exit beacons set it) — type-guarded like compass.gd; a marker
## that carries none falls back to the skin's NPC tint. Instance method so tests can call it off-tree;
## unit-tested, and test_hud_skin.gd depends on this exact contract.
func marker_color(marker: Node) -> Color:
	var raw_col: Variant = marker.get(&"color")
	return raw_col if raw_col is Color else MenuStyle.hud.minimap_npc_color


## An NPC dot's tint, by ALLEGIANCE rather than by art: a recruited companion reads blue, a hostile red and a
## friendly green, exactly as that NPC's hover name, dialogue speaker name and enemy health bar already do —
## one mapping (CBPalette.disposition_color) so the four surfaces can never drift into telling different
## stories about the same body. Anything that is not really an NPC falls back to the skin's neutral tint.
##
## Duck-typed with `== true` rather than bool(...): these are Variant returns from a dynamic call, and
## GDScript 4 has no bool(String) constructor (the house rule, and the enemy_health_bar._color_for idiom).
func npc_dot_color(npc: Node) -> Color:
	var neutral: Color = MenuStyle.hud.minimap_npc_color
	if not is_instance_valid(npc) or not npc.has_method(&"resolved_disposition"):
		return neutral
	var ally: bool = npc.has_method(&"is_following") and npc.call(&"is_following") == true
	return CBPalette.disposition_color(ally, int(npc.call(&"resolved_disposition")), neutral)


## Is this NPC worth a dot? A corpse is not — and NPCs are POOLED here, so a dead one stays in the group
## waiting to be reused and would otherwise leave a permanent blip where it fell. is_alive() is duck-typed;
## a host without it is assumed live rather than silently dropped.
func _npc_is_live(npc: Node) -> bool:
	if not is_instance_valid(npc):
		return false
	if not npc.has_method(&"is_alive"):
		return true
	return npc.call(&"is_alive") == true


## The player, always at the box centre. Heading-up welds the caret pointing screen-up and turns the plan
## under it; north-up freezes the plan and spins the caret. An authored MapData.player_marker replaces the
## drawn triangle (the widget-art fallback rule).
func _paint_player_caret() -> void:
	var c := size * 0.5
	var col: Color = MenuStyle.hud.minimap_player_color
	var art: Texture2D = map_data.player_marker if map_data != null else null
	if art != null:
		draw_texture(art, c - art.get_size() * 0.5, col)
		return
	var r := Transform2D(FloorplanSection.arrow_angle(_yaw, Settings.minimap_rotates), Vector2.ZERO)
	draw_colored_polygon(PackedVector2Array([
		c + r.basis_xform(Vector2(0.0, -arrow_size)),
		c + r.basis_xform(Vector2(arrow_size * 0.7, arrow_size * 0.8)),
		c + r.basis_xform(Vector2(-arrow_size * 0.7, arrow_size * 0.8)),
	]), col)


## The box's edge: authored frame art when the skin carries it, else a drawn contrast rim.
func _paint_chrome(hud: HudSettings) -> void:
	var frame: Texture2D = MenuStyle.hud.minimap_frame_texture
	if frame != null:
		draw_texture_rect(frame, Rect2(Vector2.ZERO, size), false)
		return
	if hud.minimap_outline_width > 0.0:
		draw_rect(Rect2(Vector2.ZERO, size), MenuStyle.hud.minimap_outline_color, false,
				hud.minimap_outline_width)


## Drop every cached deck and re-slice on the next frame. Called automatically on a level swap; exposed
## for a designer/debug hook and for a future "the level geometry changed" caller.
func rebake() -> void:
	_decks.clear()
	_deck_lru.clear()
	_deck = {}
	_band_keyed = false   # nothing drawn -> the next band choice takes the raw answer, not a stale sticky one
	_source = null   # the solids are in the OLD level's world space — re-gather, never re-cut
	_deck_dirty = true


## The subtree the wall cut is gathered from: the ancestor named "Level" (GameRoot.load_level names the
## instantiated level exactly that) when there is one, else the navmesh region's `owner` (an instantiated
## scene's children carry owner == its root), else the region itself. Resolved fresh on every gather, so a
## LevelDoor swap is picked up by the same region-instance-id staleness check that drops the deck cache —
## which is why this widget needs no signal from GameRoot.
func _level_root_for(region: Node) -> Node:
	if region == null:
		return null
	var cur: Node = region
	while cur != null:
		if cur.name == &"Level":
			return cur
		cur = cur.get_parent()
	return region.owner if region.owner != null else region


## How many floor decks are currently sliced. Introspection for tests, and the thing to check first when a
## level's map looks blank.
func deck_count() -> int:
	return _decks.size()


## The lower edge (world metres) of the band currently drawn, or 0.0 before the first deck exists.
func active_band_floor() -> float:
	return float(_deck.get("y_lo", 0.0))
