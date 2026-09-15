@tool
extends RefCounted

## Pure model for the Items & Weapons tab: describe a Resource's designer-facing exports so a dock can build a
## form from them, and translate Godot's property-hint strings into the numbers a widget needs.
##
## WHY DERIVED RATHER THAN HAND-WRITTEN: `WeaponData` carries about 120 exports across a dozen groups and `Item`
## another twenty. A hand-kept field list would be stale the first time either gained a knob — and a MISSING field
## is invisible, so the designer would simply never learn the knob exists. Walking `get_property_list()` means a
## new `@export` shows up in the tab the next time the editor reloads, with no plugin edit.
##
## It also satisfies the three-site round-trip rule (`docs/CYBER_SUNDAY_PLUGIN_QA.md`) by construction: push,
## reset and write all address the same property by name, so no widget can be written-but-never-pushed and stamp
## its construction default over authored data.
##
## NO class_name on purpose — const-preloaded by path from the dock.
## Every string here is a DEVELOPER surface and must never be routed through `PlayerText`.

## Properties never offered for editing here.
##   `id` is a primary KEY, not copy: quests, stock lists, loot tables and save files reference an item by it, so
##   renaming one in a form would silently break every reference. Same rule the Quest tab applies to `Quest.id`.
##   `resource_*` are engine bookkeeping. `script` is not content.
const SKIP_PROPS := ["id", "script", "resource_local_to_scene", "resource_name", "resource_path", "resource_scene_unique_id"]

## Types this form can edit with a real widget. Anything else (a Resource reference, an Array, a Curve) is listed
## read-only with its current value named, and stays the Inspector's job — a picker for every Resource-typed field
## would be a second, worse Inspector.
const EDITABLE_TYPES := [TYPE_BOOL, TYPE_INT, TYPE_FLOAT, TYPE_STRING, TYPE_STRING_NAME]


## Every designer-facing export on `res`, in declaration order:
##   {"name", "group", "type", "hint", "hint_string", "editable" (bool), "multiline" (bool)}
static func fields(res: Object) -> Array:
	var out: Array = []
	if res == null:
		return out
	var group := ""
	for p in res.get_property_list():
		var usage: int = int(p.get("usage", 0))
		if usage & PROPERTY_USAGE_GROUP:
			group = String(p.get("name", ""))
			continue
		if usage & PROPERTY_USAGE_SUBGROUP or usage & PROPERTY_USAGE_CATEGORY:
			continue
		if not (usage & PROPERTY_USAGE_SCRIPT_VARIABLE) or not (usage & PROPERTY_USAGE_EDITOR):
			continue
		var pname := String(p.get("name", ""))
		if pname == "" or SKIP_PROPS.has(pname) or pname.begins_with("_"):
			continue
		var type: int = int(p.get("type", TYPE_NIL))
		var hint: int = int(p.get("hint", PROPERTY_HINT_NONE))
		out.append({
			"name": pname,
			"group": group,
			"type": type,
			"hint": hint,
			"hint_string": String(p.get("hint_string", "")),
			"editable": EDITABLE_TYPES.has(type),
			"multiline": hint == PROPERTY_HINT_MULTILINE_TEXT,
		})
	return out


## A property name as a designer should read it: `max_stack` -> "Max stack". Godot's own inspector does the same
## thing, and the raw snake_case in a form reads as a variable rather than a setting.
static func label_of(pname: String) -> String:
	var words := pname.replace("_", " ")
	if words == "":
		return pname
	return words.substr(0, 1).to_upper() + words.substr(1)


## {min, max, step} for a numeric field. `@export_range(1, 999)` arrives as hint_string "1,999"; a bare number
## arrives with no hint at all, and gets a wide range with a fine step rather than a guess at the author's intent.
##
## The SpinBox trap this exists to avoid: a Range clamps and snaps on the way IN as well as out, so a default
## min/max/step would quietly rewrite an authored value the moment the form pushed it into the widget — a damage
## of 12.5 becoming 12 just by opening the tab.
static func range_of(field: Dictionary) -> Dictionary:
	var is_int: bool = int(field.get("type", TYPE_NIL)) == TYPE_INT
	var out := {"min": -1000000.0, "max": 1000000.0, "step": 1.0 if is_int else 0.001}
	if int(field.get("hint", PROPERTY_HINT_NONE)) != PROPERTY_HINT_RANGE:
		return out
	var parts := String(field.get("hint_string", "")).split(",")
	if parts.size() >= 2:
		out["min"] = float(parts[0])
		out["max"] = float(parts[1])
	if parts.size() >= 3 and float(parts[2]) > 0.0:
		out["step"] = float(parts[2])
	return out


## The choices of an enum/suggestion field: "MELEE:0,PISTOL:1" and "MELEE,PISTOL" both yield ["MELEE", "PISTOL"].
## Returns empty for a field that is not a choice list.
static func enum_items(field: Dictionary) -> PackedStringArray:
	var hint: int = int(field.get("hint", PROPERTY_HINT_NONE))
	if hint != PROPERTY_HINT_ENUM and hint != PROPERTY_HINT_ENUM_SUGGESTION:
		return PackedStringArray()
	var out := PackedStringArray()
	for raw in String(field.get("hint_string", "")).split(","):
		var part := String(raw).strip_edges()
		if part == "":
			continue
		var colon := part.find(":")
		out.append(part.substr(0, colon) if colon > 0 else part)
	return out


## The integer an enum choice maps to. `@export var category: Category` arrives as "MISC:3,WEAPON:0", so the
## selected ROW is not the value — reading the index as the value is the bug this prevents.
static func enum_value(field: Dictionary, index: int) -> int:
	var parts := String(field.get("hint_string", "")).split(",")
	if index < 0 or index >= parts.size():
		return index
	var part := String(parts[index]).strip_edges()
	var colon := part.find(":")
	return int(part.substr(colon + 1)) if colon > 0 else index


## The row index showing `value`, or 0 when nothing matches — the same harmless fallback `PickerRows.index_of`
## uses, so an out-of-range stored value points at a real row instead of -1.
static func enum_index(field: Dictionary, value: int) -> int:
	var parts := String(field.get("hint_string", "")).split(",")
	for i in parts.size():
		if enum_value(field, i) == value:
			return i
	return 0


## A one-line description of a value the form will NOT edit, for the read-only rows: a Resource names its file, an
## empty reference says so plainly rather than printing "<null>" at a designer.
static func describe(value: Variant) -> String:
	if value == null:
		return "(nothing)"
	if value is Resource:
		var path := (value as Resource).resource_path
		return path.get_file() if path != "" else "(built in, edit in the Inspector)"
	if value is Array:
		return "%d entries (edit in the Inspector)" % (value as Array).size()
	return str(value)


## "Saved pistol_item -- 3 changed on the item, 2 on its weapon." Pure so the wording is pinnable headless.
static func save_report(item_file: String, item_changes: int, weapon_file: String, weapon_changes: int) -> String:
	var parts := PackedStringArray()
	if item_changes > 0:
		parts.append("%s on the item" % count_of(item_changes, "change", "changes"))
	if weapon_changes > 0 and weapon_file != "":
		parts.append("%s on %s" % [count_of(weapon_changes, "change", "changes"), weapon_file])
	if parts.is_empty():
		return "Saved %s -- nothing had changed." % item_file
	return "Saved %s -- %s." % [item_file, ", ".join(parts)]


static func count_of(n: int, one: String, many: String) -> String:
	return "%d %s" % [n, one if n == 1 else many]
