@tool
class_name CanPickUp
extends LookAtInteractable

## Drop-in PICKUP component: aim at the object and press E (Interact) to add a configured Item to your
## inventory. Extends LookAtInteractable (the talk-layer hitbox + look-at outline); this adds only the
## pickup behaviour, so PickupRay detects it with ZERO changes to ray_cast.gd, like Talkable / LootableCorpse.
##
## SETUP: drop this under the visible object (or assign highlight_target), size its CollisionShape3D to
## cover the body you aim at, and set `item`. On pickup it grants the item to the player's backpack and
## frees the host (highlight_target, else our parent).

@export_group("Payload")
## the item granted on pickup (e.g. a weapon-item)
@export var item: Item:
	set(value):
		item = value
		update_configuration_warnings()
@export var amount: int = 1                ## how many of `item` to grant (weapons add as that many unique instances)
## EASY count-based PILE: grab a small mix in one pickup ("2 stims + 10 ammo") as rows (item + count), granted
## ON TOP of `item` + the loot table. Weapons become unique instances per count. Leave empty for a single-item pickup.
@export var item_stacks: Array[ItemStack] = []
## OPTIONAL drop table granted ON TOP of `item` when picked up — turns this into a "loot bag" of random
## items. Null = just `item`. Can be set WITHOUT an item, for a pure random-loot pickup.
@export var loot_table: LootTable = null

@export_group("Hover Label")
## Name shown on the look-at hover; blank -> "Take <item name>".
@export var pickup_label: String = ""

@export_group("World Visual")
## When true, build this pickup's world visual from item.world_model at spawn (and auto-fit the hover hitbox
## to it) instead of relying on an authored body — for loot-dropped / code-spawned pickups that are just an
## Item carrying a model. A null item.world_model is a no-op, so an authored prefab's own look is preserved.
@export var build_model_from_item: bool = false

## Build the item-driven world visual when asked (see build_model_from_item). Runs BEFORE super() so the
## look-at outline + auto-fit collider pick up the freshly added mesh.
func _ready() -> void:
	if Engine.is_editor_hint():
		return  # @tool: in the editor we only evaluate _get_configuration_warnings, never instance the world model
	if build_model_from_item and item != null and item.world_model != null:
		var vis: Node3D = item.world_model.instantiate()
		add_child(vis)
		highlight_target = vis
		auto_fit_collider = true
	super._ready()

## E pressed while aimed at us: grant our payload (item + any loot table) to the player's backpack, then
## remove the world object. If the bag is too full to fit our primary `item`, the pickup is REFUSED — it stays
## in the world (not consumed) and a toast says so, so a bounded (Tetris) bag never makes loot vanish.
func start_talk(player: Node) -> void:
	if player is Character and (player as Character).inventory != null:
		var inv := (player as Character).inventory
		# Bounded-bag guard: if the configured `item` can't find a home, leave the whole pickup in the world.
		if item != null and not inv.can_accept(item):
			if player.has_method(&"notify_toast"):
				player.notify_toast("No room in your backpack", Color(0.85, 0.85, 0.85))
			return
		_grant(inv)
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
				if inv.add(item.duplicate() as Item, 1) <= 0:
					break  # bounded bag filled mid-grant — stop duplicating weapons that won't fit
		else:
			inv.add(item, amount)
	ItemStack.seed_into(inv, item_stacks)  # the easy count-based pile, on top of `item`
	if loot_table != null:
		var rng := RandomNumberGenerator.new()
		rng.randomize()
		loot_table.grant(inv, rng)

## Pickable while it has anything to give — a fixed item, a count-based pile, or a loot table.
func can_be_talked_to() -> bool:
	return item != null or loot_table != null or not item_stacks.is_empty()

## Editor warning: a pickup with nothing to give is a no-op — the player can't pick it up (can_be_talked_to
## is false). Mirrors that exact emptiness check so the inspector flags an unfinished pickup.
func _get_configuration_warnings() -> PackedStringArray:
	if item == null and loot_table == null and item_stacks.is_empty():
		return PackedStringArray([
			"Nothing to grant — set `item`, add `item_stacks` rows, or assign a `loot_table`. As-is the player can't pick this up."
		])
	return PackedStringArray()

## Hover readout: the configured label, else "Take <item>", else a generic.
func look_name() -> String:
	if not pickup_label.is_empty():
		return pickup_label
	if item != null:
		return "Take %s" % item.label()
	return "Pick Up"
