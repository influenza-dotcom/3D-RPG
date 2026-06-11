class_name MoneyPickUp
extends LookAtInteractable

## A pickable stash of zorkmids. Aim at it and press Interact (E) to collect: it adds `amount` to the
## player's money, toasts the gain, and frees the host. Built on LookAtInteractable so PickupRay detects it
## with ZERO changes to ray_cast.gd, exactly like CanPickUp / LootableCorpse.
##
## SETUP: just drop a MoneyPickUp node and set `amount` — with no authored body it builds a simple gold coin
## (or `world_model` if you assign one) and auto-fits its hover hitbox. Or parent it under your own model and
## set highlight_target, like CanPickUp.

@export var amount: int = 25
## Hover label; blank -> "Take N zorkmids".
@export var pickup_label: String = ""
## OPTIONAL custom world model. Null -> a simple gold coin is built, so a bare MoneyPickUp is usable as-is.
@export var world_model: PackedScene = null

## Build the world visual (custom model, else a default coin) when no body was authored. BEFORE super() so
## the look-at outline + auto-fit collider pick up the new mesh.
func _ready() -> void:
	if highlight_target == null:
		var vis: Node3D = world_model.instantiate() if world_model != null else _default_coin()
		add_child(vis)
		highlight_target = vis
		auto_fit_collider = true
	super._ready()

## Collect: credit the player's wallet, toast the gain, remove the world object.
func start_talk(player: Node) -> void:
	if player is Player:
		(player as Player).money += amount
		if player.has_method(&"notify_toast"):
			player.notify_toast("+%d zorkmids" % amount, Color(1.0, 0.84, 0.0))
	var host := _host()
	if host != null:
		host.queue_free()
	else:
		queue_free()

## Pickable while it actually holds money.
func can_be_talked_to() -> bool:
	return amount > 0

## Hover readout: the configured label, else "Take N zorkmids".
func look_name() -> String:
	if not pickup_label.is_empty():
		return pickup_label
	return "Take %d zorkmids" % amount

## A simple gold coin built in code so a bare MoneyPickUp (no authored body, no world_model) still shows
## something pickable in the world. Swap in a real model via world_model.
func _default_coin() -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.15
	cyl.bottom_radius = 0.15
	cyl.height = 0.04
	mi.mesh = cyl
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, 0.84, 0.0)
	mat.metallic = 0.9
	mat.roughness = 0.3
	mi.material_override = mat
	return mi
