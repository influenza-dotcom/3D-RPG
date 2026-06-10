class_name NpcTargeting
extends Node

## NPC target ACQUISITION, split off npc.gd (Wave 3 SRP #6). Decides WHO this NPC fights: a protectee's
## attacker first (companion / bodyguard duty), then a sticky lock on whoever last attacked us, else the
## nearest hostile across the player + NPC groups within sight_range. The retarget throttle in npc.gd calls
## _target_invalid() (O(1)) most frames and only pays for the full _acquire_target() scan when it must.
##
## The chosen target + its LOS body live on the NPC (_target / _target_body, read everywhere by combat,
## movement, and barks); this component computes the choice and BINDS it via host._set_target. `host` is typed
## Node to break the NpcTargeting <-> NPC class cycle, so every host.X is a dynamic call; the npc-group members
## are iterated UNTYPED for the same reason (the group only ever holds NPCs). Built in NPC._build_components.

var host: Node = null  ## the NPC we pick targets for (Node-typed to avoid the class cycle)


## Whether our current target is gone, out of sight_range, or no longer an enemy — the O(1) check the retarget
## throttle runs most frames before paying for a full _acquire_target scan.
func _target_invalid() -> bool:
	if not is_instance_valid(host._target):
		return true
	if host.global_position.distance_to(host._target.global_position) > host.sight_range:
		return true
	return not host._treats_as_enemy(host._target)


## Pick the nearest hostile node: the player(s) plus every NPC peer, filtered by host._treats_as_enemy() and
## sight_range, nearest wins. Protector duty first (defend a protectee), then a sticky lock on the last
## attacker, else the nearest-foe scan. Binds the result through host._set_target (which also feeds Perception).
func _acquire_target() -> void:
	# Protector duty FIRST: an NPC defending a protectee (a player companion OR a bodyguard) prioritises
	# whoever is threatening its charge over its own nearest foe — so it peels off to protect them. Skipped
	# entirely for an NPC with no protectee.
	if host._protectee() != null:
		var defend := _pick_defend_target()
		if defend != null:
			host._last_attacker = null  # a defend target isn't "who hit us"; don't let the attacker-lock fight it
			host._set_target(defend)
			return
	# Stay locked on the last character that actually attacked us — while it's still a valid, engageable,
	# in-range threat — instead of being pulled toward whoever is merely nearest (no easy distraction).
	if is_instance_valid(host._last_attacker) and host._treats_as_enemy(host._last_attacker) and host.global_position.distance_to(host._last_attacker.global_position) <= host.sight_range:
		host._set_target(host._last_attacker)
		return
	host._last_attacker = null  # the aggressor died / fled out of sight_range / is no longer engageable — drop it
	var best: Node3D = null
	var best_d := INF
	# Every member of the &"Player" group is a candidate — the real player AND any recruited companion (which
	# joins that group so a player-hostile enemy targets it too). Iterate them all so an ally can't displace the
	# real player from the scan; each gets the same hostility + range test as any NPC.
	for pnode in host.get_tree().get_nodes_in_group(&"Player"):
		var player := pnode as Node3D
		if not is_instance_valid(player) or not host._treats_as_enemy(player):
			continue
		var pd = host.global_position.distance_to(player.global_position)
		if pd <= host.sight_range and pd < best_d:
			best = player
			best_d = pd
	for node in host.get_tree().get_nodes_in_group(&"npc"):
		var npc = node  # untyped: the npc group only holds NPCs, and typing it NPC would re-form the class cycle
		if npc == host or not is_instance_valid(npc):
			continue
		if not host._treats_as_enemy(npc):
			continue
		var d = host.global_position.distance_to(npc.global_position)
		if d <= host.sight_range and d < best_d:
			best = npc
			best_d = d
	host._set_target(best)


## Companion defence: the foe a following NPC should engage to protect its leader, or null if none qualifies.
## Prefers the leader's MOST-RECENT attacker when it exposes one (NPC leaders carry _last_attacker; the player
## doesn't), else the nearest NPC hostile to the leader within our sight. Every candidate is filtered through
## host._treats_as_enemy so we only fight a genuine enemy / unaligned-hostile assailant — never a bumped ally.
func _pick_defend_target() -> Node3D:
	var prot = host._protectee()
	if not is_instance_valid(prot):
		return null
	# 1) The protectee's own latest attacker, if it publishes one. Engage it only if it's in our sight and
	#    we'd actually treat it as an enemy.
	var la := prot.get(&"_last_attacker") as Node3D
	if is_instance_valid(la) and host._treats_as_enemy(la) \
			and host.global_position.distance_to(la.global_position) <= host.sight_range:
		return la
	# 2) Otherwise, the nearest NPC hostile TOWARD the protectee and within our reach. Nearest to US wins.
	var best: Node3D = null
	var best_d := INF
	for node in host.get_tree().get_nodes_in_group(&"npc"):
		var npc = node
		if npc == host or not is_instance_valid(npc):
			continue
		if not npc.is_hostile_to(prot):
			continue  # only step in for foes actually hostile to our charge
		if not host._treats_as_enemy(npc):
			continue
		var d = host.global_position.distance_to(npc.global_position)
		if d <= host.sight_range and d < best_d:
			best = npc
			best_d = d
	return best
