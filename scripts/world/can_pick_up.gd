class_name CanPickUp
extends LookAtInteractable

## Drop-in PICKUP component: aim at the object and press E (Interact) to add a configured Item to your
## inventory. Extends LookAtInteractable (the talk-layer hitbox + look-at outline); this adds only the
## pickup behaviour, so PickupRay detects it with ZERO changes to ray_cast.gd, like Talkable / LootableCorpse.
##
## SETUP: drop this under the visible object (or assign highlight_target), size its CollisionShape3D to
## cover the body you aim at, and set `item`. On pickup it grants the item to the player's backpack and
## frees the host (highlight_target, else our parent).

@export var item: Item                     ## the item granted on pickup (e.g. a weapon-item)
@export var amount: int = 1
## Name shown on the look-at hover; blank -> "Take <item name>".
@export var pickup_label: String = ""
## OPTIONAL drop table granted ON TOP of `item` when picked up — turns this into a "loot bag" of random
## items. Null = just `item`. Can be set WITHOUT an item, for a pure random-loot pickup.
@export var loot_table: LootTable = null

## E pressed while aimed at us: grant our payload (item + any loot table) to the player's backpack, then
## remove the world object.
func start_talk(player: Node) -> void:
	if player is Character and (player as Character).inventory != null:
		_grant((player as Character).inventory)
	var host := _host()
	if host != null:
		host.queue_free()
	else:
		queue_free()

## Grant our payload to `inv`: the configured item (weapons as UNIQUE instances) plus the optional loot
## table rolled on top. Split out so it's unit-testable without the pickup's host-free side effect.
func _grant(inv: CharacterInventory) -> void:
	if item != null:
		if item.is_weapon():
			for _n in maxi(1, amount):
				inv.add(item.duplicate() as Item, 1)
		else:
			inv.add(item, amount)
	if loot_table != null:
		var rng := RandomNumberGenerator.new()
		rng.randomize()
		loot_table.grant(inv, rng)

## Pickable while it has anything to give — a fixed item or a loot table.
func can_be_talked_to() -> bool:
	return item != null or loot_table != null

## Hover readout: the configured label, else "Take <item>", else a generic.
func look_name() -> String:
	if not pickup_label.is_empty():
		return pickup_label
	if item != null:
		return "Take %s" % item.label()
	return "Pick Up"
