extends GutTest

## NoiseSource -- the shared &"noise" distraction channel (stealth Slice 0a / 4). The pure audible() range
## gate carries the unit coverage, and the group scan itself (NpcSenses.loudest_noise) is driven with a bare
## listener host; the investigate routing (NPC._react_unaware) is in-tree and playtest-verified. Also checks the
## one-shot decay/lifetime self-management vs the persistent mode.


## The NPC side of the channel, stripped to what NpcSenses.loudest_noise() reads off its host: a position in the tree
## and a Perception (null = no wall occlusion, distance-only hearing).
class Listener extends Node3D:
	var _perception = null


func test_a_fresh_source_is_heard_by_no_npc_until_its_radius_is_driven() -> void:
	# Drives the REAL scan an unaware NPC runs (NpcSenses.loudest_noise over the source group), so this covers the
	# default AND the group wiring: a freshly dropped source must be silent, and driving it must make it heard.
	var npc := Listener.new()
	add_child_autofree(npc)
	var senses := NpcSenses.new()
	senses.host = npc
	var s := NoiseSource.new()
	add_child_autofree(s)
	s.global_position = Vector3(1.0, 0.0, 0.0)  # a metre from the NPC
	assert_eq(senses.loudest_noise(), null,
		"a default-constructed NoiseSource is SILENT: an NPC a metre away must not hear it until its owner drives radius")
	s.radius = 5.0
	assert_eq(senses.loudest_noise(), s,
		"once its radius is driven the same source IS the loudest noise reaching that NPC (control: the scan sees it)")
	senses.free()

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
	# The silence guard only shows at distance ZERO: anywhere farther, 'distance <= 0' already refuses a radius-0 source.
	assert_true(NoiseSource.audible(0.5, src, src),
		"control: a listener standing ON a sounding source hears it, so distance 0 is not refused on its own")
	assert_false(NoiseSource.audible(0.0, src, src),
		"radius 0 (silent) -> never heard, even by a listener standing exactly on the source")


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
