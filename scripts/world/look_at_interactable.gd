class_name LookAtInteractable
extends Area3D

## Shared base for the look-at INTERACTABLE world components (ItemContainer, CanPickUp, Merchant,
## LootableCorpse): the talk-layer hitbox + the white look-at outline, so each component writes only its OWN
## behaviour (start_talk / can_be_talked_to / look_name). PickupRay DUCK-TYPES this talk-handler surface, so
## every method here keeps the exact name + signature it relies on. Reuses TalkHelpers verbatim.
##
## A subclass needing extra _ready work (seed an inventory, add a custom collision shape) OVERRIDES _ready
## and calls super() first; Merchant sets its own collision_layer (it has a data-only mode) and then calls
## _build_outline() instead of super().

## Node whose MeshInstance3D descendants get the look-at outline on hover. Null -> our parent.
@export var highlight_target: Node3D
@export var highlight_color: Color = Color(1.0, 1.0, 1.0, 1.0)
@export var highlight_width: float = 1.0
## OPT-IN: at runtime, fit our look-at hitbox (a BoxShape3D CollisionShape3D, created if absent) to the host
## meshes' combined bounds — so you don't hand-size a collider per placement. OFF by default, so existing
## hand-sized colliders are never touched. (An in-editor live preview would need @tool; this is the safe
## runtime version — the gameplay hitbox is correct even though the editor still shows the authored shape.)
@export var auto_fit_collider: bool = false

var _outline_mat: ShaderMaterial
var _meshes: Array[MeshInstance3D] = []

## Become a look-at hitbox on the talk layer (so the interaction ray can hit us; we sense nothing), then
## build the outline over the host's meshes.
func _ready() -> void:
	collision_layer = TalkHelpers.TALK_LAYER
	collision_mask = 0
	_build_outline()
	if auto_fit_collider:
		_fit_hitbox_to_host()

## (Re)build the outline material + collect the host's meshes. Split out so a subclass can call it after it
## sets its own collision layer (Merchant) rather than going through _ready's default.
func _build_outline() -> void:
	_outline_mat = TalkHelpers.make_outline_material(highlight_color, highlight_width)
	var host := _host()
	if host != null:
		_meshes = TalkHelpers.collect_meshes(host, self)

## Fit our look-at hitbox to the host's visual bounds (opt-in via auto_fit_collider): size a BoxShape3D
## CollisionShape3D — created if absent — to the host meshes' combined AABB in our local space, so you don't
## hand-size a collider per placement. No-op with no meshes. Runtime only (the editor shows the authored shape).
func _fit_hitbox_to_host() -> void:
	var combined := AABB()
	var have := false
	for m in _meshes:
		if m == null or m.mesh == null:
			continue
		var to_local := global_transform.affine_inverse() * m.global_transform
		var local_aabb := to_local * m.mesh.get_aabb()
		combined = local_aabb if not have else combined.merge(local_aabb)
		have = true
	if not have:
		return
	var cs := _hitbox_shape()
	var box := BoxShape3D.new()
	box.size = combined.size
	cs.shape = box
	cs.position = combined.position + combined.size * 0.5

## Our CollisionShape3D child (the look-at hitbox), creating an empty one if none exists yet.
func _hitbox_shape() -> CollisionShape3D:
	for c in get_children():
		if c is CollisionShape3D:
			return c as CollisionShape3D
	var cs := CollisionShape3D.new()
	add_child(cs)
	return cs

## The node this component represents (outline target): the configured target, else our parent.
func _host() -> Node3D:
	if highlight_target != null:
		return highlight_target
	return get_parent() as Node3D

## Look-at highlight toggle — outlines the host's meshes.
func set_look_highlight(on: bool) -> void:
	TalkHelpers.set_overlay(_meshes, _outline_mat if on else null)

## No NPC behind a world interactable (so the FNV hover won't greet/tint it; player.gd null-guards this).
## Typed Node (not NPC) on purpose: LootableCorpse extends this and NPC creates LootableCorpse, so an NPC
## return type would form an NPC <-> LookAtInteractable class-reference loop. The value is always null here.
func host_npc() -> Node:
	return null

# --- Behaviour: subclasses override these (the rest of the duck-typed talk-handler surface) ---

## Interact pressed while aimed at us. Override per component (open loot / pick up / open shop).
func start_talk(_player: Node) -> void:
	pass

## Whether we can be interacted with right now. Override if conditional (e.g. only while non-empty).
func can_be_talked_to() -> bool:
	return true

## Hover readout label. Override per component.
func look_name() -> String:
	return "Interact"
