@tool
extends RefCounted

## WIRING AUDITS (Domain C of the project audit): three cross-file dangling-reference passes that the per-file
## scanners in scan_disk.gd can't see, because a wiring bug is only visible once the WHOLE project is in view --
## a story flag a dialogue READS that nothing ever WRITES (a dead gate), a quest-id a trigger advances that no
## .tres declares (a typo), a faction-id a merchant prices against that has no resource. Each pass GATHERS literals
## across every res:// .tscn/.tres/.gd into sets, then RESOLVES references against those sets. Returns
## Array[{severity, source, message, domain}] (errors first), the same finding shape scan_disk emits. Every row is
## domain "content" (a wiring slip is fixed in a .tres / .tscn field, never in code), so the Audit tab always lists
## it under the designer's default view. The dict may only GAIN keys: validate_all.gd, cyber_cmds.gd and
## tests/test_devtools_audit_wiring.gd read these rows and predate the key.
##
## PASS 4 (the bottom of this file) is the one WITHIN-RESOURCE wiring pass: a conversation's choices name their
## destination by a DialogueLine.id (target_id / target_on_fail_id), and a dangling id, a duplicate id, or a line
## named after a sentinel word is exactly the same kind of typo as a dead flag -- just scoped to one
## DialogueResource. It is not chained from run(): scan_disk.gd calls it per file, from the loaded .tres it already
## has AND from the text of every .tscn that embeds a conversation (inline conversations on a Talkable were never
## audited before ids; now they are).
##
## PASS 1 also checks the story-flag CATALOG (resources/story/FlagCatalog.tres, read through StoryFlags): a flag the
## content reads or writes that the catalog does not list is a WARN, so a typo'd or undocumented flag shows up even
## when its misspelling happens to be both read and written.
##
## SPLIT: every predicate below is a PURE static func (no EditorInterface / no scene tree / no autoload) so the GUT
## suite tests the classifier + resolver logic on small fixture strings/dicts; run() and the .tres LOADS are the
## thin editor glue on top. Designer-first: the rows surface in the existing Audit tab automatically.

# --- field vocabularies (the REAL export names, read off the live scripts) ------------------------------------
## Story-flag fields that WRITE a flag (they call GameState.set_flag): TriggerVolume/DialogueChoice/Switch.set_flag,
## Lock.unlock_flag, TutorialPrompt.seen_flag, Readable.set_flag_on_read, CutsceneAction.flag_name,
## QuestStage.set_flag_on_enter. unlock_flag is ALSO read by Door, so it's a writer AND a reader. (set_flag does NOT
## false-match set_flag_on_read / set_flag_on_enter: _field_string_values anchors `^\s*<field>\s*=`, and set_flag is
## followed by "_on_...", not "="; each field is matched independently.)
const FLAG_WRITE_FIELDS: Array[String] = ["set_flag", "unlock_flag", "seen_flag", "set_flag_on_read", "flag_name", "set_flag_on_enter"]
## Story-flag fields that READ a flag (a gate / expiry): DialogueChoice.required_flag, Quest.expire_on_flag,
## Door.unlock_flag, and a FLAG QuestObjective's target_id (advanced when its flag is set).
const FLAG_READ_FIELDS: Array[String] = ["required_flag", "expire_on_flag", "unlock_flag"]
## Quest-id reference fields (TriggerVolume + DialogueChoice + Quest.prereq_quest_id): each must name a real Quest.id.
const QUEST_ID_FIELDS: Array[String] = ["complete_quest_id", "advance_quest_id", "required_quest_id", "prereq_quest_id"]
## Faction-id reference fields (AlarmPanel/Merchant/NpcData/npc.gd/BuildGate/DialogueChoice): each must resolve.
const FACTION_ID_FIELDS: Array[String] = [
	"alarm_faction_id", "faction_id", "required_faction_id", "reward_reputation_faction_id",
]
## The QuestObjective.Type.FLAG enum ordinal (KILL,TALK,PICKUP,ENTER_AREA,USE_ITEM,FLAG) -- a FLAG objective's
## target_id IS a flag name. Mirrors quest_objective.gd's enum order.
const OBJ_TYPE_FLAG := 5

# `tests` is skipped: GUT fixtures write/read throwaway story flags (e.g. "hostage_dead"/"reached_exit") that no
# production content keys off — gathering them only produces permanent dead-gate/typo baseline noise that masks a
# real production wiring bug. Production flag/quest/faction wiring must be self-contained, so excluding tests is safe.
const SKIP_DIRS: Array[String] = [".godot", "addons", ".git", "tests"]
const FACTION_DIR := "res://resources/factions/"
## The Audit tab's row-filter domain for every wiring row (see the header).
const DOMAIN := "content"

## Shared one-read-per-file cache (see scan_cache.gd) — this pass walks res:// reading the SAME files scan_disk just
## read. Inert outside audit_panel's begin()/end() window, so a standalone run behaves exactly as before.
const ScanCache := preload("res://addons/cybersunday_tools/panel_audit/scan_cache.gd")
## The story-flag catalog registry (no class_name, no autoload; the catalog .tres is loaded lazily by path).
const StoryFlags := preload("res://scripts/quests/story_flags.gd")

## scan_disk.gd is resolved with a LAZY load(), NOT a `const` preload: scan_disk already preloads THIS file (its
## run() appends our rows), so a const preload back would be a parse-time cyclic reference. load() at call time is
## served from the resource cache, so the cost is a dictionary lookup.
const SCAN_DISK_PATH := "res://addons/cybersunday_tools/panel_audit/scan_disk.gd"


## Blank out `#` line-comments (length-preserving) via scan_disk's masker — the SAME primitive scan_disk, scan_text
## and scan_menu_sound all mask with. Needed because this project documents call idioms in prose: an unmasked
## `## ... GameState.set_flag("vault_open")` in a docstring would register a phantom WRITER for that flag, which
## either marks a real dead gate as covered (dropping a true finding) or invents a "written but never read" row.
## Degrades to the raw text if scan_disk can't be loaded — a scan is never worth a hard failure.
static func _mask_comments(text: String) -> String:
	var sd: Variant = load(SCAN_DISK_PATH)
	if sd == null:
		return text
	return String(sd.mask_comments(text))


# ============================================================================================================
# EDITOR GLUE -- run() walks the project ONCE into the gathered sets, loads the quest/faction .tres the passes
# need, then hands the PURE predicates above their data. No EditorInterface / scene tree (DirAccess + load only),
# so it runs from the audit button; the test suite exercises the predicates, not this walk.
# ============================================================================================================

## The three wiring passes, merged + errors-first. scan_disk.run() appends this. Walks res:// once, collecting
## flag/quest/faction literals + loading the quest & faction resources, then evaluates the pure predicates.
static func run() -> Array:
	var ctx := {
		"writers": {}, "readers": {}, "flag_src": {},
		"quest_ids": {}, "objectives_by_quest": {},
		"faction_ids": {}, "quest_refs": [], "advance_pairs": [], "faction_refs": [],
		"stages_by_quest": {}, "stage_jumps": [], "quest_stage_findings": [],
	}
	_collect_factions(ctx)   # build the known-faction set (filenames + load to verify internal id) FIRST
	_collect_quests(ctx)     # build the known-quest + per-quest objective sets
	_walk("res://", ctx)     # gather every flag/quest/faction literal across .tscn/.tres/.gd
	var out: Array = []
	# Errors-first: id-resolution failures (ERROR) before the flag dead-gate/typo WARNs.
	for ref in ctx["quest_refs"]:
		var msg := resolve_quest_id(ref["value"], ctx["quest_ids"])
		if msg != "":
			out.append(_f("ERROR", ref["source"], "%s %s" % [ref["field"], msg]))
	for pair in ctx["advance_pairs"]:
		var msg := resolve_objective_id(pair["quest"], pair["objective"], ctx["objectives_by_quest"])
		if msg != "":
			out.append(_f("ERROR", pair["source"], msg))
	for jump in ctx["stage_jumps"]:
		var msg := resolve_stage_jump(jump["quest"], jump["stage"], ctx["quest_ids"], ctx["stages_by_quest"])
		if msg != "":
			out.append(_f("ERROR", jump["source"], msg))
	out.append_array(ctx["quest_stage_findings"])
	for ref in ctx["faction_refs"]:
		var msg := resolve_faction_id(ref["value"], ctx["faction_ids"])
		if msg != "":
			out.append(_f("ERROR", ref["source"], "%s %s" % [ref["field"], msg]))
	out.append_array(ctx["faction_dict_findings"] if ctx.has("faction_dict_findings") else [])
	out.append_array(ctx["faction_mismatch_findings"] if ctx.has("faction_mismatch_findings") else [])
	out.append_array(flag_findings(ctx["writers"], ctx["readers"], ctx["flag_src"]))
	out.append_array(uncatalogued_flag_findings(ctx["writers"], ctx["readers"], StoryFlags.name_set(), ctx["flag_src"]))
	return out


## Recursive res:// walk: for every .gd/.tscn/.tres, collect flag refs (tagged by source) + quest/faction refs.
static func _walk(path: String, ctx: Dictionary) -> void:
	var d := DirAccess.open(path)
	if d == null:
		return
	d.list_dir_begin()
	var entry := d.get_next()
	while entry != "":
		if entry.begins_with("."):
			entry = d.get_next()
			continue
		var full := path.path_join(entry)
		if d.current_is_dir():
			if not SKIP_DIRS.has(entry):
				_walk(full, ctx)
		else:
			_gather_file(full, ctx)
		entry = d.get_next()
	d.list_dir_end()


static func _gather_file(path: String, ctx: Dictionary) -> void:
	var ext := path.get_extension()
	if ext != "gd" and ext != "tscn" and ext != "tres":
		return
	var text := ScanCache.text_of(path)
	if text.is_empty():
		return
	# Flags: merge this file's writers/readers into the project sets, remembering the FIRST source of each name.
	var refs := collect_flag_refs(text)
	for name in refs["write"]:
		ctx["writers"][name] = true
		if not ctx["flag_src"].has(name):
			ctx["flag_src"][name] = path
	for name in refs["read"]:
		ctx["readers"][name] = true
		if not ctx["flag_src"].has(name):
			ctx["flag_src"][name] = path
	# Quest-id refs (skip the quest .tres themselves so a quest declaring its own id isn't counted as a ref).
	for r in collect_quest_id_refs(text):
		ctx["quest_refs"].append({"field": r["field"], "value": r["value"], "source": path})
	for p in collect_advance_pairs(text):
		ctx["advance_pairs"].append({"quest": p["quest"], "objective": p["objective"], "source": path})
	for j in collect_stage_jumps(text):
		ctx["stage_jumps"].append({"quest": j["quest"], "stage": j["stage"], "source": path})
	for r in collect_faction_id_refs(text):
		ctx["faction_refs"].append({"field": r["field"], "value": r["value"], "source": path})


## Build the known-faction set (filename ids) + verify each .tres's internal id matches its filename + scan its
## relations dict keys. The relations / reward_reputation dict-key checks need the LOADED resource.
static func _collect_factions(ctx: Dictionary) -> void:
	var mismatch: Array = []
	var dict_findings: Array = []
	var loaded: Array = []  # [{path, res, filename_id}] -- relations checked AFTER the full id set is built
	var d := DirAccess.open(FACTION_DIR)
	if d != null:
		for fn in d.get_files():
			var fid := ""
			if fn.ends_with(".tres"):
				fid = fn.trim_suffix(".tres")
			elif fn.ends_with(".res"):
				fid = fn.trim_suffix(".res")
			else:
				continue
			ctx["faction_ids"][fid] = true
			var res: Variant = load(FACTION_DIR + fn)
			if res is Faction:
				loaded.append({"path": FACTION_DIR + fn, "res": res, "filename_id": fid})
				var mm := faction_id_filename_mismatch(str((res as Faction).id), fid)
				if mm != "":
					mismatch.append(_f("ERROR", FACTION_DIR + fn, mm))
	# relations dict keys (now the whole id set is known) -- a relation toward an unknown faction.
	for e in loaded:
		var rel: Dictionary = (e["res"] as Faction).relations
		for bad in unknown_dict_keys(rel, ctx["faction_ids"]):
			dict_findings.append(_f("WARN", e["path"], "Faction.relations has a key \"%s\" that names no faction under resources/factions/." % bad))
	ctx["faction_mismatch_findings"] = mismatch
	ctx["faction_dict_findings"] = dict_findings


## Build the known-quest id set + per-quest objective-id set by loading every Quest .tres (header type match),
## and scan each Quest.reward_reputation dict for keys that name no faction. Recursive (quests can nest anywhere).
static func _collect_quests(ctx: Dictionary) -> void:
	_collect_quests_dir("res://resources/", ctx)


static func _collect_quests_dir(path: String, ctx: Dictionary) -> void:
	var d := DirAccess.open(path)
	if d == null:
		return
	d.list_dir_begin()
	var entry := d.get_next()
	while entry != "":
		if entry.begins_with("."):
			entry = d.get_next()
			continue
		var full := path.path_join(entry)
		if d.current_is_dir():
			_collect_quests_dir(full, ctx)
		elif full.get_extension() == "tres":
			_maybe_collect_quest(full, ctx)
		entry = d.get_next()
	d.list_dir_end()


static func _maybe_collect_quest(path: String, ctx: Dictionary) -> void:
	if not ("script_class=\"Quest\"" in ScanCache.text_of(path)):
		return  # only LOAD a .tres whose header declares Quest -- avoids loading every resource
	var q: Variant = load(path)
	if not (q is Quest):
		return
	var quest := q as Quest
	var qid := str(quest.id)
	if qid != "":
		ctx["quest_ids"][qid] = true
		# EVERY objective the quest can ever ask for (all_objectives: every stage's, for a staged quest) -- a trigger
		# or conversation may legitimately advance an objective of a later stage.
		var objs := {}
		for obj in quest.all_objectives():
			if obj != null and str(obj.id) != "":
				objs[str(obj.id)] = true
		ctx["objectives_by_quest"][qid] = objs
		if quest.has_stages():
			var sids := {}
			for sid in quest.stage_ids():
				sids[String(sid)] = true
			ctx["stages_by_quest"][qid] = sids
	for problem in quest_stage_problems(quest):
		ctx["quest_stage_findings"].append(_f(String(problem["severity"]), path, String(problem["message"])))
	# reward_reputation dict keys must name real factions (faction set was built first).
	if not ctx.has("faction_dict_findings"):
		ctx["faction_dict_findings"] = []
	for bad in unknown_dict_keys(quest.reward_reputation, ctx["faction_ids"]):
		ctx["faction_dict_findings"].append(_f("WARN", path, "Quest.reward_reputation has a key \"%s\" that names no faction under resources/factions/." % bad))


# ============================================================================================================
# PASS 1 -- STORY-FLAG WIRING
# ============================================================================================================

## Pull every flag literal out of one file's text, tagged write/read by which field carried it. Returns
## { "write": [names...], "read": [names...] } (a name can appear in both lists across files). Also catches a
## bare GameState.set_flag("x") / .get_flag("x") call in .gd source. PURE -- the run() aggregator merges these.
static func collect_flag_refs(text: String) -> Dictionary:
	var out := {"write": [], "read": []}
	for field in FLAG_WRITE_FIELDS:
		for v in _field_string_values(text, field):
			out["write"].append(v)
	for field in FLAG_READ_FIELDS:
		for v in _field_string_values(text, field):
			out["read"].append(v)
	# FLAG QuestObjective target_id is a flag READ (a quest waits on the flag being set elsewhere). target_id is
	# overloaded (KILL/TALK/etc. use it too), so only count a block's target_id when THAT block itself is a FLAG
	# type (a Quest .tres holds many mixed-type sub_resources -- a whole-file scan over-counts every target_id).
	for block in _resource_blocks(text):
		if _has_flag_objective(block):
			for v in _field_string_values(block, "target_id"):
				out["read"].append(v)
	# Bare autoload calls in .gd source (a hand-coded gate) -- set_flag(...) writes, get_flag/has_flag(...) read.
	# Masked FIRST: unlike the `field = "x"` regexes above (anchored at ^\s*, so a `#` comment line can never match),
	# a bare CALL matches anywhere on the line, so a flag call quoted in a docstring would count as a real usage.
	var masked := _mask_comments(text)
	for v in _call_string_args(masked, "set_flag"):
		out["write"].append(v)
	for v in _call_string_args(masked, "get_flag"):
		out["read"].append(v)
	for v in _call_string_args(masked, "has_flag"):
		out["read"].append(v)
	return out

## Given the merged write-set + read-set names (Dictionaries used as sets: { name: true }), produce the findings:
## a flag READ with no WRITER is a DEAD GATE (it can never open); a flag WRITTEN with no READER is a likely TYPO
## (nothing keys off it). Both WARN. PURE + the heart of pass 1 -- tested directly on fixture sets.
static func flag_findings(writers: Dictionary, readers: Dictionary, src_of: Dictionary = {}) -> Array:
	var out: Array = []
	for name in readers:
		if not writers.has(name):
			out.append(_f("WARN", _src(src_of, name), "Story flag \"%s\" is READ (a gate/objective) but nothing WRITES it — a dead gate that can never open. Add a set_flag, or fix the name." % name))
	for name in writers:
		if not readers.has(name):
			out.append(_f("WARN", _src(src_of, name), "Story flag \"%s\" is WRITTEN but nothing READS it — a likely typo, or a gate you forgot to wire." % name))
	return out


## A flag the content reads OR writes that the story-flag catalog does not list: one WARN per name (sorted, so the Audit
## rows are stable). `catalogued` is a set { name: true } (StoryFlags.name_set()). WARN, not ERROR — the flag still works
## at runtime; the catalog is the designer's shared vocabulary, and an entry is one Inspector row to add. PURE.
static func uncatalogued_flag_findings(writers: Dictionary, readers: Dictionary, catalogued: Dictionary, src_of: Dictionary = {}) -> Array:
	var used := {}
	for name in writers:
		used[str(name)] = true
	for name in readers:
		used[str(name)] = true
	var names := used.keys()
	names.sort()
	var out: Array = []
	for name in names:
		if not catalogued.has(name):
			out.append(_f("WARN", _src(src_of, name), "Story flag \"%s\" is not in the flag catalog (%s) — add it there with a one-line description so every flag field suggests it, or fix the name if it is a typo." % [name, StoryFlags.CATALOG_PATH]))
	return out


# ============================================================================================================
# PASS 2 -- QUEST-ID + OBJECTIVE-ID WIRING
# ============================================================================================================

## Resolve one quest-id reference against the known-quest set ({ id: true }). Returns "" when it resolves (or the
## id is blank = an unset field, which is fine), else an error MESSAGE. PURE -- the core pass-2 predicate.
static func resolve_quest_id(quest_id: String, known: Dictionary) -> String:
	if quest_id == "":
		return ""
	if known.has(quest_id):
		return ""
	return "references quest id \"%s\", which no Quest .tres declares (a typo, or the quest was renamed/removed)." % quest_id

## Resolve an advance pair (quest_id, objective_id) against the per-quest objective map ({ quest_id: { obj_id:
## true } }). Returns "" when the quest exists AND owns that objective (or either is blank), else an error MESSAGE.
## PURE -- pass-2's objective-existence predicate.
static func resolve_objective_id(quest_id: String, objective_id: String, objectives_by_quest: Dictionary) -> String:
	if quest_id == "" or objective_id == "":
		return ""
	if not objectives_by_quest.has(quest_id):
		return "advances objective \"%s\" of quest \"%s\", but no Quest .tres declares that quest." % [objective_id, quest_id]
	var objs: Dictionary = objectives_by_quest[quest_id]
	if not objs.has(objective_id):
		return "advances objective \"%s\", which quest \"%s\" doesn't declare — fix the objective id." % [objective_id, quest_id]
	return ""

## All quest-id references in one file's text, as [{field, value}] (blank values dropped). PURE. The advance pair
## is handled separately by collect_advance_pairs so both halves stay together.
static func collect_quest_id_refs(text: String) -> Array:
	var out: Array = []
	for field in QUEST_ID_FIELDS:
		for v in _field_string_values(text, field):
			if v != "":
				out.append({"field": field, "value": v})
	return out

## The (advance_quest_id, advance_objective_id) pairs in one file's text -- both fields sit on the same node, so we
## pair them WITHIN each [node ...]/[sub_resource ...] block (TriggerVolume / DialogueChoice each carry exactly one
## such pair per block). PURE. Pairing per-block (not by flat per-file index) keeps a half-configured node --
## advance_quest_id with NO advance_objective_id, which is allowed to ship -- from shifting the pairing onto other
## blocks. Only emits a pair when BOTH are present in that block (one-without-the-other is a separate concern).
static func collect_advance_pairs(text: String) -> Array:
	var out: Array = []
	for block in _resource_blocks(text):
		var quests := _field_string_values(block, "advance_quest_id")
		var objs := _field_string_values(block, "advance_objective_id")
		var n: int = mini(quests.size(), objs.size())
		for i in n:
			if quests[i] != "" and objs[i] != "":
				out.append({"quest": quests[i], "objective": objs[i]})
	return out


# ------------------------------------------------------------------------------------------------------------
# PASS 2b -- QUEST STAGES (QuestStage ids, next_stage_id, DialogueChoice.set_quest_stage_id)
# ------------------------------------------------------------------------------------------------------------
# A staged quest's stage ids are primary keys (the save stores the current one) AND the targets of two references:
# a stage's next_stage_id inside the quest, and a conversation choice's set_quest_stage_id (whose quest is the same
# block's advance_quest_id). Every way one of those can name nothing is an ERROR -- at runtime each is a silent
# refusal (the quest just never moves), exactly the dead-end class this pass exists for.

## The findings about ONE loaded quest's own stages, as [{severity, message}] (the caller stamps the source). PURE --
## duck-typed over the resource, so a test hands it Quest.new()s. Rules:
##   ERROR  a stage with a blank id (the save cannot remember it; nothing can jump to it)
##   ERROR  two stages with the same id (the resolver takes the first; the second is unreachable)
##   ERROR  a next_stage_id that names no stage of this quest (the quest stalls there instead of moving on)
##   WARN   a null row in `stages` (a deleted sub-resource: ignored at runtime)
##   WARN   a staged quest that ALSO carries objectives on the Quest itself (they are ignored once stages exist)
static func quest_stage_problems(quest: Variant) -> Array:
	var out: Array = []
	if typeof(quest) != TYPE_OBJECT or not is_instance_valid(quest):
		return out
	var stages_v: Variant = quest.get("stages")
	if not (stages_v is Array) or (stages_v as Array).is_empty():
		return out
	var stages: Array = stages_v
	var seen := {}
	for i in stages.size():
		var st: Variant = stages[i]
		if st == null:
			out.append({"severity": "WARN", "message": "Quest stage %d is empty (a missing stage) -- it is skipped; remove the row." % (i + 1)})
			continue
		var sid := String(st.get("id"))
		if sid == "":
			out.append({"severity": "ERROR", "message": "Quest stage %d has no id -- a save cannot remember it and nothing can move the quest to it." % (i + 1)})
		elif seen.has(sid):
			out.append({"severity": "ERROR", "message": "Quest stage %d reuses the id \"%s\" (stage %d already has it) -- stage ids must be unique within a quest." % [i + 1, sid, int(seen[sid]) + 1]})
		else:
			seen[sid] = i
	for i in stages.size():
		var st: Variant = stages[i]
		if st == null:
			continue
		var nxt := String(st.get("next_stage_id"))
		if nxt != "" and not seen.has(nxt):
			out.append({"severity": "ERROR", "message": "Quest stage \"%s\" moves on to stage \"%s\", which this quest doesn't have -- the quest would stall there. Pick a real stage or leave Next stage blank to end the quest." % [String(st.get("id")), nxt]})
	var own_v: Variant = quest.get("objectives")
	if own_v is Array and not (own_v as Array).is_empty():
		out.append({"severity": "WARN", "message": "This quest has stages AND its own objectives -- once a quest has stages only the stages' objectives count, so its own %d are ignored. Move them into a stage." % (own_v as Array).size()})
	return out


## Resolve one set_quest_stage_id jump (the quest named by the SAME block's advance_quest_id). "" when it resolves or the
## stage id is blank; an unknown quest id is left to pass 2's quest-id resolver (it already reports advance_quest_id),
## so it is NOT double-reported here. PURE.
static func resolve_stage_jump(quest_id: String, stage_id: String, known_quests: Dictionary, stages_by_quest: Dictionary) -> String:
	if stage_id == "":
		return ""
	if quest_id == "":
		return "set_quest_stage_id \"%s\" names no quest -- fill Advance quest id with the quest to move." % stage_id
	if not known_quests.has(quest_id):
		return ""
	if not stages_by_quest.has(quest_id):
		return "set_quest_stage_id \"%s\" jumps quest \"%s\", which has no stages -- add stages to the quest, or remove the jump." % [stage_id, quest_id]
	if not (stages_by_quest[quest_id] as Dictionary).has(stage_id):
		return "set_quest_stage_id \"%s\" names a stage quest \"%s\" doesn't have -- the jump would be refused." % [stage_id, quest_id]
	return ""


## The (advance_quest_id, set_quest_stage_id) jumps in one file's text, paired WITHIN each [node]/[sub_resource]
## block like collect_advance_pairs (a DialogueChoice carries both on one block). Emitted whenever the block names a
## stage -- a blank quest half is itself the finding. PURE.
static func collect_stage_jumps(text: String) -> Array:
	var out: Array = []
	for block in _resource_blocks(text):
		var stages := _field_string_values(block, "set_quest_stage_id")
		if stages.is_empty() or String(stages[0]) == "":
			continue
		var quests := _field_string_values(block, "advance_quest_id")
		out.append({"quest": String(quests[0]) if not quests.is_empty() else "", "stage": String(stages[0])})
	return out


# ============================================================================================================
# PASS 3 -- FACTION-ID + DICT-KEY WIRING
# ============================================================================================================

## Resolve one faction-id literal against the known-faction set ({ id: true }). "" when it resolves / is blank,
## else an error MESSAGE. PURE -- pass-3's core resolver (shared by the field refs AND the dict-key checks).
static func resolve_faction_id(faction_id: String, known: Dictionary) -> String:
	if faction_id == "":
		return ""
	if known.has(faction_id):
		return ""
	return "references faction id \"%s\", which has no resource under resources/factions/ (the NPC/merchant falls back to UNALIGNED)." % faction_id

## All faction-id field references in one file's text, as [{field, value}] (blank dropped). PURE.
static func collect_faction_id_refs(text: String) -> Array:
	var out: Array = []
	for field in FACTION_ID_FIELDS:
		for v in _field_string_values(text, field):
			if v != "":
				out.append({"field": field, "value": v})
	return out

## Check every KEY of a faction-keyed Dictionary (Faction.relations / Quest.reward_reputation) against the known
## set. Returns the list of UNKNOWN keys (a relation/reward pointed at a non-existent faction). PURE -- the
## dict-key predicate. Keys arrive as StringName or String; both normalise to String for the lookup.
static func unknown_dict_keys(d: Dictionary, known: Dictionary) -> Array:
	var out: Array = []
	for k in d:
		var key := str(k)
		if key != "" and not known.has(key):
			out.append(key)
	return out

## Does a faction resource's INTERNAL id match its filename (the convention Reputation keys on)? Returns "" on a
## match, else an error MESSAGE. PURE -- mirrors Factions.by_id's warning, but as an audit finding.
static func faction_id_filename_mismatch(internal_id: String, filename_id: String) -> String:
	if internal_id == filename_id:
		return ""
	return "faction .tres internal id \"%s\" != its filename \"%s\" — Reputation keys on the INTERNAL id, so refs to \"%s\" silently miss." % [internal_id, filename_id, filename_id]


# --- shared pure regex helpers --------------------------------------------------------------------------------

## Split a .tscn/.tres text into its `[node ...]` / `[sub_resource ...]` / `[resource]` blocks so per-block fields
## (a FLAG objective's target_id, a node's advance pair) stay together instead of being scanned project-/file-wide.
## Each returned substring is one header line + everything up to (not including) the next `[` section header. The
## leading preamble (before the first header, e.g. the `[gd_resource ...]` line) is also returned so a non-block
## fixture string still yields its content. PURE. The existing field/value regexes work per-substring.
static func _resource_blocks(text: String) -> Array:
	var out: Array = []
	var re := RegEx.new()
	re.compile("(?m)^\\[")  # the start of every section header line ([node, [sub_resource, [resource, ...)
	var starts: Array = []
	for m in re.search_all(text):
		starts.append(m.get_start())
	if starts.is_empty():
		out.append(text)  # no headers (a bare fixture) -- treat the whole text as one block
		return out
	var first_start: int = starts[0]
	if first_start > 0:
		out.append(text.substr(0, first_start))  # preamble before the first header
	for i in starts.size():
		var s: int = starts[i]
		var e: int = (starts[i + 1] if i + 1 < starts.size() else text.length())
		out.append(text.substr(s, e - s))
	return out


## Every string value assigned to `field` in the text: matches both the .tscn/.tres `field = &"v"` / `field = "v"`
## serialized form AND a GDScript `field = &"v"` assignment. Returns the raw values (possibly empty strings).
static func _field_string_values(text: String, field: String) -> Array:
	var out: Array = []
	var re := RegEx.new()
	re.compile("(?m)^\\s*" + field + "\\s*=\\s*&?\"([^\"]*)\"")
	for m in re.search_all(text):
		out.append(m.get_string(1))
	return out

## Every string-literal argument passed to a `name(...)` call in .gd source (e.g. set_flag(&"x") / get_flag("x")).
## Skips a call whose first arg isn't a plain string literal (a variable / expression — can't resolve statically).
static func _call_string_args(text: String, fn: String) -> Array:
	var out: Array = []
	var re := RegEx.new()
	re.compile("\\b" + fn + "\\(\\s*&?\"([^\"]+)\"")
	for m in re.search_all(text):
		out.append(m.get_string(1))
	return out

## True if the text contains a QuestObjective whose `type` is FLAG (so a target_id in it is a flag name). The
## serialized form is `type = 5`; matches that ordinal anywhere in the resource (objectives are sub-resources).
static func _has_flag_objective(text: String) -> bool:
	var re := RegEx.new()
	re.compile("(?m)^\\s*type\\s*=\\s*" + str(OBJ_TYPE_FLAG) + "\\s*$")
	return re.search(text) != null

# ============================================================================================================
# PASS 4 -- DIALOGUE TARGET-ID WIRING (within one conversation)
# ============================================================================================================
#
# Both entry points build the SAME plain model, then one predicate judges it:
#   model = { "lines": [ { "id": String, "choices": [ { "target_id": String, "target_on_fail_id": String,
#                                                        "target": int, "target_on_fail": int, "gated": bool } ] } ] }
# `dialogue_model_from_resource` reads a LOADED DialogueResource duck-typed (scan_disk already loads every
# DialogueResource .tres; GUT feeds .new() resources); `dialogue_models_from_text` PARSES the serialized form, which
# is how a conversation embedded in a .tscn (a Talkable's inline `dialogue`) gets audited without instantiating the
# scene. The rules mirror the runtime resolver (DialogueResource.resolve_target: id if non-blank, else the int):
#   ERROR  a target_id / target_on_fail_id that is non-blank, not END / CONTINUE, and names no line (the conversation
#          would END there with a warning -- a typo).
#   ERROR  two lines with the same id (the resolver silently takes the FIRST).
#   ERROR  a line whose id is END / CONTINUE (the sentinel wins, so the line is unreachable by id).
#   ERROR  a legacy int (consulted only while the id is blank) outside 0..n-1 and not a sentinel -- the check that
#          used to live in scan_disk, kept with the same wording.
#   WARN   a conversation that has STARTED using ids (any line id, any choice id) but still has a choice pointing
#          by number at a REAL line -- the mixed state where Up / Down / Remove shift that choice but not its
#          id-addressed neighbours. A sentinel int is not positional and stays silent; an out-of-range int is the
#          ERROR above, not a migrate nudge; the fail branch only counts when the choice is gated (it is inert
#          otherwise); a wholly by-number conversation (no id anywhere) produces NO warning at all.

## The int sentinels, mirrored as literals like graph_data.gd does (no class_name dependency at parse time).
const DLG_END := -1
const DLG_CONTINUE := -2
const DLG_ID_END := "END"
const DLG_ID_CONTINUE := "CONTINUE"
## The choice fields that make a choice GATED (its fail branch is live). Mirrors dialogue_view.gd's gate set.
const DLG_GATE_FIELDS: Array[String] = [
	"required_stat", "required_flag", "required_faction_id", "required_perk_id", "required_item_id", "required_quest_id",
]
## The three dialogue scripts, by the path tail a .tres / .tscn ext_resource line carries.
const DLG_SCRIPT_LINE := "scripts/dialogue/dialogue_line.gd"
const DLG_SCRIPT_CHOICE := "scripts/dialogue/dialogue_choice.gd"
const DLG_SCRIPT_RESOURCE := "scripts/dialogue/dialogue_resource.gd"


## The plain model of a LOADED DialogueResource (duck-typed: `res.get("lines")`, `line.get("id")` ...), so this pass
## has no compile-time dependency on the dialogue class_names and a GUT test can hand it .new() resources. Null rows
## (a deleted sub-resource in a hand-edited file) become an id-less line with no choices / are skipped as choices.
static func dialogue_model_from_resource(res: Variant) -> Dictionary:
	var lines_out: Array = []
	if typeof(res) != TYPE_OBJECT or not is_instance_valid(res):
		return {"lines": lines_out}
	var raw_lines: Variant = res.get("lines")
	if not (raw_lines is Array):
		return {"lines": lines_out}
	for line in raw_lines:
		var entry := {"id": "", "choices": []}
		if line != null:
			entry["id"] = _dlg_text(line.get("id"))
			var raw_choices: Variant = line.get("choices")
			if raw_choices is Array:
				for ch in raw_choices:
					if ch == null:
						continue
					var gated := false
					for f in DLG_GATE_FIELDS:
						if _dlg_text(ch.get(f)) != "":
							gated = true
							break
					entry["choices"].append({
						"target_id": _dlg_text(ch.get("target_id")),
						"target_on_fail_id": _dlg_text(ch.get("target_on_fail_id")),
						"target": _dlg_int(ch.get("target"), DLG_CONTINUE),
						"target_on_fail": _dlg_int(ch.get("target_on_fail"), DLG_END),
						"gated": gated,
					})
		lines_out.append(entry)
	return {"lines": lines_out}


## Every conversation serialized in one .tres / .tscn text, as [{model, where}]. `where` is "" for the main
## [resource] of a .tres and, for a .tscn, the node that carries the inline conversation ("Talkable under
## Characters/OldMan") so the finding says WHICH talker to open. Parsing, not loading: the three dialogue scripts
## are found by their ext_resource path, every [sub_resource] / [resource] block is classified by its `script =`,
## a resource block's `lines = Array[...]([SubResource("a"), ...])` names its line blocks, and a line block's
## `choices = ...` names its choice blocks. A conversation whose lines are ExtResources (a line shared from another
## file -- nothing in this project does that) is skipped rather than guessed at. PURE.
static func dialogue_models_from_text(text: String) -> Array:
	var out: Array = []
	var kinds := _dlg_ext_kinds(text)
	if kinds.is_empty():
		return out
	var lines_by_id := {}      # sub_resource id -> {"id": String, "choice_refs": [sub ids]}
	var choices_by_id := {}    # sub_resource id -> the choice model row
	var resources := []        # [{"key": sub id or "", "line_refs": [sub ids]}]
	var node_owner := {}       # resource sub id -> "NodeName under parent/path"
	var re_sub := RegEx.new()
	re_sub.compile("^\\[sub_resource [^\\]]*\\bid=\"([^\"]+)\"")
	var re_node := RegEx.new()
	re_node.compile("^\\[node [^\\]]*\\bname=\"([^\"]+)\"(?:[^\\]]*\\bparent=\"([^\"]*)\")?")
	var re_script := RegEx.new()
	re_script.compile("(?m)^\\s*script\\s*=\\s*ExtResource\\(\"([^\"]+)\"\\)")
	var re_subref := RegEx.new()
	re_subref.compile("SubResource\\(\"([^\"]+)\"\\)")
	for block in _resource_blocks(text):
		var header := String(block.split("\n", true, 1)[0])
		var sub_m := re_sub.search(header)
		var is_main := header.begins_with("[resource]")
		if sub_m == null and not is_main:
			var node_m := re_node.search(header)
			if node_m != null:
				# A node block: remember which inline conversation(s) it carries, for the finding's wording.
				var label := node_m.get_string(1)
				if node_m.get_group_count() >= 2 and node_m.get_string(2) != "":
					label += " under " + node_m.get_string(2)
				for rm in re_subref.search_all(block):
					if not node_owner.has(rm.get_string(1)):
						node_owner[rm.get_string(1)] = label
			continue
		var key := "" if is_main else sub_m.get_string(1)
		var script_m := re_script.search(block)
		if script_m == null:
			continue
		var kind := String(kinds.get(script_m.get_string(1), ""))
		if kind == DLG_SCRIPT_LINE:
			lines_by_id[key] = {"id": _dlg_first(_field_string_values(block, "id")), "choice_refs": _dlg_refs_on_field(block, "choices", re_subref)}
		elif kind == DLG_SCRIPT_CHOICE:
			var gated := false
			for f in DLG_GATE_FIELDS:
				if _dlg_first(_field_string_values(block, f)) != "":
					gated = true
					break
			choices_by_id[key] = {
				"target_id": _dlg_first(_field_string_values(block, "target_id")),
				"target_on_fail_id": _dlg_first(_field_string_values(block, "target_on_fail_id")),
				"target": _dlg_int_field(block, "target", DLG_CONTINUE),
				"target_on_fail": _dlg_int_field(block, "target_on_fail", DLG_END),
				"gated": gated,
			}
		elif kind == DLG_SCRIPT_RESOURCE:
			resources.append({"key": key, "line_refs": _dlg_refs_on_field(block, "lines", re_subref)})
	for r in resources:
		var model_lines: Array = []
		for lref in r["line_refs"]:
			var line_row: Dictionary = lines_by_id.get(lref, {"id": "", "choice_refs": []})
			var choices: Array = []
			for cref in line_row["choice_refs"]:
				if choices_by_id.has(cref):
					choices.append(choices_by_id[cref])
			model_lines.append({"id": line_row["id"], "choices": choices})
		out.append({"model": {"lines": model_lines}, "where": String(node_owner.get(r["key"], ""))})
	return out


## The findings for one conversation model (see the PASS 4 header for the rules). `where` prefixes every message
## (an inline conversation names its node); "" for a .tres, whose `source` already names the file.
static func dialogue_findings(model: Dictionary, source: String, where: String = "") -> Array:
	var out: Array = []
	var lines: Array = model.get("lines", [])
	var n := lines.size()
	var prefix := (where + ": ") if where != "" else ""
	# The id table + the two id-shape errors, first: a duplicate or a sentinel-named line is what makes every
	# resolution below unreliable, so it is reported ahead of the references that depend on it.
	var index_of_id := {}
	var uses_ids := false
	for i in n:
		var lid := String(lines[i].get("id", ""))
		if lid == "":
			continue
		uses_ids = true
		if lid == DLG_ID_END or lid == DLG_ID_CONTINUE:
			out.append(_f("ERROR", source, "%sLine %d's id is \"%s\", a reserved word (it means finish / next line) -- no choice can ever reach it by id. Rename it." % [prefix, i, lid]))
		elif index_of_id.has(lid):
			out.append(_f("ERROR", source, "%sLine %d has id \"%s\", which line %d already uses -- ids must be unique within a conversation." % [prefix, i, lid, int(index_of_id[lid])]))
		else:
			index_of_id[lid] = i
	for i in n:
		for ch in lines[i].get("choices", []):
			if String(ch.get("target_id", "")) != "" or String(ch.get("target_on_fail_id", "")) != "":
				uses_ids = true
	var known := ", ".join(index_of_id.keys()) if not index_of_id.is_empty() else "none yet"
	for i in n:
		for ch in lines[i].get("choices", []):
			var gated: bool = bool(ch.get("gated", false))
			_dlg_target_findings(out, source, prefix, i, "Target", String(ch.get("target_id", "")), int(ch.get("target", DLG_CONTINUE)), n, index_of_id, known, uses_ids, true)
			_dlg_target_findings(out, source, prefix, i, "Fail target", String(ch.get("target_on_fail_id", "")), int(ch.get("target_on_fail", DLG_END)), n, index_of_id, known, uses_ids, gated)
	return out


## One destination (id form + legacy int) of one choice. `live` = whether the branch is reachable at all (the fail
## branch of an ungated choice is not: a dangling id there is still an ERROR -- an authored id that names nothing is
## wrong regardless -- but the by-number WARN is skipped, since nothing positional can go wrong on a dead branch).
static func _dlg_target_findings(out: Array, source: String, prefix: String, li: int, field: String, tid: String, t: int, n: int, index_of_id: Dictionary, known: String, uses_ids: bool, live: bool) -> void:
	if tid != "":
		if tid == DLG_ID_END or tid == DLG_ID_CONTINUE:
			return
		if not index_of_id.has(tid):
			out.append(_f("ERROR", source, "%sLine %d: a choice's %s points at id \"%s\", which no line in this conversation has (ids here: %s)." % [prefix, li, field, tid, known]))
		return
	# Legacy int path (the id is blank, so the int is what the runtime consults).
	if t < DLG_CONTINUE or t >= n:
		out.append(_f("ERROR", source, "%sLine %d: a choice's %s points at line %d, which doesn't exist — the lines run 0 to %d (or End / Continue)." % [prefix, li, field, t, n - 1]))
		return
	if live and uses_ids and t >= 0:
		out.append(_f("WARN", source, "%sLine %d: a choice's %s still points by line number (line %d) while this conversation uses ids -- reordering lines would move it. Open it in Dialogue Edit and press Migrate to Ids." % [prefix, li, field, t]))


## The findings for every conversation in one file's text (the .tscn entry point scan_disk uses).
static func dialogue_findings_in_text(text: String, source: String) -> Array:
	var out: Array = []
	for entry in dialogue_models_from_text(text):
		out.append_array(dialogue_findings(entry["model"], source, String(entry["where"])))
	return out


# --- pass-4 text helpers -------------------------------------------------------------------------------------------

## ext_resource id -> which dialogue script it is (one of the three DLG_SCRIPT_* tails), for every ext_resource line
## whose path is a dialogue script. Attribute ORDER in the header is not assumed: path and id are pulled separately.
static func _dlg_ext_kinds(text: String) -> Dictionary:
	var out := {}
	var re_line := RegEx.new()
	re_line.compile("(?m)^\\[ext_resource ([^\\]]*)\\]")
	var re_path := RegEx.new()
	re_path.compile("\\bpath=\"([^\"]+)\"")
	var re_id := RegEx.new()
	re_id.compile("\\bid=\"([^\"]+)\"")
	for m in re_line.search_all(text):
		var attrs := m.get_string(1)
		var pm := re_path.search(attrs)
		var im := re_id.search(attrs)
		if pm == null or im == null:
			continue
		var path := pm.get_string(1)
		for tail in [DLG_SCRIPT_LINE, DLG_SCRIPT_CHOICE, DLG_SCRIPT_RESOURCE]:
			if path.ends_with(tail):
				out[im.get_string(1)] = tail
	return out


## The SubResource("...") ids listed on `field = Array[...]([...])` in one block, in order (empty when absent).
static func _dlg_refs_on_field(block: String, field: String, re_subref: RegEx) -> Array:
	var re := RegEx.new()
	re.compile("(?m)^\\s*" + field + "\\s*=\\s*(.*)$")
	var m := re.search(block)
	var refs: Array = []
	if m == null:
		return refs
	for rm in re_subref.search_all(m.get_string(1)):
		refs.append(rm.get_string(1))
	return refs


## The int value of `field = <int>` in one block, or `fallback` when the field is absent (a .tres omits defaults).
## Anchored on `field\\s*=` so `target_id = ...` can never satisfy a lookup for `target`.
static func _dlg_int_field(block: String, field: String, fallback: int) -> int:
	var re := RegEx.new()
	re.compile("(?m)^\\s*" + field + "\\s*=\\s*(-?\\d+)\\s*$")
	var m := re.search(block)
	return int(m.get_string(1)) if m != null else fallback


static func _dlg_first(values: Array) -> String:
	return String(values[0]) if not values.is_empty() else ""


static func _dlg_text(v: Variant) -> String:
	if v is String or v is StringName:
		return String(v)
	return ""


static func _dlg_int(v: Variant, fallback: int) -> int:
	if v is int or v is float:
		return int(v)
	return fallback


static func _src(src_of: Dictionary, name: String) -> String:
	return str(src_of.get(name, "res:// (project-wide)"))

## The finding shape (domain fixed at content -- see the header).
static func _f(sev: String, src: String, msg: String) -> Dictionary:
	return {"severity": sev, "source": src, "message": msg, "domain": DOMAIN}
