extends GutTest

## Rank 14: ContentValidator aggregates the content sanity checks. check_items is unit-tested with synthetic
## items; run() is driven over the real project, both with a caller-supplied item list (the editor callers' path)
## and over the live registry, where the shipped content must come back clean.

const Validator = preload("res://scripts/tools/content_validator.gd")

func _item(id: StringName, cat := Item.Category.MISC, cal := &"") -> Item:
	var it := Item.new()
	it.id = id
	it.category = cat
	it.caliber = cal
	return it

## Every problem line that mentions `needle`.
func _mentioning(problems: PackedStringArray, needle: String) -> PackedStringArray:
	var out := PackedStringArray()
	for line in problems:
		if line.contains(needle):
			out.append(line)
	return out

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
	assert_eq(_mentioning(problems, "blank id").size(), 1,
		"the blank-id item is reported once — it can't be save/load tracked (got: %s)" % str(problems))
	assert_eq(_mentioning(problems, "Duplicate item id 'pistol'").size(), 1,
		"the SECOND 'pistol' is reported as a duplicate, once — the first occurrence is the legitimate one (got: %s)" % str(problems))
	assert_eq(_mentioning(problems, "'ammoX' has no caliber").size(), 1,
		"the uncalibered ammo row is the one flagged — no weapon can draw from it (got: %s)" % str(problems))
	assert_eq(_mentioning(problems, "ammo9").size(), 0,
		"ammo that HAS a caliber is fine and must not be reported (got: %s)" % str(problems))

func test_check_items_clean_list() -> void:
	var problems := PackedStringArray()
	Validator.check_items([_item(&"a"), _item(&"b", Item.Category.AMMO, &"9mm")], problems)
	assert_eq(problems.size(), 0, "clean items -> no problems")

func test_run_checks_the_item_list_it_is_handed() -> void:
	# The editor callers (Level tab, Audit tab, File -> Run) hand run() the on-disk item scan because ItemDb is empty
	# at edit time. That list must be the one checked — the old unconditional registry read made every edit-time
	# report pass with the item checks silently skipped.
	var problems := Validator.run([_item(&"zz_validator_dupe"), _item(&"zz_validator_dupe")])
	assert_eq(_mentioning(problems, "Duplicate item id 'zz_validator_dupe'").size(), 1,
		"run(items) must run the item checks over the SUPPLIED list, so its duplicate is reported (got: %s)" % str(problems))

func test_shipped_content_passes_its_own_validator() -> void:
	# No list: a non-editor caller (GUT, validate_all, a running game) checks the live ItemDb registry plus every
	# faction and authored Perk / GoapProfile under res://resources. The shipped project must report nothing.
	var problems := Validator.run()
	assert_eq(problems.size(), 0,
		"the shipped content must be clean — fix the authored resource each line names: %s" % "\n".join(problems))
