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

## Drives the `requires_item_id` dropdown from the item ids on disk (const-preloaded — see item_ids.gd).
const ItemIds = preload("res://scripts/items/item_ids.gd")
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
## Starts locked? A locked door won't open on Interact until it's unlocked (by a child Lock, a key, or a flag).
@export var locked: bool = false
## OPTIONAL key: an inventory Item.id that unlocks this door on Interact. Empty = no key (use a flag or a Lock child).
@export var requires_item_id: StringName = &""
## Consume the key on a successful unlock (true) or keep it as a reusable key (false).
@export var consume_key: bool = false
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
		locked = GameState.as_bool(st["locked"], locked)
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
		return "[PH] Locked"
	return "[PH] Close door" if _open else "[PH] Open door"

## Unlock attempt: a child Lock (if present) owns it; else an unlock_flag that's set; else the keyed-item gate.
## Returns true if the door is now unlocked (and flips `locked` off).
func _try_unlock(player: Node) -> bool:
	var gate := BuildGate.of(self)
	if gate != null and not gate.passes(player):
		if player != null and player.has_method(&"notify_toast"):
			player.notify_toast(gate.deny_reason(player), Color(1.0, 0.55, 0.4))
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
	if requires_item_id != &"":
		var inv: Variant = player.get(&"inventory") if player != null else null
		var ci := inv as CharacterInventory  # null if inv isn't a CharacterInventory — capture once, guard on != null
		var key: Item = ci.find_by_id(requires_item_id) if ci != null else null
		if key != null:
			if consume_key:
				ci.remove(key, 1)
			locked = false
			if player != null and player.has_method(&"notify_toast"):
				player.notify_toast("[PH] Unlocked", Color(0.4, 1.0, 0.45))
			return true
		if player != null and player.has_method(&"notify_toast"):
			player.notify_toast("[PH] Locked — requires %s" % _key_label(), Color(1.0, 0.55, 0.4))
		return false
	# Locked with no Lock / flag / key authored: a dead bolt the player can't pick.
	if player != null and player.has_method(&"notify_toast"):
		player.notify_toast("[PH] Locked", Color(1.0, 0.55, 0.4))
	return false

func _is_unlocked_by_flag() -> bool:
	return unlock_flag != &"" and GameState.get_flag_bool(unlock_flag)

func _key_label() -> String:
	for it in ItemDb.all_items():
		if it != null and it.id == requires_item_id:
			return it.label()
	return String(requires_item_id).capitalize()

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
	GameState.record_object_state(GameState.current_level_path, _save_key(), {"open": _open, "locked": locked})

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
	if pivot == null:
		return PackedStringArray(["Door has no `pivot` assigned — open/close will do nothing. Assign the DoorPivot child (the node holding the mesh + StaticBody3D blocker)."])
	return PackedStringArray()

## Self-populate the `requires_item_id` key dropdown from the item ids on disk (a SUGGESTION, still typable).
func _validate_property(property: Dictionary) -> void:
	if property.name == "requires_item_id":
		property.hint = PROPERTY_HINT_ENUM_SUGGESTION
		property.hint_string = ItemIds.ids_csv()
