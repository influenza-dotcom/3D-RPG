class_name Merchant
extends Area3D

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

## What the shop sells. Add the SAME item twice for two of it (ammo stacks; weapons stay separate). Weapons
## are stocked as UNIQUE instances so each is its own object (no shared-instance bugs).
@export var starting_stock: Array[Item] = []
## Shown on the look-at hover ("Trade: <name>") + the shop title. Blank -> just "Merchant".
@export var shop_name: String = ""
## The shop's till (zorkmids). Selling TO the merchant draws from this; it can't buy what it can't afford.
@export var money: int = 1000
## The player BUYS at item.value × this (>= 1.0 marks up). 1.0 = sold at face value.
@export var buy_mult: float = 1.0
## The player SELLS at item.value × this (< 1.0 marks down — the merchant's cut). 0.5 = half value.
@export var sell_mult: float = 0.5
## STANDALONE (default): sit on the talk layer so Interact opens the shop directly. Off -> DATA-ONLY: the
## ray won't detect us, and a dialogue NPC drives access via its "Trade" option.
@export var standalone: bool = true
## Node whose MeshInstance3D descendants get the white outline on hover. Null -> our parent.
@export var highlight_target: Node3D
@export var highlight_color: Color = Color(1.0, 1.0, 1.0, 1.0)
@export var highlight_width: float = 1.0

## The shop's stock — ShopScreen reads this. Built in _ready (a child CharacterInventory), seeded from starting_stock.
var stock: CharacterInventory
var _outline_mat: ShaderMaterial
var _meshes: Array[MeshInstance3D] = []

func _ready() -> void:
	# Standalone = a look-at hitbox on the talk layer (ray detects it); data-only merchants sense nothing.
	collision_layer = TalkHelpers.TALK_LAYER if standalone else 0
	collision_mask = 0
	stock = CharacterInventory.new()
	stock.name = &"Stock"
	add_child(stock)
	for it in starting_stock:
		if it == null:
			continue
		if it.is_weapon():
			stock.add(it.duplicate() as Item, 1)  # unique instance per weapon, like ItemContainer / CanPickUp
		else:
			stock.add(it, 1)
	_outline_mat = TalkHelpers.make_outline_material(highlight_color, highlight_width)
	var host := _host()
	if host != null:
		_meshes = TalkHelpers.collect_meshes(host, self)

## The node this merchant represents (outline target): the configured target, else our parent.
func _host() -> Node3D:
	if highlight_target != null:
		return highlight_target
	return get_parent() as Node3D

# ---------------------------------------------------------------------------
# Pricing + transactions
# ---------------------------------------------------------------------------

## Zorkmids the player PAYS to buy one `item` (value marked up by buy_mult; at least 1 for a valued item).
func buy_price(item: Item) -> int:
	if item == null or item.value <= 0:
		return 0
	return maxi(1, int(ceil(item.value * buy_mult)))

## Zorkmids the player RECEIVES for selling one `item` (value marked down by sell_mult).
func sell_price(item: Item) -> int:
	if item == null or item.value <= 0:
		return 0
	return maxi(0, int(floor(item.value * sell_mult)))

## Player buys ONE `item` from the shop: it must be in stock, have a positive price, and the player must
## afford it. Moves the item into the player's backpack and the zorkmids into the till. True on success.
func buy(item: Item, player_node: Node) -> bool:
	var player := player_node as Player
	if stock == null or item == null or player == null or player.inventory == null:
		return false
	if not stock.has(item):
		return false
	var price := buy_price(item)
	if price <= 0 or player.money < price:
		return false
	player.money -= price
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
	var price := sell_price(item)
	if price <= 0 or money < price:
		return false
	money -= price
	player.money += price
	player.inventory.transfer_to(stock, item, 1)
	return true

# ---------------------------------------------------------------------------
# Talk-handler surface (used only when standalone — a direct-interact shop)
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

## No NPC behind a standalone merchant (the FNV hover won't greet/tint it; player.gd null-guards host_npc()).
func host_npc() -> NPC:
	return null

## Look-at highlight toggle — outlines the host's meshes, exactly like Talkable / ItemContainer.
func set_look_highlight(on: bool) -> void:
	TalkHelpers.set_overlay(_meshes, _outline_mat if on else null)
