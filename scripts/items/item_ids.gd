extends RefCounted

## Item-id registry: every Item.id authored under resources/items/, for a PROPERTY_HINT_ENUM_SUGGESTION dropdown
## so designers PICK an item id instead of typing one that must match EXACTLY — a typo'd Lock/Door
## requires_item_id, or a PICKUP/USE_ITEM QuestObjective.target_id, silently never resolves. Completes the
## drift-prone-id dropdown set alongside calibers / faction_id / unlock_id.
##
## NO class_name on purpose — const-preloaded where needed (Lock / Door / QuestObjective), so there's nothing for
## the global script class cache to miss; mirrors the Calibers / Factions registries. Fields are read duck-typed
## (res.get) so the registry needs no compile-time dep on Item (no preload cycle).

const ITEMS_DIR := "res://resources/items/"

## Every Item.id on disk: scan resources/items/ and collect each resource's non-empty `id` — distinct + sorted.
## EDITOR/TEST use only (the dropdown self-populates from this); never on a hot path — ItemDb keeps the runtime map.
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
		var id: Variant = res.get("id")  # an Item carries one; a non-Item resource -> null
		if id == null:
			continue
		var id_s := String(id)
		if id_s != "" and not out.has(id_s):
			out.append(id_s)
	out.sort()
	return out

## The item ids as a comma-separated string, for a PROPERTY_HINT_ENUM_SUGGESTION dropdown hint_string.
static func ids_csv() -> String:
	return ",".join(ids())
