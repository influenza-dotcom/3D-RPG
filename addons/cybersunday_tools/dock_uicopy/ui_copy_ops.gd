@tool
extends RefCounted

## Pure model for the UI Copy tab: read the player-facing string constants out of `scripts/ui/player_text.gd`,
## validate an edit against the contract its test enforces, and splice edited values back into the source.
##
## WHY THIS EXISTS: roughly 200 of the project's unauthored `[PH]` strings live in that one 1,860-line script, and
## the Text tab cannot see them — it edits fields on `.tres` resources. So the single largest body of player-facing
## copy in the game was reachable only by opening GDScript, which the authoring guide's first page promises a
## designer never has to do.
##
## WHY IT IS SAFE TO REWRITE A `.gd` HERE: every one of those constants is a ONE-LINE declaration
## (`const NAME := "text"`) — there is not a single multi-line string, line continuation or concatenation at const
## scope in the file. So an edit is a value substitution inside one known line, never a reflow of code. The
## rewrite is line-indexed rather than offset-spliced for exactly that reason: a line either is a known constant
## declaration or is copied through untouched. `tests/test_devtools_ui_copy.gd` pins the proof that matters — a
## parse of the real file followed by a rewrite of every value back to itself is byte-identical.
##
## WHAT IS DELIBERATELY OUT OF SCOPE (v1): the ~200 prose literals that sit INSIDE function bodies as arguments to
## `TextFormat.subst` / `TextFormat.plural`, in ternaries and `match` arms. Those are position-dependent inside
## multi-line call expressions where a line-based rewrite would corrupt code. They are listed read-only by the tab
## so a writer can SEE them and ask for them to be lifted to constants, which is the refactor this file's own
## header argues for anyway (a constant is what the deferred `tr()` sweep can wrap; an inline literal is not).
##
## NO class_name on purpose — const-preloaded by path from the dock, mirroring `content_save_guard.gd`.
## Every string here is a DEVELOPER surface and must never be routed through `PlayerText`.

## The one file this tab edits.
const SOURCE_PATH := "res://scripts/ui/player_text.gd"

## Constants that are machinery, not copy. `PH_PREFIX` / `PH_PREFIX_SPACE` define the placeholder marker itself —
## editing either would change what "unauthored" means everywhere — and `tests/test_player_text.gd` exempts them
## from its `[PH] `-shape assertion by name, which is the tell that they are not prose.
const SKIP_NAMES := ["PH_PREFIX", "PH_PREFIX_SPACE"]

## A single-line string constant: `const NAME := "value"`. Anchored at both ends, so a dictionary or array
## constant (`const X := {`) and a preload (`const Perks := preload(...)`) simply do not match and are copied
## through untouched by the rewrite.
const CONST_RE := "^const ([A-Z][A-Z0-9_]*) := \"(.*)\"$"

## The named substitution tokens a template carries: `{amount}`, `{part}`. `TextFormat.subst` is REPLACE-based, so
## a token the writer deletes or misspells does not error — the value silently renders as nothing. That is why the
## token set is validated rather than trusted.
const TOKEN_RE := "\\{([a-z_0-9]+)\\}"

## Legacy `%` format slots still present in a few death-message templates. Counted, not named, because the `%`
## operator is positional.
const PERCENT_RE := "%[+ #0-9.]*[sdfx]"

## A prose literal inside a function body needs at least this many characters before the tab lists it — shorter
## quoted strings in this file are format tokens, dictionary keys and ids, not sentences.
const MIN_PROSE := 12


## Every editable copy constant in `text`, in declaration order:
##   {"name", "value" (UNESCAPED, ready for a text box), "line" (0-based), "doc" (the ## block above it)}
## The `doc` matters more than it looks: those comment blocks carry hard constraints a copy editor cannot infer —
## "ONE LINE, and keep any re-wording inside one", "keep every line under ~100 chars: it paints on an 11px
## autowrapped band", "the minus is U+2212 MINUS SIGN, NOT an ASCII hyphen". The tab shows them beside the field.
static func parse(text: String) -> Array:
	var out: Array = []
	var re := RegEx.new()
	re.compile(CONST_RE)
	var lines := text.split("\n")
	var doc := PackedStringArray()
	for i in lines.size():
		var line := String(lines[i])
		if line.begins_with("##"):
			doc.append(line.substr(2).strip_edges())
			continue
		var m := re.search(line)
		if m == null:
			# Any non-doc, non-constant line ends the doc run — a blank line between a comment and a constant
			# means the comment belonged to whatever came before.
			doc = PackedStringArray()
			continue
		var cname := m.get_string(1)
		if SKIP_NAMES.has(cname):
			doc = PackedStringArray()
			continue
		out.append({
			"name": cname,
			"value": unescape(m.get_string(2)),
			"line": i,
			"doc": " ".join(doc),
		})
		doc = PackedStringArray()
	return out


## The `PREFIX_` a constant groups under — `OPTIONS_CB_NONE` -> "OPTIONS". This naming convention is the file's
## real section structure: only five banner comments exist in 1,860 lines, but the prefixes cover all but nine
## constants. A name with no underscore (BACK, CANCEL, STRANGER...) groups under "General".
static func group_of(cname: String) -> String:
	var idx := cname.find("_")
	if idx <= 0:
		return "General"
	return cname.substr(0, idx)


## Source form -> text-box form. Nine constants carry an embedded newline escape for a genuinely multi-line
## rendered string; a writer must see and edit those as real line breaks or the escape gets mangled into the prose.
##
## A single left-to-right scan, NOT chained `replace()` calls through a sentinel: the obvious sentinel is a NUL,
## and putting one in a GDScript String makes the engine log "Unexpected NUL character" and substitute U+FFFD, so
## a value carrying an escaped backslash would come back corrupted. Scanning consumes each escape exactly once.
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
			elif n == "\\" or n == "\"":
				out += n
			else:
				out += c + n  # an escape this tab does not own: pass it through untouched
			i += 2
			continue
		out += c
		i += 1
	return out


## Text-box form -> source form. Backslash FIRST, or an escaped backslash would swallow the escape that follows it.
static func escape(value: String) -> String:
	return value.replace("\\", "\\\\").replace("\"", "\\\"").replace("\n", "\\n").replace("\t", "\\t")


## "" when `value` may be saved for `cname`, else the plain reason it may not.
##
## Each rule mirrors an assertion in `tests/test_player_text.gd`, so a refusal here is the tab catching what CI
## would otherwise catch after the commit — except the token rule, which no test can catch because a dropped token
## fails SILENTLY at runtime (`TextFormat.subst` replaces what it finds and leaves the rest alone).
static func validate(cname: String, value: String, original: String) -> String:
	if value.strip_edges() == "":
		return "%s can't be empty -- an empty line paints an invisible blank on screen." % cname
	if value.contains(".gd"):
		return "%s can't name a script file: the player would read it." % cname
	if value.begins_with("[PH]") and not value.begins_with("[PH] "):
		return "%s needs a space after [PH], or the marker stops being recognised." % cname
	var lost := lost_tokens(original, value)
	if lost != "":
		return "%s still needs %s -- without it, that value renders as nothing." % [cname, lost]
	if percent_count(value) != percent_count(original):
		return "%s has to keep its %% slots: the game fills those in." % cname
	return ""


## The `{tokens}` present in `original` but missing from `value`, as a readable list. Extra tokens are allowed:
## adding one renders literally, which is visible and self-correcting, while dropping one renders nothing.
static func lost_tokens(original: String, value: String) -> String:
	var re := RegEx.new()
	re.compile(TOKEN_RE)
	var lost := PackedStringArray()
	for m in re.search_all(original):
		var tok := m.get_string(0)
		if not value.contains(tok) and not lost.has(tok):
			lost.append(tok)
	return ", ".join(lost)


static func percent_count(s: String) -> int:
	var re := RegEx.new()
	re.compile(PERCENT_RE)
	return re.search_all(s).size()


## Write `edits` ({name: new unescaped value}) back into `text`, returning {"text", "count"}.
##
## Line-indexed on purpose: each edit is located by re-matching the constant declaration on its own line, so a
## line that is not a known single-line constant is impossible to touch. An edit whose name no longer sits where
## `parse` found it is SKIPPED rather than guessed at — the caller reports the count it actually applied.
static func apply(text: String, edits: Dictionary) -> Dictionary:
	if edits.is_empty():
		return {"text": text, "count": 0}
	var re := RegEx.new()
	re.compile(CONST_RE)
	var lines := text.split("\n")
	var count := 0
	for i in lines.size():
		var m := re.search(String(lines[i]))
		if m == null:
			continue
		var cname := m.get_string(1)
		if not edits.has(cname) or SKIP_NAMES.has(cname):
			continue
		var next := "const %s := \"%s\"" % [cname, escape(String(edits[cname]))]
		if next == String(lines[i]):
			continue
		lines[i] = next
		count += 1
	return {"text": "\n".join(lines), "count": count}


## The prose literals that live INSIDE function bodies — read-only in v1. Returns
## {"line" (0-based), "func_name", "text"} so the tab can show a writer what is still stuck in code and name the
## function to ask about.
static func inline_literals(text: String) -> Array:
	var out: Array = []
	var fn := RegEx.new()
	fn.compile("^static func ([a-z_0-9]+)")
	var lit := RegEx.new()
	lit.compile("\"([^\"\\\\]{%d,})\"" % MIN_PROSE)
	var current := ""
	var lines := text.split("\n")
	for i in lines.size():
		var line := String(lines[i])
		var fm := fn.search(line)
		if fm != null:
			current = fm.get_string(1)
			continue
		if current == "" or line.strip_edges().begins_with("#"):
			continue
		for m in lit.search_all(line):
			var body := m.get_string(1)
			if not body.contains(" "):
				continue  # a dictionary key or an id, not a sentence
			out.append({"line": i, "func_name": current, "text": body})
	return out


## The headline count for the tab's status line.
static func summary(entries: Array, inline_count: int) -> String:
	var ph := 0
	for e in entries:
		if String(e.get("value", "")).begins_with("[PH] "):
			ph += 1
	return "%s, %d still marked [PH]. %s in code, which this tab can only show you." % [
		count_of(entries.size(), "line", "lines"),
		ph,
		count_of(inline_count, "more line is", "more lines are"),
	]


## "1 line" / "3 lines" — a real singular/plural pair, never a hand-rolled "(s)".
static func count_of(n: int, one: String, many: String) -> String:
	return "%d %s" % [n, one if n == 1 else many]
