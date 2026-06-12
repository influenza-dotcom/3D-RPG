class_name Hotbar
extends Control

## Deus Ex-style HOTBAR: ten slots along the bottom of the screen, AUTO-FILLED from the backpack — every
## weapon and consumable the player acquires takes the first free slot (ammo / misc are skipped: pressing a
## number for loose rounds does nothing useful). Keys 1-0 (the "Weapon Slot N" actions, rebindable in
## Settings > Controls) activate a slot: a WEAPON equips through the normal swap path — pressing its key
## again unequips back to fists, mirroring the inventory UI's toggle — and a CONSUMABLE is used (a health
## pack heals). Items that leave the bag (dropped / sold / used up) vacate their slot automatically.
##
## Built in code by the UI layer (ui.gd setup, once the player is known), like the rest of the HUD. Slot
## assignment is DERIVED from bag contents in insertion order, so a saved game rebuilds the same layout.
## Input is gated like every other raw-input consumer: nothing fires through a menu, a conversation, or
## death (the pausing screens pause this node with the tree; the rest are checked explicitly).

const SLOTS: int = 10
## Sized for the PS1-res 396x216 viewport: 10 slots x 38px + 9 x 1px gaps = 389px, just inside the screen.
const SLOT_SIZE := Vector2(38, 24)
const LABEL_MAX_CHARS: int = 6          ## item names are clipped to keep the slots uniform
const COLOR_EMPTY := Color(1, 1, 1, 0.25)
const COLOR_FILLED := Color(0.92, 0.92, 0.95)
const COLOR_EQUIPPED := Color(1.0, 0.86, 0.3)  ## the drawn weapon's slot — gold, like the money readout

var _player: Player = null
var _items: Array[Item] = []            ## slot index -> Item (null = empty); the single source of truth
var _slot_panels: Array[PanelContainer] = []
var _slot_names: Array[Label] = []
var _slot_counts: Array[Label] = []

func setup(player: Player) -> void:
	_player = player
	_items.resize(SLOTS)
	_build_bar()
	if _player != null and _player.inventory != null:
		_player.inventory.changed.connect(_sync_slots)
		# The equipped marker changes WITHOUT a contents change (equip from the bag UI / fists fallback),
		# so the highlight refreshes on the equip seams too.
		_player.inventory.equip_weapon_requested.connect(func(_w): _refresh_display())
		_player.inventory.equipped_item_lost.connect(_refresh_display)
		_sync_slots()

## Keep slots in step with the bag: vacate slots whose item left it, then give every unslotted weapon /
## consumable the first free slot (insertion order — the bag's stack order — so layouts are stable).
func _sync_slots() -> void:
	var inv := _player.inventory if _player != null else null
	if inv == null:
		return
	for i in SLOTS:
		if _items[i] != null and not inv.has(_items[i]):
			_items[i] = null
	for s in inv.contents():
		var it: Item = s["item"]
		if it == null or not (it.is_weapon() or it.is_consumable()):
			continue
		if _items.has(it):
			continue
		var free := _items.find(null)
		if free < 0:
			break  # bar full — further items live only in the bag (Tab)
		_items[free] = it
	_refresh_display()

func _unhandled_input(event: InputEvent) -> void:
	# Gate like MouseInput / ScopeIn / the grapple: no hotbar through a non-pausing menu, a conversation,
	# or while dead. (The pausing screens stop this node with the tree, so they need no check.)
	if _player == null or _player._dead or DialogueManager.is_active() \
			or OptionsMenu.is_open() or InventoryScreen.is_open() or LootScreen.is_open():
		return
	for i in SLOTS:
		if event.is_action_pressed(InputManager.hotbar_actions[i]):
			_activate(i)
			get_viewport().set_input_as_handled()
			return

## Use slot `i`: equip the weapon (or unequip it if already drawn — the inventory UI's toggle), or use the
## consumable. Empty slots do nothing.
func _activate(i: int) -> void:
	var it := _items[i]
	var inv := _player.inventory
	if it == null or inv == null:
		return
	if it.is_weapon():
		if inv.equipped_item == it:
			inv.unequip()  # pressing the drawn weapon's key puts it away (back to fists)
		else:
			inv.equip_item(it)
	elif it.is_consumable():
		_player.use_consumable(it)  # refuses safely at full HP; consuming the last one vacates the slot via changed
	_refresh_display()

# ---------------------------------------------------------------------------------------------------
# Display
# ---------------------------------------------------------------------------------------------------

func _build_bar() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	var bar := HBoxContainer.new()
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.add_theme_constant_override(&"separation", 1)
	bar.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	bar.position.y = -SLOT_SIZE.y - 4.0
	bar.grow_horizontal = Control.GROW_DIRECTION_BOTH
	add_child(bar)
	for i in SLOTS:
		var panel := PanelContainer.new()
		panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
		panel.custom_minimum_size = SLOT_SIZE
		panel.self_modulate = Color(1, 1, 1, 0.55)  # quiet, semi-transparent chrome under the HUD
		var v := VBoxContainer.new()
		v.mouse_filter = Control.MOUSE_FILTER_IGNORE
		v.add_theme_constant_override(&"separation", 0)
		panel.add_child(v)
		var key := Label.new()
		key.mouse_filter = Control.MOUSE_FILTER_IGNORE
		key.text = str((i + 1) % 10)  # slots 1..9 then 0, matching the keyboard row
		key.add_theme_font_size_override(&"font_size", 7)
		key.add_theme_color_override(&"font_color", Color(1, 1, 1, 0.5))
		v.add_child(key)
		var name_l := Label.new()
		name_l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		name_l.add_theme_font_size_override(&"font_size", 8)
		name_l.add_theme_color_override(&"font_outline_color", Color.BLACK)
		name_l.add_theme_constant_override(&"outline_size", 2)
		name_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		# clip_text keeps the label from contributing its TEXT width as a minimum size: a wide-glyph item
		# name could otherwise push its PanelContainer past SLOT_SIZE and re-overflow the 396px viewport.
		name_l.clip_text = true
		v.add_child(name_l)
		var count_l := Label.new()
		count_l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		count_l.add_theme_font_size_override(&"font_size", 7)
		count_l.add_theme_color_override(&"font_color", Color(1, 1, 1, 0.6))
		count_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		v.add_child(count_l)
		bar.add_child(panel)
		_slot_panels.append(panel)
		_slot_names.append(name_l)
		_slot_counts.append(count_l)

## Redraw every slot: clipped item name (empty slots show nothing), a stack count for consumables, and the
## gold tint on the drawn weapon's slot.
func _refresh_display() -> void:
	var inv := _player.inventory if _player != null else null
	for i in SLOTS:
		var it := _items[i]
		if i >= _slot_names.size():
			break
		if it == null:
			_slot_names[i].text = ""
			_slot_counts[i].text = ""
			_slot_names[i].add_theme_color_override(&"font_color", COLOR_EMPTY)
			continue
		_slot_names[i].text = it.label().left(LABEL_MAX_CHARS)
		var equipped := inv != null and inv.equipped_item == it
		_slot_names[i].add_theme_color_override(&"font_color", COLOR_EQUIPPED if equipped else COLOR_FILLED)
		var count := inv.count_of(it) if (inv != null and it.is_consumable()) else 0
		_slot_counts[i].text = ("x%d" % count) if count > 1 else ""
