extends CanvasLayer
## @system Economy
## @seam `_take` on a zorkmids tile credits real `add_money` (never `transfer_to`) and debits the source's `money` float only if `is_mirrored(item)`.
## @risk Drop the `is_mirrored` guard: taking a live-pickpocket NPC's coin tile also debits its separate pocket float — that cash is destroyed silently.
## @risk `transfer_to`'ing a zorkmids tile (vs `add_money`) lets the player's purse trim it back to the wallet value — the take silently evaporates.
## @test res://tests/test_loot_drop.gd
## LootScreen — the transfer overlay for LOOTING a corpse or PICKPOCKETING a live NPC. Autoload,
## non-pausing, clones the InventoryScreen / OptionsMenu pattern (frees the mouse on open; player control
## is suppressed via the is_open() gates). Two columns: the SOURCE's items (click one to TAKE all of it
## into the player) and the PLAYER's items (shown for context — transfer is one-way in v1). Opened by
## LootableCorpse.start_talk (open_for) or Talkable.start_talk while sneaking (pickpocket).

signal opened
signal closed

const PANEL_MARGIN := 0.12  ## fraction of the screen left as a border around the panel (any resolution)
const _DEFAULT_HINT := PlayerText.LOOT_HINT  ## detail line when nothing is hovered

## How the SOURCE carries money — decides how cash is TAKEN / DEPOSITED (see _wallet_mode):
##   TILE  — money is a real zorkmids coin tile in the source inventory, looted like any other item (take =
##           click the tile via _take's zorkmids branch; deposit = add a tile via _deposit_coins_to_source).
##           No "Take N zm" button — cash is just an item. Used by EVERY cash source now:
##             * a STATIC source (corpse / dropped bag / container) seeds the tile up front (LootableCorpse.setup
##               / ItemContainer._seed_money_coins);
##             * a LIVE pickpocket target's Character.money float is FROZEN into a coin tile on open
##               (_freeze_live_wallet) and THAWED back into that float on close (_refloat_live_wallet) — so a
##               live NPC still stores its wallet as a plain float between robberies (it drops as loot on death,
##               funds its shopping), but loots as a clickable tile while you're in its pockets.
##   NONE  — no lootable cash at all (gear exchange with a following ally): depositing zorkmids is refused.
const WALLET_NONE := 0
const WALLET_TILE := 2  ## (1 was the retired FLOAT "Take N zm" button — a live wallet is a frozen tile now)

var _root: Control
var _title: Label
var _source_grid: GridInventoryView   ## the SOURCE bag as a grid (corpse / container / pockets) — click a tile to TAKE
var _player_grid: GridInventoryView   ## the PLAYER bag as a grid — click a tile to DEPOSIT into the source; drag to rearrange
var _detail: Label                    ## hovered-item breakdown shown under the grids (shared by both)
var _is_open := false
var _prev_mouse_mode: Input.MouseMode = Input.MOUSE_MODE_CAPTURED
var _player: Player = null
var _source_inv: CharacterInventory = null  ## the inventory being looted / pickpocketed
var _free_when_empty: Node = null           ## a corpse to free when emptied; null for a LIVE source (pickpocket)
var _source_heading: Label = null           ## the SOURCE column's heading, retitled per-open ("Corpse" / "Pockets")
## The LIVE pickpocket target whose Character.money float is FROZEN into a coin tile for the session
## (_freeze_live_wallet on open) and THAWED back into that float on close (_refloat_live_wallet). Non-null ONLY
## for a live pickpocket; null for a corpse / dropped bag / container (their cash is a permanent coin tile they
## already own) and for a gear exchange (no lootable cash). It's the one signal that tells _open/close to
## "re-mint this float as a tile / fold it back" instead of leaving an already-owned coin tile alone.
var _money_source: Node = null
## How the current source carries cash — WALLET_TILE / WALLET_NONE (see the consts above). Set per-open by _open;
## routes zorkmids deposits (stash a coin tile vs. refuse) and, for a live pickpocket, gates the freeze/thaw.
var _wallet_mode: int = WALLET_NONE
## The CHARACTER whose carry limit caps what the player can GIVE (deposit): a live exchange / pickpocket
## target. Null (corpses, containers) = unlimited dumping, as before. Read dynamically (carry_capacity).
var _capacity_owner: Node = null
## When true, the SOURCE's actively-WIELDED weapon (source_inv.equipped_item) can't be TAKEN — you can't lift
## a gun out of someone's hands. Set ONLY by pickpocket() (a live, unaware NPC); corpse loot, gear exchange,
## and containers leave it false, so a downed enemy's gun and an ally's swapped weapon stay takeable as before.
## Disarming a live NPC is still possible by lifting its AMMO (which it can't clutch shut) — see _take.
var _lock_equipped: bool = false
## The LIVE NPC being pickpocketed, or null for every other source (corpse / container / exchange). Non-null turns
## on the pickpocket RISK layer in _take (cash lifts through the coin-tile branch too now): a value/equipped steal-GATE plus a per-lift CAUGHT roll,
## both bent by the player's PICKPOCKET skill (PickpocketSettings + CharacterStats). Set by pickpocket(); cleared on close.
var _pickpocket_target: Node = null

func _ready() -> void:
	layer = 121                                  # above the HUD / inventory, peer of the modal overlays
	process_mode = Node.PROCESS_MODE_ALWAYS      # keep working regardless of any pause
	_build_ui()
	_root.visible = false

func is_open() -> bool:
	return _is_open

# ---------------------------------------------------------------------------------------------------
# Open / close
# ---------------------------------------------------------------------------------------------------

## Open the loot transfer for `corpse`, looting into `player`. Refuses to stack over another modal /
## dialogue, and bails safely on an invalid corpse or no player (start-menu / test safety).
func open_for(corpse: LootableCorpse, player: Node) -> void:
	if not is_instance_valid(corpse) or corpse.inventory == null:
		return
	var who := PlayerText.loot_title("LOOTING", corpse.corpse_name)
	# TILE mode: the corpse's cash is a real zorkmids tile in corpse.inventory (LootableCorpse.setup seeds it),
	# so there's no money-float source and no "Take N zm" button — you loot the coins by clicking the tile.
	_open(corpse.inventory, corpse, player, who, PlayerText.LOOT_CORPSE_HEADING, null, null, false, false, null, WALLET_TILE)

## Pickpocket a LIVE character: loot their inventory WITHOUT freeing them. Opened by Talkable.start_talk
## when the player is crouched and the NPC is unaware (off-guard).
func pickpocket(npc: Node, player: Node) -> void:
	if not is_instance_valid(npc):
		return
	var inv: Variant = npc.get(&"inventory")
	if not (inv is CharacterInventory):
		return
	var name_v: Variant = npc.get(&"display_name")
	var nm: String = name_v if name_v is String else ""
	var who := PlayerText.loot_title("PICKPOCKETING", nm)
	# The live NPC's wallet is liftable too, and PLANTING items on them respects their carry limit. The weapon in
	# their hands (equipped_item) stays PADLOCKED unless the player's PICKPOCKET clears the equipped threshold — a
	# master thief can pluck a drawn gun; a novice steals their ammo (or loots the corpse) to disarm instead. The
	# last arg marks this a live pickpocket, arming the steal-gate + caught roll in _take (see _pickpocket_target).
	var lock := not _player_can_lift_equipped(player)
	# TILE mode: the NPC's Character.money float is FROZEN into a real zorkmids coin tile in its pockets on open
	# (_freeze_live_wallet, gated on the money_source passed here), looted like any other item with the same caught
	# roll — no "Take N zm" button. Un-taken (or planted) coins THAW back into its float on close (_refloat_live_wallet).
	_open(inv, null, player, who, PlayerText.LOOT_POCKETS_HEADING, npc, npc, lock, false, npc, WALLET_TILE)

## EXCHANGE GEAR with a FOLLOWING ALLY (the "Exchange Gear" dialogue option, offered only to companions
## actively following you — the gate lives in DialogueManager._speaker_exchange_npc): the same two-way
## transfer screen, no sneaking required — equipment only (no wallet button; robbing a friend's cash isn't
## "exchanging"), and what you GIVE is capped by their carry capacity.
func exchange(npc: Node, player: Node) -> void:
	if not is_instance_valid(npc):
		return
	var inv: Variant = npc.get(&"inventory")
	if not (inv is CharacterInventory):
		return
	var name_v: Variant = npc.get(&"display_name")
	var nm: String = name_v if name_v is String else ""
	var who := PlayerText.loot_exchange_title(nm)
	_open(inv, null, player, who, PlayerText.LOOT_THEIR_GEAR_HEADING, null, npc)

## Open a persistent CONTAINER's inventory (a crate / chest / locker). Like open_for, but the container is
## NEVER freed when emptied — it's a fixture you can also deposit into. Opened by Container.start_talk.
func open_container(container: Node, player: Node) -> void:
	if not is_instance_valid(container):
		return
	var inv: Variant = container.get(&"inventory")
	if not (inv is CharacterInventory):
		return
	var name_v: Variant = container.get(&"container_name")
	var nm: String = name_v if name_v is String else ""
	var who := PlayerText.loot_title("LOOTING", nm) if not nm.is_empty() else PlayerText.LOOT_CONTAINER_TITLE
	# TILE mode: a crate stashes zorkmids as a real coin tile in its contents (ItemContainer seeds the authored
	# `money` in _seed_money_coins), looted like any other item — no money-float source, no "Take N zm" button.
	# container_source=true -> the roomier container grid (a fixed crate stashes more than an NPC can carry),
	# unlike a corpse / dropped bag, which renders at the player's grid size.
	_open(inv, null, player, who, PlayerText.LOOT_CONTAINER_HEADING, null, null, false, true, null, WALLET_TILE)

## Shared open: bind the source + player inventories, free the mouse, show the title + columns. Refuses to
## stack over another modal / dialogue, and bails on no source / no player.
func _open(source_inv: CharacterInventory, free_when_empty: Node, player: Node, title: String, source_heading: String, money_source: Node = null, capacity_owner: Node = null, lock_equipped: bool = false, container_source: bool = false, pickpocket_target: Node = null, wallet_mode: int = WALLET_NONE) -> void:
	# Refuse to stack over another modal / dialogue — derives from the shared InputManager registry (the old inline
	# list omitted Stats/Reputation/Journal/ChipInstall/Chess); any_modal_open(self) excludes this screen. T1.
	if _is_open or DialogueManager.is_active() or InputManager.any_modal_open(self):
		return
	if source_inv == null:
		return
	_player = player as Player
	if not is_instance_valid(_player) or _player.inventory == null:
		return
	_source_inv = source_inv
	_free_when_empty = free_when_empty
	_money_source = money_source
	_wallet_mode = wallet_mode
	_capacity_owner = capacity_owner
	_lock_equipped = lock_equipped
	_pickpocket_target = pickpocket_target  # non-null (a live pickpocket) arms the steal-gate + caught roll in _take
	# Tell the SOURCE grid to render its wielded weapon as LOCKED (a padlock, un-clickable-to-take) when this
	# session locks it — a live pickpocket. Cleared for every other source (corpse / container / exchange).
	_source_grid.lock_equipped = lock_equipped
	# Give the SOURCE a spatial grid (lazily, once) so it renders as a grid alongside the player's bag — the
	# Tetris-loot view. NPC-derived sources (a corpse / dropped bag copy, or a gear-exchange partner) get the
	# PLAYER's grid size, so an NPC's inventory and the bag it drops match the player's exactly. A live pickpocket
	# target is ALREADY grid-enabled at that size from NPC._ready, so this guard leaves it untouched. Only a
	# persistent CONTAINER (crate / chest) gets the larger container grid (roomier stash). Guarded so re-opening a
	# container keeps its layout; the player's own bag is grid-enabled by Player._ready.
	if not source_inv.grid_enabled():
		if container_source:
			source_inv.enable_grid(GameSettings.inventory.container_grid_cols, GameSettings.inventory.container_grid_rows)
		else:
			source_inv.enable_grid(GameSettings.inventory.grid_cols, GameSettings.inventory.grid_rows)
	_source_grid.bind(source_inv)
	# A live pickpocket's wallet float is minted as a coin tile NOW (money_source non-null + already grid-bounded),
	# so the source column renders it as a tile from the first _rebuild. Done BEFORE _bind(true) so the add()'s
	# `changed` isn't yet connected (no premature rebuild). Corpses / containers / exchange (money_source null) no-op.
	_freeze_live_wallet()
	_player_grid.bind(_player.inventory)
	_bind(true)
	_is_open = true
	_prev_mouse_mode = ModalMenu.grab_mouse()
	# Runtime re-titles must route through title_text — make_title only cases its constructor argument, and the
	# corpse/NPC names baked into `title` are designer-authored mixed case ("LOOTING Bandit" pre-fix).
	_title.text = MenuStyle.title_text(title)
	if _source_heading != null:
		_source_heading.text = MenuStyle.title_text(source_heading)  # headings share the skin's title casing
	_detail.text = _DEFAULT_HINT
	_rebuild()
	_root.visible = true
	opened.emit()

func close() -> void:
	if not _is_open:
		return
	_bind(false)
	# Thaw a pickpocketed NPC's frozen wallet back into its money float (any un-taken + planted coins), stripping
	# the temporary tile — AFTER _bind(false) so the remove()'s `changed` doesn't trigger a rebuild mid-close.
	_refloat_live_wallet()
	_is_open = false
	_root.visible = false
	ModalMenu.restore_mouse(_prev_mouse_mode)
	# Leave the source's grid ON at close. Every NPC is permanently bounded to the player's grid from NPC._ready,
	# so a pickpocket / exchange target keeps that cap (it isn't a per-session view anymore); a corpse is freed on
	# empty and a persistent container WANTS its layout to persist. (Older builds un-gridded a live source here
	# because only the player's bag was bounded — NPCs now carry the same bounded grid the player does.)
	_source_grid.lock_equipped = false  # the weapon-lock is per-session; the next open re-sets it
	_source_grid.bind(null)  # drop the bound inventories so the views never hold a stale ref after close
	_player_grid.bind(null)
	_source_inv = null
	_free_when_empty = null
	_money_source = null
	_wallet_mode = WALLET_NONE
	_capacity_owner = null
	_lock_equipped = false
	_pickpocket_target = null
	_player = null
	closed.emit()

## (Dis)connect both inventories' `changed` so the two columns refresh on any transfer. is_instance_valid
## guards a corpse freed mid-loot; Godot also auto-drops the connection when a node frees.
func _bind(on: bool) -> void:
	var invs := [
		_source_inv if is_instance_valid(_source_inv) else null,
		_player.inventory if is_instance_valid(_player) else null,
	]
	for inv in invs:
		if inv == null:
			continue
		if on and not inv.changed.is_connected(_on_changed):
			inv.changed.connect(_on_changed)
		elif not on and inv.changed.is_connected(_on_changed):
			inv.changed.disconnect(_on_changed)

func _on_changed() -> void:
	if _is_open:
		_rebuild()

func _unhandled_input(event: InputEvent) -> void:
	# Close on the SAME Interact key that opens it (the ray consumes the OPENING press, so this only fires on
	# a later press — see ray_cast.gd, which skips interacting while we're open), or on Esc.
	if _is_open and (event.is_action_pressed(InputManager.action_pickup) or event.is_action_pressed(&"ui_cancel")):
		close()
		get_viewport().set_input_as_handled()

# ---------------------------------------------------------------------------------------------------
# Transfer + lists
# ---------------------------------------------------------------------------------------------------

## Take ALL of `item` from the corpse into the player. When the corpse is fully drained (no items AND no
## wallet left), close + free it — nothing left to loot.
func _take(item: Item) -> void:
	if not is_instance_valid(_source_inv) or not is_instance_valid(_player) or _player.inventory == null:
		return
	# You can't lift the weapon a live NPC is actively HOLDING (pickpocket only — see _lock_equipped). Refuse the
	# take with a hint; ammo, wallet, and everything else in their pockets is still fair game.
	if _equipped_locked(item, _source_inv, _lock_equipped):
		if _player.has_method(&"notify_toast"):
			_player.notify_toast(PlayerText.TOAST_CANT_LIFT_EQUIPPED, Color(0.85, 0.85, 0.85))
		return
	# PICKPOCKET RISK (a live target only; corpse/container/exchange skip this via a null _pickpocket_target).
	# First a steal-GATE: too-valuable gear (over the skill-scaled allowance) can't be lifted unnoticed. Then a
	# per-lift CAUGHT roll — on a hit the NPC notices, turns hostile, and the pockets slam shut. Both bend with the
	# player's pickpocket skill (PickpocketSettings + CharacterStats), so a master thief lifts more, caught less.
	if is_instance_valid(_pickpocket_target):
		var sheet: CharacterStats = _player.stats_or_default() if _player.has_method(&"stats_or_default") else null
		if not _pickpocket_can_lift(item, _source_inv.equipped_item, sheet, GameSettings.pickpocket):
			if _player.has_method(&"notify_toast"):
				_player.notify_toast(PlayerText.TOAST_TOO_VALUABLE_TO_LIFT, Color(0.85, 0.85, 0.85))
			return
		if _pickpocket_caught():
			_on_pickpocket_caught()
			return
	# A zorkmids stack is WALLET MONEY wearing an item costume — the coin tile a corpse / container carries
	# (LootableCorpse.setup / ItemContainer._seed_money_coins), a live pickpocket's wallet float frozen into a tile
	# for the session (_freeze_live_wallet), or the player's own MoneyPurse mirror. transfer_to would hand the player
	# a stack their own purse then trims back to their wallet value — the taken amount silently evaporates. Convert it
	# to real money instead. The extra `money`-float debit below is ONLY correct when the source's coin tile is a
	# genuine MIRROR of a live wallet float (a MoneyPurse owner — only the player, who is never a loot source). A
	# corpse / container / pickpocket NPC has NO purse, so is_mirrored(item) (F-C12) reads false and its float is left
	# alone — for a pickpocket NPC the float is already 0 anyway (frozen into this tile), thawed back only on close.
	if item.id == Zorkmids.ITEM_ID:
		var count := _source_inv.count_of(item)
		if count <= 0:
			return
		var amt := float(count) * Zorkmids.QUANTUM
		_source_inv.remove(item, count)
		if _money_source != null and is_instance_valid(_money_source) and _source_inv.is_mirrored(item):
			var raw: Variant = _money_source.get(&"money")
			if raw is float or raw is int:
				_money_source.set(&"money", maxf(0.0, float(raw) - amt))
		_player.add_money(amt)
		_maybe_free_drained_corpse()
		return
	var want := _source_inv.count_of(item)
	var moved := _source_inv.transfer_to(_player.inventory, item, want)
	# A bounded (Tetris) bag may not fit everything — what didn't fit stays on the source (transfer_to rolls it
	# back). Say so rather than letting the click look like it silently did nothing.
	if moved < want and _player.has_method(&"notify_toast"):
		_player.notify_toast(PlayerText.TOAST_NO_ROOM_FOR_ALL, Color(0.85, 0.85, 0.85))
	_maybe_free_drained_corpse()

## PICKPOCKET wallet FREEZE: a live target's cash is its Character.money float; on open we mint it as a real
## zorkmids COIN TILE in its pockets so it loots exactly like a corpse's / container's (a clicked tile — no
## "Take N zm" button). One unit = one QUANTUM, so a fractional wallet stays exact. The whole float becomes one
## 1×1 tile and the float zeroes to its (quantum-rounding, ~0) residual; the coins THAW back on close
## (_refloat_live_wallet). set_item_count — not add() — is used so that even a FULL pocket keeps the tile
## (unplaced but rendered in the grid's overflow strip and still clickable) instead of add() silently dropping it;
## it folds in any coins already in the bag (normally none — an NPC's cash is a float) so nothing is clobbered.
## No-op unless there's a live wallet owner (_money_source) holding positive cash and a registered coin Item, so
## corpses / containers / exchange (money_source null) never re-mint — they already own (or lack) their coin tile.
func _freeze_live_wallet() -> void:
	if _money_source == null or not is_instance_valid(_money_source) or not is_instance_valid(_source_inv):
		return
	var raw: Variant = _money_source.get(&"money")
	if not (raw is float or raw is int):
		return
	var money := float(raw)
	if money <= 0.0:
		return
	var coin := ItemDb.item_by_id(Zorkmids.ITEM_ID)
	if coin == null:
		return
	var want := int(round(money / Zorkmids.QUANTUM))
	_source_inv.set_item_count(coin, want + _source_inv.count_of(coin), 1, 1)  # whole wallet as one 1×1 tile (kept even if unplaced)
	_money_source.set(&"money", maxf(0.0, money - float(want) * Zorkmids.QUANTUM))  # tile now IS the wallet; float zeroes to its residual

## PICKPOCKET wallet THAW (the inverse of _freeze_live_wallet): on close, fold any zorkmids coin tile still in the
## pickpocketed NPC's pockets — un-taken coins PLUS anything the player planted — back into its Character.money
## float, then strip the tile. So a live NPC carries its cash as a plain float again the moment the screen closes
## (its wallet drops as loot on death, funds its shopping, etc.). No-op unless a live wallet owner (_money_source)
## is set — corpses / containers keep their coin tile permanently. Uses set() (not add_money): the value is already
## quantum-aligned and this is transient bookkeeping, not a gameplay credit that should fire money_changed.
func _refloat_live_wallet() -> void:
	if _money_source == null or not is_instance_valid(_money_source) or not is_instance_valid(_source_inv):
		return
	var coin := ItemDb.item_by_id(Zorkmids.ITEM_ID)
	if coin == null:
		return
	var units := _source_inv.count_of(coin)
	if units <= 0:
		return
	var raw: Variant = _money_source.get(&"money")
	var base := float(raw) if raw is float or raw is int else 0.0
	_source_inv.remove(coin, units)
	_money_source.set(&"money", maxf(0.0, base + float(units) * Zorkmids.QUANTUM))

## The source's wallet, type-guarded: a vanished source, or one without a `money` property at all
## (a plain container / a test stub), reads as 0 instead of crashing float() on a null get().
func _source_money() -> float:
	if _money_source == null or not is_instance_valid(_money_source):
		return 0.0
	var raw: Variant = _money_source.get(&"money")
	return float(raw) if raw is float or raw is int else 0.0

## True once the source holds NOTHING — bag empty and no wallet cash left on the money source.
func _source_drained() -> bool:
	if is_instance_valid(_source_inv) and not _source_inv.is_empty():
		return false
	if _source_money() > 0.0:
		return false
	return true

## Close + free a fully drained temporary CORPSE (free_when_empty != null). A persistent CONTAINER (and a
## live pickpocket source) has free_when_empty == null: it STAYS OPEN showing "(empty)" so you can keep
## depositing — close it manually with Esc / the interact key.
func _maybe_free_drained_corpse() -> void:
	if not _source_drained():
		return
	var emptied := _free_when_empty
	if emptied != null:
		close()
		# A standalone corpse cleans itself up here; a host that owns the cleanup keeps it: a skeleton-attached
		# corpse is faded by its Ragdoll, a bag-attached one is freed (together with the bag) by its LootBag.
		var host := emptied.get_parent()
		if is_instance_valid(emptied) and not (host is Ragdoll or host is LootBag):
			emptied.queue_free()

## Deposit `item` from the player INTO the source (the reverse of _take) — the whole stack, except that a
## LIVE receiver (exchange / pickpocket-planting) takes only what fits under its CARRY CAPACITY: NPCs can't
## be given more than they can carry. Corpses / containers have no owner and accept anything, as before.
## Depositing the wielded weapon is allowed: you fall back to bare fists once it leaves the bag.
func _deposit(item: Item) -> void:
	if not is_instance_valid(_source_inv) or not is_instance_valid(_player) or _player.inventory == null:
		return
	# The player's coin tile IS the wallet (MoneyPurse mirrors `money` into a zorkmids stack): transfer_to would
	# move the mirror while the wallet float stays put, and the purse re-mints the full pile next frame -- an
	# infinite money dupe into any container / corpse / companion. So cash is never transfer_to'd: a TILE source
	# (corpse / container / pickpocketed pocket) gets a real coin tile stashed (debited from the player's wallet);
	# a NONE source (gear exchange with an ally) refuses it — gifting / robbing a friend's wallet isn't
	# "exchanging". (There's no float-deposit path anymore: a live pickpocket wallet is a coin tile for the whole
	# session — frozen on open, thawed on close — so planting cash on it just adds to that tile.)
	if item.id == Zorkmids.ITEM_ID:
		if _wallet_mode == WALLET_TILE:
			_deposit_coins_to_source()
		elif _player.has_method(&"notify_toast"):
			_player.notify_toast(PlayerText.TOAST_NO_ZORKMID_POCKET, Color(0.85, 0.85, 0.85))
		return
	var count := _player.inventory.count_of(item)
	if _capacity_owner != null and is_instance_valid(_capacity_owner):
		# .get(), not a direct access: the owner is duck-typed, and a receiver WITHOUT a
		# carry_capacity property (a stub / non-Character) is simply uncapped, like a container.
		var cap: Variant = _capacity_owner.get(&"carry_capacity")
		if cap is float or cap is int:
			count = _fits_under_capacity(item, count, _source_inv.total_weight(), float(cap))
			if count <= 0:
				if _player.has_method(&"notify_toast"):
					_player.notify_toast(PlayerText.TOAST_THEY_CANT_CARRY_MORE, Color(0.85, 0.85, 0.85))
				return
	# Depositing the weapon you're WIELDING is allowed: the transfer clears the backpack's equipped_item,
	# which fires equipped_item_lost -> the player falls back to bare fists. No need to swap first.
	var moved := _player.inventory.transfer_to(_source_inv, item, count)
	# The source now has a spatial grid (T4) — it can run out of room. transfer_to rolls back what didn't fit;
	# say so rather than letting a click look like it did nothing.
	if moved < count and _player.has_method(&"notify_toast"):
		_player.notify_toast(PlayerText.TOAST_NO_ROOM_IN_THERE, Color(0.85, 0.85, 0.85))
	# Planting a WEAPON on a live receiver that can never use it (a civilian NPC — no weapon hub) is silently
	# futile: it enters their bag but they can't draw it (the combat rearm only equips a backpack weapon for a
	# hub-carrying combatant, and even that only once ALERTED). Warn so the player isn't misled into thinking
	# they armed the target. The deposit still STANDS — you can stash / plant items on a civilian for other
	# reasons; it just won't put a gun in their hands. A disarmed COMBATANT reads can_wield_weapons() == true,
	# so no warning there (it WILL draw the planted gun on its next combat tick — that path is unchanged).
	if moved > 0 and item.is_weapon() and _plant_target_cannot_wield() and _player.has_method(&"notify_toast"):
		_player.notify_toast(PlayerText.TOAST_THEY_CANT_USE_WEAPON, Color(0.85, 0.85, 0.85))

## TILE-mode deposit: stash the player's whole wallet into the source (corpse / container / pickpocketed pocket)
## as a real zorkmids COIN TILE. add() tops the source's existing coin tile (no new cell) or claims a fresh 1×1;
## a full bounded source may only take part, so we debit ONLY what actually landed and leave the shortfall in the
## player's wallet (no cash ever vanishes into a full bag). _source_inv.add emits `changed`, which rebuilds both
## grids. For a live pickpocket pocket the stashed coins thaw into the NPC's money float on close (_refloat_live_wallet).
func _deposit_coins_to_source() -> void:
	if not is_instance_valid(_player) or not is_instance_valid(_source_inv):
		return
	var amount := snappedf(maxf(0.0, _player.money), Zorkmids.QUANTUM)
	if amount <= 0.0:
		if _player.has_method(&"notify_toast"):
			_player.notify_toast(PlayerText.TOAST_NO_ZORKMIDS_TO_DEPOSIT, Color(0.85, 0.85, 0.85))
		return
	var coin := ItemDb.item_by_id(Zorkmids.ITEM_ID)
	if coin == null:  # zorkmids unregistered (shouldn't happen — the player wouldn't have a coin tile either)
		if _player.has_method(&"notify_toast"):
			_player.notify_toast(PlayerText.TOAST_NO_ZORKMID_POCKET, Color(0.85, 0.85, 0.85))
		return
	var want := int(round(amount / Zorkmids.QUANTUM))
	var added := _source_inv.add(coin, want)
	if added <= 0:
		if _player.has_method(&"notify_toast"):
			_player.notify_toast(PlayerText.TOAST_NO_ROOM_IN_THERE, Color(0.85, 0.85, 0.85))
		return
	_player.add_money(-float(added) * Zorkmids.QUANTUM)  # debit only what fit; the rest stays in the wallet
	if added < want and _player.has_method(&"notify_toast"):
		_player.notify_toast(PlayerText.TOAST_DEPOSITED_WHAT_FIT, Color(0.85, 0.85, 0.85))
	_rebuild()

## True when the live deposit receiver is a Character that can NEVER wield a weapon (a CIVILIAN NPC with no
## weapon hub), so planting a gun on it can't arm it. Duck-typed: a corpse / container leaves _capacity_owner
## null (returns false — stashing a weapon there is normal and unwarned), and any receiver that doesn't expose
## can_wield_weapons() is likewise left alone. Only a live NPC that explicitly reports it can't wield trips the
## warning; a disarmed COMBATANT (can_wield_weapons() == true) does not.
func _plant_target_cannot_wield() -> bool:
	if _capacity_owner == null or not is_instance_valid(_capacity_owner):
		return false
	if not _capacity_owner.has_method(&"can_wield_weapons"):
		return false
	return not _capacity_owner.can_wield_weapons()

## How many of `item` (holding `have`) still FIT under `capacity` for a receiver already carrying
## `load_weight` — the give-cap math, pure + static for the tests. Weightless items always fit; an
## already-over-capacity receiver takes nothing.
static func _fits_under_capacity(item: Item, have: int, load_weight: float, capacity: float) -> int:
	if item == null or have <= 0:
		return 0
	if item.weight <= 0.0:
		return have
	return clampi(int(floor((capacity - load_weight) / item.weight)), 0, have)

## True when `item` is the SOURCE's actively-wielded weapon AND this session locks it (a live pickpocket): the
## take-guard for "you can't lift a gun out of their hands". Pure + static so the rule is unit-testable off-tree.
## Corpse loot / gear exchange / containers pass lock_equipped=false, so nothing is ever locked there; a live
## NPC's un-drawn spare weapon (equipped_item is only the ONE in hand) and its ammo also stay takeable.
static func _equipped_locked(item: Item, source_inv: CharacterInventory, lock_equipped: bool) -> bool:
	return lock_equipped and item != null and source_inv != null and item == source_inv.equipped_item

## True if `player`'s LARCENY skill clears the equipped-weapon threshold — so a live pickpocket may lift the
## weapon the target is actively holding (below it, the weapon stays padlocked). Duck-typed + baseline-safe: a
## sheet-less player reads larceny 0, gated out unless the threshold itself is 0.
static func _player_can_lift_equipped(player: Node) -> bool:
	if player == null or not player.has_method(&"stats_or_default"):
		return false
	return player.stats_or_default().get_stat(&"larceny") >= GameSettings.pickpocket.equipped_pickpocket_threshold

## PICKPOCKET steal-GATE (pure, so it unit-tests off-tree): can this item be lifted from a live target given the
## player's `stats` and the encounter `settings`? Loose cash and valueless junk always pocket; the weapon in their
## HANDS (equipped_item) needs larceny >= equipped_threshold; anything else must sit under the skill-scaled value
## allowance (pickpocket_value_allowance). A null item / sheet / settings fails safe (nothing lifted).
static func _pickpocket_can_lift(item: Item, equipped_item: Item, stats: CharacterStats, settings: PickpocketSettings) -> bool:
	if item == null or stats == null or settings == null:
		return false
	if equipped_item != null and item == equipped_item:
		return stats.get_stat(&"larceny") >= settings.equipped_pickpocket_threshold
	if item.id == Zorkmids.ITEM_ID or item.value <= 0.0:
		return true  # loose cash / worthless scraps are always pocketable
	return item.value <= stats.pickpocket_value_allowance(settings.base_value_allowance, settings.value_allowance_per_point)

## The pickpocket SUCCESS chance (0..100 %) of lifting `item` unnoticed, or -1 when it CAN'T be lifted at all (over
## the value allowance, or the drawn weapon below the equipped threshold — the steal-GATE refuses it). Success is
## 1 - pickpocket_catch_chance: the odds the per-lift CAUGHT roll in _take does NOT fire, so the hover number and the
## take use the exact same math. `mod` folds an active larceny status buff. Pure + static (value args), so it
## unit-tests off-tree alongside _pickpocket_can_lift; a null item / sheet / settings reads -1 (nothing liftable).
static func _pickpocket_success_percent(item: Item, equipped_item: Item, stats: CharacterStats, settings: PickpocketSettings, mod: float = 0.0) -> int:
	if not _pickpocket_can_lift(item, equipped_item, stats, settings):
		return -1
	var catch := stats.pickpocket_catch_chance(settings.base_catch_chance, settings.catch_chance_per_point, mod)
	return int(round(clampf(1.0 - catch, 0.0, 1.0) * 100.0))

## Roll the per-lift CAUGHT check against the player's larceny skill (+ an active larceny buff). RNG lives HERE
## (a gameplay roll), never in CharacterStats — the pure formula only returns the probability, keeping it testable.
## No player / no sheet -> never caught (fail safe).
func _pickpocket_caught() -> bool:
	if not is_instance_valid(_player) or not _player.has_method(&"stats_or_default"):
		return false
	var settings := GameSettings.pickpocket
	var mod: float = _player.status_stat_modifier(&"larceny") if _player.has_method(&"status_stat_modifier") else 0.0
	var chance := _player.stats_or_default().pickpocket_catch_chance(settings.base_catch_chance, settings.catch_chance_per_point, mod)
	return randf() < chance

## Caught in the act: toast the player, slam the pockets shut, and PROVOKE the NPC (it turns hostile + the faction
## sours, exactly like being shot). Then react_to_caught_theft makes the victim SPIN AROUND to face the thief and
## engage, latches the one-strike lockout (no re-picking this mark — Talkable.pickpocket_allowed), and rallies
## nearby enemies to turn and LOOK. provoke() runs BEFORE the reaction so the victim reads as hostile-to-player when
## it tries to lock the thief as its target. Capture target + player BEFORE close() nulls them out.
func _on_pickpocket_caught() -> void:
	var target := _pickpocket_target
	var player := _player
	if is_instance_valid(player) and player.has_method(&"notify_toast"):
		player.notify_toast(PlayerText.TOAST_CAUGHT, Color(1.0, 0.4, 0.35))
	close()
	if not is_instance_valid(target):
		return
	if target.has_method(&"provoke"):
		target.provoke(player)
	if target.has_method(&"react_to_caught_theft"):
		target.react_to_caught_theft(player, GameSettings.pickpocket.caught_witness_radius)
	elif target.has_method(&"mark_pickpocket_caught"):
		target.mark_pickpocket_caught()  # non-NPC / stub fallback: at least latch the one-strike lockout

func _rebuild() -> void:
	# Re-read both grids (the source you TAKE from, your bag you DEPOSIT from). The grid views render the tiles;
	# the transfer happens on a tile click (wired in _open: source -> _take, player -> _deposit). Cash rides INSIDE
	# the source grid as a zorkmids coin tile now — every cash source is TILE mode — so there's no wallet button.
	_source_grid.refresh()
	_player_grid.refresh()

## Click a SOURCE tile -> take that whole stack into the player (the grid view emits activate_requested).
func _on_source_activate(item: Item) -> void:
	if item != null:
		_take(item)

## Click one of YOUR tiles -> deposit that stack into the source.
func _on_player_activate(item: Item) -> void:
	if item != null:
		_deposit(item)

## The pickpocket odds line shown atop the hover tooltip while robbing a LIVE target: "72% to lift unnoticed", or a
## reason it can't be lifted at all (too valuable / the weapon in their hands). Empty for every non-pickpocket source
## (corpse / container / exchange). Only ever called for a SOURCE-side hover (see _on_hover's is_source gate) — you
## can't steal your own deposit-side goods, and a shared Item template can't be told apart by identity alone.
func _pickpocket_hover_line(item: Item) -> String:
	if item == null or not is_instance_valid(_pickpocket_target) or not is_instance_valid(_source_inv):
		return ""
	if not is_instance_valid(_player) or not _player.has_method(&"stats_or_default"):
		return ""
	var sheet: CharacterStats = _player.stats_or_default()
	var settings := GameSettings.pickpocket
	var equipped := _source_inv.equipped_item
	var mod: float = _player.status_stat_modifier(&"larceny") if _player.has_method(&"status_stat_modifier") else 0.0
	var pct := _pickpocket_success_percent(item, equipped, sheet, settings, mod)
	if pct < 0:
		# Un-liftable: distinguish the drawn weapon (padlocked below the equipped threshold) from over-value gear.
		return PlayerText.TOAST_CANT_LIFT_EQUIPPED if item == equipped else PlayerText.TOAST_TOO_VALUABLE_TO_LIFT
	return PlayerText.pickpocket_success(pct)

## Either grid's hover changed -> show that item's breakdown under the grids (or the click/drag hint). The holder
## inventory (for a weapon's spare-ammo line) is whichever bag actually holds the item. `is_source` (bound per grid
## in _build_ui) is TRUE only for the SOURCE column, gating the pickpocket odds line to items you'd actually steal.
func _on_hover(item: Item, is_source: bool = false) -> void:
	if item == null:
		_detail.text = _DEFAULT_HINT
		return
	var holder: CharacterInventory = null
	if is_instance_valid(_player) and _player.inventory != null and _player.inventory.has(item):
		holder = _player.inventory
	elif is_instance_valid(_source_inv):
		holder = _source_inv
	var body := ItemInfo.tooltip(item, holder)
	# While robbing a LIVE target, PREPEND the odds of lifting THIS item unnoticed — the same steal-gate + caught
	# roll the take actually faces (see _take). Prepended (not appended) so it stays visible even if the rest of a
	# long weapon tooltip clips off the fixed-height footer. Only on the SOURCE side (is_source): you don't steal
	# your own deposit-side goods, and a shared coin/ammo template can't be told apart by identity. Empty for every
	# non-pickpocket source, so those are unchanged.
	var pp := _pickpocket_hover_line(item) if is_source else ""
	_detail.text = ("%s\n%s" % [pp, body]) if not pp.is_empty() else body

# ---------------------------------------------------------------------------------------------------
# UI construction
# ---------------------------------------------------------------------------------------------------

func _build_ui() -> void:
	_root = Control.new()
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP  # eat clicks so nothing falls through to gameplay behind
	MenuStyle.apply(_root)  # shared menu Theme (panel/buttons/tooltips/fonts) — reskin via resources/ui/menu_skin.tres
	add_child(_root)

	_root.add_child(MenuStyle.make_dim())

	var panel := PanelContainer.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	panel.anchor_left = PANEL_MARGIN
	panel.anchor_top = PANEL_MARGIN
	panel.anchor_right = 1.0 - PANEL_MARGIN
	panel.anchor_bottom = 1.0 - PANEL_MARGIN
	panel.offset_left = 0
	panel.offset_top = 0
	panel.offset_right = 0
	panel.offset_bottom = 0
	_root.add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", MenuStyle.skin.content_separation)  # shared rhythm across every panel screen
	panel.add_child(vbox)

	# The tracked title — a plain full-width header, reassigned per-open (_open sets _title.text via title_text).
	# Cash now rides inside the SOURCE grid as a zorkmids coin tile (no "Take N zm" button), so the title no longer
	# needs an HBox row to share width with a wallet button.
	_title = MenuStyle.make_title(PlayerText.LOOT_TITLE)
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_child(_title)

	# The two grids sit SIDE-BY-SIDE — source column left, your bag right. The old vertical stack dated from a
	# stale 396px-wide-canvas assumption; at the REAL 792x444 canvas no cell size fits the widest source (a 10x8
	# container grid) PLUS the player's grid stacked (the audit shots showed ~1.5 rows of each — ~80% of loot
	# hidden). Half the panel (~281px) fits 10 columns at 28px by width, and the height budget wired in
	# _build_grid_section fits all 8 rows at 22px cells — both grids whole, zero scrollbars, at the design canvas.
	# (Corpses / dropped bags / NPCs render at the player's smaller grid, so they fit with room to spare.)
	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", MenuStyle.skin.content_separation)
	columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(columns)
	var headers: Array = []
	_source_grid = _build_grid_section(columns, PlayerText.LOOT_SOURCE_HEADING, headers)
	_source_heading = headers[0]  # remember the SOURCE heading so _open can retitle it ("Corpse" / "Pockets" / ...)
	_player_grid = _build_grid_section(columns, PlayerText.LOOT_YOU_HEADING, headers)
	_source_grid.activate_requested.connect(_on_source_activate)
	# .bind(true/false) APPENDS an is_source flag after the signal's `item` arg, so _on_hover knows WHICH grid the
	# cursor is over — the pickpocket odds line must show only on the SOURCE side, and can't be inferred from the
	# item alone (a shared Item template like the zorkmids coin / ammo lives in BOTH bags at once).
	_source_grid.hover_changed.connect(_on_hover.bind(true))
	_player_grid.activate_requested.connect(_on_player_activate)
	_player_grid.hover_changed.connect(_on_hover.bind(false))

	# Detail line under both grids: the hovered item's breakdown, else the click/drag hint. Lives inside a
	# FIXED-HEIGHT clip host (same construct as InventoryScreen's footer): a min height on the Label alone
	# doesn't stop an over-long tooltip — a Label reports its full wrapped height as its min, so the VBox grew
	# and shrank the EXPAND_FILL grid columns above, juddering them on hover. A plain Control host with
	# clip_contents keeps the footer exactly this tall (anchored children don't feed its minimum), so a long
	# tooltip clips instead of re-laying-out the grids. ~4 hint lines; top-aligned so shorter text leaves dead
	# space below rather than re-centering.
	var footer := Control.new()
	footer.clip_contents = true
	footer.custom_minimum_size.y = 4 * (MenuStyle.skin.hint_size + 4)
	footer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_child(footer)
	_detail = MenuStyle.make_hint(_DEFAULT_HINT)
	_detail.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)  # fill the fixed host; overflow is clipped, not laid out
	_detail.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_detail.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	footer.add_child(_detail)

## One grid COLUMN — heading + scrollable grid in a VBox — added side-by-side into `parent` (the columns HBox);
## returns its GridInventoryView and appends its heading Label to `headers` (so _build_ui can keep the SOURCE
## heading for per-open retitling; headers[0] = source, headers[1] = player — order pinned by the call sites).
## The scroll is only the too-short-window fallback: its resized hook hands the grid the slot's height as its
## max_view_height budget, so at the design 792x444 canvas both grids render whole with no scrollbars.
func _build_grid_section(parent: Container, heading: String, headers: Array) -> GridInventoryView:
	var column := VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_theme_constant_override("separation", MenuStyle.skin.content_separation)
	parent.add_child(column)
	var head := Label.new()
	head.text = MenuStyle.title_text(heading)  # section headers follow the skin's title casing
	head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	head.add_theme_font_size_override("font_size", MenuStyle.skin.header_size)
	column.add_child(head)
	headers.append(head)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_child(scroll)
	var grid := GridInventoryView.new()
	scroll.add_child(grid)
	scroll.resized.connect(_on_grid_slot_resized.bind(scroll, grid))  # bound method, not a lambda (freed-capture safety)
	return grid

## A grid's scroll slot changed size (first layout, window resize) — hand THAT grid its exact height budget so
## _recompute_cell fits cells by HEIGHT as well as width (all rows visible; the scrollbar only ever appears as
## the fallback when even MIN_CELL rows overflow). refresh() applies the new cell size immediately; safe while
## closed / unbound — refresh() on an unbound grid just clears its rows.
func _on_grid_slot_resized(scroll: ScrollContainer, grid: GridInventoryView) -> void:
	if grid == null or not is_instance_valid(scroll):
		return
	grid.max_view_height = int(scroll.size.y)
	grid.refresh()
