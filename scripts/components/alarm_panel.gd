@tool
class_name AlarmPanel
extends Node3D

## Drop-in ALARM (GA-3). Trip it — wire a TriggerVolume (action = "trip", target = this), have a guard call
## trip(), or hook it to an interactable — to (1) spawn a reinforcement wave from a wired EncounterSpawner,
## (2) turn a whole faction hostile to the player, and (3) optionally sound a klaxon. ONE-SHOT: a second trip
## does nothing, so the wave can't be farmed. The faction reputation penalty is applied EXACTLY ONCE here (not
## once per NPC), so sounding the alarm on a big squad doesn't multiply the standing hit (the GA-3 risk).

## Faction registry (no class_name -> preloaded by path), used by _validate_property to populate the
## alarm_faction_id dropdown from resources/factions/ (mirrors NpcData / npc.gd).
const Factions := preload("res://scripts/faction/factions.gd")

## The EncounterSpawner fired for reinforcements when the alarm trips. Empty = no reinforcements (aggro only).
@export var spawner_path: NodePath
## Which faction turns hostile to the player on trip — a dropdown auto-populated from resources/factions/.
## Empty = no faction aggro (just reinforcements / the klaxon).
@export var alarm_faction_id: String = ""
## OPTIONAL klaxon played at this panel when the alarm trips. Null = silent.
@export var alarm_sound: AudioStream = null

var _tripped: bool = false

## Trip the alarm: reinforcements + faction-wide aggro + klaxon. One-shot — a second call is a no-op.
func trip() -> void:
	if _tripped or not is_inside_tree():
		return
	_tripped = true
	if not spawner_path.is_empty():
		var spawner := get_node_or_null(spawner_path) as EncounterSpawner
		if spawner != null:
			spawner.trigger_spawn()  # the reinforcement wave
	_aggro_faction()
	if alarm_sound != null:
		AudioManager.play_sfx(global_position, alarm_sound)

## Turn the alarm faction hostile to the player. The reputation penalty is applied ONCE (here), then every
## member is flipped hostile WITHOUT re-dropping rep — so the standing hit is a single provoke, not one per NPC.
func _aggro_faction() -> void:
	if alarm_faction_id.is_empty():
		return
	var fac := Factions.by_id(alarm_faction_id)
	if fac == null:
		return
	Reputation.add_reputation(fac, -GameSettings.reputation.provoke_penalty)  # ONCE — never multiplied by squad size
	aggro_faction_members(get_tree().get_nodes_in_group(&"npc"), fac, get_tree().get_first_node_in_group(&"player"))

## Flip every member of `fac` in `npcs` hostile to `player` WITHOUT each re-dropping rep (provoke(.., false)) —
## the caller applies the faction penalty once. Returns how many were flipped. Static + list-injected + duck-typed
## so it unit-tests with stubs (the &"npc" group holds only real NPCs in play). Skips nulls / non-provokable nodes.
static func aggro_faction_members(npcs: Array, fac: Faction, player: Node) -> int:
	if fac == null:
		return 0
	var count := 0
	for node in npcs:
		if node == null or not node.has_method(&"provoke"):
			continue
		var f = node.get(&"faction")
		if f is Faction and (f as Faction).id == fac.id:
			node.provoke(player, false)  # hostile, but DON'T re-drop rep — we applied the penalty once above
			count += 1
	return count

## True once the alarm has been tripped (a second trip is a no-op) — for a designer to read / gate on.
func has_tripped() -> bool:
	return _tripped

## Editor-only: populate the alarm_faction_id dropdown from the factions on disk so a new faction .tres appears
## automatically (the disk-backed-dropdown idiom; safe under @tool because this node has no runtime lifecycle).
func _validate_property(property: Dictionary) -> void:
	if property.name == &"alarm_faction_id":
		property.hint = PROPERTY_HINT_ENUM_SUGGESTION
		property.hint_string = Factions.ids_csv()
