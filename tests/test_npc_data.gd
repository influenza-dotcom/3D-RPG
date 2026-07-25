extends GutTest

## NpcData — the data-driven NPC archetype profile (roadmap keystone #1). Pure Resource, tested OFF-TREE:
## NpcData.new() for the default-parity check; the stamp path uses an off-tree NPC (load().new(), so _ready
## never runs) and calls npc._apply_profile() directly. This guards the two contracts the keystone rests on:
## a fresh profile reproduces the NPC's own defaults, and a profile is stamped onto the NPC (with no profile
## being a strict no-op, so every existing inline-authored scene is unaffected).

const NPC_PATH := "res://scripts/npc/npc.gd"


func test_npcdata_defaults_match_npc_export_defaults() -> void:
	# A fresh profile must reproduce npc.gd's own export defaults, so assigning a "blank" profile is a no-op
	# in effect — otherwise migrating a scene to a profile would silently shift its stats.
	var d := NpcData.new()
	assert_eq(d.disposition, Disposition.Kind.HOSTILE,
		"default disposition HOSTILE — a fresh profile is a plain enemy, matching npc.gd")
	assert_eq(d.threat_response, 0, "default threat_response 0 == ThreatResponse.FIGHT")
	assert_almost_eq(d.max_hp, 10.0, 0.0001, "default max_hp 10.0 — NpcData's own authored NPC baseline (an NpcData-spawned NPC stamps this at spawn; Character's bare code default is a separate 4.0)")
	assert_almost_eq(d.move_speed, 4.0, 0.0001, "default move_speed 4.0 matches npc.gd")
	assert_almost_eq(d.sight_range, 25.0, 0.0001, "default sight_range 25.0 matches npc.gd")
	assert_almost_eq(d.friendly_aggro_threshold, 8.0, 0.0001, "default friendly_aggro_threshold 8.0 matches npc.gd")
	assert_true(d.show_laser, "default show_laser true matches npc.gd")
	assert_eq(d.weapon_data, null, "no weapon by default (a civilian profile)")
	assert_eq(d.faction, null, "no faction by default")
	assert_false(d.sitting, "default sitting false matches npc.gd")
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
	# (npc default max_hp is 4.0 and sight_range 25.0 -- see test_npcdata_defaults_match_npc_export_defaults.)
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


func test_stamp_profile_full_matches_stamped_array_both_ways() -> void:
	# M7: three lists must stay in lockstep — NpcData exports, _stamp_profile_full's `X = profile.X` assignments, and
	# PROFILE_STAMPED_FIELDS (which the additive-merge snapshot/restore iterates). The test above pins array -> property;
	# THIS pins _stamp_profile_full <-> PROFILE_STAMPED_FIELDS by SET-EQUALITY. A field added to NpcData + the stamp body
	# but forgotten in the array compiles + passes the full-clobber path, yet silently DROPS the inline override on the
	# additive-merge path (no signal). Both directions catch it.
	var src := FileAccess.get_file_as_string(NPC_PATH)
	var start := src.find("func _stamp_profile_full")
	assert_gt(start, -1, "_stamp_profile_full should exist in npc.gd")
	var body_end := src.find("\nfunc ", start + 1)
	var body := src.substr(start, body_end - start) if body_end > start else src.substr(start)
	var re := RegEx.new()
	re.compile("(?m)^\\t(\\w+) = profile\\.\\w+")  # every `<field> = profile.<field>` assignment in the stamp body
	var stamped := {}
	for m in re.search_all(body):
		stamped[m.get_string(1)] = true
	assert_gt(stamped.size(), 50, "sanity: the stamp body should assign ~55 fields (guards against a regex that matched nothing)")
	var listed := {}
	for f in NPC.PROFILE_STAMPED_FIELDS:
		listed[String(f)] = true
	for f in stamped:
		assert_true(listed.has(f), "_stamp_profile_full stamps '%s' but PROFILE_STAMPED_FIELDS omits it -> the additive merge silently clobbers an inline override" % f)
	for f in listed:
		assert_true(stamped.has(f), "PROFILE_STAMPED_FIELDS lists '%s' but _stamp_profile_full doesn't stamp it (stale array entry)" % f)


# --- BarkSet (per-archetype bark lines carried by NpcData.bark_set) ----------------------------------

func test_barkset_categories_default_empty() -> void:
	# Empty means "use the NPC's built-in default lines" — a fresh BarkSet overrides nothing.
	var b := BarkSet.new()
	assert_eq(b.spot.size(), 0, "BarkSet.spot defaults empty -> the NPC's default contact lines are used")
	assert_eq(b.death_ally.size(), 0, "BarkSet.death_ally defaults empty")
	assert_eq(b.greet.size(), 0, "BarkSet.greet defaults empty")
	b = null


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


func test_npcdata_can_carry_a_bark_set() -> void:
	var d := NpcData.new()
	assert_null(d.bark_set, "NpcData.bark_set defaults null -> the NPC uses its built-in default lines")
	d.bark_set = BarkSet.new()
	assert_not_null(d.bark_set, "a profile can carry a BarkSet to override bark lines per archetype")
	d = null


# --- Authored profile round-trip ---------------------------------------------------------------------

func test_authored_default_profile_tres_loads_and_keeps_defaults() -> void:
	# End-to-end: an authored .tres deserializes as NpcData, its set fields (incl. a referenced faction) load,
	# and UNSET fields keep their defaults — so a profile changes only what it explicitly authors.
	var d = load("res://resources/characters/DefaultCharacterRes.tres")
	assert_not_null(d, "DefaultCharacterRes.tres loads (a copy-able archetype template)")
	assert_true(d is NpcData, "DefaultCharacterRes.tres deserializes as an NpcData")
	assert_eq(d.display_name, "Default", "authored display_name loads from the .tres")
	assert_almost_eq(d.max_hp, 14.0, 0.0001, "authored max_hp loads")
	assert_almost_eq(d.move_speed, 4.5, 0.0001, "authored move_speed loads")
	assert_almost_eq(d.miss_chance, 0.15, 0.0001, "authored miss_chance loads")
	assert_almost_eq(d.outline_width, 2.0, 0.0001, "authored outline_width loads")
	assert_not_null(d.faction, "an authored faction reference (townsfolk.tres) loads as a Faction")
	assert_eq(d.disposition, Disposition.Kind.HOSTILE, "an UNSET field keeps its NpcData default (HOSTILE)")
	assert_eq(d.weapon_data, null, "unset weapon_data stays null (no weapon authored)")


# --- Carried inventory (item_stacks: the DETERMINISTIC items the NPC holds, vs the random loot table) ---

func test_npcdata_item_stacks_default_empty() -> void:
	var d := NpcData.new()
	assert_eq(d.item_stacks.size(), 0,
		"a fresh profile carries no extra items by default (just its weapon + ammo)")
	d = null


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
