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
## It can be SHOT TO PIECES too. The panel's blocker (DoorPivot/DoorBody) carries scripts/components/door_panel.gd,
## which forwards every take_damage() a gun round / fired projectile / blast lands on it up to take_damage() here:
## `max_hp` drains, the player's top-centre enemy health bar shows the door's HP exactly as it shows an NPC's
## (attacker.on_damaged_target — the same seam Character.take_damage pushes), and at 0 the panel + blocker are freed
## (the doorway is clear for everyone, lock or no lock), a break_sound / break_effect play, and a one-shot noise
## pulse on the &"noise" channel draws listening NPCs to investigate. MELEE swings thud off by default
## (`melee_can_damage`); damage_trace.run_pellet consults the panel's blocks_melee_damage() before applying a swing.
## The "destroyed" bit persists beside open/locked in the world_objects ledger; partial damage does not.
##
## NOTE: extends LookAtInteractable (an Area3D), not StaticBody3D — the physical block lives on the child
## StaticBody3D under the pivot. That's what lets a door be both a solid blocker AND an Interact target, since
## the interaction ray detects the talk-layer Area, not the world-layer body.

signal opened
signal closed
## A hit landed on the panel: its HP after the hit and its max. Mirrors Character.damaged for a HUD/quest listener.
signal damaged(hp: float, max_hp: float)
## The panel broke (0 HP). Same signal name CanDestroy / Throwable emit, so a child SpawnOnDestroy drops loot from a
## door too. Emitted AFTER the destroyed pose is applied (pivot freed, prompt off) and the ledger written.
signal destroyed

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

@export_group("Durability")
## Can this door be shot to pieces at all? ON: every gun round, fired projectile and blast that lands on the panel
## takes `max_hp` down, and at 0 the panel (mesh + blocker) is destroyed — the doorway is simply clear, for the player
## AND for NPCs, whatever the lock said (no key, no pick — bring a bigger gun). OFF: shots spark off it forever (a
## blast door). Needs the prefab's DoorPivot/DoorBody to carry door_panel.gd (a config warning says so if not).
@export var destructible: bool = true
## Hit points. Damage arrives already scaled (weapon damage x the shooter's stats / perks / difficulty), so read it in
## rounds: 60 = a handful of pistol shots or a shotgun blast or two. NOT persisted — a chipped door is whole again
## after a reload; only a BROKEN door stays broken (via `save_id` / the ledger, like a destroyed CanDestroy).
@export var max_hp: float = 60.0
## Let MELEE swings (a knife, fists, a bat) damage the door too? OFF by default: a swing thuds off the panel (impact
## sound + spark, no HP lost) and only guns / projectiles / explosions break it. A THROWN knife is a projectile hit.
@export var melee_can_damage: bool = false
## Optional one-shot played at the panel on EVERY hit, on top of the weapon's own generic impact. Null = none.
@export var hit_sound: AudioStream
## One-shot played at the panel when it breaks — the crash the player hears. Null = silent to the PLAYER (NPCs still
## hear the noise pulse below).
@export var break_sound: AudioStream
## Optional VFX scene spawned where the panel stood when it breaks (a splinter burst). A GPUParticles3D root is
## started and frees itself when finished; anything else is left to clean itself up. Null = none.
@export var break_effect: PackedScene
## How far (m) the break is HEARD by NPCs: a one-shot NoiseSource pulse on the shared &"noise" channel at the door,
## so an unaware guard within this radius comes to investigate (after their hearing reaction time) — the same
## channel gunfire and a thrown decoy use. 0 = silent to NPCs. Needs NpcAiSettings.hearing_initiates (on as shipped).
@export var break_noise_radius: float = 20.0
## Seconds the break noise stays audible at full radius. Keep it ABOVE NpcAiSettings.distraction_scan_interval
## (0.3 s as shipped), or an NPC's periodic scan can fall entirely between the crash and its expiry and miss it.
@export var break_noise_lifetime: float = 0.5

@export_group("Look")
## Drop a texture here to skin the panel: every MeshInstance3D under the pivot gets a StandardMaterial3D with this
## as its albedo (nearest-filtered, matching the TrenchBroom door materials). Previews live in the editor. Clear it
## to put back whatever material the panel wore before (stashed on the generated material, so it survives a save).
@export var texture: Texture2D: set = _set_texture
## Multiplies the texture (white = as authored) — a red door from the same texture. Only read while `texture` is set.
@export var texture_tint: Color = Color.WHITE: set = _set_texture_tint

@export_group("Save")
## OPTIONAL stable id so this door's open/locked/destroyed state survives a save/load AND node renames/moves. Leave
## blank for the level+path+position fallback (fine for a door that never moves — see WorldSaveId); set it on
## important hand-placed doors. Only doors actually opened/closed/unlocked/broken at least once are written to the ledger.
@export var save_id: StringName = &""

## Live hit points. Seeded from max_hp here (so an off-tree instance is whole) and again in _ready (the authored
## value lands after this initialiser runs). Read by value only — the HUD bar never retains us.
var hp: float = max_hp
var _destroyed: bool = false
## Code-built at runtime (like an NPC's): the one-shot &"noise" burst the break pulses. Null off-tree / in-editor.
var _noise: NoisePulser = null
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
		_apply_texture()  # the one runtime thing the editor previews: the panel's texture skin
		return  # @tool: skip the talk-layer/outline setup in-editor (only _get_configuration_warnings runs)
	super()  # LookAtInteractable._ready: talk-layer hitbox + look-at outline
	hp = max_hp
	_apply_texture()
	_build_noise()
	if pivot != null:
		_closed_yaw = pivot.rotation.y
		_cache_area_hitbox_transforms()
		if start_open:
			_open = true
			_set_pivot_yaw(_closed_yaw + deg_to_rad(open_angle))
	# Restore saved open/locked state OVER the authored defaults (GameState.world_objects). Runs in _ready like the
	# Corpse-discovery restore; current_level_path is already set by GameRoot before the level subtree's _ready.
	var st := GameState.object_state(GameState.current_level_path, _save_key())
	# A door broken earlier this run stays broken: apply the destroyed pose SILENTLY (no crash, no noise, no FX) and
	# skip the lock / swing / open restore — there is no panel left for any of it to pose.
	if GameState.as_bool(st.get("destroyed", false)):
		_destroyed = true
		_apply_destroyed_pose()
		return
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
	return not _destroyed  # a broken frame has nothing to open (its talk-layer hitbox is off too — see _apply_destroyed_pose)

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
	if _destroyed:
		return true  # no panel left to be in anyone's way (nothing bumps it either — the blocker is gone)
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
	if _open or _destroyed:
		return  # a broken door has no panel to swing (and must not write "open" over its "destroyed" ledger entry)
	_open = true
	_open_sign = side
	_swing_to(_closed_yaw + _open_yaw_offset())
	_persist()  # a successful unlock flows through toggle()->open/close, so this also captures the locked flip
	opened.emit()

func close() -> void:
	if not _open or _destroyed:
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
	# record_object_state REPLACES the entry, so every bit rides in every write — "destroyed" included (else any
	# later open/close write would silently resurrect a broken door on reload).
	GameState.record_object_state(GameState.current_level_path, _save_key(), {"open": _open, "locked": locked_bit, "swing": _open_sign, "destroyed": _destroyed})

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

# --- Durability: shoot the door down (door_panel.gd forwards the blocker's hits here) ---

## A hit landed on the panel. Signature mirrors Character / CanDestroy.take_damage so DamageApplier's 3-arg dynamic
## call, ExplosionArea's blast and a 4-arg hitscan call all land unchanged (the panel script forwards them verbatim).
## Damage arrives already scaled by the shooter (weapon x stats x perks x difficulty — damage_trace / projectile);
## there is no armour here, a door is not a Character. Pushes the attacker's enemy-health readout the way
## Character.take_damage does (on_damaged_target, duck-typed: only the Player implements it, so an NPC's stray round
## costs one has_method), with the PRE-hit HP so the bar draws its chip shard. Ignored while indestructible / broken.
## The melee gate is NOT here: a swing never reaches take_damage — damage_trace.run_pellet stops it at the panel
## (DamageApplier.blocks_melee), which is what keeps the swing's own impact sound and spark.
func take_damage(amount: float, _was_crit: bool = false, attacker: Node = null, _hit_pos: Vector3 = Vector3.INF) -> void:
	if _destroyed or not destructible or amount <= 0.0:
		return
	var hp_before := hp
	hp = maxf(0.0, hp - amount)
	damaged.emit(hp, max_hp)
	if hit_sound != null and is_inside_tree():
		AudioManager.play_sfx(_panel_position(), hit_sound)
	# Validity first (house rule): a projectile's shooter can be freed mid-flight; projectile.gd collapses that to
	# null before calling us, but a future caller might not.
	if attacker != null and is_instance_valid(attacker) and attacker != self and attacker.has_method(&"on_damaged_target"):
		attacker.call(&"on_damaged_target", self, hp, max_hp, hp_before)  # runs BEFORE the break so the bar shows the final 0
	if hp <= 0.0:
		_break()

func is_destroyed() -> bool:
	return _destroyed

## The break: FX + crash SFX + the NPC-audible noise pulse (all in-tree only), then the destroyed pose, the ledger
## write and the signal. Latched by _destroyed so a multi-pellet lethal frame (a shotgun) breaks it exactly once.
func _break() -> void:
	if _destroyed:
		return
	_destroyed = true
	if is_inside_tree():
		var at := _panel_position()
		if break_effect != null:
			var fx := break_effect.instantiate()
			if fx != null:  # empty-PackedScene reimport transient -> instantiate() can return null; skip, don't crash
				get_tree().root.add_child(fx)
				if fx is Node3D:
					(fx as Node3D).global_position = at
				if fx is GPUParticles3D:
					(fx as GPUParticles3D).emitting = true
					(fx as GPUParticles3D).finished.connect(fx.queue_free)
		if break_sound != null:
			AudioManager.play_sfx(at, break_sound)
		if _noise != null:
			_noise.lifetime = break_noise_lifetime
			_noise.pulse(break_noise_radius)  # a one-shot NoiseSource at the door: listening NPCs come to look
	_apply_destroyed_pose()
	_persist()
	destroyed.emit()

## What a broken door IS, applied both on the live break and on a reload that restores the "destroyed" bit: the
## pivot (mesh + blocker) is freed so the doorway is physically clear, the look-at hitbox leaves the talk layer so
## the interaction ray finds nothing (no "Open door" prompt on a splintered frame), and the outline's mesh list is
## dropped (it pointed into the freed panel). queue_free, never free: a live break runs inside a physics callback
## (the pellet trace / a projectile's body_entered) on the very body being removed.
func _apply_destroyed_pose() -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()
	if pivot != null:
		pivot.queue_free()
		pivot = null
	_area_hitbox_rest_transforms.clear()
	_meshes.clear()
	collision_layer = 0

## Where the panel stands right now, in world space (the blocker's collision shape, else the first mesh, else the
## hinge) — where the hit / break sounds and the splinter FX play. Falls back to our own position off-panel.
func _panel_position() -> Vector3:
	if pivot != null and pivot.is_inside_tree():
		return pivot.to_global(_panel_point_in_pivot())
	return global_position if is_inside_tree() else Vector3.ZERO

## Build the noise pulser the break fires through (the NPC idiom: code-built, tuned by the host's exports). Runtime
## only — _ready's editor branch never reaches here, and an off-tree door (a unit test) has no _ready at all.
func _build_noise() -> void:
	_noise = NoisePulser.new()
	_noise.name = "BreakNoise"
	_noise.radius = break_noise_radius
	_noise.lifetime = break_noise_lifetime
	add_child(_noise)

# --- Look: skin the panel with a texture (editor-previewed) ---

## Marks a material THIS door generated for `texture`, so a re-apply updates it in place instead of stacking a new
## one per edit, and a clear knows it may remove it.
const TEXTURE_MAT_META := &"door_texture_material"
## Where the generated material stashes the override the panel wore BEFORE (the prefab's grey placeholder), so
## clearing `texture` puts it back — even after a save/reload, since resource metadata is serialized with it.
const AUTHORED_MAT_META := &"door_authored_material"

func _set_texture(v: Texture2D) -> void:
	texture = v
	_apply_texture()

func _set_texture_tint(v: Color) -> void:
	texture_tint = v
	_apply_texture()

## Apply (or clear) the texture skin on every MeshInstance3D under the pivot. No-op with no pivot yet — the setter
## fires while the scene is still instantiating (children not built), and _ready applies once they are. With no
## texture set and no generated material present it touches nothing, so an untextured door never dirties its scene.
func _apply_texture() -> void:
	if pivot == null:
		return
	for m in pivot.find_children("*", "MeshInstance3D", true, false):
		var mi := m as MeshInstance3D
		var cur := mi.material_override
		var ours := cur != null and cur.has_meta(TEXTURE_MAT_META)
		if texture == null:
			if ours:
				mi.material_override = cur.get_meta(AUTHORED_MAT_META, null) as Material  # back to the authored look
			continue
		var mat: StandardMaterial3D = cur as StandardMaterial3D if ours else null
		if mat == null:
			mat = StandardMaterial3D.new()
			mat.set_meta(TEXTURE_MAT_META, true)
			if cur != null:
				mat.set_meta(AUTHORED_MAT_META, cur)
			# Match tb_materials/textures/door*.tres: crunchy nearest sampling, no specular sheen.
			mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS
			mat.metallic_specular = 0.0
		mat.albedo_texture = texture
		mat.albedo_color = texture_tint
		mi.material_override = mat

## Does any body under the pivot forward hits (door_panel.gd's take_damage)? Without one a destructible door can
## never be hurt: shots land on a bare StaticBody3D that has no take_damage to call. Edit-time safe.
func _panel_takes_damage() -> bool:
	if pivot == null:
		return false
	for b in pivot.find_children("*", "StaticBody3D", true, false):
		if b.has_method(&"take_damage"):
			return true
	return false

func _get_configuration_warnings() -> PackedStringArray:
	var warnings := PackedStringArray()
	if destructible and pivot != null and not _panel_takes_damage():
		warnings.append("`destructible` is ON but no StaticBody3D under the pivot can take a hit, so shots can never hurt this door. The prefab's DoorPivot/DoorBody carries res://scripts/components/door_panel.gd (it forwards take_damage to this Door) — re-attach that script to the blocker body, or turn `destructible` off.")
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
