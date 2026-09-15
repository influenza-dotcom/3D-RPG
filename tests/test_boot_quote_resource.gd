extends GutTest

## BootQuote (resources/ui/boot_quote.gd) — the one-quote Resource the boot card reads (`.text` / `.attribution`).
## tests/test_boot_quotes.gd pins the authored POOL (boot_quotes.tres); this pins the SCRIPT itself: a fresh
## BootQuote ships blank on both fields (so a half-authored entry fails the pool test rather than showing a
## stale default), `text` is a MULTILINE export (the card centres each hard line break the designer presses
## Enter for), and every authored pool entry is this class.

const SCRIPT_PATH := "res://resources/ui/boot_quote.gd"
const POOL_PATH := "res://resources/ui/boot_quotes.tres"


func test_fresh_quote_is_blank_on_both_fields() -> void:
	var q := BootQuote.new()
	assert_true(q is Resource, "a Resource, so it can be authored inline in a BootQuotes .tres")
	assert_eq(q.text, "", "text ships blank — no stale default can leak onto the card")
	assert_eq(q.attribution, "", "attribution ships blank")
	q = null


func test_fields_round_trip_and_duplicate() -> void:
	var q := BootQuote.new()
	q.text = "Line one\nLine two"
	q.attribution = "Samuel \"Bodyshot\" Johnson"
	assert_eq(q.text, "Line one\nLine two", "text keeps its hard line breaks")
	assert_eq(q.attribution, "Samuel \"Bodyshot\" Johnson", "attribution keeps quotes")
	var d := q.duplicate() as BootQuote
	assert_eq(d.text, q.text, "duplicate copies text")
	assert_eq(d.attribution, q.attribution, "duplicate copies attribution")
	q = null
	d = null


func test_text_is_a_multiline_export() -> void:
	var q := BootQuote.new()
	var hint := -1
	var attrib_exported := false
	for p in q.get_property_list():
		if p.name == "text":
			hint = p.hint
		elif p.name == "attribution":
			attrib_exported = (p.usage & PROPERTY_USAGE_EDITOR) != 0
	assert_eq(hint, PROPERTY_HINT_MULTILINE_TEXT, "`text` must be @export_multiline so Enter inserts the line breaks the card centres")
	assert_true(attrib_exported, "`attribution` must be exported for the inspector")
	q = null


func test_the_authored_pool_is_made_of_this_class() -> void:
	var pool = load(POOL_PATH)
	assert_not_null(pool, "boot_quotes.tres must load")
	if pool == null or not ("quotes" in pool):
		return
	for q in pool.quotes:
		assert_true(q is BootQuote, "every pool entry must be a BootQuote (the card reads .text / .attribution off it)")
		if q is BootQuote:
			assert_eq((q.get_script() as Script).resource_path, SCRIPT_PATH, "…running boot_quote.gd")
