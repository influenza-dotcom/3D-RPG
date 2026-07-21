class_name PickupBeaconSettings
extends Resource

## Global tuning for pickup item lights: the small coloured glow attached to a world pickup or dropped loot-sack.
## Read via GameSettings.pickup_beacons; edit the numbers in resources/tuning/PickupBeaconSettings.tres, never in
## code.
##
## Colours are keyed by PICKUP KIND, so a designer re-themes every light of a type from one place. The per-kind
## branch order in color_for_kind MUST stay in lock-step with PickupBeacon.Kind (WEAPON=1 ... MISC=8); AUTO(0) is
## resolved to a concrete kind by the component BEFORE the palette is asked, so it never reaches here.

@export_group("Palette (per pickup kind)")
## Guns / melee -- a WEAPON-category item.
@export var weapon_color: Color = Color(0.95, 0.35, 0.2)
## Reserve ammo -- an AMMO-category item.
@export var ammo_color: Color = Color(0.95, 0.72, 0.15)
## Heal / stim -- a CONSUMABLE-category item.
@export var consumable_color: Color = Color(0.3, 0.9, 0.4)
## Held-passive buff items (the Chrome Grin idiom: item.held_passive_effect set).
@export var passive_color: Color = Color(0.72, 0.42, 1.0)
## Microchip upgrades (item.installs_ability set) -- tuned to echo UpgradePickup's acquire toast.
@export var chip_color: Color = Color(0.35, 0.8, 1.0)
## Zorkmid stashes -- a MoneyPickUp.
@export var money_color: Color = Color(1.0, 0.84, 0.2)
## Enemy-dropped loot sacks / lootable corpses -- a LootableCorpse container.
@export var loot_bag_color: Color = Color(0.4, 0.92, 0.8)
## Everything else (plain MISC junk, or a pickup we can't classify).
@export var misc_color: Color = Color(0.82, 0.85, 0.9)

@export_group("Item light look")
## Energy of the OmniLight3D glow on the item. Excluded from stealth (see PickupBeacon), so this is a purely
## cosmetic local light -- it never makes the player easier to detect.
@export var light_energy: float = 2.2
## That glow's omni_range (m) -- kept small so it reads as a light on the item, not a world floodlight.
@export var light_range: float = 3.0

@export_group("Distance fade")
## At/beyond this distance (m) the item light reaches FULL brightness.
@export var full_distance: float = 9.0
## At/within this distance (m) the item light is fully OFF. Between near_distance and full_distance it lerps.
@export var near_distance: float = 3.0
## Optional hard cull range (m): past this the light hides entirely. 0 = never cull.
@export var max_distance: float = 0.0

@export_group("Loot-sack scaling")
## A loot sack / corpse scales its glow energy by HOW MUCH it holds. Scale is min at 1 stack, max at
## count_for_max stacks. ONLY loot-bag lights scale; every other pickup stays at scale 1.
@export var bag_min_scale: float = 0.7
@export var bag_max_scale: float = 1.7
## Distinct stacks at which a sack's light reaches bag_max_scale.
@export var bag_count_for_max: int = 8

## Palette lookup by PickupBeacon.Kind int (WEAPON=1 ... LOOT_BAG=7). AUTO(0) / MISC(8) / anything unknown -> misc.
## Kept as an int match (not a typed Kind param) so this resource has NO dependency on the component script -- the
## component owns the enum and passes int(kind) here.
func color_for_kind(kind: int) -> Color:
	match kind:
		1: return weapon_color
		2: return ammo_color
		3: return consumable_color
		4: return passive_color
		5: return chip_color
		6: return money_color
		7: return loot_bag_color
		_: return misc_color

## The count-scaled multiplier for a loot sack holding `stacks` distinct stacks: bag_min_scale at 1 (or fewer),
## ramping to bag_max_scale at bag_count_for_max. Pure -> unit-tested (test_pickup_beacon.gd).
func bag_scale_for(stacks: int) -> float:
	if bag_count_for_max <= 1:
		return bag_max_scale
	var t := clampf(float(stacks - 1) / float(bag_count_for_max - 1), 0.0, 1.0)
	return lerpf(bag_min_scale, bag_max_scale, t)
