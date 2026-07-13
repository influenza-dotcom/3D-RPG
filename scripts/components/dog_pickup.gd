@tool
class_name DogPickup
extends CanPickUp

## Dog-specific pickup payload. It turns the live dog's random size into a unique
## inventory item: bigger dogs are worth more, weigh more, and take more grid cells.

@export var value_power: float = 2.0
@export var weight_power: float = 3.0

var _template_item: Item = null
var _last_size_mult: float = -1.0
var _last_coat_mult: float = -1.0


func _ready() -> void:
	_remember_template()
	if not Engine.is_editor_hint():
		refresh_item_from_size()
	super._ready()


func start_talk(player: Node) -> void:
	refresh_item_from_size()
	_capture_live_state()  # stash coat + befriend state onto the item so a re-dropped dog keeps them
	super.start_talk(player)


## Stamp the live dog's runtime state onto the Item being stashed, so dropping it later rebuilds the SAME dog instead
## of a re-rolled stray (the reported "changes colour / stops being befriended when dropped" bug). Size is already
## carried via SIZE_META (build_item_for_size); this adds the coat tint and the befriended flag + name. Read back by
## WorldItem.build → the fresh dog's RandomCoat.preset_tint / Claimable.preset_* on drop. Meta absent => neutral
## restore (a hand-placed dog item with no captured state just rolls a fresh coat and spawns unclaimed).
func _capture_live_state() -> void:
	if item == null:
		return
	var host := _host()
	if host == null:
		return
	# Coat: the colour actually on the mesh right now — covers this dog's RandomCoat roll AND any spray-paint recolour.
	var tint := RandomCoat.read_applied_tint(host)
	if tint.a > 0.0:
		item.set_meta(RandomCoat.COAT_META, tint)
	# Befriended: capture the claim state + the name so a dropped dog is still yours. Clear stale meta when NOT claimed
	# (the item object is reused across hovers/pickups, so a released dog mustn't ride an old befriend back into a drop).
	var claimable := _find_claimable(host)
	if claimable != null and claimable.is_claimed():
		item.set_meta(Claimable.CLAIMED_META, true)
		var chosen := claimable.claim_name()  # the name pushed onto the host when it was befriended
		item.set_meta(Claimable.CLAIMED_NAME_META, chosen)
		if not chosen.is_empty():
			item.display_name = chosen  # the backpack tile reads the dog's NAME, not just "Dog"
	else:
		if item.has_meta(Claimable.CLAIMED_META):
			item.remove_meta(Claimable.CLAIMED_META)
		if item.has_meta(Claimable.CLAIMED_NAME_META):
			item.remove_meta(Claimable.CLAIMED_NAME_META)


## The Claimable befriend-sensor child on `host`, or null (a dog scene has one; a generic prop may not).
func _find_claimable(host: Node) -> Claimable:
	for c in host.get_children():
		if c is Claimable:
			return c as Claimable
	return null


func look_name() -> String:
	refresh_item_from_size()
	# A BEFRIENDED dog reads by the NAME you gave it — "Take Brian", not "Take Large Dog". The name lives on the host
	# (claim pushed it onto display_name); we prefer it over item.label() here so the E-stash prompt matches the
	# Throwable's own carry readout (which already resolves the host name). An explicit pickup_label still wins, and an
	# un-named dog falls back to super's "Take <size label>".
	if pickup_label.is_empty() and item != null:
		var befriended := _befriended_name()
		if not befriended.is_empty():
			return "Take %s" % befriended
	return super.look_name()


## The name a befriended dog was given — its Claimable's resolved claim_name() — or "" when it isn't befriended (so
## the prompt falls back to the size label). Drives the "Take <name>" pickup readout on an adopted dog.
func _befriended_name() -> String:
	var host := _host()
	if host == null:
		return ""
	var claimable := _find_claimable(host)
	if claimable == null or not claimable.is_claimed():
		return ""
	return claimable.claim_name()


func refresh_item_from_size() -> void:
	_remember_template()
	if _template_item == null:
		return
	var size_mult := _host_size_mult()
	var coat_mult := _host_coat_mult()
	# Rebuild when EITHER the size or the coat's value multiplier changed. The coat rolls on a deferred call (after
	# _ready), so the first refresh sees the neutral placeholder and a later hover / the pickup sees the rolled coat and
	# recomputes the price — that's why coat_mult is in the guard, not just size.
	if is_equal_approx(size_mult, _last_size_mult) and is_equal_approx(coat_mult, _last_coat_mult) and item != null:
		return
	item = build_item_for_size(_template_item, size_mult, value_power, weight_power, coat_mult)
	_last_size_mult = size_mult
	_last_coat_mult = coat_mult


func _remember_template() -> void:
	if _template_item == null and item != null:
		_template_item = item


func _host_size_mult() -> float:
	var host := _host()
	if host == null:
		return 1.0
	var random_size := host.get_node_or_null("RandomSize") as RandomSize
	if random_size == null:
		return 1.0
	if random_size.rolled_scale_mult > 0.0:
		return random_size.rolled_scale_mult
	if random_size.preset_scale_mult > 0.0:
		return random_size.preset_scale_mult
	return 1.0


## The value multiplier for this dog's COAT — read off the host's RandomCoat (its `effective_value_mult`, which prices
## the preset colour a re-dropped dog carries or the colour currently on the mesh). 1.0 when there's no RandomCoat or
## none of its coats are priced, so a plain dog is unaffected.
func _host_coat_mult() -> float:
	var host := _host()
	if host == null:
		return 1.0
	var coat := _find_random_coat(host)
	if coat == null:
		return 1.0
	return coat.effective_value_mult()


## The RandomCoat sibling on `host`, or null. Mirrors _find_claimable — the dog scene parents its RandomCoat under the
## same host this pickup points at (highlight_target = the dog root).
func _find_random_coat(host: Node) -> RandomCoat:
	for c in host.get_children():
		if c is RandomCoat:
			return c as RandomCoat
	return null


static func build_item_for_size(template: Item, size_mult: float, value_power_override: float = 2.0, weight_power_override: float = 3.0, coat_value_mult: float = 1.0) -> Item:
	if template == null:
		return null
	var safe_size := maxf(size_mult, 0.01)
	var dog := template.duplicate() as Item
	dog.max_stack = 1
	# Value scales with BOTH size (a power curve) and coat (a flat per-coat multiplier — rarer coats are worth more);
	# weight and footprint are size-only, so a rare coat prices a dog up without making it heavier or bulkier to haul.
	dog.value = snappedf(template.value * pow(safe_size, maxf(value_power_override, 0.0)) * maxf(coat_value_mult, 0.0), 0.01)
	dog.weight = snappedf(template.weight * pow(safe_size, maxf(weight_power_override, 0.0)), 0.01)
	var footprint := footprint_for_size(safe_size)
	dog.grid_width = footprint.x
	dog.grid_height = footprint.y
	dog.display_name = display_name_for_size(template.label(), safe_size)
	dog.set_meta(RandomSize.SIZE_META, safe_size)
	return dog


static func footprint_for_size(size_mult: float) -> Vector2i:
	if size_mult < 0.9:
		return Vector2i(1, 2)
	if size_mult < 1.2:
		return Vector2i(2, 2)
	return Vector2i(3, 3)


static func display_name_for_size(base_name: String, size_mult: float) -> String:
	# [PH] placeholder marker: added ONCE at the front. Strip any marker already on base_name (a marked
	# item label) first so a sized, named dog never reads "[PH] Small [PH] Rex".
	var base := base_name if not base_name.is_empty() else PlayerText.DOG
	base = PlayerText.strip_prefix(base)
	var sized := base
	if size_mult < 0.9:
		sized = "Small %s" % base
	elif size_mult >= 1.2:
		sized = "Large %s" % base
	return PlayerText.prefixed(sized)
