class_name PaintProjectile
extends Node3D

## A code-built paint blob: flies forward with a light arc, raycasts its path each frame, and
## splashes a coloured, unlit paint Decal on the first surface it hits. Spawned by Attack for the
## spray-paint weapon and handed the wheel-selected colour. Fully self-contained — no scene needed.

const PAINT_TEXTURE: Texture2D = preload("res://resources/weapons/paint.webp")  ## paint splat (transparent webp)
const PAINT_SIZE: float = 0.5
const PAINT_EMISSION: float = 1.0      ## full-bright so paint never dims in shadow
const PAINT_ALPHA: float = 1.0         ## fully opaque — fresh paint covers what's underneath, no blending
const PAINT_GROW: float = 0.15         ## how much an existing same-colour splat grows when re-hit
const PAINT_MAX_SIZE := Vector3(1.5, 0.9, 1.5)  ## a merged splat won't grow past this
const MERGE_RADIUS_FACTOR: float = 0.3 ## "lands on" = new splat within this fraction of a splat's width
const PAINT_CULL_MASK: int = 1048571   ## all render layers except the gun's (layer 3)
const MAX_PAINT_DECALS: int = 8000     ## global cap; oldest culled past this
const PAINT_GRAVITY: float = 6.0       ## gentle downward arc on the blob (0 = straight shot)
const LIFETIME: float = 4.0            ## free the blob if it never hits anything
const BLOB_RADIUS: float = 0.06
const SPLAT_SOUND: AudioStream = preload("res://assets/audio/528834__magnuswaker__meaty-splosh.wav")  ## swap for a dedicated paint splat
const SPLAT_VOLUME_DB: float = -4.0
const EXPLOSION_AREA: PackedScene = preload("uid://co1ehjy0gbhu3")  ## reused bullet-hit spark, tinted to the paint

var velocity: Vector3
var paint_color: Color = Color.WHITE
var shooter: Node = null

var _life: float = LIFETIME
## Monotonic counter so each new splat sorts on top of older overlapping ones (newest wins).
static var _paint_order: float = 0.0

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
	velocity += Vector3.DOWN * PAINT_GRAVITY * delta

## Project a persistent coloured, unlit Decal onto the surface the blob hit (mirrors the look the
## hitscan version used). Capped globally at MAX_PAINT_DECALS, oldest culled first.
func _splash(pos: Vector3, normal: Vector3, body: Node) -> void:
	# Wet splat at the impact, pitch-varied so a fast spray doesn't sound like one flat tone.
	AudioManager.play_sfx(pos, SPLAT_SOUND, SPLAT_VOLUME_DB, randf_range(0.9, 1.1))
	# Reuse the bullet-impact spark as a coloured paint pop (cosmetic: no force, no damage).
	var burst := EXPLOSION_AREA.instantiate()
	burst.max_explosion_force = 0.0
	burst.deals_damage = false
	burst.explosion_radius = GameSettings.effects.explosion_spark_radius
	burst.tint_color = paint_color
	get_tree().root.add_child(burst)
	burst.position = pos
	# Land on an existing splat of the same colour? Grow that one instead of stacking a new decal.
	for node in get_tree().get_nodes_in_group(&"paint_decal"):
		var existing := node as Decal
		if existing == null:
			continue
		var same_colour = existing.get_meta(&"paint_color", Color.BLACK) == paint_color
		if same_colour and pos.distance_to(existing.global_position) <= existing.size.x * MERGE_RADIUS_FACTOR:
			existing.size = (existing.size + Vector3(PAINT_GROW, PAINT_GROW * 0.6, PAINT_GROW)).min(PAINT_MAX_SIZE)
			existing.sorting_offset = _next_paint_sort()  # the freshly-grown splat comes to the top
			return
	var decal := Decal.new()
	decal.texture_albedo = PAINT_TEXTURE
	decal.texture_emission = PAINT_TEXTURE
	decal.emission_energy = PAINT_EMISSION
	decal.size = Vector3(PAINT_SIZE, PAINT_SIZE * 0.6, PAINT_SIZE)
	decal.cull_mask = PAINT_CULL_MASK
	decal.modulate = Color(paint_color, PAINT_ALPHA)
	decal.set_meta(&"paint_color", paint_color)  # base colour, for same-colour merge checks later
	# Newest splat wins the depth fight — give each a higher sort priority than the last.
	decal.sorting_offset = _next_paint_sort()
	# Parent the decal to whatever it hit so it rides along when that body moves (enemies, props).
	# Falls back to the world root for plain static geometry or anything without a Node3D.
	var parent_node: Node = body if body is Node3D else get_tree().root
	parent_node.add_child(decal)
	# Orient so the decal projects along -Y into the surface (mirrors Character.spawn_blood_decal).
	var up := normal
	var z := (Vector3.FORWARD if absf(up.dot(Vector3.UP)) > 0.99 else Vector3.UP).slide(up).normalized()
	var x := up.cross(z).normalized()
	decal.global_transform = Transform3D(Basis(x, up, z), pos + normal * 0.02)
	decal.add_to_group(&"paint_decal")
	if get_tree().get_node_count_in_group(&"paint_decal") > MAX_PAINT_DECALS:
		var oldest := get_tree().get_first_node_in_group(&"paint_decal")
		if oldest:
			oldest.queue_free()

## sorting_offset reliably supports ~1024 layers — a counter that climbs past that breaks the sort,
## so wrap it. Keeps the newest splat in the engine's working range so it stays on top of recent paint.
func _next_paint_sort() -> float:
	_paint_order += 1.0
	return fmod(_paint_order, 1024.0)
