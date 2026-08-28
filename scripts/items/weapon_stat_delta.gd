@tool
class_name WeaponStatDelta
extends Resource

## ONE arithmetic line a weapon part applies to ONE WeaponData scalar — the atom a WeaponMod is a list of.
## Authored as an inline sub-resource on the part's .tres (nothing to cross-reference, one file per part).
## @tool only so the `property` field self-populates its dropdown (see _validate_property) — no lifecycle.
##
## The maths lives in WeaponModKit.rebuild, never here: a delta is inert DATA. That is what lets the fold
## always restart from the pristine template and stay idempotent, order-independent and drift-free.

## Drives the `property` dropdown from WeaponData's own exports (const-preloaded, NO class_name).
const WeaponFields = preload("res://scripts/items/weapon_fields.gd")

## SET establishes the value, ADD adjusts it, MULT scales it — applied in that order across ALL fitted
## parts (WeaponModKit.rebuild), so the fitted SET is a fixed-arity map and fit order can never change
## the numbers.
enum Op { SET, ADD, MULT }

## Which WeaponData field this line moves. DROPDOWN-suggested from WeaponData's own scalar exports (see
## _validate_property), so a typo'd name is a dropdown miss instead of a silent no-op — and only fields the
## SAVE can carry are ever offered (WeaponFields is asserted a subset of ItemDb._is_weapon_delta_type).
@export var property: StringName = &""
## SET replaces the template value, ADD adds to it, MULT scales it. IGNORED for a BOOL target, which always
## uses `flag` below — there is no sensible "add" to a true/false.
@export var op: Op = Op.ADD
## The number. Coerced to the target field's declared type on apply (an INT field rounds it).
@export var amount: float = 0.0
## Used INSTEAD OF `amount` when `property` names a BOOL field (auto_fire, has_muzzle_flash, no_ads,
## auto_reload, projectile_explodes, spawns_casing, has_tracer, …) — the suppressor's "no muzzle flash".
@export var flag: bool = false

## Self-populate the `property` dropdown from WeaponData's mod-targetable scalars (a SUGGESTION hint, so a
## field being added in the same editing session is still typable). ⭐This is the ONLY authoring source for
## the field name — it is what makes "a delta the save silently reverts on load" unauthorable.
func _validate_property(prop: Dictionary) -> void:
	if prop.name == "property":
		prop.hint = PROPERTY_HINT_ENUM_SUGGESTION
		prop.hint_string = WeaponFields.ids_csv()
