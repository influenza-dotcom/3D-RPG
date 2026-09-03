@tool
extends RefCounted

## PURE structural diff of two .tscn files (the Scene Diff tab). Parses each scene's TEXT into a node model
## {node_path: {name, type, props}} WITHOUT instantiating it (no _init side effects, no renderer), then diffs the two
## models into added / removed / changed nodes with per-property differences. Both functions are pure + unit-tested;
## the tab does the file reads + tree render. READ-ONLY: this only compares — there is no merge (apply changes by
## hand; auto-merging scenes is unsafe). LIMITATION: property values are read one line at a time, so a rare
## multi-line node property is compared by its first line only — enough to FLAG a change, not to show every byte.

## Parse a .tscn's text into {node_path: {name: String, type: String, props: {name: value_text}}}. The root keys as
## "." and every other node as its NodePath-from-root (parent "." -> the node name; parent "Foo" -> "Foo/<name>").
## `name` is the node's own name from the [node ...] header — for every child it is also the last segment of the
## key, but the ROOT's key is the fixed "." (the tab renders it as "<RootName> (root)", and diff_scenes reports a
## root rename through it). ext_resource / sub_resource / connection blocks are ignored — only [node ...] sections +
## their property lines are modelled.
static func parse_scene(text: String) -> Dictionary:
	var nodes := {}
	var cur := ""
	var re_name := RegEx.new(); re_name.compile("name=\"([^\"]+)\"")
	var re_type := RegEx.new(); re_type.compile("type=\"([^\"]+)\"")
	var re_parent := RegEx.new(); re_parent.compile("parent=\"([^\"]+)\"")
	for line in text.split("\n"):
		var s := line.strip_edges()
		if s.begins_with("[node "):
			var nm := re_name.search(s)
			if nm == null:
				cur = ""
				continue
			var name := nm.get_string(1)
			var tm := re_type.search(s)
			var node_type := tm.get_string(1) if tm != null else ""  # "" = an instanced scene (instance=...)
			var pm := re_parent.search(s)
			var parent := pm.get_string(1) if pm != null else ""  # "" = the root node
			var key := "." if parent == "" else (name if parent == "." else parent + "/" + name)
			cur = key
			nodes[key] = {"name": name, "type": node_type, "props": {}}
		elif s.begins_with("["):
			cur = ""  # left the node block (ext_resource / sub_resource / connection / editable / ...)
		elif cur != "" and " = " in s:
			var idx := s.find(" = ")
			nodes[cur]["props"][s.substr(0, idx)] = s.substr(idx + 3)
	return nodes


## Diff two parsed models (a = "before"/left, b = "after"/right). Returns {added, removed, changed} where added /
## removed are node-path arrays (in b-only / a-only) and changed is [{key, type_change, props_added, props_removed,
## props_changed}] for nodes in BOTH whose type or any property differs. A child rename shows up as one removed +
## one added key (children key by name); the ROOT keys as "." on both sides, so its rename is reported as a
## "name: Old -> New" entry in props_changed instead — the only place a rename is visible as a change. Models built
## without a `name` (older callers, hand-made fixtures) diff as before. Pure.
static func diff_scenes(a: Dictionary, b: Dictionary) -> Dictionary:
	var added: Array = []
	var removed: Array = []
	var changed: Array = []
	for k in b:
		if not a.has(k):
			added.append(k)
	for k in a:
		if not b.has(k):
			removed.append(k)
			continue
		var pa: Dictionary = a[k]["props"]
		var pb: Dictionary = b[k]["props"]
		var type_change := ""
		if String(a[k]["type"]) != String(b[k]["type"]):
			type_change = "type %s -> %s" % [String(a[k]["type"]), String(b[k]["type"])]
		var p_added: Array = []
		var p_removed: Array = []
		var p_changed: Array = []
		if k == ".":
			var name_a := String(a[k].get("name", ""))
			var name_b := String(b[k].get("name", ""))
			if name_a != name_b:
				p_changed.append("name: %s -> %s" % [name_a, name_b])
		for pk in pb:
			if not pa.has(pk):
				p_added.append(pk)
		for pk in pa:
			if not pb.has(pk):
				p_removed.append(pk)
			elif String(pa[pk]) != String(pb[pk]):
				p_changed.append("%s: %s -> %s" % [pk, str(pa[pk]), str(pb[pk])])
		if type_change != "" or not p_added.is_empty() or not p_removed.is_empty() or not p_changed.is_empty():
			p_added.sort()
			p_removed.sort()
			p_changed.sort()
			changed.append({"key": k, "type_change": type_change, "props_added": p_added, "props_removed": p_removed, "props_changed": p_changed})
	added.sort()
	removed.sort()
	changed.sort_custom(func(x, y): return String(x["key"]) < String(y["key"]))
	return {"added": added, "removed": removed, "changed": changed}
