extends GutTest

## Scene-drift contract for the ragdoll corpse (scenes/props/skeleton.tscn). Ragdoll no longer binds the
## corpse light via a ~15-segment authored NodePath (it silently resolved to null on any re-import/re-rig and
## crashed _process); it now uses NodeFinder.find_first_of_class(self, OmniLight3D). This test pins the two nodes
## that lookup + the physics start depend on, so a re-import that drops or renames them fails loudly HERE instead
## of at runtime. Off-tree instantiate() does NOT run Ragdoll._ready (no physics await) — safe per the no-_ready rule.
const RAGDOLL_SCENE := "res://scenes/props/skeleton.tscn"

func test_ragdoll_scene_carries_corpse_light_and_bones() -> void:
	var ps := load(RAGDOLL_SCENE) as PackedScene
	assert_not_null(ps, "skeleton.tscn (the ragdoll scene) must load")
	var root := ps.instantiate()  # off-tree instantiate does NOT run Ragdoll._ready (no physics await) — safe per the no-_ready rule
	assert_not_null(NodeFinder.find_first_of_class(root, OmniLight3D), "ragdoll scene must carry an OmniLight3D corpse light — Ragdoll._process fades it; drift guard")
	assert_not_null(NodeFinder.find_first_of_class(root, PhysicalBoneSimulator3D), "ragdoll scene must carry a PhysicalBoneSimulator3D so the corpse can ragdoll")
	root.free()
