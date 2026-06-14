extends GutTest

## NPC perception-config wiring (stealth Slice 0b): the NPC must COPY its per-archetype perception tunables onto
## the code-built Perception child in _build_perception. Regression for the crouch_sight_mult leak -- it was an
## @export on Perception but never copied in _build_perception, so it sat at the 0.5 default and was silently
## un-tunable per-archetype (the stealth crouch-sight-reduction mechanic couldn't be designer-authored).
##
## Built off-tree via .new() (no _ready, per CLAUDE.md); _build_perception only constructs + configures a
## Perception child (Perception.new() + field copies + a signal connect + add_child) -- safe off-tree.

const NPC_PATH := "res://scripts/npc/npc.gd"

func test_build_perception_copies_per_archetype_tunables() -> void:
	var npc = load(NPC_PATH).new()
	npc.crouch_sight_mult = 0.2
	npc.sight_range = 33.0
	npc._build_perception()
	assert_not_null(npc._perception, "a Perception child is built")
	assert_almost_eq(npc._perception.crouch_sight_mult, 0.2, 0.0001, "crouch_sight_mult is now copied onto Perception (the fixed leak)")
	assert_almost_eq(npc._perception.sight_range, 33.0, 0.0001, "and the existing fields still copy")
	npc.free()
