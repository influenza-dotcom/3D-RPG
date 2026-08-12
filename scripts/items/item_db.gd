extends Node

## ItemDb (autoload) — the registry that maps a WeaponData to its weapon-Item, so the player seed, the
## NPC seed, and corpse loot all resolve a weapon to the SAME Item. Weapon-items + ammo-items are authored
## .tres in resources/items/; register a new one simply by DROPPING ITS .tres IN THAT FOLDER — the folder is
## scanned at boot, so there's no hand-maintained path list to forget. Lookups are O(1) keyed by the
## WeaponData resource (Godot caches a .tres to one instance, so identical refs share a key).

## Folder scanned at boot for item resources: a weapon-item buckets by its WeaponData, an ammo-item by caliber.
const ITEMS_DIR := "res://resources/items"

var _by_weapon: Dictionary = {}    ## WeaponData -> Item (weapon template)
var _by_caliber: Dictionary = {}   ## StringName caliber -> Item (ammo template)
var _by_id: Dictionary = {}        ## StringName Item.id -> Item (template) — the save system's stable key
var _all: Array[Item] = []

func _ready() -> void:
	var dir := DirAccess.open(ITEMS_DIR)
	if dir == null:
		push_warning("ItemDb: cannot open %s — no items registered" % ITEMS_DIR)
		return
	for file in dir.get_files():
		var f := file.trim_suffix(".remap")  # exported builds may append .remap to packed resources
		if not (f.ends_with(".tres") or f.ends_with(".res")):
			continue
		var item := load(ITEMS_DIR.path_join(f)) as Item
		if item == null:
			push_warning("ItemDb: '%s' in resources/items/ is not an Item resource (skipped)" % f)
			continue
		_all.append(item)
		if item.weapon != null:
			_by_weapon[item.weapon] = item
		elif item.caliber != &"":
			_by_caliber[item.caliber] = item
		if item.id != &"":
			if _by_id.has(item.id):
				push_warning("ItemDb: duplicate item id '%s' ('%s') — ids must be unique for save/load" % [item.id, f])
			_by_id[item.id] = item
		else:
			push_warning("ItemDb: '%s' has a blank `id` — it can't be save/load tracked. Set Item.id." % f)
		if item.category == Item.Category.AMMO and item.caliber == &"":
			push_warning("ItemDb: '%s' is AMMO with no `caliber` — no weapon can draw from it. Set its caliber." % f)

## The registered TEMPLATE weapon-Item for `weapon` (shared, for lookup), or null if none is registered.
## To ACQUIRE a weapon into an inventory, use make_weapon_item() instead so each one is its own object.
func weapon_item_for(weapon: WeaponData) -> Item:
	if weapon == null:
		return null
	return _by_weapon.get(weapon, null)

## A FRESH, UNIQUE weapon-Item for `weapon` — a duplicate of the registered template, so every acquired
## weapon is its own object: two pistols (seeded + looted) are DISTINCT items, and equipping one marks
## only that one. The WeaponData itself stays shared (duplicate() doesn't deep-copy sub-resources).
## null if the weapon isn't registered. Use this for the player seed, NPC seed, and loot.
func make_weapon_item(weapon: WeaponData) -> Item:
	var template := weapon_item_for(weapon)
	return template.duplicate() as Item if template != null else null

## The shared ammo-Item template for `caliber` (e.g. &"9mm"), or null if none is registered. Ammo stacks
## by type, so the SHARED template is used directly (no per-instance uniqueness like weapons). Used to
## seed reserve ammo and to author clip pickups.
func ammo_item_for(caliber: StringName) -> Item:
	if caliber == &"":
		return null
	return _by_caliber.get(caliber, null)

## The registered TEMPLATE whose Item.id matches — the save system's stable lookup. Null if unregistered.
func item_by_id(id: StringName) -> Item:
	if id == &"":
		return null
	return _by_id.get(id, null)

## An item INSTANCE for a saved id: a weapon comes back as a FRESH unique item (like make_weapon_item, so
## two saved pistols restore as two distinct objects); everything else returns the SHARED template — ammo /
## consumables stack by template identity, so the shared object is what CharacterInventory.add must see.
## Null = unknown id (an item removed from the game) — the loader skips it rather than failing the load.
func restore_item(id: StringName) -> Item:
	var template := item_by_id(id)
	if template == null:
		return null
	return make_weapon_item(template.weapon) if template.is_weapon() else template

## Restore one serialized inventory stack entry. Plain ids use restore_item(); weapon entries may also carry a
## `weapon_delta` dict of script-export scalar values that differ from the registered template.
func restore_item_from_save(entry: Dictionary) -> Item:
	var item := restore_item(StringName(str(entry.get("id", ""))))
	if item == null:
		return null
	return apply_weapon_delta(item, entry.get("weapon_delta", {}))

## Difference between this weapon item's WeaponData and its registered template. Only script-export scalar values
## are serialized; asset refs/resources stay authored on the template.
func weapon_delta_for(item: Item) -> Dictionary:
	if item == null or not item.is_weapon() or item.weapon == null:
		return {}
	var template := item_by_id(item.id)
	if template == null or not template.is_weapon() or template.weapon == null:
		return {}
	var delta := {}
	for prop in item.weapon.get_property_list():
		if not _is_saved_weapon_property(prop):
			continue
		var prop_name := String(prop["name"])
		var current = item.weapon.get(prop_name)
		var base = template.weapon.get(prop_name)
		if current != base:
			delta[prop_name] = _store_weapon_delta_value(current, int(prop["type"]))
	return delta

## Apply a saved weapon_delta to a restored weapon item, deep-copying its WeaponData before mutation so the
## registered template and sibling weapon instances remain untouched.
func apply_weapon_delta(item: Item, raw_delta) -> Item:
	if item == null or not item.is_weapon() or not (raw_delta is Dictionary) or raw_delta.is_empty():
		return item
	var copy := item.clone_unique()
	var delta: Dictionary = raw_delta
	for prop in copy.weapon.get_property_list():
		if not _is_saved_weapon_property(prop):
			continue
		var prop_name := String(prop["name"])
		if not delta.has(prop_name):
			continue
		var value = _coerce_weapon_delta_value(delta[prop_name], int(prop["type"]))
		if value != null:
			copy.weapon.set(prop_name, value)
	return copy

func _is_saved_weapon_property(prop: Dictionary) -> bool:
	var usage := int(prop.get("usage", 0))
	if (usage & PROPERTY_USAGE_SCRIPT_VARIABLE) == 0:
		return false
	return _is_weapon_delta_type(int(prop.get("type", TYPE_NIL)))

# The per-instance weapon-delta (clone_unique) only carries SCALAR / simple-value properties — arrays,
# dictionaries, and nested Resources are NOT delta-able (they'd need a deep copy + merge, not a flat set()).
# Add a type here only if set() + _coerce_weapon_delta_value round-trip it cleanly.
func _is_weapon_delta_type(t: int) -> bool:
	return t in [TYPE_BOOL, TYPE_INT, TYPE_FLOAT, TYPE_STRING, TYPE_STRING_NAME, TYPE_VECTOR2, TYPE_VECTOR3, TYPE_COLOR]

func _store_weapon_delta_value(value, t: int) -> Variant:
	if t == TYPE_STRING_NAME:
		return String(value)
	return value

func _coerce_weapon_delta_value(value, t: int) -> Variant:
	match t:
		TYPE_BOOL:
			if value is bool or value is int or value is float:
				return bool(value)
			return null
		TYPE_INT:
			if value is int or value is float or value is bool:
				return int(value)
			return null
		TYPE_FLOAT:
			if value is int or value is float or value is bool:
				return float(value)
			return null
		TYPE_STRING:
			if value == null:
				return null
			return str(value)
		TYPE_STRING_NAME:
			if value == null:
				return null
			return StringName(str(value))
		TYPE_VECTOR2:
			if value is Vector2:
				return value
			return null
		TYPE_VECTOR3:
			if value is Vector3:
				return value
			return null
		TYPE_COLOR:
			if value is Color:
				return value
			return null
	return null

## Every registered item (copy, so callers can't mutate the registry). For tools / UI / debug.
func all_items() -> Array[Item]:
	return _all.duplicate()
