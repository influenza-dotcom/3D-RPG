class_name ViewModelCamera
extends Node3D

## FPS view-model render pass: draws the first-person gun on TOP of the world so it never
## clips through geometry and can carry its own FOV — the standard Godot-4 idiom, which (unlike
## "two current Camera3Ds on one viewport", where only one wins) REQUIRES a second viewport.
##
## How it works:
##  - The view model already lives ALONE on render layer 3 (value VIEW_MODEL_LAYER); gun_mesh.gd
##    forces every gun submesh onto it. We drop that layer from the MAIN camera's cull_mask, so
##    the main pass no longer draws the gun, then render the gun in its own SubViewport whose
##    camera masks ONLY that layer. The SubViewport SHARES the main World3D (so its camera sees
##    the same gun nodes) and clears its own depth buffer, so the gun is painted over the world
##    with no clipping.
##  - The gun camera copies the main camera's global_transform + fov every frame, so shake, bob,
##    landing dip, strafe tilt and ADS zoom all ride along for free (they're all baked into the
##    main camera's global transform / fov by CameraEffects + ScreenShake + ScopeIn).
##  - The SubViewport's texture is composited over the main view by a SubViewportContainer added
##    to the HUD CanvasLayer.
##  - LIGHTING: the gun camera gets its OWN Environment (a flat ambient FILL) — REQUIRED, not optional. This world
##    is lit almost entirely by volumetric FOG (its actual ambient is ~0), and fog is integrated over DISTANCE, so
##    it fills far geometry but contributes ~nothing to a gun 30 cm from the lens. On the shared world the view
##    model therefore rendered effectively BLACK wherever a direct light didn't strike it. The flat fill makes it
##    readable everywhere while direct lights still add on top. See the view_model_* exports.
##
## RUNNABILITY: `enabled` defaults to false, and that default is DEAD for the player —
## Head._setup_view_model_camera builds this node in code and sets `enabled = true` unconditionally, so
## the dedicated pass is what actually ships and there is no .tscn override to check. The default only
## describes what a bare instance of this class does. (Read that before reasoning about which camera
## draws the gun: the answer is this one, and the main camera has VIEW_MODEL_LAYER stripped.)
## While off, NOTHING changes — the main camera keeps its full cull_mask and still draws the gun. The
## main-camera layer drop happens ONLY after the SubViewport pass is fully built, and the gun is
## restored to the main camera if this node leaves the tree, so a half-built pass can never leave
## the player weaponless. The one thing that needs the editor to judge is the composite ORDER vs the
## post-process dither (see _attach_container) — tune it live.

## Render layer the view model lives on (editor layer 3 = bit value 4). Matches the GunMesh's
## `layers` in view_model.tscn and the layer gun_mesh.gd forces its submeshes onto.
const VIEW_MODEL_LAYER: int = 4

## Master switch. OFF (default) = legacy single-camera rendering, gun drawn by the main camera.
## ON = dedicated view-model camera pass (see the class doc). Off by default so the game is
## unchanged until the composite ordering is verified in the editor.
@export var enabled: bool = false

## Extra FOV for the view model, ADDED to the main camera's FOV each frame. 0 = identical to the
## world (the gun tracks the main FOV, including ADS zoom). A small negative value makes the gun
## read slightly "longer"/closer, the classic FPS weapon look.
##
## ⭐⭐ SHIPS 0.0 AND THE WEAPON'S OUTLINE DEPENDS ON IT (2026-08-27). Since the inverted hull was deleted,
## the view model's outline is InkOutline's screen-space ring, rasterised from a tint SubViewport whose
## camera clones the MAIN camera. This pass renders the gun at `main fov + fov_offset`. At 0 the two
## projections are identical and the ring sits exactly on the weapon; at anything else the gun is drawn
## at one FOV and its outline at another, so the line slides off the silhouette — growing with the offset,
## with no error anywhere and nothing in a headless test that can see it.
## Want the longer-gun look? The ring pass needs its own view-model tint viewport at this FOV first; one
## camera cannot hold two projections. `tests/test_ink_outline.gd` pins this default at 0 so the coupling
## cannot be broken silently.
@export var fov_offset: float = 0.0

## --- View-model LIGHTING ---------------------------------------------------------------------------------------
## The gun camera gets its OWN Environment — a flat ambient FILL — because the world's own lighting can't light a gun
## held at arm's length. The levels run with almost no ambient (the level WorldEnvironment's ambient is ~0 — see
## SliceTestLevel's env: ambient_light_energy 0.08, sky contribution 0) and lean on volumetric FOG for the scene
## fill, but fog is integrated over DISTANCE — it fills far geometry and contributes ~nothing 30 cm from the lens.
## So on the shared world the view model came out effectively BLACK wherever a direct light didn't strike it. The
## flat fill makes it readable everywhere; direct lights (sun / lamps / muzzle flash) still add on top — lit BY the
## world, just never black. (A camera with no environment falls back to the WORLD env, so this REPLACES that
## fallback: same near-zero fill result, now with a real ambient + a CLEAR bg so the composite can't paint the sky.)

## Explicit Environment for the gun pass. Null (default) -> one is built from the view_model_ambient_* knobs below,
## and its tonemap tracks the level's WorldEnvironment (_follow_world_tonemap) so the gun grades like the world.
## Set this to hand-author the view model's look (its own glow / adjustments / a stronger fill) in the inspector —
## it's then used verbatim, tonemap included, and neither the grade follow nor the night-fill dim touches it.
@export var view_model_environment: Environment = null

## Flat ambient FILL colour for the built-in view-model environment (ignored when view_model_environment is set).
## Keep it near white so the fill doesn't recolour the hands/gun; tint it slightly for a mood.
@export var view_model_ambient_color: Color = Color(0.9, 0.91, 0.95)

## Flat ambient FILL energy for the built-in view-model environment (ignored when view_model_environment is set).
## The BASE brightness the view model never drops below (direct lights add on top). ~0.75 reads as "in shadow but
## clearly visible". Raise for a brighter always-lit gun; lower to let the world's darkness show on it more.
@export var view_model_ambient_energy: float = 0.75

## Fraction of the fill energy left at DEEP NIGHT when a DayNightSky is driving the level (group "day_night",
## duck-typed current_day_factor) — the gun dims with the world instead of glowing full-fill in the dark.
## 1.0 = constant fill day and night. A level with NO day/night driver keeps the constant fill, so the gun
## never darkens against a bright static world. Ignored when view_model_environment is authored (used verbatim).
@export var night_fill_scale: float = 0.35

var _main_camera: Camera3D            ## the live first-person camera we mirror (CameraEffects)
## The HUD-ghost drop-in, for its `set_ghosted` opt-out helper alone (see _attach_container).
## Preloaded BY PATH + used through the const — the editor class-cache cascade guard.
const HUD_GHOST_SCRIPT := preload("res://scripts/ui/hud_ghost.gd")

var _sub_viewport: SubViewport        ## off-screen pass that renders ONLY the gun layer
var _gun_camera: Camera3D             ## camera inside _sub_viewport; masks ONLY VIEW_MODEL_LAYER
var _container: SubViewportContainer  ## composites _sub_viewport's texture over the main view
var _main_cull_mask_backup: int = 0   ## the main camera's original cull_mask, restored on exit
var _layer_dropped: bool = false      ## true once VIEW_MODEL_LAYER has been removed from the main cam
var _composited: bool = false         ## true when the SubViewport is shown via a SubViewportContainer
var _tonemap_source: Environment = null  ## world Environment the gun's grade was last copied from (see _follow_world_tonemap)

## Build the view-model pass against the live first-person camera. Called once by head.setup().
## No-op (and the game renders normally) while `enabled` is false. `ui` is the HUD CanvasLayer the
## composite container is parented under; if it's null the container is skipped (the gun still
## renders, just not composited — kept defensive so a missing HUD never crashes the camera).
func setup(main_camera: Camera3D, ui: CanvasLayer) -> void:
	_main_camera = main_camera
	if not enabled or _main_camera == null:
		return
	# Deferred so the whole rig has finished entering the tree first: get_world_3d() and the
	# viewport size are only reliable once we're fully in the scene (this runs from the host's
	# _enter_tree). Mirrors gun_mesh.gd deferring its first _equip_view_model.
	_build_pass.call_deferred(ui)

func _build_pass(ui: CanvasLayer) -> void:
	# Off-screen pass sharing the MAIN world so its camera sees the same gun nodes. Transparent bg
	# so only the gun (not a clear colour) composites over the world. UPDATE_ALWAYS so it redraws
	# every frame as the gun sways/recoils.
	_sub_viewport = SubViewport.new()
	_sub_viewport.transparent_bg = true
	_sub_viewport.world_3d = _main_camera.get_world_3d()
	_sub_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_sub_viewport.handle_input_locally = false

	# The gun camera: masks ONLY the view-model layer, so this pass draws the gun and nothing else. current within
	# its own SubViewport (the only camera there); does NOT fight the main viewport's active camera. It gets its OWN
	# Environment — a flat ambient FILL (see the class doc + the view_model_* exports) — so the gun isn't black at
	# arm's length in this fog-lit, ~zero-ambient world. NO CameraAttributes on purpose (the main camera's near-DOF
	# would blur a gun 30 cm from the lens).
	_gun_camera = Camera3D.new()
	_gun_camera.cull_mask = VIEW_MODEL_LAYER
	_gun_camera.fov = _main_camera.fov
	_gun_camera.near = _main_camera.near
	_gun_camera.far = _main_camera.far
	_gun_camera.keep_aspect = _main_camera.keep_aspect
	_gun_camera.environment = _resolve_view_model_environment()
	_gun_camera.current = true
	_sub_viewport.add_child(_gun_camera)

	# Parent the SubViewport: under the composite container if there's a HUD (the container drives
	# its size + paints it over the world), else under this node as a bare off-screen pass (it still
	# renders to its texture; just not shown — defensive, a missing HUD must not crash the camera).
	_attach_container(ui)
	if not _composited:
		_sub_viewport.size = _viewport_pixel_size()
		add_child(_sub_viewport)

	# Now that the gun camera is in the tree, give it the live pose so the first frame is correct
	# (global_transform needs an in-tree node; _process keeps it synced thereafter).
	_sync_gun_camera()

	# Atomic last step: now that the gun has its own pass, stop the MAIN camera drawing it.
	# Doing this LAST means any failure above leaves the gun on the main camera (still visible).
	_main_cull_mask_backup = _main_camera.cull_mask
	_main_camera.cull_mask = _main_camera.cull_mask & ~VIEW_MODEL_LAYER
	_layer_dropped = true

## Composite the gun pass over the main view via a full-rect SubViewportContainer on the HUD layer.
## Born stretch=true and stretch STAYS true in every presentation: the container OWNS the SubViewport's
## size in its own logical units — the full canvas in RETRO (canvas px ARE render px there), and under
## HIGH FIDELITY _sync_pass_resolution re-rects the container itself to the native target and scales it
## back onto the canvas (see there for the stretch-off feedback loop this dodges). Mouse-ignore means it
## never eats clicks.
## Inserted as the FIRST child of the HUD CanvasLayer so
## the post-process ColorRect (also on this layer, formerly child 0) still draws on TOP of it —
## i.e. the gun is dithered/posterised WITH the world rather than floating crisp above it. If a
## crisp (un-dithered) gun is preferred, move this above the ColorRect instead. Sets _composited.
func _attach_container(ui: CanvasLayer) -> void:
	if ui == null:
		return
	_container = SubViewportContainer.new()
	_container.name = "ViewModelComposite"
	_container.stretch = true  # PERMANENT in both presentations — _sync_pass_resolution moves the container's rect, never this flag
	_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_container.set_anchors_preset(Control.PRESET_FULL_RECT)
	_container.add_child(_sub_viewport)  # the container is the SubViewport's sole parent
	ui.add_child(_container)
	ui.move_child(_container, 0)  # draw UNDER the post-process ColorRect (HUD child 0 was that rect)
	# ...and OUT of the HUD-ghost capture (scripts/ui/hud_ghost.gd). Being a Control on the HUD layer is an
	# implementation detail of how the gun pass is composited — it is not a HUD readout, and the ghost's rule
	# is "an instrument readout trails". Left in, the whole weapon would smear behind itself on every turn,
	# which reads as the gun being made of light rather than as a UI afterimage. This one line is also why
	# the arms/gun stay crisp while the panel and reticle around them ghost.
	HUD_GHOST_SCRIPT.set_ghosted(_container, false)
	_composited = true

## The gun pass's own render target, whose ALPHA is exactly the weapon's screen coverage — the SubViewport
## clears TRANSPARENT and only the view-model layer draws into it, so alpha is 1 on the gun/arms and 0
## everywhere else. WorldGhost samples it to keep the temporal trail off the weapon (the world behind it
## still ghosts); nothing else may rely on the RGB, which is the gun's own lit colour and not a mask.
## Null while the pass is not composited — a caller must treat that as "no mask", never as "mask everything".
func coverage_texture() -> Texture2D:
	if not _composited or _sub_viewport == null:
		return null
	return _sub_viewport.get_texture()

func _process(_delta: float) -> void:
	if _gun_camera == null or _main_camera == null:
		return
	_sync_gun_camera()
	_follow_world_tonemap()
	_follow_day_night()
	_sync_pass_resolution()

## Keep the gun pass's render target matched to the CURRENT presentation mode, polled every frame so a live
## Options flip bites the next one (the Settings contract: native_scale()/render_size() are read LIVE, never
## cached — the cached-base_fov lesson). Both arms route through here so they cannot drift:
##  - COMPOSITED (the shipping path): in RETRO the full-rect stretched container owns the size — in CANVAS
##    units, which ARE render px there, so this poll writes nothing (today's pipeline, bit-identical). Under
##    HIGH FIDELITY a full-rect stretched container can only size in canvas units and would pin the gun at
##    retro res over a native-crisp world — so the CONTAINER is sized to Settings.render_size() in logical
##    units and Control.scale'd back down so its on-screen footprint stays the full canvas: the stretched
##    container then sizes the viewport native itself, and the drawn texture lands 1:1 on native pixels
##    through the window's canvas transform. WorldGhost's gun coverage mask sharpens for free, since it
##    samples this same target. ⭐stretch STAYS TRUE in both modes: the obvious "stretch off + drive the
##    SubViewport size by hand" FEEDS BACK — with stretch off a SubViewportContainer's MINIMUM SIZE becomes
##    its child viewport's size (in this Control's LOGICAL units), the full-rect anchors lose to the
##    minimum, the container grows, and the next per-frame write re-inflates it ~native_scale()x. Measured
##    2026-08-25: the pass hit 7,244,550 px wide in ~20 frames — "Texture dimensions exceed device maximum",
##    then D3D12 CreateResource E_OUTOFMEMORY took every later render-target read down with it (null
##    get_image() in the QA harness). With stretch on, the container's minimum size stays zero and the
##    anchors stay in charge of nothing (top-left preset + manual rect while native).
##  - NON-COMPOSITED fallback: offscreen-only, sized straight to _viewport_pixel_size() as before (now
##    defined as RENDER px, so the two arms agree in both modes).
## The pass also mirrors the ROOT's supersample under HIGH FIDELITY (scaling_3d_scale = Settings.render_scale,
## read live) so gun and world resolve identically; RETRO keeps 1.0 — the pass never inherited the RETRO 2.0
## supersample, and matching today's pixels wins over matching the world's (the low-res blit hides the
## difference there anyway).
func _sync_pass_resolution() -> void:
	if _sub_viewport == null:
		return
	var ns := Settings.native_scale()
	var want_3d := Settings.render_scale if ns > 1.0 else 1.0
	if _sub_viewport.scaling_3d_scale != want_3d:
		_sub_viewport.scaling_3d_scale = want_3d
	if _composited:
		if _container == null:
			return
		if ns > 1.0:
			# NATIVE: container sized to the render target in logical units, scaled back onto the canvas.
			# stretch stays TRUE — see the doc block's feedback-loop warning before "simplifying" this.
			var rs := Vector2(Settings.render_size()).max(Vector2.ONE)
			var canvas := _container.get_viewport_rect().size.max(Vector2.ONE)
			if _container.anchor_right != 0.0:  # leave the full-rect preset once, on entry to the native path
				_container.set_anchors_preset(Control.PRESET_TOP_LEFT)
			if _container.position != Vector2.ZERO:
				_container.position = Vector2.ZERO
			if _container.size != rs:
				_container.size = rs  # the stretched container sizes the SubViewport to match this
			_container.scale = canvas / rs
		elif _container.anchor_right == 0.0 or _container.offset_right != 0.0:
			# RETRO restored: geometry handed back to the full-rect anchors — the pre-presentation tree.
			# MUST be the anchors_AND_OFFSETS form: plain set_anchors_preset PRESERVES the current rect by
			# rewriting the offsets (measured 2026-08-25 — the container stayed 1280x720 over a 792x444
			# canvas, drawing the gun ~1.6x oversize in RETRO after a flip), and the offset_right guard
			# re-runs this once if that state ever gets in some other way.
			_container.scale = Vector2.ONE
			_container.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	else:
		var want := _viewport_pixel_size()
		if _sub_viewport.size != want:
			_sub_viewport.size = want

## Keep the gun graded on the WORLD's tonemap, re-copying whenever the level's Environment changes IDENTITY.
## REQUIRED, not belt-and-braces — the build-time copy in build_default_environment cannot fire at boot: game.tscn's
## GameRoot loads the level with `load_level.call_deferred` from its _ready, while head.setup() queues _build_pass
## from the Player's _enter_tree, which runs FIRST. So at build time there is no WorldEnvironment in the tree yet,
## `world_env` comes back null, and the whole copy is skipped — measured 2026-08-24 with
## scripts/tools/view_model_tonemap_qa_shots.gd, which caught the gun shipping on tonemap_mode 0 (LINEAR) against
## an AgX world. The same re-copy also re-grades the gun after a LevelDoor swap brings in a differently-graded level.
## Compared by identity, not by value, so this is one group lookup per frame and a designer's live inspector edit to
## the world env is deliberately NOT chased (nothing in the project writes tonemap_* at runtime). Skipped entirely on
## an authored view_model_environment, which is the designer's verbatim look.
func _follow_world_tonemap() -> void:
	if view_model_environment != null or _gun_camera.environment == null:
		return
	var world_env := _world_environment()
	if world_env == null or world_env == _tonemap_source:
		return
	copy_tonemap(world_env, _gun_camera.environment)
	_tonemap_source = world_env

## Dim the built-in fill with the level's day/night cycle so the gun goes dark WITH the world at night. Only
## while a DayNightSky is live (group "day_night") — its absence means a static level, where the constant fill
## is correct — and never on an authored view_model_environment, which is the designer's verbatim look.
func _follow_day_night() -> void:
	if view_model_environment != null or _gun_camera.environment == null:
		return
	var dns := get_tree().get_first_node_in_group(Groups.DAY_NIGHT)
	var day := 1.0
	if dns != null and dns.has_method(&"current_day_factor"):
		day = clampf(float(dns.current_day_factor()), 0.0, 1.0)
	_gun_camera.environment.ambient_light_energy = view_model_ambient_energy * lerpf(maxf(0.0, night_fill_scale), 1.0, day)

## Copy the live camera's pose + FOV onto the gun camera so the view model tracks shake / bob /
## landing dip / strafe tilt / ADS zoom (all already baked into the main camera each frame).
func _sync_gun_camera() -> void:
	_gun_camera.global_transform = _main_camera.global_transform
	_gun_camera.fov = _main_camera.fov + fov_offset

## The root viewport's RENDER pixel size, so the gun pass matches the world's target 1:1 in either
## presentation: the native window under HIGH FIDELITY, the ~792x444 logical canvas under RETRO.
## Settings.render_size() is the one authority — get_visible_rect() alone reports the LOGICAL canvas in
## both modes (that is the design of the canvas_items size-2d override), which would under-size this pass
## ~2.4x at native. Settings also owns the off-tree/headless fallback: the 792x444 logical canvas (the
## hardcoded 396x216 that used to sit here was the pre-stretch-scale BASE size — half the real canvas
## even in RETRO).
func _viewport_pixel_size() -> Vector2i:
	return Settings.render_size()

## The Environment the gun pass renders with: the authored override when set, else a default flat-ambient FILL
## (built to match the world's tonemap) — see the class doc for WHY the view model needs its own fill.
func _resolve_view_model_environment() -> Environment:
	if view_model_environment != null:
		return view_model_environment
	_tonemap_source = _world_environment()  # null at boot (the level loads later) -> _follow_world_tonemap copies it in
	return build_default_environment(_tonemap_source, view_model_ambient_color, view_model_ambient_energy)

## The level's WorldEnvironment's Environment (group "world_environment", as camera_effects / day_night_sky use), or
## null if there isn't one yet. Read only to COPY the tonemap onto the view-model env; a missing one just means the
## gun doesn't match the world's tonemap — it still gets its ambient fill, so the pitch-black fix stands regardless.
func _world_environment() -> Environment:
	if not is_inside_tree():
		return null
	var we := get_tree().get_first_node_in_group(Groups.WORLD_ENVIRONMENT) as WorldEnvironment
	return we.environment if we != null else null

## Build the default view-model Environment: a FLAT ambient fill (colour + energy) so the gun/hands are never pitch
## black, with fog OFF (a gun 30 cm from the lens shouldn't be fogged) and a CLEAR background (the SubViewport is
## transparent_bg and composites over the world — it must never paint a sky). Copies the world env's TONEMAP when
## given, so the view model grades like the world; everything else stays default to keep the fill predictable.
## Pure (no tree / node access) so it's unit-testable in isolation.
static func build_default_environment(world_env: Environment, ambient_color: Color, ambient_energy: float) -> Environment:
	var env := Environment.new()
	env.background_mode = Environment.BG_CLEAR_COLOR              # CLEAR, not Sky — a Sky bg still DRAWS under transparent_bg (godot#84930) and would paint the world's sky over the composite; CLEAR + transparent_bg is truly transparent
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR   # a flat fill, independent of the world's ~zero ambient
	env.ambient_light_color = ambient_color
	env.ambient_light_energy = ambient_energy
	env.ambient_light_sky_contribution = 0.0
	# No fog in the view-model pass — the world's volumetric fog is its SCENE fill, meaningless on a gun at arm's length.
	env.fog_enabled = false
	env.volumetric_fog_enabled = false
	# Grade the gun like the world: copy the tonemap so it doesn't read brighter / more saturated than the tonemapped
	# world beside it (the levels use AgX). Glow / adjustments stay default to keep the flat fill predictable.
	# A null world_env (no level in the tree yet at boot, or ink_outline's deliberate null) just skips the copy —
	# the live pass then picks it up from _follow_world_tonemap once the level's WorldEnvironment exists.
	if world_env != null:
		copy_tonemap(world_env, env)
	return env

## Copy a world Environment's TONEMAP onto a view-model Environment — the one definition of "grades like the world",
## shared by the build-time path above and the per-frame _follow_world_tonemap re-sync. Tonemap ONLY: ambient, fog,
## background, glow and adjustments belong to the view-model pass and must not be dragged over from the world.
static func copy_tonemap(from: Environment, to: Environment) -> void:
	to.tonemap_mode = from.tonemap_mode
	to.tonemap_exposure = from.tonemap_exposure
	to.tonemap_white = from.tonemap_white
	# AgX — the mode the levels ship (tonemap_mode 4) — IGNORES tonemap_white and takes its curve from these two
	# instead, so copying only the three above left the gun on the AgX DEFAULTS (contrast 1.25 / white 16.29) while
	# trenchboom_test_level authors contrast 2.0: the gun's shadows sat lifted against the world composited right
	# behind it. Copied unconditionally rather than only under AgX — they are inert under every other tonemapper,
	# and a level that switches to AgX later must not silently re-open the mismatch.
	to.tonemap_agx_contrast = from.tonemap_agx_contrast
	to.tonemap_agx_white = from.tonemap_agx_white

## Restore the main camera's full cull_mask if this pass is torn down (e.g. the rig is freed), so
## the gun never disappears just because the view-model pass went away. The composite container
## lives under the HUD (not under this node), so free it here too — it would otherwise outlive us.
func _exit_tree() -> void:
	if _layer_dropped and is_instance_valid(_main_camera):
		_main_camera.cull_mask = _main_cull_mask_backup
		_layer_dropped = false
	if is_instance_valid(_container):
		_container.queue_free()
		_container = null
