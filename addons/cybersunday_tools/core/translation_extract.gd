@tool
extends RefCounted

## Pure model for the POT parser (core/translation_parser.gd): the entries a file contributes to the
## translation template. Godot's own POT generator (Project Settings → Localization → POT Generation) only knows
## `tr("…")` calls in scripts and the translatable properties of Controls in scenes, so the two places this
## game keeps its copy are invisible to it: the `const NAME := "…"` declarations of `scripts/ui/player_text.gd`
## (every one of them since the 2026-09-15 lift) and the authored fields of `.tres` / `.tscn` resources
## (display_name, description, quest titles, catalog labels, designer `{token}` templates, inline dialogue lines).
##
## An ENTRY is what EditorTranslationParserPlugin._parse_file returns: a PackedStringArray of
## [msgid], [msgid, context] or [msgid, context, msgid_plural]. The third shape matters: a counted line goes
## through TextFormat.plural → TranslationServer.translate_plural, which only finds a catalog entry written
## with `msgid_plural`. So the two consts a `TextFormat.plural(n, ONE, MANY)` call names are emitted as ONE
## plural entry (context "") and never as two singulars.
##
## Rules (each pinned by tests/test_devtools_translation_extract.gd):
##   • A "[PH]" placeholder is UNAUTHORED copy and is never extracted — a translator must not spend time on a
##     line the writer has not finished, and Localization.t never looks one up either.
##   • A `&"…"` StringName is an id, never copy; `resource_name`, paths and uids are skipped by name/shape; a
##     value with no letter in it (a format token, a separator) is not a sentence.
##   • Escapes are unwound (`\n`, `\t`, `\"`, `\\`) so the msgid is the string the game will look up.
##   • Order is declaration order, duplicates dropped — a stable POT diff between runs.
##
## NO class_name on purpose — const-preloaded by path from the parser plugin and the test (the core/ idiom).

const PH_MARK := "[PH]"

## `const NAME := "value"` — the same single-line shape the UI Copy tab edits (dock_uicopy/ui_copy_ops.gd).
const CONST_RE := "^const ([A-Z][A-Z0-9_]*) := \"((?:[^\"\\\\]|\\\\.)*)\"$"
## A `tr("…")` / `atr("…")` call — this parser owns the `.gd` extension, so it must also do what the engine's
## own script parser would have (there are none in this project today; the rule is kept so a future one is not
## silently dropped).
const TR_CALL_RE := "\\ba?tr\\(\\s*\"((?:[^\"\\\\]|\\\\.)*)\""
## `TextFormat.plural(<count>, ONE_CONST, MANY_CONST)` — may span lines (the call is often wrapped).
const PLURAL_CALL_RE := "TextFormat\\.plural\\(\\s*[^,()]+,\\s*([A-Z][A-Z0-9_]*)\\s*,\\s*([A-Z][A-Z0-9_]*)\\s*\\)"
## `name = "value"` at the start of a resource line (an optional `group/` prefix as in `metadata/foo`).
## A `{token}` substitution or a `%s` / `%d` / `%.2f` format specifier — stripped before the letter check.
const TOKEN_RE := "\\{[^{}]*\\}|%[-+ 0#]*[0-9]*(?:\\.[0-9]+)?[a-zA-Z]"
const FIELD_RE :="^(?:[a-z0-9_]+/)?([a-z0-9_]+) = \"((?:[^\"\\\\]|\\\\.)*)\"$"

## Property names that ARE copy, exactly …
const FIELD_NAMES: PackedStringArray = [
	"display_name", "description", "title", "label", "tab_label", "text", "tooltip_text", "hint", "caption",
	"blurb", "member_noun", "placeholder_text",
]
## … and by suffix (designer templates: `paid_message`, `self_bark_template`, `death_message_fall`, …).
const FIELD_SUFFIXES: PackedStringArray = [
	"_message", "_template", "_prompt", "_label", "_text", "_title", "_description", "_name", "_hint",
	"_caption", "_blurb", "_line",
]
## Names that match a suffix above but are machinery, never copy.
const FIELD_SKIP: PackedStringArray = ["resource_name", "node_name", "scene_file_path", "script_class"]


## Dispatch by extension: `.gd` → constants (plural pairs merged) + tr() calls; `.tres` / `.tscn` → fields.
static func for_path(path: String, text: String) -> Array[PackedStringArray]:
	match path.get_extension().to_lower():
		"gd":
			return from_gdscript(text)
		"tres", "tscn":
			return from_resource_text(text)
	var none: Array[PackedStringArray] = []
	return none


## Entries for a GDScript source: every `const NAME := "…"` in declaration order — except that the two
## consts a `TextFormat.plural(n, ONE, MANY)` call names become one [one, "", many] entry at ONE's position —
## then every `tr("…")` / `atr("…")` argument. Filtered + deduplicated by msgid.
static func from_gdscript(text: String) -> Array[PackedStringArray]:
	var const_re := RegEx.new()
	const_re.compile(CONST_RE)
	var call_re := RegEx.new()
	call_re.compile(TR_CALL_RE)
	var plural_re := RegEx.new()
	plural_re.compile(PLURAL_CALL_RE)
	# Pass 1 — which const names form plural pairs (ONE -> MANY), and which are the MANY halves.
	var many_of := {}
	var is_many := {}
	for pm in plural_re.search_all(text):
		many_of[pm.get_string(1)] = pm.get_string(2)
		is_many[pm.get_string(2)] = true
	# Pass 2 — the consts, in order, with the pairs merged.
	var values := {}
	var order := PackedStringArray()
	for line in text.split("\n"):
		var m := const_re.search(line)
		if m == null:
			continue
		values[m.get_string(1)] = unescape(m.get_string(2))
		order.append(m.get_string(1))
	var out: Array[PackedStringArray] = []
	for cname in order:
		if is_many.has(cname) and not many_of.has(cname):
			continue  # emitted with its singular
		var value: String = values[cname]
		if many_of.has(cname) and values.has(many_of[cname]):
			var plural: String = values[many_of[cname]]
			if is_translatable(value) and is_translatable(plural):
				_add(out, PackedStringArray([value, "", plural]))
			continue
		_add(out, PackedStringArray([value]))
	# Pass 3 — tr()/atr() calls.
	for line in text.split("\n"):
		for cm in call_re.search_all(line):
			_add(out, PackedStringArray([unescape(cm.get_string(1))]))
	return out


## Entries for a text resource (.tres / .tscn): every copy-bearing `name = "…"` field, filtered + deduplicated.
static func from_resource_text(text: String) -> Array[PackedStringArray]:
	var field_re := RegEx.new()
	field_re.compile(FIELD_RE)
	var out: Array[PackedStringArray] = []
	for line in text.split("\n"):
		var m := field_re.search(line)
		if m == null or not is_copy_field(m.get_string(1)):
			continue
		_add(out, PackedStringArray([unescape(m.get_string(2))]))
	return out


## The msgids of `entries` (each entry's first element) — the flat view tests and readouts want.
static func msgids(entries: Array[PackedStringArray]) -> PackedStringArray:
	var out := PackedStringArray()
	for e in entries:
		out.append(e[0])
	return out


## Whether a resource property name carries player-facing copy (see FIELD_NAMES / FIELD_SUFFIXES / FIELD_SKIP).
static func is_copy_field(name: String) -> bool:
	if FIELD_SKIP.has(name):
		return false
	if FIELD_NAMES.has(name):
		return true
	for suffix in FIELD_SUFFIXES:
		if name.ends_with(suffix):
			return true
	return false


## Whether a string value is worth a translator's time: non-blank, not a "[PH]" placeholder, not a path or uid,
## and carrying at least one letter (a bare "%s", "{n}" or "—" is a token or a separator, not a sentence).
static func is_translatable(value: String) -> bool:
	var s := value.strip_edges()
	if s.is_empty() or s.contains(PH_MARK):
		return false
	if s.begins_with("res://") or s.begins_with("uid://") or s.begins_with("user://"):
		return false
	# A token's own name is not a word: "{n}" and "%s" carry a letter but no copy.
	var token_re := RegEx.new()
	token_re.compile(TOKEN_RE)
	s = token_re.sub(s, "", true)
	for i in s.length():
		var ch := s[i]
		if ch.to_upper() != ch.to_lower():
			return true  # a cased letter, in any script that has case
	return false


## Source-form escapes → the runtime string (the same scan ui_copy_ops.unescape does; duplicated rather than
## preloaded so core/ never depends on a dock).
static func unescape(raw: String) -> String:
	var out := ""
	var i := 0
	while i < raw.length():
		var c := raw[i]
		if c == "\\" and i + 1 < raw.length():
			var n := raw[i + 1]
			if n == "n":
				out += "\n"
			elif n == "t":
				out += "\t"
			elif n == "r":
				out += "\r"
			elif n == "\\" or n == "\"":
				out += n
			else:
				out += c + n
			i += 2
			continue
		out += c
		i += 1
	return out


static func _add(out: Array[PackedStringArray], entry: PackedStringArray) -> void:
	if not is_translatable(entry[0]):
		return
	for e in out:
		if e[0] == entry[0]:
			return
	out.append(entry)
