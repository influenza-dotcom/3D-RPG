extends GutTest

## GUT suite for the faction/reputation data layer (scripts/faction/faction.gd,
## scripts/npc/disposition.gd, managers/Reputation.gd). Mostly pure logic, no physics: Faction is a Resource
## (.new(), or the shipped .tres files read through Factions), Disposition is an enum namespace, and Reputation's
## math runs on fresh instances (.new()) rather than the live autoload, so the autoload's standings are never touched.
## The one scene-tree exception is test_adjust_unscaled_reverses_a_delta_exactly: it parents two fresh Reputation
## instances and a stub in the &"Player" group (Groups.PLAYER) under this test node so add_reputation's streetwise
## scaling really runs, and add_child_autofree removes all three when that test ends. Any in-tree Reputation (the
## live autoload included) scales by whatever non-NPC member that group holds, which is why the stub must never
## outlive its test.

const FACTION_PATH := "res://scripts/faction/faction.gd"
const REPUTATION_PATH := "res://managers/Reputation.gd"
const NPC_PATH := "res://scripts/npc/npc.gd"
const NPC_DATA_PATH := "res://scripts/npc/npc_data.gd"
const Factions := preload("res://scripts/faction/factions.gd")

# --- Disposition enum shape (order is load-bearing for the rep->disposition mapping) ---

func test_disposition_kind_has_three_ordered_members() -> void:
	assert_eq(Disposition.Kind.size(), 3,
		"Disposition.Kind must have exactly 3 members — HOSTILE/NEUTRAL/FRIENDLY")
	assert_eq(Disposition.Kind.HOSTILE, 0,
		"HOSTILE must be 0 — .tres files serialize the enum as its ordinal; raiders.tres stores 0")
	assert_eq(Disposition.Kind.NEUTRAL, 1,
		"NEUTRAL must be 1 (the middle band reputation defers to the faction default in)")
	assert_eq(Disposition.Kind.FRIENDLY, 2,
		"FRIENDLY must be 2 — rising reputation walks the enum upward toward this")

# --- Faction resource ---

func test_faction_defaults() -> void:
	var f = load(FACTION_PATH).new()
	assert_eq(f.id, &"",
		"Faction.id must default to empty StringName — each .tres sets a unique id")
	assert_eq(f.default_disposition, Disposition.Kind.NEUTRAL,
		"Faction.default_disposition must default NEUTRAL so a half-authored faction isn't accidentally hostile")
	assert_eq(f.relation_to(&"anyone"), 0.0,
		"relation_to() must return 0.0 for an unlisted faction (neutral relations by default)")

func test_shipped_raiders_and_townsfolk_fight_each_other_by_faction_id() -> void:
	# The world's NPC-vs-NPC war is authored data: raiders.tres and townsfolk.tres each list the other with a
	# relation < 0, and HostilityHelpers (behind NPC.is_hostile_to) reads it through relation_to keyed by the OTHER
	# faction's id. Nothing else pins the shipped relations; a designer clearing one side silently ends that half.
	var raiders := Factions.by_id("raiders")
	var townsfolk := Factions.by_id("townsfolk")
	var wildlife := Factions.by_id("neutral_wildlife")
	assert_true(raiders != null and townsfolk != null and wildlife != null, "the three shipped faction .tres files must load")
	if raiders == null or townsfolk == null or wildlife == null:
		return
	assert_true(HostilityHelpers.npc_vs_npc_hostile(raiders, townsfolk),
		"shipped raiders must attack townsfolk on sight (raiders.tres relation to townsfolk < 0)")
	assert_true(HostilityHelpers.npc_vs_npc_hostile(townsfolk, raiders),
		"shipped townsfolk must fight back against raiders (townsfolk.tres relation to raiders < 0)")
	assert_false(HostilityHelpers.npc_vs_npc_hostile(raiders, wildlife),
		"control: a faction raiders.tres does not list (neutral wildlife) is left alone -- unlisted reads neutral, not enemy")
	# Keyed by id, not by resource instance: a townsperson carrying its own copy of the faction (a duplicated /
	# local-to-scene resource) is still the raiders' enemy.
	var copy = load(FACTION_PATH).new()
	copy.id = &"townsfolk"
	assert_true(HostilityHelpers.npc_vs_npc_hostile(raiders, copy),
		"the relation must be looked up by the other faction's id, so a separate Faction resource with id townsfolk is still hostile")

# --- Reputation mapping (fresh instance so the autoload's pool isn't touched) ---

func _fresh_rep() -> Node:
	return load(REPUTATION_PATH).new()

func _faction(id: StringName, default_disp: int) -> Resource:
	var f = load(FACTION_PATH).new()
	f.id = id
	f.default_disposition = default_disp
	return f

func test_reputation_starts_at_zero() -> void:
	var rep := _fresh_rep()
	var f := _faction(&"townsfolk", Disposition.Kind.NEUTRAL)
	assert_eq(rep.get_reputation(f), 0.0,
		"An unseen faction must start at 0.0 reputation")
	rep.free()

func test_add_reputation_accumulates() -> void:
	var rep := _fresh_rep()
	var f := _faction(&"townsfolk", Disposition.Kind.NEUTRAL)
	rep.add_reputation(f, 10.0)
	rep.add_reputation(f, -3.0)
	assert_eq(rep.get_reputation(f), 7.0,
		"add_reputation must accumulate signed deltas into the faction's pool")
	rep.free()

func test_neutral_faction_reads_default_at_zero_rep() -> void:
	var rep := _fresh_rep()
	var f := _faction(&"townsfolk", Disposition.Kind.NEUTRAL)
	assert_eq(rep.disposition_for(f), Disposition.Kind.NEUTRAL,
		"At rep 0 inside the neutral band, disposition_for must defer to the faction's NEUTRAL default")
	rep.free()

func test_hostile_default_faction_reads_hostile_at_zero_rep() -> void:
	var rep := _fresh_rep()
	var f := _faction(&"raiders", Disposition.Kind.HOSTILE)
	assert_eq(rep.disposition_for(f), Disposition.Kind.HOSTILE,
		"A HOSTILE-default faction (raiders) must read HOSTILE at rep 0 so factioned raiders fight like classic enemies")
	rep.free()

func test_low_reputation_forces_hostile() -> void:
	# Thresholds come from GameSettings.reputation -- the resource disposition_for actually reads -- so a retune of
	# ReputationSettings.tres moves the fixture with it.
	var hostile_at: float = GameSettings.reputation.hostile_threshold
	var rep := _fresh_rep()
	var f := _faction(&"townsfolk", Disposition.Kind.NEUTRAL)
	rep.add_reputation(f, hostile_at + 0.5)
	assert_eq(rep.disposition_for(f), Disposition.Kind.NEUTRAL,
		"control: just above hostile_threshold a NEUTRAL-default faction still reads its default")
	rep.adjust_unscaled(f, -0.5)  # land EXACTLY on the threshold
	assert_eq(rep.disposition_for(f), Disposition.Kind.HOSTILE,
		"reputation AT hostile_threshold must already force HOSTILE (the threshold is inclusive)")
	rep.adjust_unscaled(f, -1.0)
	assert_eq(rep.disposition_for(f), Disposition.Kind.HOSTILE,
		"reputation below hostile_threshold forces HOSTILE even for a NEUTRAL-default faction")
	rep.free()

func test_high_reputation_reads_friendly() -> void:
	var friendly_at: float = GameSettings.reputation.friendly_threshold
	var rep := _fresh_rep()
	var f := _faction(&"townsfolk", Disposition.Kind.NEUTRAL)
	rep.add_reputation(f, friendly_at - 0.5)
	assert_eq(rep.disposition_for(f), Disposition.Kind.NEUTRAL,
		"control: just below friendly_threshold a NEUTRAL-default faction still reads its default")
	rep.adjust_unscaled(f, 0.5)  # land EXACTLY on the threshold
	assert_eq(rep.disposition_for(f), Disposition.Kind.FRIENDLY,
		"reputation AT friendly_threshold must already read FRIENDLY (the threshold is inclusive)")
	rep.adjust_unscaled(f, 1.0)
	assert_eq(rep.disposition_for(f), Disposition.Kind.FRIENDLY,
		"reputation above friendly_threshold reads FRIENDLY")
	rep.free()

func test_null_faction_is_safe() -> void:
	var rep := _fresh_rep()
	assert_eq(rep.get_reputation(null), 0.0,
		"get_reputation(null) must be 0.0 — an unaligned NPC must never crash the manager")
	assert_eq(rep.add_reputation(null, 5.0), 0.0,
		"add_reputation(null, ...) must no-op to 0.0")
	rep.free()

## The live human player as Reputation._stats_player() finds it: an in-tree &"Player" group member that is not an
## NPC and answers stats_or_default. That duck-typed read is all add_reputation needs to scale by STREETWISE.
class StreetwisePlayerStub extends Node:
	var sheet := CharacterStats.new()

	func stats_or_default() -> CharacterStats:
		return sheet


func test_adjust_unscaled_reverses_a_delta_exactly() -> void:
	# NPC._clear_provoke refunds a provoke by handing the ALREADY-SCALED hit back through adjust_unscaled. That only
	# lands the faction where it started if the refund skips streetwise: scaled again, a positive refund grows by the
	# gain multiplier and the faction ends up liking a forgiven attacker MORE than before. Off-tree there is no player
	# and add_reputation is unscaled too, so the refund is driven in-tree with a high-streetwise player present.
	# Every node here is added with add_child_autofree, so GUT frees it after the test even if a runtime error aborts
	# the body early: a stub left in the Player group would scale any in-tree Reputation (the live autoload included)
	# until this file's test node is freed.
	var rep := _fresh_rep()
	add_child_autofree(rep)
	var player := StreetwisePlayerStub.new()
	player.sheet.streetwise = CharacterStats.BASELINE + 5
	add_child_autofree(player)
	player.add_to_group(Groups.PLAYER)
	var f := _faction(&"townsfolk", Disposition.Kind.NEUTRAL)
	var applied: float = rep.add_reputation(f, -30.0)  # from 0, the returned total IS the applied delta
	assert_true(applied < 0.0 and applied > -30.0,
		"precondition: with a streetwise player in the tree the provoke hit must land SMALLER than -30 (got %s), or this setup is not exercising the scaled path at all" % applied)
	rep.adjust_unscaled(f, -applied)
	assert_eq(rep.get_reputation(f), 0.0,
		"adjust_unscaled must refund the already-scaled hit exactly, back to 0 — re-scaling it by streetwise would overshoot into positive standing")
	# Control: the same refund through add_reputation IS scaled by this player, so the exact round trip above is
	# adjust_unscaled's own doing and not a scaling path that happens to be dormant.
	var control := _fresh_rep()
	add_child_autofree(control)
	control.add_reputation(f, applied)
	control.add_reputation(f, -applied)
	assert_true(control.get_reputation(f) != 0.0,
		"control: add_reputation re-scales a refund by streetwise, so the same pair through it must NOT land on 0 (got %s)" % control.get_reputation(f))
	assert_eq(rep.adjust_unscaled(null, 5.0), 0.0,
		"adjust_unscaled(null, ...) must no-op to 0.0 like add_reputation")

# --- Faction dropdown auto-populated from disk (resources/factions/) ---

## First entry in get_property_list() whose name matches, else {}.
func _property(obj: Object, prop_name: String) -> Dictionary:
	for p in obj.get_property_list():
		if p.get("name", "") == prop_name:
			return p
	return {}

func test_factions_ids_scans_disk_sorted() -> void:
	var ids := Factions.ids()
	assert_true(ids.size() >= 3, "Factions.ids() must find the shipped faction .tres files in resources/factions/")
	for known in ["neutral_wildlife", "raiders", "townsfolk"]:
		assert_true(ids.has(known), "Factions.ids() must include shipped faction '%s'" % known)
	var resorted := Array(ids).duplicate()
	resorted.sort()
	assert_eq(Array(ids), resorted, "Factions.ids() must be sorted so the dropdown order is stable")
	for id in ids:
		assert_not_null(Factions.by_id(id), "every scanned id must resolve via by_id (id == filename convention): '%s'" % id)

func test_npc_data_faction_dropdown_is_dynamic() -> void:
	# NpcData is @tool with _validate_property, so its faction_id dropdown is built from disk at property-list
	# time (works at runtime too, so we can assert it here without the editor).
	var d = load(NPC_DATA_PATH).new()
	var p := _property(d, "faction_id")
	assert_false(p.is_empty(), "NpcData must expose a faction_id property")
	assert_eq(p.get("hint", -1), PROPERTY_HINT_ENUM_SUGGESTION,
		"NpcData.faction_id must be a PROPERTY_HINT_ENUM_SUGGESTION dropdown (set in _validate_property)")
	assert_eq(p.get("hint_string", ""), Factions.ids_csv(),
		"NpcData.faction_id dropdown must auto-populate from disk (Factions.ids_csv) — no hand-maintained list")
	d = null

func test_npc_faction_dropdown_is_dynamic() -> void:
	# npc.gd is @tool with _validate_property (every runtime lifecycle method is is_editor_hint-guarded), so the
	# NPC-instance faction_id dropdown auto-populates from disk too -- same as NpcData, no hardcoded list. Built
	# off-tree (no add_child) so _ready never runs (CLAUDE.md pattern); get_property_list still fires _validate_property.
	var n = load(NPC_PATH).new()
	var p := _property(n, "faction_id")
	assert_false(p.is_empty(), "NPC must expose a faction_id property")
	assert_eq(p.get("hint", -1), PROPERTY_HINT_ENUM_SUGGESTION,
		"NPC.faction_id must be a PROPERTY_HINT_ENUM_SUGGESTION dropdown (set in _validate_property)")
	assert_eq(p.get("hint_string", ""), Factions.ids_csv(),
		"NPC.faction_id dropdown must auto-populate from disk (Factions.ids_csv) -- no hand-maintained list")
	n.free()

# --- Faction content guards (catch authoring footguns at test-time, not silently at runtime) ---

func test_every_faction_id_matches_its_filename() -> void:
	# factions.gd resolves by path (id == filename); a copy-pasted .tres whose INTERNAL id != filename silently
	# merges two factions into ONE reputation pool. factions.gd only push_warns at runtime -- this fails loudly.
	var ids := Factions.ids()
	assert_true(ids.size() >= 3, "expected the shipped faction .tres files under resources/factions/")
	for id in ids:
		var f := Factions.by_id(id)
		assert_not_null(f, "faction '%s' must resolve via by_id" % id)
		if f != null:
			assert_eq(f.id, StringName(id),
				"faction '%s.tres' internal id must equal its filename (Reputation keys on the internal id)" % id)

func test_faction_relations_reference_known_factions() -> void:
	# A relation keyed on a faction id that doesn't exist (a typo) silently reads as 0.0 (neutral) -- catch it.
	var known := {}
	for id in Factions.ids():
		known[StringName(id)] = true
	for id in Factions.ids():
		var f := Factions.by_id(id)
		if f == null:
			continue
		for other in f.relations:
			assert_true(known.has(StringName(other)),
				"faction '%s' relates to unknown faction '%s' -- typo, or add the missing .tres" % [id, other])

func test_shipped_raiders_are_hostile_on_sight_at_zero_rep() -> void:
	# The synthetic hostility tests build raiders via _faction(&"raiders", HOSTILE) or hand-set
	# default_disposition, so none pins the SHIPPED resources/factions/raiders.tres. A designer flipping
	# it to NEUTRAL (default_disposition 0->1) would pass every other test while silently breaking
	# on-sight raider combat. This content guard reads the real file and fails loudly on that flip.
	var raiders := Factions.by_id("raiders")
	assert_not_null(raiders, "raiders.tres must exist")
	assert_eq(raiders.default_disposition, Disposition.Kind.HOSTILE,
		"shipped raiders.tres must be HOSTILE-by-default so raiders fight on sight at rep 0")
	var rep := _fresh_rep()
	assert_eq(rep.disposition_for(raiders), Disposition.Kind.HOSTILE,
		"at rep 0 (neutral band) the shipped raiders faction must resolve HOSTILE")
	rep.free()
