class_name Hotbar
extends Control

## Deus Ex-style HOTBAR: ten slots along the bottom of the screen, AUTO-FILLED from the backpack — every
## weapon and consumable the player acquires takes the first free slot (ammo / misc are skipped: pressing a
## number for loose rounds does nothing useful). Keys 1-0 (the "Weapon Slot N" actions, rebindable in
## Settings > Controls) activate a slot: a WEAPON equips through the normal swap path — pressing its key
## again unequips back to fists, mirroring the inventory UI's toggle — and a CONSUMABLE is used (a health
## pack heals). Items that leave the bag (dropped / sold / used up) vacate their slot automatically.
##
## HOLDABLE PROPS (the dog, a crate — any Item.is_holdable) can ALSO live on the bar, but only when MANUALLY
## assigned (hover in the backpack, press a slot key) — they never auto-fill, so a pocketful of dogs can't flood
## the bar over your weapons. Pressing a holdable's slot pulls the prop OUT of the bag into your hands (held
## hands-free like an aimed Z-grab, via Player.hold_item); pressing it again STASHES the prop back. While a prop
## is in hand its slot is RESERVED + tinted gold; dropping / throwing it (E/Z/left-click) vacates the slot.
##
## Built in code by the UI layer (ui.gd setup, once the player is known), like the rest of the HUD. AUTO-filled
## weapon/consumable slots are DERIVED from bag contents in insertion order, so a reload rebuilds that ordering
## identically. MANUAL holdable-prop assignments and custom slot swaps (assign()) are a session-only convenience —
## they are NOT persisted, so the bar re-derives from bag order on reload (the props themselves survive in the
## backpack, which IS saved).
## Input is gated like every other raw-input consumer (see ray_cast): nothing fires through a conversation, over
## any player-facing menu, during a cutscene, over the name-entry dialog, or while dead. The menu gate routes through
## the shared InputManager.any_modal_open() set (M5) so a newly-registered screen is covered automatically — EXCLUDING
## the backpack, where a slot key ASSIGNS the hovered item instead of activating (handled just below the gate) — plus
## the two control-suppressors (cutscene + name-entry) inlined explicitly so that exclude survives.

const SLOTS: int = 10
## Sized for the PS1-res 396x216 viewport: 10 slots x 38px + 9 x 1px gaps = 389px, just inside the screen.
const SLOT_SIZE := Vector2(38, 24)
const LABEL_MAX_CHARS: int = 6          ## item names are clipped to keep the slots uniform
const COLOR_EMPTY := Color(1, 1, 1, 0.25)
const COLOR_FILLED := Color(0.92, 0.92, 0.95)
const COLOR_EQUIPPED := Color(1.0, 0.86, 0.3)  ## the drawn weapon's slot — gold, like the money readout

@export_group("Idle fade")
## Fade the bar out when it hasn't been used for a moment; it pops back on any hotbar action or bag change.
@export var idle_fade: bool = true
## Seconds the bar stays fully shown after the last use before it begins to fade.
@export var visible_time: float = 2.5
## Fade-in time constant (s) when the bar wakes — lower = snappier.
@export var fade_in_time: float = 0.12
## Fade-out time constant (s) when it goes idle — higher = a slower, gentler fade.
@export var fade_out_time: float = 0.7
## Alpha the bar rests at when idle. 0 = fully hidden; raise for a faint always-on bar.
@export var idle_alpha: float = 0.0

var _player: Player = null
var _show_until: int = 0  ## msec timestamp the bar stays fully shown until (set by _wake on any use)
var _items: Array[Item] = []            ## slot index -> Item (null = empty); the single source of truth
var _slot_panels: Array[PanelContainer] = []
var _slot_names: Array[Label] = []
var _slot_counts: Array[Label] = []

func setup(player: Player) -> void:
	_player = player
	_items.resize(SLOTS)
	_build_bar()
	_wake()  # show the bar briefly on spawn, then it fades to idle
	if _player != null and _player.inventory != null:
		_player.inventory.changed.connect(_sync_slots)
		# The equipped marker changes WITHOUT a contents change (equip from the bag UI / fists fallback),
		# so the highlight refreshes on the equip seams too.
		_player.inventory.equip_weapon_requested.connect(func(_w): _refresh_display())
		_player.inventory.equipped_item_lost.connect(_refresh_display)
		# A HELD prop being dropped/thrown clears its slot's gold "in hand" tint and vacates the reservation, but no
		# inventory.changed fires then (the item left the bag back on the pull) — so refresh off the carry signal too.
		# A bound method (NOT a lambda) so a freed Hotbar auto-disconnects cleanly. Guarded: a bare test player has no head.
		if _player.head != null and _player.head.pickup_ray != null \
				and not _player.head.pickup_ray.carry_changed.is_connected(_on_carry_changed):
			_player.head.pickup_ray.carry_changed.connect(_on_carry_changed)
		_sync_slots()

## Refresh the slot highlight + reservation when a carried prop is grabbed or dropped/thrown (PickupRay.carry_changed).
## A held holdable's slot vacates on drop/throw via _sync_slots reading the now-cleared Player.held_inventory_item().
## DEFERRED: the player's OWN carry_changed handler (which clears its held-item reservation) and this one both fire
## synchronously off the same signal with no guaranteed order — running a frame late guarantees we read the settled
## reservation, so a genuine drop always vacates the slot (rather than leaving a stale gold tint if we ran first).
func _on_carry_changed(_holding: bool) -> void:
	_sync_slots.call_deferred()

## Keep slots in step with the bag: vacate slots whose item left it, then give every unslotted weapon /
## consumable the first free slot (insertion order — the bag's stack order — so layouts are stable).
func _sync_slots() -> void:
	var inv := _player.inventory if _player != null else null
	if inv == null:
		return
	# The one holdable pulled OUT into the player's hands (Player.hold_item) was removed from the bag, but its slot
	# is RESERVED while held so a second press stashes it back — so it's exempt from the "left the bag -> vacate"
	# rule below. On drop/throw the reservation clears (Player._on_carry_changed) and the slot vacates next sync.
	var held: Item = _player.held_inventory_item()
	for i in SLOTS:
		if _items[i] != null and _items[i] != held and not inv.has(_items[i]):
			_items[i] = null
	for s in inv.contents():
		var it: Item = s["item"]
		if it == null or not (it.is_weapon() or it.is_consumable()):
			continue
		if _items.has(it):
			continue
		# ONE slot per weapon KIND: weapons are unique item instances, so five looted pistols would
		# otherwise each claim a slot (flooding the bar) — and switching between identical instances is a
		# dead notch anyway (same WeaponData; the swap system rightly ignores it). Duplicates stay
		# bag-only (Tab); when the slotted one leaves the bag, the next of its kind takes the free slot.
		if it.is_weapon() and _slot_holds_weapon_kind(it.weapon):
			continue
		var free := _items.find(null)
		if free < 0:
			break  # bar full — further items live only in the bag (Tab)
		_items[free] = it
	_refresh_display()

## True if any slot already holds a weapon-item wrapping this same WeaponData (the KIND, not the instance).
func _slot_holds_weapon_kind(weapon: WeaponData) -> bool:
	for slotted in _items:
		if slotted != null and slotted.is_weapon() and slotted.weapon == weapon:
			return true
	return false

## True when `it` IS the equipped item, or is a weapon of the SAME KIND as the equipped one — the bag may
## mark a different identical instance (equipped from the inventory UI), and the slot should still read as
## "this is what's in your hands".
func _is_equipped_kind(it: Item, inv: CharacterInventory) -> bool:
	var eq := inv.equipped_item
	if eq == null:
		return false
	if eq == it:
		return true
	return it.is_weapon() and eq.is_weapon() and eq.weapon == it.weapon

func _unhandled_input(event: InputEvent) -> void:
	# Gate like ray_cast's interact key: no hotbar through a conversation, over ANY player-facing menu, during a
	# cutscene, over the pet-naming name-entry dialog, or while dead. Routes through the shared
	# InputManager.any_modal_open() set (M5), NOT a partial inline list — the old list named only options/loot, so a
	# slot key still switched weapons over the real-time Stats / Reputation / Quest-Journal tabs (which don't pause the
	# tree) and the NPC-transaction screens. T2: liveness now reads the canonical is_alive() (not _dead) and the two
	# suppressors gameplay_suppressed() adds over any_modal_open() — CutscenePlayer + NameEntryDialog — are inlined
	# EXPLICITLY rather than calling gameplay_suppressed(), because this gate must keep any_modal_open's InventoryScreen
	# EXCLUDE: the BACKPACK is the ONE modal that must fall through (a slot key ASSIGNS the hovered item, New Vegas
	# style, handled just below) rather than be swallowed. Previously a slot key still swapped weapons / used a medkit
	# during a cutscene and the pet-naming prompt.
	if _player == null or not _player.is_alive() or DialogueManager.is_active() \
			or CutscenePlayer.is_active() or NameEntryDialog.is_open() \
			or InputManager.any_modal_open(InventoryScreen):
		return
	# Backpack open: a slot key ASSIGNS the hovered item to that slot (New Vegas style) instead of activating;
	# nothing else (scroll, use) fires while you're sorting the bag.
	if InventoryScreen.is_open():
		for i in SLOTS:
			if event.is_action_pressed(InputManager.hotbar_actions[i]):
				var hov: Item = InventoryScreen.hovered_item()
				if hov != null:
					assign(hov, i)
				get_viewport().set_input_as_handled()
				return
		return
	# Scroll wheel cycles the WEAPON slots (next/prev with wrap) — never consumables: scrolling past a
	# medkit must not use it; those stay on their number keys. Yields to the spray paint's palette cycling
	# while a spray can is drawn (it owns the wheel then), explicitly rather than relying on which
	# _unhandled_input runs first.
	if event.is_action_pressed(InputManager.action_hotbar_next) or event.is_action_pressed(InputManager.action_hotbar_prev):
		if not _spray_owns_wheel():
			_wake()  # scrolling the bar wakes it even if it lands on the same weapon
			_cycle(1 if event.is_action_pressed(InputManager.action_hotbar_next) else -1)
			get_viewport().set_input_as_handled()
		return
	for i in SLOTS:
		if event.is_action_pressed(InputManager.hotbar_actions[i]):
			_wake()  # pressing a slot key wakes the bar even if the slot is empty
			_activate(i)
			get_viewport().set_input_as_handled()
			return

## True only while AIMING the drawn spray can (Zoom held, un-holstered) — that's when its painter cycles
## the colour palette with the wheel (spray_painter.gd). The BARE wheel always switches weapons, so you
## can scroll off the can like any other gun; hold aim to pick colours instead.
func _spray_owns_wheel() -> bool:
	var ws := _player.weapon_system
	if ws == null or ws.equipped_weapon == null or ws.attack == null:
		return false
	return ws.equipped_weapon.is_spray_paint and not ws.attack.holstered and Input.is_action_pressed(&"Zoom")

## Step the equipped weapon to the next/previous OCCUPIED weapon slot (wrapping). From bare fists, wheel
## down starts at the first weapon and wheel up at the last. A single carried weapon has nowhere to go.
func _cycle(dir: int) -> void:
	var inv := _player.inventory
	if inv == null:
		return
	var weapon_slots: Array[int] = []
	for i in SLOTS:
		if _items[i] != null and _items[i].is_weapon():
			weapon_slots.append(i)
	if weapon_slots.is_empty():
		return
	var cur := -1
	for i in weapon_slots.size():
		if _is_equipped_kind(_items[weapon_slots[i]], inv):  # kind-aware: a duplicate instance marked
			cur = i                                          # equipped still anchors the cycle position
			break
	var next: int
	if cur < 0:
		next = 0 if dir > 0 else weapon_slots.size() - 1
	else:
		next = (cur + dir + weapon_slots.size()) % weapon_slots.size()
		if next == cur:
			return  # only one weapon carried — nothing to scroll to
	inv.equip_item(_items[weapon_slots[next]])
	_refresh_display()

## Manually place `item` in slot `slot` (New Vegas style: hover it in the bag, press the slot key). Swaps
## with whatever already occupies the slot; the placement STICKS — _sync_slots keeps slotted items put.
## Weapons / consumables / HOLDABLE props (the dog, a crate) can be slotted; ammo / junk are ignored.
func assign(item: Item, slot: int) -> void:
	if item == null or slot < 0 or slot >= SLOTS:
		return
	if not (item.is_weapon() or item.is_consumable() or item.is_holdable()):
		return
	# Refuse to overwrite the slot RESERVED by a prop you're currently holding from the bag: that slot's item is out
	# of the bag with nowhere else to live, so displacing it here would orphan it (the re-press-to-stash + gold tint
	# both lost). Stash the held prop first, then reassign. (Moving the held item ITSELF to another slot is fine and
	# not blocked — but it can't be hovered in the bag while held anyway, so item == held never reaches here.)
	var held: Item = _player.held_inventory_item() if _player != null else null
	if held != null and _items[slot] == held and item != held:
		return
	var from := _items.find(item)  # its current slot, or -1 if it wasn't on the bar
	if from == slot:
		return  # already there
	var displaced := _items[slot]
	_items[slot] = item
	if from >= 0:
		_items[from] = displaced  # swap the two slots
	# else: `item` was unslotted; `displaced` (if any) drops off the bar — _sync_slots re-homes it right now
	_wake()
	_sync_slots()  # re-home any bumped item into a free slot immediately (also refreshes the display)

## Use slot `i`: equip the weapon (or unequip it if already drawn — the inventory UI's toggle), use the
## consumable, or pull a holdable prop into your hands (press again to stash it back). Empty slots do nothing.
func _activate(i: int) -> void:
	var it := _items[i]
	var inv := _player.inventory
	if it == null or inv == null:
		return
	if it.is_weapon():
		if _is_equipped_kind(it, inv):
			inv.unequip()  # pressing the drawn weapon's key puts it away (back to fists) — kind-aware, so a
			               # same-kind duplicate marked equipped from the bag UI still toggles off cleanly
		else:
			inv.equip_item(it)
	elif it.is_consumable():
		_player.use_consumable(it)  # refuses safely at full HP; consuming the last one vacates the slot via changed
	elif it.is_holdable():
		_player.hold_item(it)  # pull the prop out into your hands, or stash it back if already held (toggle)
	_refresh_display()

# ---------------------------------------------------------------------------------------------------
# Idle fade
# ---------------------------------------------------------------------------------------------------

## Pop the bar to full and restart the idle countdown — called on any use or bag/equip change.
func _wake() -> void:
	_show_until = Time.get_ticks_msec() + int(visible_time * 1000.0)

func _process(delta: float) -> void:
	if InventoryScreen.is_open():
		_wake()  # keep the bar shown while the bag is open so you can see where you're assigning items
	if not idle_fade:
		modulate.a = 1.0
		return
	var target: float = 1.0 if Time.get_ticks_msec() < _show_until else idle_alpha
	var t: float = fade_in_time if target > modulate.a else fade_out_time
	if t <= 0.0:
		modulate.a = target
	else:
		modulate.a = lerpf(modulate.a, target, 1.0 - exp(-delta / t))  # frame-rate-independent ease

# ---------------------------------------------------------------------------------------------------
# Display
# ---------------------------------------------------------------------------------------------------

func _build_bar() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	var bar := HBoxContainer.new()
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.add_theme_constant_override(&"separation", 1)
	bar.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	# Sit just inside the bottom-RIGHT corner, growing left + up from it.
	bar.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	bar.grow_vertical = Control.GROW_DIRECTION_BEGIN
	bar.position = Vector2(-4.0, -SLOT_SIZE.y - 4.0)
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
		# Same guard as name_l above: without clip_text a pathological stack count ("x99999999") beats the
		# SLOT_SIZE floor and the bottom-right-anchored bar re-expands LEFTWARD, sliding every slot mid-game.
		# Right-aligned, the clip eats leading digits while the right edge stays put — the right failure mode.
		count_l.clip_text = true
		v.add_child(count_l)
		bar.add_child(panel)
		_slot_panels.append(panel)
		_slot_names.append(name_l)
		_slot_counts.append(count_l)

## Redraw every slot: clipped item name (empty slots show nothing), a stack count for consumables, and the
## gold tint on the drawn weapon's slot.
func _refresh_display() -> void:
	_wake()  # a contents/equip change pops the bar so you SEE the new item / the swapped highlight
	var inv := _player.inventory if _player != null else null
	var held: Item = _player.held_inventory_item() if _player != null else null
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
		# Gold "in hand / drawn" tint: the equipped weapon's slot OR the holdable prop currently pulled into your hands.
		var active := (inv != null and _is_equipped_kind(it, inv)) or (it == held)
		_slot_names[i].add_theme_color_override(&"font_color", COLOR_EQUIPPED if active else COLOR_FILLED)
		var count := inv.count_of(it) if (inv != null and it.is_consumable()) else 0
		_slot_counts[i].text = ("x%d" % count) if count > 1 else ""
