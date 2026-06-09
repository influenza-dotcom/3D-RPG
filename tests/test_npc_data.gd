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
	assert_almost_eq(d.max_hp, 10.0, 0.0001, "default max_hp 10.0 matches Character")
	assert_almost_eq(d.move_speed, 4.0, 0.0001, "default move_speed 4.0 matches npc.gd")
	assert_almost_eq(d.sight_range, 25.0, 0.0001, "default sight_range 25.0 matches npc.gd")
	assert_almost_eq(d.friendly_aggro_threshold, 8.0, 0.0001, "default friendly_aggro_threshold 8.0 matches npc.gd")
	assert_true(d.show_laser, "default show_laser true matches npc.gd")
	assert_eq(d.weapon_data, null, "no weapon by default (a civilian profile)")
	assert_eq(d.faction, null, "no faction by default")
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

func test_authored_raider_profile_tres_loads_and_keeps_defaults() -> void:
	# End-to-end: an authored .tres deserializes as NpcData, its set fields load, and UNSET fields keep their
	# defaults — so a profile changes only what it explicitly authors.
	var d = load("res://resources/characters/raider.tres")
	assert_not_null(d, "raider.tres loads (a copy-able archetype template)")
	assert_true(d is NpcData, "raider.tres deserializes as an NpcData")
	assert_eq(d.display_name, "Raider", "authored display_name loads from the .tres")
	assert_almost_eq(d.max_hp, 14.0, 0.0001, "authored max_hp loads")
	assert_almost_eq(d.move_speed, 4.5, 0.0001, "authored move_speed loads")
	assert_almost_eq(d.miss_chance, 0.15, 0.0001, "authored miss_chance loads")
	assert_eq(d.disposition, Disposition.Kind.HOSTILE, "an UNSET field keeps its NpcData default (HOSTILE)")
	assert_eq(d.weapon_data, null, "unset weapon_data stays null (a fists raider until a weapon is assigned)")
