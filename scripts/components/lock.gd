@tool
class_name Lock
extends Node

## A LOCK component: drop one under any interactable (an ItemContainer today, or a Door via Lock.of) and the host
## asks it before opening. A lock is defined by TWO INDEPENDENT capabilities, so it no longer has to conflate a key
## with a lockpick (the old single `requires_item_id` couldn't express "key OR pick"):
##   • a KEY — an OPTIONAL inventory item (a keycard / specific key) that opens it outright (`key_item_id`), and
##   • PICKABILITY — whether a lockpick can open it AT ALL (`pickable` + `lockpick_item_id`).
## So a lock can be pickable-only (no key — the classic lockpick lock, the DEFAULT), key-only (`pickable` off),
## BOTH (a key you own OR a lockpick — and a carried KEY TAKES PRECEDENCE, never wasting a pick), or SEALED (no key,
## not pickable — only a script setting `locked = false` opens it; NOTE a Lock does NOT read `unlock_flag` as a gate,
## it merely WRITES it on a successful open — a flag-as-gate is a Door-only feature). The decision lives in lock_rules.gd so the Door's
## built-in gate applies the identical rule. The host stays in charge of what "opening" means — this node owns only
## the locked state + the attempt rules — which is what keeps the system reusable for containers/doors/safes.

signal unlocked(by: Node)  ## fired once, on the successful pick/key turn — a door swings open on this

## Drives the `key_item_id` / `lockpick_item_id` dropdowns from the item ids on disk (const-preloaded — see item_ids.gd).
const ItemIds = preload("res://scripts/items/item_ids.gd")
## The shared key-vs-pick decision (with key precedence), so Lock and the Door gate can't drift. See lock_rules.gd.
const LockRules = preload("res://scripts/components/lock_rules.gd")

## Starts locked? ON = the host stays shut until a successful pick/key turn flips it off permanently. Turn OFF to
## ship an already-open container/door (it opens with no check).
@export var locked: bool = true

@export_group("Key")
## OPTIONAL key that opens this lock OUTRIGHT, matched by Item.id (&"keycard_red", a specific key). Empty = no key
## opens it (rely on picking and/or `unlock_flag`). A carried key ALWAYS TAKES PRECEDENCE over picking.
@export var key_item_id: StringName = &""
## Consume the key on a successful key-turn? Usually false — a real key is reusable. True for a one-time token key.
@export var consume_key: bool = false

@export_group("Picking")
## Can this lock be PICKED with a lockpick AT ALL? ON (default) = a lockpick opens it; OFF = key-only / sealed. This
## is the "capable of getting lockpicked or not" switch — independent of any key.
@export var pickable: bool = true
## Which inventory item picks it (only when `pickable`). The generic &"lockpick" by default — retarget for a special
## pick / skeleton key. UNLIKE a key it opens ANY pickable lock (a key opens only its one matching lock).
@export var lockpick_item_id: StringName = &"lockpick"
## Consume one lockpick on a successful pick? True by default (a snapped pick). Off for a reusable skeleton key.
@export var consumes_pick: bool = true

## OPTIONAL: a successful unlock ALSO sets this global story flag (GameState.set_flag(unlock_flag)) — so a one-time
## door/safe opening can gate a quest objective or another door. Empty = no flag written.
@export var unlock_flag: StringName = &""

## The first Lock under `host`, or null — how an interactable discovers its own lock (Lock.of(self)).
static func of(host: Node) -> Lock:
	if host == null:
		return null
	for c in host.get_children():
		if c is Lock:
			return c as Lock
	return null

## One unlock attempt by `opener` (the player): resolves via the shared key-vs-pick rule (key precedence). On success
## the lock opens PERMANENTLY (locked = false, `unlocked` fires, the key/pick consumed per its flag); on failure a
## toast tells the opener what it needs. Safe for any opener — no inventory just fails with the right hint.
func try_unlock(opener: Node) -> bool:
	if not locked:
		return true
	var gate := BuildGate.of(self)
	if gate != null and not gate.passes(opener):
		_toast(opener, gate.deny_reason(opener), false)
		return false
	var inv: Variant = opener.get(&"inventory") if opener != null else null
	var ci := inv as CharacterInventory  # null if inv isn't a CharacterInventory — LockRules.decide handles null
	var d := LockRules.decide(ci, key_item_id, pickable, lockpick_item_id)
	match int(d["outcome"]):
		LockRules.Outcome.OPEN_KEY:
			if consume_key and ci != null:
				ci.remove(d["item"], 1)
			_open(opener, PlayerText.TOAST_UNLOCKED)  # a key turn, not a snapped pick
			return true
		LockRules.Outcome.OPEN_PICK:
			if consumes_pick and ci != null:
				ci.remove(d["item"], 1)
			_open(opener, PlayerText.lock_result(consumes_pick))  # "Lock picked" when the pick snaps, else "Unlocked"
			return true
		_:
			_toast(opener, _deny_message(int(d["outcome"])), false)
			return false

## Flip the lock open, write the optional story flag, toast success, and fire `unlocked` (the door swings on this).
func _open(opener: Node, toast_text: String) -> void:
	locked = false
	if unlock_flag != &"":
		GameState.set_flag(unlock_flag)  # record the opening as a global story flag (gate a quest / another door)
	_toast(opener, toast_text, true)
	unlocked.emit(opener)

## The most helpful deny toast for an outcome: name the key, the pick, both, or just "Locked" for a sealed bolt.
func _deny_message(outcome: int) -> String:
	match outcome:
		LockRules.Outcome.DENY_KEY:
			return PlayerText.locked_requires(LockRules.label_for(key_item_id))
		LockRules.Outcome.DENY_PICK:
			return PlayerText.locked_requires(LockRules.label_for(lockpick_item_id))
		LockRules.Outcome.DENY_KEY_OR_PICK:
			return PlayerText.locked_requires_either(LockRules.label_for(key_item_id), LockRules.label_for(lockpick_item_id))
	return PlayerText.TOAST_LOCKED  # DENY_SEALED — no key, not pickable

func _toast(opener: Node, text: String, good: bool) -> void:
	if opener != null and opener.has_method(&"notify_toast"):
		opener.notify_toast(text, Color(0.4, 1.0, 0.45) if good else Color(1.0, 0.55, 0.4))

## Self-populate the key / lockpick id dropdowns from the item ids on disk (SUGGESTIONs, so a custom / not-yet-authored
## key or pick is still typable). Keeps a lock's ids spelled exactly like the Items they need.
func _validate_property(property: Dictionary) -> void:
	if property.name == "key_item_id" or property.name == "lockpick_item_id":
		property.hint = PROPERTY_HINT_ENUM_SUGGESTION
		property.hint_string = ItemIds.ids_csv()
