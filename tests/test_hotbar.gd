extends GutTest

## The Deus Ex hotbar's AUTO-ASSIGNMENT: weapons + consumables take the first free slot, ammo/misc are
## skipped, and items that leave the bag vacate their slot. Off-tree: a bare player is handed a bare
## CharacterInventory directly (no _ready anywhere), and the Hotbar builds its Control chrome unparented.
## The key handling + equip/use activation are in-tree behaviour (playtested).

const PLAYER_PATH := "res://scripts/player/player.gd"


func _make_item(id: StringName, category: int, stack: int = 1) -> Item:
	var it := Item.new()
	it.id = id
	it.category = category as Item.Category
	it.max_stack = stack
	if category == Item.Category.WEAPON:
		it.weapon = WeaponData.new()  # is_weapon() requires a real WeaponData
	elif category == Item.Category.AMMO:
		it.caliber = &"9mm"  # is_ammo() requires a caliber
	return it


func test_hotbar_auto_assigns_and_vacates() -> void:
	var p = load(PLAYER_PATH).new()
	var inv := CharacterInventory.new()
	p.inventory = inv
	var gun := _make_item(&"gun", Item.Category.WEAPON)
	var rounds := _make_item(&"rounds", Item.Category.AMMO, 30)
	var medkit := _make_item(&"medkit", Item.Category.CONSUMABLE, 5)
	inv.add(gun)
	inv.add(rounds, 12)
	inv.add(medkit, 3)
	var hb := Hotbar.new()
	hb.setup(p)  # wires inventory.changed + does the first sync
	assert_eq(hb._items[0], gun, "the weapon takes slot 1 (insertion order)")
	assert_eq(hb._items[1], medkit, "the consumable takes the NEXT free slot — ammo is skipped entirely")
	assert_null(hb._items[2], "nothing else assigned")
	inv.remove(gun, 1)
	assert_null(hb._items[0], "an item that left the bag vacates its slot (changed -> re-sync)")
	assert_eq(hb._items[1], medkit, "other slots keep their assignment (stable layout)")
	inv.add(gun)
	assert_eq(hb._items[0], gun, "a re-acquired item fills the first FREE slot again")
	hb.free()
	p.free()
	inv.free()


func test_hotbar_one_slot_per_weapon_kind() -> void:
	# Weapons are unique ITEM instances, so five looted pistols would otherwise flood five slots — the bar
	# keeps ONE slot per WeaponData kind; duplicates stay bag-only and inherit the slot when it vacates.
	var p = load(PLAYER_PATH).new()
	var inv := CharacterInventory.new()
	p.inventory = inv
	var pistol_data := WeaponData.new()
	var pistol_a := _make_item(&"pistol", Item.Category.WEAPON)
	pistol_a.weapon = pistol_data
	var pistol_b := _make_item(&"pistol", Item.Category.WEAPON)
	pistol_b.weapon = pistol_data  # a second INSTANCE of the same kind
	var shotgun := _make_item(&"shotgun", Item.Category.WEAPON)
	inv.add(pistol_a)
	inv.add(pistol_b)
	inv.add(shotgun)
	var hb := Hotbar.new()
	hb.setup(p)
	assert_eq(hb._items[0], pistol_a, "the first pistol takes slot 1")
	assert_eq(hb._items[1], shotgun, "the DUPLICATE pistol is skipped — the shotgun takes slot 2")
	assert_null(hb._items[2], "only two slots used")
	inv.equip_item(pistol_b)  # the bag UI can equip the BAG-ONLY duplicate...
	assert_true(hb._is_equipped_kind(pistol_a, inv),
		"...and the slotted same-kind item still reads as equipped (kind-aware highlight / cycle anchor)")
	inv.remove(pistol_a, 1)
	assert_true(hb._items.has(pistol_b), "dropping the slotted pistol hands its slot to the duplicate")
	hb.free()
	p.free()
	inv.free()


func test_hotbar_scroll_cycles_weapons_only() -> void:
	# The wheel walks WEAPON slots with wrap — consumables are skipped (scrolling past a medkit must never
	# use it) and bare fists enters at the first weapon (down) / last (up).
	var p = load(PLAYER_PATH).new()
	var inv := CharacterInventory.new()
	p.inventory = inv
	var gun_a := _make_item(&"a", Item.Category.WEAPON)
	var medkit := _make_item(&"m", Item.Category.CONSUMABLE, 5)
	var gun_b := _make_item(&"b", Item.Category.WEAPON)
	inv.add(gun_a)
	inv.add(medkit)
	inv.add(gun_b)
	var hb := Hotbar.new()
	hb.setup(p)  # slots: [gun_a, medkit, gun_b]; nothing equipped (fists)
	hb._cycle(1)
	assert_eq(inv.equipped_item, gun_a, "from fists, wheel-down equips the FIRST weapon slot")
	hb._cycle(1)
	assert_eq(inv.equipped_item, gun_b, "next SKIPS the consumable straight to the next weapon")
	hb._cycle(1)
	assert_eq(inv.equipped_item, gun_a, "...and wraps back around")
	hb._cycle(-1)
	assert_eq(inv.equipped_item, gun_b, "wheel-up steps backward (wrapping)")
	inv.remove(gun_b, 1)  # the equipped weapon leaves the bag -> fists
	hb._cycle(1)
	assert_eq(inv.equipped_item, gun_a, "from fists with one weapon left, the wheel equips it")
	hb._cycle(1)
	assert_eq(inv.equipped_item, gun_a, "a single carried weapon has nowhere to scroll — stays equipped")
	hb.free()
	p.free()
	inv.free()


func test_hotbar_overflow_stays_in_the_bag() -> void:
	var p = load(PLAYER_PATH).new()
	var inv := CharacterInventory.new()
	p.inventory = inv
	var items: Array[Item] = []
	for i in 12:  # two more than the bar holds
		var it := _make_item(StringName("w%d" % i), Item.Category.WEAPON)
		items.append(it)
		inv.add(it)
	var hb := Hotbar.new()
	hb.setup(p)
	assert_eq(hb._items[9], items[9], "the tenth weapon takes the last slot")
	assert_false(hb._items.has(items[10]), "the eleventh stays bag-only — the bar never exceeds 10 slots")
	hb.free()
	p.free()
	inv.free()


func _make_holdable(id: StringName) -> Item:
	# A world_prop item (the dog / a crate) — is_holdable() but neither weapon nor consumable.
	var it := Item.new()
	it.id = id
	it.category = Item.Category.MISC
	it.world_prop = "res://scenes/dog.tscn"  # path only — is_holdable / assign / sync never load it
	return it


func test_is_holdable_classifies_props_not_gear() -> void:
	assert_true(_make_holdable(&"dog").is_holdable(), "a world_prop misc item is holdable")
	var with_model := Item.new()
	with_model.world_model = BoxMesh.new()  # any world_model (a Mesh is a Resource) => holdable
	assert_true(with_model.is_holdable(), "a world_model misc item is holdable too")
	assert_false(_make_item(&"gun", Item.Category.WEAPON).is_holdable(), "a weapon is equipped, not held")
	assert_false(_make_item(&"med", Item.Category.CONSUMABLE, 5).is_holdable(), "a consumable is used, not held")
	assert_false(_make_item(&"ammo", Item.Category.AMMO, 30).is_holdable(), "ammo is not holdable")
	assert_false(Item.new().is_holdable(), "a plain misc item with no world model/prop is not holdable")
	with_model.world_model = null


func test_zorkmids_coin_tile_is_not_holdable() -> void:
	# The wallet coin tile wears a world_model (the money-bag mesh) but is MONEY — slotting it on the hotbar and
	# activating it would mint a physics money-bag into the hands while MoneyPurse re-mints the debited wallet.
	# is_holdable() guards the zorkmids id FIRST, so the coin tile is never hotbar-assignable/holdable (F-C13-C28).
	var z := Item.new()
	z.id = Zorkmids.ITEM_ID
	z.world_model = BoxMesh.new()  # even wearing a world_model...
	assert_false(z.is_holdable(), "the wallet coin tile is money, never a holdable prop even with a world_model")
	# Guard against an over-broad id-only guard: a DIFFERENT world_model item still holds.
	var other := Item.new()
	other.id = &"crate"
	other.world_model = BoxMesh.new()
	assert_true(other.is_holdable(), "a non-zorkmids world_model item is still holdable — the guard is zorkmids-only")
	z.world_model = null
	other.world_model = null


func test_holdables_are_manual_only_and_reserve_their_slot_while_held() -> void:
	# Holdable props DON'T auto-fill (they'd flood the bar over your weapons), but CAN be hand-assigned. While one
	# is pulled out into your hands its slot is RESERVED (exempt from the "left the bag -> vacate" rule) so a second
	# press stashes it back; on drop/throw the reservation clears and the slot vacates.
	var p = load(PLAYER_PATH).new()
	var inv := CharacterInventory.new()
	p.inventory = inv
	var dog := _make_holdable(&"dog")
	inv.add(dog)
	var hb := Hotbar.new()
	hb.setup(p)
	assert_false(hb._items.has(dog), "a holdable is NOT auto-slotted — the bar auto-fills weapons/consumables only")
	hb.assign(dog, 0)
	assert_eq(hb._items[0], dog, "but it CAN be hand-assigned to a slot")
	# Simulate the pull-out in the SAME order as Player._pull_and_hold: RESERVE the item as held-in-hand FIRST, then
	# remove it from the bag. setup() wired inventory.changed -> _sync_slots, so the removal fires a sync immediately;
	# reserving first means that sync already sees the reservation and keeps the slot (reserving AFTER the removal
	# would let that sync vacate it before _held_inv_item was set — the exact ordering the real code avoids).
	p._held_inv_item = dog
	inv.remove(dog, 1)
	hb._sync_slots()
	assert_eq(hb._items[0], dog, "the reserved (held) item keeps its slot even though it left the bag")
	# Simulate a drop/throw: the reservation clears and the item is now a world prop, not in the bag.
	p._held_inv_item = null
	hb._sync_slots()
	assert_null(hb._items[0], "once dropped/thrown (reservation cleared) the slot vacates")
	hb.free()
	p.free()
	inv.free()


func test_hold_item_toggles_pull_and_stash() -> void:
	# The toggle lives on the Player: hold_item stashes the SAME item back when it's the one already held. The
	# pull-out half needs an in-tree carry ray (playtested); here we cover the stash-back + the refuse-without-ray.
	var p = load(PLAYER_PATH).new()
	var inv := CharacterInventory.new()
	p.inventory = inv
	var dog := _make_holdable(&"dog")
	# Already holding `dog` (reservation set, item out of the bag): pressing its slot stashes it back.
	p._held_inv_item = dog
	assert_true(p.hold_item(dog), "pressing the held item's slot toggles a stash-back")
	assert_null(p.held_inventory_item(), "the reservation clears after stashing")
	assert_true(inv.has(dog), "the SAME instance is re-added to the bag (slot re-fills)")
	# Not holding anything and no carry ray (bare off-tree player): a pull-out safely refuses, bag untouched.
	assert_false(p.hold_item(dog), "with no carry ray the pull-out refuses")
	assert_true(inv.has(dog), "...and the bag is untouched (the item was never removed)")
	p.free()
	inv.free()


func test_assign_refuses_over_a_held_props_reserved_slot() -> void:
	# While a prop is pulled into your hands its slot is RESERVED (the item is out of the bag with nowhere else to
	# live). Assigning ANOTHER item onto that slot from the open backpack must be refused, or the held item is
	# orphaned off the bar (re-press-to-stash + gold tint lost). Regression guard for the reviewed defect.
	var p = load(PLAYER_PATH).new()
	var inv := CharacterInventory.new()
	p.inventory = inv
	var dog := _make_holdable(&"dog")
	var gun := _make_item(&"gun", Item.Category.WEAPON)
	var hb := Hotbar.new()
	hb.setup(p)
	# Simulate holding the dog pulled from slot 0 (out of the bag, slot reserved).
	hb._items[0] = dog
	p._held_inv_item = dog
	hb.assign(gun, 0)
	assert_eq(hb._items[0], dog, "assigning another item onto the held prop's reserved slot is refused — the dog keeps its slot so a re-press still stashes it")
	hb.free()
	p.free()
	inv.free()


func test_hotbar_gate_respects_liveness() -> void:
	# T2: the _unhandled_input gate reads `not _player.is_alive()` (canonical predicate, swapped from the raw _dead
	# field) so a dead player can't swap weapons / burn a medkit mid-cinematic. The full routing (InputMap + viewport +
	# autoload screens) is playtest-gated; here we pin the exact predicate the gate reads on the bare off-tree player.
	var p = load(PLAYER_PATH).new()
	p.hp = 1.0  # _ready (which seeds hp = max_hp) doesn't run off-tree; is_alive() reads `not _dead and hp > 0`
	var inv := CharacterInventory.new()
	p.inventory = inv
	var hb := Hotbar.new()
	hb.setup(p)
	assert_true(p.is_alive(), "a fresh (living) player is alive — the hotbar gate lets a slot key through")
	p._dead = true
	assert_false(p.is_alive(), "_dead latched → not is_alive() → the hotbar gate returns before any slot activation")
	hb.free()
	p.free()
	inv.free()


func test_death_teardown_stashes_a_bag_pulled_prop() -> void:
	# T2 (F-T2-4): die()'s carry-teardown STASHES a bag-pulled prop (hotbar hold, _held_inv_item set) back into the
	# backpack instead of dropping it, so the death-milestone autosave persists the item WITH the profile. Exercised
	# via the extracted _release_or_stash_carried_prop() (die() itself drives the full cinematic and can't run off-tree).
	var p = load(PLAYER_PATH).new()
	var inv := CharacterInventory.new()
	p.inventory = inv
	var dog := _make_holdable(&"dog")
	# Simulate a live hold: the item is OUT of the bag and reserved as held-in-hand (the hotbar pull-out state).
	p._held_inv_item = dog  # deliberately do NOT inv.add — the prop lives only in the hand right now
	p._release_or_stash_carried_prop()
	assert_true(inv.has(dog), "the bag-pulled prop was STASHED back into the backpack (not dropped into the world)")
	assert_null(p.held_inventory_item(), "the reservation cleared once the item is safely back in the bag")
	# The plain-aimed-grab branch (no _held_inv_item): force-release null-guards on head off-tree, so this is a no-op.
	p._held_inv_item = null
	p._release_or_stash_carried_prop()  # must not throw — _force_release_carried_prop null-guards on head/pickup_ray
	assert_null(p.held_inventory_item(), "no reservation to begin with — a safe no-op")
	p.free()
	inv.free()


func test_stash_refuses_into_a_full_bag_and_keeps_holding() -> void:
	# If the bag filled while a prop was in hand, stashing it back must REFUSE (not clear the reservation) so the item
	# stays in hand and save-reachable rather than orphaned. Uses a bounded grid sized to 0 free cells. Regression guard.
	var p = load(PLAYER_PATH).new()
	var inv := CharacterInventory.new()
	inv.enable_grid(1, 1)  # a one-cell bag
	var filler := _make_item(&"filler", Item.Category.MISC)
	inv.add(filler)  # the single cell is now taken -> can_accept(dog) is false
	p.inventory = inv
	var dog := _make_holdable(&"dog")
	p._held_inv_item = dog  # simulate holding it (already out of the bag)
	assert_false(p.stash_held_item(), "stash into a full bag is refused")
	assert_eq(p.held_inventory_item(), dog, "the reservation is KEPT (the item stays in hand, not orphaned)")
	assert_false(inv.has(dog), "the dog was not force-added over capacity")
	p.free()
	inv.free()
