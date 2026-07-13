extends Node
## Global PS1 warp (autoload, registered as "Ps1Warp"). Applies the ps1.gdshader vertex-snap / affine-warp look to
## EVERY level as it loads, with no per-scene editing — the same "cover every scene load from an autoload" idea as
## StarSky (star_sky.gd), but for the world's MESH geometry instead of the sky.
##
## HOW: a level enters the tree as a LevelRoot (GameRoot adds the level scene as its "Level" child — see
## game_root.gd). We watch get_tree().node_added for a LevelRoot, then parent ONE ps1_applier.gd Node under it with
## target_root = that level. That reuses the applier's whole tested contract — opaque surfaces only, skips
## Character / Throwable / Camera3D subtrees (so NPC outline / hit-flash and any view-model survive), and the live
## Settings.ps1_warp_intensity accessibility slider (apply / rescale / restore). Being a CHILD of the level, the
## applier is freed WITH the level on a LevelDoor swap, so it never walks a freed scene, and its runtime material
## OVERRIDES vanish with the meshes (the saved .tscn is never touched).
##
## SCOPE: only LEVEL roots are auto-covered, so the start menu and other non-level scenes are left alone. A
## hand-authored scene that isn't a LevelRoot (e.g. computerroom.tscn) opts in by dropping the ps1_applier.gd Node
## in directly — which is exactly what this autoload does for a level automatically.
##
## (Autoloads ready BEFORE the main scene, so there is no level in the tree yet at _ready — the level's own load is
## what triggers us. reload_current_scene() on death re-runs GameRoot and re-adds a fresh LevelRoot, which we cover
## again; this autoload persists across that reload, so the node_added connection stays live.)

const PS1_APPLIER: Script = preload("res://scripts/effects/ps1_applier.gd")
## Stamped on a level root once we've parented its applier, so a duplicate node_added (or a re-entry) can't double
## it up. Runtime-only metadata on the live instance — nothing is persisted.
const APPLIED_META := &"_ps1_warp_applied"

func _ready() -> void:
	# node_added fires for every node entering the tree; the handler early-outs on the non-LevelRoot common case.
	get_tree().node_added.connect(_on_node_added)

func _on_node_added(node: Node) -> void:
	if node is LevelRoot:
		# Defer: when a LevelRoot's node_added fires, its child geometry may not have entered the tree yet, so
		# walking it now would miss meshes. By the deferred call the whole level subtree is settled.
		_cover.call_deferred(node)

func _cover(root: Node) -> void:
	if not is_instance_valid(root) or root.has_meta(APPLIED_META):
		return
	root.set_meta(APPLIED_META, true)
	var applier: Node = PS1_APPLIER.new()
	applier.name = "Ps1Warp"
	applier.target_root = root  # walk THIS level (not get_tree().current_scene, which is game.tscn's root)
	root.add_child(applier)
