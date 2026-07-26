class_name HostilityHelpers
extends RefCounted

## Pure, stateless resolution for the FNV-style NPC hostility model — the math behind NPC's
## resolved_disposition() / is_hostile_to() facades. Kept off NPC (a
## tiny static lib, like Disposition / TalkHelpers) so the rules live in ONE place and the NPC
## stays a thin coordinator: it owns the STATE (the _provoked flag + the faction / disposition
## exports) and just hands those values down here to be resolved.
##
## NEVER instantiated — a namespace for the statics. Each takes the raw state as arguments rather
## than reading the NPC, so they're trivially unit-testable and free of any node/tree dependency.
## The faction-rep lookup still flows through the Reputation autoload (a global), exactly as before.
##
## settle_provoked_grudges is the one exception to "raw state in": it takes a LIST of actors and duck-types
## them. It still never touches the tree (the caller injects the group), so it unit-tests with stubs like the
## rest — and it lives here, not on NPC, because the PLAYER is its caller and `Player -> NPC -> Groups -> Player`
## would close a class_name reference cycle.

## Resolve an NPC's CURRENT attitude toward the player from its raw state, in priority order:
##   1. provoked   -> HOSTILE (a hit always aggros, overriding everything)
##   2. individual -> the NPC's own `disposition` (an INDIVIDUAL attitude that overrides its faction)
##   3. factioned  -> Reputation's disposition for that faction (faction baseline + player rep)
##   4. unaligned  -> the standalone `disposition`
## `individual` lets a factioned NPC keep its faction (for reputation / NPC-vs-NPC / grouping) while
## reading its OWN disposition toward the player instead of the faction's.
static func resolved_kind(provoked: bool, faction: Faction, disposition: Disposition.Kind, individual: bool = false) -> Disposition.Kind:
	if provoked:
		return Disposition.Kind.HOSTILE
	if faction != null and not individual:
		return Reputation.disposition_for(faction)
	return disposition

## NPC-vs-NPC aggro: BOTH actors must be factioned AND `a_fac`'s relation to `b_fac` must be < 0
## (FNV-style "<0 = enemies"). An unaligned NPC on either side never faction-fights. Mirrors the
## NPC-branch of the old is_hostile_to(): a provoked NPC still only sours toward the PLAYER (provoke
## drops player-rep), never toward a peer, because provoke doesn't touch either faction here.
static func npc_vs_npc_hostile(a_fac: Faction, b_fac: Faction) -> bool:
	if a_fac == null or b_fac == null:
		return false
	return a_fac.relation_to(b_fac.id) < 0.0

## NPC-vs-NPC alliance — the mirror of npc_vs_npc_hostile: co-aligned if they share a faction (same .tres
## or same id) OR `a_fac`'s relation to `b_fac` is > 0 (FNV-style ">0 = allies"). An unaligned NPC (null
## faction) has no allies. Used by the death-witness reaction so a co-aligned peer cries "Murderer!" when
## the player kills its friend.
static func npc_vs_npc_allied(a_fac: Faction, b_fac: Faction) -> bool:
	if a_fac == null or b_fac == null:
		return false
	if a_fac == b_fac:
		return true
	if a_fac.id != &"" and a_fac.id == b_fac.id:
		return true
	return a_fac.relation_to(b_fac.id) > 0.0

## THE DEATH-SETTLEMENT RULE, in one predicate: does being killed by `killer` square the player's provoked
## grudges? Evaluated AT DEATH (while the killer is still a live node); the stand-down itself happens on the
## RESPAWN — see settle_provoked_grudges and Player._on_killed_by.
##
## The player must have been killed BY a live NPC that was hostile to them. A fall, a hazard, a self-inflicted
## blast, or a stray round from a FRIENDLY companion settles nothing: nobody won that fight. Gated on
## GameSettings.npc_ai.deaggro_on_player_death so a designer can switch the whole rule off.
##
## Duck-typed (has_method) rather than `is NPC` so it unit-tests with stubs and never drags the NPC scene in.
static func death_settles_grudges(killer: Object) -> bool:
	if not GameSettings.npc_ai.deaggro_on_player_death:
		return false
	if not is_instance_valid(killer) or not killer.has_method(&"stand_down_on_player_death") \
			or not killer.has_method(&"is_hostile"):
		return false
	var killer_hostile: Variant = killer.call(&"is_hostile")
	return killer_hostile is bool and killer_hostile

## THE PLAYER IS BACK: settle every PROVOKED grudge in `npcs` (each stands down via
## NPC.stand_down_on_player_death) because the fight they started ended with them dead. The de-escalation mirror
## of AlarmPanel.aggro_faction_members. Returns how many actually stood down. The CALLER owns the eligibility
## check — Player runs death_settles_grudges() at death and this sweep on the respawn, so the world only visibly
## calms down once the player is looking at it again (and the reputation toast lands on a restored HUD instead of
## being swallowed by the death cinematic).
##
## It sweeps EVERY provoked NPC, not just the killer, because the provoke reputation hit is faction-wide and
## shared — pardoning one member while its neighbours keep their deltas would leave the faction still soured below
## hostile_threshold, so resolved_kind() would read HOSTILE anyway and the "pardon" would be a no-op. (The holster
## de-escalation sweeps the whole group for the same reason — see DialogueController.on_weapon_holstered.)
##
## Only PROVOKES are settled. A faction soured by KILLS keeps that penalty (kill_penalty is never reversed), and a
## predisposed-hostile faction was never provoked, so raiders go on hunting the player either way.
##
## Static + list-injected + duck-typed so it unit-tests with stubs (the &"npc" group holds only real NPCs in
## play); nulls, freed instances and non-NPC nodes are skipped.
static func settle_provoked_grudges(npcs: Array) -> int:
	var count := 0
	for node in npcs:
		if not is_instance_valid(node) or not node.has_method(&"stand_down_on_player_death"):
			continue
		if node.stand_down_on_player_death():
			count += 1
	return count
