@tool
extends VBoxContainer

## CYBER SUNDAY → Stats: a READ-ONLY content dashboard. Counts how much of each content type you have, and lists
## "straggler candidates" — resources in REFERENCE-used folders that nothing references (a WeaponData no Item uses,
## a LootTable no NpcData uses, a Dialogue no NPC uses, ...). It does ONE project walk to build the reference set
## (reusing the same idiom as Refs/Audit), then checks each candidate. Read-only — counts + flags, never writes.
##
## Folder-scanned types are DELIBERATELY excluded from the straggler check: ItemDb scans resources/items/ and
## factions are scanned, so those are USED with no explicit ref — flagging them would be noise. The check is scoped
## to types that are used via an explicit reference. "Unreferenced" here is a delete CANDIDATE, not a verdict.

const Stats := preload("res://addons/cybersunday_tools/dock_stats/content_stats.gd")
const RefScan := preload("res://addons/cybersunday_tools/dock_refs/ref_scan.gd")

const SKIP_DIRS: Array[String] = [".godot", ".git"]
const SCANNED_EXTS: Array[String] = ["gd", "tscn", "tres", "res"]

## Every content folder to COUNT (label -> dir), mirroring content_dock's *_DIR consts.
const COUNT_DIRS := {
	"Items": "res://resources/items/", "Weapons": "res://resources/weapons/", "NPCs": "res://resources/characters/",
	"Factions": "res://resources/factions/", "Quests": "res://resources/quests/", "Dialogue": "res://resources/dialogue/",
	"Loot": "res://resources/loot/", "Perks": "res://resources/perks/", "Status": "res://resources/status/",
	"Encounters": "res://resources/encounters/", "Schedules": "res://resources/schedules/", "Cutscenes": "res://resources/cutscenes/",
	"Barks": "res://resources/barks/", "Loadouts": "res://resources/loadouts/", "Maps": "res://resources/maps/",
}
## Folders whose resources are used via an explicit reference (so "unreferenced" is meaningful). Excludes
## items/factions (folder-scanned) and characters/encounters/loadouts (profile-export / WIP-archetype noise).
##
## `quests/` was MISSING from this list, which is why an orphaned quest could never surface here: every quest is
## reached by an explicit Resource reference (`QuestStarter.quest`, `TriggerVolume.start_quest`,
## `DialogueChoice.start_quest_on_choice`), so it belongs exactly as much as `dialogue/` does. Its absence is how
## `clear_the_block.tres` — referenced by NOTHING project-wide — sat unnoticed while this tab reported clean.
## NOTE this answers a narrower question than the Reach tab: "is it referenced by anything at all?", not "can a
## PLAYER get to it from the boot scene". A quest wired only into a level nothing links to passes HERE and still
## fails there, which is why both checks exist.
const ORPHAN_DIRS: Array[String] = [
	"res://resources/weapons/", "res://resources/loot/", "res://resources/dialogue/", "res://resources/status/",
	"res://resources/cutscenes/", "res://resources/maps/", "res://resources/schedules/", "res://resources/barks/",
	"res://resources/perks/", "res://resources/quests/",
]

const COLOR_HEAD := Color(0.6, 0.85, 1.0)
const COLOR_WARN := Color(1.0, 0.82, 0.3)

var _tree: Tree = null
var _summary: Label = null


func _init() -> void:
	name = "Stats"
	add_theme_constant_override("separation", 4)
	var bar := HBoxContainer.new()
	var refresh := Button.new()
	refresh.text = "Refresh"
	refresh.tooltip_text = "Re-count content + re-scan for unreferenced straggler candidates (one project walk; read-only)."
	refresh.pressed.connect(_refresh)
	bar.add_child(refresh)
	_summary = Label.new()
	_summary.modulate = Color(1, 1, 1, 0.7)
	bar.add_child(_summary)
	add_child(bar)
	_tree = Tree.new()
	_tree.hide_root = true
	_tree.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_tree.custom_minimum_size = Vector2(0, 90)
	_tree.item_activated.connect(_on_activated)
	add_child(_tree)
	_summary.text = "Click Refresh to count content + find unreferenced stragglers."


func _refresh() -> void:
	var ref_paths := {}
	var ref_uids := {}
	_collect("res://", ref_paths, ref_uids)

	_tree.clear()
	var root := _tree.create_item()
	var counts := _tree.create_item(root)
	counts.set_text(0, "Content counts")
	counts.set_custom_color(0, COLOR_HEAD)
	var total := 0
	for label in COUNT_DIRS:
		var c := _count_tres(String(COUNT_DIRS[label]))
		total += c
		var it := _tree.create_item(counts)
		it.set_text(0, "%s: %d" % [label, c])

	var orphans: Array = []
	for d in ORPHAN_DIRS:
		for path in _tres_in(d):
			if not Stats.is_referenced(path, RefScan.uid_for(path), ref_paths, ref_uids):
				orphans.append(path)
	orphans.sort()
	var orph := _tree.create_item(root)
	orph.set_text(0, "Unreferenced straggler candidates: %d" % orphans.size())
	orph.set_custom_color(0, COLOR_WARN if not orphans.is_empty() else COLOR_HEAD)
	for o in orphans:
		var it := _tree.create_item(orph)
		it.set_text(0, o)
		it.set_metadata(0, o)

	_summary.text = "%d content resources. %d straggler candidate(s) (items/factions excluded — they load by scan; verify before deleting)." % [total, orphans.size()]


## Walk every project file once, unioning collect_referenced() into the path/uid lookup sets.
func _collect(dir: String, ref_paths: Dictionary, ref_uids: Dictionary) -> void:
	var d := DirAccess.open(dir)
	if d == null:
		return
	d.list_dir_begin()
	var e := d.get_next()
	while e != "":
		if not e.begins_with("."):
			var full := dir.path_join(e)
			if d.current_is_dir():
				if not SKIP_DIRS.has(e):
					_collect(full, ref_paths, ref_uids)
			elif SCANNED_EXTS.has(full.get_extension()):
				var refs := Stats.collect_referenced(FileAccess.get_file_as_string(full))
				for p in refs["paths"]:
					ref_paths[p] = true
				for u in refs["uids"]:
					ref_uids[u] = true
		e = d.get_next()
	d.list_dir_end()


func _count_tres(dir: String) -> int:
	return _tres_in(dir).size()


## The .tres paths directly under `dir` (non-recursive; content folders are flat). [] when the folder is absent.
func _tres_in(dir: String) -> Array:
	var out: Array = []
	var d := DirAccess.open(dir)
	if d == null:
		return out
	for f in d.get_files():
		var fn := f.trim_suffix(".remap")
		if fn.get_extension() == "tres":
			out.append(dir.path_join(fn))
	return out


func _on_activated() -> void:
	var it := _tree.get_selected()
	if it == null:
		return
	var p: Variant = it.get_metadata(0)
	if p is String and (p as String).begins_with("res://") and ResourceLoader.exists(p):
		EditorInterface.edit_resource(load(p))
		EditorInterface.select_file(p)
