extends GutTest

## A bare off-tree NPC (load().new(), no _ready — the test_hostility/test_enemies construction pattern) exposes
## aim_distance() for BodyModelSwap's "raise the arms only when the foe is close" proximity gate. With no target
## it must return INF (so the raised-arm pose stays gated OFF), and it must NOT touch global_transform on that
## path (an off-tree transform read logs a tracked engine error that fails GUT 9.6).

const NPC_PATH := "res://scripts/npc/npc.gd"

func test_aim_distance_is_inf_without_a_target() -> void:
	var e = load(NPC_PATH).new()
	assert_eq(e.aim_distance(), INF, "no target -> INF, so the raised-arm pose stays gated off (arms down)")
	e.free()
