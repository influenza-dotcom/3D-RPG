class_name Ability
extends Node

## @system Player Abilities
## @seam An enabled Ability child grants the mechanic keyed by ability_id(); has_mechanic, unlocked_list (save) and the runtime rebuild all match that id. The grant/revoke/persistence bookkeeping lives in AbilityManager (a Player-owned RefCounted); the Player keeps only the typed hot-path refs + physics beats.
## @risk A subclass that forgets to override ability_id() defaults to &"" (the ability_id() base return): present but grants no queryable mechanic — silent, no crash.
## @risk An id whose ability script is absent from disk (breaks the AbilityRegistry snake_case naming convention) can't be rebuilt on save-load or paid install (AbilityManager._build -> null, silently grants nothing); AbilityRegistry.can_build + the drift test guard it.
## @test res://tests/test_upgrades.gd
## Base for drag-drop player ABILITY components. Drop one (or several) under a Player and its PRESENCE grants
## that mechanic — no string-flag bookkeeping, and because each ability is its OWN node you can stack as many as
## you want (the one-script-per-node wall is gone). Each subclass owns its behaviour + tuning + state; the Player
## discovers its Ability children, injects itself, and calls the subclass's hooks at the load-bearing beats of
## its movement step (the call ORDER is preserved, so feel is unchanged). An UpgradePickup grants one by ADDING
## the node; the autosave lists the present ids and re-adds them on load.
##
## `host` is the owning Player — typed Node (not Player) to avoid a Player <-> Ability class cycle, so every
## host.* access is dynamic (the same idiom AimSway / HurtFeedback use).

## Turn the ability OFF without removing the node — the ACTIVE flag. The Player's gate (has_mechanic)
## ignores a disabled ability and unlocked_list() omits it, so all gameplay reads it as off; the node's
## PRESENCE still counts as INSTALLED (installed_list / mechanic_installed), and a player-toggled OFF
## implant persists through saves via GameState.disabled_unlocks (the Implants tab owns the toggle).
@export var enabled: bool = true

## The mechanic's PLAYER-FACING name ("Wall Climb"), authored on each ability scene's root in the Inspector.
## UI reads it BY ID through AbilityRegistry.display_name_for — the one canonical accessor, which degrades a
## blank/missing value to the capitalized id (the pre-authoring look), never to a blank. DISPLAY-only:
## behaviour, saves, and grants key on ability_id(), never on this string.
@export var display_name: String = ""

var host: Node = null  ## the owning Player, injected by Player._register_ability

## The mechanic id this ability grants (&"wall_climb", &"slide", …). Subclasses MUST override — the Player's gate
## and the save system match on it. The default empty id grants nothing.
func ability_id() -> StringName:
	return &""

## Injected once when the Player registers us (in _ready for editor-placed nodes, or right after add for a
## runtime grant). Subclasses override to cache the host parts they need + build in-tree helpers; call super.
func setup(player: Node) -> void:
	host = player

## Hygiene hook fired when the PLAYER switches this implant off (AbilityManager.set_active(false) — the
## Implants-tab toggle). Override to end any live use of the mechanic so a re-enable can't resume stale
## state: Slide ends a slide mid-glide, Grapple severs a live rope. NOT fired by the load path's disable
## (set_unlocks / set_disabled build fresh state) or by revoke (the node is freed outright). Default: nothing.
func on_deactivated() -> void:
	pass
