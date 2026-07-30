extends RefCounted
## Character-part LIBRARY: the disk-backed source for the `apply_*_part` pick dropdowns on BodyModelSwap and
## NpcLook, so changing an NPC's head is picking a name in the inspector instead of dragging a .glb out of the
## file explorer and then hand-dialling its scale / position / rotation (every model has its own native size,
## origin and facing -- the shipped heads sit at 0.205 / 0.4183 / 0.1199 / 0.2436 with OPPOSING yaws).
##
## AUTHORING-TIME ONLY -- nothing here is read at runtime. A pick is STAMPED: it copies the part's model + seat
## into the target's OWN exports and forgets the id. So there is no new load path, no save-format change, no
## precedence rule layered onto _host_part, and renaming or deleting a part file can never retroactively change an
## already-authored NPC. Delete res://resources/parts/ entirely and every NPC still renders exactly as it does now.
##
## LAYOUT: resources/parts/<slot>/<id>.tres, one CharacterPartOption per file, id == filename. The FOLDER is the
## scope -- resources/parts/heads/ physically cannot offer ak47.glb, which is why there is no filename heuristic
## (the asset library's `stupidbody` / `Man.glb` / `weirdo` / `model.obj` defeat every one). Adding a head is:
## duplicate a part .tres, set id + display_name, drag the model in ONCE. The dropdown picks it up with no restart.
##
## These are the SAME files the player character-creation catalog references (resources/characters/
## PlayerAppearanceCatalog.tres holds ext_resource rows into resources/parts/), so the creator and the NPC picker
## read one source of truth. Dropping a part into a slot folder reaches the NPC picker immediately but NOT the
## player creator -- that reads the catalog's `heads` array, so add it there too if players should get it.
##
## Preloaded as a const where needed (NO class_name on purpose -> nothing for the test suite's global script
## class cache to miss; the scripts/faction/factions.gd convention). It never references BodyModelSwap or NpcLook
## by type -- targets are duck-typed Objects and the field names come from fields_for -- so it can be preloaded
## from either of them without a script-cycle.

const ModelResourceUtil = preload("res://scripts/components/model_resource.gd")

const PARTS_DIR := "res://resources/parts/"

## The slot ids ARE the folder names under PARTS_DIR.
const SLOT_BODIES := &"bodies"
const SLOT_HEADS := &"heads"
const SLOT_ARMS := &"arms"
const SLOT_LEGS := &"legs"

## Which surface is being stamped. The two disagree on field names (a head's scale is `head_scale` on the swap but
## `head_model_scale` on the look), and NpcLook carries no limb models at all -- fields_for absorbs both.
const HOST_SWAP := &"swap"
const HOST_LOOK := &"look"

## Slot -> the seat field names on each surface. Every value here is asserted to exist on the real class by
## tests/test_part_library.gd, so renaming a seat field fails a test instead of silently stamping into nothing.
const FIELDS := {
	HOST_SWAP: {
		SLOT_BODIES: {"model": &"body_model", "scale": &"body_model_scale", "pos": &"body_model_position", "rot": &"body_model_rotation", "tex": &"body_texture"},
		SLOT_HEADS: {"model": &"head_model", "scale": &"head_scale", "pos": &"head_position", "rot": &"head_rotation", "tex": &"head_texture"},
		SLOT_ARMS: {"model": &"arm_model", "scale": &"arm_scale", "pos": &"arm_position", "rot": &"arm_rotation", "tex": &"arm_texture"},
		SLOT_LEGS: {"model": &"leg_model", "scale": &"leg_scale", "pos": &"leg_position", "rot": &"leg_rotation", "tex": &"leg_texture"},
	},
	HOST_LOOK: {
		SLOT_BODIES: {"model": &"body_model", "scale": &"body_model_scale", "pos": &"body_model_position", "rot": &"body_model_rotation", "tex": &"body_texture"},
		SLOT_HEADS: {"model": &"head_model", "scale": &"head_model_scale", "pos": &"head_model_position", "rot": &"head_model_rotation", "tex": &"head_texture"},
		# NpcLook deliberately carries NO arm/leg models -- the limbs swing with the gait and stay the
		# BodyModelSwap child's. An empty table makes an arms/legs pick on a look a silent no-op by construction.
	},
}

## The folder a slot's part files live in.
static func slot_dir(slot: StringName) -> String:
	return PARTS_DIR + String(slot) + "/"

## Every part id available on disk for `slot`: the .tres/.res filenames (sans extension) under its folder, sorted
## and de-duped. A missing folder yields empty (never an error) -- the library is optional by design. `.remap` is
## trimmed FIRST so an exported build's `head.tres.remap` still reads as `head`.
static func ids(slot: StringName) -> PackedStringArray:
	var out := PackedStringArray()
	var dir := DirAccess.open(slot_dir(slot))
	if dir == null:
		return out
	for raw in dir.get_files():
		var f: String = raw.trim_suffix(".remap")
		for ext in [".tres", ".res"]:
			if f.ends_with(ext):
				var pid := f.trim_suffix(ext)
				if not out.has(pid):
					out.append(pid)
				break
	out.sort()
	return out

## A slot's ids as a comma-separated string -- the hint_string for a PROPERTY_HINT_ENUM_SUGGESTION dropdown.
## Called from _validate_property, so the list is a LIVE folder scan: drop a .tres in and it appears with no
## editor restart (the Factions.ids_csv idiom).
static func ids_csv(slot: StringName) -> String:
	return ",".join(ids(slot))

## The CharacterPartOption for `id` in `slot`, or null. Empty id -> null SILENTLY (the momentary field's rest
## value). A missing file / wrong resource class / a part that can't render (is_valid: blank internal id or an
## unloadable model) -> a warning and null, so a .blend part on a machine without Blender import configured
## degrades to "nothing happened" instead of stamping a null model over a working head.
static func option_for(slot: StringName, id: String) -> CharacterPartOption:
	if id.is_empty():
		return null
	for ext in [".tres", ".res"]:
		var path: String = slot_dir(slot) + id + ext
		if not ResourceLoader.exists(path):
			continue
		var res := load(path)
		if not (res is CharacterPartOption):
			push_warning("PartLibrary: '%s' is not a CharacterPartOption -- ignored." % path)
			return null
		var opt := res as CharacterPartOption
		if not opt.is_valid():
			push_warning("PartLibrary: part '%s' can't render (blank id, or its model failed to import) -- nothing stamped." % path)
			return null
		if opt.id != StringName(id):
			# The dropdown and every lookup key on the FILENAME, so a copy-pasted .tres whose internal id drifted
			# would show under one name and save another's id into the player's appearance. Warn loudly.
			push_warning("PartLibrary: '%s' has internal id '%s' (the library keys on the filename '%s')." % [path, opt.id, id])
		return opt
	push_warning("PartLibrary: no part '%s' under %s -- nothing stamped." % [id, slot_dir(slot)])
	return null

## The seat field names for one (surface, slot) pair, or {} when that surface has no such slot (arms/legs on a
## look). Keys: "model", "scale", "pos", "rot", "tex".
static func fields_for(host_kind: StringName, slot: StringName) -> Dictionary:
	var by_slot: Dictionary = FIELDS.get(host_kind, {})
	return by_slot.get(slot, {})

## Copy `opt`'s model AND its seat (scale / position / rotation / texture) onto `target`. Returns false and writes
## NOTHING when the option is null or the surface has no such slot.
##
## ORDER MATTERS. The model is written LAST because BodyModelSwap's model setters fire _rebuild(); writing the
## seat first means the single rebuild already sees the final numbers instead of re-instancing at the old seat.
## Before anything is written, the OUTGOING values are printed to the Output panel -- a momentary pick has no
## per-property undo, so that print IS the recovery path (copy the numbers back).
static func stamp_option(target: Object, host_kind: StringName, slot: StringName, opt: CharacterPartOption) -> bool:
	if target == null or opt == null:
		return false
	var f := fields_for(host_kind, slot)
	if f.is_empty():
		return false
	var have := _property_names(target)
	if Engine.is_editor_hint():
		_print_outgoing(target, host_kind, slot, f, have)
		_warn_if_look_overrides(target, host_kind, slot)
	# whole_body (bodies only): this model IS a complete character, so the separately-composed parts must go, or
	# a floating head + limbs render inside it. Mirrors what the player customizer's configure_swap already does.
	if slot == SLOT_BODIES and opt.whole_body:
		for gone in [&"head_model", &"arm_model", &"leg_model"]:
			if have.has(gone):
				target.set(gone, null)
	if have.has(f["scale"]):
		target.set(f["scale"], opt.scale)
	if have.has(f["pos"]):
		target.set(f["pos"], opt.position)
	if have.has(f["rot"]):
		target.set(f["rot"], opt.rotation)
	if have.has(f["tex"]):
		target.set(f["tex"], opt.texture)
	# A body stamp clears the PLANAR shirt projection: it is turned on only for a player-DRAWN t-shirt, and a
	# baked/authored part texture is painted FOR the mesh's own UV atlas, so leaving it on shreds the new skin.
	if slot == SLOT_BODIES and have.has(&"body_texture_planar"):
		target.set(&"body_texture_planar", false)
	target.set(f["model"], opt.model)  # LAST: the one _rebuild() this fires already sees the final seat
	return true

## stamp_option by part id -- what the `apply_*_part` dropdowns call. False (and nothing written) for a blank or
## unknown id, so typing free text into the editable suggestion box can never blank a working part.
static func stamp(target: Object, host_kind: StringName, slot: StringName, part_id: String) -> bool:
	return stamp_option(target, host_kind, slot, option_for(slot, part_id))

## The property names `target` actually exposes, as a lookup set. Guards every write: NpcLook has no
## `body_texture_planar` and no limb models, and an off-tree test rig may be neither class.
static func _property_names(target: Object) -> Dictionary:
	var out := {}
	for p in target.get_property_list():
		out[StringName(p.get("name", ""))] = true
	return out

## Print the seat this stamp is about to overwrite, in copy-pasteable form. The momentary pick field is a single
## undoable property whose value is always "", so Ctrl+Z cannot restore the five fields the stamp wrote -- this
## print is the recovery path. Editor-only (guarded by the caller).
static func _print_outgoing(target: Object, host_kind: StringName, slot: StringName, f: Dictionary, have: Dictionary) -> void:
	var parts := PackedStringArray()
	if have.has(f["model"]):
		parts.append("model=" + ModelResourceUtil.label(target.get(f["model"]) as Resource))
	for key in ["scale", "pos", "rot"]:
		if have.has(f[key]):
			parts.append("%s=%s" % [key, target.get(f[key])])
	if have.has(f["tex"]):
		parts.append("tex=" + ModelResourceUtil.label(target.get(f["tex"]) as Resource))
	print_rich("[b]PartLibrary[/b] %s %s was: %s [i](no undo -- copy these back if you mis-picked)[/i]"
		% [host_kind, slot, " ".join(parts)])

## A pick on a BodyModelSwap is a SILENT no-op when the host NPC's `look` sets that same part's model -- the look
## wins (BodyModelSwap._host_part). Say so rather than letting the designer stamp into a field nothing reads.
## Editor-only (guarded by the caller); a look-less host, a non-Node target, or an arms/legs slot falls straight
## through (a look carries no limb models, so it can never shadow those).
##
## The look is read DUCK-TYPED, never as `is NpcLook`: npc_look.gd preloads THIS script for its own pick rows, so
## naming the class here would close a class_name<->preload parse cycle. A Resource that answers to the slot's
## look-side model field with a real model IS the override, whatever its class.
static func _warn_if_look_overrides(target: Object, host_kind: StringName, slot: StringName) -> void:
	if host_kind != HOST_SWAP:
		return
	var node := target as Node
	if node == null:
		return
	var host := node.get_parent()
	if host == null:
		return
	var lk: Variant = host.get(&"look")
	if not (lk is Resource):
		return
	var look_fields := fields_for(HOST_LOOK, slot)
	if look_fields.is_empty():
		return
	if not ModelResourceUtil.is_model((lk as Resource).get(look_fields["model"])):
		return
	push_warning(("PartLibrary: '%s' on %s sets this %s -- the LOOK WINS, so this pick will not show. " +
		"Pick on the look resource instead (or clear its %s).")
		% [ModelResourceUtil.label(lk as Resource), host.name, slot, look_fields["model"]])
