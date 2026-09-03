extends GutTest

## Contract tests for the boot-time GPU-particle pipeline prewarm (PreloadManager._prewarm_gpu_particles).
## A FIRST-TIME ParticlesShaderRD compile mid-gameplay is a known first-compile crash class on this dev
## machine's NVIDIA D3D12 driver (one real export first-boot crash during mass cache population — the
## playtest hard-crash first blamed on it turned out to be a separate godot-cpp build-flavour bug in the
## TTS GDExtension, since fixed) and, crash or not, a visible hitch — so every distinct particle pipeline
## is rendered once at boot instead. These tests are the ratchet that keeps that true as content grows:
## they scan scene/resource SOURCE TEXT off-tree (no gameplay scene is instanced, no _ready runs) and fail
## naming the exact path to add to PreloadManager.PARTICLE_WARM_PATHS. This boot pass compiles the
## particle PROCESS shaders; the draw pipelines are warmed by the in-level second stage (EffectPrewarmer at
## GameRoot.load_level), whose ratchet — tests/test_effect_prewarm.gd — requires every entry here to be
## in EffectPrewarmer.WARM_PATHS as well.

const PRELOAD_MANAGER_PATH := "res://managers/PreloadManager.gd"
const THROWABLE_PATH := "res://scripts/components/Throwable.gd"
## Where authored scenes/resources live. A particle scene saved outside these roots would dodge the scan,
## so keep them in sync with the project layout.
const SCAN_ROOTS: Array[String] = ["res://scenes", "res://resources"]
## Source-text tell that a .tscn DECLARES its own particle emitter node. A scene that merely instances
## another particle scene does not carry it — the root-instance leg of _is_particle_scene covers that
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


## True when the scene at `path` is a GPU-particle effect: it declares a GPUParticles3D node in its own
## text, or its root derives from a scene that does. Depth-guarded so a cyclic/deep derivation chain can
## never hang the suite.
func _is_particle_scene(path: String, depth: int = 0) -> bool:
	if depth > 4 or not path.ends_with(".tscn") or not FileAccess.file_exists(path):
		return false
	var text := FileAccess.get_file_as_string(path)
	if text.contains(PARTICLE_NODE_TAG):
		return true
	var base := _root_instance_path(text)
	return base != "" and _is_particle_scene(base, depth + 1)


## Slice one function's body out of a script's source: from its declaration line to the next top-level
## func (plain or static). Returns "" when the declaration is gone.
func _func_body(source: String, decl: String) -> String:
	var start := source.find(decl)
	if start < 0:
		return ""
	var next := source.find("\nfunc ", start + decl.length())
	var next_static := source.find("\nstatic func ", start + decl.length())
	if next_static >= 0 and (next < 0 or next_static < next):
		next = next_static
	if next < 0:
		return source.substr(start)
	return source.substr(start, next - start)


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


func test_spawn_confetti_routes_through_static_builder() -> void:
	var src := FileAccess.get_file_as_string(THROWABLE_PATH)
	var body := _func_body(src, "func _spawn_confetti(")
	assert_true(body != "",
			"Throwable.gd no longer has _spawn_confetti — if the confetti spawn moved/renamed, repoint this pin: its pipeline STILL needs the boot prewarm")
	assert_true(body.contains("build_confetti_burst("),
			"_spawn_confetti must construct its emitter via the shared static build_confetti_burst — that builder is what PreloadManager prewarms at boot, so an inline rebuild here would ship an un-warmed pipeline variant")
	assert_false(body.contains("ParticleProcessMaterial.new("),
			"_spawn_confetti builds a ParticleProcessMaterial inline again — move the construction back into build_confetti_burst so the boot prewarm compiles the REAL gameplay material, not a stale copy")


func test_prewarm_covers_warm_list_and_confetti() -> void:
	var src := FileAccess.get_file_as_string(PRELOAD_MANAGER_PATH)
	var body := _func_body(src, "func _prewarm_gpu_particles(")
	assert_true(body != "",
			"PreloadManager.gd no longer has _prewarm_gpu_particles — the boot particle warm-up (the first-compile hitch mitigation, and the guard against the known NVIDIA D3D12 first-compile crash class) must not be dropped")
	assert_true(body.contains("PARTICLE_WARM_PATHS"),
			"_prewarm_gpu_particles must iterate PARTICLE_WARM_PATHS — warming a private path list instead would let these contract tests pass while the boot pass warms something else entirely")
	assert_true(body.contains("build_confetti_burst("),
			"_prewarm_gpu_particles must also warm the code-built confetti burst via Throwable.build_confetti_burst — the one emitter no scene list can ever cover")


func test_confetti_builder_returns_configured_offtree_emitter() -> void:
	# Off-tree behavioral pin: the builder hands back a fully configured node (never parented, never
	# entering the tree here) whose material carries the code-GENERATING features that make this pipeline
	# its own ParticlesShaderRD variant. Values may retune freely; these features are the warm contract.
	var throwable: GDScript = load(THROWABLE_PATH)
	var p: GPUParticles3D = throwable.build_confetti_burst(8, 1.0, 3.0, 6.5, 0.6, 1.3)
	assert_not_null(p, "build_confetti_burst returned null instead of a configured GPUParticles3D")
	if p == null:
		return
	assert_true(p.one_shot, "confetti is a one-shot burst (the prewarm flips one_shot off itself to keep it drawing across warm-up frames)")
	assert_eq(p.amount, 8, "builder must apply the amount it was passed")
	var ppm := p.process_material as ParticleProcessMaterial
	assert_not_null(ppm, "confetti ParticleProcessMaterial missing — the builder no longer configures the material the prewarm exists to compile")
	if ppm != null:
		assert_eq(ppm.emission_shape, ParticleProcessMaterial.EMISSION_SHAPE_SPHERE,
				"confetti emits from a small sphere — a code-generating feature; changing it mints a new pipeline variant, which is fine ONLY because the prewarm builds through this same static")
		assert_not_null(ppm.color_initial_ramp,
				"rainbow color_initial_ramp missing — it is the feature that makes confetti its own ParticlesShaderRD variant (distinct from color_ramp), i.e. the whole reason this emitter must be prewarmed")
		assert_true(ppm.turbulence_enabled,
				"confetti turbulence_enabled is off — a code-generating feature the warmed pipeline must match")
	assert_not_null(p.draw_pass_1, "confetti fleck mesh (draw_pass_1) missing")
	p.free()
	# The boot prewarm reads the confetti tuning off a throwaway OFF-TREE Throwable (export defaults only;
	# _ready never runs) — prove that probe stays constructible bare, so a future initializer/setter that
	# needs the tree can't silently break the boot warm-up.
	var defaults: Object = throwable.new()
	assert_not_null(defaults, "Throwable.new() failed off-tree — PreloadManager's confetti-defaults probe would break at boot")
	if defaults != null:
		assert_gt(int(defaults.confetti_amount), 0,
				"confetti_amount export default must be positive — the prewarm emits with these defaults, and 0 particles would compile nothing")
		defaults.free()
