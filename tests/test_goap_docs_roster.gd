extends GutTest

## Docs-as-executable-spec for the GOAP brain. scripts/npc/goap/README.md carries the canonical goal/action NAME
## roster between <!-- GOAP_ROSTER:BEGIN --> / <!-- GOAP_ROSTER:END --> anchors — the one place a human reads the
## vocabulary. test_npc_goap_library already pins GoapLibrary to the library npc.gd actually builds, but nothing
## pinned the README to GoapLibrary, so adding/renaming a goal or action could leave that doc silently stale
## (the exact rot CLAUDE.md's docs-hygiene rule warns about). This asserts the two `- Goals:` / `- Actions:` lines
## in the anchored block equal GoapLibrary's registered names, so the README fails loudly the instant it drifts.
##
## Pure text + a static-func read: no NPC/scene/_ready, no autoloads (per CLAUDE.md's test rules). The parser reads
## only the lines BETWEEN the anchors, so the surrounding prose tables stay free human documentation.

const README_PATH := "res://scripts/npc/goap/README.md"
const BEGIN_ANCHOR := "GOAP_ROSTER:BEGIN"
const END_ANCHOR := "GOAP_ROSTER:END"
const GoapLibrary := preload("res://scripts/npc/goap/goap_library.gd")

## The raw README text, or "" (with a failing assert) if it can't be opened.
func _read_readme() -> String:
	var f := FileAccess.open(README_PATH, FileAccess.READ)
	assert_not_null(f, "GOAP README must exist at %s" % README_PATH)
	if f == null:
		return ""
	var text := f.get_as_text()
	f.close()
	return text

## The lines strictly BETWEEN the BEGIN and END anchors (both anchor lines excluded). Empty when either anchor is
## missing, so the caller can assert a deleted block gives a clear failure rather than a silent pass.
func _roster_block_lines(text: String) -> PackedStringArray:
	var out := PackedStringArray()
	var inside := false
	for line in text.split("\n"):
		if line.find(END_ANCHOR) != -1:
			break
		if inside:
			out.append(line)
		if line.find(BEGIN_ANCHOR) != -1:
			inside = true  # set AFTER the append check, so the BEGIN comment line itself is excluded
	return out

## Parse the `- <Label>: a, b, c` line (case-insensitive label, optional leading bullet) into a sorted name Array.
## [] when no such line is present, so the caller asserts the line exists separately.
func _names_after_label(block: PackedStringArray, label: String) -> Array:
	var prefix := label + ":"
	for raw in block:
		var t := raw.strip_edges()
		if t.begins_with("- "):
			t = t.substr(2).strip_edges()
		if t.to_lower().begins_with(prefix.to_lower()):
			var names: Array = []
			for tok in t.substr(prefix.length()).split(","):
				var nm := tok.strip_edges()
				if nm != "":
					names.append(nm)
			names.sort()
			return names
	return []

func _sorted(arr: PackedStringArray) -> Array:
	var out: Array = Array(arr)
	out.sort()
	return out

func test_readme_has_the_roster_block() -> void:
	# A deleted/renamed anchor block must fail here, not silently drop doc-sync coverage.
	var block := _roster_block_lines(_read_readme())
	assert_true(block.size() > 0, "README must keep the GOAP_ROSTER:BEGIN/END block (executable-spec roster) — see test_goap_docs_roster.gd")

func test_readme_goal_roster_matches_library() -> void:
	var block := _roster_block_lines(_read_readme())
	var documented := _names_after_label(block, "Goals")
	assert_true(documented.size() > 0, "README roster block must carry a `- Goals: ...` line")
	assert_eq(documented, _sorted(GoapLibrary.goal_names()), "README `- Goals:` roster must equal GoapLibrary.goal_names() — update the README block when a goal is added/renamed")

func test_readme_action_roster_matches_library() -> void:
	var block := _roster_block_lines(_read_readme())
	var documented := _names_after_label(block, "Actions")
	assert_true(documented.size() > 0, "README roster block must carry a `- Actions: ...` line")
	assert_eq(documented, _sorted(GoapLibrary.action_names()), "README `- Actions:` roster must equal GoapLibrary.action_names() — update the README block when an action is added/renamed")
