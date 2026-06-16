extends Node
## Sky-FX manager (autoload, registered as "StarSky"). Paints the level's sky at runtime with the HORIZON
## shader (horizon_sky.gdshader) and keeps the scene moody, NON-destructively (the saved .tscn is untouched).
## The level's authored skybox IMAGE is laid FLAT along the horizon (cylindrical), with a sky gradient + amber
## light-pollution haze, instead of the equirectangular SPHERE mapping that pinches it. (A level with no image
## just gets the gradient + haze.) It also pins a dim ambient + disables sky reflections so the bright sky never
## washes the scene white and the fog reads. Re-applies whenever a WorldEnvironment (group "world_environment",
## or the node type) enters the tree, covering every scene load with no scene editing.
##
## flash_kill() -- the player calls it on a kill (Player.on_dealt_hit, which ALSO does a screen-space flash) --
## spikes the shader's `flash` uniform then fades it, so the whole sky pops on a kill (Hotline Miami). Tune the
## flash timing + the night-ambient tint on GameSettings.effects (Sky FX group); tune the sky look on the
## shader's uniforms.

const HORIZON_SHADER := preload("res://resources/shaders/horizon_sky.gdshader")

## The single live sky material we drive the kill flash on. Last-painted-env wins; the shipped levels carry
## exactly one WorldEnvironment each, so this points at the visible sky. (A future additively-loaded second
## env would need flash_kill to iterate live envs instead.)
var _sky_mat: ShaderMaterial = null
var _flash_tween: Tween = null

func _ready() -> void:
	get_tree().node_added.connect(_on_node_added)
	# Cover an environment already in the tree when this autoload initialises.
	for n in get_tree().get_nodes_in_group(&"world_environment"):
		_apply_to(n)

func _on_node_added(node: Node) -> void:
	if node is WorldEnvironment or node.is_in_group(&"world_environment"):
		_apply_to(node)

## Paint the horizon sky onto a WorldEnvironment + pin the moody ambient. Idempotent.
func _apply_to(node: Node) -> void:
	var we := node as WorldEnvironment
	if we == null or we.environment == null:
		return
	var env := we.environment
	# Capture the authored skybox image (if any) as a LOCAL, BEFORE we paint over it -- no cross-scene cache
	# keyed on a recyclable Environment instance id to go stale (wrong skybox after a reload) or leak.
	var pano: Texture2D = null
	if env.sky != null and env.sky.sky_material is PanoramaSkyMaterial:
		pano = (env.sky.sky_material as PanoramaSkyMaterial).panorama
	_paint(env, pano)
	# Keep the scene moody -- never let the bright sky LIGHT it white. (Losing this is what washed it out.)
	_apply_night_ambient(env)

## Paint the horizon shader as the env's sky (idempotent), binding the authored skybox image so it can be laid
## flat along the horizon. A level with no image renders the plain gradient + haze.
func _paint(env: Environment, pano: Texture2D) -> void:
	if env.sky != null and env.sky.sky_material is ShaderMaterial and (env.sky.sky_material as ShaderMaterial).shader == HORIZON_SHADER:
		_sky_mat = env.sky.sky_material  # already ours -> keep its existing panorama binding
		return
	var mat := ShaderMaterial.new()
	mat.shader = HORIZON_SHADER
	mat.set_shader_parameter("panorama", pano)
	mat.set_shader_parameter("use_panorama", pano != null)
	var sky := Sky.new()
	sky.sky_material = mat
	env.sky = sky
	env.background_mode = Environment.BG_SKY
	_ensure_sky_visible(env)
	_sky_mat = mat

## Our shader sky needs non-zero energy to render -- the TestLevel envs ship at background_energy_multiplier = 0
## (which would black-hole the sky). Lift the pathological zero case; a real authored energy is left alone.
func _ensure_sky_visible(env: Environment) -> void:
	if env.background_mode == Environment.BG_SKY and env.background_energy_multiplier <= 0.0:
		env.background_energy_multiplier = 1.0

## The authored envs light their AMBIENT from the (bright) sky, which washes the scene white. Pin a dim fixed
## ambient (GameSettings.effects.sky_ambient_fill) + drop sky reflections so it reads moody and the fog stands
## out. Idempotent; only converts a sky-sourced ambient (a deliberately-authored fixed ambient is left alone).
func _apply_night_ambient(env: Environment) -> void:
	if env.ambient_light_source == Environment.AMBIENT_SOURCE_BG or env.ambient_light_source == Environment.AMBIENT_SOURCE_SKY:
		env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		env.ambient_light_color = GameSettings.effects.sky_ambient_fill
		env.ambient_light_energy = 1.0
	if env.reflected_light_source == Environment.REFLECTION_SOURCE_BG or env.reflected_light_source == Environment.REFLECTION_SOURCE_SKY:
		env.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED

## Flash the whole sky on a kill (Hotline Miami): spike the shader's `flash` uniform to 1, then fade it; a rapid
## second kill restarts the flash. Real-time (set_ignore_time_scale) so a kill's slow-mo doesn't stretch it and
## desync it from the HUD kill flash. Timing lives on GameSettings.effects (Sky FX group).
func flash_kill() -> void:
	if _sky_mat == null:
		return
	if _flash_tween != null and _flash_tween.is_valid():
		_flash_tween.kill()
	_flash_tween = create_tween().set_ignore_time_scale(true)
	_flash_tween.tween_property(_sky_mat, "shader_parameter/flash", 1.0, GameSettings.effects.sky_flash_up_time)
	_flash_tween.tween_property(_sky_mat, "shader_parameter/flash", 0.0, GameSettings.effects.sky_flash_down_time)
