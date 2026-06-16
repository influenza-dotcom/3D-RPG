extends RefCounted
## Faction registry: resolve the game's Faction resources by their stable id, so a designer can pick an NPC's
## faction from a DROPDOWN (faction_id) instead of hunting the .tres in the file browser. By convention each
## faction's id matches its filename under resources/factions/, so resolution is a plain path load -- export-safe
## and cached by the resource loader. Adding a faction .tres there (id == filename) makes it resolvable with NO
## code change (type its id into faction_id; the dropdown suggestions list the shipped ones).
##
## Preloaded as a const where needed (NO class_name on purpose -> nothing for the test suite's global script
## class cache to miss).

const FACTION_DIR := "res://resources/factions/"

## The Faction whose id (== its .tres filename) is `id`, or null (empty id, or no such faction -> UNALIGNED).
static func by_id(id: String) -> Faction:
	if id.is_empty():
		return null
	for ext in [".tres", ".res"]:
		var path: String = FACTION_DIR + id + ext
		if ResourceLoader.exists(path):
			var res := load(path)
			if res is Faction:
				# Reputation / relations key on the resource's INTERNAL id, so a copy-pasted .tres whose id
				# doesn't match its filename would silently merge two factions into one rep pool -- warn loudly.
				if (res as Faction).id != StringName(id):
					push_warning("Factions: '%s' has internal id '%s' (Reputation keys on the internal id, not the filename '%s')." % [path, (res as Faction).id, id])
				return res
	# A faction_id that resolves to nothing falls back to UNALIGNED -- surface it (editor/debug warning, not a GUT error).
	push_warning("Factions: no faction resource for id '%s' under %s -- the NPC falls back to UNALIGNED. Check the faction_id." % [id, FACTION_DIR])
	return null

## Every faction id available on disk: the .tres/.res filenames (sans extension) under FACTION_DIR, sorted.
## EDITOR/TEST use -- it scans the folder so the faction_id dropdown self-populates (NpcData._validate_property)
## and a drift test can catch a hand-maintained suggestion list (npc.gd) going stale. Runtime faction resolution
## stays by_id's direct path load (export-safe); this scan is never on a gameplay hot path.
static func ids() -> PackedStringArray:
	var out := PackedStringArray()
	var dir := DirAccess.open(FACTION_DIR)
	if dir == null:
		return out
	for f in dir.get_files():
		for ext in [".tres", ".res"]:
			if f.ends_with(ext):
				var fid := f.trim_suffix(ext)
				if not out.has(fid):
					out.append(fid)
				break
	out.sort()
	return out

## The faction ids as a comma-separated string, for a PROPERTY_HINT_ENUM_SUGGESTION dropdown hint_string.
static func ids_csv() -> String:
	return ",".join(ids())
