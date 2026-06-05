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
## Reputation lost when the player KILLS a member of a faction (NPC._on_died drops this) — even a hostile
## one: putting their people down still sours the faction.
const KILL_REP_PENALTY: float = 12.0
## Standing is clamped to [REP_MIN, REP_MAX] so it can't run away to +/- infinity from repeated kills /
## rewards. Set comfortably past the HOSTILE/FRIENDLY thresholds so it doesn't pin disposition too early.
const REP_MIN: float = -100.0
const REP_MAX: float = 100.0

## faction_id (StringName) -> reputation (float). Missing key == 0.0.
var _reputation: Dictionary = {}

## Emitted whenever a faction's standing actually changes (delta != 0), so the HUD can toast it.
signal reputation_changed(faction: Faction, delta: float, new_total: float)
## Emitted when a faction's DISPOSITION crosses a threshold (its Disposition.Kind toward the player
## actually changes — e.g. NEUTRAL -> HOSTILE), so the HUD can announce the new alignment.
signal alignment_changed(faction: Faction, new_kind: int)

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
	var before_kind := disposition_for(faction)  # read BEFORE the rep changes
	var before := get_reputation(faction)
	var total := clampf(before + delta, REP_MIN, REP_MAX)
	_reputation[faction.id] = total
	var actual_delta := total - before  # 0 when already pinned at a bound — don't toast/announce a no-op
	if actual_delta != 0.0:
		reputation_changed.emit(faction, actual_delta, total)
		# Crossed a HOSTILE/NEUTRAL/FRIENDLY threshold? Announce the new alignment too.
		var after_kind := disposition_for(faction)
		if after_kind != before_kind:
			alignment_changed.emit(faction, after_kind)
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
