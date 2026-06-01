class_name Attack
extends Node3D

signal spawn_projectile(_from, _direction, _visual_only: bool)
signal play_animation
signal reload_started
signal swap_started
signal swap_finished
signal flash_muzzle
signal shell_particle
const VISUAL_TRACER_FALLBACK_DISTANCE: float = 100.0
const EXPLOSION_AREA = preload("uid://co1ehjy0gbhu3")
const HIT_SPARK_BACKOFF: float = 0.4
const HIT_SPARK_SPEED_TO_SCALE: float = 32.0
# Time the gun mesh spends raising back up after the mesh swaps. Matches the
# gun_mesh raise tween (_on_ammo_finished_reloading, 0.5s). Attacks stay blocked
# for this extra window so you can't fire mid-raise.
const SWAP_RAISE_DURATION: float = 0.5

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
var _is_scoped: bool = false
var _did_air_dash: bool = false

func _ready() -> void:
	inventory.weapon_changed.connect(_on_weapon_changed)
	current_weapon = inventory.equipped_weapon
	base_spread = current_weapon.pellet_spread
	current_spread = base_spread

func _on_weapon_changed(_weapon: WeaponData):
	current_weapon = _weapon
	base_spread = _weapon.pellet_spread
	current_spread = base_spread

func _physics_process(_delta: float) -> void:
	# Reset the per-airtime dash lock once we're back on the ground so the next
	# airtime gets a fresh launch (single_air_dash weapons, e.g. melee).
	if character and character.is_on_floor():
		_did_air_dash = false

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

func _on_mouse_input_attack(_camera: Camera3D = null, from_ai := false) -> void:
	if not current_weapon:
		return
	if !attack.is_stopped() or !reload.is_stopped() or !swap.is_stopped():
		return
	# Semi-auto weapons (e.g. melee) fire once per click instead of continuously
	# while held (MouseInput emits `attack` every frame the button is down). An AI
	# wielder (from_ai) sets its own cadence, so it skips the player input check.
	if not from_ai and not current_weapon.auto_fire and not Input.is_action_just_pressed("Attack"):
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
				collider.take_damage(current_weapon.damage * (current_weapon.headshot_multiplier if collider is Character and (collider as Character).is_headshot(_result.position) else 1.0) * (current_weapon.sneak_attack_multiplier if collider is Character and (collider as Character).is_off_guard() else 1.0))
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
