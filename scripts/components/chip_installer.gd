@tool
## @system Player Abilities
## @seam Paid-install chokepoint: a chip Item (installs_ability) -> permanent mechanic via can_grant guard -> charge -> consume -> unlock_mechanic + autosave.
## @risk Drop the pre-charge can_grant_mechanic guard (in install_carried + buy_and_install): a typo'd installs_ability then silently takes money + eats the chip for nothing.
## @risk Rename install_carried/install_fee: the DialogueManager/ChipInstallScreen has_method duck-type check fails silently and the 'Install' option just vanishes.
## @test res://tests/test_chip_install.gd
class_name ChipInstaller
extends LookAtInteractable


## Drop-in UPGRADE MECHANIC component. The player finds/buys MICROCHIP items (Item.installs_ability set, see
## resources/items/chip_*.tres) but holding one does nothing — they bring it HERE and pay zorkmids to have it
## INSTALLED, which permanently grants the encapsulated ability via Player.unlock_mechanic. Every player upgrade
## (wall_climb, grapple, slide, air_dash, laser_sight, fall_immunity) ships as one of these chips.
##
## Two ways to use it, exactly like Merchant / Healer:
##   1. STANDALONE (a workbench / a lone mechanic NPC with no Talkable): leave `standalone` on (default) — it
##      sits on the talk layer, so aiming at it and pressing Interact opens the install screen directly.
##   2. ON A DIALOGUE NPC: set `standalone` = false so the ray IGNORES it (the NPC's Talkable drives the
##      conversation); the dialogue then offers an "Install" option that opens THIS installer's screen.
##
## ECONOMY (all derived from the chip Item's `value`, no hardcoded price consts):
##   - INSTALL a chip the player already carries -> value × install_mult (floored at min_fee). Just labour.
##   - BUY & INSTALL a chip the mechanic stocks    -> value × buy_mult (the chip) PLUS the install fee, so
##     finding a chip yourself is always cheaper than buying it here (rewards exploration).
## Both consume the chip (it goes into the machine — never lingers in the bag) and route the charge through the
## player's wallet seam (add_money), then unlock_mechanic + autosave (a new ability is a milestone). Each path
## first verifies the grant resolves via Player.can_grant_mechanic (a typo'd installs_ability builds nothing) —
## so an unresolvable chip is refused with NO charge, never taking money for an ability it can't install.
##
## SETUP: drop it under the mechanic / workbench (or assign highlight_target), size its CollisionShape3D to the
## body you aim at (or set auto_fit_collider), fill `stock_counts` with the chips it sells, and tune the fees.
## DUCK-TYPED SURFACE: DialogueManager + ChipInstallScreen find this by `install_carried` + `install_fee`.

@export_group("Stock")
## The CHIPS this mechanic sells (buy & install in one stop) — one StockEntry per line (a chip Item + how many).
## Leave empty for an install-only mechanic (the player must find every chip in the world first).
@export var stock_counts: Array[StockEntry] = []
@export_group("Display")
## Shown on the look-at hover + the install screen title. Blank -> just "Mechanic".
@export var installer_name: String = ""
@export_group("Pricing")
## Fee to install a chip the player ALREADY CARRIES = chip.value × this (floored at min_fee). < 1.0 = cheaper
## than the chip's face value (you paid for the chip by finding it; this is just the labour).
@export var install_mult: float = 0.5
## Sale markup for a chip the mechanic STOCKS = chip.value × this. The buy-&-install total is this PLUS the
## install fee, so buying here always costs more than installing a chip you found.
@export var buy_mult: float = 1.25
## Minimum install fee (zorkmids), so a cheap chip still costs something to fit.
@export var min_fee: int = 10
@export_group("Behavior")
## STANDALONE (default): sit on the talk layer so Interact opens the install screen directly. Off -> DATA-ONLY:
## the ray won't detect us, and a dialogue NPC drives access via its "Install" option.
@export var standalone: bool = true

## The chips this mechanic sells — a child CharacterInventory, seeded from stock_counts in _ready (like Merchant).
var stock: CharacterInventory

## Editor warning: a standalone installer on a dialogue NPC steals the interaction ray from the NPC's Talkable.
func _get_configuration_warnings() -> PackedStringArray:
	if standalone and _on_dialogue_host():
		return PackedStringArray([
			"`standalone` is on but this ChipInstaller is a child of a dialogue NPC — its talk-layer hitbox steals the interaction ray from the NPC's Talkable. Set `standalone` = false and open the install screen from the dialogue's \"Install\" option.",
		])
	return PackedStringArray()

func _ready() -> void:
	if Engine.is_editor_hint():
		_editor_fit_hitbox()  # preview the auto-fit hitbox in-editor (resizes an existing collider; safe)
		return  # @tool: only _get_configuration_warnings runs in-editor; the stock build + hitbox setup is runtime-only
	# Standalone = a look-at hitbox on the talk layer (ray detects it); data-only installers sense nothing.
	collision_layer = TalkHelpers.TALK_LAYER if standalone else 0
	collision_mask = 0
	stock = CharacterInventory.new()
	stock.name = &"Stock"
	add_child(stock)
	_seed_stock(stock)
	_build_outline()  # look-at outline over the host's meshes (LookAtInteractable helper)
	if auto_fit_collider:
		_fit_hitbox_to_host()

## Seed `into` from the authored chip stock. Non-weapon items (chips are MISC) stack by shared template, so a
## line stocks `count` of the shared Item — matching Merchant's non-weapon branch. Split out for tests.
func _seed_stock(into: CharacterInventory) -> void:
	if into == null:
		return
	for entry in stock_counts:
		if entry == null or entry.item == null or entry.count <= 0:
			continue
		if not entry.item.is_upgrade_chip():
			continue  # only chips belong in an installer's stock; a stray non-chip line is ignored
		into.add(entry.item, entry.count)

# ---------------------------------------------------------------------------
# Pricing
# ---------------------------------------------------------------------------

## Zorkmids to INSTALL a chip the player already carries — value × install_mult, floored at min_fee. 0 for a
## null / non-chip / worthless item (the install screen won't offer those).
func install_fee(item: Item) -> int:
	if item == null or not item.is_upgrade_chip() or item.value <= 0.0:
		return 0
	return maxi(min_fee, int(round(item.value * install_mult)))

## Zorkmids to BUY & INSTALL a stocked chip the player doesn't have — the marked-up chip PLUS the install fee,
## so it's always dearer than installing a chip you found yourself.
func buy_and_install_cost(item: Item) -> int:
	if item == null or not item.is_upgrade_chip() or item.value <= 0.0:
		return 0
	return int(round(item.value * buy_mult)) + install_fee(item)

# ---------------------------------------------------------------------------
# What's installable right now (the two screen sections)
# ---------------------------------------------------------------------------

## Chips in the PLAYER's bag whose ability isn't installed yet — the "install your chips" section. One row per
## distinct ability (carrying two identical chips still shows one row; installing consumes one).
func installable_carried(player_node: Node) -> Array:
	var player := player_node as Player
	if player == null or player.inventory == null:
		return []
	return _distinct_installable(player.inventory.contents(), player, {})

## Stocked chips the player can BUY & install — a chip whose ability is neither installed NOR already carried
## (if you carry it, install it cheaply from the other section instead).
func installable_stock(player_node: Node) -> Array:
	var player := player_node as Player
	if player == null or stock == null:
		return []
	var carried := {}
	for it in installable_carried(player):
		carried[(it as Item).installs_ability] = true
	return _distinct_installable(stock.contents(), player, carried)

## Shared filter: from `entries` ({"item","count"} dicts) keep each chip whose ability the player hasn't
## installed and isn't in `exclude` (a set of ability ids), deduped by ability id. Returns Array[Item].
## INSTALLED (mechanic_installed), not ACTIVE (has_mechanic): an implant the player switched OFF on the
## Implants tab is still owned — offering its chip again would charge money just to flip it back on.
func _distinct_installable(entries: Array, player: Player, exclude: Dictionary) -> Array:
	var out: Array = []
	var seen := {}
	for e in entries:
		var item: Item = e.get("item")
		# value<=0 chip has a 0 fee (install_fee returns 0) -> would render a permanently-disabled '0 zm' row; drop
		# it here so install_fee's contract ("the install screen won't offer those") holds for BOTH sections.
		if item == null or not item.is_upgrade_chip() or item.value <= 0.0:
			continue
		var id := item.installs_ability
		if seen.has(id) or exclude.has(id) or player.mechanic_installed(id):
			continue
		seen[id] = true
		out.append(item)
	return out

# ---------------------------------------------------------------------------
# Transactions
# ---------------------------------------------------------------------------

## Install a chip the player is CARRYING: charge install_fee, CONSUME one chip from the bag, grant the ability.
## Guards: must be a chip, not already installed, actually held, and affordable. True on success.
func install_carried(item: Item, player_node: Node) -> bool:
	var player := player_node as Player
	if player == null or item == null or not item.is_upgrade_chip() or player.inventory == null:
		return false
	if player.mechanic_installed(item.installs_ability) or not player.inventory.has(item):
		return false  # INSTALLED guard: a switched-off implant is still owned — never charge to re-enable it
	# Resolve the grant BEFORE charging: a typo'd installs_ability (no ability script on disk for it, so
	# AbilityRegistry.can_build is false) would build nothing, yet the old flow still took money + consumed the chip.
	# Refuse with no charge instead.
	if not player.can_grant_mechanic(item.installs_ability):
		push_warning("ChipInstaller: chip '%s' installs unknown ability '%s' — install refused, no charge." % [item.label(), item.installs_ability])
		return false
	var cost := install_fee(item)
	if cost <= 0 or not player.can_pay(float(cost)):  # the ONE affordability predicate (cash -> savings -> armed rail)
		return false
	if not player.charge(float(cost)):      # routes through the payment seam -> HUD readout + floating -N
		return false
	player.inventory.remove(item, 1)        # the chip is consumed into the machine
	_grant(item, player)
	return true

## Buy a stocked chip AND install it in one step: charge buy_and_install_cost, CONSUME one from stock, grant the
## ability. The chip never enters the player's bag. Guards: chip, not installed, in stock, affordable.
func buy_and_install(item: Item, player_node: Node) -> bool:
	var player := player_node as Player
	if player == null or item == null or not item.is_upgrade_chip() or stock == null:
		return false
	if player.mechanic_installed(item.installs_ability) or not stock.has(item):
		return false  # same INSTALLED guard as install_carried — an owned-but-off implant is not for sale
	# Same pre-charge guard as install_carried: never take money for a chip whose ability can't be built.
	if not player.can_grant_mechanic(item.installs_ability):
		push_warning("ChipInstaller: chip '%s' installs unknown ability '%s' — install refused, no charge." % [item.label(), item.installs_ability])
		return false
	var cost := buy_and_install_cost(item)
	if cost <= 0 or not player.can_pay(float(cost)):  # the ONE affordability predicate (cash -> savings -> armed rail)
		return false
	if not player.charge(float(cost)):
		return false
	stock.remove(item, 1)                   # taken off the shelf and fitted straight in
	_grant(item, player)
	return true

## Shared install tail: grant the mechanic, persist the run (an unlock is a milestone, like UpgradePickup), and
## toast. Assumes the charge + chip-consume already happened — both transaction paths gate that charge on
## player.can_grant_mechanic() first, so _grant is only ever reached for an ability that actually resolves.
func _grant(item: Item, player: Player) -> void:
	player.unlock_mechanic(item.installs_ability)
	GameState.autosave(player)
	if player.has_method(&"notify_toast"):
		player.notify_toast(PlayerText.installed(item.label()), Color(0.5, 0.85, 1.0))

# ---------------------------------------------------------------------------
# Behaviour (talk-handler surface — used only when standalone, a direct-interact mechanic)
# ---------------------------------------------------------------------------

## Interact pressed while aimed at us: open the install screen for this mechanic.
func start_talk(player: Node) -> void:
	ChipInstallScreen.open_install(self, player)

## Always interactable — the mechanic is open for business even with an empty shelf (you can still install chips you found).
func can_be_talked_to() -> bool:
	return true

## Hover readout: "Upgrades: <name>" (or just "Mechanic" when unnamed).
func look_name() -> String:
	return PlayerText.chip_installer_prompt(installer_name)
