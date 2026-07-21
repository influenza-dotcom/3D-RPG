extends Node3D
## ComputerRoom — the boot scene (project main_scene): the code-built StartMenu appears first as a black
## internet-warning card, with the room timer/audio held silent behind it. After the startup gate clears, clicking
## (the Attack action) or pressing any key powers the monitor on; when the turn-on sound finishes, the menu fades in
## over the room. The menu is instanced at RUNTIME under the existing CanvasLayer, appended AFTER the CRT
## post-process ColorRect so it draws crisp above the shader and gets the mouse first; its skin backdrop is suppressed
## (show_background = false) so the room stays visible behind the buttons. From there the menu owns the rest of the
## flow (character creation, quote card, threaded load).

@onready var buzz: AudioStreamPlayer3D = $computer/Buzz
@onready var monitor_glow: OmniLight3D = $computer/MonitorGlow
@onready var ambient_dust: AmbientDust = $AmbientDust
@onready var world_environment: WorldEnvironment = $WorldEnvironment
@onready var canvas_layer: CanvasLayer = $CanvasLayer
@onready var startup_timer: Timer = $Timer

@onready var turn_on: AudioStreamPlayer3D = $computer/TurnOn
@onready var fan: AudioStreamPlayer3D = $computer/Fan

# Move constants out of _process to save CPU performance
const MINIMUM_DENSITY: float = 0.05
const DECAY_RATE: float = 0.125

## The hosted main menu. Loaded at runtime (not preload) so a broken menu script can't keep this scene from
## opening in the editor.
const START_MENU_SCENE := "res://scenes/start_menu.tscn"
const MENU_FADE_IN: float = 0.8  ## seconds the menu takes to fade in once the monitor is lit
const STARTUP_GATE_INPUT_SHIELD := 0.22

var _menu: Control = null
var _startup_gate_done := false
var _startup_input_locked := false

func _ready() -> void:
	startup_timer.stop()
	_build_menu()
	canvas_layer.visible = true
	if _menu != null:
		if _menu.has_signal(&"startup_gate_finished"):
			_menu.connect(&"startup_gate_finished", Callable(self, "_on_startup_gate_finished"))
		_menu.visible = true
	else:
		_on_startup_gate_finished()

func _input(event: InputEvent) -> void:
	if _startup_gate_done and not _startup_input_locked and not monitor_glow.visible and _is_boot_skip_event(event):
		startup_timer.stop()
		_on_turn_on_finished()
		get_viewport().set_input_as_handled()

func _is_boot_skip_event(event: InputEvent) -> bool:
	if event is InputEventKey:
		var key := event as InputEventKey
		return key.pressed and not key.echo
	if event.is_action_pressed(&"Attack"):
		return true
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		return mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT
	return false

func _on_turn_on_finished() -> void:
	canvas_layer.visible = true
	monitor_glow.visible = true
	ambient_dust.visible = true
	buzz.play()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_reveal_menu(true)

## Instance the StartMenu hidden under the CanvasLayer. add_child appends it after the post-process rect, so
## the menu draws on top (crisp, un-pixelated) and receives mouse events regardless of the rect's filter.
func _build_menu() -> void:
	var packed := load(START_MENU_SCENE) as PackedScene
	if packed == null:
		push_error("ComputerRoom: failed to load %s" % START_MENU_SCENE)
		return
	_menu = packed.instantiate() as Control
	if _menu == null:
		push_error("ComputerRoom: %s did not instantiate a Control" % START_MENU_SCENE)
		return
	_menu.set(&"show_background", false)  # duck-typed: keeps this scene free of a hard StartMenu dependency
	_menu.set(&"wait_for_host_boot", true)
	_menu.visible = false
	canvas_layer.add_child(_menu)

func _reveal_menu(fade: bool) -> void:
	if _menu == null:
		return
	if not _menu.visible:
		_menu.visible = true
	if _menu.has_method(&"reveal_hosted_menu"):
		_menu.call(&"reveal_hosted_menu")
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if fade:
		_menu.modulate.a = 0.0
		create_tween().tween_property(_menu, "modulate:a", 1.0, MENU_FADE_IN)

func _on_startup_gate_finished() -> void:
	if _startup_gate_done:
		return
	_startup_gate_done = true
	_arm_startup_input_lock()
	if Settings.debug_skip_menu or monitor_glow.visible:
		_reveal_menu(false)
	else:
		Input.mouse_mode = Input.MOUSE_MODE_HIDDEN
		startup_timer.start()

func _arm_startup_input_lock() -> void:
	_startup_input_locked = true
	var timer := get_tree().create_timer(STARTUP_GATE_INPUT_SHIELD, true)
	timer.timeout.connect(_release_startup_input_lock, CONNECT_ONE_SHOT)

func _release_startup_input_lock() -> void:
	_startup_input_locked = false

func _process(delta: float) -> void:
	if monitor_glow.visible:
		var env = world_environment.environment
		
		env.volumetric_fog_density = lerpf(
			env.volumetric_fog_density, 
			MINIMUM_DENSITY, 
			1.0 - exp(-DECAY_RATE * delta)
		)


func _on_timer_timeout() -> void:
	if not _startup_gate_done or monitor_glow.visible:
		return
	turn_on.play()
	fan.play()
