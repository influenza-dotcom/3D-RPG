extends GutTest

## Pins the PURE scaling curves behind the dropped MONEY BAG (scripts/components/money_bag.gd): a fat purse is a
## bigger, heavier, harder-hitting throwable. The three curves are static + explicit-arg (no live GameSettings),
## mirroring Throwable.loyal_scale, so they're testable off-tree. build() itself (which wires the Throwable + the
## MoneyPickUp reclaim child) is in-tree behaviour verified by playtest, not re-run here.

# --- size: min + per_sqrt·√amount, clamped [min, max] --------------------------------------------------------

func test_size_floors_at_min_for_an_empty_or_negative_bag() -> void:
	assert_eq(MoneyBag.size_for(0.0, 0.25, 1.2, 0.05), 0.25,
		"a 0-zorkmid bag is the minimum size — the floor, never smaller")
	assert_eq(MoneyBag.size_for(-10.0, 0.25, 1.2, 0.05), 0.25,
		"a negative amount can't shrink the bag below the min (maxf(0) guard)")

func test_size_grows_with_wealth_on_a_sqrt_curve() -> void:
	# √100 = 10, so 0.25 + 0.05*10 = 0.75.
	assert_almost_eq(MoneyBag.size_for(100.0, 0.25, 1.2, 0.05), 0.75, 0.0001,
		"100 zorkmids grows the bag along the sqrt curve to 0.75 m")
	assert_true(MoneyBag.size_for(50.0, 0.25, 1.2, 0.05) > MoneyBag.size_for(10.0, 0.25, 1.2, 0.05),
		"more cash is always a bigger bag (monotonic in the unclamped range)")

func test_size_caps_at_max_for_a_fortune() -> void:
	assert_eq(MoneyBag.size_for(1000000.0, 0.25, 1.2, 0.05), 1.2,
		"however rich you are, the bag never grows past the max diameter (stays grabbable, not a boulder)")

# --- mass: base + per_zm·amount, clamped [base, max] ---------------------------------------------------------

func test_mass_scales_and_caps() -> void:
	assert_eq(MoneyBag.mass_for(0.0, 1.0, 0.02, 30.0), 1.0,
		"a near-empty purse is the base mass")
	assert_almost_eq(MoneyBag.mass_for(100.0, 1.0, 0.02, 30.0), 3.0, 0.0001,
		"100 zorkmids adds 100*0.02 = 2 kg on top of the 1 kg base")
	assert_eq(MoneyBag.mass_for(100000.0, 1.0, 0.02, 30.0), 30.0,
		"a fortune's mass caps so the bag isn't an immovable anchor")

# --- throw damage: 1 + per_zm·amount, clamped [1, max] -------------------------------------------------------

func test_damage_mult_is_one_when_empty_and_scales_with_wealth() -> void:
	assert_eq(MoneyBag.damage_mult_for(0.0, 0.05, 8.0), 1.0,
		"a broke bag hits like any prop its size — no bonus (1x)")
	assert_almost_eq(MoneyBag.damage_mult_for(20.0, 0.05, 8.0), 2.0, 0.0001,
		"20 zorkmids at 0.05/zm doubles the throw damage")
	assert_almost_eq(MoneyBag.damage_mult_for(100.0, 0.05, 8.0), 6.0, 0.0001,
		"100 zorkmids is a 6x wrecking ball")

func test_damage_mult_caps_and_never_drops_below_one() -> void:
	assert_eq(MoneyBag.damage_mult_for(100000.0, 0.05, 8.0), 8.0,
		"an obscene fortune's throw damage is capped so it can't trivially one-shot everything")
	assert_eq(MoneyBag.damage_mult_for(50.0, 0.05, 0.5), 1.0,
		"a max_mult authored below 1 still floors at 1x — a money bag never hits SOFTER than a plain prop")
