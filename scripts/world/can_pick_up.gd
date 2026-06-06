class_name CanPickUp
extends Area3D

## Drop-in PICKUP component: aim at the object and press E (Interact) to add a configured Item to your
## inventory. It reuses the look-at talk plumbing verbatim — an Area3D on TalkHelpers.TALK_LAYER exposing
## the talk-handler surface — so PickupRay detects it and E picks it up with ZERO changes to ray_cast.gd,
## exactly like Talkable / LootableCorpse.
##
## SETUP: drop this under the visible object (or assign highlight_target), size its CollisionShape3D to
## cover the body you aim at, and set `item`. On pickup it grants the item to the player's backpack and
## frees the host (highlight_target, else our parent).

@export var item: Item                     ## the item granted on pickup (e.g. a weapon-item)
@export var amount: int = 1
## Name shown on the look-at hover; blank -> "Take <item name>".
@export var pickup_label: String = ""
## Node whose MeshInstance3D descendants get the white outline + that's freed on pickup. Null -> our parent.
@export var highlight_target: Node3D
@export var highlight_color: Color = Color(1.0, 1.0, 1.0, 1.0)
@export var highlight_width: float = 1.0

var _outline_mat: ShaderMaterial
var _meshes: Array[MeshInstance3D] = []

func _ready() -> void:
	# Become a look-at hitbox: sit on the talk layer so the interaction ray can hit us; sense nothing.
	collision_layer = TalkHelpers.TALK_LAYER
	collision_mask = 0
	_outline_mat = TalkHelpers.make_outline_material(highlight_color, highlight_width)
	var host := _host()
	if host != null:
		_meshes = TalkHelpers.collect_meshes(host, self)

## The node this pickup represents (outline target + freed on pickup): the configured target, else parent.
func _host() -> Node3D:
	if highlight_target != null:
		return highlight_target
	return get_parent() as Node3D

# --- Talk-handler surface (PickupRay treats it as a look-at target) ---

## E pressed while aimed at us: grant the item to the player's backpack, then remove the world object.
## Weapons are granted as UNIQUE instances (duplicated) so every picked-up weapon is its own object.
func start_talk(player: Node) -> void:
	if item == null:
		return
	if player is Character and (player as Character).inventory != null:
		var inv: CharacterInventory = (player as Character).inventory
		if item.is_weapon():
			for _n in maxi(1, amount):
				inv.add(item.duplicate() as Item, 1)
		else:
			inv.add(item, amount)
	var host := _host()
	if host != null:
		host.queue_free()
	else:
		queue_free()

## Pickable only while it has an item to give.
func can_be_talked_to() -> bool:
	return item != null

## Hover readout: the configured label, else "Take <item>", else a generic.
func look_name() -> String:
	if not pickup_label.is_empty():
		return pickup_label
	if item != null:
		return "Take %s" % item.label()
	return "Pick Up"

## No NPC behind a pickup (so the FNV hover won't greet/tint it; player.gd null-guards host_npc()).
func host_npc() -> NPC:
	return null

## Look-at highlight toggle — outlines the host's meshes, exactly like Talkable.
func set_look_highlight(on: bool) -> void:
	TalkHelpers.set_overlay(_meshes, _outline_mat if on else null)
