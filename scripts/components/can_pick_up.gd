@tool
class_name CanPickUp
extends LookAtInteractable

const ModelResourceUtil = preload("res://scripts/components/model_resource.gd")
const WorldSaveId = preload("res://scripts/world/world_save_id.gd")  # stable per-object save key (GameState.world_objects)

## Drop-in PICKUP component: aim at the object and press E (Interact) to add a configured Item to your
## inventory. Extends LookAtInteractable (the talk-layer hitbox + look-at outline); this adds only the
## pickup behaviour, so PickupRay detects it with ZERO changes to ray_cast.gd, like Talkable / LootableCorpse.
##
## SETUP: drop this under the visible object (or assign highlight_target), size its CollisionShape3D to
## cover the body you aim at, and set `item`. On pickup it grants the item to the player's backpack and
## frees the host (highlight_target, else our parent).

@export_group("Payload")
## the item granted on pickup (e.g. a weapon-item)
@export var item: Item:
	set(value):
		item = value
		update_configuration_warnings()
@export var amount: int = 1                ## how many of `item` to grant (weapons add as that many unique instances)
## EASY count-based PILE: grab a small mix in one pickup ("2 stims + 10 ammo") as rows (item + count), granted
## ON TOP of `item` + the loot table. Weapons become unique instances per count. Leave empty for a single-item pickup.
@export var item_stacks: Array[ItemStack] = []
## OPTIONAL drop table granted ON TOP of `item` when picked up — turns this into a "loot bag" of random
## items. Null = just `item`. Can be set WITHOUT an item, for a pure random-loot pickup.
@export var loot_table: LootTable = null

@export_group("Hover Label")
## Name shown on the look-at hover; blank -> "Take <item name>".
@export var pickup_label: String = ""

@export_group("Item Light")
## Add a small colour-coded light to this pickup. The colour is derived from the item's kind (weapon / ammo /
## consumable / passive / chip), or LOOT_BAG for a pure loot-table cache. Turn OFF for a bespoke pickup that
## shouldn't glow (a large authored prop, a hidden stash). See scripts/components/pickup_beacon.gd +
## GameSettings.pickup_beacons for the palette.
@export var item_light: bool = true
## Compatibility for scenes/resources authored before the old beacon became an item light.
@export_storage var loot_beacon: bool = true:
	set(value):
		loot_beacon = value
		if not value:
			item_light = false

@export_group("World Visual")
## When true, build this pickup's world visual from item.world_model at spawn (and auto-fit the hover hitbox
## to it) instead of relying on an authored body — for loot-dropped / code-spawned pickups that are just an
## Item carrying a model. A null item.world_model is a no-op, so an authored prefab's own look is preserved.
@export var build_model_from_item: bool = false

@export_group("Save")
## OPTIONAL stable id so a HAND-PLACED pickup stays collected across a save/load (and node moves). Blank =
## level+path+position fallback. Ignored for loot-dropped / code-spawned pickups (build_model_from_item) — those
## aren't re-instanced on reload and have no stable identity, so they're never persisted.
@export var save_id: StringName = &""

var _claimed: bool = false  ## latched the instant pickup commits, before the deferred queue_free lands

## Build the item-driven world visual when asked (see build_model_from_item). Runs BEFORE super() so the
## look-at outline + auto-fit collider pick up the freshly added mesh.
func _ready() -> void:
	if Engine.is_editor_hint():
		return  # @tool: in the editor we only evaluate _get_configuration_warnings, never instance the world model
	# Stay collected across a reload: a hand-placed pickup already taken this run doesn't respawn. Loot-dropped /
	# code-spawned pickups (build_model_from_item) are skipped — they're never re-instanced on reload nor persisted.
	# The "gone" bit is coerced through GameState.as_bool (persisted-Variant safety, mirrors Door): a hand-edited /
	# legacy gamestate.cfg could hold a String under the key, and a bare truthiness test on a non-empty String reads
	# true — as_bool degrades non-numeric junk to the default (and dodges the bool(<String>) crash) instead.
	if not build_model_from_item and GameState.as_bool(GameState.object_state(GameState.current_level_path, _save_key()).get("gone", false)):
		queue_free()
		return
	if build_model_from_item and item != null:
		# Build the item's own world_model, else a default placeholder so a loot-dropped / code-spawned pickup is
		# never invisible (mirrors MoneyPickUp/UpgradePickup). Assign item.world_model for a real look.
		var vis: Node3D = ModelResourceUtil.instantiate(item.world_model, "WorldModel") if item.world_model != null else null
		if vis == null:
			vis = _default_item_visual()
		add_child(vis)
		highlight_target = vis
		auto_fit_collider = true
	super._ready()
	# Item light: a colour-coded local glow on the pickup. Covers hand-placed pickups AND dropped/placed items
	# (WorldItem.build wires a CanPickUp whose _ready runs this) AND loot-dropped ones (build_model_from_item).
	# Colour comes from the item's kind; a pure loot-table pickup with no fixed `item` glows as a LOOT_BAG cache.
	# Skipped in-editor (we returned above) and when opted out per-instance.
	if item_light and _has_payload():
		if item != null:
			PickupBeacon.attach_for_item(self, item)
		else:
			PickupBeacon.attach_kind(self, PickupBeacon.Kind.LOOT_BAG)

## A small glowing box built in code so a build_model_from_item pickup whose item has no world_model still shows
## SOMETHING pickable in the world (matches the MoneyPickUp coin / UpgradePickup emblem fallbacks).
func _default_item_visual() -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(0.25, 0.25, 0.25)
	mi.mesh = box
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.85, 0.8, 0.55)
	mat.emission_enabled = true
	mat.emission = Color(0.8, 0.7, 0.3)
	mat.emission_energy_multiplier = 1.5
	mi.material_override = mat
	return mi

## E pressed while aimed at us: grant our payload (item + any loot table) to the player's backpack, then
## remove the world object. If the bag is too full to fit our primary `item`, the pickup is REFUSED — it stays
## in the world (not consumed) and a toast says so, so a bounded (Tetris) bag never makes loot vanish.
func start_talk(player: Node) -> void:
	if not _has_payload() or _claimed:
		return
	var inv: CharacterInventory = null
	var character := player as Character
	if character != null:
		inv = character.inventory
	if inv != null:
		# Bounded-bag guard: if the configured `item` can't find a home, leave the whole pickup in the world.
		if item != null and not inv.can_accept(item):
			if player.has_method(&"notify_toast"):
				player.notify_toast(PlayerText.TOAST_BACKPACK_FULL, Color(0.85, 0.85, 0.85))
			return
	_claimed = true
	_disable_interaction_now()
	if inv != null:
		# _grant has COMMITTED whatever fit (primary + stacks + loot). The host is ALWAYS freed below: if we left it
		# in the world after a PARTIAL grant, can_be_talked_to() stays true and a re-interact would re-grant the
		# WHOLE payload = an item-DUPLICATION exploit. So a partial fit just toasts (not silent) and the overflow is
		# lost; the "nothing fits at all" case was already refused by the can_accept guard above (no grant ran).
		var fully_placed := _grant(inv)
		if not fully_placed and player.has_method(&"notify_toast"):
			player.notify_toast(PlayerText.TOAST_BACKPACK_PARTIAL, Color(0.85, 0.85, 0.85))
		if item != null and item.id != &"":
			GameState.notify_pickup(item.id)  # advance any "collect <item>" quest objective
	# Free the CORRECT node: when build_model_from_item built our visual, _host() is that child (OUR descendant), so
	# freeing only it would orphan this CanPickUp Area3D in the level (inert, but a leak every loot drop) — free
	# SELF instead. Otherwise the host is the world object we sit under, so free that. (Mirrors MoneyPickUp.)
	# Persist "gone" for a hand-placed pickup so it stays collected across a reload (loot drops excluded — see
	# _ready). Recorded on the committed grant, before the deferred free below.
	if not build_model_from_item and not Engine.is_editor_hint():
		GameState.record_object_state(GameState.current_level_path, _save_key(), {"gone": true})
	var host := _host()
	if host != null and host != self and not is_ancestor_of(host):
		host.queue_free()
	else:
		queue_free()

func _save_key() -> String:
	return WorldSaveId.key_for(self, save_id)

func _disable_interaction_now() -> void:
	set_look_highlight(false)
	collision_layer = 0
	collision_mask = 0

## Grant our payload to `inv`: the configured item (weapons as UNIQUE instances) plus the optional loot
## table rolled on top. Split out so it's unit-testable without the pickup's host-free side effect.
## Returns false when the primary `item` couldn't be FULLY placed (a full grid bag) — the caller then leaves
## the pickup in the world instead of freeing it and silently dropping the overflow.
func _grant(inv: CharacterInventory) -> bool:
	var fully_placed := true
	if item != null:
		if item.is_weapon():
			for _n in maxi(1, amount):
				if inv.add(item.duplicate() as Item, 1) <= 0:
					fully_placed = false
					break  # bounded bag filled mid-grant — stop duplicating weapons that won't fit
		else:
			var placed := inv.add(item, amount)
			if placed < amount:
				fully_placed = false  # grid bag couldn't take the whole stack
	ItemStack.seed_into(inv, item_stacks)  # the easy count-based pile, on top of `item`
	if loot_table != null:
		var rng := RandomNumberGenerator.new()
		rng.randomize()
		loot_table.grant(inv, rng)
	return fully_placed

## Pickable while it has anything to give — a fixed item, a count-based pile, or a loot table.
func can_be_talked_to() -> bool:
	return not _claimed and _has_payload()

func _has_payload() -> bool:
	return item != null or loot_table != null or not item_stacks.is_empty()

## Editor warning: a pickup with nothing to give is a no-op — the player can't pick it up (can_be_talked_to
## is false). Mirrors that exact emptiness check so the inspector flags an unfinished pickup.
func _get_configuration_warnings() -> PackedStringArray:
	if item == null and loot_table == null and item_stacks.is_empty():
		return PackedStringArray([
			"Nothing to grant — set `item`, add `item_stacks` rows, or assign a `loot_table`. As-is the player can't pick this up."
		])
	return PackedStringArray()

## Hover readout: the configured label, else "Take <item>", else a generic.
func look_name() -> String:
	if not pickup_label.is_empty():
		return pickup_label
	if item != null:
		return PlayerText.take_item(item.label())
	return PlayerText.PICK_UP
