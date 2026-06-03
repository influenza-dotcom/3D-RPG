extends GutTest

## GUT suite for the faction/reputation data layer (scripts/faction/faction.gd,
## scripts/npc/disposition.gd, managers/Reputation.gd). Pure logic — no scene tree, no physics:
## Faction is a Resource (.new()), Disposition is an enum namespace, and Reputation's math is
## exercised on a fresh instance (.new()) rather than the live autoload so tests don't leak state.

const FACTION_PATH := "res://scripts/faction/faction.gd"
const REPUTATION_PATH := "res://managers/Reputation.gd"

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

func test_faction_relations_lookup() -> void:
	var f = load(FACTION_PATH).new()
	f.relations = { &"raiders": -1.0 }
	assert_eq(f.relation_to(&"raiders"), -1.0,
		"relation_to() must read the authored relations dictionary by faction id")

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
	var rep := _fresh_rep()
	var f := _faction(&"townsfolk", Disposition.Kind.NEUTRAL)
	rep.add_reputation(f, rep.HOSTILE_THRESHOLD - 1.0)  # below the hostile threshold
	assert_eq(rep.disposition_for(f), Disposition.Kind.HOSTILE,
		"Reputation at/below HOSTILE_THRESHOLD must force HOSTILE even for a NEUTRAL-default faction")
	rep.free()

func test_high_reputation_reads_friendly() -> void:
	var rep := _fresh_rep()
	var f := _faction(&"townsfolk", Disposition.Kind.NEUTRAL)
	rep.add_reputation(f, rep.FRIENDLY_THRESHOLD + 1.0)
	assert_eq(rep.disposition_for(f), Disposition.Kind.FRIENDLY,
		"Reputation at/above FRIENDLY_THRESHOLD must read FRIENDLY")
	rep.free()

func test_null_faction_is_safe() -> void:
	var rep := _fresh_rep()
	assert_eq(rep.get_reputation(null), 0.0,
		"get_reputation(null) must be 0.0 — an unaligned NPC must never crash the manager")
	assert_eq(rep.add_reputation(null, 5.0), 0.0,
		"add_reputation(null, ...) must no-op to 0.0")
	rep.free()
