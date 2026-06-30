class_name MoneyPickUp
extends LookAtInteractable

const ModelResourceUtil = preload("res://scripts/components/model_resource.gd")

## A pickable stash of zorkmids. Aim at it and press Interact (E) to collect: it adds `amount` to the
## player's money, toasts the gain, and frees the host. Built on LookAtInteractable so PickupRay detects it
## with ZERO changes to ray_cast.gd, exactly like CanPickUp / LootableCorpse.
##
## SETUP: just drop a MoneyPickUp node and set `amount` — with no authored body it builds a simple gold coin
## (or `world_model` if you assign one) and auto-fits its hover hitbox. Or parent it under your own model and
## set highlight_target, like CanPickUp.

@export var amount: float = 25.0  ## fractional fine — 0.5 is half a zorkmid
## Hover label; blank -> "Take N zorkmids".
@export var pickup_label: String = ""
## OPTIONAL custom world model. Supports scene imports and raw Mesh resources.
## Null -> a simple gold coin is built, so a bare MoneyPickUp is usable as-is.
@export var world_model: Resource = null

## Build the world visual (custom model, else a default coin) when no body was authored. BEFORE super() so
## the look-at outline + auto-fit collider pick up the new mesh.
func _ready() -> void:
	if highlight_target == null:
		var vis: Node3D = ModelResourceUtil.instantiate(world_model, "WorldModel") if world_model != null else null
		if vis == null:
			vis = _default_coin()
		add_child(vis)
		highlight_target = vis
		auto_fit_collider = true
	super._ready()

func _validate_property(property: Dictionary) -> void:
	if property.name == &"world_model":
		property.hint = PROPERTY_HINT_RESOURCE_TYPE
		property.hint_string = ModelResourceUtil.HINT

## Collect: credit the player's wallet, toast the gain, remove the world object.
func start_talk(player: Node) -> void:
	if player is Player:
		(player as Player).add_money(amount)  # fires the HUD money readout + the floating +N indicator
	amount = 0.0  # zero BEFORE freeing so can_be_talked_to() goes false even if the free is deferred a frame
	# Free the CORRECT node: a built-in coin child is OUR descendant (host is a child of self) — freeing it would
	# leave the MoneyPickUp behind, so free SELF; otherwise the host is the world object we sit under, free that.
	var host := _host()
	if host != null and host != self and not is_ancestor_of(host):
		host.queue_free()
	else:
		queue_free()

## Pickable while it actually holds money.
func can_be_talked_to() -> bool:
	return amount > 0.0

## Hover readout: the configured label, else "Take N zorkmids".
func look_name() -> String:
	if not pickup_label.is_empty():
		return pickup_label
	return "Take %s zorkmids" % Zorkmids.fmt(amount)

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
