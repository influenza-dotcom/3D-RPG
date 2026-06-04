class_name GunVisuals
extends Node3D

## The view-model's LOOK pass — built in code (no .tscn) and owned by GunMesh. Split off so the gun-mesh
## root stays a thin coordinator: this child owns the rim-light + black inverted-hull outline materials
## (and the rim/outline tuning exports + shader), and the recursive walks that stamp shadows-off, the rim
## light, and the outline onto a gun subtree. The root just calls dress(target) — once on itself from
## _ready, then on each swapped-in weapon model.
##
## Host-coupled: GunMesh builds it in _ready and sets `host` right after .new(); this child needs the host
## only as the Node3D whose `layers` every submesh is forced onto (so projected world decals — keyed to a
## cull_mask that excludes the gun's render layer — never land on the weapon). Off-tree (a unit-test GunMesh
## built via .new() with no add_child) this child never exists, so GunMesh's _ready never runs and never
## dresses anything — matching the monolith, where _ready (and the deferred view-model equip) never ran
## either.

const RIM_LIGHT_SHADER = preload("res://resources/shaders/rim_light.gdshader")

@export_group("Rim Light")
@export var rim_color: Color = Color(0.95, 0.88, 0.75)
@export var rim_power: float = 5.0
@export var rim_strength: float = 0.5
@export var rim_top_bias: float = 0.35

@export_group("Outline")
## Black inverted-hull outline on the view model (same shader the NPCs/ragdoll use). The gun
## sits much closer to the camera than an NPC, so the clip-space inflation reads large — tune
## this DOWN from the NPC's 0.085 until the rim looks right in-game.
@export var outline_color: Color = Color.BLACK
@export var outline_width: float = 0.02
## MeshInstance3D name substrings (case-insensitive) to SKIP when applying the outline — for a modeled
## laser sight / dot baked into a gun model that should read as a see-through emitter, not an outlined
## prop. If your gun's laser sight still gets outlined, add its exact node name to this list.
@export var outline_skip_name_hints: PackedStringArray = ["laser", "sight", "beam"]

## The GunMesh this dresses — set right after .new() in GunMesh._ready. READ-only here (we only force the
## submeshes onto host.layers); the canonical state stays on the host.
var host: GunMesh

var _rim_material: ShaderMaterial
var _outline_material: ShaderMaterial  ## black inverted-hull outline, shared across every gun submesh

## Build the shared rim-light + outline materials once, the moment this child enters the tree (before
## GunMesh._ready calls dress). The monolith built them in its own _ready (_setup_rim_light / _setup_outline)
## before applying; keeping the build here means dress() only ever APPLIES, so the rim/outline look never
## drifts between the rig and a swapped weapon model.
func _ready() -> void:
	_rim_material = ShaderMaterial.new()
	_rim_material.shader = RIM_LIGHT_SHADER
	_rim_material.set_shader_parameter("rim_color", rim_color)
	_rim_material.set_shader_parameter("rim_power", rim_power)
	_rim_material.set_shader_parameter("rim_strength", rim_strength)
	_rim_material.set_shader_parameter("top_bias", rim_top_bias)
	# The SAME shared builder the NPCs and the ragdoll use (TalkHelpers.make_outline_material), so the look
	# never drifts. It rides material_overlay (a free slot here; the rim light lives on the surface overrides'
	# next_pass, so the two don't clash) and therefore draws on the gun's own render layer / camera with the
	# mesh.
	_outline_material = TalkHelpers.make_outline_material(outline_color, outline_width)

## Stamp the full look onto `target` — shadows off, rim light chained onto every surface, black outline on
## every body mesh — in the SAME order the monolith ran it (shadows -> rim -> outline), both for the rig
## (dressed on itself from _ready) and for each swapped-in weapon model.
func dress(target: Node3D) -> void:
	if target == null:
		return
	_disable_shadows_recursive(target)
	_apply_rim_recursive(target)
	_apply_outline_recursive(target)

func _disable_shadows_recursive(node: Node) -> void:
	if node is MeshInstance3D:
		var mi := node as MeshInstance3D
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		# Force every gun mesh onto the gun's render layer (which world decals
		# exclude via cull_mask) so projected decals — e.g. the player's blob
		# shadow when crouching lowers the gun near the floor — don't land on the
		# weapon. The imported model's submeshes default to layer 1 otherwise.
		mi.layers = host.layers
	for child in node.get_children():
		_disable_shadows_recursive(child)

func _apply_rim_recursive(node: Node) -> int:
	var n := 0
	if node is MeshInstance3D:
		n += _chain_rim_on_mesh(node as MeshInstance3D)
	for child in node.get_children():
		n += _apply_rim_recursive(child)
	return n

func _chain_rim_on_mesh(mi: MeshInstance3D) -> int:
	if not mi.mesh or not _rim_material:
		return 0
	var applied := 0
	for surface_idx in mi.mesh.get_surface_count():
		var base: Material = mi.get_surface_override_material(surface_idx)
		if not base:
			base = mi.mesh.surface_get_material(surface_idx)
		if not base and mi.material_override:
			base = mi.material_override
		var chained: Material
		if base:
			chained = base.duplicate()
		else:
			chained = StandardMaterial3D.new()
		chained.next_pass = _rim_material
		mi.set_surface_override_material(surface_idx, chained)
		applied += 1
	return applied

## Walk a gun subtree setting the black outline on every body MeshInstance3D, but SKIP the Muzzle
## subtree: the muzzle flash (ExplosionMesh) already draws its own thicker outline on next_pass, so
## an overlay here would just double it. Mirrors how the placeholder-mesh toggle leaves the Muzzle + FX
## alone. The muzzle of a swapped weapon is found by name.
func _apply_outline_recursive(node: Node) -> void:
	if not _outline_material:
		return
	var muzzle_node := _find_muzzle_marker(node)
	_apply_outline_skipping(node, muzzle_node)

func _apply_outline_skipping(node: Node, skip: Node) -> void:
	if node == skip:
		return
	# A modeled laser-sight attachment on a gun should read as a see-through emitter, not a hard
	# black-outlined prop — skip any node whose name matches an outline_skip_name_hints substring (and
	# its subtree). The functional rig laser beam is a separate sibling mesh, already never walked here.
	var lower_name := String(node.name).to_lower()
	for hint in outline_skip_name_hints:
		if not hint.is_empty() and lower_name.contains(hint.to_lower()):
			return
	if node is MeshInstance3D:
		(node as MeshInstance3D).material_overlay = _outline_material
	for child in node.get_children():
		_apply_outline_skipping(child, skip)

## Find a muzzle marker anywhere under a node, case-insensitively — so "Muzzle", "muzzle", etc. all work
## and the exact capitalisation of the node name doesn't matter. Used only to SKIP the muzzle subtree when
## stamping the outline (the muzzle FX draw their own).
func _find_muzzle_marker(node: Node) -> Node3D:
	for c in node.get_children():
		if c is Node3D and str(c.name).to_lower() == "muzzle":
			return c as Node3D
		var nested := _find_muzzle_marker(c)
		if nested:
			return nested
	return null
