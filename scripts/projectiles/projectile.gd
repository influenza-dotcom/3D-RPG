@abstract
class_name Projectile
extends RigidBody3D

const DamageNumberPopupScript := preload("res://scripts/combat/damage_number_popup.gd")

## Abstract base for all projectiles: owns flight (direction/speed/life_time), the
## damage + knockback + impact-SFX orchestration in _on_body_entered, and the
## queued_for_deletion deletion hook. Concrete variants (Bullet, RockProjectile)
## implement the two per-variant hooks below: particles() and _spawn_decal().

var direction: Vector3 = Vector3.FORWARD
var speed: float = 8.00
var damage: float = 2.0
var headshot_multiplier: float = 2.0  # set by ProjectileSpawner from the weapon
var sneak_attack_multiplier: float = 2.0  # set by ProjectileSpawner from the weapon
var backstab_multiplier: float = 1.0  # set by ProjectileSpawner from the weapon (1.0 = inert)
var backstab_arc_degrees: float = 90.0  # set by ProjectileSpawner from the weapon
## Overkill penetration: when a hit deals more than the victim's HP, carry the excess on into whoever
## is behind instead of being consumed. Set by ProjectileSpawner from the weapon; default off here.
var overkill_penetration: bool = false
## Ragdoll knockback / lift shoved into a character on hit — set by ProjectileSpawner as the PER-PELLET share of
## the weapon's enemy_knockback / enemy_lift (so a multi-pellet projectile gun's total matches a hitscan one).
## 0 = no push (the inert default, so a projectile that's never given a weapon's value doesn't fling anything).
var enemy_knockback: float = 0.0
var enemy_lift: float = 0.0
## CT-3 on-hit status: the weapon's effect + the shot-level "apply this shot" roll, BOTH set by ProjectileSpawner
## (the projectile carries no WeaponData). Mirrors the hitscan seam so a near (hitscan) and far (projectile) hit
## of the same shot decide alike; a null effect / false roll is inert (a normal round applies nothing).
var on_hit_effect: StatusEffect = null
var apply_status: bool = false
var life_time: float = 10.0
@onready var collision_shape_3d: CollisionShape3D = $CollisionShape3D

var visual_only: bool = false
var _consumed: bool = false
## True once this round has penetrated a victim (overkill carry). The first hit scales by all the shooter's
## modifiers; every subsequent (pierced-into) victim takes the carried overkill FLAT — see _on_body_entered.
var _has_pierced: bool = false
## CT collateral parity: true once THIS round has killed a living Character, so the NEXT victim it pierces into
## and kills earns the shooter the extra collateral bounty (mirrors damage_trace's pellet_has_killed).
var _killed_character: bool = false
## Who fired this — set by ProjectileSpawner to the wielder. Used to flash their hitmarker
## (and feed the victim's damage arc) when a long-range/out-of-range projectile lands.
var shooter: Character = null

const BULLET_HOLE_DECAL = preload("uid://dh1ydtvwvgiqg")

const DECAL_SIZE: Vector3 = Vector3(0.3, 0.1, 0.3)
const DECAL_CULL_MASK: int = 1048571  # all render layers except the gun's (layer 3); layer-2-only missed walls
const PARTICLE_BACKOFF: float = 0.1
const IMPACT_BACKOFF: float = 0.4
const NORMAL_PARALLEL_THRESHOLD: float = 0.99
## The player's hit-against-a-character sound player, played at the impact point when a PLAYER-fired round
## lands on an NPC — the "you connected" feedback. NPC-fired hits use impact_generic instead.
@export var impact_enemy_hit: AudioStreamPlayer3D
## The catch-all impact sound player — walls/props, NPC-vs-anything hits, and the fallback clang. Played
## positionally at the hit point; for NPC-fired rounds its volume drops to GameSettings.audio.npc_impact_volume_db.
@export var impact_generic: AudioStreamPlayer3D

signal queued_for_deletion(_last_pos: Vector3)

func _ready() -> void:
	contact_monitor = true
	max_contacts_reported = 1
	linear_velocity = direction * speed
	if direction != Vector3.ZERO:
		look_at(global_position + direction, Vector3.UP)
	# The whiz falloff is a GLOBAL tuning knob (AudioSettings.bullet_whiz_max_distance) — stamp it onto the
	# scene's authored WhizSFX so tuning it actually changes the game. Volume deliberately stays scene-authored
	# (the pistol round's 80 dB crack vs the lobbed variants' -2 dB are per-scene mixes, not one global).
	var whiz := get_node_or_null(^"WhizSFX") as AudioStreamPlayer3D
	if whiz != null:
		whiz.max_distance = GameSettings.audio.bullet_whiz_max_distance
	await get_tree().create_timer(life_time).timeout
	if is_inside_tree():
		queue_free()

## Spawn this variant's impact particles (blood/dust for a bullet, scorch dust for a
## rocket). Called from _on_body_entered on every hit. Concrete subclasses implement.
@abstract func particles(_body, _last_velocity) -> void

func _on_body_entered(body: Node) -> void:
	if _consumed:
		return
	_consumed = true
	# The shooter can be freed mid-flight (e.g. the enemy that fired this died before the shot landed).
	# A freed reference passed to take_damage() errors, so collapse it to null = an unattributed hit.
	if not is_instance_valid(shooter):
		shooter = null
	var last_velocity := linear_velocity
	linear_velocity = Vector3.ZERO

	particles(body, last_velocity)

	if body.has_method("take_damage"):
		if !visual_only:
			# Crit + sneak assessment, pre-hit HP, and the take_damage dispatch are the SHARED hit-application
			# sequence (DamageApplier — incl. the player's immunity to NPC headshots), so a pellet and a fired
			# round land a hit through the same code. No hit position is passed (hit_pos stays the Vector3.INF
			# "no surface point" default): a flying round has never carried one — a deliberate, preserved
			# asymmetry vs the raycast path.
			var from_ai := not (shooter and shooter.is_in_group(Groups.PLAYER))
			var was_crit := DamageApplier.crit_for(body, global_position, from_ai)
			var off_guard := DamageApplier.off_guard_for(body)
			var shooter_stats: CharacterStats = shooter.stats_or_default() if shooter != null else null
			var shooter_gunplay: float = shooter.status_stat_modifier(&"gunplay") if shooter != null else 0.0  # PD-1: active gunplay buff
			# FIRST hit vs OVERKILL CARRY. Only the first hit scales by the shooter's modifiers (PD-1 stats +
			# crit/sneak/backstab in scaled_damage, PD-2 perks, ML-4 difficulty); the leftover overkill then flows
			# on as FLAT damage with NONE of them re-applied — mirroring the hitscan pierce contract
			# (damage_trace.gd's `pierce_damage < 0.0` gate) and WeaponData's documented flat carry. Without this
			# gate a piercing PLAYER round re-multiplies the carry per victim (mult^2, mult^3, …).
			var dealt: float
			if _has_pierced:
				dealt = damage  # carried overkill — already fully scaled on the first hit
			else:
				dealt = ShotResolver.scaled_damage(damage, headshot_multiplier, sneak_attack_multiplier, was_crit, off_guard, backstab_multiplier, _projectile_behind(body), shooter_stats, shooter_gunplay)  # PD-1: shooter GUNPLAY (+ active buff) scales damage
				if body is Character:  # CT-2 weakpoint: first-hit only (mirrors damage_trace.gd) — empty zone map = 1.0, inert
					dealt *= (body as Character).zone_damage_mult_at(global_position)
				if shooter != null:  # PD-2: the shooter's unlocked perks add a second damage source (live-summed; respec reverses it)
					dealt *= 1.0 + shooter.perk_combat_bonus(&"damage")
					if was_crit:
						dealt *= 1.0 + shooter.perk_combat_bonus(&"crit")
				if not from_ai:
					dealt *= GameSettings.difficulty.damage_dealt_mult  # ML-4: difficulty scales the PLAYER's outgoing damage (1.0 at Normal)
			var hp_before: float = DamageApplier.hp_before(body)
			DamageApplier.apply(body, dealt, was_crit, shooter)
			# CT-2 parity with the hitscan path (damage_trace.gd): the victim mitigates damage INSIDE take_damage
			# (armour / DR), so the HP actually lost can be LESS than `dealt`. Re-read live HP and drive the kill /
			# collateral / pierce checks off the REAL loss — else an armoured SURVIVOR is wrongly counted killed and
			# the round pierces THROUGH it. A lethal hit frees deferred, so the body still exists this frame.
			var hp_after: float = DamageApplier.hp_before(body) if is_instance_valid(body) else 0.0
			var real_loss: float = hp_before - hp_after
			if body is Character:
				DamageNumberPopupScript.show(body, real_loss, global_position, was_crit, shooter)
				# CT-3 status-on-hit, mirroring the hitscan seam (damage_trace.run_pellet): a FIRST hit (not a
				# pierce carry) on a still-alive character applies the weapon's on_hit_effect. apply_status is the
				# shot-level roll forwarded by ProjectileSpawner; a null effect short-circuits so normal rounds are inert.
				if apply_status and not _has_pierced and hp_before > 0.0 and on_hit_effect != null:
					(body as Character).apply_status_effect(on_hit_effect)
				# Knockback parity with the hitscan path (damage_trace.run_pellet): shove the victim along the round's
				# travel direction + an upward lift so projectile weapons ragdoll like hitscan ones. On every character
				# hit (incl. a pierce carry); the spawner already divided the force by pellet_count.
				var _push_dir := last_velocity.normalized() if last_velocity.length_squared() > 0.0001 else direction.normalized()
				(body as Character).explosion_velocity += _push_dir * enemy_knockback + Vector3.UP * enemy_lift
				# Mirror the hitscan path for projectile hits (the SMG and other short-range
				# weapons deal their damage out here, past the raycast's effective_range): the
				# victim's directional arc + the shooter's hitmarker (player flashes; enemies no-op).
				if shooter:
					(body as Character).indicate_damage_from(shooter.global_position, shooter)
					shooter.on_dealt_hit(body is Character and (body as Character).is_headshot(global_position), clampf((body as Character).hp / maxf((body as Character).max_hp, 1.0), 0.0, 1.0))
				# Pitch tracks the enemy's remaining HP — deeper as they near death.
				var enemy := body as Character
				var frac := clampf(enemy.hp / maxf(enemy.max_hp, 1.0), 0.0, 1.0)
				var hit_pitch := lerpf(GameSettings.audio.enemy_hit_pitch_low_hp, GameSettings.audio.enemy_hit_pitch_full_hp, frac) * (1.5 if (body as Character).is_headshot(global_position) else 1.0)
				# Overkill pierces on: if this hit has damage to spare beyond the enemy's HP, the
				# projectile survives and flies on. Decide that BEFORE the impact one-shot so a surviving
				# round plays a throwaway copy instead of reparenting/freeing its own @export node (which
				# it still needs for the next pierce).
				var overkill := maxf(dealt - hp_before, 0.0)  # carry = the PRE-mitigation excess (matches damage_trace.gd); used only on a real kill
				# COLLATERAL bounty parity with the hitscan path (damage_trace.gd): a kill by THIS round, where a
				# Character already died to it, pays the shooter an extra bounty (headshot variant on a crit). Gated on
				# the REAL post-mitigation loss (real_loss) — pre-mitigation `dealt` would pay a false-positive bounty on
				# an armoured SURVIVOR. hp_before > 0 keeps a pierce through an already-dead body from counting.
				if HitResolution.award_collateral_kill(real_loss, hp_before, was_crit, shooter, _killed_character):
					_killed_character = true  # this Character kill qualifies whoever the round pierces into next
				# Pierce ONLY on a confirmed KILL (real_loss >= hp_before, like damage_trace.gd:162) — an armoured/DR
				# SURVIVOR keeps overkill > 0 yet must NOT be pierced through. Carried magnitude is the pre-mit excess.
				var will_penetrate := overkill_penetration and real_loss >= hp_before and overkill > 0.0
				# The player ALSO hears the per-weapon impact-against-a-character (impact_enemy_hit /
				# impact_enemy_sound), HP-pitched, alongside the 2D ding from on_dealt_hit; an NPC-fired
				# round plays the positional generic impact instead (no ding for a distant NPC-vs-NPC trade).
				if shooter and shooter.is_in_group(Groups.PLAYER):
					_emit_impact(impact_enemy_hit, hit_pitch, will_penetrate)
				else:
					_emit_impact(impact_generic, hit_pitch, will_penetrate)
				# Carry the excess into whoever's behind — drop to the leftover (flat: _has_pierced makes the
				# re-entry skip ALL the shooter's mults above), ignore this body, and fly on instead of consumed.
				if will_penetrate:
					damage = overkill
					_has_pierced = true
					add_collision_exception_with(body)
					linear_velocity = last_velocity
					_consumed = false
					return
			elif not body is Throwable:
				# Throwables (crates, gibs) play their own contextual impact
				# sound via on_impact() below — skip the weapon's generic clang.
				_emit_impact(impact_generic, randf_range(GameSettings.audio.impact_pitch_min, GameSettings.audio.impact_pitch_max))
	else:
		_spawn_decal(last_velocity)
		if !visual_only:
			_emit_impact(impact_generic, randf_range(GameSettings.audio.impact_pitch_min, GameSettings.audio.impact_pitch_max))

	if not visual_only and body is RigidBody3D and not (body is Projectile):
		var rb := body as RigidBody3D
		var impulse := last_velocity.normalized() * GameSettings.physics_damage.bullet_interactable_knockback
		rb.apply_impulse(impulse, global_position - rb.global_position)
		if rb is Throwable:
			(rb as Throwable).on_impact(GameSettings.physics_damage.interactable_impact_max_velocity)

	if not visual_only:
		var hit_dir := last_velocity.normalized()
		queued_for_deletion.emit(global_position - hit_dir * IMPACT_BACKOFF)
	queue_free()

## Spawn this variant's impact decal (small bullet hole vs large scorch), oriented to
## the surface hit. Called from _on_body_entered for non-damageable bodies. Subclasses implement.
@abstract func _spawn_decal(last_velocity: Vector3) -> void


func _on_queued_for_deletion(_last_pos: Vector3) -> void:
	on_deletion()

func _orient_decal_to_normal(decal: Decal, normal: Vector3) -> void:
	var up := normal
	var z: Vector3
	if absf(up.dot(Vector3.UP)) > NORMAL_PARALLEL_THRESHOLD:
		z = Vector3.FORWARD.slide(up).normalized()
	else:
		z = Vector3.UP.slide(up).normalized()
	var x := up.cross(z).normalized()
	decal.global_transform.basis = Basis(x, up, z)

func on_deletion() -> void:
	pass

## Whether THIS projectile's shot lands in the victim's rear arc — for the backstab multiplier (mirrors the
## hitscan path). Inert (false) at the default backstab_multiplier of 1.0, or for a non-Character / missing
## shooter. Rear-arc geometry off the shooter's position vs the victim's +Z facing.
func _projectile_behind(body: Object) -> bool:
	if backstab_multiplier == 1.0 or not (body is Character) or not is_instance_valid(shooter):
		return false
	var v := body as Node3D
	return DamageApplier.is_behind(shooter.global_position, v.global_position, v.global_transform.basis.z, backstab_arc_degrees)

## Play an impact one-shot at the hit point so it outlives the projectile's queue_free. For an NPC-fired
## round the volume drops to GameSettings.audio.npc_impact_volume_db so the 3D distance attenuation applies (the
## nodes are authored very loud for always-audible PLAYER feedback, which from a distant NPC reads as a flat 2D
## blast); the player's own shots keep the authored volume.
## When the projectile DIES this hit we reparent its own @export node out to the tree root and let it
## free itself — fine, the projectile is leaving. When it SURVIVES (overkill pierce) we must NOT touch
## that node: it's still needed for the next pierce, and reparenting + freeing it would crash the 2nd
## hit. In that case spawn a throwaway copy carrying the same stream/bus/falloff at the impact point.
func _emit_impact(sfx: AudioStreamPlayer3D, pitch: float, survives: bool = false) -> void:
	if not is_instance_valid(sfx):
		return
	if sfx.stream == null:
		return  # a null-stream player never emits `finished`, so neither the one_shot clone nor the reparented sfx would free — skip
	var volume := sfx.volume_db if (shooter and shooter.is_in_group(Groups.PLAYER)) else GameSettings.audio.npc_impact_volume_db
	if survives:
		# Self-contained one-shot: clone the @export node's stream + 3D falloff at the hit point, leaving
		# the original parented to the projectile for the next pierce.
		var one_shot := AudioStreamPlayer3D.new()
		one_shot.stream = sfx.stream
		one_shot.bus = sfx.bus
		one_shot.volume_db = volume
		one_shot.unit_size = sfx.unit_size
		one_shot.max_db = sfx.max_db
		one_shot.max_distance = sfx.max_distance
		one_shot.pitch_scale = pitch
		get_tree().root.add_child(one_shot)
		one_shot.global_position = global_position
		one_shot.play()
		one_shot.finished.connect(one_shot.queue_free)
		return
	# Projectile is leaving — hand its own impact player to the root so it outlives queue_free.
	if sfx.get_parent() == self:
		sfx.reparent(get_tree().root)
	sfx.pitch_scale = pitch
	sfx.volume_db = volume
	sfx.play()
	sfx.finished.connect(sfx.queue_free)
