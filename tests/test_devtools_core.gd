extends GutTest

## Pins the CYBER SUNDAY editor-plugin core/ data + helpers (the palette, item placer, level dock and audit
## panel all build on these). Pure logic -- no editor, no tree mutation beyond a throwaway Node graph.

const Catalog := preload("res://addons/cybersunday_tools/core/catalog.gd")
const GroupsReflect := preload("res://addons/cybersunday_tools/core/groups_reflect.gd")
const SceneWalk := preload("res://addons/cybersunday_tools/core/scene_walk.gd")


func test_catalog_is_populated() -> void:
	assert_gt(Catalog.COMPONENTS.size(), 0, "the component catalog should list components")


func test_every_catalog_script_path_resolves() -> void:
	for row in Catalog.COMPONENTS:
		var p: String = row.get("script_path", "")
		assert_true(ResourceLoader.exists(p), "catalog script_path should exist on disk: %s (%s)" % [p, row.get("class_name", "?")])


func test_catalog_scene_paths_resolve_when_set() -> void:
	for row in Catalog.COMPONENTS:
		var p: String = row.get("scene_path", "")
		if p != "":
			assert_true(ResourceLoader.exists(p), "catalog scene_path should exist on disk: %s (%s)" % [p, row.get("class_name", "?")])


func test_catalog_add_mode_is_child_or_instance() -> void:
	for row in Catalog.COMPONENTS:
		var m: String = row.get("add_mode", "")
		assert_true(m == "child" or m == "instance", "add_mode must be 'child' or 'instance', got '%s' for %s" % [m, row.get("class_name", "?")])


func test_catalog_rows_carry_a_category_and_name() -> void:
	for row in Catalog.COMPONENTS:
		assert_ne(String(row.get("class_name", "")), "", "every catalog row needs a class_name")
		assert_ne(String(row.get("category", "")), "", "every catalog row needs a category")


# --- PL2: catalog drift guards (coverage + key_exports / extends validation) ---------------------------------

const KNOWN_DROPPABLES := ["Readable", "Switch", "Claimable", "FallImmunity",
	"RandomCoat", "SprayPaintable", "RandomInventory", "PropFollow",
	"RewardStinger", "CrippleCallout", "NoisePulser", "DebugOverlay",
	"ChessMatch", "ChessVisualizer", "SilentTakedownAbility", "RandomSize",
	"IndoorAmbienceDucker"]


func _catalog_class_names() -> Dictionary:
	var out := {}
	for row in Catalog.COMPONENTS:
		out[String(row.get("class_name", ""))] = true
	return out


func test_catalog_covers_known_droppables() -> void:
	# PL2: these drop-ins were absent from the catalog, so a designer browsing the palette never saw them. Pin their
	# presence so a future edit can't silently drop a droppable back out of the palette.
	var names := _catalog_class_names()
	for cn in KNOWN_DROPPABLES:
		assert_true(names.has(cn), "the catalog must cover the droppable '%s' (else it's invisible in the palette)" % cn)


func test_catalog_class_names_unique() -> void:
	var seen := {}
	for row in Catalog.COMPONENTS:
		var cn := String(row.get("class_name", ""))
		assert_false(seen.has(cn), "duplicate catalog row for class_name '%s'" % cn)
		seen[cn] = true


## All @export/var names across a script's GDScript inheritance chain (its own + every base script), WITHOUT
## instantiating — so a @tool component's _init never runs. Inherited exports (e.g. FallImmunity's `enabled` from
## Ability) are included by walking get_base_script().
func _script_property_names(script: Script) -> Dictionary:
	var names := {}
	var s := script
	while s != null:
		for p in s.get_script_property_list():
			# Only REAL script variables. get_script_property_list also emits @export_group / @export_category
			# pseudo-entries (usage GROUP/CATEGORY, no SCRIPT_VARIABLE bit) whose names ("Actions", the "<file>.gd"
			# category, …) would otherwise pollute the set and let a key_export that happens to match a group label
			# pass without being a real property. Filter to SCRIPT_VARIABLE so the drift guard can't silently pass a ghost.
			if int(p.get("usage", 0)) & PROPERTY_USAGE_SCRIPT_VARIABLE:
				names[String(p.get("name", ""))] = true
		s = s.get_base_script()
	var native := String(script.get_instance_base_type())
	if ClassDB.class_exists(native):
		for p in ClassDB.class_get_property_list(native):
			var name := String(p.get("name", ""))
			if name != "":
				names[name] = true
	return names


func test_catalog_key_exports_exist_on_class() -> void:
	# PL2: every key_export the palette advertises must be a REAL property on the class. Without this, renaming e.g.
	# CanPickUp.loot_table leaves the palette showing a ghost field with a green suite. Reflection over the GDScript
	# chain plus the native base class (no instantiation) so @tool components are safe to check and native inspector
	# knobs such as RigidBody3D.mass can be advertised intentionally.
	for row in Catalog.COMPONENTS:
		var path: String = row.get("script_path", "")
		var script := load(path) as Script
		assert_not_null(script, "catalog script should load: %s" % path)
		if script == null:
			continue
		var props := _script_property_names(script)
		for ex in row.get("key_exports", []):
			assert_true(props.has(String(ex)), "%s.key_exports lists '%s' but no such property exists on the class" % [row.get("class_name", "?"), ex])


## The set of custom (class_name'd GDScript) base names in a script's inheritance chain (LookAtInteractable, Ability, …).
func _custom_base_names(script: Script) -> Dictionary:
	var out := {}
	var s := script.get_base_script()
	while s != null:
		if s.has_method("get_global_name"):
			var gn := String(s.get_global_name())
			if gn != "":
				out[gn] = true
		s = s.get_base_script()
	return out


func test_catalog_extends_matches_base_chain() -> void:
	# PL2: the catalog's `extends` (shown in the palette) must be a real base of the class — a custom class_name in the
	# GDScript chain (LookAtInteractable / Ability), or a native base type (Area3D / Node / Node3D).
	for row in Catalog.COMPONENTS:
		var path: String = row.get("script_path", "")
		var script := load(path) as Script
		if script == null:
			continue
		var declared := String(row.get("extends", ""))
		if declared == "":
			continue
		var custom := _custom_base_names(script)
		var native := String(script.get_instance_base_type())
		var ok := custom.has(declared) or declared == native or (ClassDB.class_exists(declared) and ClassDB.is_parent_class(native, declared))
		assert_true(ok, "%s declares extends '%s' but its base chain is custom=%s native=%s" % [row.get("class_name", "?"), declared, str(custom.keys()), native])


func test_groups_reflect_includes_player_excludes_dead_lowercase() -> void:
	var names := GroupsReflect.allowed_names()
	assert_true(names.has(&"Player"), "the canonical &\"Player\" group should be in the allowed set")
	assert_false(names.has(&"player"), "the dead lowercase &\"player\" group must NOT be a registered name")


func test_scene_walk_collect_all_visits_every_node() -> void:
	var root := Node.new()
	var a := Node.new()
	var b := Node.new()
	root.add_child(a)
	a.add_child(b)  # nested, so a flat children loop would miss it
	var all := SceneWalk.collect_all(root)
	assert_eq(all.size(), 3, "collect_all should visit root + every descendant")
	root.free()
