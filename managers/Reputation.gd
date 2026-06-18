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
##
## The thresholds/penalties/clamp bounds are designer-tunable on GameSettings.reputation
## (ReputationSettings.tres) — a designer balances how quickly the world turns on you without code.

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

## Add (or subtract, with a negative delta) reputation with a faction. Returns the new total. The player's
## STREETWISE stat scales how the delta lands — gains bigger, losses smaller (both multipliers are exactly
## 1.0 on a baseline sheet, and with no live player the delta is untouched, so tests/menus are unaffected).
func add_reputation(faction: Faction, delta: float) -> float:
	if faction == null:
		return 0.0
	var sp := _stats_player()
	if sp != null and delta != 0.0:
		delta *= sp.stats_or_default().rep_gain_mult() if delta > 0.0 else sp.stats_or_default().rep_loss_mult()
	var before_kind := disposition_for(faction)  # read BEFORE the rep changes
	var before := get_reputation(faction)
	var rep_min: float = GameSettings.reputation.rep_min
	var rep_max: float = GameSettings.reputation.rep_max
	var total := clampf(before + delta, rep_min, rep_max)
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
	var hostile_threshold: float = GameSettings.reputation.hostile_threshold
	var friendly_threshold: float = GameSettings.reputation.friendly_threshold
	if rep <= hostile_threshold:
		return Disposition.Kind.HOSTILE
	if rep >= friendly_threshold:
		return Disposition.Kind.FRIENDLY
	# Inside the neutral band: defer to how the faction feels by default.
	return faction.default_disposition

## Wipe all standing (new game / load). Kept explicit so a save system can repopulate via
## add_reputation without leaking the previous run's pools.
func reset() -> void:
	_reputation.clear()

## A copy of every faction's current standing (faction_id -> float), for the save profile (GameState.capture).
func all_standings() -> Dictionary:
	return _reputation.duplicate()

## Replace all standing from a saved profile (Player applies this on a loaded game). The values are the final,
## already-scaled-and-clamped totals from when they were earned, so they're set DIRECTLY — not re-run through
## add_reputation (which would re-scale by streetwise). Keys may be String or StringName; stored as StringName
## (the faction.id type get_reputation keys on).
func restore(data: Dictionary) -> void:
	_reputation.clear()
	for k in data:
		_reputation[StringName(str(k))] = float(data[k])

## The human player whose STREETWISE scales reputation deltas: the &"Player" group member that isn't an NPC
## (companions join the group for targeting), duck-typed on stats_or_default. Null when none is alive
## (start menu / unit tests), in which case deltas land unscaled.
func _stats_player() -> Node:
	# is_inside_tree(), not get_tree()==null: calling get_tree() on an off-tree node (a bare unit-test
	# instance) logs an engine ERROR before returning null, and GUT fails the test on that error.
	if not is_inside_tree():
		return null  # off-tree -> no player, delta unscaled
	for p in get_tree().get_nodes_in_group(&"Player"):
		if not (p is NPC) and p.has_method(&"stats_or_default"):
			return p
	return null
