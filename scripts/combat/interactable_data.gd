class_name InteractableData
extends Resource

@export var max_hp: int = 5
@export var mass: float = 1.0
@export var mesh: Mesh
@export var material: Material
@export var impact_sound: AudioStream
@export var destroy_sound: AudioStream
@export var destroy_particle_scene: PackedScene
@export var destroy_screen_shake: float = 0.35
@export var physics_material: PhysicsMaterial
