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

var host: Player

var _speed_lines: ColorRect  ## white speed-vignette overlay; intensity driven by movement speed
var _dash_flash: ColorRect   ## brief white full-screen flash fired when the air-dash recharges
var _hurt_flash: ColorRect   ## brief red full-screen flash fired when the player takes damage
var _kill_flash: ColorRect   ## brief full-screen flash fired on a kill (sky-independent -> shows over the skybox)
var _dash_flash_tween: Tween  ## cached so a rapid re-fire kills the prior fade instead of stacking overlapping tweens
var _hurt_flash_tween: Tween
var _kill_flash_tween: Tween
var _damage_indicators: DamageIndicators
var _aim_indicators: AimIndicators
var _sniper_glints
var _hitmarker: Hitmarker
var _stealth_label: Label   ## Fallout-style [HIDDEN]/[DETECTED]/[DANGER] readout at the top of the screen
var _stealth_level_shown: int = -1  ## last level whose text/colour we set (so we only re-theme on a change)
var _detection_bar: ProgressBar  ## the graded detection "heat" meter under the label (0..1, the worst NPC's)
var _takedown_label: Label   ## Slice 6b: "[key] Take Down <name>" prompt, shown only while an unaware NPC is in takedown range
var _takedown_bar: ProgressBar  ## the hold-progress fill under the takedown prompt (0..1)
var _pet_label: Label   ## "[key] Pet <name>" prompt, shown only while a Pettable object is in pet range (PetInteraction)
var _pet_bar: ProgressBar  ## the hold-progress fill under the pet prompt (0..1)
var _claim_label: Label   ## "[key] Claim/Unclaim <name>" prompt, shown only while a Claimable object is in range (ClaimInteraction)
var _claim_bar: ProgressBar  ## the hold-progress fill under the claim prompt (0..1; ONLY the HOLD-to-unclaim path fills it — a claim is a tap)

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
	_hurt_flash.color = Color(GameSettings.player_feedback.hurt_flash_color, 0.0)
	_hurt_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.add_child(_hurt_flash)
	_hurt_flash.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# Full-screen flash when the player gets a KILL (Hotline Miami); sky-independent so it shows over the
	# skybox too. Alpha is pulsed in flash_kill().
	_kill_flash = ColorRect.new()
	_kill_flash.color = Color(GameSettings.player_feedback.kill_flash_color, 0.0)
	_kill_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.add_child(_kill_flash)
	_kill_flash.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
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
	# Graded detection "heat" bar just under the label: a slim 0..1 fill that rises with the worst NPC's
	# detection meter, so you can SEE how close you are to being spotted (not just the 3 binary states). Same
	# crouch-gated visibility rule as the label — see set_detection_meter. Default ProgressBar look; restyle later.
	_detection_bar = ProgressBar.new()
	_detection_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_detection_bar.min_value = 0.0
	_detection_bar.max_value = 1.0
	_detection_bar.show_percentage = false
	_detection_bar.custom_minimum_size = Vector2(120.0, 6.0)
	_detection_bar.visible = false
	ui.add_child(_detection_bar)
	_detection_bar.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_detection_bar.offset_top = 40.0
	_detection_bar.offset_left = -60.0
	_detection_bar.offset_right = 60.0
	# Slice 6b takedown cue: a centre "[key] Take Down <name>" prompt + a hold-progress fill, shown only while an
	# unaware NPC is in takedown range (driven by SilentTakedown via Player.set_takedown_cue). Hidden otherwise.
	_takedown_label = Label.new()
	_takedown_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_takedown_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_takedown_label.add_theme_font_size_override(&"font_size", 13)
	_takedown_label.add_theme_constant_override(&"outline_size", 6)
	_takedown_label.add_theme_color_override(&"font_outline_color", Color(0.0, 0.0, 0.0, 0.85))
	_takedown_label.visible = false
	ui.add_child(_takedown_label)
	_takedown_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_takedown_label.offset_top = 96.0
	_takedown_label.offset_left = -180.0
	_takedown_label.offset_right = 180.0
	_takedown_bar = ProgressBar.new()
	_takedown_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_takedown_bar.min_value = 0.0
	_takedown_bar.max_value = 1.0
	_takedown_bar.show_percentage = false
	_takedown_bar.custom_minimum_size = Vector2(120.0, 5.0)
	_takedown_bar.visible = false
	ui.add_child(_takedown_bar)
	_takedown_bar.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_takedown_bar.offset_top = 116.0
	_takedown_bar.offset_left = -60.0
	_takedown_bar.offset_right = 60.0
	# Pet cue: a centre "[key] Pet <name>" prompt + hold fill, shown only while a Pettable object is in pet range
	# (driven by PetInteraction via Player.set_pet_cue). Its OWN widgets (not the takedown's) so the two verbs never
	# clobber each other's cue; placed at the SAME centre-top spot — they're mutually exclusive (object vs NPC) so
	# only one is ever visible at a time, giving a single consistent prompt location.
	_pet_label = Label.new()
	_pet_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_pet_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_pet_label.add_theme_font_size_override(&"font_size", 13)
	_pet_label.add_theme_constant_override(&"outline_size", 6)
	_pet_label.add_theme_color_override(&"font_outline_color", Color(0.0, 0.0, 0.0, 0.85))
	_pet_label.visible = false
	ui.add_child(_pet_label)
	_pet_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_pet_label.offset_top = 96.0
	_pet_label.offset_left = -180.0
	_pet_label.offset_right = 180.0
	_pet_bar = ProgressBar.new()
	_pet_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_pet_bar.min_value = 0.0
	_pet_bar.max_value = 1.0
	_pet_bar.show_percentage = false
	_pet_bar.custom_minimum_size = Vector2(120.0, 5.0)
	_pet_bar.visible = false
	ui.add_child(_pet_bar)
	_pet_bar.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_pet_bar.offset_top = 116.0
	_pet_bar.offset_left = -60.0
	_pet_bar.offset_right = 60.0

	# Claim/Unclaim prompt (driven by ClaimInteraction via Player.set_claim_cue). Placed ABOVE the pet/takedown prompt
	# (offset 96) with its own hold bar just under it (76), so an object that is BOTH claimable AND pettable — the dog
	# — shows both stacked ("[T] Befriend Dog" over "[Q] Pet Dog") with no overlap. The bar fills only on a HOLD-to-
	# unclaim (a befriend is a tap), shown between the label (56) and the pet cluster (96).
	_claim_label = Label.new()
	_claim_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_claim_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_claim_label.add_theme_font_size_override(&"font_size", 13)
	_claim_label.add_theme_constant_override(&"outline_size", 6)
	_claim_label.add_theme_color_override(&"font_outline_color", Color(0.0, 0.0, 0.0, 0.85))
	_claim_label.visible = false
	ui.add_child(_claim_label)
	_claim_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_claim_label.offset_top = 56.0
	_claim_label.offset_left = -180.0
	_claim_label.offset_right = 180.0
	_claim_bar = ProgressBar.new()
	_claim_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_claim_bar.min_value = 0.0
	_claim_bar.max_value = 1.0
	_claim_bar.show_percentage = false
	_claim_bar.custom_minimum_size = Vector2(120.0, 5.0)
	_claim_bar.visible = false
	ui.add_child(_claim_bar)
	_claim_bar.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_claim_bar.offset_top = 76.0
	_claim_bar.offset_left = -60.0
	_claim_bar.offset_right = 60.0

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
	# `sneaking` is the player's is_crouching() (player.gd), so should_show already means "sneaking OR
	# detected/in danger" — the contract in this func's docstring. Gate visibility on it directly; an earlier
	# `if is_crouching()` wrapper dropped the detected-while-STANDING half, hiding the readout mid-firefight.
	var should_show := sneaking or level != StealthStatus.Level.HIDDEN
	_stealth_label.visible = should_show
	if not should_show or level == _stealth_level_shown:
		return
	_stealth_level_shown = level
	match level:
		StealthStatus.Level.DANGER:
			_stealth_label.text = "[ DANGER ]"
			_stealth_label.add_theme_color_override(&"font_color", Color(1.0, 0.27, 0.22))
		StealthStatus.Level.CAUTION:
			_stealth_label.text = "[ CAUTION ]"
			_stealth_label.add_theme_color_override(&"font_color", Color(1.0, 0.6, 0.2))
		StealthStatus.Level.DETECTED:
			_stealth_label.text = "[ DETECTED ]"
			_stealth_label.add_theme_color_override(&"font_color", Color(1.0, 0.82, 0.3))
		_:
			_stealth_label.text = "[ HIDDEN ]"
			_stealth_label.add_theme_color_override(&"font_color", Color(0.55, 0.82, 0.62))

## Drive the detection "heat" bar off `meter` (0..1, the worst NPC's detection of us). Crouch-gated like the
## label, and only while there's actually some heat, so it stays off during normal play. The fill warms green ->
## red with the meter (via self_modulate) for an at-a-glance read of how close you are to being spotted.
func set_detection_meter(meter: float, sneaking: bool) -> void:
	if _detection_bar == null:
		return
	var m := clampf(meter, 0.0, 1.0)
	# Accessibility/declutter: the player can hide the heat bar entirely (Options > Accessibility > Show
	# Detection Meter, persisted via Settings). Default on -> unchanged. The [ HIDDEN/DETECTED/DANGER ] label
	# stays regardless; this only governs the graded fill bar.
	var show := Settings.detection_meter_enabled and sneaking and m > 0.001 and host.is_crouching()
	_detection_bar.visible = show
	if not show:
		return
	_detection_bar.value = m
	_detection_bar.self_modulate = Color(0.55, 0.82, 0.62).lerp(Color(1.0, 0.27, 0.22), m)

## Force the stealth readout OFF (label + detection bar hidden). Called by Player.die() so the last-shown
## [ DANGER ]/[ CAUTION ] state can't ride into the death cinematic or get remembered by ui.hide_hud_for_death()
## and RESTORED onto the fresh life — the exact bug the look-at readout already dodges via its die()-side
## _apply_look_readout(null) clear. Resets the cached level so the next life re-themes the label from scratch.
func clear_stealth_readout() -> void:
	_stealth_level_shown = -1
	if _stealth_label != null:
		_stealth_label.visible = false
	if _detection_bar != null:
		_detection_bar.visible = false

## Slice 6b: drive the takedown prompt + hold-progress. `active` shows "[key] Take Down <name>" (text) plus the
## hold fill (progress 0..1, the bar appears once the hold starts); inactive hides both. Driven every frame by
## SilentTakedown via Player.set_takedown_cue.
func set_takedown_cue(active: bool, text: String, progress: float) -> void:
	if _takedown_label == null:
		return
	_takedown_label.visible = active
	_takedown_bar.visible = active and progress > 0.001
	if not active:
		return
	_takedown_label.text = text
	_takedown_bar.value = clampf(progress, 0.0, 1.0)

## Drive the PET prompt + hold-progress (the friendly twin of set_takedown_cue). `active` shows "[key] Pet <name>"
## plus the hold fill (the bar appears once the hold starts); inactive hides both. Driven every frame by
## PetInteraction via Player.set_pet_cue.
func set_pet_cue(active: bool, text: String, progress: float) -> void:
	if _pet_label == null:
		return
	_pet_label.visible = active
	_pet_bar.visible = active and progress > 0.001
	if not active:
		return
	_pet_label.text = text
	_pet_bar.value = clampf(progress, 0.0, 1.0)

## Drive the CLAIM/UNCLAIM prompt. `active` shows the text; `progress` fills the bar only on a HOLD-to-unclaim (a
## claim is a tap, passed progress 0 → bar hidden). Driven every frame by ClaimInteraction via Player.set_claim_cue.
func set_claim_cue(active: bool, text: String, progress: float) -> void:
	if _claim_label == null:
		return
	_claim_label.visible = active
	_claim_bar.visible = active and progress > 0.001
	if not active:
		return
	_claim_label.text = text
	_claim_bar.value = clampf(progress, 0.0, 1.0)

## Force every interaction prompt cue OFF (takedown / pet / claim label + hold bar). Called by Player.die() for the
## SAME reason as clear_stealth_readout(): each cue is driven per-frame by a SEPARATE Player-child interaction node
## (SilentTakedown / PetInteraction / ClaimInteraction) that keeps running after the player's set_physics_process(false),
## so a prompt visible at the instant of death would be remembered by ui.hide_hud_for_death() and re-shown STALE by
## restore_hud_after_death() on the in-place revive. Reuses the existing facades (inactive => label + bar hidden).
func clear_interaction_cues() -> void:
	set_takedown_cue(false, "", 0.0)
	set_pet_cue(false, "", 0.0)
	set_claim_cue(false, "", 0.0)

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
		if _dash_flash_tween != null and _dash_flash_tween.is_valid():
			_dash_flash_tween.kill()
		_dash_flash.color.a = GameSettings.player_feedback.dash_flash_peak_alpha
		_dash_flash_tween = create_tween().set_ignore_time_scale(true)
		_dash_flash_tween.tween_property(_dash_flash, "color:a", 0.0, GameSettings.player_feedback.dash_flash_time)

## Pulse the whole screen RED for a beat when the player takes damage (peak alpha -> ease to 0). Real-time
## (ignore_time_scale) so a hit's slow-mo / death cinematic doesn't stretch the flash.
func flash_hurt() -> void:
	if _hurt_flash:
		if _hurt_flash_tween != null and _hurt_flash_tween.is_valid():
			_hurt_flash_tween.kill()
		_hurt_flash.color.a = GameSettings.player_feedback.hurt_flash_peak_alpha
		_hurt_flash_tween = create_tween().set_ignore_time_scale(true)
		_hurt_flash_tween.tween_property(_hurt_flash, "color:a", 0.0, GameSettings.player_feedback.hurt_flash_time)

## Kill flash: a quick full-screen colour pop when the player lands a kill (Hotline Miami). Independent of the
## sky shader, so it shows over the authored skybox too. Real-time (ignore_time_scale) so a kill's slow-mo
## doesn't stretch it.
func flash_kill() -> void:
	if _kill_flash:
		if _kill_flash_tween != null and _kill_flash_tween.is_valid():
			_kill_flash_tween.kill()
		_kill_flash.color = Color(GameSettings.player_feedback.kill_flash_color, GameSettings.player_feedback.kill_flash_peak_alpha)
		_kill_flash_tween = create_tween().set_ignore_time_scale(true)
		_kill_flash_tween.tween_property(_kill_flash, "color:a", 0.0, GameSettings.player_feedback.kill_flash_time)

## Drive the speed vignette off the movement-speed intensity `t`, smoothed the same way the falling-air
## wind is (so the white air-streaks swell and fade in lockstep with it).
func drive_speed_lines(t: float, smooth: float) -> void:
	if _speed_lines:
		var sl_mat := _speed_lines.material as ShaderMaterial
		if sl_mat:
			var cur := float(sl_mat.get_shader_parameter("intensity"))
			sl_mat.set_shader_parameter("intensity", lerpf(cur, t, smooth))
