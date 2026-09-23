extends GutTest

## BootQuote (resources/ui/boot_quote.gd) — the one-quote Resource the boot card reads (`.text` / `.attribution`).
## tests/test_boot_quotes.gd pins the authored POOL (boot_quotes.tres); this pins the SCRIPT itself: a new
## BootQuote starts blank on both fields (so a half-authored entry fails the pool guard rather than showing a
## stale default), `text` is a MULTILINE export (the card centres each hard line break the designer presses
## Enter for), and every authored pool entry is this class.

const SCRIPT_PATH := "res://resources/ui/boot_quote.gd"
const POOL_PATH := "res://resources/ui/boot_quotes.tres"


## The content guard tests/test_boot_quotes.gd runs over the authored pool: a quote the card can actually show.
func _is_authored(q: BootQuote) -> bool:
	return q.text.strip_edges() != "" and q.attribution.strip_edges() != ""


func test_a_new_pool_entry_starts_blank_so_the_pool_guard_catches_it() -> void:
	# A designer adds an element and picks "New BootQuote" but never fills it in. That entry must start BLANK on
	# both fields, so the pool content guard flags it — a non-blank default would slip a stale placeholder onto the
	# boot card and pass the guard. Control: a filled-in entry passes the same guard.
	var filled := BootQuote.new()
	filled.text = "I think, therefore I aim."
	filled.attribution = "Someone"
	assert_true(_is_authored(filled), "control: a filled-in entry passes the pool guard")
	var untouched := BootQuote.new()
	assert_false(_is_authored(untouched),
		"an untouched \"New BootQuote\" is caught as unauthored — it must not arrive carrying default text or a byline")
	assert_eq(untouched.text.strip_edges(), "", "…its text starts blank (nothing stale can reach the card)")
	var no_byline := BootQuote.new()
	no_byline.text = "A line with no byline"
	assert_false(_is_authored(no_byline),
		"an entry whose attribution was never typed is caught too — the byline must not default to anything")
	filled = null
	untouched = null
	no_byline = null


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
