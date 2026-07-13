@tool
class_name Lock
extends Node

## A LOCK component: drop one under any interactable and the host asks it before opening — an ItemContainer
## today, a DOOR tomorrow (the door's own interact just checks Lock.of(self) the same way). Picking needs
## the required item (a lockpick by default) in the opener's backpack; a KEYED variant is the same component
## with requires_item_id set to a key/keycard id and consumes_item off. The host stays in charge of what
## "opening" means — this node owns only the locked state + the attempt rules — which is what keeps the
## system reusable for doors/gates/safes later.

signal unlocked(by: Node)  ## fired once, on the successful pick/key turn — a door swings open on this

## Drives the `requires_item_id` dropdown from the item ids on disk (const-preloaded, NO class_name — see item_ids.gd).
const ItemIds = preload("res://scripts/items/item_ids.gd")

## Starts locked? ON = the host stays shut until a successful pick/key turn flips it off permanently. Turn
## OFF to ship an already-open container/door (it opens with no item check).
@export var locked: bool = true
## The inventory item that opens this lock, matched by Item.id: &"lockpick" picks it open, &"keycard_red"
## keys a future door, etc. The opener must carry at least one.
@export var requires_item_id: StringName = &"lockpick"
## Consume one required item on success — true for a snapped lockpick, false for a reusable key.
@export var consumes_item: bool = true
## OPTIONAL: a successful unlock ALSO sets this global story flag (GameState.set_flag(unlock_flag, true)) — so a
## one-time door/safe opening can gate a quest objective or another door. Empty = no flag written.
@export var unlock_flag: StringName = &""

## The first Lock under `host`, or null — how an interactable discovers its own lock (Lock.of(self)).
static func of(host: Node) -> Lock:
	if host == null:
		return null
	for c in host.get_children():
		if c is Lock:
			return c as Lock
	return null

## One unlock attempt by `opener` (the player): needs the required item in opener.inventory. On success the
## lock opens PERMANENTLY (locked = false, `unlocked` fires, the item is consumed if consumes_item); on
## failure a toast tells the opener what it needs. Safe for any opener — no inventory just fails quietly.
func try_unlock(opener: Node) -> bool:
	if not locked:
		return true
	var gate := BuildGate.of(self)
	if gate != null and not gate.passes(opener):
		if opener != null and opener.has_method(&"notify_toast"):
			opener.notify_toast(gate.deny_reason(opener), Color(1.0, 0.55, 0.4))
		return false
	var inv: Variant = opener.get(&"inventory") if opener != null else null
	var ci := inv as CharacterInventory  # null if inv isn't a CharacterInventory — capture once, guard on != null
	var pick: Item = ci.find_by_id(requires_item_id) if ci != null else null
	if pick == null:
		if opener != null and opener.has_method(&"notify_toast"):
			opener.notify_toast("[PH] Locked — requires %s" % _required_label(), Color(1.0, 0.55, 0.4))
		return false
	if consumes_item:
		ci.remove(pick, 1)
	locked = false
	if unlock_flag != &"":
		GameState.set_flag(unlock_flag)  # record the opening as a global story flag (gate a quest / another door)
	if opener != null and opener.has_method(&"notify_toast"):
		opener.notify_toast("[PH] Lock picked" if consumes_item else "[PH] Unlocked", Color(0.4, 1.0, 0.45))
	unlocked.emit(opener)
	return true

## The required item's display name when it's registered (ItemDb), else the raw id — for the failure toast.
func _required_label() -> String:
	for it in ItemDb.all_items():
		if it != null and it.id == requires_item_id:
			return it.label()
	return String(requires_item_id).capitalize()

## Self-populate the `requires_item_id` dropdown from the item ids on disk (a SUGGESTION, so a custom / not-yet-
## authored key is still typable). Keeps a lock's key spelled exactly like the Item it needs.
func _validate_property(property: Dictionary) -> void:
	if property.name == "requires_item_id":
		property.hint = PROPERTY_HINT_ENUM_SUGGESTION
		property.hint_string = ItemIds.ids_csv()
