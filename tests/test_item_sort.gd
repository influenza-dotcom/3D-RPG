extends GutTest

## ItemSort (scripts/ui/item_sort.gd) — the DISPLAY-ONLY ordering behind the inventory / shop Sort button
## (shop_screen.gd cycles `_sort_mode` with next_mode, captions the button with button_text, and repacks a bag
## through sorted(inv.placed_contents(), mode)). Pure statics over {"item","count"} stacks, so everything here is
## off-tree: hand-built Item resources released with `= null`.
##
## The contract worth pinning is the one a player would notice the moment it slipped:
##   • sorted() returns a NEW array and never mutates the bag's row order (DEFAULT must keep insertion order —
##     "bag order" is what the player packed, and a mode that shuffled the underlying rows would move tiles);
##   • VALUE / WEIGHT sort DESCENDING (priciest / heaviest first — "find what's slowing you down");
##   • NAME is natural + case-insensitive ("Ammo 2" before "Ammo 10"; "apple" beside "Banana");
##   • every mode breaks ties by name so two hovers of the same bag never reorder;
##   • extra row keys (placed_contents' key / x / y / w / h) ride along untouched — the view keys on them.


# --- Fixtures ------------------------------------------------------------------------------------------------

func _item(id: String, category: Item.Category, value: float, weight: float, display_name: String = "") -> Item:
	var it := Item.new()
	it.id = StringName(id)
	it.display_name = display_name
	it.category = category
	it.value = value
	it.weight = weight
	return it

func _stack(item: Item, count: int = 1, extra: Dictionary = {}) -> Dictionary:
	var row := {"item": item, "count": count}
	row.merge(extra)
	return row

func _labels(stacks: Array) -> Array:
	var out: Array = []
	for s in stacks:
		out.append(s["item"].label())
	return out

## A four-stack bag in a deliberately scrambled insertion order.
func _bag() -> Array:
	return [
		_stack(_item("pistol", Item.Category.WEAPON, 250.0, 1.2, "Pistol"), 1),
		_stack(_item("ammo_10", Item.Category.AMMO, 5.0, 0.3, "Ammo 10"), 3),
		_stack(_item("apple", Item.Category.CONSUMABLE, 5.0, 0.2, "apple"), 2),
		_stack(_item("ammo_2", Item.Category.AMMO, 4.0, 0.3, "Ammo 2"), 1),
		_stack(_item("Banana", Item.Category.CONSUMABLE, 250.0, 0.5, "Banana"), 1),
	]


# --- The mode cycle ------------------------------------------------------------------------------------------

func test_labels_cover_every_mode_exactly_once() -> void:
	assert_eq(ItemSort.LABELS.size(), ItemSort.Mode.size(),
		"LABELS must have one caption per Mode — next_mode wraps on LABELS.size(), so a missing row skips a mode")
	for mode in ItemSort.Mode.values():
		assert_true(ItemSort.LABELS.has(mode), "Mode %d needs a caption in LABELS" % mode)
		assert_false(String(ItemSort.LABELS[mode]).is_empty(), "Mode %d's caption must be non-empty" % mode)

func test_next_mode_walks_the_enum_and_wraps_to_default() -> void:
	assert_eq(ItemSort.next_mode(ItemSort.Mode.DEFAULT), ItemSort.Mode.NAME, "DEFAULT -> NAME")
	assert_eq(ItemSort.next_mode(ItemSort.Mode.NAME), ItemSort.Mode.TYPE, "NAME -> TYPE")
	assert_eq(ItemSort.next_mode(ItemSort.Mode.TYPE), ItemSort.Mode.VALUE, "TYPE -> VALUE")
	assert_eq(ItemSort.next_mode(ItemSort.Mode.VALUE), ItemSort.Mode.WEIGHT, "VALUE -> WEIGHT")
	assert_eq(ItemSort.next_mode(ItemSort.Mode.WEIGHT), ItemSort.Mode.DEFAULT, "the last mode wraps back to DEFAULT")

func test_next_mode_cycles_through_every_mode_before_repeating() -> void:
	var mode: int = ItemSort.Mode.DEFAULT
	var seen := {}
	for i in ItemSort.Mode.size():
		assert_false(seen.has(mode), "the cycle must not revisit mode %d before covering them all" % mode)
		seen[mode] = true
		mode = ItemSort.next_mode(mode)
	assert_eq(mode, ItemSort.Mode.DEFAULT, "a full lap lands back on DEFAULT")
	assert_eq(seen.size(), ItemSort.Mode.size(), "a full lap visits every mode")

func test_button_text_captions_the_mode_and_degrades_to_default() -> void:
	assert_eq(ItemSort.button_text(ItemSort.Mode.DEFAULT), "Sort: Default", "the DEFAULT caption")
	assert_eq(ItemSort.button_text(ItemSort.Mode.NAME), "Sort: Name", "the NAME caption")
	assert_eq(ItemSort.button_text(ItemSort.Mode.WEIGHT), "Sort: Weight", "the WEIGHT caption")
	assert_eq(ItemSort.button_text(999), "Sort: Default", "an out-of-range mode (a stale save value) reads as Default")


# --- sorted() ------------------------------------------------------------------------------------------------

func test_sorted_default_keeps_bag_order() -> void:
	var bag := _bag()
	assert_eq(_labels(ItemSort.sorted(bag, ItemSort.Mode.DEFAULT)), _labels(bag),
		"DEFAULT is insertion order — what the player packed, untouched")

func test_sorted_never_mutates_the_input() -> void:
	var bag := _bag()
	var before := _labels(bag)
	var out := ItemSort.sorted(bag, ItemSort.Mode.NAME)
	assert_eq(_labels(bag), before, "the bag's own row order is untouched — sorting is for SHOW only")
	assert_ne(out, bag, "sorted() hands back a NEW array, not the bag's array")
	assert_eq(out.size(), bag.size(), "every stack survives the sort")

func test_sorted_by_name_is_natural_and_case_insensitive() -> void:
	var out := _labels(ItemSort.sorted(_bag(), ItemSort.Mode.NAME))
	assert_eq(out, ["Ammo 2", "Ammo 10", "apple", "Banana", "Pistol"],
		"natural order puts 'Ammo 2' before 'Ammo 10', and lowercase 'apple' sits beside 'Banana' rather than after 'Pistol'")

func test_sorted_by_value_is_priciest_first_with_name_tiebreak() -> void:
	var out := _labels(ItemSort.sorted(_bag(), ItemSort.Mode.VALUE))
	assert_eq(out, ["Banana", "Pistol", "Ammo 10", "apple", "Ammo 2"],
		"250 > 250 tie by name (Banana, Pistol), then 5 > 5 tie by name (Ammo 10, apple), then 4")

func test_sorted_by_weight_is_heaviest_first_with_name_tiebreak() -> void:
	var out := _labels(ItemSort.sorted(_bag(), ItemSort.Mode.WEIGHT))
	assert_eq(out, ["Pistol", "Banana", "Ammo 2", "Ammo 10", "apple"],
		"1.2, 0.5, then the 0.3 tie by name (Ammo 2 before Ammo 10), then 0.2")

func test_sorted_by_type_groups_by_category_ordinal_then_name() -> void:
	# Item.Category is WEAPON, CONSUMABLE, AMMO, MISC — TYPE groups by that ordinal, names within a group.
	var out := ItemSort.sorted(_bag(), ItemSort.Mode.TYPE)
	var cats: Array = []
	for s in out:
		cats.append(int(s["item"].category))
	var sorted_cats := cats.duplicate()
	sorted_cats.sort()
	assert_eq(cats, sorted_cats, "categories come out in ascending enum order")
	assert_eq(_labels(out), ["Pistol", "apple", "Banana", "Ammo 2", "Ammo 10"],
		"WEAPON, then CONSUMABLE (apple, Banana by name), then AMMO (Ammo 2, Ammo 10 natural)")

func test_sorted_falls_back_to_the_id_when_no_display_name() -> void:
	# Item.label() is display_name else id — the sort must compare the same label the tile paints.
	var bag := [
		_stack(_item("zeta", Item.Category.MISC, 1.0, 1.0)),
		_stack(_item("alpha", Item.Category.MISC, 1.0, 1.0)),
	]
	assert_eq(_labels(ItemSort.sorted(bag, ItemSort.Mode.NAME)), ["alpha", "zeta"],
		"nameless items sort by their id, the label the player actually sees")

func test_sorted_preserves_extra_row_keys() -> void:
	# The shop repacks placed_contents() rows — {item, count, key, x, y, ...} — and the view keys tiles on them.
	var a := _item("a", Item.Category.MISC, 1.0, 1.0, "A")
	var b := _item("b", Item.Category.MISC, 9.0, 1.0, "B")
	var bag := [_stack(a, 1, {"key": 7, "x": 2}), _stack(b, 4, {"key": 3, "x": 0})]
	var out := ItemSort.sorted(bag, ItemSort.Mode.VALUE)
	assert_eq(out[0]["item"], b, "priciest first")
	assert_eq(out[0]["key"], 3, "the row's own key rides along")
	assert_eq(out[0]["count"], 4, "and its count")
	assert_eq(out[1]["x"], 2, "every extra key survives on every row")
	a = null
	b = null

func test_sorted_handles_an_empty_bag_and_a_single_stack() -> void:
	assert_eq(ItemSort.sorted([], ItemSort.Mode.NAME).size(), 0, "an empty bag sorts to an empty array")
	var one := [_stack(_item("solo", Item.Category.MISC, 1.0, 1.0, "Solo"))]
	for mode in ItemSort.Mode.values():
		assert_eq(_labels(ItemSort.sorted(one, mode)), ["Solo"], "a single stack is itself under mode %d" % mode)
