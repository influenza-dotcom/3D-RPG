class_name NpcMortality
extends Node

## The NPC's death WORLD-SPAWNS, split off npc.gd: on death leave (a) a lootable corpse holding the backpack +
## wallet and (b) an invisible discoverable Corpse marker for stealth body-discovery, and award the player kill-XP.
## The ORCHESTRATION (assist-thanks, faction souring, kill-quest, freeze-frame, witness barks) stays on NPC._on_died,
## which calls these in its authored order via thin facades (_drop_loot / _award_kill_xp / _spawn_corpse_marker).
## Rolling the loot table INTO the backpack (NPC._roll_loot) stays on NPC too — it runs pre-death in gore() and is
## unit-tested off-tree, so it never left the root.
##
## host is Node-typed to break the NpcMortality <-> NPC class cycle, so every host member is read DYNAMICALLY (a
## rename of one of those npc.gd/Character members fails at RUNTIME, not compile — see scripts/npc/README.md). Every
## method spawns into the world and guards is_inside_tree, so on an off-tree unit-test NPC — where this component is
## never built and NPC's facades no-op — behaviour is exactly the monolith's.

var host: Node = null

## Leave a lootable corpse at the death spot holding a copy of our backpack — a PERSISTENT node (not the fading
## ragdoll) the player loots with E. Skipped when a ragdoll already carries the loot, when the bag AND wallet are
## both empty, or off-tree. Spawned into our PARENT (the world), not under us, since the NPC is about to queue_free.
func drop_loot() -> void:
	# A skeleton corpse already carries the loot directly (GoreSpawner attaches a LootableCorpse to the ragdoll),
	# so only drop a free-standing lootable corpse for an NPC that has NO ragdoll to loot.
	if host.ragdoll_scene != null:
		return
	if not host.is_inside_tree():
		return
	# Drop a corpse when there's ANYTHING to loot — items OR the wallet (an empty-bagged NPC with zorkmids must
	# still leave a lootable body, or its cash is buried with it).
	if (host.inventory == null or host.inventory.is_empty()) and host.money <= 0.0:
		return
	var world := host.get_parent()
	if world == null:
		return
	var corpse := LootableCorpse.new()
	# "Loot <name>" shows what the player KNOWS at the moment of death: their real name if they'd introduced
	# themselves, else "Stranger" (GameState.public_name). A body you never learned the name of stays a Stranger.
	corpse.setup(host.inventory, GameState.public_name(host.display_name), host.money)
	world.add_child(corpse)
	corpse.global_position = host.global_position

## Grant the player XP for the kill — a global flat amount (GameSettings.xp.xp_per_kill), routed to the live HUMAN
## player via host._real_player() so it lands on any player-caused kill. No-op if xp_per_kill is 0 or no player is in the tree.
func award_kill_xp() -> void:
	var amount: float = GameSettings.xp.xp_per_kill
	if amount <= 0.0 or not host.is_inside_tree() or host.get_tree() == null:
		return
	var player = host._real_player()  # plain = : a dynamic host call returns Variant (no := inference off a Node-typed host)
	if player != null and player.has_method(&"add_xp"):
		player.add_xp(amount)

## Stealth body-discovery: leave an invisible, discoverable Corpse marker at the death spot (separate from any
## ragdoll / LootableCorpse) so a nearby UNAWARE NPC can NOTICE the death and investigate. Off by default
## (host._body_discovery_on()) -> nothing spawns, so stealth kills stay free until the designer opts in. Spawned into
## our PARENT (the world), since the NPC is about to queue_free.
func spawn_corpse_marker() -> void:
	if not host._body_discovery_on():
		return
	if not host.is_inside_tree():
		return
	var world := host.get_parent()
	if world == null:
		return
	var marker := Corpse.new()
	marker.who = host.display_name
	world.add_child(marker)
	marker.global_position = host.global_position
