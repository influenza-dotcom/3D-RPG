@tool
extends RefCounted

## Batch AUTO-FIX engine for the audit panel. DETECTION stays in scan_disk: a finding carries an optional `fix`
## descriptor — {kind, source} — when (and only when) its issue has ONE unambiguous mechanical correction. This
## module turns those descriptors into a previewed, confirmed, applied change.
##
## Three fix kinds today, all safe + recoverable:
##   - "player_group": the DEAD lowercase "player" group literal in a .gd -> Groups.PLAYER (the canonical fix the
##     finding message already prescribes; Groups is a global class_name so it always resolves).
##   - "group_literal": a REGISTERED group name used as a raw string literal in a .gd -> its Groups.<CONST> (e.g.
##     add_to_group(&"npc") -> add_to_group(Groups.NPC)). The name->const map comes from GroupsReflect (single source
##     of truth = the Groups consts), so the rewrite is unambiguous; lowercase "player" and unregistered typos are
##     left alone (they aren't in the map).
##   - "loot_clamp": a LootTable entry whose max_count < min_count -> raise max up to min (matches what
##     LootTable.roll() already does at runtime via maxi(lo, max_count), so behaviour is unchanged — the data just
##     stops lying).
##
## EVERY apply backs the file up BEFORE it writes, so the Fix dialog's "each gets a .bak copy beside it" is literally
## true: the two .gd rewrites copy the prior bytes to "<path>.bak" (the content_save_guard idiom, DirAccess.copy_absolute,
## best-effort — a failed copy is warned and the fix still lands, a safety aid never blocks the fix), and the LootTable
## resave goes through ContentSaveGuard.save_with_backup. A mis-fix is one rename of the .bak away from undone;
## version control stays the deeper rollback. The .bak siblings are git-ignored (*.bak) and are never content.
##
## NOT auto-fixed (need a human, no single right answer): unregistered-group typos, missing ext_resource files,
## out-of-range dialogue targets, null/item-less/zero-chance loot entries. Those stay flagged-only.
##
## The PURE transforms (rewrite_player_group_text / rewrite_group_literals_text / clamp_loot_entries / build_plan) are
## unit-tested off-tree; the apply_* functions do the guarded disk I/O — tests/test_devtools_audit.gd drives the two
## file paths against TEMP COPIES under user:// (never project content), the editor verifies the rest. Every I/O step
## fails SOFT (returns an error string in plain words, never throws), so a locked/missing file degrades to a reported
## skip, not a broken panel. Plan labels are DESIGNER words (the file name, "code only, safe"): they are the body of
## the Fix preview dialog, which has no tooltip to hide a path in.

const GroupsReflect := preload("res://addons/cybersunday_tools/core/groups_reflect.gd")
## The detector owns the comment-masking primitive; the rewrites below search the MASKED text (so a literal inside a
## `#` comment is neither rewritten nor counted) but splice into the ORIGINAL — mask_comments preserves length/offsets.
const ScanDisk := preload("res://addons/cybersunday_tools/panel_audit/scan_disk.gd")
## The one recoverable-save seam every CYBER SUNDAY content writer uses: backup_path() names the .bak sibling for the
## .gd copies, save_with_backup() does copy + save for the LootTable resave.
const ContentSaveGuard := preload("res://addons/cybersunday_tools/core/content_save_guard.gd")
## Same first-arg group APIs the detector (scan_disk.GROUP_CALL) recognizes — kept in sync so every literal the audit
## FLAGS, the fixer can also REWRITE.
const GROUP_CALLS := "add_to_group|remove_from_group|is_in_group|get_nodes_in_group|get_first_node_in_group|get_node_count_in_group"
## The fix kinds apply_plan() can actually execute. build_plan() admits only these, so a custom audit rule that tags
## a finding with an unrecognized `fix` kind is treated as flagged-only (it can't smuggle an unapplyable row in).
const KNOWN_KINDS := ["player_group", "group_literal", "loot_clamp"]

## Skip reasons, in the words the result dialog shows the designer.
const ERR_READ := "couldn't read the script -- save any open scripts first, then press Fix again."
const ERR_WRITE := "couldn't write the script -- is the file locked or read-only?"
const ERR_MISSING := "the file no longer exists."
const ERR_NOT_LOOT := "not a loot table file."
const ERR_UNKNOWN_KIND := "this isn't a correction the panel knows how to make."


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


## The preview line for one plan row, in plain words: what changes, in which file (by file name -- the dialog body
## has no tooltip for a path), and for the script rewrites the reassurance that it is code-only and safe.
static func _label_for(kind: String, source: String) -> String:
	var file := source.get_file()
	match kind:
		"player_group":
			return "Use the proper group name for \"player\" in %s  (code only, safe)" % file
		"group_literal":
			return "Use the proper group names in %s  (code only, safe)" % file
		"loot_clamp":
			return "Fix loot table %s: max count raised to min count" % file.get_basename()
	return "Fix %s" % file


# --- pure transforms (unit-tested) ---------------------------------------------------------------------------

## Rewrite EVERY dead lowercase "player" / &"player" group-call argument in `text` to Groups.PLAYER, leaving the
## rest of each line (and any non-group-call "player" string, e.g. a dict key) untouched — the regex only matches
## inside a group API call, mirroring scan_disk.scan_gd_text's detection. Returns {text, count}. Splices matches in
## REVERSE so earlier offsets stay valid. The `&` (StringName sigil) is dropped: Groups.PLAYER is already a StringName.
static func rewrite_player_group_text(text: String) -> Dictionary:
	var re := RegEx.new()
	re.compile("(\\b(?:" + GROUP_CALLS + ")\\(\\s*)&?\"player\"")
	var matches := re.search_all(ScanDisk.mask_comments(text))  # skip literals inside comments; offsets map to `text`
	var out := text
	for i in range(matches.size() - 1, -1, -1):
		var m: RegExMatch = matches[i]
		out = out.substr(0, m.get_start(0)) + m.get_string(1) + "Groups.PLAYER" + out.substr(m.get_end(0))
	return {"text": out, "count": matches.size()}


## Rewrite every REGISTERED group-call literal in `text` to its Groups const — add_to_group(&"npc") -> add_to_group(
## Groups.NPC), get_nodes_in_group("Player") -> get_nodes_in_group(Groups.PLAYER). `const_names` is the name->const
## map (GroupsReflect.const_by_name); a literal whose name isn't in it — lowercase "player" (that's the player_group
## fix's job) or an unregistered typo (needs a human) — is LEFT UNTOUCHED. Only the group-call argument is rewritten,
## so a non-group "npc"/"Player" string elsewhere on the line is untouched. Splices in REVERSE so offsets stay valid.
## The `&` sigil is dropped: every Groups const is already a StringName. Returns {text, count}.
static func rewrite_group_literals_text(text: String, const_names: Dictionary) -> Dictionary:
	var re := RegEx.new()
	re.compile("(\\b(?:" + GROUP_CALLS + ")\\(\\s*)&?\"([^\"]+)\"")
	var matches := re.search_all(ScanDisk.mask_comments(text))  # skip literals inside comments; offsets map to `text`
	var out := text
	var count := 0
	for i in range(matches.size() - 1, -1, -1):
		var m: RegExMatch = matches[i]
		var key := StringName(m.get_string(2))
		if not const_names.has(key):
			continue  # lowercase "player" / unregistered typo — not a registered const, leave it
		out = out.substr(0, m.get_start(0)) + m.get_string(1) + "Groups." + String(const_names[key]) + out.substr(m.get_end(0))
		count += 1
	return {"text": out, "count": count}


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

## Apply a deduped plan. Returns {fixed, files, errors, written} — `fixed` = total individual corrections, `files` =
## DISTINCT files written, `written` = their paths, `errors` = one {source, error} row per skipped file (never
## throws). The skip row keeps the PATH and the plain-words reason apart so the panel can name the file its own way
## (file name + folder) instead of printing a res:// path into designer copy. Caller re-scans + reimports afterward.
##
## `files`/`written` count each PATH once, not each plan row: build_plan emits one row per (kind, source), so a single
## .gd carrying both a dead "player" literal AND a registered group literal yields TWO rows for the SAME file. Both
## rows rewrite it, but the write-contract report must name it once (a path listed twice reads as two files changed).
## The second rewrite of the same file also overwrites the .bak the first one made — so the .bak holds the bytes from
## just before the LAST rewrite, one step of undo, which is the guard's documented depth everywhere else too.
static func apply_plan(plan: Array) -> Dictionary:
	var fixed := 0
	var errors: Array = []
	var written: Array = []  # the DISTINCT source paths actually rewritten — the panel REPORTs these (write contract)
	var seen_written := {}   # path -> true, so a second fix kind on the same file doesn't list/count it again
	for row in plan:
		var kind := String(row.get("kind", ""))
		var source := String(row.get("source", ""))
		var r: Dictionary
		match kind:
			"player_group":
				r = _apply_player_group(source)
			"group_literal":
				r = _apply_group_literal(source)
			"loot_clamp":
				r = _apply_loot_clamp(source)
			_:
				# Unreachable from the panel (build_plan admits only KNOWN_KINDS), but apply_plan is public: answer in
				# the same designer words as every other skip reason, since this lands in the result dialog verbatim.
				r = {"ok": false, "count": 0, "error": ERR_UNKNOWN_KIND}
		if r.get("ok", false):
			fixed += int(r.get("count", 0))
			if int(r.get("count", 0)) > 0 and not seen_written.has(source):
				seen_written[source] = true
				written.append(source)
		else:
			# {source, error}, NEVER a pre-joined "<path>: <reason>" string: the panel names the file its own way
			# (file name + folder) in the result dialog, which is designer copy with no tooltip to hide a path in.
			errors.append({"source": source, "error": str(r.get("error", "the fix didn't run."))})
	return {"fixed": fixed, "files": written.size(), "errors": errors, "written": written}


static func _apply_player_group(path: String) -> Dictionary:
	var text := _read_text(path)
	if text.is_empty():
		return {"ok": false, "count": 0, "error": ERR_READ}
	return _write_rewrite(path, rewrite_player_group_text(text))


static func _apply_group_literal(path: String) -> Dictionary:
	var text := _read_text(path)
	if text.is_empty():
		return {"ok": false, "count": 0, "error": ERR_READ}
	return _write_rewrite(path, rewrite_group_literals_text(text, GroupsReflect.const_by_name()))


static func _apply_loot_clamp(path: String) -> Dictionary:
	if not ResourceLoader.exists(path):
		return {"ok": false, "count": 0, "error": ERR_MISSING}
	var table := load(path)
	if not (table is LootTable):
		return {"ok": false, "count": 0, "error": ERR_NOT_LOOT}
	var n := clamp_loot_entries(table)
	if n == 0:
		return {"ok": true, "count": 0}
	# Prior bytes -> <path>.bak, then the save: the same one-deep undo every content editor's Save button has.
	var err := ContentSaveGuard.save_with_backup(table, path)
	if err != OK:
		return {"ok": false, "count": 0, "error": "couldn't save the loot table: %s." % error_string(err)}
	return {"ok": true, "count": n}


## The script's text, or "" when it can't be opened (an unsaved editor buffer / a locked file). A flagged script is
## never genuinely empty, so "" is an unambiguous read failure here.
static func _read_text(path: String) -> String:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return ""
	var text := f.get_as_text()
	f = null
	return text


## Write one rewritten script: nothing touched when the transform changed nothing; otherwise the prior bytes are copied
## to "<path>.bak" FIRST (the content_save_guard idiom -- copy_absolute overwrites an older .bak, so it is one-deep) and
## then the file is overwritten in place. A failed backup is warned but never blocks the fix.
static func _write_rewrite(path: String, res: Dictionary) -> Dictionary:
	if int(res["count"]) == 0:
		return {"ok": true, "count": 0}
	var bak := ContentSaveGuard.backup_path(path)
	var cp := DirAccess.copy_absolute(path, bak)
	if cp != OK:
		push_warning("FixOps: couldn't back up %s -> %s (%s); fixing anyway." % [path, bak, error_string(cp)])
	var w := FileAccess.open(path, FileAccess.WRITE)
	if w == null:
		return {"ok": false, "count": 0, "error": ERR_WRITE}
	w.store_string(res["text"])
	w = null
	return {"ok": true, "count": int(res["count"])}
