@tool
extends RefCounted

## Domain F of the project audit: the CONTENT CHECK. ContentValidator.run (duplicate / blank item ids, ammo with no
## caliber, a faction whose internal id differs from its file name, Perk / GoapProfile authoring slips) rendered as
## audit rows, so the designer sees ONE list in the Audit tab instead of a second report on the Level tab. Fed by the
## shared ItemScan folder walk: ItemDb (the runtime registry) is a non-@tool autoload and is EMPTY inside the editor,
## so without the hand-over the item rules would run over nothing and pass. Read-only.
##
## Every row is domain DOMAIN ("content") -- always listed under the panel's default "Scene + Content" view -- and
## severity SEVERITY ("WARN", the exact string audit_panel colours and counts). The item files ItemScan could not
## load are reported as ONE extra row (source = the items folder) rather than dropped: a shorter list reads as "my
## item vanished" mid-reimport.
##
## run() is the editor glue (folder scan + validator). findings_for() takes the item list in, so
## tests/test_devtools_audit.gd pins the row shape with a temporary Item list; finding_from_problem() / source_for() /
## skipped_finding() are PURE string work on top.

const ItemScan := preload("res://addons/cybersunday_tools/core/item_scan.gd")

const SEVERITY := "WARN"
const DOMAIN := "content"
## The `source` of a problem the validator states without naming a file (a bare item / faction sentence that matches
## no scanned item). Not a res:// path, so the panel's double-click leaves it alone.
const SOURCE_FALLBACK := "content"


static func run() -> Array:
	var rep := ItemScan.scan_report()
	return findings_for(rep["items"], rep["skipped"])


## Rows for the given items plus the paths ItemScan could not load. ContentValidator.run(items) ALSO walks resources/
## for the faction / Perk / GoapProfile checks, so this is pure only with respect to the item list.
static func findings_for(items: Array, skipped: PackedStringArray = PackedStringArray()) -> Array:
	var out: Array = []
	for p in ContentValidator.run(items):
		out.append(finding_from_problem(String(p), items))
	if not skipped.is_empty():
		out.append(skipped_finding(skipped))
	return out


## One validator sentence -> a finding. The source is whichever file the sentence names (see source_for), read off the
## ORIGINAL text. The message is the validator's own sentence with one edit: the "res://" prefix is dropped from any
## path written into it (the Perk / GoapProfile sentences carry one). ContentValidator's own callers -- the headless
## validate_all CI gate, the File -> Run report -- keep the full path, because a terminal line has nowhere else to put
## it; an audit ROW does (its tooltip carries the whole source path), and the engine prefix is noise the designer
## never types. The folders stay: "tough.tres" alone would not say which of two same-named perks broke.
static func finding_from_problem(problem: String, items: Array = []) -> Dictionary:
	return {
		"severity": SEVERITY,
		"source": source_for(problem, items),
		"message": problem.replace("res://", ""),
		"domain": DOMAIN,
	}


## The file a validator sentence is about, so the row can double-click to it: a res:// path written into the text
## (the Perk / GoapProfile rows), else the scanned item whose id, display name or file stem is the first quoted
## token (the item rows name the item, not its file -- ItemScan hands over loaded resources, so the path is known),
## else SOURCE_FALLBACK. Only plain property reads on the items: Item is a game script, and this is a @tool one.
static func source_for(problem: String, items: Array = []) -> String:
	var path_re := RegEx.new()
	path_re.compile("res://[^\\s'\")]+")
	var pm := path_re.search(problem)
	if pm != null:
		return pm.get_string(0)
	var quote_re := RegEx.new()
	quote_re.compile("'([^']+)'")
	var qm := quote_re.search(problem)
	if qm == null:
		return SOURCE_FALLBACK
	var key := qm.get_string(1)
	for it in items:
		if not (it is Resource):
			continue
		var res := it as Resource
		if res.resource_path.is_empty():
			continue
		if str(res.get("id")) == key or str(res.get("display_name")) == key or res.resource_path.get_file().get_basename() == key:
			return res.resource_path
	return SOURCE_FALLBACK


## The one row for item files that exist but did not load as an Item (mid-reimport, or a broken script). Sourced at
## the items folder so double-click reveals it in the FileSystem dock; names every file so nothing is silently short.
static func skipped_finding(skipped: PackedStringArray) -> Dictionary:
	var names := PackedStringArray()
	for p in skipped:
		names.append(String(p).get_file())
	var count := "1 item file" if skipped.size() == 1 else "%d item files" % skipped.size()
	return {
		"severity": SEVERITY,
		"source": ItemScan.ITEMS_DIR,
		"message": "%s could not be read and went unchecked: %s -- reimport in progress? press Scan again." % [count, ", ".join(names)],
		"domain": DOMAIN,
	}
