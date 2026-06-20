@tool
class_name ItemContainer
extends LookAtInteractable

## Drop-in LOOTABLE CONTAINER component (a crate, chest, locker, fridge): aim at it and press E (Interact)
## to open the loot transfer on its OWN inventory — take items out, or deposit your own in (two-way).
## Extends LookAtInteractable (the talk-layer hitbox + look-at outline); this adds the inventory + open
## behaviour. Unlike a corpse, a container is PERSISTENT: it's never freed, so you can stash gear and return.
##
## SETUP: drop this under the visible object (or assign highlight_target), size its CollisionShape3D to
## cover the body you aim at, and (optionally) fill `starting_items` with what it holds.

## EASY count-based contents: "5 healthpacks, 30 pistol ammo, 2 shotguns" is three rows (item + count) instead of
## repeating an item in starting_items. The preferred way to fill a crate. Seeded with starting_items + the table.
@export var item_stacks: Array[ItemStack] = []
## LEGACY fixed contents: add the SAME item twice for two of it. Prefer item_stacks above (it has a count).
## Weapons are seeded as UNIQUE instances so each is its own object (no shared-instance bugs).
@export var starting_items: Array[Item] = []
## Zorkmids stashed in this container -- looted via the same "Take N zm" row a corpse offers. 0 = no cash.
@export var money: float = 0.0
## OPTIONAL drop table rolled into the contents at spawn, ON TOP of the above — for a crate/chest with random
## loot. Null = just the fixed contents. (Weapons rolled from the table are unique instances.)
@export var loot_table: LootTable = null
## Name shown on the look-at hover ("Loot <name>") + the transfer screen title. Blank -> just "Container".
@export var container_name: String = ""

## The container's contents — LootScreen reads this. Built in _ready (a child CharacterInventory), seeded
## from starting_items.
var inventory: CharacterInventory

func _ready() -> void:
	if Engine.is_editor_hint():
		_editor_fit_hitbox()  # preview the auto-fit hitbox in-editor (resizes an existing collider; safe)
		return  # @tool: the inventory build + seed is runtime-only
	super()  # talk-layer hitbox + look-at outline (LookAtInteractable)
	add_to_group(&"containers")  # discoverable by NpcScavenge (an NPC raids nearby crates for a better gun)
	inventory = CharacterInventory.new()
	inventory.name = &"Contents"
	add_child(inventory)
	_seed_contents()

## Seed the contents: the authored starting_items (weapons as unique instances), then roll the optional
## loot_table on top. Split out so it's unit-testable off-tree (set `inventory`, call directly).
func _seed_contents() -> void:
	if inventory == null:
		return
	ItemStack.seed_into(inventory, item_stacks)  # the easy count-based contents
	for it in starting_items:
		if it == null:
			continue
		if it.is_weapon():
			inventory.add(it.duplicate() as Item, 1)  # unique instance per weapon, like CanPickUp / drops
		else:
			inventory.add(it, 1)
	if loot_table != null:
		var rng := RandomNumberGenerator.new()
		rng.randomize()
		loot_table.grant(inventory, rng)

# --- Behaviour (talk-handler surface) ---

## E pressed while aimed at us: pick/key any Lock child first (one attempt per press — see Lock.try_unlock),
## then open the loot transfer on this container's inventory (NEVER frees it). A failed attempt toasts what
## the lock needs and leaves it shut.
func start_talk(player: Node) -> void:
	var lock := Lock.of(self)
	if lock != null and lock.locked and not lock.try_unlock(player):
		return  # still locked — the toast said why
	Restocker.notify_visit(self)  # a child Restocker in ON_VISIT mode refills the crate before it opens
	LootScreen.open_container(self, player)

## Top the container's contents back up to its authored baseline (item_stacks + starting_items), adding ONLY
## the shortfall per item kind — never doubling, never removing what the player deposited. A child Restocker
## calls this so a looted crate refills on a return visit. (The optional loot_table is NOT re-rolled.)
func refill() -> void:
	if inventory == null:
		return
	var baseline := {}
	for st in item_stacks:
		if st != null:
			CharacterInventory.accumulate_baseline(baseline, st.item, st.count)
	for it in starting_items:
		CharacterInventory.accumulate_baseline(baseline, it, 1)
	CharacterInventory.refill_to_baseline(inventory, baseline)

## Always interactable — a container is openable even when empty, so you can deposit into it.
func can_be_talked_to() -> bool:
	return true

## Hover readout: "Loot <name>" (or just "Container" when unnamed) — "Unlock <name>" while a Lock child
## holds it shut, so the [E] prompt says what pressing it will actually attempt.
func look_name() -> String:
	var lock := Lock.of(self)
	if lock != null and lock.locked:
		return "Unlock %s" % (container_name if not container_name.is_empty() else "Container")
	return "Loot %s" % container_name if not container_name.is_empty() else "Container"
