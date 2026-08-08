extends GutTest
## CanPickUp + CanDestroy world components. GUT unit suite.
##
## CanPickUp is built off-tree (Area3D; _ready only sets up the talk hitbox, which the pure talk-handler
## surface doesn't need). Its grant is exercised with an off-tree Character stand-in (an NPC, which IS a
## Character) carrying a manual backpack — no in-tree player needed. CanDestroy's HP/destroy logic runs
## off-tree too (its _destroy guards side effects behind is_inside_tree(), so an off-tree instance just
## emits `destroyed` + frees). The in-tree look-at highlight + shoot-to-destroy hit are manual-verify, per
## the repo's no-_ready-in-unit-tests convention.

const PISTOL := preload("res://resources/weapons/pistol.tres")
const PISTOL_ITEM := preload("res://resources/items/pistol_item.tres")


# ---------------------------------------------------------------------------
# CanPickUp — talk-handler surface + grant
# ---------------------------------------------------------------------------

func test_can_pick_up_surface() -> void:
	var cp := CanPickUp.new()
	cp.item = PISTOL_ITEM
	assert_true(cp.can_be_talked_to(),
		"a pickup with an item is interactable")
	assert_eq(cp.look_name(), "Take Pistol",
		"the default hover readout is 'Take <item label>'")
	assert_true(cp.host_npc() == null,
		"a pickup has no NPC behind it (so the FNV hover won't greet/tint it)")
	cp.pickup_label = "Grab the rock"
	assert_eq(cp.look_name(), "Grab the rock",
		"an explicit pickup_label overrides the default readout")
	cp.item = null
	assert_false(cp.can_be_talked_to(),
		"a pickup with no item is not interactable")
	cp.free()


func test_can_pick_up_grants_unique_weapon_to_player() -> void:
	var cp := CanPickUp.new()
	cp.item = PISTOL_ITEM
	# An NPC IS a Character; built off-tree (no _ready) it's a fine Character stand-in with a manual bag.
	var player: NPC = load("res://scripts/npc/npc.gd").new()
	var bag := CharacterInventory.new()
	player.inventory = bag
	cp.start_talk(player)  # grants a UNIQUE pistol, then queue_frees cp (its host is null off-tree)
	var stacks := bag.contents()
	assert_eq(stacks.size(), 1,
		"picking up grants exactly one item to the player's backpack")
	var it: Item = stacks[0]["item"]
	assert_true(it.is_weapon() and it.weapon == PISTOL,
		"the granted item is a weapon item wrapping the configured weapon")
	assert_true(it != PISTOL_ITEM,
		"a picked-up weapon is a UNIQUE copy, not the shared template (so it can't double-mark as equipped)")
	bag.free()
	player.free()
	# cp queue_free'd itself in start_talk; don't free it again.


func test_can_pick_up_auto_equips_into_empty_hands() -> void:
	# An UNARMED player (equipped_item null = bare fists) who takes a weapon off the ground has it drawn for
	# them. The instance equipped must be the UNIQUE copy that was just granted, never the shared template:
	# equipped_item is what the UI paints its "(equipped)" marker from, so equipping the template would mark
	# the wrong stack the moment the player carries two of the same gun.
	var cp := CanPickUp.new()
	cp.item = PISTOL_ITEM
	var player: NPC = load("res://scripts/npc/npc.gd").new()
	var bag := CharacterInventory.new()
	player.inventory = bag
	watch_signals(bag)
	cp.start_talk(player)
	var granted: Item = bag.contents()[0]["item"]
	assert_true(bag.equipped_item == granted,
		"an unarmed player equips the picked-up weapon — the granted copy, not the shared item template")
	assert_signal_emitted(bag, "equip_weapon_requested",
		"auto-equip goes through the normal equip bridge so the owner plays the swap/draw")
	bag.free()
	player.free()
	# cp queue_free'd itself in start_talk; don't free it again.


func test_can_pick_up_never_swaps_a_weapon_out_of_armed_hands() -> void:
	# THE reason auto-equip is gated on empty hands: grabbing a pipe off the floor mid-fight must not put the
	# rifle away. Anything already equipped — even something the player is holstering — leaves the pickup as a
	# plain backpack grant. Pinned separately from the toggles because this one isn't configurable: it's the
	# rule itself.
	var cp := CanPickUp.new()
	cp.item = PISTOL_ITEM
	var player: NPC = load("res://scripts/npc/npc.gd").new()
	var bag := CharacterInventory.new()
	player.inventory = bag
	var wielded: Item = PISTOL_ITEM.duplicate() as Item
	bag.add(wielded, 1)
	bag.equip_item(wielded)  # the player is now ARMED
	cp.start_talk(player)
	assert_eq(bag.contents().size(), 2,
		"the picked-up weapon still lands in the backpack for an armed player")
	assert_true(bag.equipped_item == wielded,
		"picking a weapon up never takes the one already in your hands away from you")
	bag.free()
	player.free()
	# cp queue_free'd itself in start_talk; don't free it again.


func test_can_pick_up_auto_equip_is_vetoed_per_pickup_and_by_the_options_toggle() -> void:
	# TWO independent vetoes, both read live at pickup time: the designer's per-pickup export (a quest weapon
	# the player should own but not wield) and the player's Options -> Game toggle. Either one off = the
	# weapon still lands in the bag, just un-drawn.
	var cp := CanPickUp.new()
	cp.item = PISTOL_ITEM
	cp.auto_equip_weapon = false
	var player: NPC = load("res://scripts/npc/npc.gd").new()
	var bag := CharacterInventory.new()
	player.inventory = bag
	cp.start_talk(player)
	assert_eq(bag.contents().size(), 1, "the weapon is still granted with auto-equip off")
	assert_null(bag.equipped_item, "auto_equip_weapon = false leaves the picked-up weapon un-drawn")

	var was: bool = Settings.auto_equip_pickups
	Settings.auto_equip_pickups = false  # set directly, not via the setter — no settings.cfg write in a test
	var cp2 := CanPickUp.new()
	cp2.item = PISTOL_ITEM  # export left at its default ON, so only the Options toggle can veto here
	var bag2 := CharacterInventory.new()
	player.inventory = bag2
	cp2.start_talk(player)
	Settings.auto_equip_pickups = was
	assert_eq(bag2.contents().size(), 1, "the weapon is still granted with the Options toggle off")
	assert_null(bag2.equipped_item, "Settings.auto_equip_pickups = false leaves the picked-up weapon un-drawn")
	bag2.free()
	bag.free()
	player.free()
	# cp / cp2 queue_free'd themselves in start_talk; don't free them again.


func test_can_pick_up_start_talk_is_single_use_before_free_processes() -> void:
	var cp := CanPickUp.new()
	cp.item = PISTOL_ITEM
	var player: NPC = load("res://scripts/npc/npc.gd").new()
	var bag := CharacterInventory.new()
	player.inventory = bag
	cp.start_talk(player)
	assert_false(cp.can_be_talked_to(),
		"a committed pickup stops being interactable immediately, before queue_free processes")
	cp.start_talk(player)
	assert_eq(bag.contents().size(), 1,
		"pressing interact again in the same frame must not grant the pickup a second time")
	bag.free()
	player.free()
	# cp queue_free'd itself in start_talk; don't free it again.


func test_can_pick_up_null_item_grants_nothing() -> void:
	var cp := CanPickUp.new()
	# No item configured -> start_talk is a guarded no-op (doesn't crash, grants nothing).
	var player: NPC = load("res://scripts/npc/npc.gd").new()
	var bag := CharacterInventory.new()
	player.inventory = bag
	cp.start_talk(player)
	assert_true(bag.is_empty(),
		"a pickup with no item grants nothing")
	bag.free()
	player.free()
	cp.free()


# ---------------------------------------------------------------------------
# CanDestroy — HP / destroy logic (off-tree; _destroy guards side effects)
# ---------------------------------------------------------------------------

func test_can_destroy_decrements_and_survives() -> void:
	var cd := CanDestroy.new()
	cd.max_hp = 3
	cd.hp = 3  # _ready (which seeds hp = max_hp) doesn't run off-tree
	watch_signals(cd)
	cd.take_damage(1.0)
	assert_eq(cd.hp, 2,
		"a non-lethal shot chips one HP")
	assert_signal_not_emitted(cd, "destroyed",
		"it doesn't break until HP reaches 0")
	cd.free()


func test_can_destroy_breaks_at_zero_hp() -> void:
	var cd := CanDestroy.new()
	cd.max_hp = 1
	cd.hp = 1
	watch_signals(cd)
	cd.take_damage(2.0)  # one shot over its HP -> destroyed (off-tree: emits + frees, no side effects)
	assert_signal_emitted(cd, "destroyed",
		"a shot that drops HP to 0 destroys it (one-shot at max_hp 1)")
	# _destroy already queue_free'd cd; don't double-free.


func test_can_destroy_ignores_nonpositive_damage() -> void:
	var cd := CanDestroy.new()
	cd.max_hp = 2
	cd.hp = 2
	cd.take_damage(0.0)
	assert_eq(cd.hp, 2,
		"a 0-damage hit doesn't chip HP or destroy it")
	cd.free()


# ---------------------------------------------------------------------------
# SpawnOnDestroy — wires to the host's destroy signal so it drops loot on break
# ---------------------------------------------------------------------------

func test_spawn_on_destroy_connects_to_candestroy_host() -> void:
	var cd := CanDestroy.new()
	var sod := SpawnOnDestroy.new()
	cd.add_child(sod)
	add_child_autofree(cd)  # runs _ready on both -> sod connects to its host's `destroyed`
	assert_true(cd.is_connected(&"destroyed", Callable(sod, "_on_destroyed")),
		"SpawnOnDestroy must connect to its CanDestroy host's `destroyed` signal so drops spawn on break")


func test_spawn_on_destroy_is_safe_without_scene() -> void:
	var sod := SpawnOnDestroy.new()  # no add_child, no spawn_scene
	sod._on_destroyed()  # must be a guarded no-op with nothing configured
	assert_eq(sod.count, 1,
		"count defaults to 1")
	sod.free()


# ---------------------------------------------------------------------------
# Container — persistent lootable container (talk-handler surface + seeding)
# ---------------------------------------------------------------------------

func test_container_surface() -> void:
	var c := ItemContainer.new()
	assert_true(c.can_be_talked_to(),
		"a container is always interactable (open it to take OR deposit)")
	assert_eq(c.look_name(), "[PH] Container",
		"an unnamed container reads 'Container' on the hover readout")
	c.container_name = "Footlocker"
	assert_eq(c.look_name(), "[PH] Loot Footlocker",
		"a named container reads 'Loot <name>'")
	assert_true(c.host_npc() == null,
		"a container has no NPC behind it (so the FNV hover won't greet/tint it)")
	assert_true(c.has_method("start_talk"),
		"Container exposes start_talk so the interaction ray opens it")
	assert_true(c.has_method("set_look_highlight"),
		"Container exposes set_look_highlight for the look-at outline")
	c.free()


func test_container_seeds_unique_weapon_in_tree() -> void:
	# In-tree _ready builds the container's inventory + seeds it from item_stacks. A seeded weapon is a
	# UNIQUE copy, so two containers holding the same weapon .tres can't double-mark as equipped.
	var c := ItemContainer.new()
	var stack := ItemStack.new()
	stack.item = PISTOL_ITEM
	var items: Array[ItemStack] = [stack]
	c.item_stacks = items
	add_child_autofree(c)  # runs _ready -> builds + seeds the inventory
	assert_not_null(c.inventory, "the container builds its own inventory")
	var stacks := c.inventory.contents()
	assert_eq(stacks.size(), 1, "the container is seeded with its one starting item")
	var it: Item = stacks[0]["item"]
	assert_true(it.is_weapon() and it.weapon == PISTOL,
		"the seeded weapon item wraps the configured weapon")
	assert_true(it != PISTOL_ITEM,
		"a seeded weapon is a UNIQUE copy, not the shared template")
