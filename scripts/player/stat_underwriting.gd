@tool
class_name StatUnderwriting
extends Resource

## ONE row of the Ledger's actuarial table — how New Game's credit check prices a single CharacterStat.
## `EconomySettings.credit_underwriting` holds one of these per stat, and `EconomySettings.credit_rating_for`
## reads nothing else about a build: re-pricing the whole bank means dragging four numbers per stat in the
## inspector, with no code change. A stat with no row here is invisible to the bank (it contributes nothing and
## moves no normalizer) — deliberately fail-QUIET at runtime, and fail-LOUD in the drift test that pins every
## CharacterStats.STAT_NAMES entry to a row.
##
## THE TWO HALVES. Positive points are ASSETS the bank lends against (income_weight + survival_weight);
## negative points are COLLATERAL the applicant has already pledged (dump_severity). That split is what makes
## the model monotone — investing can only ever raise a score and dumping can only ever lower it, for ANY
## weights authored here — so no table a designer types in can re-create the inverted model this replaced
## (where committing to a build was taxed and allocating nothing rated best).
##
## Weights are read through `maxf(0.0, ...)`, so a mis-authored NEGATIVE can never pay score into a build.

## Which CharacterStat this row prices. A PROPERTY_HINT_ENUM_SUGGESTION dropdown off the STAT_NAMES master
## (the BuildGate.required_stat idiom) — pick from the list; a typo'd name simply never matches a build.
@export var stat: StringName = &""

@export_group("Assets (per point ABOVE zero)")
## Predicted EARNING POWER per point — "can this body generate zorkmids?". Drives the CAPACITY line. Highest
## on the stats that actually convert into money (gunplay's headshot bounties, streetwise's trade margins).
@export var income_weight: float = 0.0
## Predicted SURVIVAL per point — "will it live long enough to repay?". Drives the VIABILITY line. Highest on
## the stats that keep the character breathing (strength's max HP, agility's traversal).
@export var survival_weight: float = 0.0

@export_group("Collateral (per point BELOW zero)")
## Score cost per point pledged, before the superlinear curve (`EconomySettings.credit_dump_exponent`) is
## applied. Raise it for a stat the bank considers reckless to sell off.
@export var dump_severity: float = 0.0
## How many points below zero still COST anything. Past this depth the pledge is worthless to the bank —
## author it at the point where the stat's derived effect has already bottomed out (e.g. strength saturates
## at 2 because `max_hp` is floored from strength -2 down, so -3/-4/-5 take nothing further away).
@export_range(0, 20) var dump_saturation: int = 5


## Editor dropdown for `stat`, off the CharacterStats.STAT_NAMES master (BuildGate / NpcData idiom).
## SUGGESTION, not ENUM: the box stays editable, and an unmatched name is inert rather than fatal.
func _validate_property(property: Dictionary) -> void:
	if property.name == &"stat":
		property.hint = PROPERTY_HINT_ENUM_SUGGESTION
		property.hint_string = CharacterStats.stat_names_csv()
