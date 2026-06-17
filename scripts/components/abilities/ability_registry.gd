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
