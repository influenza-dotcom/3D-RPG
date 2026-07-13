extends GutTest

## C6: a TARGET-LESS flee must not null-deref. A scripted investigate() / alarm leaves perception non-UNAWARE with
## NO _target, yet GoapActionFlee still runs -> _act_flee -> host._flee_threat_point(). The combat-hot _aim_point()
## hard-derefs both target handles and would crash; _flee_threat_point() falls back to Perception.last_known_position
## instead. Built off-tree via load(...).new() WITHOUT _ready (per CLAUDE.md). The last-known path reads NO transform
## (last_known_position is a plain Vector3 field) so it is GUT 9.6-safe; the target-present path and the
## no-perception global_position fallback both read transforms -> verified by inspection + playtest.

const NPC_PATH := "res://scripts/npc/npc.gd"
const PERC_PATH := "res://scenes/enemies/perception.gd"


func test_flee_threat_point_uses_last_known_when_targetless() -> void:
	var e = load(NPC_PATH).new()
	var perc = load(PERC_PATH).new()
	perc.last_known_position = Vector3(5, 0, -3)
	e._perception = perc  # no _target / _target_body (bare .new()), so the target handles are null
	assert_eq(e._flee_threat_point(), Vector3(5, 0, -3), "target-less flee runs from last_known_position, not a crash (C6)")
	perc.free()
	e.free()
