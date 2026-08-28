class_name Minimap
extends Control

## @system Minimap
## @seam AUTHORED SCENE: scenes/ui/hud_minimap.tscn, instantiated by ui.gd into the _weighted carrier (top-right corner, shared with the quest tracker). The SCENE owns the box — anchors, offsets, z_index, texture filter and the two art slots — and ui.gd MEASURES it back through UI.minimap_box() so the clock and the objective tracker reflow when an artist drags it. Geometry comes from the level's baked NavigationMesh via FloorplanSection, paint from MenuStyle.hud.minimap_*, fallback layout from GameSettings.hud.minimap_*, and the player's choices are polled LIVE off Settings.minimap_enabled / _rotates / _zoom so an Options change bites the same frame with no rebuild.
## @seam THE ART SANDWICH — the artist's drop-in surface, and the reason this widget is a scene at all. This script's _draw is ONE layer; the scene wraps it in two empty full-rect slots whose TREE ORDER is the render order: %MapUnder (forced show_behind_parent in _ready, so the slot NAME is the contract rather than a checkbox an artist must remember) renders wholly BEHIND the plan — a backdrop supplied there wants the ALPHA of MenuStyle.hud.minimap_backing_color zeroed so it shows through, the alpha-as-null sentinel this project already uses for StationMarker.color — and %MapOver renders wholly IN FRONT of plan, markers, caret and rim, which is where a bezel/frame/glass/vignette belongs (a NinePatchRect there beats minimap_frame_texture's plain stretch). THREE LIMITS: art cannot be inserted BETWEEN the plan and the marker channels (they are one _draw), everything is clipped to the box by clip_contents below, and art children need NO repaint wiring at all — each is its own CanvasItem, so nothing an artist adds can touch _needs_repaint / _painted / the drawn stamps. ⚠ The live READ is only half of that: a Control repaints solely on queue_redraw, so it also takes the drawn-options stamps below to notice the row moved — without them the live read is a lie for any player who is standing still (see the queue_redraw @risk).
## @seam TWO HOSTS, ONE WIDGET. Besides the HUD corner box this script is also the body of the MAP TAB (scripts/ui/map_screen.gd + scenes/ui/map_screen.tscn — the sixth Pip-Boy tab, default M), which authors a second instance filling a menu panel. The map tab differs ONLY in the "Instance view" exports (a wider world_span_override, its own zoom_override driven by Settings.map_zoom, heading = NORTH_UP, zoom_key_enabled off, labels on, a live view_offset it pans with, waypoint_pin_offscreen on) — every layer, marker channel, deck cache and idle-gate term is shared code. So a paint site that reads Settings.minimap_zoom / _rotates / GameSettings.hud.minimap_world_span DIRECTLY is a bug: it makes the map tab silently draw the HUD box's view. Go through effective_zoom() / effective_rotates() / effective_world_span(), and stamp what you drew (_drawn_zoom / _drawn_span / _drawn_rotates / _drawn_view_offset) or the idle gate strands the stale picture.
## @seam The level swap is detected from the Groups.NAVMESH region's INSTANCE ID, not a GameRoot signal — a freed region leaves the group by itself, so the deck cache self-heals across a LevelDoor transition and this widget needs no new wiring in game_root.gd.
## @seam The authored underlay is per-level: LevelData.map_data, PULLED (never pushed) by _resolve_level_underlay inside rebake() — the same region-instance-id hook — via Groups.GAME_ROOT's `level`. The widget's own map_data export is a per-instance override that wins when set, and a level without an authored map CLEARS the previous level's art (the stamp writes null too).
## @risk Renders ONLY the player's own floor band, so a mezzanine or catwalk above the cut is invisible and a staircase reads as a gap between two decks.
## @risk An unbaked level has no walkable fill and a level with no static colliders has no walls; either degrades to a partial map in silence, because both are legitimate states. Minimap.deck_count() is the introspection seam when a level looks blank.
## @seam FOUR marker channels, painted in this order and each with its own rules: Groups.MINIMAP (POI beacons — a plain dot, PINS to the rim), Groups.MINIMAP_STATION (station glyphs — stroked shapes, pin per StationMarker.pin_offscreen), the PLAYER'S OWN WAYPOINTS (filled AND stroked, larger still, labelled on the map tab, pinned per RECORD — the TRACKED pin always, the rest only where the host set waypoint_pin_offscreen; see _paint_waypoints), Groups.NPC (bodies — filled shapes by allegiance, NEVER pinned, and drawn ONLY inside an installed SCANNER IMPLANT's radius: no chip, no bodies at all — see _sample_scan_range). A node in two channels is drawn by both on purpose: a shop riding a dialogue NPC is both a place to trade and a body with an allegiance.
## @seam THE WAYPOINT CHANNEL IS DATA, NOT NODES. It reads GameState.waypoints_for(current_level_path) — records authored by the player through the Map tab or the Mark Waypoint key, shaped and clamped by scripts/world/waypoint_book.gd, persisted in the profile's [waypoints] section. Nothing is spawned into the world for a pin, so there is no lifecycle to get wrong across a level swap or a load; the screen-edge compass reads the same ledger directly rather than a group. Its idle-gate trailing edge is the GameState.waypoints_rev / selected_waypoint stamp pair (_waypoints_changed), NOT a signal — this widget exists as a bare off-tree .new() in ~39 test sites and must never own a connection.
## @seam SHAPE is the primary marker channel and HUE the secondary one (MapGlyph): hostile caret / ally diamond / friendly dot / neutral ring, and seven stroked station shapes. At a ~4 px radius hue alone could not carry the distinction, and Settings.colorblind_safe_cues exists because it is contested even at size.
## @risk A hostile's alert ring reads NPC.suspicion_of(player), which is target-gated — it only ever reports awareness OF THE PLAYER, never of another NPC. Widening it to is_in_combat() (target-agnostic) would ring every guard fighting a stray dog and read as "they are onto you".
## @risk A CanvasItem repaints ONLY on queue_redraw(), and the idle gate deliberately withholds that from a standing, still player — so every fact this picture shows owes the gate a way to ask for the ONE repaint that takes it back OFF the canvas when it stops being true. _needs_repaint is that gate, and three of its terms exist purely as those trailing edges (_painted for the marker channels, the drawn-options stamps for the player's Options rows, the drawn-skin stamp for the ARTIST's hud_skin.tres). A new painted channel added without one strands its art on the map forever.
## @risk Never draw a sight CONE here. Perception.can_see() raycasts, and _draw/_process run OFF the physics frame where direct_space_state returns EMPTY silently — a cone would look right in tests and report "sees nothing" in play. The authored sight_range/fov_degrees would draw a cone that is also a wallhack.
## @test res://tests/test_minimap.gd
##
## The HUD minimap: a procedural VECTOR FLOORPLAN of the floor the player is standing on, drawn straight
## into a Control with no authored texture, no per-level MapData and no second 3D pass.
##
## WHY NOT A RENDERED IMAGE. The box is ~108 px on the LOGICAL 792x444 canvas — in RETRO presentation that
## canvas is the render target, nearest-upscaled ~2.4x to the window; in HIGH FIDELITY the same canvas item
## rasterises at NATIVE resolution, which only makes the case stronger (vector strokes get crisper while a
## downscaled 3D render of grey brushwork stays mush in a ~108 px box). A canvas item is also structurally
## immune to ps1.gdshader's vertex snap — that is a SPATIAL shader and cannot reach 2D drawing — so the
## plan never warps with the world.
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

## Which way is up, per widget — see the `heading` export in the "Instance view" group. FOLLOW_SETTING keeps
## the historical behaviour (the player's Options row); the other two are the per-instance forces the map tab
## needs. Declared before the export blocks so the inspector dropdown resolves it.
enum Heading { FOLLOW_SETTING, NORTH_UP, HEADING_UP }

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
## Dot every LIVING Groups.NPC body WITHIN SCANNER RANGE, tinted by allegiance (hostile / friendly / recruited
## companion) through CBPalette, so the colours match the hover name, the dialogue speaker name and the enemy
## health bar. The designer switch; the player's own is Options -> Accessibility -> "NPCs On Minimap".
##
## ⭐THREE OWNERS, NOT TWO, and the third is the gameplay one: the player must have a SCANNER IMPLANT installed
## and switched on (BioScanner 22 m / DeepScanner 55 m — Player.body_scan_range). Without a chip this channel
## draws NOTHING, at any zoom, on either host. That is the whole point: the Map tab shows 120 m of world,
## zooms to 240 and pans 400, so an ungated body channel was a free through-wall census of the level — you
## could read every patrol in the building from a locked room. The other three channels are unaffected; they
## draw places you were told about, shops you can see, pins you placed and noise you made yourself.
## Unlike a POI marker an NPC dot is never pinned to the rim — see _paint_one_marker.
@export var dot_npcs: bool = true
## Glyph every Groups.MINIMAP_STATION member (a station carrying a StationMarker) with its kind's SHAPE. The
## designer switch; the player's own is Options -> Accessibility -> "Stations On Minimap", and BOTH must be on —
## the dot_npcs / Settings.minimap_show_npcs two-owner idiom, verbatim.
@export var dot_stations: bool = true
## Glyph every waypoint the PLAYER placed on this level (GameState.waypoints_for — see
## scripts/world/waypoint_book.gd for the record). The fourth marker channel, and the only one whose content
## the player authored: they picked its place, its name, its icon and its colour.
##
## ⭐NO Settings ROW, deliberately, and it is the one member of the marker family without one. The other three
## channels draw things the WORLD put there — bodies, shops, your own noise — so a player who finds them
## cluttered needs a switch. A waypoint is on the map because that player put it there, and the switch for
## "I don't want this pin" is deleting it. A row that hides the pins you placed would mostly serve to make
## them look broken. Per-INSTANCE tuning (the HUD box vs the Map tab) is this export, authored on each widget.
@export var dot_waypoints: bool = true

@export_group("Noise")
## Ring the player caret at the radius their own footsteps and gunfire currently carry — Player.noise_radius,
## the very scalar enemy Perception.can_hear() tests against, drawn in TRUE WORLD METRES so an NPC dot inside
## the ring is an NPC that can hear you. The designer switch; the player's own is Options -> Accessibility ->
## "Noise On Minimap", and BOTH must be on — the dot_npcs / Settings.minimap_show_npcs two-owner idiom.
##
## ⭐This channel draws sound YOU MADE and never sound made AT you. It is a mirror of your own state, not a
## sensor: it cannot reveal a body that minimap_show_npcs was not already drawing, which is what keeps it
## clear of the wallhack line the sight-cone @risk above draws. A Groups.NOISE scan — NPC gunfire and death
## pulses — would cross it, and is deliberately not done here.
##
## ⭐IT REPORTS THE SCALAR, NOT WHETHER ANYONE IS LISTENING. NoiseEmitter writes noise_radius with no gate at
## all, while the LISTENER side is gated on GameSettings.npc_ai.hearing_initiates — which ships true in the
## .tres but false in the .gd default. In a build with that flag off the ring keeps saying "you are loud" while
## literally nothing in the world can hear you. It is also an unoccluded WORST CASE rather than a promise:
## hearing is attenuated per listener through walls (hearing_wall_attenuation / hearing_occlusion) and only
## hostile NPCs act on it, so a body inside the ring MAY have heard you — which is the right way round for a
## stealth readout to be wrong.
##
## Worth knowing on the MAP TAB: at that instance's district-scale world_span_override a 28 m ring is a
## sub-pixel dot, so the channel is effectively invisible there. That is honest (it IS that small at that
## scale); if it ever reads as broken, switch this export off on that instance rather than scaling the ink.
@export var ring_noise: bool = true
## DEV LAYER, ships OFF. Adds the whole Groups.NOISE channel — every live NoiseSource, not just the player's:
## NPC gunfire and death pulses, thrown decoys. Rings in the same tint at half alpha, each with its radius in
## metres, plus a header line counting live sources. A diagnostic for tuning the stealth channel, NOT a player
## feature — it is exactly the through-wall knowledge ring_noise above is careful not to grant, so leave it off
## outside a debugging session. Text is drawn with the engine fallback font and owes PlayerText nothing (dev
## surface, never localised); it deliberately overflows the 108 px HUD box and is meant to be read on the map tab.
@export var debug_noise: bool = false

## The wall layer's geometry source, gathered ONCE per level. Preloaded BY PATH and kept untyped so this
## file parses before the editor registers the new class_name (the STAMINA_RING_SCRIPT cache guard).
const FLOORPLAN_SOURCE := preload("res://scripts/ui/floorplan_source.gd")

## The marker-art precedence / sizing rules (scripts/ui/minimap_art.gd — statics only). Preloaded BY PATH and
## kept untyped for the same cache reason as the line above: a NEW class_name is not in the editor's global
## cache until it reimports, and a by-name reference here would take this whole file down until it does.
const MINIMAP_ART := preload("res://scripts/ui/minimap_art.gd")

## The waypoint record's rules — the icon-ordinal -> MapGlyph.Shape mapping this widget paints with, and the
## hit-test the Map tab's click goes through. Preloaded BY PATH and untyped for the SAME class-cache reason as
## the two consts above; that file deliberately carries no class_name at all.
const WAYPOINT_BOOK := preload("res://scripts/world/waypoint_book.gd")

@export_group("Instance view")
# THE SECOND SURFACE. This widget started as the HUD corner box and is now also the body of the MAP TAB
# (scripts/ui/map_screen.gd — the sixth Pip-Boy tab, default M), which wants the SAME plan drawn a very
# different way: a much wider span, north-up, a zoom the player drives from that screen rather than the
# Options row, and a view they can DRAG off themselves. Every knob below is a per-INSTANCE override that ships
# INERT (0 / ZERO / FOLLOW_SETTING / true), so the shipped HUD box behaves byte-identically and a bare `.new()`
# (tests/test_minimap.gd pins ~39 sites on one) is untouched. Read them through effective_world_span() /
# effective_zoom() / effective_rotates() — NEVER off Settings directly at a paint site, or the map tab silently
# draws the HUD's view.
## Metres across the box's SHORT axis at zoom 1, overriding GameSettings.hud.minimap_world_span for THIS
## widget. 0 = follow the tuning resource (the HUD case). The map tab sets GameSettings.hud.map_world_span.
@export var world_span_override: float = 0.0
## Zoom multiplier for THIS widget (divides the span above, so >1 shows FEWER metres). 0 = follow the player's
## Options row, Settings.minimap_zoom (the HUD case). The map tab pushes Settings.map_zoom through here, which
## is why _options_changed compares the EFFECTIVE value — a stamp against the raw Settings row would leave the
## map tab's own zoom unable to ask for the repaint it needs.
@export var zoom_override: float = 0.0
## Which way is up. FOLLOW_SETTING = the player's Options row (Settings.minimap_rotates — the HUD case);
## NORTH_UP / HEADING_UP force it for this widget. The map tab forces NORTH_UP: a full-panel map you READ
## wants a fixed bearing, while a corner box you glance at while running wants heading-up.
@export var heading: Heading = Heading.FOLLOW_SETTING
## Poll the "Cycle Minimap Zoom" key (InputManager.action_minimap_zoom) from _process. ON for the HUD box —
## that key IS the HUD map's zoom cycle. OFF for any widget whose host owns its zoom (the map tab, whose
## wheel/buttons write Settings.map_zoom), so one press can never move two maps at once.
@export var zoom_key_enabled: bool = true
## HOW FAR THE VIEW IS DRAGGED OFF THE PLAYER, in WORLD METRES on the XZ plane (+x = world +X, +y = world +Z).
## Inert ZERO on the HUD corner box, which is player-centred and has no gesture that could move it; the MAP TAB
## writes it as the player drags the plan, walks it with the movement keys/stick, or the level swaps (it resets
## to ZERO on open). The clamp on its length is GameSettings.hud.map_pan_range and the key/stick rate is
## map_pan_speed — both the map screen's to apply, because both are that screen's feel rather than this
## widget's geometry.
##
## ⭐IT IS A VIEW TERM, NOT A CENTRE. It is added to _centre_xz INSIDE view_matrix() — the single construction
## site — so the picture, the click-to-world inverse and every marker's screen point all move together and
## cannot fork. Panning therefore moves the PLAYER CARET off the box centre too, which is the honest read: the
## caret says where you are, not where the window is (see _paint_player_caret, which projects it like any
## other marker rather than assuming the centre).
##
## Like every other painted fact it owes the idle gate a trailing edge — _drawn_view_offset, compared in
## _options_changed() — or a drag made while the player stands still would move nothing at all.
@export var view_offset: Vector2 = Vector2.ZERO
## Rim-pin waypoints that are OFF the box instead of dropping them. FALSE for the HUD corner box, and that
## default is a bug fix rather than a preference: every pin on the level used to pin, and a screenshot harness
## caught six 5.5 px glyph stacks overlapping on a 108 px box, which is a radar made of noise rather than a
## map. TRUE for the MAP TAB (map_screen.gd pushes it from _bind_ui) — that surface is the editor, and a pin
## you cannot see is a pin you cannot select.
##
## ⭐THE TRACKED PIN IGNORES THIS AND ALWAYS PINS (waypoint_pins_offscreen is the one place that decision is
## made, for both the paint and the hit test). One pin per profile is the player's declared destination, and
## an arrow at the rim pointing at it IS the navigation loop this channel exists to close.
@export var waypoint_pin_offscreen: bool = false
## Paint each waypoint's typed NAME beside its glyph. OFF for the HUD corner box — at ~108 px a caption is
## most of the map, and the glyph's shape and colour already carry which pin it is — ON for the Map tab,
## which is a page you READ and where a pin without its name is just a dot. Also gated by the skin's
## minimap_waypoint_label_px (0 = no labels anywhere), so an artist can retire the text without touching
## either host.
@export var waypoint_labels: bool = false
## Index of the waypoint drawn with a SELECTION RING, or -1 for none. Written by the Map tab as the player
## picks pins; nothing selects anything on the HUD box.
##
## ⭐IT IS PART OF THE IDLE GATE. Like every other fact this widget paints, a selection that changes while the
## player stands still asks for the ONE repaint that moves the ring — see _waypoints_changed(), which stamps
## this beside the ledger revision. Setting it without that stamp would strand the ring on the old pin.
@export var selected_waypoint: int = -1

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
## HOW LOUD THE PLAYER IS, in metres, as of this frame's _process sample — 0 when silent or when either owner
## of the channel is off. Sampled in _process (never read fresh in _draw) so the gate below and the ink can
## never disagree about the same frame; see _sample_noise_radius.
var _noise_r: float = 0.0
## ⭐QUANTISER, AND IT IS LOAD-BEARING RATHER THAN COSMETIC. Ground deceleration is an EXPONENTIAL lerp
## (player.gd's `lerpf(velocity.x, ..., 1.0 - pow(1.0 - ground_ratio, fps_factor))`), which asymptotes and
## NEVER reaches exactly 0.0 — so a player who has ever walked keeps a residual ground speed forever, and a
## raw `_drawn_noise_r != _noise_r` compare would mismatch in the last float bits EVERY FRAME and pin the idle
## gate open at full frame rate, in a silent room, with nothing on screen to show for it and every test green.
## Snapping to 0.25 m collapses anything under ~0.104 m/s of residual speed to exactly 0.0. The cost is 0.68 px
## of stepping at the shipped 2.7 px/m — invisible — in exchange for removing that whole class of dead repaint.
const NOISE_STEP_M := 0.25
## HOW FAR THIS PLAYER'S SCANNER IMPLANT READS BODIES, in metres, as of this frame's _process sample — 0 when
## no scanner is installed (or it is switched off, or either half of the body-dot channel is off). Sampled in
## _process like _noise_r and for the same reason: the idle gate below, the paint site and the rim fade all read
## this ONE field, so they cannot disagree about the same frame. See _sample_scan_range.
##
## NO QUANTISER, unlike NOISE_STEP_M above, and the asymmetry is deliberate: this is an AUTHORED CONSTANT read
## off an ability scene (22.0 / 55.0), not a number integrated from an exponential lerp, so it holds still to
## the bit while the implant does and the stamp compare is quiet on its own.
var _scan_r: float = 0.0
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
## …and the SPAN that paint was made from. The fifth member of the same family, added with the per-instance
## view overrides: a host that retunes world_span_override at runtime (or a designer nudging
## GameSettings.hud.map_world_span through the Remote inspector) rescales every metre on the map exactly the
## way the zoom row does, and owes the idle gate the same trailing edge. Seeded NAN for the same reason.
var _drawn_span: float = NAN
## …and WHERE THE VIEW WAS DRAGGED TO. The sixth member, and the one the map tab's pan lives or dies on: the
## player panning the plan is the exact case the idle gate is built to withhold repaints from (nothing on the
## map moved, nobody walked, no Options row changed), so without this stamp a drag would slide the mouse and
## leave the picture exactly where it was. Seeded Vector2.INF — a value no finite offset can equal, so the
## first compare mismatches — rather than ZERO, which is the shipped HUD box's real value.
var _drawn_view_offset: Vector2 = Vector2.INF
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
## THE NOISE RADIUS THIS PAINT WAS MADE FROM — the noise channel's whole contribution to the idle gate, and
## its trailing edge. Seeded 0.0 to match a silent _noise_r, so a boot frame asks for nothing on its account
## (the first paint is already forced by _deck_dirty). Stamped from _noise_r, NEVER from a fresh sample: a
## stamp compared against a differently-sourced value is the bug _options_changed's effective_zoom() note
## records, and it pins the gate open forever.
var _drawn_noise_r: float = 0.0
## THE SCANNER RANGE THIS PAINT WAS MADE FROM — the body channel's own trailing edge, and the one the Implants
## tab lives or dies on. Installing a chip, or flipping a scanner off in that tab, changes what the body channel
## draws while nothing on the map moves and no Settings row changes: the player is standing in a menu. Without
## this stamp the dots you just paid for would not appear (and the ones you just switched off would not leave)
## until you walked. Seeded 0.0 to match a chip-less _scan_r, so a boot frame asks for nothing on its account.
var _drawn_scan_r: float = 0.0
## THE WAYPOINT LEDGER'S REVISION AS THIS PAINT READ IT, and the selection that paint drew — the fourth
## marker channel's whole contribution to the idle gate, and the pair of trailing edges it owes.
##
## Two ints rather than a signal connection, and that is the design: this widget legitimately exists as a bare
## off-tree .new() at ~39 sites in tests/test_minimap.gd, so a GameState.waypoints_changed -> queue_redraw wire
## would need connect/disconnect guards on every one of those (a duplicate connect, or a disconnect on a freed
## listener, is an ENGINE ERROR and GUT 9.6 fails a whole suite on one). A stamp needs no lifecycle at all.
##
## Seeded to values no live state can equal (-1 is not a reachable revision — GameState seeds it 0 and only
## ever increments; -2 is not a reachable selection, since -1 already means "none") so the first compare
## mismatches and the first paint is honest even before _deck_dirty forces one.
var _drawn_waypoint_rev: int = -1
var _drawn_waypoint_sel: int = -2
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
	# Sampled HERE, once, and stamped by _draw from this same field — see _drawn_noise_r.
	_noise_r = _sample_noise_radius(p)
	# ...and the body channel's whole gate, on the same terms and for the same reason — see _sample_scan_range.
	# This is also the ONLY place the player is asked for it: _paint_markers already has `who` resolved, but a
	# paint site that re-asked would be a second question that could drift from the one the idle gate asked.
	_scan_r = _sample_scan_range(p)
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
##
## `debug_noise` PINS THIS GATE OPEN ON PURPOSE, and is the one term here that is not self-clearing. The dev
## layer draws live Groups.NOISE sources that appear, decay and free themselves on their own schedule, so
## nothing this widget stamps could describe them; a developer who switched it on wants a per-frame repaint and
## that is what the switch means. It ships OFF, so a shipped build pays one bool read for it — and it is placed
## before the two functions that do real work so it short-circuits them when it IS on.
func _needs_repaint(moved: bool) -> bool:
	return _deck_dirty or moved or debug_noise or _noise_changed() or _scan_changed() or _waypoints_changed() or _painted \
			or _options_changed() or _skin_changed() or _has_live_markers()


## HOW LOUD THE PLAYER IS RIGHT NOW, in metres — or 0.0 if the noise channel is off for EITHER owner.
##
## Read off the Player rather than scanned out of Groups.NOISE, and that is the design rather than a shortcut:
## `noise_radius` IS the scalar enemy Perception.can_hear() tests against (NoiseEmitter writes it every frame),
## so this ring reports the number the AI acts on and cannot drift from it. The group would only have to be
## filtered back down to the player's own live source anyway — and scanning it would sweep in NPC gunfire and
## death pulses, which is the wallhack this channel is careful not to be (see ring_noise).
##
## ⭐THE TWO-OWNER GATE IS READ HERE AND NOWHERE ELSE. That is what lets _noise_changed() and the paint site ask
## literally the same question instead of two questions that can drift apart — the defect
## tests/test_minimap.gd's "the idle gate asks the same question the paint site does" was written for, after the
## NPC channel's probe read the designer switch but not the player's Options row. It also means switching the
## row off needs no stamp of its own: the sample collapses to 0.0, which trips the compare below, which paints
## one clearing frame and shuts the gate.
##
## Duck-typed .get() so nothing here hard-depends on the Player class (an off-tree stub answers nothing and
## reads as silent). snappedf is NOT tidiness — see NOISE_STEP_M.
func _sample_noise_radius(p: Node) -> float:
	if not (ring_noise and Settings.minimap_show_noise):
		return 0.0
	var v: Variant = p.get(&"noise_radius")
	if not (v is float or v is int):
		return 0.0
	var m := snappedf(maxf(0.0, float(v)), NOISE_STEP_M)
	# ⭐THE DRAWABILITY FLOOR LIVES HERE, NOT AT THE PAINT SITE. A ring no bigger than the caret it surrounds is
	# just a fatter caret, so it is not drawn — and if that decision sat in _paint_noise_ring while the gate
	# compared bare metres, the two would disagree for every radius in the gap and the gate would buy repaints
	# for a ring the paint site then declined to draw. Deciding it once, here, is what keeps the promise the
	# rest of this function's doc makes. Reuses the caret's own size rather than inventing a minimum-radius knob.
	# effective_* (never Settings.minimap_zoom) so the map tab's own view is respected — see the header @seam.
	var ppm := FloorplanSection.px_per_metre(size, effective_world_span(), effective_zoom())
	return m if m * ppm > MenuStyle.hud.minimap_caret_px else 0.0


## THE NOISE CHANNEL'S WHOLE CONTRIBUTION TO THE GATE, and the only ANIMATED thing this widget draws. One field
## compare, so it sits ahead of _options_changed's five and well ahead of the allocating term.
##
## It is both halves at once. While a gunshot's radius is collapsing (28 m -> 0 over ~0.6 s) the sample moves
## every frame, so the gate stays open and the ring animates — without the per-frame unconditional repaint an
## always-true probe would cost. And when the sound stops, the sample reaches exactly 0.0 while the stamp still
## says 6.0: that mismatch buys precisely ONE clearing repaint, which re-stamps to 0.0 and shuts the gate again.
## Same self-clearing shape as the drawn-options stamps, and the reason this channel needs no _painted latch.
##
## ⭐It deliberately does NOT go into _has_live_markers(). That function and _painted are a matched pair — see
## _painted's note — so folding the ring in would drag the latch in with it and put a per-frame
## Groups.human_player scan into the one term documented as allocating.
func _noise_changed() -> bool:
	return _drawn_noise_r != _noise_r


## HOW FAR THE PLAYER'S SCANNER IMPLANT READS OTHER BODIES RIGHT NOW, in metres — or 0.0 if the body channel is
## off for ANY of its three owners (the designer's dot_npcs, the player's Options row, and the implant itself).
## ZERO MEANS NO DOTS AT ALL, which is the shipped state of a fresh game: a scanner chip is what puts other
## people on your map, exactly as the takedown chip is what lets you kill quietly.
##
## Read off the Player rather than off the ability node, and that is design rather than shortcut: this widget
## legitimately exists as a bare off-tree .new() in tests and must not hard-depend on any ability class, so it
## asks the one duck-typed question every other consumer asks (has_method + call, `is float or is int`, exactly
## like _sample_noise_radius). A host that cannot answer reads as NO SCANNER, which fails CLOSED — the safe
## direction for a channel whose whole job is now to withhold information.
##
## ⭐THE THREE-OWNER GATE IS READ HERE AND NOWHERE ELSE, the _sample_noise_radius rule verbatim: _scan_changed(),
## _has_live_markers() and _paint_markers' early-out all ask `_scan_r`, so the idle gate and the paint site ask
## literally the same question instead of two questions that can drift apart. It is also why switching the
## Options row off (or an implant off) needs no stamp of its own — the sample collapses to 0.0, and that IS the
## clearing edge. tests/test_minimap.gd's "the idle gate asks the same question the paint site does" is the
## tripwire for the defect this shape exists to prevent.
func _sample_scan_range(p: Node) -> float:
	if not (dot_npcs and Settings.minimap_show_npcs):
		return 0.0
	if not p.has_method(&"body_scan_range"):
		return 0.0
	var v: Variant = p.call(&"body_scan_range")
	if not (v is float or v is int):
		return 0.0
	return maxf(0.0, float(v))


## THE BODY CHANNEL'S TRAILING EDGE. One field compare, no allocation, so it sits beside _noise_changed() well
## ahead of the group scan.
##
## Unlike the noise ring this is QUIET almost all of the time — the range is an authored constant while an
## implant is installed, so the compare agrees every frame of normal play and buys no repaints at all. It moves
## on exactly the events that have nothing else to ask for a repaint: a chip installed at a ChipInstaller, a
## scanner toggled in the Implants tab, a save loaded, a New Game. Every one of those happens while the player
## is standing still in a menu, which is precisely the state the idle gate withholds repaints in — so without
## this the dots you just paid for would not appear until you walked.
func _scan_changed() -> bool:
	return _drawn_scan_r != _scan_r


## HAS THE PLAYER'S OWN MAP CHANGED SINCE THE LAST PAINT? Two int compares, no allocation, no tree access —
## cheap enough to sit beside _noise_changed() ahead of the allocating group scan.
##
## It covers more than "a pin was added": GameState bumps waypoints_rev on every add, edit, delete, per-level
## clear, disk load and New Game reset, AND on a LEVEL CHANGE. That last one is not decoration — the paint
## site reads waypoints_for(GameState.current_level_path), so walking through a LevelDoor swaps the whole list
## without touching any pin. The deck rebake would usually force a repaint on that frame anyway, but it is
## keyed off the NAVMESH region's instance id, and two consecutive levels that BOTH lack a region both read
## 0 — no rebake, and the previous level's pins would sit on the new level's map until something else moved.
##
## The selection half is the map tab's ring, which changes with no ledger mutation at all.
func _waypoints_changed() -> bool:
	return _drawn_waypoint_rev != GameState.waypoints_rev or _drawn_waypoint_sel != selected_waypoint


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


## THE VIEW THIS WIDGET DRAWS, after the per-instance overrides. Every paint site and every stamp goes
## through these three — reading Settings.minimap_* at a paint site is the bug that makes the map tab quietly
## draw the HUD box's view (see the "Instance view" export group).
##
## Zero is the "not overridden" sentinel for both numbers, not a legal value: a zero span or zero zoom is a
## divide-by-nothing that FloorplanSection.px_per_metre already answers with 1.0 px/m, so nothing is lost by
## spending it as the sentinel and the inspector default can stay a plain 0.
func effective_world_span() -> float:
	return world_span_override if world_span_override > 0.0 else GameSettings.hud.minimap_world_span

func effective_zoom() -> float:
	return zoom_override if zoom_override > 0.0 else Settings.minimap_zoom

func effective_rotates() -> bool:
	match heading:
		Heading.NORTH_UP:
			return false
		Heading.HEADING_UP:
			return true
	return Settings.minimap_rotates


## HOW MANY PIXELS ONE WORLD METRE IS, under this widget's own view. Split out of _draw so the paint and the
## Map tab's click can never be computed two different ways — the header @seam's whole warning applied to a
## second reader.
func pixels_per_metre() -> float:
	return FloorplanSection.px_per_metre(size, effective_world_span(), effective_zoom())


## THE ONE PLACE THE VIEW MATRIX IS BUILT. _draw paints through it; point_to_world() inverts it so a click on
## the Map tab lands on the metre the player pointed at. Two constructions of "the same" matrix is exactly the
## bug class this file keeps documenting: the picture and the interaction would drift by whatever the second
## copy forgot (a zoom override, a heading force, a pan), and nothing would look wrong until a player used it.
##
## ⭐THE PAN IS APPLIED HERE AND NOWHERE ELSE. `_centre_xz + view_offset` is the effective centre, so the whole
## world — the underlay, the fill, the walls, all four marker channels, the caret and the click inverse — moves
## as one. Adding the offset at a paint site instead would give the picture one centre and the hit test another,
## which is the defect the waypoint hit test already shipped once (see waypoint_at_point).
func view_matrix() -> Transform2D:
	return FloorplanSection.view_transform(_centre_xz + view_offset, _yaw, pixels_per_metre(), size,
			effective_rotates())


## A point in this widget's LOCAL pixel space -> the world position it names. The map is a floorplan, so only
## X and Z come out of the projection; the height is the FLOOR THE PLAYER IS STANDING ON (_ground_y, the same
## reference every vertical decision here keys off), which is what makes a pin placed by clicking the plan sit
## on the storey being drawn rather than at world zero.
##
## ⭐Before the first grounded sample _ground_y is 0.0 and meaningless, so the active deck's own floor is used
## instead — a map with a deck is a map that has sliced a band, and that band's lower edge is the honest answer
## when nothing better exists.
func point_to_world(local: Vector2) -> Vector3:
	var xz := view_matrix().affine_inverse() * local
	return Vector3(xz.x, _ground_y if _ground_primed else active_band_floor(), xz.y)


## The index of the waypoint whose glyph is under `local`, or -1. The Map tab's hit-test, and the reason
## clicking an existing pin selects it instead of dropping a second pin on top of it.
##
## ⭐IT TESTS IN SCREEN SPACE, against the SAME `_marker_point` positions `_paint_waypoints` actually inked —
## never against the pins' world positions. The first version did the latter (invert the click, nearest pin
## in world XZ) and it was wrong in exactly the way the view_matrix() doc warns about two projections: a
## rim-PINNED glyph is drawn at a screen point that corresponds to no world point at all, so the glyph you
## could see was a glyph you could not click, and the miss fell through to "place a NEW pin" right under it.
## Sharing the projection (and the same `pad`) is what makes hit and paint unable to disagree.
##
## The tolerance is the glyph's drawn radius plus a little, in real pixels — a constant on-screen target at
## every zoom, which is what the player is actually aiming at. A pin the paint skipped (Vector2.INF — the
## distance cull, or an off-box pin this host does not pin) is skipped here too: what is not drawn is not
## clickable.
##
## ⭐EVERY PER-RECORD DECISION GOES THROUGH THE SAME TWO FUNCTIONS THE PAINT CALLS — waypoint_pins_offscreen()
## and _waypoint_pad(). This loop used to hardcode `true` and one pad for every pin, which was true of the
## channel at the time; the day the paint learned to pin per record, a copy here would have re-opened the
## visible-but-unclickable bug from the other side (a pin the HUD box declines to draw would still be clickable
## in the corner, and the map tab's tracked pin would be clickable at the wrong rim inset).
func waypoint_at_point(local: Vector2) -> int:
	var view := view_matrix()
	var skin = MenuStyle.hud
	var r: float = skin.minimap_waypoint_glyph_px
	var best := -1
	var best_d: float = r + 3.0
	var list: Array = GameState.waypoints_for(GameState.current_level_path)
	for i in list.size():
		var entry: Variant = list[i]
		if not (entry is Dictionary):
			continue
		var rec := entry as Dictionary
		var pos: Variant = rec.get("pos")
		if not (pos is Vector3):
			continue
		var q := _marker_point(pos as Vector3, view, skin, waypoint_pins_offscreen(rec),
				_waypoint_pad(skin, waypoint_is_tracked(rec)))
		if q == Vector2.INF:
			continue
		var d := local.distance_to(q)
		if d <= best_d:
			best_d = d
			best = i
	return best


## HAS THE VIEW THIS WIDGET DRAWS MOVED SINCE THE LAST PAINT? Zoom, span, heading-up/north-up and the pan all
## change the VIEW MATRIX; the two show_* rows add or remove a whole marker channel. Six compares and no
## allocation, so it is cheap enough to ask every frame — and it is what makes the zoom key bite as well, since
## _poll_zoom_key writes through the same Settings setter the Options slider does. NAN's own inequality is what
## makes the seeded first compare mismatch, and Vector2.INF's does the same for the pan.
##
## The name is historical: it started life as the player's OPTIONS rows and now also carries the two terms a
## HOST drives (world_span_override / zoom_override / heading through the effective_* accessors, and
## view_offset directly). What unites them is that all six decide the PICTURE rather than its contents, which
## is why the artist's skin and the marker channels each keep their own probe.
##
## ⭐The three view terms compare the EFFECTIVE values, not the raw Settings rows. A widget with
## zoom_override set (the map tab) would otherwise stamp its own zoom and then compare it against
## Settings.minimap_zoom — a permanent mismatch that pins the idle gate open forever, while a change to the
## override it actually draws from asks for nothing.
func _options_changed() -> bool:
	return _drawn_zoom != effective_zoom() \
			or _drawn_span != effective_world_span() \
			or _drawn_rotates != effective_rotates() \
			or _drawn_view_offset != view_offset \
			or _drawn_show_npcs != Settings.minimap_show_npcs \
			or _drawn_show_stations != Settings.minimap_show_stations


## Is there anything on the map that moves independently of the player? Cheap (two group-size reads) and
## it keeps the idle gate honest — see the note at its call site, _needs_repaint.
##
## The NPC term asks the SAME question the paint site asks, and it now does so by reading the ONE sampled
## field both of them read — `_scan_r`, which already folds in all three owners of the channel (dot_npcs, the
## player's Options row, and the scanner implant). It previously read only the designer half, so a player who
## switched dots off in Options still paid a full repaint every frame for bodies that were never drawn, which
## is exactly the cost the Options row is supposed to remove. The same now holds for the much more common
## case: a player with NO scanner chip pays nothing at all for a level full of bodies.
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
	var bodies := _scan_r > 0.0
	var stations := dot_stations and Settings.minimap_show_stations
	if not (bodies or stations):
		return false
	return not get_tree().get_nodes_in_group(Groups.NPC).is_empty()


## THE ZOOM CYCLE KEY (default K — it moved off M when the Map tab claimed that key). Walks
## GameSettings.hud.minimap_zoom_steps in order and wraps, writing through
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
	# zoom_key_enabled is the FOURTH gate, and the one the map tab needs: that widget's zoom is its host's
	# (Settings.map_zoom, driven by the wheel and the footer buttons), so letting this key also write
	# Settings.minimap_zoom from a second live instance would move two maps on one press.
	if not zoom_key_enabled or steps.is_empty() or InputManager.gameplay_suppressed():
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
	# THE ARTIST'S SURFACE, hoisted once for the whole paint: every colour and every width/size the map inks
	# (MenuStyle.hud, hud_skin.tres). Untyped for the class_name-cache reason MenuStyle.hud itself is.
	# The tuning half (GameSettings.hud) is no longer hoisted here: the world span moved behind
	# effective_world_span() with the per-instance overrides, and the only other knobs this path wants are
	# the deck-slicing numbers, read up in _ensure_deck, and minimap_band_height, read at its own two sites.
	var skin = MenuStyle.hud
	# STAMP THE OPTIONS THIS PAINT IS MADE FROM, before anything reads them below. _process compares the stamp
	# next frame, and that comparison is the only thing asking for a repaint when a player standing still flips
	# an Options row — see _options_changed.
	_drawn_zoom = effective_zoom()
	_drawn_span = effective_world_span()
	_drawn_rotates = effective_rotates()
	_drawn_view_offset = view_offset
	_drawn_show_npcs = Settings.minimap_show_npcs
	_drawn_show_stations = Settings.minimap_show_stations
	_drawn_skin_id = MenuStyle.hud.get_instance_id()
	# THE SAMPLE, not a fresh read — see _drawn_noise_r.
	_drawn_noise_r = _noise_r
	# ...and the scanner's reach this paint drew bodies to, on the same terms — see _drawn_scan_r.
	_drawn_scan_r = _scan_r
	# ...and the player's own map, both halves. Stamped HERE rather than inside _paint_waypoints because that
	# function early-outs on `dot_waypoints` and on an empty ledger: a stamp taken past either of those would
	# never move on a widget with the channel switched off, and _waypoints_changed() would then pin the idle
	# gate open at full frame rate for a channel that draws nothing. The _paint_markers `_painted` clobber note
	# below is the same lesson learned once already.
	_drawn_waypoint_rev = GameState.waypoints_rev
	_drawn_waypoint_sel = selected_waypoint
	# THE BACKING IS AN ALPHA-SENTINEL SLOT. An artist supplying a backdrop in %MapUnder zeroes this colour's
	# alpha in hud_skin.tres so their art shows through — the StationMarker.color idiom. draw_rect at alpha 0
	# costs one no-op command, so there is nothing to branch on.
	draw_rect(Rect2(Vector2.ZERO, size), MenuStyle.hud.minimap_backing_color, true)
	var ppm := pixels_per_metre()
	var view := view_matrix()
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
						FloorplanSection.stroke_width(skin.minimap_wall_glow_width, ppm,
								Settings.native_scale()))
			# ONE call for the whole floorplan. The width goes through stroke_width because draw_multiline's
			# width is in LOCAL units and this matrix scales by ppm — a raw px value would fatten as the
			# player zooms in. Settings.native_scale() rides along, read LIVE each paint (never cached — a
			# mid-session presentation flip must bite the next repaint): the shipped wall width is 0 = the
			# hairline, and in HIGH FIDELITY stroke_width substitutes one LOGICAL px for it so the walls keep
			# their RETRO weight instead of thinning to one NATIVE px (~2.4x thinner at 1080p).
			draw_multiline(walls, skin.minimap_wall_color,
					FloorplanSection.stroke_width(skin.minimap_wall_width, ppm,
							Settings.native_scale()))
	draw_set_transform_matrix(Transform2D.IDENTITY)
	# WHERE THE PLAYER IS ON THE BOX, projected like any other marker rather than assumed to be the centre. With
	# view_offset ZERO — the shipped HUD box — this IS size * 0.5 by construction (view_transform builds
	# `origin = rect * 0.5 - basis_xform(centre)`, so `view * centre` collapses back to rect * 0.5), which is
	# what keeps the corner box byte-identical. On the panned map tab it is the honest answer instead: the caret
	# and the noise ring travel with the world, and can leave the box entirely when the view is dragged away.
	var here := view * _centre_xz
	# OVER the plan but UNDER every marker channel and the caret: it is context for the dots, not a dot. Painted
	# from _draw rather than inside _paint_markers on purpose — that function opens with a plain `_painted = ...`
	# assignment that clobbers earlier writes and closes with an unconditional early return when body dots are
	# off, so anything added at either end of it is silently lost. Here `ppm` is also already a live local.
	_paint_noise_ring(skin, ppm, here)
	if debug_noise:
		_paint_noise_debug(view, skin, ppm)
	_paint_markers(view, skin)
	_paint_player_caret(skin, here)
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
	# THE PLAYER'S OWN PINS, over the world's fixtures and under the bodies. That order is the same priority
	# argument the three channels above already make: a pin is a note about a PLACE, so it sits on top of the
	# shop it annotates, while a body — the most volatile fact on the map — still paints over everything.
	_paint_waypoints(view, skin)
	# THE BODY CHANNEL'S WHOLE GATE, in one compare against the very field the idle gate compares — see
	# _sample_scan_range. 0.0 is "no scanner implant" (the shipped state of a fresh game) as well as "either
	# switch is off", and all three read the same here: no bodies are drawn at all.
	if _scan_r <= 0.0:
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
		#
		# The BOX is no longer the only limit, though, and it never was the honest one: it moves with the zoom
		# slider and it is 120 m wide on the Map tab. _paint_npc_dot's first act is the SCANNER RIM (_scan_fade),
		# a fixed radius in metres that the view cannot widen.
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


## THE FOURTH MARKER CHANNEL: every pin the PLAYER placed on this level, read straight off GameState's
## waypoint ledger with no scene nodes involved.
##
## ⭐WHY NO NODES, when every other channel scans a group. A waypoint has no presence in the world — nothing
## collides with it, nothing looks at it, it casts no light and it is not a thing you can walk up to. Spawning
## a Node3D per pin would buy exactly one thing (the compass's group scan) at the cost of a lifecycle: who
## owns them across a level swap, what re-spawns them after a load, what frees them on New Game. The compass
## reads the same ledger directly instead (hud_compass.gd's tracked-pin pip), which is a handful of lines with no
## lifecycle at all. If a THIRD consumer ever wants them, share the ledger, not a node.
##
## THE FAMILY SEPARATOR IS "BOTH": bodies are FILLED and small, stations are STROKED and larger, and a pin is
## filled AND stroked at a larger radius still. That silhouette belongs to no other alphabet, which is what
## lets a player pick their own mark out of a busy map at a glance — and it is why minimap_waypoint_fill_alpha
## must stay strictly between 0 and 1 (either end collapses this family into one of the other two).
##
## PINNING IS PER RECORD, not per channel, and that is the 2026-08-26 correction. The channel used to pin
## EVERY off-box pin to the rim like the POI beacons do, which is right on a page-sized map and wrong on a
## 108 px corner box: a screenshot harness caught six overlapping 5.5 px glyph stacks crowded onto the rim of
## the HUD map, hiding the plan it was supposed to annotate. So the host decides (waypoint_pin_offscreen —
## FALSE on the HUD box, TRUE on the Map tab), with the TRACKED pin as the standing exception because pointing
## at your declared destination IS the navigation loop. waypoint_pins_offscreen() is the single answer, shared
## with the hit test. Bodies remain the channel that must NEVER pin (that would be a radar); a pin you placed
## yourself leaks nothing you did not already know.
func _paint_waypoints(view: Transform2D, skin) -> void:
	if not dot_waypoints:
		return
	var list: Array = GameState.waypoints_for(GameState.current_level_path)
	if list.is_empty():
		return
	var r: float = skin.minimap_waypoint_glyph_px
	var gap: float = maxf(0.0, skin.minimap_waypoint_selected_gap_px)
	var box := Rect2(Vector2.ZERO, size)
	# Hoisted out of the loop: the label font and its metrics are the same for every pin, and get_theme_*
	# walks the theme chain. Null is a legitimate answer off-tree / before a theme resolves, and it simply
	# means no labels this paint — never an error.
	var label_px: int = int(skin.minimap_waypoint_label_px)
	var font: Font = get_theme_default_font() if (waypoint_labels and label_px > 0) else null
	# TWO PASSES: every glyph first, then every caption. In one pass a later pin's filled polygon stamped
	# straight over an earlier pin's caption whenever two pins sat within a label-length of each other —
	# which at the map tab's district span is any two pins in the same building. Captions still yield to the
	# NPC body channel, which paints after this whole function ON PURPOSE (see the _paint_markers ordering
	# note: a body is the most volatile fact on the map and wins the frame).
	#
	# The queue holds finished RECTS rather than (point, name) pairs, because the second pass has to know
	# where a caption would land before it decides whether to draw it at all — see declutter_labels.
	var label_rects: Array[Rect2] = []
	var label_names: PackedStringArray = []
	var label_sel := -1   # index INTO the queue of the SELECTED pin's caption, or -1 for none
	for i in list.size():
		var entry: Variant = list[i]
		if not (entry is Dictionary):
			continue
		var rec := entry as Dictionary
		var raw_pos: Variant = rec.get("pos")
		if not (raw_pos is Vector3):
			continue
		var w: Vector3 = raw_pos
		var tracked := waypoint_is_tracked(rec)
		# The rim inset covers the RINGS, not just the glyph: _marker_point pads by this so a pinned pin's
		# selection (and tracked) ring is not sliced by clip_contents. The SAME pad feeds waypoint_at_point —
		# the hit test must land on the exact points inked here, or a rim glyph becomes visible-but-unclickable
		# (the bug the first version shipped).
		var pad := _waypoint_pad(skin, tracked)
		var q := _marker_point(w, view, skin, waypoint_pins_offscreen(rec), pad)
		if q == Vector2.INF:
			continue
		var col := waypoint_color(int(rec.get("tint", 0)))
		# One sample for the glyph AND both rings: they annotate the same pin, so a ring at a different alpha
		# from the mark it surrounds would read as two things on two storeys.
		var fade := _marker_fade(w, skin)
		col.a *= fade
		var pts := MapGlyph.shape_points(WAYPOINT_BOOK.icon_shape(int(rec.get("icon", 0))), r)
		if not pts.is_empty():
			var fill := col
			fill.a *= clampf(skin.minimap_waypoint_fill_alpha, 0.0, 1.0)
			# draw_colored_polygon triangulates a simple concave polygon on its own, which is what lets the
			# CROSS icon fill without being decomposed — see MapGlyph._cross_points.
			draw_colored_polygon(MapGlyph.offset(pts, q), fill)
			_stroke_glyph(pts, q, col, skin)
		if i == selected_waypoint:
			# The ring rides the pin's own alpha, so a selected pin on the floor below still fades honestly
			# rather than announcing itself through the floor.
			var sel: Color = skin.minimap_waypoint_selected_color
			sel.a *= fade
			_paint_waypoint_ring(q, r + gap, sel, skin)
		if tracked:
			# ONE GAP FURTHER OUT than the selection ring, so the pin the player is walking to and the pin they
			# happen to have selected on the Map tab are two readable concentric rings rather than one ring
			# painted twice. _waypoint_pad() reserves the rim inset for exactly this radius.
			var trk: Color = skin.minimap_waypoint_tracked_color
			trk.a *= fade
			_paint_waypoint_ring(q, r + gap * 2.0, trk, skin)
		_paint_floor_tick(q, w, skin, r, col)
		# QUEUE the label, and only for a pin genuinely ON the box. A rim-PINNED glyph sits at the edge by
		# construction, so its caption would clip to a stub — and the reason it is pinned is that the place
		# is somewhere else, which the arrow already says better than a half-word does. Re-testing
		# containment here rather than having _marker_point report it keeps that function's single-return
		# contract intact for all four channels.
		if font != null and box.has_point(view * Vector2(w.x, w.z)):
			var nm := String(rec.get("name", ""))
			if not nm.is_empty():
				if i == selected_waypoint:
					label_sel = label_rects.size()
				label_rects.append(_waypoint_label_rect(font, label_px, q, pad, nm))
				label_names.append(nm)
	for i in declutter_labels(label_rects, label_sel):
		_paint_waypoint_label(font, label_px, label_rects[i], label_names[i], skin)


## Is THIS record the profile's tracked pin — the one place the player declared they are walking to?
##
## ⭐IT DELEGATES, and that is the whole point of the function existing here at all. WaypointBook.is_tracked is
## THE definition of what "tracked" reads as (an OPTIONAL key: absent on every pin saved before the feature and
## on every untracked pin since, plus the hand-edited `tracked=1` case a ConfigFile can hand back), and the
## ledger's load fold, GameState and this paint all have to answer it the same way or a pin is tracked in one
## place and not another. This wrapper exists only to give the two call sites below a bool-typed answer off the
## untyped preload — never to hold a second copy of the rule.
static func waypoint_is_tracked(rec: Dictionary) -> bool:
	var on: bool = WAYPOINT_BOOK.is_tracked(rec)
	return on


## DOES THIS RECORD RIM-PIN WHEN IT IS OFF THE BOX? The single answer, taken by the paint (_paint_waypoints)
## and by the hit test (waypoint_at_point) alike.
##
## ⭐IT IS A FUNCTION RATHER THAN TWO `or`s AT TWO SITES FOR A REASON, and the reason is the defect this whole
## channel was rebuilt around: a rim-pinned glyph is drawn at a screen point that corresponds to no world point
## at all, so the instant the two sites disagree about which pins pin, the map grows glyphs you can see and
## cannot click — and the miss falls through to "place a NEW pin", right under the one you were aiming at.
func waypoint_pins_offscreen(rec: Dictionary) -> bool:
	if waypoint_pin_offscreen:
		return true
	return waypoint_is_tracked(rec)


## The rim inset a pin's glyph needs: the glyph itself plus whatever rings it wears. The tracked pin's ring sits
## one gap further out than the selection ring, so it needs one more gap of clearance or clip_contents slices it.
##
## The SELECTED pin is deliberately NOT a term here even though its ring is real: selection is a Map-tab state
## that changes as the player clicks around, and letting it move where a pinned glyph SITS would slide the rim
## pins sideways every time the selection moved. The gap is reserved for every pin instead — three pixels of rim
## inset costs nothing, and it keeps a pin's screen point independent of what happens to be selected.
func _waypoint_pad(skin, tracked: bool) -> float:
	var gap: float = maxf(0.0, skin.minimap_waypoint_selected_gap_px)
	return float(skin.minimap_waypoint_glyph_px) + (gap * 2.0 if tracked else gap)


## One ring around a pin — the selection ring and the tracked ring are the same stroke at two radii in two
## tints, so they share a call rather than two copies of the same draw_arc argument list. 20 segments is the
## authored look; the stroke goes through stroke_width at ppm 1.0 because markers already paint in pixels.
func _paint_waypoint_ring(at: Vector2, radius: float, col: Color, skin) -> void:
	draw_arc(at, radius, 0.0, TAU, 20, col,
			FloorplanSection.stroke_width(skin.minimap_glyph_stroke_px, 1.0, Settings.native_scale()))


## WHICH CAPTIONS SURVIVE, as indices into `rects` IN PAINT ORDER, with `keep` (the selected pin's caption, or
## -1) reserved first and painted LAST so it lands on top of anything that overlaps it.
##
## THE PROBLEM IT SOLVES: zoomed out on the Map tab, four pins in one building put four captions on the same
## dozen pixels and the result is unreadable mush — not four names, not one name, just ink. A greedy pass is the
## cheapest honest answer: walk the queue in order, keep a caption only if its rect misses everything already
## kept, and drop the rest. Nothing MOVES (a label that jumped to dodge a neighbour would jitter as the player
## panned), and nothing is faded (a half-alpha name over a half-alpha name is still mush).
##
## The dropped names are not lost information: the glyph itself still draws, its shape and tint still say which
## pin it is, and zooming in separates the rects and brings the captions straight back. O(n²) over n ≤ 32
## (WaypointBook's per-level cap), and only over captions that already passed the on-box test.
##
## Static and pure so the rule is provable off-tree with no font, no theme and no tree — the _nearest_zoom_step
## convention on this widget.
static func declutter_labels(rects: Array[Rect2], keep: int) -> PackedInt32Array:
	var out := PackedInt32Array()
	var taken: Array[Rect2] = []
	var keeping := keep >= 0 and keep < rects.size()
	if keeping:
		taken.append(rects[keep])
	for i in rects.size():
		if keeping and i == keep:
			continue
		var rect: Rect2 = rects[i]
		var clear := true
		for t in taken:
			if t.intersects(rect):
				clear = false
				break
		if not clear:
			continue
		taken.append(rect)
		out.append(i)
	if keeping:
		out.append(keep)
	return out


## WHERE a pin's caption would land, as a rect in this widget's local pixels — split out of the paint so the
## declutter pass above can test a caption before a single glyph of it is drawn, and so the two can never
## disagree about where the text goes.
##
## Sits to the RIGHT of the glyph, flipping to the LEFT when that would run off the box — the pins that most
## need naming are the ones near an edge, and a caption clipped to two letters names nothing. `radius` is the
## PADDED radius (glyph + rings), so a ringed pin's caption starts clear of its outermost ring.
##
## The rect is the FONT's box, not the glyph's: top = baseline - ascent, height = the face's ascent + descent
## (which is exactly what get_string_size returns in y). Vertically the caption is centred on the glyph by half
## the ascent, not by half the font size — a font's ascent and descent are not symmetric, and the size-based
## version sits visibly low.
func _waypoint_label_rect(font: Font, px: int, at: Vector2, radius: float, text: String) -> Rect2:
	var sz := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, px)
	var gap := radius + 3.0
	var x := at.x + gap
	if x + sz.x > size.x:
		x = at.x - gap - sz.x
	return Rect2(Vector2(x, at.y - font.get_ascent(px) * 0.5), sz)


## One pin's caption, inked into the rect _waypoint_label_rect already measured for it. The placement rules all
## live in that function — this one only turns its rect into a BASELINE (top + ascent) and paints.
func _paint_waypoint_label(font: Font, px: int, rect: Rect2, text: String, skin) -> void:
	if text.is_empty():
		return
	var pos := Vector2(rect.position.x, rect.position.y + font.get_ascent(px))
	# The outline pass first (draw_string_outline paints UNDER a subsequent draw_string at the same position),
	# because this caption crosses both the dark backing and the bright wall strokes and has to stay legible
	# over both. Skipped entirely at size 0 — one branch for the artist who wants flat text.
	var outline: int = int(skin.minimap_waypoint_label_outline_size)
	if outline > 0:
		draw_string_outline(font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, px, outline,
				MenuStyle.hud.label_outline_color)
	draw_string(font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, px,
			skin.minimap_waypoint_label_color)


## A pin's tint from its stored palette INDEX. Wrapped rather than clamped, so a save written against a longer
## palette (or a hand-edited index) still resolves to a real colour instead of silently collapsing every
## out-of-range pin onto the last entry. An EMPTY palette — an artist clearing the array — degrades to the
## single fallback slot rather than to an invisible map.
##
## Instance method (not static) purely so tests can call it off-tree, the marker_color() / npc_dot_color()
## convention on this widget.
func waypoint_color(tint: int) -> Color:
	var palette: PackedColorArray = MenuStyle.hud.minimap_waypoint_palette
	if palette.is_empty():
		return MenuStyle.hud.minimap_waypoint_color
	return palette[posmod(tint, palette.size())]


## A BODY: the allegiance shape in the allegiance colour, plus an alert ring when a hostile has noticed you.
## Filled (except a neutral, which is a hollow ring) and smaller than a station glyph — see _paint_station.
##
## ...and ONLY inside the scanner implant's reach. That check is first, and it is the reason this whole channel
## is not the wallhack the other three are careful not to be: without a chip _paint_markers never calls this at
## all, and with one it reaches a fixed number of metres that no zoom, pan or window size can widen.
func _paint_npc_dot(n: Node, view: Transform2D, skin, who: Node) -> void:
	if not is_instance_valid(n):
		return
	var n3 := n as Node3D
	if n3 == null:
		return
	var w := n3.global_position
	# THE SCANNER RIM, asked BEFORE the projection and before any allegiance lookup, because it is not a
	# drawing decision: a body outside the implant's reach is not a dot this widget declined to draw, it is a
	# body this player has no way to know about. Folded into `fade` below rather than applied to the fill alone,
	# so the alert ring dims with the body it rings instead of outliving it at the rim.
	var reach := _scan_fade(w)
	if reach <= 0.0:
		return
	var r: float = skin.minimap_npc_glyph_px
	# pin_offscreen = false: the radar rule. Off the box means not drawn at all, not drawn on the edge.
	var q := _marker_point(w, view, skin, false, r)
	if q == Vector2.INF:
		return
	var ally := _npc_is_ally(n)
	var disp := _npc_disposition(n)
	var col := npc_dot_color(n)
	var fade := _marker_fade(w, skin) * reach
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
			FloorplanSection.stroke_width(skin.minimap_glyph_stroke_px, 1.0, Settings.native_scale()))


## Stroke a glyph outline. One place so "hollow glyph" is one concept: close the ring (draw_polyline strokes an
## OPEN path and would leave a visible notch), offset it to the marker point, and take the width through
## FloorplanSection.stroke_width with ppm 1.0 — markers are already in pixels, so this is purely the
## "<= 0 means the thinnest crisp stroke" rule the wall strokes use (RETRO: Godot's transform-independent
## hairline; HIGH FIDELITY: one logical px — native_scale() passed live so a skin authoring 0 keeps its weight).
func _stroke_glyph(points: PackedVector2Array, at: Vector2, col: Color, skin) -> void:
	if points.is_empty():
		return
	draw_polyline(MapGlyph.offset(MapGlyph.closed(points), at), col,
			FloorplanSection.stroke_width(skin.minimap_glyph_stroke_px, 1.0, Settings.native_scale()))


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


## HOW STRONGLY A BODY AT `w` READS THROUGH THE SCANNER: 1.0 well inside its radius, ramping to 0.0 across the
## last GameSettings.hud.minimap_scan_fade_m metres of it, and 0.0 beyond. The body channel's whole distance
## rule, and the only one this widget applies in metres rather than in pixels — which is the point, because a
## limit measured in pixels is a limit the zoom slider can widen.
##
## PLANAR X/Z, matching _marker_point's own max_marker_distance cut exactly: this is a floorplan, so there is
## one notion of "how far away is that marker" in the file and this is it. The vertical axis is already carried,
## honestly and separately, by _marker_fade's cross-floor alpha and by the up/down floor tick — a guard on the
## storey above reads as a dimmed dot with a tick, not as a neighbour.
##
## MEASURED FROM `_centre_xz`, the player's own projected point, NOT from the box centre — those are the same
## pixel on the un-panned HUD box and stop being the same the moment the Map tab drags its view away, which is
## precisely when a radius welded to the window would start scanning from wherever you happened to be looking.
## Same rule as the noise ring, and for the same reason.
##
## A ZERO BAND is the documented hard clip (see the knob): the ramp collapses to an inside/outside test rather
## than dividing by zero.
func _scan_fade(w: Vector3) -> float:
	if _scan_r <= 0.0:
		return 0.0
	var d := Vector2(w.x, w.z).distance_to(_centre_xz)
	var band: float = GameSettings.hud.minimap_scan_fade_m
	if band <= 0.0:
		return 1.0 if d <= _scan_r else 0.0
	return clampf((_scan_r - d) / band, 0.0, 1.0)


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


## THE PLAYER'S OWN NOISE FOOTPRINT: one hard-edged circle around the caret at the radius their footsteps and
## gunfire currently carry. The only thing this widget draws in WORLD METRES rather than at a fixed pixel size,
## which is the entire point — a fixed-size glyph would say "you are making noise", while a true-scale ring says
## HOW FAR, on the same scale as the plan, so an NPC dot inside it is an NPC that can hear you.
##
## CENTRED ON THE PLAYER'S PROJECTED POINT (`view * _centre_xz`, handed down from _draw), not on size * 0.5.
## Those are the same pixel on an un-panned widget — the shipped HUD box — and they stop being the same the
## moment the map tab drags its view_offset off the player, which is exactly when a ring welded to the box
## centre would start reporting your footsteps as coming from wherever the window happens to be looking.
## _paint_player_caret takes the same point, so the ring and the caret it surrounds can never separate.
##
## THE ANIMATION IS FREE, AND THAT IS THE DESIGN. NoiseEmitter recomputes noise_radius every physics frame and
## decays a gunshot spike at 45 m/s, so a shot bursts the ring straight past the box edge and sweeps it back
## into the caret over ~0.6 s with NO clock here: no phase, no ring pool, no Time.get_ticks_msec(), no
## process_mode override, nothing to strand when the tree pauses. The radius is a readout of world state that
## already moves, exactly like a health bar — which is what keeps this channel the same shape as every other
## one on this widget and dodges the whole class of animated-channel bugs.
##
## No _marker_fade, no off-storey tick, no band logic: the ring is centred on the player, who is by definition
## standing on the deck being drawn. Applying the marker fade here would be actively WRONG — _ground_y is
## deliberately frozen while airborne, so your own ring would dim at the top of every jump and drop to the
## off-floor alpha the moment you stepped off a ledge, reporting your own footsteps as another storey's.
##
## Overflow is CLIPPED (clip_contents), never clamped to the rim: a 28 m gunshot ring is 76 px against a 54 px
## half-box at the shipped scale, and pinning it to the edge would draw a distance that is not the one the game
## tests. Clipping is honest, and it is what produces the collapsing-shockwave read.
func _paint_noise_ring(skin, ppm: float, at: Vector2) -> void:
	# NOTHING DECIDES DRAWABILITY HERE — _sample_noise_radius already returned 0.0 for anything too small to
	# draw, precisely so this site and the idle gate cannot disagree. A bare `> 0.0` is the whole test.
	var r_px := _noise_r * ppm
	if r_px <= 0.0:
		return
	# THE AUDIBLE AREA, painted first so the rim lands on top of it. This is the part that keeps the channel
	# honest at radii bigger than the box: a 28 m gunshot ring is ~110 px against a 54 px half-box, so its RIM is
	# entirely off-screen and the stroke alone would render the loudest event in the game as a blank map. The
	# disc is what actually carries the fact then — the whole visible floor is inside earshot, so the whole box
	# washes. It is a FLAT fill, never a gradient: NoiseSource.audible is a hard `distance <= radius` threshold,
	# and a falloff would draw a softness the game does not simulate.
	# Alpha 0 = off, the minimap_wall_glow_color sentinel, so an artist can have the outline alone for free.
	var fill: Color = MenuStyle.hud.minimap_noise_fill_color
	if fill.a > 0.0:
		draw_circle(at, r_px, fill)
	# draw_arc, NOT MapGlyph.shape_points(CIRCLE) — that alphabet is 12-sided, sized for a 4 px glyph. The
	# segment FLOOR is deliberately high: at a walk ring's ~11 px a 16-gon has 4.3 px chords, which is exactly
	# the size and construction of a stroked station badge (MapGlyph strokes those as ngons at
	# minimap_station_glyph_px), so an under-segmented ring reads as a large station glyph. Segments are free;
	# facets are not, especially in RETRO where the ~2.4x nearest upscale hardens every one.
	# Width goes through stroke_width at ppm 1.0: this paints AFTER the matrix reset, so it is already in pixels
	# and the call is purely the "<= 0 means the thinnest crisp stroke" presentation rule the glyphs use.
	draw_arc(at, r_px, 0.0, TAU, MapGlyph.ring_segments(r_px), MenuStyle.hud.minimap_noise_color,
			FloorplanSection.stroke_width(skin.minimap_glyph_stroke_px, 1.0, Settings.native_scale()), false)


## THE DEV LAYER (debug_noise), off in every shipped instance. Draws the WHOLE Groups.NOISE channel — the
## player's live source, NPC gunfire and death pulses, thrown decoys — each as a ring at its own world position
## with its radius in metres, over a header counting live sources. This is the diagnostic view of the stealth
## channel: it answers "did that shot actually emit, and how far did it reach" without attaching a debugger.
##
## Deliberately NOT gated on Settings.minimap_show_noise: that row is the player's declutter switch and this is
## a developer's instrument. It IS the through-wall knowledge _paint_noise_ring refuses to grant, which is why
## it ships off and why it is an inspector export rather than an Options row — the NavDebugOverlay convention.
##
## Every source is validated before use: NoiseSource nodes are one-shot and self-free (an NPC's death pulse is
## reparented to a SIBLING so it outlives the NPC), so the group can hand back an instance that died between the
## group read and this loop. `is_instance_valid` first — `is` on a freed instance crashes.
func _paint_noise_debug(view: Transform2D, skin, ppm: float) -> void:
	var font := ThemeDB.fallback_font
	if font == null:
		return
	var col: Color = MenuStyle.hud.minimap_noise_color
	var faint := Color(col.r, col.g, col.b, col.a * 0.5)
	var live := 0
	for n in get_tree().get_nodes_in_group(Groups.NOISE):
		if not is_instance_valid(n):
			continue
		var src := n as Node3D
		if src == null or not src.is_inside_tree():
			continue
		var radius_v: Variant = src.get(&"radius")
		if not (radius_v is float or radius_v is int):
			continue
		var radius_m := float(radius_v)
		if radius_m <= 0.0:
			continue  # a silent source is not audible at all — NoiseSource.audible requires a POSITIVE radius
		live += 1
		var w := src.global_position
		var at: Vector2 = view * Vector2(w.x, w.z)
		draw_arc(at, radius_m * ppm, 0.0, TAU, clampi(int(radius_m * ppm), 16, 64), faint,
				FloorplanSection.stroke_width(skin.minimap_glyph_stroke_px, 1.0, Settings.native_scale()), false)
		# WHO the noise is about, so a decoy (nobody in particular — emitter stays null) is separable from the
		# player's own live source and from an NPC's gunfire. Duck-read: emitter is a runtime identity that may
		# outlive its node, so it is validated rather than trusted.
		var emitter_v: Variant = src.get(&"emitter")
		var who := "-"
		if emitter_v is Node and is_instance_valid(emitter_v):
			who = String((emitter_v as Node).name)
		draw_string(font, at + Vector2(3.0, -3.0), "%.1fm %s" % [radius_m, who],
				HORIZONTAL_ALIGNMENT_LEFT, -1.0, 8, col)
	draw_string(font, Vector2(3.0, 10.0), "noise x%d  self %.2fm" % [live, _noise_r],
			HORIZONTAL_ALIGNMENT_LEFT, -1.0, 8, col)


## The player, drawn at their own PROJECTED point rather than at the box centre. Heading-up welds the caret
## pointing screen-up and turns the plan under it; north-up freezes the plan and spins the caret. An authored
## MapData.player_marker replaces the drawn triangle (the widget-art fallback rule).
##
## ⭐THE POSITION IS A PROJECTION NOW, THE ROTATION IS NOT. `at` comes from _draw as `view * _centre_xz`, which
## on an un-panned widget collapses back to size * 0.5 exactly (see the note at that call site) — so the HUD
## corner box, and every heading-up frame of it, is unchanged. Only the map tab's pan can move it, and there it
## SHOULD move: the caret is the answer to "where am I", and a caret welded to the middle of a window the player
## has dragged 300 m away would be answering "wherever you are looking", which is not a fact about the player at
## all. It is clipped like any other marker and deliberately NOT rim-pinned: panning off yourself is a thing you
## did on purpose, and an arrow chasing you round the rim would fight the pan.
func _paint_player_caret(skin, at: Vector2) -> void:
	var c := at
	var col: Color = MenuStyle.hud.minimap_player_color
	var md := active_map_data()
	var art: Texture2D = MINIMAP_ART.pick(md.player_marker if md != null else null,
			MenuStyle.hud.minimap_player_texture)
	# Hoisted above the branch: BOTH arms turn by the same angle now. An authored caret that did not swing with
	# the heading was a bug report on day one — it is the one glyph on this widget that is entirely about
	# bearing — so the art tier adopts the drawn tier's rotation instead of blitting flat at native size.
	var ang := FloorplanSection.arrow_angle(_yaw, effective_rotates())
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
	if len_px <= 0.0 or not effective_rotates():
		return
	var dir := MapGlyph.north_dir(_yaw, true)
	var centre := size * 0.5
	# Project onto the rim through the same pure edge projection every pinned marker uses, so the tick sits on
	# exactly the ring the markers pin to instead of on a second, slightly different one.
	var rim := Compass.project_to_edge(dir, size, skin.minimap_marker_edge_margin)
	draw_line(rim, rim + (centre - rim).normalized() * len_px, MenuStyle.hud.minimap_north_color,
			FloorplanSection.stroke_width(skin.minimap_glyph_stroke_px, 1.0, Settings.native_scale()))


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
