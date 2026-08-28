class_name Ragdoll
extends Node3D

# The old ~15-segment authored NodePath into the skeleton GLB silently resolved to null on any re-import
# or re-rig (the _fbx hash / bone names shift), and _process then crashed on the null deref. Find the first
# OmniLight3D under the ragdoll root instead — same NodeFinder idiom the skeleton lookup uses (_find_skeleton).
@onready var corpse_light: OmniLight3D = NodeFinder.find_first_of_class(self, OmniLight3D) as OmniLight3D

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

@export_group("Lifetime & Fade")
## Seconds the corpse lingers before it's freed.
@export var lifetime: float = 15.0
## Seconds spent fading the corpse out (mesh transparency 0 -> 1) at the end of its lifetime before free.
@export var fade_time: float = 1.5
## Corpse fade-out rate — higher fades faster.
@export var fade_speed: float = 3.0

@export_group("Outline")
## Outline the corpse — the same screen-space ring the living NPCs and every prop carry, so a dropped
## skeleton keeps that look instead of falling back to the world ink's scribbly per-crease treatment.
## It paints InkOutline.highlight_neutral (black) at InkOutline.highlight_width_px, exactly like a
## neutral bystander; there is no per-corpse colour or width, because a ring resolves one id to one
## global LUT slot (the `outline_color` / `outline_width` exports here went with the inverted hull on
## 2026-08-27). Off leaves the corpse to the world ink.
##
## ⭐ A corpse is the project's one SKINNED ringed thing — InkOutline.apply_tint mirrors `skin` and
## re-points `skeleton` onto the duplicate so the ring follows the ragdoll pose. That plumbing exists
## because of this component; before it, apply_tint skipped skinned meshes outright.
@export var outline: bool = true

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
	if corpse_light == null:
		return  # scene drift: no OmniLight3D found — skip the fade-out dimming rather than crash
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

	# Corpse cleanup. A corpse that still holds loot — items OR the wallet (can_be_talked_to covers both) —
	# LINGERS until the player drains it, then fades; one carrying nothing fades after the normal lifetime
	# so bodies don't pile up. The wallet take nudges the same changed signal (LootableCorpse.on_wallet_
	# drained), so a cash-only corpse still gets its fade.
	if is_instance_valid(loot) and loot.can_be_talked_to():
		if loot.inventory != null:
			loot.inventory.changed.connect(_on_loot_changed)
	else:
		await get_tree().create_timer(lifetime).timeout
		_fade_and_free()

## Looted dry: the last item (or the wallet) was just taken, so the lingering corpse fades + frees as normal.
func _on_loot_changed() -> void:
	if is_instance_valid(loot) and not loot.can_be_talked_to():
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
	# ⭐ The RING goes at the top of the dissolve rather than fading with it. GeometryInstance3D.transparency
	# is a per-instance fade of the corpse's own materials; the tint duplicate wears the shared ID material,
	# whose alpha channel is COVERAGE, not opacity (see InkOutline.set_tint_visible). Dropping it here is the
	# same trade BodyModelSwap makes for the dissolving first-person torso: an outline that outlives the body
	# it wraps reads far worse than one that leaves a beat early.
	InkOutline.clear_tint(self)
	var tw := create_tween().set_parallel(true)
	for m in meshes:
		tw.tween_property(m, "transparency", 1.0, fade_time)
	tw.chain().tween_callback(queue_free)

## First Skeleton3D at or under `node` (the imported model nests it a couple levels down).
func _find_skeleton(node: Node) -> Skeleton3D:
	return NodeFinder.find_first_of_class(node, Skeleton3D) as Skeleton3D

## Outline every mesh in the corpse with InkOutline's screen-space ring, and — inseparably — register those
## meshes with the actor mask so the world's ink pass skips them. The two are one contract everywhere in this
## project: ring without the mask draws two lines, mask without the ring draws none.
##
## ⭐ The mask half is NEW here (2026-08-27). Under the inverted hull this component never stamped
## ACTOR_INK_MASK_LAYER at all, so a corpse quietly wore BOTH its own rim and the world's ink and nobody
## noticed — which is also why deleting the hull would have degraded a corpse to world-ink-only rather than to
## nothing, the easiest kind of regression to miss.
func _apply_outline() -> void:
	for m in TalkHelpers.collect_meshes(self):
		# Corpses don't need to cast shadows, and skipping the shadow pass dodges the "material is null"
		# render spam from any skeleton surface that imported without a base material.
		m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		if outline:
			m.layers |= InkOutline.ACTOR_INK_MASK_LAYER
			InkOutline.apply_tint_mesh(m, InkOutline.TINT_ID_NEUTRAL)
		else:
			m.layers &= ~InkOutline.ACTOR_INK_MASK_LAYER
