extends Node
## @system PS1 Warp
## @seam GameRoot drives Ps1Warp.cover() on level load; cover() parents ONE ps1_applier under the LevelRoot (freed with it), not a global SceneTree.node_added listener.
## @risk If the LevelRoot gate breaks or GameRoot stops calling cover(), levels get no applier and the PS1 look silently disappears; test_level_data.gd::test_game_root_load_level_covers_a_levelroot_with_the_ps1_warp asserts the applier attaches on load.
## @test res://tests/test_global_node_added_listeners.gd
## @test res://tests/test_level_data.gd
## Global PS1 warp (autoload, registered as "Ps1Warp"). Applies the ps1.gdshader vertex-snap wobble (the shader's
## affine texture warp ships OFF — see ps1_applier.gd / ps1.gdshader) to
## EVERY level as it loads, with no per-scene editing — the same "cover every level from an autoload" idea as
## StarSky (star_sky.gd), but for the world's MESH geometry instead of the sky.
##
## HOW: GameRoot owns the level-load seam — it adds each level scene as its "Level" child (see game_root.gd) — so
## GameRoot CALLS us (`cover(level_root)`) the moment a level enters, and we parent ONE ps1_applier.gd Node under
## that level with target_root = it. That reuses the applier's whole tested contract — opaque surfaces only, skips
## Character / Throwable / Camera3D subtrees (so NPC outline / hit-flash and any view-model survive), and the live
## Settings.ps1_warp_intensity accessibility slider (apply / rescale / restore). Being a CHILD of the level, the
## applier is freed WITH the level on a LevelDoor swap, so it never walks a freed scene, and its runtime material
## OVERRIDES vanish with the meshes (the saved .tscn is never touched).
##
## WHY a GameRoot call and NOT a tree-wide node_added listener: SceneTree.node_added fires for EVERY node entering
## the tree project-wide, so a global listener here would tax all instantiation just to catch the rare LevelRoot.
## GameRoot already knows exactly when a level loads — boot, a LevelDoor swap, and a death reload_current_scene all
## funnel through GameRoot.load_level — so it drives the warp directly. One fewer global listener (the invariant in
## tests/test_global_node_added_listeners.gd). This autoload persists across a reload_current_scene, so it's always
## live for GameRoot to call.
##
## SCOPE: only LEVEL roots are covered (the `is LevelRoot` gate below), so the start menu and other non-level scenes
## are left alone even if a caller hands one in. A hand-authored scene that isn't a LevelRoot (e.g. computerroom.tscn)
## opts in by dropping the ps1_applier.gd Node in directly — which is exactly what this autoload does for a level
## automatically.

const PS1_APPLIER: Script = preload("res://scripts/effects/ps1_applier.gd")
## Stamped on a level root once we've parented its applier, so a duplicate cover() (GameRoot re-covering, a re-entry)
## can't double it up. Runtime-only metadata on the live instance — nothing is persisted.
const APPLIED_META := &"_ps1_warp_applied"

## GameRoot calls this as a level enters the tree (game_root.gd: load_level for a loaded level, _ready for the
## adopt-incrementally hardcoded "Level" child). Parents ONE ps1_applier under `level_root`, but only for an actual
## LevelRoot — a non-level scene handed in is ignored, keeping non-level scenes untouched. Idempotent via
## APPLIED_META so a second call for the same level is a no-op. is_instance_valid FIRST: `x is LevelRoot` on a freed
## instance is a hard error, so short-circuit on validity before the type check.
func cover(level_root: Node) -> void:
	if not is_instance_valid(level_root) or not (level_root is LevelRoot):
		return
	if level_root.has_meta(APPLIED_META):
		return
	# By the time GameRoot calls us the level's whole subtree has finished entering the tree (add_child returned), so
	# no deferral is needed — and the applier walks the geometry on its own first _process frame regardless.
	level_root.set_meta(APPLIED_META, true)
	var applier: Node = PS1_APPLIER.new()
	applier.name = "Ps1Warp"
	applier.target_root = level_root  # walk THIS level (not get_tree().current_scene, which is game.tscn's root)
	level_root.add_child(applier)
