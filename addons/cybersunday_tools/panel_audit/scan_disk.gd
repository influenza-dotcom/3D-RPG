@tool
extends RefCounted

## Domain B of the project audit: scans res:// files for silent breakage that per-node config warnings can't see --
## dead/typo'd group literals (vs the Groups registry), broken ext_resource refs, and dead LootTable / out-of-range
## DialogueResource entries. Returns Array[{severity, source, message}]. Button-triggered (it reads every file once).

const GroupsReflect := preload("res://addons/cybersunday_tools/core/groups_reflect.gd")
const WiringScan := preload("res://addons/cybersunday_tools/panel_audit/scan_wiring.gd")
const SKIP_DIRS: Array[String] = [".godot", "addons", ".git"]
const GROUP_CALL := "(add_to_group|remove_from_group|is_in_group|get_nodes_in_group|get_first_node_in_group)"


static func run() -> Array:
	var out: Array = []
	var allowed := GroupsReflect.allowed_names()
	_scan_dir("res://", out, allowed)
	# WIRING AUDITS (Domain C): cross-file dangling-reference passes (story flags / quest+objective ids /
	# faction ids + dict keys) that the per-file passes above can't see. Their own res:// walk; rows merge in.
	out.append_array(WiringScan.run())
	return out


static func _scan_dir(path: String, out: Array, allowed: Dictionary) -> void:
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
				_scan_dir(full, out, allowed)
		else:
			_scan_file(full, out, allowed)
		entry = d.get_next()
	d.list_dir_end()


static func _scan_file(path: String, out: Array, allowed: Dictionary) -> void:
	var ext := path.get_extension()
	if ext != "gd" and ext != "tscn" and ext != "tres":
		return
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return
	var text := f.get_as_text()
	if ext == "gd":
		out.append_array(scan_gd_text(text, path, allowed))
		return
	out.append_array(scan_ref_text(text, path))
	# Only LOAD the .tres if its header declares a type we semantically check -- avoids loading every resource.
	if ext == "tres":
		if "script_class=\"LootTable\"" in text:
			out.append_array(_loot_findings(load(path), path))
		elif "script_class=\"DialogueResource\"" in text:
			out.append_array(_dialogue_findings(load(path), path))


# --- pure, unit-testable text scanners -------------------------------------------------------------------------

## Group-literal findings in one .gd's source text. `allowed` is the registered-group set (GroupsReflect).
static func scan_gd_text(text: String, source: String, allowed: Dictionary) -> Array:
	var out: Array = []
	var re := RegEx.new()
	re.compile("\\b" + GROUP_CALL + "\\(\\s*&?\"([^\"]+)\"")
	for m in re.search_all(text):
		var g := m.get_string(2)
		if g == "player":
			out.append(_f("ERROR", source, "Group literal \"player\" (lowercase) is the DEAD group — nothing joins it. Use Groups.PLAYER (\"Player\")."))
		elif not allowed.has(StringName(g)):
			out.append(_f("WARN", source, "Group literal \"%s\" isn't a registered Groups name — a typo, or add it to scripts/world/groups.gd." % g))
	return out

## Broken ext_resource paths in one .tscn/.tres's text (a missing path loads as <null>).
static func scan_ref_text(text: String, source: String) -> Array:
	var out: Array = []
	var re := RegEx.new()
	re.compile("\\[ext_resource [^\\]]*path=\"(res://[^\"]+)\"")
	for m in re.search_all(text):
		var p := m.get_string(1)
		if not ResourceLoader.exists(p):
			out.append(_f("ERROR", source, "Broken ext_resource path: %s (loads as <null>)." % p))
	return out


# --- semantic .tres checks (the resource is loaded only when its header type matches) ---------------------------

static func _loot_findings(res: Variant, source: String) -> Array:
	var out: Array = []
	if not (res is LootTable):
		return out
	var i := 0
	for e in (res as LootTable).entries:
		if e == null:
			out.append(_f("WARN", source, "LootTable entry %d is null — drops nothing." % i))
		elif e.item == null:
			out.append(_f("WARN", source, "LootTable entry %d has no item — drops nothing." % i))
		elif e.chance <= 0.0:
			out.append(_f("WARN", source, "LootTable entry %d: chance is 0 — it never drops." % i))
		elif e.max_count < e.min_count:
			out.append(_f("WARN", source, "LootTable entry %d: max_count < min_count (silently clamped)." % i))
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
					_target_finding(c.target, n, source, li, "target", out)
					_target_finding(c.target_on_fail, n, source, li, "target_on_fail", out)
		li += 1
	return out

## Dialogue targets must be a valid line index or a sentinel (-1 END, -2 CONTINUE).
static func _target_finding(t: int, n: int, source: String, li: int, field: String, out: Array) -> void:
	if t < -2 or t >= n:
		out.append(_f("ERROR", source, "Dialogue line %d choice %s=%d is out of range (valid -2..%d)." % [li, field, t, n - 1]))


static func _f(sev: String, src: String, msg: String) -> Dictionary:
	return {"severity": sev, "source": src, "message": msg}
