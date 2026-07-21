extends RefCounted

## Shared UNLOCK RULE for Lock + Door. Given the opener's inventory and a lock's key/pick config, decide the outcome
## WITHOUT mutating anything — the caller consumes the item, flips `locked`, and toasts. The rule lives HERE (not
## copied into both) so its core contract can't drift between the container/safe `Lock` component and the `Door`'s
## built-in gate:
##   • a KEY and PICKABILITY are INDEPENDENT — a lock can be key-only, pickable-only, both, or sealed;
##   • a KEY YOU CARRY TAKES PRECEDENCE over a lockpick (never waste a pick on a door you have the key to).
##
## Preloaded as a const where used (NO class_name — nothing for the test global-class cache to miss, matching
## item_ids.gd / calibers.gd). `decide()` is PURE (reads the inventory, returns a plan) so it unit-tests off-tree
## with no autoloads; `label_for()` is the one impure helper (an ItemDb name lookup for the deny toast).

## The ways an unlock attempt resolves. OPEN_* say WHICH item opened it (so the caller consumes the right one and
## picks the right success toast); DENY_* say what's missing (so the caller toasts the most helpful hint).
enum Outcome { OPEN_KEY, OPEN_PICK, DENY_KEY, DENY_PICK, DENY_KEY_OR_PICK, DENY_SEALED }

## Decide how `ci` (a CharacterInventory, or null = no bag) fares against a lock configured with `key_item_id`
## (empty = no key opens it), `pickable` (can a lockpick open it at all?), and `lockpick_item_id` (which pick).
## Returns { "outcome": Outcome, "item": Item|null } — `item` is the carried Item the caller consumes on an OPEN_*
## (null on a deny). KEY IS TESTED FIRST: a carried key opens the lock even when it is ALSO pickable and the opener
## holds a lockpick — that is the "having the key takes precedence" rule, in one place.
static func decide(ci: CharacterInventory, key_item_id: StringName, pickable: bool, lockpick_item_id: StringName) -> Dictionary:
	if key_item_id != &"":
		var key: Item = ci.find_by_id(key_item_id) if ci != null else null
		if key != null:
			return {"outcome": Outcome.OPEN_KEY, "item": key}
	if pickable:
		var pick: Item = ci.find_by_id(lockpick_item_id) if ci != null else null
		if pick != null:
			return {"outcome": Outcome.OPEN_PICK, "item": pick}
	# Denied — name what's missing as specifically as the config allows, so the toast is actionable.
	var has_key := key_item_id != &""
	if has_key and pickable:
		return {"outcome": Outcome.DENY_KEY_OR_PICK, "item": null}
	if has_key:
		return {"outcome": Outcome.DENY_KEY, "item": null}
	if pickable:
		return {"outcome": Outcome.DENY_PICK, "item": null}
	return {"outcome": Outcome.DENY_SEALED, "item": null}  # no key, not pickable — a script must open it (the Door can also gate on unlock_flag; the Lock can't)

## The display name for an item id — its Item.label() when registered (ItemDb), else the id title-cased. Shared by
## Lock and Door so a key/pick is named identically in the "Locked — requires X" deny toast. Empty id -> "".
static func label_for(id: StringName) -> String:
	if id == &"":
		return ""
	for it in ItemDb.all_items():
		if it != null and it.id == id:
			return it.label()
	return String(id).capitalize()
