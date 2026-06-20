@tool
class_name PerkStation
extends LookAtInteractable

## A drop-in station that grants a single Perk on Interact — the no-choice counterpart to a level-up perk pick
## (and the perk twin of UpgradePickup). Aim + Interact and the perk's stat bonuses / ability are applied to the
## player via its PerkManager (auto-created), then the station frees itself. For "find the shrine, learn the perk".
##
## SETUP: drop it under the shrine / trainer prop (or assign highlight_target), size its CollisionShape3D, and
## assign `perk`.

@export var perk: Perk
@export var consume_on_use: bool = true  ## free the station after granting (a one-time pickup)

func _ready() -> void:
	if Engine.is_editor_hint():
		_editor_fit_hitbox()
		return
	collision_layer = TalkHelpers.TALK_LAYER
	collision_mask = 0
	_build_outline()
	if auto_fit_collider:
		_fit_hitbox_to_host()

func start_talk(player: Node) -> void:
	if perk == null or player == null:
		return
	var mgr := _perk_manager(player)
	if mgr != null and mgr.unlock_perk(perk):
		GameState.autosave(player)  # a new perk (stat bonuses + any granted mechanic) is a milestone — like UpgradePickup
		if player.has_method(&"notify_toast"):
			player.notify_toast("Learned: %s" % _perk_label(), Color(0.6, 0.85, 1.0))
		if consume_on_use:
			queue_free()
	elif player.has_method(&"notify_toast"):
		player.notify_toast("Already learned", Color(0.85, 0.85, 0.85))

func can_be_talked_to() -> bool:
	return perk != null

func look_name() -> String:
	return "Learn: %s" % _perk_label() if perk != null else "Perk"

func _perk_label() -> String:
	if perk == null:
		return "Perk"
	return perk.display_name if perk.display_name != "" else String(perk.id)

## Find (or create) the player's PerkManager child so perks work without pre-placing one.
func _perk_manager(player: Node) -> PerkManager:
	for c in player.get_children():
		if c is PerkManager:
			return c
	var mgr := PerkManager.new()
	mgr.name = &"Perks"
	player.add_child(mgr)
	return mgr

func _get_configuration_warnings() -> PackedStringArray:
	if perk == null:
		return PackedStringArray(["PerkStation has no `perk` assigned — it will grant nothing."])
	return PackedStringArray()
