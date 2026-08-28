@tool
class_name ItemContainer
extends LookAtInteractable


## Drop-in LOOTABLE CONTAINER component (a crate, chest, locker, fridge): aim at it and press F (Interact)
## to open the loot transfer on its OWN inventory — take items out, or deposit your own in (two-way).
## Extends LookAtInteractable (the talk-layer hitbox + look-at outline); this adds the inventory + open
## behaviour. Unlike a corpse, a container is PERSISTENT: it's never freed, so you can stash gear and return.
##
## SETUP: drop this under the visible object (or assign highlight_target), size its CollisionShape3D to
## cover the body you aim at, and (optionally) fill `item_stacks` with what it holds.

## EASY count-based contents: "5 healthpacks, 30 pistol ammo, 2 shotguns" is three rows (item + count) -- the
## way to fill a crate. Seeded into the contents, with the optional loot_table rolled on top.
@export var item_stacks: Array[ItemStack] = []
## Zorkmids stashed in this container. Seeded at spawn as a real zorkmids COIN TILE in `inventory` (see
## _seed_money_coins) — looted like any other item, the same coin tile a corpse now drops. 0 = no cash.
## Authoring input only: the runtime cash lives in the coin tile, so nothing reads this float after spawn.
@export var money: float = 0.0
## OPTIONAL drop table rolled into the contents at spawn, ON TOP of the above — for a crate/chest with random
## loot. Null = just the fixed contents. (Weapons rolled from the table are unique instances.)
@export var loot_table: LootTable = null
## Name shown on the look-at hover ("Loot <name>") + the transfer screen title. Blank -> just "Container".
@export var container_name: String = ""
## OPTIONAL stable id for the exact-save (WorldSnapshot quicksave/slot) tier. Leave blank for the
## level|node-path fallback (fine for a hand-placed crate that is never renamed/re-parented); set it on
## story containers whose looted/stashed state must survive a scene-layout edit. Mirrors NPC.save_id /
## Corpse.save_id. Unused by the lean autosave/Continue profile (containers re-seed there, by design).
@export var save_id: StringName = &""

## The container's contents — LootScreen reads this. Built in _ready (a child CharacterInventory), seeded
## from item_stacks.
var inventory: CharacterInventory

func _ready() -> void:
	if Engine.is_editor_hint():
		super()  # @tool: the base guard previews the auto-fit hitbox + early-returns (XC1); we skip our runtime tail
		return  # the inventory build + seed below is runtime-only
	super()  # talk-layer hitbox + look-at outline (LookAtInteractable)
	add_to_group(Groups.CONTAINERS)  # discoverable by NpcScavenge (an NPC raids nearby crates for a better gun)
	inventory = CharacterInventory.new()
	inventory.name = &"Contents"
	add_child(inventory)
	_seed_contents()

## Seed the contents: the authored item_stacks (weapons as unique instances), then roll the optional
## loot_table on top. Split out so it's unit-testable off-tree (set `inventory`, call directly).
func _seed_contents() -> void:
	if inventory == null:
		return
	ItemStack.seed_into(inventory, item_stacks)  # the easy count-based contents
	if loot_table != null:
		var rng := RandomNumberGenerator.new()
		rng.randomize()
		loot_table.grant(inventory, rng)
	_seed_money_coins()

## Turn the authored `money` into a real zorkmids COIN TILE in the contents (one unit = one QUANTUM), so a
## crate's cash loots exactly like a corpse's — no separate "Take N zm" button. Added while the grid is still
## OFF (unbounded), so it always lands; the loot screen grids the contents on open. Depositing player cash back
## in (LootScreen._deposit_coins_to_source) tops this same tile.
func _seed_money_coins() -> void:
	if money <= 0.0 or inventory == null:
		return
	var coin := ItemDb.item_by_id(Zorkmids.ITEM_ID)
	if coin != null:
		inventory.add(coin, int(round(money / Zorkmids.QUANTUM)))

# --- Behaviour (talk-handler surface) ---

## E pressed while aimed at us: pick/key any Lock child first (one attempt per press — see Lock.try_unlock),
## then open the loot transfer on this container's inventory (NEVER frees it). A failed attempt toasts what
## the lock needs and leaves it shut.
func start_talk(player: Node) -> void:
	var lock := Lock.of(self)
	if lock != null and lock.locked and not lock.try_unlock(player):
		return  # still locked — the toast said why
	Restocker.notify_visit(self)  # a child Restocker in ON_VISIT mode refills the crate before it opens
	LootScreen.open_container(self, player)

## Top the container's contents back up to its authored item_stacks baseline, adding ONLY
## the shortfall per item kind — never doubling, never removing what the player deposited. A child Restocker
## calls this so authored item_stacks refill on a return visit. The authored money is NOT re-seeded, and the
## optional loot_table is NOT re-rolled.
func refill() -> void:
	if inventory == null:
		return
	var baseline := {}
	for st in item_stacks:
		if st != null:
			CharacterInventory.accumulate_baseline(baseline, st.item, st.count)
	CharacterInventory.refill_to_baseline(inventory, baseline)

# --- WorldSnapshot exact-save tier (manual quicksave/slots) --------------------------------------------------

## POSITION-INDEPENDENT identity for the snapshot: an authored `save_id` is the whole key ("id:<x>"); else
## level|node_path — the same shape as NPC.snapshot_key (a container never moves, but the shared shape keeps
## one matching rule across the tier, and node_path survives a same-scene reload identically).
func snapshot_key() -> String:
	if save_id != &"":
		return "id:%s" % String(save_id)
	var np: String = str(get_path()) if is_inside_tree() else String(name)
	return "%s|%s" % [GameState.current_level_path, np]

## This container's exact-save state, in the [world_snapshot] "containers" entry shape:
## { stacks: serialize_stacks() rows, grid: bool, locked: bool (only when a Lock child exists) }.
## The coin tile serializes like any other stack (a container's cash is REAL loot — the PLAYER's zorkmids are
## a `money` float that never enters a bag); `grid` records whether the loot screen has bounded us yet, so a restore
## can re-bound BEFORE re-placing and the player's crate layout survives the reload.
func snapshot_contents() -> Dictionary:
	if inventory == null:
		return {}
	var d := {"stacks": inventory.serialize_stacks(), "grid": inventory.grid_enabled()}
	var lock := Lock.of(self)
	if lock != null:
		d["locked"] = lock.locked
	return d

## Central-push restore (WorldSnapshot.apply, deferred after _ready): REPLACE the freshly-seeded contents with
## the snapshot's exact bag. _ready's authored seed + loot_table roll already ran — clear() discards it, so a
## looted crate stays looted and a random table never re-rolls on quickload. When the save had the container
## grid on (the loot screen had bounded it), re-bound at the same authored dims FIRST so each stack's saved
## cell is honored; LootScreen._open's enable is guarded on grid_enabled(), so the restored layout survives
## the next open untouched. A Lock child gets its save-time locked bit back (quickload is time travel — a
## re-lock is correct; the consumed key/pick lives in the profile tier, restored by the same load). Child
## Restockers are told (note_restored) so the first reopen can't insta-refill what the snapshot restored.
func restore_snapshot_contents(d: Dictionary) -> void:
	if inventory == null:
		return  # off-tree / pre-_ready: nothing to restore into (apply() only runs against in-tree containers)
	inventory.clear()
	if bool(d.get("grid", false)) and not inventory.grid_enabled():
		inventory.enable_grid(GameSettings.inventory.container_grid_cols, GameSettings.inventory.container_grid_rows)
	var stacks_v: Variant = d.get("stacks", [])
	if stacks_v is Array:
		inventory.restore_serialized_stacks(stacks_v)
	var locked_v: Variant = d.get("locked")
	if locked_v is bool:
		var lock := Lock.of(self)
		if lock != null:
			lock.locked = locked_v
	for c in get_children():
		if c is Restocker:
			(c as Restocker).note_restored()

## Always interactable — a container is openable even when empty, so you can deposit into it.
func can_be_talked_to() -> bool:
	return true

## Hover readout: "Loot <name>" (or just "Container" when unnamed) — "Unlock <name>" while a Lock child
## holds it shut, so the [F] prompt says what pressing it will actually attempt.
func look_name() -> String:
	var lock := Lock.of(self)
	if lock != null and lock.locked:
		return PlayerText.unlock(container_name if not container_name.is_empty() else "Container")
	return PlayerText.loot(container_name)
