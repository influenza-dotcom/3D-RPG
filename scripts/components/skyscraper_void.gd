@tool
class_name SkyscraperVoid
extends Node3D

## @system Rendering
## @seam Drop-in: one SkyscraperVoid under a level root turns that level into the ROOF of a tower — at runtime it builds a seeded skyline of neighbour towers (three of them close enough to loom, all of them far enough that no roof reads as reachable), an optional skirt down the level's own outline and an optional fog plane, all visual-only (no collider, no navmesh geometry, no shadow, nothing saved).
## @risk The skirt is placed from the level's VISUAL AABB, so a stray mesh far outside the playable area (a sky prop, a forgotten test brush) drags the footprint out with it and the facade detaches from the building's edge — pin the rect by hand (fit_to_level off, or footprint_points) when the auto fit reads wrong.
## @test res://tests/test_skyscraper_void.gd
##
## "Make the bottom of the map fall away forever, so the level reads as the top of a huge skyscraper" — done
## entirely at RUNTIME, with no authoring in the map and no change to the level geometry.
##
## WHAT IT BUILDS (rebuilt from scratch every load, never saved into the .tscn):
##   • `Facade`    — a skirt around the level's own outline, hanging `depth` metres straight down. ⭐ SHIPS OFF
##                   (`facade_enabled`): from a rooftop you can barely see your own wall anyway — it is a grazing
##                   sliver at the bottom of the frame — and a wall tracing the level's boundary reads as the
##                   level having a boundary. The drop is sold by what is AROUND you, not by your own skin.
##   • `Towers`    — `tower_count` neighbouring towers standing on the haze, every roof BELOW yours, which is
##                   the cue that actually sells altitude: a wall alone reads as a pit, other roofs far below
##                   read as a skyline you are standing over.
##   • `HazeFloor` — an OPTIONAL fog plane far below (ships OFF; see `haze_floor_enabled` for why the reference
##                   has no ground at all).
##   • `Clouds`    — an OVERCAST DECK over the level (overcast_clouds.gdshader): one disc of procedural cloud
##                   cover, faded out at its own rim so it has no edge. The only transparent thing here.
##
## WHY THERE IS NO PER-FRAME WORK AND NOTHING FOLLOWS THE CAMERA. The obvious build is a short skirt that chases
## the camera down as you fall. It isn't needed and it is worse: the facade is FOUR QUADS PER WALL, so making it
## `depth` = 3 km tall costs nothing to draw, and the shader's haze has dissolved it to flat fog by ~400 m below
## your eye — the remaining kilometres are there only so that no fall can ever reach the bottom edge (this
## project's continuous-fall death, Player._update_continuous_fall_death, ends the drop in seconds — hundreds of
## metres). A camera-chasing skirt would ALSO have to drag its top edge down with it, putting a visible horizontal
## cut above a falling player where the real roof should be receding.
##
## ⭐ THE FALL IS THE PAYOFF, SO IT HAS TO SURVIVE ONE. The facade's pattern is anchored to WORLD HEIGHT in the
## shader, not to the mesh's UVs, so storeys stream past a falling player at the right speed and the haze keeps
## its distance under them the whole way down (see facade_void.gdshader's header).
##
## IT CANNOT AFFECT PLAY. No CollisionShape is created (you cannot stand on it, shoot it or walk into it), the
## meshes are not in the `navmesh` group and carry no colliders — and the shipped navmesh bakes from STATIC
## COLLIDERS (LevelRoot warns when a level says otherwise), so the bake cannot see this either. Shadows and GI
## are off. Nothing here is persisted: the save system never sees it, and a reload rebuilds it identically from
## `tower_seed`.
##
## EDITOR: it previews itself in the viewport (`preview_in_editor`), and the preview children are added WITHOUT an
## owner, so saving the scene never writes them into the .tscn. Tick `rebuild` after changing a knob.

const FACADE_SHADER: Shader = preload("res://resources/shaders/facade_void.gdshader")
const CLOUD_SHADER: Shader = preload("res://resources/shaders/overcast_clouds.gdshader")

## Marks every node this component builds, so a rebuild can clear its own output without touching a child the
## author parked here by hand.
const BUILT_META := &"skyscraper_void_built"

## Where the top of the drop sits — the "roofline".
enum Roofline {
	NODE_Y,        ## this node's own height: drag the SkyscraperVoid down to the floor you are standing on.
	LEVEL_BOTTOM,  ## the lowest point of the level's geometry.
}

@export_group("Footprint")
## ON: read the footprint RECT off the level's own geometry (the merged AABB of every MeshInstance3D under
## `fit_root`), so the facade lines up with the building's edge with nothing to author. The roofline is a
## separate question — see `roofline`. OFF: use `footprint_size` / `footprint_center` below.
@export var fit_to_level: bool = true
## What to measure when `fit_to_level` is on. Empty = this node's PARENT (drop this under the level root and it
## just works). Point it at a single "Geometry" node to keep a far-flung prop out of the fit.
@export var fit_root: NodePath = NodePath()
## Pulls the skirt INWARD from the fitted edge (metres). A small inset tucks the seam under the map's own border
## walls; a negative value pushes the facade out past them.
@export var footprint_inset: float = 0.25
## How far the top of the skirt reaches ABOVE the roofline, to bury the seam inside the level's floor slab. Keep
## it small — this is a wall poking up through the roof, so a big value shows as a parapet stub.
@export var top_overlap: float = 0.5
## Manual footprint (used when `fit_to_level` is off): full width/depth in metres, on the node's local X/Z.
@export var footprint_size: Vector2 = Vector2(80.0, 80.0)
## Manual footprint centre, on the node's local X/Z.
@export var footprint_center: Vector2 = Vector2.ZERO
## Which height the drop hangs from.
##
## ⭐ `NODE_Y` — THIS NODE'S OWN HEIGHT — IS THE DEFAULT, AND DELIBERATELY NOT THE LEVEL'S LOWEST POINT. A level's
## AABB bottom is almost never its floor: on the shipped city map it is the underside of the big skybox brush
## wrapped around the level, FIFTY METRES below the street, which hangs the whole facade in a basement nobody can
## see (probe-measured, 2026-09-17). The height you want is the floor you are standing on, and the surface that
## knows it is the editor: drag this node down to the parapet and the preview follows. `LEVEL_BOTTOM` is there for
## a level that really is a slab with nothing under it.
@export var roofline: Roofline = Roofline.NODE_Y
## Nudge the roofline up (+) or down (-) from whatever `roofline` resolved to, in metres. Sink it a metre or two
## to bury the top of the facade inside a thick floor brush.
@export var roofline_offset: float = 0.0
## OPTIONAL non-rectangular footprint: the building's outline as local X/Z points, in order (open — the loop is
## closed for you). Overrides both the fit and the manual rect. Winding doesn't matter; it is corrected so the
## facade always faces outward. Fewer than 3 points = ignored.
@export var footprint_points: PackedVector2Array = PackedVector2Array()

@export_group("The Drop")
## Build the skirt that hangs off this level's own outline. ⭐ OFF as shipped, by request: a wall tracing the
## level's boundary announces the boundary, and from up here you only ever see it edge-on. Turn it on for a
## level whose edge the player LEANS over (a parapet, a balcony), or for the payoff when they fall off it —
## storeys streaming past is the one thing the neighbour towers cannot do on their own.
@export var facade_enabled: bool = false
## How far the facade hangs below the roofline (metres). This is NOT the felt height — the haze decides that —
## it only has to out-reach the longest fall the player can survive to look at. 3 km is free (16 vertices).
@export var depth: float = 3000.0
## Height of the haze plane below the roofline (metres). Looking straight down should find fog, not the skybox.
@export var haze_floor_depth: float = 600.0
## Radius of that plane (metres). Big enough to run past the far edge of the neighbour towers, and far enough
## out that its own edge sits just a few degrees below the horizon, where it reads as one.
@export var haze_floor_extent: float = 8000.0
## Sides of the plane's outline. ⭐ IT IS A DISC, NOT A SQUARE, for one reason: a square's CORNERS are visible
## from up here as two long straight diagonals across the fog — the eye reads them instantly as the edge of a
## flat sheet (probe-measured). A 24-gon at 8 km is a horizon.
@export var haze_floor_sides: int = 24
## The fog plane, and it ships **OFF**. ⭐ THE REFERENCE FRAME HAS NO GROUND AND NO HORIZON LINE — looking down
## a tower block in Peripeteia, the depth simply falls off into darker and darker teal. A lit fog floor is a
## surface, and a surface tells the eye exactly how deep the hole is; without one there is no bottom to find.
## Turn it on for a level that wants a visible city-in-fog below (it then reads as a valley rather than a drop).
@export var haze_floor_enabled: bool = false

@export_group("Overcast")
## Build the cloud deck. It is a single disc `cloud_height` over the roofline, so from underneath it reads as an
## overcast sky and from above (a tower through it, a long fall) as a cloud floor.
##
## ⭐ IT IS A DECK RATHER THAN CLOUDS IN THE SKY SHADER on purpose: `horizon_sky.gdshader` is shared by every
## level in the game and already carries the day/night re-grade, so clouds there would be clouds everywhere.
@export var clouds_enabled: bool = true
## Metres above the roofline. Low enough and the near towers puncture it, which is the shot; high enough and it
## is just weather. Note the level's own skybox brush (if it has one) can hide a deck placed above its lid.
@export var cloud_height: float = 210.0
## Radius of the deck (metres) and how many sides its outline has. Wide enough that its rim is far past anything
## the player can see; a disc for the same reason the fog plane is one — a square's corners read as straight cuts.
@export var cloud_extent: float = 6000.0
@export var cloud_sides: int = 28
## The underside tone and the lighter tone its thinner parts take. ⭐ NEUTRAL GREY on purpose: overcast is the
## one thing up here that should read as colourless, and the blue-grey these started as just looked like more
## sky. (Grey is also safe under the RGB444 quantiser — the rule that breaks is green ABOVE red.)
@export var cloud_dark_color: Color = Color(0.24, 0.24, 0.25)
@export var cloud_light_color: Color = Color(0.40, 0.40, 0.41)
## 1 = a solid lid, 0 = clear sky. "Overcast" is high.
@export var cloud_coverage: float = 0.78
## How gradually a cloud edge thins out, and how many metres across one blob of cloud is.
@export var cloud_softness: float = 0.42
@export var cloud_scale: float = 650.0
@export var cloud_opacity: float = 0.95
## Metres per second the deck slides, and which way the weather is going.
##
## ⭐⭐THIS IS SAFE TO SHIP MOVING BECAUSE THE NOISE IS EXACTLY PERIODIC, not because the speed is low. TIME-driven
## shader noise is a trap this project has already been bitten by: TIME grows unbounded, its float precision
## decays, and a pattern that was stable at boot starts crawling or strobing hours into a session. The cloud
## shader answers that structurally — the field repeats exactly every 4096 noise cells (power-of-two hash wrap,
## lacunarity of exactly 2.0, constant per-octave offsets instead of a fractional one), and the drift offset is
## taken modulo that period in cell space. So the wrap lands on a bit-identical field, and the number fed to the
## noise never grows however long the game has been running.
@export var cloud_drift: float = 24.0
@export var cloud_drift_dir: Vector2 = Vector2(1.0, 0.25)

@export_group("Neighbour Towers")
## How many towers stand in the haze below you. 0 = just the drop.
## Enough of them, spread far enough, that the city has DEPTH — a handful of near blocks with nothing behind
## them cannot read as "running out into the distance" no matter how the fade is tuned.
@export var tower_count: int = 34
## Same layout every run / after every reload. Change it to re-roll the skyline.
@export var tower_seed: int = 20260917
## Nearest / furthest a neighbour's centre can sit from the footprint centre (metres). Keep the near end CLOSE:
## in the reference the next block is right there, looming, and it is the near neighbours that give the drop its
## parallax — a skyline that starts a kilometre out reads as wallpaper.
@export var tower_ring_min: float = 300.0
@export var tower_ring_max: float = 1400.0
## Smallest / largest neighbour footprint (metres, square-ish; each tower jitters both axes).
## Smallest / largest neighbour footprint. The big end is deliberately huge: pushed far enough out that nobody
## could mistake one for a jump, a neighbour has to be genuinely massive to still fill the frame.
@export var tower_width_min: float = 50.0
@export var tower_width_max: float = 240.0
## How far BELOW your roofline a neighbour's roof sits (metres, both positive).
@export var tower_drop_min: float = 40.0
@export var tower_drop_max: float = 600.0
## ⭐ NOT EVERY NEIGHBOUR IS BELOW YOU. `tower_rise_share` of them instead rise UP TO `tower_rise_max` metres
## ABOVE your roofline. The reference frame is not a view from the tallest building in the city — it is a view
## down a canyon, with the next block towering past the top of the screen, and that is most of what makes the
## drop feel like a drop. Set the share to 0 for the "tallest tower in the city" read instead.
@export var tower_rise_share: float = 0.35
@export var tower_rise_max: float = 120.0
## ⭐ HOW MANY NEIGHBOURS ARE RIGHT THERE, and how big the gap to them is (metres, wall to wall). THIS IS THE
## SHOT. In the reference frame the thing that says "you are somewhere very high" is not the drop under your feet
## — you can barely see your own wall from a rooftop — it is the next block standing a few dozen metres away,
## filling half the screen and running down past the bottom of it into the murk. Without these the view is
## floating slabs seen from a helicopter (probe-caught 2026-09-18). They are spread evenly around you by angle so
## one of them is always in frame, and they always rise ABOVE your roofline so they frame the drop rather than
## sit in it.
@export var tower_near_count: int = 3
## ⭐ THE GAP HAS TO READ AS UNCROSSABLE. At close range a neighbouring roof stops being scenery and starts
## looking like somewhere you could get to — and this player has a grapple, so "looks reachable" is a promise the
## level cannot keep. Wall to wall, not centre to centre.
@export var tower_near_gap: float = 95.0
## Share of neighbours that carry a narrower SETBACK block on the roof, and how tall that block can be (metres).
@export var tower_setback_share: float = 0.45
@export var tower_setback_min: float = 15.0
@export var tower_setback_max: float = 70.0
## Flat tone for the neighbours' roofs (the facade grid would read as nonsense laid flat).
@export var tower_roof_color: Color = Color(0.10, 0.11, 0.17)

@export_group("Look")
## ⭐ EVERY COLOUR HERE IS AN ORDINARY INSPECTOR COLOUR — pick it the way it should LOOK. Godot converts a Color
## written into a `source_color` shader uniform from sRGB to linear, so these are not the same numbers as the
## shader's own source defaults (which are raw linear, and only apply when nobody sets them). Writing a linear
## value here gets it converted a second time and the whole drop comes out about five times too dark — which is
## exactly how the first pass rendered a facade nobody could see (probe-measured, 2026-09-17).
##
## The palette is a designer surface, not a constant: the drop has to match whatever palette the level wears.
## ⭐⭐NOTHING IN THIS PALETTE MAY PUT GREEN ABOVE RED. This game ships a 12-bit RGB444 quantiser plus an ordered
## dither in its screen post-process (Settings.color_quantization, index 4 — see post_process.gdshader), and at
## the dark end of that lattice a colour has only a handful of steps per channel to sit on. A dark TEAL — green
## over red, which is what the first Peripeteia pass used — lands on green-leaning lattice points and DITHERS
## INTO A GHOSTLY GREEN SPECKLE over the whole building. The drop is therefore graded cold BLUE: blue dominant,
## green at or under red. It also sits better in the shipped level, which is deep blue with red and magenta neon.
##
## ⭐ THE CLEAN PROBE STAGE CANNOT SHOW THIS. The post-process lives on the PLAYER's camera, so the green only
## appears in the real game — judge any palette change with `__skyscraper_void_probe.tscn` (the in-level probe),
## never with the look probe alone.
##
## Wet concrete — the field the windows are punched into.
@export var wall_color: Color = Color(0.17, 0.18, 0.26)
## The slab edge at the bottom of every storey, catching the light. Together with `shadow_color` this is what
## makes the wall read as STACKED LEDGES rather than as a window grid — the single biggest difference between
## the reference's tower blocks and a modern curtain wall.
@export var ledge_color: Color = Color(0.23, 0.24, 0.33)
## The shadow the slab throws on the wall right above it.
@export var shadow_color: Color = Color(0.09, 0.10, 0.16)
## Unlit glass — darker than the concrete, so an unlit block is a dark mass with lights in it.
@export var window_dark_color: Color = Color(0.07, 0.08, 0.13)
## A window with a bulb on.
@export var window_lit_color: Color = Color(0.98, 0.88, 0.66)
## A second lit tone (a strip light / a screen). A block where every lit window is one colour reads as a texture.
## ⭐ PALE BLUE, NEVER CYAN: a cyan bulb is the single worst colour for the RGB444 quantiser above, and it came
## back out of the dither as a green glow.
@export var window_lit_cool_color: Color = Color(0.72, 0.78, 0.98)
## How many lit windows take the cool tone.
@export var lit_cool_share: float = 0.28
## Above 1 a lit window pushes into HDR and blooms through the level's glow.
## Kept at 1.0: pushing a window into HDR blooms it through the level's glow, and a bloomed cool bulb smears
## its hue over the concrete around it — which is how a few pale windows tinted a whole tower.
@export var window_lit_energy: float = 1.0
## Vertical rain-staining down the panels plus a per-cell jitter — what keeps a kilometre of wall from reading
## as wallpaper. Concrete only; a lit window never varies (it would read as a flicker as you move past it).
@export var grime_strength: float = 0.30
## THE COLOUR OF INFINITY — what every surface becomes once there is enough murk between it and you.
##
## ⭐ THE DEFAULT IS A COLD BLUE: the Peripeteia reference is one cold hue throughout, and blue keeps clear of the
## green-quantiser trap described above. If your level's sky is a different colour, move this toward the sky just
## under the horizon — or leave `auto_haze_from_fog` on and let the level's own fog colour drive it.
@export var haze_color: Color = Color(0.11, 0.13, 0.24)
## ⭐ WHAT THE MURK BECOMES FURTHER DOWN — THE SKY'S COLOUR BELOW THE HORIZON. Fading everything to one flat
## `haze_color` is not enough: that colour is lighter than the void behind it, so a fully-fogged tower keeps a
## perfect silhouette and you can read its foot as a notch against the sky. Once the fog has darkened to the
## colour of the empty air beside it, there is nothing left whose end could be seen.
@export var haze_deep_color: Color = Color(0.03, 0.04, 0.08)
## Metres below the eye at which the murk has fully become `haze_deep_color`.
@export var haze_deep_full: float = 420.0
## ⭐ READ `haze_deep_color` OFF THE LEVEL'S SKY instead of the export above (its `ground_color` — the band the
## sky paints BELOW the horizon, which is what fills the void the drop hangs in). This is what makes "you cannot
## see the bottom" true in a level this component knows nothing about. Falls back to the export when there is no
## such sky.
@export var auto_deep_from_sky: bool = true
## ON: take `haze_color` from the level's Environment fog colour, so the drop matches whatever sky and fog the
## level (or a day/night cycle) is wearing. Falls back to the export when the level has no fog.
@export var auto_haze_from_fog: bool = true

## ⭐⭐THE FOG IS ONE MODEL, NOT TWO FADES — AND THIS IS THE KNOB SET THAT REPLACED A BROKEN ONE. The first version
## faded a surface by how many metres it lay BELOW THE EYE, independently of how far away it was. That is a
## horizontal SLICE PLANE across the whole city: every building, near or far, dissolves at exactly the same
## height, so they all "fade out in the middle somewhere" instead of receding into the distance (reported from
## the live game twice — and no amount of range tuning could fix it, because the slice WAS the model).
##
## What replaces it is what fog actually does: light extinguished along the REAL view ray, through fog that
## thickens as it goes down —  fog = 1 - exp(-distance * density(depth)).  Looking further down a building also
## means looking further away, so depth and distance are one thing, not two. A near wall stays readable hundreds
## of metres down while a distant tower is already gone at eye level.
##
## Metres of level-view distance at which the fog is total. ⭐ KEEP IT NEAR `tower_ring_max`: that is how deep the
## city you built actually is, and the fade should run out where the city does (there are warnings both ways).
@export var haze_distance: float = 1400.0
## Every this many metres of DEPTH doubles the fog's density — how much faster the murk closes when you look
## down. Small values make a deep, soupy shaft; large values make the drop nearly as clear as the horizon.
@export var haze_depth_boost: float = 150.0
## A bubble of perfectly clear air around the camera (metres), so the wall you stand on never fogs.
@export var haze_clear: float = 40.0
## Cap on the fog (0-1). 1.0 = the far end is literally invisible.
@export var haze_max: float = 1.0
## ⭐ HOW MUCH FURTHER A LIT WINDOW CARRIES THROUGH THE MURK than the concrete around it (it divides the density;
## 1 = no further). Light carries further through fog — but it still dies, which is the point: an early version
## CAPPED the fog on windows instead, so every light stayed partly visible for ever and a tower's foot was
## readable as the line where its lights stopped.
@export var light_haze_reach: float = 1.9
## ⭐⭐WHERE THE DROP STOPS BEING DRAWN AT ALL (as a fraction of the fog, 0–1). Fading toward a colour only hides a
## surface when the thing BEHIND it is that colour — and in the shipped level it is not: the map is wrapped in a
## painted skybox brush, against whose bright art a fogged tower stayed a dark silhouette with a visible flat
## bottom. Past this point an ordered dither discards a rising share of the surface's pixels until none are left,
## so it dissolves into whatever is really behind it. THIS is what makes the buildings run down for ever.
##
## ⭐ HELD VERY LATE (0.85), because the dither is the one part of this that can look BROKEN. While it is half-on
## it is a visible screen-door, and a tower caught in that band reads as a patch of noise rather than a building
## ("towers in the distance are still faded", live game 2026-09-18). Real fog does not make a building
## see-through, it makes it a dim silhouette — so the COLOUR fade now carries almost the whole range and the
## stipple only finishes the last 15%. It still always finishes, which is what keeps every bottom unfindable.
@export var dissolve_begin: float = 0.85
## THE FOG THE CITY STANDS IN — the near tone of the optional fog plane far below, which grades out to
## `haze_color` with distance. Only used when `haze_floor_enabled` is on.
@export var haze_ground_color: Color = Color(0.30, 0.31, 0.42)
## One storey / one window column, in metres — the facade's whole sense of scale.
@export var floor_height: float = 3.0
@export var bay_width: float = 2.2
## The window punched into each bay: how much of the bay is glass, how much of the storey, and how far up the
## storey the sill sits. Small values = a housing block; large = a glass office tower.
@export var window_width: float = 0.46
@export var window_height: float = 0.40
@export var window_sill: float = 0.34
## Share of a storey taken by the lit slab edge.
@export var ledge_height: float = 0.10
## Every Nth bay is a BLIND structural pier with no window (0 = off), and this share of bay-groups is a recessed,
## shaded loggia. Both exist to break the metronome — without them a kilometre of identical window columns reads
## as a tiled texture rather than a building.
@export var pier_every: float = 7.0
@export var recess_chance: float = 0.16
## Share of windows with a light on. Low: the reference's blocks are mostly dark with scattered lights, and a
## lit-up tower reads as an office building rather than housing.
@export var lit_chance: float = 0.22

@export_group("Editor")
## Build the preview in the editor viewport. The preview children are never saved into the scene.
@export var preview_in_editor: bool = true
## Momentary: tick to rebuild now (after changing a knob, or when the level's geometry moved).
@export var rebuild: bool = false:
	set(value):
		rebuild = false
		if value:
			build()

## The fitted (or authored) footprint of the last build, in LOCAL X/Z, closed loop order. Read by the tests and
## by the probe; empty until the first build.
var last_footprint: PackedVector2Array = PackedVector2Array()
## The roofline height (local Y) the last build hung from.
var last_roof_y: float = 0.0

func _ready() -> void:
	if Engine.is_editor_hint() and not preview_in_editor:
		return
	build()

## Tear down whatever we built last time and build it again. Safe to call any number of times, in or out of the
## editor; the only nodes it frees are its own (BUILT_META).
func build() -> void:
	if not is_inside_tree():
		return
	for c in get_children():
		if c.has_meta(BUILT_META):
			remove_child(c)   # BEFORE the free, so a rebuild in the same frame can't see the old children here
			c.queue_free()

	var loop := _resolve_footprint()
	last_footprint = loop
	if loop.size() < 3:
		push_warning("SkyscraperVoid: no usable footprint (need 3+ points, or a level with geometry to fit) — nothing built.")
		update_configuration_warnings()
		return

	var haze := _resolve_haze_color()
	var deep := _resolve_deep_color()
	var facade_mat := _make_material(haze, deep, false, Color.BLACK)
	var top := last_roof_y + top_overlap
	var bottom := last_roof_y - maxf(depth, 1.0)

	if facade_enabled:
		var facade := _mesh_node("Facade")
		var walls := _build_walls(loop, top, bottom)
		walls.surface_set_material(0, facade_mat)
		facade.mesh = walls
		_add_built(facade, _flat_box(_footprint_reach(loop), bottom, top))

	if haze_floor_enabled:
		var plane := _mesh_node("HazeFloor")
		var plane_mesh := _build_haze_plane(last_roof_y - maxf(haze_floor_depth, 1.0), haze_floor_extent, haze_floor_sides)
		# vertical_haze 0: the plane is the fog itself, so only DISTANCE may fade it (see below_haze_mult).
		plane_mesh.surface_set_material(0, _make_material(haze, deep, true, haze_ground_color, 0.0))
		plane.mesh = plane_mesh
		var plane_y := last_roof_y - maxf(haze_floor_depth, 1.0)
		_add_built(plane, _flat_box(haze_floor_extent, plane_y - 1.0, plane_y + 1.0))

	if clouds_enabled:
		var clouds := _mesh_node("Clouds")
		var deck_y := last_roof_y + cloud_height
		var deck := _build_haze_plane(deck_y, cloud_extent, cloud_sides)
		deck.surface_set_material(0, _make_cloud_material())
		clouds.mesh = deck
		_add_built(clouds, _flat_box(cloud_extent, deck_y - 1.0, deck_y + 1.0))

	if tower_count > 0:
		var towers := _mesh_node("Towers")
		towers.mesh = _build_towers(loop, facade_mat, _make_material(haze, deep, true, tower_roof_color))
		_add_built(towers, _flat_box(
			tower_ring_max + tower_width_max + _footprint_reach(loop),
			last_roof_y - maxf(sqrt(maxf(haze_distance, 10.0) * maxf(haze_depth_boost, 5.0) * maxf(light_haze_reach, 1.0)) * 2.0, maxf(haze_floor_depth, tower_drop_max)) - 300.0,
			last_roof_y + maxf(tower_rise_max, 1.0) * 1.6 + maxf(tower_setback_max, 0.0) + 10.0))

	update_configuration_warnings()

# -------------------------------------------------------------------------------------------------------------
# FOOTPRINT
# -------------------------------------------------------------------------------------------------------------

## The outline to hang the facade from, as LOCAL X/Z points wound COUNTER-CLOCKWISE in X/Z (which, with the wall
## builder below, is what makes the quads face OUTWARD). Also sets `last_roof_y`.
func _resolve_footprint() -> PackedVector2Array:
	# The level is measured once, and only when something actually needs it (the rect fit, or a LEVEL_BOTTOM
	# roofline) — walking a whole city map's meshes is not free.
	var box := AABB()
	var need_fit := footprint_points.size() < 3 and fit_to_level
	if need_fit or roofline == Roofline.LEVEL_BOTTOM:
		box = _level_aabb()

	# The roofline first: it is independent of the outline's shape, and NODE_Y (local 0) means "hang it from
	# wherever the author dragged this node".
	last_roof_y = roofline_offset
	if roofline == Roofline.LEVEL_BOTTOM and box.size != Vector3.ZERO:
		# Measured in GLOBAL space (that is where the geometry lives) and brought back into this node's local
		# space, so a SkyscraperVoid the author moved or nested still lines up with the building.
		last_roof_y = minf(to_local(box.position).y, to_local(box.position + box.size).y) + roofline_offset

	if footprint_points.size() >= 3:
		return _wind_ccw(footprint_points.duplicate())

	var size := footprint_size
	var centre := footprint_center
	if need_fit:
		if box.size == Vector3.ZERO:
			return PackedVector2Array()
		var lo := to_local(box.position)
		var hi := to_local(box.position + box.size)
		centre = Vector2((lo.x + hi.x) * 0.5, (lo.z + hi.z) * 0.5)
		size = Vector2(absf(hi.x - lo.x), absf(hi.z - lo.z))
	var h := size * 0.5 - Vector2(footprint_inset, footprint_inset)
	if h.x <= 0.0 or h.y <= 0.0:
		return PackedVector2Array()
	return _wind_ccw(PackedVector2Array([
		centre + Vector2(-h.x, -h.y), centre + Vector2(h.x, -h.y),
		centre + Vector2(h.x, h.y), centre + Vector2(-h.x, h.y),
	]))

## The merged world-space AABB of every MeshInstance3D under the fit root, EXCLUDING our own output (otherwise the
## second fit would measure the first facade — a footprint that grows every rebuild).
func _level_aabb() -> AABB:
	var root := get_node_or_null(fit_root) if not fit_root.is_empty() else get_parent()
	if root == null:
		return AABB()
	var box := AABB()
	var first := true
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n == self or (n is Node3D and n.has_meta(BUILT_META)):
			continue
		if n is MeshInstance3D:
			var mi := n as MeshInstance3D
			if mi.mesh != null and mi.is_inside_tree():
				var world: AABB = mi.global_transform * mi.get_aabb()
				box = world if first else box.merge(world)
				first = false
		for c in n.get_children():
			stack.append(c)
	return box

## Return `loop` wound counter-clockwise in X/Z (positive shoelace area). The author's points may be wound either
## way, and a clockwise loop would build every wall quad inside-out — an invisible facade with backface culling on.
static func _wind_ccw(loop: PackedVector2Array) -> PackedVector2Array:
	var area := 0.0
	for i in loop.size():
		var a := loop[i]
		var b := loop[(i + 1) % loop.size()]
		area += a.x * b.y - b.x * a.y
	if area >= 0.0:
		return loop
	var flipped := PackedVector2Array()
	for i in range(loop.size() - 1, -1, -1):
		flipped.append(loop[i])
	return flipped

# -------------------------------------------------------------------------------------------------------------
# MESHES
# -------------------------------------------------------------------------------------------------------------

## The facade skirt: one outward-facing quad per footprint edge, from `top` down to `bottom`.
##
## ⭐ UV.x IS METRES ALONG THE WALL, NOT 0..1. The shader divides it by `bay_width` to get window columns, so the
## window grid keeps one real-world size on a 12 m edge and a 200 m edge — the thing that makes the building read
## as huge instead of as a scaled-up box. (UV.y is written for completeness; the shader takes the vertical from
## WORLD height so the pattern can never swim.)
func _build_walls(loop: PackedVector2Array, top: float, bottom: float) -> ArrayMesh:
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var uvs := PackedVector2Array()
	var idx := PackedInt32Array()
	var run := 0.0   # metres travelled around the perimeter, so the grid is continuous across corners
	for i in loop.size():
		var a := loop[i]
		var b := loop[(i + 1) % loop.size()]
		var edge := b - a
		var length := edge.length()
		if length <= 0.0001:
			continue
		# CCW loop in X/Z -> the outward normal is the edge direction rotated -90°.
		var dir := edge / length
		var normal := Vector3(dir.y, 0.0, -dir.x)
		var base := verts.size()
		verts.append(Vector3(a.x, top, a.y))
		verts.append(Vector3(b.x, top, b.y))
		verts.append(Vector3(b.x, bottom, b.y))
		verts.append(Vector3(a.x, bottom, a.y))
		for _n in 4:
			norms.append(normal)
		uvs.append(Vector2(run, 0.0))
		uvs.append(Vector2(run + length, 0.0))
		uvs.append(Vector2(run + length, top - bottom))
		uvs.append(Vector2(run, top - bottom))
		idx.append_array([base, base + 2, base + 1, base, base + 3, base + 2])
		run += length
	return _surface(verts, norms, uvs, idx)

## The fog far below: one up-facing DISC of radius `extent` at `y`, centred on the footprint.
func _build_haze_plane(y: float, extent: float, sides: int) -> ArrayMesh:
	var ring := PackedVector2Array()
	var n := maxi(sides, 3)
	for i in n:
		var a := TAU * float(i) / float(n)
		ring.append(_footprint_centre() + Vector2(cos(a), sin(a)) * extent)
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var uvs := PackedVector2Array()
	var idx := PackedInt32Array()
	_append_cap(_wind_ccw(ring), y, verts, norms, uvs, idx)
	return _surface(verts, norms, uvs, idx)

## A custom AABB `reach` metres either side of the footprint centre, spanning `low`..`high` in Y. Every built
## child gets one (see `_add_built`).
func _flat_box(reach: float, low: float, high: float) -> AABB:
	var c := _footprint_centre()
	return AABB(Vector3(c.x - reach, low, c.y - reach), Vector3(reach * 2.0, maxf(high - low, 1.0), reach * 2.0))

## How far the footprint reaches from its own centre (its half-diagonal), in metres.
func _footprint_reach(loop: PackedVector2Array) -> float:
	var c := _footprint_centre()
	var reach := 1.0
	for p in loop:
		reach = maxf(reach, (p - c).length())
	return reach

## The centre of the last resolved footprint, in local X/Z — what the fog disc and the tower ring are built around.
func _footprint_centre() -> Vector2:
	if last_footprint.is_empty():
		return Vector2.ZERO
	var c := Vector2.ZERO
	for p in last_footprint:
		c += p
	return c / float(last_footprint.size())

## Every neighbour tower in ONE mesh, two surfaces (walls, roof caps) = two draw calls for the whole skyline.
## Deterministic from `tower_seed`: the same skyline after a reload, a death or a door, with nothing saved.
func _build_towers(loop: PackedVector2Array, wall_mat: ShaderMaterial, roof_mat: ShaderMaterial) -> ArrayMesh:
	var centre := _footprint_centre()
	# Keep neighbours clear of OUR footprint: the ring is measured from the centre, so a wide building needs every
	# neighbour pushed out past its own half-diagonal (`span`) or a tower would stand inside the level. The near
	# neighbours below clear it by `tower_near_gap` exactly, which is what makes them loom.
	var span := 0.0
	for p in loop:
		span = maxf(span, (p - centre).length())

	var rng := RandomNumberGenerator.new()
	rng.seed = tower_seed
	var wv := PackedVector3Array()
	var wn := PackedVector3Array()
	var wuv := PackedVector2Array()
	var wi := PackedInt32Array()
	var rv := PackedVector3Array()
	var rn := PackedVector3Array()
	var ruv := PackedVector2Array()
	var ri := PackedInt32Array()

	var near_n := clampi(tower_near_count, 0, tower_count)
	for t in tower_count:
		var near := t < near_n
		var w := rng.randf_range(tower_width_min, tower_width_max)
		var d := rng.randf_range(tower_width_min, tower_width_max)
		# The near neighbours are spread EVENLY by angle (plus a jitter) so one of them is in frame whichever way
		# the player faces; the rest are placed at random around the ring.
		var angle := rng.randf() * TAU
		if near:
			angle = TAU * (float(t) + rng.randf() * 0.5) / float(maxi(near_n, 1))
		# ⭐ BIASED OUTWARD (`pow(randf(), 0.55)` skews a uniform roll toward 1). A uniform roll over the ring puts
		# as many neighbours in the first 200 m as in the last 1800, which ringed the player with a stadium wall
		# of towers instead of a city with a couple of blocks close by (probe-caught, 2026-09-18).
		# ⭐ CLEARANCE IS MEASURED WITH THE HALF-DIAGONAL, NOT THE HALF-WIDTH. A tower is an axis-aligned box
		# placed at an arbitrary ANGLE, so the part of it nearest to us is a CORNER, and a corner sticks out by
		# sqrt(w²+d²)/2 — up to 1.41x the half-width. Budgeting with the half-width let a wide neighbour at a
		# diagonal angle reach back INSIDE the level (a wall 35 m from the centre of a 40x60 building;
		# test-caught 2026-09-18) and made `tower_near_gap` mean something other than what it says.
		var reach := Vector2(w, d).length() * 0.5
		var dist := maxf(tower_ring_min, span + reach) \
			+ pow(rng.randf(), 0.55) * maxf(tower_ring_max - tower_ring_min, 1.0)
		if near:
			# `span` is our own half-diagonal and `reach` theirs, so whatever the angle, what is left between the
			# two buildings is at least `tower_near_gap` — the number a designer can actually reason about.
			dist = span + reach + maxf(tower_near_gap, 1.0) + rng.randf() * 30.0
		var at := centre + Vector2(cos(angle), sin(angle)) * dist
		# Most neighbours sit below your roofline; `tower_rise_share` of them tower over it instead (see the
		# export). The roll is taken from the SAME rng in the same order for every tower, so the skyline stays
		# reproducible from the seed.
		var roof := last_roof_y - rng.randf_range(tower_drop_min, tower_drop_max)
		if near:
			# A near neighbour ALWAYS towers over you: it is the frame around the drop, not part of it.
			roof = last_roof_y + rng.randf_range(maxf(tower_rise_max, 1.0) * 0.5, maxf(tower_rise_max, 1.0) * 1.6)
		elif rng.randf() < clampf(tower_rise_share, 0.0, 1.0):
			roof = last_roof_y + rng.randf_range(maxf(tower_rise_max, 1.0) * 0.15, maxf(tower_rise_max, 1.0))
		# ⭐ EVERY NEIGHBOUR IS ROOTED DEEPER THAN THE MURK EVER CLEARS. A tower whose foot sits inside the visible
		# range shows its bottom edge as a line where its window lights stop, which is the one thing the drop must
		# never show. The fog is total at the depth where distance x density(depth) passes ~3, and for a WINDOW
		# (which carries `light_haze_reach` further) that root is about sqrt(haze_distance * boost * reach) —
		# doubled here for headroom, because the cost of being wrong is a visible foot and the cost of being
		# generous is nothing at all.
		var invisible_below := maxf(sqrt(maxf(haze_distance, 10.0) * maxf(haze_depth_boost, 5.0) * maxf(light_haze_reach, 1.0)) * 2.0, haze_floor_depth + 200.0)
		var foot := minf(roof - 60.0, last_roof_y - invisible_below)
		var rect := _wind_ccw(PackedVector2Array([
			at + Vector2(-w * 0.5, -d * 0.5), at + Vector2(w * 0.5, -d * 0.5),
			at + Vector2(w * 0.5, d * 0.5), at + Vector2(-w * 0.5, d * 0.5),
		]))
		_append_walls(rect, roof, foot, wv, wn, wuv, wi)
		_append_cap(rect, roof, rv, rn, ruv, ri)
		# A SETBACK on some towers: a narrower block standing on the roof. Four identical prisms read as a test
		# scene; two-stage silhouettes read as buildings, for one extra rect and no new material.
		if rng.randf() < clampf(tower_setback_share, 0.0, 1.0):
			var sw := w * rng.randf_range(0.45, 0.72)
			var sd := d * rng.randf_range(0.45, 0.72)
			var cap_top := roof + rng.randf_range(tower_setback_min, maxf(tower_setback_max, tower_setback_min))
			var cap := _wind_ccw(PackedVector2Array([
				at + Vector2(-sw * 0.5, -sd * 0.5), at + Vector2(sw * 0.5, -sd * 0.5),
				at + Vector2(sw * 0.5, sd * 0.5), at + Vector2(-sw * 0.5, sd * 0.5),
			]))
			_append_walls(cap, cap_top, roof, wv, wn, wuv, wi)
			_append_cap(cap, cap_top, rv, rn, ruv, ri)

	# Materials are set HERE, by surface, because this mesh has two of them — and `material_override` on the node
	# would silently paint the roof caps with the facade grid (an override outranks every surface material).
	var mesh := ArrayMesh.new()
	if _append_surface(mesh, wv, wn, wuv, wi):
		mesh.surface_set_material(mesh.get_surface_count() - 1, wall_mat)
	if _append_surface(mesh, rv, rn, ruv, ri):
		mesh.surface_set_material(mesh.get_surface_count() - 1, roof_mat)
	return mesh

## _build_walls' loop, appending into shared arrays (so every tower lands in one surface).
func _append_walls(loop: PackedVector2Array, top: float, bottom: float, verts: PackedVector3Array,
		norms: PackedVector3Array, uvs: PackedVector2Array, idx: PackedInt32Array) -> void:
	var run := 0.0
	for i in loop.size():
		var a := loop[i]
		var b := loop[(i + 1) % loop.size()]
		var edge := b - a
		var length := edge.length()
		if length <= 0.0001:
			continue
		var dir := edge / length
		var normal := Vector3(dir.y, 0.0, -dir.x)
		var base := verts.size()
		verts.append(Vector3(a.x, top, a.y))
		verts.append(Vector3(b.x, top, b.y))
		verts.append(Vector3(b.x, bottom, b.y))
		verts.append(Vector3(a.x, bottom, a.y))
		for _n in 4:
			norms.append(normal)
		uvs.append(Vector2(run, 0.0))
		uvs.append(Vector2(run + length, 0.0))
		uvs.append(Vector2(run + length, top - bottom))
		uvs.append(Vector2(run, top - bottom))
		idx.append_array([base, base + 2, base + 1, base, base + 3, base + 2])
		run += length

## An up-facing cap over a CCW loop (the `_wind_ccw` sense), fanned from its first vertex — convex loops only,
## which the tower rects and the fog disc both are.
##
## ⭐ THE WINDING IS LOAD-BEARING AND FAILS SILENTLY. Reversed, every cap faces DOWN and backface culling deletes
## it from every view above it: the fog disc vanishes and you look straight through the floor of the world into
## the sky, and the neighbour towers lose their roofs. It cost a probe cycle to find, because a facade with no
## fog behind it still looks like *something*. `test_the_caps_face_up` pins the triangle winding itself, not the
## NORMAL attribute — the attribute was already correct while the geometry pointed the other way.
func _append_cap(loop: PackedVector2Array, y: float, verts: PackedVector3Array, norms: PackedVector3Array,
		uvs: PackedVector2Array, idx: PackedInt32Array) -> void:
	var base := verts.size()
	for p in loop:
		verts.append(Vector3(p.x, y, p.y))
		norms.append(Vector3.UP)
		uvs.append(p)
	for i in range(1, loop.size() - 1):
		idx.append_array([base, base + i, base + i + 1])

func _surface(verts: PackedVector3Array, norms: PackedVector3Array, uvs: PackedVector2Array,
		idx: PackedInt32Array) -> ArrayMesh:
	var mesh := ArrayMesh.new()
	_append_surface(mesh, verts, norms, uvs, idx)
	return mesh

## Appends one triangle surface. Returns false (adding nothing) for empty arrays, so a caller that assigns
## materials by surface index can't hand the next surface's material to the wrong geometry.
func _append_surface(mesh: ArrayMesh, verts: PackedVector3Array, norms: PackedVector3Array,
		uvs: PackedVector2Array, idx: PackedInt32Array) -> bool:
	if verts.is_empty() or idx.is_empty():
		return false
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = norms
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = idx
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return true

# -------------------------------------------------------------------------------------------------------------
# MATERIAL / NODES
# -------------------------------------------------------------------------------------------------------------

## A facade material (or a flat-filled one for the haze plane / roof caps). A ShaderMaterial on purpose and not a
## StandardMaterial3D: Ps1Warp's applier swaps every plain BaseMaterial3D surface in a level for the PS1 warp
## shader, which would repaint the whole drop — it skips ShaderMaterial surfaces, so this is how the facade keeps
## its own shader (see scripts/effects/ps1_applier.gd::_ps1ify).
func _make_material(haze: Color, deep: Color, flat: bool, flat_tone: Color, vertical_haze: float = 1.0) -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = FACADE_SHADER
	mat.set_shader_parameter("haze_color", haze)
	mat.set_shader_parameter("haze_distance", maxf(haze_distance, 10.0))
	mat.set_shader_parameter("haze_depth_boost", maxf(haze_depth_boost, 5.0))
	mat.set_shader_parameter("haze_clear", maxf(haze_clear, 0.0))
	mat.set_shader_parameter("haze_max", clampf(haze_max, 0.0, 1.0))
	mat.set_shader_parameter("floor_height", maxf(floor_height, 0.1))
	mat.set_shader_parameter("bay_width", maxf(bay_width, 0.1))
	mat.set_shader_parameter("window_width", clampf(window_width, 0.0, 1.0))
	mat.set_shader_parameter("window_height", clampf(window_height, 0.0, 1.0))
	mat.set_shader_parameter("window_sill", clampf(window_sill, 0.0, 1.0))
	mat.set_shader_parameter("ledge_height", clampf(ledge_height, 0.0, 0.5))
	mat.set_shader_parameter("pier_every", maxf(pier_every, 0.0))
	mat.set_shader_parameter("recess_chance", clampf(recess_chance, 0.0, 1.0))
	mat.set_shader_parameter("lit_chance", clampf(lit_chance, 0.0, 1.0))
	mat.set_shader_parameter("wall_color", wall_color)
	mat.set_shader_parameter("ledge_color", ledge_color)
	mat.set_shader_parameter("shadow_color", shadow_color)
	mat.set_shader_parameter("window_dark_color", window_dark_color)
	mat.set_shader_parameter("window_lit_color", window_lit_color)
	mat.set_shader_parameter("window_lit_cool_color", window_lit_cool_color)
	mat.set_shader_parameter("lit_cool_share", clampf(lit_cool_share, 0.0, 1.0))
	mat.set_shader_parameter("window_lit_energy", maxf(window_lit_energy, 0.0))
	mat.set_shader_parameter("light_haze_reach", maxf(light_haze_reach, 1.0))
	mat.set_shader_parameter("haze_deep_color", deep)
	mat.set_shader_parameter("haze_deep_full", maxf(haze_deep_full, 1.0))
	mat.set_shader_parameter("dissolve_begin", clampf(dissolve_begin, 0.0, 1.0))
	mat.set_shader_parameter("grime_strength", clampf(grime_strength, 0.0, 1.0))
	mat.set_shader_parameter("flat_fill", flat)
	mat.set_shader_parameter("flat_fill_color", flat_tone)
	mat.set_shader_parameter("below_haze_mult", clampf(vertical_haze, 0.0, 1.0))
	return mat

## The overcast deck's material. Its own shader, not the facade's: this is the one surface here that wants real
## alpha (see overcast_clouds.gdshader) rather than the dither the drop dissolves with.
func _make_cloud_material() -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = CLOUD_SHADER
	mat.set_shader_parameter("cloud_dark", cloud_dark_color)
	mat.set_shader_parameter("cloud_light", cloud_light_color)
	mat.set_shader_parameter("coverage", clampf(cloud_coverage, 0.0, 1.0))
	mat.set_shader_parameter("softness", clampf(cloud_softness, 0.01, 1.0))
	mat.set_shader_parameter("cloud_scale", maxf(cloud_scale, 10.0))
	mat.set_shader_parameter("opacity", clampf(cloud_opacity, 0.0, 1.0))
	mat.set_shader_parameter("drift", maxf(cloud_drift, 0.0))
	mat.set_shader_parameter("drift_dir", cloud_drift_dir)
	# The rim fade needs to know where the disc is and how big it is; it is centred on the footprint like
	# everything else this component builds, in WORLD space (the shader reads world positions).
	var centre := _footprint_centre()
	mat.set_shader_parameter("disc_centre", to_global(Vector3(centre.x, 0.0, centre.y)))
	mat.set_shader_parameter("disc_radius", maxf(cloud_extent, 1.0))
	return mat

func _mesh_node(node_name: String) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = node_name
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	return mi

## Parent a built child. `box` is its custom AABB: these meshes are kilometres tall and the haze plane is
## kilometres wide, and a camera looking down over the parapet sees them almost edge-on — leaving Godot to cull
## them by their real bounds is what pops the whole drop out of frame at the worst possible moment.
func _add_built(mi: MeshInstance3D, box: AABB) -> void:
	mi.custom_aabb = box
	mi.set_meta(BUILT_META, true)
	add_child(mi)   # deliberately NO owner: an editor preview is never written into the saved scene

## `haze_color`, or the level's own fog colour when `auto_haze_from_fog` is on and the level has fog. Matching the
## fog is what welds the drop to the sky: a facade dissolving into a grey that isn't the sky's grey draws a visible
## edge exactly where the illusion needs none.
func _resolve_haze_color() -> Color:
	if not auto_haze_from_fog:
		return haze_color
	var env := _level_environment()
	if env != null and env.fog_enabled:
		return env.fog_light_color
	return haze_color

## `haze_deep_color`, or the level sky's own below-the-horizon band when `auto_deep_from_sky` is on and the
## level's sky exposes one. StarSky paints every level with horizon_sky.gdshader, whose `ground_color` uniform is
## precisely the colour sitting behind the drop — so reading it makes the dissolve exact instead of hand-matched.
## `get_shader_parameter` returns null for a uniform nobody has written (the shader's own default is in force),
## which is not a colour we can match, so that case keeps the authored export.
func _resolve_deep_color() -> Color:
	if not auto_deep_from_sky:
		return haze_deep_color
	var env := _level_environment()
	if env == null or env.sky == null:
		return haze_deep_color
	var sky_mat := env.sky.sky_material as ShaderMaterial
	if sky_mat == null:
		return haze_deep_color
	var ground: Variant = sky_mat.get_shader_parameter("ground_color")
	return ground if ground is Color else haze_deep_color

func _level_environment() -> Environment:
	if not is_inside_tree():
		return null
	for n in get_tree().get_nodes_in_group(Groups.WORLD_ENVIRONMENT):
		var we := n as WorldEnvironment
		if we != null and we.environment != null:
			return we.environment
	var root := get_parent()
	if root == null:
		return null
	for c in root.get_children():
		if c is WorldEnvironment and (c as WorldEnvironment).environment != null:
			return (c as WorldEnvironment).environment
	return null

func _get_configuration_warnings() -> PackedStringArray:
	var w := PackedStringArray()
	if footprint_points.size() > 0 and footprint_points.size() < 3:
		w.append("`footprint_points` needs 3+ points to be an outline (it has %d) — it is being ignored." % footprint_points.size())
	if fit_to_level and footprint_points.size() >= 3:
		w.append("`footprint_points` overrides `fit_to_level` — the fit is doing nothing. Clear the points, or untick the fit.")
	if haze_floor_enabled and depth <= haze_floor_depth:
		w.append("`depth` (%.0f m) is not deeper than `haze_floor_depth` (%.0f m) — the fog plane would sit at or below the bottom edge of the facade, showing the cut. Make the drop deeper." % [depth, haze_floor_depth])
	for named in [["wall_color", wall_color], ["ledge_color", ledge_color], ["shadow_color", shadow_color],
			["haze_color", haze_color], ["window_dark_color", window_dark_color]]:
		var col: Color = named[1]
		if col.g > col.r + 0.05:
			w.append("`%s` has more green than red (%.2f vs %.2f). This game quantises the screen to 12-bit RGB444 and dithers it, and at the dark end a green-leaning colour comes back as a ghostly green speckle over the whole building. Grade the drop blue: blue dominant, green at or under red." % [named[0], col.g, col.r])
	if tower_count > 0 and haze_distance < tower_ring_max * 0.5:
		w.append("`haze_distance` (%.0f m) is much shorter than the ring the towers stand in (`tower_ring_max` %.0f m) — the far half of the skyline fogs out in one step instead of receding. Match the fade to the city you actually built." % [haze_distance, tower_ring_max])
	if tower_count > 0 and haze_distance > tower_ring_max * 4.0:
		w.append("`haze_distance` (%.0f m) is far longer than the city is deep (`tower_ring_max` %.0f m) — the furthest neighbour is still crisp, so nothing reads as fading into the distance." % [haze_distance, tower_ring_max])
	if clouds_enabled and cloud_extent < haze_distance:
		w.append("`cloud_extent` (%.0f m) is smaller than `haze_distance` (%.0f m) — the deck's rim can fall inside the distance the player can still see, so the overcast has a visible edge. Make it wider." % [cloud_extent, haze_distance])
	if clouds_enabled and cloud_height <= tower_rise_max and tower_near_count > 0:
		w.append("`cloud_height` (%.0f m) is at or under `tower_rise_max` (%.0f m), so the near towers stand clean through the overcast. That is a fine shot on purpose — ignore this if you meant it." % [cloud_height, tower_rise_max])
	if haze_clear >= haze_distance * 0.5:
		w.append("`haze_clear` (%.0f m) is a large share of `haze_distance` (%.0f m) — that much perfectly clear air leaves the fog no room to build up." % [haze_clear, haze_distance])
	if not rotation.is_zero_approx():
		w.append("This node is rotated — the drop is built on world Y (gravity, the haze under your eye) and the fitted footprint is axis-aligned, so a rotation shears the facade off the building's edge. Keep the rotation at 0 and move/author the footprint instead.")
	if tower_near_count > 0 and tower_near_gap < 40.0:
		w.append("`tower_near_gap` is %.0f m — a neighbouring roof that close reads as somewhere the player could jump or grapple to, which is a promise the level cannot keep. Keep it well clear (the shipped value is 95 m)." % tower_near_gap)
	if tower_count > 0 and tower_ring_min < _footprint_reach(last_footprint) and not last_footprint.is_empty():
		w.append("`tower_ring_min` (%.0f m) is inside this building's own footprint (%.0f m from its centre) — neighbours are pushed out to clear it, so the near ring is not doing what the number says." % [tower_ring_min, _footprint_reach(last_footprint)])
	return w
