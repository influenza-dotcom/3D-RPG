extends GutTest

## StealthStatus (the Fallout-style [HIDDEN]/[DETECTED]/[DANGER] alert + a graded detection METER) — aggregates
## how aware nearby NPCs are of the player; the WORST awareness wins, the HIGHEST detection meter is the HUD
## "heat" + names the spotter. Pure logic: stub "NPCs" expose awareness_of + detection_of. NPC.awareness_of /
## detection_of are checked off-tree (no Perception child -> UNAWARE / 0, so the HUD never crashes on a bare NPC).

## A stand-in NPC reporting a fixed Perception.State + detection meter, duck-typed for StealthStatus.
class _StubNpc:
	var _state: int
	var _meter: float
	func _init(s: int, m: float = 0.0) -> void:
		_state = s
		_meter = m
	func awareness_of(_who: Node) -> int:
		return _state
	func detection_of(_who: Node) -> float:
		return _meter

func test_all_unaware_is_hidden() -> void:
	var p := Node.new()
	var npcs := [_StubNpc.new(Perception.State.UNAWARE), _StubNpc.new(Perception.State.UNAWARE)]
	assert_eq(StealthStatus.of_player(p, npcs)[&"level"], StealthStatus.Level.HIDDEN, "no NPC aware -> HIDDEN")
	p.free()

func test_empty_world_is_hidden_zero_meter_no_spotter() -> void:
	var p := Node.new()
	var snap := StealthStatus.of_player(p, [])
	assert_eq(snap[&"level"], StealthStatus.Level.HIDDEN, "no NPCs -> HIDDEN")
	assert_almost_eq(float(snap[&"meter"]), 0.0, 0.0001, "no NPCs -> zero heat")
	assert_null(snap[&"spotter"], "no NPCs -> no spotter")
	p.free()

func test_detecting_is_detected() -> void:
	var p := Node.new()
	assert_eq(StealthStatus.of_player(p, [_StubNpc.new(Perception.State.UNAWARE), _StubNpc.new(Perception.State.DETECTING)])[&"level"],
		StealthStatus.Level.DETECTED, "an NPC DETECTING (meter filling) -> DETECTED")
	p.free()

func test_investigating_is_caution() -> void:
	var p := Node.new()
	assert_eq(StealthStatus.of_player(p, [_StubNpc.new(Perception.State.INVESTIGATING)])[&"level"],
		StealthStatus.Level.CAUTION, "an NPC INVESTIGATING (actively searching, lost you) -> CAUTION")
	p.free()

func test_caution_outranks_detected() -> void:
	# A searcher (CAUTION) outranks a being-seen meter (DETECTED) in the worst-of aggregate (the tunable order).
	var p := Node.new()
	assert_eq(StealthStatus.of_player(p, [_StubNpc.new(Perception.State.DETECTING), _StubNpc.new(Perception.State.INVESTIGATING)])[&"level"],
		StealthStatus.Level.CAUTION, "a searching NPC (CAUTION) outranks a merely DETECTING one")
	p.free()

func test_any_alerted_is_danger_and_outranks_the_rest() -> void:
	var p := Node.new()
	# ALERTED wins regardless of order (worst categorical level).
	assert_eq(StealthStatus.of_player(p, [_StubNpc.new(Perception.State.DETECTING), _StubNpc.new(Perception.State.ALERTED)])[&"level"],
		StealthStatus.Level.DANGER, "an ALERTED foe -> DANGER, outranking a merely DETECTING one")
	assert_eq(StealthStatus.of_player(p, [_StubNpc.new(Perception.State.ALERTED), _StubNpc.new(Perception.State.DETECTING)])[&"level"],
		StealthStatus.Level.DANGER, "ALERTED still wins when it comes first")
	assert_eq(StealthStatus.of_player(p, [_StubNpc.new(Perception.State.INVESTIGATING), _StubNpc.new(Perception.State.ALERTED)])[&"level"],
		StealthStatus.Level.DANGER, "an ALERTED foe -> DANGER, outranking a searching (CAUTION) one")
	p.free()

func test_reports_worst_meter_and_its_spotter() -> void:
	var p := Node.new()
	var hot := _StubNpc.new(Perception.State.DETECTING, 0.8)
	var npcs := [_StubNpc.new(Perception.State.DETECTING, 0.3), hot, _StubNpc.new(Perception.State.UNAWARE, 0.0)]
	var snap := StealthStatus.of_player(p, npcs)
	assert_almost_eq(float(snap[&"meter"]), 0.8, 0.0001, "the highest detection meter is the HUD heat")
	assert_eq(snap[&"spotter"], hot, "and the spotter is the NPC holding it")
	p.free()

func test_npc_awareness_and_detection_are_neutral_off_tree() -> void:
	# A bare NPC (no _ready) has no Perception child, so awareness_of is UNAWARE and detection_of is 0 -- the
	# stealth HUD is safe to poll a freshly built / off-tree NPC.
	var n = load("res://scripts/npc/npc.gd").new()
	assert_eq(n.awareness_of(n), Perception.State.UNAWARE, "no Perception child -> UNAWARE")
	assert_almost_eq(n.detection_of(n), 0.0, 0.0001, "no Perception child -> 0 detection")
	n.free()
