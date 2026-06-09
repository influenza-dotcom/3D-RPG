class_name ItemContainer
extends LookAtInteractable

## Drop-in LOOTABLE CONTAINER component (a crate, chest, locker, fridge): aim at it and press E (Interact)
## to open the loot transfer on its OWN inventory — take items out, or deposit your own in (two-way).
## Extends LookAtInteractable (the talk-layer hitbox + look-at outline); this adds the inventory + open
## behaviour. Unlike a corpse, a container is PERSISTENT: it's never freed, so you can stash gear and return.
##
## SETUP: drop this under the visible object (or assign highlight_target), size its CollisionShape3D to
## cover the body you aim at, and (optionally) fill `starting_items` with what it holds.

## What the container starts with. Add the SAME item twice for two of it (ammo stacks; weapons stay
## separate). Weapons are seeded as UNIQUE instances so each is its own object (no shared-instance bugs).
@export var starting_items: Array[Item] = []
## Name shown on the look-at hover ("Loot: <name>") + the transfer screen title. Blank -> just "Container".
@export var container_name: String = ""

## The container's contents — LootScreen reads this. Built in _ready (a child CharacterInventory), seeded
## from starting_items.
var inventory: CharacterInventory

func _ready() -> void:
	super()  # talk-layer hitbox + look-at outline (LookAtInteractable)
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

# --- Behaviour (talk-handler surface) ---

## E pressed while aimed at us: open the loot transfer on this container's inventory (NEVER frees it).
func start_talk(player: Node) -> void:
	LootScreen.open_container(self, player)

## Always interactable — a container is openable even when empty, so you can deposit into it.
func can_be_talked_to() -> bool:
	return true

## Hover readout: "Loot: <name>" (or just "Container" when unnamed).
func look_name() -> String:
	return "Loot: %s" % container_name if not container_name.is_empty() else "Container"
