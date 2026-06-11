class_name Bonfire
extends LookAtInteractable

## Drop-in BONFIRE / checkpoint, dual-mode like Merchant / Healer:
##   1. STANDALONE (a lit campfire prop): leave standalone on (default) — aim + Interact to rest here.
##   2. ON A DIALOGUE NPC: set standalone = false; the NPC's dialogue offers a "Rest" option.
##
## RESTING restores you to full (HP + limbs) and sets THIS as your respawn point. On death you're brought
## back to LIFE here — the world is NOT reset (enemies stay as they are; nothing reloads), you just return
## to the bonfire. (Autosave-to-disk + a level-up menu layer onto this next.)
##
## SETUP: drop it under the campfire (or assign highlight_target), size its CollisionShape3D to the body
## you aim at, and name it.

@export var bonfire_name: String = ""             ## hover + (later) the rest menu title; blank -> "Bonfire"
@export var standalone: bool = true               ## true -> direct-interact; false -> data-only, driven by dialogue

func _ready() -> void:
	# Standalone = a look-at hitbox on the talk layer (ray detects it); data-only bonfires sense nothing.
	collision_layer = TalkHelpers.TALK_LAYER if standalone else 0
	collision_mask = 0
	_build_outline()
	if auto_fit_collider:
		_fit_hitbox_to_host()

## Rest at this bonfire: full heal (HP + limbs) and register it as the respawn point. Always succeeds for a
## real player. The respawn is read by Player._respawn_at_checkpoint on death.
func rest(player_node: Node) -> bool:
	var player := player_node as Player
	if player == null:
		return false
	player.heal(player.max_hp)   # heal() clamps to max_hp -> full
	player.heal_limbs()
	GameState.set_respawn(global_position, global_rotation.y)
	GameState.autosave(player)  # resting is a milestone — persist the run (incl. THIS as the new respawn point)
	if player.has_method(&"notify_toast"):
		var where := bonfire_name if not bonfire_name.is_empty() else "the bonfire"
		player.notify_toast("Rested at %s" % where, Color(1.0, 0.66, 0.3))
	return true

# ---------------------------------------------------------------------------
# Behaviour (talk-handler surface — used only when standalone, a direct-interact bonfire)
# ---------------------------------------------------------------------------

## Interact pressed while aimed at us: rest here.
func start_talk(player: Node) -> void:
	rest(player)

## Always interactable.
func can_be_talked_to() -> bool:
	return true

## Hover readout: "Rest: <name>" (or "Rest at bonfire" when unnamed).
func look_name() -> String:
	return "Rest: %s" % bonfire_name if not bonfire_name.is_empty() else "Rest at bonfire"
