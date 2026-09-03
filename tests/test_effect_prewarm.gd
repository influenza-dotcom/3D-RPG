extends GutTest

## Contract tests for the IN-LEVEL effect prewarm — stage two of the first-kill / first-hit hitch fix.
## Stage one is the boot-time SubViewport pass (PreloadManager._prewarm_gpu_particles, ratcheted by
## tests/test_preload_prewarm.gd): it compiles every GPU-particle PROCESS shader, but it runs during the
## boot screen, in a throwaway world, before game.tscn exists — so it can't build the draw pipelines
## (PSOs) gameplay actually uses: those are keyed on the renderer-global requirement set (the InkOutline
## normal-roughness prepass, the 16-bit shadow atlases, cubemap shadows) that only exists once the level
## and the player rig are live. EffectPrewarmer (scripts/components/effect_prewarmer.gd) closes that gap:
## GameRoot.load_level runs it right after the level enters the tree, and it draws every combat spawnable
## in EffectPrewarmer.WARM_PATHS once, in the REAL World3D, in front of the live camera, on the black
## fade-in — plus the code-built 2D/billboard feedback (damage numbers, bark icons) that has no
## precompilation at all. A real-renderer probe measured the first kill at ~+45 ms and the first hit at
## ~+20 ms over a warm repeat, with surface/specialization pipeline compiles appearing ONLY in first-use
## phases; scripts/tools/__first_kill_hitch_probe.gd is that probe.
##
## Everything here is OFF-TREE source-text scanning, the test_preload_prewarm.gd idiom (its helpers are
## copied, not shared — a cross-test dependency would couple two ratchets): no gameplay scene is
## instanced, no _ready runs, and every failure names the exact res:// path or call to add. Ratchets:
##   (a) every PreloadManager.PARTICLE_WARM_PATHS entry is ALSO in WARM_PATHS (the two ambient_dust scenes
##       excepted — they already live in levels, so a live instance warms them at level load),
##   (b) every PreloadManager.PATHS entry whose .tscn declares a MeshInstance3D / GPUParticles3D / Decal
##       is in WARM_PATHS (a load()-cached scene that never DRAWS before the first kill is the exact gap),
##   (c) every WARM_PATHS entry exists on disk,
##   (d) source pins on the seams the warm relies on: DamageNumberPopup.show / NpcBarkUi.show_icon route
##       through their static builders (so the warm draws the SAME object gameplay builds), load_level
##       invokes the prewarmer after _apply_ps1_warp, and Player.add_xp queues its autosave instead of
##       writing the profile synchronously on the kill frame.
## ⭐A NEGATIVE source pin matches CALL text ("GameState.autosave(self)"), never a bare name: this
## project's headers are explanatory, and a comment naming the thing a function deliberately avoids would
## turn a bare-name guard red (memory: source-text-assert-matches-its-own-disclaimer). GUT traps honoured:
## assert_lte/gte (no _le/_ge), and assert_string_contains has NO message arg — assert_true(text.contains()).

const PRELOAD_MANAGER_PATH := "res://managers/PreloadManager.gd"
const EFFECT_PREWARMER_PATH := "res://scripts/components/effect_prewarmer.gd"
const DAMAGE_NUMBER_PATH := "res://scripts/combat/damage_number_popup.gd"
const BARK_UI_PATH := "res://scripts/npc/npc_bark_ui.gd"
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

var _preload_paths: Array = []
var _particle_paths: Array = []
var _warm_paths: Array = []


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


func test_prewarmer_declares_the_contract_surface() -> void:
	assert_true(FileAccess.file_exists(EFFECT_PREWARMER_PATH),
			"%s is missing — the in-level effect prewarm (stage two of the first-kill hitch fix) is gone; GameRoot.load_level has nothing to drive" % EFFECT_PREWARMER_PATH)
	if not FileAccess.file_exists(EFFECT_PREWARMER_PATH):
		return
	var src := FileAccess.get_file_as_string(EFFECT_PREWARMER_PATH)
	assert_true(src.contains("class_name EffectPrewarmer"),
			"effect_prewarmer.gd must declare class_name EffectPrewarmer — GameRoot.load_level and these tests reach it by that name")
	assert_true(src.contains("const WARM_PATHS"),
			"effect_prewarmer.gd must declare const WARM_PATHS (the res:// scene list warmed in-level) — a private/renamed list would let every ratchet below pass while warming something else")
	assert_true(src.contains("func warm("),
			"effect_prewarmer.gd must expose func warm(camera: Camera3D) — the entry point load_level calls once the level and the live camera are in the tree")
	assert_gt(_warm_paths.size(), 0,
			"EffectPrewarmer.WARM_PATHS is empty (or not an Array) — the in-level warm draws nothing, so every combat spawnable first-compiles its pipelines mid-fight again")


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
			"EffectPrewarmer.WARM_PATHS is empty (or the script is missing) — nothing to check on disk; see test_prewarmer_declares_the_contract_surface")
	for path in _warm_paths:
		assert_true(String(path).begins_with("res://") and String(path).ends_with(".tscn"),
				"EffectPrewarmer.WARM_PATHS entry '%s' is not a res://...tscn path — the list holds authored scene paths (not uid:// or scripts) so it stays human-readable and scannable" % path)
		assert_true(FileAccess.file_exists(String(path)),
				"EffectPrewarmer.WARM_PATHS entry '%s' does not exist on disk — fix the path in scripts/components/effect_prewarmer.gd (the prewarmer skips a missing entry with only a warning, so its pipelines would first-compile mid-combat again)" % path)


func test_damage_number_show_routes_through_build_label() -> void:
	# Ratchet (d): the warm must draw the SAME Label3D gameplay builds (font size, outline, billboard,
	# no_depth_test, render_priority all shape the material) — so the construction lives in one static.
	var src := FileAccess.get_file_as_string(DAMAGE_NUMBER_PATH)
	assert_true(src.contains("static func build_label("),
			"damage_number_popup.gd must expose static func build_label(...) — the one builder both DamageNumberPopup.show and the in-level prewarm construct the damage-number Label3D through")
	var body := _func_body(src, "static func show(")
	assert_true(body != "",
			"damage_number_popup.gd no longer has static func show( — if the damage-number spawn moved/renamed, repoint this pin: its Label3D STILL needs to be built by build_label so the warm matches it")
	assert_true(body.contains("build_label("),
			"DamageNumberPopup.show must construct its Label3D via build_label( — an inline Label3D.new() here would ship a label the prewarm never drew (a different material variant = a first-hit pipeline compile again)")


func test_bark_icon_routes_through_build_icon() -> void:
	# Same contract for the NPC alert "!" / turn-hostile cue: a billboarded, unshaded, no-depth Sprite3D
	# whose material the first bark would otherwise mint mid-combat.
	var src := FileAccess.get_file_as_string(BARK_UI_PATH)
	assert_true(src.contains("static func build_icon("),
			"npc_bark_ui.gd must expose static func build_icon(...) — the one builder both NpcBarkUi.show_icon and the in-level prewarm construct the alert Sprite3D through")
	var body := _func_body(src, "func show_icon(")
	assert_true(body != "",
			"npc_bark_ui.gd no longer has func show_icon( — if the alert-icon popup moved/renamed, repoint this pin: its Sprite3D STILL needs to be built by build_icon so the warm matches it")
	assert_true(body.contains("build_icon("),
			"NpcBarkUi.show_icon must construct its Sprite3D via build_icon( — an inline Sprite3D.new() here would ship an icon the prewarm never drew (a different material variant = a first-alert pipeline compile again)")


func test_load_level_invokes_the_prewarmer_after_ps1_warp() -> void:
	# The warm must run with the level IN the tree and AFTER the PS1 warp has been handed the level root:
	# earlier, the renderer-global requirements (InkOutline prepass, shadow atlases) aren't live yet and the
	# warm would compile the wrong keys; before _apply_ps1_warp, the warm-up instances would be swept into
	# the level's material override pass. Pinned by ORDER inside load_level's body, not by mere presence.
	var src := FileAccess.get_file_as_string(GAME_ROOT_PATH)
	var body := _func_body(src, "func load_level(")
	assert_true(body != "",
			"game_root.gd no longer has func load_level( — the level-load seam moved; repoint this pin, the effect prewarm STILL has to run on every level load (boot, LevelDoor swap, death reload)")
	var warp_at := body.find("_apply_ps1_warp(")
	assert_true(warp_at >= 0,
			"GameRoot.load_level no longer calls _apply_ps1_warp( — the PS1-warp handoff moved; repoint this pin (the prewarm must still run after the level root is in the tree)")
	if warp_at < 0:
		return
	var after_warp := body.substr(warp_at)
	# Pin the CALL text, never a name a comment could satisfy (the source-text-assert-matches-its-own-disclaimer
	# trap in reverse): the invocation is `_prewarm_effects()`, and its body must be the thing that reaches the
	# EffectPrewarmer script — deleting the call while keeping load_level's prose must turn this red.
	assert_true(after_warp.contains("_prewarm_effects("),
			"GameRoot.load_level must CALL _prewarm_effects( AFTER its _apply_ps1_warp(inst) call — none found in that stretch of the body, so no level load warms the combat effects and the first kill hitches again")
	var helper := _func_body(src, "func _prewarm_effects(")
	assert_true(helper != "",
			"game_root.gd no longer has func _prewarm_effects( — the in-level warm helper moved; repoint this pin (load_level must still reach the EffectPrewarmer on every level load)")
	assert_true(helper.contains("EFFECT_PREWARMER_SCRIPT_PATH") or helper.contains("EffectPrewarmer"),
			"GameRoot._prewarm_effects must build/reach the EffectPrewarmer (by EFFECT_PREWARMER_SCRIPT_PATH or the class) — a helper that no longer names it warms nothing")


func test_add_xp_queues_its_autosave_instead_of_writing_on_the_kill_frame() -> void:
	# Every credited kill reaches Player.add_xp; a SYNCHRONOUS GameState.autosave(self) there is a profile
	# serialise + disk write on the very frame the gore burst lands. The wallet already coalesces through
	# _queue_autosave() (one deferred end-of-frame write) — XP must ride the same seam.
	var src := FileAccess.get_file_as_string(PLAYER_PATH)
	var body := _func_body(src, "func add_xp(")
	assert_true(body != "",
			"player.gd no longer has func add_xp( — the XP inflow moved; repoint this pin, its autosave must STILL be the deferred/coalesced one")
	assert_true(body.contains("_queue_autosave()"),
			"Player.add_xp must call _queue_autosave() — the one-frame-deferred, coalesced flush the wallet and bag already use — so a kill produces ONE end-of-frame write instead of a synchronous save on the kill frame")
	# Negative pin on the CALL text, never the bare name `autosave`: add_xp's own doc comment may mention it.
	assert_false(body.contains("GameState.autosave(self)"),
			"Player.add_xp still calls GameState.autosave(self) synchronously — that is a profile serialise + disk write inside the death-freeze frame; route it through _queue_autosave() (the flush calls GameState.autosave for you)")
