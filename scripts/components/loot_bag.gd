@tool  # base Throwable is @tool; match it so the editor runs our _ready consistently (our loot hook is runtime-guarded)
class_name LootBag
extends Throwable

## A dead actor's loot, dropped as a physics BAG. It IS a Throwable — a real rigid body — so it falls
## and rests on the floor on its own (gravity, no manual snapping) and can be picked up / kicked / thrown
## like any prop. GoreSpawner spawns it into the enemy's `ragdoll_scene` slot and attaches a LootableCorpse
## child holding a COPY of the dead actor's backpack + wallet. That makes the bag a "DUAL ITEM", exactly
## like a dropped weapon (a Throwable + a CanPickUp): aim at it and press Interact to LOOT it (the
## LootableCorpse handler), or the Throw key to GRAB it and carry/throw it. PickupRay tells the two apart by
## is_ancestor_of — the loot handler is our child, so Interact runs the loot instead of a physical grab.
##
## Everything that makes it feel physical — collider auto-fit to the mesh, the hover outline, impact
## sounds, carry/throw — is inherited from Throwable; the ONLY thing this subclass adds is the loot-spawn
## gate below. Keep `destructible = false` on the scene so a stray shot can't burst the bag and lose the
## loot (dropped-weapon dual items do the same). Assign scenes/props/loot_bag.tscn to `ragdoll_scene`.

## When true, GoreSpawner skips spawning this bag entirely if the dying actor has nothing to loot — no
## items AND no cash — so an empty-handed kill leaves no bag (the bag IS the loot container, so an empty
## one is pointless). Turn OFF to always drop a bag. Read by GoreSpawner._spawn_ragdoll off the instance
## (via get()) before it enters the tree; a plain Throwable lacks it (null -> false) and so always spawns.
@export var spawn_only_with_loot: bool = true

## The LootableCorpse GoreSpawner attaches as our child — a COPY of the dead actor's backpack + wallet, set
## (corpse.set(&"loot", …)) before we enter the tree. We watch its inventory so the bag frees ITSELF once
## drained (below). Null when the actor carried nothing to loot (no loot child, so nothing to empty).
var loot: LootableCorpse = null

## Free the whole bag once it's looted empty, so an emptied bag disappears instead of littering the floor.
## When the last item (or the wallet) leaves, the LootableCorpse's inventory `changed` fires — the wallet
## take routes through LootableCorpse.on_wallet_drained — and can_be_talked_to() flips false. Mirrors
## Ragdoll's linger-until-looted; LootScreen deliberately leaves the free to us (it skips freeing a corpse
## whose host is a LootBag, exactly as it does for a Ragdoll), so the bag AND its loot child go together
## instead of stranding an empty bag.
func _ready() -> void:
	super._ready()  # Throwable: collider auto-fit, physics, hover outline, carry/throw
	if is_instance_valid(loot) and loot.inventory != null:
		loot.inventory.changed.connect(_on_loot_changed)

func _on_loot_changed() -> void:
	if is_instance_valid(loot) and not loot.can_be_talked_to():
		queue_free()
