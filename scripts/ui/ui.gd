class_name UI
extends CanvasLayer

## HUD layer. Polls the player's HP and the Ammo clip each frame to refresh the
## labels, and owns the BloodSplatter overlay that Player.on_nearby_death drives.
## The is_instance_valid guards below matter: player/ammo can be freed during a
## death/scene reload while this layer briefly persists.

@export var player: Character
@export var ammo_count: Ammo
@export var hp: Label
@export var ammo: Label
@export var blood_splatter: BloodSplatter

var crosshair: ColorRect  ## centered white semi-transparent circle reticle; shown only while scoped (ADS)
const CROSSHAIR_SIZE := Vector2(4, 4)  ## reticle box (px); a shader discs it — smaller than the old 6px square

## Scope optics overlays: a darkening vignette + an additive anamorphic lens flare, shown only while
## scoped down the rifle (set_scope_optics). Built in _ready so they ride the same HUD layer.
const SCOPE_VIGNETTE_SHADER := preload("res://resources/shaders/scope_vignette.gdshader")
const SCOPE_FLARE_SHADER := preload("res://resources/shaders/scope_lens_flare.gdshader")
var _scope_vignette: ColorRect
var _scope_flare: ColorRect

func _ready() -> void:
	# Centered white, semi-transparent CIRCLE reticle. Hidden until ScopeIn reports scoped-in (set_scoped).
	# MOUSE_FILTER_IGNORE so it never eats clicks (HUD gotcha).
	crosshair = ColorRect.new()
	crosshair.mouse_filter = Control.MOUSE_FILTER_IGNORE
	crosshair.custom_minimum_size = CROSSHAIR_SIZE
	crosshair.size = CROSSHAIR_SIZE
	crosshair.set_anchors_preset(Control.PRESET_CENTER)
	crosshair.position = -crosshair.size * 0.5  # centre the box on the screen centre
	# A tiny canvas shader turns the box into a soft white, semi-transparent disc (a round reticle).
	var circle_mat := ShaderMaterial.new()
	circle_mat.shader = _make_circle_shader()
	crosshair.material = circle_mat
	crosshair.visible = false
	add_child(crosshair)
	# Scope optics: a vignette (darkens the edges) + a lens flare (additive anamorphic streak), both
	# full-rect, mouse-ignoring, hidden until set_scope_optics shows them on a rifle scope-in. Added
	# AFTER the crosshair so they composite on top of the rest of the HUD.
	_scope_vignette = _make_scope_overlay(SCOPE_VIGNETTE_SHADER)
	_scope_flare = _make_scope_overlay(SCOPE_FLARE_SHADER)

## Build one full-rect, input-ignoring HUD overlay carrying `shader`, hidden by default.
func _make_scope_overlay(shader: Shader) -> ColorRect:
	var rect := ColorRect.new()
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var mat := ShaderMaterial.new()
	mat.shader = shader
	rect.material = mat
	rect.visible = false
	add_child(rect)
	return rect

## A tiny canvas-item shader that fills a Control with a soft white, semi-transparent disc — the round
## ADS reticle. Built inline so it needs no .gdshader asset.
func _make_circle_shader() -> Shader:
	var sh := Shader.new()
	sh.code = "shader_type canvas_item;\nvoid fragment() {\n\tfloat d = distance(UV, vec2(0.5));\n\tCOLOR = vec4(1.0, 1.0, 1.0, (1.0 - smoothstep(0.4, 0.5, d)) * 0.6);\n}"
	return sh

## Toggle the aiming reticle with the scope state. Null-guarded so it is safe to call before
## _ready has built the dot (mirrors the is_instance_valid defensiveness in _process).
func set_scoped(scoped: bool) -> void:
	if crosshair:
		crosshair.visible = scoped

## Show/hide the rifle scope optics (vignette + lens flare). Driven by player._on_scoped_in; only the
## scoped rifle turns these on, so a generic ADS weapon still scopes without the scope-tunnel look.
func set_scope_optics(on: bool) -> void:
	if _scope_vignette:
		_scope_vignette.visible = on
	if _scope_flare:
		_scope_flare.visible = on

## Inject the player whose HP this HUD shows and the ammo clip it reads. Called once by
## the host so the HUD's cross-actor refs don't depend on scene NodePaths, which get
## cleared when this layer is extracted into its own scene.
func setup(p_player: Character, p_ammo_count: Ammo) -> void:
	player = p_player
	ammo_count = p_ammo_count

func _process(_delta: float) -> void:
	if is_instance_valid(player):
		hp.text = str(player.hp)
	
	if is_instance_valid(ammo_count):
		ammo.text = "%d" % ammo_count.current_ammo
