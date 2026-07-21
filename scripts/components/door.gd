@tool
class_name Door
extends LookAtInteractable

## A drop-in DOOR: aim + Interact to swing it open/closed, or drive it from a TriggerVolume / switch / cutscene
## via open() / close() / toggle(). Built on LookAtInteractable (the aim-at-and-Interact base, so it gets the
## look-at outline + the Interact hookup for free) with a child PIVOT that holds the door's mesh AND its
## StaticBody3D blocker — swinging the pivot moves the panel (and its collision) out of the doorway, so an open
## door simply isn't in the way. Locking reuses a child Lock component if present, OR the built-in key / flag gate.
##
## NOTE: extends LookAtInteractable (an Area3D), not StaticBody3D — the physical block lives on the child
## StaticBody3D under the pivot. That's what lets a door be both a solid blocker AND an Interact target, since
## the interaction ray detects the talk-layer Area, not the world-layer body.

signal opened
signal closed

## Drives the `key_item_id` / `lockpick_item_id` dropdowns from the item ids on disk (const-preloaded — see item_ids.gd).
const ItemIds = preload("res://scripts/items/item_ids.gd")
## The shared key-vs-pick decision (with key precedence), so the Door gate and the Lock component can't drift.
const LockRules = preload("res://scripts/components/lock_rules.gd")
const WorldSaveId = preload("res://scripts/world/world_save_id.gd")  # stable per-object save key (see GameState.world_objects)

@export_group("Swing")
## The node rotated when the door opens — it holds the door's mesh + its StaticBody3D blocker, so the whole
## panel swings out of the doorway. Assign the prefab's "DoorPivot". Without it, open/close are no-ops.
@export var pivot: Node3D
## Degrees around Y the pivot turns when open (negative swings the other way).
@export var open_angle: float = 90.0
## Seconds the open/close swing takes.
@export var open_duration: float = 0.5
## Start the level with this door already open.
@export var start_open: bool = false

@export_group("Lock")
## Starts locked? A locked door won't open on Interact until it's unlocked (by a child Lock, a key, a lockpick, or
## a flag). For richer locks (a keyed AND pickable safe on a container), drop a child `Lock` — it takes over and
## these built-in fields are ignored; these cover the common inline door lock.
@export var locked: bool = false
## OPTIONAL key: an inventory Item.id that unlocks this door OUTRIGHT. Empty = no key (rely on picking / a flag). A
## carried key TAKES PRECEDENCE over a lockpick, so a door that's keyed AND pickable never wastes a pick.
@export var key_item_id: StringName = &""
## Consume the key on a successful key-turn (true) or keep it as a reusable key (false, the usual).
@export var consume_key: bool = false
## Can this door be PICKED with a lockpick AT ALL? OFF by default (a locked door is a dead bolt unless you say so) —
## turn ON to make it lockpickable, independent of any key. This is the "capable of getting lockpicked or not" switch.
@export var pickable: bool = false
## Which inventory item picks it (only when `pickable`). The generic &"lockpick" by default.
@export var lockpick_item_id: StringName = &"lockpick"
## Consume one lockpick on a successful pick? True by default (a snapped pick).
@export var consumes_pick: bool = true
## OPTIONAL: while this global story flag is true the door counts as unlocked (GameState.get_flag) — "the gate
## opens once you've flipped the switch". Empty = no flag gate.
@export var unlock_flag: StringName = &""

@export_group("Save")
## OPTIONAL stable id so this door's open/locked state survives a save/load AND node renames/moves. Leave blank for
## the level+path+position fallback (fine for a door that never moves — see WorldSaveId); set it on important
## hand-placed doors. Only doors actually opened/closed/unlocked at least once are written to the ledger.
@export var save_id: StringName = &""

var _open: bool = false
var _closed_yaw: float = 0.0
var _tween: Tween
var _area_hitbox_rest_transforms: Dictionary = {}
var _area_hitboxes_cached: bool = false

func _ready() -> void:
	if Engine.is_editor_hint():
		return  # @tool: skip the talk-layer/outline setup in-editor (only _get_configuration_warnings runs)
	super()  # LookAtInteractable._ready: talk-layer hitbox + look-at outline
	if pivot != null:
		_closed_yaw = pivot.rotation.y
		_cache_area_hitbox_transforms()
		if start_open:
			_open = true
			_set_pivot_yaw(_closed_yaw + deg_to_rad(open_angle))
	# Restore saved open/locked state OVER the authored defaults (GameState.world_objects). Runs in _ready like the
	# Corpse-discovery restore; current_level_path is already set by GameRoot before the level subtree's _ready.
	var st := GameState.object_state(GameState.current_level_path, _save_key())
	if st.has("locked"):
		var locked_bit := GameState.as_bool(st["locked"], locked)
		locked = locked_bit
		# For a Door authored with a child Lock the REAL locked state lives on that Lock (the Door's own `locked` stays
		# false), so mirror the restored bit onto it — else a picked/keyed-open door re-locks on reload when the Lock
		# re-instantiates at its authored locked = true (look_name would show "Locked" on an open door + re-demand a
		# consumed pick). A door without a child Lock is unaffected (lk == null).
		var lk := Lock.of(self)
		if lk != null:
			lk.locked = locked_bit
	if st.has("open"):
		_open = GameState.as_bool(st["open"], _open)
		if pivot != null:
			_set_pivot_yaw(_closed_yaw + (deg_to_rad(open_angle) if _open else 0.0))

# --- Interact surface (LookAtInteractable) ---
func start_talk(player: Node) -> void:
	# A default-locked child Lock counts as locked even when the Door's own `locked` export is off — consult it
	# so an authored Lock isn't silently bypassed. _try_unlock owns the Lock (and the key/flag gate) once entered.
	var lk := Lock.of(self)
	if (locked or (lk != null and lk.locked)) and not _try_unlock(player):
		return  # still locked — _try_unlock toasted why
	toggle()

func can_be_talked_to() -> bool:
	return true

func look_name() -> String:
	# Locked = the Door's own `locked` (not flag-unlocked) OR a still-locked child Lock — show 'Locked' for both.
	var lk := Lock.of(self)
	if (locked and not _is_unlocked_by_flag()) or (lk != null and lk.locked):
		return PlayerText.PROMPT_LOCKED
	return PlayerText.PROMPT_CLOSE_DOOR if _open else PlayerText.PROMPT_OPEN_DOOR

## Unlock attempt: a child Lock (if present) owns it entirely; else an unlock_flag that's set; else the built-in
## key-OR-lockpick gate (same shared rule as the Lock component, with key precedence). Flips `locked` off on success.
func _try_unlock(player: Node) -> bool:
	var gate := BuildGate.of(self)
	if gate != null and not gate.passes(player):
		_toast(player, gate.deny_reason(player), false)
		return false
	var lk := Lock.of(self)
	if lk != null:
		if lk.try_unlock(player):
			locked = false
			return true
		return false
	if _is_unlocked_by_flag():
		locked = false
		return true
	var inv: Variant = player.get(&"inventory") if player != null else null
	var ci := inv as CharacterInventory  # null if inv isn't a CharacterInventory — LockRules.decide handles null
	var d := LockRules.decide(ci, key_item_id, pickable, lockpick_item_id)
	match int(d["outcome"]):
		LockRules.Outcome.OPEN_KEY:
			if consume_key and ci != null:
				ci.remove(d["item"], 1)
			locked = false
			_toast(player, PlayerText.TOAST_UNLOCKED, true)
			return true
		LockRules.Outcome.OPEN_PICK:
			if consumes_pick and ci != null:
				ci.remove(d["item"], 1)
			locked = false
			_toast(player, PlayerText.lock_result(consumes_pick), true)  # "Lock picked" when the pick snaps
			return true
		_:
			# Denied — key-only, pickable-only, both, or a sealed dead bolt (DENY_SEALED -> "Locked").
			_toast(player, _deny_message(int(d["outcome"])), false)
			return false

func _is_unlocked_by_flag() -> bool:
	return unlock_flag != &"" and GameState.get_flag_bool(unlock_flag)

## The most helpful deny toast for an outcome: name the key, the lockpick, both, or just "Locked" for a sealed bolt.
func _deny_message(outcome: int) -> String:
	match outcome:
		LockRules.Outcome.DENY_KEY:
			return PlayerText.locked_requires(LockRules.label_for(key_item_id))
		LockRules.Outcome.DENY_PICK:
			return PlayerText.locked_requires(LockRules.label_for(lockpick_item_id))
		LockRules.Outcome.DENY_KEY_OR_PICK:
			return PlayerText.locked_requires_either(LockRules.label_for(key_item_id), LockRules.label_for(lockpick_item_id))
	return PlayerText.TOAST_LOCKED  # DENY_SEALED — locked with no key and not pickable

func _toast(player: Node, text: String, good: bool) -> void:
	if player != null and player.has_method(&"notify_toast"):
		player.notify_toast(text, Color(0.4, 1.0, 0.45) if good else Color(1.0, 0.55, 0.4))

# --- Drive externally (a TriggerVolume action / switch / cutscene): open() / close() / toggle() ---
func open() -> void:
	if _open:
		return
	_open = true
	_swing_to(_closed_yaw + deg_to_rad(open_angle))
	_persist()  # a successful unlock flows through toggle()->open/close, so this also captures the locked flip
	opened.emit()

func close() -> void:
	if not _open:
		return
	_open = false
	_swing_to(_closed_yaw)
	_persist()
	closed.emit()

## Persist this door's open/locked state to the world-object ledger (keyed by level + save_id/fallback). No-op in
## the editor and off-tree, so a @tool preview or a bare unit test never mutates GameState.
func _persist() -> void:
	if Engine.is_editor_hint() or not is_inside_tree():
		return
	# Persist the EFFECTIVE locked bit: for a Door with a child Lock the real state lives on the Lock (Door.locked
	# stays false), so save the Lock's; _ready restores it back onto the Lock. Without a child Lock this is Door.locked.
	var lk := Lock.of(self)
	var locked_bit := lk.locked if lk != null else locked
	GameState.record_object_state(GameState.current_level_path, _save_key(), {"open": _open, "locked": locked_bit})

func _save_key() -> String:
	return WorldSaveId.key_for(self, save_id)

func toggle() -> void:
	if _open:
		close()
	else:
		open()

func is_open() -> bool:
	return _open

## Swing the pivot to `target_yaw` (radians). Tweened in-tree; snapped instantly off-tree (a bare unit test).
func _swing_to(target_yaw: float) -> void:
	if pivot == null:
		return
	_ensure_area_hitboxes_cached()
	if _tween != null and _tween.is_valid():
		_tween.kill()
	if not is_inside_tree():
		_set_pivot_yaw(target_yaw)
		return
	_tween = create_tween()
	_tween.tween_method(_set_pivot_yaw, pivot.rotation.y, target_yaw, maxf(0.01, open_duration))

func _set_pivot_yaw(yaw: float) -> void:
	if pivot == null:
		return
	_ensure_area_hitboxes_cached()
	pivot.rotation.y = yaw
	_sync_area_hitboxes_to_pivot()

func _ensure_area_hitboxes_cached() -> void:
	if not _area_hitboxes_cached:
		_cache_area_hitbox_transforms()

func _cache_area_hitbox_transforms() -> void:
	_area_hitbox_rest_transforms.clear()
	if pivot == null:
		_area_hitboxes_cached = true
		return
	var pivot_to_door := pivot.transform.affine_inverse()
	for child in get_children():
		var cs := child as CollisionShape3D
		if cs != null:
			_area_hitbox_rest_transforms[cs] = pivot_to_door * cs.transform
	_area_hitboxes_cached = true

func _sync_area_hitboxes_to_pivot() -> void:
	if pivot == null:
		return
	for key in _area_hitbox_rest_transforms.keys():
		if not is_instance_valid(key):
			continue
		var cs := key as CollisionShape3D
		if cs == null:
			continue
		var rest_transform: Transform3D = _area_hitbox_rest_transforms[cs]
		cs.transform = pivot.transform * rest_transform

func _get_configuration_warnings() -> PackedStringArray:
	var warnings := PackedStringArray()
	if pivot == null:
		warnings.append("Door has no `pivot` assigned — open/close will do nothing. Assign the DoorPivot child (the node holding the mesh + StaticBody3D blocker).")
	# A child Lock takes over unlocking entirely (see _try_unlock), so the Door's OWN Lock fields become dead config —
	# warn if any is set, so a designer configures the Lock child instead of the ignored built-in gate.
	if Lock.of(self) != null and (key_item_id != &"" or pickable or unlock_flag != &""):
		warnings.append("A child Lock is present — it OWNS unlocking, so the Door's built-in Lock fields (key_item_id / pickable / lockpick_item_id / unlock_flag) are IGNORED. Configure the Lock child, or remove it to use the built-in gate.")
	return warnings

## Self-populate the key / lockpick id dropdowns from the item ids on disk (SUGGESTIONs, still typable).
func _validate_property(property: Dictionary) -> void:
	if property.name == "key_item_id" or property.name == "lockpick_item_id":
		property.hint = PROPERTY_HINT_ENUM_SUGGESTION
		property.hint_string = ItemIds.ids_csv()
