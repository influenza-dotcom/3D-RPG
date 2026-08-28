extends GutTest

## Per-instance Item state (EL-3): Item.clone_unique() — the seam that gives an acquired weapon its OWN
## WeaponData so per-instance stat deltas (loot rarity / variance / future weapon mods) can't alias the shared
## template or sibling instances. This is OPT-IN: the acquire pipeline still shares the template WeaponData
## (the codebase keys weapon KIND off WeaponData object identity — hotbar grouping, the swap no-op), so callers
## clone only when they need a divergent stat block. These tests pin the deep-copy contract; the loot-side
## routing + delta persistence land with EL-4 (loot rarity).


func test_clone_unique_makes_a_distinct_item_and_weapon() -> void:
	var template := ItemDb.item_by_id(&"pistol")
	assert_not_null(template, "the authored pistol item is registered")
	var c := template.clone_unique()
	assert_true(c != template, "clone_unique returns a DISTINCT Item, not the template")
	assert_not_null(c.weapon, "the clone still has a weapon")
	assert_true(c.weapon != template.weapon, "...with its OWN WeaponData (not the shared template's)")
	assert_eq(c.weapon.damage, template.weapon.damage, "cloned from the template — identical stats to start")


func test_mutating_the_clone_weapon_does_not_touch_the_template() -> void:
	# The whole point: a per-instance stat change on one weapon must not bleed into the template or its siblings.
	var template := ItemDb.item_by_id(&"pistol")
	var before: float = template.weapon.damage
	var a := template.clone_unique()
	var b := template.clone_unique()
	a.weapon.damage = before + 5.0
	assert_eq(template.weapon.damage, before, "the shared template is untouched by mutating a clone")
	assert_eq(b.weapon.damage, before, "a sibling clone is untouched too (no shared WeaponData)")
	assert_eq(a.weapon.damage, before + 5.0, "the mutated clone keeps its own divergent stat")


func test_clone_unique_preserves_the_weapon_kind_id() -> void:
	# The clone keeps Item.id — the stable weapon-KIND key the hotbar/stacking rely on, so a cloned pistol is
	# still grouped/stacked as a pistol even though its WeaponData object differs.
	var template := ItemDb.item_by_id(&"pistol")
	var c := template.clone_unique()
	assert_eq(c.id, template.id, "clone keeps the weapon-kind id")
	assert_true(c.is_weapon(), "clone is still a weapon")


## ⭐The @export_storage keystone, seen from the Item side. clone_unique() deep-copies the WeaponData with
## Resource.duplicate(), which carries STORAGE-usage properties and SILENTLY DROPS a plain `var` (probed on
## 4.7.1: @export_storage = usage 4098, a bare var = 4096). If the six mod slot ids ever lost that usage, every
## acquired / restored / looted modded gun would come back STOCK with no error anywhere — the fitted parts would
## simply evaporate. Item.id matters just as much on this path: ItemDb.rebuild_weapon_mods looks the pristine
## weapon TEMPLATE up by it on load, so a clone that lost its id would re-derive from nothing.
func test_clone_unique_preserves_the_fitted_mod_slot_ids_and_the_item_id() -> void:
	var template := ItemDb.item_by_id(&"pistol")
	assert_not_null(template, "the authored pistol item is registered")
	var src := template.clone_unique()
	# All six slots, not just one: they are six independent fields, and a broken MOD_SLOT_PROPS row would show
	# up as exactly one of them failing to survive.
	for slot in WeaponData.MOD_SLOT_PROPS.size():
		src.weapon.set_mod_id(slot, StringName("test_part_" + str(slot)))
	var c := src.clone_unique()
	assert_eq(c.id, template.id, "the clone keeps Item.id — the key the load path re-derives the stat block from")
	assert_true(c.weapon != src.weapon, "...and still gets its OWN WeaponData")
	for slot in WeaponData.MOD_SLOT_PROPS.size():
		assert_eq(c.weapon.mod_id(slot), StringName("test_part_" + str(slot)), "slot " + str(slot) + "'s fitted part id survives clone_unique")
	assert_eq(template.weapon.mod_id(WeaponData.ModSlot.BARREL), &"", "the registered template is still unmodded (a template with a fitted id would give every instance a permanent delta)")


func test_clone_unique_on_nonweapon_returns_shared_template() -> void:
	# Ammo / consumables stack by shared-template identity — clone_unique must NOT fork them, or stacking breaks.
	var ammo := ItemDb.item_by_id(&"ammo_pistol")
	assert_not_null(ammo, "the authored ammo_pistol item is registered")
	assert_false(ammo.is_weapon(), "precondition: ammo is not a weapon")
	assert_eq(ammo.clone_unique(), ammo, "a non-weapon clone_unique returns the SHARED template (stacking intact)")
