class_name MoneyBag
extends RefCounted

## Builds the physics MONEY BAG the player drops when they dump their zorkmids (Player.drop_money). It's a real
## Throwable — grab it with the carry key, hurl it as a weapon — with a MoneyPickUp child so aiming + Interact
## scoops the whole purse back into your wallet and frees the bag. That's the same "dual item" a dropped weapon or
## a corpse's LootBag uses (a Throwable for the carry key + a LookAtInteractable child for Interact); PickupRay
## routes the carry key to the body and Interact to the child.
##
## A fat purse is a better bludgeon: the bag GROWS and HITS HARDER the more cash it holds — its size, mass, and the
## Throwable's impact_damage_mult all scale with the amount (soft curves, clamped, all knobs on EconomySettings).
## Built in code (like MoneyPickUp's fallback coin) so drop_money can size each bag to its exact drop — no scene.
##
## The size/mass/damage curves are PURE + static (explicit-arg, mirroring Throwable.loyal_scale) so they're
## unit-testable without a live GameSettings; build() reads the knobs off GameSettings.economy and applies them.

## Bag diameter (m) for `amount` zorkmids: min_size + per_sqrt·√amount, clamped to [min_size, max_size]. Sqrt so
## wealth reads fast at first then tapers — a modest purse already looks bigger; a fortune doesn't become a boulder.
static func size_for(amount: float, min_size: float, max_size: float, per_sqrt: float) -> float:
	var a := maxf(0.0, amount)
	return clampf(min_size + per_sqrt * sqrt(a), min_size, maxf(min_size, max_size))

## Bag mass (kg): base + per_zm·amount, clamped to [base, max_mass]. Heavier when richer, so a fat purse carries
## more momentum into whatever you bean with it.
static func mass_for(amount: float, base: float, per_zm: float, max_mass: float) -> float:
	var a := maxf(0.0, amount)
	return clampf(base + per_zm * a, base, maxf(base, max_mass))

## Throw-damage multiplier: 1 + per_zm·amount, clamped to [1, max_mult]. 1× for a near-empty purse; a real fortune
## swings like a wrecking ball (capped so it can't trivially one-shot everything).
static func damage_mult_for(amount: float, per_zm: float, max_mult: float) -> float:
	var a := maxf(0.0, amount)
	return clampf(1.0 + per_zm * a, 1.0, maxf(1.0, max_mult))

## Build a money bag holding `amount` zorkmids, ready to add_child into the world (the caller positions it —
## Player.drop_money drops it at the feet-forward point). Sizes the sack mesh + collider, sets the mass + throw-
## damage multiplier, and wires the MoneyPickUp reclaim child (Interact = pocket it all, free the bag).
static func build(amount: float) -> Throwable:
	var eco := GameSettings.economy
	var size := size_for(amount, eco.money_bag_min_size, eco.money_bag_max_size, eco.money_bag_size_per_sqrt_zm)

	var bag := Throwable.new()
	bag.name = &"MoneyBag"
	# A stray shot must NOT burst your purse and lose the cash — dropped weapons + corpse loot bags are
	# indestructible for the same reason. The bag only leaves the world by being looted (Interact) or falling out.
	bag.destructible = false
	bag.mass = mass_for(amount, eco.money_bag_base_mass, eco.money_bag_mass_per_zm, eco.money_bag_max_mass)
	bag.impact_damage_mult = damage_mult_for(amount, eco.money_bag_damage_per_zm, eco.money_bag_max_damage_mult)

	# The sack itself: the SAME bag.glb the corpse LootBag ships (and the inventory tile renders) — one bag model
	# everywhere, just scaled to this drop's wealth. Mirrors loot_bag.tscn's structure exactly: an EMPTY
	# MeshInstance3D root (the `mesh_instance` Throwable drives fade/breathe/outline through) with the GLB instanced
	# under it, scaled. _visual_aabb walks the child WITH its transform, so Throwable._ready auto-fits the collider —
	# and the MoneyPickUp child its interact hitbox — to the scaled bag; the RigidBody itself stays unscaled (no
	# scaled-physics weirdness). Added BEFORE the reclaim child so both auto-fits see it on _ready.
	var mi := _build_sack(size)
	bag.add_child(mi)
	bag.mesh_instance = mi

	var cs := CollisionShape3D.new()
	cs.name = &"Collider"
	cs.shape = BoxShape3D.new()  # Throwable._autofit_collision_shape resizes it to the sack's AABB in _ready
	bag.add_child(cs)
	bag.collision_shape = cs

	# Reclaim handler (the "dual item"): aim + Interact pockets the whole purse and frees the bag. highlight_target
	# is the BAG ROOT (not the sack mesh) so MoneyPickUp._host() resolves to the bag — Interact frees the WHOLE bag
	# (a mesh target would free only the sack), and the hover outline wraps it. auto_fit sizes the talk-hitbox to it.
	var reclaim := MoneyPickUp.new()
	reclaim.name = &"Reclaim"
	reclaim.amount = amount
	reclaim.highlight_target = bag
	reclaim.auto_fit_collider = true
	# A dropped money bag is a DYNAMIC spawn with no stable identity — it must never enter the world_objects ledger
	# (would clutter it and could mis-key onto a different object). Opt the reclaim child out of "gone" persistence
	# BEFORE add_child, so its _ready never records/reads a stray key. Hand-placed MoneyPickUps keep the default true.
	reclaim.persist_collected = false
	bag.add_child(reclaim)
	return bag


## The bag model — the ONE bag asset the game uses: scenes/bag.glb, same as the corpse LootBag
## (scenes/props/loot_bag.tscn) and the zorkmids inventory tile (Item.world_model). Do not substitute a
## procedural stand-in here; the drop must match the loot bag the player already knows.
const BAG_GLB := preload("res://assets/models/bag/bag.glb")
## Reference proportions taken from loot_bag.tscn: at GLB scale 0.18 the bag stands ~0.459 m tall (its authored
## collider height) with the visual offset -0.049 in Y to centre it on the body origin. Used to convert a target
## overall bag HEIGHT (m) into the GLB's instance scale + the matching centring offset.
const BAG_REF_SCALE: float = 0.18
const BAG_REF_HEIGHT: float = 0.459
const BAG_REF_Y_OFFSET: float = -0.049

## Build the money-sack visual at a given overall bag height `size` (m): an EMPTY MeshInstance3D root (what
## Throwable drives as `mesh_instance`) with bag.glb instanced under it, uniformly scaled from the loot_bag.tscn
## reference proportions and re-centred with the same proportional Y offset — so a wealth-scaled money bag is
## pixel-for-pixel the corpse loot bag at a different size.
static func _build_sack(size: float) -> MeshInstance3D:
	var root := MeshInstance3D.new()
	root.name = &"Sack"  # no mesh of its own — the GLB child is the visual, exactly like loot_bag.tscn's layout
	var bag_visual := BAG_GLB.instantiate() as Node3D
	if bag_visual == null:
		push_warning("MoneyBag: bag.glb did not instantiate a Node3D — the money bag will be invisible (collider keeps its authored default)")
		return root
	bag_visual.name = &"Bag"
	var s := BAG_REF_SCALE * (size / BAG_REF_HEIGHT)
	bag_visual.scale = Vector3.ONE * s
	bag_visual.position = Vector3(0.0, BAG_REF_Y_OFFSET * (s / BAG_REF_SCALE), 0.0)  # centre on the body origin, scaled proportionally
	root.add_child(bag_visual)
	return root
