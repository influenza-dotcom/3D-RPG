class_name DamageTrace

## The per-pellet PIERCE-TRACE walk, split off attack.gd's fire coroutine. One pellet's whole journey lives here:
## the segment-walk raycast, hit FX, damage application
## (through DamageApplier + ShotResolver), victim/wielder feedback, hitstop, knockback, decals, impact audio,
## and the overkill pierce-through that carries leftover damage into whoever is behind the kill.
##
## Stateless static in the ShotResolver / GunFX / DamageApplier mold. Every tree-dependent handle (space
## state, FX root, camera) is sampled ONCE by the caller and passed in — a static must not fetch them, and
## the bare-Attack unit tests never reach here. The per-pellet RESULT is returned (visual_target /
## hit_anything / hit_npc) rather than emitted: spawn_projectile must keep firing from the Attack node
## (weapon.tscn wires it there) and the reckless-fire reaction needs the whole shot's hit_npc.

## Max enemies a single overkill-penetrating pellet can pierce in one shot (a runaway-loop backstop).
const MAX_OVERKILL_PENETRATIONS: int = 6

## Trace one pellet from `ray_origin` along `pellet_direction` and apply everything it does to the world.
## `audio` is the wielder's WeaponAudio child or null (an off-tree/bare wielder has none — every use is
## guarded). Returns { "visual_target": Vector3, "hit_anything": bool, "hit_npc": bool } for the caller's
## projectile-visual emit, tracer, and post-shot reaction.
## `range_mult` scales the pellet's reach off the weapon's hip-fire effective_range — the caller passes
## > 1.0 while the wielder is aiming down sights (ADS) so a scoped shot connects farther; 1.0 = hip fire.
static func run_pellet(space_state: PhysicsDirectSpaceState3D, fx_root: Node, camera: Camera3D,
		weapon: WeaponData, character: Character, ray_origin: Vector3, pellet_direction: Vector3,
		from_ai: bool, audio, range_mult: float = 1.0, apply_status: bool = false) -> Dictionary:
	# Penetration trace: keep tracing along this pellet, carrying OVERKILL damage (anything beyond a
	# victim's remaining HP) on through whoever is behind them. pierce_damage < 0 marks the FIRST hit
	# (full weapon damage + crit/sneak); >= 0 is leftover overkill flowing on as flat damage. Stops at
	# a survivor, a wall/prop, or the penetration cap.
	var seg_origin := ray_origin
	var seg_range := weapon.effective_range * range_mult
	var exclude: Array[RID] = [character.get_rid()]
	var pierce_damage := -1.0
	## True once a CHARACTER has died to this pellet — the precondition for any later hit counting as a
	## COLLATERAL kill. A Throwable (gib / crate) popping mid-chain carries the overkill on but neither sets
	## nor clears this: shooting THROUGH a crate into your first victim isn't collateral (no prior kill),
	## while enemy -> gib -> enemy still is (the first enemy died to the same pellet).
	var pellet_has_killed := false
	var penetrations := 0
	var visual_target: Vector3 = ray_origin + pellet_direction * GameSettings.weapon_general.visual_tracer_fallback_distance
	var hit_anything := false
	var hit_npc := false
	while penetrations <= MAX_OVERKILL_PENETRATIONS:
		var _query := PhysicsRayQueryParameters3D.create(seg_origin, seg_origin + pellet_direction * seg_range)
		_query.exclude = exclude
		var _result := space_state.intersect_ray(_query)
		if not _result:
			break
		visual_target = _result.position
		hit_anything = true
		GunFX.spawn_hit_spark(fx_root, _result.position, pellet_direction)
		# Overkill feedback: when this hit carries leftover damage PIERCING from a prior kill
		# (pierce_damage >= 0; < 0 marks the first hit), draw a tracer down the pierce segment + a bigger
		# burst where it lands, so the player can actually SEE the overkill punch through.
		if pierce_damage >= 0.0:
			GunFX.spawn_tracer(fx_root, seg_origin, _result.position, camera)
			GunFX.spawn_overkill_burst(fx_root, _result.position, pellet_direction)
		var collider: Object = _result.collider
		var continue_pierce := false
		if collider.has_method("take_damage"):
			# Crit + sneak assessment, pre-hit HP, and the take_damage dispatch are the SHARED hit-
			# application sequence (DamageApplier — incl. the player's immunity to NPC headshots), so a
			# hitscan pellet and a fired round land a hit through the same code.
			var was_crit := DamageApplier.crit_for(collider, _result.position, from_ai)
			# First hit uses the weapon's full damage (+ crit/sneak); a penetrating segment carries the
			# flat OVERKILL from the previous kill instead (no re-applied multipliers).
			var off_guard := DamageApplier.off_guard_for(collider)
			# Backstab: only a first hit (pierce < 0), only when the weapon enables it (multiplier != 1.0) and
			# the victim is a facing Character — rear-arc geometry off the shooter's position. resolve_damage
			# folds in the weapon's backstab_multiplier when `behind`. Inert at the default 1.0 multiplier.
			var behind := false
			if pierce_damage < 0.0 and weapon.backstab_multiplier != 1.0 and collider is Character:
				var v := collider as Node3D
				behind = DamageApplier.is_behind(character.global_position, v.global_position, v.global_transform.basis.z, weapon.backstab_arc_degrees)
			var dmg: float = ShotResolver.resolve_damage(weapon, was_crit, off_guard, pierce_damage, behind, character.stats_or_default(), character.status_stat_modifier(&"gunplay"))  # PD-1: shooter's GUNPLAY (+ active buff) scales damage (baseline = no-op)
			# CT-2 weakpoint: a FIRST hit (not overkill pierce) is scaled by the victim's per-zone multiplier
			# (empty map -> 1.0, so inert by default). First-hit-only, like crit/backstab — overkill carries flat.
			if pierce_damage < 0.0 and collider is Character:
				dmg *= (collider as Character).zone_damage_mult_at(_result.position)
			# PD-2: the SHOOTER's unlocked perks add a second damage source (live-summed, so a respec reverses it).
			# First-hit only (pierce < 0), like the stat scaling; crit perks stack their bonus on a headshot.
			if pierce_damage < 0.0:
				dmg *= 1.0 + character.perk_combat_bonus(&"damage")
				if was_crit:
					dmg *= 1.0 + character.perk_combat_bonus(&"crit")
				if not from_ai:
					dmg *= GameSettings.difficulty.damage_dealt_mult  # ML-4: difficulty scales the PLAYER's outgoing damage (1.0 at Normal)
			var hp_before: float = DamageApplier.hp_before(collider)
			DamageApplier.apply(collider, dmg, was_crit, character, _result.position)
			# CT-2 fix: the victim mitigates damage INSIDE take_damage (armour / DR), so the HP actually lost can be
			# LESS than dmg. Re-read live HP and drive the kill check / overkill pierce / hitstop off the REAL loss
			# (`dealt`), not the pre-mitigation dmg — otherwise an armoured SURVIVOR is wrongly counted killed and the
			# pellet pierces THROUGH it. A lethal hit queue_frees deferred, so the body still exists this frame with
			# hp <= 0; the validity guard covers a synchronously-freed node. For a non-armoured victim dealt == dmg.
			var hp_after: float = DamageApplier.hp_before(collider) if is_instance_valid(collider) else 0.0
			var dealt: float = hp_before - hp_after
			# CT-3 status-on-hit: a FIRST hit (not overkill pierce) on a still-alive character applies the weapon's
			# on-hit StatusEffect (the chemistry substrate). The shot-level roll happens once in the caller
			# (apply_status); apply_effect refreshes by id, so a multi-pellet hit refreshes rather than stacks.
			if apply_status and pierce_damage < 0.0 and hp_before > 0.0 and collider is Character and weapon.on_hit_effect != null:
				(collider as Character).apply_status_effect(weapon.on_hit_effect)
			# COLLATERAL bounty: a kill made by CARRIED overkill, where a CHARACTER already died to this
			# same pellet (pellet_has_killed — a gib/crate popping mid-chain doesn't qualify the NEXT victim
			# as collateral on its own), pays the shooter an EXTRA 2 zm on top of the normal kill bounty —
			# 4 when the collateral blow itself was a headshot. hp_before > 0 keeps a pierce through an
			# already-dead body from counting; every Character has a wallet now, so an NPC's collateral
			# earns into its lootable pocket the same as the player's.
			if collider is Character and hp_before > 0.0 and dealt >= hp_before:
				if pellet_has_killed:
					# Sizes are designer knobs — resources/tuning/EconomySettings.tres.
					var collateral_pay: float = GameSettings.economy.collateral_headshot_bounty if was_crit \
							else GameSettings.economy.collateral_bounty
					character.reward_kill(collateral_pay)
					if character.has_method(&"notify_toast"):
						character.notify_toast("Collateral kill!  +%s zm" % Zorkmids.fmt(collateral_pay), Color(1.0, 0.86, 0.3))
				pellet_has_killed = true  # this Character kill qualifies whoever dies BEHIND them
			if collider is NPC:
				hit_npc = true  # the shot connected with an NPC — suppresses the wielder's reckless-fire remark
			# Toast the player whether THIS shot landed as a sneak attack (target off-guard) or not.
			# Player shots only; the wielder throttles it so a burst/multi-pellet shot shows one line.
			if not from_ai and collider is Character and character.has_method(&"notify_sneak_result"):
				character.notify_sneak_result(off_guard)
			if collider is Character:
				(collider as Character).indicate_damage_from(ray_origin, character)
				var hp_frac := clampf((collider as Character).hp / maxf((collider as Character).max_hp, 1.0), 0.0, 1.0)
				character.on_dealt_hit(was_crit, hp_frac)  # wielder's hit feedback: player flashes + dings; enemies no-op
				# Per-weapon hitstop on landing a hit on an enemy (tunable so a fast SMG doesn't stack freezes).
				# The BASE hold/recovery scale UP with the damage this hit dealt and again on a headshot, so a
				# sniper bodyshot barely freezes while a headshot freezes hard. Clamped so a huge overkill /
				# stacked-crit hit can't lock the game up. ONLY the player's own hits freeze — an NPC-vs-NPC
				# trade (from_ai) must not slow time during enemy infighting, so the hitstop is gated on the
				# shooter being the player (NOT from_ai).
				if not from_ai and collider is NPC and (weapon.hitstop_duration > 0.0 or weapon.hitstop_recovery > 0.0):
					var hitstop_mult := ShotResolver.hitstop_multiplier(dealt, was_crit)
					# NOTE: the 0.1 here is FreezeFrame's hold-to-recovery ease (a fixed feel constant), left
					# hardcoded — not a per-weapon designer knob worth a WeaponData or GameSettings field.
					FreezeFrame.freeze(weapon.hitstop_duration * hitstop_mult, 0.1, weapon.hitstop_recovery * hitstop_mult)
				var horizontal_push := pellet_direction.normalized() * weapon.enemy_knockback / weapon.pellet_count
				var vertical_lift := Vector3.UP * weapon.enemy_lift / weapon.pellet_count
				collider.explosion_velocity += horizontal_push + vertical_lift
				if collider.get("bloody_mess"):
					# Cap per-pellet decals so multi-pellet weapons (shotgun) don't spawn dozens.
					collider.bloody_mess.splatter_at(_result.position, pellet_direction, ShotResolver.decals_per_pellet(weapon.pellet_count))
				# Impact-against-a-character sound, played POSITIONALLY at the hit point (not from the
				# weapon-mounted node at the hands): per-weapon enemy-impact for the player, generic for an AI
				# wielder so a distant NPC-vs-NPC trade just sounds where it happens.
				if audio:
					audio.play_enemy_impact(collider as Character, (collider as Character).is_headshot(_result.position), from_ai, _result.position)
			elif not (collider is Throwable):
				# A take_damage-able non-character that isn't a Throwable plays the generic impact,
				# positionally at the hit point.
				if audio:
					audio.play_generic_impact(_result.position, from_ai)
			# Overkill pierces on — Characters AND Throwables (gibs especially): damage beyond the victim's
			# HP flows into whoever's behind them. ONE shared block (it was copy-pasted per type); anything
			# else (a destructible prop) stops the pellet exactly as before.
			# Overkill pierces ONLY on a confirmed KILL (dealt >= hp_before — the same real-kill condition the
			# collateral block above uses). The kill gate is ESSENTIAL: `dmg` is PRE-mitigation, so an armoured/DR
			# SURVIVOR (mitigation dropped dealt below hp_before) still has dmg - hp_before > 0 — without the gate the
			# pellet would pierce THROUGH a living target (the CT-2 bug). Carried magnitude = the pre-mitigation
			# excess (matches projectile.gd:134); on a kill, dmg >= hp_before so it's >= 0.
			if (collider is Character or collider is Throwable) and weapon.overkill_penetration and hp_before > 0.0 and dealt >= hp_before:
				var overkill := maxf(dmg - hp_before, 0.0)
				if overkill > 0.0:
					pierce_damage = overkill
					seg_range = maxf(seg_range - seg_origin.distance_to(_result.position), 0.0)
					# NOTE: the 0.1 nudges the next segment's origin just past the hit point so the re-cast
					# doesn't immediately re-hit the same surface — a fixed geometry epsilon, not a designer knob.
					seg_origin = _result.position + pellet_direction * 0.1
					exclude.append((collider as CollisionObject3D).get_rid())
					penetrations += 1
					continue_pierce = true
		elif not collider is Throwable:
			if audio:
				audio.play_generic_impact(_result.position, from_ai)
		if collider is RigidBody3D and not (collider is Character):
			var rb := collider as RigidBody3D
			var impulse: Vector3 = pellet_direction.normalized() * GameSettings.physics_damage.bullet_interactable_knockback
			rb.apply_impulse(impulse, _result.position - rb.global_position)
			if rb is Throwable:
				(rb as Throwable).on_impact(GameSettings.physics_damage.interactable_impact_max_velocity)
		if continue_pierce:
			continue
		break
	return { "visual_target": visual_target, "hit_anything": hit_anything, "hit_npc": hit_npc }
