extends GutTest

## Character-creation budget logic: the ZERO-SUM stat allocator. Every stat starts at 0; a "+" must be paid for by
## a "−" elsewhere so the net allocation never exceeds 0; underspending into a net-negative (deliberately weak)
## build is allowed; there is NO per-stat cap. Plus the confirm-emit contract StartMenu consumes.
##
## The screen is a light UI Control (not a Player/NPC), so building it in-tree is safe — add_child_autofree runs its
## _ready (which builds the widgets + seeds every stat to 0). We then drive its public interaction methods directly.

const CC_PATH := "res://scripts/ui/character_creation.gd"

func _make_screen():
	var cc = load(CC_PATH).new()
	add_child_autofree(cc)  # _ready builds the UI and seeds every stat to 0
	return cc

func test_all_stats_start_at_zero_with_no_spare_points() -> void:
	var cc = _make_screen()
	assert_eq(cc._spare(), 0, "a fresh sheet is all-zero, so there are no spare points")
	for stat in cc.STATS:
		assert_eq(int(cc._values[stat]), 0, "%s starts at baseline 0" % stat)

func test_cannot_raise_without_freeing_a_point_first() -> void:
	var cc = _make_screen()
	cc._on_plus(&"strength")  # no spare points -> refused (net can't exceed 0)
	assert_eq(int(cc._values[&"strength"]), 0, "raising a stat from an all-zero sheet is refused")
	assert_eq(cc._spare(), 0, "still no spare points")

func test_lower_then_raise_is_zero_sum() -> void:
	var cc = _make_screen()
	cc._on_minus(&"agility")                # frees a point
	assert_eq(int(cc._values[&"agility"]), -1, "lowering a stat has no floor")
	assert_eq(cc._spare(), 1, "lowering frees one point to spend")
	cc._on_plus(&"gunplay")                 # spend it elsewhere
	assert_eq(int(cc._values[&"gunplay"]), 1, "the freed point is spent raising another stat")
	assert_eq(cc._spare(), 0, "the build is back to net 0 (zero-sum)")

func test_plus_steppers_gate_on_spare_points() -> void:
	var cc = _make_screen()
	assert_true((cc._plus_buttons[&"strength"] as Button).disabled, "the + stepper is disabled with no spare points")
	cc._on_minus(&"strength")
	assert_false((cc._plus_buttons[&"gunplay"] as Button).disabled, "freeing a point enables the + steppers")

func test_underspend_leaves_net_negative() -> void:
	var cc = _make_screen()
	cc._on_minus(&"stealth")
	cc._on_minus(&"stealth")   # two spare points
	cc._on_plus(&"strength")     # spend one, leave one unspent
	assert_eq(cc._spare(), 1, "you may leave points unspent — a deliberately weaker (net-negative) build")
	var net := 0
	for stat in cc.STATS:
		net += int(cc._values[stat])
	assert_lte(net, 0, "the net allocation is never positive")

func test_per_stat_caps_clamp_at_min_and_max() -> void:
	var cc = _make_screen()
	# Dump one stat well past the floor -> clamps at STAT_MIN (-5), and the − stepper disables there.
	for i in range(12):
		cc._on_minus(&"gunplay")
	assert_eq(int(cc._values[&"gunplay"]), cc.STAT_MIN, "a stat can't be lowered below STAT_MIN (-5)")
	assert_true((cc._minus_buttons[&"gunplay"] as Button).disabled, "the − stepper disables at the floor")
	# Free plenty of points (three stats at -5 = 15 spare), then overfill one stat -> clamps at STAT_MAX (+10).
	for i in range(12):
		cc._on_minus(&"streetwise")
	for i in range(12):
		cc._on_minus(&"agility")
	for i in range(20):
		cc._on_plus(&"strength")
	assert_eq(int(cc._values[&"strength"]), cc.STAT_MAX, "a stat can't be raised above STAT_MAX (+10), even with spare points")
	assert_true((cc._plus_buttons[&"strength"] as Button).disabled, "the + stepper disables at the ceiling")

func test_confirm_emits_trimmed_name_and_stat_dict() -> void:
	var cc = _make_screen()
	cc._name_edit.text = "  Rae Vandel  "
	cc._on_minus(&"agility")
	cc._on_plus(&"strength")
	watch_signals(cc)
	cc._on_begin()
	assert_signal_emitted(cc, "confirmed", "Begin emits the confirmed signal")
	var params: Array = get_signal_parameters(cc, "confirmed")  # [character_name, stat_values, appearance]
	assert_eq(str(params[0]), "Rae Vandel", "the name is trimmed before it's emitted")
	var sv: Dictionary = params[1]
	assert_eq(int(sv[&"strength"]), 1, "the emitted stat dict carries the raised stat")
	assert_eq(int(sv[&"agility"]), -1, "the emitted stat dict carries the lowered (negative) stat")
	# The third param is the appearance the Look tab built (head/body ids + colours) — StartMenu stamps it onto GameState.
	assert_true(params[2] is Dictionary, "the appearance dict is emitted as the third param")
	var appearance: Dictionary = params[2]
	assert_true(appearance.has("head") and appearance.has("body"), "the appearance carries a head + body pick")
