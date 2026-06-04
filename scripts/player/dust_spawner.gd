class_name DustSpawner
extends Node3D

## Spawns the little ground-puff GPUParticles3D the actor kicks up — the player fires it on jump,
## land, and while sliding (NPCs could too). Lifted out of Character so the raycast-to-ground +
## particle setup lives in one place; Character keeps a thin spawn_dust() facade that delegates here.
##
## Code-built child of Character (added in its _ready). Reads the host's CHARACTER_DUST const (kept
## on the root) and all tuning off GameSettings.effects, and probes the ground from the HOST's
## position (not this node's), so the puff lands under the actor exactly as the monolith did.

## The actor we belong to — set right after .new(), before add_child. We spawn from its position and
## exclude it from the ground probe.
var _host: Character

## Raycast straight down from the host to find the ground, then drop a one-shot dust puff there,
## scaled + ratio-clamped by `intensity` (jump/land/slide pass their own). Adds the puff under the
## scene root (world-space, independent of the moving actor) and self-frees it when it finishes.
## Bails when the host isn't in the tree (no world to raycast) — mirrors the monolith's guard.
func spawn(intensity: float = 1.0) -> void:
	if not _host.is_inside_tree():
		return
	var space_state := _host.get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(
		_host.global_position,
		_host.global_position + Vector3.DOWN * GameSettings.effects.dust_ground_probe_distance
	)
	query.exclude = [_host]
	var result := space_state.intersect_ray(query)
	var pos: Vector3 = result.position if result else _host.global_position
	var dust: GPUParticles3D = Character.CHARACTER_DUST.instantiate()
	_host.get_tree().root.add_child(dust)
	dust.global_position = pos + Vector3.UP * GameSettings.effects.dust_ground_offset
	var safe_intensity = max(intensity, 0.05)
	dust.scale = Vector3.ONE * safe_intensity
	dust.amount_ratio = clampf(safe_intensity, GameSettings.effects.dust_amount_ratio_min, 1.0)
	dust.emitting = true
	dust.finished.connect(dust.queue_free)
