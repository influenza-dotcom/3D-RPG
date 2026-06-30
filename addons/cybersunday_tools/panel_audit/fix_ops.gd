@tool
extends RefCounted

## Batch AUTO-FIX engine for the audit panel. DETECTION stays in scan_disk: a finding carries an optional `fix`
## descriptor — {kind, source} — when (and only when) its issue has ONE unambiguous mechanical correction. This
## module turns those descriptors into a previewed, confirmed, applied change.
##
## Two fix kinds today, both safe + reversible-via-VCS:
##   - "player_group": the DEAD lowercase "player" group literal in a .gd -> Groups.PLAYER (the canonical fix the
##     finding message already prescribes; Groups is a global class_name so it always resolves).
##   - "loot_clamp": a LootTable entry whose max_count < min_count -> raise max up to min (matches what
##     LootTable.roll() already does at runtime via maxi(lo, max_count), so behaviour is unchanged — the data just
##     stops lying).
##
## NOT auto-fixed (need a human, no single right answer): unregistered-group typos, broken ext_resource paths,
## out-of-range dialogue targets, null/item-less/zero-chance loot entries. Those stay flagged-only.
##
## The PURE transforms (rewrite_player_group_text / clamp_loot_entries / build_plan) are unit-tested off-tree; the
## apply_* functions do the guarded disk I/O and are editor-verified. Every I/O step fails SOFT (returns an error
## string, never throws), so a locked/missing file degrades to a reported skip instead of a broken panel.

const GROUP_CALLS := "add_to_group|remove_from_group|is_in_group|get_nodes_in_group|get_first_node_in_group"
## The fix kinds apply_plan() can actually execute. build_plan() admits only these, so a custom audit rule that tags
## a finding with an unrecognized `fix` kind is treated as flagged-only (it can't smuggle an unapplyable row in).
const KNOWN_KINDS := ["player_group", "loot_clamp"]


## Collapse audit findings into a DEDUPED fix plan: one row per (kind, source). A file with several dead "player"
## literals — or a LootTable with several bad entries — yields a SINGLE plan row (one rewrite / one resave covers
## them all). Each row: {kind, source, label}. Pure (no I/O) so the UI flow is unit-testable without the editor.
static func build_plan(findings: Array) -> Array:
	var seen := {}
	var plan: Array = []
	for f in findings:
		if not (f is Dictionary):
			continue
		var fix: Variant = f.get("fix")
		if not (fix is Dictionary):
			continue
		var kind := String(fix.get("kind", ""))
		var source := String(fix.get("source", f.get("source", "")))
		if not KNOWN_KINDS.has(kind) or source == "":
			continue
		var key := kind + "|" + source
		if seen.has(key):
			continue
		seen[key] = true
		plan.append({"kind": kind, "source": source, "label": _label_for(kind, source)})
	return plan


static func _label_for(kind: String, source: String) -> String:
	match kind:
		"player_group":
			return "Replace dead \"player\" group literal(s) -> Groups.PLAYER  in  %s" % source
		"loot_clamp":
			return "Clamp max_count up to min_count on LootTable entr(ies)  in  %s" % source
	return "Fix  in  %s" % source


# --- pure transforms (unit-tested) ---------------------------------------------------------------------------

## Rewrite EVERY dead lowercase "player" / &"player" group-call argument in `text` to Groups.PLAYER, leaving the
## rest of each line (and any non-group-call "player" string, e.g. a dict key) untouched — the regex only matches
## inside a group API call, mirroring scan_disk.scan_gd_text's detection. Returns {text, count}. Splices matches in
## REVERSE so earlier offsets stay valid. The `&` (StringName sigil) is dropped: Groups.PLAYER is already a StringName.
static func rewrite_player_group_text(text: String) -> Dictionary:
	var re := RegEx.new()
	re.compile("(\\b(?:" + GROUP_CALLS + ")\\(\\s*)&?\"player\"")
	var matches := re.search_all(text)
	var out := text
	for i in range(matches.size() - 1, -1, -1):
		var m: RegExMatch = matches[i]
		out = out.substr(0, m.get_start(0)) + m.get_string(1) + "Groups.PLAYER" + out.substr(m.get_end(0))
	return {"text": out, "count": matches.size()}


## Clamp every entry whose max_count < min_count UP to min_count (in place). Returns the number fixed. A null entry
## or one that's already valid is skipped. `table` is duck-typed (LootTable) so a test can pass a bare .new().
static func clamp_loot_entries(table) -> int:
	if table == null or not ("entries" in table):
		return 0
	var n := 0
	for e in table.entries:
		if e != null and e.max_count < e.min_count:
			e.max_count = e.min_count
			n += 1
	return n


# --- guarded apply (editor-side I/O) -------------------------------------------------------------------------

## Apply a deduped plan. Returns {fixed, files, errors} — `fixed` = total individual corrections, `files` = files
## written, `errors` = human-readable skip reasons (never throws). Caller re-scans + reimports afterward.
static func apply_plan(plan: Array) -> Dictionary:
	var fixed := 0
	var files := 0
	var errors: Array = []
	var written: Array = []  # the source paths actually rewritten — so the panel can REPORT what changed (write contract)
	for row in plan:
		var kind := String(row.get("kind", ""))
		var source := String(row.get("source", ""))
		var r: Dictionary
		match kind:
			"player_group":
				r = _apply_player_group(source)
			"loot_clamp":
				r = _apply_loot_clamp(source)
			_:
				r = {"ok": false, "count": 0, "error": "unknown fix kind '%s'" % kind}
		if r.get("ok", false):
			fixed += int(r.get("count", 0))
			if int(r.get("count", 0)) > 0:
				files += 1
				written.append(source)
		else:
			errors.append("%s: %s" % [source, str(r.get("error", "failed"))])
	return {"fixed": fixed, "files": files, "errors": errors, "written": written}


static func _apply_player_group(path: String) -> Dictionary:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {"ok": false, "count": 0, "error": "can't read (open scripts must be saved first)"}
	var text := f.get_as_text()
	f = null
	var res := rewrite_player_group_text(text)
	if int(res["count"]) == 0:
		return {"ok": true, "count": 0}
	var w := FileAccess.open(path, FileAccess.WRITE)
	if w == null:
		return {"ok": false, "count": 0, "error": "can't write (file locked?)"}
	w.store_string(res["text"])
	w = null
	return {"ok": true, "count": int(res["count"])}


static func _apply_loot_clamp(path: String) -> Dictionary:
	if not ResourceLoader.exists(path):
		return {"ok": false, "count": 0, "error": "resource missing"}
	var table := load(path)
	if not (table is LootTable):
		return {"ok": false, "count": 0, "error": "not a LootTable"}
	var n := clamp_loot_entries(table)
	if n == 0:
		return {"ok": true, "count": 0}
	var err := ResourceSaver.save(table, path)
	if err != OK:
		return {"ok": false, "count": 0, "error": "save failed (%d)" % err}
	return {"ok": true, "count": n}
