class_name ShellDrop
extends GPUParticles3D

## Ejected spent-casing particle burst. Connected to Attack.shell_particle, which Attack only emits when
## WeaponData.spawns_casing is true — so the per-weapon casing toggle lives upstream and this node just
## re-fires the one-shot emitter. Attack also calls set_casing_scale() so a heavier round drops a bigger
## shell (per WeaponData.casing_size_scale).

var _base_scale_min: float = 1.0  ## authored particle draw scale, captured so set_casing_scale is relative
var _base_scale_max: float = 1.0

func _ready() -> void:
	# Own a PRIVATE copy of the process material so resizing the casing per-weapon can't bleed into any
	# other emitter sharing the authored resource. Capture the authored draw scale as the 1.0 baseline.
	var pm := process_material as ParticleProcessMaterial
	if pm != null:
		pm = pm.duplicate() as ParticleProcessMaterial
		process_material = pm
		_base_scale_min = pm.scale_min
		_base_scale_max = pm.scale_max

func emit() -> void:
	restart()

## Resize the ejected casing's VISUAL by `factor` (1.0 = the authored size). Scales the particle DRAW
## scale via the process material — the node's own .scale does NOT affect world-space (local_coords off)
## particle size, which is why setting it did nothing. Called by Attack before each eject from
## WeaponData.casing_size_scale, so a heavier round (e.g. the sniper) drops a bigger shell.
func set_casing_scale(factor: float) -> void:
	var pm := process_material as ParticleProcessMaterial
	if pm == null:
		return
	pm.scale_min = _base_scale_min * factor
	pm.scale_max = _base_scale_max * factor
