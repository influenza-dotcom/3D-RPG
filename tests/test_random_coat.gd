extends GutTest

## Tests for RandomCoat — the "pick a random albedo per instance" cosmetic drop-in. The PICK is pure static maths
## (literal rolls, no tree), so it's unit-tested here. The actual recolour (duplicate material_override + set albedo)
## is in-tree / deferred and needs a real MeshInstance3D + host, so it's manual-playtest only (mirrors PropFollow,
## whose in-tree teleport is likewise playtest-only).

const RandomCoat := preload("res://scripts/components/random_coat.gd")


func test_pick_index_low_roll_first() -> void:
	assert_eq(RandomCoat.pick_index(6, 0.0), 0, "a roll of 0 selects the first coat in the pool")


func test_pick_index_high_roll_last() -> void:
	# randf() returns [0,1) so 0.999… is the practical top; it must land on the LAST index, never out of bounds.
	assert_eq(RandomCoat.pick_index(6, 0.999), 5, "a near-1 roll selects the last coat (never past the end)")


func test_pick_index_midpoint() -> void:
	assert_eq(RandomCoat.pick_index(4, 0.5), 2, "the midpoint roll lands in the middle of the pool")


func test_pick_index_clamps_at_one() -> void:
	# Defensive: even a roll of exactly 1.0 (which randf never returns) must clamp inside the pool, not overflow.
	assert_eq(RandomCoat.pick_index(3, 1.0), 2, "a roll of 1.0 clamps to the last index instead of going out of range")


func test_pick_index_empty_pool_safe() -> void:
	assert_eq(RandomCoat.pick_index(0, 0.7), 0, "an empty pool returns 0 rather than dividing into nothing / erroring")


func test_pick_index_single_option() -> void:
	assert_eq(RandomCoat.pick_index(1, 0.42), 0, "a one-coat pool always returns the only index")


func test_enabled_by_default() -> void:
	# Off-tree field read — no add_child, so no _ready/deferred coat runs. The component ships ON so a dog wearing it
	# gets a random coat out of the box; a designer flips it off to pin a specific look.
	var c = RandomCoat.new()
	assert_true(c.enabled, "RandomCoat ships enabled — dropping it on a prop randomises the coat by default")
	assert_eq(c.coat_tints.size(), 0, "the tint pool is empty by default (the dog scene authors its own natural coats)")
	assert_eq(c.coat_value_mults.size(), 0, "no coat prices by default -> every coat is worth the same (backwards-compatible)")
	c.free()


# ---------------------------------------------------------------------------
# Coat-based pricing — rarer coats sell for more (folded into DogPickup value)
# ---------------------------------------------------------------------------

func test_value_mult_reads_index_aligned_entry() -> void:
	# A coat's price multiplier is the coat_value_mults entry index-aligned to the coat_tints entry it matches.
	var c := RandomCoat.new()
	var tints: Array[Color] = [Color(1, 1, 1, 1), Color(0.17, 0.17, 0.18, 1)]
	var mults: Array[float] = [1.0, 3.0]
	c.coat_tints = tints
	c.coat_value_mults = mults
	assert_almost_eq(c.value_mult_for_tint(Color(0.17, 0.17, 0.18, 1)), 3.0, 0.0001,
		"a rare (black) coat prices at its ×3.0 pool entry")
	assert_almost_eq(c.value_mult_for_tint(Color(1, 1, 1, 1)), 1.0, 0.0001,
		"the plain white coat prices at its ×1.0 entry")
	c.free()


func test_value_mult_unmatched_tint_is_neutral() -> void:
	# An arbitrary colour off no pool entry (a spray-paint recolour) matches nothing -> the neutral ×1.0, so painting a
	# prize coat can't accidentally inflate (or the match-tolerance mis-price) its value.
	var c := RandomCoat.new()
	var tints: Array[Color] = [Color(1, 1, 1, 1), Color(0.17, 0.17, 0.18, 1)]
	var mults: Array[float] = [1.0, 3.0]
	c.coat_tints = tints
	c.coat_value_mults = mults
	assert_almost_eq(c.value_mult_for_tint(Color(0.9, 0.1, 0.5, 1)), 1.0, 0.0001,
		"a colour matching no coat prices at the neutral ×1.0")
	c.free()


func test_value_mult_no_prices_authored_is_neutral() -> void:
	# The backwards-compatible default: coats but no multipliers -> every coat prices ×1.0 (old scenes are unaffected).
	var c := RandomCoat.new()
	var tints: Array[Color] = [Color(1, 1, 1, 1), Color(0.17, 0.17, 0.18, 1)]
	c.coat_tints = tints
	assert_almost_eq(c.value_mult_for_tint(Color(0.17, 0.17, 0.18, 1)), 1.0, 0.0001,
		"with no coat_value_mults authored, every coat is worth the same ×1.0")
	c.free()


func test_value_mult_short_pool_falls_back_to_neutral() -> void:
	# A multiplier pool SHORTER than the tint pool: coats past the end have no authored price -> ×1.0 (the config
	# warning nags the designer to align them, but pricing stays safe).
	var c := RandomCoat.new()
	var tints: Array[Color] = [Color(1, 1, 1, 1), Color(0.17, 0.17, 0.18, 1)]
	var mults: Array[float] = [2.0]  # only prices the first coat
	c.coat_tints = tints
	c.coat_value_mults = mults
	assert_almost_eq(c.value_mult_for_tint(Color(1, 1, 1, 1)), 2.0, 0.0001, "the priced coat uses its entry")
	assert_almost_eq(c.value_mult_for_tint(Color(0.17, 0.17, 0.18, 1)), 1.0, 0.0001,
		"a coat past the end of a short multiplier pool falls back to ×1.0")
	c.free()


func test_effective_value_mult_prefers_preset() -> void:
	# A re-dropped dog carries a preset_tint and must be priced from THAT restored colour the instant it spawns (its
	# roll is skipped) — effective_value_mult reads the preset, not the not-yet-applied mesh colour. Off-tree safe: the
	# preset branch never touches get_parent().
	var c := RandomCoat.new()
	var tints: Array[Color] = [Color(1, 1, 1, 1), Color(0.17, 0.17, 0.18, 1)]
	var mults: Array[float] = [1.0, 3.0]
	c.coat_tints = tints
	c.coat_value_mults = mults
	c.preset_tint = Color(0.17, 0.17, 0.18, 1)
	assert_almost_eq(c.effective_value_mult(), 3.0, 0.0001,
		"a re-dropped (preset) rare coat keeps its ×3.0 price, so the dog round-trips its value as well as its colour")
	c.free()


func test_config_warning_flags_length_mismatch() -> void:
	# The @tool guard-rail: a multiplier pool whose length differs from the tint pool would silently mis-price, so it
	# warns. Empty multipliers ("price all coats the same") is NOT a mismatch.
	var c := RandomCoat.new()
	var tints: Array[Color] = [Color(1, 1, 1, 1), Color(0.17, 0.17, 0.18, 1)]
	c.coat_tints = tints
	assert_eq(c._get_configuration_warnings().size(), 0, "no multipliers authored is fine — no warning")
	var short_mults: Array[float] = [1.0]
	c.coat_value_mults = short_mults
	assert_gt(c._get_configuration_warnings().size(), 0, "a length mismatch warns the designer to align the pools")
	c.free()
