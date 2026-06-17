extends GutTest

## Caliber registry (scripts/items/calibers.gd) that backs the weapon/ammo `caliber` dropdown. It scans
## resources/items/ for ammo calibers so a designer picks from a SUGGESTION list instead of typing a string
## that must match exactly. These tests pin: the scan finds the shipped calibers, ids_csv mirrors ids, and —
## the anti-gotcha guard — every WEAPON's caliber actually has matching ammo on disk (else it can't reload).

const CALIBERS := preload("res://scripts/items/calibers.gd")
const WEAPONS_DIR := "res://resources/weapons/"

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

func test_ids_csv_is_comma_joined_ids() -> void:
	assert_eq(CALIBERS.ids_csv(), ",".join(CALIBERS.ids()),
		"ids_csv must be the comma-joined ids (the dropdown hint_string)")

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
