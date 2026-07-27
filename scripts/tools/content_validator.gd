class_name ContentValidator
extends RefCounted

## Aggregates the project's content sanity checks into ONE report: duplicate / blank item ids, ammo without a
## caliber, faction internal-id != filename, and Perk / GoapProfile authoring errors. run() returns the problem
## list (empty = clean) — reused by the validate_content.gd EditorScript (a designer runs it from the editor),
## a future "Validate" dock button, and the tests. The only side effects are the validate() helpers' own
## push_warnings; nothing is mutated. Tools-only (a recursive resource scan), never on a gameplay hot path.

const Factions := preload("res://scripts/faction/factions.gd")
const GoapLibrary := preload("res://scripts/npc/goap/goap_library.gd")
const FACTION_DIR := "res://resources/factions/"

## The full report — a list of human-readable content problems (empty = content is clean).
static func run() -> PackedStringArray:
	var problems := PackedStringArray()
	check_items(ItemDb.all_items(), problems)
	_check_factions(problems)
	_check_authored(problems)
	return problems

## Item checks (PURE over the given list, so it's unit-testable): unique non-blank ids + ammo needs a caliber.
static func check_items(items: Array, problems: PackedStringArray) -> void:
	var seen := {}
	for it in items:
		if it == null:
			continue
		var lbl: String = it.label()
		if it.id == &"":
			problems.append("Item '%s' has a blank id — it can't be save/load tracked." % lbl)
		elif seen.has(it.id):
			problems.append("Duplicate item id '%s' — item ids must be unique." % it.id)
		else:
			seen[it.id] = true
		if it.category == Item.Category.AMMO and it.caliber == &"":
			problems.append("Ammo item '%s' has no caliber — no weapon can draw from it." % lbl)

## Faction check: each faction .tres's INTERNAL id must equal its filename (Reputation keys on the internal id).
static func _check_factions(problems: PackedStringArray) -> void:
	for fid in Factions.ids():
		var f := load(FACTION_DIR + fid + ".tres") as Faction
		if f == null:
			f = load(FACTION_DIR + fid + ".res") as Faction
		if f != null and f.id != StringName(fid):
			problems.append("Faction '%s' has internal id '%s' — it must match the filename (Reputation keys on the internal id)." % [fid, f.id])

## Perk + GoapProfile authoring checks: scan authored resources and run each type's own validate().
static func _check_authored(problems: PackedStringArray) -> void:
	var paths := PackedStringArray()
	_collect_resources("res://resources/", paths)
	if ResourceLoader.exists("res://resources/goap/goapprofile.tres"):
		paths.append("res://resources/goap/goapprofile.tres")
	var goals := GoapLibrary.goal_names()
	var actions := GoapLibrary.action_names()
	for p in paths:
		var res := load(p)
		if res is Perk:
			if not (res as Perk).validate():
				problems.append("Perk '%s' (%s) has stat_bonuses keys that aren't CharacterStats attributes." % [(res as Perk).id, p])
		elif res is GoapProfile:
			if not (res as GoapProfile).validate(goals, actions):
				problems.append("GoapProfile '%s' has goal/action override rows with unknown names." % p)

## Recursively collect .tres/.res paths under `root` (skipping hidden dirs). Tools-only.
static func _collect_resources(root: String, out: PackedStringArray) -> void:
	var dir := DirAccess.open(root)
	if dir == null:
		return
	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		var full := root.path_join(entry)
		if dir.current_is_dir():
			if not entry.begins_with("."):
				_collect_resources(full, out)
		elif entry.ends_with(".tres") or entry.ends_with(".res"):
			out.append(full)
		entry = dir.get_next()
	dir.list_dir_end()
