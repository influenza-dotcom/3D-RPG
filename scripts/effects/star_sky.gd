extends Node
## Sky-FX manager (autoload, registered as "StarSky"). Paints the level's sky at runtime with the HORIZON
## shader (horizon_sky.gdshader) and keeps the scene moody, NON-destructively (the saved .tscn is untouched).
## The level's authored skybox IMAGE is laid FLAT along the horizon (cylindrical), with a sky gradient + amber
## light-pollution haze, instead of the equirectangular SPHERE mapping that pinches it. (A level with no image
## just gets the gradient + haze.) It also pins a dim ambient + disables sky reflections so the bright sky never
## washes the scene white and the fog reads. Re-applies whenever a WorldEnvironment (group "world_environment",
## or the node type) enters the tree, covering every scene load with no scene editing.
##
## TWO SKY FLASHES, one per player event, on two INDEPENDENT shader channels so neither can cut the other short:
##   flash_kill()  -- the player scored a kill  -> `flash` / `flash_color`           (ships RED, ~1 s)
##   flash_hurt()  -- the player TOOK DAMAGE    -> `hurt_flash` / `hurt_flash_color` (ships RED, shorter/partial)
## Each spikes its level uniform, HOLDS it, then fades it (Hotline Miami), and each WRITES its colour every
## trigger so the pop is the DESIGNER's colour rather than the shader's default. Both are twins of a screen-space
## flash on PlayerHud (flash_kill / flash_hurt) and both honour the Accessibility "Screen Flashes" toggle.
## Tune both channels + the night-ambient tint on GameSettings.effects (Sky FX group); tune the sky look itself on
## the shader's uniforms.

const HORIZON_SHADER := preload("res://resources/shaders/horizon_sky.gdshader")

## The single live sky material we drive the kill flash on. Last-painted-env wins; the shipped levels carry
## exactly one WorldEnvironment each, so this points at the visible sky. (A future additively-loaded second
## env would need flash_kill to iterate live envs instead.)
var _sky_mat: ShaderMaterial = null
## Live tween per flash CHANNEL, keyed by that channel's level uniform (&"flash" / &"hurt_flash"). Keyed rather
## than two fields so the channels are provably independent (a kill can never kill the hurt tween) and a third
## channel is a new key, not new plumbing.
var _channel_tweens: Dictionary = {}
## One-shot warning latch per channel, same keys: a sky material missing a channel's uniform warns ONCE for that
## channel, not once per kill / per bullet taken.
var _channel_warned: Dictionary = {}

func _ready() -> void:
	# NOTE (perf, accepted): node_added fires for EVERY node entering the tree, but the handler is a cheap
	# is-check / group lookup that early-outs on the non-env common case — no restructure (e.g. a dedicated
	# signal) is warranted for this volume.
	get_tree().node_added.connect(_on_node_added)
	# Cover an environment already in the tree when this autoload initialises.
	for n in get_tree().get_nodes_in_group(Groups.WORLD_ENVIRONMENT):
		_apply_to(n)

func _on_node_added(node: Node) -> void:
	if node is WorldEnvironment or node.is_in_group(Groups.WORLD_ENVIRONMENT):
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

## Pop the whole sky on a KILL (Hotline Miami): red, ~1 s. Fired by Player.on_scored_kill(), which is itself
## fired once per victim from Character.take_damage's lethal branch — so every kill the player is credited with
## reaches here, including a takedown, a DoT tick and a fall they caused.
func flash_kill() -> void:
	var fx := GameSettings.effects
	_run_channel(&"flash", &"flash_color", fx.sky_flash_color, fx.sky_flash_peak,
			fx.sky_flash_up_time, fx.sky_flash_hold_time, fx.sky_flash_down_time)

## Wash the whole sky RED when the player TAKES DAMAGE. Fired from Player.take_damage — the single funnel every
## damage vector in the game already goes through (enemy fire, explosions, hazards, status DoT, falls), so this
## needs no per-source wiring, exactly like the kill cue.
##
## Ships SHORTER and PARTIAL where the kill flash is long and total, and that asymmetry is deliberate: you take
## damage an order of magnitude more often than you kill, so a solid red sky held for a second would sit red
## through an entire firefight and smear into the kill flash's own red. Tune it to match the kill flash exactly
## (peak 1.0, same three times) if you want them symmetrical -- but then the two cues stop reading apart at all.
func flash_hurt() -> void:
	var fx := GameSettings.effects
	_run_channel(&"hurt_flash", &"hurt_flash_color", fx.sky_hurt_color, fx.sky_hurt_peak,
			fx.sky_hurt_up_time, fx.sky_hurt_hold_time, fx.sky_hurt_down_time)

## Drive ONE sky-flash channel: write its colour, then tween its level up -> HOLD -> back to 0, replacing any beat
## already running on that channel (a rapid re-trigger restarts it rather than stacking two tweens on one uniform).
## Channels are keyed by `level_param`, so the kill and hurt beats never touch each other's tween.
##
## Real-time (set_ignore_time_scale) so a kill's slow-mo doesn't stretch the beat and desync it from the
## screen-space twin on PlayerHud.
##
## Accessibility: the "Screen Flashes" toggle (Options -> Accessibility, read live) suppresses EVERY whole-sky pop
## for photosensitive players — checked here so it covers each channel by construction, and the twin PlayerHud
## flashes honour the same flag, so a kill / a hit is fully flash-free when it's off.
##
## Guards the tween: a sky material whose shader doesn't expose this channel's level uniform — a non-horizon env,
## or a STALE / failed shader compile after an editor reimport — would otherwise spam "property does not exist"
## plus a no-Tweeners error on EVERY trigger. Skip gracefully (warn once per channel); it self-heals once the
## horizon shader is live again.
func _run_channel(level_param: StringName, color_param: StringName, color: Color, peak: float,
		up: float, hold: float, down: float) -> void:
	if not Settings.screen_flash_enabled:
		return
	if _sky_mat == null or not _has_param(level_param):
		if _sky_mat != null and not bool(_channel_warned.get(level_param, false)):
			_channel_warned[level_param] = true
			push_warning("StarSky: the sky material exposes no `%s` shader param — skipping that sky flash (the sky shader isn't horizon_sky.gdshader, or it needs a reimport)." % level_param)
		return
	# Re-assert the COLOUR on every trigger rather than once at paint time, for two reasons: the designer's colour
	# stays live-tunable in the Remote inspector mid-fight, and _paint's "already ours" early-out (which
	# deliberately keeps an existing panorama binding) can never strand a stale colour on a re-entered environment.
	# Skipped silently on a sky shader that declares the level uniform but not the colour one — the pop still
	# happens in the shader's OWN default colour, which degrades to a wrong hue rather than to nothing.
	if _has_param(color_param):
		_sky_mat.set_shader_parameter(color_param, color)
	var previous: Tween = _channel_tweens.get(level_param, null)
	if previous != null and previous.is_valid():
		previous.kill()
	# Three beats — up / SUSTAIN / down — mirroring Character._build_flash_tween's per-part hit flash. The sustain
	# is what makes a long beat read as a COLOUR: with only up+down, a ~1 s flash is a slow ramp THROUGH the colour
	# that the eye reads as the sky brightening, not as the sky turning red. Interval only when it is actually
	# held, so a designer zeroing the hold gets a clean two-beat tween instead of a degenerate 0 s tweener.
	var prop := "shader_parameter/" + String(level_param)
	# SEED THE LEVEL UNIFORM BEFORE TWEENING IT, or the flash never renders at all.
	# A ShaderMaterial PUBLISHES a `shader_parameter/<uniform>` property for every uniform its shader declares,
	# but `get()` on one returns Nil until something ASSIGNS it — a shader-side default
	# (horizon_sky.gdshader's `uniform float flash ... = 0.0`) is NOT copied into the material's param_cache.
	# _paint() seeds only panorama/use_panorama, so `flash` / `hurt_flash` start Nil. tween_property reads the
	# property for its INITIAL value, gets Nil, and the tweener dies with
	#   "Type mismatch between initial and final value: Nil and float"
	# once per tween_property call — twice per trigger, every trigger. _has_param() cannot catch this: it
	# matches on property NAME, which IS published, so the guard above passes. And because the tween never
	# runs, nothing ever writes the uniform, so it stays Nil forever — it can never self-heal.
	if _sky_mat.get(prop) == null:
		_sky_mat.set_shader_parameter(level_param, 0.0)
	var t := create_tween().set_ignore_time_scale(true)
	t.tween_property(_sky_mat, prop, clampf(peak, 0.0, 1.0), up)
	if hold > 0.0:
		t.tween_interval(hold)
	t.tween_property(_sky_mat, prop, 0.0, down)
	_channel_tweens[level_param] = t

## True when the live sky material actually exposes shader uniform `uniform_name`, so tweening / setting
## shader_parameter/<uniform_name> is valid. A ShaderMaterial publishes one `shader_parameter/<uniform>` property
## per declared uniform, so the material's own property list is exactly what the tween validates against (no
## shader-introspection guesswork). Used for ALL FOUR flash uniforms across the two channels (kill: `flash` /
## `flash_color`, hurt: `hurt_flash` / `hurt_flash_color`): the LEVEL one is TWEENED — a missing one errors
## per-frame — and the COLOUR one is SET, where a missing one is silent, which is exactly why it's checked too.
func _has_param(uniform_name: StringName) -> bool:
	var prop := "shader_parameter/" + String(uniform_name)
	for p in _sky_mat.get_property_list():
		if p.get("name", "") == prop:
			return true
	return false
