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

const TRIGGER_RADIUS: float = 1.2  ## radius (m) of the loot interaction hitbox at the death spot

## The dead NPC's items, copied here so freeing the NPC can't affect the loot. Public — LootScreen and the
## talk-handler methods below read it.
var inventory: CharacterInventory
var corpse_name: String = ""   ## the dead NPC's display name, for the "Loot X" hover readout
var _follow_bones: Array = []  ## host ragdoll's PhysicalBone3D nodes (empty for a free-standing corpse)

func _ready() -> void:
	super()  # talk-layer hitbox + look-at outline over the host body (the skeleton)
	# Our own interaction hitbox: a sphere at the death spot (the base sets the layer/outline, not a shape).
	var shape := CollisionShape3D.new()
	var sph := SphereShape3D.new()
	sph.radius = TRIGGER_RADIUS
	shape.shape = sph
	add_child(shape)
	# Track the host ragdoll's physical bones so the hitbox FOLLOWS the crumpling body each frame: the ragdoll
	# root stays put at the death spot while the bones flop + settle metres away, so a fixed sphere at the root
	# never lines up with the visible skeleton. A free-standing corpse (no ragdoll) has no bones, so it stays put.
	var host := _host()
	if host != null:
		_follow_bones = host.find_children("*", "PhysicalBone3D", true, false)

## Keep the interaction hitbox centred on the actual (settled) skeleton: snap to the bones' centroid each
## frame. No-op for a free-standing corpse (no bones to follow) — it stays where NPC._drop_loot placed it.
func _physics_process(_delta: float) -> void:
	if not _follow_bones.is_empty():
		global_position = _follow_center()

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

## Copy `source`'s stacks into our own backpack and remember the dead NPC's name. Call right after .new()
## (the loot inventory child is built here); the corpse can then be added to the world and positioned.
func setup(source: CharacterInventory, who: String) -> void:
	corpse_name = who
	if inventory == null:
		inventory = CharacterInventory.new()
		inventory.name = "Loot"
		add_child(inventory)
	if source != null:
		for s in source.contents():
			inventory.add(s["item"], s["count"])

# --- Behaviour (talk-handler surface) ---

## E pressed while aimed at the corpse: open the loot transfer screen (NOT a conversation).
func start_talk(player: Node) -> void:
	LootScreen.open_for(self, player)

## Lootable only while it still holds something — an emptied corpse stops highlighting and won't reopen.
func can_be_talked_to() -> bool:
	return inventory != null and not inventory.is_empty()

## HUD readout when aimed at: "Loot <name>" (or just "Loot" if the NPC was unnamed).
func look_name() -> String:
	return "Loot %s" % corpse_name if not corpse_name.is_empty() else "Loot"
