class_name ItemSort
extends RefCounted

## Display-sorting for the inventory / shop item lists. The player cycles a mode with the Sort button; the
## {"item","count"} stacks from CharacterInventory.contents() are reordered for SHOW ONLY — the underlying
## bag order is never mutated. DEFAULT leaves them in bag (insertion) order.

enum Mode { DEFAULT, NAME, TYPE, VALUE, WEIGHT }

const LABELS := {
	Mode.DEFAULT: "Default",
	Mode.NAME: "Name",
	Mode.TYPE: "Type",
	Mode.VALUE: "Value",
	Mode.WEIGHT: "Weight",
}

## The next mode in the cycle (wraps back to DEFAULT).
static func next_mode(mode: int) -> int:
	return (mode + 1) % LABELS.size()

## "Sort: Name" — the Sort button's caption for `mode`.
static func button_text(mode: int) -> String:
	return "Sort: %s" % LABELS.get(mode, "Default")

## A NEW array of `stacks` ordered per `mode` (the input is never mutated). DEFAULT keeps bag order.
## Ties always fall back to name so the order is stable and predictable.
static func sorted(stacks: Array, mode: int) -> Array:
	var out: Array = stacks.duplicate()
	if mode == Mode.NAME:
		out.sort_custom(func(a, b): return String(a["item"].label()).naturalnocasecmp_to(String(b["item"].label())) < 0)
	elif mode == Mode.TYPE:
		out.sort_custom(func(a, b):
			var ca: int = a["item"].category
			var cb: int = b["item"].category
			if ca != cb:
				return ca < cb
			return String(a["item"].label()).naturalnocasecmp_to(String(b["item"].label())) < 0)
	elif mode == Mode.VALUE:
		out.sort_custom(func(a, b):
			var va: float = a["item"].value
			var vb: float = b["item"].value
			if va != vb:
				return va > vb  # priciest first
			return String(a["item"].label()).naturalnocasecmp_to(String(b["item"].label())) < 0)
	elif mode == Mode.WEIGHT:
		out.sort_custom(func(a, b):
			var wa: float = a["item"].weight
			var wb: float = b["item"].weight
			if wa != wb:
				return wa > wb  # heaviest first — find what's slowing you down
			return String(a["item"].label()).naturalnocasecmp_to(String(b["item"].label())) < 0)
	return out
