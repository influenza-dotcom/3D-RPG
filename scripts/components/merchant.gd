@tool
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
## the body you aim at, fill `stock_counts` with what's for sale, and set `money` / the multipliers.

## Faction registry (preloaded by path) for the reputation-pricing dropdown (WR-2).
const Factions = preload("res://scripts/faction/factions.gd")

@export_group("Stock")
## What the shop sells WITH QUANTITIES — one StockEntry per line (item + how many): "3 health packs,
## 20 pistol clips, 2 shotguns" is three entries. The preferred way to author stock.
@export var stock_counts: Array[StockEntry] = []
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
## WR-2 faction pricing: the merchant's faction (dropdown from resources/factions/). With a
## reputation_discount_curve set, the player's STANDING with this faction bends the price. Empty = no faction pricing.
@export var faction_id: String = ""
## Maps the player's standing with `faction_id` (normalised 0..1 over the rep min/max) to a FAVOR fraction:
## the player buys at (1 - favor)x and sells at (1 + favor)x. 0 = neutral, 0.2 = 20% friendlier, NEGATIVE Y =
## a hostile markup. null = inert (no faction pricing — today's behaviour). Authored as a Curve over X in 0..1.
@export var reputation_discount_curve: Curve = null
@export_group("Behavior")
## STANDALONE (default): sit on the talk layer so Interact opens the shop directly. Off -> DATA-ONLY: the
## ray won't detect us, and a dialogue NPC drives access via its "Trade" option.
@export var standalone: bool = true
@export_group("Access")
## OPTIONAL story-flag gate: when set, the merchant refuses to trade (with a toast) unless
## str(GameState.get_flag(required_flag)) == required_flag_value. Empty = always open. For a vendor you unlock
## after a quest ("the fence opens once you've met the boss").
@export var required_flag: StringName = &""
## The flag value (stringified) needed to trade. Default "true" matches a flag set with GameState.set_flag's
## default value. Only matters when required_flag is set.
@export var required_flag_value: String = "true"

## The shop's stock — ShopScreen reads this. Built in _ready (a child CharacterInventory), seeded from stock_counts.
var stock: CharacterInventory

## Editor warning: a standalone Merchant on a dialogue NPC steals the interaction ray from the NPC's Talkable.
func _get_configuration_warnings() -> PackedStringArray:
	var w := PackedStringArray()
	if standalone and _on_dialogue_host():
		w.append("`standalone` is on but this Merchant is a child of a dialogue NPC — its talk-layer hitbox steals the interaction ray from the NPC's Talkable. Set `standalone` = false and open the shop from the dialogue's \"Trade\" option.")
	return w

## Self-populate the faction_id dropdown from the factions on disk (WR-2), like NpcData / BuildGate.
func _validate_property(property: Dictionary) -> void:
	if property.name == "faction_id":
		property.hint = PROPERTY_HINT_ENUM_SUGGESTION
		property.hint_string = Factions.ids_csv()

func _ready() -> void:
	if Engine.is_editor_hint():
		_editor_fit_hitbox()  # preview the auto-fit hitbox in-editor (resizes an existing collider; safe)
		return  # @tool: only _get_configuration_warnings runs in-editor; the Stock build + hitbox setup is runtime-only
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

## Seed `into` from the authored stock: the COUNTED lines (stock_counts — N per entry). A weapon entry stocks one UNIQUE duplicate per count, so "2 shotguns" are two
## distinct objects (no shared-instance bugs); stackables stack. Split from _ready so tests can exercise
## the seeding on a bare inventory without the component's scene-side setup.
func _seed_stock(into: CharacterInventory) -> void:
	if into == null:
		return
	for entry in stock_counts:
		if entry == null or entry.item == null or entry.count <= 0:
			continue
		if not _entry_unlocked(entry):  # WR-5: a rep-gated line stays off the shelf until the player's standing earns it
			continue
		if entry.item.is_weapon():
			for i in entry.count:
				into.add(entry.item.duplicate() as Item, 1)
		else:
			into.add(entry.item, entry.count)

# ---------------------------------------------------------------------------
# Pricing + transactions
# ---------------------------------------------------------------------------

## WR-2: the faction FAVOR fraction at the player's current standing with `faction_id` — sampled from
## reputation_discount_curve over the normalised standing (0..1 across the rep min/max). 0 when no faction /
## no curve (inert). Positive = friendlier (cheaper buys, dearer sells); negative = a hostile markup.
func _rep_favor() -> float:
	if reputation_discount_curve == null or faction_id == "":
		return 0.0
	var fac := Factions.by_id(faction_id)
	if fac == null:
		return 0.0
	var rep_min: float = GameSettings.reputation.rep_min
	var rep_max: float = GameSettings.reputation.rep_max
	var t := inverse_lerp(rep_min, rep_max, Reputation.get_reputation(fac))
	return reputation_discount_curve.sample(clampf(t, 0.0, 1.0))

## WR-5: whether `entry`'s reputation gate is met right now — true unless the line sets required_reputation and
## the player's standing with this merchant's faction is below it. A merchant with no faction_id (or an id that
## doesn't resolve) can't measure standing, so the gate is ignored and the line stocks. Read at seed + refill,
## so the visible stock reflects standing at restock time (and a line drops back out if standing later falls).
func _entry_unlocked(entry: StockEntry) -> bool:
	if entry == null or entry.required_reputation == 0.0:
		return true
	if faction_id == "":
		return true  # no faction to measure standing against -> can't gate, so don't withhold stock
	var fac := Factions.by_id(faction_id)
	if fac == null:
		return true
	return Reputation.get_reputation(fac) >= entry.required_reputation

## Zorkmids the player PAYS to buy one `item` (value marked up by buy_mult; at least 1 for a valued item).
## `buyer` (the player) applies its STREETWISE discount when provided (1.0 on a baseline sheet) — pass it
## wherever a price is SHOWN or CHARGED so the label and the till always agree.
func buy_price(item: Item, buyer: Node = null) -> float:
	if item == null or item.value <= 0.0:
		return 0.0
	var mult := buy_mult
	if buyer != null and buyer.has_method(&"stats_or_default"):
		var pmod: float = buyer.status_stat_modifier(&"streetwise") if buyer.has_method(&"status_stat_modifier") else 0.0
		mult *= buyer.stats_or_default().buy_price_mult(pmod)  # active streetwise buff sweetens the price
	mult *= maxf(0.0, 1.0 - _rep_favor())  # WR-2: a favoured faction sells to you cheaper (floored at free)
	# Round UP to the smallest coin (the merchant's margin never rounds away), floored at one coin. The
	# inner snappedf (in CENT units, to a thousandth of a cent) scrubs binary-float noise BEFORE the
	# directional round, so 49.999999... cents reads as the 50 it truly is instead of ceiling 0.45 to 0.46.
	return maxf(Zorkmids.QUANTUM, ceilf(snappedf(item.value * mult / Zorkmids.QUANTUM, 0.001)) * Zorkmids.QUANTUM)

## Zorkmids the player RECEIVES for selling one `item` (value marked down by sell_mult; the seller's
## STREETWISE claws part of the markdown back — 1.0 on a baseline sheet).
func sell_price(item: Item, seller: Node = null) -> float:
	if item == null or item.value <= 0.0:
		return 0.0
	var mult := sell_mult
	if seller != null and seller.has_method(&"stats_or_default"):
		var pmod: float = seller.status_stat_modifier(&"streetwise") if seller.has_method(&"status_stat_modifier") else 0.0
		mult *= seller.stats_or_default().sell_price_mult(pmod)  # active streetwise buff claws back more of the markdown
	mult *= maxf(0.0, 1.0 + _rep_favor())  # WR-2: a favoured faction pays you MORE (the inverse of the buy discount)
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
	# Bounded-bag guard: don't charge for something the (Tetris) backpack can't hold — the transfer below would
	# move nothing and the player would lose the coin. Refuse the sale and tell them why.
	if not player.inventory.can_accept(item):
		if player.has_method(&"notify_toast"):
			player.notify_toast(PlayerText.TOAST_BACKPACK_FULL, Color(0.85, 0.85, 0.85))
		return false
	player.add_money(-price)
	money = snappedf(money + price, Zorkmids.QUANTUM)  # keep the till on the coin grid like every wallet (Character.add_money snaps)
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
	money = snappedf(money - price, Zorkmids.QUANTUM)  # keep the till on the coin grid like every wallet (Character.add_money snaps)
	player.add_money(price)
	player.inventory.transfer_to(stock, item, 1)
	return true

# ---------------------------------------------------------------------------
# Behaviour (talk-handler surface — used only when standalone, a direct-interact shop)
# ---------------------------------------------------------------------------

## Interact pressed while aimed at us: open the shop on this merchant's stock — unless a story-flag gate refuses.
func start_talk(player: Node) -> void:
	if required_flag != &"" and str(GameState.get_flag(required_flag)) != required_flag_value:
		if player != null and player.has_method(&"notify_toast"):
			player.notify_toast(PlayerText.TOAST_NOT_OPEN_FOR_BUSINESS, Color(1.0, 0.55, 0.4))
		return
	Restocker.notify_visit(self)  # a child Restocker in ON_VISIT mode tops the shop up before it opens
	ShopScreen.open_shop(self, player)

## Top the shop's stock back up to its authored baseline (stock_counts), adding ONLY the
## shortfall per item kind — never doubling what's there, never removing what the player sold in. A child
## Restocker calls this on a timer / on visit so a cleaned-out vendor replenishes.
func refill() -> void:
	if stock == null:
		return
	var baseline := {}
	for entry in stock_counts:
		if entry != null and _entry_unlocked(entry):  # WR-5: a rep-gated line refills only once the standing is met (and drops back out if it falls)
			CharacterInventory.accumulate_baseline(baseline, entry.item, entry.count)
	CharacterInventory.refill_to_baseline(stock, baseline)

## Always interactable — a shop is open for business even when its stock is empty (you can still sell).
func can_be_talked_to() -> bool:
	return true

## Hover readout: "Trade: <name>" (or just "Merchant" when unnamed).
func look_name() -> String:
	return PlayerText.trade_prompt(shop_name)
