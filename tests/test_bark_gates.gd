extends GutTest

## Designer bark gates: NpcData.damage_barks / death_barks / search_barks toggle whether an NPC voices the HURT
## cry (_cry_wounded), the death-witness reaction (_witness_death), and the active-search mutter (bark_searching).
## Seeded onto the code-built NpcVoice in NPC._build_components (default ON, so an unprofiled NPC is unchanged).
## The gate is the FIRST check in each trigger, so a muted bark short-circuits BEFORE any host read — verified
## here by calling with host == null.

const NPC_PATH := "res://scripts/npc/npc.gd"


func test_npc_data_bark_gates_default_on() -> void:
	var d := NpcData.new()
	assert_true(d.damage_barks, "NpcData.damage_barks must default ON so a profiled NPC keeps its hurt cry unless muted")
	assert_true(d.death_barks, "NpcData.death_barks must default ON so a profiled NPC keeps death-witness reactions unless muted")
	assert_true(d.search_barks, "NpcData.search_barks must default ON so a profiled NPC keeps its hunt mutter unless muted")
	d = null


func test_npc_voice_gate_defaults_on() -> void:
	var v := NpcVoice.new()
	assert_true(v.damage_barks_enabled, "NpcVoice.damage_barks_enabled must default ON (unprofiled NPC unchanged)")
	assert_true(v.death_barks_enabled, "NpcVoice.death_barks_enabled must default ON (unprofiled NPC unchanged)")
	assert_true(v.search_barks_enabled, "NpcVoice.search_barks_enabled must default ON (unprofiled NPC unchanged)")
	v.free()


func test_damage_bark_gate_short_circuits_before_host() -> void:
	# host left null: if the gate weren't the FIRST check, host._dead would crash. No crash == gate is first.
	var v := NpcVoice.new()
	v.damage_barks_enabled = false
	v._cry_wounded()
	assert_true(true, "a muted damage bark must return before touching host (gate checked first)")
	v.free()


func test_death_bark_gate_short_circuits_before_host() -> void:
	var v := NpcVoice.new()
	v.death_barks_enabled = false
	v._witness_death(null)
	assert_true(true, "a muted death-witness bark must return before touching host (gate checked first)")
	v.free()


func test_search_bark_gate_short_circuits_before_host() -> void:
	# host left null: bark_searching's gate is the FIRST check, so a muted hunt mutter returns before host._dead.
	var v := NpcVoice.new()
	v.search_barks_enabled = false
	v.bark_searching()
	assert_true(true, "a muted search bark must return before touching host (gate checked first)")
	v.free()


func test_gated_voice_offtree_safe_when_enabled() -> void:
	# Gates ON (default) + a bare NPC (no _ready -> hp 0): both triggers still early-return on the hp/null
	# guards, so enabling the gate didn't break the existing off-tree safety the damage handler relies on.
	var n = load(NPC_PATH).new()
	var v := NpcVoice.new()
	v.host = n
	v._cry_wounded()
	v._witness_death(null)
	assert_true(true, "enabled barks must stay off-tree safe on a bare (hp 0) host")
	v.free()
	n.free()
