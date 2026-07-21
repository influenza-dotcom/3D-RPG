class_name CharacterPreview
extends Control

## A self-contained, live 3D CHARACTER SHOWCASE for the UI — a Dota-2-style "hero view": a SubViewport rendering an
## isolated 3D stage (its own World3D, so it works at the start menu before any level loads) with a BodyModelSwap-
## built character standing on a lit PEDESTAL, over a soft radial BACKDROP, under a three-point STUDIO light rig,
## with tonemap + bloom. Drop it into a menu, call set_appearance(...) with the player's chosen head/body/colours,
## and it shows exactly what the catalog would render on a real rig. Used by the character-creation screen (full
## body, while you cycle parts), the Stats screen (a head-and-shoulders portrait), and the fullscreen
## CharacterInspectScreen (full body + the equipped weapon in hand).
##
## It drives the BodyModelSwap through the catalog's configure_swap(), which sets the swap's OWN exports — so the
## preview never needs a host `look` (and can never leak a head/body into the player's first-person legs rig). The
## swap parents under a tiny duck-typed host (character_preview_host.gd) so a mounted weapon can raise the arms into
## the two-handed hold, exactly like an NPC (see set_weapon()).
##
## INTERACTION (allow_interaction): the character sits on a slow, gentle TURNTABLE at all times; LEFT-DRAG spins it
## by hand (the drift pauses while you drag and resumes on release), and the MOUSE WHEEL dollies the camera in/out.
## Fully hands-off with allow_interaction off — then it's just the gentle turntable.
##
## FRAMING is AUTOMATIC: after each rebuild the character's geometry AABB is measured (reusing ItemMeshView's static
## helper) and the camera is fit to it — full-body or head-and-shoulders — and the pedestal is dropped to the feet.
## So swapping to a taller head / a whole-body model / adding a weapon reframes cleanly with no hand-tuned numbers.
##
## LAZY BUILD: the 3D stage (SubViewport + character models) is built on the first set_active(true), NOT at _ready.
## A host that's mostly hidden sets auto_start = false and only pays the cost the first time it's shown — the Stats
## autoload does, and so does the creation overlay (its Look/Shirt tab previews activate via _sync_previews only
## while their tab is the visible one). A host that's visible from birth can leave auto_start = true instead.

## The measure/AABB helper is shared with the item mesh tiles so the character frames by the SAME geometry-only rule
## (GeometryInstance3D minus particles) — no class_name on it, so preload by path.
const ItemMeshView := preload("res://scripts/ui/item_mesh_view.gd")
## The duck-typed stand-in the swap parents under (answers is_holding_gun / velocity / is_on_floor). Path-preloaded,
## no class_name — a private preview helper.
const PreviewHost := preload("res://scripts/ui/character_preview_host.gd")

## Gently rotate the character so you can read it in the round. Off -> it holds the front-facing rest pose (drag
## still turns it when allow_interaction is on).
@export var auto_rotate: bool = true
## Turntable speed (radians/sec) of the gentle idle drift — kept subtle on purpose (a slow showcase spin, not a fan).
@export var spin_rate: float = 0.35
## Build + start rendering the moment this enters the tree. Persistent hosts set false and drive set_active() manually.
@export var auto_start: bool = true
## Let the player LEFT-DRAG to spin the character and WHEEL to zoom. Off -> display-only (the gentle turntable only).
@export var allow_interaction: bool = true
## Show the lit pedestal disc under the feet. Auto-suppressed in head-only framing (the feet aren't in shot anyway).
@export var show_pedestal: bool = true
## Draw the soft radial backdrop behind the character (dark vignette, lit centre). Off -> the menu panel shows through.
@export var show_backdrop: bool = true

# --- Studio light rig energies (colours/angles are fixed in _ensure_built; expose the energies for quick tuning) ---
## Key light strength — the main warm front-left-above light (casts the character's shadow onto the pedestal).
@export var key_energy: float = 1.35
## Fill light strength — the cool front-right light that softens the shadow side. Keep it well below the key.
@export var fill_energy: float = 0.55
## Rim/back light strength — the bright light from behind that separates the silhouette from the backdrop.
@export var rim_energy: float = 1.8

# --- Weapon in hand (set via set_weapon) ------------------------------------------------------------------------
## Where the mounted weapon sits, in CHARACTER-LOCAL space (+Z is the character's forward / toward the camera). The
## arms raise into the two-handed hold and the gun floats at this anchor — nudge it into the hands. Mirrors the NPC
## rig, where the held model hangs off a hand-anchor Marker3D at an authored offset.
@export var weapon_hand_offset: Vector3 = Vector3(0.08, 0.1, 0.28)
## Corrective rotation (degrees) mapping the weapon view-model's business-end onto the character's +Z forward —
## same default as the NPC hand mount (weapon_mesh_rotation). Overridden per weapon by WeaponData.npc_hold_override.
@export var weapon_hand_rotation: Vector3 = Vector3(0.0, -90.0, 0.0)

var _catalog: CharacterAppearanceCatalog
var _backdrop: TextureRect          ## the radial-gradient vignette drawn BEHIND the SubViewport (Control-space, theme-free)
var _viewport: SubViewport
var _stage: Node3D                   ## the fixed studio: lights + pedestal + camera live here (do NOT rotate)
var _char_root: Node3D              ## the TURNTABLE — the host + swap + weapon anchor mount here and spin together
var _swap: BodyModelSwap
var _hand: Marker3D                 ## weapon hand anchor (child of _char_root, so the gun turns with the character)
var _weapon_mesh: Node3D            ## the currently-mounted weapon view-model (freed + rebuilt per set_weapon)
var _camera: Camera3D
var _appearance: Dictionary = {}
var _weapon: WeaponData = null       ## the weapon to render in hand (null -> unarmed; arms rest)
var _head_only: bool = false
var _built: bool = false
var _active: bool = false

# Framing + interaction state.
var _cam_target: Vector3 = Vector3.ZERO   ## look-at point from the last auto-frame
var _cam_dir: Vector3 = Vector3(0.0, 0.12, 1.0).normalized()  ## fixed studio view direction (front, slightly above)
var _cam_base_dist: float = 2.4            ## fit distance from the AABB; _zoom scales it
var _zoom: float = 1.0                      ## wheel dolly multiplier on _cam_base_dist (clamped)
var _dragging: bool = false

const ZOOM_MIN := 0.55
const ZOOM_MAX := 1.7
const DRAG_SENSITIVITY := 0.011  ## radians of turntable yaw per pixel of horizontal drag

func _ready() -> void:
	_catalog = CharacterAppearanceCatalog.get_catalog()
	_build_backdrop()  # behind the (later-added) viewport; shows even before the 3D stage is lazily built
	if auto_start:
		set_active(true)
	else:
		set_process(false)  # nothing to spin until built + activated

## Start/stop the live render + turntable. The FIRST set_active(true) also lazily builds the 3D stage. A persistent
## host set_active(false) while closed so the SubViewport isn't rendering off-screen every frame.
func set_active(active: bool) -> void:
	_active = active
	if active:
		_ensure_built()
	if _viewport != null:
		_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS if active else SubViewport.UPDATE_DISABLED
	set_process(active and _built)

## Show `appearance` (the GameState-style dict: head/body ids + skin/arm/leg Colours; empty = the shipped default).
## Safe to call before the stage is built (stored, applied on build) and every time the player cycles a part.
func set_appearance(appearance: Dictionary) -> void:
	_appearance = appearance.duplicate()
	if _built:
		_rebuild_character()

## Frame full-body (creation / inspect) or head-and-shoulders (Stats). Safe before build (stored, applied on build).
func set_head_only(head_only: bool) -> void:
	_head_only = head_only
	if _built:
		_rebuild_character()  # reframes + toggles the pedestal

## Show `weapon` in the character's hands (the equipped WeaponData; null -> unarmed). The arms raise into the
## two-handed hold (via the preview host's is_holding_gun) and the weapon's view-model hangs off the hand anchor,
## exactly like the NPC rig. Safe before build (stored, applied on build).
func set_weapon(weapon: WeaponData) -> void:
	_weapon = weapon
	if _built:
		_mount_weapon()

## The soft radial vignette behind the character — a Control-space gradient (independent of the 3D world's own
## transparent background), so the character always reads against a controlled dark backdrop instead of the raw
## menu panel. Built once; toggled by show_backdrop.
func _build_backdrop() -> void:
	if not show_backdrop:
		return
	var grad := Gradient.new()
	grad.set_color(0, Color(0.17, 0.18, 0.22))   # lit-ish centre behind the figure
	grad.set_color(1, Color(0.04, 0.045, 0.06))  # near-black edges -> a soft vignette
	var tex := GradientTexture2D.new()
	tex.gradient = grad
	tex.width = 256
	tex.height = 256
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(1.0, 0.5)  # radius reaches the horizontal edge
	_backdrop = TextureRect.new()
	_backdrop.texture = tex
	_backdrop.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_backdrop.stretch_mode = TextureRect.STRETCH_SCALE  # fill the whole rect with the gradient
	_backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_backdrop)  # FIRST child -> drawn behind the SubViewportContainer added later

## Build the SubViewport stage once: an isolated World3D with a studio Environment (ambient + tonemap + bloom), a
## three-point light rig, a framing camera, the pedestal, and the turntable root the character mounts under. Kept
## in code so the whole showcase is one drop-in Control.
func _ensure_built() -> void:
	if _built:
		return
	_built = true

	var container := SubViewportContainer.new()
	container.stretch = true
	container.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	container.mouse_filter = Control.MOUSE_FILTER_IGNORE  # this Control's _gui_input owns drag/zoom; the container passes through
	add_child(container)

	_viewport = SubViewport.new()
	_viewport.own_world_3d = true                                   # isolated world — no level needed (start menu); Ps1Warp never walks it
	_viewport.transparent_bg = true                                 # composite the character over our own backdrop, not the world
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS  # keep the turntable + breathing animating
	_viewport.msaa_3d = Viewport.MSAA_4X                            # crisp low-poly silhouette edges, esp. at fullscreen inspect
	container.add_child(_viewport)

	_stage = Node3D.new()
	_stage.name = "Stage"
	_viewport.add_child(_stage)

	_build_environment()
	_build_lights()

	_camera = Camera3D.new()
	_camera.fov = 34.0
	_stage.add_child(_camera)

	_build_pedestal()

	# The TURNTABLE: the host + swap + weapon anchor spin together here; the pedestal/lights/camera stay fixed under
	# the stage, so the character rotates on a static pedestal (the Dota hero-view feel).
	_char_root = PreviewHost.new()
	_char_root.name = "CharRoot"
	_stage.add_child(_char_root)

	_swap = BodyModelSwap.new()
	_swap.name = "PreviewBody"
	_swap.breathe = true          # a little idle life; no host velocity -> the gait stays at rest
	_swap.show_mouth = false      # a showcase shouldn't flap a talking mouth
	_char_root.add_child(_swap)

	_hand = Marker3D.new()
	_hand.name = "WeaponHand"
	_char_root.add_child(_hand)

	_rebuild_character()

## The studio Environment: modest cool ambient so the rim/key read, ACES tonemapping, and a subtle bloom so the
## bright rim light glows. Isolated in this SubViewport's own world — the global Ps1Warp only
## walks LevelRoots, so it never touches this.
func _build_environment() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_CLEAR_COLOR  # transparent_bg cuts the actual pixels; this just seeds ambient/tonemap
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.34, 0.36, 0.42)
	env.ambient_light_energy = 0.7
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_exposure = 1.0
	env.glow_enabled = true
	env.glow_intensity = 0.35
	env.glow_bloom = 0.05
	env.glow_hdr_threshold = 1.0
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_ADDITIVE
	var world_env := WorldEnvironment.new()
	world_env.environment = env
	_stage.add_child(world_env)

## A three-point rig: a warm KEY (front-left-above, the only shadow-caster, so the figure grounds onto the
## pedestal), a cool FILL (front-right, softens the shadow side), and a bright RIM/back light (behind, separates
## the silhouette from the dark backdrop). Energies are exported for quick tuning.
func _build_lights() -> void:
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-38.0, 40.0, 0.0)
	key.light_color = Color(1.0, 0.95, 0.88)
	key.light_energy = key_energy
	key.shadow_enabled = true
	_stage.add_child(key)

	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-12.0, -55.0, 0.0)
	fill.light_color = Color(0.72, 0.80, 0.95)
	fill.light_energy = fill_energy
	_stage.add_child(fill)

	var rim := DirectionalLight3D.new()
	rim.rotation_degrees = Vector3(-32.0, 200.0, 0.0)  # from behind-above, raking toward the camera
	rim.light_color = Color(0.85, 0.90, 1.0)
	rim.light_energy = rim_energy
	_stage.add_child(rim)

## The pedestal: a low dark disc the character stands on. Positioned/sized to the feet in _rebuild_character
## (from the measured AABB). Hidden in head-only framing. (No emissive accent ring — it read as a stray glowing
## white circle around the figure; the plain dark disc grounds the character without the halo.)
func _build_pedestal() -> void:
	var disc := MeshInstance3D.new()
	disc.name = "Pedestal"
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.7
	cyl.bottom_radius = 0.78
	cyl.height = 0.08
	disc.mesh = cyl
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.10, 0.11, 0.14)
	mat.metallic = 0.3
	mat.roughness = 0.6
	disc.material_override = mat
	_stage.add_child(disc)

func _rebuild_character() -> void:
	if _catalog == null or _swap == null:
		return
	_catalog.configure_swap(_swap, _appearance)
	_mount_weapon()
	_frame_to_character()  # measure -> auto-frame the camera + drop the pedestal to the feet

## Mount (or clear) the equipped weapon's view-model in the hand and raise/lower the arms accordingly. Mirrors the
## NPC hand mount (npc.gd _build_weapon_mesh): parent the view_model under the hand anchor with the corrective
## rotation, or the weapon's own npc_hold_override pose when it authors one. Never shown in head-only framing.
func _mount_weapon() -> void:
	if is_instance_valid(_weapon_mesh):
		_weapon_mesh.queue_free()
		_weapon_mesh = null
	var host := _char_root as Object
	var show_gun := _weapon != null and not _head_only and _weapon.view_model != null
	if host != null:
		host.set(&"holding", show_gun)  # raise the arms into the two-handed hold only when a gun is actually shown
	if not show_gun:
		return
	var inst: Node = _weapon.view_model.instantiate()
	if not (inst is Node3D):
		if inst != null:
			inst.free()
		return
	_weapon_mesh = inst
	_hand.position = weapon_hand_offset
	_hand.add_child(_weapon_mesh)
	# A weapon may author an NPC hand-hold override (its FP view-model root bakes a first-person pose); honour it,
	# else just correct the yaw and let it sit at the anchor — the same branch the NPC rig uses.
	if _weapon.npc_hold_override:
		_weapon_mesh.position = _weapon.npc_hold_position
		_weapon_mesh.rotation_degrees = _weapon.npc_hold_rotation
		_weapon_mesh.scale = Vector3.ONE * _weapon.npc_hold_scale
	else:
		_weapon_mesh.rotation_degrees = weapon_hand_rotation

## Measure the built character and fit the camera to it (full body or head-and-shoulders), then sit the pedestal on
## the feet. Robust to any appearance/weapon swap — no hand-tuned per-model numbers. Falls back to fixed framing if
## the measure comes back empty (headless / a model with no geometry).
func _frame_to_character() -> void:
	var aabb := ItemMeshView.measure_aabb(_swap)  # geometry-only bounds, in _swap-local space (== _char_root space)
	var pedestal := _stage.get_node_or_null(^"Pedestal") as MeshInstance3D
	if aabb.size.y <= 0.001:
		# No measurable geometry (headless test / empty catalog): keep the shipped fallback framing.
		_cam_target = Vector3(0.0, 0.62, 0.0) if _head_only else Vector3(0.0, 0.12, 0.0)
		_cam_base_dist = 1.2 if _head_only else 2.4
		if pedestal != null:
			pedestal.visible = false
		_apply_camera()
		return

	var centre := aabb.position + aabb.size * 0.5
	var feet_y := aabb.position.y
	var top_y := aabb.position.y + aabb.size.y

	if _head_only:
		# Frame the head-and-shoulders: aim near the top of the figure and fit a slice ~a third of its height.
		_cam_target = Vector3(centre.x, top_y - aabb.size.y * 0.14, centre.z)
		_cam_base_dist = _fit_distance(aabb.size.y * 0.34, maxf(aabb.size.x, aabb.size.z))
		if pedestal != null:
			pedestal.visible = false  # feet aren't in shot
	else:
		_cam_target = centre
		_cam_base_dist = _fit_distance(aabb.size.y, maxf(aabb.size.x, aabb.size.z))
		if pedestal != null and show_pedestal:
			pedestal.visible = true
			pedestal.position = Vector3(centre.x, feet_y - 0.02, centre.z)  # top of the disc just under the feet
			var pr: float = maxf(0.35, maxf(aabb.size.x, aabb.size.z) * 0.75)
			_size_pedestal(pedestal, pr)
		elif pedestal != null:
			pedestal.visible = false
	_apply_camera()

## Camera distance that fits a frame of `frame_h` tall (and `frame_w` wide, aspect-corrected) at the current fov,
## with headroom. KEEP_HEIGHT projection: fit the height, and widen the distance if the width would overflow.
func _fit_distance(frame_h: float, frame_w: float) -> float:
	var half_fov := deg_to_rad(_camera.fov) * 0.5
	var vp_size := _viewport.size if _viewport != null else Vector2i(400, 500)
	var aspect := maxf(0.2, float(vp_size.x)) / maxf(1.0, float(vp_size.y))
	var need_h := (frame_h * 0.5) / tan(half_fov)
	var need_w := (frame_w * 0.5) / (tan(half_fov) * aspect)
	return maxf(need_h, need_w) * 1.25  # 1.25 = breathing room around the figure

## Resize the pedestal disc to radius `r`.
func _size_pedestal(disc: MeshInstance3D, r: float) -> void:
	var cyl := disc.mesh as CylinderMesh
	if cyl != null:
		cyl.top_radius = r
		cyl.bottom_radius = r * 1.1

## Place the (fixed) camera along the studio view direction at the zoomed fit distance, looking at the frame target.
func _apply_camera() -> void:
	if _camera == null or not _camera.is_inside_tree():
		return
	var dist: float = _cam_base_dist * _zoom
	_camera.position = _cam_target + _cam_dir * dist
	_camera.look_at(_cam_target)

func _process(delta: float) -> void:
	# The gentle idle turntable: always drifting unless the player is actively dragging it.
	if auto_rotate and _built and not _dragging and is_instance_valid(_char_root):
		_char_root.rotate_y(spin_rate * delta)

## Left-drag spins the turntable by hand; the mouse wheel dollies the camera. Runs only with allow_interaction on
## (the container child is MOUSE_FILTER_IGNORE, so gui input lands here on this Control).
func _gui_input(event: InputEvent) -> void:
	if not allow_interaction or not _built:
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			_dragging = mb.pressed
			accept_event()
		elif mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_UP:
			_zoom = clampf(_zoom * 0.9, ZOOM_MIN, ZOOM_MAX)   # wheel up -> closer
			_apply_camera()
			accept_event()
		elif mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_zoom = clampf(_zoom * 1.1, ZOOM_MIN, ZOOM_MAX)   # wheel down -> farther
			_apply_camera()
			accept_event()
	elif event is InputEventMouseMotion and _dragging and is_instance_valid(_char_root):
		var mm := event as InputEventMouseMotion
		_char_root.rotate_y(-mm.relative.x * DRAG_SENSITIVITY)  # drag right -> spin the front toward you
		accept_event()
