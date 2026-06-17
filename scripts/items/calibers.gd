extends RefCounted

## Caliber registry: the distinct ammo calibers authored under resources/items/ (an ammo Item carries a
## `caliber` and no `weapon`). Lets a designer pick a weapon's `caliber` — and an ammo Item's caliber — from a
## DROPDOWN instead of typing a string that must match the ammo's caliber EXACTLY: a mismatch makes a weapon
## that can never reload (the classic "caliber with no ammo" trap). Completes the drift-prone-id dropdown set
## alongside faction_id / unlock_id / required_stat.
##
## NO class_name on purpose — const-preloaded where needed (WeaponData / Item), so there's nothing for the
## global script class cache to miss; mirrors the Factions registry.

const ITEMS_DIR := "res://resources/items/"

## Every ammo caliber on disk: scan resources/items/ and, for each ammo Item (carries a caliber, no weapon),
## collect its caliber — distinct + sorted. EDITOR/TEST use: the caliber dropdown self-populates from this
## (WeaponData / Item._validate_property), and a test pins that every weapon's caliber has matching ammo.
## Runtime ammo resolution stays ItemDb's cached _by_caliber map; this folder scan is never on a hot path.
## Fields are read duck-typed (res.get) so the registry needs no compile-time dep on Item (no preload cycle).
static func ids() -> PackedStringArray:
	var out := PackedStringArray()
	var dir := DirAccess.open(ITEMS_DIR)
	if dir == null:
		return out
	for file in dir.get_files():
		var f := file.trim_suffix(".remap")  # exported builds may append .remap to packed resources
		if not (f.ends_with(".tres") or f.ends_with(".res")):
			continue
		var res := load(ITEMS_DIR.path_join(f))
		if res == null:
			continue
		var cal: Variant = res.get("caliber")  # ammo Items carry one; a non-Item / non-ammo resource -> null or &""
		var wep: Variant = res.get("weapon")   # a weapon Item sets this; ammo doesn't — so this excludes weapons
		if cal == null or wep != null:
			continue
		var cal_s := String(cal)
		if cal_s != "" and not out.has(cal_s):
			out.append(cal_s)
	out.sort()
	return out

## The ammo calibers as a comma-separated string, for a PROPERTY_HINT_ENUM_SUGGESTION dropdown hint_string.
static func ids_csv() -> String:
	return ",".join(ids())
