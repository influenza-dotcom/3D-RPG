extends GutTest

## NoisePulser (scripts/components/noise_pulser.gd): the generic EVENT / one-shot half of the shared &"noise"
## channel. Drop it under any Node3D, call pulse(), and a one-shot NoiseSource burst appears for listening NPCs —
## host-agnostic (reads get_parent()), so it needs no NPC. The channel is INERT unless hearing_initiates is on, so
## these toggle that flag on the shared NpcAiSettings.tres (Godot caches by path -> the same instance the pulser
## reads) and restore it after, proving both the heard and the inert paths. NoisePulser has no _ready/_physics_process,
## so a bare .new() is safe headless; the spawn needs an in-tree host, built per test.

const NPC_AI := preload("res://resources/tuning/NpcAiSettings.tres")

var _hearing_was: bool = false


func before_each() -> void:
	_hearing_was = NPC_AI.hearing_initiates


func after_each() -> void:
	NPC_AI.hearing_initiates = _hearing_was  # never leak a toggled global into the next test


## A NoisePulser under an in-tree Node3D host (both autofreed). The host's PARENT (the test) is where a pulse
## parents its NoiseSource, so a spawned source outlives the host — capture + autofree() it per test.
func _pulser_under_host() -> NoisePulser:
	var host := Node3D.new()
	add_child_autofree(host)
	var p := NoisePulser.new()
	host.add_child(p)  # freed with the autofreed host
	return p


func test_pulse_spawns_a_one_shot_source_when_heard() -> void:
	NPC_AI.hearing_initiates = true
	var p := _pulser_under_host()
	p.radius = 10.0
	p.decay = 0.0
	p.lifetime = 0.3
	(p.get_parent() as Node3D).global_position = Vector3(1.0, 2.0, 3.0)
	var src: NoiseSource = p.pulse()
	assert_not_null(src, "a heard, positive-radius pulse spawns a NoiseSource")
	autofree(src)
	assert_true(src.is_in_group(&"noise"), "...registered on the shared &\"noise\" channel")
	assert_almost_eq(src.radius, 10.0, 0.001, "the audible radius is the @export radius")
	assert_gt(src.lifetime, 0.0, "...one-shot: a positive lifetime so it self-frees")
	assert_almost_eq(src.global_position, Vector3(1.0, 2.0, 3.0), Vector3(0.01, 0.01, 0.01), "spawned at the host's position")


func test_pulse_is_inert_when_nothing_listens() -> void:
	NPC_AI.hearing_initiates = false
	var p := _pulser_under_host()
	assert_null(p.pulse(10.0), "nothing consumes the channel -> pulse spawns no node (avoids per-bullet churn)")


func test_radius_override_wins_over_the_export() -> void:
	NPC_AI.hearing_initiates = true
	var p := _pulser_under_host()
	p.radius = 5.0
	var src: NoiseSource = p.pulse(20.0)
	assert_not_null(src, "an override still spawns")
	autofree(src)
	assert_almost_eq(src.radius, 20.0, 0.001, "radius_override >= 0 wins over the @export radius")


func test_silent_pulse_spawns_nothing() -> void:
	NPC_AI.hearing_initiates = true
	var p := _pulser_under_host()
	assert_null(p.pulse(0.0), "a radius-0 override is silent -> no source")
	p.radius = 0.0
	assert_null(p.pulse(), "a radius-0 default is silent -> no source")


func test_offtree_pulse_spawns_nothing() -> void:
	NPC_AI.hearing_initiates = true
	var p := NoisePulser.new()  # never parented -> get_parent() is null
	assert_null(p.pulse(10.0), "off-tree (no host) there is nowhere to place the sound")
	p.free()


func test_lifetime_is_floored_to_stay_one_shot() -> void:
	# A 0 lifetime with 0 decay would make the NoiseSource PERSISTENT (never self-frees) — a leak. The floor forces one-shot.
	NPC_AI.hearing_initiates = true
	var p := _pulser_under_host()
	p.lifetime = 0.0
	var src: NoiseSource = p.pulse(5.0)
	assert_not_null(src, "the pulse still spawns")
	autofree(src)
	assert_gt(src.lifetime, 0.0, "lifetime is floored above 0 so the source is one-shot, never a leaking persistent one")


func test_throttled_pulse_blocks_a_rapid_second() -> void:
	NPC_AI.hearing_initiates = true
	var p := _pulser_under_host()
	p.min_interval = 10.0  # a wide window so the two calls land inside it
	var first: NoiseSource = p.pulse(10.0, true)
	assert_not_null(first, "the first throttled pulse fires")
	autofree(first)
	assert_null(p.pulse(10.0, true), "a second throttled pulse within min_interval is folded into the first (no new source)")


func test_unthrottled_pulse_ignores_the_interval() -> void:
	# A one-off death cry (throttled = false) must sound even mid-burst, when the gunfire throttle window is open.
	NPC_AI.hearing_initiates = true
	var p := _pulser_under_host()
	p.min_interval = 10.0
	var burst: NoiseSource = p.pulse(10.0, true)
	assert_not_null(burst, "a throttled pulse arms the window")
	autofree(burst)
	var cry: NoiseSource = p.pulse(12.0, false)
	assert_not_null(cry, "an un-throttled pulse bypasses min_interval")
	autofree(cry)
