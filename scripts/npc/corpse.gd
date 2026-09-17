@tool
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

## Stable key for an authored corpse marker (the primary key; see WorldSaveId). A blank one falls back to the
## path/position key, which a rename or move loses, so a hand-placed body in a level warns until it has one. A marker
## spawned at a death at runtime never needs one.
@export var save_id: StringName = &""

## Once true, NPCs stop reacting to this body. Flipped by the FIRST NPC that notices it (NpcDistraction.discover_corpse),
## so a single body draws ONE investigator rather than spooking every passer-by off the same spot. This one-shot
## marker is persisted by GameState so an already-investigated authored body does not re-spook after Continue.
var discovered: bool = false
## The dead NPC's display name, kept for flavour (a future "It's <name>!" line could read it). Set by the
## spawner; harmless when empty.
var who: String = ""

func _ready() -> void:
	if Engine.is_editor_hint():
		return  # @tool only so the editor shows _get_configuration_warnings; a marker does nothing in the editor
	add_to_group(GROUP)
	# Through WorldSaveId's legacy path: a hand-placed body stamped with a save_id still finds a discovery saved before.
	if WorldSaveId.corpse_discovered(self, save_id):
		discovered = true

func _get_configuration_warnings() -> PackedStringArray:
	var w := PackedStringArray()
	var id_warning := WorldSaveId.blank_id_warning(self)
	if id_warning != "":
		w.append(id_warning)
	return w

## The persistence key for the narrow "already discovered" marker — the SHARED WorldSaveId key: an authored save_id
## is the whole key ("id:<x>", survives moves), else the level|scene-path|rounded-position fallback. A body that
## gains a save_id reads its old fallback-keyed discovery once through WorldSaveId.corpse_discovered (the legacy read
## path). Older history: the bespoke pre-WorldSaveId key also folded in `who`; a save from before THAT fold still
## re-keys, so a once-investigated body with no save_id may re-spook once (body-discovery is off by default).
func save_key() -> String:
	return WorldSaveId.key_for(self, save_id)

## Pure first-gate: can an observer at `observer_pos` NOTICE a body at `corpse_pos`? Just the range test --
## within `sight_range` metres (and a positive range). Static + Vector3-only so it tests off-tree with no
## nodes or transform reads; the live scan (NPC._nearest_visible_corpse) adds a line-of-sight ray on top of this.
static func noticeable(corpse_pos: Vector3, observer_pos: Vector3, sight_range: float) -> bool:
	return sight_range > 0.0 and corpse_pos.distance_to(observer_pos) <= sight_range
