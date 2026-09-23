extends GutTest

## Contract tests for the boot-time GPU-particle pipeline prewarm (PreloadManager._prewarm_gpu_particles).
## A FIRST-TIME ParticlesShaderRD compile mid-gameplay is a known first-compile crash class on this dev
## machine's NVIDIA D3D12 driver (one real export first-boot crash during mass cache population — the
## playtest hard-crash first blamed on it turned out to be a separate godot-cpp build-flavour bug in the
## TTS GDExtension, since fixed) and, crash or not, a visible hitch — so every distinct particle pipeline
## is rendered once at boot instead. Two halves:
##  - the RATCHET that keeps the warm list complete as content grows: it scans scene/resource SOURCE TEXT
##    off-tree (no gameplay scene is instanced, no _ready runs) and fails naming the exact path to add to
##    PreloadManager.PARTICLE_WARM_PATHS;
##  - the WARM-UP itself, driven on a fresh PreloadManager in the test tree (the autoload skips it headless, but the
##    function runs fine here): every listed scene must land EMITTING in the isolated viewport, the code-built confetti
##    must be the very pipeline a confetti kill spawns, and the viewport must be torn down afterwards. Headless never
##    compiles a shader, so what is proven is that the right emitters are DRAWING for the frames a real GPU compiles in.
## This boot pass compiles the particle PROCESS shaders; the draw pipelines are warmed by the in-level second
## stage (EffectPrewarmer at GameRoot.load_level), whose ratchet — tests/test_effect_prewarm.gd — requires every
## entry here to be in EffectPrewarmer.WARM_PATHS as well.

const PRELOAD_MANAGER_PATH := "res://managers/PreloadManager.gd"
const THROWABLE_PATH := "res://scripts/components/Throwable.gd"
## Where authored scenes/resources live. A particle scene saved outside these roots would dodge the scan,
## so keep them in sync with the project layout.
const SCAN_ROOTS: Array[String] = ["res://scenes", "res://resources"]
## Source-text tell that a .tscn DECLARES its own particle emitter node — on a [node] header WITHOUT instance=
## (a placement of another scene may spell the type out too; see _declares_own_emitter). A scene whose ROOT is an
## instance of a particle scene is covered by the root-instance leg of _is_particle_scene instead
## (e.g. spark_attack.tscn, whose root IS a dust.tscn instance).
const PARTICLE_NODE_TAG := "type=\"GPUParticles3D\""

var _warm_paths: Array = []


func before_all() -> void:
	var pm: GDScript = load(PRELOAD_MANAGER_PATH)
	_warm_paths = pm.PARTICLE_WARM_PATHS


## Recursively collect res:// file paths under `root` whose names end with one of `exts`.
func _collect_files(root: String, exts: Array, out: Array) -> void:
	var dir := DirAccess.open(root)
	if dir == null:
		return
	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		if dir.current_is_dir():
			if not entry.begins_with("."):
				_collect_files(root.path_join(entry), exts, out)
		else:
			for ext in exts:
				if entry.ends_with(ext):
					out.append(root.path_join(entry))
					break
		entry = dir.get_next()
	dir.list_dir_end()


## id -> res:// path for every [ext_resource ...] tag in a serialized .tscn/.tres file's text.
## \bid= deliberately: the uid="..." attribute contains the substring id= and must not match.
func _ext_resource_map(text: String) -> Dictionary:
	var map := {}
	var path_re := RegEx.create_from_string("\\bpath=\"([^\"]+)\"")
	var id_re := RegEx.create_from_string("\\bid=\"([^\"]+)\"")
	for line in text.split("\n"):
		if not line.begins_with("[ext_resource"):
			continue
		var path_m := path_re.search(line)
		var id_m := id_re.search(line)
		if path_m != null and id_m != null:
			map[id_m.get_string(1)] = path_m.get_string(1)
	return map


## The res:// path a scene's ROOT node instances (a derived effect scene like spark_attack over dust),
## or "" when the root is a plain typed node. Only the FIRST [node ...] tag is the root; child instance
## placements all carry parent= and are uses of an effect, not new effect authoring.
func _root_instance_path(text: String) -> String:
	var inst_re := RegEx.create_from_string("instance=ExtResource\\(\"([^\"]+)\"\\)")
	for line in text.split("\n"):
		if not line.begins_with("[node "):
			continue
		var m := inst_re.search(line)
		if m == null:
			return ""
		return String(_ext_resource_map(text).get(m.get_string(1), ""))
	return ""


## True when some [node ...] header in a scene's text declares a GPUParticles3D of the scene's OWN. A header that
## also carries instance= is a PLACEMENT of another scene — a level dropping ambient_dust.tscn in, which the editor
## may serialize with type= spelled out and a plain-value override such as `motes` — i.e. a use of an effect that is
## already warmed under its own path, not new emitter authoring (and not a new pipeline).
func _declares_own_emitter(text: String) -> bool:
	for line in text.split("\n"):
		if line.begins_with("[node ") and line.contains(PARTICLE_NODE_TAG) and not line.contains("instance="):
			return true
	return false


## True when the scene at `path` is a GPU-particle effect: it declares a GPUParticles3D node in its own
## text, or its root derives from a scene that does. Depth-guarded so a cyclic/deep derivation chain can
## never hang the suite.
func _is_particle_scene(path: String, depth: int = 0) -> bool:
	if depth > 4 or not path.ends_with(".tscn") or not FileAccess.file_exists(path):
		return false
	var text := FileAccess.get_file_as_string(path)
	if _declares_own_emitter(text):
		return true
	var base := _root_instance_path(text)
	return base != "" and _is_particle_scene(base, depth + 1)


func test_warm_list_paths_exist_on_disk() -> void:
	assert_gt(_warm_paths.size(), 0,
			"PreloadManager.PARTICLE_WARM_PATHS is empty — the boot particle prewarm (the first-compile hitch mitigation, and the guard against the known NVIDIA D3D12 first-compile crash class) is warming nothing")
	for path in _warm_paths:
		assert_true(FileAccess.file_exists(String(path)),
				"PARTICLE_WARM_PATHS entry '%s' does not exist on disk — a renamed/moved effect scene silently un-warms its pipeline (the prewarm skips missing paths with only a warning); fix the path in managers/PreloadManager.gd" % path)


func test_warm_list_entries_read_as_particle_scenes() -> void:
	# Bidirectional health check: every warm entry must LOOK like a particle scene to this file's scanner.
	# If an entry stops qualifying, either it lost its emitter (remove it from the list) or the scanner's
	# source-text assumptions rotted — and a rotten scanner would make the coverage tests below pass
	# while asserting nothing, which is exactly the silent failure this test exists to catch.
	for path in _warm_paths:
		assert_true(_is_particle_scene(String(path)),
				"warm-list entry '%s' does not read as a GPU-particle scene to the scanner — remove it from PARTICLE_WARM_PATHS if its emitter is gone, or fix this test's scanner if the .tscn serialization changed" % path)


func test_every_authored_particle_scene_is_warmed() -> void:
	var files: Array = []
	for root in SCAN_ROOTS:
		_collect_files(String(root), [".tscn"], files)
	assert_gt(files.size(), 0,
			"the scene scan found no .tscn files under %s — scan roots are wrong, so no coverage was checked" % str(SCAN_ROOTS))
	for path in files:
		if not _is_particle_scene(String(path)):
			continue
		assert_true(_warm_paths.has(path),
				"'%s' contains a GPUParticles3D but is NOT in PreloadManager.PARTICLE_WARM_PATHS — its pipeline would first-compile mid-gameplay (a visible hitch, and the known NVIDIA D3D12 first-compile crash class); add it to the warm list" % path)


func test_destroy_effect_references_are_warmed() -> void:
	# Designer-assigned break/destroy VFX (ThrowableData.destroy_particle_scene, CanDestroy.destroy_effect)
	# are the seam where a NEW particle scene can ship from the Inspector without any code change — the one
	# route the code-facing tests above can't see coming. Any such reference that resolves to a particle
	# scene must be warmed; non-particle effects (e.g. the mesh-flash explosion_area_2) need no pipeline.
	var files: Array = []
	for root in SCAN_ROOTS:
		_collect_files(String(root), [".tscn", ".tres"], files)
	var ref_re := RegEx.create_from_string("^(destroy_particle_scene|destroy_effect)\\s*=\\s*ExtResource\\(\"([^\"]+)\"\\)")
	var refs_found := 0
	for path in files:
		var text := FileAccess.get_file_as_string(String(path))
		if not (text.contains("destroy_particle_scene") or text.contains("destroy_effect")):
			continue
		var ext_map := _ext_resource_map(text)
		for line in text.split("\n"):
			var m := ref_re.search(line)
			if m == null:
				continue
			refs_found += 1
			var target: String = String(ext_map.get(m.get_string(2), ""))
			assert_true(target != "",
					"%s: %s ExtResource id '%s' did not resolve to an ext_resource path — the scanner's serialization assumptions broke, so this leg can no longer be trusted" % [path, m.get_string(1), m.get_string(2)])
			if target != "" and _is_particle_scene(target):
				assert_true(_warm_paths.has(target),
						"%s assigns %s = '%s', a particle scene NOT in PreloadManager.PARTICLE_WARM_PATHS — the first prop break/destruction would first-compile it mid-gameplay; add it to the warm list" % [path, m.get_string(1), target])
	assert_gt(refs_found, 0,
			"no destroy_particle_scene/destroy_effect assignment was found anywhere under the scan roots — the project has several (dog.tscn, dogcrate.tscn, gore_gib_data.tres, ...), so the scan or the serialization format changed and this leg asserted nothing")


## The SubViewport _prewarm_gpu_particles parks under its PreloadManager, or null.
func _warm_viewport(pm: Node) -> SubViewport:
	for child in pm.get_children():
		if child is SubViewport:
			return child as SubViewport
	return null


## The features of an emitter that GENERATE particle shader code — the things that pick its ParticlesShaderRD
## variant — plus its draw mesh type. Plain values (amount, speeds, colours) are left out on purpose: they reuse a
## pipeline, so two emitters with equal feature sets share one compile.
func _pipeline_features(p: GPUParticles3D) -> Dictionary:
	var ppm := p.process_material as ParticleProcessMaterial
	if ppm == null:
		return {}
	return {
		emission_shape = ppm.emission_shape,
		color_ramp = ppm.color_ramp != null,
		color_initial_ramp = ppm.color_initial_ramp != null,
		scale_curve = ppm.scale_curve != null,
		turbulence = ppm.turbulence_enabled,
		collision_mode = ppm.collision_mode,
		draw_pass_1 = p.draw_pass_1.get_class() if p.draw_pass_1 != null else "",
	}


func test_prewarm_draws_every_warm_scene_in_its_own_world_then_frees_it() -> void:
	var pm: Node = load(PRELOAD_MANAGER_PATH).new()
	add_child_autofree(pm)  # _ready re-loads PATHS (cache hits) and skips the deferred warm-up on the headless renderer
	pm._prewarm_gpu_particles()  # a coroutine: runs to its first frame await, leaving the warm-up viewport live
	var vp := _warm_viewport(pm)
	assert_true(vp != null, "the boot warm-up must render into a throwaway SubViewport — none was created, so no particle pipeline is warmed at boot")
	if vp == null:
		return
	assert_true(vp.own_world_3d,
		"the warm-up viewport must own its World3D — sharing the main one would drop warm-up particles into gameplay physics and lighting")
	assert_true(vp.get_camera_3d() != null, "the warm-up viewport needs a current camera or nothing in it is drawn, and nothing compiles")
	var by_path := {}
	for child in vp.get_children():
		if child.scene_file_path != "":
			by_path[child.scene_file_path] = child
	for path in _warm_paths:
		var inst: Node = by_path.get(path)
		assert_true(inst is GPUParticles3D,
			"PARTICLE_WARM_PATHS entry '%s' was not instanced as an emitter in the warm-up viewport — its pipeline first-compiles mid-combat" % path)
		if inst is GPUParticles3D:
			assert_true((inst as GPUParticles3D).emitting,
				"'%s' sits in the warm-up viewport NOT emitting — an idle emitter draws nothing, so its pipeline never compiles at boot" % path)
			assert_false((inst as GPUParticles3D).one_shot,
				"'%s' is still one-shot in the warm-up — a short burst can finish before the driver compiles it; the warm-up must keep it emitting" % path)
		assert_true(pm._cache.has(path),
			"'%s' must stay cached after the warm-up — npc.gd load()s the muzzle FX at runtime and would pay the disk read on the first armed NPC" % path)
	# Poll for the teardown instead of counting frames: the warm-up's hold length is a compile-safety tuning knob that
	# has been retuned before, and this test is about the viewport going away, not how long it is held. The lambda
	# captures pm (alive until the test ends), never vp: a freed capture errors before the lambda body even runs.
	var torn_down: bool = await wait_until(func() -> bool: return _warm_viewport(pm) == null, 5.0, "warm-up viewport teardown")
	assert_true(torn_down and not is_instance_valid(vp),
		"the warm-up viewport must be freed once the pipelines have had their frames — left alive it renders emitters off-screen for the whole session")


func test_prewarmed_confetti_is_the_pipeline_a_confetti_kill_spawns() -> void:
	# The confetti trick-shot burst has no scene to list: it is built in code. What the boot warm-up renders and what a
	# kill actually spawns must be ONE pipeline, or the kill pays a first-time compile seconds after it lands.
	var pm: Node = load(PRELOAD_MANAGER_PATH).new()
	add_child_autofree(pm)
	pm._prewarm_gpu_particles()
	var vp := _warm_viewport(pm)
	assert_true(vp != null, "setup: the warm-up viewport exists")
	if vp == null:
		return
	var warmed: GPUParticles3D = null
	for child in vp.get_children():
		if child is GPUParticles3D and child.scene_file_path == "":
			warmed = child as GPUParticles3D
	assert_true(warmed != null, "the boot warm-up must also render the code-built confetti burst — no scene list can ever cover it")
	# The gameplay side: a confetti kill's spawn off a bare in-tree Throwable (its export defaults — the same tuning
	# the warm-up reads off its own throwaway Throwable).
	var prop: Node3D = load(THROWABLE_PATH).new()
	add_child_autofree(prop)
	# Found by diffing EVERY emitter in the tree, not the root's children: gameplay spawns parent through WorldSpawn
	# (the level / chunk when one exists), so where the burst lands is not this test's business.
	var emitters_before := get_tree().root.find_children("*", "GPUParticles3D", true, false)
	prop._spawn_confetti()
	var spawned: GPUParticles3D = null
	for node in get_tree().root.find_children("*", "GPUParticles3D", true, false):
		if not emitters_before.has(node):
			spawned = node as GPUParticles3D
	assert_true(spawned != null, "setup: Throwable._spawn_confetti must put a GPUParticles3D burst into the world")
	if warmed != null and spawned != null:
		assert_true(warmed.emitting, "the warmed confetti must be emitting in the warm-up viewport, or nothing compiles")
		assert_true(spawned.emitting, "a confetti kill fires its burst on spawn")
		assert_true(spawned.one_shot,
			"a kill's confetti must be a ONE-SHOT burst: _spawn_confetti frees it on `finished`, which a looping emitter never emits, so it would spray over the body forever (only the warm-up's own copy is switched to looping)")
		assert_false(_pipeline_features(spawned).is_empty(),
			"a kill's confetti has no ParticleProcessMaterial — there is no pipeline to compare, so the parity check below would pass on nothing")
		assert_eq(_pipeline_features(warmed), _pipeline_features(spawned),
			"the warmed confetti and a kill's confetti have different shader FEATURES (emission shape / ramps / turbulence / collision / mesh) — the kill mints an un-warmed pipeline")
		assert_eq(warmed.amount, spawned.amount,
			"the warm-up must build the confetti from the gameplay tuning (Throwable's confetti_amount), not a private copy of the numbers")
	if spawned != null:
		spawned.free()
	# Let the warm-up coroutine run to its end (it frees its viewport as its last step) before autofree drops pm: a
	# PreloadManager freed while the coroutine is still suspended logs an engine error on resume, and GUT pins that
	# error on whichever test is running at the time. Polled, so a retuned hold length can't outlast a frame count.
	await wait_until(func() -> bool: return _warm_viewport(pm) == null, 5.0, "warm-up coroutine finished")
