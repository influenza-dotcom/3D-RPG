extends GutTest

## PartLibrary (scripts/components/part_library.gd): the disk-backed part library behind the `apply_*_part` PICK
## dropdowns on BodyModelSwap and NpcLook. Covers four things the design leans on:
##   1. the folder scan (ids / ids_csv / option_for) and its SOFT failures,
##   2. the CONTENT guards -- every part file's internal id matches its filename, and the player catalog really
##      does reference the shared resources/parts/ files rather than re-inlining sub-resources,
##   3. the field-name table, including the swap-vs-look asymmetry, REFLECTED against the real classes so a
##      renamed seat field fails here instead of silently stamping into nothing,
##   4. stamping: model + seat land together, unknown ids write nothing, and the pick field is MOMENTARY (it
##      always reads back "", which is what keeps it out of every saved .tscn/.tres).
##
## Everything is built OFF-TREE (load(path).new() without add_child) per CLAUDE.md -- no NPC/BodyModelSwap _ready
## runs, and _rebuild() early-returns on `not is_inside_tree()`, so no model is ever instanced here.

const PartLibrary = preload("res://scripts/components/part_library.gd")
const BMS_PATH := "res://scripts/components/body_model_swap.gd"

## First entry in get_property_list() whose name matches, else {}. _validate_property runs during
## get_property_list() at RUNTIME too (it is not gated by is_editor_hint), so the dropdown hints are testable
## off-tree -- the tests/test_faction.gd idiom.
func _property(obj: Object, prop_name: String) -> Dictionary:
	for p in obj.get_property_list():
		if p.get("name", "") == prop_name:
			return p
	return {}

## A part whose MODEL failed to import (the .blend parts on a machine with no Blender import path configured)
## can't be asserted against -- report and skip rather than going red on a Blender-less clone.
func _importable(slot: StringName, id: String) -> CharacterPartOption:
	var opt := PartLibrary.option_for(slot, id)
	if opt == null:
		gut.p("skipping part '%s/%s' -- it did not resolve (model import unavailable on this machine?)" % [slot, id])
	return opt

# --- 1-2: the folder scan -----------------------------------------------------------------------------------

func test_ids_are_sorted_and_ship_the_seeded_parts() -> void:
	var heads := PartLibrary.ids(PartLibrary.SLOT_HEADS)
	for want in ["chrysalis", "head", "headblue", "kyle", "spiky"]:
		assert_true(heads.has(want), "resources/parts/heads/ ships '%s.tres', got %s" % [want, heads])
	var sorted_heads := PackedStringArray(heads)
	sorted_heads.sort()
	assert_eq(Array(heads), Array(sorted_heads), "ids() returns the slot's parts SORTED (the dropdown order)")
	for slot in [PartLibrary.SLOT_BODIES, PartLibrary.SLOT_ARMS, PartLibrary.SLOT_LEGS]:
		assert_true(PartLibrary.ids(slot).has("standard"),
			"resources/parts/%s/ ships 'standard.tres', got %s" % [slot, PartLibrary.ids(slot)])

func test_missing_slot_and_missing_id_are_soft() -> void:
	assert_eq(PartLibrary.ids(&"nope").size(), 0, "a slot folder that doesn't exist scans to empty, never an error")
	assert_eq(PartLibrary.ids_csv(&"nope"), "", "an empty slot yields an empty hint_string (a blank dropdown)")
	assert_null(PartLibrary.option_for(PartLibrary.SLOT_HEADS, ""),
		"the momentary field's rest value ('') resolves to null SILENTLY -- it is not a mis-pick")
	assert_null(PartLibrary.option_for(PartLibrary.SLOT_HEADS, "definitely_not_a_head"),
		"an unknown id resolves to null so nothing is stamped")

# --- 3-5: content guards ------------------------------------------------------------------------------------

func test_every_part_id_matches_its_filename_and_is_valid() -> void:
	# The library keys on the FILENAME while CharacterPartOption carries its own `id` (which a save stores), so a
	# copy-pasted .tres whose internal id drifted would list under one name and persist another's.
	for slot in [PartLibrary.SLOT_BODIES, PartLibrary.SLOT_HEADS, PartLibrary.SLOT_ARMS, PartLibrary.SLOT_LEGS]:
		var ids := PartLibrary.ids(slot)
		assert_gt(ids.size(), 0, "slot '%s' ships at least one part" % slot)
		var seen := {}
		var valid := 0
		for id in ids:
			assert_false(seen.has(id), "part id '%s' appears once in slot '%s'" % [id, slot])
			seen[id] = true
			var opt := _importable(slot, id)
			if opt == null:
				continue
			valid += 1
			assert_eq(String(opt.id), id,
				"part '%s/%s.tres' must carry the matching internal id" % [slot, id])
			assert_true(opt.is_valid(), "part '%s/%s.tres' resolves to a renderable option" % [slot, id])
		assert_gt(valid, 0, "slot '%s' has at least one part that actually resolves" % slot)

func test_the_authored_catalog_references_the_shared_part_files() -> void:
	# ONE source of truth: the player character-creation catalog must point at resources/parts/*.tres, the same
	# files the NPC pickers offer. Fails loudly if anyone re-inlines a [sub_resource] into the catalog.
	CharacterAppearanceCatalog.reset_cache()
	var cat := CharacterAppearanceCatalog.get_catalog()
	assert_not_null(cat, "the appearance catalog resolves")
	for pair in [[cat.valid_heads(), PartLibrary.SLOT_HEADS], [cat.valid_bodies(), PartLibrary.SLOT_BODIES]]:
		var list: Array = pair[0]
		var slot: StringName = pair[1]
		assert_gt(list.size(), 0, "the catalog ships at least one valid %s" % slot)
		for opt in list:
			var path: String = (opt as CharacterPartOption).resource_path
			assert_true(path.begins_with(PartLibrary.PARTS_DIR),
				"catalog %s option '%s' must be an EXTERNAL part file under %s, got '%s'"
					% [slot, (opt as CharacterPartOption).id, PartLibrary.PARTS_DIR, path])
			var stem := path.get_file().get_basename()
			var from_library := PartLibrary.option_for(slot, stem)
			assert_not_null(from_library, "the library resolves the catalog's '%s'" % stem)
			if from_library != null:
				assert_eq(from_library.resource_path, path,
					"the catalog and the library hand back the SAME resource for '%s'" % stem)
	CharacterAppearanceCatalog.reset_cache()

func test_code_fallback_catalog_stays_in_sync_with_the_shipped_parts() -> void:
	# character_appearance_catalog.gd default() is the CODE fallback used only when the authored .tres is missing;
	# its comment says "Keep in sync with the authored .tres". This makes that enforceable instead of aspirational.
	var fallback := CharacterAppearanceCatalog.default()
	for pair in [[fallback.heads, PartLibrary.SLOT_HEADS], [fallback.bodies, PartLibrary.SLOT_BODIES]]:
		var list: Array = pair[0]
		var slot: StringName = pair[1]
		for entry in list:
			var opt := entry as CharacterPartOption
			var lib := _importable(slot, String(opt.id))
			if lib == null or opt.model == null:
				continue
			assert_almost_eq(lib.scale, opt.scale, 0.0001,
				"'%s' scale must match between default() and resources/parts/%s/%s.tres" % [opt.id, slot, opt.id])
			assert_eq(lib.position, opt.position, "'%s' position must match default()" % opt.id)
			assert_eq(lib.rotation, opt.rotation, "'%s' rotation must match default()" % opt.id)
			assert_eq(lib.model.resource_path, opt.model.resource_path,
				"'%s' must point at the same model as default()" % opt.id)
	fallback = null

# --- 6-7: the field-name table ------------------------------------------------------------------------------

func test_fields_for_covers_the_real_field_name_asymmetry() -> void:
	# The two surfaces genuinely disagree, which is the whole reason this table exists.
	assert_eq(PartLibrary.fields_for(PartLibrary.HOST_SWAP, PartLibrary.SLOT_BODIES)["scale"], &"body_model_scale",
		"a BODY's scale is body_model_scale on BOTH surfaces")
	assert_eq(PartLibrary.fields_for(PartLibrary.HOST_SWAP, PartLibrary.SLOT_HEADS)["scale"], &"head_scale",
		"a HEAD's scale is head_scale on BodyModelSwap")
	assert_eq(PartLibrary.fields_for(PartLibrary.HOST_LOOK, PartLibrary.SLOT_HEADS)["scale"], &"head_model_scale",
		"...but head_model_scale on NpcLook -- the asymmetry fields_for exists to absorb")
	assert_true(PartLibrary.fields_for(PartLibrary.HOST_LOOK, PartLibrary.SLOT_ARMS).is_empty(),
		"NpcLook carries no arm model, so an arms pick on a look is a no-op by construction")
	assert_true(PartLibrary.fields_for(PartLibrary.HOST_LOOK, PartLibrary.SLOT_LEGS).is_empty(),
		"NpcLook carries no leg model either")
	assert_true(PartLibrary.fields_for(&"not_a_surface", PartLibrary.SLOT_HEADS).is_empty(),
		"an unknown surface yields no fields rather than a crash")

func test_every_field_name_the_table_returns_actually_exists() -> void:
	# The highest-value guard here: renaming a seat field (head_scale -> head_size, say) would otherwise leave the
	# stamp writing into a property that doesn't exist, silently doing half the job.
	var bms = load(BMS_PATH).new()
	var look := NpcLook.new()
	var surfaces := {PartLibrary.HOST_SWAP: bms, PartLibrary.HOST_LOOK: look}
	for host_kind in surfaces:
		var target: Object = surfaces[host_kind]
		var have := {}
		for p in target.get_property_list():
			have[String(p.get("name", ""))] = true
		for slot in [PartLibrary.SLOT_BODIES, PartLibrary.SLOT_HEADS, PartLibrary.SLOT_ARMS, PartLibrary.SLOT_LEGS]:
			var f: Dictionary = PartLibrary.fields_for(host_kind, slot)
			for key in f:
				assert_true(have.has(String(f[key])),
					"fields_for(%s, %s)['%s'] names '%s', which must exist on that class" % [host_kind, slot, key, f[key]])
	bms.free()
	look = null

# --- 8-11: stamping -----------------------------------------------------------------------------------------

func test_stamp_writes_model_and_seat_together() -> void:
	var opt := _importable(PartLibrary.SLOT_HEADS, "chrysalis")
	if opt == null:
		return
	var bms = load(BMS_PATH).new()
	bms.head_model = BoxMesh.new()  # a stand-in "wrong" head at a wrong seat
	bms.head_scale = 9.0
	assert_true(PartLibrary.stamp(bms, PartLibrary.HOST_SWAP, PartLibrary.SLOT_HEADS, "chrysalis"),
		"stamping a known head reports success")
	assert_true(str(bms.head_model.resource_path).ends_with("head_chrysalis.glb"),
		"the part's MODEL landed, got '%s'" % bms.head_model.resource_path)
	assert_almost_eq(bms.head_scale, 0.2436, 0.0001, "the part's fitted SCALE landed with it")
	assert_eq(bms.head_position, Vector3(0, 0.468, 0.1173), "the part's fitted POSITION landed with it")
	assert_eq(bms.head_rotation, Vector3(0, -90, 0), "the part's fitted ROTATION landed with it")
	bms.free()

func test_stamp_of_an_unknown_or_blank_id_changes_nothing() -> void:
	var bms = load(BMS_PATH).new()
	var keep := BoxMesh.new()
	bms.head_model = keep
	bms.head_scale = 9.0
	for bad in ["", "definitely_not_a_head"]:
		assert_false(PartLibrary.stamp(bms, PartLibrary.HOST_SWAP, PartLibrary.SLOT_HEADS, bad),
			"stamping '%s' reports failure" % bad)
		assert_eq(bms.head_model, keep, "an unresolvable id ('%s') must not touch the model" % bad)
		assert_eq(bms.head_scale, 9.0, "an unresolvable id ('%s') must not touch the seat" % bad)
	bms.free()

func test_the_pick_field_is_momentary_and_never_stores() -> void:
	# Always reading back "" is what keeps these rows out of every saved .tscn/.tres: Godot's serializer skips
	# default-valued properties, so the pick can never become a second source of truth for what model is in a slot.
	if _importable(PartLibrary.SLOT_HEADS, "chrysalis") != null:
		var bms = load(BMS_PATH).new()
		bms.apply_head_part = "chrysalis"
		assert_almost_eq(bms.head_scale, 0.2436, 0.0001, "assigning apply_head_part stamps the seat")
		assert_eq(bms.apply_head_part, "", "...and the pick row snaps back to empty (momentary)")
		if _importable(PartLibrary.SLOT_ARMS, "standard") != null:
			bms.apply_arm_part = "standard"
			assert_almost_eq(bms.arm_scale, 0.35, 0.0001, "apply_arm_part stamps the arm seat")
			assert_eq(bms.apply_arm_part, "", "the arm pick row is momentary too")
		if _importable(PartLibrary.SLOT_LEGS, "standard") != null:
			bms.apply_leg_part = "standard"
			assert_almost_eq(bms.leg_scale, 0.44, 0.0001, "apply_leg_part stamps the leg seat")
			assert_eq(bms.apply_leg_part, "", "the leg pick row is momentary too")
		bms.free()
	if _importable(PartLibrary.SLOT_HEADS, "spiky") != null:
		var look := NpcLook.new()
		look.apply_head_part = "spiky"
		assert_almost_eq(look.head_model_scale, 0.1199, 0.0001,
			"on a look the seat lands in head_model_scale -- the look's OWN field names")
		assert_eq(look.apply_head_part, "", "the look's pick row is momentary too")
		look = null

func test_whole_body_clears_composed_parts_and_a_body_stamp_clears_planar() -> void:
	var bms = load(BMS_PATH).new()
	bms.head_model = BoxMesh.new()
	bms.arm_model = BoxMesh.new()
	bms.leg_model = BoxMesh.new()
	var whole := CharacterPartOption.new()
	whole.id = &"whole"
	whole.model = SphereMesh.new()
	whole.whole_body = true
	assert_true(PartLibrary.stamp_option(bms, PartLibrary.HOST_SWAP, PartLibrary.SLOT_BODIES, whole),
		"a whole_body option stamps onto the body slot")
	for gone in ["head_model", "arm_model", "leg_model"]:
		assert_null(bms.get(gone),
			"a whole_body model IS the character, so the composed '%s' must be cleared or it renders inside it" % gone)
	# A plain (composing) body clears the planar shirt projection: that is for a player-DRAWN texture only, and an
	# authored part texture is painted FOR the mesh's own UV atlas.
	bms.body_texture_planar = true
	var plain := CharacterPartOption.new()
	plain.id = &"plain"
	plain.model = BoxMesh.new()
	assert_true(PartLibrary.stamp_option(bms, PartLibrary.HOST_SWAP, PartLibrary.SLOT_BODIES, plain),
		"a plain body option stamps")
	assert_false(bms.body_texture_planar, "a body stamp clears body_texture_planar")
	whole = null
	plain = null
	bms.free()

func test_stamp_onto_a_look_uses_the_looks_own_field_names() -> void:
	var opt := _importable(PartLibrary.SLOT_HEADS, "chrysalis")
	if opt == null:
		return
	var look := NpcLook.new()
	assert_true(PartLibrary.stamp(look, PartLibrary.HOST_LOOK, PartLibrary.SLOT_HEADS, "chrysalis"),
		"stamping a head onto a look reports success")
	assert_almost_eq(look.head_model_scale, 0.2436, 0.0001, "the look's head seat is head_model_scale")
	assert_eq(look.head_model_position, Vector3(0, 0.468, 0.1173), "...head_model_position")
	assert_eq(look.head_model_rotation, Vector3(0, -90, 0), "...and head_model_rotation")
	assert_false(PartLibrary.stamp(look, PartLibrary.HOST_LOOK, PartLibrary.SLOT_ARMS, "standard"),
		"a look has no arm model, so an arms pick reports failure and writes nothing")
	look = null

# --- 12: the dropdowns are live -----------------------------------------------------------------------------

func test_pick_dropdowns_are_dynamic() -> void:
	# hint_string is compared against a LIVE recompute, never a hardcoded list -- adding a part .tres must never
	# require editing this test (that is the whole point of the disk-backed scan).
	var bms = load(BMS_PATH).new()
	var swap_rows := {
		"apply_body_part": PartLibrary.SLOT_BODIES,
		"apply_head_part": PartLibrary.SLOT_HEADS,
		"apply_arm_part": PartLibrary.SLOT_ARMS,
		"apply_leg_part": PartLibrary.SLOT_LEGS,
	}
	for row in swap_rows:
		var prop := _property(bms, row)
		assert_false(prop.is_empty(), "BodyModelSwap exposes a '%s' pick row" % row)
		assert_eq(prop.get("hint", -1), PROPERTY_HINT_ENUM_SUGGESTION,
			"BodyModelSwap.%s is a suggestion dropdown (editable, so a free-typed id is harmless)" % row)
		assert_eq(prop.get("hint_string", ""), PartLibrary.ids_csv(swap_rows[row]),
			"BodyModelSwap.%s lists the live folder scan for its slot" % row)
	bms.free()
	var look := NpcLook.new()
	var look_rows := {"apply_body_part": PartLibrary.SLOT_BODIES, "apply_head_part": PartLibrary.SLOT_HEADS}
	for row in look_rows:
		var prop := _property(look, row)
		assert_false(prop.is_empty(), "NpcLook exposes a '%s' pick row" % row)
		assert_eq(prop.get("hint", -1), PROPERTY_HINT_ENUM_SUGGESTION,
			"NpcLook.%s is a suggestion dropdown" % row)
		assert_eq(prop.get("hint_string", ""), PartLibrary.ids_csv(look_rows[row]),
			"NpcLook.%s lists the live folder scan for its slot" % row)
	assert_true(_property(look, "apply_arm_part").is_empty(),
		"NpcLook must NOT offer a limb pick row -- it has no limb model to stamp into")
	look = null
