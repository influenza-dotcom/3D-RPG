class_name ShellDrop
extends GPUParticles3D

## Ejected spent-casing particle burst. Connected to Attack.shell_particle, which
## Attack only emits when WeaponData.spawns_casing is true — so the per-weapon casing
## toggle lives upstream and this node just re-fires the one-shot emitter.

func emit() -> void:
	restart()
