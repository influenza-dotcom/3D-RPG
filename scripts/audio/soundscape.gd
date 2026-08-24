class_name Soundscape
extends RefCounted

## The ONE owner of "WHO OWNS THE SOUNDSCAPE RIGHT NOW". Pure statics; never instantiated.
##
## Extracted from MusicDirector on 2026-08-22, when the wandering exploration bed
## (scripts/components/wander_music.gd) became a second consumer. The two layers are EXACT COMPLEMENTS — the
## combat score rises precisely when the wandering bed must get out of its way — so a drift between two copies
## of this scan is not a cosmetic bug: it is either a GAP where neither plays or an OVERLAP where both do. A
## complement has to be derived from the same answer, not from a second opinion. (Same reasoning as
## scripts/audio/loopable_stream.gd, extracted the same day for the same kind of reason.)
##
## MusicDirector._scan_alert_levels / ._radio_audible_to_player still exist under their old names and delegate
## here, so tests that force those seams on an instance are unaffected.


## The world's awareness, worst-first — the same escalation the stealth HUD prints. Returned by alert_level()
## for consumers that want ONE ordered answer; the combat score keeps the raw pair instead (see scan()).
##   COMBAT  — somebody is ENGAGED: ALERTED with a live target. An actual firefight.
##   CAUTION — nobody is engaged, but somebody is HUNTING: sweeping a last-known spot, chasing a heard noise,
##             standing over a found body (Perception INVESTIGATING — what the HUD prints as [CAUTION]).
##   CALM    — nobody is aware of anything. Exploration.
enum Alert {
	CALM = 0,
	CAUTION = 1,
	COMBAT = 2,
}


## ONE pass over the `npc` group returning the two flags the dynamic score has always kept:
##   { "combat": somebody is ENGAGED, "caution": somebody is merely HUNTING and nobody is engaged }
## They are NOT mutually exclusive across a crowd: one shooter and one searcher sets BOTH, which is exactly
## what lets a consumer hold a separate linger per tier. Kept as the raw pair (rather than only the collapsed
## alert_level below) so MusicDirector's delegation is byte-for-byte the behaviour it shipped with.
##
## Deliberately a FULL walk, never an early-out on the first fighter. Bailing is free today — COMBAT outranks
## CAUTION at every consumer — but it would make the `caution` answer depend on GROUP ORDER (a shooter listed
## before a searcher would hide the searcher), and that becomes audible the moment anyone gives the two tiers
## different linger times. An O(n) walk on a 0.3 s poll is not worth that trap.
##
## TARGET-AGNOSTIC, matching the long-shipped combat scan: an NPC hunting ANOTHER NPC still scores. That is why
## the music can play while the stealth HUD reads [HIDDEN] — the score follows the fight IN THE WORLD, the HUD
## follows the fight aimed at YOU. To make the music match the HUD instead, gate both predicates on the human
## player here, in this one place, and both layers move together.
##
## A null tree (a bare off-tree instance in a unit test) means nobody is aware of anything.
static func scan(tree: SceneTree) -> Dictionary:
	var out := {"combat": false, "caution": false}
	if tree == null:
		return out
	for n in tree.get_nodes_in_group(Groups.NPC):
		# is_instance_valid FIRST: `is` on a freed instance crashes (house trap).
		if not is_instance_valid(n) or not (n is NPC):
			continue
		var npc := n as NPC
		# Per NPC, not per group: an ALERTED one satisfies BOTH predicates and must count only as a fight.
		if npc.is_in_combat():
			out["combat"] = true
		elif npc.is_hunting():
			out["caution"] = true
	return out


## scan() collapsed to ONE ordered tier, worst-first — the convenient form for a consumer that only needs to
## know how loud the world currently is (the wandering bed, a debug readout). COMBAT outranks CAUTION, so a
## mixed crowd of one shooter and one searcher reports COMBAT.
static func alert_level(tree: SceneTree) -> Alert:
	var s := scan(tree)
	if bool(s["combat"]):
		return Alert.COMBAT
	if bool(s["caution"]):
		return Alert.CAUTION
	return Alert.CALM


## True when `player` stands within the `audible_radius` of any PLAYING in-world Radio — the cue that makes
## every non-diegetic music layer yield, because a radio you can actually HEAR owns the moment.
##
## Duck-typed over the Groups.MUSIC group (a Radio joins it while switched on) so this never hard-references
## the Radio class; mirrors NPC._nearest_audible_radio (npc.gd). DISTANCE-GATED on purpose: a radio across the
## map is already near-silent from its AudioStreamPlayer3D's 3D attenuation, and must NOT mute the score for a
## fight — or a quiet walk — happening over there.
##
## The LISTENER IS PASSED IN rather than looked up here, and that is a test seam, not an accident: MusicDirector
## and WanderMusic each expose an overridable `_real_player()` so a headless test can stand up a stub radio and
## a stub listener without a live Player. A null player (or null tree) reports false — no listener, no yield.
static func radio_audible_to(tree: SceneTree, player: Node3D) -> bool:
	if tree == null or player == null:
		return false
	var here := player.global_position
	for n in tree.get_nodes_in_group(Groups.MUSIC):
		if not (n is Node3D) or not n.has_method(&"is_playing"):
			continue
		var radio := n as Node3D
		if not bool(radio.call(&"is_playing")):
			continue
		var radius_v: Variant = radio.get(&"audible_radius")  # duck-typed: a music-group node may lack it -> skip
		if not (radius_v is float or radius_v is int):
			continue
		if here.distance_to(radio.global_position) <= float(radius_v):
			return true
	return false
