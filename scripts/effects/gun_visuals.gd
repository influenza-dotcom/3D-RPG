class_name GunVisuals
extends Node3D

## The view-model's LOOK pass — built in code (no .tscn) and owned by GunMesh. Split off so the gun-mesh
## root stays a thin coordinator: this child owns the rim-light material (and its tuning exports), and the
## recursive walks that stamp shadows-off, the rim light, and the OUTLINE ID onto a gun subtree. The root
## just calls dress(target) — once on itself from _ready, then on each swapped-in weapon model.
##
## Host-coupled but host-AGNOSTIC: GunMesh builds one in _ready for the gun, and the Player builds one for
## the first-person ARMS rig (the bare fists wear the same look as every weapon). The host is needed only
## for its render `layers` (duck-typed — so projected world decals, keyed to a cull_mask that excludes the
## gun's layer, never land on the weapon); a host with no `layers` property (the BodyModelSwap arms rig,
## which already forces its parts onto the view-model layer itself) leaves mesh layers untouched. Off-tree
## (a unit-test GunMesh built via .new() with no add_child) this child never exists, so nothing dresses —
## matching the monolith.

const RIM_LIGHT_SHADER = preload("res://resources/shaders/rim_light.gdshader")

@export_group("Rim Light")
## Tint of the additive fresnel rim glow on the view model — warm off-white by default. Sets the shader's
## `rim_color`; pick the hue the gun's edges catch (e.g. cool blue for a sci-fi look).
@export var rim_color: Color = Color(0.95, 0.88, 0.75)
## Fresnel falloff exponent (shader range 0.1–8). HIGHER tightens the glow to a thin edge-only rim; LOWER
## spreads it across more of the surface.
@export var rim_power: float = 5.0
## Overall brightness of the rim glow (shader range 0–4). 0 = no rim; raise it to make the edge light pop.
@export var rim_strength: float = 0.5
## Top-down bias of the rim (0–1): 0 lights the rim evenly all around, 1 weights it toward upward-facing
## surfaces so the gun reads as lit from above. Sets the shader's `top_bias`.
@export var rim_top_bias: float = 0.35

@export_group("Outline")
## ⭐⭐ THE VIEW MODEL'S OUTLINE IS INKOUTLINE'S SCREEN-SPACE RING (InkOutline.TINT_ID_VIEW_MODEL), and
## dress() stamps it on every body mesh of the rig and of each swapped-in weapon model. There is no
## colour or width knob here any more: a ring resolves ONE id to ONE global LUT slot, so the gun's colour
## lives on InkOutline.highlight_view_model and its thickness on InkOutline.highlight_width_px, tunable
## live in the remote inspector like the rest of the pass.
##
## WHY THE RING AND NOT THE INVERTED HULL IT REPLACED (2026-08-27, the project-wide retirement): a shell
## is a second draw call per submesh, it fights the flash/rim chain for the ONE material_overlay slot, and
## it has to be authored at a width nobody can verify — which is exactly how the gun spent 2026-06-03 to
## 2026-08-18 wearing a rim of 0.02, a metres-era leftover that measured FIVE pixels on a whole pistol
## (988 at the NPC-parity 2.0 it was eventually corrected to). Nobody caught it for two months because the
## gun had no other outline to compare against. A constant-pixel ring cannot have that failure mode.
##
## ⭐ STILL TRUE, and load-bearing: the gun renders on ViewModelCamera.VIEW_MODEL_LAYER, InkOutline's mask
## camera culls that layer, and the world's screen-space ink is DISCARDED over the weapon on purpose. So
## the ring is the view model's ONLY outline — if a mesh here gets no tint duplicate it has no line at all.
## The ring's occlusion test exempts id 10 for the same reason (see ink_outline.gdshader): the gun is
## composited over the world by its own camera, so it must never be depth-tested against it.
## MeshInstance3D name substrings (case-insensitive) to SKIP when outlining — for a modeled
## laser sight / dot baked into a gun model that should read as a see-through emitter, not an outlined
## prop. If your gun's laser sight still gets outlined, add its exact node name to this list.
@export var outline_skip_name_hints: PackedStringArray = ["laser", "sight", "beam"]

## The node this dresses FOR — GunMesh for the gun, the BodyModelSwap arms rig for the fists. Set right
## after .new() by the builder. READ-only here, and only its `layers` are read (duck-typed .get, absent =
## leave mesh layers alone); the canonical state stays on the host.
var host: Node3D

var _rim_material: ShaderMaterial

## Build the shared rim-light material once, the moment this child enters the tree (before GunMesh._ready
## calls dress). The monolith built it in its own _ready (_setup_rim_light) before applying; keeping the
## build here means dress() only ever APPLIES, so the look never drifts between the rig and a swapped
## weapon model. ⭐ The outline no longer has a material to build — it is an id stamped per mesh in
## dress() — which retires the old ordering trap that `outline_width` had to be set BEFORE add_child or
## _ready would bake the stale value into a shared material.
func _ready() -> void:
	_rim_material = ShaderMaterial.new()
	_rim_material.shader = RIM_LIGHT_SHADER
	_rim_material.set_shader_parameter("rim_color", rim_color)
	_rim_material.set_shader_parameter("rim_power", rim_power)
	_rim_material.set_shader_parameter("rim_strength", rim_strength)
	_rim_material.set_shader_parameter("top_bias", rim_top_bias)

## Stamp the full look onto `target` — shadows off, rim light chained onto every surface, the outline id on
## every body mesh — in the SAME order the monolith ran it (shadows -> rim -> outline), both for the rig
## (dressed on itself from _ready) and for each swapped-in weapon model.
## ⭐ ORDER MATTERS between the first and last steps: _disable_shadows_recursive ASSIGNS `layers` from the
## host, and a tint duplicate is shielded from that walk by its meta — but only because the duplicate is
## recognisable. Stamp first and the assignment would still skip it; stamp last (as here) and the question
## never arises for a freshly built duplicate.
func dress(target: Node3D) -> void:
	if target == null:
		return
	_disable_shadows_recursive(target)
	_apply_rim_recursive(target)
	_apply_outline_recursive(target)

func _disable_shadows_recursive(node: Node) -> void:
	if node is MeshInstance3D:
		var mi := node as MeshInstance3D
		# InkOutline's invisible tint duplicate (meta &"npc_tint_dup") already ships shadows off, and the layer
		# ASSIGNMENT below would move it off ACTOR_TINT_LAYER onto whatever camera the host draws on — which
		# renders ink_tint.gdshader's raw R/G log-depth bytes as moving yellow/green stripe bands (the failure
		# reported 2026-08-25, see scripts/effects/body_part_gib.gd:186). A duplicate has no children to walk.
		if mi.has_meta(&"npc_tint_dup"):
			return
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		# Force every gun mesh onto the gun's render layer (which world decals
		# exclude via cull_mask) so projected decals — e.g. the player's blob
		# shadow when crouching lowers the gun near the floor — don't land on the
		# weapon. The imported model's submeshes default to layer 1 otherwise.
		# Duck-typed: the arms rig host has no `layers` and keeps its own (it already
		# forced the view-model layer onto every part).
		var host_layers: Variant = host.get(&"layers") if host != null else null
		if host_layers != null:
			mi.layers = int(host_layers)
	for child in node.get_children():
		_disable_shadows_recursive(child)

func _apply_rim_recursive(node: Node) -> int:
	var n := 0
	if node is MeshInstance3D:
		var mi := node as MeshInstance3D
		# InkOutline's invisible tint duplicate (meta &"npc_tint_dup") carries the ONE shared tint material for the
		# whole game (identity rides its per-instance "disposition_id" uniform). _chain_rim_on_mesh DUPLICATES
		# material_override to chain the rim onto it — which would both break that one-material contract (a fresh
		# copy per gun, per swap, losing the instance uniform) and rasterise a lit rim into the tint buffer, whose
		# RGB are raw depth/id NUMBERS, not colour. Skip it; a duplicate has no children to walk.
		if mi.has_meta(&"npc_tint_dup"):
			return 0
		n += _chain_rim_on_mesh(mi)
	for child in node.get_children():
		n += _apply_rim_recursive(child)
	return n

func _chain_rim_on_mesh(mi: MeshInstance3D) -> int:
	if not mi.mesh or not _rim_material:
		return 0
	# A mesh carrying a material_override (BodyModelSwap._skin tints the arms that way) outranks every
	# per-surface override, so the rim must chain onto the OVERRIDE itself or it silently loses. Duplicated
	# per-instance, same as the surface path below.
	if mi.material_override != null:
		var dup := mi.material_override.duplicate()
		dup.next_pass = _rim_material
		mi.material_override = dup
		return 1
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

## Walk a gun subtree stamping InkOutline.TINT_ID_VIEW_MODEL on every body MeshInstance3D, but SKIP the
## Muzzle subtree: the muzzle flash (ExplosionMesh) stamps its own outline id, so a second one here would
## put two duplicates in the same silhouette — and the tint buffer is one id per pixel, so they would
## z-fight rather than blend. Mirrors how the placeholder-mesh toggle leaves the Muzzle + FX alone. The
## muzzle of a swapped weapon is found by name.
##
## ⭐ Re-run on every model swap, which is what keeps a swapped-in weapon ringed: the duplicates live under
## the OLD model's meshes and die with it, and dress() is called again on the new one (gun_mesh.gd).
func _apply_outline_recursive(node: Node) -> void:
	var muzzle_node := _find_muzzle_marker(node)
	_apply_outline_skipping(node, muzzle_node)

func _apply_outline_skipping(node: Node, skip: Node) -> void:
	if node == skip:
		return
	# InkOutline's invisible tint duplicate (meta &"npc_tint_dup") IS the outline; walking into it would
	# ask apply_tint_mesh to give the duplicate a duplicate. Same node the layer/rim walks above must leave
	# alone (2026-08-25 stripe bands); it has no children.
	if node is MeshInstance3D and (node as MeshInstance3D).has_meta(&"npc_tint_dup"):
		return
	# A modeled laser-sight attachment on a gun should read as a see-through emitter, not a hard
	# black-outlined prop — skip any node whose name matches an outline_skip_name_hints substring (and
	# its subtree). The functional rig laser beam is a separate sibling mesh, already never walked here.
	var lower_name := String(node.name).to_lower()
	for hint in outline_skip_name_hints:
		if not hint.is_empty() and lower_name.contains(hint.to_lower()):
			return
	if node is MeshInstance3D:
		# apply_tint_mesh, not apply_tint: the walking form would re-adopt the very children this
		# function just refused (a "laser" mesh parented under an outlined receiver).
		InkOutline.apply_tint_mesh(node as MeshInstance3D, InkOutline.TINT_ID_VIEW_MODEL)
	for child in node.get_children():
		_apply_outline_skipping(child, skip)

## Find a muzzle marker anywhere under a node, case-insensitively — so "Muzzle", "muzzle", etc. all work
## and the exact capitalisation of the node name doesn't matter. Used only to SKIP the muzzle subtree when
## stamping the outline (the muzzle FX draw their own).
func _find_muzzle_marker(node: Node) -> Node3D:
	return NodeFinder.find_first_by_name(node, "muzzle")
