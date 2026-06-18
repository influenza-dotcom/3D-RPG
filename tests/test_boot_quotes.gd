extends GutTest

## The boot-intro quote pool (res://resources/ui/boot_quotes.tres, a BootQuotes resource) is designer-authored
## content the start menu reads at runtime. Pin that it loads and every entry has BOTH a text and an attribution
## (the card reads .text / .attribution). Read duck-typed, mirroring how start_menu._pick_quote consumes it.

const PATH := "res://resources/ui/boot_quotes.tres"

func test_boot_quotes_loads_and_is_populated() -> void:
	assert_true(ResourceLoader.exists(PATH), "boot_quotes.tres must exist")
	var res = load(PATH)
	assert_not_null(res, "boot_quotes.tres must load (a parse error = no authored quotes, only the fallback)")
	if res == null:
		return
	assert_true("quotes" in res, "the resource exposes a `quotes` array (the BootQuotes script attached)")
	assert_gt(res.quotes.size(), 0, "at least one authored quote")
	for q in res.quotes:
		assert_not_null(q, "no null entries in the quotes array")
		if q != null:
			assert_ne(str(q.text).strip_edges(), "", "every quote has text")
			assert_ne(str(q.attribution).strip_edges(), "", "every quote has an attribution")

func test_random_returns_a_quote_when_populated() -> void:
	var res = load(PATH)
	if res == null or not ("quotes" in res) or res.quotes.is_empty():
		return
	assert_not_null(res.random(), "random() returns a quote when the pool is non-empty")
