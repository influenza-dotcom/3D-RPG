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

const Factions = preload("res://scripts/faction/factions.gd")

func test_reputation_gate_pass_and_fail() -> void:
	# WR-1: a BuildGate can gate the world on the player's standing with a faction.
	Reputation.reset()
	var fac := Factions.by_id("townsfolk")  # a real faction on disk
	var gate := BuildGate.new()
	gate.required_faction_id = "townsfolk"
	gate.required_reputation = 20.0
	var p = load("res://scripts/player/player.gd").new()  # off-tree -> add_reputation lands unscaled
	assert_false(gate.passes(p), "standing 0 < 20 fails the rep gate")
	assert_ne(gate.deny_reason(p), "", "a failed rep gate gives a deny reason")
	Reputation.add_reputation(fac, 25.0)
	assert_true(gate.passes(p), "standing 25 >= 20 passes the rep gate")
	gate.free()
	p.free()
	Reputation.reset()  # global autoload — leave it clean for other tests

func test_reputation_gate_unknown_faction_fails_closed() -> void:
	var gate := BuildGate.new()
	gate.required_faction_id = "no_such_faction_xyz"  # unresolvable -> a misconfigured gate stays locked
	var p = load("res://scripts/player/player.gd").new()
	assert_false(gate.passes(p), "an unresolvable faction id fails closed")
	gate.free()
	p.free()

func test_deny_reason_names_the_failed_requirement_not_the_first_set() -> void:
	# deny_reason must report the requirement that actually FAILED — not merely the first one that's SET. A MET stat
	# gate alongside a failing perk gate must surface the PERK, not the (passing) stat.
	var gate := BuildGate.new()
	gate.required_stat = &"strength"
	gate.required_value = 3
	gate.required_perk = &"deadeye"  # the bare opener has no PerkManager child -> the perk gate fails
	var p = load("res://scripts/player/player.gd").new()
	var sheet := CharacterStats.new()
	sheet.strength = 5  # MEETS the stat gate
	p.stats = sheet
	assert_false(gate.passes(p), "the perk gate still blocks even though the stat is met")
	assert_true(gate.deny_reason(p).to_lower().contains("perk"), "deny_reason names the FAILED perk gate, not the passing stat")
	gate.free()
	p.free()
	sheet = null

func test_deny_reason_uses_authored_display_labels() -> void:
	# Display resolution lives INSIDE PlayerText.requires_* now — deny_reason's whole job is to pass the RAW ID.
	# Perk gate: the rendered toast names the AUTHORED Perk.display_name resolved from disk by that id
	# ([PH]-stripped, since requires_perk prepends its own marker). Today that label equals the capitalized id,
	# so this pins the ROUTING — it starts catching drift the moment the designer renames the perk.
	var p = load("res://scripts/player/player.gd").new()  # off-tree (no _ready); no PerkManager child -> perk gate fails
	var gate := BuildGate.new()
	gate.required_perk = &"tough_hide"
	var perk_res := load("res://resources/perks/tough_hide.tres") as Perk
	assert_not_null(perk_res, "the shipped tough_hide perk exists for the label lookup")
	if perk_res != null:
		assert_eq(gate.deny_reason(p),
			"[PH] Requires the %s perk" % PlayerText.strip_prefix(perk_res.display_name),
			"the perk deny toast renders the authored ([PH]-stripped) display_name, resolved from the raw id")
	gate.free()
	# Standing gate: neutral_wildlife's authored name is "Wildlife" — NOT the capitalized id "Neutral Wildlife" —
	# so this genuinely distinguishes authored-name routing from the old capitalize-the-id path.
	Reputation.reset()
	var fac := Factions.by_id("neutral_wildlife")
	assert_not_null(fac, "the shipped neutral_wildlife faction exists for the label lookup")
	var gate2 := BuildGate.new()
	gate2.required_faction_id = "neutral_wildlife"
	gate2.required_reputation = 50.0  # standing 0 < 50 -> denied
	if fac != null:
		assert_eq(gate2.deny_reason(p), "[PH] Requires standing with %s" % fac.display_name,
			"the standing deny toast renders the authored Faction.display_name, resolved from the raw id")
	gate2.free()
	p.free()
	Reputation.reset()  # global autoload — leave it clean for other tests

func test_of_finds_child_gate() -> void:
	var host := Node.new()
	var gate := BuildGate.new()
	host.add_child(gate)
	assert_eq(BuildGate.of(host), gate, "of() finds the BuildGate child")
	var bare := Node.new()
	assert_null(BuildGate.of(bare), "of() is null when there's no BuildGate child")
	host.free()
	bare.free()
