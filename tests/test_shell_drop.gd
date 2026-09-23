extends GutTest

## ShellDrop (scripts/components/shell_drop.gd) — the ejected-casing one-shot burst. Two contracts:
##   1. PRIVATE PROCESS MATERIAL. _ready duplicates the authored ParticleProcessMaterial so set_casing_scale on
##      one weapon's emitter can never resize another's (every gun mesh instantiates the same shell_drop.tscn).
##   2. set_casing_scale(factor) is RELATIVE TO THE AUTHORED SIZE, not compounding: Attack calls it before EVERY
##      eject with WeaponData.casing_size_scale, so a sniper (2x) followed by a pistol (1x) must land back on 1x,
##      not 2x then 2x again. It scales the process material's draw scale — the node's own .scale does nothing
##      for world-space particles, which is why the method exists.
## Plus the authored scene shape Attack relies on (a one-shot, not-emitting, single-casing emitter).

const SCRIPT_PATH := "res://scripts/components/shell_drop.gd"
const SCENE_PATH := "res://scenes/effects/shell_drop.tscn"


func _in_tree():
	var sd := (load(SCENE_PATH) as PackedScene).instantiate() as GPUParticles3D
	add_child_autofree(sd)
	return sd


func test_scene_is_a_one_shot_single_casing_emitter() -> void:
	var ps := load(SCENE_PATH) as PackedScene
	assert_not_null(ps, "shell_drop.tscn must load (EffectPrewarmer and every gun mesh instantiate it)")
	if ps == null:
		return
	var sd := ps.instantiate() as GPUParticles3D
	assert_not_null(sd, "the root is a GPUParticles3D")
	assert_eq((sd.get_script() as Script).resource_path, SCRIPT_PATH, "the root runs shell_drop.gd")
	assert_true(sd.one_shot, "one_shot: restart() fires ONE burst per eject")
	assert_false(sd.emitting, "authored not-emitting — it waits for Attack.shell_particle")
	assert_eq(sd.amount, 1, "one casing per shot")
	assert_true(sd.process_material is ParticleProcessMaterial, "the authored process material is a ParticleProcessMaterial (what set_casing_scale resizes)")
	assert_true(sd.has_method(&"set_casing_scale"), "Attack duck-types on set_casing_scale before each eject")
	assert_true(sd.has_method(&"emit"), "emit() is the re-fire entry")
	sd.free()


func test_ready_takes_a_private_copy_of_the_process_material() -> void:
	var authored := ((load(SCENE_PATH) as PackedScene).instantiate() as GPUParticles3D)
	var shared: ParticleProcessMaterial = authored.process_material
	var a = _in_tree()
	var b = _in_tree()
	assert_ne(a.process_material, shared, "in-tree instance A must own a duplicate, not the scene's shared sub-resource")
	assert_ne(b.process_material, shared, "in-tree instance B must own a duplicate too")
	assert_ne(a.process_material, b.process_material, "two emitters must not share one material")
	assert_eq((a.process_material as ParticleProcessMaterial).scale_min, shared.scale_min, "the copy starts at the authored draw scale")
	assert_eq((a.process_material as ParticleProcessMaterial).scale_max, shared.scale_max, "the copy starts at the authored draw scale")
	authored.free()


func test_casing_scale_is_relative_to_the_authored_size() -> void:
	var sd = _in_tree()
	var pm := sd.process_material as ParticleProcessMaterial
	var base_min := pm.scale_min
	var base_max := pm.scale_max
	sd.set_casing_scale(2.0)
	assert_almost_eq(pm.scale_min, base_min * 2.0, 0.0001, "2x doubles the authored min draw scale")
	assert_almost_eq(pm.scale_max, base_max * 2.0, 0.0001, "2x doubles the authored max draw scale")
	sd.set_casing_scale(2.0)
	assert_almost_eq(pm.scale_max, base_max * 2.0, 0.0001, "calling 2x again stays 2x — relative to the AUTHORED size, never compounding")
	sd.set_casing_scale(1.0)
	assert_almost_eq(pm.scale_min, base_min, 0.0001, "1.0 restores the authored min exactly (the next weapon's eject lands on ITS size)")
	assert_almost_eq(pm.scale_max, base_max, 0.0001, "1.0 restores the authored max exactly")
	sd.set_casing_scale(0.5)
	assert_almost_eq(pm.scale_max, base_max * 0.5, 0.0001, "a light round shrinks the casing")


func test_scaling_one_emitter_leaves_another_untouched() -> void:
	var a = _in_tree()
	var b = _in_tree()
	var b_pm := b.process_material as ParticleProcessMaterial
	var b_max := b_pm.scale_max
	a.set_casing_scale(3.0)
	assert_eq(b_pm.scale_max, b_max, "the sniper's 3x casing must not bleed into the pistol's emitter")


func test_casing_scale_leaves_an_emitter_without_a_particle_material_as_authored() -> void:
	# The guard's two refusals: no process material at all, and a process material that is not a
	# ParticleProcessMaterial (a ShaderMaterial has no draw-scale range to resize). Either must be left exactly as
	# authored — no material conjured, no swap — and GUT's engine-error check covers "no error". The CONTROL at the
	# end is the shipped scene emitter (a real ParticleProcessMaterial), which the same call DOES resize.
	var bare = load(SCRIPT_PATH).new()
	add_child_autofree(bare)
	bare.set_casing_scale(2.0)
	assert_null(bare.process_material,
		"a material-less ShellDrop must stay material-less — resizing a casing must not invent an emitter setup")
	var shader_pm := ShaderMaterial.new()
	var custom = load(SCRIPT_PATH).new()
	custom.process_material = shader_pm
	add_child_autofree(custom)
	custom.set_casing_scale(2.0)
	assert_eq(custom.process_material, shader_pm,
		"a custom (shader) process material must survive set_casing_scale untouched, not be replaced by a stock one")
	var control = _in_tree()
	var control_pm := control.process_material as ParticleProcessMaterial
	var authored_max := control_pm.scale_max
	control.set_casing_scale(2.0)
	assert_almost_eq(control_pm.scale_max, authored_max * 2.0, 0.0001,
		"control: the same call on the shipped ParticleProcessMaterial emitter DOES resize the casing")


func test_emit_restarts_the_one_shot() -> void:
	var sd = _in_tree()
	sd.emit()
	assert_true(sd.emitting, "emit() restarts the one-shot burst (emitting flips on until the burst finishes)")
