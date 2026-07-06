class_name CharacterPreview
extends Control

## A self-contained, live 3D CHARACTER PORTRAIT for the UI: a SubViewport rendering an isolated 3D stage (its own
## World3D, so it works at the start menu before any level loads) with a BodyModelSwap-built character on a slow
## turntable. Drop it into a menu, call set_appearance(...) with the player's chosen head/body/colours, and it
## shows exactly what the catalog would render on a real rig. Used by BOTH the character-creation screen (full
## body, while you cycle parts) and the Stats screen (a head-and-shoulders portrait of your saved look).
##
## It drives the BodyModelSwap through the catalog's configure_swap(), which sets the swap's OWN exports — so the
## preview never needs a host `look` (and can never leak a head/body into the player's first-person legs rig).
##
## LAZY BUILD: the 3D stage (SubViewport + character models) is built on the first set_active(true), NOT at _ready.
## A persistent host that's built once and mostly hidden (the Stats autoload) sets auto_start = false and only pays
## the cost the first time it's opened; a short-lived host (the creation overlay) leaves auto_start = true and it
## builds as soon as it enters the tree.

## Auto-spin the character so you can read it in the round. Off -> it holds the front-facing rest pose.
@export var auto_rotate: bool = true
## Turntable speed (radians/sec) when auto_rotate is on.
@export var spin_rate: float = 0.6
## Build + start rendering the moment this enters the tree. Persistent hosts set false and drive set_active() manually.
@export var auto_start: bool = true

var _catalog: CharacterAppearanceCatalog
var _viewport: SubViewport
var _char_root: Node3D
var _swap: BodyModelSwap
var _camera: Camera3D
var _appearance: Dictionary = {}
var _head_only: bool = false
var _built: bool = false
var _active: bool = false

func _ready() -> void:
	_catalog = CharacterAppearanceCatalog.get_catalog()
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

## Frame full-body (creation) or head-and-shoulders (Stats). Safe before build (stored, applied on build).
func set_head_only(head_only: bool) -> void:
	_head_only = head_only
	if _built:
		_apply_framing()

## Build the SubViewport stage once: an isolated World3D with ambient + a key light, a framing camera, and the
## turntable root the character mounts under. Kept in code so the whole preview is one drop-in Control.
func _ensure_built() -> void:
	if _built:
		return
	_built = true

	var container := SubViewportContainer.new()
	container.stretch = true
	container.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	container.mouse_filter = Control.MOUSE_FILTER_IGNORE  # clicks pass through to the pickers laid over/around it
	add_child(container)

	_viewport = SubViewport.new()
	_viewport.own_world_3d = true                                   # isolated world — no level needed (start menu)
	_viewport.transparent_bg = true                                 # show the menu panel behind the character
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS  # keep the turntable + breathing animating
	_viewport.msaa_3d = Viewport.MSAA_2X                            # soften the low-poly silhouette edges
	container.add_child(_viewport)

	var stage := Node3D.new()
	stage.name = "Stage"
	_viewport.add_child(stage)

	# Ambient fill + a key light so the face reads (an isolated world is otherwise pitch black).
	var env := Environment.new()
	env.background_mode = Environment.BG_CLEAR_COLOR
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.55, 0.57, 0.62)
	env.ambient_light_energy = 1.0
	var world_env := WorldEnvironment.new()
	world_env.environment = env
	stage.add_child(world_env)

	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-35.0, 35.0, 0.0)                # over-the-shoulder key from front-left-above
	key.light_energy = 1.1
	stage.add_child(key)

	_camera = Camera3D.new()
	_camera.fov = 36.0
	stage.add_child(_camera)

	_char_root = Node3D.new()
	_char_root.name = "CharRoot"
	stage.add_child(_char_root)

	_swap = BodyModelSwap.new()
	_swap.name = "PreviewBody"
	_swap.breathe = true          # a little idle life; no host velocity -> the gait stays at rest
	_swap.show_mouth = false      # a portrait shouldn't flap a talking mouth
	_char_root.add_child(_swap)

	_apply_framing()
	_rebuild_character()

func _apply_framing() -> void:
	if _camera == null:
		return
	if _head_only:
		_camera.fov = 30.0
		_camera.position = Vector3(0.0, 0.62, 1.15)
		_camera.look_at(Vector3(0.0, 0.62, 0.0))
	else:
		_camera.fov = 36.0
		_camera.position = Vector3(0.0, 0.15, 2.35)
		_camera.look_at(Vector3(0.0, 0.12, 0.0))

func _rebuild_character() -> void:
	if _catalog == null or _swap == null:
		return
	_catalog.configure_swap(_swap, _appearance)

func _process(delta: float) -> void:
	if auto_rotate and _built and is_instance_valid(_char_root):
		_char_root.rotate_y(spin_rate * delta)
