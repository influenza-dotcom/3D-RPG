extends GutTest

## Contract tests for the IN-LEVEL effect prewarm — stage two of the first-kill / first-hit hitch fix.
## Stage one is the boot-time SubViewport pass (PreloadManager._prewarm_gpu_particles, ratcheted by
## tests/test_preload_prewarm.gd): it compiles every GPU-particle PROCESS shader, but it runs during the
## boot screen, in a throwaway world, before game.tscn exists — so it can't build the draw pipelines
## (PSOs) gameplay actually uses: those are keyed on the renderer-global requirement set (the InkOutline
## normal-roughness prepass, the 16-bit shadow atlases, cubemap shadows) that only exists once the level
## and the player rig are live. EffectPrewarmer (scripts/components/effect_prewarmer.gd) closes that gap:
## GameRoot.load_level runs it right after the level enters the tree, and it draws every combat spawnable
## in EffectPrewarmer.WARM_PATHS once, in the REAL World3D, in front of the live camera, behind a black
## cover it raises itself — plus the code-built 2D/billboard feedback (damage numbers, bark icons) that has no
## precompilation at all. A real-renderer probe measured the first kill at ~+45 ms and the first hit at
## ~+20 ms over a warm repeat, with surface/specialization pipeline compiles appearing ONLY in first-use
## phases; scripts/tools/probes/__first_kill_hitch_probe.gd is that probe.
##
## The tests here, by kind:
##   LIST RATCHETS (off-tree, scene-text scans; helpers copied from test_preload_prewarm.gd, not shared — a
##   cross-test dependency would couple two ratchets):
##     (a) every PreloadManager.PARTICLE_WARM_PATHS entry is ALSO in WARM_PATHS (the two ambient_dust scenes
##         excepted — they already live in levels, so a live instance warms them at level load),
##     (b) every PreloadManager.PATHS entry whose .tscn declares a MeshInstance3D / GPUParticles3D / Decal
##         is in WARM_PATHS (a load()-cached scene that never DRAWS before the first kill is the exact gap),
##     (c) every WARM_PATHS entry exists on disk.
##   THE PASS, DRIVEN: warm() refuses the headless DisplayServer (nothing renders, so nothing compiles), so these
##   drive EffectPrewarmer._warm_pass — the body past that gate — in the GUT tree and look at what it leaves behind:
##   every warm scene instanced once and then parked hidden, frozen, collision-less, muted and KEPT; the black cover
##   up over the draw and down again on EVERY exit (a pass that completes, and one cut short in each of its holds —
##   it was visible for ~800 ms on every first load while it relied on the Player's spawn fade); the grid inside the
##   frustum; and the once-per-process latch (a second pass, on the same node or on a rebuilt one, draws nothing).
##   GAMEPLAY == WARM: the damage number DamageNumberPopup.show spawns and the alert icon NpcBarkUi.show_icon pops
##   carry the same material-shaping flags as the ones the pass drew — a different variant is a first-hit compile.
##   Player.add_xp is driven off-tree: its autosave is QUEUED to the end of the frame, never written on the kill frame.
##   THE LEVEL-LOAD SEAM: GameRoot.load_level is driven on a runtime-built subclass that only LOGS its PS1-warp handoff
##   and its prewarm call (both are ordinary self-calls, so they dispatch to the overrides): every fresh level load, boot
##   and a swap alike, prewarms AFTER the warp and with that level in the tree. What _prewarm_effects then does is not
##   drivable here — it returns on the headless DisplayServer before building anything — so only its wiring is pinned:
##   the script path GameRoot builds the prewarmer from must resolve to EffectPrewarmer (a miss is only a warning).
## GUT traps honoured: assert_lt/gt (no _le/_ge), assert_true(x != null) (assert_not_null stringifies eagerly), and
## assert_string_contains has NO message arg — assert_true(text.contains()).

const PRELOAD_MANAGER_PATH := "res://managers/PreloadManager.gd"
const EFFECT_PREWARMER_PATH := "res://scripts/components/effect_prewarmer.gd"
const GAME_ROOT_PATH := "res://scripts/world/game_root.gd"
const PLAYER_PATH := "res://scripts/player/player.gd"

## Particle scenes that are ALLOWED to be missing from WARM_PATHS: both ambient_dust scenes are placed in
## the levels themselves, so a live instance builds its surface cache (and so its PSOs) the moment the
## level loads — the in-level warm has nothing to add for them. The boot SubViewport still compiles their
## process shader (they stay in PARTICLE_WARM_PATHS). Any OTHER particle scene is a combat spawnable that
## first appears mid-fight and must be listed. Keep this list to scenes a level authors directly.
const AMBIENT_ONLY_PATHS: Array[String] = [
	"res://scenes/effects/ambient_dust.tscn",
	"res://scenes/components/ambient_dust.tscn",
	# Weather, the same shape: a level instances it and it draws from the first frame (it rides the camera), so
	# its PSOs are built by the level itself; it is never spawned mid-fight.
	"res://scenes/components/rain_fall.tscn",
]

## Scenes the FIRST kill reaches by a runtime load() / a first draw (the investigation's top resource-load
## and first-draw costs). They belong in PreloadManager.PATHS (disk I/O warm) AND — because each declares a
## MeshInstance3D — ratchet (b) then requires them in WARM_PATHS (pipeline warm) too.
const FIRST_KILL_SCENES: Array[String] = [
	# BodyPartGibs.default_scene() load()s the chassis on the FIRST death (not preload: Throwable<->Character cycle).
	"res://scenes/effects/body_part_gib.tscn",
	# Character.gib_scene's default — model.obj is drawn by NO other scene, so its pipelines are first-kill only.
	"res://scenes/effects/gore_gib.tscn",
	# The shipped NPC "ragdoll" (NPC.tscn ragdoll_scene) — bag.glb is never on screen before the first kill.
	"res://scenes/props/loot_bag.tscn",
]

## Source-text tells that a .tscn DECLARES something the renderer builds a pipeline (or an atlas) for. A
## scene that only INSTANCES another scene doesn't carry them — the root-instance leg of _declares_drawable
## covers a derived effect (spark_attack.tscn's root IS a dust.tscn instance).
const DRAWABLE_NODE_TAGS: Array[String] = [
	"type=\"MeshInstance3D\"",
	"type=\"GPUParticles3D\"",
	"type=\"Decal\"",
]

## The properties that pick a billboard's MATERIAL VARIANT / glyph raster — what has to match between the object the
## warm drew and the one gameplay spawns, or the warm compiled one pipeline and the first hit / alert pays another.
## Colour (modulate), scale and pixel_size (the quad's world size) are deliberately absent: they are per-instance
## parameters, not part of the key. The icon's texture is absent too: the test hands show_icon the warm icon's own.
const LABEL_VARIANT_PROPS: Array[StringName] = [
	&"billboard", &"shaded", &"double_sided", &"no_depth_test", &"fixed_size", &"alpha_cut",
	&"alpha_antialiasing_mode", &"texture_filter", &"render_priority", &"outline_render_priority",
	&"font", &"font_size", &"outline_size",
]
const SPRITE_VARIANT_PROPS: Array[StringName] = [
	&"billboard", &"shaded", &"double_sided", &"no_depth_test", &"fixed_size", &"alpha_cut",
	&"alpha_antialiasing_mode", &"texture_filter", &"render_priority", &"transparent",
]

## A Character that never runs Character._ready (GoreSpawner / DustSpawner / inventory setup) or its physics step —
## just enough of a victim for DamageNumberPopup.should_show's `is Character` + in-tree checks. Built at run time by
## path so this file still parses while character.gd is mid-edit.
const INERT_CHARACTER_SOURCE := "extends \"res://scripts/player/character.gd\"\n\nfunc _ready() -> void:\n\tpass\n\nfunc _physics_process(_delta: float) -> void:\n\tpass\n"

## A GameRoot that never boots (its _ready would write GameState.respawn_level_matches and defer a load) and whose two
## post-load passes only LOG what load_level handed them, in call order: "warp:<marker>" / "prewarm:<marker>", where
## <marker> names the level that pass could see IN THE TREE. load_level reaches both through plain self-calls, so the
## overrides receive them. Built at run time by path, like INERT_CHARACTER_SOURCE: game_root.gd is a @tool script that
## other work edits, and this file must still parse while it does.
const SPY_GAME_ROOT_SOURCE := "extends \"res://scripts/world/game_root.gd\"\n\nvar calls: Array = []\n\nfunc _ready() -> void:\n\tpass\n\nfunc _apply_ps1_warp(level_root: Node) -> void:\n\tcalls.append(\"warp:\" + _marker_in_tree(level_root))\n\nfunc _prewarm_effects() -> void:\n\tcalls.append(\"prewarm:\" + _marker_in_tree(_host().get_node_or_null(^\"Level\")))\n\nfunc _marker_in_tree(level_root: Node) -> String:\n\tif level_root == null or not level_root.is_inside_tree() or level_root.get_child_count() == 0:\n\t\treturn \"<no level in the tree>\"\n\treturn String(level_root.get_child(0).name)\n"
const WORLD_SNAPSHOT_PATH := "res://scripts/world/world_snapshot.gd"

var _preload_paths: Array = []
var _particle_paths: Array = []
var _warm_paths: Array = []
var _warmed_before: bool = false
# GameState fields GameRoot.load_level reads or writes (the tests/test_level_cache.gd set), banked around every test.
var _s_level_path: String = ""
var _s_apply_pending: String = ""
var _s_reload_pending: bool = false
var _s_ledger: RefCounted = null
var _s_dead: Dictionary = {}


func before_all() -> void:
	var pm: GDScript = load(PRELOAD_MANAGER_PATH)
	_preload_paths = pm.PATHS
	_particle_paths = pm.PARTICLE_WARM_PATHS
	# Read the warm list off the script's constant map rather than as a property: a missing/renamed const
	# then fails a test with a message instead of erroring out the whole file before any test runs.
	if FileAccess.file_exists(EFFECT_PREWARMER_PATH):
		var ep: GDScript = load(EFFECT_PREWARMER_PATH)
		if ep != null:
			var consts: Dictionary = ep.get_script_constant_map()
			var raw: Variant = consts.get("WARM_PATHS", [])
			if raw is Array:
				_warm_paths = raw


func before_each() -> void:
	# The draw pass is latched once per PROCESS (a static): every driven test starts from a process that has not
	# warmed yet, and after_each hands the latch back exactly as it found it for the files that run after this one.
	_warmed_before = EffectPrewarmer._warmed
	EffectPrewarmer._warmed = false
	# GameRoot.load_level talks to the GameState AUTOLOAD (records the active level path, arms and lifts its capture
	# guards); the level-load test drives it, so hand every field it touches back exactly as found.
	_s_level_path = GameState.current_level_path
	_s_apply_pending = GameState._level_apply_pending
	_s_reload_pending = GameState._reload_pending
	_s_ledger = GameState.world_snapshot
	_s_dead = GameState._dead_authored


func after_each() -> void:
	EffectPrewarmer._warmed = _warmed_before
	GameState.current_level_path = _s_level_path
	GameState._level_apply_pending = _s_apply_pending
	GameState._reload_pending = _s_reload_pending
	GameState.world_snapshot = _s_ledger
	GameState._dead_authored = _s_dead


# --- helpers: scene-text scanning (the list ratchets) ---------------------------------------------------------------

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
## or "" when the root is a plain typed node. Only the FIRST [node ...] tag is the root.
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


## True when the scene at `path` declares a MeshInstance3D / GPUParticles3D / Decal in its own text, or
## its root derives from a scene that does. Depth-guarded so a cyclic derivation chain can never hang.
func _declares_drawable(path: String, depth: int = 0) -> bool:
	if depth > 4 or not path.ends_with(".tscn") or not FileAccess.file_exists(path):
		return false
	var text := FileAccess.get_file_as_string(path)
	for tag in DRAWABLE_NODE_TAGS:
		if text.contains(String(tag)):
			return true
	var base := _root_instance_path(text)
	return base != "" and _declares_drawable(base, depth + 1)


# --- helpers: driving the pass --------------------------------------------------------------------------------------

## A live camera in the GUT world (identity transform, looking down -Z) for the pass to park its grid in front of.
func _camera() -> Camera3D:
	var cam := Camera3D.new()
	add_child_autofree(cam)
	return cam


## A fresh in-tree prewarmer, the way GameRoot builds one as a child of the game root.
func _warmer() -> EffectPrewarmer:
	var warmer := EffectPrewarmer.new()
	add_child_autofree(warmer)
	return warmer


## `warmer`'s black cover while it is up, or null (never raised / already taken down).
func _live_cover(warmer: EffectPrewarmer) -> CanvasLayer:
	var cover := warmer.get_node_or_null(NodePath(EffectPrewarmer.COVER_NODE)) as CanvasLayer
	if cover == null or cover.is_queued_for_deletion():
		return null
	return cover


## `node` and every descendant.
func _subtree(node: Node) -> Array[Node]:
	var out: Array[Node] = [node]
	for child in node.get_children():
		out.append_array(_subtree(child))
	return out


## Step process frames until `reached` returns true; false if it never does within `max_frames`.
func _frames_until(reached: Callable, max_frames: int = 240) -> bool:
	for _i in max_frames:
		if reached.call():
			return true
		await get_tree().process_frame
	return bool(reached.call())


## Pull a prewarmer with a pass still in flight out of the tree (what a death reload / level swap does to game.tscn
## mid-warm) and give its pass two frames to notice and exit.
func _leave_tree_mid_pass(warmer: EffectPrewarmer) -> void:
	remove_child(warmer)
	await get_tree().process_frame
	await get_tree().process_frame


## Start a pass WITHOUT awaiting it, step until `reached` says it is in the stretch under test, prove the cover is
## still up there (the control: an uninterrupted pass keeps it up), then pull the prewarmer out of the tree.
## Returns the cover that was up, so the caller can check the exit took it down. Untyped on purpose: by the time it
## returns, a working exit has FREED that cover, and a freed object at a typed return / parameter aborts the call.
func _cover_of_pass_cut_short(warmer: EffectPrewarmer, stretch: String, reached: Callable) -> Variant:
	warmer._warm_pass(_camera())
	var got_there: bool = await _frames_until(reached)
	assert_true(got_there, "the warm pass never reached its %s — the pass's structure changed; this test can't cut it short there" % stretch)
	var cover := _live_cover(warmer)
	assert_true(cover != null,
			"control: the black cover must be UP during the pass's %s — the warm grid is a full-brightness draw two metres from the camera" % stretch)
	await _leave_tree_mid_pass(warmer)
	return cover


func _assert_cover_taken_down(cover: Variant, stretch: String) -> void:
	var still_up: bool = is_instance_valid(cover) and not (cover as Node).is_queued_for_deletion()
	assert_false(still_up,
			"a warm pass cut short during its %s left its black cover up — that exit never called _drop_cover, and in a game that survives the reload (a LevelDoor swap re-parenting the prewarmer) the screen stays black" % stretch)


## Names of the `props` on which `shown` (what gameplay spawned) differs from `warmed` (what the pass drew).
func _variant_mismatches(shown: Object, warmed: Object, props: Array[StringName]) -> Array[String]:
	var out: Array[String] = []
	for p in props:
		if shown.get(p) != warmed.get(p):
			out.append("%s (gameplay %s vs warm %s)" % [p, shown.get(p), warmed.get(p)])
	return out


## The single warm node of `type` (a native class name) among the code-built effects, or null.
func _warm_node_of_type(warmer: EffectPrewarmer, type: String) -> Node:
	for n in warmer._warm_nodes:
		if is_instance_valid(n) and n.scene_file_path == "" and n.is_class(type):
			return n
	return null


# --- the list ratchets ----------------------------------------------------------------------------------------------

func test_every_boot_particle_scene_is_also_warmed_in_level() -> void:
	# Ratchet (a): the boot SubViewport compiles a particle's PROCESS shader; only the in-level pass can
	# build its DRAW pipelines under the live requirement set. Both lists must therefore agree, minus the
	# scenes a level already authors (AMBIENT_ONLY_PATHS).
	assert_gt(_particle_paths.size(), 0,
			"PreloadManager.PARTICLE_WARM_PATHS is empty — nothing to cross-check; the boot particle warm is gone (tests/test_preload_prewarm.gd guards that side)")
	for path in _particle_paths:
		if AMBIENT_ONLY_PATHS.has(String(path)):
			continue
		assert_true(_warm_paths.has(String(path)),
				"'%s' is in PreloadManager.PARTICLE_WARM_PATHS but NOT in EffectPrewarmer.WARM_PATHS — its process shader warms at boot, but its draw pipelines would still first-compile mid-combat; add it to WARM_PATHS in scripts/components/effect_prewarmer.gd" % path)
	for path in AMBIENT_ONLY_PATHS:
		assert_true(_particle_paths.has(String(path)),
				"allow-list entry '%s' is no longer in PreloadManager.PARTICLE_WARM_PATHS — prune it from this test's AMBIENT_ONLY_PATHS so the exemption can't quietly cover a future scene at that path" % path)


func test_every_drawable_preload_scene_is_warmed_in_level() -> void:
	# Ratchet (b): PreloadManager.PATHS keeps a PackedScene HOT on disk, but a load()ed scene that never
	# instantiates before the first kill compiles nothing — its meshes / particles / decals still hit the
	# renderer cold. Any PATHS entry that declares one of those must also be drawn by the in-level warm.
	assert_gt(_preload_paths.size(), 0,
			"PreloadManager.PATHS is empty — the disk-I/O warm list is gone, so this ratchet checked nothing")
	var drawable_found := 0
	for path in _preload_paths:
		if not _declares_drawable(String(path)):
			continue  # e.g. weapon.tscn / blood_drop.tscn: their visuals come from instanced children or none at all
		drawable_found += 1
		assert_true(_warm_paths.has(String(path)),
				"'%s' is in PreloadManager.PATHS and declares a MeshInstance3D/GPUParticles3D/Decal, but is NOT in EffectPrewarmer.WARM_PATHS — the scene is cache-warm yet its pipelines first-compile the frame it first spawns; add it to WARM_PATHS in scripts/components/effect_prewarmer.gd" % path)
	assert_gt(drawable_found, 0,
			"no PreloadManager.PATHS entry read as drawable to the scanner — the project has many (explosion_area, gore_gib, the projectiles, both decals, ...), so the .tscn serialization or the tag list changed and this ratchet asserted nothing")


func test_first_kill_scenes_are_preloaded() -> void:
	# The three scenes the investigation found paid on the FIRST kill as a runtime load() or a first draw.
	# PATHS pins the disk read; ratchet (b) above then carries each into WARM_PATHS for the pipelines.
	for path in FIRST_KILL_SCENES:
		assert_true(FileAccess.file_exists(String(path)),
				"'%s' does not exist on disk — this test's FIRST_KILL_SCENES list names a moved/renamed scene; repoint it (and the matching PreloadManager.PATHS entry)" % path)
		assert_true(_preload_paths.has(String(path)),
				"'%s' is NOT in PreloadManager.PATHS — the first death still pays a synchronous disk load / parse for it inside the death freeze; add it to PATHS in managers/PreloadManager.gd" % path)


func test_warm_list_entries_exist_on_disk() -> void:
	# Ratchet (c): a renamed/moved scene would silently un-warm itself — the prewarmer skips a missing
	# path with only a warning, and the first spawn hitches again with nothing in the log to explain it.
	# The size assert first: an EMPTY list would otherwise make zero assertions and read as a "risky" pass.
	assert_gt(_warm_paths.size(), 0,
			"EffectPrewarmer.WARM_PATHS is empty (or the script / the const is missing) — the in-level warm draws nothing, so every combat spawnable first-compiles its pipelines mid-fight again")
	for path in _warm_paths:
		assert_true(String(path).begins_with("res://") and String(path).ends_with(".tscn"),
				"EffectPrewarmer.WARM_PATHS entry '%s' is not a res://...tscn path — the list holds authored scene paths (not uid:// or scripts) so it stays human-readable and scannable" % path)
		assert_true(FileAccess.file_exists(String(path)),
				"EffectPrewarmer.WARM_PATHS entry '%s' does not exist on disk — fix the path in scripts/components/effect_prewarmer.gd (the prewarmer skips a missing entry with only a warning, so its pipelines would first-compile mid-combat again)" % path)


# --- the pass, driven -----------------------------------------------------------------------------------------------

func test_warm_refuses_to_draw_on_the_headless_display_server() -> void:
	if DisplayServer.get_name() != "headless":
		pending("warm()'s headless refusal can only be observed on the headless DisplayServer (this run renders)")
		return
	var cam := _camera()
	var warmer := _warmer()
	await warmer.warm(cam)
	assert_eq(warmer.get_child_count(), 0,
			"EffectPrewarmer.warm built something on the headless DisplayServer — nothing renders there, so nothing compiles: CI / the soak harness would pay the whole draw pass (and its instances' _ready side effects) for nothing")
	assert_false(EffectPrewarmer._warmed,
			"EffectPrewarmer.warm spent the once-per-process latch on a headless run — a draw pass it never performed")
	# Control: the same prewarmer, same tree, past the render gate, does build.
	warmer._warm_pass(cam)
	assert_gt(warmer._warm_nodes.size(), 0,
			"control: the pass past warm()'s gate must instance warm scenes in this very setup — otherwise the refusal above proved nothing")
	await _leave_tree_mid_pass(warmer)


func test_first_pass_draws_every_warm_scene_once_then_parks_it_hidden_inert_and_kept() -> void:
	var cam := _camera()
	var warmer := _warmer()
	await warmer._warm_pass(cam)
	await get_tree().process_frame  # past the end-of-frame deletes the pass queued (its cover)

	# Every listed scene went through the live world exactly once.
	var instanced := {}
	for n in warmer._warm_nodes:
		if is_instance_valid(n) and n.scene_file_path != "":
			instanced[n.scene_file_path] = int(instanced.get(n.scene_file_path, 0)) + 1
	for path in EffectPrewarmer.WARM_PATHS:
		assert_eq(int(instanced.get(path, 0)), 1,
				"the warm pass drew '%s' %d times, not once — a scene it skips first-compiles its pipelines on the first kill / hit; one it draws twice doubles the load-in cost" % [path, int(instanced.get(path, 0))])

	# The code-built feedback nothing on disk lists.
	var label := _warm_node_of_type(warmer, "Label3D") as Label3D
	assert_true(label != null, "the warm pass drew no damage-number Label3D — the first hit mints its material variant + glyph raster mid-fight")
	if label != null:
		for digit in range(10):
			assert_true(label.text.contains(str(digit)),
					"the warm damage number never rasterised the digit %d — the first hit showing it pays the glyph raster" % digit)
	assert_true(_warm_node_of_type(warmer, "Sprite3D") != null,
			"the warm pass drew no alert-icon Sprite3D — the first NPC alert mints its material variant mid-firefight")
	assert_true(_warm_node_of_type(warmer, "GPUParticles3D") != null,
			"the warm pass drew no confetti burst — the first trick shot compiles its draw pipelines on the spot")

	# Parked: hidden, not simulating, and KEPT (freeing under an in-flight background compile is a use-after-free).
	for n in warmer._warm_nodes:
		assert_true(is_instance_valid(n) and n.get_parent() == warmer,
				"a warm instance was freed or moved after the pass — they must stay alive under the prewarmer (a material freed under an in-flight compile is a crash)")
		if not is_instance_valid(n):
			continue
		if n is Node3D:
			assert_false((n as Node3D).visible,
					"warm instance '%s' is still visible after the pass — it sits two metres in front of the player's face for the whole level" % n.name)
		if n.scene_file_path != "" and not (n is GPUParticles3D):
			# (An emitter ROOT is deliberately ALWAYS — _arm_particles un-pauses it to draw; parking stops its emission.)
			assert_false(n.can_process(),
					"warm scene '%s' can still process after the pass — its fade timers / self-free / body_entered would run on a hidden prop" % n.scene_file_path)
		for part in _subtree(n):
			if part is GPUParticles3D:
				assert_false((part as GPUParticles3D).emitting,
						"'%s' in warm instance '%s' is still emitting after the pass — a hidden emitter simulating for the whole level" % [part.name, n.name])

	# Inert from the moment it entered: nothing collides, nothing falls, nothing is heard, nothing hurts. The counters
	# keep these checks honest — the list holds projectiles, gibs, a blast and a growing decal, so none may be vacuous.
	var bodies_checked := 0
	var blasts_checked := 0
	var growing_decals_checked := 0
	for n in warmer._warm_nodes:
		if not is_instance_valid(n):
			continue
		for part in _subtree(n):
			if part is CollisionObject3D:
				bodies_checked += 1
				var co := part as CollisionObject3D
				assert_true(co.collision_layer == 0 and co.collision_mask == 0,
						"'%s' in warm instance '%s' is still on collision layer %d / mask %d — the player can bump into (or be hit by) an invisible warm prop" % [part.name, n.name, co.collision_layer, co.collision_mask])
			if part is RigidBody3D:
				assert_true((part as RigidBody3D).freeze,
						"rigid body '%s' in warm instance '%s' is not frozen — it falls / rolls out of the warm grid" % [part.name, n.name])
			var volume: Variant = part.get(&"volume_db") if (part is AudioStreamPlayer or part is AudioStreamPlayer2D or part is AudioStreamPlayer3D) else null
			if volume != null:
				assert_true(float(volume) <= -60.0,
						"audio player '%s' in warm instance '%s' is at %.1f dB — the warm pass is audible on every level load" % [part.name, n.name, float(volume)])
			if part.get(&"deals_damage") != null:
				blasts_checked += 1
				assert_false(bool(part.get(&"deals_damage")),
						"warm explosion '%s' still deals damage — the load-in warm would blast the player standing two metres away" % n.name)
			if part is Decal and part.get(&"target_size") is Vector3:
				growing_decals_checked += 1
				assert_true((part as Decal).size.is_equal_approx(part.get(&"target_size")),
						"warm decal '%s' is still at its 1 mm spawn size — its grow tween never runs on a DISABLED node, so it projects onto nothing and warms nothing" % n.name)
	assert_gt(bodies_checked, 0, "no collision body / area found in any warm instance — the inert checks above checked nothing (the projectiles, gibs and blast all carry one)")
	assert_gt(blasts_checked, 0, "no warm instance exposes deals_damage — explosion_area.tscn's blast was not drawn, so its neutralising went unchecked")
	assert_gt(growing_decals_checked, 0, "no warm Decal exposes target_size — blood_splat_decal.tscn was not drawn, so its full-size start went unchecked")

	# The node itself back at rest, the cover gone, the decal-atlas keeper alive and hidden.
	assert_true(warmer.visible, "the prewarmer was left hidden after its pass — the node's resting state is visible (its parked children hide on their own flags)")
	assert_true(_live_cover(warmer) == null,
			"the black cover is still up after a COMPLETED warm pass — the screen stays black for the rest of the session")
	var keeper := warmer.get_node_or_null(NodePath(EffectPrewarmer.DECAL_KEEPER_NODE)) as Node3D
	assert_true(keeper != null, "no decal-atlas keeper after the pass — the first bullet hole repacks the global decal atlas mid-fight")
	if keeper != null:
		assert_false(keeper.visible, "the decal-atlas keeper is visible — a stray bullet hole floating in the level")
		assert_false(keeper.can_process(), "the decal-atlas keeper can process — its fade timer would free it and evict the atlas texture")
		assert_false(warmer._warm_nodes.has(keeper), "the decal-atlas keeper is listed among the warm instances — it is per-game.tscn, not part of the once-per-process pass")


func test_second_pass_is_a_no_op_on_the_same_node_and_on_a_rebuilt_one() -> void:
	var cam := _camera()
	var first := _warmer()
	await first._warm_pass(cam)
	await get_tree().process_frame
	var drawn := first._warm_nodes.size()
	var children := first.get_child_count()
	# Control: the first pass of the process really drew.
	assert_gt(drawn, EffectPrewarmer.WARM_PATHS.size() - 1,
			"control: the process's FIRST warm pass drew only %d instances — the latch (or something before it) stopped a pass that should have run" % drawn)

	# Again on the same node (a LevelDoor swap re-running load_level): nothing new, no cover.
	await first._warm_pass(cam)
	assert_eq(first._warm_nodes.size(), drawn,
			"a SECOND warm pass in the same process instanced more warm scenes — the pipelines already exist for the process's lifetime, so every level swap would re-pay the load-in frames")
	assert_eq(first.get_child_count(), children,
			"a second warm pass on the same prewarmer added children (a cover, a keeper, instances) — it must be a no-op")

	# A rebuilt prewarmer (a death reload frees game.tscn and builds a new one): draws nothing, raises no cover, but
	# still re-creates its decal-atlas keeper — that one dies with game.tscn, so it is the exception to the latch.
	var rebuilt := _warmer()
	await rebuilt._warm_pass(cam)
	assert_eq(rebuilt._warm_nodes.size(), 0,
			"a prewarmer rebuilt by a death reload ran the draw pass again — the once-per-process latch is not holding")
	assert_true(rebuilt.get_node_or_null(NodePath(EffectPrewarmer.COVER_NODE)) == null,
			"a latched pass raised a black cover anyway — a death reload would flash black over a pass that never draws")
	assert_true(rebuilt.get_node_or_null(NodePath(EffectPrewarmer.DECAL_KEEPER_NODE)) != null,
			"a rebuilt prewarmer did not re-create its decal-atlas keeper — after the first death reload the atlas texture is evicted with the old game.tscn and the next bullet hole repacks it mid-fight")


func test_cover_is_an_opaque_full_screen_black_up_before_the_first_warm_instance_draws() -> void:
	var warmer := _warmer()
	warmer._warm_pass(_camera())  # not awaited: runs synchronously up to the pass's first frame hold
	assert_gt(warmer._warm_nodes.size(), 0,
			"control: by its first frame hold the pass must already have warm instances in the world")
	var cover := _live_cover(warmer)
	assert_true(cover != null,
			"warm instances are in the world and about to draw, but no black cover is up — the grid plays out at full brightness in front of the player on every first level load (the Player's spawn fade is NOT a cover: its tween burns its whole duration on the load frame's delta)")
	if cover != null:
		assert_true(cover.visible, "the warm cover's CanvasLayer is hidden — it covers nothing")
		var rect: ColorRect = null
		for child in cover.get_children():
			if child is ColorRect:
				rect = child
		assert_true(rect != null, "the warm cover has no ColorRect — nothing is painted over the draw pass")
		if rect != null:
			assert_true(rect.color.is_equal_approx(Color.BLACK),
					"the warm cover paints %s, not opaque black — the warm grid shows through it" % rect.color)
			var screen := cover.get_viewport().get_visible_rect()
			assert_true(rect.get_global_rect().encloses(screen),
					"the warm cover rect %s does not enclose the screen %s — part of the warm grid is visible around it" % [rect.get_global_rect(), screen])
			assert_eq(rect.mouse_filter, Control.MOUSE_FILTER_IGNORE,
					"the warm cover eats mouse input — a click during the load-in warm is swallowed")
	await _leave_tree_mid_pass(warmer)


func test_pass_cut_short_while_instancing_takes_its_cover_down() -> void:
	var warmer := _warmer()
	var cover: Variant = await _cover_of_pass_cut_short(warmer, "scene-instancing loop",
			func() -> bool: return warmer._warm_nodes.size() > 0 and warmer._warm_nodes.size() < EffectPrewarmer.WARM_PATHS.size())
	_assert_cover_taken_down(cover, "scene-instancing loop")


func test_pass_cut_short_during_the_visible_hold_takes_its_cover_down() -> void:
	var warmer := _warmer()
	warmer.frames_visible = 12  # a wide window to cut it in
	var cover: Variant = await _cover_of_pass_cut_short(warmer, "visible hold",
			func() -> bool: return warmer._warm_nodes.size() > EffectPrewarmer.WARM_PATHS.size() and warmer.visible)
	_assert_cover_taken_down(cover, "visible hold")


func test_pass_cut_short_during_the_hidden_hold_takes_its_cover_down() -> void:
	var warmer := _warmer()
	warmer.frames_hidden = 12  # a wide window to cut it in
	var cover: Variant = await _cover_of_pass_cut_short(warmer, "hidden hold",
			func() -> bool: return not warmer.visible)
	_assert_cover_taken_down(cover, "hidden hold")


func test_warm_grid_parks_every_slot_in_front_of_the_camera_without_stacking() -> void:
	var warmer := _warmer()
	warmer.spawn_distance = 2.5
	var cam := _camera()
	cam.global_transform = Transform3D(Basis(Vector3.UP, deg_to_rad(90.0)), Vector3(4.0, 1.5, -2.0))
	var forward := -cam.global_transform.basis.z
	var slots := EffectPrewarmer.WARM_PATHS.size() + 3  # every scene plus the code-built label / icon / confetti
	var placed: Array[Vector3] = []
	for slot in slots:
		var p := warmer._slot_position(cam, slot)
		assert_almost_eq((p - cam.global_position).dot(forward), 2.5, 0.001,
				"warm slot %d is not spawn_distance ahead of the camera along its view axis — it is parked behind or beside the player and warms nothing" % slot)
		assert_true(cam.is_position_in_frustum(p),
				"warm slot %d at %s falls outside the camera frustum — a culled instance compiles no draw pipeline" % [slot, p])
		for other in placed.size():
			assert_gt(p.distance_to(placed[other]), warmer.spawn_spread * 0.5,
					"warm slots %d and %d overlap — the grid stacks instances on one point instead of spreading them across the view" % [other, slot])
		placed.append(p)


func test_neutralise_freezes_uncollides_and_mutes_the_whole_subtree() -> void:
	var root := RigidBody3D.new()
	root.collision_layer = 5
	root.collision_mask = 3
	var loud_3d := AudioStreamPlayer3D.new()
	loud_3d.autoplay = true
	root.add_child(loud_3d)
	var holder := Node3D.new()
	root.add_child(holder)
	var area := Area3D.new()
	area.collision_layer = 1
	area.collision_mask = 1
	holder.add_child(area)
	var loud := AudioStreamPlayer.new()
	loud.autoplay = true
	area.add_child(loud)
	var loud_2d := AudioStreamPlayer2D.new()
	loud_2d.autoplay = true
	holder.add_child(loud_2d)
	var nested_body := RigidBody3D.new()
	holder.add_child(nested_body)

	EffectPrewarmer._neutralise(root)

	for co: CollisionObject3D in [root, area, nested_body]:
		assert_true(co.collision_layer == 0 and co.collision_mask == 0,
				"'%s' (depth %d) keeps collision layer %d / mask %d after _neutralise — a warm instance deep in a scene can still be walked into or shot" % [co.get_class(), _depth(co, root), co.collision_layer, co.collision_mask])
	for body: RigidBody3D in [root, nested_body]:
		assert_true(body.freeze, "a RigidBody3D at depth %d is not frozen by _neutralise — it drops out of the warm grid" % _depth(body, root))
	assert_true(not loud_3d.autoplay and loud_3d.volume_db <= -60.0,
			"the AudioStreamPlayer3D under the root still autoplays / is audible after _neutralise")
	assert_true(not loud.autoplay and loud.volume_db <= -60.0,
			"an AudioStreamPlayer two levels down still autoplays / is audible after _neutralise — the load-in warm plays a sound")
	assert_true(not loud_2d.autoplay and loud_2d.volume_db <= -60.0,
			"an AudioStreamPlayer2D under a plain Node3D still autoplays / is audible after _neutralise")
	root.free()


func _depth(node: Node, root: Node) -> int:
	var d := 0
	var cur := node
	while cur != root and cur != null:
		cur = cur.get_parent()
		d += 1
	return d


func test_armed_emitter_simulates_under_a_disabled_warm_root_and_stops_when_parked() -> void:
	var root := Node3D.new()
	root.process_mode = Node.PROCESS_MODE_DISABLED  # what _warm_scene does to every warm instance
	var holder := Node3D.new()
	root.add_child(holder)
	var emitter := GPUParticles3D.new()
	emitter.one_shot = true
	emitter.emitting = false
	holder.add_child(emitter)
	add_child_autofree(root)
	# Control: under a DISABLED warm root an un-armed emitter never simulates, so its draw would cover an empty buffer.
	assert_false(emitter.can_process(), "control: an emitter under a PROCESS_MODE_DISABLED root must not process before arming")

	EffectPrewarmer._arm_particles(root)
	assert_true(emitter.can_process(),
			"an armed emitter under the DISABLED warm root still can't process — the draw pass is issued over an empty particle buffer and compiles nothing useful")
	assert_true(emitter.emitting and not emitter.one_shot,
			"an armed emitter is not continuously emitting (emitting %s, one_shot %s) — a one-shot burst finishes before the warm frames draw it" % [emitter.emitting, emitter.one_shot])
	assert_false(holder.can_process(),
			"arming the particles re-enabled processing on a non-emitter node — the warm instance's timers / self-free would run")

	EffectPrewarmer._stop_particles(root)
	assert_false(emitter.emitting, "a parked warm emitter is still emitting — it simulates hidden for the rest of the level")


# --- gameplay spawns what the pass drew -----------------------------------------------------------------------------

func test_gameplay_damage_number_carries_the_variant_the_warm_pass_drew() -> void:
	var warmer := _warmer()
	await warmer._warm_pass(_camera())
	var warm_label := _warm_node_of_type(warmer, "Label3D") as Label3D
	assert_true(warm_label != null, "the warm pass drew no damage-number Label3D — nothing to compare gameplay's against")
	var player_script: GDScript = load(PLAYER_PATH)
	var victim_script := GDScript.new()
	victim_script.source_code = INERT_CHARACTER_SOURCE
	var reload_err := victim_script.reload()
	assert_true(player_script != null and reload_err == OK,
			"could not build the Player shooter / Character victim (player.gd or character.gd failed to load) — the damage-number spawn can't be driven")
	if warm_label == null or player_script == null or reload_err != OK:
		return
	var attacker: Node = player_script.new()  # off-tree: only `is Player` is read; its _ready never runs
	var victim: Node3D = victim_script.new()
	add_child_autofree(victim)

	for crit in [false, true]:
		var before := get_tree().root.find_children("*", "Label3D", true, false)
		DamageNumberPopup.show(victim, 37.0, Vector3(0.0, 1.0, 0.0), crit, attacker)
		var spawned: Array[Node] = []
		for n in get_tree().root.find_children("*", "Label3D", true, false):
			if not before.has(n):
				spawned.append(n)
		assert_eq(spawned.size(), 1,
				"DamageNumberPopup.show (crit %s) spawned %d Label3Ds for one player hit on a Character, not 1" % [crit, spawned.size()])
		if spawned.size() != 1:
			continue
		var shown := spawned[0] as Label3D
		var mismatches := _variant_mismatches(shown, warm_label, LABEL_VARIANT_PROPS)
		assert_eq(mismatches.size(), 0,
				"the damage number gameplay spawns (crit %s) is not the label variant the warm pass drew — first hit compiles a new pipeline mid-fight; differs on: %s" % [crit, ", ".join(mismatches)])
		for ch in shown.text:
			assert_true(warm_label.text.contains(ch),
					"gameplay's damage number shows '%s', a glyph the warm label never rasterised" % ch)
		shown.free()
	attacker.free()


func test_gameplay_alert_icon_carries_the_variant_the_warm_pass_drew() -> void:
	var warmer := _warmer()
	await warmer._warm_pass(_camera())
	var warm_icon := _warm_node_of_type(warmer, "Sprite3D") as Sprite3D
	assert_true(warm_icon != null and warm_icon.texture != null,
			"the warm pass drew no textured alert-icon Sprite3D — nothing to compare gameplay's against")
	if warm_icon == null or warm_icon.texture == null:
		return
	var bark := NpcBarkUi.new()
	add_child_autofree(bark)
	for follow in [true, false]:
		var before := get_tree().root.find_children("*", "Sprite3D", true, false)
		bark.show_icon(warm_icon.texture, follow)
		var spawned: Array[Node] = []
		for n in get_tree().root.find_children("*", "Sprite3D", true, false):
			if not before.has(n):
				spawned.append(n)
		assert_eq(spawned.size(), 1,
				"NpcBarkUi.show_icon (follow %s) popped %d Sprite3Ds for one alert, not 1" % [follow, spawned.size()])
		if spawned.size() != 1:
			continue
		var mismatches := _variant_mismatches(spawned[0], warm_icon, SPRITE_VARIANT_PROPS)
		assert_eq(mismatches.size(), 0,
				"the alert icon gameplay pops (follow %s) is not the sprite variant the warm pass drew — the first alert compiles a new pipeline mid-firefight; differs on: %s" % [follow, ", ".join(mismatches)])
		spawned[0].free()


# --- the kill frame writes nothing ----------------------------------------------------------------------------------

func test_add_xp_queues_its_autosave_to_the_end_of_the_frame() -> void:
	var player_script: GDScript = load(PLAYER_PATH)
	assert_true(player_script != null, "player.gd failed to load — Player.add_xp can't be driven")
	if player_script == null:
		return
	var p = player_script.new()  # off-tree: _ready never runs; the deferred flush hits GameState.autosave's tree guard
	# Control / guard: a grant of nothing changes nothing and queues no write.
	p.add_xp(0.0)
	assert_false(p._autosave_queued, "Player.add_xp(0) queued an autosave — a zero grant must not touch the profile")
	p.add_xp(25.0)
	assert_true(p._autosave_queued,
			"Player.add_xp did not QUEUE its autosave — every credited kill must ride the coalesced end-of-frame _queue_autosave (the wallet's seam), never a synchronous profile serialise + disk write inside the death-freeze frame")
	await get_tree().process_frame
	await get_tree().process_frame
	assert_false(p._autosave_queued,
			"the autosave Player.add_xp queued was never flushed by the end of the frame — XP from a kill would not reach the profile")
	p.free()


# --- the level-load seam --------------------------------------------------------------------------------------------

## An in-memory level for GameRoot.load_level: its root carries ONE child named `marker` (so a spy can tell which level
## a pass saw) and the LevelData has no resource_path (so GameRoot's level cache never parks or restores it).
func _in_memory_level(marker: String) -> LevelData:
	var root := Node3D.new()
	var tag := Node.new()
	tag.name = marker
	root.add_child(tag)
	tag.owner = root
	var scene := PackedScene.new()
	var packed := scene.pack(root)
	root.free()
	assert_eq(packed, OK, "could not pack the in-memory test level '%s' — load_level has nothing to instance" % marker)
	var data := LevelData.new()
	data.scene = scene
	return data


func test_load_level_prewarms_after_the_ps1_warp_with_the_level_in_the_tree() -> void:
	# The warm must see the level IN the tree (the renderer-global requirement set it compiles against only exists once
	# level + rig are live) and must come AFTER the PS1-warp handoff (so the warm instances, parented under the host,
	# are never swept into the level's material override pass) — on EVERY fresh level load: boot and a LevelDoor swap.
	var spy_script := GDScript.new()
	spy_script.source_code = SPY_GAME_ROOT_SOURCE
	var reload_err := spy_script.reload()
	assert_eq(reload_err, OK,
			"could not build the spy GameRoot (game_root.gd failed to load, or load_level's pass names changed) — the level-load order can't be driven")
	if reload_err != OK:
		return
	GameState.current_level_path = ""  # both test levels are pathless: the load records no change of level
	var snapshot_script: GDScript = load(WORLD_SNAPSHOT_PATH)
	GameState.world_snapshot = snapshot_script.new()  # a fresh, empty world ledger for this load
	GameState._dead_authored = {}
	var gr = spy_script.new()
	add_child_autofree(gr)

	gr.load_level(_in_memory_level("BootLevel"), &"", false)
	var calls: Array = gr.calls
	assert_eq(calls, ["warp:BootLevel", "prewarm:BootLevel"],
			"a boot load_level must hand the level to the PS1 warp and THEN fire the effect prewarm with that level in the tree — anything else means the prewarm never runs (the first kill hitches again), runs before the level is live (it compiles against the wrong renderer keys), or runs before the warp (its instances ride the level's material sweep)")

	gr.load_level(_in_memory_level("DoorLevel"), &"", false)
	calls = gr.calls
	assert_eq(calls, ["warp:BootLevel", "prewarm:BootLevel", "warp:DoorLevel", "prewarm:DoorLevel"],
			"a level SWAP (a LevelDoor re-running load_level) must warp and then prewarm the NEW level, in the tree — the prewarmer's own once-per-process latch, not load_level, is what decides whether it draws again")
	await get_tree().process_frame  # let load_level's deferred dead-NPC sweep run against this test's empty ledger


func test_game_root_builds_its_prewarmer_from_a_path_that_resolves_to_the_effect_prewarmer() -> void:
	# Wiring pin (the exported-path-resolves kind): GameRoot._prewarm_effects builds the prewarmer by SCRIPT PATH at run
	# time and only push_warnings when that load fails, so a moved or renamed effect_prewarmer.gd would silently switch
	# the whole in-level warm off. The call itself is not drivable headless (the helper returns before the load).
	var game_root_script: GDScript = load(GAME_ROOT_PATH)
	assert_true(game_root_script != null, "game_root.gd failed to load — the prewarmer wiring can't be checked")
	if game_root_script == null:
		return
	var consts: Dictionary = game_root_script.get_script_constant_map()
	var path: String = str(consts.get("EFFECT_PREWARMER_SCRIPT_PATH", ""))
	assert_true(path != "" and ResourceLoader.exists(path),
			"GameRoot.EFFECT_PREWARMER_SCRIPT_PATH ('%s') is missing or names no file — GameRoot can't build the prewarmer and every level load skips the effect warm with only a warning" % path)
	if path == "" or not ResourceLoader.exists(path):
		return
	var built: Script = load(path) as Script
	var probe := EffectPrewarmer.new()
	assert_true(built != null and built == probe.get_script(),
			"GameRoot.EFFECT_PREWARMER_SCRIPT_PATH ('%s') resolves to a script that is not EffectPrewarmer — the node GameRoot builds is not the pass these tests drive" % path)
	probe.free()
