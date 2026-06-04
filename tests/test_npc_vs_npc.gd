extends GutTest

## NPC-vs-NPC hostility (is_hostile_to) + that player targeting is preserved. Pure-logic: NPCs are
## built off-tree via load().new() so _ready (and the group-add / outline) never runs; we test the
## hostility predicate directly. Scan/throttle is exercised in-engine during manual verify (§10).

const RANGED_PATH := "res://scripts/npc/npc.gd"
const FACTION_PATH := "res://scripts/faction/faction.gd"

func before_each() -> void:
	Reputation.reset()

func after_all() -> void:
	Reputation.reset()

func _faction(fid: StringName, rels: Dictionary = {}) -> Faction:
	var f: Faction = load(FACTION_PATH).new()
	f.id = fid
	f.default_disposition = Disposition.Kind.NEUTRAL
	f.relations = rels
	return f

# A stand-in for the player: any Node in the "Player" group. Node (not Node3D) is fine — is_hostile_to
# only checks group membership + is_hostile() for the player branch.
func _player_stub() -> Node:
	var p := Node.new()
	p.add_to_group(&"Player")
	return p

func test_opposed_factions_are_mutually_hostile() -> void:
	var raider: NPC = load(RANGED_PATH).new()
	var towns: NPC = load(RANGED_PATH).new()
	raider.faction = _faction(&"raiders", { &"townsfolk": -1.0 })
	towns.faction  = _faction(&"townsfolk", { &"raiders": -1.0 })
	assert_true(raider.is_hostile_to(towns), "raider should attack opposed townsfolk")
	assert_true(towns.is_hostile_to(raider), "townsfolk (reverse relation) should attack raider")
	raider.free(); towns.free()

func test_one_directional_relation_is_asymmetric() -> void:
	var raider: NPC = load(RANGED_PATH).new()
	var towns: NPC = load(RANGED_PATH).new()
	raider.faction = _faction(&"raiders", { &"townsfolk": -1.0 })
	towns.faction  = _faction(&"townsfolk")  # no reverse relation
	assert_true(raider.is_hostile_to(towns), "raider attacks (its relation is <0)")
	assert_false(towns.is_hostile_to(raider), "townsfolk has no <0 relation -> not hostile")
	raider.free(); towns.free()

func test_same_faction_ignore_each_other() -> void:
	var a: NPC = load(RANGED_PATH).new()
	var b: NPC = load(RANGED_PATH).new()
	var shared := _faction(&"raiders", { &"townsfolk": -1.0 })
	a.faction = shared
	b.faction = shared
	assert_false(a.is_hostile_to(b), "same faction (relation_to self = 0) must not fight")
	a.free(); b.free()

func test_unaligned_npcs_never_fight_each_other() -> void:
	# Both unaligned and HOSTILE (today's default standalone disposition) — still ignore each other,
	# because NPC-vs-NPC requires BOTH factioned. Standalone disposition is player-only.
	var a: NPC = load(RANGED_PATH).new()
	var b: NPC = load(RANGED_PATH).new()
	a.disposition = Disposition.Kind.HOSTILE
	b.disposition = Disposition.Kind.HOSTILE
	assert_false(a.is_hostile_to(b), "unaligned enemies don't fight NPCs even if HOSTILE")
	a.free(); b.free()

func test_factioned_vs_unaligned_never_fights() -> void:
	var raider: NPC = load(RANGED_PATH).new()
	var loner: NPC = load(RANGED_PATH).new()
	raider.faction = _faction(&"raiders", { &"townsfolk": -1.0 })
	loner.faction = null  # unaligned
	assert_false(raider.is_hostile_to(loner), "can't be faction-hostile to a factionless NPC")
	assert_false(loner.is_hostile_to(raider), "unaligned NPC never faction-fights")
	raider.free(); loner.free()

func test_player_still_hostile_for_unaligned_hostile_enemy() -> void:
	# The preserved-behavior contract: today's lone enemy (unaligned + HOSTILE) still attacks player.
	var e: NPC = load(RANGED_PATH).new()
	var player := _player_stub()
	assert_true(e.is_hostile_to(player), "unaligned HOSTILE enemy must still target the player")
	e.free(); player.free()

func test_player_not_hostile_when_neutral_unaligned() -> void:
	var e: NPC = load(RANGED_PATH).new()
	e.disposition = Disposition.Kind.NEUTRAL
	var player := _player_stub()
	assert_false(e.is_hostile_to(player), "neutral unaligned NPC ignores the player")
	e.free(); player.free()

func test_factioned_npc_player_hostility_tracks_reputation() -> void:
	# Faction NPC + player: is_hostile_to(player) must still flow through is_hostile()/Reputation.
	var e: NPC = load(RANGED_PATH).new()
	e.faction = _faction(&"raiders")  # NEUTRAL default
	var player := _player_stub()
	assert_false(e.is_hostile_to(player), "neutral-rep faction NPC ignores player")
	Reputation.add_reputation(e.faction, -100.0)  # tank rep below HOSTILE threshold
	assert_true(e.is_hostile_to(player), "low player rep -> faction NPC hostile to player")
	e.free(); player.free()

func test_provoke_does_not_create_npc_hostility() -> void:
	# Provoke sours toward the PLAYER only; it must NOT make a same-faction peer a target.
	var a: NPC = load(RANGED_PATH).new()
	var b: NPC = load(RANGED_PATH).new()
	var shared := _faction(&"raiders")
	a.faction = shared
	b.faction = shared
	a.provoke()  # player-facing aggro
	assert_false(a.is_hostile_to(b), "provoke must not turn an NPC against a same-faction peer")
	a.free(); b.free()

func test_self_and_null_are_not_hostile() -> void:
	var e: NPC = load(RANGED_PATH).new()
	e.faction = _faction(&"raiders", { &"townsfolk": -1.0 })
	assert_false(e.is_hostile_to(e), "an NPC is never hostile to itself")
	assert_false(e.is_hostile_to(null), "null target is never hostile")
	e.free()
