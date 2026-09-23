extends GutTest

## NpcData — the data-driven NPC archetype profile (roadmap keystone #1). Tested OFF-TREE: every stamp runs on an
## off-tree NPC (load().new(), so _ready never runs) through npc._apply_profile() directly. This guards the contracts
## the keystone rests on: a blank profile stamps back the NPC's own defaults (the one deliberate exception is the
## archetype HP baseline), a profile is stamped onto the NPC (no profile being a strict no-op, so every existing
## inline-authored scene is unaffected), the full stamp and the additive merge agree on which fields a profile owns,
## and the profile's loot / carried items / BarkSet reach the systems that consume them.

const NPC_PATH := "res://scripts/npc/npc.gd"


func test_a_blank_profile_stamps_back_every_npc_default() -> void:
	# The migration contract: pointing an inline-authored NPC at a BLANK profile must not silently retune it, so every
	# field the stamp writes has to default to what npc.gd defaults to. Driven through the real (full-clobber) stamp
	# against a second untouched NPC, so a default that drifts on EITHER side fails here.
	var reference = load(NPC_PATH).new()
	var n = load(NPC_PATH).new()
	var d := NpcData.new()
	n.profile = d
	n._apply_profile()
	for f in NPC.PROFILE_STAMPED_FIELDS:
		if f == &"max_hp":
			# The one deliberate difference: NpcData authors its own HP baseline (npc_data.gd) while Character's bare
			# code default is a separate, lower number. So no parity here, but a blank profile's HP must be a live body.
			assert_gt(n.max_hp, 0.0, "a blank profile must spawn a living NPC, not one already at 0 HP")
			continue
		assert_eq(n.get(f), reference.get(f),
			"a blank profile changed '%s' from the npc.gd default — migrating a scene onto a profile would silently retune it" % f)
	reference.free()
	n.free()
	d = null


func test_apply_profile_stamps_fields_onto_npc() -> void:
	var n = load(NPC_PATH).new()
	var d := NpcData.new()
	d.display_name = "Boss"
	d.max_hp = 99.0
	d.move_speed = 7.0
	d.miss_chance = 0.5
	d.fire_range = 42.0
	d.disposition = Disposition.Kind.FRIENDLY
	d.threat_response = 1  # FLEE
	d.sitting = true
	d.wanders = true
	n.profile = d
	n._apply_profile()
	assert_eq(n.display_name, "Boss", "profile display_name is stamped onto the NPC")
	assert_almost_eq(n.max_hp, 99.0, 0.0001, "profile max_hp stamped (BEFORE super() would seed hp from it)")
	assert_almost_eq(n.move_speed, 7.0, 0.0001, "profile move_speed stamped")
	assert_almost_eq(n.miss_chance, 0.5, 0.0001, "profile miss_chance stamped")
	assert_almost_eq(n.fire_range, 42.0, 0.0001, "profile fire_range stamped")
	assert_eq(n.disposition, Disposition.Kind.FRIENDLY, "profile disposition stamped")
	assert_eq(n.threat_response, 1, "profile threat_response (int) stamped onto the NPC's ThreatResponse enum field")
	assert_true(n.sitting, "profile sitting stamped")
	assert_true(n.wanders, "profile wanders stamped")
	n.free()
	d = null


func test_apply_profile_null_is_a_noop() -> void:
	# The keystone's safety contract: an NPC with no profile keeps its inline exports untouched, so every
	# existing hand-authored scene behaves exactly as before.
	var n = load(NPC_PATH).new()
	var before_speed: float = n.move_speed
	var before_hp: float = n.max_hp
	var before_sight: float = n.sight_range
	n.profile = null
	n._apply_profile()
	assert_almost_eq(n.move_speed, before_speed, 0.0001, "no profile -> move_speed untouched")
	assert_almost_eq(n.max_hp, before_hp, 0.0001, "no profile -> max_hp untouched")
	assert_almost_eq(n.sight_range, before_sight, 0.0001, "no profile -> sight_range untouched")
	n.free()


# --- Additive profile merge (profile_fills_blanks_only) ----------------------------------------------

func test_apply_profile_clobber_overwrites_inline() -> void:
	# DEFAULT behavior (flag off): the profile is authoritative -- it overwrites an inline tweak. Pins that the
	# refactor didn't change the original all-or-nothing semantics every existing scene relies on.
	var n = load(NPC_PATH).new()
	n.max_hp = 99.0  # an inline per-instance tweak
	var d := NpcData.new()
	d.max_hp = 50.0
	n.profile = d
	n.profile_fills_blanks_only = false
	n._apply_profile()
	assert_almost_eq(n.max_hp, 50.0, 0.0001, "flag off -> the profile (50) clobbers the inline tweak (99), as before")
	n.free()
	d = null


func test_apply_profile_additive_keeps_inline_overrides() -> void:
	# flag ON: a field the instance overrode inline WINS; a field left at the npc default takes the profile value.
	# (npc default max_hp is 4.0 and sight_range 25.0; a blank profile's parity is test_a_blank_profile_stamps_back_every_npc_default.)
	var n = load(NPC_PATH).new()
	n.max_hp = 99.0  # an inline override (!= the npc default 4.0)
	# leave sight_range untouched (== the npc default 25.0)
	var d := NpcData.new()
	d.max_hp = 50.0       # the profile sets the overridden field differently...
	d.sight_range = 88.0  # ...and sets the un-overridden field
	n.profile = d
	n.profile_fills_blanks_only = true
	n._apply_profile()
	assert_almost_eq(n.max_hp, 99.0, 0.0001, "additive: the inline override (99) wins over the profile (50)")
	assert_almost_eq(n.sight_range, 88.0, 0.0001, "additive: a field left at default takes the profile value (88)")
	n.free()
	d = null


## Property names exposed by `obj` (for the stamped-field drift check).
func _prop_names(obj: Object) -> Dictionary:
	var names := {}
	for p in obj.get_property_list():
		names[p.get("name", "")] = true
	return names


func test_profile_stamped_fields_all_resolve_on_npc_and_npcdata() -> void:
	# The additive merge snapshots/restores PROFILE_STAMPED_FIELDS by name via get()/set(); a typo or renamed
	# field would silently fail to preserve an override. Pin every name to a real property on BOTH the NPC and
	# the NpcData it reads from.
	var n = load(NPC_PATH).new()
	var d := NpcData.new()
	var npc_props := _prop_names(n)
	var nd_props := _prop_names(d)
	for f in NPC.PROFILE_STAMPED_FIELDS:
		assert_true(npc_props.has(String(f)), "stamped field '%s' must be a real NPC property" % f)
		assert_true(nd_props.has(String(f)), "stamped field '%s' must be a real NpcData property" % f)
	n.free()
	d = null


## The script properties NpcData and the NPC both declare: every field a profile COULD stamp.
func _shared_profile_props(profile: NpcData, npc_props: Dictionary) -> Array[Dictionary]:
	var shared: Array[Dictionary] = []
	for p in profile.get_property_list():
		if (int(p.usage) & PROPERTY_USAGE_SCRIPT_VARIABLE) != 0 and npc_props.has(String(p.name)):
			shared.append(p)
	return shared


## A copy that later in-place edits can't reach, so a before/after comparison sees real changes only.
func _snapshot(v: Variant) -> Variant:
	if v is Array or v is Dictionary:
		return v.duplicate()
	return v


## A Resource of the exported class `type_name` (a project script class or an engine class), or null.
func _resource_of(type_name: String) -> Variant:
	for g in ProjectSettings.get_global_class_list():
		if String(g["class"]) == type_name:
			return load(String(g["path"])).new()
	if ClassDB.can_instantiate(type_name):
		return ClassDB.instantiate(type_name)
	if ClassDB.is_parent_class("PlaceholderTexture2D", type_name):
		return PlaceholderTexture2D.new()  # an abstract texture slot (popup_positive: Texture)
	return null


## A value of the same type as `v` that is guaranteed to differ from it: the probe the stamp-set tests push through a
## profile or an inline edit. `prop` is NpcData's property-list entry (its class_name picks the Resource to build).
func _differing_value(v: Variant, prop: Dictionary) -> Variant:
	match typeof(v):
		TYPE_BOOL:
			return not v
		TYPE_INT:
			return 1 if v == 0 else 0  # an enum's first two members (disposition, threat_response)
		TYPE_FLOAT:
			return v + 1.25
		TYPE_STRING:
			return v + "_probe"
		TYPE_STRING_NAME:
			return StringName(String(v) + "_probe")
		TYPE_COLOR:
			return Color.WHITE if v != Color.WHITE else Color.BLACK
		TYPE_VECTOR3:
			return v + Vector3(1.0, 2.0, 3.0)
		TYPE_DICTIONARY:
			return {} if not v.is_empty() else {0: 1.5}
		TYPE_ARRAY:
			var out: Array = v.duplicate()  # keeps the element type (item_stacks is Array[ItemStack])
			if out.is_empty():
				var element_script = out.get_typed_script()
				if element_script != null:
					out.append(element_script.new())
				else:
					# An untyped or builtin/engine-class-typed shared array (Array[StringName], Array[Texture2D]): one
					# converted element still differs from the empty default, instead of a null-call crash in the probe.
					out.append(type_convert(1, out.get_typed_builtin()) if out.is_typed() else 1)
			else:
				out.clear()
			return out
		TYPE_NIL:
			return _resource_of(String(prop.get("class_name", "")))
		TYPE_OBJECT:
			return null
	return v


func test_full_stamp_writes_exactly_the_profile_stamped_fields() -> void:
	# PROFILE_STAMPED_FIELDS is what the additive merge snapshots and restores, so it must be the SAME set the full
	# stamp writes. Driven, not read: every property NpcData and the NPC share gets a profile value that differs from
	# the NPC's own, the full stamp runs, and the fields that actually changed must be exactly the listed ones.
	var n = load(NPC_PATH).new()
	var d := NpcData.new()
	var before := {}
	for p in _shared_profile_props(d, _prop_names(n)):
		var field := String(p.name)
		before[field] = _snapshot(n.get(field))
		d.set(field, _differing_value(n.get(field), p))
		assert_ne(d.get(field), before[field], "probe setup: the profile's '%s' must differ from the NPC's before stamping" % field)
	n.profile = d
	n._apply_profile()
	var written := {}
	for field in before:
		if n.get(field) != before[field]:
			written[field] = true
	var listed := {}
	for f in NPC.PROFILE_STAMPED_FIELDS:
		listed[String(f)] = true
	for field in written:
		assert_true(listed.has(field),
			"the full stamp writes '%s' but PROFILE_STAMPED_FIELDS omits it -> the additive merge clobbers an inline override of it" % field)
	for field in listed:
		assert_true(written.has(field),
			"PROFILE_STAMPED_FIELDS lists '%s' but the full stamp never writes it -> a profile's '%s' is silently ignored" % [field, field])
	n.free()
	d = null


func test_additive_merge_keeps_an_inline_override_on_every_shared_field() -> void:
	# profile_fills_blanks_only ON: whatever an instance edited inline must survive its profile, on EVERY field a
	# profile could stamp. A field the stamp writes but the merge forgets to snapshot fails here as the bug a designer
	# would see: a seated townsperson standing back up, a hand-tuned HP reverting to the archetype's.
	var n = load(NPC_PATH).new()
	var d := NpcData.new()
	var inline := {}
	for p in _shared_profile_props(d, _prop_names(n)):
		var field := String(p.name)
		var default_value: Variant = _snapshot(n.get(field))
		n.set(field, _differing_value(n.get(field), p))
		inline[field] = _snapshot(n.get(field))
		assert_ne(inline[field], default_value, "probe setup: the inline edit of '%s' must move it off the npc.gd default" % field)
		d.set(field, _differing_value(inline[field], p))
		assert_ne(d.get(field), inline[field], "probe setup: the profile's '%s' must differ from the inline edit" % field)
	for f in NPC.PROFILE_STAMPED_FIELDS:
		assert_true(inline.has(String(f)), "probe setup: the stamped field '%s' must be among the inline-edited fields" % f)
	n.profile = d
	n.profile_fills_blanks_only = true
	n._apply_profile()
	for field in inline:
		assert_eq(n.get(field), inline[field], "the additive merge overwrote the inline override on '%s' with the profile's value" % field)
	n.free()
	d = null


# --- BarkSet (per-archetype bark lines carried by NpcData.bark_set) ----------------------------------

func test_bark_pool_prefers_override_else_fallback() -> void:
	# Per-category resolution (static): a non-empty override wins; an empty override falls back to the default.
	var fallback: Array[String] = ["default"]
	var custom: Array[String] = ["custom"]
	var empty: Array[String] = []
	assert_eq(NPC._bark_pool(fallback, custom), custom, "a non-empty override pool wins over the default")
	assert_eq(NPC._bark_pool(fallback, empty), fallback, "an empty override falls back to the default pool")


func test_pick_bark_draws_from_the_resolved_pool() -> void:
	var only_default: Array[String] = ["only-default"]
	var only_custom: Array[String] = ["only-custom"]
	var empty: Array[String] = []
	assert_eq(NPC._pick_bark(only_default, only_custom), "only-custom", "picks from the override when it has lines")
	assert_eq(NPC._pick_bark(only_default, empty), "only-default", "picks from the default when the override is empty")
	assert_eq(NPC._pick_bark(empty, empty), "", "no lines anywhere -> empty string (safe)")


func test_a_profile_bark_set_is_what_the_npc_voice_speaks_from() -> void:
	# NpcData.bark_set reaches the NPC through _build_components, which hands it to the NpcVoice child every bark picks
	# its line from. Off-tree (no _ready): _build_components is called directly, as tests/test_npc.gd does.
	var raider_barks := BarkSet.new()
	var pardon: Array[String] = ["raider pardon line"]
	raider_barks.pardon = pardon
	var d := NpcData.new()
	d.bark_set = raider_barks
	var n = load(NPC_PATH).new()
	n.profile = d
	n._build_components()
	assert_true(n._voice._bark_set == raider_barks, "a profiled NPC's voice speaks from the profile's BarkSet")
	# A real consumer of the voice's BarkSet: the holster-pardon pool resolves through _voice._bark_set.
	assert_eq(n._pardon_lines(false), pardon, "the profiled NPC's pardon pool is the archetype's line")
	n.free()
	# Control: a profile that carries NO BarkSet leaves the voice on the shipped default lines, never on null.
	var plain := NpcData.new()
	var m = load(NPC_PATH).new()
	m.profile = plain
	m._build_components()
	assert_true(m._voice._bark_set == load("res://resources/barks/default_barks.tres"),
		"a profile without a BarkSet keeps the shared default_barks lines")
	m.free()
	d = null
	plain = null
	raider_barks = null


# --- Authored profile round-trip ---------------------------------------------------------------------

## The property keys an authored .tres sets in its [resource] block, mapped to their raw value text.
func _authored_resource_keys(path: String) -> Dictionary:
	var keys := {}
	var in_resource := false
	for line in FileAccess.get_file_as_string(path).split("\n"):
		var trimmed := line.strip_edges()
		if trimmed.begins_with("["):
			in_resource = trimmed == "[resource]"
			continue
		var eq := trimmed.find(" = ")
		if in_resource and eq > 0:
			keys[trimmed.substr(0, eq)] = trimmed.substr(eq + 3)
	keys.erase("script")
	return keys


func test_authored_default_profile_tres_loads_and_keeps_defaults() -> void:
	# End-to-end: the copy-able archetype template deserializes as NpcData, every value it AUTHORS arrives (a
	# referenced faction included), and every stamped field it leaves UNSET keeps the NpcData default, so a profile
	# changes only what it explicitly authors. The authored set is read from the template's own [resource] block,
	# so retuning a value never breaks this. A value this line parser can't evaluate on its own (any Ext/SubResource
	# reference, bare or inside a typed array; a multi-line dictionary) is only checked to have loaded.
	const TEMPLATE := "res://resources/characters/DefaultCharacterRes.tres"
	var d = load(TEMPLATE)
	assert_true(d is NpcData, "DefaultCharacterRes.tres deserializes as an NpcData")
	var authored := _authored_resource_keys(TEMPLATE)
	assert_gt(authored.size(), 0, "sanity: the parser found the template's [resource] block and at least one authored key")
	var live_props := _prop_names(d)
	for key: String in authored:
		assert_true(live_props.has(key),
			"the template authors '%s' but NpcData no longer declares it (a stale key silently drops on load)" % key)
		var text: String = authored[key]
		if text.contains("Resource("):
			# Checked BEFORE str_to_var, which would try to load a resource id as a res:// path and push engine errors.
			assert_true(d.get(key) != null, "the authored reference '%s' loads, not null (%s)" % [key, text])
			continue
		var parsed: Variant = str_to_var(text)
		if typeof(parsed) == TYPE_NIL and text != "null":
			continue  # a multi-line or otherwise unparseable literal: the line parser only saw its first line
		if typeof(parsed) == TYPE_FLOAT:
			var loaded: float = d.get(key)
			var written: float = parsed
			assert_almost_eq(loaded, written, 0.0001, "the authored '%s' loads as written (%s)" % [key, text])
		else:
			assert_eq(d.get(key), parsed, "the authored '%s' loads as written (%s)" % [key, text])
	var fresh := NpcData.new()
	for f in NPC.PROFILE_STAMPED_FIELDS:
		if not authored.has(String(f)):
			assert_eq(d.get(f), fresh.get(f), "the template leaves '%s' unset, so it keeps the NpcData default" % f)
	fresh = null


# --- Carried inventory (item_stacks: the DETERMINISTIC items the NPC holds, vs the random loot table) ---

func test_apply_profile_stamps_item_stacks() -> void:
	var n = load(NPC_PATH).new()
	var d := NpcData.new()
	var keycard := Item.new()
	keycard.id = &"keycard"
	var stack := ItemStack.new()
	stack.item = keycard
	var carried: Array[ItemStack] = [stack]
	d.item_stacks = carried
	n.profile = d
	n._apply_profile()
	assert_eq(n.item_stacks.size(), 1, "the profile's carried item stacks are stamped onto the NPC")
	assert_eq(n.item_stacks[0].item, keycard, "...the same item the profile authored")
	n.free()
	d = null
	keycard = null


func test_seed_carried_items_fills_the_backpack_weapons_unique() -> void:
	# _seed_carried_items adds the authored carried items to the backpack. Off-tree: a hand-set inventory, no
	# _ready. Non-weapons are seeded as the shared item; weapons are duplicated to unique instances.
	var n = load(NPC_PATH).new()
	n.inventory = CharacterInventory.new()
	var keycard := Item.new()
	keycard.id = &"keycard"
	var spare_gun := Item.new()
	spare_gun.category = Item.Category.WEAPON
	spare_gun.weapon = WeaponData.new()
	var keycard_stack := ItemStack.new()
	keycard_stack.item = keycard
	var gun_stack := ItemStack.new()
	gun_stack.item = spare_gun
	var carried: Array[ItemStack] = [keycard_stack, gun_stack]
	n.item_stacks = carried
	n._seed_carried_items()
	assert_eq(n.inventory.count_of(keycard), 1, "a non-weapon carried item is seeded as the shared item")
	assert_eq(n.inventory.count_of(spare_gun), 0,
		"a carried weapon is duplicated — the shared template isn't in the bag")
	assert_eq(n.inventory.contents().size(), 2, "2 stacks: the keycard + 1 unique weapon instance")
	n.inventory.free()
	n.free()
	keycard = null
	spare_gun = null


# --- Inline loot table (loot on the NPC node itself, for a non-profiled NPC) -------------------------

func _loot_table_for(item: Item) -> LootTable:
	var entry := LootEntry.new()
	entry.item = item
	entry.chance = 1.0  # always drops -> deterministic (loot_table.gd: chance 1.0 always)
	entry.min_count = 1
	entry.max_count = 1
	var entries: Array[LootEntry] = [entry]
	var table := LootTable.new()
	table.entries = entries
	return table


func test_roll_loot_uses_inline_table_when_no_profile() -> void:
	# A non-profiled NPC can now roll an inline `loot` table (previously loot was profile-only).
	var n = load(NPC_PATH).new()
	n.inventory = CharacterInventory.new()
	var drop := Item.new()
	drop.id = &"inline_drop"
	n.loot = _loot_table_for(drop)
	n._roll_loot()
	assert_eq(n.inventory.count_of(drop), 1, "no profile -> the inline `loot` table is rolled into the bag")
	n.inventory.free()
	n.free()
	drop = null


func test_roll_loot_profile_table_wins_over_inline() -> void:
	# The all-or-nothing profile contract: with a profile assigned, profile.loot wins and the inline table is
	# ignored (both set), exactly like the other profile-driven fields.
	var n = load(NPC_PATH).new()
	n.inventory = CharacterInventory.new()
	var inline_drop := Item.new()
	inline_drop.id = &"inline_drop"
	var profile_drop := Item.new()
	profile_drop.id = &"profile_drop"
	n.loot = _loot_table_for(inline_drop)
	var d := NpcData.new()
	d.loot = _loot_table_for(profile_drop)
	n.profile = d
	n._roll_loot()
	assert_eq(n.inventory.count_of(profile_drop), 1, "a profile's loot table wins")
	assert_eq(n.inventory.count_of(inline_drop), 0, "the inline table is ignored when a profile is assigned")
	n.inventory.free()
	n.free()
	d = null
	inline_drop = null
	profile_drop = null
