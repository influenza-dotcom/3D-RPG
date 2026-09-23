extends GutTest

## Slice 7 (encounter spawning): what a freshly-authored SpawnDefinition does, the scatter-offset bound, and the
## guards on EncounterSpawner / WaveManager. Spawning a REAL enemy scene runs NPC._ready, so that path (and wave
## timing) is playtest-verified per the in-tree convention; the spawn PIPELINE itself is driven here with a stand-in
## scene of one bare Node3D (no NPC, no _ready of consequence), which is enough to prove the guards refuse and a
## valid definition gets past them.

## A PackedScene of one bare Node3D — the stand-in "enemy" the guard tests spawn.
func _stand_in_scene() -> PackedScene:
	var root := Node3D.new()
	root.name = "StandInSpawn"
	var ps := PackedScene.new()
	assert_eq(ps.pack(root), OK, "fixture: the stand-in spawn scene packs")
	root.free()
	return ps


func test_a_fresh_definition_is_an_ambush_that_scatters_its_bodies() -> void:
	var d := SpawnDefinition.new()
	# Authoring decision: an EncounterSpawner is the ambush tool, so a definition dropped in untouched spawns bodies
	# that come straight for the player (a designer opts OUT for a sleeping squad).
	assert_true(d.auto_aggro, "SHIP DECISION: a fresh SpawnDefinition aggroes on arrival — encounters are ambushes by default")
	# The default scatter must actually scatter: with a zero radius every body of a count>1 wave lands on the
	# spawner's exact origin, and overlapping capsules blow apart through the floor / walls.
	var s := EncounterSpawner.new()
	var spread := false
	for i in 20:
		var o := s._random_offset(d.spawn_radius)
		if o.length() > 0.01:
			spread = true
		assert_lte(o.length(), d.spawn_radius + 0.001, "a default-radius offset stays inside the default radius")
	assert_true(spread, "the default spawn_radius must scatter bodies off the spawner origin, never stack a wave on one point")
	s.free()
	d = null

func test_random_offset_within_radius() -> void:
	var s := EncounterSpawner.new()
	for i in 20:
		var o := s._random_offset(5.0)
		assert_almost_eq(o.y, 0.0, 0.001, "the scatter offset is horizontal")
		assert_lte(o.length(), 5.001, "offset stays within the radius")
	assert_eq(s._random_offset(0.0), Vector3.ZERO, "zero radius -> no offset")
	s.free()

func test_spawn_guards_refuse_bad_setups_but_a_scene_only_definition_spawns() -> void:
	var level := Node3D.new()
	add_child_autofree(level)
	var s := EncounterSpawner.new()
	level.add_child(s)  # pool is empty, so _ready returns at once
	watch_signals(s)
	# Nothing configured: a trigger (a TriggerVolume / WaveManager calling in) is a quiet no-op, never an index error.
	s.trigger_spawn()
	s.trigger_spawn_wave(0)
	assert_signal_emit_count(s, "spawned", 0, "no definitions -> nothing spawns and nothing errors")
	# A definition with no scene (a half-authored row) spawns nothing.
	var blank := SpawnDefinition.new()
	s.spawn_definitions.append(blank)
	s.trigger_spawn_wave(0)
	assert_signal_emit_count(s, "spawned", 0, "a definition with no npc_scene spawns nothing")
	# The same spawner with a real scene: out-of-range wave indices are refused...
	var def := SpawnDefinition.new()
	def.npc_scene = _stand_in_scene()
	s.spawn_definitions.clear()
	s.spawn_definitions.append(def)
	s.trigger_spawn_wave(-1)
	s.trigger_spawn_wave(1)
	assert_signal_emit_count(s, "spawned", 0, "wave -1 and wave 1 do not exist on a one-definition spawner — refused, not wrapped")
	# ...and an off-tree spawner has no level to put a body in.
	var loose := EncounterSpawner.new()
	loose.spawn_definitions.append(def)
	watch_signals(loose)
	loose.trigger_spawn_wave(0)
	assert_signal_emit_count(loose, "spawned", 0, "a spawner with no parent spawns nothing (there is no level to add the body to)")
	loose.free()
	# CONTROL: the very same definition on the in-tree spawner gets past every guard — with ONLY its scene set, the
	# defaults spawn at least one body, into the level beside the spawner, inside the scatter radius.
	var before := level.get_child_count()
	s.trigger_spawn_wave(0)
	assert_signal_emitted(s, "spawned", "a valid wave index on an in-tree spawner with a scene spawns")
	assert_gt(level.get_child_count(), before, "the spawned body is added to the level as the spawner's sibling")
	var body := level.get_child(level.get_child_count() - 1) as Node3D
	assert_true(body != null and body.name.begins_with("StandInSpawn"), "the new sibling is the definition's scene")
	if body != null:
		assert_lte(body.global_position.distance_to(s.global_position), def.spawn_radius + 0.001,
			"a scattered body lands within spawn_radius of the spawner")
	blank = null

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
