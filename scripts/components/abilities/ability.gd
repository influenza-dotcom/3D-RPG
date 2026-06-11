class_name Ability
extends Node

## Base for drag-drop player ABILITY components. Drop one (or several) under a Player and its PRESENCE grants
## that mechanic — no string-flag bookkeeping, and because each ability is its OWN node you can stack as many as
## you want (the one-script-per-node wall is gone). Each subclass owns its behaviour + tuning + state; the Player
## discovers its Ability children, injects itself, and calls the subclass's hooks at the load-bearing beats of
## its movement step (the call ORDER is preserved, so feel is unchanged). An UpgradePickup grants one by ADDING
## the node; the autosave lists the present ids and re-adds them on load.
##
## `host` is the owning Player — typed Node (not Player) to avoid a Player <-> Ability class cycle, so every
## host.* access is dynamic (the same idiom AimSway / HurtFeedback use).

## Turn the ability OFF without removing the node (a temporarily-revoked upgrade). The Player's gate
## (has_mechanic) ignores a disabled ability, and unlocked_list() omits it, so it doesn't persist as granted.
@export var enabled: bool = true

var host: Node = null  ## the owning Player, injected by Player._register_ability

## The mechanic id this ability grants (&"wall_climb", &"slide", …). Subclasses MUST override — the Player's gate
## and the save system match on it. The default empty id grants nothing.
func ability_id() -> StringName:
	return &""

## Injected once when the Player registers us (in _ready for editor-placed nodes, or right after add for a
## runtime grant). Subclasses override to cache the host parts they need + build in-tree helpers; call super.
func setup(player: Node) -> void:
	host = player
