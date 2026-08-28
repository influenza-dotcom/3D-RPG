class_name Explosion
extends Area3D

## One-shot radial blast. On _ready it sizes its flash mesh, push collider, screen-
## shake collider, and light from explosion_radius; on body entry it applies a
## distance-falloff push (+ optional damage); a timer self-frees it.
##
## DUAL MODE via collision_shape: present = a real explosion (physics push collider,
## full-size mesh/light). Absent = a light-only visual (e.g. a bullet hit spark) —
## the mesh/light shrink and no push collider is built. `deals_damage` gates damage.

## The path to THIS component's own scene. It MUST be a runtime load() string, NOT preload(), because this script is
## explosion_area.tscn's ROOT — preloading your own scene is the documented class_name<->preload(scene) parse cycle.
const _AREA_SCENE_PATH := "res://scenes/effects/explosion_area.tscn"

@onready var omni_light_3d: OmniLight3D = $OmniLight3D

@export_group("Node References")
## The flash mesh (a SphereMesh). _ready duplicates + resizes it from explosion_radius and forwards speed_to_scale; tint_color recolours it.
@export var mesh_instance: ExplosionMesh
## The physics PUSH collider. Presence is the DUAL-MODE switch: wired = a real blast (full-size mesh/light + push); leave EMPTY for a light-only spark (shrunken visual, no shove).
@export var collision_shape: CollisionShape3D
## Optional second (larger) collider feeding ScreenShakeArea. _ready sizes it to ~2x explosion_radius (clamped) so the camera-shake reach can exceed the push reach.
@export var screen_shake_collision_shape: CollisionShape3D
# (The self-destruct Timer child is NOT an export — its timeout is scene-wired straight to _on_timer_timeout,
# and its wait_time is authored on the Timer node itself; nothing reads it through a property.)

@export_group("Blast Physics")
## Peak radial push impulse at ground zero, falling off linearly to 0 at explosion_radius. 0 = no shove (a purely visual flash/spark).
@export var max_explosion_force: float = 20.0
## Blast radius in metres — sizes the flash mesh, push collider, light throw, AND the push-falloff distance. Bodies past this take no force.
@export var explosion_radius: float = 4.0
## Blast DAMAGE dealt to a body inside explosion_radius. FLAT (any in-radius body takes the full amount — the PUSH
## falls off with distance, the damage does not; this matches the pre-M9 global behaviour). -1 = use the global
## GameSettings.physics_damage.explosion_damage fallback: environmental blasts (ExplosiveBarrel) leave it -1, while a
## weapon's ProjectileSpawner forwards WeaponData.explosion_damage here so a rocket can hit harder than a grenade.
@export var explosion_damage: float = -1.0
## Bias the radial push toward straight UP for characters — 0 = no change,
# 1 = pure vertical pop. Gives the "juggle" feel without flinging horizontally.
@export_range(0.0, 1.0) var upward_bias: float = 0.0

@export_group("Behavior")
## Opt-in camera shake: when true (and a ScreenShakeArea is wired) a Player in range gets a distance-scaled screen shake. Default off — shake is per-explosion.
@export var allowed_shake_screen: bool = false
## When true the blast damages overlapping bodies (take_damage); false = a cosmetic-only blast (spark/paint splat) that still pushes if max_explosion_force > 0.
@export var deals_damage: bool = true

@export_group("Appearance")
## Forwarded to the flash mesh: 0 = pop to full size instantly (muzzle flash); >0 = grow from zero at this rate (an expanding blast bloom).
@export var speed_to_scale: float = 0.0
## Recolour the flash + light to this (alpha > 0 = active). Used by the paint splat to match paint.
@export var tint_color: Color = Color(0, 0, 0, 0)

## Who caused this blast (the projectile's shooter), set by explosion.gd when spawned. ONLY a player
## instigator flashes the player's hitmarker — an NPC's rocket splashing another NPC must not ping it.
## Null = unknown (e.g. a cosmetic spark) and is treated as not-the-player.
var instigator: Node = null

func _ready() -> void:
	# Size the flash mesh from explosion_radius — only when it's wired AND its mesh is a
	# SphereMesh (a non-sphere or unwired drop-in must not crash on the cast).
	if mesh_instance != null and mesh_instance.mesh is SphereMesh:
		mesh_instance.mesh = mesh_instance.mesh.duplicate()
		var sphere := mesh_instance.mesh as SphereMesh
		if collision_shape == null:
			# Light-only spark: shrunken visual, no push collider.
			sphere.radius = explosion_radius / 4
			sphere.height = explosion_radius / 2
		else:
			sphere.radius = explosion_radius
			sphere.height = explosion_radius * 2.0
		# ⭐ The child's _ready() runs BEFORE ours, so if this flash opted into `has_outline` its outline
		# ring was already stamped against the sphere we just replaced — and a tint duplicate SNAPSHOTS its
		# host's mesh. Without this the ring would be drawn at the AUTHORED radius around a flash resized to
		# explosion_radius. Same contract the placeholder pistol's ghost outline taught (2026-08-27); see
		# InkOutline.sync_tint_mesh.
		InkOutline.sync_tint_mesh(mesh_instance)
	# Size the push collider only when present (presence = real-blast switch) AND a sphere.
	if collision_shape != null and collision_shape.shape is SphereShape3D:
		collision_shape.shape = collision_shape.shape.duplicate()
		(collision_shape.shape as SphereShape3D).radius = explosion_radius
	if screen_shake_collision_shape != null and screen_shake_collision_shape.shape is SphereShape3D:
		screen_shake_collision_shape.shape = screen_shake_collision_shape.shape.duplicate()
		var shake_radius := maxf(explosion_radius * 2.0, GameSettings.screen_shake.explosion_min_shake_radius)
		(screen_shake_collision_shape.shape as SphereShape3D).radius = shake_radius
	if mesh_instance != null:
		mesh_instance.speed_to_scale = speed_to_scale
		# The child ExplosionMesh._ready() already locked its start scale from its OWN (pre-forward) speed_to_scale
		# default (children _ready before parents), so a spawner's bloom request was silently ignored. Re-apply the
		# start scale from the runtime value: ZERO so the grow-from-zero bloom plays, else ONE for an instant flash.
		mesh_instance.scale = Vector3.ZERO if speed_to_scale > 0.0 else Vector3.ONE
	if omni_light_3d:
		# A FORCEFUL blast (rocket/rock) floors its flash to explosion_min_flash_radius so even a small one still
		# lights the area; a cosmetic hit spark / paint splat (force 0) instead scales its light to its OWN tiny
		# radius -- otherwise a 0.3 m bullet spark floods a 4 m area with light (the reported glitch).
		var base_r: float = explosion_radius if collision_shape != null else explosion_radius / 2.0
		var floor_r: float = GameSettings.effects.explosion_min_flash_radius if max_explosion_force > 0.0 else 0.0
		var flash_radius: float = maxf(base_r, floor_r)
		omni_light_3d.omni_range = flash_radius
		omni_light_3d.light_energy = flash_radius * GameSettings.effects.explosion_flash_energy_per_radius
	if tint_color.a > 0.0:
		if mesh_instance:
			mesh_instance.tint(tint_color)
		if omni_light_3d:
			omni_light_3d.light_color = tint_color
	_limit_monitoring_window()

## An explosion is instantaneous: it only needs to detect the bodies it overlaps for a frame
## or two (to damage / push / shake), NOT for its whole 0.2s visual lifetime. If the Area3D
## keeps monitoring that whole time, every gore drop / gib / body that spawns or drifts inside
## churns enter+exit events — and when those bodies (or this area) free mid-overlap, Jolt spams
## "_flush_events: ref_count <= 0" and the frame hitches hard on every kill. So: detect, then
## stop monitoring. The mesh + light still fade out on the Timer.
func _limit_monitoring_window() -> void:
	var visual_only := not deals_damage and max_explosion_force <= 0.0
	if not visual_only:
		# Let body_entered fire for everything we already overlap, then stop. Re-check between the awaits:
		# a blast freed mid-window (level unload, quit) would otherwise call .physics_frame on a null get_tree().
		await get_tree().physics_frame
		if not is_inside_tree():
			return
		await get_tree().physics_frame
		if not is_inside_tree():
			return
	# set_deferred, NOT a direct write — the project's own idiom for this exact operation (trigger_volume.gd:90).
	# Area3D::set_monitoring is BLOCKED while the physics server is flushing queries, and the visual_only branch
	# above reaches this line synchronously from _ready(), i.e. from inside whatever add_child() built us — which
	# for the bullet-spark bridge (explosion.gd) is a RigidBody3D contact callback, mid-flush. Deferring lands
	# both branches safely outside the flush.
	set_deferred(&"monitoring", false)
	var shake := get_node_or_null("ScreenShakeArea")
	if shake is Area3D:
		(shake as Area3D).set_deferred(&"monitoring", false)

## Push (and optionally damage) each body entering the blast. Force falls off
## linearly to zero at explosion_radius. Characters/enemies receive a DECAYING blast
## impulse (explosion_velocity, see Character); loose rigid bodies get a real impulse.
func _on_body_entered(body: Node3D) -> void:
	# Area is a sphere, but clamp to the exact radius so edge cases just outside the
	# intended range receive no force.
	var distance_to_blast := body.global_position.distance_to(global_position)
	if distance_to_blast > explosion_radius:
		return

	var force_multiplier := 1.0 - (distance_to_blast / explosion_radius)
	var applied_force := max_explosion_force * force_multiplier
	var push_direction := global_position.direction_to(body.global_position).normalized()

	if deals_damage and body.has_method("take_damage"):
		# Attribute the blast to whoever fired it (instigator = the projectile's shooter), so a PLAYER
		# explosion kill pays the zorkmid bounty. No hit_pos -> blasts don't apply locational/limb damage.
		# M9: a per-instance explosion_damage override (>= 0) wins; -1 (barrels, unconfigured) falls back to the global knob.
		var dmg: float = resolve_damage(explosion_damage, GameSettings.physics_damage.explosion_damage)
		# PRE-hit HP, captured before the blast lands, so the hit-confirm block below can tell a body THIS blast just
		# killed from one that was ALREADY a corpse: after take_damage the two are indistinguishable (it early-outs on
		# its own _dead latch, leaving hp at its lethal value), and blasts routinely reach corpses — an NPC holds its
		# pose for the whole death-freeze beat with its collider live. -1 marks "not a Character".
		var hp_before := (body as Character).hp if body is Character else -1.0
		body.take_damage(dmg, false, instigator)
		# Flash the player's hitmarker when our blast connects — enemy splash OR self-damage.
		# But ONLY when the PLAYER instigated this blast (see the gate below) — enemies have rockets now.
		if body is Character:
			# Directional damage arc toward the blast — self-damage (player in their own
			# explosion) shows it; enemies no-op.
			(body as Character).indicate_damage_from(global_position)
			# Hitmarker is PLAYER feedback for a hit the player dealt — flash it only when the player
			# instigated THIS blast (an NPC's rocket splashing another NPC must not ping it).
			# Pass the victim's POST-damage HP fraction, exactly like the hitscan (damage_trace) and direct-impact
			# (projectile) paths do. This is the hit DING's pitch, which tracks the target's remaining HP (deeper as it
			# nears death) — a bare on_dealt_hit() defaulted hp_frac to 1.0, so every explosive in the game dinged at
			# the full-HP end no matter how close to dead it left the target. headshot stays false: a blast deals no
			# locational damage (no hit_pos above). A hit on a body that was ALREADY dead reports full HP rather than
			# its real 0, so splashing a corpse keeps the hitmarker + ding this path has always given without dinging
			# it as a fresh death-blow. NOT the kill flash — that fires once per victim from take_damage's lethal
			# branch, on the resolved killer, and never rides hp_frac.
			if is_instance_valid(instigator) and instigator.is_in_group(Groups.PLAYER) and instigator.has_method(&"on_dealt_hit"):
				var victim := body as Character
				var hp_frac := 1.0 if hp_before <= 0.0 else clampf(victim.hp / maxf(victim.max_hp, 1.0), 0.0, 1.0)
				instigator.on_dealt_hit(false, hp_frac)

	# Player (a Character but NOT an NPC): blast push with optional upward bias, lessened by how loaded they are.
	if body is Character and body is not NPC:
		var biased_dir := push_direction.lerp(Vector3.UP, upward_bias).normalized()
		body.explosion_velocity += biased_dir * applied_force * (body as Character).encumbrance_launch_multiplier()
	# Enemies get DOUBLE force so they juggle/fly dramatically — the gore payoff (always full, never
	# lessened by load: the encumbrance "launched less" rule is for the PLAYER).
	elif body is NPC:
		var biased_dir := push_direction.lerp(Vector3.UP, upward_bias).normalized()
		body.explosion_velocity += biased_dir * applied_force * 2
	elif body is RigidBody3D:
		var rb := body as RigidBody3D
		if rb.freeze:
			return
		rb.apply_impulse(push_direction * applied_force, Vector3.ZERO)

## Resolve the blast damage: a per-instance override (>= 0) wins; -1 falls back to the global knob. Pure + static so
## the -1-vs-override rule is unit-testable without triggering a physics overlap (M9).
static func resolve_damage(override_amount: float, global_amount: float) -> float:
	return override_amount if override_amount >= 0.0 else global_amount


## Instantiate a fresh Explosion, recovering from the editor-reimport window where the scene momentarily bakes empty.
## The ONE source for the blast scene — gun_fx (hit spark / overkill burst / muzzle flash), paint_projectile (the paint
## pop) and explosion.gd (the projectile-death bridge) all call this instead of copy-pasting the recovery idiom.
## Fast path: load() is cached after the first call. If the cached scene is null / uninstantiable (it compiled while
## the .tscn was mid-reimport, the reported "no blast spawns" hiccup) re-read it FRESH from disk, bypassing the cache.
## Returns null ONLY if the scene is genuinely unavailable — every caller null-guards and skips its cosmetic FX (or the
## bridge push-warns) rather than crashing. An exported build always hits the cached fast path.
## GOTCHA: runtime load(), never preload(_AREA_SCENE_PATH) — this script IS that scene's root (preload = parse cycle).
static func instantiate_recovering() -> Explosion:
	var scene := load(_AREA_SCENE_PATH) as PackedScene
	if scene == null or not scene.can_instantiate():
		scene = ResourceLoader.load(_AREA_SCENE_PATH, "PackedScene", ResourceLoader.CACHE_MODE_IGNORE) as PackedScene
	if scene == null or not scene.can_instantiate():
		return null
	return scene.instantiate() as Explosion


func _on_timer_timeout() -> void:
	queue_free()
