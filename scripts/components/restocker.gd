@tool
class_name Restocker
extends Node

## Drop-in RESTOCKER: keeps a Merchant or ItemContainer topped up to its fixed authored stock/item baseline over
## time, so a vendor you cleaned out replenishes and a looted crate's item_stacks refill on a return visit. Drop it as a CHILD of the
## Merchant / ItemContainer (or point `target_path` at one). Two modes:
##   • TIMER — refills every `interval` seconds.
##   • ON_VISIT — refills when the player next opens it (the first visit always; later visits no more often
##     than `interval` seconds, so re-opening rapidly doesn't spam stock). ONE exception: a quickload that
##     restores an ItemContainer's exact contents marks the cycle spent (note_restored), so the first reopen
##     after loading does NOT top the restored bag back up.
## The host's refill() only adds the SHORTFALL vs its authored stock/item rows — it never doubles stock and
## never removes what the player sold/deposited in. Container money is not re-seeded, and loot tables are not re-rolled.

enum Mode { TIMER, ON_VISIT }

## TIMER refills on a clock; ON_VISIT refills when the player reopens it (rate-limited by `interval`).
@export var mode: Mode = Mode.TIMER
## Seconds between restocks. 0 = use GameSettings.economy.restock_interval (the global default).
@export var interval: float = 0.0
## OPTIONAL: the Merchant / ItemContainer to restock. Empty = this node's parent.
@export var target_path: NodePath

var _target: Node = null
var _elapsed: float = 0.0       ## seconds since the last refill (drives both the timer and the visit rate-limit)
## So the FIRST ON_VISIT always restocks, regardless of elapsed time — EXCEPT after a snapshot restore, which
## pre-sets it true (see note_restored) so a quickload can't be milked as a free instant refill.
var _refilled_once: bool = false

func _ready() -> void:
	if Engine.is_editor_hint():
		return  # @tool: only the configuration warning runs in-editor; restocking is runtime-only
	_target = _resolve_target()
	set_process(true)  # accumulate _elapsed for the timer AND the visit rate-limit

func _process(delta: float) -> void:
	_elapsed += delta
	if mode == Mode.TIMER and _elapsed >= _interval():
		_do_refill()

## Called (via the static notify_visit) when the host is opened — refills if this is an ON_VISIT restocker and
## either it's the first visit or the rate-limit interval has elapsed.
func _on_visit() -> void:
	if mode != Mode.ON_VISIT:
		return
	if not _refilled_once or _elapsed >= _interval():
		_do_refill()

func _do_refill() -> void:
	_elapsed = 0.0
	_refilled_once = true
	if _target != null and _target.has_method(&"refill"):
		_target.refill()

func _interval() -> float:
	if interval > 0.0:
		return interval
	# Read economy via Object.get() rather than `GameSettings.economy` so a transient
	# autoload-reload state (editor reimport / hot-reload while the game runs) yields null
	# instead of raising "Invalid access to property 'economy'". TIMER mode evaluates this
	# EVERY frame, so it's the one economy reader that reliably collides with a sub-second
	# reload hiccup; the null guard below already handles the recovered-to-null result.
	var eco: Variant = GameSettings.get(&"economy")
	if eco != null:
		return maxf(0.1, eco.restock_interval)
	return 60.0

func _resolve_target() -> Node:
	if not target_path.is_empty():
		return get_node_or_null(target_path)
	return get_parent()

## Exact-snapshot restore hook (WorldSnapshot tier): after a quickload rebuilds the host's contents to their
## save-time state, treat the restock cycle as freshly spent — _refilled_once so the FIRST-visit-always rule
## can't fire (an ON_VISIT crate would otherwise top a just-restored looted bag straight back up, making
## quickload a free instant restock), and _elapsed = 0 so the next refill waits a full interval. Deliberately
## CONSERVATIVE, not exact: the true pre-save _elapsed isn't persisted, so a restock can arrive up to one
## interval later than it would have — the safe direction (never earlier/doubled).
func note_restored() -> void:
	_refilled_once = true
	_elapsed = 0.0

## Trigger a refill on a Merchant / ItemContainer's child ON_VISIT Restocker, if it has one. The host calls this
## in start_talk before opening, so the player sees restocked goods.
static func notify_visit(host: Node) -> void:
	if host == null:
		return
	for c in host.get_children():
		if c is Restocker:
			(c as Restocker)._on_visit()

func _get_configuration_warnings() -> PackedStringArray:
	var t := _resolve_target()
	if t == null:
		return PackedStringArray(["Restocker has no target — set target_path, or make it a child of a Merchant / ItemContainer."])
	if not t.has_method(&"refill"):
		return PackedStringArray(["Restocker's target '%s' has no refill() — it must be a Merchant or ItemContainer." % str(t.name)])
	return PackedStringArray()
