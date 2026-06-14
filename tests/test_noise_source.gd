extends GutTest

## NoiseSource -- the shared &"noise" distraction channel (stealth Slice 0a / 4). The pure audible() range
## gate carries the unit coverage; the live group scan + investigate routing (NPC._react_unaware) is in-tree
## and playtest-verified. Also checks the one-shot decay/lifetime self-management vs the persistent mode.


func test_group_and_defaults() -> void:
	assert_eq(NoiseSource.GROUP, &"noise", "the scan group tag is the canonical &\"noise\"")
	var s := NoiseSource.new()
	assert_eq(s.radius, 0.0, "a fresh source is silent (radius 0) until driven")
	assert_eq(s.decay, 0.0, "default decay 0 -> constant radius")
	assert_eq(s.lifetime, 0.0, "default lifetime 0 -> persistent (externally driven), never self-frees")
	s.free()

func test_ready_joins_the_scan_group() -> void:
	var s := NoiseSource.new()
	add_child_autofree(s)  # in-tree so _ready runs
	assert_true(s.is_in_group(&"noise"), "_ready registers the source in the &\"noise\" scan group")


# --- audible(): the pure range gate ---

func test_audible_is_a_range_gate() -> void:
	var src := Vector3(10.0, 0.0, 0.0)
	assert_true(NoiseSource.audible(8.0, src, Vector3(4.0, 0.0, 0.0)), "listener 6 m off, radius 8 -> heard")
	assert_false(NoiseSource.audible(8.0, src, Vector3(-5.0, 0.0, 0.0)), "listener 15 m off, radius 8 -> unheard")

func test_audible_includes_edge_and_guards_silence() -> void:
	var src := Vector3.ZERO
	assert_true(NoiseSource.audible(5.0, src, Vector3(5.0, 0.0, 0.0)), "exactly at the radius edge still counts (<=)")
	assert_false(NoiseSource.audible(0.0, src, Vector3(0.1, 0.0, 0.0)), "radius 0 (silent) -> never heard, even point-blank")


# --- one-shot fade/expiry vs persistent ---

func test_one_shot_decays_radius() -> void:
	var s := NoiseSource.new()
	s.radius = 10.0
	s.decay = 4.0
	s._physics_process(1.0)
	assert_almost_eq(s.radius, 6.0, 0.001, "a one-shot source loses `decay` m per second (10 - 4*1)")
	s.free()

func test_one_shot_frees_after_lifetime() -> void:
	var s := NoiseSource.new()
	s.radius = 5.0
	s.lifetime = 0.5
	add_child_autofree(s)
	s._physics_process(0.6)  # past lifetime
	assert_true(s.is_queued_for_deletion(), "past its lifetime, a one-shot source frees itself")

func test_persistent_source_ignores_physics() -> void:
	var s := NoiseSource.new()
	s.radius = 7.0  # decay 0 + lifetime 0 -> externally driven; _physics_process must not touch it
	s._physics_process(5.0)
	assert_eq(s.radius, 7.0, "a persistent source's radius is left to its owner (the player's live emitter)")
	assert_false(s.is_queued_for_deletion(), "and it never self-frees")
	s.free()
