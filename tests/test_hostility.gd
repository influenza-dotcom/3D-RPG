extends GutTest

## GUT suite for the NPC hostility resolution + aggro-on-attack layer (scripts/npc/npc.gd) and
## the Perception/RangedEnemy hostility gate. Enemies are built off-tree (load().new() WITHOUT
## add_child) so _ready never runs — matching test_npc.gd / test_enemies.gd construction.

const ENEMY_PATH := "res://scenes/enemies/enemy.gd"
const RANGED_PATH := "res://scenes/enemies/ranged_enemy.gd"
const FACTION_PATH := "res://scripts/faction/faction.gd"

func before_each() -> void:
	Reputation.reset()  # the autoload is global; wipe standing so tests don't bleed into each other

func after_all() -> void:
	Reputation.reset()

# --- THE DEFAULT THAT KEEPS EXISTING ENEMIES HOSTILE ------------------------

func test_unaligned_enemy_defaults_to_hostile() -> void:
	# The load-bearing default: a plain Enemy sets neither faction nor disposition, so it must be
	# unaligned (faction==null) + disposition==HOSTILE => is_hostile() true. This is why every
	# existing enemy scene keeps fighting exactly as before with zero scene edits.
	var e = load(ENEMY_PATH).new()
	assert_null(e.faction,
		"NPC.faction must default null (UNALIGNED) so an enemy uses its standalone disposition")
	assert_eq(e.disposition, Disposition.Kind.HOSTILE,
		"NPC.disposition must default HOSTILE so an unaligned enemy is aggressive on sight like today")
	assert_true(e.is_hostile(),
		"A default Enemy must resolve is_hostile()==true so existing scenes never go passive")
	e.free()

func test_provoked_starts_false() -> void:
	var e = load(ENEMY_PATH).new()
	assert_false(e._provoked,
		"_provoked must start false — nothing has aggroed the NPC yet")
	e.free()

# --- Resolution priority: provoked > faction(+rep) > standalone disposition ---

func test_unaligned_neutral_is_not_hostile() -> void:
	var e = load(ENEMY_PATH).new()
	e.faction = null
	e.disposition = Disposition.Kind.NEUTRAL
	assert_false(e.is_hostile(),
		"An unaligned NEUTRAL NPC must not be hostile — it uses its standalone disposition")
	e.free()

func test_faction_overrides_standalone_disposition() -> void:
	# With a faction set, the standalone disposition is IGNORED; Reputation decides.
	var e = load(ENEMY_PATH).new()
	var f = load(FACTION_PATH).new()
	f.id = &"townsfolk"
	f.default_disposition = Disposition.Kind.NEUTRAL
	e.faction = f
	e.disposition = Disposition.Kind.HOSTILE  # would be hostile if unaligned — but faction wins
	assert_false(e.is_hostile(),
		"A factioned NPC must resolve via Reputation (NEUTRAL here), ignoring its standalone HOSTILE disposition")
	e.free()

func test_low_rep_makes_factioned_npc_hostile() -> void:
	var e = load(ENEMY_PATH).new()
	var f = load(FACTION_PATH).new()
	f.id = &"townsfolk"
	f.default_disposition = Disposition.Kind.NEUTRAL
	e.faction = f
	Reputation.add_reputation(f, Reputation.HOSTILE_THRESHOLD - 1.0)
	assert_true(e.is_hostile(),
		"Tanking reputation below HOSTILE_THRESHOLD must make a factioned NPC hostile")
	e.free()

func test_provoked_overrides_friendly_faction() -> void:
	var e = load(ENEMY_PATH).new()
	var f = load(FACTION_PATH).new()
	f.id = &"townsfolk"
	f.default_disposition = Disposition.Kind.FRIENDLY
	e.faction = f
	Reputation.add_reputation(f, Reputation.FRIENDLY_THRESHOLD + 100.0)  # very friendly
	assert_false(e.is_hostile(),
		"Sanity: a very-high-rep FRIENDLY faction NPC is not hostile before provocation")
	e.provoke()
	assert_true(e.is_hostile(),
		"provoke() must force HOSTILE even over a FRIENDLY high-rep faction — a direct attack always aggros")
	e.free()

# --- Aggro-on-attack: player hit provokes; faction rep drops ----------------

func test_player_attack_provokes_unaligned_neutral() -> void:
	var e = load(ENEMY_PATH).new()
	e.faction = null
	e.disposition = Disposition.Kind.NEUTRAL
	var fake_player := Node3D.new()
	fake_player.add_to_group(&"Player")
	add_child_autofree(fake_player)
	assert_false(e.is_hostile(), "precondition: neutral NPC starts non-hostile")
	e._on_damaged_by(fake_player, false)
	assert_true(e._provoked,
		"A hit from the player must set _provoked")
	assert_true(e.is_hostile(),
		"A provoked NPC must resolve hostile (aggro-on-attack)")
	e.free()

func test_non_player_attack_does_not_provoke() -> void:
	var e = load(ENEMY_PATH).new()
	e.faction = null
	e.disposition = Disposition.Kind.NEUTRAL
	var other := Node3D.new()  # NOT in the Player group (e.g. friendly fire)
	add_child_autofree(other)
	e._on_damaged_by(other, false)
	assert_false(e._provoked,
		"A hit from a non-player must NOT provoke — only the player aggros a neutral NPC")
	e.free()

func test_provoke_drops_faction_reputation() -> void:
	var e = load(ENEMY_PATH).new()
	var f = load(FACTION_PATH).new()
	f.id = &"townsfolk"
	f.default_disposition = Disposition.Kind.NEUTRAL
	e.faction = f
	var before := Reputation.get_reputation(f)
	e.provoke()
	assert_eq(Reputation.get_reputation(f), before - Reputation.PROVOKE_REP_PENALTY,
		"Provoking a factioned NPC must drop the player's reputation with that faction by PROVOKE_REP_PENALTY")
	e.free()

func test_already_hostile_does_not_double_drop_rep() -> void:
	var e = load(ENEMY_PATH).new()
	var f = load(FACTION_PATH).new()
	f.id = &"raiders"
	f.default_disposition = Disposition.Kind.HOSTILE  # already hostile
	e.faction = f
	var fake_player := Node3D.new()
	fake_player.add_to_group(&"Player")
	add_child_autofree(fake_player)
	e._on_damaged_by(fake_player, false)  # already hostile -> early return, no provoke
	assert_eq(Reputation.get_reputation(f), 0.0,
		"Attacking an already-hostile factioned NPC must NOT drop reputation (it was already fighting you)")
	e.free()

# --- Perception hostility gate ----------------------------------------------

func test_perception_has_hostility_gate_defaulting_true() -> void:
	var p := Perception.new()
	assert_true(p.is_hostile,
		"Perception.is_hostile must default true so a bare/old-style enemy senses exactly as before")
	p.free()

func test_perception_non_hostile_cannot_see_or_hear() -> void:
	var p := Perception.new()
	p.is_hostile = false
	assert_false(p.can_see(),
		"A non-hostile Perception must never see the player — the gate short-circuits can_see()")
	assert_false(p.can_hear(),
		"A non-hostile Perception must never hear the player — the gate short-circuits can_hear()")
	p.free()

# --- RangedEnemy still exposes the aggro hook + legacy handler --------------

func test_ranged_enemy_has_aggro_and_legacy_handlers() -> void:
	var n = load(RANGED_PATH).new()
	assert_true(n.has_method("_on_damaged_by"),
		"RangedEnemy must expose _on_damaged_by — the attacker-aware aggro/turn-toward-shooter path")
	assert_true(n.has_method("_on_damaged"),
		"RangedEnemy must keep _on_damaged — the damaged-signal freeze-frame handler wired in enemy.tscn")
	assert_true(n.has_method("is_hostile"),
		"RangedEnemy must inherit is_hostile() so the AI can gate on it")
	n.free()
