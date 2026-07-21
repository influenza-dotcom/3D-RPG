class_name StealthStatus

## The player's overall stealth level, aggregated from how aware nearby NPCs are OF THE PLAYER — drives the
## Fallout-style [HIDDEN] / [DETECTED] / [CAUTION] / [DANGER] HUD readout, plus a graded detection METER (0..1)
## and the NPC holding it, for the detection-bar HUD + a directional "who's onto me" cue. Pure (takes the player +
## the npc list), so it unit-tests without a tree; the WORST awareness across all NPCs wins.

## Worst-to-best ladder (the int order IS the priority for maxi()): DANGER (in combat) > CAUTION (actively
## searching, lost you) > DETECTED (meter filling, being seen) > HIDDEN. The CAUTION-vs-DETECTED order is a
## deliberate, single-line-tunable call — swap their positions here to make a being-seen NPC outrank a searcher.
enum Level { HIDDEN, DETECTED, CAUTION, DANGER }

## A snapshot of the player's stealth standing across `npcs`, as a Dictionary:
##   level   : Level — worst categorical awareness (ALERTED -> DANGER, INVESTIGATING -> CAUTION, DETECTING -> DETECTED, else HIDDEN)
##   meter   : float — the highest detection meter (0..1) any NPC holds toward the player (the HUD "heat")
##   spotter : Node  — the NPC holding that highest meter, or null (for a directional cue)
## `npcs` is typically get_tree().get_nodes_in_group(Groups.NPC); members are duck-typed for awareness_of /
## detection_of (NPCs expose both; a member missing either is skipped for that aggregate).
static func of_player(player: Node, npcs: Array) -> Dictionary:
	var worst_level: int = Level.HIDDEN
	var max_meter := 0.0
	var spotter: Object = null  # Object, not Node: the aggregate is duck-typed (real NPCs are Nodes; tests stub RefCounteds)
	for n in npcs:
		if n == null or not n.has_method(&"awareness_of"):
			continue
		var lvl: int = Level.HIDDEN
		match n.awareness_of(player):
			Perception.State.ALERTED:
				lvl = Level.DANGER
			Perception.State.INVESTIGATING:
				lvl = Level.CAUTION
			Perception.State.DETECTING:
				lvl = Level.DETECTED
		worst_level = maxi(worst_level, lvl)
		if n.has_method(&"detection_of"):
			var m: float = n.detection_of(player)
			if m > max_meter:
				max_meter = m
				spotter = n
	return {&"level": worst_level, &"meter": max_meter, &"spotter": spotter}
