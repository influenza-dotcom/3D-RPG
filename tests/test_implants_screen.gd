extends GutTest

## Roster behaviour for the ImplantsScreen autoload (the fifth Pip-Boy tab): installed_ids() and
## carried_chips() are duck-typed pure reads off a player object, so they are driven here with bare stubs —
## no Player._ready (forbidden in unit tests), no scene tree mutations. Both read the INSTALLED predicate
## (installed_list / mechanic_installed), not the ACTIVE one: an implant switched off from this very tab is
## still owned, so it must stay on the roster and its chip must stay out of the carried section. The toggle
## itself (set_mechanic_active + persistence) is test_implant_toggle.gd; the screen's open/close/tab-switch
## behaviour is the shared PlayerMenus contract (test_player_menus.gd + playtest); the scene wiring is
## test_implants_screen_scene.gd.

const AbilityRegistry := preload("res://scripts/components/abilities/ability_registry.gd")

## A bare player stand-in carrying just the surfaces the roster reads: the AbilityManager projections
## (installed_list / mechanic_installed — INSTALLED, plus has_mechanic for the per-row ACTIVE paint) and an
## `inventory` with contents() (the CharacterInventory shape — [{"item": Item, "count": int}]). `installed`
## is everything fitted; `switched_off` is the subset the player has toggled off, so the stub models the
## split the real Player does instead of equating the two predicates.
class _BagStub extends RefCounted:
	var entries: Array = []
	func contents() -> Array:
		return entries

class _PlayerStub extends RefCounted:
	var installed: Array[StringName] = []
	var switched_off: Array[StringName] = []
	var inventory = null
	func installed_list() -> Array:
		return installed
	func unlocked_list() -> Array:
		var out: Array = []
		for id in installed:
			if not switched_off.has(id):
				out.append(id)
		return out
	func mechanic_installed(id: StringName) -> bool:
		return installed.has(id)
	func has_mechanic(id: StringName) -> bool:
		return installed.has(id) and not switched_off.has(id)


func _chip(path: String) -> Item:
	var item: Item = load(path)
	assert_not_null(item, "%s loads (a real authored chip pins the roster against real data)" % path)
	return item


func test_installed_ids_lists_installed_sorted_by_display_name() -> void:
	var p := _PlayerStub.new()
	p.installed = [&"wall_climb", &"grapple", &"silent_takedown"]
	var out: Array[StringName] = ImplantsScreen.installed_ids(p)
	assert_eq(out.size(), 3, "every installed ability id is listed")
	for id in p.installed:
		assert_has(out, id, "installed '%s' appears in the roster" % id)
	for i in range(out.size() - 1):
		assert_true(
			AbilityRegistry.display_name_for(out[i]).naturalnocasecmp_to(AbilityRegistry.display_name_for(out[i + 1])) < 0,
			"the roster is sorted by AUTHORED display name ('%s' before '%s'), not by grant order" % [out[i], out[i + 1]])
	p = null


func test_installed_ids_keeps_a_switched_off_implant_on_the_roster() -> void:
	# The toggle's whole premise: a switched-off implant must STAY listed (it's the row you click to switch
	# back on). Reading the ACTIVE projection here would make an implant vanish the moment you turned it off.
	var p := _PlayerStub.new()
	p.installed = [&"grapple", &"air_dash"]
	p.switched_off = [&"air_dash"]
	var out: Array[StringName] = ImplantsScreen.installed_ids(p)
	assert_eq(out.size(), 2, "both implants are listed, on or off")
	assert_has(out, &"air_dash", "the switched-off implant stays on the roster")
	p = null


func test_installed_ids_degrades_to_empty_without_the_surface() -> void:
	# Duck-typed absence = neutral: a null player or one without installed_list() reads as "nothing installed",
	# never a crash (the screen's own open() bails without a valid player before this is ever painted).
	var none: Array[StringName] = ImplantsScreen.installed_ids(null)
	assert_eq(none.size(), 0, "a null player has no installed roster")
	var bare: Array[StringName] = ImplantsScreen.installed_ids(RefCounted.new())
	assert_eq(bare.size(), 0, "an object without installed_list() degrades to empty, never crashes")


func test_carried_chips_lists_only_uninstalled_distinct_chips() -> void:
	var wall := _chip("res://resources/items/chip_wall_climb.tres")
	var grapple := _chip("res://resources/items/chip_grapple.tres")
	var p := _PlayerStub.new()
	var bag := _BagStub.new()
	p.inventory = bag
	# TWO SEPARATE bag entries whose items install the SAME ability (a stack split / a duplicate .tres) —
	# the dedupe is keyed on installs_ability, so they must collapse to one row. Plus one grapple chip and
	# a plain non-chip item. A count>1 single entry can't pin the dedupe (one entry = one seen-check), so
	# the second wall chip is a DISTINCT Item resource sharing the ability id.
	var wall_twin: Item = wall.duplicate()
	var plain := Item.new()
	bag.entries = [
		{"item": wall, "count": 1},
		{"item": wall_twin, "count": 1},
		{"item": grapple, "count": 1},
		{"item": plain, "count": 1},
	]
	var out: Array[Item] = ImplantsScreen.carried_chips(p)
	assert_eq(out.size(), 2, "one row per DISTINCT uninstalled chip ability (the twin dedupes); the non-chip item is ignored")
	assert_has(out, wall, "the carried wall-climb chip is listed (first-seen wins over its twin)")
	assert_has(out, grapple, "the carried grapple chip is listed")
	# Install one: its chip drops out of the carried section (it moves to installed_ids).
	p.installed = [wall.installs_ability]
	out = ImplantsScreen.carried_chips(p)
	assert_eq(out.size(), 1, "an installed ability's chip leaves the carried section")
	assert_has(out, grapple, "...and the still-uninstalled chip remains")
	# ...and it STAYS out once switched off: an owned-but-off implant isn't something to go get fitted (the
	# ChipInstaller re-sell guard, mirrored here so the tab can't advertise a chip the mechanic won't take).
	p.switched_off = [wall.installs_ability]
	out = ImplantsScreen.carried_chips(p)
	assert_eq(out.size(), 1, "a switched-OFF implant's chip stays out of the carried section (still owned)")
	assert_has(out, grapple, "...only the genuinely uninstalled chip is listed")
	p = null
	bag = null
	plain = null
	wall_twin = null


func test_carried_chips_empty_without_inventory() -> void:
	var p := _PlayerStub.new()  # inventory left null
	var out: Array[Item] = ImplantsScreen.carried_chips(p)
	assert_eq(out.size(), 0, "no bag reads as no carried chips, never a crash")
	out = ImplantsScreen.carried_chips(null)
	assert_eq(out.size(), 0, "a null player likewise")
	p = null
