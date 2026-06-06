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
