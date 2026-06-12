extends GutTest

## Unit tests for the "Enemies" subsystem: perception.gd, enemy.gd, ranged_enemy.gd,
## death.gd, and damage.gd (all under res://scenes/enemies/).
##
## WHAT THIS COVERS
##  - Perception (class_name Perception): exported defaults + State enum shape, the
##    just_spotted signal's existence and its NON-emission with no target, and every
##    state-machine transition that is reachable with target==null (so sense() never
##    touches physics). Specifically: UNAWARE stays UNAWARE; alert_to() forces ALERTED;
##    ALERTED -> INVESTIGATING when unseen; INVESTIGATING -> UNAWARE on forget timeout;
##    DETECTING meter draining to UNAWARE; and can_see()/can_hear() false guard paths.
##  - Enemy / RangedEnemy: exported SCRIPT defaults + inherited Character API + AI
##    method/constant surface, all via load(path).new() WITHOUT add_child so _ready()
##    never runs.
##  - death.gd / damage.gd: type identity + handler method presence (has_method only).
##
## WHAT THIS DELIBERATELY SKIPS (and why)
##  - Perception.can_see()/can_hear() POSITIVE paths and just_spotted EMISSION: reaching
##    them requires a valid target Node3D plus a live physics World3D
##    (get_world_3d().direct_space_state.intersect_ray) / target.noise_radius math. Off a
##    real scene get_world_3d() is null and intersect_ray errors. We keep target unset in
##    every Perception test and drive transitions by setting state/detection directly, so
##    sense() only ever exercises the guard-only / float-math arms.
##  - Enemy/RangedEnemy apply_velocity / _physics_process / _ready / _act_alerted /
##    _move_toward / _aim_* / _on_spotted / _on_died / _on_damaged INVOCATION: these need
##    an in-tree CharacterBody3D under physics, instantiate weapon.tscn, add_child a
##    muzzle/weapon/NavigationAgent3D, read GameSettings.physics_damage.*, write
##    Engine.time_scale (FreezeFrame), mutate a shared static cooldown, or play real audio.
##    We assert their PRESENCE (has_method) but never call them.
##  - death.gd/damage.gd handler INVOCATION (_on_enemy_died/_play_applause/_on_enemy_damaged):
##    they add_child audio players to the tree, play(), create_tween, and call AudioManager.
##    has_method only.
##  - enemy.tscn blast_damp_divisor==1.0 (the SCENE override) and Character's script-default
##    1.12 on a base Character: already covered by test_smoke.gd. Here we assert ENEMY's own
##    SCRIPT default (1.12, inherited) without instantiating the scene.


# ---------------------------------------------------------------------------
# Perception — exported defaults + State enum (pure: no _ready/_init/@onready,
# no autoloads, so a bare .new() never errors). Instantiate WITHOUT add_child.
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


func test_perception_construction_initial_state_and_defaults() -> void:
	var p := Perception.new()  # no add_child: Perception has no _ready; nothing to trip on
	assert_eq(p.state, Perception.State.UNAWARE,
		"A fresh Perception must start UNAWARE — an enemy isn't born already alerted")
	assert_eq(p.detection, 0.0,
		"The awareness meter must start empty (0.0) so a glimpse isn't an instant alert")
	assert_eq(p.sight_range, 25.0,
		"sight_range default 25.0 m defines how far the enemy can see; designers tune from this")
	assert_eq(p.fov_degrees, 110.0,
		"fov_degrees default 110.0 sets the full horizontal view-cone the target must be inside")
	assert_eq(p.time_to_detect, 1.0,
		"time_to_detect default 1.0 s is the player's reaction window before full ALERTED")
	assert_eq(p.forget_time, 4.0,
		"forget_time default 4.0 s is how long it stays wary before giving up to UNAWARE")
	assert_eq(p.eye_height, 1.4,
		"eye_height default 1.4 m is where sight/LOS rays originate (the enemy's 'eyes')")
	assert_true(p.hearing,
		"hearing defaults true so enemies react to gunfire/fast movement out of the box")
	p.free()


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
# Every test keeps target unset so can_see()/can_hear() return at their
# is_instance_valid(target) guards and sense() never reaches physics.
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
# Enemy — exported SCRIPT defaults + inherited Character API. Loaded via
# load(path).new() WITHOUT add_child so Character._ready() never runs.
# (Does NOT duplicate test_smoke's enemy.tscn blast_damp==1.0 scene test.)
# ---------------------------------------------------------------------------

func test_enemy_script_defaults_and_inherited_character_api() -> void:
	var n = load("res://scripts/npc/npc.gd").new()  # no add_child: skip _ready entirely
	assert_eq(n.blast_damp_divisor, 1.12,
		"Enemy's SCRIPT default blast_damp_divisor must be the inherited 1.12 (the .tscn's 1.0 override is tested in test_smoke)")
	assert_eq(n.max_hp, 10.0,
		"Enemy max_hp default 10.0 (inherited from Character) sets baseline enemy health")
	assert_eq(n.head_local_y, 0.4,
		"head_local_y default 0.4 (inherited) defines the headshot zone used by attacker crit math")
	assert_true(n.has_method("apply_velocity"),
		"Enemy must override apply_velocity() to add knockback friction on top of the blast tail")
	assert_true(n.has_method("_on_damaged"),
		"Enemy must define _on_damaged (wired to Character's `damaged` signal in enemy.tscn)")
	assert_true(n.has_method("_on_died"),
		"Enemy must define _on_died (wired to Character's `died` signal for the kill freeze-frame)")
	n.free()


func test_enemy_is_off_guard_default_false() -> void:
	# Enemy does not override is_off_guard(); the base Character returns false. A plain Enemy
	# (no Perception) must therefore not be an ambush target — only RangedEnemy wires perception.
	var n = load("res://scripts/npc/npc.gd").new()  # no add_child
	assert_false(n.is_off_guard(),
		"A base Enemy must report is_off_guard()==false (Character's default; no Perception to make it true)")
	n.free()


# ---------------------------------------------------------------------------
# RangedEnemy — exported SCRIPT defaults, constants, off-guard guard, and AI
# method surface. Loaded via load(path).new() WITHOUT add_child: its real
# _ready() instantiates weapon.tscn, add_childs a muzzle/weapon/nav, and calls
# get_tree() — none of which is safe in a unit test.
# ---------------------------------------------------------------------------

func test_ranged_enemy_exported_defaults() -> void:
	var n = load("res://scripts/npc/npc.gd").new()  # no add_child: _ready MUST NOT run
	# Weapon group
	assert_null(n.weapon_data,
		"weapon_data must default null after the fold — a bare NPC is a civilian; ranged_enemy.tscn sets a weapon to make a combatant")
	assert_eq(n.rate_of_fire_factor, 1.0,
		"rate_of_fire_factor default 1.0 = the weapon's own attack_speed paces shots (no per-NPC cooldown)")
	assert_eq(n.miss_chance, 0.0,
		"miss_chance default 0.0 = an NPC never deliberately misses the player until tuned up")
	assert_eq(n.fire_range, 30.0,
		"fire_range default 30.0 m caps how far it will shoot (separate from sight range)")
	assert_eq(n.target_height, 0.0,
		"target_height default 0.0 aims dead-centre on the player capsule")
	# Perception group (RangedEnemy's own exports, fed into its child Perception)
	assert_eq(n.sight_range, 25.0,
		"RangedEnemy sight_range default 25.0 m mirrors Perception's default")
	assert_eq(n.fov_degrees, 110.0,
		"RangedEnemy fov_degrees default 110.0 mirrors Perception's view cone")
	assert_eq(n.time_to_detect, 1.0,
		"RangedEnemy time_to_detect default 1.0 s is the reaction window")
	assert_eq(n.forget_time, 4.0,
		"RangedEnemy forget_time default 4.0 s is the wariness duration")
	assert_eq(n.eye_height, 1.4,
		"RangedEnemy eye_height default 1.4 m is the sight ray origin height")
	assert_true(n.hearing,
		"RangedEnemy hearing defaults true so it reacts to noise outside its cone")
	assert_eq(n.turn_speed, 8.0,
		"turn_speed default 8.0 controls how fast it rotates to face a target")
	# Laser group
	assert_true(n.show_laser,
		"show_laser defaults true so the telegraphing laser sight is on by default")
	# Movement group
	assert_eq(n.move_speed, 4.0,
		"move_speed default 4.0 m/s sets walk/chase pace")
	assert_eq(n.move_accel, 25.0,
		"move_accel default 25.0 m/s^2 governs ground accel and knockback braking")
	assert_eq(n.air_accel, 2.0,
		"air_accel default 2.0 m/s^2 is low so a blast carries it before it recovers")
	assert_eq(n.engage_range_fraction, 0.9,
		"engage_range_fraction default 0.9 means it closes to 90% of effective range before holding")
	assert_eq(n.jump_velocity, 10.0,
		"jump_velocity default 10.0 m/s is the hop impulse for ledges / up nav-links")
	n.free()


func test_ranged_enemy_constants() -> void:
	# Constants need no instance — read straight off the class. These pin the laser cap and the
	# shared alert-sting throttle window.
	assert_eq(NPC.LASER_MAX_LENGTH, 60.0,
		"LASER_MAX_LENGTH must be 60.0 m — the fallback laser reach when no weapon range applies")
	assert_eq(NPC.ALERT_COOLDOWN_MS, 3000,
		"ALERT_COOLDOWN_MS must be 3000 — the shared throttle so a swarm spotting you plays one sting")


func test_ranged_enemy_is_off_guard_false_before_ready() -> void:
	# is_off_guard() is `_perception != null and ...`. Without _ready(), _perception is null, so
	# the short-circuit must return false — proving a not-yet-initialised enemy isn't an exploit.
	var n = load("res://scripts/npc/npc.gd").new()  # no add_child: _perception stays null
	assert_false(n.is_off_guard(),
		"RangedEnemy.is_off_guard() must be false while _perception is null (the null-guard short-circuit)")
	n.free()


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
	assert_true(n.has_method("_on_damaged"),
		"RangedEnemy must override _on_damaged() (a hit alerts it toward the shooter)")
	n.free()


# ---------------------------------------------------------------------------
# death.gd / damage.gd — type identity + handler presence only. These scripts
# have NO class_name, so load by path. Their handlers do audio + tree side
# effects, so we assert has_method but NEVER call them. Bare AudioStreamPlayer3D
# instances were never added to the tree, so .free() (not add_child_autofree).
# ---------------------------------------------------------------------------

func test_death_script_surface() -> void:
	var n = load("res://scenes/enemies/death.gd").new()  # no add_child
	assert_true(n is AudioStreamPlayer3D,
		"death.gd must extend AudioStreamPlayer3D (it's the positional death-SFX node on the enemy)")
	assert_true(n.has_method("_on_enemy_died"),
		"death.gd must define _on_enemy_died (wired to the enemy's `died` signal in enemy.tscn)")
	assert_true(n.has_method("_play_applause"),
		"death.gd must define _play_applause (the crit-only kill cheer)")
	n.free()


func test_damage_script_surface() -> void:
	var n = load("res://scenes/enemies/damage.gd").new()  # no add_child
	assert_true(n is AudioStreamPlayer3D,
		"damage.gd must extend AudioStreamPlayer3D (the positional hurt-SFX node on the enemy)")
	assert_true(n.has_method("_on_enemy_damaged"),
		"damage.gd must define _on_enemy_damaged (wired to the enemy's `damaged` signal in enemy.tscn)")
	n.free()