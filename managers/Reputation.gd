extends Node

## Tracks the PLAYER's standing with each faction and maps that standing onto a Disposition the
## NPC AI can act on. The single source of truth for "how does faction X feel about the player
## right now". UNALIGNED NPCs do not consult this — they use their own standalone disposition.
##
## Reputation is keyed by Faction.id (StringName), not the resource instance, so the same logical
## faction loaded from disk in two places shares one pool. Standing starts at 0 for any faction
## not yet seen. The threshold mapping below turns a signed score into HOSTILE / NEUTRAL / FRIENDLY,
## then clamps to the faction's baseline so a faction that is HOSTILE-by-default can't become
## FRIENDLY without enough positive rep, and a FRIENDLY-by-default faction sours if you wrong it.

## Reputation at or below this => the faction treats the player as HOSTILE (e.g. you shot them up).
const HOSTILE_THRESHOLD: float = -25.0
## Reputation at or above this => the faction treats the player as FRIENDLY.
const FRIENDLY_THRESHOLD: float = 25.0
## Reputation lost when the player provokes a member of a faction (NPC.provoke drops this).
const PROVOKE_REP_PENALTY: float = 30.0

## faction_id (StringName) -> reputation (float). Missing key == 0.0.
var _reputation: Dictionary = {}

## Current standing with a faction (0.0 if never modified). Accepts the Faction resource and reads
## its id; null faction => 0.0 (an unaligned NPC should never call this).
func get_reputation(faction: Faction) -> float:
	if faction == null:
		return 0.0
	return float(_reputation.get(faction.id, 0.0))

## Add (or subtract, with a negative delta) reputation with a faction. Returns the new total.
func add_reputation(faction: Faction, delta: float) -> float:
	if faction == null:
		return 0.0
	var total := get_reputation(faction) + delta
	_reputation[faction.id] = total
	return total

## Resolve how a faction currently feels about the player: start from the faction's baseline
## disposition, then let reputation push it. Low rep forces HOSTILE; high rep can raise a
## neutral/hostile faction toward FRIENDLY. The baseline acts as the midpoint the thresholds
## move away from, so a HOSTILE-default faction stays hostile until rep clears FRIENDLY_THRESHOLD.
func disposition_for(faction: Faction) -> Disposition.Kind:
	if faction == null:
		return Disposition.Kind.NEUTRAL  # caller shouldn't ask, but fail safe to neutral
	var rep := get_reputation(faction)
	if rep <= HOSTILE_THRESHOLD:
		return Disposition.Kind.HOSTILE
	if rep >= FRIENDLY_THRESHOLD:
		return Disposition.Kind.FRIENDLY
	# Inside the neutral band: defer to how the faction feels by default.
	return faction.default_disposition

## Wipe all standing (new game / load). Kept explicit so a save system can repopulate via
## add_reputation without leaking the previous run's pools.
func reset() -> void:
	_reputation.clear()
