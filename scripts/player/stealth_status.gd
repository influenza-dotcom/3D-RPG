class_name StealthStatus

## The player's overall stealth level, aggregated from how aware nearby NPCs are OF THE PLAYER — drives the
## Fallout-style [HIDDEN] / [DETECTED] / [DANGER] HUD readout. Pure (takes the player + the npc list), so it
## unit-tests without a tree; the WORST awareness across all NPCs wins.

enum Level { HIDDEN, DETECTED, DANGER }

## The worst awareness any NPC in `npcs` currently holds toward `player`: an ALERTED foe -> DANGER, a
## DETECTING / INVESTIGATING one -> DETECTED, all UNAWARE (or not tracking us) -> HIDDEN. `npcs` is typically
## get_tree().get_nodes_in_group(&"npc"); each member is duck-typed for awareness_of (NPCs expose it).
static func of_player(player: Node, npcs: Array) -> Level:
	var worst := Level.HIDDEN
	for n in npcs:
		if n == null or not n.has_method(&"awareness_of"):
			continue
		match n.awareness_of(player):
			Perception.State.ALERTED:
				return Level.DANGER  # nothing is worse — stop early
			Perception.State.DETECTING, Perception.State.INVESTIGATING:
				worst = Level.DETECTED
	return worst
