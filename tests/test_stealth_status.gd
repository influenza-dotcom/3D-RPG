extends GutTest

## StealthStatus (the Fallout-style [HIDDEN]/[DETECTED]/[DANGER] alert) — aggregates how aware nearby NPCs are
## of the player; the WORST awareness wins. Pure logic: stub "NPCs" expose awareness_of(). NPC.awareness_of
## itself is checked off-tree (no Perception child -> UNAWARE, so the HUD never crashes on a bare NPC).

## A stand-in NPC that reports a fixed Perception.State, duck-typed for StealthStatus (it just needs awareness_of).
class _StubNpc:
	var _state: int
	func _init(s: int) -> void:
		_state = s
	func awareness_of(_who: Node) -> int:
		return _state


func test_all_unaware_is_hidden() -> void:
	var p := Node.new()
	var npcs := [_StubNpc.new(Perception.State.UNAWARE), _StubNpc.new(Perception.State.UNAWARE)]
	assert_eq(StealthStatus.of_player(p, npcs), StealthStatus.Level.HIDDEN,
		"no NPC aware of the player -> HIDDEN")
	p.free()


func test_empty_world_is_hidden() -> void:
	var p := Node.new()
	assert_eq(StealthStatus.of_player(p, []), StealthStatus.Level.HIDDEN, "no NPCs at all -> HIDDEN")
	p.free()


func test_detecting_or_investigating_is_detected() -> void:
	var p := Node.new()
	assert_eq(StealthStatus.of_player(p, [_StubNpc.new(Perception.State.UNAWARE), _StubNpc.new(Perception.State.DETECTING)]),
		StealthStatus.Level.DETECTED, "an NPC DETECTING the player -> DETECTED")
	assert_eq(StealthStatus.of_player(p, [_StubNpc.new(Perception.State.INVESTIGATING)]),
		StealthStatus.Level.DETECTED, "an NPC INVESTIGATING (searching) the player -> DETECTED")
	p.free()


func test_any_alerted_is_danger_and_outranks_detected() -> void:
	var p := Node.new()
	# ALERTED wins regardless of order (the early-return on the worst level).
	assert_eq(StealthStatus.of_player(p, [_StubNpc.new(Perception.State.DETECTING), _StubNpc.new(Perception.State.ALERTED)]),
		StealthStatus.Level.DANGER, "an ALERTED foe -> DANGER, outranking a merely DETECTING one")
	p.free()


func test_npc_awareness_of_is_unaware_off_tree() -> void:
	# A bare NPC (no _ready) has no Perception child, so awareness_of is UNAWARE — the stealth HUD is safe to
	# poll a freshly built / off-tree NPC.
	var n = load("res://scripts/npc/npc.gd").new()
	assert_eq(n.awareness_of(n), Perception.State.UNAWARE, "no Perception child -> UNAWARE (off-tree safe)")
	n.free()
