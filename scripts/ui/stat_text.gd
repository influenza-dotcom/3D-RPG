class_name StatText
extends Resource

## Editable player-facing TEXT for one CharacterStats entry — its title + one-line blurb. Pulled OUT of the
## hardcoded const tables that used to live in stat_info.gd (TITLES / BLURB) and into an authored resource, so the
## stat wording can be edited in the CYBER SUNDAY Text tab like every other bit of game prose — the "stats are
## bad, and I can't even edit them" problem. One .tres per stat in resources/stats/, keyed by `id`
## (&"strength" … &"agility", matching CharacterStats). StatInfo reads the title + blurb from here; the live
## "current effect" line stays COMPUTED in code (it's derived numbers, not prose). A missing/blank resource makes
## StatInfo fall back to a bare title, so a deleted file degrades gracefully instead of blanking a tooltip.

## Folder scanned for the six stat-text resources (one per CharacterStat id).
const STATS_DIR := "res://resources/stats/"

@export var id: StringName = &""                 ## the stat key: &"strength" … &"agility" (matches CharacterStats)
@export var display_name: String = ""            ## the stat's title as shown in menus (e.g. "Strength")
@export_multiline var description: String = ""   ## the one-line "what it does" blurb under the title

## Lazy id -> StatText cache, built once from STATS_DIR on first lookup (works at runtime AND in the editor). It's
## static so StatInfo's pure static formatter can reach it without an instance or an autoload. Rebuilt on a plugin
## / editor reload (statics reset); the six files are otherwise fixed, so a one-time scan is plenty.
static var _by_id: Dictionary = {}
static var _scanned: bool = false

## The StatText for `id`, or null if none is authored — StatInfo then falls back to a bare default title.
static func by_id(stat_id: StringName) -> Resource:
	if not _scanned:
		_scan()
	return _by_id.get(stat_id, null)

## Every authored stat-text resource (directory order) — for the Text tab / tooling.
static func all() -> Array:
	if not _scanned:
		_scan()
	return _by_id.values()

static func _scan() -> void:
	_scanned = true
	_by_id.clear()
	if not DirAccess.dir_exists_absolute(STATS_DIR):
		return
	for n in DirAccess.get_files_at(STATS_DIR):
		if n.get_extension().to_lower() != "tres":
			continue
		var st := load(STATS_DIR.path_join(n))
		if st != null and st.get("id") != &"":
			_by_id[st.get("id")] = st
