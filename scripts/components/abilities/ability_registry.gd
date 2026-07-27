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


## The ability SCENE path for a mechanic id — the inverse of ids()'s snake_case derivation (to_pascal_case
## roundtrips every shipped name; the test_upgrades drift guard keeps filenames conventional). Empty for a blank
## id. Does NOT check existence — pair with ResourceLoader.exists before load(). Export-safe (a direct path, no
## directory listing), unlike the editor/test-only ids() scan.
static func scene_path_for(id: StringName) -> String:
	if String(id).is_empty():
		return ""
	return "%s%s.tscn" % [ABILITY_DIR, String(id).to_pascal_case()]


## Lazy id -> AUTHORED display name cache ("" cached when the scene authors none); display_name_for applies the
## capitalize fallback on read. Static like StatText's cache — reset on an editor/plugin reload, and the ability
## scenes are otherwise fixed, so a one-time read per id is plenty.
static var _display_names: Dictionary = {}


## The PLAYER-FACING name for a mechanic id — the `display_name` authored on the ability scene's root
## (Ability.display_name), else the snake_case id title-cased ("wall_climb" -> "Wall Climb"), so a blank/missing
## name degrades to exactly the old capitalized-id look instead of blanking. THE canonical ability-name accessor:
## every UI that shows an ability id to the player (the upgrade-chip tooltip's "Installs …" line) reads through
## here. Reads the PackedScene's SceneState — never instantiate() — so a name lookup can't run ability lifecycle
## code. A blank id returns "" (nothing to name).
static func display_name_for(id: StringName) -> String:
	if String(id).is_empty():
		return ""
	if not _display_names.has(id):
		_display_names[id] = _authored_display_name(id)
	var authored := String(_display_names[id])
	return authored if not authored.is_empty() else String(id).capitalize()


## The display_name stored on `id`'s ability scene root, or "" — no scene by the naming convention, or no
## authored value (SceneState lists only NON-DEFAULT properties, so a blank export is simply absent).
static func _authored_display_name(id: StringName) -> String:
	var path := scene_path_for(id)
	if path == "" or not ResourceLoader.exists(path):
		return ""
	var ps := load(path) as PackedScene
	if ps == null:
		return ""
	var st := ps.get_state()
	if st == null or st.get_node_count() == 0:
		return ""
	for i in st.get_node_property_count(0):
		if String(st.get_node_property_name(0, i)) == "display_name":
			return String(st.get_node_property_value(0, i))
	return ""
