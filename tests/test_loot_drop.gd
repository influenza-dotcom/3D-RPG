extends GutTest
## Loot drop (Phase F): a LootableCorpse copies a dead NPC's backpack and exposes the talk-handler surface
## so PickupRay opens the LootScreen on it; taking items moves them corpse -> player. GUT unit suite.
##
## SCOPE: LootableCorpse is built off-tree via .new() (Area3D; its _ready only builds the look-at hitbox,
## which the pure setup/look_name/can_be_talked_to/host_npc surface doesn't need). The take MECHANIC is
## asserted at the CharacterInventory level (transfer_to). The NPC._on_died spawn and the E -> LootScreen
## open are integration (need an in-tree NPC death / a live Player) and are verified by manual playtest,
## per the repo's no-_ready-in-unit-tests convention. LootScreen gets the same autoload smoke coverage as
## test_options_menu / test_inventory_screen.

const PISTOL_ITEM := preload("res://resources/items/pistol_item.tres")
const SHOTGUN_ITEM := preload("res://resources/items/shotgun_item.tres")

func after_each() -> void:
	if LootScreen.is_open():
		LootScreen.close()

# ---------------------------------------------------------------------------
# LootableCorpse — pure surface (off-tree)
# ---------------------------------------------------------------------------

func test_corpse_setup_copies_source_inventory_and_name() -> void:
	var src := CharacterInventory.new()
	src.add(PISTOL_ITEM, 1)
	src.add(SHOTGUN_ITEM, 1)
	var corpse := LootableCorpse.new()
	corpse.setup(src, "Bandit")
	assert_eq(corpse.corpse_name, "Bandit",
		"setup() records the dead NPC's name for the loot readout")
	assert_true(corpse.inventory.has(PISTOL_ITEM) and corpse.inventory.has(SHOTGUN_ITEM),
		"the corpse must hold a copy of the dead NPC's whole backpack")
	# Independent copy: emptying the source must NOT drain the corpse.
	src.remove(PISTOL_ITEM, 1)
	assert_true(corpse.inventory.has(PISTOL_ITEM),
		"the corpse copy is independent — mutating the source backpack must not change the loot")
	src.free()
	corpse.free()

func test_corpse_look_name() -> void:
	var corpse := LootableCorpse.new()
	corpse.setup(null, "Bandit")
	assert_eq(corpse.look_name(), "Loot: Bandit",
		"a named corpse reads 'Loot: <name>' on the hover HUD")
	var anon := LootableCorpse.new()
	anon.setup(null, "")
	assert_eq(anon.look_name(), "Loot",
		"an unnamed corpse reads just 'Loot'")
	corpse.free()
	anon.free()

func test_corpse_can_be_talked_to_tracks_emptiness() -> void:
	var src := CharacterInventory.new()
	src.add(PISTOL_ITEM, 1)
	var corpse := LootableCorpse.new()
	corpse.setup(src, "Bandit")
	assert_true(corpse.can_be_talked_to(),
		"a corpse with loot is interactable (highlights + opens)")
	corpse.inventory.remove(PISTOL_ITEM, 1)
	assert_false(corpse.can_be_talked_to(),
		"an emptied corpse is no longer interactable — it stops highlighting and won't reopen")
	src.free()
	corpse.free()

func test_corpse_host_npc_is_null() -> void:
	var corpse := LootableCorpse.new()
	corpse.setup(null, "Bandit")
	assert_true(corpse.host_npc() == null,
		"a corpse has no NPC behind it, so the FNV hover won't try to greet/tint it (player.gd null-guards)")
	corpse.free()

func test_corpse_start_talk_without_player_is_safe() -> void:
	var src := CharacterInventory.new()
	src.add(PISTOL_ITEM, 1)
	var corpse := LootableCorpse.new()
	corpse.setup(src, "Bandit")
	corpse.start_talk(null)  # no player -> LootScreen.open_for must guard, not crash or open
	assert_false(LootScreen.is_open(),
		"opening loot with no valid player must not open the screen")
	src.free()
	corpse.free()

# ---------------------------------------------------------------------------
# The take mechanic (CharacterInventory level)
# ---------------------------------------------------------------------------

func test_loot_transfer_moves_items_corpse_to_player() -> void:
	var corpse_inv := CharacterInventory.new()
	corpse_inv.add(PISTOL_ITEM, 1)
	var player_inv := CharacterInventory.new()
	var moved := corpse_inv.transfer_to(player_inv, PISTOL_ITEM, 1)
	assert_eq(moved, 1, "one pistol is taken")
	assert_false(corpse_inv.has(PISTOL_ITEM), "the taken item leaves the corpse")
	assert_true(player_inv.has(PISTOL_ITEM), "the taken item arrives in the player's backpack")
	corpse_inv.free()
	player_inv.free()

# ---------------------------------------------------------------------------
# LootScreen autoload smoke
# ---------------------------------------------------------------------------

func test_loot_screen_autoload_and_ui_built() -> void:
	assert_not_null(LootScreen, "LootScreen autoload should be registered")
	assert_not_null(LootScreen._root, "the overlay root should be built at startup")
	assert_not_null(LootScreen._corpse_list, "the corpse column list should be built at startup")
	assert_not_null(LootScreen._player_list, "the player column list should be built at startup")

func test_loot_screen_starts_closed() -> void:
	assert_false(LootScreen.is_open(), "the loot screen starts closed")

func test_loot_screen_open_for_invalid_corpse_is_safe() -> void:
	LootScreen.open_for(null, null)  # invalid corpse -> guarded early-return
	assert_false(LootScreen.is_open(), "open_for(null, ...) must not open the screen")
