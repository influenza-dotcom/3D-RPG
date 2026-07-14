class_name MoneyPurse
extends Node

## @system Economy
## @seam Mirrors `Character.money` into one derived `zorkmids` coin stack (1 unit = QUANTUM) in the player-only bag, self-heals it on any external bag touch, and register_mirror's it as a VIEW.
## @risk If GameState.capture stops skipping `Zorkmids.ITEM_ID`, the coin stack is double-persisted; on load sync() reconciles the reloaded tile to `money` so the wallet does NOT inflate (push-only mirror) — only the single-source invariant breaks.
## @risk If `is_mirrored` wrongly reads TRUE for a real loot source carrying a separate `money` float (corpse/container/pickpocket NPC), taking its coin tile ALSO debits that float -> that cash silently destroyed (F-C37 test guards it).
## @risk If the `_syncing` latch breaks, each external bag touch fires a redundant second sync + extra changed/autosave churn (idempotent set_item_count stops it short of infinite recursion).
## @test res://tests/test_money_purse.gd
## @test res://tests/test_loot_drop.gd
## Makes the player's zorkmids show up as a REAL item in the backpack. The wallet itself stays a fractional
## float on Character (`money`, the single source of truth the whole economy — merchants, pickups, bounties,
## save/load, death transfer — reads directly); this component MIRRORS that float into one coin `Item` stack
## in `character.inventory`, so the money is a genuine grid tile you can drag and drop like any other item.
##
## FRACTIONS: the inventory stores INTEGER stack counts, but zorkmids are fractional (0.01 quantum). So one
## unit of the coin stack = one Zorkmids.QUANTUM (0.01 zm): a 12.5-zorkmid wallet is a stack of 1250 units,
## rendered back as "12.5" via Zorkmids.fmt(count × QUANTUM) (grid_tile draws it). Integer stacks stay exact,
## the amount stays fractional, and the whole Tetris machinery is untouched.
##
## SELF-HEALING: money is authoritative, this stack is a derived VIEW. Two hooks keep them in lock-step:
##   * money_changed -> push the new amount into the stack (a sale, a kill bounty, a spend, a pickup).
##   * inventory.changed -> re-assert the stack back to the wallet, so ANY external touch of the coin pile is
##     corrected to match `money` (nothing but add_money may move money). A reentrancy latch stops our own
##     stack write from recursing through that second hook.
## The save layer EXCLUDES the coin stack (GameState.capture skips Zorkmids.ITEM_ID); money persists as the
## [player] wallet float and this rebuilds the stack from it on the next spawn/load.
##
## PLAYER-ONLY: built by Player._ready (an NPC wallet stays an abstract float that drops as loot — no coin tile
## in its bag). Wired like the other Character drop-in children (PassiveItemBuffs): `_host` is set BEFORE
## add_child so it's live the instant it enters the tree. Off-tree (no _ready) it simply does nothing.

var _host: Character = null   ## the owning character; set before add_child, exactly like PassiveItemBuffs._host
var _item: Item = null        ## the shared zorkmids template (resolved from ItemDb on first use)
var _syncing: bool = false    ## reentrancy latch — our own set_item_count fires inventory.changed

func _ready() -> void:
	if _host == null:
		return
	if not _host.money_changed.is_connected(_on_money_changed):
		_host.money_changed.connect(_on_money_changed)
	if _host.inventory != null and not _host.inventory.changed.is_connected(_on_inventory_changed):
		_host.inventory.changed.connect(_on_inventory_changed)
	# Mark the coin tile a MIRROR on the PLAYER's backpack (only the player has a MoneyPurse): CharacterInventory.
	# is_mirrored(coin) now reads true here and nowhere else, so a looting path debits a separate `money` float ONLY
	# for this genuine wallet mirror — an NPC / corpse / container coin tile (no purse -> never registered) stays
	# real loot and its pocket float is never double-spent (F-C37).
	if _host.inventory != null:
		_host.inventory.register_mirror(Zorkmids.ITEM_ID)
	sync()  # seed the coin tile from the wallet's current (already-finalized) value

## The shared zorkmids Item template (from the item registry), or null when none is registered — then this
## whole component no-ops and the economy just runs on the float, exactly as it did before the coin tile.
func _coin_item() -> Item:
	if _item == null:
		_item = ItemDb.item_by_id(Zorkmids.ITEM_ID)
	return _item

## Push the wallet's current amount into the coin stack: count = round(money / QUANTUM). The round() lands on the
## exact coin grid (money is already quantized), so the round-trip fmt(count × QUANTUM) reprints the wallet verbatim.
## ALSO sizes the stack's grid FOOTPRINT to a square that grows with the amount (a fat purse hogs backpack space) —
## the inventory only ever grows it into free cells, never evicting other items. Guards the write with the
## reentrancy latch so the inventory.changed it emits doesn't recurse.
func sync() -> void:
	if _host == null or _host.inventory == null:
		return
	var item := _coin_item()
	if item == null:
		return
	var coins := int(round(_host.money / Zorkmids.QUANTUM))
	var eco := GameSettings.economy
	var side := grid_side_for(_host.money, eco.money_bag_grid_min_side, eco.money_bag_grid_max_side, eco.money_bag_grid_side_per_sqrt_zm)
	_syncing = true
	_host.inventory.set_item_count(item, coins, side, side)
	_syncing = false

## The zorkmids stack's grid footprint SIDE (cells) for a wallet of `amount`: min_side + floor(per_sqrt·√amount),
## clamped to [min_side, max_side]. A whole-cell step (floored) so the pile jumps size tiers, not smoothly — e.g. at
## the shipped 0.2/1/3 knobs it's 1×1 under 25 zm, 2×2 to 100 zm, 3×3 above. Pure + static (explicit-arg, like
## MoneyBag's curves) so it's unit-testable without a live GameSettings.
static func grid_side_for(amount: float, min_side: int, max_side: int, per_sqrt: float) -> int:
	var a := maxf(0.0, amount)
	return clampi(min_side + int(floor(per_sqrt * sqrt(a))), min_side, maxi(min_side, max_side))

func _on_money_changed(_total: float, _delta: float) -> void:
	sync()

## Any other change to the bag (loot arriving, ammo spent, a stack dragged) — re-assert the coin pile to the
## wallet. Skipped while WE are the one writing (the latch), so this only fires for genuinely external touches.
func _on_inventory_changed() -> void:
	if _syncing:
		return
	sync()
