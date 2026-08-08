class_name BodyPartGibs
extends Node

## Drop-in: PER-ACTOR control over the body-part death burst -- the thing that makes a character come apart
## into its OWN head / torso / arms / legs (LEGO- or Roblox-style) instead of only spraying generic meat
## chunks. Drop it under a Character (the Enemy root, the Player) and tune it in the Inspector.
##
## YOU DO NOT NEED THIS NODE FOR THE FEATURE TO WORK. Body-part gibs are ON by default for every character
## that has a BodyModelSwap, governed globally by GameSettings.effects.body_part_gibs_enabled (the
## "Body-part gibs" group on resources/tuning/EffectsSettings.tres). This component exists to OVERRIDE that
## for one actor -- and when it is present it WINS over the global switch, in both directions:
##   * a boss you want to leave in one piece  -> drop one in, untick `enabled`
##   * body parts off globally, on for one actor -> drop one in, leave `enabled` ticked
##
## HOW IT IS FOUND: GoreSpawner (scripts/player/gore_spawner.gd) scans the dying actor's DIRECT children for
## a BodyPartGibs on death. So it must be a direct child of the Character root, not nested deeper.
##
## WHAT IT NEEDS TO WORK: the actor must have a BodyModelSwap child with real part models -- that component
## IS the source of the flying parts (the burst duplicates its live head/torso/arm/leg nodes, skin and all).
## An actor with no BodyModelSwap, or one whose parts are all unmodelled, silently falls back to the plain
## meat-chunk burst.
##
## WHERE THE FEEL NUMBERS LIVE: launch speed, spin, lifetime, HP and mass are GLOBAL, on
## GameSettings.effects (`body_part_gib_*`), so retuning the burst once retunes it everywhere. Only the
## per-actor decisions are here.

## Path of the shipped gib chassis (the physics body a flying part is mounted on). Resolved lazily by
## default_scene() with a runtime load(), never a preload: that scene's root runs Throwable.gd, which
## type-refs Character, and preloading it from anything on Character's own parse path closes a cyclic
## reference (the same reason Character.gib_scene load()s gore_gib.tscn -- see character.gd).
const DEFAULT_SCENE_PATH := "res://scenes/effects/body_part_gib.tscn"

## Process-wide cache for DEFAULT_SCENE_PATH, so a firefight doesn't re-resolve the scene on every death.
static var _default_scene: PackedScene = null

## Master switch for THIS actor, and the whole reason to drop this node in. Ticked: this character bursts
## into its own body parts even if the global switch is off. Unticked: it never does, even if the global
## switch is on -- it dies with the plain meat-chunk burst (`gib_count` chunks) instead.
@export var enabled: bool = true

## Override chassis for THIS actor's flying parts. Null (the norm) uses the shipped
## scenes/effects/body_part_gib.tscn. Point it at your own scene to give one character heavier, bouncier or
## differently-sounding limbs -- it must be a Throwable whose `mesh_instance` is an EMPTY MeshInstance3D
## mount point (see scripts/effects/body_part_gib.gd for the full chassis contract).
@export var part_gib_scene: PackedScene

@export_group("Which parts fly")
## Fling the head. Untick to keep it attached in spirit -- an unticked part simply isn't spawned, and no meat
## chunk is substituted for it.
@export var burst_head: bool = true
## Fling the torso -- the big one, the piece that reads as "the body". Untick and the death is mostly limbs.
@export var burst_torso: bool = true
## Fling BOTH arms (they are one pair; there is no left/right split, matching how BodyModelSwap models them).
@export var burst_arms: bool = true
## Fling BOTH legs.
@export var burst_legs: bool = true

@export_group("Mix")
## How many ordinary MEAT chunks still burst alongside the body parts for THIS actor. -1 (the default) uses
## the global GameSettings.effects.body_part_gib_meat_count. 0 = parts only, a clean toy-like break-up with
## no loose gore; raise it for a messier kill. The plain `gib_count` is what a character bursts into when
## body parts are OFF, and is not used here.
@export var meat_gib_count: int = -1

## Multiplier on how hard THIS actor's parts are flung (on top of the global
## body_part_gib_vel_min/max). 1.0 = normal. Raise it for something that should come apart explosively;
## lower it for a heavy body that should just slump into pieces.
@export var launch_speed_scale: float = 1.0


## The shipped chassis, loaded once per run. Public because GoreSpawner needs it for an actor that has NO
## BodyPartGibs component at all (the default-on path).
static func default_scene() -> PackedScene:
	if _default_scene == null:
		_default_scene = load(DEFAULT_SCENE_PATH) as PackedScene
	return _default_scene


## PURE part filter (static so GUT can pin every combination off-tree, the Pettable.eligible idiom).
## `key` is a BodyModelSwap character_parts() key: torso / head / arm_l / arm_r / leg_l / leg_r. An
## unrecognised key returns false -- a part this component has no toggle for is not silently flung.
static func wants_part(key: String, head: bool, torso: bool, arms: bool, legs: bool) -> bool:
	match key:
		"head":
			return head
		"torso":
			return torso
		"arm_l", "arm_r":
			return arms
		"leg_l", "leg_r":
			return legs
	return false


## Whether this actor flings the part with the given character_parts() key.
func includes(key: String) -> bool:
	return wants_part(key, burst_head, burst_torso, burst_arms, burst_legs)


## The chassis THIS actor's parts ride on: the per-actor override when set, else the shipped default.
func resolved_scene() -> PackedScene:
	return part_gib_scene if part_gib_scene != null else default_scene()


## THE MARKER METHOD GoreSpawner finds this component by, and the whole per-actor config in one read.
## Deliberately a plain Dictionary rather than handing back `self`: gore_spawner.gd sits on Character's parse
## path, and a `BodyPartGibs` TYPE reference there would make every actor script fail to compile until the
## editor happens to register this new class_name in its global cache (the class-cache cascade). Duck-typing
## on this method name — exactly how npc.gd finds a BodyModelSwap via character_parts() — has no such
## dependency, and lets a unit-test stub stand in for the whole component.
func body_part_gib_config() -> Dictionary:
	return {
		"enabled": enabled,
		"scene": resolved_scene(),
		"meat_gib_count": meat_gib_count,
		"speed_scale": launch_speed_scale,
		"head": burst_head,
		"torso": burst_torso,
		"arms": burst_arms,
		"legs": burst_legs,
	}


## The meat-chunk count for this actor: the per-actor override when it is >= 0, else `fallback` (the global
## body_part_gib_meat_count). Static + literal-arg so the -1-means-inherit rule is unit-testable.
static func resolve_meat_count(override_count: int, fallback: int) -> int:
	return override_count if override_count >= 0 else fallback
