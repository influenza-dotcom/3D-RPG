extends GutTest
## Contract suite for the WALLET ROW + its AmountPrompt — the affordance that replaced the backpack's
## zorkmids COIN TILE when money stopped being an inventory item. The player's cash is `Character.money`,
## a plain float, so the two gestures the tile used to carry live on a row above the grid (InventoryScreen)
## and under your column in the loot screen (LootScreen): **Drop…** spills a chosen slice as a physics
## MoneyBag, **Stash…** deposits a chosen amount into the loot source as a coin tile.
##
## What's pinned here is the PROMPT's arithmetic contract, because everything downstream trusts it: what it
## hands the callback is already clamped to the cap and snapped to Zorkmids.QUANTUM, so a caller never
## re-validates. Plus the two screens' wiring (the row exists and built its own prompt) — a bind that broke
## would leave the wallet unreachable with no other way to drop cash. The in-tree gesture itself (click Drop,
## bag lands on the floor) is playtest, per the project's testing policy.

var _got: Array = []

func before_each() -> void:
	_got.clear()

func _prompt() -> AmountPrompt:
	# add_child_autofree so _ready runs (the card is built there) and the node is released after the test.
	return add_child_autofree(AmountPrompt.new()) as AmountPrompt

func _collect() -> Callable:
	return func(n: float) -> void: _got.append(n)


func test_starts_closed_and_opens_on_ask() -> void:
	var p := _prompt()
	assert_false(p.is_open(), "the card ships hidden — it only ever appears on top of a screen that asks")
	p.ask("DROP", 10.0, "Drop", _collect())
	assert_true(p.is_open(), "ask() shows the card")


func test_seeds_the_full_cap_so_confirm_alone_means_all_of_it() -> void:
	# The coin tile's ONE gesture was "right-click = dump the whole purse". Seeding the field with the cap
	# keeps that available as Enter-Enter, while a typed number takes over the moment you touch a digit.
	var p := _prompt()
	p.ask("DROP", 12.5, "Drop", _collect())
	assert_almost_eq(p.amount(), 12.5, 0.001, "the prompt opens holding the whole wallet")


func test_amount_clamps_to_the_cap() -> void:
	var p := _prompt()
	p.ask("DROP", 12.5, "Drop", _collect())
	p._edit.text = "999"
	p._on_text_changed("999")
	assert_almost_eq(p.amount(), 12.5, 0.001,
		"typing more than you carry clamps to the wallet — a caller can never be handed money that isn't there")


func test_entry_is_filtered_to_digits_and_one_dot() -> void:
	var p := _prompt()
	p.ask("DROP", 100.0, "Drop", _collect())
	p._edit.text = "3.5.7abc"
	p._on_text_changed("3.5.7abc")
	assert_eq(p._edit.text, "3.57",
		"letters and a SECOND dot are dropped as you type (the ATM's filter) — the field can never hold junk")
	assert_almost_eq(p.amount(), 3.57, 0.001, "…and what survives parses as the number it looks like")


func test_junk_and_blank_read_as_zero_not_a_crash() -> void:
	var p := _prompt()
	p.ask("DROP", 100.0, "Drop", _collect())
	for junk in ["", ".", "   "]:
		p._edit.text = junk
		assert_eq(p.amount(), 0.0, "'%s' reads as 0.0 — never bool(<String>), which throws" % junk)


func test_fill_chips_take_a_fraction_of_the_cap() -> void:
	var p := _prompt()
	p.ask("DROP", 50.0, "Drop", _collect())
	p._on_fill(0.5)
	assert_almost_eq(p.amount(), 25.0, 0.001, "the Half chip fills half the wallet")
	p._on_fill(1.0)
	assert_almost_eq(p.amount(), 50.0, 0.001, "the All chip fills the whole wallet")


func test_confirm_hands_back_the_clamped_amount_and_closes() -> void:
	var p := _prompt()
	p.ask("DROP", 50.0, "Drop", _collect())
	p._on_fill(0.5)
	p._on_confirm_pressed()
	assert_eq(_got.size(), 1, "confirming calls the callback exactly once")
	assert_almost_eq(float(_got[0]), 25.0, 0.001, "…with the amount the field showed")
	assert_false(p.is_open(), "…and the card closes itself, BEFORE the callback runs (it may rebuild the host)")


func test_a_zero_entry_refuses_instead_of_committing_nothing() -> void:
	var p := _prompt()
	p.ask("DROP", 50.0, "Drop", _collect())
	p._edit.text = ""
	p._on_text_changed("")
	assert_true(p._confirm_btn.disabled, "a blank entry disables the commit, so the button says so before the click")
	p._on_confirm_pressed()
	assert_eq(_got.size(), 0, "a blank confirm never fires the callback")
	assert_true(p.is_open(), "…and doesn't close either — the card waits for a real number")


func test_an_empty_wallet_is_refused_before_the_card_ever_opens() -> void:
	# Asking "how much of nothing?" is an unanswerable card. ask() refuses outright (with the denial cue) so
	# pressing Drop on a broke wallet always ANSWERS rather than opening a dead prompt.
	var p := _prompt()
	p.ask("DROP", 0.0, "Drop", _collect())
	assert_false(p.is_open(), "a non-positive cap refuses to open")
	p.ask("DROP", -5.0, "Drop", _collect())
	assert_false(p.is_open(), "…as does a negative one (a quantized wallet is never negative, but fail safe)")


func test_cancel_closes_without_calling_back() -> void:
	var p := _prompt()
	p.ask("DROP", 50.0, "Drop", _collect())
	p._on_cancel_pressed()
	assert_false(p.is_open(), "Cancel closes the card")
	assert_eq(_got.size(), 0, "…and commits nothing")


func test_close_drops_the_callback_so_a_stale_confirm_cannot_fire() -> void:
	var p := _prompt()
	p.ask("DROP", 50.0, "Drop", _collect())
	p.close()
	p._on_confirm_pressed()  # a queued click landing after the host closed us
	assert_eq(_got.size(), 0, "a confirm on a closed card commits nothing — close() releases the callback + cap")


# ---------------------------------------------------------------------------
# The two screens' wiring: the row exists and each screen built its own prompt.
# ---------------------------------------------------------------------------

func test_inventory_screen_has_a_wallet_row_and_a_prompt() -> void:
	assert_not_null(InventoryScreen._wallet, "the backpack binds its %Wallet readout — the wallet's only paint site in the menu")
	assert_not_null(InventoryScreen._drop_money_btn, "…and the Drop button that opens the amount card")
	assert_not_null(InventoryScreen._amount_prompt, "…and code-builds the card itself (like the grid view)")
	assert_false(InventoryScreen._amount_prompt.is_open(), "the card ships closed")


func test_loot_screen_has_a_wallet_row_and_a_prompt() -> void:
	assert_not_null(LootScreen._wallet, "the loot screen binds YOUR %PlayerWallet readout")
	assert_not_null(LootScreen._stash_btn, "…and the Stash button that opens the amount card")
	assert_not_null(LootScreen._amount_prompt, "…and code-builds its own card")
	assert_false(LootScreen._amount_prompt.is_open(), "the card ships closed")


func test_zorkmids_never_reach_the_players_backpack_as_an_item() -> void:
	# The whole point of the change: money is not an inventory item. The coin Item still exists (a LOOT
	# source carries its cash as one), but nothing mirrors it into the player's bag any more — so the
	# mirror predicate that used to tell the two apart is gone, and Item.is_holdable still refuses the id.
	var inv := CharacterInventory.new()
	assert_false(inv.has_method("is_mirrored"),
		"CharacterInventory has no mirror registry left — no stack in the player's bag is a wallet VIEW")
	inv.free()
	var coin: Item = ItemDb.item_by_id(Zorkmids.ITEM_ID)
	assert_not_null(coin, "the coin template is still registered — corpses / containers / frozen pockets use it")
	assert_false(coin.is_holdable(),
		"a coin tile is money, never a hotbar prop — holding one would mint a money-bag nothing paid for")
