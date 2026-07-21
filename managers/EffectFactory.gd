extends Node

## @system Effect And Audio Seams
## @seam EffectFactory autoload owns ONE gameplay spawn (spawn_blood_particle) over a null-safe spawn_at that auto-emits+frees particles; it is NOT a VFX registry.
## @risk Re-adding a per-effect slot or spawn_* wrapper is a silent no-op unless it routes through spawn_at AND a call site reads it (the removed slots failed exactly this way).
## @risk The instantiate()-null guard returns null with NO log at all (only the null-scene path warns) — an empty/broken effect scene yields zero VFX silently, no crash, easy to miss.
## @test res://tests/test_managers_tuning.gd
## @test res://tests/test_autoload_order.gd
## EffectFactory — the ONE gameplay spawn seam for the blood-impact particle (spawn_blood_particle), plus a generic
## spawn_at(scene, pos) helper. It is NOT a central VFX registry.
##
## The other visual effects (blood/bullet-hole decals, dust, explosions, gore gibs) are spawned by their OWN systems,
## which preload their scene UID directly AND pass per-instance config a shared slot can't carry — an explosion's
## force/radius/instigator, the CACHE_MODE_IGNORE reimport-recovery reload. To RESTYLE one of those, edit the effect's
## own .tscn (by UID) — see docs/AUTHORING_GUIDE.md "Restyling the effects themselves".
##
## H3: an earlier version exported a slot per effect and called itself the "central spawner", but repointing a slot
## was a SILENT no-op (the call sites don't read it), so a designer who swapped e.g. `explosion_area` saw nothing
## change. Those misleading slots + their unused spawn_* wrappers were removed. Add a spawn_* wrapper here ONLY when a
## new site wants a stable, string-free entry point this factory actually owns (i.e. one that routes through spawn_at).

## Blood spray particle burst on bullet impact / gib break — the one effect this factory spawns for gameplay
## (ram_reactor, Throwable). To restyle blood, edit blood.tscn (uid://c7v6vgs74fhn4), not this slot.
@export var blood_particle: PackedScene = preload("uid://c7v6vgs74fhn4")  # blood.tscn


## Instantiate `scene` at `pos` under `parent` (or the scene root), auto-emitting + auto-freeing particles. Null-safe:
## a null scene, or an empty-PackedScene reimport transient (instantiate() returns null), warns/skips instead of crashing.
##
## This is the SHARED instantiate -> position -> emit -> auto-free seam: spawn_blood_particle routes through it, and
## Throwable._spawn_destroy_particle calls it directly for the break puff (both were hand-copies of this exact idiom).
## It is deliberately the ONE chokepoint for that idiom, so a future global "cosmetic effects off (perf/accessibility)"
## guard or an object pool has a single home here — the richer effects (explosions, oriented decals, host-driven gibs)
## carry per-instance config a point-spawn can't and stay on their own systems (see the header + H3 note).
func spawn_at(scene: PackedScene, pos: Vector3, parent: Node = null) -> Node:
	if scene == null:
		push_warning("EffectFactory.spawn_at called with null scene")
		return null
	var inst = scene.instantiate()
	if inst == null: return null  # empty-PackedScene reimport transient -> instantiate() can return null; skip instead of crashing
	var target := parent if parent else get_tree().root
	target.add_child(inst)
	if inst is Node3D:
		(inst as Node3D).global_position = pos
	# GPUParticles3D: emit + auto-free
	if inst is GPUParticles3D:
		(inst as GPUParticles3D).emitting = true
		(inst as GPUParticles3D).finished.connect(inst.queue_free)
	elif inst.has_signal("finished"):
		inst.finished.connect(inst.queue_free)
	return inst


## The one gameplay effect entry point this factory owns — keeps the effect name out of call-site strings.
func spawn_blood_particle(pos: Vector3) -> Node: return spawn_at(blood_particle, pos)
