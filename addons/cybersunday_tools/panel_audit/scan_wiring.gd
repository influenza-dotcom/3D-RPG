@tool
extends RefCounted

## WIRING AUDITS (Domain C of the project audit): three cross-file dangling-reference passes that the per-file
## scanners in scan_disk.gd can't see, because a wiring bug is only visible once the WHOLE project is in view --
## a story flag a dialogue READS that nothing ever WRITES (a dead gate), a quest-id a trigger advances that no
## .tres declares (a typo), a faction-id a merchant prices against that has no resource. Each pass GATHERS literals
## across every res:// .tscn/.tres/.gd into sets, then RESOLVES references against those sets. Returns
## Array[{severity, source, message}] (errors first), the same finding shape scan_disk emits.
##
## SPLIT: every predicate below is a PURE static func (no EditorInterface / no scene tree / no autoload) so the GUT
## suite tests the classifier + resolver logic on small fixture strings/dicts; run() and the .tres LOADS are the
## thin editor glue on top. Designer-first: the rows surface in the existing Audit tab automatically.

# --- field vocabularies (the REAL export names, read off the live scripts) ------------------------------------
## Story-flag fields that WRITE a flag (they call GameState.set_flag): TriggerVolume/DialogueChoice.set_flag,
## Lock.unlock_flag, TutorialPrompt.seen_flag. unlock_flag is ALSO read by Door, so it's a writer AND a reader.
const FLAG_WRITE_FIELDS: Array[String] = ["set_flag", "unlock_flag", "seen_flag"]
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

const SKIP_DIRS: Array[String] = [".godot", "addons", ".git"]
const FACTION_DIR := "res://resources/factions/"


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
	for ref in ctx["faction_refs"]:
		var msg := resolve_faction_id(ref["value"], ctx["faction_ids"])
		if msg != "":
			out.append(_f("ERROR", ref["source"], "%s %s" % [ref["field"], msg]))
	out.append_array(ctx["faction_dict_findings"] if ctx.has("faction_dict_findings") else [])
	out.append_array(ctx["faction_mismatch_findings"] if ctx.has("faction_mismatch_findings") else [])
	out.append_array(flag_findings(ctx["writers"], ctx["readers"], ctx["flag_src"]))
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
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return
	var text := f.get_as_text()
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
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return
	if not ("script_class=\"Quest\"" in f.get_as_text()):
		return  # only LOAD a .tres whose header declares Quest -- avoids loading every resource
	var q: Variant = load(path)
	if not (q is Quest):
		return
	var quest := q as Quest
	var qid := str(quest.id)
	if qid != "":
		ctx["quest_ids"][qid] = true
		var objs := {}
		for obj in quest.objectives:
			if obj != null and str(obj.id) != "":
				objs[str(obj.id)] = true
		ctx["objectives_by_quest"][qid] = objs
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
	# overloaded (KILL/TALK/etc. use it too), so only count it when a FLAG type sits in the same resource block.
	if _has_flag_objective(text):
		for v in _field_string_values(text, "target_id"):
			out["read"].append(v)
	# Bare autoload calls in .gd source (a hand-coded gate) -- set_flag(...) writes, get_flag/has_flag(...) read.
	for v in _call_string_args(text, "set_flag"):
		out["write"].append(v)
	for v in _call_string_args(text, "get_flag"):
		out["read"].append(v)
	for v in _call_string_args(text, "has_flag"):
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
## pair them positionally (TriggerVolume / DialogueChoice each carry exactly one such pair per resource block).
## PURE. Only emits a pair when BOTH are present (one-without-the-other is a separate config-warning concern).
static func collect_advance_pairs(text: String) -> Array:
	var out: Array = []
	var quests := _field_string_values(text, "advance_quest_id")
	var objs := _field_string_values(text, "advance_objective_id")
	var n: int = mini(quests.size(), objs.size())
	for i in n:
		if quests[i] != "" and objs[i] != "":
			out.append({"quest": quests[i], "objective": objs[i]})
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

static func _src(src_of: Dictionary, name: String) -> String:
	return str(src_of.get(name, "res:// (project-wide)"))

static func _f(sev: String, src: String, msg: String) -> Dictionary:
	return {"severity": sev, "source": src, "message": msg}
