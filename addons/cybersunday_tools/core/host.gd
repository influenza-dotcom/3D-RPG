@tool
extends RefCounted

## HOST LOOKUP for the CYBER SUNDAY tabs. Every tab lives somewhere under cyber_panel.gd (today: an inner job-group
## TabContainer inside the outer panel), and the panel is the only thing that knows how to switch tabs, expand the
## bottom panel, and route a content file to the tab that edits it (`open_in_editor` / `show_tab`). Tabs must NEVER
## reach the panel with get_parent() chains or hard-coded node paths -- the nesting depth is a layout detail that
## has already changed once (flat strip -> job groups) and may change again. They call `Host.find(self)` and
## null-check the result: off-tree (GUT constructs every tab bare, with no parent) it returns null, which is the
## contract that keeps the handoff buttons harmless under test.

## Walk up from `from` to the nearest ancestor that exposes the panel API (duck-typed, both sides are @tool so the
## call honours the "never call a non-@tool instance method from a @tool dock" rule). null when there is none.
static func find(from: Node) -> Node:
	var n: Node = from
	while n != null:
		if n.has_method("open_in_editor") and n.has_method("show_tab"):
			return n
		n = n.get_parent()
	return null


## Convenience: switch to the named tab (a Control `name`, e.g. "Reach") and return it, or null when there is no host
## (headless) or no such tab. The host expands the bottom panel as part of show_tab, so the designer actually sees it.
static func show_tab(from: Node, tab_name: String) -> Control:
	var host := find(from)
	if host == null:
		return null
	var c: Variant = host.call("show_tab", tab_name)
	return c as Control


## Convenience: hand a content file to the tab that edits it (Quest -> Quest Edit, DialogueResource -> Dialogue Edit,
## LootTable -> Loot Edit, NpcData -> Place). false when there is no host, or the type has no in-plugin editor (the
## host then falls back to the Inspector itself). Callers keep their own EditorInterface.edit_resource fallback for
## the headless case.
static func open_in_editor(from: Node, path: String) -> bool:
	var host := find(from)
	if host == null:
		return false
	return bool(host.call("open_in_editor", path))
