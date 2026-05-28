class_name InteractableData
extends Resource

## Data resource for a destructible physics prop (crates, gore gibs, etc.) — the
## Interactable analogue of WeaponData. Interactable.gd reads these to set HP, mass,
## look, sounds, and destruction FX, so one Interactable scene can be reskinned into
## many object types purely by swapping the .tres.

@export var max_hp: int = 5
@export var mass: float = 1.0
@export var mesh: Mesh
@export var material: Material
@export var impact_sound: AudioStream
@export var destroy_sound: AudioStream
@export var destroy_particle_scene: PackedScene
@export var destroy_screen_shake: float = 0.35
@export var physics_material: PhysicsMaterial
# Leave a scorch/blast decal on the floor when destroyed (e.g. crates). Gibs
# set this false since they spawn their own blood decals.
@export var spawns_destroy_decal: bool = true
