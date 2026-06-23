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

const GROUP := Groups.CORPSE  ## same value (&"corpse") as before — npc.gd's Corpse.GROUP read is unaffected

## Once true, NPCs stop reacting to this body. Flipped by the FIRST NPC that notices it (NPC._discover_corpse),
## so a single body draws ONE investigator rather than spooking every passer-by off the same spot.
## TODO save-gap: `discovered` is NOT persisted across save/reload — a body already investigated before a
## save will re-spook NPCs after a reload. Persisting corpse markers is a dedicated save-format change.
var discovered: bool = false
## The dead NPC's display name, kept for flavour (a future "It's <name>!" line could read it). Set by the
## spawner; harmless when empty.
var who: String = ""

func _ready() -> void:
	add_to_group(GROUP)

## Pure first-gate: can an observer at `observer_pos` NOTICE a body at `corpse_pos`? Just the range test --
## within `sight_range` metres (and a positive range). Static + Vector3-only so it tests off-tree with no
## nodes or transform reads; the live scan (NPC._nearest_visible_corpse) adds a line-of-sight ray on top of this.
static func noticeable(corpse_pos: Vector3, observer_pos: Vector3, sight_range: float) -> bool:
	return sight_range > 0.0 and corpse_pos.distance_to(observer_pos) <= sight_range
