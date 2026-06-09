class_name ItemContainer
extends Area3D

## Drop-in LOOTABLE CONTAINER component (a crate, chest, locker, fridge): aim at it and press E (Interact)
## to open the loot transfer on its OWN inventory — take items out, or deposit your own in (two-way). It
## reuses the look-at talk plumbing verbatim — an Area3D on TalkHelpers.TALK_LAYER exposing the talk-handler
## surface — so PickupRay detects it with ZERO changes to ray_cast.gd, exactly like Talkable / CanPickUp.
## Unlike a corpse, a container is PERSISTENT: it's never freed, so you can stash gear in it and come back.
##
## SETUP: drop this under the visible object (or assign highlight_target), size its CollisionShape3D to
## cover the body you aim at, and (optionally) fill `starting_items` with what it holds.

## What the container starts with. Add the SAME item twice for two of it (ammo stacks; weapons stay
## separate). Weapons are seeded as UNIQUE instances so each is its own object (no shared-instance bugs).
@export var starting_items: Array[Item] = []
## Name shown on the look-at hover ("Loot: <name>") + the transfer screen title. Blank -> just "Container".
@export var container_name: String = ""
## Node whose MeshInstance3D descendants get the white outline on hover. Null -> our parent.
@export var highlight_target: Node3D
@export var highlight_color: Color = Color(1.0, 1.0, 1.0, 1.0)
@export var highlight_width: float = 1.0

## The container's contents — LootScreen reads this. Built in _ready (a child CharacterInventory), seeded
## from starting_items.
var inventory: CharacterInventory
var _outline_mat: ShaderMaterial
var _meshes: Array[MeshInstance3D] = []

func _ready() -> void:
	# Become a look-at hitbox: sit on the talk layer so the interaction ray can hit us; sense nothing.
	collision_layer = TalkHelpers.TALK_LAYER
	collision_mask = 0
	inventory = CharacterInventory.new()
	inventory.name = &"Contents"
	add_child(inventory)
	for it in starting_items:
		if it == null:
			continue
		if it.is_weapon():
			inventory.add(it.duplicate() as Item, 1)  # unique instance per weapon, like CanPickUp / drops
		else:
			inventory.add(it, 1)
	_outline_mat = TalkHelpers.make_outline_material(highlight_color, highlight_width)
	var host := _host()
	if host != null:
		_meshes = TalkHelpers.collect_meshes(host, self)

## The node this container represents (outline target): the configured target, else our parent.
func _host() -> Node3D:
	if highlight_target != null:
		return highlight_target
	return get_parent() as Node3D

# --- Talk-handler surface (PickupRay treats it as a look-at target) ---

## E pressed while aimed at us: open the loot transfer on this container's inventory (NEVER frees it).
func start_talk(player: Node) -> void:
	LootScreen.open_container(self, player)

## Always interactable — a container is openable even when empty, so you can deposit into it.
func can_be_talked_to() -> bool:
	return true

## Hover readout: "Loot: <name>" (or just "Container" when unnamed).
func look_name() -> String:
	return "Loot: %s" % container_name if not container_name.is_empty() else "Container"

## No NPC behind a container (so the FNV hover won't greet/tint it; player.gd null-guards host_npc()).
func host_npc() -> NPC:
	return null

## Look-at highlight toggle — outlines the host's meshes, exactly like Talkable / CanPickUp.
func set_look_highlight(on: bool) -> void:
	TalkHelpers.set_overlay(_meshes, _outline_mat if on else null)
