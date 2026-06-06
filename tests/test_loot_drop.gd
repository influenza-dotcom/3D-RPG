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

# ---------------------------------------------------------------------------
# Pickpocket — lift a LIVE (unfreed) source's pockets (Talkable.start_talk while sneaking)
# ---------------------------------------------------------------------------

func test_loot_screen_pickpocket_invalid_npc_is_safe() -> void:
	LootScreen.pickpocket(null, null)  # invalid NPC -> guarded early-return
	assert_false(LootScreen.is_open(), "pickpocket(null, ...) must not open the screen")

func test_loot_screen_pickpocket_without_inventory_is_safe() -> void:
	# A host with no `inventory` property (e.g. an inanimate Talkable on a car/terminal) -> get() is null,
	# not a CharacterInventory, so pickpocket bails instead of opening an empty transfer.
	var bare := Node.new()
	LootScreen.pickpocket(bare, null)
	assert_false(LootScreen.is_open(),
		"pickpocketing something with no inventory must not open the screen")
	bare.free()

func test_pickpocket_opens_live_source_and_never_frees_it() -> void:
	# Pickpocket must open the transfer on the LIVE NPC's own inventory and — unlike looting a corpse — must
	# NEVER free the source when emptied (you're robbing a living person, not a body). Build an off-tree
	# Player with a hand-set backpack (no _ready) + a minimal live "NPC" stand-in, then drive the public API.
	var player = load("res://scripts/player/player.gd").new()
	player.inventory = CharacterInventory.new()
	var mark := _PickpocketTarget.new()
	mark.inventory = CharacterInventory.new()
	mark.inventory.add(PISTOL_ITEM, 1)
	LootScreen.pickpocket(mark, player)
	assert_true(LootScreen.is_open(),
		"pickpocketing a live, unaware NPC opens the transfer on their own inventory")
	LootScreen._take(PISTOL_ITEM)
	assert_true(player.inventory.has(PISTOL_ITEM),
		"the lifted item lands in the player's backpack")
	assert_false(LootScreen.is_open(),
		"taking the last pocketed item empties the source and closes the transfer")
	assert_true(is_instance_valid(mark),
		"a pickpocketed LIVE NPC is NEVER freed — only looted corpses are (free_when_empty is null here)")
	mark.inventory.free()
	mark.free()
	player.inventory.free()
	player.free()

# ---------------------------------------------------------------------------
# Pickpocket prompt — Talkable.look_name_for shows "Pick Pocket <name>"
# ---------------------------------------------------------------------------

func test_talkable_look_name_for_falls_back_to_plain_name() -> void:
	var t := Talkable.new()
	t.display_name = "Mark"
	# No host NPC + no crouched player -> pickpocketing doesn't apply -> the plain speaker name, no prefix.
	assert_eq(t.look_name_for(null), "Mark",
		"look_name_for falls back to the plain name when pickpocketing doesn't apply")
	t.free()

func test_talkable_look_name_for_shows_pickpocket_prompt() -> void:
	# A crouched player aiming at an off-guard NPC must read "Pick Pocket <name>", so the prompt matches what
	# Interact will do. Build the pieces off-tree (no _ready): an NPC named via display_name with a fresh
	# Perception (default State.UNAWARE -> is_off_guard() true), a Talkable hosted on it, and a player
	# crouched past the 0.5 mark.
	var npc = load("res://scripts/npc/npc.gd").new()
	npc.display_name = "Mark"
	var perc = load("res://scenes/enemies/perception.gd").new()  # default State.UNAWARE -> off-guard
	npc._perception = perc
	var t := Talkable.new()
	t.highlight_target = npc
	var player = load("res://scripts/player/player.gd").new()
	var c = load("res://scripts/player/crouch.gd").new()
	c.crouch_t = 0.8
	player.crouch = c
	assert_eq(t.look_name_for(player), "Pick Pocket Mark",
		"a crouched player aiming at an off-guard NPC sees a 'Pick Pocket <name>' prompt")
	c.free()
	player.free()
	t.free()
	perc.free()
	npc.free()

# ---------------------------------------------------------------------------
# Test helpers
# ---------------------------------------------------------------------------

## Minimal stand-in for a live, pickpocketable NPC: just the two members LootScreen.pickpocket reads off it
## via Object.get (an `inventory` CharacterInventory + a `display_name`). NOT a real NPC (no _ready, no
## Perception), so the open path is exercised without instancing the whole actor.
class _PickpocketTarget extends Node:
	var inventory: CharacterInventory
	var display_name := "Mark"
