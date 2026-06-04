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
##
## RUNNABILITY: `enabled` defaults to false. While off, NOTHING changes — the main camera keeps
## its full cull_mask and still draws the gun exactly as before, so the game is unaffected. The
## main-camera layer drop happens ONLY after the SubViewport pass is fully built, and the gun is
## restored to the main camera if this node leaves the tree, so a half-built pass can never leave
## the player weaponless. Turn `enabled` on (here or in the inspector) to switch to the dedicated
## view-model camera; the one thing that needs the editor to judge is the composite ORDER vs the
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
## read slightly "longer"/closer, the classic FPS weapon look — tune to taste.
@export var fov_offset: float = 0.0

var _main_camera: Camera3D            ## the live first-person camera we mirror (CameraEffects)
var _sub_viewport: SubViewport        ## off-screen pass that renders ONLY the gun layer
var _gun_camera: Camera3D             ## camera inside _sub_viewport; masks ONLY VIEW_MODEL_LAYER
var _container: SubViewportContainer  ## composites _sub_viewport's texture over the main view
var _main_cull_mask_backup: int = 0   ## the main camera's original cull_mask, restored on exit
var _layer_dropped: bool = false      ## true once VIEW_MODEL_LAYER has been removed from the main cam
var _composited: bool = false         ## true when the SubViewport is shown via a SubViewportContainer

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

	# The gun camera: masks ONLY the view-model layer, so this pass draws the gun and nothing else.
	# It has no Environment, so the world's fog/sky don't tint the gun. current within its own
	# SubViewport (the only camera there); does NOT fight the main viewport's active camera.
	_gun_camera = Camera3D.new()
	_gun_camera.cull_mask = VIEW_MODEL_LAYER
	_gun_camera.fov = _main_camera.fov
	_gun_camera.near = _main_camera.near
	_gun_camera.far = _main_camera.far
	_gun_camera.keep_aspect = _main_camera.keep_aspect
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
## stretch=true makes the container OWN the SubViewport's size (it tracks the screen), and
## mouse-ignore means it never eats clicks. Inserted as the FIRST child of the HUD CanvasLayer so
## the post-process ColorRect (also on this layer, formerly child 0) still draws on TOP of it —
## i.e. the gun is dithered/posterised WITH the world rather than floating crisp above it. If a
## crisp (un-dithered) gun is preferred, move this above the ColorRect instead. Sets _composited.
func _attach_container(ui: CanvasLayer) -> void:
	if ui == null:
		return
	_container = SubViewportContainer.new()
	_container.name = "ViewModelComposite"
	_container.stretch = true
	_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_container.set_anchors_preset(Control.PRESET_FULL_RECT)
	_container.add_child(_sub_viewport)  # the container is the SubViewport's sole parent
	ui.add_child(_container)
	ui.move_child(_container, 0)  # draw UNDER the post-process ColorRect (HUD child 0 was that rect)
	_composited = true

func _process(_delta: float) -> void:
	if _gun_camera == null or _main_camera == null:
		return
	_sync_gun_camera()
	# Only the bare (non-composited) fallback needs manual sizing — a stretched SubViewportContainer
	# owns the size when composited, so touching it here would fight the container.
	if not _composited and _sub_viewport:
		var want := _viewport_pixel_size()
		if _sub_viewport.size != want:
			_sub_viewport.size = want

## Copy the live camera's pose + FOV onto the gun camera so the view model tracks shake / bob /
## landing dip / strafe tilt / ADS zoom (all already baked into the main camera each frame).
func _sync_gun_camera() -> void:
	_gun_camera.global_transform = _main_camera.global_transform
	_gun_camera.fov = _main_camera.fov + fov_offset

## The main viewport's current pixel size, so the gun pass renders at the same (low) internal
## resolution as the world and the composite lines up 1:1.
func _viewport_pixel_size() -> Vector2i:
	var vp := get_viewport()
	if vp:
		return Vector2i(vp.get_visible_rect().size)
	return Vector2i(396, 216)  # project's authored internal resolution as a safe fallback

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
