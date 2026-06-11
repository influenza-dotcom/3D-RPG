class_name Lock
extends Node

## A LOCK component: drop one under any interactable and the host asks it before opening — an ItemContainer
## today, a DOOR tomorrow (the door's own interact just checks Lock.of(self) the same way). Picking needs
## the required item (a lockpick by default) in the opener's backpack; a KEYED variant is the same component
## with requires_item_id set to a key/keycard id and consumes_item off. The host stays in charge of what
## "opening" means — this node owns only the locked state + the attempt rules — which is what keeps the
## system reusable for doors/gates/safes later.

signal unlocked(by: Node)  ## fired once, on the successful pick/key turn — a door swings open on this

@export var locked: bool = true
## The inventory item that opens this lock, matched by Item.id: &"lockpick" picks it open, &"keycard_red"
## keys a future door, etc. The opener must carry at least one.
@export var requires_item_id: StringName = &"lockpick"
## Consume one required item on success — true for a snapped lockpick, false for a reusable key.
@export var consumes_item: bool = true

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
	var inv: Variant = opener.get(&"inventory") if opener != null else null
	var pick: Item = (inv as CharacterInventory).find_by_id(requires_item_id) if inv is CharacterInventory else null
	if pick == null:
		if opener != null and opener.has_method(&"notify_toast"):
			opener.notify_toast("Locked — requires %s" % _required_label(), Color(1.0, 0.55, 0.4))
		return false
	if consumes_item:
		(inv as CharacterInventory).remove(pick, 1)
	locked = false
	if opener != null and opener.has_method(&"notify_toast"):
		opener.notify_toast("Lock picked" if consumes_item else "Unlocked", Color(0.4, 1.0, 0.45))
	unlocked.emit(opener)
	return true

## The required item's display name when it's registered (ItemDb), else the raw id — for the failure toast.
func _required_label() -> String:
	for it in ItemDb.all_items():
		if it != null and it.id == requires_item_id:
			return it.label()
	return String(requires_item_id).capitalize()
