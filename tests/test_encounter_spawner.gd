extends GutTest

## Slice 7 (encounter spawning): SpawnDefinition defaults, the scatter-offset bound, and the no-op guards on
## EncounterSpawner / WaveManager. The actual NPC instantiation + wave timing instance enemy scenes (which run
## NPC._ready), so they are playtest-verified per the in-tree convention, not unit-tested.

func test_spawn_definition_defaults() -> void:
	var d := SpawnDefinition.new()
	assert_eq(d.count, 1, "one by default")
	assert_almost_eq(d.spawn_radius, 2.0, 0.001, "default scatter radius")
	assert_true(d.auto_aggro, "spawns aggro by default")
	assert_almost_eq(d.spawn_delay, 0.0, 0.001, "no stagger by default")
	d = null

func test_random_offset_within_radius() -> void:
	var s := EncounterSpawner.new()
	for i in 20:
		var o := s._random_offset(5.0)
		assert_almost_eq(o.y, 0.0, 0.001, "the scatter offset is horizontal")
		assert_lte(o.length(), 5.001, "offset stays within the radius")
	assert_eq(s._random_offset(0.0), Vector3.ZERO, "zero radius -> no offset")
	s.free()

func test_spawn_guards_are_safe() -> void:
	var s := EncounterSpawner.new()
	# empty definitions / bad index -> no-op (off-tree, no parent), no crash
	s.trigger_spawn()
	s.trigger_spawn_wave(-1)
	s.trigger_spawn_wave(0)
	assert_eq(s.spawn_definitions.size(), 0, "nothing configured, nothing spawned")
	s.free()

func test_wave_manager_no_spawner_is_inert() -> void:
	var w := WaveManager.new()
	w.start()  # no spawner_path -> inert
	assert_false(w.is_running(), "start() with no spawner is inert")
	assert_false(w._get_configuration_warnings().is_empty(), "warns without a spawner_path")
	w.free()

## Records provoke() calls so we can assert auto_aggro spawns REP-NEUTRALLY (mirrors test_alarm_panel's stub).
class _ProvokeRec extends Node:
	var provoke_count := 0
	var last_apply_rep := true
	func provoke(_a = null, apply_rep := true) -> void:
		provoke_count += 1
		last_apply_rep = apply_rep

func test_auto_aggro_provokes_without_dropping_rep() -> void:
	# An authored ambush must aggro each spawn but NOT drop faction rep per member — else an N-member wave
	# multiplies the faction-rep hit by the squad size (GA-3). _aggro_spawn must pass apply_rep=false.
	var rec := _ProvokeRec.new()
	EncounterSpawner._aggro_spawn(rec, null)
	assert_eq(rec.provoke_count, 1, "auto_aggro provokes the spawn")
	assert_false(rec.last_apply_rep,
		"must provoke with apply_rep=false so an N-member wave doesnt multiply the faction rep hit")
	rec.free()
