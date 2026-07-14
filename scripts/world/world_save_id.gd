extends RefCounted

## @system Save Model
## @seam WorldSaveId.key_for(node, save_id): an authored save_id is the whole key 'id:<x>' (survives moves), else a level|path|position (_round_cm) fallback — the shared GameState.world_objects key generalizing Corpse.save_key().
## @risk Changing the fallback shape (node_path source or _round_cm precision) silently re-keys every un-authored object, so its saved state stops matching on reload — no error.
## @risk Moving/renaming a hand-placed node between saves silently orphans its fallback-keyed state; give important objects/bodies a save_id or their world-state is lost after any layout edit.
## @test res://tests/test_game_save.gd
## Preloaded as a const where needed (NO class_name — nothing for the global script class cache to miss, matching
## Factions / GoapLibrary / ItemIds). Consumers: `const WorldSaveId = preload("res://scripts/world/world_save_id.gd")`.
##
## Stable-enough persistence key for a per-placed WORLD object — a door's open/locked state, a consumed pickup, a
## destroyed prop — keyed into GameState.world_objects (the additive per-object ledger). Generalizes
## Corpse.save_key() so every persistable component keys the same way.
##
## An authored `save_id` wins ("id:<x>"). Otherwise a level|scene-path|rounded-position FALLBACK lets a hand-placed
## object survive a reload WITHOUT authoring a new id. The fallback is FRAGILE: it silently re-keys if a designer
## moves or renames the node between saves (a saved-open door could then fail to restore, or restore onto a
## different door). So set an explicit `save_id` on the hand-placed objects whose state MUST survive layout edits —
## exactly the Corpse.save_id guidance. The node_path component keeps keys distinct even at the same position, so a
## dynamically-spawned object recording state can't collide with a different authored one.

static func key_for(node: Node3D, save_id: StringName) -> String:
	if save_id != &"":
		return "id:%s" % String(save_id)
	var node_path: String = str(node.get_path()) if node.is_inside_tree() else String(node.name)
	# global_position off-tree raises an engine error; the fallback is only meaningful in-tree (restore runs in
	# _ready), so zero the position off-tree rather than error — the node_path still distinguishes such keys.
	var p := node.global_position if node.is_inside_tree() else Vector3.ZERO
	return "%s|%s|%.2f,%.2f,%.2f" % [
		GameState.current_level_path,
		node_path,
		_round_cm(p.x), _round_cm(p.y), _round_cm(p.z),
	]

static func _round_cm(v: float) -> float:
	return roundf(v * 100.0) / 100.0
