extends GutTest

## Fast off-tree coverage for the NPC-pooling reset surface (NpcPool). The full acquire -> kill -> reuse INTEGRATION
## (which runs NPC._ready + a real death) is the opt-in soak test tests_soak/test_npc_pool_reuse.gd — CLAUDE.md
## forbids NPC._ready in the fast suite. Here we pin the PURE pieces: the loadout signature + override stamping on
## SpawnDefinition, CharacterInventory.clear(), each stateful component's own reset_for_reuse(), and the report math.
## Components are built with .new() WITHOUT add_child (their reset methods touch only their own fields — no tree,
## no host), and torn down bare, exactly like the other component unit tests.

const NPC_SCENE := preload("res://scenes/characters/NPC.tscn")
const PISTOL := preload("res://resources/weapons/pistol.tres")
const MELEE := preload("res://resources/weapons/melee.tres")

# --- SpawnDefinition: loadout signature + override stamping (shared by EncounterSpawner + NpcPool warming) ---------

func test_loadout_signature_matches_same_loadout_and_differs_on_weapon() -> void:
	var a := SpawnDefinition.new()
	a.npc_scene = NPC_SCENE
	a.weapon_override = PISTOL
	var b := SpawnDefinition.new()
	b.npc_scene = NPC_SCENE
	b.weapon_override = PISTOL
	var c := SpawnDefinition.new()
	c.npc_scene = NPC_SCENE
	c.weapon_override = MELEE
	assert_eq(a.loadout_signature(), b.loadout_signature(),
		"identical scene+profile+faction+weapon => same pool bucket signature")
	assert_ne(a.loadout_signature(), c.loadout_signature(),
		"a different weapon override => a different bucket (pistol raider must not reuse a melee body)")
	a = null; b = null; c = null

## A settable stand-in for the NPC exports apply_overrides() stamps (untyped so set() coerces cleanly off-tree).
class _StampTarget extends Node:
	var profile
	var faction_id = &"seed"
	var faction
	var weapon_data

func test_apply_overrides_stamps_faction_and_weapon() -> void:
	var fac := Faction.new()
	var def := SpawnDefinition.new()
	def.faction_override = fac
	def.weapon_override = PISTOL
	var t := _StampTarget.new()
	def.apply_overrides(t)
	assert_eq(t.faction, fac, "faction_override is stamped onto the NPC")
	assert_eq(t.weapon_data, PISTOL, "weapon_override is stamped onto the NPC")
	assert_eq(String(t.faction_id), "", "faction_id dropdown is cleared so the override wins in _resolve_faction")
	t.free(); def = null; fac = null

func test_apply_overrides_prefers_profile() -> void:
	var prof := NpcData.new()
	var def := SpawnDefinition.new()
	def.profile = prof
	var t := _StampTarget.new()
	def.apply_overrides(t)
	assert_eq(t.profile, prof, "a profile is stamped as the archetype")
	t.free(); def = null; prof = null

# --- CharacterInventory.clear(): the backpack wipe used before re-seeding a reused NPC's loadout ------------------

func test_inventory_clear_empties_but_keeps_grid_enabled() -> void:
	var inv := CharacterInventory.new()
	inv.enable_grid(6, 4)
	var w := Item.new()
	w.weapon = PISTOL  # a weapon item so equip_item marks it
	inv.add(w, 1)
	inv.add(Item.new(), 3)
	inv.equip_item(w)
	assert_false(inv.is_empty(), "sanity: the bag has stacks before clear()")
	inv.clear()
	assert_true(inv.is_empty(), "clear() drops every stack")
	assert_eq(inv.equipped_item, null, "clear() drops the equipped marker")
	assert_true(inv.grid_enabled(), "clear() keeps the spatial cap ENABLED (a live NPC stays bounded for life)")
	assert_eq(inv.grid_cols(), 6, "clear() keeps the grid dimensions so a re-seed re-places cleanly")
	inv.free(); w = null

# --- Component reset_for_reuse(): each clears ONLY its own per-life state --------------------------------------

func test_goap_executor_reset_clears_plan() -> void:
	var ex := GoapExecutor.new()
	ex.plan = [1, 2, 3]
	ex.index = 2
	ex.current_goal = GoapGoal.new()
	ex.reset_for_reuse()
	assert_eq(ex.plan.size(), 0, "reset drops the previous life's plan so the first tick replans")
	assert_eq(ex.index, 0, "reset rewinds the step index")
	assert_eq(ex.current_goal, null, "reset drops the stale goal")
	ex = null

func test_npc_combat_reset_clears_dodge() -> void:
	var c := NpcCombat.new()
	c._dodge_t = 1.5
	c._dodge_cd = 0.7
	c._dodge_dir = Vector3.RIGHT
	c.reset_for_reuse()
	assert_almost_eq(c._dodge_t, 0.0, 0.0001, "an active strafe burst is cancelled")
	assert_almost_eq(c._dodge_cd, 0.0, 0.0001, "the dodge cadence is reset")
	assert_eq(c._dodge_dir, Vector3.ZERO, "the held strafe direction is cleared")
	c.free()

func test_locomotor_reset_clears_stuck_and_hop() -> void:
	var loco := Locomotor.new()
	loco._stuck_hold_t = 1.5
	loco._hopping = true
	loco._jump_cd = 0.9
	loco.desired_velocity = Vector3.ONE
	loco._has_target = true
	loco._arrived = false
	loco._last_allow_hop = true
	loco._last_target_climb = 2.0
	loco.reset_for_reuse()
	assert_almost_eq(loco._stuck_hold_t, 0.0, 0.0001, "the give-up hold latch that would freeze the body is cleared")
	assert_false(loco._hopping, "the mid-hop latch is cleared so stuck accounting isn't corrupted")
	assert_almost_eq(loco._jump_cd, 0.0, 0.0001, "the hop cooldown is cleared")
	assert_eq(loco.desired_velocity, Vector3.ZERO, "the stale steering output is zeroed")
	assert_false(loco._has_target, "no phantom travel before the first move_to")
	assert_true(loco._arrived, "the arrived latch returns to its post-_ready default")
	assert_false(loco._last_allow_hop, "no stale chase-hop permission survives reuse")
	assert_almost_eq(loco._last_target_climb, 0.0, 0.0001, "the cached climb for stuck-hop recovery is cleared")
	loco.free()

func test_npc_locomotion_reset_clears_wander() -> void:
	var nl := NpcLocomotion.new()
	nl._has_wander_target = true
	nl._wander_dwell = 2.0
	nl._wander_target = Vector3(9, 0, 9)
	nl.reset_for_reuse()
	assert_false(nl._has_wander_target, "a reused wanderer picks a fresh point near its NEW spawn")
	assert_almost_eq(nl._wander_dwell, 0.0, 0.0001, "no stale dwell freezes it at spawn")
	assert_eq(nl._wander_target, Vector3.ZERO, "the old roam destination is cleared")
	nl.free()

func test_perception_reset_forgets_target_and_returns_unaware() -> void:
	var perc := Perception.new()
	perc.state = Perception.State.ALERTED
	perc.detection = 1.0
	var dummy := Node3D.new()
	perc.target = dummy
	perc.target_body = dummy
	perc.last_known_position = Vector3(5, 0, 5)
	perc.reset_for_reuse()
	assert_eq(perc.state, Perception.State.UNAWARE, "a reused NPC re-detects from scratch (edge-triggered '!' re-fires)")
	assert_almost_eq(perc.detection, 0.0, 0.0001, "the awareness meter is emptied")
	assert_eq(perc.target, null, "the stale target ref is dropped (no ghost engagement)")
	assert_eq(perc.target_body, null, "the stale LOS body is dropped")
	assert_eq(perc.last_known_position, Vector3.ZERO, "the old investigate seed is cleared")
	assert_true(perc.is_hostile, "hostility resets to the default true")
	perc.free(); dummy.free()

# --- Component resets added from the adversarial review (scavenge / voice / self-heal / talk) ------------------

func test_scavenge_reset_drops_stale_raid() -> void:
	var sc := NpcScavenge.new()
	var crate := Node3D.new()
	sc._target = crate
	sc._scan_t = 1.2
	sc.reset_for_reuse()
	assert_eq(sc._target, null, "a reused NPC drops the previous life's container raid (no wrong-way walk-off)")
	assert_almost_eq(sc._scan_t, 0.0, 0.0001, "the scan throttle is reset")
	sc.free(); crate.free()

func test_voice_reset_rewinds_bark_cooldowns() -> void:
	var v := NpcVoice.new()
	v._last_bark_msec = 999999
	v._last_greet_msec = 999999
	v._last_search_msec = 999999
	v.reset_for_reuse()
	assert_eq(v._last_bark_msec, -100000, "a quick respawn isn't muted — the bark cooldown rewinds to its sentinel")
	assert_eq(v._last_greet_msec, -100000, "greet cooldown rewound")
	assert_eq(v._last_search_msec, -100000, "search-mutter cooldown rewound")
	v.free()

func test_self_healer_reset_rewinds_heal_cooldown() -> void:
	var h := SelfHealer.new()
	h._last_heal_msec = 999999
	h.reset_for_reuse()
	assert_eq(h._last_heal_msec, -1_000_000_000, "a reused NPC can heal early in its new life (cooldown rewound)")
	h.free()

func test_talk_approach_reset_abandons_walkup() -> void:
	var t := TalkApproach.new()
	var player := Node3D.new()
	t._target = player
	t._timeout = 3.0
	assert_true(t.is_approaching(), "sanity: approaching before reset")
	t.reset_for_reuse()
	assert_false(t.is_approaching(), "a reused NPC isn't locked into the prior life's pre-talk walk-up")
	assert_almost_eq(t._timeout, 0.0, 0.0001, "the approach timeout is cleared")
	t.free(); player.free()

func test_forget_dead_peer_drops_grudge_and_attacker() -> void:
	# A pooled body is the SAME instance reborn, so a peer must drop its grudge/last-attacker refs to it on death.
	var a := NPC.new()   # off-tree (no _ready) — standard NPC unit-test pattern
	var b := NPC.new()
	a._npc_grudges.append(b)
	a._last_attacker = b
	# _target left null so forget_dead_peer's _set_target path (tree-touching) isn't exercised off-tree.
	a.forget_dead_peer(b)
	assert_false(a._npc_grudges.has(b), "the grudge against a reused peer is dropped (no phantom feud)")
	assert_eq(a._last_attacker, null, "the last-attacker ref to a reused peer is cleared")
	a.free(); b.free()

# --- NpcPoolReuseReport verdict math (pure) --------------------------------------------------------------------

func test_reuse_report_ok_requires_all_invariants() -> void:
	var r := NpcPoolReuseReport.new()
	r.nav_ready = true
	r.warmed = 3
	r.pool_count_start = 3
	r.pool_count_final = 3
	r.reused_all_same = true
	r.reset_clean = true
	assert_true(r.pool_stable(), "start==final==warmed => the pool never grew")
	assert_true(r.ok(), "all invariants met => ok")
	r.pool_count_final = 5  # a leak: the pool grew
	assert_false(r.pool_stable(), "a grown pool is not stable")
	assert_false(r.ok(), "a leak fails the verdict")
	r = null
