class_name Ragdoll
extends Node3D

@onready var corpse_light: OmniLight3D = $"Sketchfab_Scene/Sketchfab_model/root/GLTF_SceneRootNode/Sketchfab_model_0/bdd64caeeafd42c4825df715cd846b8e_fbx_1/Object_2_2/RootNode_3/full_skeleton_controler_6/pan_controler_7/Object_8_8/GLTF_created_0/Skeleton3D/PhysicalBoneSimulator3D/Physical Bone GLTF_created_0_rootJoint/OmniLight3D"

## Drives a rigged-skeleton corpse: on spawn it starts the physical-bone simulation so the model
## goes limp, launches it in the direction of the killing blow, and removes it after a while so
## corpses don't pile up forever.
##
## SETUP (one-time, in the editor — physical bones can't be authored from code):
##   1. In the FileSystem dock, right-click lowpoly_human_skeleton_rigged.glb -> New Inherited Scene.
##   2. Select the Skeleton3D node; in the toolbar's "Skeleton3D" menu choose "Create Physical
##      Skeleton" (adds a PhysicalBoneSimulator3D with a PhysicalBone3D + capsule per bone).
##   3. Stand the model upright / facing forward if it imported rotated (rotate the model node), so
##      it doesn't spawn lying on its side.
##   4. Attach THIS script to the scene's root node and save it as
##      res://scenes/effects/skeleton_ragdoll.tscn.
##   5. Assign that scene to the enemy's `ragdoll_scene` (Character export).
## Tune the physical bones' collision layer/mask so the corpse hits the floor but not the player.

## Seconds the corpse lingers before it's freed.
@export var lifetime: float = 15.0
## Seconds spent fading the corpse out (mesh transparency 0 -> 1) at the end of its lifetime before free.
@export var fade_time: float = 1.5

## Rim outline drawn on the corpse's meshes — the same effect the living NPCs and weapons carry, so a
## dropped skeleton keeps that look. Black + a thin width matches the combat rim; tweak per scene.
@export var outline_color: Color = Color.BLACK
@export var outline_width: float = 0.085

## World-space impulse the corpse launches with — set by the spawner right before it's added to the
## tree (so it's already set when _ready starts the simulation).
var launch: Vector3 = Vector3.ZERO

## The lootable corpse component GoreSpawner attached, holding a COPY of the dead actor's backpack. While
## it still holds items the corpse does NOT fade on the normal lifetime — it lingers until the player
## loots it empty, then fades as normal. Null when the actor carried nothing. Set before add_child.
var loot: LootableCorpse = null
## Latched once the fade-out begins so the loot-changed signal can't kick off a second fade/free.
var _fading := false

func _process(delta: float) -> void:
	if !_fading:
		return
	var fade_speed := 3.0   # adjust this to taste
	var t := 1.0 - exp(-fade_speed * delta)
	corpse_light.omni_range = lerpf(corpse_light.omni_range, 0.0, t)

func _ready() -> void:
	_apply_outline()
	# Stop any imported animation first — otherwise it keeps posing the skeleton and the ragdoll
	# reads as "frozen" (the animation fights the physics).
	for ap in find_children("*", "AnimationPlayer", true, false):
		(ap as AnimationPlayer).stop()

	# Let the freshly-spawned bones register with the physics server before we drive them — calling
	# start_simulation the same frame they're added can no-op and leave the corpse frozen.
	await get_tree().physics_frame

	# Start the simulation + collect the physical bones. Godot 4.4+ nests the bones under a
	# PhysicalBoneSimulator3D (which owns start_simulation); older setups hang them off the Skeleton3D.
	var bones: Array = []
	var sims := find_children("*", "PhysicalBoneSimulator3D", true, false)
	if not sims.is_empty():
		sims[0].physical_bones_start_simulation()
		bones = sims[0].find_children("*", "PhysicalBone3D", true, false)
	else:
		var skel := _find_skeleton(self)
		if skel == null:
			push_warning("Ragdoll: no PhysicalBoneSimulator3D or Skeleton3D found — run 'Create Physical Skeleton' on the model's Skeleton3D in the ragdoll scene.")
			return
		skel.physical_bones_start_simulation()
		bones = skel.find_children("*", "PhysicalBone3D", true, false)

	if bones.is_empty():
		push_warning("Ragdoll: started simulation but found 0 PhysicalBone3D nodes — the skeleton has no physical bones, so it can't ragdoll.")
	else:
		# Always shove the bones so the corpse actually starts moving: a clean shot leaves launch
		# ~zero and a just-simulated bone with no initial velocity can sit frozen; a blast's big
		# launch dominates when it's there.
		var impulse := launch
		if impulse.length() < 3.0:
			impulse += Vector3(randf_range(-2.0, 2.0), 3.0, randf_range(-2.0, 2.0))
		for b in bones:
			# Per-bone jitter ON TOP of the shared launch: each bone gets pulled a slightly different
			# way, so the limbs flail and the corpse crumples out of its stiff bind/T-pose right away
			# instead of falling as a rigid mannequin holding the pose.
			var jitter := Vector3(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)) * 2.5
			(b as PhysicalBone3D).apply_central_impulse(impulse + jitter)

	# Corpse cleanup. A corpse that still holds loot LINGERS until the player empties it, then fades; an
	# empty corpse (or one carrying nothing) fades after the normal lifetime so bodies don't pile up.
	if loot != null and loot.inventory != null and not loot.inventory.is_empty():
		loot.inventory.changed.connect(_on_loot_changed)
	else:
		await get_tree().create_timer(lifetime).timeout
		_fade_and_free()

## Looted empty: the last item was just taken, so the lingering corpse now fades + frees as normal.
func _on_loot_changed() -> void:
	if loot != null and loot.inventory != null and loot.inventory.is_empty():
		_fade_and_free()

## Fade the corpse out (every mesh's per-instance transparency 0 -> 1) over fade_time, then free it — so
## it dissolves away instead of popping out. Frees immediately if there are somehow no meshes to fade.
## Idempotent: the _fading latch stops a second loot-changed tick from starting another fade.
func _fade_and_free() -> void:
	if _fading:
		return
	_fading = true
	var meshes := TalkHelpers.collect_meshes(self)
	if meshes.is_empty():
		queue_free()
		return
	var tw := create_tween().set_parallel(true)
	for m in meshes:
		tw.tween_property(m, "transparency", 1.0, fade_time)
	tw.chain().tween_callback(queue_free)

## First Skeleton3D at or under `node` (the imported model nests it a couple levels down).
func _find_skeleton(node: Node) -> Skeleton3D:
	if node is Skeleton3D:
		return node as Skeleton3D
	for c in node.get_children():
		var found := _find_skeleton(c)
		if found != null:
			return found
	return null

## Draw the rim outline on every mesh in the corpse, reusing the shared builder so the dropped
## skeleton carries the same rim the living NPCs (and weapons) do. Applied as a material_overlay,
## which follows the skinned ragdoll pose.
func _apply_outline() -> void:
	var mat := TalkHelpers.make_outline_material(outline_color, outline_width)
	for m in TalkHelpers.collect_meshes(self):
		m.material_overlay = mat
		# Corpses don't need to cast shadows, and skipping the shadow pass dodges the "material is null"
		# render spam from any skeleton surface that imported without a base material.
		m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
