class_name WeaponModelSwapper
extends Node3D

## Swaps the equipped weapon's own view-model in and out under the gun rig — built in code (no .tscn) and
## owned by GunMesh. Split off so the root stays a thin coordinator: this child instantiates the equipped
## weapon's view_model scene under the rig (freeing the previous one), dresses it via GunVisuals, snaps the
## muzzle via MuzzleRig, and hides/restores the rig's built-in placeholder gun. A weapon with no view_model
## falls back to that placeholder, so unassigned weapons still show something.
##
## Host-coupled: GunMesh builds it in _ready, sets `host` right after .new() (the model is added under the
## host so the rim/outline/shadow passes and the laser's marker search all see it in the gun subtree), and
## wires the sibling `visuals` + `muzzle_rig`. The first equip is deferred from GunMesh._ready so the inventory
## has equipped its first weapon before we read it; re-run on swap_finished. Off-tree (a unit-test GunMesh built
## via .new() with no add_child) this child never exists and the deferred equip never runs — matching the
## monolith, where _equip_view_model's `if not inventory or not inventory.equipped_weapon: return` short-circuited
## a bare instance anyway.

## The GunMesh under which the view-model is parented — set right after .new() in GunMesh._ready. READ-only
## here aside from re-parenting the model under it; the canonical state stays on the host.
var host: GunMesh
## Sibling look/muzzle children, wired right after .new(): dress a swapped model + snap the rig muzzle to it.
var visuals: GunVisuals
var muzzle_rig: MuzzleRig

var _weapon_model: Node                   ## the equipped weapon's instantiated view-model
var _placeholder_meshes: Dictionary = {}  ## stashed built-in rig meshes, so they can be restored

## The currently-equipped view-model (or null), so the sibling MuzzleRig can search it for per-weapon anchor
## markers (equipped_marker) without owning it.
func current_model() -> Node:
	return _weapon_model

## Show the equipped weapon's own view-model. Instantiates its view_model scene under the rig
## (freeing the previous one) so each weapon has its own mesh + material, and hides the rig's
## built-in placeholder gun. A weapon with no view_model falls back to that placeholder, so
## unassigned weapons still show something.
func equip() -> void:
	var inventory: Inventory = host.inventory
	if not inventory or not inventory.equipped_weapon:
		return
	if is_instance_valid(_weapon_model):
		_weapon_model.queue_free()
		_weapon_model = null
	var scene: PackedScene = inventory.equipped_weapon.view_model
	if scene:
		_weapon_model = scene.instantiate()
		host.add_child(_weapon_model)
		if visuals:
			visuals.dress(_weapon_model as Node3D)
		if muzzle_rig:
			muzzle_rig.align_to(_weapon_model)
		_set_placeholder_hidden(true)
	else:
		# Placeholder weapon (no view_model): still reset the rig muzzle so it doesn't keep the
		# previous weapon's marker spot.
		if muzzle_rig:
			muzzle_rig.align_to(null)
		_set_placeholder_hidden(false)

## Hide/restore the rig's built-in placeholder gun (Sketchfab_Scene) by stashing/restoring each of
## its meshes — NOT toggling visibility, because the Muzzle + FX are parented under it and would
## vanish too. The Muzzle subtree is skipped entirely.
func _set_placeholder_hidden(hidden: bool) -> void:
	var sk := host.get_node_or_null("Sketchfab_Scene")
	var muzzle_node := host.get_node_or_null("Sketchfab_Scene/Muzzle")
	if sk and muzzle_node:
		_toggle_placeholder_meshes(sk, muzzle_node, hidden)

func _toggle_placeholder_meshes(node: Node, muzzle_node: Node, hidden: bool) -> void:
	if node == muzzle_node:
		return  # never touch the Muzzle + its FX
	if node is MeshInstance3D:
		var mi := node as MeshInstance3D
		if hidden:
			if mi.mesh:
				_placeholder_meshes[mi] = mi.mesh
				mi.mesh = null
		elif _placeholder_meshes.has(mi):
			mi.mesh = _placeholder_meshes[mi]
	for c in node.get_children():
		_toggle_placeholder_meshes(c, muzzle_node, hidden)
