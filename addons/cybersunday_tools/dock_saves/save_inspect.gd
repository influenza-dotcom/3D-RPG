@tool
extends RefCounted

## Read-only model for the GameState save-file inspector. Lists the known save slots and flattens a loaded
## ConfigFile into a {section -> rows} tree the Saves tab renders. PURE (config_model is unit-tested with an
## in-memory ConfigFile); the tab does the disk read + UI. This NEVER writes — it only reads saves.
##
## Paths MIRROR managers/GameState.gd (SAVE_PATH / QUICKSAVE_PATH / slot_path). They're stable user:// names —
## changing one would orphan existing saves — and they're duplicated here because GameState is an autoload with no
## class_name, so its consts aren't reachable from an edit-time @tool script. Keep in sync if those paths ever move.

const SLOT_COUNT := 3


## The known save files in display order: [{label, path}]. Existence is the caller's check (FileAccess.file_exists),
## so this stays pure + testable without touching the disk.
static func known_saves() -> Array:
	var out: Array = [
		{"label": "Autosave", "path": "user://gamestate.cfg"},
		{"label": "Quicksave", "path": "user://quicksave.cfg"},
	]
	for i in range(1, SLOT_COUNT + 1):
		out.append({"label": "Slot %d" % i, "path": "user://save_slot_%d.cfg" % i})
	return out


## Flatten a loaded ConfigFile into [{section, rows:[{key, value}]}] for the tree. Generic — works for ANY section
## or key, so it keeps reflecting the save even as GameState's schema grows. `value` is a readable one-line string.
static func config_model(cfg: ConfigFile) -> Array:
	var out: Array = []
	if cfg == null:
		return out
	for section in cfg.get_sections():
		var rows: Array = []
		for key in cfg.get_section_keys(section):
			rows.append({"key": String(key), "value": fmt_value(cfg.get_value(section, key))})
		out.append({"section": String(section), "rows": rows})
	return out


## One-line, readable rendering of a saved value: a Vector3 as (x, y, z); an Array/Dictionary as a size-prefixed
## preview (so a big inventory blob doesn't blow up the row); everything else via str(). Pure + tested.
static func fmt_value(v: Variant) -> String:
	match typeof(v):
		TYPE_VECTOR3:
			var vec := v as Vector3
			return "(%.2f, %.2f, %.2f)" % [vec.x, vec.y, vec.z]
		TYPE_ARRAY:
			return "Array(%d): %s" % [(v as Array).size(), str(v)]
		TYPE_DICTIONARY:
			return "Dict(%d): %s" % [(v as Dictionary).size(), str(v)]
		_:
			return str(v)
