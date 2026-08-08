extends GutTest

## The H / DropHeld TOGGLE on your own weapon: H takes the wielded knife out of the holster and into your hands as
## a throwable prop, and H AGAIN puts it back — into the bag AND back in your grip — instead of dropping it on the
## floor. These pin the seam that decides which of those two a press is: Player.return_held_weapon_to_hands (true
## only for the weapon YOUR OWN holster gave up) and the re-wield at the end of stash_held_item.
##
## Off-tree, following tests/test_hotbar.gd: a bare player script instance is handed a bare CharacterInventory (no
## _ready anywhere — see the CLAUDE.md rule), and the carry itself is simulated by setting the reservation fields
## the pull would have set. The physical carry (the prop, the view-model hands, the holster/draw-lock dance) is
## in-tree behaviour and stays playtested.

const PLAYER_PATH := "res://scripts/player/player.gd"


func _make_weapon(id: StringName) -> Item:
	var it := Item.new()
	it.id = id
	it.category = Item.Category.WEAPON
	it.weapon = WeaponData.new()  # is_weapon() requires a real WeaponData
	return it


func _make_holdable(id: StringName) -> Item:
	# A world_prop item (the dog / a crate) — is_holdable() but neither weapon nor consumable.
	var it := Item.new()
	it.id = id
	it.category = Item.Category.MISC
	it.world_prop = "res://scenes/characters/dog.tscn"  # path only — nothing here loads it
	return it


## Put the player in the state hold_equipped_weapon leaves behind: the weapon is OUT of the bag, reserved as
## held-in-hand, and flagged as having come from the holster (so the next H is a put-back, not a drop).
func _simulate_h_pull(p, item: Item) -> void:
	p._held_inv_item = item
	p._held_from_weapon_slot = true


func test_h_again_puts_the_weapon_back_in_your_hands() -> void:
	var p = load(PLAYER_PATH).new()
	var inv := CharacterInventory.new()
	p.inventory = inv
	var knife := _make_weapon(&"knife")
	_simulate_h_pull(p, knife)
	assert_true(p.return_held_weapon_to_hands(), "H on your OWN pulled weapon is consumed by the put-back")
	assert_true(inv.has(knife), "the SAME item instance is back in the backpack")
	assert_eq(inv.equipped_item, knife, "and RE-WIELDED — a put-back must not leave you on bare fists")
	assert_null(p.held_inventory_item(), "the in-hand reservation cleared")
	assert_false(p._held_from_weapon_slot, "the toggle flag cleared with it — nothing left to put back")
	p.free()
	inv.free()


func test_a_hotbar_pulled_prop_still_drops() -> void:
	# The H verb only toggles the weapon YOUR HOLSTER gave up. A prop pulled from the backpack via the hotbar is
	# untouched here so PickupRay falls through to its gentle tap-drop, exactly as before.
	var p = load(PLAYER_PATH).new()
	var inv := CharacterInventory.new()
	p.inventory = inv
	var dog := _make_holdable(&"dog")
	p._held_inv_item = dog  # a hotbar pull: reserved, but NOT from the weapon slot
	assert_false(p.return_held_weapon_to_hands(), "a hotbar-pulled prop doesn't own the H press")
	assert_eq(p.held_inventory_item(), dog, "and nothing was put away — the drop path still has a prop to release")
	assert_false(inv.has(dog), "the bag was left untouched")
	p.free()
	inv.free()


func test_a_world_grabbed_prop_still_drops() -> void:
	# Nothing came out of the bag at all (a crate grabbed off the floor with E/Z) — H must still set it down.
	var p = load(PLAYER_PATH).new()
	var inv := CharacterInventory.new()
	p.inventory = inv
	assert_false(p.return_held_weapon_to_hands(), "a world-grabbed prop doesn't own the H press")
	p.free()
	inv.free()


func test_stashing_a_hotbar_prop_never_equips_it() -> void:
	# The re-wield is gated on the weapon-slot flag, not merely on "it went back in the bag": putting the dog away
	# from the hotbar must not touch what you're wielding.
	var p = load(PLAYER_PATH).new()
	var inv := CharacterInventory.new()
	p.inventory = inv
	var dog := _make_holdable(&"dog")
	p._held_inv_item = dog
	assert_true(p.stash_held_item(), "the hotbar prop went back into the bag")
	assert_true(inv.has(dog), "…as the same instance")
	assert_null(inv.equipped_item, "and nothing was equipped — a dog is not a weapon and never came from the holster")
	p.free()
	inv.free()


func test_a_refused_put_back_keeps_the_weapon_in_hand() -> void:
	# Loot filled the footprint the pull freed: stash_held_item refuses (toasts + keeps holding). H must still read
	# as CONSUMED so PickupRay doesn't fall through and fling your knife on the floor as a consolation prize.
	var p = load(PLAYER_PATH).new()
	var inv := CharacterInventory.new()
	inv.enable_grid(1, 1)  # a one-cell bag…
	var filler := Item.new()
	filler.id = &"filler"
	filler.category = Item.Category.MISC
	inv.add(filler)  # …now full, so can_accept(knife) is false
	p.inventory = inv
	var knife := _make_weapon(&"knife")
	_simulate_h_pull(p, knife)
	assert_true(p.return_held_weapon_to_hands(), "the press is still consumed — H never turns into a surprise drop")
	assert_eq(p.held_inventory_item(), knife, "the knife stays IN HAND (reserved + save-reachable), as the toast says")
	assert_null(inv.equipped_item, "and nothing was equipped — you can't wield an item that isn't in the bag")
	p.free()
	inv.free()


func test_the_put_back_suppresses_the_fists_until_the_rewield_lands() -> void:
	# The bare-fist FLASH fix: stash_held_item's carry release restores the holster while the combat inventory
	# still reads FISTS (the real weapon is only re-equipped at the end), so without suppression the first-person
	# fists rise over the weapon's own re-draw. The seam is _rewield_in_flight: armed BEFORE the release, still
	# up when the rewield request goes out, down once the put-back returns. Observed AT the two signals that
	# bracket the window — the bag re-add (changed, fired before the release) and equip_weapon_requested.
	var p = load(PLAYER_PATH).new()
	var inv := CharacterInventory.new()
	p.inventory = inv
	var knife := _make_weapon(&"knife")
	_simulate_h_pull(p, knife)
	var seen := {}
	inv.changed.connect(func() -> void:
		if not seen.has("add"):
			seen["add"] = p._rewield_in_flight)
	inv.equip_weapon_requested.connect(func(_w: WeaponData) -> void:
		seen["equip"] = p._rewield_in_flight)
	assert_false(p._rewield_in_flight, "the suppression is DOWN before the put-back")
	assert_true(p.return_held_weapon_to_hands(), "the put-back ran")
	assert_true(seen.get("add", false), "armed by the time the bag re-add fires — i.e. BEFORE the carry release")
	assert_true(seen.get("equip", false), "…and still up when the rewield request goes out")
	assert_false(p._rewield_in_flight, "and DOWN once the put-back returns — nothing suppressed afterwards")
	p.free()
	inv.free()


func test_stashing_a_hotbar_prop_never_arms_the_fists_suppression() -> void:
	# The genuine drop-to-unarmed handoff must keep working: a NON-weapon put-away (the dog) never rewields, so
	# it must never arm _rewield_in_flight — an unarmed player stashing the dog still gets the seamless
	# carry→fists handoff in _on_carry_changed.
	var p = load(PLAYER_PATH).new()
	var inv := CharacterInventory.new()
	p.inventory = inv
	var dog := _make_holdable(&"dog")
	p._held_inv_item = dog
	var seen := {}
	inv.changed.connect(func() -> void:
		if not seen.has("add"):
			seen["add"] = p._rewield_in_flight)
	assert_true(p.stash_held_item(), "the hotbar prop went back into the bag")
	assert_false(seen.get("add", true), "the suppression never rose — a non-weapon stash must not hide the fists")
	assert_false(p._rewield_in_flight, "…and stays down after")
	p.free()
	inv.free()


func test_pickup_ray_h_press_routes_to_the_put_back_not_a_release() -> void:
	# The PickupRay branch itself: with your own weapon in hand the H press must return through the put-back and
	# NEVER reach _release (which would clear _holding and fire carry_changed(false) — i.e. drop it).
	var p = load(PLAYER_PATH).new()
	var inv := CharacterInventory.new()
	p.inventory = inv
	var knife := _make_weapon(&"knife")
	_simulate_h_pull(p, knife)
	var ray := PickupRay.new()
	ray.player = p
	ray._holding = true  # carrying (held_object is the world prop in-game; the release path is freed-safe without it)
	ray._drop_held_in_hand()
	assert_true(ray._holding, "the put-back consumed the press — _release was never reached")
	assert_eq(inv.equipped_item, knife, "…and the knife is wielded again")
	# The same press with a world-grabbed prop (no reservation) must still fall through to the release.
	p._held_inv_item = null
	p._held_from_weapon_slot = false
	ray._drop_held_in_hand()
	assert_false(ray._holding, "a plain carried prop still takes the drop path")
	ray.free()
	p.free()
	inv.free()
