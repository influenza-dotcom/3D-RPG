class_name LootableCorpse
extends Area3D

## A dead body's loot + interaction hitbox. Copies the dead NPC's backpack and reuses the look-at talk
## plumbing verbatim: an Area3D on TalkHelpers.TALK_LAYER exposing the talk-handler surface (start_talk /
## can_be_talked_to / set_look_highlight / look_name / host_npc), so PickupRay detects it and E opens the
## LootScreen with ZERO changes to ray_cast.gd. start_talk opens the loot transfer, not a conversation.
##
## Normally attached as a CHILD of the dead NPC's ragdoll/skeleton (by GoreSpawner), so the player loots
## the body directly and the ragdoll LINGERS until this is emptied (ragdoll.gd gates its fade on it). An
## NPC with no ragdoll instead gets a free-standing one at the death spot (NPC._drop_loot). Built while
## the dead NPC's backpack still exists; setup() copies it so freeing the NPC can't drain the loot.

const TRIGGER_RADIUS: float = 1.2  ## radius (m) of the loot interaction hitbox at the death spot

## The dead NPC's items, copied here so freeing the NPC can't affect the loot. Public — LootScreen and the
## talk-handler methods below read it.
var inventory: CharacterInventory
var corpse_name: String = ""   ## the dead NPC's display name, for the "Loot: X" hover readout

func _ready() -> void:
	# A look-at hitbox only: sit on the talk layer (the ray's areas-only query masks it) and sense nothing.
	collision_layer = TalkHelpers.TALK_LAYER
	collision_mask = 0
	var shape := CollisionShape3D.new()
	var sph := SphereShape3D.new()
	sph.radius = TRIGGER_RADIUS
	shape.shape = sph
	add_child(shape)

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

# --- Talk-handler surface (mirrors Talkable so PickupRay treats the corpse as a look-at target) ---

## E pressed while aimed at the corpse: open the loot transfer screen (NOT a conversation).
func start_talk(player: Node) -> void:
	LootScreen.open_for(self, player)

## Lootable only while it still holds something — an emptied corpse stops highlighting and won't reopen.
func can_be_talked_to() -> bool:
	return inventory != null and not inventory.is_empty()

## HUD readout when aimed at: "Loot: <name>" (or just "Loot" if the NPC was unnamed).
func look_name() -> String:
	return "Loot: %s" % corpse_name if not corpse_name.is_empty() else "Loot"

## No NPC behind a corpse — the FNV hover then won't try to greet / disposition-tint it (player.gd
## null-guards host_npc()).
func host_npc() -> NPC:
	return null

## Look-at highlight toggle. The corpse owns no mesh (the ragdoll is the visual and it fades), so this is
## a no-op; the name readout is the feedback. Kept to satisfy the talk-handler contract.
func set_look_highlight(_on: bool) -> void:
	pass
