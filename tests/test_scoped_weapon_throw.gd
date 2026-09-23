extends GutTest

## The ADS + ATTACK weapon throw: aim down sights with the knife, pull the trigger, and the blade is HURLED down your
## look ray instead of swung. Three seams meet here and each has its own failure mode:
##   1. Attack.is_scoped_throw_gesture — WHICH trigger pulls are the throw (a pure static, the PickupRay.is_throw_release
##      idiom). Widen it and hip-firing the knife stops swinging; narrow it and the gesture silently dies.
##   2. Player.throw_equipped_weapon — the throw itself, and (the part pinned here) every REFUSAL. A refusal must leave
##      the backpack EXACTLY as it found it and return false, so Attack falls through to an ordinary attack. The bug
##      this guards against is the worst one available: an aimed trigger pull that quietly loses your only knife.
##   3. PickupRay.throw_held — the one definition of "a full throw", shared by the left-click fling and by the code-side
##      thrower above. Empty hands must be a false, not a release of nothing; a held prop must leave as a real throw.
##
## Off-tree, following tests/test_drop_held_weapon_toggle.gd: a bare player script instance, no _ready anywhere (see the
## CLAUDE.md rule). The throw's SUCCESS path physically needs a world (the pull parents a built drop under the player's
## parent and places it at the hold anchor), so it stays in-tree behaviour and is playtested.
##
## ⭐ WHY THE RIG (_rigged): a player with NO head refuses at the missing-carry-ray check no matter what else is true,
## so a refusal test built on that player cannot tell its own guard from the missing rig. Every Player refusal below
## therefore runs on a player that HAS a head and a free carry ray, whose bag is a spy that logs the pull's first
## question ("do you still hold this weapon?"). Each guard test first runs the CONTROL — the same rig, alive and
## wielding, reaches the pull — and then flips ONE condition and proves the pull is never asked for.

const PLAYER_PATH := "res://scripts/player/player.gd"

## A CharacterInventory that logs every has() question and answers it exactly as the real bag does (super). The pull
## (Player._pull_and_hold) asks the bag for the weapon before it touches anything else, so a logged question is the
## off-tree proof that a throw got past every one of throw_equipped_weapon's refusals. Built at runtime so no new
## script file (and .uid sidecar) is needed.
const SPY_INVENTORY_SOURCE := "extends CharacterInventory\n\nvar asked_for: Array = []\n\nfunc has(item: Item) -> bool:\n\tasked_for.append(item)\n\treturn super(item)\n"

var _spy_inventory_script: GDScript = null


func after_all() -> void:
	_spy_inventory_script = null


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


func _new_spy_inventory() -> Object:
	if _spy_inventory_script == null:
		_spy_inventory_script = GDScript.new()
		_spy_inventory_script.source_code = SPY_INVENTORY_SOURCE
		_spy_inventory_script.reload()
	return _spy_inventory_script.new()


## A LIVING player carrying `item` (and wielding it when `wield`) with a real carry rig: a Head whose pickup_ray is a
## free PickupRay. What it deliberately lacks is the in-tree half — the ray has no hold_anchor and the player has no
## parent world — so a throw that clears every refusal still backs out INSIDE the pull, before the bag is touched.
func _rigged(item: Item, wield: bool = true) -> Dictionary:
	var p = load(PLAYER_PATH).new()
	var inv = _new_spy_inventory()
	p.inventory = inv
	inv.add(item, 1)
	if wield:
		inv.equip_item(item)
	var head := Head.new()
	var ray := PickupRay.new()
	head.pickup_ray = ray
	p.head = head
	inv.asked_for.clear()  # only the throw's own questions count
	return {"p": p, "inv": inv, "head": head, "ray": ray}


func _free(fx: Dictionary) -> void:
	for key in ["p", "inv", "head", "ray"]:
		var o: Object = fx[key]
		if is_instance_valid(o):
			o.free()


## THE CONTROL each refusal test runs first: the same rig and the same kind of weapon, alive and wielding, DOES get
## through to the pull, asking the bag for exactly the wielded instance. Without it a refusal test would pass just as
## happily against a throw that refuses everything.
func _assert_control_reaches_the_pull() -> void:
	var knife := _make_weapon(&"control_knife")
	var fx := _rigged(knife)
	var inv = fx["inv"]
	fx["p"].throw_equipped_weapon()
	assert_eq(inv.asked_for.size(), 1,
		"CONTROL: a living player wielding a knife with a free carry ray must get past every refusal into the pull —"
		+ " if this fails, the refusal asserted after it proves nothing")
	assert_true(inv.asked_for.size() == 1 and inv.asked_for[0] == knife,
		"CONTROL: the pull asks for the WIELDED instance, not some other item in the bag")
	_free(fx)


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

func test_a_pull_that_cannot_be_built_refuses_keeps_the_weapon_and_lowers_the_carry_latch() -> void:
	# The off-tree stand-in for every "the throw could not be built" case (no hold anchor, no world): the throw clears
	# all its own refusals and enters the pull, and the pull backs out. THE invariant: backing out costs you nothing —
	# the knife is still in the bag AND still wielded, so the click falls through to an ordinary scoped swing.
	var knife := _make_weapon(&"knife")
	var fx := _rigged(knife)
	var p = fx["p"]
	var inv = fx["inv"]
	var ray: PickupRay = fx["ray"]
	assert_false(p.throw_equipped_weapon(), "a pull that cannot be built refuses instead of half-happening")
	assert_eq(inv.asked_for.size(), 1,
		"the throw really did reach the pull — so the refusal is the pull backing out, not an earlier guard")
	assert_true(inv.has(knife), "a refused throw leaves the weapon IN THE BACKPACK — it must never be lost")
	assert_eq(inv.equipped_item, knife, "and still WIELDED, so the fall-through swing has something to swing")
	assert_null(p.held_inventory_item(), "and nothing is left reserved as 'in your hands'")
	assert_null(ray.held_object, "and the carry ray grabbed nothing")
	assert_false(p._throwing_wielded_weapon,
		"and the zero-frame-carry latch raised for the pull is DOWN again — left up it would silently mute the holster"
		+ " dance and the FP-hands relay on every ordinary carry after it")
	_free(fx)


func test_no_carry_rig_refuses_and_keeps_the_weapon() -> void:
	_assert_control_reaches_the_pull()
	var knife := _make_weapon(&"knife")
	var fx := _rigged(knife)
	var p = fx["p"]
	var inv = fx["inv"]
	p.head = null  # the ONE difference from the control: no head, so no carry ray to throw from
	assert_false(p.throw_equipped_weapon(), "with no carry rig the throw refuses instead of half-happening")
	assert_eq(inv.asked_for.size(), 0, "and it refuses BEFORE the pull — nothing starts taking the knife out")
	assert_true(inv.has(knife), "a refused throw leaves the weapon IN THE BACKPACK")
	assert_eq(inv.equipped_item, knife, "and still WIELDED, so the fall-through swing has something to swing")
	_free(fx)


func test_bare_fists_refuse_the_throw() -> void:
	_assert_control_reaches_the_pull()
	var knife := _make_weapon(&"knife")
	var fx := _rigged(knife, false)  # the ONE difference: the knife is carried but NOT drawn — bare fists
	var p = fx["p"]
	var inv = fx["inv"]
	assert_false(p.throw_equipped_weapon(),
		"nothing equipped (bare fists) means there is no item to throw — an undrawn knife in the bag is not fair game")
	assert_eq(inv.asked_for.size(), 0, "the pull never starts, so the bag is never asked to give the knife up")
	assert_true(inv.has(knife), "the undrawn knife stays in the backpack")
	assert_null(inv.equipped_item, "and the refused throw did not draw it either")
	_free(fx)


func test_a_non_weapon_in_the_weapon_slot_refuses() -> void:
	_assert_control_reaches_the_pull()
	var ration := _make_misc(&"ration")
	var fx := _rigged(ration, false)
	var p = fx["p"]
	var inv = fx["inv"]
	# equip_item refuses a non-weapon, so this state has to be WRITTEN into the slot. equipped_item is a plain field
	# other code assigns directly (the Player's spawn loadout marking does), which is why the throw re-checks it.
	inv.equipped_item = ration
	assert_false(p.throw_equipped_weapon(), "only a real weapon item is throwable by this gesture")
	assert_eq(inv.asked_for.size(), 0, "a ration in the weapon slot never reaches the pull")
	assert_true(inv.has(ration), "and it stays in the backpack")
	_free(fx)


func test_a_dying_player_cannot_throw() -> void:
	# die() is already emptying your hands (the carried-prop stash / force-release). A throw over the cinematic would
	# race that cleanup and could leave a prop mid-flight across the in-place revive.
	_assert_control_reaches_the_pull()
	var knife := _make_weapon(&"knife")
	var fx := _rigged(knife)
	var p = fx["p"]
	var inv = fx["inv"]
	p._dying = true  # the ONE difference from the control
	assert_false(p.throw_equipped_weapon(), "no throw over the death cinematic")
	assert_eq(inv.asked_for.size(), 0,
		"the dying player never starts pulling the knife out — with a free carry ray in place, the death latch is the"
		+ " only thing that stopped it")
	assert_true(inv.has(knife), "and the weapon is untouched — the respawn re-applies the save's equip")
	assert_eq(inv.equipped_item, knife, "and still the wielded item")
	_free(fx)


func test_a_dead_player_cannot_throw() -> void:
	_assert_control_reaches_the_pull()
	var knife := _make_weapon(&"knife")
	var fx := _rigged(knife)
	var p = fx["p"]
	var inv = fx["inv"]
	p._dead = true  # Character's latch, set BEFORE die() runs — checked as well as _dying so either path is covered
	assert_false(p.throw_equipped_weapon(), "a dead player throws nothing")
	assert_eq(inv.asked_for.size(), 0,
		"the dead player never starts pulling the knife out — the Character death latch alone must stop it")
	assert_true(inv.has(knife), "and the weapon stays in the backpack")
	assert_eq(inv.equipped_item, knife, "and still the wielded item")
	_free(fx)


# ---------------------------------------------------------------------------------------------------------------
# 3. PickupRay.throw_held — the shared full-impulse throw
# ---------------------------------------------------------------------------------------------------------------

func test_throwing_with_empty_hands_is_a_refusal_not_a_release() -> void:
	# Returning false (rather than falling into _release with nothing held) is what lets a caller read "I could not
	# throw" as "this press was not mine" — and it is why the guard sits BEFORE the GameSettings impulse read, so an
	# off-tree ray can answer at all.
	var ray := PickupRay.new()
	watch_signals(ray)
	assert_false(ray.throw_held(), "empty hands: throw_held refuses")
	assert_signal_not_emitted(ray, "carry_changed",
		"and announces no release — a carry_changed(false) for nothing would tell the player's hands a carry just"
		+ " ended when none began")
	ray.free()


func test_throwing_a_held_prop_launches_it_as_a_full_throw() -> void:
	# The success half of the definition, and the control for the refusal above: the same bare ray, now holding a
	# prop, DOES let go. "A full throw" is more than letting go — it must be the throw-strength release that arms the
	# throw-only behaviours (the streak, the nosing, the throw sound), never the gentle tap-drop of a short F press.
	var ray := PickupRay.new()
	var prop := Throwable.new()  # off-tree: no _ready runs; just a body to hold and launch
	ray.held_object = prop
	ray._holding = true  # set alongside held_object by every real grab (PickupRay._pick_up)
	watch_signals(ray)
	assert_true(ray.throw_held(), "holding a prop, throw_held throws it and says so")
	assert_null(ray.held_object, "the prop has left your hands")
	assert_signal_emit_count(ray, "carry_changed", 1, "exactly one carry_changed for the release")
	assert_signal_emitted_with_parameters(ray, "carry_changed", [false], 0)
	assert_true(prop.is_trailing(),
		"it left as a real THROW — the in-flight streak is armed, which a tap-drop never does")
	assert_lt(prop.linear_velocity.z, -GameSettings.physics_damage.pickup_drop_impulse,
		"launched FORWARD down the look ray (-Z), harder than a tap-drop would set it down")
	prop.free()
	ray.free()
