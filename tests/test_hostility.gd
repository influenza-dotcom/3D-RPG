extends GutTest

## GUT suite for the NPC hostility resolution + aggro-on-attack layer (scripts/npc/npc.gd) and
## the Perception/RangedEnemy hostility gate. Enemies are built off-tree (load().new() WITHOUT
## add_child) so _ready never runs — matching test_npc.gd / test_enemies.gd construction.

const ENEMY_PATH := "res://scripts/npc/npc.gd"
const RANGED_PATH := "res://scripts/npc/npc.gd"
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

func test_attack_focuses_the_attacker_over_the_nearest() -> void:
	# Being hit must lock the attacker as the target immediately (and remember it as _last_attacker so
	# _acquire_target keeps favouring it), so a closer bystander can't distract the NPC off its aggressor.
	var e = load(RANGED_PATH).new()
	e.disposition = Disposition.Kind.HOSTILE
	var fake_player := Node3D.new()
	fake_player.add_to_group(&"Player")
	add_child_autofree(fake_player)
	e._on_damaged_by(fake_player, false)
	assert_eq(e._last_attacker, fake_player,
		"A hit must record the attacker as _last_attacker so re-scans favour it over the nearest hostile")
	assert_eq(e._target, fake_player,
		"A hit must immediately focus the attacker, not wait for the retarget throttle")
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

# --- Co-aligned alliance (HostilityHelpers.npc_vs_npc_allied) — drives the "Murderer!" death reaction ---

func test_same_faction_npcs_are_allied() -> void:
	var f = load(FACTION_PATH).new()
	f.id = &"townsfolk"
	assert_true(HostilityHelpers.npc_vs_npc_allied(f, f),
		"Two NPCs sharing the SAME faction must be co-aligned (allies)")

func test_same_faction_id_counts_as_allied() -> void:
	var a = load(FACTION_PATH).new()
	var b = load(FACTION_PATH).new()
	a.id = &"townsfolk"
	b.id = &"townsfolk"
	assert_true(HostilityHelpers.npc_vs_npc_allied(a, b),
		"Distinct faction resources that share an id must still count as co-aligned")

func test_positive_relation_is_allied() -> void:
	var a = load(FACTION_PATH).new()
	var b = load(FACTION_PATH).new()
	a.id = &"caravans"
	b.id = &"townsfolk"
	a.relations = {&"townsfolk": 1.0}
	assert_true(HostilityHelpers.npc_vs_npc_allied(a, b),
		"A positive (>0) faction-vs-faction relation must count as allied")

func test_enemy_or_neutral_relation_is_not_allied() -> void:
	var a = load(FACTION_PATH).new()
	var b = load(FACTION_PATH).new()
	a.id = &"raiders"
	b.id = &"townsfolk"
	a.relations = {&"townsfolk": -1.0}
	assert_false(HostilityHelpers.npc_vs_npc_allied(a, b),
		"An enemy (negative) relation must NOT count as allied")
	a.relations = {}
	assert_false(HostilityHelpers.npc_vs_npc_allied(a, b),
		"An unlisted (zero) relation must NOT count as allied")

func test_unaligned_faction_has_no_allies() -> void:
	var f = load(FACTION_PATH).new()
	f.id = &"townsfolk"
	assert_false(HostilityHelpers.npc_vs_npc_allied(null, f),
		"A null (unaligned) faction has no allies")
	assert_false(HostilityHelpers.npc_vs_npc_allied(f, null),
		"Nothing is allied with a null (unaligned) faction")

# --- Death-witness reaction API + lines (npc.gd) ---------------------------

func test_npc_exposes_death_witness_api() -> void:
	var n = load(ENEMY_PATH).new()
	assert_true(n.has_method("_witness_death"),
		"NPC must expose _witness_death — a nearby NPC reacts when the player kills another")
	assert_true(n.has_method("_announce_death_to_witnesses"),
		"NPC must expose _announce_death_to_witnesses — the dying NPC notifies nearby witnesses")
	assert_true(n.has_method("_is_ally_of"),
		"NPC must expose _is_ally_of — the co-aligned check behind the 'Murderer!' reaction")
	n.free()

func test_death_witness_lines_present() -> void:
	assert_true(NPC.DEATH_ALLY_LINES.has("Murderer!"),
		"A co-aligned NPC's death reaction must include 'Murderer!'")
	assert_gt(NPC.DEATH_APPROVE_LINES.size(), 0,
		"There must be approval lines for a friendly witnessing a hostile's death")
	assert_gt(NPC.DEATH_QUESTION_LINES.size(), 0,
		"There must be questioning/indifferent lines for a neutral witness")

# --- Reputation bounds + kill penalty --------------------------------------

func test_reputation_clamps_to_bounds() -> void:
	var f = load(FACTION_PATH).new()
	f.id = &"townsfolk"
	Reputation.add_reputation(f, 10000.0)
	assert_eq(Reputation.get_reputation(f), Reputation.REP_MAX,
		"Reputation must clamp UP to REP_MAX, not run away to +infinity")
	Reputation.add_reputation(f, -100000.0)
	assert_eq(Reputation.get_reputation(f), Reputation.REP_MIN,
		"Reputation must clamp DOWN to REP_MIN")

func test_kill_rep_penalty_and_clamp_range_are_sane() -> void:
	assert_gt(Reputation.KILL_REP_PENALTY, 0.0,
		"KILL_REP_PENALTY must be a positive amount of reputation lost per faction kill")
	assert_lt(Reputation.REP_MIN, Reputation.REP_MAX,
		"REP_MIN must be below REP_MAX (a valid clamp range)")

# --- Protector / bodyguard + wounded-ally + temperament API ----------------

func test_npc_exposes_protector_and_wounded_api() -> void:
	var n = load(ENEMY_PATH).new()
	assert_true(n.has_method("guard"),
		"NPC must expose guard() — bodyguard ANY character, not just the player")
	assert_true(n.has_method("stop_guarding"),
		"NPC must expose stop_guarding()")
	assert_true(n.has_method("_protectee"),
		"NPC must expose _protectee() — the generic 'who do I defend' hook")
	assert_true(n.has_method("_cry_wounded"),
		"NPC must expose _cry_wounded() — the wounded-ally bark")
	assert_eq(n.temperament, 0.0,
		"temperament default 0.0 = fearless (never flees from being hurt) until tuned")
	assert_null(n._protectee(),
		"a fresh NPC defends nobody (no leader, no guard target)")
	n.free()

func test_npc_greet_api() -> void:
	assert_gt(NPC.GREET_LINES.size(), 0,
		"NPC must have hover-greeting lines for the look-at greeting")
	var n = load(ENEMY_PATH).new()
	assert_true(n.has_method("greet"),
		"NPC must expose greet() — the FNV-style look-at hover greeting")
	n.greet()  # safe off-tree: a hostile-by-default bare NPC early-returns, and no talkable -> no-op
	assert_true(true, "greet() must be safe to call off-tree")
	n.free()

func test_npc_combat_bark_api() -> void:
	assert_gt(NPC.RELOAD_LINES.size(), 0,
		"NPC must have reload call-out lines (spoken when the AI ducks to reload)")
	assert_gt(NPC.COMBAT_END_LINES.size(), 0,
		"NPC must have combat-over call-out lines (spoken when a fighter gives up the chase)")
	assert_true(NPC.LOST_INTEREST_LINES.has("Must be gone now."),
		"NPC must have the lost-interest line 'Must be gone now.' (spoken when it gives up searching)")
	var n = load(ENEMY_PATH).new()
	assert_true(n.has_method("_try_reload_bark"),
		"NPC must expose _try_reload_bark() — the reload shout, fired from _act_alerted on reload")
	assert_true(n.has_method("_try_combat_end_bark"),
		"NPC must expose _try_combat_end_bark() — the combat-over shout, fired on the return to UNAWARE")
	assert_true(n.has_method("_try_lost_interest_bark"),
		"NPC must expose _try_lost_interest_bark() — the gave-up-searching shout, fired on the return to UNAWARE")
	n._try_reload_bark()       # safe off-tree: bare NPC has hp 0 (no _ready) -> early-returns, no talkable
	n._try_combat_end_bark()
	n._try_lost_interest_bark()
	assert_true(true, "all three combatant/sentry barks must be safe to call off-tree")
	n.free()

func test_npc_unarmed_fist_fallback_surface() -> void:
	# With nothing equipped, an NPC falls back to a weak "fists" melee. The actual swing (_act_unarmed /
	# _punch) needs a live target + take_damage, so it's manual-verify; here we pin the FISTS weapon + the
	# method surface the unarmed branch routes to.
	assert_not_null(NPC.FISTS, "NPC.FISTS must be the fallback fists weapon for unarmed attacks")
	assert_gt(NPC.FISTS.damage, 0.0, "fists deal some (weak) damage")
	var n = load(ENEMY_PATH).new()
	assert_true(n.has_method("_act_unarmed"),
		"NPC must expose _act_unarmed() — the close-in-and-punch loop when it has no usable gun")
	assert_true(n.has_method("_punch"),
		"NPC must expose _punch() — lands one weak fist hit on the current target")
	n.free()

func test_unarmed_attack_paces_to_fist_cadence_and_damage() -> void:
	# So a punch CHARGES + telegraphs like a gun shot, an unarmed NPC's wind-up timer + threat readout use the
	# FISTS weapon (not a stale/absent gun). Off-tree -> _can_fight_with_gun() is false (no equipped weapon).
	var n = load(ENEMY_PATH).new()
	var expected_interval: float = maxf(0.05, NPC.FISTS.attack_speed * n.rate_of_fire_factor)
	assert_almost_eq(n._shot_interval(), expected_interval, 0.0001,
		"an unarmed NPC's attack interval is the fists' cadence, so the charge wind-up paces to the punch")
	assert_almost_eq(n._attack_damage(), NPC.FISTS.damage, 0.0001,
		"an unarmed NPC reports the fists' damage on the player's threat indicator, not a stale gun's")
	n.free()

func test_engage_range_scales_with_weapon() -> void:
	# The standoff distance (how close the NPC wants to be) scales with the equipped weapon's effective_range
	# — a long-range weapon holds far, a short one closes in — and is NOT hard-capped by fire_range. A
	# range-less weapon (effective_range 0, e.g. the thrown rock) falls back to fire_range.
	var n = load(ENEMY_PATH).new()
	var sniper := WeaponData.new()
	sniper.effective_range = 500.0
	var shotgun := WeaponData.new()
	shotgun.effective_range = 5.0
	var rangeless := WeaponData.new()
	rangeless.effective_range = 0.0
	assert_almost_eq(n._engage_range_for(sniper), 500.0, 0.0001,
		"a long-range weapon engages at its full effective_range (not capped by fire_range)")
	assert_almost_eq(n._engage_range_for(shotgun), 5.0, 0.0001,
		"a short-range weapon closes right in")
	assert_almost_eq(n._engage_range_for(rangeless), minf(n.fire_range, NPC.UNRANGED_AIM_FALLBACK), 0.0001,
		"a range-less weapon falls back to fire_range (held to UNRANGED_AIM_FALLBACK)")
	n.free()
	sniper = null
	shotgun = null
	rangeless = null

func test_engage_range_unarmed_is_fist_reach() -> void:
	var n = load(ENEMY_PATH).new()  # off-tree: no _weapon -> _can_fight_with_gun() false -> unarmed branch
	assert_almost_eq(n._engage_range(), NPC.FISTS.effective_range, 0.0001,
		"unarmed, the engage distance is the fists' reach — the standoff still scales with the 'weapon'")
	n.free()

func test_entering_dialogue_clears_the_bark_bubble() -> void:
	# Entering a conversation force-clears any live bark balloon (so it doesn't hang over the dialogue) and
	# its no-overlap gate. The bubble itself is a real node (manual-verify); here we pin the gate clear, which
	# is the side effect _clear_bark_bubble performs through set_in_dialogue.
	var n = load(ENEMY_PATH).new()
	n._bark_until_msec = Time.get_ticks_msec() + 100000  # pretend a bark is currently on screen
	n.set_in_dialogue(true)
	assert_eq(n._bark_until_msec, 0,
		"entering dialogue clears the bark bubble + its no-overlap gate")
	assert_true(n._bark_bubble == null, "no lingering bark bubble handle after entering dialogue")
	n.free()

func test_bark_duration_scales_with_line_length() -> void:
	# _emit_bark suppresses a new bark while the previous bubble is still up (no talking over itself); the
	# window is _bark_duration_ms, which tracks _popup_text's on-screen time. The suppression itself needs a
	# live tree (await + tween), so it's manual-verify; here we pin the duration math it relies on.
	var n = load(ENEMY_PATH).new()
	var short_ms: int = n._bark_duration_ms("Hi")
	var long_ms: int = n._bark_duration_ms("This is a much, much longer call-out that lingers on screen.")
	assert_gt(short_ms, 0, "a bark bubble has a positive on-screen duration")
	assert_gt(long_ms, short_ms, "a longer line stays up longer, so its no-overlap window is longer too")
	n.free()
