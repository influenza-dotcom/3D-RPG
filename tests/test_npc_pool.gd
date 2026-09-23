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

## A PROFILE is the whole archetype: NPC._ready's full stamp writes faction_id / faction / weapon_data FROM it. So a
## profile-only definition stamps the profile and leaves those fields alone. Clearing faction_id is the faction
## override's job, and doing it here would blank an id the NPC's own authored faction resolves through.
func test_apply_overrides_profile_only_stamps_the_archetype_and_nothing_else() -> void:
	var prof := NpcData.new()
	var def := SpawnDefinition.new()
	def.profile = prof
	var t := _StampTarget.new()
	def.apply_overrides(t)
	assert_eq(t.profile, prof, "a profile is stamped as the archetype")
	assert_eq(String(t.faction_id), "seed",
		"a profile-only spawn must not clear the NPC's faction_id: only a faction_override does that")
	assert_null(t.faction, "a profile-only spawn stamps no faction of its own (the profile supplies it at _ready)")
	assert_null(t.weapon_data, "a profile-only spawn stamps no weapon of its own (the profile supplies it at _ready)")
	assert_push_warning_count(0, "a well-formed profile-only definition warns about nothing")
	t.free(); def = null; prof = null

## The precedence contract when a designer sets BOTH: the profile is still stamped (so NPC._ready's full archetype
## stamp overwrites the overrides) and the designer is told the overrides are ignored.
func test_apply_overrides_warns_when_a_profile_is_mixed_with_overrides() -> void:
	var prof := NpcData.new()
	var def := SpawnDefinition.new()
	def.profile = prof
	def.weapon_override = PISTOL
	var t := _StampTarget.new()
	def.apply_overrides(t)
	assert_eq(t.profile, prof, "the profile is stamped even alongside overrides, so the archetype wins at _ready")
	assert_push_warning("the profile wins",
		"a definition mixing a profile with overrides must warn the designer that the overrides are ignored")
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

## A speaking NPC stand-in for NpcVoice (the duck-typed host surface tests/test_bark_gates.gd pins against the real
## npc.gd): alive, non-hostile, idle, with a Talkable and the player in earshot, so on each trigger below the ONLY
## filter left is its cooldown. Every emitted line is recorded in order.
class _VoiceHost extends Node3D:
	var WARN_ATTACK_LINES: Array[String] = ["Cut that out!"]
	var GREET_LINES: Array[String] = ["Hey there."]
	var SEARCH_LINES: Array[String] = ["Where are you?"]
	var _dead := false
	var hp := 10.0
	var talkable: Node = null
	var player: Node3D = null
	var emitted: Array[String] = []

	func is_hostile() -> bool: return false
	func is_in_combat() -> bool: return false
	func _find_talkable(): return talkable
	func _real_player(): return player
	func _pick_bark(fallback: Array[String], _override: Array[String]) -> String: return fallback[0]
	func _emit_bark(line: String, _voice) -> void: emitted.append(line)

class _VoiceTalkable extends Node:
	var voice: VoiceData = null

## The pooled body's three independent voice cooldowns (the shared bark, the hover greeting, the search mutter), each
## driven through a real trigger: the previous life speaks, the same body inside the cooldown is muted (the control),
## and after reset_for_reuse the reborn NPC speaks again at once — a quick same-wave respawn is not born mute.
func test_voice_reset_lets_a_reused_npc_speak_at_once() -> void:
	var h := _VoiceHost.new()
	h.talkable = _VoiceTalkable.new()
	h.add_child(h.talkable)
	add_child_autofree(h)  # in-tree: the search mutter measures the player's distance off global_position
	var listener := Node3D.new()
	add_child_autofree(listener)
	listener.position = Vector3(1.0, 0.0, 0.0)
	h.player = listener
	var v := NpcVoice.new()
	v.host = h
	autofree(v)
	v.warn_attack()
	v.greet()
	v.bark_searching()
	assert_eq(h.emitted, ["Cut that out!", "Hey there.", "Where are you?"] as Array[String],
		"sanity: the previous life speaks once on each channel, arming all three cooldowns")
	v.warn_attack()
	v.greet()
	v.bark_searching()
	assert_eq(h.emitted.size(), 3, "control: the same body still inside those cooldowns is muted on every channel")
	v.reset_for_reuse()
	h.emitted.clear()
	v.warn_attack()
	assert_eq(h.emitted, ["Cut that out!"] as Array[String],
		"after reuse the shared bark cooldown is clear: the reborn NPC's first call-out is not swallowed")
	v.greet()
	assert_eq(h.emitted.back(), "Hey there.", "after reuse the hover greeting is not held by the previous life's cooldown")
	v.bark_searching()
	assert_eq(h.emitted.back(), "Where are you?", "after reuse the search mutter is not held by the previous life's cooldown")

func test_distraction_reset_clears_scan_state() -> void:
	# NpcDistraction owns the noise/music scan throttles + the once-per-attend music-comment latch; a reused body
	# must not inherit them (a stale _music_commented_radio would silently swallow the same-radio music comment for
	# the whole next life). Path-loaded, not the bare class_name — mirroring how npc.gd builds it (@tool parse /
	# new-classname cascade), same as the home-return leash.
	var d = load("res://scripts/npc/npc_distraction.gd").new()
	var radio := Node3D.new()
	d._distraction_scan_t = 1.2
	d._music_scan_t = 0.7
	d._music_commented_radio = radio
	d.reset_for_reuse()
	assert_almost_eq(d._distraction_scan_t, 0.0, 0.0001, "the noise/corpse scan throttle is reset")
	assert_almost_eq(d._music_scan_t, 0.0, 0.0001, "the music scan throttle is reset")
	assert_null(d._music_commented_radio, "the once-per-attend comment latch is dropped (a reused body comments again)")
	d.free(); radio.free()

## A duck-typed hurt body for SelfHealer.react (hp / max_hp / inventory / heal), carrying a REAL backpack so the
## medkit lookup and spend are production code too.
class _HealHost:
	var hp := 20.0
	var max_hp := 100.0
	var inventory: CharacterInventory = null
	func heal(amount: float) -> void:
		hp = minf(hp + amount, max_hp)

## The previous life chugs a medkit just before it dies; the body is pooled and respawns hurt. Inside the old cooldown
## the same healer refuses (the control); after reset_for_reuse the reborn NPC heals on its very first hit, whatever
## cooldown the designer authored.
func test_self_healer_reset_lets_a_reused_npc_heal_on_its_first_hit() -> void:
	var host := _HealHost.new()
	host.inventory = CharacterInventory.new()
	var kit := Item.new()
	kit.category = Item.Category.CONSUMABLE
	kit.heal_amount = 30.0
	kit.max_stack = 5
	host.inventory.add(kit, 3)
	var healer := SelfHealer.new()
	healer.cooldown_ms = 600_000  # a long authored cooldown: the rewind must clear ANY configured window
	healer.react(host)
	assert_eq(host.inventory.count_of(kit), 2, "sanity: the previous life spends one medkit, arming the cooldown")
	host.hp = 20.0
	healer.react(host)
	assert_eq(host.inventory.count_of(kit), 2, "control: the same body inside that cooldown does not heal")
	healer.reset_for_reuse()
	healer.react(host)
	assert_eq(host.inventory.count_of(kit), 1, "a reused NPC reaches for a medkit on its first hit in the new life")
	assert_almost_eq(host.hp, 50.0, 0.0001, "...and the heal actually lands")
	healer.free()
	host.inventory.free()
	kit = null

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
	# CONTROL first: a run that met every invariant passes. Then each invariant is broken ON ITS OWN from that same
	# passing report, so a verdict that silently dropped any one condition would stay green for that case.
	assert_true(_passing_reuse_report().pool_stable(), "control: start == final == warmed -> the pool never grew")
	assert_true(_passing_reuse_report().ok(), "control: all invariants met -> ok")

	var no_nav := _passing_reuse_report()
	no_nav.nav_ready = false
	assert_false(no_nav.ok(), "the navmesh never synced -> INCONCLUSIVE, which must never read as a pass")

	var nothing_warmed := _passing_reuse_report()
	nothing_warmed.warmed = 0
	nothing_warmed.pool_count_start = 0
	nothing_warmed.pool_count_final = 0
	assert_true(nothing_warmed.pool_stable(), "precondition: an empty pool is trivially 'stable' (0 -> 0)")
	assert_false(nothing_warmed.ok(), "a pool warmed with ZERO bodies proved nothing about reuse -> not ok")

	var grew := _passing_reuse_report()
	grew.pool_count_final = 5
	assert_false(grew.pool_stable(), "a pool that ended with more bodies than it was warmed with is not stable")
	assert_false(grew.ok(), "a leak (the pool grew across cycles) fails the verdict")

	var short_warm := _passing_reuse_report()
	short_warm.pool_count_start = 2
	assert_false(short_warm.pool_stable(), "a pool that started short of its warm count is not stable")
	assert_false(short_warm.ok(), "...and fails the verdict")

	var fresh_instances := _passing_reuse_report()
	fresh_instances.reused_all_same = false
	assert_false(fresh_instances.ok(), "a re-spawn that handed back a FRESH instance instead of a pooled one fails the verdict")

	var dirty_reset := _passing_reuse_report()
	dirty_reset.reset_clean = false
	assert_false(dirty_reset.ok(), "a reused body that came back with stale state fails the verdict")


## A report for a run that met every invariant — the baseline each case in the verdict test breaks one thing from.
func _passing_reuse_report() -> NpcPoolReuseReport:
	var r := NpcPoolReuseReport.new()
	r.nav_ready = true
	r.warmed = 3
	r.pool_count_start = 3
	r.pool_count_final = 3
	r.reused_all_same = true
	r.reset_clean = true
	return r
