extends GutTest

## Rank 9 (encounter clearing): EncounterSpawner._alive tracking → cleared / alive_count_changed, and
## WaveManager.wait_for_clear's null-spawner short-circuit. Driven with stub nodes (no real NPC _ready).

const EncounterSpawnerScript = preload("res://scripts/components/encounter_spawner.gd")
const WaveManagerScript = preload("res://scripts/components/wave_manager.gd")

func test_clear_fires_when_last_spawn_gone() -> void:
	var spawner = EncounterSpawnerScript.new()
	watch_signals(spawner)
	var a := Node.new()
	var b := Node.new()
	add_child_autofree(a)
	add_child_autofree(b)
	spawner._track_spawn(a)
	spawner._track_spawn(b)
	assert_eq(spawner.alive_count(), 2, "two tracked spawns are alive")
	spawner._on_spawn_gone(a)
	assert_eq(spawner.alive_count(), 1, "one down, one alive")
	assert_signal_not_emitted(spawner, "cleared", "not cleared while one remains")
	spawner._on_spawn_gone(b)
	assert_eq(spawner.alive_count(), 0, "both down")
	assert_signal_emitted(spawner, "cleared", "cleared once the last spawn is gone")
	assert_signal_emit_count(spawner, "alive_count_changed", 4, "two adds + two removes")
	spawner.free()

func test_double_gone_is_idempotent() -> void:
	var spawner = EncounterSpawnerScript.new()
	watch_signals(spawner)
	var a := Node.new()
	add_child_autofree(a)
	spawner._track_spawn(a)
	spawner._on_spawn_gone(a)  # e.g. died — corpse lingers
	spawner._on_spawn_gone(a)  # e.g. tree_exited later — must not re-fire
	assert_signal_emit_count(spawner, "cleared", 1, "cleared fires exactly once per encounter")
	spawner.free()

func test_empty_spawner_never_clears() -> void:
	var spawner = EncounterSpawnerScript.new()
	watch_signals(spawner)
	assert_eq(spawner.alive_count(), 0, "nothing spawned")
	assert_signal_not_emitted(spawner, "cleared", "a spawner that never spawned never reports cleared")
	spawner.free()

func test_cleared_suppressed_while_a_wave_is_still_spawning() -> void:
	# The bug: killing an early spawn BEFORE its staggered reinforcements arrived emptied _alive and fired `cleared`
	# mid-ambush. _spawning (raised during trigger_spawn_wave's stagger) now suppresses it; the gate resolves only
	# once the wave is done AND all spawns are gone. Driven white-box (no real timers).
	var spawner = EncounterSpawnerScript.new()
	watch_signals(spawner)
	spawner._spawning = 1  # simulate a wave mid-stagger
	var first := Node.new()
	add_child_autofree(first)
	spawner._track_spawn(first)
	spawner._on_spawn_gone(first)  # player kills spawn #1 before #2 arrives -> _alive empty, but still spawning
	assert_signal_not_emitted(spawner, "cleared", "a death mid-stagger must NOT fire cleared while the wave is still spawning")
	var second := Node.new()  # the reinforcement arrives
	add_child_autofree(second)
	spawner._track_spawn(second)
	spawner._spawning = 0  # the wave has finished spawning
	spawner._on_spawn_gone(second)  # now the last spawn dies -> wave done + empty -> cleared
	assert_signal_emitted(spawner, "cleared", "once the wave finished and the last spawn died, cleared fires")
	spawner.free()

func test_wait_for_clear_null_spawner_returns() -> void:
	var wm = WaveManagerScript.new()
	# no spawner_path assigned → wait_for_clear must return immediately, not hang
	await wm.wait_for_clear()
	assert_true(true, "wait_for_clear returned with no spawner")
	wm.free()
