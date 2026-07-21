class_name LootableCorpse
extends LookAtInteractable

## A dead body's loot + interaction hitbox. Copies the dead NPC's backpack and extends LookAtInteractable
## (the talk-layer surface + look-at outline over the body), so PickupRay detects it and E opens the
## LootScreen with ZERO changes to ray_cast.gd. start_talk opens the loot transfer, not a conversation.
## On top of the base it adds a SPHERE hitbox that follows the crumpling ragdoll.
##
## Normally attached as a CHILD of the dead NPC's ragdoll/skeleton (by GoreSpawner), so the player loots
## the body directly and the ragdoll LINGERS until this is emptied (ragdoll.gd gates its fade on it). An
## NPC with no ragdoll instead gets a free-standing one at the death spot (NPC._drop_loot). Built while
## the dead NPC's backpack still exists; setup() copies it so freeing the NPC can't drain the loot.

## radius (m) of the loot interaction hitbox at the death spot
@export var trigger_radius: float = 1.2

## The dead NPC's items, copied here so freeing the NPC can't affect the loot. Public — LootScreen and the
## talk-handler methods below read it.
var inventory: CharacterInventory
var corpse_name: String = ""   ## the dead NPC's display name, for the "Loot X" hover readout
## The dead NPC's WALLET (designer-set money + any kill bounties it earned in life) rides into the loot as a
## real zorkmids COIN TILE in `inventory` (seeded in setup), NOT a separate float / "Take N zm" button — so
## cash loots exactly like any other item and an otherwise-empty corpse stays lootable while the tile remains.
var _item_light: PickupBeacon = null   ## item light over the sack/body, sized by how much loot remains (hidden when empty)
var _follow_bones: Array = []  ## host ragdoll's PhysicalBone3D nodes (empty for a free-standing corpse)
var _settled: bool = false     ## once the ragdoll stops moving we stop the per-frame transform writes (it has settled)
var _settle_t: float = 0.0     ## seconds the centroid has stayed within SETTLE_EPSILON of its last position
var _recheck_t: float = 0.0    ## once settled, counts down to the next cheap drift re-check (re-arms a bumped corpse)

## How still (m of centroid drift per frame) and for how long (s) the ragdoll must be before we stop following.
const SETTLE_EPSILON: float = 0.01
const SETTLE_HOLD: float = 0.5
## How often (s) a SETTLED corpse re-checks its centroid, so a later bump (explosion / a pile-on) re-arms the follow.
const RESETTLE_CHECK: float = 0.5

func _ready() -> void:
	super()  # talk-layer hitbox + look-at outline over the host body (the skeleton)
	# A dead body is a lootable container too: join &"containers" so a nearby unarmed / under-armed NPC RAIDS it
	# for a better (or its first) gun via NpcScavenge -- exactly like a crate. An emptied corpse scores -INF, so
	# the raid skips it; when the ragdoll fades and frees this, it leaves the group automatically.
	add_to_group(Groups.CONTAINERS)
	# Our own interaction hitbox: a sphere at the death spot (the base sets the layer/outline, not a shape).
	var shape := CollisionShape3D.new()
	var sph := SphereShape3D.new()
	sph.radius = trigger_radius
	shape.shape = sph
	add_child(shape)
	# Track the host ragdoll's physical bones so the hitbox FOLLOWS the crumpling body each frame: the ragdoll
	# root stays put at the death spot while the bones flop + settle metres away, so a fixed sphere at the root
	# never lines up with the visible skeleton. A free-standing corpse (no ragdoll) has no bones, so it stays put.
	var host := _host()
	if host != null:
		_follow_bones = host.find_children("*", "PhysicalBone3D", true, false)
	# Item light: a colour-coded local glow over the sack / body. It rides us as a child (so it follows the settling
	# ragdoll, or sits on the dropped bag), scales with how MUCH is still inside, and hides once drained. `inventory`
	# is built in setup() before we're added, so it exists here; we re-size on every inventory `changed`.
	_item_light = PickupBeacon.attach_kind(self, PickupBeacon.Kind.LOOT_BAG)
	if inventory != null:
		inventory.changed.connect(_refresh_item_light)
	_refresh_item_light()

## Resize the item light to match how much the sack/body still holds (distinct stacks). Fired on every inventory
## change; a drained container reports 0 and the light parks itself hidden (the bag then frees; a ragdoll lingers).
func _refresh_item_light() -> void:
	if _item_light == null or not is_instance_valid(_item_light):
		return
	_item_light.set_item_count(inventory.contents().size() if inventory != null else 0)

## Keep the interaction hitbox centred on the actual (settled) skeleton: snap to the bones' centroid each
## frame. No-op for a free-standing corpse (no bones to follow) — it stays where NPC._drop_loot placed it.
func _physics_process(delta: float) -> void:
	if _follow_bones.is_empty():
		return
	if _settled:
		# Settled: skip the per-frame write, but re-check on a slow cadence so a LATER bump (an explosion knock,
		# another ragdoll piling on) re-arms the follow instead of stranding the hitbox at the stale centroid.
		_recheck_t -= delta
		if _recheck_t > 0.0:
			return
		_recheck_t = RESETTLE_CHECK
		if global_position.distance_to(_follow_center()) > SETTLE_EPSILON:
			_settled = false  # the body moved again — resume following from next frame
			_settle_t = 0.0
		return
	var center := _follow_center()
	# Once the ragdoll has stopped drifting for SETTLE_HOLD seconds, stop the per-frame transform writes:
	# an idle corpse keeps the same centroid, so following it every frame for the whole linger is pure waste.
	if global_position.distance_to(center) <= SETTLE_EPSILON:
		_settle_t += delta
		if _settle_t >= SETTLE_HOLD:
			_settled = true
			_recheck_t = RESETTLE_CHECK
	else:
		_settle_t = 0.0
	global_position = center

## The point the hitbox should sit at: the average global position of the followed physical bones (the body's
## rough centre of mass), or our current position when there are no bones to follow.
func _follow_center() -> Vector3:
	var center := Vector3.ZERO
	var n := 0
	for b in _follow_bones:
		if is_instance_valid(b):
			center += (b as Node3D).global_position
			n += 1
	return center / float(n) if n > 0 else global_position

## Copy `source`'s stacks into our own backpack, remember the dead NPC's name, and pocket its wallet. Call
## right after .new() (the loot inventory child is built here); the corpse can then be added + positioned.
func setup(source: CharacterInventory, who: String, wallet: float = 0.0) -> void:
	corpse_name = who
	if inventory == null:
		inventory = CharacterInventory.new()
		inventory.name = "Loot"
		add_child(inventory)
	if source != null:
		for s in source.contents():
			inventory.add(s["item"], s["count"])
	# Seed the dead NPC's wallet as a real zorkmids COIN TILE (one unit = one QUANTUM, so a fractional wallet
	# stays exact — see Zorkmids / MoneyPurse). Added while the bag's grid is still OFF (unbounded), so it always
	# lands; the loot screen grids the copy on open. Taking the tile credits the player via LootScreen._take's
	# zorkmids branch (Character.add_money), same as looting the ground / a shop refund.
	if wallet > 0.0:
		var coin := ItemDb.item_by_id(Zorkmids.ITEM_ID)
		if coin != null:
			inventory.add(coin, int(round(wallet / Zorkmids.QUANTUM)))

# --- Behaviour (talk-handler surface) ---

## E pressed while aimed at the corpse: open the loot transfer screen (NOT a conversation).
func start_talk(player: Node) -> void:
	LootScreen.open_for(self, player)

## Lootable only while it still holds something. Cash is now a coin TILE in the bag (setup seeds it), so an
## items-empty check covers both items AND money — a fully drained corpse stops highlighting and won't reopen.
## Taking the last tile fires inventory.changed, which the ragdoll's linger-until-drained fade already watches.
func can_be_talked_to() -> bool:
	return inventory != null and not inventory.is_empty()

## HUD readout when aimed at: "Loot <name>" while there's anything TO loot — the player's readout then
## prefixes the interact key ("[E] Loot Kyle"), since the key hint only shows for actionable targets. Once
## EMPTIED, just the bare name: the readout deliberately follows non-actionable targets too (like a hostile
## NPC's name), and an emptied corpse advertising "Loot" with no key was the misleading state.
func look_name() -> String:
	if not can_be_talked_to():
		return corpse_name  # emptied — nothing to loot, so no verb and no key hint
	return "Loot %s" % corpse_name if not corpse_name.is_empty() else "Loot"
