extends GutTest

## Rank 14: ContentValidator aggregates the content sanity checks. check_items is unit-tested with synthetic
## items; run() is a smoke test over the real project (must not crash; reports the shipped content's problems).

const Validator = preload("res://scripts/tools/content_validator.gd")

func _item(id: StringName, cat := Item.Category.MISC, cal := &"") -> Item:
	var it := Item.new()
	it.id = id
	it.category = cat
	it.caliber = cal
	return it

func test_check_items_flags_blank_dup_and_ammo() -> void:
	var problems := PackedStringArray()
	var items := [
		_item(&"pistol"),
		_item(&""),                                   # blank id
		_item(&"pistol"),                             # duplicate of the first
		_item(&"ammo9", Item.Category.AMMO, &"9mm"),  # ok ammo
		_item(&"ammoX", Item.Category.AMMO, &""),     # ammo with no caliber
	]
	Validator.check_items(items, problems)
	assert_eq(problems.size(), 3, "blank id + duplicate + ammo-no-caliber = 3 problems (got: %s)" % str(problems))

func test_check_items_clean_list() -> void:
	var problems := PackedStringArray()
	Validator.check_items([_item(&"a"), _item(&"b", Item.Category.AMMO, &"9mm")], problems)
	assert_eq(problems.size(), 0, "clean items -> no problems")

func test_run_executes_over_real_content() -> void:
	var problems = Validator.run()
	assert_true(problems is PackedStringArray, "run() returns a PackedStringArray")
	gut.p("ContentValidator.run() shipped-content report (%d): %s" % [problems.size(), str(problems)])
