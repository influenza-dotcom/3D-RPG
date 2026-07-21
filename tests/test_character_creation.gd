extends GutTest

## Character-creation stat allocation. The ZERO-SUM allocator now lives in a pure StatBudget (scripts/ui/stat_budget.gd):
## every stat starts at 0; a "+" must be paid for by a "−" elsewhere (net never > 0); underspending into a
## net-negative (deliberately weak) build is allowed; each stat clamps to [STAT_MIN, STAT_MAX]. Those RULES are
## pinned OFF-TREE on StatBudget directly — no scene boot. The WIDGET/SIGNAL contract (stepper enable/disable +
## the confirmed(name, stats, appearance) payload StartMenu consumes) stays IN-TREE on the real screen, because
## the screen's _ready builds the full overlay incl. a live 3D CharacterPreview.

const CC_PATH := "res://scripts/ui/character_creation.gd"
const CC := preload(CC_PATH)  # read STAT_MIN / STAT_MAX consts off the script without booting the screen
const StatBudgetScript := preload("res://scripts/ui/stat_budget.gd")


# --- Pure allocator rules: StatBudget, off-tree, no screen boot ------------------------------------------------

func _budget():
	# Mirror the real config: the same stat list the screen uses, and its clamp bounds.
	return StatBudgetScript.new(CharacterStats.STAT_NAMES, CC.STAT_MIN, CC.STAT_MAX)

func test_all_stats_start_at_zero_with_no_spare_points() -> void:
	var b = _budget()
	assert_eq(b.spare(), 0, "a fresh sheet is all-zero, so there are no spare points")
	for stat in CharacterStats.STAT_NAMES:
		assert_eq(int(b.values[stat]), 0, "%s starts at baseline 0" % stat)
	b = null

func test_cannot_raise_without_freeing_a_point_first() -> void:
	var b = _budget()
	assert_false(b.try_raise(&"strength"), "raising from an all-zero sheet is refused (net can't exceed 0)")
	assert_eq(int(b.values[&"strength"]), 0, "the refused raise left the stat at baseline 0")
	assert_eq(b.spare(), 0, "still no spare points")
	b = null

func test_lower_then_raise_is_zero_sum() -> void:
	var b = _budget()
	assert_true(b.try_lower(&"agility"), "lowering a stat frees a point")
	assert_eq(int(b.values[&"agility"]), -1, "lowering a stat has no floor at 0 — negatives are real")
	assert_eq(b.spare(), 1, "lowering frees one point to spend")
	assert_true(b.try_raise(&"gunplay"), "the freed point can be spent elsewhere")
	assert_eq(int(b.values[&"gunplay"]), 1, "the freed point raised another stat")
	assert_eq(b.spare(), 0, "the build is back to net 0 (zero-sum)")
	b = null

func test_underspend_leaves_net_negative() -> void:
	var b = _budget()
	b.try_lower(&"larceny")
	b.try_lower(&"larceny")    # two spare points freed
	b.try_raise(&"strength")   # spend one, leave one unspent
	assert_eq(b.spare(), 1, "you may leave points unspent — a deliberately weaker (net-negative) build")
	assert_lte(b.net(), 0, "the net allocation is never positive")
	b = null

func test_clamps_at_min_and_max() -> void:
	var b = _budget()
	for i in range(12):
		b.try_lower(&"gunplay")   # dump one stat well past the floor
	assert_eq(int(b.values[&"gunplay"]), CC.STAT_MIN, "a stat can't be lowered below STAT_MIN")
	assert_false(b.can_lower(&"gunplay"), "at the floor, lowering is no longer allowed")
	# Free plenty of points (three stats at the floor), then overfill one stat -> clamps at STAT_MAX.
	for i in range(12):
		b.try_lower(&"streetwise")
	for i in range(12):
		b.try_lower(&"agility")
	for i in range(30):
		b.try_raise(&"strength")
	assert_eq(int(b.values[&"strength"]), CC.STAT_MAX, "a stat can't be raised above STAT_MAX, even with spare points")
	assert_false(b.can_raise(&"strength"), "at the ceiling, raising is no longer allowed")
	b = null


# --- Widget + signal contract: the real screen, in-tree -------------------------------------------------------

func _make_screen():
	var cc = load(CC_PATH).new()
	add_child_autofree(cc)  # _ready builds the UI (incl. the 3D preview) and seeds the StatBudget to all-zero
	return cc

func test_shirt_preview_does_not_auto_rotate_while_painting() -> void:
	var cc = _make_screen()
	assert_true(cc._preview.auto_rotate, "the Look preview keeps its showcase turntable")
	assert_false(cc._shirt_preview.auto_rotate, "the Shirt preview holds still while painting")

func test_plus_steppers_gate_on_spare_points() -> void:
	var cc = _make_screen()
	assert_true((cc._plus_buttons[&"strength"] as Button).disabled, "the + stepper is disabled with no spare points")
	cc._on_minus(&"strength")
	assert_false((cc._plus_buttons[&"gunplay"] as Button).disabled, "freeing a point enables the + steppers")

func test_steppers_disable_at_caps() -> void:
	var cc = _make_screen()
	for i in range(12):
		cc._on_minus(&"gunplay")
	assert_true((cc._minus_buttons[&"gunplay"] as Button).disabled, "the − stepper disables at the floor (STAT_MIN)")
	for i in range(12):
		cc._on_minus(&"streetwise")
	for i in range(12):
		cc._on_minus(&"agility")
	for i in range(30):
		cc._on_plus(&"strength")
	assert_true((cc._plus_buttons[&"strength"] as Button).disabled, "the + stepper disables at the ceiling (STAT_MAX)")

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

# A run MUST be NAMED before it can begin: Begin is gated OFF while the name is blank (widget state), and _on_begin
# refuses to emit a nameless run (the backstop). Setting .text in code doesn't emit text_changed, so we drive
# _on_name_changed as the LineEdit signal would.
func test_begin_disabled_until_named() -> void:
	var cc = _make_screen()
	assert_true((cc._begin_btn as Button).disabled, "Begin boots disabled on a fresh, unnamed sheet")
	assert_true(cc._name_hint.visible, "the 'name required' hint shows while unnamed")
	cc._name_edit.text = "Rae Vandel"
	cc._on_name_changed("Rae Vandel")
	assert_false((cc._begin_btn as Button).disabled, "naming the character enables Begin")
	assert_false(cc._name_hint.visible, "the hint hides once a name is entered")
	cc._name_edit.text = "   "  # whitespace-only strips to empty -> still unnamed
	cc._on_name_changed("   ")
	assert_true((cc._begin_btn as Button).disabled, "a whitespace-only name still counts as unnamed")
	assert_true(cc._name_hint.visible, "the hint returns when the name is cleared to blank")

func test_begin_refuses_blank_name() -> void:
	var cc = _make_screen()
	cc._name_edit.text = "   "  # blank after strip_edges
	watch_signals(cc)
	cc._on_begin()
	assert_signal_not_emitted(cc, "confirmed", "Begin refuses to emit a nameless run even if pressed while blank")
