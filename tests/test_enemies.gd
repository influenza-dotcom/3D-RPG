extends GutTest

## Unit tests for the "Enemies" subsystem: perception.gd, death.gd and damage.gd (all under res://scripts/npc/),
## plus the enemy-facing slice of npc.gd. The old enemy.gd / ranged_enemy.gd pair folded into npc.gd, so every
## "Enemy" / "RangedEnemy" below IS an NPC built from that one script.
##
## WHAT THIS COVERS
##  - Perception (class_name Perception): the State enum shape and every state-machine transition reachable with
##    target == null (UNAWARE stays UNAWARE, alert_to forces ALERTED, ALERTED -> INVESTIGATING when unseen,
##    INVESTIGATING -> UNAWARE on the forget timeout, DETECTING draining to UNAWARE, refresh_investigation). And
##    IN-TREE, with a real Node3D target in an otherwise empty world (an empty world is a clear line of sight, so only
##    the cone and the range decide): the shipped defaults behaving as a fair sensor (a cone ahead, a finite range, a
##    reaction window before ALERTED), the pursuit grace that keeps an ALERTED enemy chasing after LOS breaks, and a
##    zero grace giving up at once on a target that is still live.
##  - NPC, built off-tree via load(path).new() WITHOUT add_child so _ready() never runs: the defaults that are SHIP
##    decisions (civilian by default, laser telegraph + hearing on), the tuning invariants the design needs (a view
##    cone, a reaction window, neutral rate factor, air control weaker than ground), is_off_guard driven through a
##    real code-built Perception, aim_error_spread against a DIALLED GameSettings cone (and the off-tree Player's
##    zero cone under the same dial), the aim-ray reach relation,
##    the Locomotor hop/launch statics npc.gd forwards, and the AI method surface (has_method is sanctioned here:
##    an NPC's _ready cannot run headless, and NpcCombat / GOAP call these duck-typed).
##  - enemy.tscn as scene DATA (instantiate() without the tree): the authored hit/death signal rows resolve to real
##    handlers, and the headshot zone + eye line sit inside the prefab's own capsule.
##  - death.gd / damage.gd: type identity, plus death.gd's death_cry export DECLARATION (the scenes wire it by name;
##    its value is pinned in test_smoke.gd).
##  - death.gd's _on_enemy_died() DRIVEN FOR REAL, end to end: an in-tree Character whose crit latches were
##    set through the real take_damage, a real Death child, and an assertion that the crowd cheer actually
##    lands in the tree on an all-headshot kill and stays silent on a body shot. Plus the gore splash's
##    self-free, and the enemy.tscn `died` -> Death connection that fires the whole thing.
##
## WHAT THIS DELIBERATELY SKIPS (and why)
##  - The Perception hostility gate and hearing POSITIVES: tests/test_hostility.gd and
##    tests/test_perception_hearing_buffer.gd own them.
##  - NPC apply_velocity / _physics_process / _ready / _act_alerted / _move_toward / _aim_* / _on_spotted /
##    _on_died / _on_damaged INVOCATION: these need an in-tree CharacterBody3D under physics, instantiate
##    weapon.tscn, add_child a muzzle/weapon/NavigationAgent3D, read GameSettings.physics_damage.*, write
##    Engine.time_scale (FreezeFrame), mutate a shared static cooldown, or play real audio. Their presence is pinned
##    (method surface + the enemy.tscn connection rows) but they are never called.
##  - damage.gd's _on_enemy_damaged INVOCATION (it needs a real hurt-cry stream); its WIRING is pinned by the
##    enemy.tscn connection test. death.gd's _on_enemy_died is NO LONGER skipped — see the invocation tests below:
##    while it went untested death.gd could have stopped calling _play_applause() with the whole suite still green.
##  - enemy.tscn's blast_damp_divisor == 1.0 SCENE override: covered by test_smoke.gd.

## The shipped GameSettings.npc_ai.aim_error_deg, restored after every test (the aim-error test dials it).
var _saved_aim_error_deg: float = 0.0


func before_each() -> void:
	_saved_aim_error_deg = GameSettings.npc_ai.aim_error_deg


func after_each() -> void:
	GameSettings.npc_ai.aim_error_deg = _saved_aim_error_deg


# ---------------------------------------------------------------------------
# Perception — State enum + shipped defaults. Perception has no _ready, so a bare .new() never errors; the
# off-tree tests keep target unset (sense() never reaches physics), the in-tree ones use an empty world.
# ---------------------------------------------------------------------------

func test_perception_state_enum_has_four_ordered_members() -> void:
	# The owner's _physics_process matches on these exact ordinals; a reorder or a missing
	# member would silently misroute every AI state, so pin both the count and the values.
	assert_eq(Perception.State.size(), 4,
		"Perception.State must have exactly 4 members — the AI state machine branches on each one")
	assert_eq(Perception.State.UNAWARE, 0,
		"State.UNAWARE must be 0 (the initial/idle state the enemy resets to)")
	assert_eq(Perception.State.DETECTING, 1,
		"State.DETECTING must be 1 (meter-filling 'noticing you' state that fires just_spotted)")
	assert_eq(Perception.State.ALERTED, 2,
		"State.ALERTED must be 2 (fully locked-on / fire-ready state)")
	assert_eq(Perception.State.INVESTIGATING, 3,
		"State.INVESTIGATING must be 3 (wary-at-last-known-spot state)")


func test_fresh_perception_starts_unaware_and_stays_wary_after_losing_you() -> void:
	var p := Perception.new()  # no add_child: target-less, so sense() only runs the float-math arms
	assert_eq(p.state, Perception.State.UNAWARE,
		"A fresh Perception must start UNAWARE — an enemy isn't born already alerted")
	assert_eq(p.detection, 0.0,
		"The awareness meter must start empty (0.0) so a glimpse isn't an instant alert")
	assert_true(p.hearing,
		"SHIP DECISION: hearing is on by default, so an enemy reacts to gunfire / running outside its view cone out of the box")
	# The default forget_time must buy a real search: lose the target, then keep looking past the next frame.
	p.alert_to(Vector3.ZERO)  # -> ALERTED
	p.sense(0.016)            # unseen (no target) -> INVESTIGATING, the default forget_time armed
	p.sense(0.016)            # one more unseen frame
	assert_eq(p.state, Perception.State.INVESTIGATING,
		"with the default forget_time an enemy that loses you keeps searching past the next frame — it must not forget you instantly")
	p.free()


func test_default_perception_sees_a_cone_ahead_within_range_after_a_reaction_window() -> void:
	# The shipped Perception defaults must add up to a FAIR sensor: a view CONE (sneaking up from behind works), a
	# finite sight_range (distance is cover), and a reaction window before a sighting becomes a lock. In-tree because
	# can_see() raycasts; the world is empty, so the ray is always clear and only the cone + range decide. The target
	# rides at eye level so the distances below are exactly the distances the range gate measures.
	var p := Perception.new()
	add_child_autofree(p)
	var target := Node3D.new()
	add_child_autofree(target)
	p.target = target
	target.global_position = Vector3(0.0, p.eye_height, 5.0)  # dead ahead: +Z is the model's front
	assert_true(p.can_see(),
		"control: a target 5 m dead ahead in a clear world must be seen with the default range and cone")
	# Off-axis on purpose: an EXACTLY-behind point (0, eye, -5) measures 180.000005 degrees through float32
	# Vector3.angle_to, so even an all-round 360-degree fov would refuse it and this check could never catch a cone
	# widened to all-round vision. (3, eye, -4) is still 5 m away and ~143 degrees off the facing: plainly behind.
	target.global_position = Vector3(3.0, p.eye_height, -4.0)
	assert_false(p.can_see(),
		"the default fov is a CONE, not all-round vision: the same target 5 m BEHIND (diagonally) must be unseen")
	target.global_position = Vector3(0.0, p.eye_height, p.sight_range - 0.5)
	assert_true(p.can_see(), "a target just inside the default sight_range, dead ahead, must still be seen")
	target.global_position = Vector3(0.0, p.eye_height, p.sight_range + 0.5)
	assert_false(p.can_see(), "a target just beyond the default sight_range must be unseen — distance is cover")
	# Reaction window: coming into view only NOTICES (DETECTING); another frame in view still hasn't locked on; a full
	# detection time of continuous sight does.
	target.global_position = Vector3(0.0, p.eye_height, 5.0)
	p.sense(0.016)
	assert_eq(p.state, Perception.State.DETECTING,
		"a target coming into view is NOTICED first (DETECTING) — never an instant ALERTED")
	p.sense(0.016)
	assert_eq(p.state, Perception.State.DETECTING,
		"one more frame in view must not lock on: the default time_to_detect gives the player a reaction window")
	p.sense(p.time_to_detect * 2.0)
	assert_eq(p.state, Perception.State.ALERTED,
		"a sighting held past the full detection time does lock on — the window is finite, not a blind spot")


func test_perception_refresh_investigation_holds_the_giveup_clock() -> void:
	# The owner calls refresh_investigation() each frame it's still WALKING to the last-known spot, so
	# forget_time measures time actually SEARCHING there — without it a distant enemy burned its whole
	# budget en route and gave up on arrival ("enemies don't really investigate").
	var p := Perception.new()  # no add_child: pure state-machine fields, no physics
	p.state = Perception.State.INVESTIGATING
	p._investigate_t = 0.4  # nearly given up mid-walk...
	p.refresh_investigation()
	assert_eq(p._investigate_t, p.forget_time,
		"refresh while traveling re-arms the full forget_time, so the search clock starts on ARRIVAL")
	p.state = Perception.State.UNAWARE
	p._investigate_t = 0.0
	p.refresh_investigation()
	assert_eq(p._investigate_t, 0.0,
		"refresh is a no-op outside INVESTIGATING — it must never resurrect a finished investigation")
	p.free()


# ---------------------------------------------------------------------------
# Perception — just_spotted signal + safe (target-less) transition logic.
# The off-tree tests keep target unset so can_see()/can_hear() return at their
# is_instance_valid(target) guards and sense() never reaches physics; the two pursuit-grace
# tests are the in-tree exceptions (they need a live target to lose sight of).
# ---------------------------------------------------------------------------

func test_perception_just_spotted_does_not_fire_without_target() -> void:
	# just_spotted only emits on ENTERING DETECTING, which requires can_see()==true; with no
	# target can_see() early-returns false, so the signal must stay silent. This both proves
	# the signal exists (watch_signals would fail on an unknown signal) and that an idle,
	# target-less enemy never spuriously plays the MGS "!" sting.
	var p := Perception.new()  # no add_child: keep _ready/physics out of it
	watch_signals(p)
	p.sense(0.016)
	p.sense(0.016)
	assert_signal_not_emitted(p, "just_spotted",
		"just_spotted must NOT fire while there is no target — it gates the alert sting on actually seeing you")
	p.free()


func test_perception_sense_unaware_stays_unaware_with_no_target() -> void:
	var p := Perception.new()  # no add_child
	p.sense(0.1)
	assert_eq(p.state, Perception.State.UNAWARE,
		"With nothing seen or heard, UNAWARE must stay UNAWARE — no target means no reason to react")
	assert_eq(p.detection, 0.0,
		"The detection meter must remain empty while UNAWARE with no perception")
	p.free()


func test_perception_alert_to_forces_alerted() -> void:
	# alert_to() is the 'just got shot — instantly know roughly where you are' hook. It must
	# hard-set ALERTED + a full meter + the supplied position, with no physics involved.
	var p := Perception.new()  # no add_child
	p.alert_to(Vector3(1, 2, 3))
	assert_eq(p.state, Perception.State.ALERTED,
		"alert_to() must force ALERTED so a hit can't be a free backstab")
	assert_eq(p.detection, 1.0,
		"alert_to() must fill the meter to 1.0 (fully alert) immediately")
	assert_eq(p.last_known_position, Vector3(1, 2, 3),
		"alert_to() must record the passed position as the last-known spot to turn toward")
	p.free()


func test_perception_forget_clears_to_unaware() -> void:
	# forget() is the 'no valid target -> oblivious' reset the NPC calls in its no-target frame, so a stale
	# ALERTED/INVESTIGATING from an abruptly-lost target can't mislead the GOAP planner into a targetless combat
	# action. It must hard-drop to UNAWARE with a cleared meter, no physics involved.
	var p := Perception.new()  # no add_child
	p.state = Perception.State.ALERTED
	p.detection = 1.0
	p.forget()
	assert_eq(p.state, Perception.State.UNAWARE,
		"forget() must drop to UNAWARE so the no-target idle floor (Hold) is what the executor selects")
	assert_eq(p.detection, 0.0,
		"forget() must clear the detection meter so a returned target is re-detected, not instantly re-locked")
	p.free()


func test_perception_alerted_drops_to_investigating_when_unseen() -> void:
	# The ALERTED arm reads only `seen`; with target==null seen is false, so it must hand off
	# to INVESTIGATING (turn toward the last-known spot) while holding detection at 1.0. This
	# path never calls _target_point()/physics.
	var p := Perception.new()  # no add_child
	p.alert_to(Vector3.ZERO)            # -> ALERTED
	p.sense(0.016)                      # unseen -> INVESTIGATING
	assert_eq(p.state, Perception.State.INVESTIGATING,
		"Losing sight of an ALERTED target must drop to INVESTIGATING, not vanish to UNAWARE")
	assert_eq(p.detection, 1.0,
		"The ALERTED arm pins detection to 1.0 before handing off, so it re-locks fast if seen again")
	p.free()


func test_perception_investigating_times_out_to_unaware() -> void:
	# INVESTIGATING with nothing seen/heard only does float math + an _investigate_t countdown;
	# once that timer runs out it must forget (UNAWARE, empty meter). No _target_point()/physics.
	var p := Perception.new()  # no add_child
	p.forget_time = 1.0
	p.alert_to(Vector3.ZERO)            # -> ALERTED
	p.sense(0.016)                      # unseen -> INVESTIGATING, arms _investigate_t = forget_time
	assert_eq(p.state, Perception.State.INVESTIGATING,
		"Precondition: one unseen tick from ALERTED must land in INVESTIGATING before the timeout test")
	p.sense(2.0)                        # delta > forget_time, still unseen -> times out
	assert_eq(p.state, Perception.State.UNAWARE,
		"INVESTIGATING must give up to UNAWARE once forget_time elapses with nothing perceived")
	assert_eq(p.detection, 0.0,
		"Forgetting the target must clear the detection meter to 0.0")
	p.free()


func test_pursuit_grace_keeps_alerted_after_los_loss_then_downgrades() -> void:
	# The "follow me off a ledge" fix: losing sight of an ALERTED target must NOT instantly drop to INVESTIGATING.
	# For pursuit_grace_time the enemy stays ALERTED (so GOAP keeps pursuing your LIVE position off the rim) and
	# last_known_position TRACKS the live target, so a grace that expires searches where you WENT, not where LOS broke.
	# In-tree (can_see() raycasts): an EMPTY world = clear LOS, so "seen" toggles purely by moving the target in/out of
	# the view cone — no occluder geometry needed. Mirrors the ledge drop, where the lip occludes LOS the same way.
	var p := Perception.new()
	add_child_autofree(p)
	p.pursuit_grace_time = 0.5
	p.forget_time = 4.0
	var target := Node3D.new()
	add_child_autofree(target)
	target.global_position = Vector3(0.0, 0.0, 5.0)  # in front (+Z = model front), in range, clear LOS -> can_see() true
	p.target = target
	p.target_body = target
	# Enter ALERTED with the target in view, and let one seen tick arm the grace.
	p.state = Perception.State.ALERTED
	p.detection = 1.0
	p.sense(0.1)
	assert_eq(p.state, Perception.State.ALERTED, "precondition: a seen ALERTED tick stays ALERTED and arms the coast")
	# Break line of sight WITHOUT leaving range: swing the target behind the enemy (out of the horizontal view cone).
	target.global_position = Vector3(0.0, 0.0, -5.0)
	p.sense(0.1)
	assert_eq(p.state, Perception.State.ALERTED,
		"within pursuit_grace_time a just-lost ALERTED target keeps the enemy ALERTED (pursuing), not INVESTIGATING")
	assert_almost_eq(p.last_known_position.z, -5.0, 0.01,
		"during the grace, last_known_position tracks the LIVE target, so a grace expiry searches where you went")
	# Let the grace clock run out with the target still unseen -> NOW it downgrades to the last-known search.
	p.sense(1.0)
	assert_eq(p.state, Perception.State.INVESTIGATING,
		"once pursuit_grace_time elapses still unseen, the enemy downgrades to INVESTIGATING the last-known spot")
	assert_eq(p._investigate_t, p.forget_time,
		"the downgrade arms the full forget_time search clock, exactly as the old instant give-up did")


## An in-tree Perception with `grace` s of pursuit grace, locked on (ALERTED) to a LIVE target dead ahead for one seen
## tick (which re-arms the grace clock), then the target swung behind it (out of the view cone, still 5 m away and
## still valid) and ONE short unseen tick sensed. Returns the state that tick lands in. An empty world = clear LOS, so
## the cone alone decides "seen".
func _state_after_one_unseen_tick(grace: float) -> Perception.State:
	var p := Perception.new()
	add_child_autofree(p)
	p.pursuit_grace_time = grace
	var target := Node3D.new()
	add_child_autofree(target)
	target.global_position = Vector3(0.0, p.eye_height, 5.0)  # dead ahead (+Z = model front), in range
	p.target = target
	p.state = Perception.State.ALERTED
	p.detection = 1.0
	p.sense(0.016)
	assert_eq(p.state, Perception.State.ALERTED,
		"precondition (grace %s s): a seen ALERTED tick stays ALERTED and re-arms the pursuit grace" % grace)
	target.global_position = Vector3(3.0, p.eye_height, -4.0)  # behind, off-axis: out of the cone, same 5 m
	p.sense(0.016)
	return p.state


func test_pursuit_grace_zero_preserves_instant_giveup() -> void:
	# Regression guard: pursuit_grace_time = 0 must reproduce the OLD behaviour — one unseen tick from ALERTED lands
	# straight in INVESTIGATING (no coast), even though the target is still live and the seen tick before it just
	# re-armed the grace clock. The target must be LIVE for this to mean anything: with a null target the ALERTED arm
	# drops to INVESTIGATING through its is_instance_valid(target) check whatever the grace is.
	assert_eq(_state_after_one_unseen_tick(0.5), Perception.State.ALERTED,
		"control: with a 0.5 s grace the same live target lost for one 16 ms tick keeps the enemy ALERTED, so the drop below comes from the zero grace, not from losing the target")
	assert_eq(_state_after_one_unseen_tick(0.0), Perception.State.INVESTIGATING,
		"with grace 0, losing an ALERTED target drops to INVESTIGATING on the first unseen tick (legacy contract)")


func test_perception_detecting_meter_drains_to_unaware_when_unseen() -> void:
	# Drive the DETECTING arm directly: a partially-filled meter must drain by the rate math and,
	# once empty with nothing heard, fall back to UNAWARE. seen=false means no _target_point() call.
	var p := Perception.new()  # no add_child
	p.state = Perception.State.DETECTING
	p.detection = 0.05
	p.time_to_detect = 1.0
	p.sense(1.0)                        # unseen: drains, clamps to 0.0, not heard -> UNAWARE
	assert_eq(p.state, Perception.State.UNAWARE,
		"A DETECTING meter that drains to empty with nothing heard must revert to UNAWARE")
	assert_eq(p.detection, 0.0,
		"The drained meter must clamp at 0.0 (never negative)")
	p.free()


func test_perception_can_see_and_can_hear_false_without_target() -> void:
	# Both sensors guard on is_instance_valid(target) before any world/physics access, so a
	# target-less Perception must report no perception — the only safe (physics-free) assertion.
	var p := Perception.new()  # no add_child
	assert_false(p.can_see(),
		"can_see() must return false with no target — it bails at the is_instance_valid(target) guard before any ray")
	assert_false(p.can_hear(),
		"can_hear() must return false with no target even though hearing defaults true")
	p.free()


# ---------------------------------------------------------------------------
# enemy.tscn as scene DATA — instantiate() WITHOUT add_child, so no _ready runs
# (the node paths and exported values resolve at instantiate time).
# ---------------------------------------------------------------------------

func test_enemy_scene_hit_and_death_rows_resolve_to_real_handlers() -> void:
	# The prefab wires its hit / death reactions as [connection] rows that name a method BY STRING. Rename a handler
	# on either script, or drop a row, and nothing fails to parse: the NPC just stops reacting (no hurt cry, no kill
	# freeze-frame, no death splash). Resolve every row against the instantiated nodes, then require the three rows
	# the hit/death reactions hang off (died -> Death._on_enemy_died has its own test below).
	var packed := load("res://scenes/characters/enemy.tscn") as PackedScene
	assert_true(packed != null, "enemy.tscn must load")
	if packed == null:
		return
	var state := packed.get_state()
	var root := packed.instantiate()
	var wired: Array[String] = []
	for i in state.get_connection_count():
		var source := root.get_node_or_null(state.get_connection_source(i))
		var target := root.get_node_or_null(state.get_connection_target(i))
		var sig := state.get_connection_signal(i)
		var method := state.get_connection_method(i)
		assert_true(source != null and source.has_signal(sig),
			"enemy.tscn row `%s` -> %s: the source node %s must exist and declare that signal" % [sig, method, state.get_connection_source(i)])
		assert_true(target != null and target.has_method(method),
			"enemy.tscn row `%s` -> %s: the target node %s must exist and actually define that handler, or the reaction silently never runs" % [sig, method, state.get_connection_target(i)])
		wired.append("%s:%s->%s" % [sig, state.get_connection_target(i), method])
	assert_has(wired, "damaged:.->_on_damaged",
		"enemy.tscn must connect `damaged` to the NPC's own _on_damaged (the hit reaction: turn toward the shooter)")
	assert_has(wired, "died:.->_on_died",
		"enemy.tscn must connect `died` to the NPC's own _on_died (kill freeze-frame, witness barks, loot corpse, XP)")
	assert_has(wired, "damaged:Damage->_on_enemy_damaged",
		"enemy.tscn must connect `damaged` to the Damage node's _on_enemy_damaged, or every hit lands with no hurt cry")
	root.free()


func test_enemy_head_zone_and_eye_line_sit_inside_the_capsule_head() -> void:
	# head_local_y and eye_height are both measured UP from the NPC origin, which on this prefab is the CAPSULE CENTRE,
	# not the feet. Both must land in the upper half of the prefab's OWN capsule: a head zone below the centre turns
	# chest hits into headshots and one above the crown makes headshots impossible; an eye line above the crown is the
	# old 1.4 bug (NPCs saw and heard over cover their heads were visibly behind). The eyes sit in the head, so the eye
	# line is above the base of the head zone.
	var packed := load("res://scenes/characters/enemy.tscn") as PackedScene
	assert_true(packed != null, "enemy.tscn must load")
	if packed == null:
		return
	var enemy := packed.instantiate() as NPC
	assert_true(enemy != null, "enemy.tscn's root must be an NPC")
	if enemy == null:
		return
	var col := enemy.get_node_or_null(^"CollisionShape3D") as CollisionShape3D
	var cap: CapsuleShape3D = col.shape as CapsuleShape3D if col != null else null
	assert_true(cap != null, "enemy.tscn must carry its CollisionShape3D capsule (the body every hit and ray measures)")
	if cap != null:
		var centre_y := col.position.y
		var crown_y := centre_y + cap.height * 0.5
		assert_gt(enemy.head_local_y, centre_y,
			"the headshot zone must start ABOVE the capsule centre, or a chest hit counts as a headshot")
		assert_lt(enemy.head_local_y, crown_y,
			"the headshot zone must start BELOW the capsule crown, or no hit on this body can ever be a headshot")
		assert_gt(enemy.eye_height, enemy.head_local_y,
			"the eye line must sit inside the head zone — eyes below the base of the skull would see from the chest")
		assert_lt(enemy.eye_height, crown_y,
			"the eye line must stay under the capsule crown, or the NPC sees and hears over cover its head is visibly behind")
	enemy.free()


# ---------------------------------------------------------------------------
# NPC (the folded Enemy / RangedEnemy) — defaults, off-guard, aim cone, method
# surface. Loaded via load(path).new() WITHOUT add_child: its real _ready()
# instantiates weapon.tscn, add_childs a muzzle/weapon/nav, and calls get_tree()
# — none of which is safe in a unit test.
# ---------------------------------------------------------------------------

func test_is_off_guard_until_its_perception_locks_on() -> void:
	# Sneak-attack eligibility: an NPC is off guard while UNAWARE, DETECTING or INVESTIGATING, and loses it the moment
	# it locks on (ALERTED). An NPC with no Perception yet (off-tree / before _ready) is never an ambush target.
	var n = load("res://scripts/npc/npc.gd").new()  # no add_child: _ready never runs, so _perception starts null
	assert_false(n.is_off_guard(),
		"an NPC with no Perception yet must NOT read as off guard — the null guard, not a free sneak-attack crit")
	n._build_perception()  # the real code-built Perception child, configured from the NPC's exports (off-tree safe)
	for s in [Perception.State.UNAWARE, Perception.State.DETECTING, Perception.State.INVESTIGATING]:
		n._perception.state = s
		assert_true(n.is_off_guard(),
			"an NPC whose Perception is %s has not locked on yet, so it must be off guard (sneak-attack eligible)" % Perception.State.keys()[s])
	n._perception.state = Perception.State.ALERTED
	assert_false(n.is_off_guard(),
		"once ALERTED (locked on and engaging) the NPC is no longer off guard — no more free sneak damage")
	n.free()


func test_npc_exported_defaults_ship_a_fair_civilian() -> void:
	var n = load("res://scripts/npc/npc.gd").new()  # no add_child: _ready MUST NOT run
	# Ship decisions (player-facing on/off defaults).
	assert_null(n.weapon_data,
		"SHIP DECISION: a bare NPC is a CIVILIAN (weapon_data null) — a combatant scene opts in by assigning a weapon")
	assert_true(n.show_laser,
		"SHIP DECISION: the laser-sight telegraph is on by default, so an armed NPC visibly warns before it fires")
	assert_true(n.hearing,
		"SHIP DECISION: NPCs hear noise outside their view cone by default")
	# Stealth fairness invariants the defaults must satisfy (these are copied onto the NPC's Perception).
	assert_gt(n.time_to_detect, 0.0,
		"time_to_detect must be > 0: a spotted player always gets a reaction window instead of an instant lock")
	assert_gt(n.fov_degrees, 0.0, "fov_degrees must be > 0 or the NPC is blind")
	assert_lt(n.fov_degrees, 360.0,
		"fov_degrees must stay under 360: the view is a CONE, so approaching from behind can stay unseen")
	assert_gt(n.forget_time, 0.0, "forget_time must be > 0 so an NPC that loses you searches before it gives up")
	# Combat / movement invariants.
	assert_true(n.miss_chance >= 0.0 and n.miss_chance <= 1.0,
		"miss_chance is a per-shot probability and must sit in [0, 1]")
	assert_true(n.engage_range_fraction > 0.0 and n.engage_range_fraction <= 1.0,
		"engage_range_fraction must be in (0, 1]: the NPC closes to WITHIN its weapon's range before holding, never stands off out of range")
	assert_lt(n.air_accel, n.move_accel,
		"air_accel must be weaker than ground move_accel, so a blast carries the NPC before it recovers")
	var gun := WeaponData.new()
	gun.attack_speed = 0.7
	assert_almost_eq(NPC.shot_interval_for(gun, n.rate_of_fire_factor, 0.0), gun.attack_speed, 0.0001,
		"the default rate_of_fire_factor is NEUTRAL: an NPC fires at its weapon's own authored attack_speed until a designer dials difficulty")
	assert_almost_eq(n.jump_velocity, GameSettings.player_movement.jump_velocity, 0.0001,
		"the default NPC hop matches the Player's basic jump, so it vaults the same ledges you do (jump_velocity_for_climb scales it up for taller ones)")
	n.free()
	gun = null


## The stat half of "NPCs are not aimbots" (2026-08-25): aim_error_spread is the per-shot cone (radians)
## attack.gd adds to every ranged pellet an NPC fires. Base = GameSettings.npc_ai.aim_error_deg, scaled by
## the SAME CharacterStats.sway_mult formula the player's aim wander uses — so WHO the NPC is (its NpcData
## stat sheet's gunplay) decides how well it shoots. Off-tree .new() per the header rule. The base cone is
## DIALLED to a known 10 degrees (after_each restores the shipped tuning), so the expectations are independent
## numbers rather than the method's own formula re-typed.
func test_npc_aim_error_spread_scales_with_gunplay() -> void:
	GameSettings.npc_ai.aim_error_deg = 10.0
	var base_rad := deg_to_rad(10.0)
	var n = load("res://scripts/npc/npc.gd").new()  # no add_child: _ready MUST NOT run
	assert_almost_eq(n.aim_error_spread(), base_rad, 0.000001,
		"a sheetless NPC (stats null -> baseline gunplay, sway_mult 1.0) sprays the FULL dialled cone")
	var marksman := CharacterStats.new()
	marksman.gunplay = 5  # sway_mult 0.6 — the same 8%-per-point steadiness the player's aim wander uses
	n.stats = marksman
	assert_almost_eq(n.aim_error_spread(), base_rad * 0.6, 0.000001,
		"gunplay 5 shoots 40% tighter — the identical sway_mult formula, so stats mean the same thing on both sides of a fight")
	var elite := CharacterStats.new()
	elite.gunplay = 20  # sway_mult floors at 0.0 — perfectly accurate, never negative (an inverted cone)
	n.stats = elite
	assert_almost_eq(n.aim_error_spread(), 0.0, 0.000001,
		"very high gunplay floors the cone at 0 — an elite is surgical, and the mult can never go negative")
	n.stats = null
	GameSettings.npc_ai.aim_error_deg = -5.0
	assert_almost_eq(n.aim_error_spread(), 0.0, 0.000001,
		"a negative aim_error_deg dial means NO cone — never a negative (inverted) spread")
	n.free()
	marksman = null
	elite = null


## The PLAYER side of the same seam must stay 0: its accuracy already runs through AimSway/bloom, so a second cone
## would double-punish. Asked of a real Player (off-tree, never _ready'd), the class attack.gd actually calls, with
## the base cone DIALLED to 10 degrees (after_each restores it): a cone that reached the Player, through its own
## override or through the Character base it inherits, reads non-zero here. The NPC control shows the same dial
## does produce a cone, so the Player's 0 is not just an undialled setting.
func test_player_fires_with_no_aim_error_cone() -> void:
	GameSettings.npc_ai.aim_error_deg = 10.0
	var n = load("res://scripts/npc/npc.gd").new()  # no add_child: _ready MUST NOT run
	assert_gt(n.aim_error_spread(), 0.0,
		"control: with aim_error_deg dialled to 10 an NPC adds a real aim-error cone to its shots")
	n.free()
	var p = load("res://scripts/player/player.gd").new()  # no add_child: Player._ready MUST NOT run
	assert_eq(p.aim_error_spread(), 0.0,
		"the Player must add NO aim-error cone under the same dial: its accuracy already runs through AimSway / bloom, and a second cone would double-punish")
	p.free()


func test_unequipped_aim_ray_reaches_at_least_as_far_as_the_npc_sees() -> void:
	# _aim_range() is the length of the clear-shot ray and of the laser. A shot only reads CLEAR when that ray's hit is
	# the target's own collider, so a reach shorter than the NPC's sight would leave it staring at a target it can see
	# with a ray that stops in mid-air: never a clear shot, a laser ending short of you. With nothing equipped there
	# is no weapon range to scale from, so the fallback reach must still cover the sight range.
	var n = load("res://scripts/npc/npc.gd").new()  # no add_child: _weapon stays null -> the fallback reach
	assert_gte(n._aim_range(), n.sight_range,
		"an NPC with no equipped weapon must still cast its aim ray at least sight_range far, or a target it can see is never a clear shot")
	n.free()


func test_jump_velocity_for_climb_scales_launch_to_target_height() -> void:
	# Pure static physics (no instance): jump_velocity is the MINIMUM pop, and a taller target gets a stronger launch
	# sized to reach its height — so a hostile NPC jumps UP onto your ledge instead of falling short under you.
	# A low climb the base pop already clears stays at the base 4.5 m/s (no needless extra launch).
	assert_almost_eq(NPC.jump_velocity_for_climb(0.5, 9.8, 4.5), 4.5, 0.001,
		"a climb the base pop already clears must keep the base jump_velocity (don't over-launch a low crate)")
	# A target above the base reach gets a launch whose apex (v^2/2g) actually reaches the target height, not short.
	var v := NPC.jump_velocity_for_climb(2.0, 9.8, 4.5)
	assert_gt(v, 4.5,
		"a target above the base reach must get a STRONGER launch than jump_velocity (reach your height)")
	assert_gte((v * v) / (2.0 * 9.8), 2.0,
		"the scaled launch's apex (v^2/2g) must actually reach the target climb, not stop short of it")
	# Taller target -> taller launch (monotonic in climb), so the impulse tracks how high you are.
	assert_gt(NPC.jump_velocity_for_climb(3.0, 9.8, 4.5), NPC.jump_velocity_for_climb(2.0, 9.8, 4.5),
		"a higher target must demand a higher launch so the hop tracks your height")
	# Degenerate inputs fall back to the base pop instead of NaN/zero: a non-positive climb, and zero-gravity areas.
	assert_almost_eq(NPC.jump_velocity_for_climb(0.0, 9.8, 4.5), 4.5, 0.001,
		"a non-positive climb must return the base pop (nothing to scale toward)")
	assert_almost_eq(NPC.jump_velocity_for_climb(2.0, 0.0, 4.5), 4.5, 0.001,
		"g <= 0 (zero-gravity area) must fall back to the base pop, never divide by zero")


func test_nav_hop_gate_requires_threatening_nearby_climb() -> void:
	# No upper climb bound any more: a threatening NPC hops at any real climb it's standing next to, scaling the
	# launch to your height (see jump_velocity_for_climb). The gate only rejects same-floor, too-far, and civilians.
	assert_true(NPC.should_nav_hop(true, 4.5, true, 0.0, 0.8, 0.3),
		"a threatening grounded NPC beside a clearable low ledge should hop")
	assert_true(NPC.should_nav_hop(true, 4.5, true, 0.0, 5.0, 0.3),
		"a tall but nearby climb must STILL hop now — the NPC scales its launch to reach you (no out-of-reach cap)")
	assert_false(NPC.should_nav_hop(true, 4.5, true, 0.0, 0.2, 0.3),
		"same-floor / curb-sized height deltas must not make NPCs hop in close combat")
	assert_false(NPC.should_nav_hop(true, 4.5, true, 0.0, 0.8, 2.0),
		"NPCs should only hop when they are actually at the step/raised target")
	assert_false(NPC.should_nav_hop(false, 4.5, true, 0.0, 0.8, 0.3),
		"idle/civilian movement callers keep jumping disabled")
	assert_false(NPC.should_nav_hop(true, 0.0, true, 0.0, 0.8, 0.3),
		"jump_velocity = 0 disables hopping (hop_velocity <= 0 short-circuits)")
	assert_false(NPC.should_nav_hop(true, 4.5, false, 0.0, 0.8, 0.3),
		"an airborne NPC must not re-hop mid-arc (the on_floor gate)")
	assert_false(NPC.should_nav_hop(true, 4.5, true, 0.5, 0.8, 0.3),
		"a hop still on cooldown must not re-fire (the jump_cooldown gate)")


func test_stuck_recovery_hop_gate_is_chase_only() -> void:
	assert_true(NPC.should_stuck_recovery_hop(true, 4.5, true, 0.0, NPC.STUCK_HOP_TIME, 4.0),
		"a hop-capable grounded chaser blocked long enough should try a recovery vault")
	assert_false(NPC.should_stuck_recovery_hop(true, 4.5, true, 0.0, NPC.STUCK_HOP_TIME - 0.01, 4.0),
		"a brief bump is handled by normal pathing/slide, not a jump")
	assert_false(NPC.should_stuck_recovery_hop(false, 4.5, true, 0.0, NPC.STUCK_HOP_TIME, 4.0),
		"idle/civilian movement still never uses the recovery hop")
	assert_false(NPC.should_stuck_recovery_hop(true, 4.5, false, 0.0, NPC.STUCK_HOP_TIME, 4.0),
		"must be grounded to recover-hop")
	assert_false(NPC.should_stuck_recovery_hop(true, 4.5, true, 0.5, NPC.STUCK_HOP_TIME, 4.0),
		"cooldown suppresses repeated pogoing")
	assert_false(NPC.should_stuck_recovery_hop(true, 0.0, true, 0.0, NPC.STUCK_HOP_TIME, 4.0),
		"jump_velocity = 0 disables all hop recovery")


func test_collision_bottom_y_reads_capsule_bottom() -> void:
	var root := Node3D.new()
	add_child_autofree(root)
	root.global_position = Vector3(0.0, 10.0, 0.0)
	var col := CollisionShape3D.new()
	root.add_child(col)
	col.position = Vector3(0.0, -0.25, 0.0)
	var cap := CapsuleShape3D.new()
	cap.height = 2.0
	col.shape = cap
	assert_almost_eq(NPC.collision_bottom_y(root, root.global_position.y), 8.75, 0.001,
		"capsule-bottom math must recover floor height from a character root plus child collider")
	assert_almost_eq(NPC.collision_bottom_y(col, col.global_position.y), 8.75, 0.001,
		"the same bottom math must work when combat passes the target CollisionShape3D directly")


func test_ranged_enemy_ai_method_surface_exists() -> void:
	# Confirm the WeaponHost aim contract + AI hooks are present WITHOUT invoking them (each needs
	# _player/_muzzle/_nav/_weapon and/or live physics, set up only in a real _ready).
	var n = load("res://scripts/npc/npc.gd").new()  # no add_child
	assert_true(n.has_method("is_off_guard"),
		"RangedEnemy must expose is_off_guard() (sneak-attack eligibility)")
	assert_true(n.has_method("_act_alerted"),
		"RangedEnemy must define _act_alerted() (the chase/aim/fire behaviour)")
	assert_true(n.has_method("_move_toward"),
		"RangedEnemy must define _move_toward() (NavigationAgent3D pathing step)")
	assert_true(n.has_method("_aim_laser_at"),
		"RangedEnemy must define _aim_laser_at() (laser sight + clear-shot test)")
	assert_true(n.has_method("get_aim_origin"),
		"RangedEnemy must implement get_aim_origin() for the WeaponHost aim contract")
	assert_true(n.has_method("get_aim_direction"),
		"RangedEnemy must implement get_aim_direction() for the WeaponHost aim contract")
	assert_true(n.has_method("get_aim_basis"),
		"RangedEnemy must implement get_aim_basis() for the WeaponHost aim contract")
	assert_true(n.has_method("_on_spotted"),
		"RangedEnemy must define _on_spotted() (the just_spotted -> alert-sting handler)")
	assert_true(n.has_method("_on_locked_on"),
		"RangedEnemy must define _on_locked_on() (the just_alerted -> charge-sting handler; without it the first charge is silent during the run-in)")
	assert_true(n.has_method("_on_damaged"),
		"RangedEnemy must override _on_damaged() (a hit alerts it toward the shooter)")
	n.free()


# ---------------------------------------------------------------------------
# death.gd / damage.gd — type identity + handler presence, then death.gd's
# _on_enemy_died DRIVEN in-tree under a real Character. These scripts have NO
# class_name, so load by path. The surface tests' bare AudioStreamPlayer3D
# instances are never added to the tree, so .free() (not add_child_autofree).
# ---------------------------------------------------------------------------

func test_death_script_surface() -> void:
	var n = load("res://scripts/npc/death.gd").new()  # no add_child
	assert_true(n is AudioStreamPlayer3D,
		"death.gd must extend AudioStreamPlayer3D (it's the positional death-SFX node on the enemy)")
	assert_true(n.has_method("_on_enemy_died"),
		"death.gd must define _on_enemy_died (wired to the enemy's `died` signal in enemy.tscn)")
	assert_true(n.has_method("_play_applause"),
		"death.gd must define _play_applause (the crit-only kill cheer)")
	# The death_cry EXPORT (the dying NPC's voice, layered over the gore splash). Its authored VALUE lives in the
	# scene and is pinned by test_smoke.gd; what this pins is the export itself, because renaming or dropping it
	# orphans every `death_cry = ExtResource(...)` row already written into enemy.tscn / SliceTestLevel.tscn and
	# they go quiet with no error. Scan the property list rather than reading it: an unset export and a MISSING
	# one both read back as null through .get(), so a read cannot tell the two apart.
	var declares_cry := false
	for prop in n.get_property_list():
		if String(prop.get("name", "")) == "death_cry":
			declares_cry = true
			break
	assert_true(declares_cry,
		"death.gd must declare the death_cry export — the scenes author it by that exact name")
	n.free()


## A concrete, in-tree Character to hang a real Death node off. Character is @abstract with no abstract
## methods, so a plain subclass instantiates (the _Stub / _KillSpy idiom from test_character.gd). Nothing is
## overridden: these tests never kill it, they only set the crit latches that death.gd reads.
class _Victim extends Character:
	pass


## Build an in-tree victim whose _took_any_hit/_all_crits latches were set by the REAL take_damage, with a
## real death.gd node parented under it. max_hp is raised BEFORE add_child so _ready seeds hp from it and the
## hits below stay non-lethal — death.gd reads the latches, not the corpse.
func _victim_with_death_node(crit: bool):
	var victim := _Victim.new()
	victim.max_hp = 1000.0
	add_child_autofree(victim)
	victim.take_damage(1.0, crit)
	var death = load("res://scripts/npc/death.gd").new()
	death.name = &"Death"
	victim.add_child(death)
	return death


## Every AudioStreamPlayer/3D parented DIRECTLY to the tree root — where all four of death.gd's one-shots
## land. Snapshot before and after so a test can tell what THIS call spawned and clean up after itself.
func _root_audio() -> Array[Node]:
	var out: Array[Node] = []
	for n in get_tree().root.get_children():
		if n is AudioStreamPlayer or n is AudioStreamPlayer3D:
			out.append(n)
	return out


## THE REWARD ITSELF, driven end to end. This is the assertion that was missing while the applause was
## suspected of having silently stopped: it is not enough that play_applause() works (test_audio_manager_spawn)
## and that the latches work (test_character) — something has to prove death.gd still JOINS them.
func test_all_crit_kill_actually_plays_the_applause() -> void:
	var death = _victim_with_death_node(true)
	var before := _root_audio()
	death._on_enemy_died()
	var cheered := false
	for n in _root_audio():
		if n in before:
			continue
		if n is AudioStreamPlayer and (n as AudioStreamPlayer).stream == AudioManager.APPLAUSE:
			cheered = true
		n.queue_free()  # these are one-shots parented to the ROOT; they outlive this test if we leave them
	assert_true(cheered,
		"an all-headshot kill must actually reach AudioManager.play_applause() — death.gd is the only thing joining killed_by_only_crits() to the cheer, and nothing else asserts it does")


## The negative half, and the one that makes the test above mean something: if this ever goes green-by-accident
## (an applause on every death) the reward stops being a reward.
func test_body_shot_kill_plays_no_applause() -> void:
	var death = _victim_with_death_node(false)
	var before := _root_audio()
	death._on_enemy_died()
	var cheered := false
	for n in _root_audio():
		if n in before:
			continue
		if n is AudioStreamPlayer and (n as AudioStreamPlayer).stream == AudioManager.APPLAUSE:
			cheered = true
		n.queue_free()
	assert_false(cheered,
		"a kill with any non-crit damage in it must NOT cheer — _all_crits is a one-way latch and death.gd must respect it")


## The gore splash is the ONE sound death.gd hand-rolls instead of routing through AudioManager, so it is also
## the one that must clean up after itself. It is parented to the tree ROOT, so a missing free outlives even a
## level change, and stop_sfx() cannot collect it either (that queue_free is gated on ONE_SHOT_META, which a
## hand-rolled spawn never sets). Regression pin: this exact line was once deleted and nothing noticed.
func test_the_hand_rolled_gore_splash_frees_itself() -> void:
	var death = _victim_with_death_node(true)
	var before := _root_audio()
	death._on_enemy_died()
	var splash: AudioStreamPlayer3D = null
	for n in _root_audio():
		if n in before:
			continue
		if n is AudioStreamPlayer3D and (n as AudioStreamPlayer3D).stream != null 				and (n as AudioStreamPlayer3D).stream.resource_path.ends_with("Spplshh.mp3"):
			splash = n
	assert_not_null(splash,
		"death.gd must still spawn the positional gore splash at the death site")
	if splash == null:
		return
	var frees_itself := false
	for c in splash.finished.get_connections():
		if (c["callable"] as Callable).get_method() == &"queue_free":
			frees_itself = true
	assert_true(frees_itself,
		"the hand-rolled splash must connect finished -> queue_free: it is parented to the tree ROOT, so without it every NPC death leaks a player for the whole session and stop_sfx() cannot reclaim it")
	for n in _root_audio():
		if n not in before:
			n.queue_free()


## The wiring that fires all of the above. A scene-DATA pin (no instantiation): test_smoke asserts the Death
## node exists and carries its death_cry, but nothing asserted the signal that actually calls into it — drop
## this connection and every kill goes completely silent with no error anywhere.
func test_enemy_scene_wires_died_to_the_death_handler() -> void:
	var packed: PackedScene = load("res://scenes/characters/enemy.tscn")
	assert_not_null(packed, "enemy.tscn must load")
	var state := packed.get_state()
	# Guard against a VACUOUS pass: if get_state() ever returns a scene with no connections at all (a format
	# change, an inherited-scene quirk), the loop below would simply not run and `wired` would be false —
	# but a reader would be entitled to assume the opposite. Prove there is real data to scan first.
	assert_gt(state.get_connection_count(), 0,
		"enemy.tscn must declare signal connections at all — a zero count would make the scan below meaningless")
	var wired := false
	for i in state.get_connection_count():
		if state.get_connection_signal(i) == &"died" and state.get_connection_method(i) == &"_on_enemy_died":
			wired = true
			break
	assert_true(wired,
		"enemy.tscn must connect `died` to the Death node's _on_enemy_died — that connection is the ONLY thing that turns a death into the splash, the cry, the cha-ching and the applause")


func test_damage_script_surface() -> void:
	var n = load("res://scripts/npc/damage.gd").new()  # no add_child
	assert_true(n is AudioStreamPlayer3D,
		"damage.gd must extend AudioStreamPlayer3D (the positional hurt-SFX node on the enemy)")
	assert_true(n.has_method("_on_enemy_damaged"),
		"damage.gd must define _on_enemy_damaged (wired to the enemy's `damaged` signal in enemy.tscn)")
	n.free()
