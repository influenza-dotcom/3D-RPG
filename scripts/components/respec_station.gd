@tool
class_name RespecStation
extends LookAtInteractable


## A drop-in station that REFUNDS all perks for a fee: aim + Interact, pay respec_cost, and every unlocked perk
## is reversed (stat bonuses undone, granted abilities revoked) and its skill point refunded — re-pick from
## scratch at a LevelUp. The respec twin of PerkStation; not consumed (respec as often as you can pay).
##
## SETUP: drop it under the shrine / trainer prop (or assign highlight_target), size its CollisionShape3D, tune
## respec_cost. Aim + Interact opens a RespecScreen confirm modal (the cost + the perks that will be refunded, with
## Confirm / Cancel) which pauses the world like the shop/heal/level-up screens and drives do_respec() on Confirm.

@export var station_name: String = ""    ## hover label; blank -> "Respec"
@export var respec_cost: float = 100.0   ## zorkmids charged per respec (0 = free)

func _ready() -> void:
	if Engine.is_editor_hint():
		_editor_fit_hitbox()  # preview the auto-fit hitbox in-editor (resizes an existing collider; safe)
		return  # @tool: only the hitbox preview runs in-editor; the outline/layer setup is runtime-only
	collision_layer = TalkHelpers.TALK_LAYER
	collision_mask = 0
	_build_outline()
	if auto_fit_collider:
		_fit_hitbox_to_host()

## Aim + Interact opens the confirm modal (mirrors LevelUp.start_talk -> LevelUpScreen). The modal previews the
## cost + the perks that will be refunded and calls do_respec() on Confirm; nothing changes until then.
func start_talk(player: Node) -> void:
	if player == null:
		return
	RespecScreen.open_respec(self, player)

## The respec transaction: reverse every unlocked perk (refunding each skill point), charge respec_cost, and
## autosave the reversed build. Returns the perk count refunded. Called by RespecScreen on Confirm — but it is
## self-guarding (no perks / can't afford -> 0, no charge) so it is also safe to call directly or from a test.
func do_respec(player: Node) -> int:
	if player == null:
		return 0
	var pm := _perk_manager(player)
	if pm == null or pm.unlocked_ids().is_empty():
		return 0
	if float(player.money) < respec_cost:
		return 0
	var n := pm.respec()
	if respec_cost != 0.0 and player.has_method(&"add_money"):
		player.add_money(-respec_cost)
	GameState.autosave(player)  # the authoritative persist of the reversed build
	if player.has_method(&"notify_toast"):
		player.notify_toast(PlayerText.respec_refunded(n), Color(0.6, 0.85, 1.0))
	return n

## The player's PerkManager — public wrapper for RespecScreen's refund preview (creates it if absent, same as
## the transaction path, so an empty preview is a real 0-perk manager, not a crash).
func perk_manager(player: Node) -> PerkManager:
	return _perk_manager(player)

func can_be_talked_to() -> bool:
	return true

func look_name() -> String:
	return PlayerText.respec_prompt(station_name)

## Find or create the player's PerkManager (mirrors PerkStation / LevelUp._perk_manager).
func _perk_manager(player: Node) -> PerkManager:
	for c in player.get_children():
		if c is PerkManager:
			return c as PerkManager
	var mgr := PerkManager.new()
	mgr.name = &"Perks"
	player.add_child(mgr)
	return mgr
