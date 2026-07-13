class_name MoneyPickUp
extends LookAtInteractable

const ModelResourceUtil = preload("res://scripts/components/model_resource.gd")
const WorldSaveId = preload("res://scripts/world/world_save_id.gd")  # stable per-object save key (GameState.world_objects)
## The default "cha-ching!" jingle played when a stash is collected (uid://dpu3xluhnn4u1).
const CHACHING := preload("res://assets/audio/sfx/Chaching.mp3")

## A pickable stash of zorkmids. Aim at it and press Interact (E) to collect: it adds `amount` to the
## player's money, drives the HUD readout/floating delta, plays its pickup sound, and frees the host.
## Built on LookAtInteractable so PickupRay detects it with ZERO changes to ray_cast.gd, exactly like
## CanPickUp / LootableCorpse.
##
## SETUP: just drop a MoneyPickUp node and set `amount` — with no authored body it builds a simple gold coin
## (or `world_model` if you assign one) and auto-fits its hover hitbox. Or parent it under your own model and
## set highlight_target, like CanPickUp.

@export var amount: float = 25.0  ## fractional fine — 0.5 is half a zorkmid
## Hover label; blank -> "Take N zorkmids".
@export var pickup_label: String = ""
## OPTIONAL custom world model. Supports scene imports and raw Mesh resources.
## Null -> a simple gold coin is built, so a bare MoneyPickUp is usable as-is.
@export var world_model: Resource = null
## The "cha-ching!" reward jingle played on collect. Defaults to the coin sound so a bare pickup already sounds
## right; clear it in the Inspector for a silent pickup, or swap in your own reward sting.
@export var pickup_sound: AudioStream = CHACHING
## Loudness of the pickup jingle in decibels (0 = the clip's own level).
@export var pickup_volume_db: float = 0.0

@export_group("Save")
## OPTIONAL stable id so a HAND-PLACED money pickup stays collected across a save/load (and node moves). Blank =
## level+path+position fallback (fine for a pickup that never moves — see WorldSaveId). Mirrors CanPickUp/CanDestroy.
@export var save_id: StringName = &""
## A hand-placed pickup persists its "gone" bit so it doesn't respawn once collected; a code-SPAWNED one opts out (a
## dropped money bag's Reclaim child sets this false) — a dynamic spawn has no stable identity and must never enter
## the world_objects ledger (would clutter it and could mis-key). Leave true for authored pickups.
@export var persist_collected: bool = true

## Build the world visual (custom model, else a default coin) when no body was authored. BEFORE super() so
## the look-at outline + auto-fit collider pick up the new mesh.
func _ready() -> void:
	# Stay collected across a reload: a hand-placed money pickup already scooped this run doesn't respawn (mirrors
	# CanPickUp). A code-spawned pickup (persist_collected=false — a dropped money bag's Reclaim child) is skipped: a
	# dynamic spawn has no stable identity. The "gone" bit is coerced via GameState.as_bool (persisted-Variant safety).
	if persist_collected and GameState.as_bool(GameState.object_state(GameState.current_level_path, _save_key()).get("gone", false)):
		queue_free()
		return
	if highlight_target == null:
		var vis: Node3D = ModelResourceUtil.instantiate(world_model, "WorldModel") if world_model != null else null
		if vis == null:
			vis = _default_coin()
		add_child(vis)
		highlight_target = vis
		auto_fit_collider = true
	super._ready()

func _validate_property(property: Dictionary) -> void:
	if property.name == &"world_model":
		property.hint = PROPERTY_HINT_RESOURCE_TYPE
		property.hint_string = ModelResourceUtil.HINT

## Collect: credit the player's wallet, trigger HUD money feedback, remove the world object.
func start_talk(player: Node) -> void:
	if player is Player:
		(player as Player).add_money(amount)  # fires the HUD money readout + the floating +N indicator
	# "cha-ching!" — a one-shot reward cue. Routed through AudioManager (NOT a child AudioStreamPlayer) so it
	# outlives us freeing our own node this very frame; 2D/in-your-ear like the hit + reward cues (you're always
	# point-blank when you Interact). play_2d_sfx no-ops on a null stream, so clearing pickup_sound = silent pickup.
	AudioManager.play_2d_sfx(pickup_sound, pickup_volume_db)
	amount = 0.0  # zero BEFORE freeing so can_be_talked_to() goes false even if the free is deferred a frame
	# Persist "gone" so a hand-placed money pickup stays collected across a reload (stops respawn / infinite-money on
	# Continue). A code-spawned bag Reclaim child opts out via persist_collected=false — a dynamic spawn has no stable
	# identity. Recorded on the committed grant, before the deferred free below. Mirrors CanPickUp; not @tool, so the
	# editor guard is harmless-safe (kept for symmetry with UpgradePickup).
	if persist_collected and not Engine.is_editor_hint():
		GameState.record_object_state(GameState.current_level_path, _save_key(), {"gone": true})
	# Free the CORRECT node: a built-in coin child is OUR descendant (host is a child of self) — freeing it would
	# leave the MoneyPickUp behind, so free SELF; otherwise the host is the world object we sit under, free that.
	var host := _host()
	if host != null and host != self and not is_ancestor_of(host):
		host.queue_free()
	else:
		queue_free()

func _save_key() -> String:
	return WorldSaveId.key_for(self, save_id)

## Pickable while it actually holds money.
func can_be_talked_to() -> bool:
	return amount > 0.0

## Hover readout: the configured label, else "Take N zorkmids".
func look_name() -> String:
	if not pickup_label.is_empty():
		return pickup_label
	return "[PH] Take %s zorkmids" % Zorkmids.fmt(amount)

## A simple gold coin built in code so a bare MoneyPickUp (no authored body, no world_model) still shows
## something pickable in the world. Swap in a real model via world_model.
func _default_coin() -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.15
	cyl.bottom_radius = 0.15
	cyl.height = 0.04
	mi.mesh = cyl
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, 0.84, 0.0)
	mat.metallic = 0.9
	mat.roughness = 0.3
	mi.material_override = mat
	return mi
