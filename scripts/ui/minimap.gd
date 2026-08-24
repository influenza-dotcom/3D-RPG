class_name Minimap
extends Control

## @system Minimap
## @seam AUTHORED SCENE: scenes/ui/hud_minimap.tscn, instantiated by ui.gd into the _weighted carrier (top-right corner, shared with the quest tracker). The SCENE owns the box — anchors, offsets, z_index, texture filter and the two art slots — and ui.gd MEASURES it back through UI.minimap_box() so the clock and the objective tracker reflow when an artist drags it. Geometry comes from the level's baked NavigationMesh via FloorplanSection, paint from MenuStyle.hud.minimap_*, fallback layout from GameSettings.hud.minimap_*, and the player's choices are polled LIVE off Settings.minimap_enabled / _rotates / _zoom so an Options change bites the same frame with no rebuild.
## @seam THE ART SANDWICH — the artist's drop-in surface, and the reason this widget is a scene at all. This script's _draw is ONE layer; the scene wraps it in two empty full-rect slots whose TREE ORDER is the render order: %MapUnder (forced show_behind_parent in _ready, so the slot NAME is the contract rather than a checkbox an artist must remember) renders wholly BEHIND the plan — a backdrop supplied there wants the ALPHA of MenuStyle.hud.minimap_backing_color zeroed so it shows through, the alpha-as-null sentinel this project already uses for StationMarker.color — and %MapOver renders wholly IN FRONT of plan, markers, caret and rim, which is where a bezel/frame/glass/vignette belongs (a NinePatchRect there beats minimap_frame_texture's plain stretch). THREE LIMITS: art cannot be inserted BETWEEN the plan and the marker channels (they are one _draw), everything is clipped to the box by clip_contents below, and art children need NO repaint wiring at all — each is its own CanvasItem, so nothing an artist adds can touch _needs_repaint / _painted / the drawn stamps. ⚠ The live READ is only half of that: a Control repaints solely on queue_redraw, so it also takes the drawn-options stamps below to notice the row moved — without them the live read is a lie for any player who is standing still (see the queue_redraw @risk).
## @seam The level swap is detected from the Groups.NAVMESH region's INSTANCE ID, not a GameRoot signal — a freed region leaves the group by itself, so the deck cache self-heals across a LevelDoor transition and this widget needs no new wiring in game_root.gd.
## @seam The authored underlay is per-level: LevelData.map_data, PULLED (never pushed) by _resolve_level_underlay inside rebake() — the same region-instance-id hook — via Groups.GAME_ROOT's `level`. The widget's own map_data export is a per-instance override that wins when set, and a level without an authored map CLEARS the previous level's art (the stamp writes null too).
## @risk Renders ONLY the player's own floor band, so a mezzanine or catwalk above the cut is invisible and a staircase reads as a gap between two decks.
## @risk An unbaked level has no walkable fill and a level with no static colliders has no walls; either degrades to a partial map in silence, because both are legitimate states. Minimap.deck_count() is the introspection seam when a level looks blank.
## @seam THREE marker channels, painted in this order and each with its own rules: Groups.MINIMAP (POI beacons — a plain dot, PINS to the rim), Groups.MINIMAP_STATION (station glyphs — stroked shapes, pin per StationMarker.pin_offscreen), Groups.NPC (bodies — filled shapes by allegiance, NEVER pinned). A node in two channels is drawn by both on purpose: a shop riding a dialogue NPC is both a place to trade and a body with an allegiance.
## @seam SHAPE is the primary marker channel and HUE the secondary one (MapGlyph): hostile caret / ally diamond / friendly dot / neutral ring, and seven stroked station shapes. At a ~4 px radius hue alone could not carry the distinction, and Settings.colorblind_safe_cues exists because it is contested even at size.
## @risk A hostile's alert ring reads NPC.suspicion_of(player), which is target-gated — it only ever reports awareness OF THE PLAYER, never of another NPC. Widening it to is_in_combat() (target-agnostic) would ring every guard fighting a stray dog and read as "they are onto you".
## @risk A CanvasItem repaints ONLY on queue_redraw(), and the idle gate deliberately withholds that from a standing, still player — so every fact this picture shows owes the gate a way to ask for the ONE repaint that takes it back OFF the canvas when it stops being true. _needs_repaint is that gate, and three of its terms exist purely as those trailing edges (_painted for the marker channels, the drawn-options stamps for the player's Options rows, the drawn-skin stamp for the ARTIST's hud_skin.tres). A new painted channel added without one strands its art on the map forever.
## @risk Never draw a sight CONE here. Perception.can_see() raycasts, and _draw/_process run OFF the physics frame where direct_space_state returns EMPTY silently — a cone would look right in tests and report "sees nothing" in play. The authored sight_range/fov_degrees would draw a cone that is also a wallhack.
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
##   2. the wall strokes, a chest-height section cut of the level's STATIC colliders (added by FloorplanSource),
##      drawn as ONE MERGED SILHOUETTE — a level is built out of overlapping boxes, and the sides buried inside
##      a neighbouring solid are seams of a single wall, so they are differenced away (see
##      FloorplanSection.silhouette; GameSettings.hud.minimap_merge_solids turns it off).
## Layer 1 alone is already a usable map and needs nothing but a baked navmesh, which every level here has.
## Both are baked ONCE per floor band and then drawn under ONE view matrix, so walking around a floor costs
## a single draw call over a cached buffer and no CPU vertex work at all.
##
## MARKERS are the existing POI channel, unchanged: anything in Groups.MINIMAP (a WorldMarker you place, or
## one QuestMarkerSync spawns for a live objective) gets a dot in its own `color`. Off-floor markers FADE
## rather than lying about being in this room, and off-box ones pin to the rim through the compass's own
## project_to_edge — the same pure projection, not a second copy of it.
##
## The optional authored underlay: a MapData's image is drawn UNDER the procedural plan, positioned by its
## own world_bounds through the SAME matrix, so the picture and the dots can never fork projections. It is
## authored PER LEVEL — LevelData.map_data, stamped by _resolve_level_underlay through Groups.GAME_ROOT on
## the same staleness hook that drops the deck cache — with this widget's own `map_data` export kept as a
## per-instance override that wins when set. Both null — the shipped case — just means the plan is the
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
# MARKER SIZES ARE NOT HERE ANY MORE. The POI dot's radius and the player caret's half-length used to be
# `marker_radius` / `arrow_size` @exports on this widget, which left the four marker sizes spread over three
# files: two here, and the body/station radii on GameSettings.hud. They are now
# MenuStyle.hud.minimap_poi_glyph_px / minimap_caret_px, beside every other size and colour the map paints —
# one resource answers "how big is everything and what colour is it". What stays below is what this widget
# DOES rather than how it LOOKS.
## Hide markers further than this many metres away (0 = no limit) — the compass.gd idiom.
@export var max_marker_distance: float = 0.0
## Dot every LIVING Groups.NPC body, tinted by allegiance (hostile / friendly / recruited companion) through
## CBPalette, so the colours match the hover name, the dialogue speaker name and the enemy health bar. The
## designer switch; the player's own is Options -> Accessibility -> "NPCs On Minimap", and BOTH must be on.
## Unlike a POI marker an NPC dot is never pinned to the rim — see _paint_one_marker.
@export var dot_npcs: bool = true
## Glyph every Groups.MINIMAP_STATION member (a station carrying a StationMarker) with its kind's SHAPE. The
## designer switch; the player's own is Options -> Accessibility -> "Stations On Minimap", and BOTH must be on —
## the dot_npcs / Settings.minimap_show_npcs two-owner idiom, verbatim.
@export var dot_stations: bool = true

## The wall layer's geometry source, gathered ONCE per level. Preloaded BY PATH and kept untyped so this
## file parses before the editor registers the new class_name (the STAMINA_RING_SCRIPT cache guard).
const FLOORPLAN_SOURCE := preload("res://scripts/ui/floorplan_source.gd")

## The marker-art precedence / sizing rules (scripts/ui/minimap_art.gd — statics only). Preloaded BY PATH and
## kept untyped for the same cache reason as the line above: a NEW class_name is not in the editor's global
## cache until it reimports, and a by-name reference here would take this whole file down until it does.
const MINIMAP_ART := preload("res://scripts/ui/minimap_art.gd")

@export_group("Authored underlay (optional)")
## PER-INSTANCE OVERRIDE: an authored top-down MapData drawn UNDER the procedural plan and positioned
## through the same view matrix via its world_bounds. It is also where marker ART comes from (player_marker /
## npc_marker). The normal authoring surface is LevelData.map_data (resolved per level into
## _level_map_data); set THIS only to pin one widget's underlay regardless of level — when set it WINS over
## the level's (see active_map_data). Null — the shipped HUD case — defers to the level.
@export var map_data: MapData

## deck_key -> {fill: PackedVector2Array, idx: PackedInt32Array, walls: PackedVector2Array, y_lo, y_hi}
var _decks: Dictionary = {}
var _deck_lru: Array[int] = []      ## deck keys, least-recently-used first
var _deck: Dictionary = {}          ## the ACTIVE deck (empty until one is built)
## Instance id of the NavigationRegion3D the decks were sliced from. Seeded -1 — an id no region (and no
## ABSENCE of a region, which reads 0) can ever produce — so the FIRST processed frame always trips the
## staleness check below: even a REGION-LESS boot must rebake once, or an authored level underlay would
## silently never resolve on a level with no NavigationRegion3D.
var _source_region_id: int = -1
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
var _level_map_data: MapData = null ## the ACTIVE level's authored underlay (LevelData.map_data), re-stamped — even to null — on every rebake
## True while the canvas still HOLDS marker art from a channel the idle gate WATCHES — a Groups.MINIMAP beacon
## or a Groups.NPC body dot. A CanvasItem re-runs _draw() ONLY when something calls queue_redraw(); it does not
## repaint per frame. So the frame a channel goes empty the gate below shuts, and the dots painted on the
## PREVIOUS frame stay on the map for as long as the player stands still: the last quest beacon is collected, or
## the last NPC dies, and its blip is simply left there. Same defect and same fix as the stuck aim arc
## (aim_indicators.gd's own _painted) — this latch lets that one frame queue exactly ONE clearing repaint.
##
## It cannot PIN the gate open the way a bare "is anything drawn" flag would (this widget always paints a
## backing, a caret and a frame, so "anything drawn" is true forever and the idle gate would be dead). It is set
## ONLY from the two channels _has_live_markers() itself probes, so `_painted and not _has_live_markers()` is
## reachable for exactly one frame — the repaint it asks for finds those channels empty and clears it again.
## Station glyphs deliberately do NOT set it: a fixed shop would hold the gate open forever, which is the very
## thing _has_live_markers() excludes them to avoid. The station channel's stranding case that is reachable in
## shipped content is its Options row, and that is covered by the drawn-options stamps below; the two that stay
## open are both authoring-only — a station node spawned or freed at runtime (every shipped one is authored into
## the .tscn), and a station that MOVES on a carrier which is not itself in Groups.NPC (a lift, a vehicle), which
## is the trap the _has_live_markers docs already describe.
var _painted: bool = false
## THE PLAYER'S FOUR MINIMAP CHOICES AS THE LAST _draw READ THEM. These Settings rows carry no apply step by
## design — "Minimap reads it live in _draw" — which quietly assumed a repaint would be along shortly. For a
## player standing still in a room with nothing live on the map, none ever is: switch NPC dots or station glyphs
## off in Options and the dots you just turned off stay painted; nudge the zoom slider (or press the zoom key,
## which writes through the same setter) and nothing moves until you walk. Comparing the stamp each frame is
## what makes the live read true. Self-clearing like _painted: _draw re-stamps, so one repaint later the compare
## agrees again and the idle gate shuts as before. Seeded NAN so the first compare mismatches any saved zoom.
var _drawn_zoom: float = NAN
var _drawn_rotates: bool = false
var _drawn_show_npcs: bool = false
var _drawn_show_stations: bool = false
## THE SKIN THIS PAINT WAS MADE FROM — the artist's half of the same trailing-edge problem the four stamps above
## solve for the player. MenuStyle.set_hud_skin() swaps MenuStyle.hud and calls rebuild(); it emits nothing and
## touches no HUD widget. Its own doc's claim that "the HUD's _draw consumers read MenuStyle.hud live each frame"
## is FALSE for this widget in exactly the way it was false for the four Settings rows before those stamps
## existed: swap a skin (or hand an artist a second .tres) while standing still in an empty room and the map
## keeps the old backing, walls, rim and caret forever.
##
## An INSTANCE ID, not a hash of the slots: this compare runs every frame from _needs_repaint and must not
## allocate, on a widget whose body loop is already commented for hoisting one lookup out of a per-NPC path.
## Seeded 0 — no instance id is ever 0 — so the first compare mismatches, which _deck_dirty already forced.
var _drawn_skin_id: int = 0
## The skin this widget is currently listening to, so the connection is re-pointed on a swap and never doubled.
## See _sync_skin_signal.
var _signal_skin: Resource = null


## The box is AUTHORED now (scenes/ui/hud_minimap.tscn), so this no longer builds a look — it enforces the two
## properties an artist must not be able to break, and adopts whatever art the scene carries. Every line below is
## a silent no-op on a bare .new() with no children and no scene owner, which is the contract
## tests/test_minimap.gd:24 pins and test_hud_skin.gd leans on.
##
## texture_filter is deliberately NOT written here any more: it is authored in the scene (NEAREST, the pixel
## look), and a hand-painted frame is exactly the case that might legitimately want otherwise. It inherits down
## to the art slots for free — CanvasItem.texture_filter defaults to TEXTURE_FILTER_PARENT_NODE.
func _ready() -> void:
	# The default MOUSE_FILTER_STOP would make this box eat clicks in the corner of the screen — every
	# other HUD element in this project is explicitly IGNORE for exactly that reason. Code-owned, not
	# authored: there is no legitimate want for a HUD readout to take mouse input.
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip_contents = true          # a marker pinned to the rim must not escape onto the quest tracker
	_adopt_authored_art(self)
	# THE SLOT NAME IS THE CONTRACT. Forcing it here rather than trusting the .tscn's checkbox means an artist
	# who duplicates the scene, or rebuilds the slot by hand, still gets "under" from calling it MapUnder.
	var under := get_node_or_null(^"%MapUnder")
	if under is CanvasItem:
		(under as CanvasItem).show_behind_parent = true
	# The editor-only fill: it exists so the 2D editor shows a box to align art against instead of an empty
	# outline. It has no job at runtime, where the real backing rect paints over it anyway.
	var preview := get_node_or_null(^"%EditorPreview")
	if preview is CanvasItem:
		(preview as CanvasItem).visible = false
	_sync_skin_signal()


## Sweep every authored art node to MOUSE_FILTER_IGNORE. mouse_filter does NOT propagate to children, and an
## authored TextureRect / NinePatchRect / ColorRect / Panel defaults to MOUSE_FILTER_STOP — so the FIRST piece of
## art an artist drops into %MapUnder or %MapOver would re-open the exact bug the _ready comment above exists to
## prevent: the top-right corner of the screen quietly eating clicks. Deliberately stomps the inspector value
## rather than trusting it, because there is no HUD art that wants the mouse.
##
## `^"%MapUnder"` and friends are read with get_node_or_null, never the `%Name` sugar (which is get_node and
## pushes an ENGINE ERROR when absent — GUT 9.6 fails a whole suite on one of those, and a bare .new() has none
## of these nodes).
func _adopt_authored_art(node: Node) -> void:
	for child in node.get_children():
		if child is Control:
			(child as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE
		_adopt_authored_art(child)


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
	_poll_zoom_key()
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
	# overridden whenever something else on the map can move — or VANISH, or be switched off — on its own;
	# otherwise a marker (or a dotted NPC) would freeze in place the moment the player stopped walking. See
	# _needs_repaint.
	var moved := FloorplanSection.needs_redraw(_prev_centre, _centre_xz, _prev_yaw, _yaw,
			GameSettings.hud.minimap_redraw_pos_eps, GameSettings.hud.minimap_redraw_yaw_eps)
	if _needs_repaint(moved):
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


## THE IDLE GATE, as one question: does the canvas still match the world this frame? A standing, still player
## looking at an empty map answers no on every term and costs nothing, which is the whole point of the gate.
##
## Ordered cheapest-first and short-circuited: three plain field reads, then four Settings compares, then the
## only term that allocates (one or two group arrays). Note that two of the five are
## TRAILING EDGES, not live facts: because a CanvasItem repaints only on queue_redraw, asking "is anything live
## NOW" is not enough. Something that WAS painted and has since stopped being true needs one further repaint to
## be taken back OFF the canvas, or it stays there for as long as the player stands still. `_painted` is that
## edge for the marker channels; the drawn-options stamps are that edge for the player's Options rows. Both are
## re-stamped by the very _draw they trigger, so neither can hold this gate open past the one clearing frame.
##
## Instance-shaped and separated out so a test can step the gate frame by frame without the rest of _process:
## reaching it for real needs a live human player in the tree (Groups.human_player positively identifies the
## Player CLASS, so no lighter stand-in gets past the bail above), which is a heavy rig for a unit test.
## tests/test_minimap.gd does both — one test drives the whole _process path, the rest step this directly.
func _needs_repaint(moved: bool) -> bool:
	return _deck_dirty or moved or _painted or _options_changed() or _skin_changed() or _has_live_markers()


## Has the ARTIST's skin moved since the last paint? The sixth term, and the one that makes hud_skin.tres a live
## surface rather than a boot-time one — see _drawn_skin_id for the stale-paint bug it closes.
##
## Deliberately NOT folded into _options_changed(): that function's name and doc are about the PLAYER's Options
## rows, tests read _drawn_show_npcs / _drawn_show_stations through it by name, and a skin term hiding in there
## would be stale prose the next reader has to disprove.
func _skin_changed() -> bool:
	return _drawn_skin_id != MenuStyle.hud.get_instance_id()


## THE LIVE-EDIT HALF. The instance-id compare above catches a whole-skin SWAP; it cannot see an artist editing a
## slot on the SAME .tres — which is precisely what Godot's built-in Remote inspector does against a running
## game, and the tightest art loop this project can offer someone who is not a Godot user. Resource.changed fires
## for exactly that edit. Costs nothing in a shipped build, where nothing emits it.
##
## Called from _ready and from the TAIL of _draw, so a runtime set_hud_skin re-points the connection on the very
## repaint the id compare just asked for. The is_instance_valid + is_connected guards are not defensive habit: a
## duplicate connect, or a disconnect on a freed Resource, is an ENGINE ERROR, and GUT 9.6 fails a whole suite on
## one of those. `changed` carries no arguments and queue_redraw takes none, so the direct connection is legal.
func _sync_skin_signal() -> void:
	var s: Resource = MenuStyle.hud
	if s == _signal_skin:
		return
	if is_instance_valid(_signal_skin) and _signal_skin.changed.is_connected(queue_redraw):
		_signal_skin.changed.disconnect(queue_redraw)
	_signal_skin = s
	if s != null and not s.changed.is_connected(queue_redraw):
		s.changed.connect(queue_redraw)


## Has one of the player's minimap Options rows moved since the last paint? Zoom and heading-up/north-up change
## the VIEW MATRIX; the two show_* rows add or remove a whole marker channel. Four compares and no allocation,
## so it is cheap enough to ask every frame — and it is what makes the M zoom key bite as well, since
## _poll_zoom_key writes through the same Settings setter the Options slider does. NAN's own inequality is what
## makes the seeded first compare mismatch.
func _options_changed() -> bool:
	return _drawn_zoom != Settings.minimap_zoom \
			or _drawn_rotates != Settings.minimap_rotates \
			or _drawn_show_npcs != Settings.minimap_show_npcs \
			or _drawn_show_stations != Settings.minimap_show_stations


## Is there anything on the map that moves independently of the player? Cheap (two group-size reads) and
## it keeps the idle gate honest — see the note at its call site, _needs_repaint.
##
## The NPC term now asks the SAME question the paint site asks — `dot_npcs and Settings.minimap_show_npcs` —
## because it previously read only the designer half. A player who switched dots off in Options still paid a
## full repaint every frame for bodies that were never drawn, which is exactly the cost the Options row is
## supposed to remove.
##
## Groups.MINIMAP_STATION IS DELIBERATELY NOT SCANNED even though stations are a third painted channel. A
## station does not move, so a repaint on its behalf is a repaint for nothing, and a level with one shop in it
## would pin this gate open forever for no gain.
##
## But the moving-station case is real and must not freeze: 7 of the 8 stations placed in this project ride a
## dialogue NPC, so their glyphs walk around with the body. Groups.NPC is the correct probe for BOTH channels —
## the only station that moves is one attached to a body that is already in that group — so the NPC scan is
## reached whenever EITHER channel is drawn. Reading only the NPC toggle here would freeze a walking
## shopkeeper's glyph mid-stride for any player who turned body dots off.
func _has_live_markers() -> bool:
	if not get_tree().get_nodes_in_group(Groups.MINIMAP).is_empty():
		return true
	var bodies := dot_npcs and Settings.minimap_show_npcs
	var stations := dot_stations and Settings.minimap_show_stations
	if not (bodies or stations):
		return false
	return not get_tree().get_nodes_in_group(Groups.NPC).is_empty()


## THE ZOOM CYCLE KEY (default M). Walks GameSettings.hud.minimap_zoom_steps in order and wraps, writing through
## Settings.set_minimap_zoom — the SAME setter the Options slider calls, so the key and the slider are one value
## and a keyed zoom persists to user://settings.cfg like any other choice.
##
## Three gates, all necessary: this runs from _process, which is already past the is_visible_in_tree bail (so a
## hidden HUD ignores the key); gameplay_suppressed() keeps it from firing under an open Pip-Boy or shop, where
## the same physical key may mean something else; and an EMPTY steps list disables the feature outright rather
## than dividing by zero.
##
## "Nearest step, then advance" rather than a remembered index: the slider can move the value out from under us
## between presses, and an index would then jump somewhere unrelated. This way the key always advances from
## whatever the map is actually showing.
func _poll_zoom_key() -> void:
	var steps: PackedFloat32Array = GameSettings.hud.minimap_zoom_steps
	if steps.is_empty() or InputManager.gameplay_suppressed():
		return
	if not Input.is_action_just_pressed(InputManager.action_minimap_zoom):
		return
	Settings.set_minimap_zoom(steps[(_nearest_zoom_step(steps, Settings.minimap_zoom) + 1) % steps.size()])


## Index of the authored step closest to `now`. Static-shaped (no state) and separated out so the wrap-around
## walk is provable off-tree without an InputMap, a tree or a Settings autoload.
static func _nearest_zoom_step(steps: PackedFloat32Array, now: float) -> int:
	var best := 0
	var best_d := INF
	for i in steps.size():
		var d := absf(steps[i] - now)
		if d < best_d:
			best_d = d
			best = i
	return best


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
				GameSettings.hud.minimap_max_solid_span, GameSettings.hud.minimap_min_solid_span,
				GameSettings.hud.minimap_merge_solids, GameSettings.hud.minimap_merge_weld)
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
	# THE TWO SURFACES, hoisted once for the whole paint. `skin` is the ARTIST's (every colour and every
	# width/size the map inks — MenuStyle.hud, hud_skin.tres); `hud` is what the map DOES rather than how it
	# looks, and by this point only three of its knobs are still read down here (world span, band height, and
	# the deck-slicing numbers above). Untyped for the class_name-cache reason MenuStyle.hud itself is.
	var hud: HudSettings = GameSettings.hud
	var skin = MenuStyle.hud
	# STAMP THE OPTIONS THIS PAINT IS MADE FROM, before anything reads them below. _process compares the stamp
	# next frame, and that comparison is the only thing asking for a repaint when a player standing still flips
	# an Options row — see _options_changed.
	_drawn_zoom = Settings.minimap_zoom
	_drawn_rotates = Settings.minimap_rotates
	_drawn_show_npcs = Settings.minimap_show_npcs
	_drawn_show_stations = Settings.minimap_show_stations
	_drawn_skin_id = MenuStyle.hud.get_instance_id()
	# THE BACKING IS AN ALPHA-SENTINEL SLOT. An artist supplying a backdrop in %MapUnder zeroes this colour's
	# alpha in hud_skin.tres so their art shows through — the StationMarker.color idiom. draw_rect at alpha 0
	# costs one no-op command, so there is nothing to branch on.
	draw_rect(Rect2(Vector2.ZERO, size), MenuStyle.hud.minimap_backing_color, true)
	var ppm := FloorplanSection.px_per_metre(size, hud.minimap_world_span, Settings.minimap_zoom)
	var view := FloorplanSection.view_transform(_centre_xz, _yaw, ppm, size, Settings.minimap_rotates)
	# EVERYTHING below this line that is in WORLD METRES goes through this one matrix. The underlay, the
	# fill, the walls and (via `view` passed down) the markers all share it, which is the whole reason the
	# image and the dots cannot drift apart.
	draw_set_transform_matrix(view)
	var underlay := active_map_data()
	if underlay != null and underlay.map_texture != null:
		# world_bounds IS the draw rect under this matrix — it is already in world X/Z metres.
		draw_texture_rect(underlay.map_texture, underlay.world_bounds, false)
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
			# THE OPTIONAL GLOW PASS, first so it lands UNDER the strokes it surrounds: the same wall geometry
			# drawn once more, wider, in its own colour. That is the whole restyle affordance for the plan —
			# neon bloom, or a dark drop-shadowed "inked on paper" look — for one extra draw call over a buffer
			# that is already built, and with no shader and no second viewport.
			#
			# ALPHA 0 = OFF is the switch (the alpha-as-null sentinel, as with the backing), so the shipped map
			# pays exactly one Color.a compare for a feature it does not use.
			var glow: Color = skin.minimap_wall_glow_color
			if glow.a > 0.0:
				draw_multiline(walls, glow,
						FloorplanSection.stroke_width(skin.minimap_wall_glow_width, ppm))
			# ONE call for the whole floorplan. The width goes through stroke_width because draw_multiline's
			# width is in LOCAL units and this matrix scales by ppm — a raw px value would fatten as the
			# player zooms in.
			draw_multiline(walls, skin.minimap_wall_color,
					FloorplanSection.stroke_width(skin.minimap_wall_width, ppm))
	draw_set_transform_matrix(Transform2D.IDENTITY)
	_paint_markers(view, skin)
	_paint_player_caret(skin)
	_paint_chrome(skin)
	# Re-point the live-edit listener at whatever skin this paint just read. Here rather than only in _ready so
	# a runtime MenuStyle.set_hud_skin re-subscribes on the very repaint _skin_changed asked for.
	_sync_skin_signal()


## THE THREE MARKER CHANNELS, painted back-to-front in this order: POI beacons, then station glyphs, then
## bodies. Markers are painted in SCREEN space (the matrix is already reset) but positioned through `view`, so
## they sit exactly on the plan they annotate — and because they are in pixels, a glyph is the same size at
## every zoom while the plan under it scales.
##
## The order is the priority: a body is the most volatile fact on the map and paints last, so a shopkeeper's
## allegiance dot sits ON TOP of the shop glyph they carry rather than under it.
func _paint_markers(view: Transform2D, skin) -> void:
	var md := active_map_data()
	# An authored MapData.npc_marker now reaches the POI channel ONLY. It used to be handed to the NPC loop as
	# well, so a level that authored a body blip silently retextured every quest beacon too — and, worse, one
	# texture cannot carry an allegiance, which is the distinction the NPC channel exists to make. Bodies are
	# drawn shapes now; this slot stays the POI beacons' art.
	# THE POI CHANNEL'S ART, in precedence order: this level's authored MapData.npc_marker, else the skin's
	# drop-in slot, else null (the flat drawn dot — the shipped case).
	var art: Texture2D = MINIMAP_ART.pick(md.npc_marker if md != null else null,
			MenuStyle.hud.minimap_poi_texture)
	# This paint DEFINES what stays on the canvas until something next queues a redraw, so record whether the
	# channels the idle gate watches put anything on it — see _painted. Taken from "the channel had a member",
	# not "a glyph actually landed": a marker can be skipped below for being off-box while its owner is still
	# live and moving, and an unnecessary clearing repaint costs one free frame where a missed one strands a
	# dot on the map forever.
	var pois := get_tree().get_nodes_in_group(Groups.MINIMAP)
	_painted = not pois.is_empty()
	# POI markers PIN to the rim when off-box: a quest objective's whole job is to point you at something you
	# cannot see yet.
	for n in pois:
		_paint_one_marker(n, view, skin, art, true, marker_color(n))
	if dot_stations and Settings.minimap_show_stations:
		for n in get_tree().get_nodes_in_group(Groups.MINIMAP_STATION):
			_paint_station(n, view, skin)
	if not (dot_npcs and Settings.minimap_show_npcs):
		return
	# Resolved ONCE for the whole body loop, not per body, and only AFTER the early-out above. The alert ring
	# needs the human player, and Groups.human_player is a full PLAYER-group scan — asking it per NPC per frame
	# turned an O(bodies) paint into O(bodies x party) on a widget that already repaints every frame in any
	# populated level.
	var who := Groups.human_player(get_tree())
	var bodies := get_tree().get_nodes_in_group(Groups.NPC)
	_painted = _painted or not bodies.is_empty()
	for n in bodies:
		# An NPC that also carries a WorldMarker is already drawn above; skip it rather than double-painting
		# a dot at half the intended alpha. (A station on the SAME body is deliberately NOT skipped — that is
		# two different facts about one node, and suppressing the dot was the bug that made a vendor's
		# allegiance invisible.)
		if n.is_in_group(Groups.MINIMAP):
			continue
		if not _npc_is_live(n):
			continue
		# NPC dots deliberately do NOT pin to the rim. A pinned dot would report every body on the level
		# against the box edge — that is a radar, not a floorplan, and it would quietly hand the player
		# through-wall knowledge of the whole map. Clipped to the box, a dot means "actually near you".
		_paint_npc_dot(n, view, skin, who)


## A POI beacon (a WorldMarker, or one QuestMarkerSync spawned for a live objective). UNCHANGED behaviour: an
## authored MapData texture if there is one, else a plain filled dot at skin.minimap_poi_glyph_px. This channel keeps the
## flat-dot look on purpose — a quest beacon already carries its own authored `color`, and giving it a shape
## from the station alphabet would say something about its KIND that a WorldMarker has no field to mean.
func _paint_one_marker(n: Node, view: Transform2D, skin, art: Texture2D,
		pin_offscreen: bool, col: Color) -> void:
	if not is_instance_valid(n):
		return
	var n3 := n as Node3D
	if n3 == null:
		return
	var w := n3.global_position
	var q := _marker_point(w, view, skin, pin_offscreen, skin.minimap_poi_glyph_px)
	if q == Vector2.INF:
		return
	col.a *= _marker_fade(w, skin)
	if art != null:
		# Stretched into the SAME square the drawn dot occupied (2x skin.minimap_poi_glyph_px), not blitted at its native
		# size: a delivered PNG must not be able to set its own footprint on a 108 px box. See MinimapArt.
		draw_texture_rect(art, MINIMAP_ART.glyph_rect(q, skin.minimap_poi_glyph_px), false, col)
	else:
		draw_circle(q, skin.minimap_poi_glyph_px, col)
	_paint_floor_tick(q, w, skin, skin.minimap_poi_glyph_px, col)


## A STATION GLYPH: the kind's shape, STROKED rather than filled, at the station's own radius. Stroked-and-larger
## is what separates the station family from the body family, which share shapes — a hollow triangle is a
## campfire, a solid one is a man with a gun.
##
## The node in the group is the StationMarker itself (it joins itself, so its own transform is the pin — a
## designer can nudge it off the counter and onto the doorway without moving the station's hitbox).
func _paint_station(n: Node, view: Transform2D, skin) -> void:
	if not is_instance_valid(n):
		return
	var m := n as StationMarker
	if m == null:
		return
	var w := m.global_position
	var r: float = skin.minimap_station_glyph_px
	var q := _marker_point(w, view, skin, m.pin_offscreen, r)
	if q == Vector2.INF:
		return
	var col := m.resolved_color(MenuStyle.hud.minimap_station_color, MenuStyle.hud.minimap_exit_color)
	col.a *= _marker_fade(w, skin)
	# The glyph does NOT rotate with the map: a shop is a shop from every bearing, and a spinning chevron would
	# read as a heading it does not have. (Contrast the player caret, which is all heading.) That holds for the
	# art slot too — it is drawn axis-aligned into the glyph's own square.
	var art := MINIMAP_ART.station_texture(MenuStyle.hud, m.kind) as Texture2D
	if art != null:
		# NOTE an art slot bypasses glyph_angle's TRAIN inversion: an authored trainer badge is already
		# unmistakable against the hostile caret, which is the only thing that flip existed to guarantee.
		draw_texture_rect(art, MINIMAP_ART.glyph_rect(q, r), false, col)
	else:
		_stroke_glyph(MapGlyph.shape_points(StationMarker.glyph_shape(m.kind), r,
				StationMarker.glyph_angle(m.kind)), q, col, skin)
	_paint_floor_tick(q, w, skin, r, col)


## A BODY: the allegiance shape in the allegiance colour, plus an alert ring when a hostile has noticed you.
## Filled (except a neutral, which is a hollow ring) and smaller than a station glyph — see _paint_station.
func _paint_npc_dot(n: Node, view: Transform2D, skin, who: Node) -> void:
	if not is_instance_valid(n):
		return
	var n3 := n as Node3D
	if n3 == null:
		return
	var w := n3.global_position
	var r: float = skin.minimap_npc_glyph_px
	# pin_offscreen = false: the radar rule. Off the box means not drawn at all, not drawn on the edge.
	var q := _marker_point(w, view, skin, false, r)
	if q == Vector2.INF:
		return
	var ally := _npc_is_ally(n)
	var disp := _npc_disposition(n)
	var col := npc_dot_color(n)
	var fade := _marker_fade(w, skin)
	col.a *= fade
	var pts := MapGlyph.shape_points(
			MapGlyph.npc_shape(ally, disp, Disposition.Kind.HOSTILE, Disposition.Kind.FRIENDLY), r)
	if MapGlyph.npc_is_hollow(ally, disp, Disposition.Kind.HOSTILE, Disposition.Kind.FRIENDLY):
		_stroke_glyph(pts, q, col, skin)
	else:
		draw_colored_polygon(MapGlyph.offset(pts, q), col)
	_paint_alert_ring(n, who, q, skin, r, fade)
	_paint_floor_tick(q, w, skin, r, col)


## THE ALERT RING: a hostile who has noticed you grows an amber halo, one radius step per suspicion tier. Drawn
## OUTSIDE the caret so the disposition channel underneath is untouched — recolouring or resizing the dot itself
## would fight the shape/hue vocabulary the rest of this file establishes.
##
## Read from NPC.suspicion_of(player), which is TARGET-GATED: it reports awareness of the PLAYER only, so a guard
## trading fire with a stray dog does not ring. That gate is the whole reason this is honest rather than a
## "someone somewhere is fighting" light.
##
## STEALTH LINE. This reveals nothing the player cannot already learn — the detection meter and the [HIDDEN]
## badge both report the same worst-case awareness, and the ring rides a dot that is already clipped to the box
## and never pinned. What it adds is WHICH body noticed, which is the difference between "run" and "deal with
## that one guard".
func _paint_alert_ring(n: Node, who: Node, at: Vector2, skin, glyph_px: float,
		fade: float) -> void:
	var ring := MapGlyph.alert_ring_px(alert_tier(n, who), glyph_px,
			skin.minimap_alert_ring_gap_px, skin.minimap_alert_ring_step_px)
	if ring <= 0.0:
		return
	var col: Color = MenuStyle.hud.minimap_alert_color
	col.a *= fade
	_stroke_glyph(MapGlyph.shape_points(MapGlyph.Shape.CIRCLE, ring), at, col, skin)


## The alert tier drawn around a body: 0 for anything that is not a non-ally HOSTILE, else its
## Perception.SuspicionTier toward `who`.
##
## THE HOSTILE GATE IS THE POINT. suspicion_of() answers for any NPC with a Perception, so without this a
## shopkeeper glancing at you, or a companion tracking you as its follow target, would wear the same amber
## threat halo as a guard drawing a bead — the ring would stop meaning "danger" and start meaning "someone
## looked at you", which is worse than no ring at all.
##
## Public and instance-shaped so a test can pin the gate off-tree without a Perception, a tree or a player.
func alert_tier(npc: Node, who: Node) -> int:
	if who == null or npc == null or not npc.has_method(&"suspicion_of"):
		return 0
	if _npc_is_ally(npc) or _npc_disposition(npc) != Disposition.Kind.HOSTILE:
		return 0
	return int(npc.call(&"suspicion_of", who))


## The little up/down tick beside a marker on a DIFFERENT storey. The alpha fade alone was honest but mute — it
## said "not here" without saying "up" or "down", so a beacon overhead and a beacon far away looked identical.
## Drawn in the marker's own colour at its own alpha, so it fades with what it annotates.
func _paint_floor_tick(at: Vector2, w: Vector3, skin, radius: float, col: Color) -> void:
	var len_px: float = skin.minimap_floor_tick_px
	if len_px <= 0.0:
		return
	var dir := MapGlyph.floor_tick(w.y - _ground_y, GameSettings.hud.minimap_band_height)
	if dir == 0:
		return
	# Screen +Y is DOWN, so an ABOVE marker (dir +1) draws its tick toward -Y.
	var base := at + Vector2(0.0, -float(dir) * (radius + 1.0))
	draw_line(base, base + Vector2(0.0, -float(dir) * len_px), col,
			FloorplanSection.stroke_width(skin.minimap_glyph_stroke_px, 1.0))


## Stroke a glyph outline. One place so "hollow glyph" is one concept: close the ring (draw_polyline strokes an
## OPEN path and would leave a visible notch), offset it to the marker point, and take the width through
## FloorplanSection.stroke_width with ppm 1.0 — markers are already in pixels, so this is purely the
## "<= 0 means Godot's transform-independent hairline" rule the wall strokes use.
func _stroke_glyph(points: PackedVector2Array, at: Vector2, col: Color, skin) -> void:
	if points.is_empty():
		return
	draw_polyline(MapGlyph.offset(MapGlyph.closed(points), at), col,
			FloorplanSection.stroke_width(skin.minimap_glyph_stroke_px, 1.0))


## Where a world point lands on the box, or Vector2.INF for "do not draw". The ONE place the distance cull, the
## off-box test and the rim pin live, shared by all three channels so they can never disagree about whether a
## marker is on screen.
##
## `pad` is the glyph's own radius: the rim inset has to clear the glyph or clip_contents (set in _ready, so a
## pinned marker cannot escape onto the quest tracker) would slice it in half. maxf keeps the shipped POI
## behaviour byte-identical — skin.minimap_poi_glyph_px 4.0 against an edge margin of 5.0 still resolves to 5.0.
func _marker_point(w: Vector3, view: Transform2D, skin, pin_offscreen: bool, pad: float) -> Vector2:
	if max_marker_distance > 0.0 and Vector2(w.x, w.z).distance_to(_centre_xz) > max_marker_distance:
		return Vector2.INF
	var q: Vector2 = view * Vector2(w.x, w.z)
	if Rect2(Vector2.ZERO, size).has_point(q):
		return q
	if not pin_offscreen:
		return Vector2.INF  # off the box and not worth pointing at — see the radar note at the call site
	# Off the box: pin it to the rim pointing the right way, through the compass's own pure edge projection
	# rather than a second implementation of the same maths.
	return Compass.project_to_edge(q - size * 0.5, size,
			maxf(skin.minimap_marker_edge_margin, pad + 1.0))


## Vertical honesty: a beacon two storeys up fades instead of pretending to be in this room. Returns the alpha
## MULTIPLIER so each channel can apply it to its own colour.
func _marker_fade(w: Vector3, skin) -> float:
	return FloorplanSection.marker_alpha(w.y - _ground_y, GameSettings.hud.minimap_band_height,
			skin.minimap_marker_floor_alpha)


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
## The `neutral` argument is now MenuStyle.hud.minimap_neutral_color, NOT minimap_npc_color. That old fallback
## is a salmon RED: at a ~4 px glyph, multiplied down by the off-floor fade, a bystander was indistinguishable
## from CBPalette's hostile red, so the map called every civilian in the level a threat. minimap_npc_color keeps
## its real job as the POI-beacon fallback in marker_color() above.
func npc_dot_color(npc: Node) -> Color:
	var neutral: Color = MenuStyle.hud.minimap_neutral_color
	if not is_instance_valid(npc) or not npc.has_method(&"resolved_disposition"):
		return neutral
	return CBPalette.disposition_color(_npc_is_ally(npc), _npc_disposition(npc), neutral)


## Is this a recruited COMPANION? Duck-typed, and the ONE place the question is asked — the hue (via
## CBPalette.disposition_color) and the SHAPE (via MapGlyph.npc_shape) both read it, so a body can never be
## drawn as an ally diamond in a hostile red.
func _npc_is_ally(npc: Node) -> bool:
	return npc.has_method(&"is_following") and npc.call(&"is_following") == true


## This body's resolved disposition as a Disposition.Kind int, or NEUTRAL for anything that cannot answer.
## Same duck-typing rule as everything else in this widget: has_method first, `== true` never bool(...), and a
## non-NPC degrades rather than crashing — this runs over a whole group every frame.
func _npc_disposition(npc: Node) -> int:
	if not npc.has_method(&"resolved_disposition"):
		return Disposition.Kind.NEUTRAL
	return int(npc.call(&"resolved_disposition"))


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
func _paint_player_caret(skin) -> void:
	var c := size * 0.5
	var col: Color = MenuStyle.hud.minimap_player_color
	var md := active_map_data()
	var art: Texture2D = MINIMAP_ART.pick(md.player_marker if md != null else null,
			MenuStyle.hud.minimap_player_texture)
	# Hoisted above the branch: BOTH arms turn by the same angle now. An authored caret that did not swing with
	# the heading was a bug report on day one — it is the one glyph on this widget that is entirely about
	# bearing — so the art tier adopts the drawn tier's rotation instead of blitting flat at native size.
	var ang := FloorplanSection.arrow_angle(_yaw, Settings.minimap_rotates)
	if art != null:
		_draw_rotated(art, c, ang, Vector2(skin.minimap_caret_px, skin.minimap_caret_px) * 2.0, col)
		return
	var r := Transform2D(ang, Vector2.ZERO)
	draw_colored_polygon(PackedVector2Array([
		c + r.basis_xform(Vector2(0.0, -skin.minimap_caret_px)),
		c + r.basis_xform(Vector2(skin.minimap_caret_px * 0.7, skin.minimap_caret_px * 0.8)),
		c + r.basis_xform(Vector2(-skin.minimap_caret_px * 0.7, skin.minimap_caret_px * 0.8)),
	]), col)


## Draw `tex` centred on `at`, turned by `rot`, stretched to `px`. draw_texture has no rotation argument, so a
## turning glyph has to go through this canvas item's own transform command.
##
## THE RESET IS LOAD-BEARING. draw_set_transform APPENDS a command to this item's draw list — it is not global
## state and it does not end when this function returns. _paint_chrome and _paint_north_tick paint in screen
## space AFTER the caret and would inherit the spin, so the identity reset is not tidiness, it is the fix.
func _draw_rotated(tex: Texture2D, at: Vector2, rot: float, px: Vector2, col: Color) -> void:
	var s := tex.get_size()
	if s.x <= 0.0 or s.y <= 0.0:
		return
	draw_set_transform(at, rot, px / s)
	draw_texture(tex, -s * 0.5, col)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## The box's edge: authored frame art when the skin carries it, else a drawn contrast rim. The north tick rides
## OVER either, because it annotates the plan rather than the frame.
func _paint_chrome(skin) -> void:
	var frame: Texture2D = MenuStyle.hud.minimap_frame_texture
	if frame != null:
		draw_texture_rect(frame, Rect2(Vector2.ZERO, size), false)
	elif skin.minimap_outline_width > 0.0:
		draw_rect(Rect2(Vector2.ZERO, size), MenuStyle.hud.minimap_outline_color, false,
				skin.minimap_outline_width)
	_paint_north_tick(skin)


## THE NORTH TICK: a short spoke on the rim pointing at world north. Only meaningful in HEADING-UP mode, where
## the plan turns under a fixed caret and there is otherwise NO fixed bearing anywhere on the HUD — you can spin
## on the spot and every landmark moves. In north-up mode the plan is already axis-locked, so the tick would be
## a permanent mark at 12 o'clock saying what the whole map already says; it is skipped.
##
## Drawn as a spoke INWARD from the rim rather than a letter: this is a Control with no font override, and a
## glyph at this size would be a smudge (and a character assigned to a .text would owe PlayerText a string —
## a drawn line owes nothing, because it is geometry, not copy).
func _paint_north_tick(skin) -> void:
	var len_px: float = skin.minimap_north_tick_px
	if len_px <= 0.0 or not Settings.minimap_rotates:
		return
	var dir := MapGlyph.north_dir(_yaw, true)
	var centre := size * 0.5
	# Project onto the rim through the same pure edge projection every pinned marker uses, so the tick sits on
	# exactly the ring the markers pin to instead of on a second, slightly different one.
	var rim := Compass.project_to_edge(dir, size, skin.minimap_marker_edge_margin)
	draw_line(rim, rim + (centre - rim).normalized() * len_px, MenuStyle.hud.minimap_north_color,
			FloorplanSection.stroke_width(skin.minimap_glyph_stroke_px, 1.0))


## Drop every cached deck and re-slice on the next frame. Called automatically on a level swap; exposed
## for a designer/debug hook and for a future "the level geometry changed" caller.
func rebake() -> void:
	_decks.clear()
	_deck_lru.clear()
	_deck = {}
	_band_keyed = false   # nothing drawn -> the next band choice takes the raw answer, not a stale sticky one
	_source = null   # the solids are in the OLD level's world space — re-gather, never re-cut
	_resolve_level_underlay()   # the level changed (or might have): re-stamp its authored underlay, even to null
	_deck_dirty = true


## The underlay actually drawn: this widget's own authored export when set (a per-instance override), else
## the ACTIVE level's LevelData.map_data (stamped by _resolve_level_underlay on every rebake). Null means
## the procedural plan is the whole picture. Instance method so tests can pin the precedence off-tree.
func active_map_data() -> MapData:
	return map_data if map_data != null else _level_map_data


## THE CONSUMPTION SEAM for authored maps: read the active level's LevelData.map_data off the GameRoot
## (Groups.GAME_ROOT — the LevelDoor lookup idiom) and stamp it, POSSIBLY WITH NULL — a level without an
## authored map must CLEAR the previous level's art, or a swap would keep drawing the old image in the new
## level's world space. Rides rebake(), so the same region-instance-id staleness check that drops the deck
## cache re-resolves the underlay too, and neither game_root.gd nor ui.gd needs any wiring for it. The
## `.get()` read is the house rule for duck-typed host property reads; no tree, no GameRoot, or a
## non-LevelData `level` all degrade to "no underlay". (Edge: a SWAP between two region-less levels never
## trips the staleness check, so the second keeps the first's underlay — the boot half of that gap is
## closed by _source_region_id's -1 seed, and every shipped level carries a region; the LevelRoot
## validator flags a missing one, though only on LevelRoot-rooted scenes.)
func _resolve_level_underlay() -> void:
	if not is_inside_tree():
		_level_map_data = null
		return
	var gr := get_tree().get_first_node_in_group(Groups.GAME_ROOT)
	var ld := (gr.get(&"level") if gr != null else null) as LevelData
	_level_map_data = ld.map_data if ld != null else null


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
