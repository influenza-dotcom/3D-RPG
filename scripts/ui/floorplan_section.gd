class_name FloorplanSection
extends RefCounted

## @system Minimap
## @seam view_transform() is THE single projection the HUD minimap draws through: handed to draw_set_transform_matrix(), it maps world (x, z) metres straight onto the Control's pixel space, so the baked floorplan, the optional authored underlay and every marker dot share ONE matrix and can never fork projections.
## @seam walkable_triangles() turns the level's BAKED NavigationMesh into a flat triangle list for one floor band — the day-one picture, needing no authored texture and no MapData; it reads the same three accessors NavMeshAudit / NavLinkPlanner already rely on (get_vertices / get_polygon_count / get_polygon).
## @risk A section cut renders ONLY the band it cuts — a mezzanine, catwalk or stair tread above the cut plane is invisible by construction, and a flight of stairs reads as a gap between two bands.
## @risk band_floor quantises the player's ORIGIN Y and never raycasts down: get_world_3d().direct_space_state returns EMPTY, silently, outside a physics frame — a previously-shipped bug class in this project.
## @test res://tests/test_floorplan_section.gd
##
## The pure geometry brain behind the HUD minimap (scripts/ui/minimap.gd). STATICS ONLY — no nodes, no tree
## access, no autoload reads — so every risky bit of maths here is provable off-tree the way HudSway,
## NavMeshAudit and Compass.project_to_edge are. The widget keeps the impure half: finding the navmesh
## region, caching decks, and painting.
##
## WHY A VECTOR PLAN AND NOT A RENDERED IMAGE. The map box is ~108 px on a 792x444 canvas that is then
## nearest-upscaled ~2.4x to the window (project.godot: viewport 396x216, stretch scale 0.5). A downscaled
## 3D render of grey brushwork is mush at that size; a hairline stroke is crisp. A canvas item is also
## structurally immune to ps1.gdshader's vertex snap — that is a SPATIAL shader and cannot touch 2D drawing.

## Pixels per world metre. `world_span` is the metres the SHORT axis of `rect` shows at zoom 1.0; zoom > 1
## shows FEWER metres (zooms IN). Any degenerate input returns 1.0 rather than dividing by zero — a minimap
## that draws at the wrong scale for one frame is a cosmetic bug, a division by zero is a crash.
static func px_per_metre(rect: Vector2, world_span: float, zoom: float) -> float:
	var short := minf(rect.x, rect.y)
	if short <= 0.0 or world_span <= 0.0 or zoom <= 0.0:
		return 1.0
	return short / (world_span / zoom)


## THE MATRIX. Maps WORLD (x, z) metres onto the Control's local pixel space, player-centred.
##   rotate = true  -> HEADING-UP: the plan turns under a fixed caret. rot = +yaw (derivation below).
##   rotate = false -> NORTH-UP:   the plan is axis-locked, +X right and +Z down — the same handedness as
##                                 MapData.world_to_uv, so an authored underlay lines up with the dots.
##
## DERIVATION (check it, don't trust it). Godot's forward is -basis.z, so a Node3D at yaw t faces
## f = (-sin t, -cos t) in the XZ plane. Transform2D(a) has basis x = (cos a, sin a), y = (-sin a, cos a),
## so it maps f to (sin(a - t), -cos(a - t)). Screen-up is (0, -1), which needs a - t = 0, i.e. a = yaw.
## Pinned at t in {0, +-PI/2, PI} by test_view_transform_rotate_puts_forward_at_screen_up.
##
## Because the whole plan is drawn under this ONE matrix, the per-frame cost of the floorplan is a single
## draw call over a cached vertex buffer — no CPU vertex work at all. That is the performance argument for
## this widget, and the reason the deck cache is keyed by floor band rather than rebuilt on the fly.
static func view_transform(centre_xz: Vector2, yaw: float, ppm: float, rect: Vector2, rotate: bool) -> Transform2D:
	var rot := yaw if rotate else 0.0
	var r := Transform2D(rot, Vector2.ZERO)
	var m := Transform2D(r.x * ppm, r.y * ppm, Vector2.ZERO)
	m.origin = rect * 0.5 - m.basis_xform(centre_xz)
	return m


## The player caret's OWN rotation, in the same screen space. Heading-up welds the caret pointing up and
## turns the world under it (0.0); north-up freezes the world and spins the caret (-yaw — the same
## derivation inverted, since the caret art points at (0, -1) when unrotated).
static func arrow_angle(yaw: float, rotate: bool) -> float:
	return 0.0 if rotate else -yaw


## draw_multiline's `width` is in LOCAL units, and view_transform scales local by `ppm` — so a naive 1.0
## would FATTEN as the player zooms in. This converts a wanted PIXEL width into the local units that render
## as that many pixels. A want_px <= 0 returns -1.0: Godot's transform-INDEPENDENT hairline primitive, which
## sidesteps the trap entirely and is the shipped default (GameSettings.hud.minimap_wall_width = 0.0).
static func stroke_width(want_px: float, ppm: float) -> float:
	if want_px <= 0.0:
		return -1.0
	return want_px / maxf(ppm, 0.0001)


## The floor band `origin_y` falls in, as the band's LOWER edge in world metres. Bands are half-open
## [floor, floor + band) so a point exactly on a boundary belongs to the band above — which keeps
## walkable_triangles' filter and the deck cache agreeing about who owns a shared edge.
static func band_floor(origin_y: float, band: float) -> float:
	if band <= 0.0:
		return origin_y
	return floorf(origin_y / band) * band


## The deck cache's key: the band index as an int, so a Dictionary lookup is an int compare rather than a
## float one. Stable inside a band (a player walking around one floor never re-slices).
static func deck_key(origin_y: float, band: float) -> int:
	if band <= 0.0:
		return 0
	return int(floorf(origin_y / band))


## The height the section cut is taken at: `cut_height` metres above the player's ORIGIN. Chest height cuts
## through walls and doorways but under most desks and railings, which is what makes a floorplan read as
## rooms. NEVER a downward raycast — see the @risk above.
static func cut_plane(origin_y: float, cut_height: float) -> float:
	return origin_y + cut_height


## Vertical honesty for markers: a beacon two floors up FADES instead of lying about being in this room.
## dy = 0 -> 1.0; |dy| >= band -> floor_alpha; linear between, and never outside [floor_alpha, 1.0].
static func marker_alpha(dy: float, band: float, floor_alpha: float) -> float:
	var fa := clampf(floor_alpha, 0.0, 1.0)
	if band <= 0.0:
		return fa
	return lerpf(1.0, fa, clampf(absf(dy) / band, 0.0, 1.0))


## The redraw gate: has the view moved enough to be worth repainting? A standing, still player costs
## literally zero. Pure, so "cheap when idle" is pinned by a test rather than assumed. The yaw delta is
## wrapped to +-PI — without it, crossing the +-PI seam reads as a full-circle flick (the ui.gd sway bug).
static func needs_redraw(prev: Vector2, now: Vector2, prev_yaw: float, yaw: float,
		pos_eps: float, yaw_eps: float) -> bool:
	if prev.distance_squared_to(now) > pos_eps * pos_eps:
		return true
	return absf(wrapf(yaw - prev_yaw, -PI, PI)) > yaw_eps


## THE DAY-ONE PICTURE: the walkable floor for one band, taken from the level's BAKED NavigationMesh and
## returned as a flat triangle-vertex list in WORLD XZ metres (three entries per triangle), ready to wrap in
## an ArrayMesh and draw under view_transform. Recast polygons are convex, so a fan from vertex 0 is exact.
##
## `xf` is the region's global Transform3D — the mesh's vertices are region-LOCAL, and a level that offsets
## or rotates its NavigationRegion3D would otherwise draw its floor in the wrong place.
##
## Band membership is decided by each polygon's CENTROID Y (world space), half-open [y_lo, y_hi), matching
## band_floor. A null mesh, an unbaked mesh, or one whose polygon indices are out of range returns an EMPTY
## array and pushes NOTHING: GUT 9.6 fails the whole suite on any engine error, and an unbaked level is a
## normal state here (the level just draws walls and no fill), not an exceptional one.
static func walkable_triangles(nav: NavigationMesh, xf: Transform3D, y_lo: float, y_hi: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	if nav == null:
		return out
	var n := nav.get_polygon_count()
	if n == 0:
		return out
	var verts := nav.get_vertices()
	var vcount := verts.size()
	if vcount == 0:
		return out
	for i in n:
		var poly := nav.get_polygon(i)
		var cnt := poly.size()
		if cnt < 3:
			continue
		# Bounds-check before ANY indexing: a corrupt / partially-imported mesh would otherwise raise an
		# engine error mid-draw, which under GUT takes the whole suite down.
		var safe := true
		for k in cnt:
			if poly[k] < 0 or poly[k] >= vcount:
				safe = false
				break
		if not safe:
			continue
		var c := Vector3.ZERO
		for k in cnt:
			c += verts[poly[k]]
		c = xf * (c / float(cnt))
		if c.y < y_lo or c.y >= y_hi:
			continue
		var v0 := xf * verts[poly[0]]
		for k in range(1, cnt - 1):
			var v1 := xf * verts[poly[k]]
			var v2 := xf * verts[poly[k + 1]]
			out.append(Vector2(v0.x, v0.z))
			out.append(Vector2(v1.x, v1.z))
			out.append(Vector2(v2.x, v2.z))
	return out
