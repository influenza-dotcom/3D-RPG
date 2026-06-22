class_name NodeFinder
extends RefCounted

## Shared depth-first node searches (static-only; never instanced). Replaces the per-script copies of the same
## "find the first node of type T" / "find the first node named X" tree-walks.

## First node of class `klass` AT OR UNDER `node` (INCLUDES `node` itself), depth-first. null if none.
## Caller casts the result, e.g. `NodeFinder.find_first_of_class(root, Skeleton3D) as Skeleton3D`.
static func find_first_of_class(node: Node, klass: Variant) -> Node:
	if is_instance_of(node, klass):
		return node
	for c in node.get_children():
		var found := find_first_of_class(c, klass)
		if found != null:
			return found
	return null

## Append every node of class `klass` AT OR UNDER `node` (INCLUDES `node` itself) to `out`, depth-first. `out` is a
## typed Array (e.g. `Array[NavigationAgent3D]`); only matching instances are appended, so the type stays valid.
static func collect_by_class(node: Node, klass: Variant, out: Array) -> void:
	if is_instance_of(node, klass):
		out.append(node)
	for c in node.get_children():
		collect_by_class(c, klass, out)

## First Node3D UNDER `node` (children only — NOT `node` itself) whose name equals `lower_name` case-insensitively,
## depth-first. null if none.
static func find_first_by_name(node: Node, lower_name: String) -> Node3D:
	for c in node.get_children():
		if c is Node3D and str(c.name).to_lower() == lower_name:
			return c as Node3D
		var nested := find_first_by_name(c, lower_name)
		if nested != null:
			return nested
	return null
