class_name InkOutline
extends MeshInstance3D

## @system Ink Outline
## @seam A screen-filling quad childed to a Camera3D; ink_outline.gdshader edge-detects that camera's DEPTH + NORMAL_ROUGHNESS buffers to ink the WORLD, while actors (NPCs / props / gibs / corpses / the view model — everything wearing a tint RING) are excluded per-pixel via a coverage+depth mask SubViewport fed by the ACTOR_INK_MASK_LAYER render-layer stamp, and get their own outline from the ring pass instead.
## @risk THE RING AND THE MASK STAMP ARE ONE CONTRACT. Actor exclusion rests on the ACTOR_INK_MASK_LAYER stamp riding the overlay walks (Character._apply_overlay_to_meshes / NpcOutline.apply_part_overlays / Throwable._setup_overlay_chain / body_part_gib strip / BodyModelSwap._apply_actor_outline / ExplosionMesh._ready) while apply_tint rides the SAME walks — stamp without a ring and the thing has NO outline at all (the player's own first-person body until 2026-08-15, every explosion and hit spark until 2026-08-16); ring without a stamp and the world's ink draws a second line beside it (the doubled-outline complaint). Neither fails loudly.
## @risk The mask viewport SHARES the main World3D, so anything visual parented inside it is registered with the MAIN scenario too and the main camera would draw it; the resolve quad only stays invisible because it sits on MASK_INTERNAL_LAYER, a render bit above the 20 a default cull_mask carries. Give it an ordinary layer and it paints its raw depth encoding over the whole screen.
## @risk The mask's depth channel is a NUMBER encoded in an 8-bit sRGB colour target — it survives only because the resolve shader pre-compensates for that transfer and the mask camera's Environment is pinned to the LINEAR tonemapper. A filmic tonemap, an exposure change, glow or colour adjustments on that Environment all corrupt it silently, and the symptom is actors flickering back to a doubled outline.
## @risk A tint duplicate is a CHILD MeshInstance3D on ACTOR_TINT_LAYER wearing one shared material whose identity rides an instance uniform, and every mesh walker in the project has to skip it on TINT_DUP_META. A walker that forgets (or a layer ASSIGNMENT that moves it onto an ordinary camera) paints ink_tint.gdshader's raw log-depth bytes on screen as moving yellow/green stripe bands — no error, no failing test, just stripes.
## @risk The duplicate SNAPSHOTS its host's `mesh` (a plain property with no change notification), so any site that reassigns or CLEARS a ringed MeshInstance3D's mesh must call InkOutline.sync_tint_mesh on it — WeaponModelSwapper hides the rig's placeholder pistol that way and left a permanent ghost outline of it floating by the player's hand. Nothing errors; a shape simply hangs in the frame around geometry that is gone.
## @risk The quad is culled by its real AABB before the vertex shader can fill the screen, so losing extra_cull_margin makes the whole effect vanish at certain camera angles rather than fail loudly.
## @risk The mask is a SECOND scene render — it costs a full extra pass over every masked actor/prop. It is deliberately stripped to coverage-only (no AA/TAA/shadow atlas, coarse LOD); re-enabling any of that, or letting it inherit the project's 3D supersample again, doubles the frame cost of a level full of props with no visual gain.
## @risk The ink's suppression window must be sized off width_px, NEVER off the mask's resolution — scaling it off the mask texel erases world ink several px out from every actor, a distance-invariant bare halo you can spot people by. Nothing MASK-resolution-derived may reach the shader (the native_scale() factor _params folds into the px-unit uniforms is INK-buffer-derived — the buffer VIEWPORT_SIZE measures — and is required, not banned); mask_resolution below 1.0 widens that band and is the one saving here that is not free.
## @risk If the Forward+ depth prepass is ever disabled the normal buffer stops filling and the CREASE lines quietly disappear, leaving silhouettes only — no error, just fewer lines.
## @risk The contact merge (contact_merge_m) deletes a real SILHOUETTE whenever the surface behind it is nearer than the threshold, which is exactly what makes a stack of slabs read as one solid — and also what makes a crate parked against a wall, a low ledge, or a doorway into a shallow alcove lose the line that said they were separate things. It is measured in world metres, so it does NOT relax with distance the way every other term here does. Nothing errors; the frame just reads flatter.
## @risk The seam merge (crease_min_feature_px) is the ONE crease term that only ever REMOVES lines, and it decides by screen-space width alone: raise it and small real features (a reveal, a trim, a stair tread at distance) silently lose their interior lines while their silhouettes stay — nothing errors, the world just reads flatter far away, and a tread that projects narrower than the reach loses its line and gets it back as you approach. It does not touch the depth term, so a genuine gap between two pieces still draws. concave_crease_strength below 1 removes the floor/wall junction and every inside corner along with the slab-on-wall lines it is aimed at — they are the same crease.
## @test res://tests/test_ink_outline.gd
## Borderlands-style black ink outline, as a DROP-IN: child one of these to any Camera3D and every
## surface that camera renders gets the same screen-space black line — EXCEPT the actors, which are
## excluded per-pixel via the actor mask below and outlined by THIS node's second pass instead: the
## screen-space tint RING (see ACTOR_TINT_LAYER / apply_tint). The WORLD is what the edge detect inks;
## everything that moves is ringed. There is nothing to author per mesh and nothing to keep in sync.
##
## ⭐⭐ ONE TECHNIQUE, TWO PASSES, AND AS OF 2026-08-27 NOTHING ELSE. The inverted-hull shell
## (resources/shaders/outline.gdshader) that used to own actors, props, corpses, the look-at hover and
## the view model is DELETED. The user's brief was "replace all the shitty existing outlines with the
## new outline shader we added for enemies, this includes view models and everything", and the reasons
## the shell had to go were already all on the record: a constant-screen-width shell's WORLD thickness
## grows with distance until it out-thickens the ~10 cm Lego limbs and shatters into confetti (2026-08-25,
## the NPC retirement); it needs a second draw call per mesh; it fights every other system for the ONE
## material_overlay slot per mesh (which is why the look-at highlight had to stash and restore); and it
## is a TRANSPARENT material, so it writes no depth and left the actor mask with coverage it could not
## place in space (the "O shape" round). The ring has none of those properties: constant PIXEL width at
## any range, one extra raster of a flat duplicate, its own node slot, and opaque.
##
## WHY ACTORS ARE EXCLUDED FROM THE INK (learned the hard way — playtest round 2): an actor's OPAQUE BODY
## is a depth discontinuity like any other, so the edge detect draws a line straddling its silhouette —
## which lands half on the actor's own outline and half on the world, reading as a smeared second outline
## hugging the clean one. It is also the wrong LOOK: the ink's crease/silhouette treatment on small
## organic bodies reads scribbly, and a coloured signal outline (hostile red) got black-ringed on top.
## So the ring owns everything that carries an id and the ink owns the world, and the two never stack.
##
## HOW: everything ringed renders (additionally) on the ACTOR_INK_MASK_LAYER render layer — the
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
## pixel", and a VFX mesh that stamps it without an id is asking for NO line, which is a legitimate
## answer here in a way it never is for an actor.
##
## ⭐THE RING AND THE STAMP ARE ONE CONTRACT, and 2026-08-15 is the case that proves it. The player's own
## first-person body had NEITHER — Character's walk is scoped to `mesh`, and the Player's `mesh` is the
## GunMesh, so the legs/torso/body-arms rig (a sibling subtree childed straight to the Player) was never
## reached. It was not double-outlined; it was outlined by the WRONG SYSTEM, wearing the world's line while
## every NPC beside it wore its own. Note what "just stamp the mask bit" would have done there: removed the
## only outline it had. A new actor path owes BOTH halves, which is why BodyModelSwap applies them
## through a single switch (`actor_outline`) that cannot be half-set.
##
## ⭐THE VIEW MODEL IS THE THIRD SHAPE OF THAT CONTRACT — excluded from the ink by LAYER, not by stamp. The
## gun draws on ViewModelCamera.VIEW_MODEL_LAYER, the mask camera culls that layer, and the ink is
## discarded over the weapon on purpose. Its outline is TINT_ID_VIEW_MODEL, stamped by GunVisuals.dress()
## on the rig and on every swapped-in weapon model.
##
## ⭐⭐ WHY THE RING LANDS ON THE GUN AT ALL, stated precisely because the obvious reading is WRONG. The
## view model is NOT drawn by the main camera: Head._setup_view_model_camera sets ViewModelCamera.enabled
## true unconditionally (the `@export var enabled: bool = false` default is dead for the player — the node
## is code-built, so there is no .tscn override to check), and that pass STRIPS VIEW_MODEL_LAYER from the
## main camera's cull_mask. The gun renders in its own SubViewport with its own cleared depth and its own
## environment, composited over the frame on the HUD layer. The tint camera, meanwhile, clones the MAIN
## camera. The two line up only because the gun camera copies the main camera's transform / fov / near /
## far verbatim and `ViewModelCamera.fov_offset` ships 0.0 — i.e. the two projections are identical BY
## COINCIDENCE OF TUNING, not by construction.
## ⭐ So: give fov_offset a non-zero value and the weapon's ring slides off the weapon, with no error
## anywhere. That export carries the warning, and test_ink_outline.gd pins its default at 0. If you want
## the classic "longer gun" FOV, teach _sync_mask_camera to render the tint pass at the gun camera's fov
## first — which needs a second tint viewport, because one camera cannot hold two projections.
## ⭐ It is also why the ring branch in ink_outline.gdshader exempts id 10 from the occlusion compare: the
## main depth buffer has no gun in it, so the depth behind the weapon would read as "the gun is hidden"
## every time you walk up to a wall.
## (History worth keeping: from 2026-06-03 to 2026-08-18 the gun's hull shipped at outline_width 0.02, a
## metres-era leftover that was ~5 rim pixels on a whole pistol, and the weapon effectively had no outline
## at all. Nobody caught it for two months because there was nothing to compare it against.)
##
## THE MASK IS A SECOND SCENE RENDER — KEEP IT CHEAP. Every ringed thing in the level carries the
## mask layer (each NPC body part, each Throwable prop, the gibs, the view model), and each of those
## draws base + flash next_pass. Rendering that set a second time at the frame's full
## internal resolution roughly DOUBLES the per-object cost of a prop-heavy level — which is exactly what
## shipped first and what made the game crawl. Most of that was waste: the shader reads this texture's
## ALPHA as a coverage field and nothing else, so the pass needs no anti-aliasing, no shadows, no
## lighting, no supersample and no mesh detail, and `_build_mask_pass` strips a SubViewport's defaults
## down accordingly. The one saving that is NOT free is the mask's RESOLUTION — see `mask_resolution`.
##
## SUPPRESSION IS SIZED OFF THE LINE, NEVER OFF THE MASK. The shader kills ink within half a line-width
## of an actor's silhouette — the line that would otherwise straddle it, which is the doubled outline
## the ring already owns — and not one pixel past that. An earlier version scaled that window off the
## mask's TEXEL SIZE instead, and at a half-resolution mask it erased world ink 3 px out from every
## actor: a bare ring that does not shrink with distance, so a far-off NPC sat in a void bigger than
## itself and you could pick people out by it. `filter_linear` on the mask is what makes the honest
## version possible — it turns a blocky stencil into a coverage field whose 0.5 crossing IS the true
## silhouette, sub-texel. Nothing MASK-resolution-derived is pushed to the shader, deliberately (the
## px-unit knobs ARE pushed native_scale()-compensated, but that factor derives from the ink's own
## buffer, never from the mask — see _params).
##
## ⭐⭐ THE MASK KNOWS HOW FAR AWAY ITS ACTORS ARE (2026-08-13). For most of this pass's life it did not,
## and that was its worst artefact: the mask camera renders ONLY actors, so nothing in that viewport could
## occlude them, and an NPC standing behind a wall stamped its full silhouette into the mask anyway and bit
## that shape out of every ink line it overlapped. On long straight lines — stair nosings, the corners of
## buildings — you got clean circles punched through the ink wherever somebody stood on the other side. It
## read as a heat sense, not an outline. And it was never about NPCs: every ringed thing on the mask
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
## pass cannot vouch for (a transparency-faded prop, coverage wider than the dilation, an actor past the
## encoding window) keeps the unconditional suppression it always had. See actor_coverage() in the shader.
##
## TWO THINGS TRIED FIRST, both recorded so nobody rebuilds them:
##  * STENCIL on this quad (a stencil write on the actor material, `compare_not_equal` here).
##    It compiles, errors nowhere, and does NOTHING: the quad is `depth_test_disabled`, which drops the
##    depth-stencil attachment for that pipeline, so the compare never runs — every actor came back
##    double-inked. Do NOT re-try plain stencil on this quad.
##  * A CPU occluded-actor cull — see the block further down, which is worth reading before touching any
##    of this: it did not merely fail, it broke the world ink outright.
##
## WHY AN EDGE FILTER AND NOT AN INVERTED HULL, FOR THE WORLD: a hull needs a second draw call per mesh,
## fights ps1_applier for the material slot on every piece of level geometry, shatters on the UNWELDED
## func_godot brush mesh (see ps1.gdshader's SEAM WARNING), and paints the screen black when you stand
## inside an extruded room. Borderlands' own ink was a post-process edge filter, which is what
## ink_outline.gdshader is. The hull was kept for ACTORS for three months on the strength of being exact
## up close; 2026-08-25 (limb confetti at range) and 2026-08-27 (the user's "replace all the shitty
## existing outlines") retired it there too, and the ring below is what it became. The long form lives in
## that shader's header — read it before changing the technique.
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
## The rendering/scaling_3d/scale every px-unit knob in this file was TUNED against — project.godot's
## authored 2.0, which made the RETRO ink buffer 1584x888 (the "twice the 792-wide canvas" every width
## comment derives from). _px_unit_scale() divides the live supersample by this so a knob keeps its
## authored on-screen fraction under HIGH FIDELITY at any Render Scale. If the project setting is ever
## re-authored, move this with it (and expect every width comment in this file + the shader to drift).
const AUTHORED_SUPERSAMPLE: float = 2.0
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
## Render layer for the OUTLINE ID duplicates (the flat meshes apply_tint parents under every outlined
## mesh in the game) — the same above-the-editor's-20 trick as MASK_INTERNAL_LAYER, so no ordinary
## camera can ever draw them; only the tint camera below opts in. This is the screen-space replacement
## for the retired inverted-hull rim: all of one NPC's parts land in ONE raster silhouette in the tint
## buffer, and the ink shader draws the colored ring around it at constant PIXEL width, so there is no
## shell geometry left to out-thicken a limb and confetti (the 2026-08-25 saga; see
## resources/shaders/ink_tint.gdshader and docs/CURRENT_ARCHITECTURE.md).
## ⭐ ONE BUFFER FOR THE WHOLE GAME, resolved by plain opaque z-test, and the VIEW MODEL is the nearest
## thing in it — the weapon sits ~0.2-0.4 m from the lens while everything else is metres away. The ring
## resolver takes the NEAREST covered tap, so in the ~highlight_width_px band hugging the weapon's
## silhouette an enemy's red ring paints the view model's black instead. That is the correct answer (the
## gun is in front of them, and the hull it replaced painted its own rim over that band too), but it is
## worth knowing before reading it as a bug: a hostile's ring is briefly black where it grazes your gun.
const ACTOR_TINT_LAYER: int = 1 << 21
const TINT_SHADER: Shader = preload("res://resources/shaders/ink_tint.gdshader")

## ⭐⭐ THE META EVERY MESH WALKER IN THE PROJECT KEYS ON to leave a tint duplicate alone. Renaming it
## un-shields TalkHelpers.collect_meshes, BodyPartGib._walk_strip, BodyModelSwap's five raw walkers,
## WorldItem._make_world_renderable, GunVisuals and more — with NO compile error and NO runtime error,
## just the duplicate's raw log-depth bytes appearing on screen as moving yellow/green stripe bands
## (the 2026-08-25 gib report). Treat it exactly like BodyModelSwap's `bms_body_transp` tag.
const TINT_DUP_META: StringName = &"npc_tint_dup"
## Child node name for a tint duplicate. The META is the shield; this is only for get-or-create, so it is
## one name for every consumer (a mesh can carry at most ONE tint id — see the id table below).
const TINT_DUP_NAME := "NpcTintDup"

## --- The look-at hover's BORROW bookkeeping (set_tint_highlight) ------------------------------------
## All three live on the DUPLICATE, never on the source mesh, so they die with it and a mesh walker that
## already shields itself on TINT_DUP_META can never see them.
## The id (+ band blend) the duplicate goes back to when the hover ends — written by every ordinary
## apply_tint, so it tracks a disposition change that happens WHILE you are looking at somebody.
const TINT_BASE_META: StringName = &"npc_tint_base"
## Present while the look-at hover owns this duplicate's colour. apply_tint respects it: it updates the
## base but does not repaint, so a retint under the cursor can never flicker the white off for a frame.
const TINT_HOVER_META: StringName = &"npc_tint_hover"
## Present when the hover CREATED this duplicate (scenery that has no ring of its own — a terminal, a
## car, a vending machine). Those are freed on look-away instead of restored, which is what stops a
## hover from stranding a permanent white ring on the level.
const TINT_HOVER_OWNED_META: StringName = &"npc_tint_hover_owned"

## THE TINT ID SPACE — what a duplicate's `disposition_id` means to ink_outline.gdshader's ring pass.
## 0 = no ring (apply_tint frees the duplicate). Every id below draws its ring at EVERY range: since
## 2026-08-27 the ring is the ONLY outline technique in the game, so an id that went quiet at some
## distance would leave its mesh with no line at all.
##  1..4 DISPOSITIONS (hostile / friendly / companion / neutral-black). The colour blooms from neutral
##      black to the disposition colour as the actor closes (highlight_color_near_m/far_m) — the one
##      family that is distance-aware, because "who is that?" is a question about approach.
##  5..6 WORLD PROPS (rest-black / claimed-blue). Unconditional since the hull was deleted; until then
##      this was the FAR half of a crossfade that handed close range back to the shell.
##  7..8 THE ENGAGED-HOSTILE BAND — the one CONTINUOUS span in the table. A hostile NPC that has
##      LOCKED ONTO THE PLAYER (Perception ALERTED with the player as its live target —
##      NPC.is_alerted_on_player()) is stamped `TINT_ID_HOSTILE_ENGAGED + mix` instead of plain
##      hostile, and the shader floors the close-range bloom by the fraction past 7: full red AT ANY
##      DISTANCE once locked on ("they're shooting at you" must read from across the map), easing back
##      to the distance bloom when the lock breaks. NpcOutline drives the mix 0..1 over
##      NPC.outline_target_fade_s. 7.0 exactly behaves like id 1; nothing may ever stamp past 8.0 —
##      the band's fractional headroom is the whole reason 7..8 are a PAIR and not two ids.
##    9 THE LOOK-AT HOVER (white). Borrowed onto meshes whose id belongs to somebody else — see
##      set_tint_highlight, which stashes the base id and puts it back on look-away.
##   10 THE VIEW MODEL (black): your own weapon and first-person body.
## ⭐ ONE ID PER PIXEL: the ring resolves a single winning tap and one LUT colour, so two duplicates on
## the same mesh would z-fight, not blend. That is exactly why the hover is an id SWAP on the ONE
## duplicate (set_tint_highlight) rather than a second overlay — the invariant is "one duplicate per
## mesh, one id at a time", and every consumer here obeys it by construction.
## ⭐⭐ THE SPAN IS 16 AND IT IS A LITERAL IN THREE FILES — this const, ink_tint.gdshader's
## `clamp(disposition_id, 0.0, 16.0) / 16.0`, and ink_outline.gdshader's `best_id * 16.0`. A shader
## uniform default cannot carry arithmetic (the compile rule this project has been burned by), so they
## cannot share a symbol; test_ink_outline.gd pins all three against each other instead. It was 8 until
## the hull's retirement needed ids 9 and 10.
const TINT_ID_SPAN: int = 16
const TINT_ID_NONE: int = 0
const TINT_ID_HOSTILE: int = 1
const TINT_ID_FRIENDLY: int = 2
const TINT_ID_COMPANION: int = 3
const TINT_ID_NEUTRAL: int = 4
const TINT_ID_PROP_REST: int = 5
const TINT_ID_PROP_CLAIMED: int = 6
const TINT_ID_HOSTILE_ENGAGED: int = 7
const TINT_ID_HOVER: int = 9
const TINT_ID_VIEW_MODEL: int = 10

## Give every visible mesh under `root` a tint duplicate carrying `id` (see the id table above), or
## remove them when `id` is TINT_ID_NONE. Idempotent and cheap to re-call: a duplicate is get-or-created
## by name and its mesh + id are re-stamped every pass, so this doubles as the RESYNC after a model swap
## (BodyModelSwap._rebuild frees the part nodes and their duplicates go with them). Safe off-tree.
## `blend` is the fractional offset INTO a continuous band — meaningful only with
## TINT_ID_HOSTILE_ENGAGED (the 7..8 lock-on fade; see the id table); every discrete id ignores it at
## its default 0.0.
##
## The duplicate is a CHILD of the mesh it mirrors, which buys three things for free: it follows every
## transform, it inherits visibility (a hidden limb correctly leaves the silhouette), and it dies with
## its host. Walkers are shielded by TINT_DUP_META, never by the node name.
##
## ⭐ SKINNED MESHES ARE MIRRORED, not skipped (2026-08-27). They used to be — "a skin-bound duplicate
## needs its own skeleton plumbing, and every ringed body is rigid swapped parts" — and that was true
## until the hull was deleted, at which point the skinned bodies that HAD been leaning on it (Ragdoll's
## corpses, the bare Man.glb fallback body) would have been left with no outline at all. The plumbing is
## two properties: copy `skin`, and re-express `skeleton` as a path from the DUPLICATE (it is a child of
## the mesh, so the source's own relative path would resolve one level short). Resolved after add_child,
## because get_path_to needs both nodes parented; an unresolvable skeleton leaves the duplicate rigid
## rather than throwing, which reads as a ring frozen in the rest pose — visible, and better than none.
static func apply_tint(root: Node, id: int, blend: float = 0.0) -> void:
	_stamp_tint(root, id, blend)

## Drop every tint duplicate under `root` — the removal path a consumer needs when its outline is turned
## off at runtime (has_outline cleared, a prop consumed, an NPC pooled into a life that wants no ring).
## Without this the only removal was an id-0 apply, which a disabled consumer never reaches.
static func clear_tint(root: Node) -> void:
	apply_tint(root, TINT_ID_NONE)

## ⭐⭐ THE LOOK-AT HOVER, as an id BORROW. `meshes` is the caller's already-pruned mesh list (the
## TalkHelpers.set_overlay signature this replaced, kept so Talkable / DialogueNPC / LookAtInteractable
## keep their `owns_its_overlay` prune and their lazily-collected head), and the borrow is the exact
## shape the old overlay stash had: on look-AT we remember whatever id the duplicate was wearing and
## stamp TINT_ID_HOVER; on look-AWAY we put the remembered id back. Without the stash, hovering an
## outlined enemy once would leave it wearing white forever.
##
## A mesh with no duplicate yet (a car, a terminal, a vending machine — anything whose outline was only
## ever the world's ink) gets one CREATED for the hover and FREED again on look-away, tagged so the
## restore path can tell "borrowed" from "owned". That tag is why a hover can never strand a permanent
## white ring on scenery.
##
## ⭐ Idempotent in BOTH directions: the ray drives this every frame the target changes, and a double-on
## must not overwrite the stashed base id with the hover id (which would make the white permanent).
static func set_tint_highlight(meshes: Array[MeshInstance3D], on: bool) -> void:
	if Engine.is_editor_hint():
		return
	for m in meshes:
		if not is_instance_valid(m) or m.has_meta(TINT_DUP_META):
			continue
		var dup := m.get_node_or_null(TINT_DUP_NAME) as MeshInstance3D
		if on:
			if dup == null:
				dup = _make_tint_dup(m)
				dup.set_meta(TINT_HOVER_OWNED_META, true)  # nobody else wants a ring here — ours to free
			elif not dup.has_meta(TINT_BASE_META):
				# A duplicate with no recorded base can only be one this method made earlier, so it is
				# already ours; re-tagging is harmless and keeps the free path unconditional.
				dup.set_meta(TINT_HOVER_OWNED_META, true)
			dup.set_meta(TINT_HOVER_META, true)
			_push_tint_id(dup, float(TINT_ID_HOVER))
		elif dup != null:
			dup.remove_meta(TINT_HOVER_META)
			if dup.has_meta(TINT_HOVER_OWNED_META):
				_free_tint_dup(m, dup)
			else:
				_push_tint_id(dup, float(dup.get_meta(TINT_BASE_META, float(TINT_ID_NONE))))

## The stamp walk behind apply_tint. The base-id bookkeeping lives here so a re-apply mid-hover (an NPC
## turning hostile while you look at it, a prop being claimed under the cursor) updates the id that gets
## RESTORED without disturbing the white you are currently seeing.
static func _stamp_tint(root: Node, id: int, blend: float) -> void:
	if root == null:
		return
	# Editor guard: several callers are @tool (Throwable, BodyModelSwap). Creating duplicate nodes at
	# EDIT time would litter authored scenes with unowned, unsaved children. ⭐ The consequence a
	# designer will notice: the ring is not previewable in the editor viewport the way a hull material
	# was. Judge it in-game, or with scripts/tools/__ink_cb_ring_shots.gd.
	if Engine.is_editor_hint():
		return
	for m in TalkHelpers.collect_meshes(root, null, true):
		apply_tint_mesh(m, id, blend)

## Stamp ONE mesh, no walk. The entry point for a consumer that owns its own traversal because it has to
## SKIP things: GunVisuals leaves the muzzle subtree and any `outline_skip_name_hints` match alone, and
## routing that through the walking apply_tint would re-adopt exactly the children it just refused.
## Same contract as apply_tint otherwise: idempotent, safe off-tree, TINT_ID_NONE removes.
static func apply_tint_mesh(m: MeshInstance3D, id: int, blend: float = 0.0) -> void:
	if not is_instance_valid(m) or m.has_meta(TINT_DUP_META) or Engine.is_editor_hint():
		return
	var value := float(id) + clampf(blend, 0.0, 1.0)
	var dup := m.get_node_or_null(TINT_DUP_NAME) as MeshInstance3D
	if id == TINT_ID_NONE:
		if dup != null:
			_free_tint_dup(m, dup)
		return
	if dup == null:
		dup = _make_tint_dup(m)
	else:
		# A duplicate the hover created and then handed a real owner stops being the hover's to free.
		dup.remove_meta(TINT_HOVER_OWNED_META)
	dup.mesh = m.mesh  # re-stamped every pass, so a swapped-in model stays mirrored
	_bind_skin(m, dup)
	dup.set_meta(TINT_BASE_META, value)
	# While the look-at hover owns this duplicate the white outranks us; we have already recorded the
	# id it goes back to, which is the whole point of the stash.
	if not dup.has_meta(TINT_HOVER_META):
		_push_tint_id(dup, value)

## Build the invisible duplicate for one source mesh and parent it under that mesh — which buys three
## things for free: it follows every transform, it inherits visibility (a hidden limb correctly leaves
## the silhouette), and it dies with its host. Walkers are shielded by TINT_DUP_META, never by the name.
static func _make_tint_dup(m: MeshInstance3D) -> MeshInstance3D:
	var dup := MeshInstance3D.new()
	dup.name = TINT_DUP_NAME
	dup.set_meta(TINT_DUP_META, true)
	# `=`, never `|=`: the duplicate must be on the tint layer and NOTHING else, or an ordinary
	# camera draws its raw depth encoding (the stripe bands).
	dup.layers = ACTOR_TINT_LAYER
	dup.material_override = tint_material()
	dup.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	dup.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	m.add_child(dup)
	dup.mesh = m.mesh
	_bind_skin(m, dup)
	return dup

## ⭐⭐ RE-MIRROR one duplicate's MESH from its host — the call every site that REASSIGNS a ringed
## MeshInstance3D's `mesh` owes, and the bug that proves it: a permanent ghost outline of the silenced
## pistol floating by the player's right hand (reported 2026-08-27, hours after the ring took the view
## model over).
##
## The duplicate takes a SNAPSHOT of `m.mesh` when it is stamped. That is fine for `visible`, for the
## transform, and for the duplicate's lifetime — it is a CHILD, so it inherits all three for free — but
## `mesh` is a plain property with no change notification, so a host that swaps or CLEARS its mesh later
## leaves the duplicate rasterising a shape that is no longer on screen. WeaponModelSwapper hides the
## rig's built-in placeholder pistol by exactly that route (`mi.mesh = null`, stashing the old mesh so it
## can be restored — NOT `visible = false`, because the Muzzle and its FX are parented under it and would
## vanish too), so the placeholder's silhouette stayed in the tint buffer forever and the ring pass drew
## it around nothing. The inverted hull this replaced could not have that failure: it rode
## `material_overlay` ON the mesh, so a null mesh drew nothing by construction.
##
## ⭐ THE RULE, then: **a tint duplicate mirrors exactly one property of its host, and `mesh` is it.**
## Reassign a ringed mesh's `mesh` and call this on the same line. No error, no failing test and no
## editor warning marks the omission — only a shape hanging in the frame.
## Cheap and idempotent: one property write, and a no-op on a mesh that carries no duplicate.
static func sync_tint_mesh(m: MeshInstance3D) -> void:
	if not is_instance_valid(m) or m.has_meta(TINT_DUP_META):
		return
	var dup := m.get_node_or_null(TINT_DUP_NAME) as MeshInstance3D
	if dup != null:
		dup.mesh = m.mesh  # null included: a host with no mesh must ring nothing

## Mirror a SKINNED source's deformation onto its duplicate (see apply_tint's header). No-op for the
## rigid meshes that are most of this game, and safe to re-run: both writes are idempotent.
static func _bind_skin(m: MeshInstance3D, dup: MeshInstance3D) -> void:
	if m.skin == null:
		return
	var skel := m.get_node_or_null(m.skeleton) as Skeleton3D
	if skel == null:
		return
	dup.skin = m.skin
	dup.skeleton = dup.get_path_to(skel)

## remove_child BEFORE queue_free: a queued node stays a CHILD until the frame ends, so a clear
## immediately followed by an apply (a prop claimed and released on the same frame, a pooled NPC
## re-dressed on spawn, a hover that ends on the frame a new one begins) would get_node_or_null the
## DOOMED node back and re-stamp a duplicate that is about to vanish — leaving the host silently
## ringless.
static func _free_tint_dup(m: MeshInstance3D, dup: MeshInstance3D) -> void:
	m.remove_child(dup)
	dup.queue_free()

## One instance-uniform write. Split out so the hover, the restore and the ordinary stamp cannot drift
## on the uniform's NAME (it is a string on both sides of the shader boundary).
static func _push_tint_id(dup: MeshInstance3D, value: float) -> void:
	dup.set_instance_shader_parameter(&"disposition_id", value)

## The id a mesh's duplicate is currently BASED on (ignoring any live hover borrow), or TINT_ID_NONE when
## it has no duplicate. The "is this outline mine?" question a consumer has to answer before REMOVING one:
## BodyModelSwap's strip path uses it exactly the way it used to check its own `bms_actor_rim` meta, so
## un-ticking actor_outline on a rig that some other system also rings can never take that system's ring.
static func tint_base_id(m: MeshInstance3D) -> int:
	if not is_instance_valid(m):
		return TINT_ID_NONE
	var dup := m.get_node_or_null(TINT_DUP_NAME) as MeshInstance3D
	if dup == null:
		return TINT_ID_NONE
	return int(floor(float(dup.get_meta(TINT_BASE_META, 0.0))))

## ⭐⭐ SHOW / HIDE the rings under `root` without destroying them — the ring's answer to an outline that
## has to FADE WITH ITS GEOMETRY. The hull could do that honestly (its ALPHA was a uniform, and
## BodyModelSwap drove it off body_transparency so a dissolving first-person chest took its outline with
## it). A ring cannot: the tint buffer's A channel IS coverage, tested `> 0.5`, and its RGB are packed
## numbers — there is no per-instance alpha to turn down, and making the duplicate transparent would
## move it out of the depth-writing opaque pass that resolves overlapping actors.
## So the ring switches instead of fading, and the caller picks the midpoint of the dissolve to switch at.
## A hard cut at half-dissolved is the honest trade: the alternative is a solid black silhouette hanging
## around a chest that has faded away, which is the exact failure the alpha drive was added to prevent.
## Visibility is on the DUPLICATE, so it survives re-stamps and costs nothing to re-assert.
static func set_tint_visible(root: Node, on: bool) -> void:
	if root == null or Engine.is_editor_hint():
		return
	for m in TalkHelpers.collect_meshes(root, null, true):
		if m.has_meta(TINT_DUP_META):
			continue
		var dup := m.get_node_or_null(TINT_DUP_NAME) as MeshInstance3D
		if dup != null:
			dup.visible = on

## The ONE shared material every tint duplicate wears — identity rides `instance uniform disposition_id`
## (set per duplicate via set_instance_shader_parameter), so one material serves every NPC in the game.
## Static get-or-create so NpcOutline reaches it without a path to the InkOutline instance; the depth
## window is stamped from the SAME consts the mask pair uses, so the three encoders cannot drift.
static var _tint_material: ShaderMaterial = null
static func tint_material() -> ShaderMaterial:
	if _tint_material == null:
		_tint_material = ShaderMaterial.new()
		_tint_material.shader = TINT_SHADER
		_tint_material.set_shader_parameter("depth_near", MASK_DEPTH_NEAR)
		_tint_material.set_shader_parameter("depth_far", MASK_DEPTH_FAR)
	return _tint_material

## Master switch. Off = the quad is hidden and never drawn; the frame renders with no ink at all.
@export var enabled: bool = true

@export_group("Line")
## Ink colour. Black is the Borderlands look; a very dark blue/brown reads softer if pure black
## fights the posterise. Alpha multiplies into the final line opacity.
@export var ink_color: Color = Color(0.0, 0.0, 0.0, 1.0)
## Authored line opacity at 100% intensity. Below 1.0 the ink sits as a tint over the art rather than
## a hard outline; the player's Options dial scales THIS value, it does not replace it.
@export_range(0.0, 1.0, 0.01) var opacity: float = 1.0
## Line thickness, AUTHORED in pixels of the RETRO 3D buffer. Under RETRO the 396x216 window x viewport
## stretch 0.5 gives the 792x444 canvas as the root target, and rendering/scaling_3d/scale 2.0 renders
## that at 1584x888 — so 2.0 here is about ONE pixel of the image the player actually sees, and the
## shipped 3.0 about one and a half. Under HIGH FIDELITY the ink quad's buffer is NATIVE x render_scale
## instead, so _params multiplies the pushed value by the live Settings.native_scale() — the authored
## number keeps this unit in both modes (in RETRO the factor is exactly 1.0). 3.0 was picked by eye off
## a render probe: 2.0 is legible but reads as a tasteful technical edge, and Borderlands' ink is bolder
## than tasteful. Constant in screen space by construction — a distant wall's line is exactly as thick
## as a near one's, which is the comic look.
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
## ⭐⭐ SEAM MERGE: the narrowest feature, in the width_px unit (authored RETRO-buffer px — twice the
## 792-wide canvas; _params pushes it x native_scale() like width_px, so the reach keeps its on-screen
## size under HIGH FIDELITY), that still earns a crease line. The confirming taps sit exactly this far
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
## (the camera's old 30 m resting far DoF was retired 2026-08-24 — ADS is the only far blur now), so
## the far field softens once instead of in separate steps. In a FOGGED level this window is only the
## backstop — fog_match below is what actually pulls the ink in to the distance the player can
## genuinely see; on a fogless level (the main level, since 2026-08-24) it is the whole mechanism.
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
## Resolution the ACTOR MASK renders at, as a fraction of the PRE-SUPERSAMPLE frame — the logical
## canvas x Settings.native_scale(), what _main_viewport_size returns: 792x444 in RETRO, the native
## window size in HIGH FIDELITY, i.e. the ink buffer at 1/render_scale in both modes — the effect's one
## real performance knob, and the one thing here you can SEE if you push it too far. The mask is a second
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
## can live with 2 px. ⭐ That whole table was measured against the RETRO buffer; under HIGH FIDELITY
## 1.0 means a NATIVE-sized mask (~5.9x the RETRO pixels at 1080p), so re-run the probe at native
## resolution before shipping a lower HF default — a legitimate perf trade once re-measured, not before.
## Live — resizes on the next frame.
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
## none of its own. Historically that was the hull RIM — a transparent-pass material that reached the
## mask's COVERAGE but not its DEPTH, so a hidden actor punched an OUTLINE of itself through the world's
## lines instead of a solid hole ("an O shape around it"). The hull is gone (2026-08-27) and the ring's
## duplicates are OPAQUE, so the common case now agrees by construction — but the search stays, because
## the SAME shape still arises from anything the resolve pass cannot place in depth: a prop faded through
## GeometryInstance3D.transparency, a coarse-LOD silhouette, an actor at the edge of the encoding window.
## Cheap (5 gate taps decide whether the search runs at all) and it fails toward the old behaviour.
##
## ⭐⭐ WHY THE SEARCH LIVES IN THE INK SHADER AND NOT IN THE RESOLVE PASS. The resolve pass could only
## spread depth outward by ALSO spreading the mask's alpha — and the mask's alpha is coverage, and coverage
## is suppressed ink. Every pixel of ring it repaired bought a pixel of bare halo around every VISIBLE
## actor, which is the artefact this pass has already been burned by twice. Searching here reads a wider
## neighbourhood and claims not one extra pixel of the frame, so the radius is generous for free.
##
## 12 was sized to out-reach the widest authored hull rim on screen (2.0 units x 2 x the RETRO render
## scale 2.0 = 8 px, plus margin). With no hull to out-reach it is now pure slack for the transparency
## cases above; it costs taps, not pixels of frame, so it is left where it was measured rather than
## re-tuned blind.
@export_range(0.0, 48.0, 1.0) var mask_rim_search_px: float = 12.0

## ⭐⭐ RING -> INK HANDOFF, in metres of ACTOR distance. Nearer than `near` the tint ring owns an actor's
## outline and this pass suppresses its own ink over/near them — the shipped design.
## Farther than `far` the actor is inked exactly like world geometry, because at a dozen pixels tall the
## mask stops being trustworthy per-pixel: it renders COARSER LODs (MASK_LOD_THRESHOLD) whose silhouette no
## longer matches the main pass, so the occlusion verdict sprays suppression holes that read as random
## black fragments on distant enemies — while the screen-space edge detect is distance-proof by
## construction (a constant-width line at any range). Between the two the suppression fades smoothly.
## Both thresholds are pushed PRE-ENCODED into the mask's log depth space (encode_actor_depth below) so
## the shader compares them straight against its searched depth.
## ⭐ SHIPPED NEUTRALIZED (a band at the top of the encoding window, where fog + the ink's own distance
## fade killed every line long ago): the suppression effectively never releases, i.e. the original "ink
## never draws on a masked actor" contract — re-affirmed by the user 2026-08-25 after a brief
## ink-outlines-NPCs experiment. It is now doubly right: the ring is EVERY actor's and every prop's only
## outline at every range, so handing one back to the world ink would swap a clean constant-width line
## for a scribbly one, not fill a gap. The dial is kept as the escape hatch for a level that wants
## distant masked things to fall back to ink; pulling it in is a look change, not a fix.
## ⭐ Named for the hull it used to hand off to. The name is kept because it is an authored export and
## renaming it would silently drop any value a .tscn has already set on it.
## ⭐ Both values MUST stay INSIDE the MASK_DEPTH window: past 300 m they encode to the same 0.0 and the
## shader's smoothstep(e_far, e_near, e) degenerates to undefined edge0==edge1 behaviour (the 350/400
## mistake — caught by the e_near > e_far test the same hour it was made).
@export_range(1.0, 299.0, 0.5) var hull_handoff_near_m: float = 290.0
@export_range(2.0, 299.5, 0.5) var hull_handoff_far_m: float = 299.0

## ⭐⭐ THE OUTLINE RING — the screen-space replacement for the retired inverted-hull rim, and since
## 2026-08-27 the ONLY outline anything in this game wears. Width of the ring drawn around every tinted
## silhouette (see ACTOR_TINT_LAYER), in the width_px unit
## (RETRO-buffer px; pushed x _px_unit_scale like every px knob here). Constant on screen at ANY
## distance by construction — the property no shell geometry could ever deliver — and depth-compared
## per pixel against the scene, so it never shows through a wall. 0 disables the ring (and the taps).
@export_range(0.0, 8.0, 0.5) var highlight_width_px: float = 2.0
## The id -> color LUT for ink_tint.gdshader's disposition ids (1/2/3), NORMAL-palette half. ⭐ KEEP IN
## STEP with NPC.OUTLINE_HOSTILE / OUTLINE_FRIENDLY / OUTLINE_FOLLOWING (= CBPalette's NORMAL_* pair) —
## NpcOutline maps its disposition to the ID, and these decide what that ID paints. Duplicated as
## exports rather than read off NPC so the ring is tunable per level/scene without touching combat code
## (and so this file has no NPC dependency).
## ⭐ THE COLORBLIND-SAFE OVERRIDE (2026-08-27): with Settings.colorblind_safe_cues ON, _params pushes
## CBPalette.SAFE_HOSTILE / SAFE_FRIENDLY over these two slots — accessibility WINS over per-scene
## tuning, deliberately: the toggle exists to take red/green out of the game's cues, and an authored red
## here is exactly what it must replace. Read from CBPalette's consts (never its Settings-reading
## helpers — _cb_safe() owns the flag read, reimport-hardened) so the ring can never drift from the
## laser / hover name / health-bar cues. Live: the _pushed compare repaints the frame the toggle flips.
## Companion (id 3) and neutral (id 4) don't swap — blue/black sit outside the red/green axis, matching
## NPC.OUTLINE_FOLLOWING, which is likewise fixed in both modes.
@export var highlight_hostile: Color = Color(0.9, 0.1, 0.1)
@export var highlight_friendly: Color = Color(0.1, 0.8, 0.2)
@export var highlight_companion: Color = Color(0.15, 0.45, 1.0)
## Id 4 — the NEUTRAL ring, and the id 5 PROP ring reuses it. Black on purpose: everything wearing a
## ring is excluded from the world ink, so the ring is its only outline and a neutral bystander (or a
## crate) should read exactly like the classic black rim did.
@export var highlight_neutral: Color = Color(0.0, 0.0, 0.0)
## ⭐ Id 9 — THE LOOK-AT HOVER, "you are aiming at this and Interact will do something". This ONE colour
## replaced the per-component `highlight_color` the deleted hull carried on Talkable / DialogueNPC /
## LookAtInteractable / Throwable: a ring resolves one id to one LUT slot, so the hover colour is global
## now. Those components keep their own `highlight_color` / `highlight_width` exports as the VISIBILITY
## switch they already doubled as — alpha 0 or width 0 still means "this one gets no hover outline" (the
## shipping ATM relies on it) — they just no longer decide the hue.
@export var highlight_hover: Color = Color(1.0, 1.0, 1.0)
## ⭐ Id 10 — THE VIEW MODEL: your own weapon and first-person body, on ViewModelCamera.VIEW_MODEL_LAYER.
## A slot of its own rather than reusing neutral so the gun's line stays tunable against the world's
## (GunVisuals.outline_color used to own that and is gone with the hull). BLACK is the house look.
@export var highlight_view_model: Color = Color(0.0, 0.0, 0.0)
## ⭐ THE CLOSE-RANGE COLOR BLOOM (user-requested, 2026-08-25 — the loved behaviour from the hull era,
## rebuilt on the ring): at range every DISPOSITION ring renders as the NEUTRAL black — an outline is
## always there, reading like the classic rim — and the disposition color FADES IN as the actor closes:
## full red/green/blue nearer than `near`, pure black past `far`, a smooth blend between. The distance is
## the ACTOR'S own (the tint buffer's encoded depth at the winning tap), so each enemy blooms on its own
## approach. Constant color at every range instead: raise `near` toward the window top — the mix then
## never leaves the colored end. Both values MUST stay INSIDE the MASK_DEPTH window (the 350/400 lesson:
## past 300 m encodings collapse equal and the smoothstep degenerates). Pushed PRE-ENCODED, the
## hull_handoff idiom.
## ⭐ Ids 5, 6, 9 and 10 (props, the hover, the view model) are NOT dispositions and deliberately ignore
## this — they paint their LUT slot flat at every range. A hover white that faded with distance would
## contradict the prompt it accompanies, and a prop that faded would have no outline at all now that the
## hull is gone.
@export_range(1.0, 299.0, 0.5) var highlight_color_near_m: float = 8.0
@export_range(2.0, 299.5, 0.5) var highlight_color_far_m: float = 22.0

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
var _tint_viewport: SubViewport = null      ## disposition tint/ID pass (ACTOR_TINT_LAYER); built beside the mask
var _tint_camera: Camera3D = null           ## camera inside it; synced with the mask camera every frame
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
	# THE DISPOSITION TINT PASS, built beside the mask with the same lessons applied (shared World3D,
	# stripped viewport, clear-background LINEAR-pinned environment — ink_tint.gdshader's encoding rides
	# the same sRGB pre-compensation as the resolve pass, so a re-grading tonemapper would corrupt it the
	# same way). No resolve quad: each tint fragment encodes its OWN view depth, and the duplicates are
	# OPAQUE, so overlapping NPCs resolve nearest-wins by plain z-test.
	_tint_viewport = SubViewport.new()
	_tint_viewport.transparent_bg = true
	_tint_viewport.world_3d = get_viewport().find_world_3d()
	_tint_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_tint_viewport.handle_input_locally = false
	_tint_viewport.size = _mask_size()
	_strip_mask_viewport(_tint_viewport)
	_tint_camera = Camera3D.new()
	_tint_camera.cull_mask = ACTOR_TINT_LAYER
	_tint_camera.environment = _build_mask_environment()
	_tint_camera.current = true
	_tint_viewport.add_child(_tint_camera)
	add_child(_tint_viewport)
	_sync_mask_camera()
	# One-time bind, the actor_mask idiom: a ViewportTexture tracks its viewport through resizes. The
	# uniform's own filter_nearest hint is load-bearing — the RG depth bytes and the B id must never be
	# interpolated between neighbouring actors.
	_material.set_shader_parameter("actor_tint", _tint_viewport.get_texture())

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
	# The tint camera rides the exact same sync — one frame of divergence between the two buffers would
	# put the colored ring a step off the silhouette during camera whips.
	if _tint_camera != null:
		_tint_camera.global_transform = cam.global_transform
		_tint_camera.fov = cam.fov
		_tint_camera.near = cam.near
		_tint_camera.far = cam.far
		_tint_camera.keep_aspect = cam.keep_aspect
		if _tint_viewport.size != want:
			_tint_viewport.size = want

func _main_viewport_size() -> Vector2i:
	var vp := get_viewport()
	if vp:
		# The pre-supersample frame — Settings.render_size(): the native window under HIGH FIDELITY, the
		# logical ~792x444 canvas in RETRO (the mathematical identity of the old visible-rect read, which
		# get_visible_rect() still reports in both presentations). It keeps the mask at 1/render_scale of
		# the ink buffer in both modes — the invariant the shader's tight gather and the rim search were
		# measured against. EXACT per-axis on purpose, never visible-rect x the scalar native_scale():
		# the canvas_items stretch is slightly anisotropic (444 x 2.4242 = 1076, not 1080), and a
		# 4-px-short mask target skews the mask CAMERA's aspect against the main render — actor
		# silhouettes then land horizontally offset from the picture sampled at the same SCREEN_UV, a
		# real slice of the "outlines don't quite connect" report (2026-08-25). Falls back to the
		# visible-rect x native_scale path only if Settings is missing (a bare harness tree).
		if _settings != null and _settings.has_method(&"render_size"):
			return _settings.call(&"render_size")
		return Vector2i((vp.get_visible_rect().size * _native_scale()).round())
	return Vector2i(792, 444)  # the logical CANVAS (396x216 x stretch 0.5) — only RETRO's screen buffer — as an off-tree fallback

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
	# ⭐⭐ EXCEPT WHEN THE RING NEEDS IT (2026-08-27). The ring draws on this same quad, and since the hull
	# was deleted it is the only outline anything in the game has — so a player who turns the aesthetic
	# "Ink Outline" slider to 0% must still see hostile red, the colourblind-safe palette, claimed-prop
	# blue, the look-at hover and their own weapon's line. The quad therefore stays visible for the ring
	# alone, with the WORLD's line zeroed by ink_params (ink_opacity 0, width_px 0) and the ring
	# deliberately not multiplied by ink_opacity in the shader. Before the migration this cost nothing to
	# get right, because every one of those cues was an inverted-hull rim the slider could not reach.
	var ink_on := bool(params["apply"])
	visible = ink_on or ring_enabled()
	# The MASK pass answers one question — "may the world's ink draw on this pixel?" — so it is gated with
	# the ink, not with the quad. No ink, no silhouettes worth rendering.
	if _mask_viewport != null:
		_mask_viewport.render_target_update_mode = (
			SubViewport.UPDATE_ALWAYS if ink_on else SubViewport.UPDATE_DISABLED
		)
	# ⭐ The TINT pass is a SECOND full scene render over every ringed thing in the level, and until
	# 2026-08-27 it was never gated at all — it kept drawing at 0% intensity and with `enabled` off, for a
	# texture nothing sampled. That was a handful of NPC parts when the ring only served NPCs; with props,
	# gibs, corpses, the hover and the whole view model on it, an ungated pass is most of the frame drawn
	# a third time for nothing.
	if _tint_viewport != null:
		_tint_viewport.render_target_update_mode = (
			SubViewport.UPDATE_ALWAYS if visible and ring_enabled() else SubViewport.UPDATE_DISABLED
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

## Whether the RING half of this pass has anything to draw: the tint buffer exists, the node is on, and
## the ring has a width. Public because it is a real question about this node's state (a probe or a perf
## harness asking "is the tint pass live?"), and because _params and _refresh must answer it identically
## — they gate different things on it (the uniform set, the quad's visibility, the tint viewport's update
## mode) and a drift between them would show up as a frame of missing outlines, not an error.
## ⭐ Deliberately independent of Settings.ink_outline_intensity: see the ring block in _refresh.
func ring_enabled() -> bool:
	return enabled and _tint_viewport != null and highlight_width_px > 0.0

## Whether the player's Colorblind-Safe Cues toggle is ON — decides which palette the ring LUT pushes
## (see highlight_hostile's doc). The _intensity idiom: a per-frame poll of the Settings autoload, so it
## rides the hardened .get() + null-guard read (a reimport transient must degrade to the authored look
## for a frame, never throw), and off-tree (a bare test/harness — _settings is null) it is false: the
## authored NORMAL palette, the exact pre-override behaviour.
func _cb_safe() -> bool:
	if _settings == null:
		return false
	var v: Variant = _settings.get(&"colorblind_safe_cues")
	return bool(v) if v != null else false

## Render px per authored canvas px on the root viewport — the unit converter for this pass's px-unit
## knobs and the mask's sizing, read LIVE from the Settings autoload on EVERY call. Never cache it: a
## mid-session presentation flip or resize must bite the very next _params/_mask_size poll (the
## cached-base_fov lesson), and the _pushed compare in _refresh is what turns a changed factor into a
## re-push. The _intensity idiom: _settings is null off-tree (a bare test/harness — _ready never ran)
## and the method-guard survives a reimport, both degrading to exactly 1.0 — the RETRO identity, under
## which every multiply that consumes this is a mathematical no-op.
func _native_scale() -> float:
	if _settings == null or not _settings.has_method(&"native_scale"):
		return 1.0
	return maxf(1.0, float(_settings.call(&"native_scale")))

## The px-unit compensation for this pass's authored knobs (width_px, crease_min_feature_px,
## mask_rim_search_px). They are authored in RETRO-BUFFER pixels — the ~792-wide canvas x the project's
## AUTHORED rendering/scaling_3d/scale supersample of 2.0, i.e. a 1584x888 buffer (width_px 3.0 =
## 3/1584 of the screen's width). Preserving that ON-SCREEN FRACTION is the whole point, and the HIGH
## FIDELITY buffer is native x the LIVE scaling_3d_scale — which the settings migration seeds at
## render_scale 1.0 — so a bare native_scale() multiply DOUBLES every px unit's screen fraction
## (measured 2026-08-25: fat halo outlines floating off distant NPCs, "hovering" until you close in,
## and mis-joined line work). Hence HF multiplies by native_scale() x (live supersample / the authored
## 2.0). RETRO returns native_scale() verbatim (1.0 — bit-identical, deliberately INCLUDING the
## pre-existing quirk that the Render Scale slider thickens/thins retro ink; do not "fix" that here).
func _px_unit_scale() -> float:
	var ns := _native_scale()
	if ns <= 1.0:
		return ns  # RETRO / off-tree / headless: the exact pre-presentation identity
	var vp := get_viewport()
	var s3d: float = vp.scaling_3d_scale if vp != null else AUTHORED_SUPERSAMPLE
	return ns * s3d / AUTHORED_SUPERSAMPLE

## GDScript mirror of ink_outline.gdshader's encode_actor_depth — ⭐ KEEP IDENTICAL to the shader's copy
## (and actor_mask_resolve.gdshader's): the hull-handoff thresholds are pushed through THIS function and
## compared inside the shader against values its own copy produced, so a drift between the two silently
## moves the handoff band. Log-encoded, near -> 1.0, far -> 0.0 (encoded depth DECREASES with distance).
## Static + pure so the encoding contract is assertable off-tree.
static func encode_actor_depth(d: float, near_m: float, far_m: float) -> float:
	var lo := maxf(near_m, 0.001)
	var hi := maxf(far_m, lo * 1.001)
	return 1.0 - clampf(log(clampf(d, lo, hi) / lo) / log(hi / lo), 0.0, 1.0)

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
	# ⭐ `apply` is the WORLD ink's switch, and a zeroed slider still has to push the full uniform set when
	# the RING is on — ink_params already returns ink_opacity 0 / width_px 0 there, so the edge detect
	# contributes nothing and only the ring paints. See _refresh for why the ring outlives the slider.
	if not scaled["apply"] and not ring_enabled():
		return scaled
	# The three px-unit uniforms (width_px here, crease_min_feature_px and mask_rim_search_px below) are
	# authored in RETRO-buffer pixels; under HIGH FIDELITY the ink quad's buffer goes native-sized, so
	# they are converted at THIS push site — never inside the pure ink_params, whose exact outputs are
	# test-pinned — by the live _px_unit_scale() (1.0 in RETRO/off-tree, so the multiply is then an exact
	# identity; in HF it preserves each knob's ON-SCREEN FRACTION against the live buffer, supersample
	# included — see the helper for the halo regression a bare native_scale() multiply caused).
	# Uncompensated they would not merely thin: the Roberts taps sit width_px/2 apart, so an unscaled
	# width also collapses the tap spacing and lines go MISSING, not hairline. Read live every call,
	# never cached; the _pushed compare in _refresh re-pushes on a mid-session flip for free.
	var ns := _px_unit_scale()
	scaled["width_px"] = float(scaled["width_px"]) * ns
	scaled["ink_color"] = ink_color
	scaled["depth_threshold"] = depth_threshold
	scaled["min_depth_reference"] = min_depth_reference
	scaled["grazing_tolerance"] = grazing_tolerance
	scaled["contact_merge_m"] = contact_merge_m
	scaled["crease_strength"] = crease_strength
	scaled["crease_threshold"] = crease_threshold
	# Same px unit as width_px — the two scale together, which is what keeps the shader-side floor
	# max(crease_min_feature_px, width_px) self-consistent at any native scale.
	scaled["crease_min_feature_px"] = crease_min_feature_px * ns
	scaled["concave_crease_strength"] = concave_crease_strength
	scaled["fade_start"] = fade_start
	scaled["fade_end"] = fade_end
	scaled["fog_extinction"] = _fog_sigma * fog_match
	# True only once the mask pass exists, so the shader never samples an unbound mask (off-tree /
	# pre-deferred-build frames ink everything, actors included, for at most one frame at startup).
	# ⭐ AND only while the world ink is actually drawing: on a ring-only frame the mask viewport is frozen
	# (see _refresh), and sampling a stale coverage field to decide where to suppress a line that has zero
	# alpha anyway is pure work. The ring never consulted it — it is computed before the exclusion and
	# survives its discard by construction.
	scaled["use_actor_mask"] = _mask_viewport != null and bool(scaled["apply"])
	# The occlusion test (see occlusion_aware_mask). The encoding window is pushed from the SAME constants
	# the resolve material gets, which is the only reason the two shaders can be trusted to agree.
	scaled["use_mask_occlusion"] = occlusion_aware_mask
	scaled["mask_depth_near"] = MASK_DEPTH_NEAR
	scaled["mask_depth_far"] = MASK_DEPTH_FAR
	scaled["mask_occlusion_bias"] = mask_occlusion_bias
	# Same px unit as width_px: the reach is a screen-space search, so it must gain the buffer's factor
	# to keep covering the same fraction of the image at any Render Scale.
	scaled["mask_rim_search_px"] = mask_rim_search_px * ns
	# RING -> INK HANDOFF thresholds, pre-encoded into the mask's log depth space (the shader compares
	# them straight against searched_depth's value — see the export doc). far is floored a hair past
	# near so a designer who authors the pair backwards gets a hard step, never an inverted smoothstep.
	scaled["hull_handoff_e_near"] = encode_actor_depth(hull_handoff_near_m, MASK_DEPTH_NEAR, MASK_DEPTH_FAR)
	scaled["hull_handoff_e_far"] = encode_actor_depth(maxf(hull_handoff_far_m, hull_handoff_near_m + 0.01), MASK_DEPTH_NEAR, MASK_DEPTH_FAR)
	# THE DISPOSITION HIGHLIGHT ring — same px unit as width_px, same live compensation; gated off
	# entirely until the tint pass exists so the shader never samples an unbound tint buffer.
	scaled["use_actor_tint"] = _tint_viewport != null and highlight_width_px > 0.0
	scaled["highlight_width_px"] = highlight_width_px * ns
	# Colorblind-Safe Cues ON swaps the hostile/friendly LUT slots to CBPalette's SAFE_* pair (orange /
	# cyan) — over the authored exports, deliberately; see highlight_hostile's doc. CONSTS, not
	# CBPalette.hostile()/friendly(): those helpers read the Settings autoload DIRECTLY every call, and
	# this runs per frame — the reimport-transient throw the hardened _cb_safe() read exists to absorb.
	# The engaged 7..8 band resolves to the same highlight_hostile slot in the shader, so a locked-on
	# enemy's any-distance glow re-paints orange with it for free. Companion/neutral are fixed both modes.
	var cb_safe := _cb_safe()
	scaled["highlight_hostile"] = CBPalette.SAFE_HOSTILE if cb_safe else highlight_hostile
	scaled["highlight_friendly"] = CBPalette.SAFE_FRIENDLY if cb_safe else highlight_friendly
	scaled["highlight_companion"] = highlight_companion
	scaled["highlight_neutral"] = highlight_neutral
	# The two slots the hull's retirement added. Neither swaps under Colorblind-Safe Cues: white and black
	# sit off the red/green axis entirely, and both are CONTRAST cues rather than identity ones.
	scaled["highlight_hover"] = highlight_hover
	scaled["highlight_view_model"] = highlight_view_model
	# The color bloom's band, pre-encoded like the handoff pair (far floored past near so an authored
	# inversion degrades to a hard step, never an undefined smoothstep).
	scaled["highlight_e_color_near"] = encode_actor_depth(highlight_color_near_m, MASK_DEPTH_NEAR, MASK_DEPTH_FAR)
	scaled["highlight_e_color_far"] = encode_actor_depth(maxf(highlight_color_far_m, highlight_color_near_m + 0.01), MASK_DEPTH_NEAR, MASK_DEPTH_FAR)
	# NOTE: the mask's resolution is deliberately NOT pushed. The shader sizes its suppression window off
	# width_px alone (filter_linear makes the mask a sub-texel coverage field), because scaling that
	# window off the mask's texel size is exactly what put a halo around every actor. ⭐ TWO KINDS of
	# "resolution-derived", and only one is banned: anything derived from the MASK's resolution or texel
	# size must never reach this set (that is the halo), while the native_scale() factor above is
	# INK-BUFFER-derived — the very buffer VIEWPORT_SIZE measures — and is REQUIRED, or suppression stops
	# being sized off the line under HIGH FIDELITY. See the exclusion block in ink_outline.gdshader
	# before pushing anything mask-derived here.
	return scaled
