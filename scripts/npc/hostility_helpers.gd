class_name HostilityHelpers
extends RefCounted

## Pure, stateless resolution for the FNV-style NPC hostility model — the math behind NPC's
## resolved_disposition() / is_hostile_to() / _is_unaligned_hostile() facades. Kept off NPC (a
## tiny static lib, like Disposition / TalkHelpers) so the rules live in ONE place and the NPC
## stays a thin coordinator: it owns the STATE (the _provoked flag + the faction / disposition
## exports) and just hands those values down here to be resolved.
##
## NEVER instantiated — a namespace for the statics. Each takes the raw state as arguments rather
## than reading the NPC, so they're trivially unit-testable and free of any node/tree dependency.
## The faction-rep lookup still flows through the Reputation autoload (a global), exactly as before.

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

## True for an UNALIGNED-HOSTILE profile — no faction, standalone disposition HOSTILE (today's plain
## enemy). A FOLLOWING companion treats such a foe as fair game when defending its leader even though
## it has no faction quarrel with it, without ever turning on a neutral/allied bystander.
static func is_unaligned_hostile(faction: Faction, disposition: Disposition.Kind) -> bool:
	return faction == null and disposition == Disposition.Kind.HOSTILE
