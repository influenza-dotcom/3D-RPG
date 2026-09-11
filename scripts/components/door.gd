@tool
class_name Door
extends LookAtInteractable

## A drop-in DOOR: aim + Interact to swing it open/closed, or drive it from a TriggerVolume / switch / cutscene
## via open() / close() / toggle(). Built on LookAtInteractable (the aim-at-and-Interact base, so it gets the
## look-at outline + the Interact hookup for free) with a child PIVOT that holds the door's mesh AND its
## StaticBody3D blocker — swinging the pivot moves the panel (and its collision) out of the doorway, so an open
## door simply isn't in the way. Locking reuses a child Lock component if present, OR the built-in key / flag gate.
##
## NPCs open it too, by WALKING INTO it. Levels keep every Door OUTSIDE the `navmesh` bake source, so the bake runs
## straight through the doorway and A* already routes NPCs through it; the closed panel's StaticBody3D is the only
## thing in the way. When an NPC's body presses into that panel, npc.gd `_open_bumped_doors` resolves this door with
## of_collider() and calls npc_try_open(). That path is READ-ONLY on the lock (a locked door stays a wall to NPCs) and
## swings the panel AWAY from the NPC (npc_swing_away), so it never sweeps through the body that opened it.
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
## How far of_collider() walks UP from a hit body looking for its Door. The prefab's blocker sits at
## Door/DoorPivot/DoorBody (2 hops); the slack covers a designer nesting the panel a node or two deeper.
const COLLIDER_SEARCH_DEPTH := 4
## swing_sign_away's tie band (squared metres): closer than this to equidistant keeps the authored side.
const SWING_TIE_EPSILON := 0.0001

@export_group("Swing")
## The node rotated when the door opens — it holds the door's mesh + its StaticBody3D blocker, so the whole
## panel swings out of the doorway. Assign the prefab's "DoorPivot". Without it, open/close are no-ops.
@export var pivot: Node3D
## Degrees around Y the pivot turns when open (negative swings the other way). This is the side the player's
## Interact, triggers and cutscenes always use; an NPC may swing it the mirror way (see npc_swing_away).
@export var open_angle: float = 90.0
## Seconds the open/close swing takes.
@export var open_duration: float = 0.5
## Start the level with this door already open.
@export var start_open: bool = false

@export_group("Lock")
## Starts locked? A locked door won't open on Interact until it's unlocked (by a child Lock, a key, a lockpick, or
## a flag). For richer locks (a keyed AND pickable safe on a container), drop a child `Lock` — it takes over and
## these built-in fields are ignored; these cover the common inline door lock. NPCs never open a locked door.
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

@export_group("NPCs")
## Can an NPC open this door by walking into it? ON (default): an NPC whose path runs through the doorway bumps the
## closed panel and it swings open (npc.gd `_open_bumped_doors` -> npc_try_open). A LOCKED door stays shut to NPCs
## regardless — they never unlock, pick, or spend a key. OFF = a door only the player works (a player-only shortcut);
## NPCs press against it and the Locomotor's give-up hold takes over, exactly as with a locked door.
@export var npc_can_open: bool = true
## When an NPC opens it, swing the panel AWAY from that NPC (whichever side that is) instead of always toward the
## authored open_angle side, so the panel never sweeps through the body that opened it. Turn OFF for a door that can
## only swing one way (hinged against a wall, a closet door that would clip into shelving).
@export var npc_swing_away: bool = true

@export_group("Save")
## OPTIONAL stable id so this door's open/locked state survives a save/load AND node renames/moves. Leave blank for
## the level+path+position fallback (fine for a door that never moves — see WorldSaveId); set it on important
## hand-placed doors. Only doors actually opened/closed/unlocked at least once are written to the ledger.
@export var save_id: StringName = &""

var _open: bool = false
## Which side the door stands open toward: +1 = the authored open_angle side, -1 = its mirror (an NPC swung it away
## from itself). Persisted beside open/locked as "swing", so a reload restores the panel on the side it actually stood.
var _open_sign: float = 1.0
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
	# The swing side must land BEFORE the open restore below poses the panel. Absent (a save from before NPCs opened
	# doors) = the authored side, which is what every such door was opened toward.
	if st.has("swing"):
		var swing: Variant = st["swing"]
		if swing is float or swing is int:
			_open_sign = -1.0 if float(swing) < 0.0 else 1.0
	if st.has("open"):
		_open = GameState.as_bool(st["open"], _open)
		if pivot != null:
			_set_pivot_yaw(_closed_yaw + (_open_yaw_offset() if _open else 0.0))

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
	if is_effectively_locked():
		return PlayerText.PROMPT_LOCKED
	return PlayerText.PROMPT_CLOSE_DOOR if _open else PlayerText.PROMPT_OPEN_DOOR

## Locked as everyone but the player's own unlock attempt sees it: the Door's own bolt (unless its unlock_flag is set)
## OR a still-locked child Lock. look_name shows "Locked" on exactly this, and NPCs refuse the door on it.
func is_effectively_locked() -> bool:
	var lk := Lock.of(self)
	return (locked and not _is_unlocked_by_flag()) or (lk != null and lk.locked)

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

# --- NPC surface: bump-to-open (npc.gd _open_bumped_doors) ---

## The Door that OWNS `collider` — the panel's StaticBody3D, as reported by a slide contact — or null. Walks up at most
## COLLIDER_SEARCH_DEPTH parents: a door's blocker always lives under its pivot, so a wall or floor body resolves to
## null in a few cheap hops. Null-safe.
static func of_collider(collider: Node) -> Door:
	var n := collider
	for _hop in COLLIDER_SEARCH_DEPTH + 1:
		if n == null:
			return null
		if n is Door:
			return n as Door
		n = n.get_parent()
	return null

## NPC entry point: open for an NPC that walked into the panel. READ-ONLY on the lock — an NPC never unlocks, picks,
## spends a key, or toasts, so a locked door stays a wall to NPCs and its lock state belongs to the player alone.
## Swings AWAY from `opener` when npc_swing_away is on (and the opener is in-tree to measure), else the authored side.
## Returns true when the door is (now) open, false when it refused.
func npc_try_open(opener: Node3D) -> bool:
	if _open:
		return true
	if not npc_can_open or pivot == null or is_effectively_locked():
		return false
	if npc_swing_away and opener != null and opener.is_inside_tree():
		open_away_from(opener.global_position)
	else:
		open()
	return true

# --- Drive externally (a TriggerVolume action / switch / cutscene): open() / close() / toggle() ---
func open() -> void:
	_open_toward(1.0)  # the authored open_angle side — the player's Interact, triggers, cutscenes

## Open toward whichever side leaves the panel FARTHER from `world_pos` (see swing_sign_away), so it never sweeps
## through whoever stands there. The NPC path uses it; a script may too. Falls back to the authored side when the
## panel can't be measured (off-tree, nothing with a position under the pivot).
func open_away_from(world_pos: Vector3) -> void:
	_open_toward(_swing_sign_away_from(world_pos))

## The one open path: `side` +1 = the authored open_angle side, -1 = its mirror.
func _open_toward(side: float) -> void:
	if _open:
		return
	_open = true
	_open_sign = side
	_swing_to(_closed_yaw + _open_yaw_offset())
	_persist()  # a successful unlock flows through toggle()->open/close, so this also captures the locked flip
	opened.emit()

func close() -> void:
	if not _open:
		return
	_open = false
	_swing_to(_closed_yaw)
	_persist()
	closed.emit()

## Persist this door's open/locked state (and its swing side) to the world-object ledger (keyed by level +
## save_id/fallback). No-op in the editor and off-tree, so a @tool preview or a bare unit test never mutates GameState.
## GameState.load_from_disk only shape-checks each entry as a Dictionary, so the extra "swing" float round-trips.
func _persist() -> void:
	if Engine.is_editor_hint() or not is_inside_tree():
		return
	# Persist the EFFECTIVE locked bit: for a Door with a child Lock the real state lives on the Lock (Door.locked
	# stays false), so save the Lock's; _ready restores it back onto the Lock. Without a child Lock this is Door.locked.
	var lk := Lock.of(self)
	var locked_bit := lk.locked if lk != null else locked
	GameState.record_object_state(GameState.current_level_path, _save_key(), {"open": _open, "locked": locked_bit, "swing": _open_sign})

func _save_key() -> String:
	return WorldSaveId.key_for(self, save_id)

func toggle() -> void:
	if _open:
		close()
	else:
		open()

func is_open() -> bool:
	return _open

## The open pose's yaw offset from closed: open_angle, on the side the door was opened toward (_open_sign).
func _open_yaw_offset() -> float:
	return deg_to_rad(open_angle) * _open_sign

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

## In-tree measure for open_away_from: brings the opener into the pivot's PARENT space — the frame rotation.y turns in.
## A non-uniformly scaled Door (the live level's is ~4 x 1.6 x 1) is fine: an affine map keeps a point on the same side
## of the panel, and that side is all swing_sign_away decides. +1 (the authored side) whenever it can't measure.
func _swing_sign_away_from(world_pos: Vector3) -> float:
	if pivot == null or not pivot.is_inside_tree():
		return 1.0
	var frame := pivot.get_parent() as Node3D
	if frame == null:
		return 1.0
	return swing_sign_away(pivot.position, _closed_yaw, deg_to_rad(open_angle), _panel_point_in_pivot(), frame.to_local(world_pos))

## A point on the swinging panel in the PIVOT's own frame: the first CollisionShape3D under the pivot (the blocker),
## else the first MeshInstance3D. ZERO when neither exists, which swing_sign_away reads as a tie (authored side).
## In-tree only (reads global positions).
func _panel_point_in_pivot() -> Vector3:
	var parts := pivot.find_children("*", "CollisionShape3D", true, false)
	if parts.is_empty():
		parts = pivot.find_children("*", "MeshInstance3D", true, false)
	if parts.is_empty():
		return Vector3.ZERO
	return pivot.to_local((parts[0] as Node3D).global_position)

## PURE swing-side pick. Every argument is in the pivot's PARENT space (the frame rotation.y turns in) except
## `panel_local`, a point on the panel in the pivot's own frame. Returns the sign of open_angle that leaves the panel
## FARTHER from `opener`: for |open_angle| <= 180 the swept sector lies wholly on the side the panel ends on, so "ends
## farther" means "never sweeps through the opener". A tie (opener on the closed plane, or a panel point on the hinge
## line) keeps the authored side, +1. Assumes the pivot only yaws (no pitch/roll/scale) — true of every authored door.
static func swing_sign_away(pivot_pos: Vector3, closed_yaw: float, open_angle_rad: float, panel_local: Vector3, opener: Vector3) -> float:
	var arm := Vector3(panel_local.x, 0.0, panel_local.z)
	var authored_end := pivot_pos + Basis(Vector3.UP, closed_yaw + open_angle_rad) * arm
	var mirror_end := pivot_pos + Basis(Vector3.UP, closed_yaw - open_angle_rad) * arm
	var to_authored := Vector2(authored_end.x - opener.x, authored_end.z - opener.z).length_squared()
	var to_mirror := Vector2(mirror_end.x - opener.x, mirror_end.z - opener.z).length_squared()
	return -1.0 if to_mirror > to_authored + SWING_TIE_EPSILON else 1.0

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
	# NPCs route THROUGH a doorway only because the bake never sees the closed panel. Under a navmesh-group node (the
	# bake's source) the blocker bakes into the mesh, the doorway erodes shut, and no NPC ever paths through it.
	if _inside_navmesh_source():
		warnings.append("This Door sits inside the navmesh bake source (it or an ancestor is in the `navmesh` group), so its closed panel bakes the doorway SHUT and NPCs will never path through it. Move the Door out from under the NavigationRegion3D / Geometry nodes (e.g. to the level root), then re-bake.")
	return warnings

## Is this door (or an ancestor) in the navmesh bake-source group? See the config warning above.
func _inside_navmesh_source() -> bool:
	var n: Node = self
	while n != null:
		if n.is_in_group(Groups.NAVMESH):
			return true
		n = n.get_parent()
	return false

## Self-populate the key / lockpick id dropdowns from the item ids on disk (SUGGESTIONs, still typable).
func _validate_property(property: Dictionary) -> void:
	if property.name == "key_item_id" or property.name == "lockpick_item_id":
		property.hint = PROPERTY_HINT_ENUM_SUGGESTION
		property.hint_string = ItemIds.ids_csv()
