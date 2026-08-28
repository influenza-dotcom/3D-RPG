extends RefCounted

## Mod-targetable WeaponData field registry: the scalar `@export`s a WeaponStatDelta is allowed to move.
## Lets a designer PICK the property a weapon part changes from a DROPDOWN instead of typing a field name that
## must match WeaponData's own spelling EXACTLY — a typo'd `property` is a delta that silently never applies,
## the worst failure this system can have (the part costs money, fits, and does nothing).
##
## ⭐The set is DERIVED, never hand-listed: reflect over a throwaway WeaponData and keep the
## PROPERTY_USAGE_SCRIPT_VARIABLE props whose type is BOOL / INT / FLOAT. Those are exactly the types
## ItemDb._is_weapon_delta_type round-trips through a save, so a designer CANNOT author a delta the save
## cannot carry — the field list and the persistence allow-list can never drift apart, because one is
## computed from the same reflection the other one runs. (STRING/STRING_NAME/VECTOR/COLOR delta-able types
## are deliberately NOT offered: a WeaponStatDelta is one arithmetic line — SET/ADD/MULT over a number or a
## bool flag — and `caliber` has its own typed `caliber_override` on WeaponMod.)
##
## The six `mod_*` slot ids are SUBTRACTED: they are the fold's own bookkeeping, so a delta writing one would
## be a part re-stamping its own (or another) slot mid-rebuild — a loop, not a stat change.
##
## NO class_name on purpose — const-preloaded where needed (WeaponStatDelta), so there's nothing for the
## global script class cache to miss; mirrors the Calibers / ItemIds registries.

## Reflection cost is trivial, but this is read once per inspector repaint of every delta row on every part,
## so cache it. STATIC, like AbilityRegistry._display_names: it resets on an editor/plugin script reload,
## which is exactly when WeaponData's property list could have changed.
static var _ids: PackedStringArray = PackedStringArray()

## Every WeaponData property a weapon part may move — sorted, distinct, and stable across runs (a dropdown
## that reorders itself between opens is unusable). EDITOR/TEST use only: the fold reads `delta.property`
## directly and never consults this list.
static func ids() -> PackedStringArray:
	if not _ids.is_empty():
		return _ids
	var out := PackedStringArray()
	# A throwaway instance, never added to anything: get_property_list() is an instance method and WeaponData
	# is a plain Resource with no _init side effects. Freed by refcount as soon as this function returns.
	var probe := WeaponData.new()
	for prop in probe.get_property_list():
		if (int(prop.get("usage", 0)) & PROPERTY_USAGE_SCRIPT_VARIABLE) == 0:
			continue
		if not (int(prop.get("type", TYPE_NIL)) in [TYPE_BOOL, TYPE_INT, TYPE_FLOAT]):
			continue
		var prop_name := StringName(prop["name"])
		if WeaponData.MOD_SLOT_PROPS.has(prop_name):  # the fold's own bookkeeping — see the header
			continue
		out.append(String(prop_name))
	out.sort()
	_ids = out
	return _ids

## The field names as a comma-separated string, for a PROPERTY_HINT_ENUM_SUGGESTION dropdown hint_string.
static func ids_csv() -> String:
	return ",".join(ids())
