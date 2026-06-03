class_name Attack
extends Node3D

signal spawn_projectile(_from, _direction, _visual_only: bool)
signal play_animation
signal reload_started
signal swap_started
signal swap_finished
signal flash_muzzle
signal shell_particle
signal holster_changed(on: bool)  ## weapon put away / brought back out (hold-R toggle, or dialogue)
const VISUAL_TRACER_FALLBACK_DISTANCE: float = 100.0
const EXPLOSION_AREA = preload("uid://co1ehjy0gbhu3")
## The muzzle flash sits right at the camera, so its world-space size must be tiny (the spark
## radius used for impacts out in the world reads as screen-filling up close).
const MUZZLE_FLASH_RADIUS: float = 0.06
const HIT_SPARK_BACKOFF: float = 0.4
const HIT_SPARK_SPEED_TO_SCALE: float = 32.0
# Time the gun mesh spends raising back up after the mesh swaps. Matches the
# gun_mesh raise tween (_on_ammo_finished_reloading, 0.5s). Attacks stay blocked
# for this extra window so you can't fire mid-raise.
const SWAP_RAISE_DURATION: float = 0.5

## Which palette colour the mousewheel has selected for the spray. The splat look + decal cap now
## live on PaintProjectile (the blob the spray lobs), so they're not duplicated here.
var _paint_color_index: int = 0
var _custom_color: Color = Color.WHITE       ## last colour chosen in the right-click picker
var _use_custom_color: bool = false          ## a picker pick overrides the palette until the wheel is used again
var _color_picker_layer: CanvasLayer = null  ## lazily built on first right-click
var _color_picker: ColorPicker = null

@export var character: Character
@export var inventory: Inventory
@export var muzzle: Node3D
@export var clip: Ammo
@export var scope_in: ScopeIn

@export var attack_audio: AudioStreamPlayer3D
@export var attack: Timer
@export var reload: Timer
@export var swap: Timer
@export var reload_sfx: AudioStreamPlayer3D
@onready var shell_impact: AudioStreamPlayer3D = $ShellImpact

@export var impact: AudioStreamPlayer3D
@export var impact_enemy_hit: AudioStreamPlayer3D

@export var empty_clip: AudioStreamPlayer3D


var current_weapon: WeaponData
var base_spread: float
var current_spread: float
var _swap_raising: bool = false
var holstered: bool = false  ## weapon put away (hidden; can't fire or reload) until brought back out
var gun_raised: bool = true  ## false while the view-model tweens into view (set by GunMesh); blocks firing mid-raise
var _drew_on_press: bool = false  ## the click that drew the weapon must not also fire; cleared on release
var _is_scoped: bool = false
## Emitted the instant the air-dash lock clears on landing — i.e. the dash just became available
## again. The player listens to flash the screen + chirp a "dash ready" cue.
signal air_dash_recharged

var _did_air_dash: bool = false

func _ready() -> void:
	inventory.weapon_changed.connect(_on_weapon_changed)
	# Entering a conversation dismisses the spray colour picker (no-op for a wielder with no picker).
	DialogueManager.dialogue_started.connect(_close_picker_for_dialogue)
	current_weapon = inventory.equipped_weapon
	# A wielder may add this Weapon before equipping a WeaponData (enemies do), so current_weapon
	# can be null here — the equip fires weapon_changed a beat later and seeds the spread then.
	if current_weapon:
		base_spread = current_weapon.pellet_spread
		current_spread = base_spread

func _on_weapon_changed(_weapon: WeaponData):
	current_weapon = _weapon
	base_spread = _weapon.pellet_spread
	current_spread = base_spread
	if _is_color_picker_open():
		_close_color_picker()  # swapping weapons dismisses the spray's colour picker

## Holster (put away + hide) the weapon, or bring it back out. Hold-R toggles it; dialogue forces it.
## While holstered the weapon can't fire or reload; gun_mesh hides via the holster_changed signal.
func toggle_holster() -> void:
	set_holstered(not holstered)

func set_holstered(on: bool) -> void:
	if on == holstered:
		return
	holstered = on
	if on and _is_color_picker_open():
		_close_color_picker()  # putting the can away dismisses its colour picker
	holster_changed.emit(on)

func _physics_process(_delta: float) -> void:
	# The press that drew a holstered weapon must not fire; clear that block once it's released.
	if _drew_on_press and not Input.is_action_pressed("Attack"):
		_drew_on_press = false
	# Reset the per-airtime dash lock once we're back on the ground so the next
	# airtime gets a fresh launch (single_air_dash weapons, e.g. melee).
	if character and character.is_on_floor() and _did_air_dash:
		_did_air_dash = false
		air_dash_recharged.emit()

func can_fire() -> bool:
	return current_weapon != null and attack.is_stopped() and reload.is_stopped() and swap.is_stopped()

# Put the weapon on its normal fire cooldown without actually firing. Used by
# secondary actions (e.g. the melee launch) so they share the firing cadence.
func start_secondary_cooldown() -> void:
	if not current_weapon:
		return
	attack.wait_time = current_weapon.attack_speed
	attack.start()

# True only for "long" busy states (reload/swap) — NOT the attack cooldown
# between shots. Used to forcibly break ADS without pulsing the scope every
# time a rapid-fire weapon fires.
func is_reload_or_swap_active() -> bool:
	return not reload.is_stopped() or not swap.is_stopped()

# Whether ADS may be (re)entered right now. Launch-on-scope weapons (melee) stay
# locked out of ADS after spending their one airborne dash until they land —
# otherwise you could re-scope mid-air just to dash again.
func can_enter_scope() -> bool:
	if current_weapon and current_weapon.launch_on_scoped_attack and current_weapon.single_air_dash:
		if character and not character.is_on_floor() and _did_air_dash:
			return false
	return true

## Lob a paint blob from the muzzle on the weapon's attack cadence; it splashes a coloured decal
## wherever it lands (see PaintProjectile). No ammo, no damage — purely cosmetic graffiti.
func _do_spray_paint() -> void:
	attack.wait_time = current_weapon.attack_speed
	attack.start()
	var col := _resolved_paint_color()
	var proj := PaintProjectile.new()
	proj.velocity = character.get_aim_direction() * current_weapon.projectile_speed
	proj.shooter = character
	proj.paint_color = col
	get_tree().root.add_child(proj)
	var muzzle_pos: Vector3 = muzzle.global_position if muzzle else character.get_aim_origin()
	proj.global_position = muzzle_pos
	# Coloured muzzle flash to match the paint — reuses the bullet-hit spark, tinted (like the splat).
	var flash := EXPLOSION_AREA.instantiate()
	flash.max_explosion_force = 0.0
	flash.deals_damage = false
	flash.explosion_radius = MUZZLE_FLASH_RADIUS
	flash.speed_to_scale = 0.0  # pop at full size instantly like a real muzzle flash, no grow-in
	flash.tint_color = col
	get_tree().root.add_child(flash)
	flash.position = muzzle_pos
	# Spray hiss: play the weapon's audio but don't restart it every tick (that would stutter).
	if current_weapon.audio and not attack_audio.playing:
		attack_audio.stream = current_weapon.audio
		attack_audio.play()

## Spray-can mouse input (only while the spray is equipped): right-click opens a colour picker,
## mousewheel cycles the palette presets. Neither is bound to anything else in-game.
func _unhandled_input(event: InputEvent) -> void:
	# While the colour picker is open, ANY press except a left-click (used to pick on the wheel)
	# dismisses it instantly — a key, right-click, the wheel, anything else.
	if _is_color_picker_open():
		var dismiss := false
		if event is InputEventKey and event.is_pressed() and not event.is_echo():
			dismiss = true
		elif event is InputEventMouseButton and event.is_pressed() and (event as InputEventMouseButton).button_index != MOUSE_BUTTON_LEFT:
			dismiss = true
		if dismiss:
			_close_color_picker()
			get_viewport().set_input_as_handled()
		return
	if not (event is InputEventMouseButton):
		return
	var mb := event as InputEventMouseButton
	if not mb.pressed:
		return
	if holstered:
		return  # weapon put away — no opening the picker or cycling the spray palette
	if not current_weapon or not current_weapon.is_spray_paint:
		return
	if mb.button_index == MOUSE_BUTTON_RIGHT:
		_open_color_picker()
		get_viewport().set_input_as_handled()
		return
	var n := current_weapon.paint_colors.size()
	if n == 0:
		return
	if mb.button_index == MOUSE_BUTTON_WHEEL_UP:
		_paint_color_index = (_paint_color_index + 1) % n
		_use_custom_color = false
		get_viewport().set_input_as_handled()
	elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
		_paint_color_index = (_paint_color_index + n - 1) % n
		_use_custom_color = false
		get_viewport().set_input_as_handled()

## --- Spray-paint colour picker (right-click) ---

## The colour the spray paints with: a custom pick from the picker wins, otherwise the
## mousewheel-selected palette entry (or white if the weapon defines no palette).
func _resolved_paint_color() -> Color:
	if _use_custom_color:
		return _custom_color
	if current_weapon and current_weapon.paint_colors.size() > 0:
		return current_weapon.paint_colors[_paint_color_index % current_weapon.paint_colors.size()]
	return Color.WHITE

func _is_color_picker_open() -> bool:
	return _color_picker_layer != null and _color_picker_layer.visible

func _open_color_picker() -> void:
	if _color_picker_layer == null:
		_build_color_picker()
	_color_picker.color = _resolved_paint_color()
	_color_picker_layer.visible = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func _close_color_picker() -> void:
	if _color_picker_layer:
		_color_picker_layer.visible = false
	# Don't grab the cursor back if a conversation is taking over the mouse (it stays visible for choices).
	if not DialogueManager.is_active():
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

## Dismiss the spray colour picker when a conversation begins (connected to DialogueManager).
func _close_picker_for_dialogue() -> void:
	if _is_color_picker_open():
		_close_color_picker()

func _on_picker_color_changed(c: Color) -> void:
	_custom_color = c
	_use_custom_color = true

func _build_color_picker() -> void:
	_color_picker_layer = CanvasLayer.new()
	_color_picker_layer.layer = 100  # above the HUD
	add_child(_color_picker_layer)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE  # clicks off the picker fall through so right-click can close it
	_color_picker_layer.add_child(center)
	# Wrap in a panel so it reads as a proper menu, and trim the bulky sections (presets,
	# eyedropper, mode buttons) + use the compact wheel so it fits comfortably on screen.
	var panel := PanelContainer.new()
	center.add_child(panel)
	_color_picker = ColorPicker.new()
	_color_picker.picker_shape = ColorPicker.SHAPE_HSV_WHEEL
	_color_picker.presets_visible = false
	_color_picker.sampler_visible = false
	_color_picker.color_modes_visible = false
	_color_picker.sliders_visible = false
	_color_picker.hex_visible = false
	_color_picker.color = _resolved_paint_color()
	_color_picker.color_changed.connect(_on_picker_color_changed)
	panel.add_child(_color_picker)

func _on_mouse_input_attack(_camera: Camera3D = null, from_ai := false) -> void:
	if not current_weapon:
		return
	# Don't fire while the spray's colour picker is open — those clicks are for the picker.
	if _is_color_picker_open():
		return
	# Don't fire from player input during a conversation — the click that advances the dialogue
	# box shouldn't also shoot. AI wielders still fire (the world keeps running in real time).
	if not from_ai and DialogueManager.is_active():
		return
	if holstered:
		# Clicking with the weapon put away draws it (FNV-style); this click doesn't also fire.
		if not from_ai:
			set_holstered(false)
			_drew_on_press = true
		return
	if _drew_on_press:
		return  # still holding the draw click — release and click again to fire
	if not from_ai and not gun_raised:
		return  # view-model still raising in (reload / swap / draw) — don't fire from the low muzzle
	if !attack.is_stopped() or !reload.is_stopped() or !swap.is_stopped():
		return
	# Semi-auto weapons (e.g. melee) fire once per click instead of continuously
	# while held (MouseInput emits `attack` every frame the button is down). An AI
	# wielder (from_ai) sets its own cadence, so it skips the player input check.
	if not from_ai and not current_weapon.auto_fire and not Input.is_action_just_pressed("Attack"):
		return
	# Spray paint: tag the aimed surface with a coloured decal instead of attacking.
	if current_weapon.is_spray_paint:
		_do_spray_paint()
		return
	# Attacking while scoped launches the player instead of firing (e.g. melee
	# dash). Hip-fire falls through to the normal attack below. AI never scopes.
	if not from_ai and current_weapon.launch_on_scoped_attack and _is_scoped:
		# One dash per airtime: block a second airborne launch until you land.
		if current_weapon.single_air_dash and character and not character.is_on_floor() and _did_air_dash:
			return
		_do_launch_attack()
		return
	var ammo_before := clip.current_ammo
	if !clip.consume_ammo():
		if not from_ai and Input.is_action_just_pressed("Attack"):
			empty_clip.play()
		return
	attack.wait_time = current_weapon.attack_speed
	attack.start()
	# Wind-up: heavy weapons (melee) pause briefly after the click before the
	# swing actually lands, for weight. The cooldown already started above, so
	# this delay sits inside the normal firing cadence. 0 = instant.
	if current_weapon.attack_windup > 0.0:
		var _weapon := current_weapon
		await get_tree().create_timer(current_weapon.attack_windup).timeout
		if current_weapon != _weapon:
			return
	# The wind-up await can outlive the wielder (e.g. an enemy died mid-swing and was freed /
	# detached) — bail before touching audio or physics on a node that's left the tree.
	if not is_inside_tree():
		return
	flash_muzzle.emit()
	# Fire feedback now lives on the wielder (screen shake for a player, nothing for an
	# enemy) rather than on the Weapon component.
	character.on_weapon_fired(current_weapon)
	
	var _hit_flash := character.get_hit_flash()
	if _hit_flash and current_weapon.projectile_life_time <= 0.0:
		_hit_flash.visible = true
		await get_tree().create_timer(0.085).timeout
		_hit_flash.visible = false
	
	attack_audio.stream = current_weapon.audio
	# Cruelty-Squad-style: the fire sound deepens as the magazine empties. Uses
	# the ammo count from before this shot, so a full mag fires at full pitch.
	# Infinite-ammo weapons (melee, max_ammo <= 0) keep normal pitch.
	if current_weapon.max_ammo > 0:
		var ammo_frac := clampf(float(ammo_before) / float(current_weapon.max_ammo), 0.0, 1.0)
		attack_audio.pitch_scale = lerpf(GameSettings.audio.fire_pitch_empty_ammo, GameSettings.audio.fire_pitch_full_ammo, ammo_frac)
	else:
		attack_audio.pitch_scale = 1.0
	attack_audio.play()
	if clip.current_ammo == 0:
		empty_clip.play()
	shell_impact.play()
	if current_weapon.spawns_casing:
		shell_particle.emit()
	# Apply per-weapon impact sound overrides (null keeps the scene default).
	if current_weapon.impact_sound:
		impact.stream = current_weapon.impact_sound
	if current_weapon.impact_enemy_sound:
		impact_enemy_hit.stream = current_weapon.impact_enemy_sound
	var _space_state := get_world_3d().direct_space_state
	# Aim comes from the wielder (its WeaponHost contract), not a Camera3D, so this same
	# fire path works for a player (camera aim) or an enemy (AI aim).
	var _ray_origin := character.get_aim_origin()
	var _spawn_point := muzzle.global_position if muzzle else _ray_origin
	var _direction := character.get_aim_direction()
	var _aim_basis := character.get_aim_basis()

	for i in range(current_weapon.pellet_count):
		var pellet_direction := _direction
		var spread := current_spread
		pellet_direction = pellet_direction.rotated(
			_aim_basis.x,
			randf_range(-spread, spread)
		)
		pellet_direction = pellet_direction.rotated(
			_aim_basis.y,
			randf_range(-spread, spread)
		)
		var _to := _ray_origin + pellet_direction * current_weapon.effective_range

		var _query := PhysicsRayQueryParameters3D.create(_ray_origin, _to)
		_query.exclude = [character]
		var _result := _space_state.intersect_ray(_query)

		var _visual_target: Vector3
		if _result:
			_visual_target = _result.position
			_spawn_hit_spark(_result.position, pellet_direction)
			var collider: Object = _result.collider
			if collider.has_method("take_damage"):
				var was_crit := collider is Character and (collider as Character).is_headshot(_result.position)
				collider.take_damage(current_weapon.damage * (current_weapon.headshot_multiplier if was_crit else 1.0) * (current_weapon.sneak_attack_multiplier if collider is Character and (collider as Character).is_off_guard() else 1.0), was_crit, character)
				if collider is Character:
					(collider as Character).indicate_damage_from(_ray_origin)
					character.on_dealt_hit(collider is Character and (collider as Character).is_headshot(_result.position))  # wielder's hitmarker (player flashes; enemies no-op)
					# Per-weapon hitstop on landing a hit on an enemy (tunable so a fast SMG
					# doesn't stack freezes). Skipped for player-targets (they have their own).
					if collider is Enemy and (current_weapon.hitstop_duration > 0.0 or current_weapon.hitstop_recovery > 0.0):
						FreezeFrame.freeze(current_weapon.hitstop_duration, 0.1, current_weapon.hitstop_recovery)
					var horizontal_push := pellet_direction.normalized() * current_weapon.enemy_knockback / current_weapon.pellet_count
					var vertical_lift := Vector3.UP * current_weapon.enemy_lift / current_weapon.pellet_count
					collider.explosion_velocity += horizontal_push + vertical_lift
					if collider.get("bloody_mess"):
						# Cap per-pellet decals so multi-pellet weapons (shotgun) don't
						# spawn dozens. One decal per pellet for shotguns; full count for
						# single-shot weapons.
						var decals_per_pellet := maxi(1, int(5.0 / current_weapon.pellet_count))
						collider.bloody_mess.splatter_at(_result.position, pellet_direction, decals_per_pellet)
					_play_enemy_impact(impact_enemy_hit, collider as Character, (collider as Character).is_headshot(_result.position))
				elif not collider is Interactable:
					# Interactables (crates, gibs) play their own contextual
					# impact sound via on_impact() below — skip the weapon's
					# generic clang so e.g. gibs sound fleshy, not metallic.
					_play_impact(impact)
			elif not collider is Interactable:
				_play_impact(impact)
			if collider is RigidBody3D and not (collider is Character):
				var rb := collider as RigidBody3D
				var impulse := pellet_direction.normalized() * GameSettings.physics_damage.bullet_interactable_knockback
				rb.apply_impulse(impulse, _result.position - rb.global_position)
				if rb is Interactable:
					(rb as Interactable).on_impact(GameSettings.physics_damage.interactable_impact_max_velocity)
		else:
			_visual_target = _ray_origin + pellet_direction * VISUAL_TRACER_FALLBACK_DISTANCE

		var _visual_direction := (_visual_target - _spawn_point).normalized()
		var _hit_anything: bool = _result and not _result.is_empty()
		spawn_projectile.emit(_spawn_point, _visual_direction, _hit_anything)

	play_animation.emit()

	var knockback_dir := -_direction
	character.explosion_velocity += knockback_dir * current_weapon.self_knockback


## Generic fire entry for an AI wielder (e.g. a ranged enemy): runs the same shot as a
## player click, but without the player-input gating (semi-auto, ADS launch, empty-click).
## The AI decides cadence; aim + feedback come from the wielder's Character host contract.
func try_fire() -> void:
	_on_mouse_input_attack(null, true)


func _on_reload_reload() -> void:
	if not current_weapon:
		return
	if holstered:
		return  # can't reload a holstered weapon — unholster (hold R) first
	if !reload.is_stopped() or !swap.is_stopped():
		return
	if clip.current_ammo >= current_weapon.max_ammo:
		return
	reload.wait_time = current_weapon.reload_time
	reload_sfx.play()
	reload.start()
	reload_started.emit()


func _on_swap_weapons_equip_this(_weapon: WeaponData) -> void:
	if _weapon == current_weapon:
		return
	if !swap.is_stopped() or !reload.is_stopped():
		return
	_swap_raising = false
	swap.wait_time = GameSettings.weapon_general.swap_time
	swap.start()
	swap_started.emit()
	inventory.equip(_weapon)


func _on_swap_timeout() -> void:
	if not _swap_raising:
		# Down phase finished: swap the mesh + start the raise. Keep the swap
		# timer running for the raise so attacks stay blocked until the gun is
		# fully back up (can_fire() checks swap.is_stopped()).
		swap_finished.emit()
		_swap_raising = true
		swap.wait_time = SWAP_RAISE_DURATION
		swap.start()
	else:
		# Raise phase finished: weapon is ready, attacks re-enabled.
		_swap_raising = false


func _on_scope_in_scoped_in(_tf: bool) -> void:
	_is_scoped = _tf
	current_spread = base_spread / GameSettings.weapon_general.scope_spread_divisor if _tf else base_spread

func _do_launch_attack() -> void:
	# Launch in the look direction with a slight upward arc (blast system, so it
	# decays and lets the player ram enemies). Goes on the normal fire cooldown.
	# Dashing snaps the wielder out of ADS immediately (the cooldown then blocks an
	# instant re-scope until the dash settles).
	if scope_in:
		scope_in.force_unscope()
	# Spend the one airborne dash so you can't launch again until you land.
	if current_weapon.single_air_dash and character and not character.is_on_floor():
		_did_air_dash = true
	if character:
		var look_dir := character.get_aim_direction()
		character.explosion_velocity += look_dir * current_weapon.launch_force + Vector3.UP * current_weapon.launch_upward
		# The dash whoosh (FOV punch + shake) is wielder feedback, same idea as
		# on_weapon_fired — the player does it, an enemy needs none.
		character.on_weapon_launched(current_weapon)
	if current_weapon.whiz_sound:
		AudioManager.play_2d_sfx(current_weapon.whiz_sound, 0.0, randf_range(0.9, 1.1))
	attack.wait_time = current_weapon.attack_speed
	attack.start()


func _play_impact(player: AudioStreamPlayer3D) -> void:
	player.pitch_scale = randf_range(GameSettings.audio.impact_pitch_min, GameSettings.audio.impact_pitch_max)
	player.play()

func _play_enemy_impact(player: AudioStreamPlayer3D, enemy: Character, headshot: bool = false) -> void:
	# Pitch tracks the enemy's remaining HP — the closer to death, the deeper the
	# hit sounds. HP is already post-damage here (take_damage ran first).
	if not enemy:
		_play_impact(player)
		return
	var frac := clampf(enemy.hp / maxf(enemy.max_hp, 1.0), 0.0, 1.0)
	player.pitch_scale = lerpf(GameSettings.audio.enemy_hit_pitch_low_hp, GameSettings.audio.enemy_hit_pitch_full_hp, frac) * (1.5 if headshot else 1.0)
	player.play()

func _spawn_hit_spark(hit_pos: Vector3, hit_dir: Vector3) -> void:
	var explosion = EXPLOSION_AREA.instantiate()
	explosion.max_explosion_force = 0.0
	explosion.explosion_radius = GameSettings.effects.explosion_spark_radius
	explosion.speed_to_scale = HIT_SPARK_SPEED_TO_SCALE
	explosion.deals_damage = false
	get_tree().root.add_child(explosion)
	explosion.position = hit_pos - hit_dir.normalized() * HIT_SPARK_BACKOFF
