class_name PaintProjectile
extends Node3D

## A code-built paint blob: flies forward with a light arc, raycasts its path each frame, and
## splashes a coloured, unlit paint Decal on the first surface it hits. Spawned by Attack for the
## spray-paint weapon and handed the wheel-selected colour. Fully self-contained — no scene needed.

const PAINT_TEXTURE: Texture2D = preload("uid://cqurw22t40nt6")
const PAINT_SIZE: float = 0.5
const PAINT_EMISSION: float = 1.0      ## full-bright so paint never dims in shadow
const PAINT_ALPHA: float = 1.0         ## fully opaque — fresh paint covers what's underneath, no blending
const PAINT_CULL_MASK: int = 1048571   ## all render layers except the gun's (layer 3)
const BLOB_RADIUS: float = 0.06
const SPLAT_SOUND: AudioStream = preload("uid://doeoaglvink2m")
const EXPLOSION_AREA: PackedScene = preload("uid://co1ehjy0gbhu3")  ## reused bullet-hit spark, tinted to the paint

## A fresh splat destroys + replaces any paint within this radius (× the splat width) — raise to make paint clump/merge more aggressively, lower for tighter tagging.
@export var overlap_factor: float = 0.3
## Global cap on simultaneously-live paint decals; the oldest is culled once a new splat pushes past this. Raise for a more paint-covered world (more decals = more cost).
@export var max_paint_decals: int = 8000
## Gentle downward arc applied to the blob each frame (m/s²): 0 = a dead-straight shot, higher = a lobbed paint toss.
@export var paint_gravity: float = 6.0
## Seconds the blob flies before it self-frees if it never hits anything — its max range/airtime.
@export var lifetime: float = 4.0
## Volume (dB) of the wet-splat impact SFX — sits the paint pop under or over the rest of the mix.
@export var splat_volume_db: float = -4.0

var velocity: Vector3
var paint_color: Color = Color.WHITE
var shooter: Node = null

var _life: float = lifetime

func _ready() -> void:
	# Small unshaded sphere so the blob reads as its paint colour in flight, regardless of lighting.
	var mesh := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = BLOB_RADIUS
	sphere.height = BLOB_RADIUS * 2.0
	mesh.mesh = sphere
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = paint_color
	mesh.material_override = mat
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mesh)

func _physics_process(delta: float) -> void:
	_life -= delta
	if _life <= 0.0:
		queue_free()
		return
	# Raycast the full step so a fast blob can't tunnel through a thin wall.
	var from := global_position
	var to := from + velocity * delta
	var query := PhysicsRayQueryParameters3D.create(from, to)
	if shooter and shooter.has_method("get_rid"):
		query.exclude = [shooter.get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if hit:
		_splash(hit.position, hit.normal, hit.get("collider"))
		queue_free()
		return
	global_position = to
	velocity += Vector3.DOWN * paint_gravity * delta

## Project a persistent coloured, unlit Decal onto the surface the blob hit (mirrors the look the
## hitscan version used). Capped globally at max_paint_decals, oldest culled first.
func _splash(pos: Vector3, normal: Vector3, body: Node) -> void:
	# Wet splat at the impact, pitch-varied so a fast spray doesn't sound like one flat tone.
	AudioManager.play_sfx(pos, SPLAT_SOUND, splat_volume_db, randf_range(0.9, 1.1))
	# Reuse the bullet-impact spark as a coloured paint pop (cosmetic: no force, no damage).
	var burst := EXPLOSION_AREA.instantiate()
	burst.max_explosion_force = 0.0
	burst.deals_damage = false
	burst.explosion_radius = GameSettings.effects.explosion_spark_radius
	burst.tint_color = paint_color
	get_tree().root.add_child(burst)
	burst.position = pos
	# A fresh splat replaces any paint it lands on: destroy the decals it overlaps, then drop the new
	# one on the bare surface. Newest wins — no growing, no decal-sort guesswork.
	var covered: Array[Decal] = []
	for node in get_tree().get_nodes_in_group(&"paint_decal"):
		var existing := node as Decal
		if existing == null:
			continue
		if pos.distance_to(existing.global_position) < existing.size.x * overlap_factor:
			covered.append(existing)  # overlapping paint — destroy it and replace
	for d in covered:
		d.queue_free()
	var decal := Decal.new()
	decal.texture_albedo = PAINT_TEXTURE
	decal.texture_emission = PAINT_TEXTURE
	decal.emission_energy = PAINT_EMISSION
	decal.size = Vector3(PAINT_SIZE, PAINT_SIZE * 0.6, PAINT_SIZE)
	decal.cull_mask = PAINT_CULL_MASK
	decal.modulate = Color(paint_color, PAINT_ALPHA)
	decal.set_meta(&"paint_color", paint_color)  # base colour, for overlap + merge checks later
	# Parent the decal to whatever it hit so it rides along when that body moves (enemies, props).
	# Falls back to the world root for plain static geometry or anything without a Node3D.
	var parent_node: Node = body if body is Node3D else get_tree().root
	parent_node.add_child(decal)
	# Orient so the decal projects along -Y into the surface (mirrors Character.spawn_blood_decal).
	var up := normal
	var z := (Vector3.FORWARD if absf(up.dot(Vector3.UP)) > 0.99 else Vector3.UP).slide(up).normalized()
	var x := up.cross(z).normalized()
	# Spin each splat a random amount around the surface normal so they don't all face the same way.
	var _basis := Basis(x, up, z).rotated(up, randf() * TAU)
	decal.global_transform = Transform3D(_basis, pos + normal * 0.02)
	decal.add_to_group(&"paint_decal")
	if get_tree().get_node_count_in_group(&"paint_decal") > max_paint_decals:
		var oldest := get_tree().get_first_node_in_group(&"paint_decal")
		if oldest:
			oldest.queue_free()
