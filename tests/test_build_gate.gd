extends GutTest

## Rank 15 (BuildGate): the stat/perk/ability requirement consulted by Door / Lock / TriggerVolume. Pure passes()
## + of() logic against a bare off-tree player (no _ready); the in-host consult is playtest-verified.

func test_empty_gate_passes() -> void:
	var gate := BuildGate.new()
	var p = load("res://scripts/player/player.gd").new()
	assert_true(gate.passes(p), "a gate with no requirements passes anyone")
	assert_eq(gate.deny_reason(p), "", "an empty gate gives no deny reason")
	gate.free()
	p.free()

func test_stat_gate_pass_and_fail() -> void:
	var gate := BuildGate.new()
	gate.required_stat = &"strength"
	gate.required_value = 5
	var p = load("res://scripts/player/player.gd").new()  # off-tree (no _ready)
	var sheet := CharacterStats.new()
	sheet.strength = 3
	p.stats = sheet
	assert_false(gate.passes(p), "strength 3 < 5 fails the gate")
	assert_ne(gate.deny_reason(p), "", "a failed gate gives a deny reason")
	sheet.strength = 6
	assert_true(gate.passes(p), "strength 6 >= 5 passes")
	gate.free()
	p.free()
	sheet = null

func test_null_opener_fails_closed() -> void:
	var gate := BuildGate.new()
	gate.required_stat = &"agility"
	gate.required_value = 1
	assert_false(gate.passes(null), "a null opener fails closed")
	gate.free()

func test_of_finds_child_gate() -> void:
	var host := Node.new()
	var gate := BuildGate.new()
	host.add_child(gate)
	assert_eq(BuildGate.of(host), gate, "of() finds the BuildGate child")
	var bare := Node.new()
	assert_null(BuildGate.of(bare), "of() is null when there's no BuildGate child")
	host.free()
	bare.free()
