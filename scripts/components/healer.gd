class_name Healer
extends LookAtInteractable

## Drop-in HEALER / medic component. Two ways to use it (both supported), exactly like Merchant:
##   1. STANDALONE (a healing fountain, a med-station): leave `standalone` on (default) — it sits on the talk
##      layer, so aiming at it and pressing Interact opens the heal screen (zero ray_cast changes).
##   2. ON A DIALOGUE NPC: set `standalone` = false so the ray IGNORES it (the NPC's Talkable drives the
##      conversation); the dialogue then offers a "Heal" option that opens THIS healer's screen.
##
## Pays zorkmids to restore HP to FULL and clear ALL limb damage. The cost is LINEAR in MISSING HP
## (cost_per_hp per point missing), floored at min_cost whenever there's anything to mend.
##
## SETUP: drop it under the medic / fountain (or assign highlight_target), size its CollisionShape3D to the
## body you aim at, and set heal_name / cost_per_hp / min_cost.

@export var heal_name: String = ""                ## shown on the hover + screen title; blank -> "Healer"
@export var cost_per_hp: float = 1.0              ## zorkmids charged per point of MISSING hp (the linear rate)
@export var min_cost: int = 5                     ## floor charged when there's any damage (covers limb-only heals)
## STANDALONE (default): sit on the talk layer so Interact opens the heal screen directly. Off -> DATA-ONLY:
## the ray won't detect us, and a dialogue NPC drives access via its "Heal" option.
@export var standalone: bool = true

func _ready() -> void:
	# Standalone = a look-at hitbox on the talk layer (ray detects it); data-only healers sense nothing.
	collision_layer = TalkHelpers.TALK_LAYER if standalone else 0
	collision_mask = 0
	_build_outline()  # look-at outline over the host's meshes (LookAtInteractable helper)
	if auto_fit_collider:
		_fit_hitbox_to_host()

## Zorkmids to fully heal `player` right now — LINEAR in missing HP, floored at min_cost while anything is
## hurt. 0 means there's nothing to heal (full HP + no limb damage), so the service refuses / is free.
func heal_cost(player_node: Node) -> int:
	var player := player_node as Player
	if player == null:
		return 0
	var missing: float = maxf(0.0, player.max_hp - player.hp)
	var hurt: bool = missing > 0.5 or player.has_limb_damage()
	if not hurt:
		return 0
	return maxi(min_cost, int(ceil(missing * cost_per_hp)))

## Charge + heal: restore HP to full and clear all limb damage. Returns false (charging nothing) when there
## is nothing to heal or the player can't afford the cost.
func do_heal(player_node: Node) -> bool:
	var player := player_node as Player
	if player == null:
		return false
	var cost := heal_cost(player)
	if cost <= 0 or player.money < cost:
		return false
	player.add_money(-cost)       # routes through the wallet seam -> HUD readout + the floating -N indicator
	player.heal(player.max_hp)    # heal() clamps to max_hp -> full
	player.heal_limbs()
	return true

# ---------------------------------------------------------------------------
# Behaviour (talk-handler surface — used only when standalone, a direct-interact medic)
# ---------------------------------------------------------------------------

## Interact pressed while aimed at us: open the heal screen for this healer.
func start_talk(player: Node) -> void:
	HealScreen.open_heal(self, player)

## Always interactable.
func can_be_talked_to() -> bool:
	return true

## Hover readout: "Heal: <name>" (or just "Healer" when unnamed).
func look_name() -> String:
	return "Heal: %s" % heal_name if not heal_name.is_empty() else "Healer"
