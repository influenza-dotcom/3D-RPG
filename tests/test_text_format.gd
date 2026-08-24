extends GutTest

## TextFormat (scripts/ui/text_format.gd) — the substitution / number / plural seams under THE RULE:
## substitute into ONE whole authored template via named tokens, or SELECT between whole templates;
## never splice prose fragments. These pins are the contract PlayerText (and later the per-locale
## work) builds on: token replacement is order-free and %-safe, num() is byte-identical to the old
## per-file "%.*f" + rstrip idiom (every historic copy delegates now — Zorkmids.fmt, StatInfo._num,
## ItemInfo._num, StatsScreen._stat_num), and plural() is the English singular/other split that
## tr_n() will widen later.


# --- subst: {name}-token replacement -----------------------------------------------------------------

func test_subst_replaces_named_tokens() -> void:
	assert_eq(TextFormat.subst("Hello {name}!", {"name": "Bob"}), "Hello Bob!",
		"a {token} is replaced with its dictionary value")


func test_subst_tokens_may_be_reordered_by_the_template() -> void:
	assert_eq(TextFormat.subst("{second} before {first}", {"first": "A", "second": "B"}), "B before A",
		"replacement is name-keyed, not positional — a translation may reorder tokens freely")


func test_subst_literal_percent_is_safe() -> void:
	# The whole reason subst is replace-based, not the '%' format operator: a designer's/translator's
	# literal percent (or even a stray legacy "%s") must never raise a format error.
	assert_eq(TextFormat.subst("10% off {item}", {"item": "hats"}), "10% off hats",
		"a literal % in the template never errors and never eats the token")
	assert_eq(TextFormat.subst("legacy %s stays put {n}", {"n": 1}), "legacy %s stays put 1",
		"a legacy %s slot is inert to subst (call sites that still honour it replace it themselves)")


func test_subst_missing_token_stays_visible() -> void:
	# Pinned DECISION: an unfilled {token} is left in the output — a loud authoring bug marker,
	# never a silently blank hole in the sentence.
	assert_eq(TextFormat.subst("Hi {name}", {}), "Hi {name}",
		"a token the caller forgot to supply stays visible in the rendered string")


func test_subst_extra_tokens_are_noops() -> void:
	assert_eq(TextFormat.subst("plain", {"unused": "x"}), "plain",
		"dictionary entries with no matching {token} change nothing")


func test_subst_stringifies_non_string_values() -> void:
	assert_eq(TextFormat.subst("{n} of {total}", {"n": 3, "total": 12.5}), "3 of 12.5",
		"ints/floats can be passed raw — values are str()-converted")


# --- num: THE number formatter (parity with the old idiom) --------------------------------------------

func test_num_trims_trailing_zeros_and_dot() -> void:
	assert_eq(TextFormat.num(12.0), "12", "whole amounts print bare — never a noisy '12.00'")
	assert_eq(TextFormat.num(12.5), "12.5", "one live decimal survives the trim")
	assert_eq(TextFormat.num(0.75), "0.75", "two live decimals survive the trim")
	assert_eq(TextFormat.num(0.0), "0", "zero prints as a bare '0'")
	assert_eq(TextFormat.num(3.1), "3.1", "float representation noise (3.1000...) still prints '3.1'")


func test_num_negatives() -> void:
	assert_eq(TextFormat.num(-0.5), "-0.5", "a negative keeps its minus")
	assert_eq(TextFormat.num(-12.0), "-12", "a whole negative prints bare")
	assert_eq(TextFormat.num(-0.001), "0",
		"a negative that ROUNDS to zero prints '0', not '-0' — parity with the old int() display path")


func test_num_zero_decimals_keeps_integer_zeros() -> void:
	# rstrip("0") on a dot-less string would eat real zeros ("120" -> "12"); decimals <= 0 must skip the trim.
	assert_eq(TextFormat.num(120.0, 0), "120", "decimals=0 must not strip integer trailing zeros")
	assert_eq(TextFormat.num(100.0, 0), "100", "…same for a round hundred")


func test_num_respects_decimals_argument() -> void:
	assert_eq(TextFormat.num(2.0, 1), "2", "decimals=1 still trims a .0")
	# 2.26, not 2.25: an exactly-representable .x5 tie could banker's-round down on some platforms —
	# this pin is about the decimals argument, not tie-breaking policy.
	assert_eq(TextFormat.num(2.26, 1), "2.3", "decimals=1 rounds to one place (printf rounding)")


func test_zorkmids_fmt_delegates_with_identical_output() -> void:
	# The zorkmids.gd copy of the idiom is GONE — fmt is quantize + TextFormat.num. Spot-check the
	# exact shapes test_money.gd pins, through the new path.
	for pair: Array in [[12.0, "12"], [100.0, "100"], [0.0, "0"], [12.5, "12.5"], [0.75, "0.75"], [3.1, "3.1"], [-0.5, "-0.5"], [0.999999, "1"], [12.000001, "12"]]:
		assert_eq(Zorkmids.fmt(float(pair[0])), String(pair[1]),
			"Zorkmids.fmt(%s) must still print '%s' after delegating to TextFormat.num" % [pair[0], pair[1]])


func test_stat_and_item_readout_copies_delegate_to_num() -> void:
	# The LAST per-file copies of the trim idiom are gone — StatInfo._num / ItemInfo._num / StatsScreen._stat_num
	# are TextFormat.num at decimals=1 (the old "%.1f" shape). Spot-check the one-decimal shapes through each seam.
	for pair: Array in [[4.0, "4"], [4.5, "4.5"], [-0.5, "-0.5"], [12.34, "12.3"], [0.0, "0"]]:
		assert_eq(StatInfo._num(float(pair[0])), String(pair[1]),
			"StatInfo._num(%s) must print '%s' after delegating to TextFormat.num" % [pair[0], pair[1]])
		assert_eq(ItemInfo._num(float(pair[0])), String(pair[1]),
			"ItemInfo._num(%s) must print '%s' after delegating to TextFormat.num" % [pair[0], pair[1]])
	var screen: Variant = load("res://scripts/ui/stats_screen.gd").new()  # off-tree, never added -> _ready never runs (test rules)
	assert_eq(screen._stat_num(4.5), "4.5", "StatsScreen._stat_num delegates to TextFormat.num too")
	assert_eq(screen._stat_num(12.0), "12", "…and still prints a whole value bare")
	screen.free()


# --- plural: the future tr_n() seam -------------------------------------------------------------------

func test_plural_selects_whole_variants() -> void:
	assert_eq(TextFormat.plural(1, "{n} item", "{n} items"), "{n} item", "count 1 -> the singular template")
	assert_eq(TextFormat.plural(2, "{n} item", "{n} items"), "{n} items", "count 2 -> the plural template")
	assert_eq(TextFormat.plural(0, "{n} item", "{n} items"), "{n} items", "English: zero takes the plural form")
	assert_eq(TextFormat.plural(-1, "{n} item", "{n} items"), "{n} items", "a negative count takes the plural form")


# --- pad2: the clock-face zero-pad --------------------------------------------------------------------

func test_pad2_zero_pads_to_two_digits() -> void:
	assert_eq(TextFormat.pad2(0), "00", "midnight's hour and minute both pad to two digits")
	assert_eq(TextFormat.pad2(7), "07", "a single digit gains a leading zero")
	assert_eq(TextFormat.pad2(35), "35", "a two-digit value is unchanged")

func test_pad2_does_not_truncate_a_wide_value() -> void:
	# Only the PADDING is promised. A silently clipped number is worse than a wide one, so a value outside
	# 0..99 prints in full rather than losing its leading digit.
	assert_eq(TextFormat.pad2(123), "123", "a wide value prints in full, never truncated to two characters")
	assert_eq(TextFormat.pad2(-5), "-5", "a negative value keeps its sign rather than being mangled")

func test_pad2_is_the_padding_seam_num_cannot_be() -> void:
	# Why this exists at all: num() TRIMS, and has no width option — so it can never produce a clock face.
	assert_eq(TextFormat.num(5.0, 0), "5", "num trims to the bare integer...")
	assert_eq(TextFormat.pad2(5), "05", "...which is exactly what a clock face must not do")


# --- Zorkmids.money_text: the ONE "<amount> zm" template ----------------------------------------------

func test_money_text_owns_the_currency_word() -> void:
	assert_eq(Zorkmids.money_text(12.0), "12 zm", "whole amount + the authored currency word, one space")
	assert_eq(Zorkmids.money_text(0.5), "0.5 zm", "fractional amounts ride the same single template")
	assert_eq(Zorkmids.money_text(50.5), "50.5 zm",
		"the hospital-bill amount shape — PlayerText money toasts substitute this as their {money} token")
