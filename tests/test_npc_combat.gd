extends GutTest

## H2 (Wave 5): NpcCombat is the firing-dispatch component extracted off npc.gd — the armed body (act_alerted),
## the unarmed body (act_unarmed), the punch, and the combat dodge. These pin the extraction seam:
## - the GOAP entry points act_alerted/act_unarmed exist on the component;
## - the NPC still exposes the thin _act_alerted/_act_unarmed facades the GOAP actions call, and _punch/_maybe_dodge
##   are GONE from the root (moved here);
## - the combat-dodge bookkeeping behaves (a successful roll opens a burst + re-arms the cooldown; a degenerate roll skips);
## - the GOAP FireArmed/FireUnarmed actions still call the host facades (so the extraction is invisible to the planner).
## The heavyweight per-frame bodies (aim/telegraph/fire) run only in-tree with a live weapon/perception — playtest +
## the tests_soak combat smoke harness (T1) cover those; here we pin the seam + the pure dodge logic.

const CombatScript := preload("res://scripts/npc/npc_combat.gd")


## Minimal host for the dodge path: only the dodge tuning + _desired_velocity NpcCombat._maybe_dodge reads/writes.
class _HostStub extends Node3D:
	var move_speed: float = 5.0
	var dodge_chance: float = 1.0
	var dodge_interval: float = 0.5
	var dodge_duration: float = 0.3
	var dodge_speed_fraction: float = 0.5
	var _desired_velocity: Vector3 = Vector3.ZERO


func test_combat_exposes_the_goap_entry_points() -> void:
	var c = CombatScript.new()
	assert_true(c.has_method("act_alerted"), "NpcCombat.act_alerted is the GOAP FireArmed body (reached via host._act_alerted)")
	assert_true(c.has_method("act_unarmed"), "NpcCombat.act_unarmed is the GOAP FireUnarmed body (reached via host._act_unarmed)")
	assert_null(c.host, "host defaults null (bound by NPC._build_components)")
	c.free()


func test_npc_keeps_thin_facades_and_dropped_the_moved_bodies() -> void:
	var npc = load("res://scripts/npc/npc.gd").new()
	assert_true(npc.has_method("_act_alerted"), "NPC keeps the _act_alerted facade the GOAP FireArmed action calls")
	assert_true(npc.has_method("_act_unarmed"), "NPC keeps the _act_unarmed facade the GOAP FireUnarmed action calls")
	assert_false(npc.has_method("_punch"), "_punch moved to NpcCombat (no longer on the root)")
	assert_false(npc.has_method("_maybe_dodge"), "_maybe_dodge moved to NpcCombat (no longer on the root)")
	npc.free()


func test_maybe_dodge_opens_a_burst_and_rearms_cooldown() -> void:
	var c = CombatScript.new()
	var host := _HostStub.new()
	add_child_autofree(host)  # in-tree so global_position is valid
	host.global_position = Vector3.ZERO
	c.host = host
	# dodge_chance = 1.0 so the roll always succeeds; the aim is offset so the us->target vector isn't degenerate.
	c._maybe_dodge(0.016, Vector3(5.0, 0.0, 0.0))
	assert_almost_eq(c._dodge_t, host.dodge_duration, 0.001, "a successful roll opens an active strafe burst (_dodge_t = dodge_duration)")
	assert_almost_eq(c._dodge_cd, 2.0, 0.001, "the cooldown re-arms to max(dodge_interval, DODGE_MIN_INTERVAL) = 2.0")
	assert_gt(host._desired_velocity.length(), 0.0, "the burst drives host._desired_velocity sideways")
	c.free()


func test_maybe_dodge_skips_a_degenerate_direction() -> void:
	# Standing ON the target (aim == our position) -> no meaningful lateral -> skip the dodge this cycle (no burst).
	var c = CombatScript.new()
	var host := _HostStub.new()
	add_child_autofree(host)
	host.global_position = Vector3(2.0, 0.0, 2.0)
	c.host = host
	c._maybe_dodge(0.016, Vector3(2.0, 0.0, 2.0))  # aim == position
	assert_eq(c._dodge_t, 0.0, "a degenerate (on-target) roll opens no strafe burst")
	c.free()


func test_goap_fire_actions_call_the_host_facades() -> void:
	# Drift guard: the GOAP FireArmed/FireUnarmed actions must keep calling host._act_alerted / host._act_unarmed so
	# the extraction stays invisible to the planner (the bodies moved to NpcCombat, but the entry points didn't).
	assert_string_contains(FileAccess.get_file_as_string("res://scripts/npc/goap/actions/goap_action_fire_armed.gd"), "host._act_alerted(", "FireArmed action must call host._act_alerted")
	assert_string_contains(FileAccess.get_file_as_string("res://scripts/npc/goap/actions/goap_action_fire_unarmed.gd"), "host._act_unarmed(", "FireUnarmed action must call host._act_unarmed")
