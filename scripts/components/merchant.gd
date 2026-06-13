class_name Merchant
extends LookAtInteractable

## Drop-in SHOP / MERCHANT component. Two ways to trade with it (both supported):
##   1. STANDALONE (a vending machine, store counter): leave `standalone` on (default) — it sits on the talk
##      layer, so aiming at it and pressing Interact opens the shop, exactly like ItemContainer / Talkable
##      (zero ray_cast changes).
##   2. ON A DIALOGUE NPC: set `standalone` = false so the ray IGNORES it (the NPC's Talkable drives the
##      conversation); the dialogue then offers a "Trade" option that opens THIS merchant's shop.
##
## Pricing is markup / markdown: the player BUYS at item.value × buy_mult and SELLS at item.value × sell_mult
## (sell_mult < 1). The merchant has its own `money` till — it can't buy what it can't pay for.
##
## SETUP: drop it under the shopkeeper / counter (or assign highlight_target), size its CollisionShape3D to
## the body you aim at, fill `starting_stock` with what's for sale, and set `money` / the multipliers.

@export_group("Stock")
## What the shop sells WITH QUANTITIES — one StockEntry per line (item + how many): "3 health packs,
## 20 pistol clips, 2 shotguns" is three entries. The preferred way to author stock.
@export var stock_counts: Array[StockEntry] = []
## LEGACY flat list: each entry stocks x1 (add the same item twice for two). Kept so existing merchants
## keep working; both lists seed together. Weapons are stocked as UNIQUE instances either way.
@export var starting_stock: Array[Item] = []
@export_group("Display")
## Shown on the look-at hover ("Trade: <name>") + the shop title. Blank -> just "Merchant".
@export var shop_name: String = ""
@export_group("Pricing")
## The shop's till (zorkmids — fractional, see Zorkmids). Selling TO the merchant draws from this; it
## can't buy what it can't afford.
@export var money: float = 1000.0
## The player BUYS at item.value × this (>= 1.0 marks up). 1.0 = sold at face value.
@export var buy_mult: float = 1.0
## The player SELLS at item.value × this (< 1.0 marks down — the merchant's cut). 0.5 = half value.
@export var sell_mult: float = 0.5
@export_group("Behavior")
## STANDALONE (default): sit on the talk layer so Interact opens the shop directly. Off -> DATA-ONLY: the
## ray won't detect us, and a dialogue NPC drives access via its "Trade" option.
@export var standalone: bool = true

## The shop's stock — ShopScreen reads this. Built in _ready (a child CharacterInventory), seeded from starting_stock.
var stock: CharacterInventory

func _ready() -> void:
	# Standalone = a look-at hitbox on the talk layer (ray detects it); data-only merchants sense nothing.
	# Sets the layer itself (not super()) because the base always uses TALK_LAYER, then builds the outline.
	collision_layer = TalkHelpers.TALK_LAYER if standalone else 0
	collision_mask = 0
	stock = CharacterInventory.new()
	stock.name = &"Stock"
	add_child(stock)
	_seed_stock(stock)
	_build_outline()  # look-at outline over the host's meshes (LookAtInteractable helper)
	if auto_fit_collider:
		_fit_hitbox_to_host()

## Seed `into` from the authored stock: the COUNTED lines (stock_counts — N per entry) plus the legacy x1
## list (starting_stock). A weapon entry stocks one UNIQUE duplicate per count, so "2 shotguns" are two
## distinct objects (no shared-instance bugs); stackables stack. Split from _ready so tests can exercise
## the seeding on a bare inventory without the component's scene-side setup.
func _seed_stock(into: CharacterInventory) -> void:
	if into == null:
		return
	for entry in stock_counts:
		if entry == null or entry.item == null or entry.count <= 0:
			continue
		if entry.item.is_weapon():
			for i in entry.count:
				into.add(entry.item.duplicate() as Item, 1)
		else:
			into.add(entry.item, entry.count)
	for it in starting_stock:
		if it == null:
			continue
		if it.is_weapon():
			into.add(it.duplicate() as Item, 1)  # unique instance per weapon, like ItemContainer / CanPickUp
		else:
			into.add(it, 1)

# ---------------------------------------------------------------------------
# Pricing + transactions
# ---------------------------------------------------------------------------

## Zorkmids the player PAYS to buy one `item` (value marked up by buy_mult; at least 1 for a valued item).
## `buyer` (the player) applies its PERSUASION discount when provided (1.0 on a baseline sheet) — pass it
## wherever a price is SHOWN or CHARGED so the label and the till always agree.
func buy_price(item: Item, buyer: Node = null) -> float:
	if item == null or item.value <= 0.0:
		return 0.0
	var mult := buy_mult
	if buyer != null and buyer.has_method(&"stats_or_default"):
		mult *= buyer.stats_or_default().buy_price_mult()
	# Round UP to the smallest coin (the merchant's margin never rounds away), floored at one coin. The
	# inner snappedf (in CENT units, to a thousandth of a cent) scrubs binary-float noise BEFORE the
	# directional round, so 49.999999... cents reads as the 50 it truly is instead of ceiling 0.45 to 0.46.
	return maxf(Zorkmids.QUANTUM, ceilf(snappedf(item.value * mult / Zorkmids.QUANTUM, 0.001)) * Zorkmids.QUANTUM)

## Zorkmids the player RECEIVES for selling one `item` (value marked down by sell_mult; the seller's
## PERSUASION claws part of the markdown back — 1.0 on a baseline sheet).
func sell_price(item: Item, seller: Node = null) -> float:
	if item == null or item.value <= 0.0:
		return 0.0
	var mult := sell_mult
	if seller != null and seller.has_method(&"stats_or_default"):
		mult *= seller.stats_or_default().sell_price_mult()
	# Round DOWN to the smallest coin (the player's cut never rounds up past the markdown). Same float-noise
	# scrub as buy_price, so 44.999999... cents floors to the 45 it truly is, not 44.
	return maxf(0.0, floorf(snappedf(item.value * mult / Zorkmids.QUANTUM, 0.001)) * Zorkmids.QUANTUM)

## Player buys ONE `item` from the shop: it must be in stock, have a positive price, and the player must
## afford it. Moves the item into the player's backpack and the zorkmids into the till. True on success.
func buy(item: Item, player_node: Node) -> bool:
	var player := player_node as Player
	if stock == null or item == null or player == null or player.inventory == null:
		return false
	if not stock.has(item):
		return false
	var price := buy_price(item, player)
	if price <= 0.0 or player.money < price:
		return false
	player.add_money(-price)
	money += price
	stock.transfer_to(player.inventory, item, 1)
	return true

## Player sells ONE `item` to the shop: it must be in the player's bag, have a positive price, and the till
## must afford it. Moves the item into stock and the zorkmids to the player. True on success.
func sell(item: Item, player_node: Node) -> bool:
	var player := player_node as Player
	if stock == null or item == null or player == null or player.inventory == null:
		return false
	if not player.inventory.has(item):
		return false
	var price := sell_price(item, player)
	if price <= 0.0 or money < price:
		return false
	money -= price
	player.add_money(price)
	player.inventory.transfer_to(stock, item, 1)
	return true

# ---------------------------------------------------------------------------
# Behaviour (talk-handler surface — used only when standalone, a direct-interact shop)
# ---------------------------------------------------------------------------

## Interact pressed while aimed at us: open the shop on this merchant's stock.
func start_talk(player: Node) -> void:
	ShopScreen.open_shop(self, player)

## Always interactable — a shop is open for business even when its stock is empty (you can still sell).
func can_be_talked_to() -> bool:
	return true

## Hover readout: "Trade: <name>" (or just "Merchant" when unnamed).
func look_name() -> String:
	return "Trade: %s" % shop_name if not shop_name.is_empty() else "Merchant"
