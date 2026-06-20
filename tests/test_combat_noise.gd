extends GutTest

## NPC combat noise on the shared &"noise" channel (GA-2): an NPC's gunfire + death drop a one-shot NoiseSource
## so a listening guard (GameSettings.npc_ai.hearing_initiates) can hear the firefight and investigate — combat
## is no longer silent to off-screen allies. The spawn is factored into the static NPC.emit_noise_burst so it
## unit-tests with an injected parent (no heavy NPC _ready); the gunfire throttle + the export knobs are pinned
## here. The in-tree wiring (the _act_alerted / _on_died call sites + the hearing_initiates gate) is playtested.

const NPC_PATH := "res://scripts/npc/npc.gd"


func test_combat_noise_export_defaults_are_sane() -> void:
	var n = load(NPC_PATH).new()
	assert_gt(n.gunfire_noise_radius, 0.0, "gunfire is audible by default (the channel is still inert until a listener opts in)")
	assert_gt(n.death_noise_radius, 0.0, "a death is audible by default")
	assert_gt(n.combat_noise_interval, 0.0, "the gunfire throttle interval is positive (so full-auto pulses, not per-bullet)")
	assert_gt(n.combat_noise_lifetime, 0.0, "the burst lifetime is positive so the source self-frees (never leaks)")
	n.free()


func test_emit_noise_burst_spawns_a_one_shot_source() -> void:
	var parent := Node3D.new()
	add_child_autofree(parent)
	var src: NoiseSource = NPC.emit_noise_burst(parent, Vector3(1.0, 2.0, 3.0), 10.0, 0.0, 0.3)
	assert_not_null(src, "a positive-radius burst spawns a NoiseSource")
	assert_eq(src.get_parent(), parent, "...parented to the injected holder (so it outlives the emitter)")
	assert_true(src.is_in_group(&"noise"), "...registered on the shared &\"noise\" channel")
	assert_almost_eq(src.radius, 10.0, 0.001, "the audible radius is set")
	assert_almost_eq(src.global_position, Vector3(1.0, 2.0, 3.0), Vector3(0.01, 0.01, 0.01), "spawned at the requested spot")


func test_emit_noise_burst_floors_lifetime_to_stay_one_shot() -> void:
	# A 0 lifetime would make the NoiseSource PERSISTENT (it never self-frees) — a leak. The floor forces one-shot.
	var parent := Node3D.new()
	add_child_autofree(parent)
	var src: NoiseSource = NPC.emit_noise_burst(parent, Vector3.ZERO, 5.0, 0.0, 0.0)
	assert_not_null(src, "the burst still spawns")
	assert_gt(src.lifetime, 0.0, "lifetime is floored above 0 so the source is one-shot, never a leaking persistent one")


func test_emit_noise_burst_guards() -> void:
	assert_null(NPC.emit_noise_burst(null, Vector3.ZERO, 10.0, 0.0, 0.3), "a null holder spawns nothing")
	var parent := Node3D.new()
	add_child_autofree(parent)
	assert_null(NPC.emit_noise_burst(parent, Vector3.ZERO, 0.0, 0.0, 0.3), "a silent (radius 0) burst spawns nothing")


func test_gunfire_noise_is_throttled() -> void:
	# Two shots in quick succession emit at most one noise pulse — the throttle gate stamps once and blocks the
	# rest within combat_noise_interval (off-tree: the spawn no-ops, but the throttle stamp is observable).
	var n = load(NPC_PATH).new()
	n._emit_gunfire_noise()
	var after_first: int = n._last_combat_noise_ms
	n._emit_gunfire_noise()
	assert_eq(n._last_combat_noise_ms, after_first, "a second shot within the interval is throttled (no new pulse)")
	n.free()
