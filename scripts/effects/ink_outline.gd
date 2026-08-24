class_name InkOutline
extends MeshInstance3D

## @system Ink Outline
## @seam A screen-filling quad childed to a Camera3D; ink_outline.gdshader edge-detects that camera's DEPTH + NORMAL_ROUGHNESS buffers to ink the WORLD, while actors (NPCs / props / view model — everything wearing the inverted-hull rim) are excluded per-pixel via a coverage+depth mask SubViewport fed by the ACTOR_INK_MASK_LAYER render-layer stamp.
## @risk Actor exclusion rests on the ACTOR_INK_MASK_LAYER stamp riding the overlay walks (Character._apply_overlay_to_meshes / NpcOutline.apply_part_overlays / Throwable._setup_overlay_chain / body_part_gib strip / BodyModelSwap._apply_actor_outline / ExplosionMesh._ready) — a new actor path that skips those walks gets inked over its hull rim (the doubled-outline complaint) with no error anywhere, and one that is neither hull-rimmed nor stamped (the player's own first-person body until 2026-08-15, every explosion and hit spark until 2026-08-16) wears the WORLD's line where every NPC beside it wears a rim.
## @risk The mask viewport SHARES the main World3D, so anything visual parented inside it is registered with the MAIN scenario too and the main camera would draw it; the resolve quad only stays invisible because it sits on MASK_INTERNAL_LAYER, a render bit above the 20 a default cull_mask carries. Give it an ordinary layer and it paints its raw depth encoding over the whole screen.
## @risk The mask's depth channel is a NUMBER encoded in an 8-bit sRGB colour target — it survives only because the resolve shader pre-compensates for that transfer and the mask camera's Environment is pinned to the LINEAR tonemapper. A filmic tonemap, an exposure change, glow or colour adjustments on that Environment all corrupt it silently, and the symptom is actors flickering back to a doubled outline.
## @risk The hull rim (outline.gdshader) is a TRANSPARENT material and writes NO depth, so the mask's depth stops at the actor's opaque body and the ink shader has to SEARCH outward (mask_rim_search_px) for it. Author an outline_width whose rim out-reaches that search and the rim degrades to the old always-suppress behaviour — not a break, but the hidden actor's ring-shaped halo comes back on it.
## @risk The quad is culled by its real AABB before the vertex shader can fill the screen, so losing extra_cull_margin makes the whole effect vanish at certain camera angles rather than fail loudly.
## @risk The mask is a SECOND scene render — it costs a full extra pass over every masked actor/prop. It is deliberately stripped to coverage-only (no AA/TAA/shadow atlas, coarse LOD); re-enabling any of that, or letting it inherit the project's 3D supersample again, doubles the frame cost of a level full of props with no visual gain.
## @risk The ink's suppression window must be sized off width_px, NEVER off the mask's resolution — scaling it off the mask texel erases world ink several px out from every actor, a distance-invariant bare halo you can spot people by. Nothing resolution-derived may reach the shader; mask_resolution below 1.0 widens that band and is the one saving here that is not free.
## @risk If the Forward+ depth prepass is ever disabled the normal buffer stops filling and the CREASE lines quietly disappear, leaving silhouettes only — no error, just fewer lines.
## @risk The contact merge (contact_merge_m) deletes a real SILHOUETTE whenever the surface behind it is nearer than the threshold, which is exactly what makes a stack of slabs read as one solid — and also what makes a crate parked against a wall, a low ledge, or a doorway into a shallow alcove lose the line that said they were separate things. It is measured in world metres, so it does NOT relax with distance the way every other term here does. Nothing errors; the frame just reads flatter.
## @risk The seam merge (crease_min_feature_px) is the ONE crease term that only ever REMOVES lines, and it decides by screen-space width alone: raise it and small real features (a reveal, a trim, a stair tread at distance) silently lose their interior lines while their silhouettes stay — nothing errors, the world just reads flatter far away, and a tread that projects narrower than the reach loses its line and gets it back as you approach. It does not touch the depth term, so a genuine gap between two pieces still draws. concave_crease_strength below 1 removes the floor/wall junction and every inside corner along with the slab-on-wall lines it is aimed at — they are the same crease.
## @test res://tests/test_ink_outline.gd
## Borderlands-style black ink outline, as a DROP-IN: child one of these to any Camera3D and every
## surface that camera renders gets the same screen-space black line — EXCEPT the actors. NPCs, props
## and the view model keep their authored inverted-hull look untouched (the rim IS their outline, and it
## predates this pass); they are excluded per-pixel via the actor mask below. The WORLD is what this
## pass inks; there is nothing to author per mesh and nothing to keep in sync.
##
## WHY ACTORS ARE EXCLUDED (learned the hard way — playtest round 2): an actor's OPAQUE BODY is a depth
## discontinuity like any other, so the edge detect draws a line straddling its silhouette — which lands
## half on the hull's rim ring and half on the world, reading as a smeared second outline hugging the
## clean one. (The hull itself is innocent: it writes no depth at all, being a transparent-pass material —
## measured, see actor_mask_resolve.gdshader. This file used to claim the opposite.) Making the resting
## rims transparent (round 1's fix) wasn't enough: coloured signal rims (hostile red etc.) still got
## ink-ringed, and the ink's own crease/silhouette treatment on small organic bodies reads scribbly next
## to the clean hull.
## The user's verdict was unambiguous: actors looked PERFECT with the hull alone. So the hull owns the
## actors and the ink owns the world, and the two never stack.
##
## HOW: everything hull-outlined renders (additionally) on the ACTOR_INK_MASK_LAYER render layer — the
## bit rides the same overlay walks that dress actors (Character._apply_overlay_to_meshes, NpcOutline.
## apply_part_overlays, Throwable._setup_overlay_chain, body_part_gib's strip pass, and
## BodyModelSwap._apply_actor_outline for a rig nobody else dresses), so it re-applies on
## body swaps and rebuilds for free. This node renders that layer (plus the view-model layer, which is
## already isolated) into a small mask SubViewport sharing the main world, camera-synced each
## frame; the shader discards any pixel the mask covers.
##
## THE LAYER ALSO CARRIES THINGS THAT ARE NOT ACTORS, and ExplosionMesh (2026-08-16) is the case that
## widened it: the explosion / bullet-impact flash is an OPAQUE emissive sphere, so it wrote depth like a
## wall and the edge detect ringed it in black. A muzzle flash is light, not geometry — it owes the world
## no silhouette. Nothing about this pass is actor-specific; the layer means "the ink does not own this
## pixel", and a VFX mesh that stamps it without a rim is asking for NO line, which is a legitimate
## answer here in a way it never is for an actor.
##
## ⭐THE RIM AND THE STAMP ARE ONE CONTRACT, and 2026-08-15 is the case that proves it. The player's own
## first-person body had NEITHER — Character's walk is scoped to `mesh`, and the Player's `mesh` is the
## GunMesh, so the legs/torso/body-arms rig (a sibling subtree childed straight to the Player) was never
## reached. It was not double-outlined; it was outlined by the WRONG SYSTEM, wearing the world's line while
## every NPC beside it wore a rim. Note what "just stamp the mask bit" would have done there: removed the
## only outline it had. A new actor path owes BOTH halves, which is why BodyModelSwap now applies them
## through a single switch (`actor_outline`) that cannot be half-set.
##
## ⭐THE VIEW MODEL IS THE THIRD SHAPE OF THAT CONTRACT — excluded by LAYER, not by stamp. The gun draws on
## ViewModelCamera.VIEW_MODEL_LAYER, the mask camera culls that layer, and the ink is discarded over the
## weapon on purpose — so GunVisuals' hull rim is the gun's ONLY outline and it has to be a visible width
## on its own. Until 2026-08-18 it was not: GunVisuals.outline_width shipped 0.02 (a leftover from the old
## world-space outline shader; ~1 visible pixel per unit in the screen-space one, so 5 rim pixels on the
## whole pistol) and the weapon had no outline at all. The day this pass took the ink off it was the day
## that became visible. Pinned to NPC parity (2.0) in test_ink_outline.gd — see the export's own note.
##
## THE MASK IS A SECOND SCENE RENDER — KEEP IT CHEAP. Every hull-rimmed thing in the level carries the
## mask layer (each NPC body part, each Throwable prop, the gibs, the view model), and each of those
## draws base + hull overlay + flash next_pass. Rendering that set a second time at the frame's full
## internal resolution roughly DOUBLES the per-object cost of a prop-heavy level — which is exactly what
## shipped first and what made the game crawl. Most of that was waste: the shader reads this texture's
## ALPHA as a coverage field and nothing else, so the pass needs no anti-aliasing, no shadows, no
## lighting, no supersample and no mesh detail, and `_build_mask_pass` strips a SubViewport's defaults
## down accordingly. The one saving that is NOT free is the mask's RESOLUTION — see `mask_resolution`.
##
## SUPPRESSION IS SIZED OFF THE LINE, NEVER OFF THE MASK. The shader kills ink within half a line-width
## of an actor's silhouette — the line that would otherwise straddle it, which is the doubled outline
## the hull already owns — and not one pixel past that. An earlier version scaled that window off the
## mask's TEXEL SIZE instead, and at a half-resolution mask it erased world ink 3 px out from every
## actor: a bare ring that does not shrink with distance, so a far-off NPC sat in a void bigger than
## itself and you could pick people out by it. `filter_linear` on the mask is what makes the honest
## version possible — it turns a blocky stencil into a coverage field whose 0.5 crossing IS the true
## silhouette, sub-texel. Nothing resolution-derived is pushed to the shader, deliberately.
##
## ⭐⭐ THE MASK KNOWS HOW FAR AWAY ITS ACTORS ARE (2026-08-13). For most of this pass's life it did not,
## and that was its worst artefact: the mask camera renders ONLY actors, so nothing in that viewport could
## occlude them, and an NPC standing behind a wall stamped its full silhouette into the mask anyway and bit
## that shape out of every ink line it overlapped. On long straight lines — stair nosings, the corners of
## buildings — you got clean circles punched through the ink wherever somebody stood on the other side. It
## read as a heat sense, not an outline. And it was never about NPCs: every hull-rimmed thing on the mask
## layer did it, thrown and carried props included.
##
## The fix is the depth-compare mask the two failed attempts below both pointed at. `_build_mask_pass`
## parks a second quad INSIDE the mask viewport (resources/shaders/actor_mask_resolve.gdshader) which
## reads that viewport's own depth buffer and stamps it into the mask's colour: G = the actor's distance,
## log-encoded, B = "this pixel's depth is mine", alpha = coverage as before. ink_outline.gdshader then
## compares that against the depth of what the main pass actually draws at the same pixel, and an actor
## that turns out to be behind the world stops suppressing ink there. Per-pixel, so a body half behind a
## railing is handled a pixel at a time rather than all-or-nothing.
##
## It is built to FAIL TOWARD THE OLD BEHAVIOUR, never toward a doubled outline: every case the resolve
## pass cannot vouch for (a transparency-faded prop, a rim wider than the dilation, an actor past the
## encoding window) keeps the unconditional suppression it always had. See actor_coverage() in the shader.
##
## TWO THINGS TRIED FIRST, both recorded so nobody rebuilds them:
##  * STENCIL on this quad (a stencil write on the hull in outline.gdshader, `compare_not_equal` here).
##    It compiles, errors nowhere, and does NOTHING: the quad is `depth_test_disabled`, which drops the
##    depth-stencil attachment for that pipeline, so the compare never runs — every actor came back
##    double-inked. Do NOT re-try plain stencil on this quad.
##  * A CPU occluded-actor cull — see the block further down, which is worth reading before touching any
##    of this: it did not merely fail, it broke the world ink outright.
##
## WHY THIS AND NOT THE INVERTED HULL: resources/shaders/outline.gdshader (the hull) stays what it has
## always been — the GAMEPLAY highlight: a Throwable's hover rim, an NPC's combat outline, the look-at
## talk highlight. It is deliberately NOT extended to the world. A hull needs a second draw call per
## mesh, fights ps1_applier for the material slot on every piece of level geometry, shatters on the
## UNWELDED func_godot brush mesh (see ps1.gdshader's SEAM WARNING), and paints the screen black when
## you stand inside an extruded room. Borderlands' own ink was a post-process edge filter, which is
## what ink_outline.gdshader is. The long form of all of this lives in that shader's header — read it
## before changing the technique.
##
## AUTHORING: every knob below is live. Drop the node in, press play, and tune in the remote inspector;
## the values are pushed the frame they change, no restart. The two you will reach for first are
## `width_px` (thickness) and `crease_strength` (how much interior line detail there is beyond bare
## silhouettes). `enabled` off costs nothing — the quad is hidden, so it is not drawn at all.
##
## PLAYER CONTROL: `Settings.ink_outline_intensity` (Options -> Video -> Ink Outline, 0..100%) scales
## the shipped look LIVE, the ps1_warp_intensity idiom — 100% is exactly what is authored here, lower
## values fade AND thin the line, and 0% hides the quad entirely so the frame renders clean. Polled
## each frame, so the slider bites immediately with no level reload. The mapping is the pure,
## unit-tested `ink_params()` below.

const INK_SHADER: Shader = preload("res://resources/shaders/ink_outline.gdshader")
## The mask viewport's own resolve pass — turns that viewport's depth buffer into the coverage+depth
## field the ink shader samples. See the class doc and the shader's header.
const MASK_RESOLVE_SHADER: Shader = preload("res://resources/shaders/actor_mask_resolve.gdshader")
## Render layer (bit value, editor layer 20) reserved for the actor-exclusion mask. Actor meshes get it
## OR-ed onto their layers by the overlay walks (see the class doc); the main camera's default cull_mask
## includes all 20 layers, so the extra bit never changes what the player sees — it only registers the
## mesh with the mask camera below. Layers actually in use elsewhere: 1 (world), 2, 3 (value-4 = the
## view model, ViewModelCamera.VIEW_MODEL_LAYER); 20 is far clear of all of them.
const ACTOR_INK_MASK_LAYER: int = 1 << 19
## ⭐ Render layer for the mask's own RESOLVE QUAD, and the reason it is bit 21 rather than a tidy 20 is
## the single sharpest edge in this file. The mask SubViewport SHARES the main World3D (it has to — that
## is how its camera sees the same actors), and a Node3D's visual instance registers with the world of
## the viewport it sits in. So a MeshInstance3D parented under the mask camera is in the MAIN scenario as
## well, and the MAIN camera would happily draw it: a full-screen quad of raw depth-encoding colour
## pasted over the game. Camera3D.cull_mask defaults to 0xFFFFF — the twenty layers the editor exposes —
## so a bit ABOVE those is invisible to every ordinary camera by construction, while the mask camera opts
## in explicitly. `_ready` also clears it from the host camera defensively, which is free and idempotent
## because nothing else in the project uses this bit. Verified against the driver, not assumed.
const MASK_INTERNAL_LAYER: int = 1 << 20
## The window (metres) the mask's 8-bit depth channel is log-encoded across — pushed to BOTH shaders from
## here so the encoder and the comparer cannot drift apart. Deliberately the game's own scale rather than
## the camera's near/far: a 0.05..4000 window would spend a third of its precision on distances no actor
## is ever at, and the encoding's resolution is what sets how thin a wall can be before an actor behind it
## stops registering as hidden. The resolve pass packs this window across TWO channels (~0.01% of the
## distance per step); on one channel it was ~3%, which alone kept anyone under a metre behind cover from
## registering.
const MASK_DEPTH_NEAR: float = 0.1
const MASK_DEPTH_FAR: float = 300.0
## Frustum culling runs on the node's REAL AABB (a 1x1 quad) long before the vertex shader gets to
## expand it to fill the screen, so without a generous margin the effect blinks out whenever that
## little quad leaves the frustum. Large enough to be unconditional, well under the engine's 16384 cap.
const CULL_MARGIN := 4096.0
## Automatic-LOD bias for the mask pass (Viewport.mesh_lod_threshold, in pixels of that viewport). The
## engine default 1.0 keeps meshes at full detail; the mask only needs a SILHOUETTE that is then tested
## against a `> 0.05` alpha threshold, so it can drop to the coarsest LOD a mesh ships long before the
## main pass would. Costs nothing to raise — a mesh with no LODs authored simply ignores it.
const MASK_LOD_THRESHOLD := 8.0
## Floor on either axis of the mask viewport, so a silly `mask_resolution` (or a one-frame degenerate
## window size) can never ask the renderer for a zero-area render target.
const MASK_MIN_SIZE := 2

## Master switch. Off = the quad is hidden and never drawn; the frame renders with no ink at all.
@export var enabled: bool = true

@export_group("Line")
## Ink colour. Black is the Borderlands look; a very dark blue/brown reads softer if pure black
## fights the posterise. Alpha multiplies into the final line opacity.
@export var ink_color: Color = Color(0.0, 0.0, 0.0, 1.0)
## Authored line opacity at 100% intensity. Below 1.0 the ink sits as a tint over the art rather than
## a hard outline; the player's Options dial scales THIS value, it does not replace it.
@export_range(0.0, 1.0, 0.01) var opacity: float = 1.0
## Line thickness in pixels OF THE 3D BUFFER — which is not the window. The 396x216 window x viewport
## stretch 0.5 gives a 792x444 buffer, and rendering/scaling_3d/scale 2.0 renders that at 1584x888. So
## 2.0 here is about ONE pixel of the image the player actually sees, and the shipped 3.0 about one and
## a half. 3.0 was picked by eye off a render probe: 2.0 is legible but reads as a tasteful technical
## edge, and Borderlands' ink is bolder than tasteful. Constant in screen space by construction — a
## distant wall's line is exactly as thick as a near one's, which is the comic look.
@export_range(0.0, 8.0, 0.1) var width_px: float = 3.0

@export_group("Silhouettes")
## How different a neighbouring pixel's depth must be, as a FRACTION of the reference depth, to count
## as an object boundary. Relative rather than absolute so a 2 cm step still reads at arm's length
## while the far skyline does not collapse into a black smear. Lower = more lines, and eventually
## noise on anything at a glancing angle.
@export_range(0.001, 0.5, 0.001) var depth_threshold: float = 0.035
## Floor (metres) on the depth that threshold is measured against. Without it the view model, 20 cm
## from the lens, gets a sub-millimetre threshold and every panel gap on the gun becomes a line.
## RAISE to calm the gun down, LOWER to let it show more of its own detail. Silhouette-only knob —
## the distance fade below still uses true depth, so this cannot make near ink fade out.
@export_range(0.01, 4.0, 0.01) var min_depth_reference: float = 0.35
## Relief for surfaces seen almost edge-on (the floor ahead of you), whose depth changes hugely from
## pixel to pixel with no edge actually present. The threshold is widened by how far the surface is
## turned away from the lens, capped here. Raise if the ground carpets itself in false lines; lower
## if genuine edges on steeply-angled surfaces are going missing. The floor/wall junction is NOT this
## knob's business — two touching surfaces have no depth step at all, so that line comes from creases.
@export_range(1.0, 32.0, 0.5) var grazing_tolerance: float = 8.0
## ⭐⭐ CONTACT MERGE: how far apart (METRES) two surfaces must be at an edge before that edge counts as a
## real silhouette rather than a JOIN between two pieces that are TOUCHING. 0 = off (every depth step
## draws a line, the pre-2026-08-18 behaviour).
##
## THE ASK: ink the outside of a solid, not the joins inside it — "not where the two actually are
## touching". A level built from boxes is nothing but pieces that meet: a step on a step, a slab on a
## wall, a kerb against the road. The silhouette term drew the boundary at every one, so a flight of
## stairs read as a stack of separately outlined slabs rather than one stepped solid.
##
## HOW: at an edge pixel the two taps that found the edge land on two different surfaces, and the 3D
## distance between those points IS how far apart the pieces are along the view ray — a step's far
## surface begins at the foot of its riser, so the gap is the riser height (0.5 m on this level) however
## grazing the view; a box on the floor gives its own height; a facade against one 10 m behind gives 10 m;
## the sky gives the far plane and can never merge. Closer than this = one solid, and the shoulder runs
## to 2x so a piece near the threshold fades instead of popping as the camera moves.
##
## ⭐ A LOOK KNOB WITH TEETH. The shipped 1.0 merges this level's authored 0.5 m module (stairs, kerbs,
## slab-on-slab) and keeps everything past ~2 m. RAISE and genuinely separate things start reading as one
## mass — a crate a metre in front of a wall loses the line between them, and a doorway stops reading as
## a hole. LOWER (or 0) to get every silhouette back. It only ever REMOVES lines, and only from the DEPTH
## term — a crease at a contact line is [concave_crease_strength]'s business, and the two together are
## what make a box-built level read as single solids.
@export_range(0.0, 8.0, 0.1) var contact_merge_m: float = 1.0

@export_group("Creases")
## The interior lines: where two surfaces meet at an angle but are flush in depth — wall corners, the
## floor/wall junction, the facets of a prop, the panels of a gun. 0 = bare silhouettes only, which is
## a cleaner and cheaper look but much less Borderlands.
@export_range(0.0, 2.0, 0.05) var crease_strength: float = 1.0
## How sharp a normal change has to be before it draws. Higher = only hard corners survive; lower
## starts finding the shading detail on curved and low-poly surfaces, which reads as grime.
@export_range(0.05, 2.0, 0.01) var crease_threshold: float = 0.4
## ⭐⭐ SEAM MERGE: the narrowest feature, in pixels of the 3D buffer (the width_px unit — the buffer is
## twice the 792-wide screen), that still earns a crease line. The confirming taps sit exactly this far
## either side of the pixel, so a face narrower than this on screen cannot hold one and its creases merge
## into the surface around it. 0 = off, the pre-2026-08-18 behaviour where any normal change at all drew
## a line.
##
## THE ASK THIS ANSWERS: level geometry built from several boxes should ink as ONE solid, not as its
## parts. Mostly it already did — a screen-space pass cannot see an interior face, and two boxes sharing
## a face exactly have no depth step and no normal change between them, so a flush or interpenetrating
## join comes out as a single clean silhouette (measured, on a synthetic scene AND on the shipped map's
## flush floor/roof brush joins). The case that broke it is a box a couple of CENTIMETRES out of line:
## that leaves a sub-pixel sliver of perpendicular face along the join, which is invisible in the art and
## a full 90-degree corner to a crease term that had no idea how big a feature was. One surface came away
## split by a faint dotted line that crawls with the camera. On the shipped map that is the 6 cm plank
## trims over the yard doors seen edge-on (470 px of dashed line, all gone at the default) and a 4 mm
## decal-plate brush on the tower; on hand-placed blockout it is every join.
##
## The fix asks the only question that separates the two: does the normal change PERSIST at a wider
## radius? A real corner still has two different surfaces either side of it several pixels out; a
## misalignment sliver has the same surface on both sides. So the crease is re-measured wide (two crosses,
## the weaker wins, as a RATIO of the narrow result — an absolute second threshold dimmed every shallow
## crease) and may only ever be reduced by the answer. It is screen-space on purpose — a 4 cm kerb
## underfoot is many pixels across and keeps its line, the same kerb at 40 m is not and loses it, which is
## the right answer at both ends. The documented collateral, measured: a reveal, trim or stair tread that
## projects narrower than this loses its INTERIOR lines at that distance (its silhouette stays), and it
## comes back as you approach.
##
## RAISE to merge sloppier joins (and to drop more fine detail into flat shading at distance); set 0 to
## get every line back. ⭐ Values between 0 and width_px are floored to width_px in the shader — closer in
## than that the wide taps sit inside the narrow cross's own footprint and only thin real lines — so the
## only true "off" is exactly 0. This is the one term here that only ever REMOVES lines, so it ships at
## the smallest reach that clears the artefact rather than the largest that looks tidy.
@export_range(0.0, 16.0, 0.5) var crease_min_feature_px: float = 4.0
## ⭐ CONCAVE creases — the floor/wall junction, the inside corner of an L, the line where a slab sits on
## a wall, a tread against its riser — versus CONVEX ones (a building's outside corner, a step's nosing,
## the top of a wall). Both are 90-degree normal changes and normals alone cannot tell them apart; the
## shader reads which way the surfaces FOLD from the depth taps it already has. On a level built from
## boxes every "junction between two pieces" is a concave crease, so this is the dial for how much the
## pieces read as ONE solid: 1.0 draws every junction (the shipped look, unchanged); 0.0 draws only convex
## edges and silhouettes, so a slab on a wall or a step against a riser shows no line where they meet and
## the compound reads as one shape — the user's sketch. Note it is the SAME kind of crease as the
## floor/wall line and the inside corner of an L, so those go with it; try 0.4-0.6 for junctions that are
## present but lighter than edges. Live, like every knob here.
@export_range(0.0, 1.0, 0.05) var concave_crease_strength: float = 1.0

@export_group("Distance")
## Ink eases out across this window (metres of view depth) so the far skyline does not turn to mush
## once post_process.gdshader's pixelation collapses it. Roughly tracks ps1.gdshader's own far fade
## and the camera's 30 m DOF, so the far field softens once instead of in three separate steps. In a
## FOGGED level this window is only the backstop — fog_match below is what actually pulls the ink in
## to the distance the player can genuinely see.
@export_range(0.0, 500.0, 1.0, "or_greater") var fade_start: float = 40.0
@export_range(0.0, 1000.0, 1.0, "or_greater") var fade_end: float = 90.0
## How strongly the ink respects the level's FOG. The levels are lit almost entirely by volumetric fog
## (density ~0.05/m), which swallows geometry contrast as exp(-density * distance) — but the ink quad
## renders fog_disabled at 1 m from the lens, so the engine's fog can never dim the lines itself.
## Each frame the live WorldEnvironment's volumetric (+ classic, if enabled) fog density is read, scaled
## by THIS knob, and pushed as a matching per-metre extinction on the ink — so a line loses contrast at
## exactly the rate the surface it sits on does, instead of floating crisp over buildings the fog has
## already eaten. 1.0 = track the fog's own density; >1 pulls ink in tighter than the fog (a deliberate
## "only ink what's near" look); 0 = ignore fog entirely (the pre-fix behaviour).
@export_range(0.0, 4.0, 0.05) var fog_match: float = 1.0

@export_group("Advanced")
## Distance (metres) in front of the camera the quad is PARKED. It has nothing to do with coverage —
## the shader writes clip space directly, so the quad fills the screen from anywhere — and everything
## to do with TRANSPARENT SORT ORDER, which Godot resolves by view-space distance. At ~1 m the ink
## draws after world transparents (so it inks over them) but before anything closer to the lens, which
## leaves the muzzle flash and other view-model effects painting on TOP of the ink where they belong.
## Push it out to ink over near effects too; pull it in to let more of them sit above the line work.
@export_range(0.05, 10.0, 0.05) var sort_distance_m: float = 1.0
## Resolution the ACTOR MASK renders at, as a fraction of the main 3D buffer — the effect's one real
## performance knob, and the one thing here you can SEE if you push it too far. The mask is a second
## scene render over every hull-rimmed actor and prop in view, and the shader reads only coverage and the
## resolve pass's encoded depth, never its colour as colour, so full resolution buys nothing per se; it costs a quarter of the pixels of a
## full-size mask, and a SIXTEENTH of what the first build spent (that one also inherited the project's
## rendering/scaling_3d/scale 2.0 supersample, which `_build_mask_pass` now explicitly refuses).
##
## WHAT LOWERING IT ACTUALLY COSTS: a wider band of suppressed ink hugging every actor — the HALO.
## Some band is unavoidable and correct: the edge detect would otherwise draw a line straddling the
## actor's silhouette, which is the doubled outline the hull already owns, so the ink has to stop half
## a line-width short. That floor is ~1 px of the 792-wide screen buffer. Anything past it is waste,
## and it reads badly — a bare ring that does not shrink with distance, so a far-off NPC sits in a void
## far bigger than itself and you can spot people by it.
##
## Measured (probe: ink-loss bounding box vs the actor's own footprint, against a reference frame with
## the mask off) — 1.0 -> 1 px, 0.5 -> 2 px, 0.25 -> 2 px but it starts UNDER-suppressing, letting ink
## back onto actors. So 1.0 ships: it is the floor, and the pixels it costs are not where the effect
## was expensive (that was the inherited 2.0 supersample `_build_mask_pass` refuses — 1.0 here is still
## a QUARTER of what the first build rendered). Drop to 0.5 for another 4x if you need the frames and
## can live with 2 px. Live — resizes on the next frame.
@export_range(0.125, 1.0, 0.005) var mask_resolution: float = 1.0

@export_group("Actor occlusion")
## Whether a masked actor has to be VISIBLE to suppress the world's ink. On (the shipped behaviour) an
## actor standing behind a wall stops biting its silhouette out of the ink lines in front of it — without
## it, long straight lines come away with person-shaped circles punched through them wherever somebody is
## standing on the other side, which reads as sensing people through walls. Off restores the pre-2026-08-13
## behaviour (every masked actor suppresses ink whether or not it can be seen) — the escape hatch if the
## comparison ever misbehaves, and the A/B for judging it.
@export var occlusion_aware_mask: bool = true
## How much NEARER the world has to be, as a FRACTION of the distance, before the actor behind it stops
## suppressing ink, in the depth encoding's own units. This was the ceiling on the whole test until the
## depth went to two channels: at one 8-bit channel a step was ~3% of the distance, so an NPC had to stand
## a FULL METRE behind a wall at 6 m before anything happened, and hidden NPCs kept showing faintly
## indoors. With ~0.01% precision and the tight gather cancelling sampling noise, a gap sweep
## (`scripts/tools/__ink_gap_probe.gd`) puts detection at **2 cm of clear air at 6 m** with this value.
## LOWER buys nothing measurable — the sweep is flat below here. HIGHER goes back to leaving a halo
## around actors tucked close behind cover.
@export_range(0.0005, 0.2, 0.0005) var mask_occlusion_bias: float = 0.003
## ⭐ How far (in pixels of the ink's own 3D buffer) to look for the body's depth when a covered pixel has
## none of its own. That is the hull RIM: outline.gdshader assigns ALPHA inside a branch, which flags the
## whole material `uses_alpha` and puts it in the TRANSPARENT pass, and transparent materials write no
## depth — so an actor's rim reaches the mask's COVERAGE but not its DEPTH. Left unresolved, that ring
## keeps its ink suppressed while the body's is released, and a hidden actor punches an OUTLINE of itself
## through the world's lines instead of a solid hole ("an O shape around it").
##
## ⭐⭐ WHY THE SEARCH LIVES IN THE INK SHADER AND NOT IN THE RESOLVE PASS. The resolve pass could only
## spread depth outward by ALSO spreading the mask's alpha — and the mask's alpha is coverage, and coverage
## is suppressed ink. Every pixel of ring it repaired bought a pixel of bare halo around every VISIBLE
## actor, which is the artefact this pass has already been burned by twice. Searching here reads a wider
## neighbourhood and claims not one extra pixel of the frame, so the radius is generous for free.
##
## Must out-reach the widest rim ON SCREEN. The rim is `outline_width * 2` pixels of the MASK viewport,
## and the mask renders at half this buffer's resolution, so the project's widest authored rim (2.0)
## spans 8 px here. 12 leaves margin for a designer who nudges one up.
@export_range(0.0, 48.0, 1.0) var mask_rim_search_px: float = 12.0

## ⭐⭐ TRIED AND FULLY REMOVED 2026-08-13 — a CPU occluded-actor cull (raycast camera->actor, then strip
## ACTOR_INK_MASK_LAYER off a hidden actor's meshes) meant to kill the soft-wallhack tell above. It did not
## merely fail: it BROKE THE WORLD INK, and how it broke is worth keeping so nobody rebuilds it.
##
##   The PLAYER is a mask owner. player.gd's _enter_tree falls back to `mesh = gun_mesh`, so
##   Character._apply_overlay_to_meshes stamps the view-model meshes, and walking up from those to the
##   nearest CollisionObject3D lands on the Player CharacterBody3D. The cull then OR-ed the mask bit onto
##   every VisualInstance3D DESCENDANT of that owner — and THIS NODE is a descendant of the Player
##   (Player -> Head/camera_rig -> ScreenShake -> Camera3D -> InkOutline). So the ink quad was rendered INTO
##   the very mask SubViewport whose texture it samples: a feedback loop writing the quad's own edge detect
##   into the coverage field the main pass discards on, erasing world ink in bands around every actor and the
##   gun. Permanent from frame 2, because the verdict was memoised and never re-evaluated.
##   The same wide walk also stamped Decals and Light3Ds (both ARE VisualInstance3D — the four real stampers
##   only ever walk MeshInstance3D), breaking the no-lights-in-the-mask invariant _build_mask_pass relies on.
##   And the sample heights were measured from the CollisionObject3D origin, which on enemy.tscn sits
##   mid-capsule, so two of three rays probed empty air ABOVE the actor — and an empty raycast was read as
##   "visible", so it barely culled anything real either.
##
## RULES for whoever builds the depth-compare mask that is still the honest fix: never walk descendants of a
## mask owner (the camera rig — and this quad — hang off the Player); never read an empty raycast as proof of
## visibility; measure actor sample points from the COLLISION SHAPE, never the node origin.

var _material: ShaderMaterial = null
var _settings: Node = null                  ## the Settings autoload (null in a bare harness -> full effect)
## The level's RAW fog density (per metre, before fog_match scales it), re-read each refresh from the
## live WorldEnvironment — levels swap on LevelDoor transitions and StarSky repaints the env, so a
## cached value would go stale. 0.0 off-tree / no environment / fog off (a bare harness inks unfogged).
var _fog_sigma: float = 0.0
var _mask_viewport: SubViewport = null      ## actor coverage+depth pass; null until _build_mask_pass runs
var _mask_camera: Camera3D = null           ## camera inside it; culls ONLY the actor + view-model layers
var _mask_resolve_material: ShaderMaterial = null  ## the resolve quad's material (camera_far is pushed live)
## Last uniform set written, so an unchanged frame costs nothing. The `==` below is a genuine VALUE
## comparison (verified on 4.7: Dictionary equality compares contents, recursively, not identity), which
## is what makes comparing a freshly built Dictionary against the stored one the right question to ask.
var _pushed: Dictionary = {}
var _pushed_once: bool = false

func _ready() -> void:
	_settings = get_node_or_null(^"/root/Settings")
	var host := get_parent() as Camera3D
	if OS.is_debug_build() and host == null:
		# Not fatal — the pass still renders wherever it is — but it will edge-detect whatever camera
		# happens to see it rather than the one it was meant for, which is never what was intended.
		push_warning("InkOutline expects to be a child of the Camera3D it inks; parent is %s." % [get_parent()])
	if host != null:
		# Belt and braces on MASK_INTERNAL_LAYER (see that const). A default cull_mask never carries this
		# bit, so this is normally a no-op; it only bites if something hands the camera a hand-written
		# all-bits mask, in which case the resolve quad would paint its raw depth encoding over the frame.
		# Idempotent and side-effect-free — nothing else in the project renders on this layer.
		host.cull_mask &= ~MASK_INTERNAL_LAYER
	# The node's own visual state is OWNED here, not authored: a quad that casts shadows, bounces GI or
	# gets culled would be a bug in every scene it is dropped into, so there is nothing to gain from
	# letting a .tscn disagree. `position` is likewise ours — see sort_distance_m for what it means.
	mesh = QuadMesh.new()
	position = Vector3(0.0, 0.0, -sort_distance_m)
	extra_cull_margin = CULL_MARGIN
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	_material = ShaderMaterial.new()
	_material.shader = INK_SHADER
	material_override = _material
	# ALWAYS, not pausable: under DialogueManager's pause (the game's only one) the camera can still be
	# animated, and a frozen mask would smear stale actor silhouettes over the ink. The per-frame work
	# is pure visual sync — no game state is touched — so running through pause is safe by construction.
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_process(true)
	# Deferred, the ViewModelCamera idiom: find_world_3d() and the viewport size are only reliable once
	# the whole rig has finished entering the tree.
	_build_mask_pass.call_deferred()
	_refresh()

## Build the actor-exclusion pass (see the class doc): a SubViewport SHARING the main World3D whose
## camera culls ONLY the actor-mask + view-model layers, transparent background — so its texture's
## ALPHA is per-pixel "an actor is here", independent of how dark the actor renders. The environment is
## ViewModelCamera's clear-background build (BG_CLEAR_COLOR + fog off): the same godot#84930 lesson —
## a Sky background still draws under transparent_bg and would stamp alpha across the whole mask.
func _build_mask_pass() -> void:
	if not is_inside_tree():
		return  # freed/re-parented before the deferred call landed
	_mask_viewport = SubViewport.new()
	_mask_viewport.transparent_bg = true
	_mask_viewport.world_3d = get_viewport().find_world_3d()
	_mask_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_mask_viewport.handle_input_locally = false
	_mask_viewport.size = _mask_size()
	_strip_mask_viewport(_mask_viewport)
	_mask_camera = Camera3D.new()
	_mask_camera.cull_mask = ACTOR_INK_MASK_LAYER | ViewModelCamera.VIEW_MODEL_LAYER | MASK_INTERNAL_LAYER
	_mask_camera.environment = _build_mask_environment()
	_mask_camera.current = true
	_mask_viewport.add_child(_mask_camera)
	_mask_camera.add_child(_build_resolve_quad())
	add_child(_mask_viewport)
	_sync_mask_camera()
	# Bind ONCE: a ViewportTexture tracks its viewport through resizes, so this never needs re-pushing —
	# and it deliberately bypasses the _params change-guard (a texture is identity, not a tunable).
	# The SAME texture goes to both samplers on purpose: Godot binds one texture per uniform WITH THAT
	# UNIFORM'S OWN SAMPLER, so `actor_mask` reads it filter_linear as a coverage field while
	# `actor_mask_data` reads it filter_nearest for the depth channels that must not be interpolated.
	var tex := _mask_viewport.get_texture()
	_material.set_shader_parameter("actor_mask", tex)
	_material.set_shader_parameter("actor_mask_data", tex)

## The mask camera's Environment: ViewModelCamera's clear-background build (BG_CLEAR_COLOR + fog off) —
## the same godot#84930 lesson, a Sky background still draws under transparent_bg and would stamp alpha
## across the whole mask — with the TONEMAPPER PINNED.
##
## ⭐ The pin is not tidiness. The mask's depth channel is a number encoded into an 8-bit colour target,
## and the resolve shader pre-compensates for exactly one transfer curve on the way in: the LINEAR
## tonemapper at exposure 1 / white 1, followed by Godot's linear->sRGB target write. A filmic curve, a
## different exposure, glow or the colour adjustments would all re-grade that number, and the failure is
## silent — the comparison downstream just starts answering wrongly and actors flicker back to a doubled
## outline. build_default_environment already leaves these at Environment's defaults when handed a null
## world env; setting them here means a future change to that helper cannot quietly take them away.
func _build_mask_environment() -> Environment:
	var env := ViewModelCamera.build_default_environment(null, Color.BLACK, 0.0)
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	env.tonemap_exposure = 1.0
	env.tonemap_white = 1.0
	env.glow_enabled = false
	env.adjustment_enabled = false
	return env

## The resolve quad: a screen-filling quad INSIDE the mask viewport that reads that viewport's depth
## buffer and stamps it into the mask's colour (see actor_mask_resolve.gdshader). Everything about its
## visual state is owned here rather than authored, for the same reason the ink quad's is.
func _build_resolve_quad() -> MeshInstance3D:
	var quad := MeshInstance3D.new()
	quad.name = "ActorMaskResolve"
	quad.mesh = QuadMesh.new()
	# ⭐ NOT an ordinary render layer — see MASK_INTERNAL_LAYER. `=`, never `|=`: this quad must be on
	# that layer and NOTHING else, or the main camera draws it over the game.
	quad.layers = MASK_INTERNAL_LAYER
	# Parked nearest so it sorts LAST among the mask viewport's transparents, i.e. after every actor —
	# it has to overwrite their colour, not be overwritten by it. Coverage is unharmed: the shader writes
	# ALPHA 0 wherever it has no depth to offer, which under blend_mix leaves that pixel exactly as the
	# actors rendered it.
	quad.position = Vector3(0.0, 0.0, -0.02)
	quad.extra_cull_margin = CULL_MARGIN
	quad.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	quad.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	_mask_resolve_material = ShaderMaterial.new()
	_mask_resolve_material.shader = MASK_RESOLVE_SHADER
	_mask_resolve_material.set_shader_parameter("depth_near", MASK_DEPTH_NEAR)
	_mask_resolve_material.set_shader_parameter("depth_far", MASK_DEPTH_FAR)
	quad.material_override = _mask_resolve_material
	return quad

## Strip a SubViewport down to a COVERAGE pass. Every property here is an engine default that exists to
## make a viewport look good, and the mask is never looked at — the shader reads its alpha as coverage,
## the resolve pass's channels as depth, and throws the rest away. Left at their defaults they made this pass cost about as much as the frame it
## was helping draw, which is what made the game crawl once a level's worth of props carried the mask
## layer. Each line is a deliberate refusal, so a future "why is this not just SubViewport.new()" has an
## answer:
##  * scaling_3d — a SubViewport inherits rendering/scaling_3d/scale from project settings (verified on
##    4.7.1: it reads 2.0 here), so the mask was SUPERSAMPLING 4x. Pinned to 1.0 + BILINEAR so a project
##    that later switches to FSR2 does not hand this pass a temporal upscaler as well.
##  * MSAA / screen-space AA / TAA / debanding — all soften an EDGE, and a soft edge in an alpha mask is
##    a coverage value between 0 and 1 that the threshold rounds off anyway. TAA additionally needs a
##    motion-vector pass and history buffer for a texture nobody ever sees.
##  * positional_shadow_atlas_size — shadow atlases are PER VIEWPORT, so this one allocated its own
##    (2048^2 by default) for lights it cannot even see: Light3D is a VisualInstance3D, so the mask
##    camera's cull_mask excludes every level light along with the level geometry.
##  * occlusion culling — the occluder pass costs CPU to skip draws that are already almost free here.
##  * mesh LOD — see MASK_LOD_THRESHOLD.
func _strip_mask_viewport(vp: SubViewport) -> void:
	vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR
	vp.scaling_3d_scale = 1.0
	vp.msaa_3d = Viewport.MSAA_DISABLED
	vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED
	vp.use_taa = false
	vp.use_debanding = false
	vp.use_occlusion_culling = false
	vp.positional_shadow_atlas_size = 0
	vp.mesh_lod_threshold = MASK_LOD_THRESHOLD

## Track the host camera each frame so the mask lines up 1:1 with the main render — shake, bob, ADS
## zoom and dialogue moves all ride the parent camera's global transform. No CameraAttributes on
## purpose: DOF would soften the mask's alpha edge. Size follows the main viewport (window mode flips).
func _sync_mask_camera() -> void:
	if _mask_camera == null:
		return
	var cam := get_parent() as Camera3D
	if cam == null:
		return
	_mask_camera.global_transform = cam.global_transform
	_mask_camera.fov = cam.fov
	_mask_camera.near = cam.near
	_mask_camera.far = cam.far
	_mask_camera.keep_aspect = cam.keep_aspect
	# Follows BOTH the window (mode flips / resizes) and a live mask_resolution edit, so the knob is as
	# authorable-at-runtime as every other export on this node.
	var want := _mask_size()
	if _mask_viewport.size != want:
		_mask_viewport.size = want
	if _mask_resolve_material != null:
		# camera_far is what tells the resolve pass that an untouched depth texel means EMPTY rather than
		# "geometry at the far plane" — it mirrors the camera every frame because ADS/scope work can move it.
		_mask_resolve_material.set_shader_parameter("camera_far", _mask_camera.far)

func _main_viewport_size() -> Vector2i:
	var vp := get_viewport()
	if vp:
		return Vector2i(vp.get_visible_rect().size)
	return Vector2i(792, 444)  # the project's real screen buffer (396x216 x stretch 0.5) as a fallback

## The mask render target's size for the CURRENT window and mask_resolution.
func _mask_size() -> Vector2i:
	return mask_size(_main_viewport_size(), mask_resolution)

## Pure mask-size mapping, so the resolution policy can be asserted off-tree. Rounds rather than
## truncates (a 0.5 mask of an odd-height window should not lose a row to the floor) and never returns
## a degenerate axis.
static func mask_size(main: Vector2i, scale: float) -> Vector2i:
	var s := clampf(scale, 0.125, 1.0)
	return Vector2i(
		maxi(MASK_MIN_SIZE, int(roundf(float(main.x) * s))),
		maxi(MASK_MIN_SIZE, int(roundf(float(main.y) * s))),
	)

func _process(_delta: float) -> void:
	_refresh()


## Poll the live intensity, fold it into the authored knobs, and push only if something actually moved.
## Cheap enough to run every frame (one value compare) and it is what makes the remote-inspector edits a
## designer makes mid-playtest land on the very next frame without any explicit "apply".
func _refresh() -> void:
	# Outside the change guard below because sort_distance_m governs the node, not a uniform, so it never
	# appears in the pushed set — checked directly to keep it as live as every other knob.
	if not is_equal_approx(position.z, -sort_distance_m):
		position.z = -sort_distance_m
	_fog_sigma = _read_fog_sigma()
	_sync_mask_camera()
	var params := _params(_intensity())
	if _pushed_once and params == _pushed:
		return
	_pushed = params
	_pushed_once = true
	# 0% (or `enabled` off) hides the quad rather than pushing a zero-alpha line: an invisible node is
	# skipped by the renderer entirely, so "off" costs nothing instead of costing a full-screen draw.
	# The mask pass is gated WITH it — no ink, no reason to keep rendering actor silhouettes.
	visible = bool(params["apply"])
	if _mask_viewport != null:
		_mask_viewport.render_target_update_mode = (
			SubViewport.UPDATE_ALWAYS if visible else SubViewport.UPDATE_DISABLED
		)
	if not visible:
		return
	for key in params:
		if key != "apply":
			_material.set_shader_parameter(key, params[key])

## The level's fog density in per-metre extinction terms, read off the live WorldEnvironment (the
## "world_environment" group — the same lookup ViewModelCamera and camera_effects use). Volumetric and
## classic depth fog SUM when both run (co-existing media extinguish independently). This is a fair
## approximation, not radiometry: volumetric fog also scatters light IN (it doesn't just absorb), but
## the perceived contrast loss the ink needs to track decays at ~the transmittance rate, and the whole
## thing sits behind the designer-tunable fog_match anyway. Off-tree or env-less: 0 (no fog, full ink).
func _read_fog_sigma() -> float:
	if not is_inside_tree():
		return 0.0
	var we := get_tree().get_first_node_in_group(Groups.WORLD_ENVIRONMENT) as WorldEnvironment
	if we == null or we.environment == null:
		return 0.0
	var env := we.environment
	var sigma := 0.0
	if env.volumetric_fog_enabled:
		sigma += env.volumetric_fog_density
	if env.fog_enabled:
		sigma += env.fog_density
	return maxf(sigma, 0.0)

## The live effect strength 0..1: the player's Options dial, gated by this node's own `enabled`.
func _intensity() -> float:
	if not enabled:
		return 0.0
	if _settings == null:
		return 1.0  # no Settings autoload (a bare test / harness) -> the authored full effect
	# Per-frame autoload read via .get() + null-guard (reimport-safe), not a direct property access.
	var v: Variant = _settings.get(&"ink_outline_intensity")
	return clampf(float(v) if v != null else 1.0, 0.0, 1.0)

## Pure mapping from the player's intensity dial (0..1) to the two uniforms it governs. t=1 is exactly
## the authored look; lower t fades the ink AND thins it, because opacity alone would leave a grey band
## that the posterise downstream turns muddy, whereas a thinner still-black line stays crisp all the way
## down. t<=0 means "don't draw at all". Static + pure so it can be asserted off-tree.
static func ink_params(base_opacity: float, base_width_px: float, t: float) -> Dictionary:
	var tt := clampf(t, 0.0, 1.0)
	if tt <= 0.0:
		return {"apply": false, "ink_opacity": 0.0, "width_px": 0.0}
	return {
		"apply": true,
		"ink_opacity": clampf(base_opacity, 0.0, 1.0) * tt,
		"width_px": maxf(base_width_px, 0.0) * (0.5 + 0.5 * tt),
	}

## The full uniform set for the current intensity: the intensity-scaled pair from ink_params plus the
## authored knobs, which pass through untouched. Keyed by the shader's own uniform names, so _refresh
## can push it generically and a renamed uniform fails in one place.
func _params(t: float) -> Dictionary:
	var scaled := ink_params(opacity, width_px, t)
	if not scaled["apply"]:
		return scaled
	scaled["ink_color"] = ink_color
	scaled["depth_threshold"] = depth_threshold
	scaled["min_depth_reference"] = min_depth_reference
	scaled["grazing_tolerance"] = grazing_tolerance
	scaled["contact_merge_m"] = contact_merge_m
	scaled["crease_strength"] = crease_strength
	scaled["crease_threshold"] = crease_threshold
	scaled["crease_min_feature_px"] = crease_min_feature_px
	scaled["concave_crease_strength"] = concave_crease_strength
	scaled["fade_start"] = fade_start
	scaled["fade_end"] = fade_end
	scaled["fog_extinction"] = _fog_sigma * fog_match
	# True only once the mask pass exists, so the shader never samples an unbound mask (off-tree /
	# pre-deferred-build frames ink everything, actors included, for at most one frame at startup).
	scaled["use_actor_mask"] = _mask_viewport != null
	# The occlusion test (see occlusion_aware_mask). The encoding window is pushed from the SAME constants
	# the resolve material gets, which is the only reason the two shaders can be trusted to agree.
	scaled["use_mask_occlusion"] = occlusion_aware_mask
	scaled["mask_depth_near"] = MASK_DEPTH_NEAR
	scaled["mask_depth_far"] = MASK_DEPTH_FAR
	scaled["mask_occlusion_bias"] = mask_occlusion_bias
	scaled["mask_rim_search_px"] = mask_rim_search_px
	# NOTE: the mask's resolution is deliberately NOT pushed. The shader sizes its suppression window off
	# width_px alone (filter_linear makes the mask a sub-texel coverage field), because scaling that
	# window off the mask's texel size is exactly what put a halo around every actor. See the exclusion
	# block in ink_outline.gdshader before reintroducing anything resolution-derived here.
	return scaled
