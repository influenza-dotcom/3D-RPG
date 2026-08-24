@tool
extends RefCounted

## PURE reachability engine for CYBER SUNDAY -> Reach: the one question nothing else in this project answers,
## "what can a PLAYER actually reach from the boot scene?"
##
## WHY IT EXISTS (the two existing finders are structurally blind, not merely incomplete):
##  * Stats (dock_stats/stats_view.gd) asks "is X referenced by ANY file?". resources/quests/recover_the_package.tres
##    is referenced by scenes/levels/SliceTestLevel.tscn — a level that resources/levels/SliceTestLevel.tres points
##    at, which NOTHING points at. Stats calls that quest healthy forever. It is not: no player can ever start it.
##  * Audit (panel_audit/scan_wiring.gd) resolves quest-id STRINGS (complete/advance/prereq). All THREE quest START
##    paths are Resource REFERENCES — QuestStarter.quest, TriggerVolume.start_quest, DialogueChoice.start_quest_on_choice
##    (quest_starter.gd:13, trigger_volume.gd:54, dialogue_choice.gd:72) — so a `field = "value"` regex cannot see them.
## Reach answers a THIRD question: transitive closure from the boot roots. It is the only one that can say
## "0 quests are reachable" while every other tab reports clean.
##
## SPLIT: this file is PURE (plain RefCounted, statics only, no EditorInterface, no scene tree, no DirAccess), so
## GUT drives it on fixture strings. reach_view.gd is the thin @tool glue that owns the roots read, the res:// walk,
## the Tree render and the double-click. Same split as content_stats.gd + stats_view.gd. No `class_name` — the view
## const-preloads this by path (the plugin's house idiom; a class_name here would add a global for a tool-only type).
##
## ------------------------------------------------------------------------------------------------------------
## THE TWO WAYS TO GET A REACHABILITY REPORT WRONG. Both are silent, and this project has already been bitten once.
##
##  1. OVER-REPORT (false positives): a lot of content here is loaded by FOLDER SCAN, never by an explicit
##     reference — ItemDb scans resources/items/ (item_db.gd:10 + :18), factions are scanned, abilities resolve by
##     filename. A naive "unreferenced" finder condemns the entire project. content_stats.gd documents this rule;
##     folder_scan_roots() below is the guard, and it is DERIVED from source (see its own comment), never a
##     hand-maintained whitelist that rots.
##  2. UNDER-REPORT (an empty, all-green report): the far more dangerous failure, because it looks like success.
##     text_debt.gd once printed "TOTAL: 0" while 132 of 267 strings were unauthored placeholders. An empty Reach
##     report means the folder-scan guard OVER-fired and swallowed every real orphan. The fix for a suspiciously
##     clean report is NEVER to widen the guard — see the scoping constraint on folder_scan_roots().
##
## Those two failures pull in OPPOSITE directions, so every "safe direction" note below has to say WHICH axis it is
## safe against — the phrase alone means nothing here. Shortening the problem list is safe against 1 and is exactly
## failure 2; lengthening it is the reverse. When they conflict, prefer lengthening: a false orphan is a loud row a
## designer checks once and dismisses, whereas a false green is silent, and a silent false green is the failure this
## tab exists to catch because nothing else in the project can.
##
## KNOWN BLIND SPOT, recorded so nobody later mistakes this closure for complete: a GDScript `class_name` reference
## carries NO res:// edge. scripts/faction/factions.gd, scripts/player/perks.gd and
## scripts/components/abilities/ability_registry.gd are reached at runtime purely through their global class names,
## so their DirAccess.open(FACTION_DIR / PERK_DIR / ABILITY_DIR) folder-scan roots never fire in this walk. That is
## an UNDER-reach, i.e. failure mode 1: it can only manufacture false orphans, never a false green. It does not
## touch the report's three rosters today, because every quest START SITE is a component @export living in a
## .tscn/.tres and those arrive through ordinary ext_resource edges. Do NOT "fix" it by whitelisting those folders —
## that is failure mode 2 wearing a helpful face. The real fix, if one is ever needed, is a class_name -> script-path
## index built from the engine's global-class list, feeding ordinary edges.
##
## ------------------------------------------------------------------------------------------------------------
## PERFORMANCE IS A CORRECTNESS CONSTRAINT HERE, not a nicety. The obvious shape — closure(roots, files, uid_index)
## with files = {path: text} — is a memory bomb that fires on a tab CLICK: addons/text_to_speech/voices/ alone is
## 59 MB of .flitevox.res, ref_scan.gd:14 deliberately does not skip addons/, and Godot Strings are UTF-32
## internally (so that is a multi-hundred-MB spike to answer a question about ~40 content files). So closure()
## takes text_of as an injected Callable and pulls text ONLY for the paths it POPS — a few hundred, not 1380.
## GUT injects `func(p): return fixture[p]` over a five-entry dict; the glue injects ScanCache.text_of directly.

const Stats := preload("res://addons/cybersunday_tools/dock_stats/content_stats.gd")
const ScanWiring := preload("res://addons/cybersunday_tools/panel_audit/scan_wiring.gd")

## Extensions whose text carries res:// EDGES. Deliberately NOT ref_scan.gd:16's list: "res" is DROPPED here.
## Verified on this tree: EVERY .res file is addons/text_to_speech/voices/*.flitevox.res — 59 MB of binary voice
## data with no res:// edges in it. Reading them would cost the entire budget of this scan for exactly zero edges.
##
## What dropping "res" COSTS, with the sign stated the right way round: a .res that IS a serialized resource still
## gets marked REACHED when something points at it, but we never walk THROUGH it, so anything reachable ONLY via
## that .res becomes a false orphan — this LENGTHENS the problem list, it does not shorten it. That is the direction
## to err in here (see the two-failures block above: a false orphan is loud and checkable, a false green is silent),
## and today it costs literally nothing because the only .res in the tree are binary voice blobs. The day a real
## serialized .res ships, put "res" back.
const SCANNED_EXTS: Array[String] = ["tscn", "tres", "gd"]

## The three fields that START a quest, read off the live scripts. Each holds a Quest REFERENCE (an ExtResource in
## the serialized form), which is why scan_wiring.gd's QUEST_ID_FIELDS — all id STRINGS — cannot see any of them.
const QUEST_START_FIELDS: Array[String] = ["quest", "start_quest", "start_quest_on_choice"]
## The owning component per start field, so a finding can say "QuestStarter.quest" rather than a bare "quest" — the
## designer needs to know WHICH component to go look for in the scene, and "quest" alone names three possible things.
const QUEST_START_OWNERS := {
	"quest": "QuestStarter.quest",
	"start_quest": "TriggerVolume.start_quest",
	"start_quest_on_choice": "DialogueChoice.start_quest_on_choice",
}
## The 4th start path is not a component field at all: Quest.next_quest (quest.gd:31) auto-starts the next stage
## when this one completes — QuestTracker.gd:139-140 is the call, `if quest.next_quest != null: start_quest(...)`.
## inherit_chained_starts synthesises a site with this label. (quest.gd:29 is prereq_quest_id, an id STRING and a
## GATE, not a starter; confusing the two is how a chained stage gets reported as unwired.)
const CHAIN_FIELD := "Quest.next_quest"

## The three actionable quest verdicts (see classify_quest — TWO independent axes, not one boolean).
const VERDICT_NO_START := "NO START SITE"
const VERDICT_UNREACHABLE_START := "START SITE NOT REACHABLE"
const VERDICT_OK := "OK"

## How a path entered the closure. Kept per-path so the report can PRINT the chain it followed AND say why each hop
## was taken — a reachability gauge nobody can audit is a green light nobody should trust.
const VIA_ROOT := "root"   ## a boot root (main_scene / an autoload)
const VIA_REF := "ref"     ## an explicit reference: ext_resource / load() / preload() / a bare res:// literal
const VIA_SCAN := "scan"   ## pulled in by the FOLDER-SCAN guard (ItemDb-style: used with no explicit ref)


# ============================================================================================================
# THE CLOSURE — a BFS over reference edges. The whole point of the tab.
# ============================================================================================================

## Transitive closure from `roots`, following every res:// edge. The ONLY entry point the view needs.
##
## Injected seams (this is what keeps the module pure AND cheap):
##   `text_of(path: String) -> String`     — the text of one file; "" when unreadable. Called ONCE per popped
##                                            scannable path and never otherwise. The glue passes ScanCache.text_of
##                                            (scan_cache.gd:48) directly and does NOT open a begin()/end() window:
##                                            that singleton has ONE window, both scans are synchronous on the main
##                                            thread so there is no dedupe to win, and a Reach end() landing inside
##                                            an Audit window would wipe the audit's cache mid-scan.
##   `dir_members(dir: String) -> Array`   — the res:// file paths DIRECTLY under `dir` (non-recursive), [] when the
##                                            folder is absent. Only ever called for a folder-scan root that fired.
##   `uid_index: Dictionary`               — {"uid://...": "res://..."} consulted BEFORE the engine's ResourceUID
##                                            database, so GUT can drive a uid-only edge with a fixture uid that is
##                                            registered nowhere. The glue can pass {} and let ResourceUID answer.
##
## Returns (every value JSON-safe — plain String / int / bool):
##   reached      { path: true }        the closure
##   depth_of     { path: int }         hops from a root (BFS order, so this is the SHORTEST chain)
##   parent_of    { path: String }      the file that pulled it in ("" for a root) — feeds chain_to()
##   via          { path: VIA_* }       why it was pulled in
##   folder_roots { dir: String }       folder-scan roots that fired -> the in-closure file that declared each
##   unread       [ path ]              popped scannable paths whose text came back EMPTY. A load()/read can return
##                                      nothing mid-reimport (the editor is usually open), and reporting a CLEAN
##                                      result over a file we never actually read is the exact lie this tab exists
##                                      to catch. These are SKIPS the view must surface, never silence.
##                                      The other way in is a reference to a file that no longer EXISTS (a broken
##                                      ext_resource, which scan_disk reports as its own ERROR). Both are real
##                                      findings and both must be shown; only the remedy differs (Rescan vs. fix
##                                      the reference), which is why the row states the path and claims nothing
##                                      about the cause.
static func closure(roots: Array, text_of: Callable, uid_index: Dictionary, dir_members: Callable) -> Dictionary:
	var st := {
		"reached": {}, "depth_of": {}, "parent_of": {}, "via": {}, "queue": [],
	}
	var folder_roots := {}
	var unread: Array = []
	for r in roots:
		_visit(st, normalize_ref(str(r), uid_index), "", 0, VIA_ROOT)
	# A plain index cursor, NOT pop_front(): Array.pop_front is O(n) and this queue holds every reached path.
	var queue: Array = st["queue"]
	var head := 0
	while head < queue.size():
		var path := str(queue[head])
		head += 1
		var ext := path.get_extension()
		if not SCANNED_EXTS.has(ext):
			continue  # reached, but it carries no edges (a .png / .ogg / a binary .res) — never read it
		var text := str(text_of.call(path))
		if text.is_empty():
			unread.append(path)
			continue
		var depth := int(st["depth_of"][path]) + 1
		var e := edges(text, ext)
		for p in e["paths"]:
			_visit(st, normalize_ref(str(p), uid_index), path, depth, VIA_REF)
		for u in e["uids"]:
			_visit(st, normalize_ref(str(u), uid_index), path, depth, VIA_REF)
		# THE FOLDER-SCAN GUARD, and note WHERE it is evaluated: inside the BFS, on a file that is ALREADY in the
		# closure. That scoping is the whole feature (see folder_scan_roots) — evaluated project-wide instead, a
		# single plugin file (stats_view.gd holds 15 res:// dir literals, quests among them) would whitelist every
		# content folder and this report would go permanently, silently empty.
		if ext == "gd":
			for d in folder_scan_roots(text):
				var scan_dir := str(d)
				if folder_roots.has(scan_dir):
					# Already fired from a file popped earlier, so its members are already in `reached` and a second
					# enumeration can only re-derive the same edges off disk. Three reachable autoloads declare
					# res://resources/items (item_db.gd:10, calibers.gd:12, item_ids.gd:12), so without this the
					# folder is walked three times for zero new edges. FIRST declarer wins, matching _visit's
					# first-visit-wins rule — it is the shallowest, so the receipt row in the report names the file
					# a designer would actually go and look at.
					continue
				folder_roots[scan_dir] = path
				for member in dir_members.call(scan_dir):
					# Through normalize_ref like every other edge: NOTHING enters `reached` un-normalised. It is a
					# no-op for a well-formed res:// path and returns "" (which _visit drops) for anything else, so
					# a dir_members that hands back a stray non-path — a GUT fixture, a future glue change — can
					# never inject a key the report would then print as a file.
					_visit(st, normalize_ref(str(member), uid_index), path, depth, VIA_SCAN)
	return {
		"reached": st["reached"], "depth_of": st["depth_of"], "parent_of": st["parent_of"], "via": st["via"],
		"folder_roots": folder_roots, "unread": unread,
	}


## Mark one child reached. FIRST visit wins, which (given BFS order) makes depth_of/parent_of describe the SHORTEST
## chain to each file — and is also what terminates a reference cycle: a re-visit returns immediately.
static func _visit(st: Dictionary, child: String, parent: String, depth: int, kind: String) -> void:
	if child.is_empty():
		return
	var reached: Dictionary = st["reached"]
	if reached.has(child):
		return
	reached[child] = true
	(st["depth_of"] as Dictionary)[child] = depth
	(st["parent_of"] as Dictionary)[child] = parent
	(st["via"] as Dictionary)[child] = kind
	(st["queue"] as Array).append(child)


## Normalise one raw reference into a res:// FILE path, or "" when it names no file. Handles every form a root or an
## edge actually arrives in:
##   `*res://managers/GameState.gd`  ProjectSettings marks a singleton autoload with a leading `*`
##   `*uid://nq66c5nwjfv5`           two autoloads (FreezeFrame, DialogueManager) are uid-ONLY — no path at all
##   `res://x.tscn::3`               a sub-resource ref points at the FILE that owns it
##   `res://x.tres.remap`            exported builds append .remap; harmless to strip in the editor too
static func normalize_ref(value: String, uid_index: Dictionary) -> String:
	var v := value.strip_edges()
	if v.begins_with("*"):
		v = v.substr(1)
	if v.begins_with("uid://"):
		return resolve_uid(v, uid_index)
	if not v.begins_with("res://"):
		return ""
	v = v.get_slice("::", 0)
	return v.trim_suffix(".remap")


## Resolve `uid://...` to its res:// path. `uid_index` is consulted FIRST so a test can drive an edge that exists
## only in a fixture; otherwise the ENGINE's database answers — ResourceUID.get_id_path, not a hand-built
## {RefScan.uid_for(p): p} map, which would collide every uid-less file onto the "" key (ref_scan.gd:36-43 returns
## "" for a file with no uid) and is another registry to keep in sync with an engine feature that already ships.
## "" when the uid is malformed or names nothing — an unresolvable edge is dropped, never fake-resolved.
static func resolve_uid(uid: String, uid_index: Dictionary) -> String:
	if uid_index.has(uid):
		return str(uid_index[uid])
	var id := ResourceUID.text_to_id(uid)
	if id == ResourceUID.INVALID_ID or not ResourceUID.has_id(id):
		return ""
	return str(ResourceUID.get_id_path(id))


# ============================================================================================================
# EDGES — what one file's text points at
# ============================================================================================================

## Every res:// edge out of one file's text, as {paths: Array, uids: Array}.
##
## The path/uid halves delegate to ContentStats.collect_referenced (content_stats.gd:17-32): ext_resource rows,
## `path="res://..."`, and load()/preload() calls. Mind the SIGN of its documented over-collection: it is not the
## sign it has in Stats. An extra edge makes the closure BIGGER and the problem list SHORTER — harmless for "is X
## referenced by anything?", but the false-GREEN direction for "can a player reach X?". It is accepted for the
## SERIALIZED formats, where an over-collected `path="res://…"` is an authored reference by construction because the
## serializer is what wrote it. It is NOT accepted for .gd source, where a path can sit in prose; that is why the
## masking below is mandatory rather than a nicety.
##
## What it MISSES is the one the boot chain depends on, so we add it for .gd source: a BARE res:// literal that is
## not inside a load()/preload(). scripts/ui/computerroom.gd:29 `const START_MENU_SCENE` and
## scripts/ui/start_menu.gd:19 `const GAME_SCENE` are the ONLY link from the boot scene to the game — without
## bare_resource_literals this report would stop at computerroom.tscn and declare the entire game unreachable.
##
## Bare literals are collected for `.gd` ONLY: the `#`-comment masking they require is a GDScript notion, and in a
## .tscn/.tres every real reference is already an ext_resource row that collect_referenced sees.
##
## For .gd, collect_referenced is fed the MASKED text as well — not just bare_resource_literals. Over-collection is
## the safe direction for a "what points here?" question (ref_scan/Stats), but it is the DANGEROUS direction here:
## a `## ... preload("res://scenes/levels/SliceTestLevel.tscn")` quoted in a docstring would make an unreachable
## level look reachable, and a false GREEN is the one failure this tab must never produce.
static func edges(text: String, ext: String) -> Dictionary:
	if ext != "gd":
		var refs := Stats.collect_referenced(text)
		return {"paths": refs["paths"], "uids": refs["uids"]}
	var masked := _mask_comments(text)
	var gd_refs := Stats.collect_referenced(masked)
	var paths: Array = gd_refs["paths"]
	paths.append_array(bare_resource_literals(masked))  # masking is idempotent, so the standalone contract holds
	return {"paths": paths, "uids": gd_refs["uids"]}


## Every `"res://….(tscn|tres|res|gd)"` literal in .gd source that is NOT the argument of a load()/preload() call.
##
## The EXTENSION is required, not optional: without it `"res://resources/items"` (a folder a script is about to
## DirAccess.open) would read as an edge to a file that does not exist, and every folder literal in the project
## would become a phantom hop in the chain. Directories are handled by folder_scan_roots instead — a different
## edge kind with a different meaning.
##
## Comments are masked FIRST (scan_disk.mask_comments via the scan_wiring.gd:55-59 idiom, which degrades to the raw
## text when scan_disk can't be loaded — a scan is never worth a hard failure). This project documents call idioms
## in prose, so an unmasked `## boots res://scenes/game.tscn` docstring would invent an edge the game does not have.
## Masking is length-preserving and idempotent, so calling this on already-masked text is safe. Verified live: both
## boot links survive masking (computerroom.gd:29, start_menu.gd:19 are code) while start_menu.gd:4's docstring
## mention of res://scenes/computerroom.tscn is correctly blanked.
##
## A literal carrying a FORMAT PLACEHOLDER is rejected — see the loop. It names a template, never a file.
static func bare_resource_literals(text: String) -> Array:
	var masked := _mask_comments(text)
	var out: Array = []
	var re := RegEx.new()
	re.compile("\"(res://[^\"]*\\.(?:tscn|tres|res|gd))\"")
	for m in re.search_all(masked):
		if _preceded_by_load_call(masked, m.get_start()):
			continue  # already collected by collect_referenced's load/preload regex; skipping avoids a duplicate
		var lit := m.get_string(1)
		if lit.contains("%") or lit.contains("{"):
			# A format TEMPLATE, not a path: scripts/tools/new_level.gd:20-21 hold "res://scenes/levels/%s.tscn" and
			# "res://resources/levels/%s.tres". Admitting one marks a file that can never exist as REACHED; the
			# closure then pops it, gets "" from text_of and parks it in `unread` on EVERY scan forever. A permanent
			# phantom row in the SKIPPED section is how a designer learns to ignore that section — and skipped is the
			# one section that must never be ignored, because it is where "we never actually read this" is admitted.
			continue
		out.append(lit)
	return out


## Folders a script SCANS at runtime, so every file directly under them counts as USED even though nothing
## references it by path. This is the false-positive guard: without it ItemDb's 35 items — item_db.gd:18 opens
## ITEMS_DIR and load()s whatever it finds — would be condemned, and a report that condemns authored content is
## noise a designer learns to ignore.
##
## What it fires on TODAY, stated exactly so the receipt in the tab can be checked against it: res://resources/items,
## declared by the three reachable autoloads item_db.gd / calibers.gd / item_ids.gd. It does NOT fire for the
## factions, perks or abilities folders — not because those are not folder-scanned (they are) but because
## factions.gd / perks.gd / ability_registry.gd are only ever reached through their global `class_name`, which
## carries no res:// edge, so the closure never pops them. See the KNOWN BLIND SPOT note in the file header; the
## remedy is a class_name index, never a whitelist entry here.
##
## DERIVED from source, never a hand-maintained whitelist — a whitelist rots the first time someone adds a scanned
## folder, and it rots silently. Two rules the naive version gets wrong:
##
##  1. The literal must be a DIRECTORY (no extension). A file literal is an ordinary reference edge.
##  2. The literal, or the `const` NAME bound to it, must appear inside a `DirAccess.open(` argument. item_db.gd
##     writes `DirAccess.open(ITEMS_DIR)` — the const name at :18, with the literal all the way up at :10 — so
##     matching only inline literals would miss the single most important case in the project.
##
## And the constraint that is NOT visible from inside this function, so it is stated here too: the CALLER must
## evaluate this only on files ALREADY IN THE CLOSURE (closure() does). Run project-wide, stats_view.gd alone kills
## the feature — its COUNT_DIRS (stats_view.gd:20-26) holds 15 extension-less res:// dir literals INCLUDING
## res://resources/quests/, and :100 calls DirAccess.open(dir). That one plugin file would whitelist every content
## folder in the game and the report would go permanently, silently empty. (It does not fire even project-wide,
## because COUNT_DIRS is a Dictionary rather than a string const and `dir` is a parameter — but the report must not
## depend on that accident, and a GUT case pins the stats_view shape returning [].)
##
## Bare `res://` is excluded: the project root holds config, not scanned content, and whitelisting it buys nothing.
## Returned dirs are normalised WITHOUT a trailing slash so `res://resources/items` and `res://resources/items/`
## are one root.
##
## AND THE SIGN OF THE ERROR, because the whole acceptance bar turns on it: over-approximating here SHORTENS the
## problem list. That is safe against failure mode 1 (condemning folder-scanned content) and is EXACTLY failure
## mode 2 — a root on `res://scenes/levels` would turn the entire level roster green in one step. It is not a free
## trade, it is a bounded one, and THREE properties do the bounding. All three must survive any edit here:
##   1. SCOPE — closure() evaluates this only on .gd files ALREADY IN the closure. Run project-wide instead and one
##      plugin file ends the feature; see the stats_view paragraph above.
##   2. BLAST RADIUS — `dir_members` is NON-RECURSIVE, so a root that fires can only green the files DIRECTLY under
##      one directory, never a subtree. `res://resources` holds no files at all, only folders. Keep it that way.
##   3. RECEIPT — every root that fires is returned with the file that DECLARED it, and the tab prints both. An
##      over-approximation stays auditable instead of silently shortening the findings.
## The MISS direction is recorded too, since it is the one that condemns real content: a `DirAccess.open(` whose
## argument sits on the NEXT line is not seen (the match is rest-of-line). No call site in this project is written
## that way, and a loud false orphan is the failure we would rather have if one ever is.
static func folder_scan_roots(text: String) -> Array:
	if not ("DirAccess.open(" in text):
		return []  # fast path: almost no .gd file scans a folder, and this skips the mask + the const pass entirely
	var masked := _mask_comments(text)
	var consts := _string_const_bindings(masked)
	var out: Array = []
	var seen := {}
	var re_open := RegEx.new()
	re_open.compile("DirAccess\\.open\\(")
	var re_lit := RegEx.new()
	re_lit.compile("\"(res://[^\"]*)\"")
	var re_ident := RegEx.new()
	re_ident.compile("[A-Za-z_][A-Za-z0-9_]*")
	for m in re_open.search_all(masked):
		# The rest of the LINE, not a bracket-matched argument. Arguments nest — `DirAccess.open(ITEMS_DIR.path_join(sub))`
		# — and writing a matcher to extract exactly one buys nothing here: comments are already masked away, so the
		# tail of the line is pure code, and every extra candidate it yields must STILL be a res:// DIRECTORY literal
		# or resolve to one through a string const before _add_dir accepts it.
		var frag := _rest_of_line(masked, m.get_end())
		for lit in re_lit.search_all(frag):
			_add_dir(lit.get_string(1), out, seen)
		for ident in re_ident.search_all(frag):
			var name := ident.get_string(0)
			if consts.has(name):
				_add_dir(str(consts[name]), out, seen)
	out.sort()
	return out


static func _add_dir(literal: String, out: Array, seen: Dictionary) -> void:
	var dir := literal.strip_edges().trim_suffix("/")
	# The project ROOT is deliberately not a content-scan root: it holds config, not authored content. Which clause
	# catches it depends on the spelling, so both are here — a literal "res://" trims to "res:/" and fails
	# begins_with, while "res:///" trims to "res://" and would otherwise slip straight through.
	if dir.is_empty() or not dir.begins_with("res://") or dir == "res:/" or dir == "res://":
		return
	if not literal.get_extension().is_empty():
		return  # a FILE literal is an ordinary reference edge, not a folder scan
	if seen.has(dir):
		return
	seen[dir] = true
	out.append(dir)


## Module-level `const NAME := "res://..."` bindings in .gd source, as {NAME: literal}. Only plain string consts —
## a Dictionary/Array const (stats_view.gd's COUNT_DIRS / ORPHAN_DIRS) binds no single directory to a name, so it
## cannot satisfy the "const name inside DirAccess.open(" rule and correctly contributes nothing.
static func _string_const_bindings(text: String) -> Dictionary:
	var out := {}
	var re := RegEx.new()
	re.compile("(?m)^\\s*const\\s+([A-Za-z_][A-Za-z0-9_]*)[^\"\\n]*=\\s*\"(res://[^\"]*)\"")
	for m in re.search_all(text):
		out[m.get_string(1)] = m.get_string(2)
	return out


## Is the `"` at `quote_index` the opening quote of a load()/preload()/ResourceLoader.load() argument? Walks back
## over whitespace to the `(`, then over the identifier before it, and asks whether that identifier ENDS with
## "load" — which covers `load`, `preload` and `ResourceLoader.load` in one test.
static func _preceded_by_load_call(text: String, quote_index: int) -> bool:
	var i := quote_index - 1
	while i >= 0 and (text[i] == " " or text[i] == "\t"):
		i -= 1
	if i < 0 or text[i] != "(":
		return false
	i -= 1
	var last := i
	while i >= 0 and _is_callee_char(text[i]):
		i -= 1
	if last <= i:
		return false  # nothing but `(` in front — a parenthesised expression, not a call
	return text.substr(i + 1, last - i).ends_with("load")


## One character of a callee expression: an identifier char, or the `.` of a qualified call (ResourceLoader.load).
static func _is_callee_char(c: String) -> bool:
	return c == "_" or c == "." or c.is_valid_identifier() or c.is_valid_int()


static func _rest_of_line(text: String, from: int) -> String:
	var nl := text.find("\n", from)
	if nl < 0:
		return text.substr(from)
	return text.substr(from, nl - from)


## Blank out `#` line-comments, reusing the SAME masker every other scanner in this plugin uses (scan_disk's
## quote-aware, length-preserving mask_comments) through scan_wiring.gd:55-59, which already carries the
## degrade-to-raw-text fallback. One primitive, one behaviour — a second implementation here would drift.
static func _mask_comments(text: String) -> String:
	return ScanWiring._mask_comments(text)


# ============================================================================================================
# SERIALIZED-RESOURCE READING — ext_resource rows, and the fields that hold a Resource REFERENCE
# ============================================================================================================

## {id: path} from a .tscn/.tres's `[ext_resource ... path="..." id="N"]` rows, so an `ExtResource("N")` field value
## can be resolved to a file. The row is matched anchored at line start and `path=` / `id=` are captured
## INDEPENDENTLY — attribute order is not guaranteed by the serializer, and SliceTestLevel.tscn:15 proves a row can
## carry a path with no uid while others carry both. A uid-ONLY row (no path=) is left UNRESOLVED rather than
## fake-resolved; the closure still follows it, because collect_referenced picks the uid up separately.
static func ext_resource_index(text: String) -> Dictionary:
	var out := {}
	var re_row := RegEx.new()
	re_row.compile("(?m)^\\[ext_resource\\b[^\\]]*\\]")
	var re_path := RegEx.new()
	re_path.compile("path=\"(res://[^\"]+)\"")
	var re_id := RegEx.new()
	# The `\b` is LOAD-BEARING, not tidiness. Godot writes ext_resource attributes as
	# `type=… uid="uid://…" path=… id="9_quest"`, and the literal substring `id="` occurs INSIDE `uid="`.
	# RegEx takes the LEFTMOST match, so an unanchored `id="([^"]+)"` captures the uid string on every row
	# written in that order — ext_resource_index then maps `uid://cgt8…` -> path, `ExtResource("9_quest")`
	# resolves to "", and the whole tab degrades silently: SliceTestLevel's QuestStarter stops resolving (so
	# recover_the_package.tres reports "no start site" instead of "start site not reachable" — a WRONG verdict
	# that still looks like a finding), and trenchboom.tres's LevelData.scene never resolves, emptying the level
	# roster. `\b` cannot match between `u` and `i`, so it selects the real `id=` attribute.
	re_id.compile("\\bid=\"([^\"]+)\"")
	for m in re_row.search_all(text):
		var row := m.get_string(0)
		var mp := re_path.search(row)
		var mi := re_id.search(row)
		if mp != null and mi != null:
			out[mi.get_string(1)] = mp.get_string(1)
	return out


## Every `ExtResource("id")` in one serialized field VALUE, minus any that sits inside a typed-collection bracket.
##
## THE TRAP, verified against resources/quests/clear_the_block.tres:31 —
##     objectives = Array[ExtResource("1_tveky")]([SubResource("Resource_1cldg"), SubResource("Resource_0imx4")])
## the FIRST ExtResource on that line is the element-TYPE script (quest_objective.gd), not an element. Taking the
## first match would report a quest's objective SCRIPT as the started quest. So: match them all, then discard any
## whose span falls inside the `Array[…]` (or `Dictionary[…]`) type bracket. Bracket-counted, so nesting is fine.
static func ext_resource_ids(value: String) -> Array:
	var spans := _type_bracket_spans(value)
	var out: Array = []
	var re := RegEx.new()
	re.compile("ExtResource\\(\\s*\"([^\"]+)\"\\s*\\)")
	for m in re.search_all(value):
		var start := m.get_start()
		var inside := false
		for s in spans:
			var span := s as Array
			if start >= int(span[0]) and start <= int(span[1]):
				inside = true
				break
		if not inside:
			out.append(m.get_string(1))
	return out


## [start, end] index pairs of every `Array[...]` / `Dictionary[...]` TYPE bracket in `value` (inclusive of both
## brackets), bracket-counted so `Array[Array[ExtResource("1")]]` collapses to one span.
static func _type_bracket_spans(value: String) -> Array:
	var out: Array = []
	var re := RegEx.new()
	re.compile("\\b(?:Array|Dictionary)\\[")
	for m in re.search_all(value):
		var open := m.get_end() - 1  # index of the `[`
		var depth := 0
		var i := open
		while i < value.length():
			var c := value[i]
			if c == "[":
				depth += 1
			elif c == "]":
				depth -= 1
				if depth == 0:
					break
			i += 1
		out.append([open, i])
	return out


## Every quest START site declared in one file's text, as [{field, label, id, path}] — `path` is "" when the
## ExtResource id resolves to no row (a uid-only row, or a hand-written fixture with no header). The caller must
## SHOW those rather than drop them: a dropped site silently downgrades a wired quest to NO START SITE.
##
## `text` is SERIALIZED text (.tscn/.tres) and nothing else — the glue's SURVEY_EXTS enforces it. No comment masking
## happens here (a `#` in a .tscn is data, not a comment), so handing this .gd source would let a `## quest =
## ExtResource("x")` docstring register a phantom start site, which is a false GREEN. Use the serialized files.
##
## Split per `[node ...]` / `[sub_resource ...]` / `[resource]` block with ScanWiring._resource_blocks
## (scan_wiring.gd:374-391) so a field never pairs with a value from a different node.
##
## The field names are the REAL exports: QuestStarter.quest (quest_starter.gd:13), TriggerVolume.start_quest
## (trigger_volume.gd:54), DialogueChoice.start_quest_on_choice (dialogue_choice.gd:72). Each is matched anchored at
## line start and independently, so `quest` does not match `quest_area_id` / `required_quest_id` and `start_quest`
## does not match `start_quest_on_choice`. And because a site must be an ExtResource REFERENCE, an id-STRING field
## like `prereq_quest_id = &"clear_the_block"` yields nothing — that reference-vs-string distinction is the entire
## reason this module exists instead of another QUEST_ID_FIELDS entry.
static func quest_start_sites(text: String) -> Array:
	var out: Array = []
	# FAST REJECT, and it is a performance-as-correctness constraint rather than a nicety: the glue calls this on
	# EVERY serialized file in the project on a Rescan — 378 of them here, one a 1.1 MB / 1129-block level scene —
	# and the work below is a block split plus a compiled RegEx per block per field. A plain substring test on the
	# raw text can never produce a FALSE NEGATIVE, because the per-block regex requires that same literal field
	# name, so this only skips files that could not have matched. Derived from the const so it cannot rot if a
	# fourth start field is ever added.
	var mentions := false
	for field in QUEST_START_FIELDS:
		if text.contains(str(field)):
			mentions = true
			break
	if not mentions:
		return out

	var index := ext_resource_index(text)
	# Compiled ONCE per file, not once per block. Placed inside the block loop this is 3 * 1129 = 3387 PCRE2 compiles
	# for trenchboom_test_level.tscn alone, to answer a question about at most a handful of nodes.
	var matchers: Array = []
	for field in QUEST_START_FIELDS:
		matchers.append([str(field), _field_value_regex(str(field))])

	for block in ScanWiring._resource_blocks(text):
		var b := str(block)
		for entry in matchers:
			var pair := entry as Array
			var field := str(pair[0])
			if not b.contains(field):
				continue  # the same never-false-negative reject, per block: most blocks are geometry nodes
			for value in _field_values_with(b, pair[1] as RegEx):
				for id in ext_resource_ids(value):
					out.append({
						"field": field,                                       # the raw export name
						"label": str(QUEST_START_OWNERS.get(field, field)),   # Component.field, for the finding row
						"id": str(id),
						"path": str(index.get(id, "")),
					})
	return out


## The res:// path a single `field = ExtResource("N")` names, or "" when there is none. Read from the `[resource]`
## block when the file has one, so a LevelData's `scene` (level_data.gd:16) or a Quest's `next_quest` (quest.gd:31)
## is read off the resource itself rather than off some unrelated sub_resource.
static func resource_field_ref(text: String, field: String) -> String:
	var index := ext_resource_index(text)
	for value in _field_values(resource_block(text), field):
		var ids := ext_resource_ids(value)
		if not ids.is_empty():
			return str(index.get(ids[0], ""))
	return ""


## The `[resource]` block of a .tres, or the whole text when there is none (a .tscn, or a bare fixture string).
static func resource_block(text: String) -> String:
	for block in ScanWiring._resource_blocks(text):
		if str(block).begins_with("[resource]"):
			return str(block)
	return text


## Does this file's header declare `script_class="X"`? The one-line gate scan_wiring.gd:204 uses to avoid load()ing
## every .tres in the project just to find out what type it is — a text test, so it costs one read and never a load.
static func declares_script_class(text: String, script_class: String) -> bool:
	return ("script_class=\"%s\"" % script_class) in text


## Every raw right-hand side assigned to `field`, per line. Values are returned unparsed (ext_resource_ids does the
## parsing) so an Array-typed field keeps its whole serialization intact for the type-bracket check. The one-shot
## spelling, for resource_field_ref and the GUT cases; quest_start_sites hoists the compile instead.
static func _field_values(text: String, field: String) -> Array:
	return _field_values_with(text, _field_value_regex(field))


## The compiled matcher for one field: anchored at LINE START and naming the field exactly, which is what keeps
## `quest` from matching `required_quest_id` and `start_quest` from matching `start_quest_on_choice`. Split out so a
## caller scanning many blocks compiles it once — see quest_start_sites.
static func _field_value_regex(field: String) -> RegEx:
	var re := RegEx.new()
	re.compile("(?m)^\\s*" + field + "\\s*=\\s*(.*)$")
	return re


static func _field_values_with(text: String, re: RegEx) -> Array:
	var out: Array = []
	for m in re.search_all(text):
		out.append(m.get_string(1).strip_edges())
	return out


# ============================================================================================================
# VERDICTS — two axes, three answers
# ============================================================================================================

## Classify one quest. TWO INDEPENDENT AXES, deliberately not collapsed into one boolean, because the two failures
## need opposite fixes and a single "reachable: false" would hide which one you have:
##
##   axis 1 — does a start site EXIST at all?      no  -> NO START SITE
##            (nothing anywhere assigns this quest to a QuestStarter.quest / TriggerVolume.start_quest /
##             DialogueChoice.start_quest_on_choice. The quest is authored but unwired: WIRE IT.
##             resources/quests/clear_the_block.tres is this case — referenced by nothing project-wide.)
##   axis 2 — can the player REACH a start site?   no  -> START SITE NOT REACHABLE
##            (the wiring exists but lives in a scene the boot chain never loads. The quest does not need wiring,
##             it needs its HOST reached: recover_the_package.tres is wired to a QuestStarter in
##             scenes/levels/SliceTestLevel.tscn, and nothing points at SliceTestLevel.tres.)
##   both yes                                          -> OK
##
## `sites` is every start site found for THIS quest project-wide, as [{file, field, label}] — only `file` is read
## here; `label` is what the view PRINTS ("QuestStarter.quest"). A site inside the quest's own file is skipped — a
## resource cannot be its own start site (it is the self-chain case of next_quest).
static func classify_quest(path: String, sites: Array, reached: Dictionary) -> String:
	var real := 0
	for s in sites:
		var file := str((s as Dictionary).get("file", ""))
		if file.is_empty() or file == path:
			continue
		real += 1
		if reached.has(file):
			return VERDICT_OK
	return VERDICT_NO_START if real == 0 else VERDICT_UNREACHABLE_START


## Give every chained quest stage its parent as a start site, so a stage that is only ever started by
## Quest.next_quest (quest.gd:31) is not reported as unwired.
##
## ONE hop per quest is enough, and is also why no cycle guard is needed: every quest in the map is iterated, so
## A->B->C is covered by A's hop and B's hop, and each edge is added exactly once (a self-chain A->A is filtered by
## classify_quest's `file == path` skip). Transitivity of the VERDICT comes free from the closure itself — a
## reachable A pulls B in as an ordinary ExtResource edge, which is what makes B's site test true.
##
## `sites_by_quest` {quest_path: [{file, field, label}]}, `next_of` {quest_path: next_quest_path}. Returns a NEW
## map; the input is not mutated. A quest that appears only in `next_of` gains an entry, so a chained stage with no
## component wiring of its own is still classified rather than dropped.
static func inherit_chained_starts(sites_by_quest: Dictionary, next_of: Dictionary) -> Dictionary:
	var out := {}
	for q in sites_by_quest:
		out[str(q)] = (sites_by_quest[q] as Array).duplicate()
	for q in next_of:
		var parent := str(q)
		var child := str(next_of[q])
		if child.is_empty():
			continue
		if not out.has(child):
			out[child] = []
		(out[child] as Array).append({"file": parent, "field": CHAIN_FIELD, "label": CHAIN_FIELD})
	return out


## The chain the closure actually followed to `path`, root FIRST. Every hop, including the .gd glue scripts that
## carried an edge. [] when `path` was never reached — which is itself the honest answer.
static func chain_to(path: String, parent_of: Dictionary) -> Array:
	var out: Array = []
	var cur := path
	var guard := 0
	while not cur.is_empty() and parent_of.has(cur) and guard < 512:
		out.append(cur)
		cur = str(parent_of[cur])
		guard += 1
	out.reverse()
	return out


## The same chain with the .gd hops elided — the readable form for the header row. The real boot chain runs
## computerroom.tscn -> computerroom.gd -> start_menu.tscn -> start_menu.gd -> game.tscn -> ..., and the scripts are
## GLUE carrying the edge, not places the player goes. The first and last hops are always kept so the chain still
## states where it started and where it ended, and the full chain stays available via chain_to for auditing.
static func content_chain(chain: Array) -> Array:
	var out: Array = []
	for i in chain.size():
		var p := str(chain[i])
		if i == 0 or i == chain.size() - 1 or p.get_extension() != "gd":
			out.append(p)
	return out


# ============================================================================================================
# THE REPORT
# ============================================================================================================

## Assemble the whole report from a closure result plus what the glue found on disk. PURE and JSON-safe: every value
## below is a plain String / int / bool / Array / Dictionary — ids are str()'d AT CONSTRUCTION, never later.
## (StringName is the trap: JSON.stringify does not FAIL on one, it silently COERCES it to a quoted String and the
## document re-parses fine, so a round-trip guard is blind to exactly the bug it looks like it is catching.)
##
## `found` is the glue's disk survey:
##   levels_wired     [path]        every .tscn some LevelData.scene points at (header-gated on script_class)
##   levels_authored  [path]        every .tscn directly under res://scenes/levels/ — UNIONED in so an authored but
##                                  unwired level shows as UNREACHABLE instead of vanishing from the roster
##   quests           [path]        every Quest .tres found (NOT just the ones with sites — a quest with no site
##                                  anywhere must still appear, as NO START SITE. This is the clear_the_block row.)
##   quest_sites      {quest: [{file, field, label}]}   quest_start_sites() INVERTED: the glue walks the project,
##                                  and for every site whose `path` resolved it appends {file: <the file scanned>,
##                                  field, label} under that quest. `file` is what the reachability test keys on.
##   quest_next       {quest: next_quest_path}   resource_field_ref(text, "next_quest") per Quest .tres
##   dialogue         [path]        every DialogueResource .tres found
##   skipped          [path]        files the glue could not read/load (a mid-reimport load() returns null or an
##                                  empty PackedScene; the editor is usually open). Merged with the closure's own
##                                  `unread` so a clean-looking report can never be built over a file nobody read.
##
## Returns {chain, chain_full, chain_leaf, levels, quests, dialogue, skipped, folder_roots, counts}.
static func build_report(cl: Dictionary, found: Dictionary) -> Dictionary:
	var reached: Dictionary = cl.get("reached", {})
	var depth_of: Dictionary = cl.get("depth_of", {})
	var parent_of: Dictionary = cl.get("parent_of", {})
	var via: Dictionary = cl.get("via", {})

	var levels := level_roster(_arr(found, "levels_wired"), _arr(found, "levels_authored"), cl)
	var levels_reachable := 0
	for row in levels:
		if bool((row as Dictionary)["reachable"]):
			levels_reachable += 1

	var sites := inherit_chained_starts(_dict(found, "quest_sites"), _dict(found, "quest_next"))
	var quest_paths := {}
	for q in _arr(found, "quests"):
		quest_paths[str(q)] = true
	for q in sites:
		quest_paths[str(q)] = true
	var quest_keys := quest_paths.keys()
	quest_keys.sort()
	var quests: Array = []
	# Keyed by assignment, not a `{CONST: 0}` literal — a dictionary literal's key syntax is subtle enough that
	# spelling it out removes the question of whether the CONSTANT or its NAME ends up as the key.
	var tally := {}
	tally[VERDICT_OK] = 0
	tally[VERDICT_NO_START] = 0
	tally[VERDICT_UNREACHABLE_START] = 0
	for q in quest_keys:
		var path := str(q)
		var my_sites: Array = sites.get(path, [])
		var verdict := classify_quest(path, my_sites, reached)
		tally[verdict] = int(tally[verdict]) + 1
		var site_rows: Array = []
		for s in my_sites:
			var sd := s as Dictionary
			var file := str(sd.get("file", ""))
			var field := str(sd.get("field", ""))
			site_rows.append({
				"file": file,
				"field": field,
				"label": str(sd.get("label", QUEST_START_OWNERS.get(field, field))),
				"reachable": reached.has(file),
			})
		quests.append({
			"path": path, "verdict": verdict, "reachable": reached.has(path), "sites": site_rows,
		})

	var dialogue: Array = []
	var dialogue_reachable := 0
	var dlg_paths := _arr(found, "dialogue")
	dlg_paths.sort()
	for d in dlg_paths:
		var path := str(d)
		var ok: bool = reached.has(path)
		if ok:
			dialogue_reachable += 1
		dialogue.append({"path": path, "reachable": ok, "via": str(via.get(path, ""))})

	# The chain to PRINT: the boot chain lands in the shallowest reachable level scene (ties broken by path so the
	# header row is stable between runs). With no reachable level at all, fall back to the deepest thing we reached,
	# so the report can ALWAYS show the chain it followed — a report that cannot show its work is not auditable.
	var leaf := _shallowest_reachable_level(levels)
	if leaf.is_empty():
		leaf = _deepest_reached(depth_of)
	var full := chain_to(leaf, parent_of)

	# str() AT CONSTRUCTION, like every other value in this report — these two were the only lists that arrived
	# straight from a caller's Array instead of being rebuilt row by row, and so the only place a StringName could
	# have ridden through. It would not have thrown: JSON.stringify COERCES a StringName into a quoted String and
	# the document re-parses fine, which is exactly why a round-trip guard downstream is blind to this leak.
	var skipped: Array = []
	for sp in _arr(found, "skipped"):
		skipped.append(str(sp))
	for un in _arr(cl, "unread"):
		skipped.append(str(un))
	skipped.sort()

	var folder_roots: Dictionary = cl.get("folder_roots", {})
	var folder_root_rows: Array = []
	var folder_keys := folder_roots.keys()
	folder_keys.sort()
	for k in folder_keys:
		folder_root_rows.append({"dir": str(k), "declared_by": str(folder_roots[k])})
	var scanned_members := 0
	for p in via:
		if str(via[p]) == VIA_SCAN:
			scanned_members += 1

	return {
		"chain": content_chain(full),
		"chain_full": full,
		"chain_leaf": leaf,
		"levels": levels,
		"quests": quests,
		"dialogue": dialogue,
		"skipped": skipped,
		"folder_roots": folder_root_rows,
		"counts": {
			"reached": reached.size(),
			"levels_total": levels.size(),
			"levels_reachable": levels_reachable,
			"quests_total": quests.size(),
			"quests_ok": int(tally[VERDICT_OK]),
			"quests_no_start": int(tally[VERDICT_NO_START]),
			"quests_unreachable_start": int(tally[VERDICT_UNREACHABLE_START]),
			"dialogue_total": dialogue.size(),
			"dialogue_reachable": dialogue_reachable,
			"folder_scan_roots": folder_root_rows.size(),
			"folder_scan_members": scanned_members,
			"skipped": skipped.size(),
		},
	}


## The level roster: every .tscn a LevelData points at, UNIONED with every .tscn authored under scenes/levels/.
## The union is the point — a level nobody wired must show up as UNREACHABLE, not disappear because no LevelData
## names it. Rows are {path, reachable, via, depth, wired}; `wired` says a LevelData.scene points at it, so
## "authored, never wired" and "wired, never loaded" read as the different problems they are.
static func level_roster(wired: Array, authored: Array, cl: Dictionary) -> Array:
	var reached: Dictionary = cl.get("reached", {})
	var depth_of: Dictionary = cl.get("depth_of", {})
	var via: Dictionary = cl.get("via", {})
	var wired_set := {}
	var roster := {}
	for w in wired:
		wired_set[str(w)] = true
		roster[str(w)] = true
	for a in authored:
		roster[str(a)] = true
	var keys := roster.keys()
	keys.sort()
	var out: Array = []
	for k in keys:
		var path := str(k)
		out.append({
			"path": path,
			"reachable": reached.has(path),
			"via": str(via.get(path, "")),
			"depth": int(depth_of.get(path, -1)),
			"wired": wired_set.has(path),
		})
	return out


static func _shallowest_reachable_level(levels: Array) -> String:
	var best := ""
	var best_depth := 1 << 30
	for row in levels:
		var r := row as Dictionary
		if not bool(r["reachable"]):
			continue
		var d := int(r["depth"])
		var p := str(r["path"])
		if d < best_depth or (d == best_depth and p < best):
			best_depth = d
			best = p
	return best


static func _deepest_reached(depth_of: Dictionary) -> String:
	var best := ""
	var best_depth := -1
	for p in depth_of:
		var d := int(depth_of[p])
		var path := str(p)
		if d > best_depth or (d == best_depth and path < best):
			best_depth = d
			best = path
	return best


## Dictionary reads are Variant, so these keep the typed locals above honest (and tolerate a `found` bundle that
## simply omits a key — a partial survey degrades to an empty section, never to a crash mid-report).
static func _arr(d: Dictionary, key: String) -> Array:
	var out: Array = []
	var v: Variant = d.get(key, [])
	if v is Array:
		# Copied into an UNTYPED Array on purpose: build_report appends + sorts these, and it must never mutate the
		# caller's data nor inherit an Array[String] element type that a later append_array would have to satisfy.
		out.append_array(v as Array)
	return out


static func _dict(d: Dictionary, key: String) -> Dictionary:
	var v: Variant = d.get(key, {})
	if v is Dictionary:
		return v as Dictionary
	return {}
