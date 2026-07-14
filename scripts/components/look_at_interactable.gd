class_name LookAtInteractable
extends Area3D

## @system Interaction
## @seam Owns the duck-typed talk-handler surface (start_talk/can_be_talked_to/look_name/host_npc/set_look_highlight) + TALK_LAYER hitbox + outline that PickupRay resolves and calls by name, so every interactable subclass plugs into the ray unchanged.
## @risk Rename or re-signature a talk-handler method (start_talk/can_be_talked_to/look_name/set_look_highlight): PickupRay's has_method calls silently no-op, so the subclass stops interacting/highlighting with no error or failing call-site test.
## @risk A subclass overrides _ready without super() or without setting collision_layer=TALK_LAYER (Merchant-style): the talk ray never hits the hitbox (base _ready:40 is the only thing joining the talk layer) and the object is silently un-interactable.
## @test res://tests/test_look_at_interactable.gd
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
## Colour of the look-at outline drawn over the host on hover. Default white.
@export var highlight_color: Color = Color(1.0, 1.0, 1.0, 1.0)
## Thickness of that look-at outline (shader units). Higher = bolder outline.
@export var highlight_width: float = 1.0
## OPT-IN: fit our look-at hitbox (a BoxShape3D CollisionShape3D) to the host meshes' combined bounds, so you
## don't hand-size a collider per placement. OFF by default, so a hand-sized collider is never touched. At
## runtime the shape is created if absent; for a @tool interactable it ALSO previews IN-EDITOR — resizing an
## EXISTING CollisionShape3D to the host bounds when the scene opens (persists on save). The editor preview only
## resizes a collider you already authored (it won't add one), so a bare node shows nothing until you add a shape.
@export var auto_fit_collider: bool = false

var _outline_mat: ShaderMaterial
var _meshes: Array[MeshInstance3D] = []

## Become a look-at hitbox on the talk layer (so the interaction ray can hit us; we sense nothing), then
## build the outline over the host's meshes.
func _ready() -> void:
	# @tool base guard (XC1): a @tool SUBCLASS that does NOT override _ready (switch_lever / readable) runs THIS in the
	# editor. Preview the auto-fit hitbox, then bail before any runtime wiring (talk-layer, outline, host-mesh collect).
	# Subclasses with their OWN pre-super runtime work (container / can_pick_up / upgrade_pickup) keep a self-guard and
	# never reach here in-editor (they return before super()). LookAtInteractable itself isn't @tool, so a bare instance
	# never runs this branch — it only fires for @tool leaves that inherit this method.
	if Engine.is_editor_hint():
		_editor_fit_hitbox()
		return
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
		var _to_local := global_transform.affine_inverse() * m.global_transform
		var local_aabb := _to_local * m.mesh.get_aabb()
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

## In-editor preview of the auto-fit hitbox, called from a @tool subclass's _ready editor branch. Resizes an
## EXISTING CollisionShape3D's box to the host meshes' bounds (persists on save), mirroring _fit_hitbox_to_host
## but WITHOUT creating a collider — an add_child'd node in-editor would be transient (unowned, unsaved). Writes
## a FRESH BoxShape3D so a shared shape resource is never mutated. No-op if auto_fit is off, no collider is
## authored, or there are no host meshes.
func _editor_fit_hitbox() -> void:
	if not auto_fit_collider:
		return
	_build_outline()  # collect the host meshes into _meshes
	var cs: CollisionShape3D = null
	for c in get_children():
		if c is CollisionShape3D:
			cs = c as CollisionShape3D
			break
	if cs == null:
		return
	var combined := AABB()
	var have := false
	for m in _meshes:
		if m == null or m.mesh == null:
			continue
		var _to_local := global_transform.affine_inverse() * m.global_transform
		var local_aabb := _to_local * m.mesh.get_aabb()
		combined = local_aabb if not have else combined.merge(local_aabb)
		have = true
	if not have:
		return
	var target_pos := combined.position + combined.size * 0.5
	var cur := cs.shape as BoxShape3D
	if cur != null and cur.size.is_equal_approx(combined.size) and cs.position.is_equal_approx(target_pos):
		return  # already fitted -> don't rewrite the shape (a fresh resource each open would mark the scene dirty)
	var box := BoxShape3D.new()
	box.size = combined.size
	cs.shape = box
	cs.position = target_pos

## The node this component represents (outline target): the configured target, else our parent.
func _host() -> Node3D:
	if highlight_target != null:
		return highlight_target
	return get_parent() as Node3D

## True when this interactable is a CHILD of a dialogue NPC (parent is a DialogueNPC, or a sibling is a
## Talkable). The dual-mode stations' config warning uses it: a standalone station on a dialogue NPC steals
## the interaction ray from the NPC's Talkable. Edit-time safe (get_parent / get_children / `is` checks).
func _on_dialogue_host() -> bool:
	var p := get_parent()
	if p == null:
		return false
	if p is DialogueNPC:
		return true
	for sib in p.get_children():
		if sib != self and sib is Talkable:
			return true
	return false

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
