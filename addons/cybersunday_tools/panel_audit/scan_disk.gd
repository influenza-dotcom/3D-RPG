@tool
extends RefCounted

## Domain B of the project audit: scans res:// files for silent breakage that per-node config warnings can't see --
## dead/typo'd group literals (vs the Groups registry), missing ext_resource files, and dead LootTable / out-of-range
## DialogueResource entries. Returns Array[{severity, source, message, domain}]. Button-triggered (it reads every
## file once).
##
## `domain` is the Audit tab's row filter: the .gd group-literal rows are DOMAIN_CODE (a programmer's tidy-up the
## designer can hide behind the default "Scene + Content" view), the resource rows and the chained wiring rows are
## DOMAIN_CONTENT. The other consumers of these rows -- scripts/tools/validate_all.gd, scripts/tools/cyber_cmds.gd
## (which stamps its OWN `domain` vocabulary over the row copy it returns), tests/test_groups.gd -- predate the key
## and ignore it: this dict may only GAIN keys, never change shape, severity strings, or the messages they assert on.

const GroupsReflect := preload("res://addons/cybersunday_tools/core/groups_reflect.gd")
const WiringScan := preload("res://addons/cybersunday_tools/panel_audit/scan_wiring.gd")
## Shared one-read-per-file cache: this domain, scan_wiring, scan_text and scan_menu_sound all read the SAME .gd
## files during one Scan. Inert outside audit_panel's begin()/end() window, so a standalone run is unchanged.
const ScanCache := preload("res://addons/cybersunday_tools/panel_audit/scan_cache.gd")
## Finding domains (see the header). Rows without the key are read as content by the panel.
const DOMAIN_CODE := "code"
const DOMAIN_CONTENT := "content"
# `tests` is skipped: GUT fixtures deliberately use synthetic group literals (e.g. "noise"/"vip"/"flammable")
# and throwaway story flags that aren't real content — scanning them only adds permanent baseline noise that
# hides a genuine production typo. A broken ref inside a test fails the GUT run itself, so it's covered there.
const SKIP_DIRS: Array[String] = [".godot", "addons", ".git", "tests"]
## Every Node/SceneTree API whose FIRST argument is a group name. get_node_count_in_group was long missing here even
## though the project uses it (paint_projectile) — so it's included now; the `_flags` variants (call_group_flags …)
## are deliberately excluded, their group is the SECOND arg and this "literal right after the call" regex would misfire.
const GROUP_CALL := "(add_to_group|remove_from_group|is_in_group|get_nodes_in_group|get_first_node_in_group|get_node_count_in_group)"


static func run() -> Array:
	var out: Array = []
	var allowed := GroupsReflect.allowed_names()
	# name -> Groups const identifier, so a raw registered literal can be flagged with the EXACT Groups.<CONST> to use.
	var const_names := GroupsReflect.const_by_name()
	_scan_dir("res://", out, allowed, const_names)
	# WIRING AUDITS (Domain C): cross-file dangling-reference passes (story flags / quest+objective ids /
	# faction ids + dict keys) that the per-file passes above can't see. Their own res:// walk; rows merge in.
	out.append_array(WiringScan.run())
	return out


static func _scan_dir(path: String, out: Array, allowed: Dictionary, const_names: Dictionary) -> void:
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
				_scan_dir(full, out, allowed, const_names)
		else:
			_scan_file(full, out, allowed, const_names)
		entry = d.get_next()
	d.list_dir_end()


static func _scan_file(path: String, out: Array, allowed: Dictionary, const_names: Dictionary) -> void:
	var ext := path.get_extension()
	if ext != "gd" and ext != "tscn" and ext != "tres":
		return
	var text := ScanCache.text_of(path)
	if text.is_empty():
		return
	if ext == "gd":
		out.append_array(scan_gd_text(text, path, allowed, const_names))
		return
	out.append_array(scan_ref_text(text, path))
	# Only LOAD the .tres if its header declares a type we semantically check -- avoids loading every resource.
	if ext == "tres":
		if "script_class=\"LootTable\"" in text:
			out.append_array(_loot_findings(load(path), path))
		elif "script_class=\"DialogueResource\"" in text:
			out.append_array(_dialogue_findings(load(path), path))


# --- pure, unit-testable text scanners -------------------------------------------------------------------------

## Group-literal findings in one .gd's source text. `allowed` is the registered-group set (GroupsReflect);
## `const_names` maps each registered name -> its Groups const identifier (GroupsReflect.const_by_name), so a raw
## literal is flagged with the EXACT `Groups.<CONST>` to use (defaults to name.to_upper() when the map is omitted, e.g.
## in unit tests). Comments are masked FIRST (mask_comments): this project documents call idioms in prose (`## ...
## is_in_group(&"npc")`), so a literal quoted inside a `#` comment is not a real usage and must never be a finding. Three finding classes:
##   - lowercase "player": the DEAD group (nothing joins it) — an ERROR, auto-fixable to Groups.PLAYER.
##   - a REGISTERED name used as a raw string instead of its const — a WARN, auto-fixable to Groups.<CONST> (the
##     "non-const group use" this audit exists to eliminate: IDE autocomplete, safe rename, no silent typo drift).
##   - an UNREGISTERED name — a WARN (a typo, or a group to add to groups.gd); no single right fix, so flagged only.
## Every row here is DOMAIN_CODE: it points at a line of script, so the panel prefixes it "[code]" and hides it under
## the designer's default view (the Fix plan still includes it).
static func scan_gd_text(text: String, source: String, allowed: Dictionary, const_names: Dictionary = {}) -> Array:
	var out: Array = []
	var re := RegEx.new()
	re.compile("\\b" + GROUP_CALL + "\\(\\s*&?\"([^\"]+)\"")
	for m in re.search_all(mask_comments(text)):
		var g := m.get_string(2)
		if g == "player":
			var f := _f("ERROR", source, "Group literal \"player\" (lowercase) is the DEAD group — nothing joins it. Use Groups.PLAYER (\"Player\").", DOMAIN_CODE)
			f["fix"] = {"kind": "player_group", "source": source}  # one unambiguous fix -> the audit panel can batch-apply it
			out.append(f)
		elif allowed.has(StringName(g)):
			var cname := String(const_names.get(StringName(g), g.to_upper()))
			var f := _f("WARN", source, "Group literal \"%s\" — use Groups.%s instead of a raw string (autocomplete, safe rename, no typo drift)." % [g, cname], DOMAIN_CODE)
			f["fix"] = {"kind": "group_literal", "source": source}  # one mechanical rewrite -> the audit panel can batch-apply it
			out.append(f)
		else:
			out.append(_f("WARN", source, "Group literal \"%s\" isn't a registered Groups name — a typo, or add it to scripts/world/groups.gd." % g, DOMAIN_CODE))
	return out


## Blank out `#` line-comments — replace each comment character with a space, PRESERVING the text's length and every
## byte offset — so a group-call literal quoted INSIDE a comment (this project documents call idioms in prose) never
## trips the scanner. Length preservation is load-bearing: fix_ops runs the SAME regex over this masked text yet
## splices its rewrite into the ORIGINAL text at the matched offsets, so the fixer rewrites EXACTLY the literals this
## detector flags and never a commented idiom (keeping the two in sync, and the Fix preview count honest). Quote-aware:
## a `#` inside a "..." or '...' string is NOT a comment start, and a `\"` escape is honored. Not special-cased (both
## pathological + absent from the tree): triple-quoted multiline strings, and a group call embedded in a normal string.
static func mask_comments(text: String) -> String:
	var kept := PackedStringArray()
	for line in text.split("\n"):
		kept.append(_mask_line_comment(line))
	return "\n".join(kept)


static func _mask_line_comment(line: String) -> String:
	var in_str := false
	var quote := ""
	var i := 0
	var n := line.length()
	while i < n:
		var c := line[i]
		if in_str:
			if c == "\\":
				i += 2  # skip the escaped character (e.g. \" inside a string)
				continue
			if c == quote:
				in_str = false
		elif c == "\"" or c == "'":
			in_str = true
			quote = c
		elif c == "#":
			return line.substr(0, i) + " ".repeat(n - i)  # blank the comment, keep the length (offsets stay valid)
		i += 1
	return line

## Missing ext_resource files in one .tscn/.tres's text (a path that no longer exists loads as nothing, so the scene
## or resource silently loses that piece). A content row: the designer fixes it by re-pointing the field, not in code.
static func scan_ref_text(text: String, source: String) -> Array:
	var out: Array = []
	var re := RegEx.new()
	re.compile("\\[ext_resource [^\\]]*path=\"(res://[^\"]+)\"")
	for m in re.search_all(text):
		var p := m.get_string(1)
		if not ResourceLoader.exists(p):
			# The missing path is named WITHOUT its "res://" prefix: this is a content row, so it sits in the
			# designer's default view, and the engine prefix is noise they never type. The folders stay -- the file
			# name alone would not say WHICH "icon.png" went missing.
			out.append(_f("ERROR", source, "Missing file: %s -- this points at a file that no longer exists." % p.trim_prefix("res://")))
	return out


# --- semantic .tres checks (the resource is loaded only when its header type matches) ---------------------------

static func _loot_findings(res: Variant, source: String) -> Array:
	var out: Array = []
	if not (res is LootTable):
		return out
	var i := 0
	for e in (res as LootTable).entries:
		# Designer words, matching the Loot Edit tab the double-click opens: "row 2", "Chance", "Min", "Max" -- never
		# the class name or the property identifiers, since these are content rows in the default view.
		if e == null:
			out.append(_f("WARN", source, "Loot row %d is empty — it drops nothing." % i))
		elif e.item == null:
			out.append(_f("WARN", source, "Loot row %d has no item — it drops nothing." % i))
		elif e.chance <= 0.0:
			out.append(_f("WARN", source, "Loot row %d: Chance is 0 — it never drops." % i))
		elif e.max_count < e.min_count:
			var f := _f("WARN", source, "Loot row %d: Max is below Min — the count is quietly raised to Min every drop." % i)
			f["fix"] = {"kind": "loot_clamp", "source": source}  # raise max up to min -> matches roll()'s maxi() clamp
			out.append(f)
		i += 1
	return out

static func _dialogue_findings(res: Variant, source: String) -> Array:
	var out: Array = []
	if not (res is DialogueResource):
		return out
	var dr := res as DialogueResource
	var n := dr.lines.size()
	var li := 0
	for line in dr.lines:
		if line != null:
			for c in line.choices:
				if c != null:
					# The field names are the Dialogue Edit tab's own labels, not the property identifiers: this row
					# is what the designer reads, and double-clicking it opens exactly those two dropdowns.
					_target_finding(c.target, n, source, li, "Target", out)
					_target_finding(c.target_on_fail, n, source, li, "Fail target", out)
		li += 1
	return out

## Dialogue targets must be a valid line index or a sentinel (-1 END, -2 CONTINUE). The message names the sentinels by
## their dropdown labels (End / Continue) rather than the raw -1 / -2 the designer never sees.
static func _target_finding(t: int, n: int, source: String, li: int, field: String, out: Array) -> void:
	if t < -2 or t >= n:
		out.append(_f("ERROR", source, "Line %d: a choice's %s points at line %d, which doesn't exist — the lines run 0 to %d (or End / Continue)." % [li, field, t, n - 1]))


## The finding shape. `domain` defaults to content -- only the .gd group-literal rows pass DOMAIN_CODE.
static func _f(sev: String, src: String, msg: String, domain: String = DOMAIN_CONTENT) -> Dictionary:
	return {"severity": sev, "source": src, "message": msg, "domain": domain}
