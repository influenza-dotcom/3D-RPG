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
	StationSpeaker.ensure(self)  # always a kiosk (this station has no dialogue-hosted mode) — give it the shared panel chirp
	# The minimap pin. No `standalone` field either, so ensure() pins it. TRAIN, shared with LevelUp / PerkStation.
	StationMarker.ensure(self, StationMarker.Kind.TRAIN)

## Aim + Interact opens the confirm modal (mirrors LevelUp.start_talk -> LevelUpScreen). The modal previews the
## cost + the perks that will be refunded and calls do_respec() on Confirm; nothing changes until then.
func start_talk(player: Node) -> void:
	if player == null:
		return
	RespecScreen.open_respec(self, player)

## The respec transaction: charge respec_cost, then reverse every unlocked perk (refunding each skill point), and
## autosave the reversed build. Returns the perk count refunded. Called by RespecScreen on Confirm — but it is
## self-guarding (no perks / can't afford / a refused debit -> 0, nothing charged and nothing reversed) so it is
## also safe to call directly or from a test.
func do_respec(player: Node) -> int:
	if player == null:
		return 0
	var pm := _perk_manager(player)
	if pm == null or pm.unlocked_ids().is_empty():
		return 0
	# Gate the fee only when there IS one (the healer/chip-installer `cost <= 0 or …` convention): a 0-cost
	# station is FREE and must serve even a wallet in DEBT — the New Game implant purchase can legitimately
	# start the run negative, and `money < 0.0` must not lock a debtor out of a free service. The paid path
	# still refuses any wallet below the fee, debtors included.
	# ⭐DUCK-TYPED, like every other call in this function: `player` is a bare Node here (the dialogue path and
	# the tests both hand in stubs that carry only `money` / `add_money`). Prefer the payment seam when the
	# host has it — that is what reaches the bank account and the credit line — and fall back to the plain
	# wallet comparison when it doesn't, so a minimal host is still served correctly rather than crashing.
	var affordable: bool = player.can_pay(respec_cost) if player.has_method(&"can_pay") \
			else float(player.money) >= respec_cost
	if respec_cost > 0.0 and not affordable:
		return 0
	# CHARGE FIRST, AND NEVER DISCARD charge()'s ANSWER — the Healer.do_heal / ChipInstaller.install_carried
	# idiom (`can_pay` gate, then `if not player.charge(cost): return`, then apply). Both halves are load-bearing:
	#  * ORDER: pm.respec() subtracts every perk's stat bonuses from the LIVE character sheet, and the credit
	#    limit is derived from that same sheet — so refunding first can SHRINK the available credit BETWEEN the
	#    affordability gate above and the debit below, at which point charge() fail-closes on a respec that was
	#    genuinely affordable one line earlier.
	#  * RETURN VALUE: charge() is fail-closed (it moves NOTHING when it refuses), so ignoring the bool left the
	#    perks refunded for FREE — and the autosave below then persisted the freebie.
	# This is deliberately the OPPOSITE order to LevelUp.raise_stat's charge-last, whose stated concern is that the
	# money_changed autosave inside add_money not catch a half-applied transaction. That concern does not bite here:
	# the Player's money_changed autosave (_on_money_autosave) is a ONE-FRAME-DEFERRED coalesced flush, so the write
	# it queues already sees the finished refund below. Even if it were immediate, a transient interim snapshot
	# superseded by the authoritative autosave below would still be a far cheaper wart than a free respec — and a
	# perk refund, unlike a stat raise, is not cheaply re-appliable, which rules out the capture-and-undo variant.
	if respec_cost > 0.0:  # > 0, not != 0: a mis-authored NEGATIVE cost must not pay the player
		if player.has_method(&"charge"):
			if not player.charge(respec_cost):  # the payment seam: cash, then savings, then the armed rail
				return 0                        # fail-closed: nothing left the player, so nothing gets refunded
		elif player.has_method(&"add_money"):
			player.add_money(-respec_cost)      # minimal host (a stub / a non-Player wallet): the plain debit
	var n := pm.respec()
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
