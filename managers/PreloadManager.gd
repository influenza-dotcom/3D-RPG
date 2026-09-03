extends Node

## Warms the project's runtime-loaded scenes at startup so the FIRST in-game spawn never hitches.
## Most assets ride compile-time preload() consts (already cached when their owning script loads), but
## a handful are pulled in lazily via load() during gameplay — notably weapon.tscn (npc.gd loads it at
## runtime to dodge a circular resource dependency), plus the EffectFactory hit/blood/dust effects, the gore
## chassis scenes and the projectile scenes spawned on the first shot / kill. Touching disk + parsing those
## mid-combat is where the stutter comes from, so we pull them all in here, once, during _ready.
##
## Godot caches a resource the moment it is load()ed and keeps it cached as long as SOMETHING holds a
## reference — so simply stashing each loaded PackedScene in _cache (an autoload that lives for the whole
## session) is enough to keep it hot. Later load() calls for the same path are then cache hits, no I/O.
##
## Data-driven on purpose: to warm another asset, just add its res:// path to PATHS. Paths (not uid://)
## are used so the list stays human-readable; a typo or deleted file is guarded per-entry and skipped
## with a warning rather than crashing the boot.

## res:// paths warmed at startup. Keep this in sync with the project's runtime load() sites — anything
## NOT covered by a compile-time preload() that gets instantiated during play belongs here.
const PATHS: Array[String] = [
	# Lazily loaded by npc.gd at runtime (const WEAPON_SCENE_PATH) to break a preload cycle.
	"res://scenes/weapons/weapon.tscn",
	# Lazily load()ed by npc.gd when an armed NPC builds its muzzle FX (SMOKE_FX_SCENE_PATH). It is also a
	# GPU-particle scene, so _prewarm_gpu_particles below renders it once at boot to build its pipeline too.
	"res://scenes/effects/muzzle_smoke.tscn",
	# EffectFactory effect / decal scenes — spawned on hits, deaths and impacts.
	"res://scenes/effects/blood.tscn",
	"res://scenes/effects/bloody_mess.tscn",
	"res://scenes/effects/blood_drop.tscn",
	"res://scenes/effects/dust.tscn",
	"res://scenes/effects/dust_large.tscn",
	"res://scenes/effects/explosion_area.tscn",
	"res://scenes/throwable/cube.tscn",
	"res://scenes/decals/blood_splat_decal.tscn",
	"res://scenes/decals/bullet_hole_decal.tscn",
	# The flying-limb chassis is a RUNTIME load() on the FIRST death (BodyPartGibs.default_scene — deliberately
	# not a preload(), to dodge the Throwable<->Character parse cycle), i.e. a disk read + parse inside the
	# death-freeze beat unless it is pinned here.
	"res://scenes/effects/body_part_gib.tscn",
	# The meat chunk + the NPC prefabs' loot-bag "ragdoll": first DRAWN on the first kill. Pinned so the in-level
	# EffectPrewarmer (scripts/components/effect_prewarmer.gd) draws them from a warm cache, and so a level that
	# instances neither owner scene still has them hot.
	"res://scenes/effects/gore_gib.tscn",
	"res://scenes/props/loot_bag.tscn",
	# Projectile scenes instantiated on the first shot.
	"res://scenes/projectiles/Projectile.tscn",
	"res://scenes/projectiles/rock_projectile.tscn",
	"res://scenes/projectiles/sphere_projectile.tscn",
	"res://scenes/projectiles/bullet_casing.tscn",
]

## Every AUTHORED GPU-particle scene in the project — the render-prewarm list for _prewarm_gpu_particles
## below (the one code-built emitter, Throwable's confetti burst, has no scene to list and is warmed there
## via Throwable.build_confetti_burst). Each DISTINCT ParticleProcessMaterial feature set (a colour ramp,
## scale curve, emission shape, turbulence or collision toggle — features that GENERATE shader code, unlike
## plain values) mints its own ParticlesShaderRD pipeline, so every authored emitter is listed even where
## two happen to share a variant today (the dust family currently compiles to the same shader as blood — an
## accident of authoring, not a contract; retuning one feature on one scene would silently mint a new,
## un-warmed pipeline if that scene weren't already here). tests/test_preload_prewarm.gd ratchets this
## list: any scene declaring a GPUParticles3D node (or referenced as a destroy effect) must appear here.
const PARTICLE_WARM_PATHS: Array[String] = [
	"res://scenes/effects/ambient_dust.tscn",
	# Duplicate of ambient_dust (same AmbientDust script builds the material -> same pipeline); warmed
	# anyway so the contract test stays a simple "every particle scene is on the list" ratchet.
	"res://scenes/components/ambient_dust.tscn",
	"res://scenes/effects/blood.tscn",
	"res://scenes/effects/bloody_mess.tscn",
	"res://scenes/effects/dust.tscn",
	"res://scenes/effects/dust_large.tscn",
	"res://scenes/effects/muzzle_smoke.tscn",
	"res://scenes/effects/shell_drop.tscn",
	# Root-instance of dust.tscn with the SparkAttack script + an amount override — same pipeline family
	# as dust today, listed for the same "features could diverge" insurance as the rest of that family.
	"res://scenes/effects/spark_attack.tscn",
]

## res:// path -> the loaded Resource. Holding the ref is what keeps Godot's cache warm; nothing else
## reads this dictionary — its job is purely to own a reference for the lifetime of the session.
var _cache: Dictionary = {}


func _ready() -> void:
	for path in PATHS:
		# Guard each load independently — a single bad/removed path must not abort warming the rest,
		# and a null result (missing or failed-to-parse resource) is skipped rather than cached.
		var res: Resource = load(path)
		if res == null:
			push_warning("PreloadManager: failed to preload '%s' (skipped)" % path)
			continue
		_cache[path] = res
	# Beyond resource I/O, the FIRST kill also pays two ONE-TIME init costs that otherwise hitch mid-combat:
	# the in-game speech backend loading a 6-12 MB voice + initialising its synth on the first NPC bark (a
	# kill's witness barks — and the aggro shout when you are first shot at pays the same), and the
	# GPU-particle process pipelines (death gore, muzzle FX, break dust, confetti) compiling on first render.
	# Pay both at boot, deferred so the autoloads they reach (SpeechTts, Settings) are all up first.
	if DisplayServer.get_name() != "headless":
		call_deferred(&"_prewarm_tts")
		call_deferred(&"_prewarm_gpu_particles")


## Warm the in-game text-to-speech at boot so the FIRST NPC bark — a kill's witness reaction, or the aggro
## shout when you are first shot at — doesn't hitch mid-combat. SpeechTts.prewarm extracts the bundled Flite
## voices to user:// in an exported build (a no-op in the editor), then loads EVERY bundled voice into the
## DLL's process-wide voice cache and runs one throwaway synthesis, so a later pool player's set_voice_path /
## first speak_to_buffer are cache hits. Deferred from _ready so the SpeechTts + Settings autoloads exist.
func _prewarm_tts() -> void:
	SpeechTts.prewarm()


## Compile EVERY GPU-particle PROCESS pipeline that could otherwise compile mid-combat once, off-screen, at
## boot: all the authored emitter scenes (PARTICLE_WARM_PATHS) plus the code-built confetti burst. Renders
## them a few frames in a throwaway SubViewport with its OWN World3D + camera — no on-screen flash, no
## gameplay-physics contact — then frees it. Skipped on the headless renderer (nothing to compile, no real
## viewport there).
##
## DIVISION OF LABOUR with the in-level EffectPrewarmer (scripts/components/effect_prewarmer.gd, invoked
## from GameRoot.load_level): THIS pass runs at boot with no level up and front-loads the ParticlesShaderRD
## compiles — the DXC shader compiles a cold user://shader_cache pays, which no later pass can hide. What it
## CANNOT warm faithfully is the draw side: a lightless 16x16 own-world viewport shares none of the live
## level's render requirements (directional + omni shadow passes, fog, the decal atlas, the 2D / Label3D
## materials), so the per-material PSOs the first kill actually draws with (gibs, loot bag, the death
## splat's shadowed light, the damage number) are minted by EffectPrewarmer under the live renderer
## requirements once a level is loaded. Keep BOTH: dropping this one moves the DXC compiles into
## load_level; dropping that one puts the PSO compiles back on the first-kill frame (measured ~+45 ms over
## a warm repeat, with `surface` / `spec` compiles appearing only in the first-use phase).
##
## ⭐Crash mitigation — the CURRENT, narrower claim (2026-09-01): a FIRST-TIME ParticlesShaderRD compile on
## a Godot WorkerThread inside the NVIDIA D3D12 shader compiler (STATUS_HEAP_CORRUPTION with no Godot crash
## handler — the log simply stops) is a REAL but RARE crash class on this dev machine (an export's first-boot
## mass compile), and warming every particle scene here moves that compile into load, where it happens once
## and stays cached (if the driver bug fires anyway, a boot crash costs one relaunch and no progress). It is
## NOT the explanation for the 08/28-29 playtest crashes: dump forensics proved those were an invalid free
## at QUIT inside the TTS GDExtension (its godot-cpp was built template_debug against a release export
## engine — since rebuilt; addons/text_to_speech/REBUILD_WINDOWS.md). Any NEW GPU-particle effect that can
## first appear mid-combat still belongs in PARTICLE_WARM_PATHS (a code-built one behind a warmable static
## like Throwable.build_confetti_burst) — tests/test_preload_prewarm.gd fails with the exact path to add.
func _prewarm_gpu_particles() -> void:
	var vp := SubViewport.new()
	vp.size = Vector2i(16, 16)
	vp.own_world_3d = true  # isolated world: the warm-up particles never touch gameplay physics/lighting
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(vp)
	var cam := Camera3D.new()
	cam.position = Vector3(0.0, 0.0, 3.0)  # looks down -Z at the origin, where the effects sit
	vp.add_child(cam)
	cam.current = true
	for path in PARTICLE_WARM_PATHS:
		var ps: PackedScene = load(path)
		if ps == null:
			push_warning("PreloadManager: failed to load particle scene '%s' for prewarm (skipped)" % path)
			continue
		# Keep the PackedScene hot too — several of these are runtime load()ed (npc.gd muzzle FX), so
		# parking the ref in _cache spares the first armed NPC the disk read, same as the PATHS list.
		_cache[path] = ps
		var inst := ps.instantiate()
		if inst == null:
			continue  # empty-PackedScene reimport transient -> instantiate() can return null; skip instead of crashing
		vp.add_child(inst)
		if inst is GPUParticles3D:
			var p := inst as GPUParticles3D
			p.one_shot = false  # keep emitting across the warm-up frames so the pipeline actually draws
			p.emitting = true
	# The confetti trick-shot burst is built entirely in CODE (no scene to list) and its color_initial_ramp
	# mints its own ParticlesShaderRD variant — and it first fires seconds after a kill, the worst possible
	# moment for a first-time compile. Build it through the same static the gameplay spawn uses so the
	# warmed material can never drift from the spawned one. load(), not a class_name/preload reference, so
	# this autoload never adds a parse-time edge onto Throwable.gd (the class_name<->preload cycle trap).
	var throwable_script: GDScript = load("res://scripts/components/Throwable.gd")
	if throwable_script != null:
		var defaults: Object = throwable_script.new()  # off-tree: just the export defaults, _ready never runs
		var confetti: GPUParticles3D = throwable_script.build_confetti_burst(
				defaults.confetti_amount, defaults.confetti_lifetime,
				defaults.confetti_velocity_min, defaults.confetti_velocity_max,
				defaults.confetti_scale_min, defaults.confetti_scale_max)
		defaults.free()
		vp.add_child(confetti)
		confetti.one_shot = false  # same warm-up override as the scene emitters above
		confetti.emitting = true
	# Hold while the particle process + draw pipelines compile and cache globally, then tear down.
	# 8 frames (was 4 when this warmed 3 scenes): a first-time D3D12 compile can span several frames, and
	# tearing down early would warm only the variants the driver got to — still invisible, still boot-time.
	for _frame in 8:
		await get_tree().process_frame
	vp.queue_free()
