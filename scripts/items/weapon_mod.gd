@tool
class_name WeaponMod
extends Resource

## A WEAPON PART's payload — what a gunsmith bench fits into one of a weapon's six FO4 slots. Authored as an
## inline sub-resource on an ordinary Item .tres in resources/items/ (exactly as a weapon Item carries a
## WeaponData), so ItemDb's boot folder scan registers a new part for free: no new folder, no new registry,
## and the part loots / stacks / sells / tooltips like any other item.
##
## ⭐It carries NO display copy. `display_name`, `description`, `icon` and `value` all live on the HOST Item —
## one name for the thing whether it is on a shelf, in your pack, or fitted. The bench prices labour off
## `Item.value`, which is also why a refit never changes what a gun resells for (Merchant keys on Item.value).
##
## ⭐WeaponMod -> WeaponData is ONE-WAY: the part names the slot (WeaponData.ModSlot), the weapon never names
## the part. That is what keeps a class_name cycle out of WeaponData, whose .tres files every level loads.
## @tool only so `fits_weapon_ids` / `caliber_override` self-populate their dropdowns — no editor lifecycle.

## Item-id dropdown source for `fits_weapon_ids` (const-preloaded, NO class_name — the Calibers idiom).
const ItemIds = preload("res://scripts/items/item_ids.gd")
## Caliber dropdown source for `caliber_override` — the SAME registry WeaponData.caliber and Item.caliber use,
## so a conversion can only ever name a caliber that real ammo exists for.
const Calibers = preload("res://scripts/items/calibers.gd")

@export_group("Fitting")
## Which of the six slots this part occupies. ONE part per slot per weapon: the bench refuses fitting into an
## occupied slot (pull the old one first), which is what keeps the refund story unambiguous — you always get
## back exactly the part you paid to remove.
@export var slot: WeaponData.ModSlot = WeaponData.ModSlot.RECEIVER
## The weapon Item.ids this part fits (&"pistol", &"smg", &"shotgun", &"sniper"). ⭐EMPTY = UNIVERSAL.
## Fitment lives on the PART, so a new shotgun scope is one new .tres and ZERO edits to anything that exists —
## no weapon .tres, no bench, no table. Element dropdown via _validate_property.
@export var fits_weapon_ids: Array[StringName] = []
## Optional GUNPLAY gate — below this the bench refuses (the row dims and the Notice band says why). 0 = no
## gate. The Gun-Nut rung: levelling unlocks hardware, so a stat investment has hardware to spend itself on.
@export var min_gunplay: int = 0

@export_group("Display")
## Sort/label ordinal within the slot (Standard 0 / Long 1 / Sniper 2). ⭐PURELY PRESENTATIONAL — the fold
## never reads it, so slots stay MUTUALLY EXCLUSIVE alternatives (a sidegrade is a same-tier part with
## different trade-offs), never a cumulative ladder you climb by buying every rung.
@export var tier: int = 1

@export_group("Effect")
## The numeric/flag changes this part makes to the weapon's stat block. Applied SET -> ADD -> MULT across
## every fitted part at once (WeaponModKit.rebuild), starting from the PRISTINE template, so fit order can
## never change the numbers and removing a part returns the authored values exactly.
@export var deltas: Array[WeaponStatDelta] = []

@export_group("Part swaps")
## ⭐These seven override slots are the WHOLE REASON the save stores part IDS rather than folded values.
## They are exactly the field types ItemDb._is_weapon_delta_type rejects by design (Resources and asset refs
## need a deep copy + merge, not a flat set()), so a system that wrote them onto the weapon instance would
## have them SILENTLY REVERT on quickload with no warning anywhere. Here the save stores &"mod_suppressor"
## and the AudioStream comes back off the part's .tres — which also means a designer's retune reaches guns
## already sitting in old save files.
## Replaces WeaponData.view_model — the gun you SEE changes. Only ever reaches the eye through a real weapon
## swap (GunMesh._on_swap_finished rebuilds the view model and re-aligns the Muzzle marker), which the bench's
## _refit guarantees by handing the equip seam a NEW WeaponData object.
@export var view_model_override: PackedScene
## Replaces WeaponData.projectile_scene — explosive rounds.
@export var projectile_scene_override: PackedScene
## Replaces WeaponData.on_hit_effect — an incendiary receiver.
@export var on_hit_effect_override: StatusEffect
## Replaces WeaponData.audio, the per-shot fire sound — the suppressor's voice.
@export var fire_sound_override: AudioStream
## Replaces WeaponData.whiz_sound, the supersonic crack heard at the muzzle.
@export var whiz_sound_override: AudioStream
## Replaces WeaponData.reload_sound.
@export var reload_sound_override: AudioStream
## Replaces WeaponData.caliber — a calibre conversion. &"" = no conversion.
## ⭐Ammo._uses_reserve / has_reload_supply gate the reload on BACKPACK CLIPS OF THIS CALIBRE, so a conversion
## strands the player mid-fight if they hold no matching ammo. Author one only alongside a reason to expect
## that ammo, and price the part accordingly.
@export var caliber_override: StringName = &""

@export_group("Economy")
## Per-part labour trim ON TOP OF the bench's fit_mult / remove_mult — a scope is fiddlier than a stock.
## 1.0 = standard. The bench owns the rates (per-station tuning), the part owns the relative difficulty.
@export var fit_labour_mult: float = 1.0

## Self-populate the two drift-prone id fields: `fits_weapon_ids` gets a per-ELEMENT item-id dropdown (the
## typed-array hint idiom — "<element type>/<element hint>:<hint string>"), `caliber_override` a caliber one.
## Both are SUGGESTION hints, so a part authored before its weapon (or its ammo) still takes the id.
## The parameter is `prop`, not `property`: this resource has no `property` member but WeaponStatDelta does,
## and keeping one spelling across the pair stops a future copy-paste shadowing a real export.
func _validate_property(prop: Dictionary) -> void:
	if prop.name == "fits_weapon_ids":
		prop.hint = PROPERTY_HINT_TYPE_STRING
		prop.hint_string = "%d/%d:%s" % [TYPE_STRING_NAME, PROPERTY_HINT_ENUM_SUGGESTION, ItemIds.ids_csv()]
	if prop.name == "caliber_override":
		prop.hint = PROPERTY_HINT_ENUM_SUGGESTION
		prop.hint_string = Calibers.ids_csv()
