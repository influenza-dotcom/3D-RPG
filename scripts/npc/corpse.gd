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
## Shared per-object save key (the same one Door/CanPickUp/… use for GameState.world_objects) so corpse discovery
## keys IDENTICALLY to the rest of the ledger instead of a bespoke twin. Preloaded (no class_name) per the idiom.
const WorldSaveId = preload("res://scripts/world/world_save_id.gd")

## Optional stable key for authored corpse markers. Leave blank for the path/position fallback; set it on
## hand-placed story bodies when you want the discovery state to survive node renames or layout edits.
@export var save_id: StringName = &""

## Once true, NPCs stop reacting to this body. Flipped by the FIRST NPC that notices it (NpcDistraction.discover_corpse),
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

## Stable-enough persistence key for the narrow "already discovered" marker — now the SHARED world_objects key
## (WorldSaveId.key_for): an authored save_id is the whole key ("id:<x>", survives moves), else a
## level|scene-path|rounded-position fallback so hand-placed bodies survive reloads without a new asset. The old
## bespoke key also folded in `who` (the dead NPC's name), but node_path already disambiguates same-spot bodies, so
## dropping it just unifies the scheme (and gains WorldSaveId's off-tree guard for free — global_position off-tree
## would have errored). BACK-COMPAT: a pre-fold save's FALLBACK-keyed discovery markers re-key and won't match, so a
## once-investigated UN-AUTHORED body may re-spook once after loading an old save — low stakes (body-discovery is
## off by default, and authored "id:<x>" keys are unchanged). Give story bodies a save_id if discovery must persist.
func save_key() -> String:
	return WorldSaveId.key_for(self, save_id)

## Pure first-gate: can an observer at `observer_pos` NOTICE a body at `corpse_pos`? Just the range test --
## within `sight_range` metres (and a positive range). Static + Vector3-only so it tests off-tree with no
## nodes or transform reads; the live scan (NPC._nearest_visible_corpse) adds a line-of-sight ray on top of this.
static func noticeable(corpse_pos: Vector3, observer_pos: Vector3, sight_range: float) -> bool:
	return sight_range > 0.0 and corpse_pos.distance_to(observer_pos) <= sight_range
