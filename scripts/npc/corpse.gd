class_name Corpse
extends Node3D

## A discoverable death marker, left at an NPC's death spot when stealth body-discovery is enabled
## (GameSettings.npc_ai.body_discovery, off by default). A nearby UNAWARE NPC that SEES it gets spooked: it
## walks over to INVESTIGATE the spot and calls out ("Hey -- a body!"), so a quiet kill now risks raising the
## alarm instead of being free. In the &"corpse" group (a cheap scan target for NPC._nearest_visible_corpse); marks
## itself `discovered` once an NPC has reacted, so the whole neighbourhood doesn't pile onto one body -- one
## investigation per corpse, not one per passing NPC.
##
## A pure MARKER -- no mesh, no physics. The VISIBLE body is the ragdoll / LootableCorpse; this is just the
## "AI can notice a death here" beacon, kept separate so it spawns for EVERY death (loot or not, ragdoll or
## not) and so the noticing logic (noticeable()) stays unit-testable off-tree. Drop one into a level by hand
## to seed a "someone died here" investigation beat without an actual kill.

const GROUP := Groups.CORPSE  ## same value (&"corpse") as before; npc.gd's Corpse.GROUP read is unaffected

## Optional stable key for authored corpse markers. Leave blank for the path/position fallback; set it on
## hand-placed story bodies when you want the discovery state to survive node renames or layout edits.
@export var save_id: StringName = &""

## Once true, NPCs stop reacting to this body. Flipped by the FIRST NPC that notices it (NPC._discover_corpse),
## so a single body draws ONE investigator rather than spooking every passer-by off the same spot. This one-shot
## marker is persisted by GameState so an already-investigated authored body does not re-spook after Continue.
var discovered: bool = false
## The dead NPC's display name, kept for flavour (a future "It's <name>!" line could read it). Set by the
## spawner; harmless when empty.
var who: String = ""

func _ready() -> void:
	add_to_group(GROUP)
	if GameState.is_corpse_discovered(save_key()):
		discovered = true

## Stable-enough persistence key for the narrow "already discovered" marker. Authored save_id wins; otherwise
## use level + scene path + rounded position so hand-placed bodies survive reloads without requiring a new asset.
func save_key() -> String:
	if save_id != &"":
		return "id:%s" % String(save_id)
	var node_path: String = str(get_path()) if is_inside_tree() else String(name)
	var p := global_position
	return "%s|%s|%s|%.2f,%.2f,%.2f" % [
		GameState.current_level_path,
		node_path,
		who,
		_round_centimeters(p.x),
		_round_centimeters(p.y),
		_round_centimeters(p.z),
	]

static func _round_centimeters(v: float) -> float:
	return roundf(v * 100.0) / 100.0

## Pure first-gate: can an observer at `observer_pos` NOTICE a body at `corpse_pos`? Just the range test --
## within `sight_range` metres (and a positive range). Static + Vector3-only so it tests off-tree with no
## nodes or transform reads; the live scan (NPC._nearest_visible_corpse) adds a line-of-sight ray on top of this.
static func noticeable(corpse_pos: Vector3, observer_pos: Vector3, sight_range: float) -> bool:
	return sight_range > 0.0 and corpse_pos.distance_to(observer_pos) <= sight_range
