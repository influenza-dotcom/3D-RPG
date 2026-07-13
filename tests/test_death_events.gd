extends GutTest

## Death-event gates (NpcData.sours_faction_on_death / pause_on_kill) read by NPC._on_died via the pure
## predicates death_sours_faction() / death_pauses_game(). Default ON so a profile-less NPC dies exactly as
## before. Driven off-tree against the predicates (no _ready, no _on_died cascade) — the predicates are pure
## reads of `faction` + `profile`, so the profile/faction combos pin without a scene tree.

const NPC_PATH := "res://scripts/npc/npc.gd"

func test_npc_data_death_gates_default_on() -> void:
	var d := NpcData.new()
	assert_true(d.sours_faction_on_death, "sours_faction_on_death must default ON so a profiled kill still sours the faction")
	assert_true(d.pause_on_kill, "pause_on_kill must default ON so a profiled NPC keeps the kill-beat hitstop")
	assert_true(d.freeze_on_death, "freeze_on_death must default ON so a profiled NPC still plays the freeze-then-explode pop")
	d = null

func test_death_pauses_game_profile_less_defaults_true() -> void:
	var e = load(NPC_PATH).new()
	assert_true(e.death_pauses_game(), "a profile-less NPC keeps the kill-beat pause (unchanged behaviour)")
	e.free()

func test_death_pauses_game_respects_profile() -> void:
	var e = load(NPC_PATH).new()
	var d := NpcData.new()
	d.pause_on_kill = false
	e.profile = d
	assert_false(e.death_pauses_game(), "pause_on_kill=false -> no kill-beat hitstop (a trash-mob / swarm enemy)")
	d.pause_on_kill = true
	assert_true(e.death_pauses_game(), "pause_on_kill=true -> the pause fires")
	e.free()
	d = null

func test_death_freezes_profile_less_defaults_true() -> void:
	var e = load(NPC_PATH).new()
	assert_true(e.death_freezes(), "a profile-less NPC freezes in place before goring (unchanged default)")
	e.free()

func test_death_freezes_respects_profile() -> void:
	var e = load(NPC_PATH).new()
	var d := NpcData.new()
	d.freeze_on_death = false
	e.profile = d
	assert_false(e.death_freezes(), "freeze_on_death=false -> no freeze beat (a trash-mob / swarm enemy pops instantly)")
	d.freeze_on_death = true
	assert_true(e.death_freezes(), "freeze_on_death=true -> the freeze beat fires")
	e.free()
	d = null

func test_death_sours_faction_requires_a_faction() -> void:
	var e = load(NPC_PATH).new()
	e.faction = null
	assert_false(e.death_sours_faction(), "an unfactioned NPC has no standing to sour, regardless of the gate")
	e.free()

func test_death_sours_faction_profile_less_defaults_true() -> void:
	var e = load(NPC_PATH).new()
	e.faction = Faction.new()
	assert_true(e.death_sours_faction(), "a factioned, profile-less NPC sours its faction on a player kill (unchanged)")
	e.free()

func test_death_sours_faction_respects_profile() -> void:
	var e = load(NPC_PATH).new()
	e.faction = Faction.new()
	var d := NpcData.new()
	d.sours_faction_on_death = false
	e.profile = d
	assert_false(e.death_sours_faction(), "sours_faction_on_death=false -> a 'free kill' target (no rep drop)")
	d.sours_faction_on_death = true
	assert_true(e.death_sours_faction(), "sours_faction_on_death=true -> the faction sours")
	e.free()
	d = null
