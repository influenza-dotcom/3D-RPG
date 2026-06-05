class_name Attack
extends Node3D

## The Weapon's firing coordinator + the signal hub external code connects to. It owns the shot
## RESOLUTION (input gating, ammo, the penetration raycast loop, recoil, auto-reload), the reload /
## swap / holster / scope state machine, and the secondary (scoped-attack) launch — but delegates the
## stateless bits to helpers and the side systems to child components, so it stays a thin coordinator:
##   - ShotResolver (static): per-pellet math — spread, damage, hitstop scale, crit rule, decal cap.
##   - GunFX (static): the throwaway tracer / hit-spark / muzzle-flash visuals.
##   - SprayPainter (child): the spray colour picker UI + palette state.
##   - WeaponAudio (child): fire / dry-fire / shell / reload / impact sound playback.
## The components are built code-side in _ready, so off-tree (a unit-test Attack via .new() with no
## add_child) they stay null and every facade that touches them null-guards back to the monolith's
## old value.

signal spawn_projectile(_from, _direction, _visual_only: bool)
signal play_animation
signal reload_started
signal swap_started
signal swap_finished
signal flash_muzzle
signal shell_particle
signal holster_changed(on: bool)  ## weapon put away / brought back out (hold-R toggle, or dialogue)
const VISUAL_TRACER_FALLBACK_DISTANCE: float = 100.0
## Max enemies a single overkill-penetrating pellet can pierce in one shot (a runaway-loop backstop).
const MAX_OVERKILL_PENETRATIONS: int = 6
# Time the gun mesh spends raising back up after the mesh swaps. Matches the
# gun_mesh raise tween (_on_ammo_finished_reloading, 0.5s). Attacks stay blocked
# for this extra window so you can't fire mid-raise.
const SWAP_RAISE_DURATION: float = 0.5
## Brief beat before an auto_reload weapon starts its reload, so it doesn't snap in the instant the
## shot fires (matches the small fire-adjacent delay used elsewhere).
const AUTO_RELOAD_DELAY: float = 0.1

@export var character: Character
@export var inventory: Inventory
@export var muzzle: Node3D
## The ShellDrop emitter (the ejected-casing particle burst). Wired so a per-weapon
## casing_size_scale can resize the shell right before it's ejected. Optional — if unset (e.g. an
## enemy wielder with no view-model), the casing simply ejects at its authored size.
@export var shell_drop: GPUParticles3D
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

## Side systems, built code-side in _ready (null off-tree, so every facade that uses them null-guards):
## the spray colour picker + palette, and the gunfire sound playback.
var _spray: SprayPainter
var _audio: WeaponAudio

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
var _last_fire_msec: int = 0  ## Time.get_ticks_msec() of the last shot; 0 = never fired (reads as long-idle)

## Seconds since this weapon last fired (huge if it never has) — drives the view-model idle-lower in GunPose.
func seconds_since_fire() -> float:
	return float(Time.get_ticks_msec() - _last_fire_msec) / 1000.0

func _ready() -> void:
	inventory.weapon_changed.connect(_on_weapon_changed)
	# Spray colour picker + palette — its own child so this stays a thin firing hub.
	_spray = SprayPainter.new()
	_spray.host = self
	add_child(_spray)
	# Gunfire sound playback — its own child, handed the scene's audio players (our @export slots).
	_audio = WeaponAudio.new()
	add_child(_audio)
	_audio.setup(attack_audio, reload_sfx, impact, impact_enemy_hit, empty_clip, shell_impact)
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

## True while a fired shot is still resolving — the attack-cadence timer runs through the wind-up +
## cooldown. Lets ADS hold through a shot: a scoped sniper can't unscope until the shot finishes (see
## ScopeIn). Distinct from is_reload_or_swap_active, which force-breaks scope.
func is_shot_in_progress() -> bool:
	return not attack.is_stopped()

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
	GunFX.spawn_muzzle_flash(get_tree().root, muzzle_pos, col)
	# Spray hiss: play the weapon's audio but don't restart it every tick (that would stutter).
	if current_weapon.audio and not attack_audio.playing:
		attack_audio.stream = current_weapon.audio
		attack_audio.play()

## --- Spray-paint colour picker facade (forwards to the SprayPainter child) ---

## The colour the spray paints with — delegated to the picker child; white if it isn't built yet
## (off-tree), matching the monolith's no-palette default.
func _resolved_paint_color() -> Color:
	return _spray.resolved_color() if _spray else Color.WHITE

func _is_color_picker_open() -> bool:
	return _spray != null and _spray.is_open()

func _close_color_picker() -> void:
	if _spray:
		_spray.close()

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
		if not from_ai and Input.is_action_just_pressed("Attack") and _audio:
			_audio.play_empty()
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
	_last_fire_msec = Time.get_ticks_msec()  # view-model idle-lower hook (GunPose reads seconds_since_fire)
	# Fire feedback now lives on the wielder (screen shake for a player, nothing for an
	# enemy) rather than on the Weapon component.
	character.on_weapon_fired(current_weapon)

	var _hit_flash := character.get_hit_flash()
	if _hit_flash and current_weapon.projectile_life_time <= 0.0:
		_hit_flash.visible = true
		await get_tree().create_timer(0.085).timeout
		_hit_flash.visible = false

	if _audio:
		_audio.play_fire(current_weapon, ammo_before)
	if clip.current_ammo == 0 and _audio:
		_audio.play_empty()
	if _audio:
		_audio.play_shell()
	if current_weapon.spawns_casing:
		# Per-weapon casing size: resize the ejector right before it fires so this shot's shell drops at
		# the weapon's casing_size_scale (1.0 = unchanged; the sniper's fat round is authored bigger).
		if shell_drop:
			shell_drop.scale = Vector3.ONE * current_weapon.casing_size_scale
		shell_particle.emit()
	# Per-weapon impact sounds; fall back to the nodes' authored defaults when this weapon has none.
	if _audio:
		_audio.apply_impact_defaults(current_weapon)
	var _space_state := get_world_3d().direct_space_state
	# Aim comes from the wielder (its WeaponHost contract), not a Camera3D, so this same
	# fire path works for a player (camera aim) or an enemy (AI aim).
	var _ray_origin := character.get_aim_origin()
	var _spawn_point := muzzle.global_position if muzzle else _ray_origin
	var _direction := character.get_aim_direction()
	var _aim_basis := character.get_aim_basis()

	for i in range(current_weapon.pellet_count):
		var pellet_direction := ShotResolver.spread_direction(_direction, _aim_basis, current_spread)
		# Penetration trace: keep tracing along this pellet, carrying OVERKILL damage (anything beyond a
		# victim's remaining HP) on through whoever is behind them. pierce_damage < 0 marks the FIRST hit
		# (full weapon damage + crit/sneak); >= 0 is leftover overkill flowing on as flat damage. Stops at
		# a survivor, a wall/prop, or the penetration cap.
		var seg_origin := _ray_origin
		var seg_range := current_weapon.effective_range
		var exclude: Array[RID] = [character.get_rid()]
		var pierce_damage := -1.0
		var penetrations := 0
		var _visual_target := _ray_origin + pellet_direction * VISUAL_TRACER_FALLBACK_DISTANCE
		var _hit_anything := false
		while penetrations <= MAX_OVERKILL_PENETRATIONS:
			var _query := PhysicsRayQueryParameters3D.create(seg_origin, seg_origin + pellet_direction * seg_range)
			_query.exclude = exclude
			var _result := _space_state.intersect_ray(_query)
			if not _result:
				break
			_visual_target = _result.position
			_hit_anything = true
			GunFX.spawn_hit_spark(get_tree().root, _result.position, pellet_direction)
			var collider: Object = _result.collider
			var continue_pierce := false
			if collider.has_method("take_damage"):
				# The player is immune to headshots from NPCs — a one-shot to the head feels cheap. An AI
				# wielder's hit on the player is treated as a body shot; player shots and NPC-vs-NPC crits
				# are unaffected (crit_allowed encodes that rule).
				var was_crit := collider is Character and (collider as Character).is_headshot(_result.position) and ShotResolver.crit_allowed(collider, from_ai)
				# First hit uses the weapon's full damage (+ crit/sneak); a penetrating segment carries the
				# flat OVERKILL from the previous kill instead (no re-applied multipliers).
				var off_guard := collider is Character and (collider as Character).is_off_guard()
				var dmg: float = ShotResolver.resolve_damage(current_weapon, was_crit, off_guard, pierce_damage)
				var hp_before: float = (collider as Character).hp if collider is Character else 0.0
				collider.take_damage(dmg, was_crit, character)
				if collider is Character:
					(collider as Character).indicate_damage_from(_ray_origin, character)
					var hp_frac := clampf((collider as Character).hp / maxf((collider as Character).max_hp, 1.0), 0.0, 1.0)
					character.on_dealt_hit(was_crit, hp_frac)  # wielder's hit feedback: player flashes + dings; enemies no-op
					# Per-weapon hitstop on landing a hit on an enemy (tunable so a fast SMG doesn't stack freezes).
					# The BASE hold/recovery scale UP with the damage this hit dealt and again on a headshot, so a
					# sniper bodyshot barely freezes while a headshot freezes hard. Clamped so a huge overkill /
					# stacked-crit hit can't lock the game up. ONLY the player's own hits freeze — an NPC-vs-NPC
					# trade (from_ai) must not slow time during enemy infighting, so the hitstop is gated on the
					# shooter being the player (NOT from_ai).
					if not from_ai and collider is NPC and (current_weapon.hitstop_duration > 0.0 or current_weapon.hitstop_recovery > 0.0):
						var hitstop_mult := ShotResolver.hitstop_multiplier(dmg, was_crit)
						FreezeFrame.freeze(current_weapon.hitstop_duration * hitstop_mult, 0.1, current_weapon.hitstop_recovery * hitstop_mult)
					var horizontal_push := pellet_direction.normalized() * current_weapon.enemy_knockback / current_weapon.pellet_count
					var vertical_lift := Vector3.UP * current_weapon.enemy_lift / current_weapon.pellet_count
					collider.explosion_velocity += horizontal_push + vertical_lift
					if collider.get("bloody_mess"):
						# Cap per-pellet decals so multi-pellet weapons (shotgun) don't spawn dozens.
						collider.bloody_mess.splatter_at(_result.position, pellet_direction, ShotResolver.decals_per_pellet(current_weapon.pellet_count))
					# Impact-against-a-character sound, played POSITIONALLY at the hit point (not from the
					# weapon-mounted node at the hands): per-weapon enemy-impact for the player, generic for an AI
					# wielder so a distant NPC-vs-NPC trade just sounds where it happens.
					if _audio:
						_audio.play_enemy_impact(collider as Character, (collider as Character).is_headshot(_result.position), from_ai, _result.position)
					# Overkill pierces on: damage beyond the victim's HP flows into whoever's behind them.
					var overkill := dmg - hp_before
					if current_weapon.overkill_penetration and overkill > 0.0:
						pierce_damage = overkill
						seg_range = maxf(seg_range - seg_origin.distance_to(_result.position), 0.0)
						seg_origin = _result.position + pellet_direction * 0.1
						exclude.append((collider as CollisionObject3D).get_rid())
						penetrations += 1
						continue_pierce = true
				elif not collider is Interactable:
					# A take_damage-able non-character that isn't an Interactable plays the generic impact,
					# positionally at the hit point.
					if _audio:
						_audio.play_generic_impact(_result.position, from_ai)
			elif not collider is Interactable:
				if _audio:
					_audio.play_generic_impact(_result.position, from_ai)
			if collider is RigidBody3D and not (collider is Character):
				var rb := collider as RigidBody3D
				var impulse := pellet_direction.normalized() * GameSettings.physics_damage.bullet_interactable_knockback
				rb.apply_impulse(impulse, _result.position - rb.global_position)
				if rb is Interactable:
					(rb as Interactable).on_impact(GameSettings.physics_damage.interactable_impact_max_velocity)
			if continue_pierce:
				continue
			break

		var _visual_direction := (_visual_target - _spawn_point).normalized()
		spawn_projectile.emit(_spawn_point, _visual_direction, _hit_anything)
		if current_weapon.has_tracer:
			GunFX.spawn_tracer(get_tree().root, _spawn_point, _visual_target, get_viewport().get_camera_3d())

	play_animation.emit()

	# Recoil shoves the wielder back (the player uses it to rocket-jump). An NPC flagged
	# immune_to_weapon_knockback skips it, so a heavy-recoil weapon doesn't fling it around. get() is
	# null (falsy) for a wielder without the field (e.g. the player), so only flagged NPCs are immune.
	if not character.get(&"immune_to_weapon_knockback"):
		var knockback_dir := -_direction
		character.explosion_velocity += knockback_dir * current_weapon.self_knockback

	# Auto-reload: a weapon flagged for it starts a reload a short beat (AUTO_RELOAD_DELAY) after a
	# shot empties the clip — a bolt-action sniper re-chambers itself, but not jarringly instantly.
	if current_weapon.auto_reload and clip.current_ammo == 0:
		var _ar_weapon := current_weapon
		await get_tree().create_timer(AUTO_RELOAD_DELAY).timeout
		# Bail if the wielder was freed or swapped weapons during the wait; otherwise _on_reload_reload
		# self-guards (no-op if the clip is already full, or a reload/swap is underway).
		if is_inside_tree() and current_weapon == _ar_weapon:
			_on_reload_reload()


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
	# Fold any background top-up for this gun into the normal foreground reload the player just asked for.
	clip.cancel_background_reload(current_weapon)
	reload.wait_time = current_weapon.reload_time
	# Per-weapon reload sound; fall back to the node's authored default when this weapon has none.
	if _audio:
		_audio.play_reload(current_weapon)
	reload.start()
	reload_started.emit()


func _on_swap_weapons_equip_this(_weapon: WeaponData) -> void:
	if _weapon == current_weapon:
		return
	if !swap.is_stopped():
		return
	# Swapping while reloading is allowed: hand the in-progress reload to the clip as a slower
	# BACKGROUND reload for the OUTGOING weapon, so it keeps topping up while you fight with another gun.
	if !reload.is_stopped():
		clip.start_background_reload(current_weapon, reload.time_left)
		reload.stop()
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
