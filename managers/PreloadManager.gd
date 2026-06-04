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
	"res://scenes/effects/cube.tscn",
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
