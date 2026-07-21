class_name PickupBeacon
extends Node3D

## A pickup item light: a small colour-coded OmniLight3D attached to a world pickup. The class keeps the historic
## PickupBeacon name because pickup components and saves already reference it, but it no longer builds a vertical
## shaft or any mesh "beacon" visual. The light colour is keyed by KIND (weapon / ammo / consumable / passive-buff /
## chip / money / loot-sack / misc), pulled from the GameSettings.pickup_beacons palette.
##
## NOT hand-placed as a rule -- each pickup component spawns one FOR ITSELF at runtime via the attach_* helpers:
##   - CanPickUp / dropped-or-placed items (WorldItem.build) -> attach_for_item (colour derived from the Item)
##   - MoneyPickUp -> attach_kind(MONEY)   - UpgradePickup -> attach_kind(CHIP)
##   - LootableCorpse (enemy sacks + lootable bodies) -> attach_kind(LOOT_BAG) + set_item_count (size = how full)
## You CAN drop one under a bespoke pickup by hand: set `kind` (or leave AUTO and set `item`) and it self-builds
## on _ready. Runtime-only (deliberately NOT @tool) -- it only exists while playing.
##
## STEALTH CONTRACT: the glow OmniLight3D joins Groups.PICKUP_BEACON, which PlayerLightLevel explicitly ignores:
## this cosmetic item light must NEVER light the player up for enemy perception.
##
## PLAYER TOGGLE: honours Settings.loot_beacons_enabled, polled live each frame, so flipping the Options row hides
## / shows every pickup item light immediately with no reload.

## Concrete pickup kinds -> palette colour. AUTO defers to `item` (resolved once on _ready). The int values here
## are the contract PickupBeaconSettings.color_for_kind matches on -- keep the two in lock-step.
enum Kind { AUTO, WEAPON, AMMO, CONSUMABLE, PASSIVE, CHIP, MONEY, LOOT_BAG, MISC }

## Which palette colour to use. AUTO -> derived from `item` on _ready. Set BEFORE add_child (the attach_* helpers do).
@export var kind: Kind = Kind.AUTO
## When kind == AUTO, the item whose category decides the colour (weapon / ammo / consumable / passive / chip / misc).
@export var item: Item = null

const _FIND_INTERVAL := 0.5   ## seconds between throttled player re-lookups

var _light: OmniLight3D
var _color: Color = Color(1, 1, 1)
var _count_scale: float = 1.0   ## loot-sack size multiplier (1 for a normal single pickup)
var _brightness: float = 0.0     ## distance fade 0..1; kept separate so sack scale refreshes don't reset it
var _empty: bool = false        ## a loot sack emptied to 0 stacks: parked hidden until refilled/freed
var _player: Node3D = null
var _find_cd: float = 0.0

func _ready() -> void:
	_resolve_color()
	_build()

## Resolve `kind` (deriving from `item` when AUTO) into the concrete light colour, once.
func _resolve_color() -> void:
	var k := kind
	if k == Kind.AUTO:
		k = kind_for_item(item)
	_color = _palette().color_for_kind(int(k))

func _palette() -> PickupBeaconSettings:
	return GameSettings.pickup_beacons

## Build the one visual: a small OmniLight3D excluded from stealth via the group.
func _build() -> void:
	var pal := _palette()
	_light = OmniLight3D.new()
	_light.name = "PickupLight"
	_light.light_color = _color
	_light.omni_range = pal.light_range
	_light.shadow_enabled = false
	_light.position.y = 0.35
	# Tag OUT of stealth: PlayerLightLevel skips any light in this group so item lights can't reveal the player.
	_light.add_to_group(Groups.PICKUP_BEACON)
	add_child(_light)
	_apply_scale()
	_set_brightness(0.0)

## Re-derive the light energy from the current count scale. Called on build and whenever set_item_count changes how
## full a loot sack is.
func _apply_scale() -> void:
	if _light == null:
		return
	_sync_light()

func _process(delta: float) -> void:
	if _empty or not Settings.loot_beacons_enabled:
		_set_brightness(0.0)   # player toggled item lights off, or this sack is drained
		return
	_find_cd -= delta
	if _find_cd <= 0.0 or not is_instance_valid(_player):
		_find_cd = _FIND_INTERVAL
		_player = Groups.human_player(get_tree())
	if not is_instance_valid(_player):
		_set_brightness(0.0)
		return
	_set_brightness(_fade_for(global_position.distance_to(_player.global_position)))

## Brightness 0..1 for the current player distance: 0 within near, ramping to 1 by full, plus the optional hard cull.
func _fade_for(dist: float) -> float:
	var pal := _palette()
	if pal.max_distance > 0.0 and dist > pal.max_distance:
		return 0.0
	return fade_amount(dist, pal.near_distance, pal.full_distance)

## Drive the glow to `f` (0..1). The count scale (loot-sack fullness) multiplies in on top.
func _set_brightness(f: float) -> void:
	if _light == null:
		return
	_brightness = clampf(f, 0.0, 1.0)
	_sync_light()

func _sync_light() -> void:
	if _light == null:
		return
	var pal := _palette()
	_light.omni_range = pal.light_range * _count_scale
	_light.light_energy = pal.light_energy * _count_scale * _brightness
	_light.visible = _brightness > 0.001

## Loot-sack API: resize the item light to reflect how much the sack holds (distinct stacks). 0 parks it hidden (a
## drained corpse that lingers); a positive count scales the glow via the palette's bag curve.
func set_item_count(stacks: int) -> void:
	if stacks <= 0:
		_empty = true
		_set_brightness(0.0)
		return
	_empty = false
	_count_scale = _palette().bag_scale_for(stacks)
	_apply_scale()

## Classify an Item into a light Kind (colour). Checks the most specific role first: a microchip upgrade, then a
## weapon, ammo, consumable, and finally a mere CARRY buff (the Chrome Grin idiom -- MISC category but a held
## passive). Anything else is MISC. Pure -> unit-tested (test_pickup_beacon.gd).
static func kind_for_item(it: Item) -> Kind:
	if it == null:
		return Kind.MISC
	if it.is_upgrade_chip():
		return Kind.CHIP
	if it.is_weapon():
		return Kind.WEAPON
	if it.is_ammo():
		return Kind.AMMO
	if it.is_consumable():
		return Kind.CONSUMABLE
	if it.held_passive_effect != null:
		return Kind.PASSIVE
	return Kind.MISC

## Pure distance -> brightness ramp: 0 at/inside near_d, 1 at/beyond full_d, linear between. Degenerate
## (full_d <= near_d) becomes a hard step at full_d. Pure -> unit-tested.
static func fade_amount(dist: float, near_d: float, full_d: float) -> float:
	if full_d <= near_d:
		return 1.0 if dist >= full_d else 0.0
	return clampf((dist - near_d) / (full_d - near_d), 0.0, 1.0)

## Spawn + configure an item light of an explicit KIND under `host` and return it (used by MoneyPickUp /
## UpgradePickup / LootableCorpse). add_child runs the light's _ready synchronously when host is already in the
## tree, so `kind` MUST be set first -- it is, right here. Returns null for a null host.
static func attach_kind(host: Node3D, beacon_kind: Kind) -> PickupBeacon:
	if host == null:
		return null
	var b := PickupBeacon.new()
	b.name = "PickupLight"
	b.kind = beacon_kind
	host.add_child(b)
	return b

## Spawn + configure an item light whose colour derives from `it` (used by CanPickUp / dropped-or-placed items).
## Returns null when there's no host or no item to classify.
static func attach_for_item(host: Node3D, it: Item) -> PickupBeacon:
	if host == null or it == null:
		return null
	var b := PickupBeacon.new()
	b.name = "PickupLight"
	b.kind = Kind.AUTO
	b.item = it
	host.add_child(b)
	return b
