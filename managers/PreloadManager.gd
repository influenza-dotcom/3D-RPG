extends Node

## Warms the project's runtime-loaded scenes at startup so the FIRST in-game spawn never hitches.
## Most assets ride compile-time preload() consts (already cached when their owning script loads), but
## a handful are pulled in lazily via load() during gameplay — notably weapon.tscn (npc.gd loads it at
## runtime to dodge a circular resource dependency), plus the EffectFactory hit/blood/dust effects and
## the projectile scenes spawned on the first shot / kill. Touching disk + parsing those mid-combat is
## where the stutter comes from, so we pull them all in here, once, during _ready.
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
	"res://scenes/weapon.tscn",
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
	# Projectile scenes instantiated on the first shot.
	"res://scenes/projectiles/Projectile.tscn",
	"res://scenes/projectiles/rock_projectile.tscn",
	"res://scenes/projectiles/sphere_projectile.tscn",
	"res://scenes/projectiles/bullet_casing.tscn",
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
	# the in-game speech backend installing its voices on the first NPC bark (kills now trigger witness
	# barks), and the custom-shader GPU-particle death effects compiling on first render. Pay both at boot,
	# deferred so the autoloads they reach (SpeechTts) are all up first.
	if DisplayServer.get_name() != "headless":
		call_deferred(&"_prewarm_tts")
		call_deferred(&"_prewarm_gpu_particles")


## Warm the in-game text-to-speech at boot so the FIRST NPC bark — often a kill reaction now — doesn't hitch
## while the backend installs its voices mid-combat. SpeechTts extracts the bundled Flite voices to user:// in
## an exported build (a no-op in the editor). Deferred from _ready so the SpeechTts autoload already exists.
func _prewarm_tts() -> void:
	SpeechTts.prewarm()


## Compile the custom-shader GPU-particle death effects (blood + bloody_mess) once, off-screen, at boot so
## their render pipeline compiles during load instead of hitching on the FIRST kill. Renders them a few
## frames in a throwaway SubViewport with its OWN World3D + camera — no on-screen flash, no gameplay-physics
## contact — then frees it. Skipped on the headless renderer (nothing to compile, no real viewport there).
func _prewarm_gpu_particles() -> void:
	var paths := ["res://scenes/effects/blood.tscn", "res://scenes/effects/bloody_mess.tscn"]
	var vp := SubViewport.new()
	vp.size = Vector2i(16, 16)
	vp.own_world_3d = true  # isolated world: the warm-up particles never touch gameplay physics/lighting
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(vp)
	var cam := Camera3D.new()
	cam.position = Vector3(0.0, 0.0, 3.0)  # looks down -Z at the origin, where the effects sit
	vp.add_child(cam)
	cam.current = true
	for path in paths:
		var ps: PackedScene = load(path)
		if ps == null:
			continue
		var inst := ps.instantiate()
		vp.add_child(inst)
		if inst is GPUParticles3D:
			var p := inst as GPUParticles3D
			p.one_shot = false  # keep emitting across the warm-up frames so the pipeline actually draws
			p.emitting = true
	# A few frames so the particle process + draw pipelines compile and cache globally, then tear down.
	for _frame in 4:
		await get_tree().process_frame
	vp.queue_free()
