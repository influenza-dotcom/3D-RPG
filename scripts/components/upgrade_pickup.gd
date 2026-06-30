@tool
class_name UpgradePickup
extends LookAtInteractable

const ModelResourceUtil = preload("res://scripts/components/model_resource.gd")

## A drop-in UPGRADE: aim + Interact to permanently grant a player ability. On pickup it adds the ability NODE to
## the player (from the `grants` scene), toasts, and frees the host — the mechanic comes online immediately.
## Mirrors MoneyPickUp.
##
## SETUP: drop an UpgradePickup node and drag an ability scene (scenes/components/abilities/*.tscn) into `grants`
## + set display_name. With no authored body it builds a small glowing emblem (or world_model if you assign one)
## and auto-fits its hover hitbox. (`unlock_id` is a legacy string fallback for pickups authored before scenes.)

## The unlockable-mechanic ids on disk (scenes/components/abilities/), for the `unlock_id` dropdown. No class_name → preload as a const (matches Factions).
const AbilityRegistry := preload("res://scripts/components/abilities/ability_registry.gd")

## The ABILITY SCENE this pickup grants -- drag an ability scene (scenes/components/abilities/*.tscn) here and its
## node is added under the player on pickup, no string id to type. Takes precedence over unlock_id when set.
@export var grants: PackedScene = null:
	set(value):
		grants = value
		update_configuration_warnings()
## LEGACY fallback (used only when `grants` is empty): the mechanic id passed to player.unlock_mechanic(). Pick from
## the DROPDOWN (self-populated from the ability scenes on disk via _validate_property — add an ability scene and
## it appears), or leave it blank to use `grants`. Prefer `grants`; a blank id just means "no legacy unlock".
@export var unlock_id: String = "":
	set(value):
		unlock_id = value
		update_configuration_warnings()
@export var display_name: String = "Upgrade"   ## shown in the toast + hover, e.g. "Grappling Hook"
@export var world_model: Resource = null        ## optional custom visual; scene imports or raw Mesh resources; else a default emblem is built
## Colour of the "acquired!" toast shown on pickup. RGB tints the toast text.
@export var toast_color: Color = Color(0.5, 0.85, 1.0)

## Build the world visual (custom model, else a default emblem) when no body was authored. BEFORE super()
## so the look-at outline + auto-fit collider pick up the new mesh.
func _ready() -> void:
	if Engine.is_editor_hint():
		return  # @tool: in the editor we only evaluate _get_configuration_warnings, never instance the emblem/world model
	if highlight_target == null:
		var vis: Node3D = ModelResourceUtil.instantiate(world_model, "WorldModel") if world_model != null else null
		if vis == null:  # empty PackedScene reimport or invalid model resource -> fall back to the built-in emblem
			vis = _default_emblem()
		add_child(vis)
		highlight_target = vis
		auto_fit_collider = true
	super._ready()

## Grant the ability to the collecting player, toast it, remove the world object.
func start_talk(player: Node) -> void:
	if player is Player and _grant_to(player as Player):
		GameState.autosave(player)  # a new mechanic is a milestone — persist the run so the unlock survives a quit
		if player.has_method(&"notify_toast"):
			player.notify_toast("%s acquired!" % display_name, toast_color)
	# Free the CORRECT node: when no body was authored we built our emblem child and _host() is that descendant, so
	# freeing only it would orphan this UpgradePickup Area3D — free SELF instead. Otherwise free the host we sit
	# under. (Mirrors MoneyPickUp's self-vs-descendant guard.)
	var host := _host()
	if host != null and host != self and not is_ancestor_of(host):
		host.queue_free()
	else:
		queue_free()

## Hand our payload to the player: the ability SCENE if one's assigned (preferred -- the node's authored config
## rides along), else the unlock_id string fallback. Returns true if something was granted. A `grants` scene whose
## root isn't an Ability grants nothing (and is discarded), so a mis-assigned scene fails safe.
func _grant_to(p: Player) -> bool:
	if grants != null:
		var node := grants.instantiate()
		if node == null:  # empty-PackedScene reimport transient -> instantiate() can return null; grant nothing instead of crashing
			return false
		if node is Ability:
			p.grant_ability(node as Ability)
			return true
		node.queue_free()  # not an ability scene -> ignore it rather than parent a stray node under the player
		return false
	if unlock_id != "" and p.has_method(&"unlock_mechanic"):
		p.unlock_mechanic(unlock_id)
		return true
	return false

## Pickable while it actually grants something (an ability scene assigned, or a legacy unlock_id set).
func can_be_talked_to() -> bool:
	return grants != null or unlock_id != ""

## Editor warning: an upgrade pickup that grants nothing (no `grants` ability scene AND no legacy `unlock_id`)
## is a no-op — the player can't pick it up (can_be_talked_to is false). Mirrors that same check.
func _get_configuration_warnings() -> PackedStringArray:
	if grants == null and unlock_id == "":
		return PackedStringArray([
			"Grants nothing — assign an ability scene to `grants` (preferred) or pick a legacy `unlock_id`. As-is the player can't pick this up."
		])
	return PackedStringArray()

## Self-populate the legacy `unlock_id` dropdown from the ability scenes on disk (AbilityRegistry) rather than a
## hand-maintained suggestion list — add an ability scene and it appears. @tool, so the editor honours the hint.
func _validate_property(property: Dictionary) -> void:
	if property.name == &"world_model":
		property.hint = PROPERTY_HINT_RESOURCE_TYPE
		property.hint_string = ModelResourceUtil.HINT
	if property.name == "unlock_id":
		property.hint = PROPERTY_HINT_ENUM_SUGGESTION
		property.hint_string = AbilityRegistry.ids_csv()

## Hover readout, e.g. "Take Grappling Hook".
func look_name() -> String:
	return "Take %s" % display_name

## A small glowing emblem so a bare UpgradePickup (no authored body, no world_model) is visible + pickable.
func _default_emblem() -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var prism := PrismMesh.new()
	prism.size = Vector3(0.3, 0.45, 0.3)
	mi.mesh = prism
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.4, 0.8, 1.0)
	mat.emission_enabled = true
	mat.emission = Color(0.3, 0.7, 1.0)
	mat.emission_energy_multiplier = 2.0
	mi.material_override = mat
	return mi
