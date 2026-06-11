class_name NpcScavenge
extends Node

## NPC container RAIDING: when a nearby, UNLOCKED ItemContainer (group &"containers") holds a weapon
## STRONGER than anything the host carries — or the host is unarmed entirely — walk to it, take that
## weapon, and draw it (equip-the-strongest). Driven from npc.gd's state machine: the idle (UNAWARE)
## branch and the unarmed-ALERTED fallback both let act() own the frame's locomotion while a raid is on.
##
## Throttled (one area scan per SCAN_INTERVAL), respects Lock (a locked crate is invisible to it — NPCs
## don't pick locks), and never runs for a fleer (a FLEE NPC would never fire what it grabbed).
## `host` is the NPC — typed Node to avoid an NPC <-> NpcScavenge class cycle; host.* is dynamic.

const SCAN_INTERVAL := 1.5  ## seconds between candidate scans (the group walk is O(containers))
const SCAN_RADIUS := 12.0   ## how far the NPC notices an upgrade crate
const TAKE_REACH := 2.2     ## close enough to reach in

var host: Node = null

var _scan_t := 0.0
var _target: Node = null  ## the ItemContainer being raided (null = not scavenging)

## Drive one frame of scavenging. Returns true while WALKING TO / TAKING FROM a container — the host then
## skips its normal idle / unarmed behaviour for the frame, since the raid owns the locomotion.
func act(delta: float) -> bool:
	if host == null or host.get_tree() == null or host.is_fleeing():
		return false
	_scan_t -= delta
	if _target == null:
		if _scan_t > 0.0:
			return false
		_scan_t = SCAN_INTERVAL
		_target = _find_upgrade_container()
	if _target == null or not is_instance_valid(_target):
		_target = null
		return false
	var pos: Vector3 = _target.global_position
	if host.global_position.distance_to(pos) > TAKE_REACH:
		if host._move_toward(pos):
			host._face_travel(delta)
			return true
		_target = null  # the navmesh wouldn't route there — forget it (the next scan may find another)
		return false
	_take_best_weapon_from(_target)
	_target = null
	return true

## The nearest unlocked container within SCAN_RADIUS whose best weapon outguns ours, or null. Unarmed
## (score -1) means ANY weapon qualifies — a disarmed combatant or armed-by-circumstance civilian arms up.
func _find_upgrade_container() -> Node:
	var my_score := _current_score()
	var best: Node = null
	var best_d := INF
	for n in host.get_tree().get_nodes_in_group(&"containers"):
		if not is_instance_valid(n) or not (n is Node3D):
			continue
		var lock := Lock.of(n)
		if lock != null and lock.locked:
			continue  # NPCs don't pick locks — a locked crate is invisible to the raid
		var d: float = host.global_position.distance_to((n as Node3D).global_position)
		if d > SCAN_RADIUS or d >= best_d:
			continue
		if _best_weapon_score_in(n) > my_score:
			best = n
			best_d = d
	return best

## What the host's best carried weapon scores (-1 when unarmed, so anything beats it).
func _current_score() -> float:
	var best: Item = host.inventory.best_weapon_item() if host.inventory != null else null
	return best.weapon.power_score() if best != null else -1.0

## The container's best weapon score (-INF for none / not a container inventory).
func _best_weapon_score_in(container: Node) -> float:
	var inv: Variant = container.get(&"inventory")
	if not (inv is CharacterInventory):
		return -INF
	var it: Item = (inv as CharacterInventory).best_weapon_item()
	return it.weapon.power_score() if it != null else -INF

## Reach in: move the container's best weapon into the host's backpack and DRAW the bag's new best —
## the same equip-the-strongest rule the spawn path uses.
func _take_best_weapon_from(container: Node) -> void:
	var inv: Variant = container.get(&"inventory")
	if not (inv is CharacterInventory) or host.inventory == null:
		return
	var it: Item = (inv as CharacterInventory).best_weapon_item()
	if it == null:
		return
	(inv as CharacterInventory).transfer_to(host.inventory, it, 1)
	var best: Item = host.inventory.best_weapon_item()
	if best != null:
		host.inventory.equip_item(best)
