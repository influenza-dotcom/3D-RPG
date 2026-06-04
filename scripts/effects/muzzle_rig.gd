class_name MuzzleRig
extends Node3D

## The gun rig's MUZZLE anchor management — built in code (no .tscn) and owned by GunMesh. Split off so the
## root stays a thin coordinator: this child snaps the rig's built-in muzzle (Sketchfab_Scene/Muzzle, with
## the flash / sparks / shell / whiz FX parented under it) onto the equipped weapon's own "Muzzle" marker —
## so each weapon defines its own muzzle position right in its model scene — and restores the rig's default
## muzzle spot for a weapon with no marker. It also resolves the per-weapon anchor markers the laser sight
## reads (equipped_marker), which the root exposes as a facade.
##
## Host-coupled: GunMesh builds it in _ready, sets `host` right after .new() (the rig muzzle + Sketchfab_Scene
## live under the host), and wires `swapper` so equipped_marker can search the CURRENT view-model. Off-tree
## (a unit-test GunMesh built via .new() with no add_child) this child never exists, so GunMesh's facade
## guards on it — equipped_marker returns null, exactly as the monolith's `if not is_instance_valid(_weapon_model)`
## returned null on a bare instance (no deferred equip ever ran).

## The GunMesh that owns the rig muzzle — set right after .new() in GunMesh._ready. READ-only here.
var host: GunMesh
## The sibling model swapper, wired right after .new() — equipped_marker searches its CURRENT view-model.
var swapper: WeaponModelSwapper

var _muzzle_default_pos: Vector3  ## rig muzzle's resting local position; restored when a weapon has no marker

## Stash the rig muzzle's resting local position the moment this child enters the tree (before the deferred
## first equip can move it), so a later weapon with no marker can be restored to it. The monolith captured
## this in GunMesh._ready from Sketchfab_Scene/Muzzle.position.
func _ready() -> void:
	var sk_muzzle := host.get_node_or_null("Sketchfab_Scene/Muzzle")
	if sk_muzzle is Node3D:
		_muzzle_default_pos = (sk_muzzle as Node3D).position

## If the equipped view-model contains a node named "Muzzle", snap the rig's muzzle (and the flash /
## sparks / shell / whiz FX parented under it) onto that point — so each weapon defines its own
## muzzle position right in its own model scene. Position only; the FX keep their forward facing.
func align_to(view_model: Node) -> void:
	var rig_muzzle := host.get_node_or_null("Sketchfab_Scene/Muzzle")
	if not (rig_muzzle is Node3D):
		return
	var vm_muzzle: Node3D = _find_muzzle_marker(view_model) if view_model else null
	if vm_muzzle is Node3D:
		# Weapon defines its own muzzle point — snap the rig muzzle to it.
		(rig_muzzle as Node3D).global_position = (vm_muzzle as Node3D).global_position
	else:
		# No per-weapon marker — restore the rig's default muzzle spot (the original behaviour).
		(rig_muzzle as Node3D).position = _muzzle_default_pos

## Find a named marker (case-insensitive) on the currently-equipped view-model — the per-weapon
## anchor points the laser sight reads. null if there's no view-model or no such marker.
func equipped_marker(lower_name: String) -> Node3D:
	var model: Node = swapper.current_model() if swapper else null
	if not is_instance_valid(model):
		return null
	return _find_named_marker(model, lower_name)

## Find a marker by (lower-cased) name anywhere under a node, case-insensitively.
func _find_named_marker(node: Node, lower_name: String) -> Node3D:
	for c in node.get_children():
		if c is Node3D and str(c.name).to_lower() == lower_name:
			return c as Node3D
		var nested := _find_named_marker(c, lower_name)
		if nested:
			return nested
	return null

## Find a muzzle marker anywhere under the view-model, case-insensitively — so "Muzzle", "muzzle",
## etc. all work and the exact capitalisation of the node name doesn't matter.
func _find_muzzle_marker(node: Node) -> Node3D:
	for c in node.get_children():
		if c is Node3D and str(c.name).to_lower() == "muzzle":
			return c as Node3D
		var nested := _find_muzzle_marker(c)
		if nested:
			return nested
	return null
