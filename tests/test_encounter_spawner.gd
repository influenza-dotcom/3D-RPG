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
