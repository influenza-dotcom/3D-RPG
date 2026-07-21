extends RefCounted
## Ability registry: the unlockable-mechanic ids available on disk, so a designer picks an UpgradePickup's
## legacy `unlock_id` from a DROPDOWN that self-populates instead of a hand-maintained list. Each ability scene
## under scenes/components/abilities/ is named in PascalCase (Grapple, LaserSight, AirDash, …) and its Ability
## root's ability_id() is the snake_case of that name (grapple, laser_sight, air_dash) — so scanning the folder
## and snake-casing the filenames yields the mechanic ids. A drift test pins that convention.
##
## Preloaded as a const where needed (NO class_name on purpose → nothing for the test global script class cache
## to miss, matching Factions).

const ABILITY_DIR := "res://scenes/components/abilities/"

## The ability SCRIPTS live one folder over, named by the SAME snake_case convention (WallClimb.tscn -> id
## wall_climb -> wall_climb.gd). Deriving the script path FROM the id is what lets a runtime grant (a chip install /
## a save load) rebuild an ability with NO hand-maintained id->script table — this replaced the old
## Player.ABILITY_SCRIPTS dict, folding the two ability registries into this one.
const SCRIPT_DIR := "res://scripts/components/abilities/"

## Every unlockable-mechanic id on disk: each ability scene's PascalCase filename, snake-cased, sorted. EDITOR /
## TEST use — it self-populates the UpgradePickup `unlock_id` dropdown (_validate_property) and lets a drift test
## catch the convention (a scene filename's to_snake_case() == its Ability's ability_id()) going stale. Never on
## a gameplay hot path (the dropdown is editor-time; at runtime unlock_id is already set).
static func ids() -> PackedStringArray:
	var out := PackedStringArray()
	var dir := DirAccess.open(ABILITY_DIR)
	if dir == null:
		return out
	for f in dir.get_files():
		if f.ends_with(".tscn"):
			var id := f.trim_suffix(".tscn").to_snake_case()
			if not out.has(id):
				out.append(id)
	out.sort()
	return out

## The ability ids as a comma-separated string, for a PROPERTY_HINT_ENUM_SUGGESTION dropdown hint_string.
static func ids_csv() -> String:
	return ",".join(ids())

## The ability SCRIPT path for a mechanic id (by the snake_case convention above). Empty for a blank id. Does NOT
## check existence — pair with can_build() (or ResourceLoader.exists) before load().
static func script_path_for(id: StringName) -> String:
	if String(id).is_empty():
		return ""
	return "%s%s.gd" % [SCRIPT_DIR, id]

## True iff a RUNTIME grant can build this id — its ability script resolves on disk by the naming convention above.
## AbilityManager._build / can_grant lean on this (a typo'd or unconventional id returns false instead of silently
## building nothing), and a drift test pins that EVERY scanned scene id is buildable.
static func can_build(id: StringName) -> bool:
	var p := script_path_for(id)
	return p != "" and ResourceLoader.exists(p)
