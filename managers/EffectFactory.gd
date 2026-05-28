extends Node

# EffectFactory — central spawner for visual effects.
#
# All UIDs below were resolved by searching existing preload() sites in the
# project (see grep audit in refactor notes). If you swap an effect, change
# the @export here in the editor or edit the .tscn references.

@export var blood_decal: PackedScene = preload("uid://dg5ui5is8sakg")          # blood_splat_decal.tscn
@export var blood_particle: PackedScene = preload("uid://c7v6vgs74fhn4")       # blood.tscn
@export var bloody_mess: PackedScene = preload("uid://yeq88l33gvle")           # bloody_mess.tscn
@export var blood_drop: PackedScene = preload("uid://b3dropfx7anp")            # blood_drop.tscn
@export var bullet_hole_decal: PackedScene = preload("uid://dh1ydtvwvgiqg")    # bullet_hole_decal.tscn
@export var dust: PackedScene = preload("uid://um6f8g8g6l7v")                  # dust.tscn (also serves character_dust — same UID in legacy code)
@export var dust_large: PackedScene = preload("uid://ckxkt0g5gq8bb")           # dust_large.tscn
@export var explosion_area: PackedScene = preload("uid://co1ehjy0gbhu3")       # explosion_area.tscn
@export var gib: PackedScene = preload("uid://b8bk21rivwuok")                  # cube.tscn (proof-of-concept gore gib; swap when real gore meshes exist)

# NOTE on potential UID ambiguity (to investigate during Phase 3 migration):
#   - "blood" appears in two forms: blood.tscn (c7v6vgs74fhn4) as the particle
#     used for bullet impacts and gib break, vs bloody_mess.tscn (yeq88l33gvle)
#     as the bigger death effect. Make sure call sites pick the right one.
#   - "dust" UID um6f8g8g6l7v is reused as CHARACTER_DUST in character.gd.
#     If the design ever wants them visually distinct, split into a second
#     @export var character_dust here.


func spawn_at(scene: PackedScene, pos: Vector3, parent: Node = null) -> Node:
	if scene == null:
		push_warning("EffectFactory.spawn_at called with null scene")
		return null
	var inst = scene.instantiate()
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


# Convenience wrappers — call by name from gameplay code so we keep effect
# names out of strings. Add more as Phase 3 migration discovers needs.
func spawn_blood_particle(pos: Vector3) -> Node: return spawn_at(blood_particle, pos)
func spawn_bloody_mess(pos: Vector3) -> Node: return spawn_at(bloody_mess, pos)
func spawn_blood_drop(pos: Vector3) -> Node: return spawn_at(blood_drop, pos)
func spawn_dust(pos: Vector3) -> Node: return spawn_at(dust, pos)
func spawn_dust_large(pos: Vector3) -> Node: return spawn_at(dust_large, pos)
func spawn_gib(pos: Vector3) -> Node: return spawn_at(gib, pos)
