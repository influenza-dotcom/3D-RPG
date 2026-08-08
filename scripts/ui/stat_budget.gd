extends RefCounted

## The ZERO-SUM stat allocator behind character creation, extracted as a pure RefCounted so its rules can be
## unit-tested off-tree WITHOUT booting the character-creation overlay (which instantiates a live 3D
## CharacterPreview — expensive and irrelevant to the arithmetic). character_creation.gd owns one of these and
## mirrors its state into the widgets; the stepper enable/disable states read straight off can_raise/can_lower so
## the UI can never drift from the rules.
##
## The rules: every stat starts at 0; the ONLY way to raise one is to pull a point OUT of another (net stays
## <= 0 — you MAY underspend into a deliberately weak, net-negative build, but never net-positive); each stat is
## clamped to [stat_min, stat_max]. Negatives are real choices (CharacterStats inverts every derived effect below
## baseline), which is why lowering has a real floor rather than stopping at 0.
##
## No class_name on purpose: consumers preload it by path (const StatBudget := preload(...)), keeping it off the
## global class cache so a headless GUT run never trips the "new class_name not yet registered" cascade.

## The allocator's per-stat bounds — the SINGLE source. character_creation.gd's steppers clamp to these, and
## the Ledger's underwriting scorer normalizes against them (implant_choice.gd forwards them into
## EconomySettings.credit_rating_for), so the builder's rules and the scorer's normalizers CANNOT drift. They
## live HERE, not on a tuning resource, so the dependency arrow points one way: the bank reads the allocator,
## never the reverse. `_init` still takes explicit bounds, so a caller may override them.
const STAT_MIN := -5
const STAT_MAX := 10

var values: Dictionary = {}   ## StringName stat -> int (public: the screen reads it to stamp the value labels)
var stat_min: int
var stat_max: int
var _stats: Array[StringName]

## Seed every stat in `stats` to 0 and remember the per-stat clamp bounds. `stats` is the display-ordered stat
## list (character_creation passes CharacterStats.STAT_NAMES, the single source of truth).
func _init(stats: Array[StringName], min_value: int, max_value: int) -> void:
	_stats = stats
	stat_min = min_value
	stat_max = max_value
	for stat in _stats:
		values[stat] = 0

## Sum of every allocation. <= 0 always (zero-sum with allowed underspend), because try_raise refuses to push it above 0.
func net() -> int:
	var n := 0
	for stat in _stats:
		n += int(values[stat])
	return n

## Points freed (by lowering) but not yet spent (by raising). Equals -net, and is >= 0 by construction.
func spare() -> int:
	return -net()

## Can this stat be raised right now? A spare point must exist AND the stat must be below the ceiling.
func can_raise(stat: StringName) -> bool:
	return spare() > 0 and int(values[stat]) < stat_max

## Can this stat be lowered? Only while it's above the floor (a minus is a real penalty, not a stop-at-0).
func can_lower(stat: StringName) -> bool:
	return int(values[stat]) > stat_min

## Raise a stat by 1 if allowed. Returns true iff it actually changed (so the screen only refreshes on a real move).
func try_raise(stat: StringName) -> bool:
	if not can_raise(stat):
		return false
	values[stat] = int(values[stat]) + 1
	return true

## Lower a stat by 1 if allowed. Returns true iff it actually changed.
func try_lower(stat: StringName) -> bool:
	if not can_lower(stat):
		return false
	values[stat] = int(values[stat]) - 1
	return true

## A fresh {stat -> int} copy for the confirmed() payload StartMenu stamps onto GameState.stat_values.
func to_dict() -> Dictionary:
	var out: Dictionary = {}
	for stat in _stats:
		out[stat] = int(values[stat])
	return out
