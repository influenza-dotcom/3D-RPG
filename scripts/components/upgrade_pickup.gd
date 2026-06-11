class_name UpgradePickup
extends LookAtInteractable

## A drop-in UPGRADE: aim + Interact to permanently UNLOCK a player mechanic (the grappling hook, etc.).
## On pickup it calls player.unlock_mechanic(unlock_id), toasts, and frees the host — the gated mechanic
## (grapple / laser_sight / wall_climb / air_dash / slide) comes online immediately. Mirrors MoneyPickUp.
##
## SETUP: drop an UpgradePickup node and set unlock_id (e.g. &"grapple") + display_name. With no authored
## body it builds a small glowing emblem (or world_model if you assign one) and auto-fits its hover hitbox.

@export var unlock_id: StringName = &"grapple"
@export var display_name: String = "Upgrade"   ## shown in the toast + hover, e.g. "Grappling Hook"
@export var world_model: PackedScene = null     ## optional custom visual; else a default emblem is built
@export var toast_color: Color = Color(0.5, 0.85, 1.0)

## Build the world visual (custom model, else a default emblem) when no body was authored. BEFORE super()
## so the look-at outline + auto-fit collider pick up the new mesh.
func _ready() -> void:
	if highlight_target == null:
		var vis: Node3D = world_model.instantiate() if world_model != null else _default_emblem()
		add_child(vis)
		highlight_target = vis
		auto_fit_collider = true
	super._ready()

## Grant the unlock to the collecting player, toast it, remove the world object.
func start_talk(player: Node) -> void:
	if player is Player and player.has_method(&"unlock_mechanic"):
		(player as Player).unlock_mechanic(unlock_id)
		if player.has_method(&"notify_toast"):
			player.notify_toast("%s acquired!" % display_name, toast_color)
	var host := _host()
	if host != null:
		host.queue_free()
	else:
		queue_free()

## Pickable while it actually grants something.
func can_be_talked_to() -> bool:
	return unlock_id != &""

## Hover readout, e.g. "Take Grappling Hook".
func look_name() -> String:
	return "Take %s" % display_name

## A small glowing emblem so a bare UpgradePickup (no authored body, no world_model) is visible + pickable.
func _default_emblem() -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var prism := PrismMesh.new()
	prism.size = Vector3(0.3, 0.45, 0.3)
	mi.mesh = prism
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.4, 0.8, 1.0)
	mat.emission_enabled = true
	mat.emission = Color(0.3, 0.7, 1.0)
	mat.emission_energy_multiplier = 2.0
	mi.material_override = mat
	return mi
