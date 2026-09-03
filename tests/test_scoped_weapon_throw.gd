extends GutTest

## The ADS + ATTACK weapon throw: aim down sights with the knife, pull the trigger, and the blade is HURLED down your
## look ray instead of swung. Three seams meet here and each has its own failure mode:
##   1. Attack.is_scoped_throw_gesture — WHICH trigger pulls are the throw (a pure static, the PickupRay.is_throw_release
##      idiom). Widen it and hip-firing the knife stops swinging; narrow it and the gesture silently dies.
##   2. Player.throw_equipped_weapon — the throw itself, and (the part pinned here) every REFUSAL. A refusal must leave
##      the backpack EXACTLY as it found it and return false, so Attack falls through to an ordinary attack. The bug
##      this guards against is the worst one available: an aimed trigger pull that quietly loses your only knife.
##   3. PickupRay.throw_held — the one definition of "a full throw", shared by the left-click fling and by the code-side
##      thrower above. Empty hands must be a false, not a release of nothing.
##
## Off-tree, following tests/test_drop_held_weapon_toggle.gd: a bare player script instance gets a bare
## CharacterInventory and no _ready runs anywhere (see the CLAUDE.md rule). The SUCCESS path physically needs a world,
## a carry ray and a built drop, so it stays in-tree behaviour and is playtested — what is testable here is the gesture
## truth table and the refusals, which are exactly the parts that must never lose an item.

const PLAYER_PATH := "res://scripts/player/player.gd"


func _make_weapon(id: StringName) -> Item:
	var it := Item.new()
	it.id = id
	it.category = Item.Category.WEAPON
	it.weapon = WeaponData.new()  # is_weapon() requires a real WeaponData
	return it


func _make_misc(id: StringName) -> Item:
	var it := Item.new()
	it.id = id
	it.category = Item.Category.MISC
	return it


## A player wielding `item`, with no head/carry rig — which is what makes throw_equipped_weapon refuse off-tree.
func _armed_player(item: Item) -> Array:
	var p = load(PLAYER_PATH).new()
	var inv := CharacterInventory.new()
	p.inventory = inv
	inv.add(item, 1)
	inv.equip_item(item)
	return [p, inv]


# ---------------------------------------------------------------------------------------------------------------
# 1. The gesture truth table
# ---------------------------------------------------------------------------------------------------------------

func test_scoped_attack_with_an_opted_in_weapon_is_the_throw() -> void:
	assert_true(Attack.is_scoped_throw_gesture(true, false, true),
		"a PLAYER firing while SCOPED with a throw_on_scoped_attack weapon IS the throw gesture")


func test_hip_fire_is_never_the_throw() -> void:
	assert_false(Attack.is_scoped_throw_gesture(false, false, true),
		"un-scoped, the knife must still SWING — ADS is the whole trigger, so hip-fire can never throw it away")


func test_a_weapon_that_did_not_opt_in_is_never_thrown() -> void:
	assert_false(Attack.is_scoped_throw_gesture(true, false, false),
		"scoping a gun must not hurl it: only a weapon authoring throw_on_scoped_attack gives up its trigger")


func test_an_ai_wielder_never_throws_its_weapon() -> void:
	# An NPC's ScopeIn has no camera and never scopes, so from_ai should be unreachable with scoped=true — pinned
	# anyway because the cost of it ever being reachable is an enemy disarming itself on its first attack.
	assert_false(Attack.is_scoped_throw_gesture(true, true, true),
		"from_ai can never be the throw — an AI wielder must not throw its own weapon away")


# ---------------------------------------------------------------------------------------------------------------
# 2. Player.throw_equipped_weapon refusals — every one of these must leave the bag untouched
# ---------------------------------------------------------------------------------------------------------------

func test_no_carry_rig_refuses_and_keeps_the_weapon() -> void:
	# The off-tree stand-in for every "the throw could not be built" case (no head, no hold anchor, no world). THE
	# invariant: refusing costs you nothing — the knife is still in the bag AND still wielded, so the click falls
	# through to an ordinary scoped swing.
	var made := _armed_player(_make_weapon(&"knife"))
	var p = made[0]
	var inv: CharacterInventory = made[1]
	var knife: Item = inv.equipped_item
	assert_false(p.throw_equipped_weapon(), "with no carry rig the throw refuses instead of half-happening")
	assert_true(inv.has(knife), "a refused throw leaves the weapon IN THE BACKPACK — it must never be lost")
	assert_eq(inv.equipped_item, knife, "and still WIELDED, so the fall-through swing has something to swing")
	assert_false(p._held_from_weapon_slot,
		"and never arms the H put-back latch — the throw takes the weapon out of your hands for good")
	assert_false(p._throwing_wielded_weapon,
		"and the zero-frame-carry latch is DOWN again — left up it would silently mute the holster dance and the"
		+ " FP-hands relay on every ordinary carry after it")
	p.free()
	inv.free()


func test_bare_fists_refuse_the_throw() -> void:
	var p = load(PLAYER_PATH).new()
	var inv := CharacterInventory.new()
	p.inventory = inv
	assert_false(p.throw_equipped_weapon(), "nothing equipped (bare fists) means there is no item to throw")
	p.free()
	inv.free()


func test_a_non_weapon_in_the_weapon_slot_refuses() -> void:
	var made := _armed_player(_make_misc(&"ration"))
	var p = made[0]
	var inv: CharacterInventory = made[1]
	assert_false(p.throw_equipped_weapon(), "only a real weapon item is throwable by this gesture")
	p.free()
	inv.free()


func test_a_dying_player_cannot_throw() -> void:
	# die() is already emptying your hands (the carried-prop stash / force-release). A throw over the cinematic would
	# race that cleanup and could leave a prop mid-flight across the in-place revive.
	var made := _armed_player(_make_weapon(&"knife"))
	var p = made[0]
	var inv: CharacterInventory = made[1]
	var knife: Item = inv.equipped_item
	p._dying = true
	assert_false(p.throw_equipped_weapon(), "no throw over the death cinematic")
	assert_true(inv.has(knife), "and the weapon is untouched — the respawn re-applies the save's equip")
	p.free()
	inv.free()


func test_a_dead_player_cannot_throw() -> void:
	var made := _armed_player(_make_weapon(&"knife"))
	var p = made[0]
	var inv: CharacterInventory = made[1]
	p._dead = true  # Character's latch, set BEFORE die() runs — checked as well as _dying so either path is covered
	assert_false(p.throw_equipped_weapon(), "a dead player throws nothing")
	p.free()
	inv.free()


# ---------------------------------------------------------------------------------------------------------------
# 3. PickupRay.throw_held — the shared full-impulse throw
# ---------------------------------------------------------------------------------------------------------------

func test_throwing_with_empty_hands_is_a_refusal_not_a_release() -> void:
	# Returning false (rather than falling into _release with nothing held) is what lets a caller read "I could not
	# throw" as "this press was not mine" — and it is why the guard sits BEFORE the GameSettings impulse read, so an
	# off-tree ray can answer at all.
	var ray := PickupRay.new()
	assert_false(ray.throw_held(), "empty hands: throw_held refuses and touches nothing")
	assert_null(ray.held_object, "and leaves the carry state exactly as it was")
	ray.free()
