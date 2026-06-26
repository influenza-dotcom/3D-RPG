@tool
extends RefCounted

## PURE logic for the Stats dashboard: collect which resources a file REFERENCES, and decide if a resource is
## referenced anywhere. The tab unions collect_referenced() across the whole project into lookup sets, then asks
## is_referenced() per resource to surface stragglers. Both pure + unit-tested; the tab owns the walk + counts.
##
## CAVEAT the tab must honor: lots of content here is loaded by FOLDER SCAN (ItemDb scans resources/items/, factions
## are scanned, abilities by filename) — those are USED without an explicit ref, so the unreferenced check must be
## limited to REFERENCE-used types (a WeaponData used via Item.weapon, a LootTable via NpcData.loot, ...). This file
## just answers "is X referenced by some file"; the tab restricts WHICH folders it flags.


## Resources referenced by one file's text: every `path="res://..."` (ext_resource / sub-resource), every
## ext_resource `uid="uid://..."`, and every load()/preload("res://...") call. {paths: Array, uids: Array}. Pure.
## Over-collecting references is the SAFE direction here — it only ever makes the unreferenced list SHORTER.
static func collect_referenced(text: String) -> Dictionary:
	var paths: Array = []
	var uids: Array = []
	var re_path := RegEx.new()
	re_path.compile("path=\"(res://[^\"]+)\"")
	for m in re_path.search_all(text):
		paths.append(m.get_string(1))
	var re_uid := RegEx.new()
	re_uid.compile("ext_resource[^\\]]*uid=\"(uid://[^\"]+)\"")  # ext_resource lines only -> never a .tres's own header uid
	for m in re_uid.search_all(text):
		uids.append(m.get_string(1))
	var re_load := RegEx.new()
	re_load.compile("(?:load|preload)\\(\\s*\"(res://[^\"]+)\"")
	for m in re_load.search_all(text):
		paths.append(m.get_string(1))
	return {"paths": paths, "uids": uids}


## Is the resource at `path` (uid `uid`, may be "") referenced anywhere? `ref_paths` / `ref_uids` are Dictionaries
## used as SETS (key -> true) of everything collected across the project. Pure + O(1) lookups.
static func is_referenced(path: String, uid: String, ref_paths: Dictionary, ref_uids: Dictionary) -> bool:
	return ref_paths.has(path) or (not uid.is_empty() and ref_uids.has(uid))
