extends GutTest

## Caliber registry (scripts/items/calibers.gd) that backs the weapon/ammo `caliber` dropdown. It scans
## resources/items/ for ammo calibers so a designer picks from a SUGGESTION list instead of typing a string
## that must match exactly. These tests pin: the scan finds the shipped calibers; the collect step lists a
## shared caliber ONCE, in sorted order, and never offers a weapon Item's or a blank caliber as ammo (fed the
## shapes shipped content never has, so those rules can't pass by fixture luck); every caliber dropdown offers
## exactly those calibers as clean options; and — the anti-gotcha guard — every WEAPON's caliber actually has
## matching ammo on disk (else it can't reload).

const CALIBERS := preload("res://scripts/items/calibers.gd")
const WEAPONS_DIR := "res://resources/weapons/"
## The calibers the shipped ammo items provide (resources/items/ammo_*.tres; docs/AUTHORING_GUIDE.md lists them).
const SHIPPED_CALIBERS := ["grenades", "pistol", "rifle", "shells", "smg"]

func test_ids_nonempty_sorted_and_unique() -> void:
	var ids := CALIBERS.ids()
	assert_gt(ids.size(), 0, "there must be ammo calibers on disk for the dropdown to suggest")
	var seen := {}
	var prev := ""
	for c in ids:
		assert_false(seen.has(c), "caliber ids must be unique — duplicate '%s'" % c)
		seen[c] = true
		assert_true(prev <= c, "caliber ids must be sorted (got '%s' after '%s')" % [c, prev])
		prev = c

func test_ids_contains_known_ammo_calibers() -> void:
	var ids := CALIBERS.ids()
	for known in ["pistol", "rifle", "shells", "smg"]:
		assert_true(ids.has(known), "the '%s' ammo caliber must be discovered from resources/items/" % known)

## An ammo Item: a caliber and no weapon.
func _ammo(caliber: StringName) -> Item:
	var it := Item.new()
	it.category = Item.Category.AMMO
	it.caliber = caliber
	return it

## The options a designer sees in `obj.prop_name`'s dropdown, split out of its hint_string. Fails (and returns
## an empty list) when the property is missing or is not a SUGGESTION dropdown.
func _dropdown_options(obj: Object, prop_name: String, field: String) -> PackedStringArray:
	for p in obj.get_property_list():
		if p.get("name", "") != prop_name:
			continue
		assert_eq(p.get("hint", -1), PROPERTY_HINT_ENUM_SUGGESTION,
			"%s must be a SUGGESTION dropdown (a new caliber stays typable while its ammo is authored)" % field)
		var hint: String = p.get("hint_string", "")
		return hint.split(",")
	fail_test("%s has no property in get_property_list() — the caliber dropdown can't exist" % field)
	return PackedStringArray()

func test_ammo_sharing_a_caliber_lists_it_once_in_sorted_order() -> void:
	# Two ammo items feed "shells" (say a buckshot and a slug box), and the input order is NOT alphabetical. The
	# dropdown must offer each caliber once, alphabetised — never "shells" twice, never in folder order.
	var items: Array[Resource] = [_ammo(&"shells"), _ammo(&"pistol"), _ammo(&"shells"), _ammo(&"grenades")]
	assert_eq(Array(CALIBERS.ids_of(items)), ["grenades", "pistol", "shells"],
		"a caliber two ammo items share must be listed ONCE, and the list sorted, whatever order the items load in")

func test_weapon_item_carrying_a_caliber_is_not_offered_as_ammo() -> void:
	# A weapon Item (weapon set) is not ammo, even when its own caliber field is filled in: offering it would let
	# a designer pick a caliber that no ammo on disk actually provides.
	var gun := _ammo(&"flechette")
	gun.category = Item.Category.WEAPON
	gun.weapon = WeaponData.new()
	var items: Array[Resource] = [gun, _ammo(&"pistol")]
	assert_eq(Array(CALIBERS.ids_of(items)), ["pistol"],
		"a weapon Item's caliber must not be offered as an ammo caliber")
	# CONTROL: the very same item with no weapon IS ammo, so the weapon is what kept it out above.
	gun.weapon = null
	assert_eq(Array(CALIBERS.ids_of(items)), ["flechette", "pistol"],
		"the same item without a weapon must be collected — else the exclusion above proves nothing")

func test_blank_caliber_items_and_non_item_resources_add_no_option() -> void:
	# A healthpack (an Item with the default blank caliber) and a resource with no caliber field at all must add
	# nothing — a blank "" option would be a caliber no ammo can ever match.
	var healthpack := Item.new()
	var not_an_item := Resource.new()
	var items: Array[Resource] = [healthpack, not_an_item, _ammo(&"smg")]
	assert_eq(Array(CALIBERS.ids_of(items)), ["smg"],
		"a blank caliber or a caliber-less resource must add no dropdown option")
	# CONTROL: give the same healthpack a caliber and it IS collected, so the blank value is what kept it out.
	healthpack.caliber = &"darts"
	assert_eq(Array(CALIBERS.ids_of(items)), ["darts", "smg"],
		"the same item with a caliber set must be collected — else the blank-caliber skip above proves nothing")

func test_every_caliber_dropdown_offers_exactly_the_ammo_calibers_on_disk() -> void:
	# The three authoring fields that must name a real ammo caliber all draw their dropdown from the registry.
	# Options must be clean (Godot splits the hint on "," and keeps any padding), one per shipped caliber, no
	# blanks, no repeats, and nothing the ammo on disk doesn't provide.
	var on_disk := CALIBERS.ids()
	var weapon := WeaponData.new()
	var item := Item.new()
	var mod := WeaponMod.new()
	var dropdowns := [
		[weapon, "caliber", "WeaponData.caliber"],
		[item, "caliber", "Item.caliber"],
		[mod, "caliber_override", "WeaponMod.caliber_override"],
	]
	for d: Array in dropdowns:
		var field: String = d[2]
		var options := _dropdown_options(d[0], d[1], field)
		var seen := {}
		for opt in options:
			assert_true(opt != "" and opt == opt.strip_edges(),
				"%s offers a blank or space-padded option '%s' — picking it would match no ammo" % [field, opt])
			assert_false(seen.has(opt), "%s offers caliber '%s' twice" % [field, opt])
			seen[opt] = true
			assert_true(on_disk.has(opt), "%s offers '%s', which no ammo on disk provides" % [field, opt])
		for known in SHIPPED_CALIBERS:
			assert_true(options.has(known), "%s must offer the shipped '%s' ammo caliber" % [field, known])
		assert_eq(options.size(), on_disk.size(),
			"%s must offer every ammo caliber on disk, one option each" % field)

func test_every_weapon_caliber_has_matching_ammo() -> void:
	# The anti-gotcha guard the dropdown enforces at authoring time: a weapon whose non-empty caliber has no
	# ammo item on disk could never reload. Empty caliber (fists / melee / spray / rock-less) is skipped.
	var ids := CALIBERS.ids()
	var dir := DirAccess.open(WEAPONS_DIR)
	assert_not_null(dir, "resources/weapons/ must exist")
	if dir == null:
		return
	var checked := 0
	for file in dir.get_files():
		var f := file.trim_suffix(".remap")
		if not (f.ends_with(".tres") or f.ends_with(".res")):
			continue
		var w := load(WEAPONS_DIR.path_join(f))
		if w == null:
			continue
		var cal: Variant = w.get("caliber")
		if cal == null or String(cal) == "":
			continue  # an unreserved weapon (melee / fists / spray) needs no ammo
		checked += 1
		assert_true(ids.has(String(cal)),
			"weapon '%s' has caliber '%s' with no matching ammo on disk — it could never reload" % [f, cal])
	assert_gt(checked, 0, "expected at least one calibered weapon to validate")
