class_name PlayerHud
extends Node

## Owns the code-built fullscreen HUD overlays that ride on the player's UI layer — the speed-line
## vignette, the air-dash recharge flash, the directional damage arcs, the "being aimed at" radials,
## the distant-sniper glints, and the crosshair hitmarker. Built in code under the Player and given a
## host ref right after .new(); build() then constructs every overlay (parented to the player's UI so
## they draw over the post-process) and wires their cameras.
##
## The Player keeps the public facade method NAMES (indicate_damage_from / indicate_aimed_from /
## on_dealt_hit) and forwards them here; the speed-line + dash-flash drive is forwarded from the
## player's _update_falling_air / _on_air_dash_recharged. The aim-radial declutter while scoped is
## driven by ScopeCoordinator through set_aim_declutter().

const SPEED_LINES_SHADER = preload("res://resources/shaders/speed_lines.gdshader")
## SniperGlints HUD overlay (screen-space flare over distant aimers; stays visible while scoped). Loaded
## by PATH at runtime + left untyped so this parses even before the editor registers the new class_name
## in its global cache (otherwise: "Could not find type SniperGlints").
const SNIPER_GLINTS_SCRIPT := preload("res://scripts/ui/sniper_glints.gd")

const DASH_FLASH_PEAK_ALPHA: float = 0.5  ## white-flash opacity at the instant of recharge
const DASH_FLASH_TIME: float = 0.18       ## flash fade-out duration
const HURT_FLASH_PEAK_ALPHA: float = 0.4  ## red-flash opacity the instant the player takes damage
const HURT_FLASH_TIME: float = 0.32       ## red flash fade-out duration
const HURT_FLASH_COLOR := Color(0.85, 0.0, 0.0)  ## the full-screen damage flash tint

var host: Player

var _speed_lines: ColorRect  ## white speed-vignette overlay; intensity driven by movement speed
var _dash_flash: ColorRect   ## brief white full-screen flash fired when the air-dash recharges
var _hurt_flash: ColorRect   ## brief red full-screen flash fired when the player takes damage
var _damage_indicators: DamageIndicators
var _aim_indicators: AimIndicators
var _sniper_glints
var _hitmarker: Hitmarker
var _stealth_label: Label   ## Fallout-style [HIDDEN]/[DETECTED]/[DANGER] readout at the top of the screen
var _stealth_level_shown: int = -1  ## last level whose text/colour we set (so we only re-theme on a change)

## Build every overlay onto the player's UI layer, in the original _ready order: the speed vignette +
## dash flash go in FIRST so the damage arcs + crosshair draw on TOP of them. `ui` is the HUD layer the
## overlays parent to; `camera` is the active Camera3D the screen-space overlays project through.
func build(ui: Node, camera: Node3D) -> void:
	# Speed vignette: a fullscreen white-edge / air-streak overlay whose intensity tracks movement
	# speed. Added before the damage arcs + crosshair so those still draw on top of it.
	_speed_lines = ColorRect.new()
	var sl_mat := ShaderMaterial.new()
	sl_mat.shader = SPEED_LINES_SHADER
	sl_mat.set_shader_parameter("intensity", 0.0)
	_speed_lines.material = sl_mat
	_speed_lines.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.add_child(_speed_lines)
	_speed_lines.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# White full-screen flash for the air-dash recharge cue; alpha is pulsed in flash_dash().
	_dash_flash = ColorRect.new()
	_dash_flash.color = Color(1.0, 1.0, 1.0, 0.0)
	_dash_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.add_child(_dash_flash)
	_dash_flash.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# Red full-screen flash when the player takes damage; alpha is pulsed in flash_hurt().
	_hurt_flash = ColorRect.new()
	_hurt_flash.color = Color(HURT_FLASH_COLOR, 0.0)
	_hurt_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.add_child(_hurt_flash)
	_hurt_flash.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_damage_indicators = DamageIndicators.new()
	ui.add_child(_damage_indicators)
	_damage_indicators.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_damage_indicators.camera = camera
	_aim_indicators = AimIndicators.new()
	ui.add_child(_aim_indicators)
	_aim_indicators.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_aim_indicators.camera = camera
	# Sniper glint overlay: a screen-space flare over distant aimers. On the HUD (so it draws on TOP of
	# the post-process and stays crisp) and NOT hidden while scoped — you scope IN to find the sniper.
	_sniper_glints = SNIPER_GLINTS_SCRIPT.new()
	ui.add_child(_sniper_glints)
	_sniper_glints.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_sniper_glints.camera = camera
	_hitmarker = Hitmarker.new()
	ui.add_child(_hitmarker)
	_hitmarker.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# Stealth status readout (Fallout-style): a top-centre [HIDDEN]/[DETECTED]/[DANGER] label, outlined for
	# legibility over any backdrop. Hidden until the player crouches (sneaking) or something becomes aware of
	# them — see set_stealth_level — so it never clutters normal run-and-gun play.
	_stealth_label = Label.new()
	_stealth_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_stealth_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_stealth_label.add_theme_font_size_override(&"font_size", 12)
	_stealth_label.add_theme_constant_override(&"outline_size", 6)
	_stealth_label.add_theme_color_override(&"font_outline_color", Color(0.0, 0.0, 0.0, 0.85))
	_stealth_label.visible = false
	ui.add_child(_stealth_label)
	_stealth_label.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	_stealth_label.offset_top = 18.0
	_stealth_label.offset_bottom = 64.0

## Declutter the scope: hide the "being aimed at" radials while scoped. Driven by ScopeCoordinator.
func set_aim_declutter(scoped: bool) -> void:
	if _aim_indicators:
		_aim_indicators.visible = not scoped

## Drive the Fallout-style stealth readout. `level` is a StealthStatus.Level; `sneaking` is whether the player
## is crouched. Shown while sneaking OR while detected / in danger; hidden when standing + unseen so it
## doesn't sit on screen during normal play. The text + colour are re-set only when the level actually changes.
func set_stealth_level(level: int, sneaking: bool) -> void:
	if _stealth_label == null:
		return
	var should_show := sneaking or level != StealthStatus.Level.HIDDEN
	if host.is_crouching():
		_stealth_label.visible = should_show
	else:
		_stealth_label.visible = false
	if not should_show or level == _stealth_level_shown:
		return
	_stealth_level_shown = level
	match level:
		StealthStatus.Level.DANGER:
			_stealth_label.text = "[ DANGER ]"
			_stealth_label.add_theme_color_override(&"font_color", Color(1.0, 0.27, 0.22))
		StealthStatus.Level.DETECTED:
			_stealth_label.text = "[ DETECTED ]"
			_stealth_label.add_theme_color_override(&"font_color", Color(1.0, 0.82, 0.3))
		_:
			_stealth_label.text = "[ HIDDEN ]"
			_stealth_label.add_theme_color_override(&"font_color", Color(0.55, 0.82, 0.62))

## Ping the SINGLE aim radial toward `world_pos` (the shooter) when we actually take a hit — see the
## Player.indicate_damage_from doc for why this fills the gap left by the reset aim charge.
func indicate_damage_from(world_pos: Vector3, source: Object = null) -> void:
	if source != null and _aim_indicators:
		_aim_indicators.ping(source, world_pos)

## Show the red "being aimed at" radial toward `source` (grows with the 0..1 aim readiness, scaled by
## the shot's `damage`) plus the distant-sniper glint while they hold a clear shot.
func indicate_aimed_from(source: Object, world_pos: Vector3, charge: float, damage: float = 0.0, warning: bool = false, clear_shot: bool = true) -> void:
	if _aim_indicators:
		# Respect clear_shot for the radial too (not just the glint below): the instant the enemy can't
		# actually hit us — out of reach / LOS broken / out of ammo / mid-reload — clear the red ring instead
		# of letting `charge` bleed down over the fire interval. That bleed is what made the radial "linger",
		# worst for MELEE enemies whose FISTS interval (~0.88s) is long, so a foe you've side-stepped out of
		# reach kept a stale ring for the better part of a second.
		_aim_indicators.report(source, world_pos, charge if clear_shot else 0.0, damage, warning)
	if _sniper_glints:
		# The glint shows ONLY while the enemy currently has a CLEAR SHOT on us, so it clears the instant
		# they lose line of sight / range / ammo (or die) — instead of lingering at their position through
		# the slow post-shot charge bleed, which read as a "stuck" glint. Held at a floor so it doesn't
		# blink off at charge 0 right after each shot; brightness/size still ramp with the charge.
		_sniper_glints.report(source, world_pos, (maxf(charge, 0.35) if clear_shot else 0.0))

## Flash the crosshair hitmarker AND play the hit-confirm ding — see Player.on_dealt_hit for the pitch
## logic (deeper as the target nears death; a headshot drops it deeper still).
func on_dealt_hit(headshot := false, hp_frac := 1.0) -> void:
	if _hitmarker:
		_hitmarker.flash(headshot)
	# Pitch tracks the target's remaining HP (deeper as it nears death); a headshot drops it deeper
	# still (HEADSHOT_PITCH_MULT < 1.0). NOTE: this intentionally desyncs the ding from the per-weapon
	# impact-against-character sound (attack.gd / projectile.gd still pitch UP on headshot).
	var pitch := lerpf(GameSettings.audio.enemy_hit_pitch_low_hp, GameSettings.audio.enemy_hit_pitch_full_hp, hp_frac) * (Player.HEADSHOT_PITCH_MULT if headshot else 1.0)
	AudioManager.play_2d_sfx(Player.HIT_SFX, 0.0, pitch)

## Air-dash recharge cue: pulse the white screen-flash to peak alpha, then fade it out in real time.
func flash_dash() -> void:
	if _dash_flash:
		_dash_flash.color.a = DASH_FLASH_PEAK_ALPHA
		var tw := create_tween().set_ignore_time_scale(true)
		tw.tween_property(_dash_flash, "color:a", 0.0, DASH_FLASH_TIME)

## Pulse the whole screen RED for a beat when the player takes damage (peak alpha -> ease to 0). Real-time
## (ignore_time_scale) so a hit's slow-mo / death cinematic doesn't stretch the flash.
func flash_hurt() -> void:
	if _hurt_flash:
		_hurt_flash.color.a = HURT_FLASH_PEAK_ALPHA
		var tw := create_tween().set_ignore_time_scale(true)
		tw.tween_property(_hurt_flash, "color:a", 0.0, HURT_FLASH_TIME)

## Drive the speed vignette off the movement-speed intensity `t`, smoothed the same way the falling-air
## wind is (so the white air-streaks swell and fade in lockstep with it).
func drive_speed_lines(t: float, smooth: float) -> void:
	if _speed_lines:
		var sl_mat := _speed_lines.material as ShaderMaterial
		if sl_mat:
			var cur := float(sl_mat.get_shader_parameter("intensity"))
			sl_mat.set_shader_parameter("intensity", lerpf(cur, t, smooth))
