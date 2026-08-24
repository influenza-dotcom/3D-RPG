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
## is in hand its slot is RESERVED + tinted gold; dropping / throwing it (F/Z/left-click) vacates the slot.
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
## Slot metrics, fonts, and text tints are designer knobs (GameSettings.hud.hotbar_*, the HudSettings
## "Hotbar" group). At the defaults: 10 slots x 56px + 9 x 2px gaps = 578px on the 792x444 canvas.

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
var _slot_keys: Array[Label] = []       ## key captions — re-stamped from the LIVE InputMap on every refresh
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
	# EXCLUDE the item currently pulled out into your hands. Its slot stays RESERVED (_sync_slots) even though the item
	# has left the bag, and the H verb can now carry a WEAPON — so without this the wheel would equip_item() an item
	# that isn't in the bag, leaving equipped_item pointing at a removed item that nothing ever clears (the same
	# corruption the reserved guard in _activate prevents). Cycling to your OTHER guns while carrying still works.
	var held: Item = _player.held_inventory_item()
	var weapon_slots: Array[int] = []
	for i in SLOTS:
		if _items[i] != null and _items[i] != held and _items[i].is_weapon():
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
## SOUND: this is the ONE hotbar verb that is a MENU action rather than a gameplay one — it fires only while
## the backpack is open (the sole caller is the InventoryScreen branch of _unhandled_input), and it is a
## KEYSTROKE, so it can never inherit a button's auto-wired click. Every branch answers: a placement confirms,
## a refusal denies. Deliberately NOT extended to _activate/_cycle — those run during live gameplay, where the
## weapon draw/holster and consumable audio already speak, and a menu blip over combat would be the opposite
## mistake.
func assign(item: Item, slot: int) -> void:
	if item == null or slot < 0 or slot >= SLOTS:
		return  # a programming-level bad call, not a player action — no cue
	if not (item.is_weapon() or item.is_consumable() or item.is_holdable()):
		MenuStyle.play_denied()  # junk / quest items can't go on the bar
		return
	# Refuse to overwrite the slot RESERVED by a prop you're currently holding from the bag: that slot's item is out
	# of the bag with nowhere else to live, so displacing it here would orphan it (the re-press-to-stash + gold tint
	# both lost). Stash the held prop first, then reassign. (Moving the held item ITSELF to another slot is fine and
	# not blocked — but it can't be hovered in the bag while held anyway, so item == held never reaches here.)
	var held: Item = _player.held_inventory_item() if _player != null else null
	if held != null and _items[slot] == held and item != held:
		MenuStyle.play_denied()  # that slot is reserved by the prop in your hands
		return
	var from := _items.find(item)  # its current slot, or -1 if it wasn't on the bar
	if from == slot:
		MenuStyle.play_denied()  # already there — the keypress changed nothing
		return
	var displaced := _items[slot]
	_items[slot] = item
	if from >= 0:
		_items[from] = displaced  # swap the two slots
	# else: `item` was unslotted; `displaced` (if any) drops off the bar — _sync_slots re-homes it right now
	MenuStyle.play_select()
	_wake()
	_sync_slots()  # re-home any bumped item into a free slot immediately (also refreshes the display)

## Use slot `i`: equip the weapon (or unequip it if already drawn — the inventory UI's toggle), use the
## consumable, or pull a holdable prop into your hands (press again to stash it back). Empty slots do nothing.
func _activate(i: int) -> void:
	var it := _items[i]
	var inv := _player.inventory
	if it == null or inv == null:
		return
	# The item currently pulled OUT of the bag into your hands keeps its slot RESERVED (_sync_slots), so its key must
	# mean "put it away", NOT "equip it". Checked BEFORE the is_weapon() branch because a WEAPON is never is_holdable()
	# (Item.is_holdable) and the H verb can now carry your knife: without this, the reserved slot would equip_item() an
	# item that is no longer in the bag, leaving equipped_item pointing at a removed item that nothing ever clears —
	# throw the knife away and you'd keep wielding its stats.
	if it == _player.held_inventory_item():
		_player.hold_item(it)  # same item -> stash it back into the bag (hold_item's toggle; refuses safely if the grid is full)
		_refresh_display()
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
	# Metrics/fonts read from the HudSettings "Hotbar" knobs, once, at build. The slot CHROME (panel
	# modulate, key/count tints, name outline) is the artist's HudSkin (MenuStyle.hud, hotbar_* fields) —
	# also read once here, so a runtime set_hud_skin() swap shows on the next bar build, not live.
	# Untyped on purpose: a `HudSkin` annotation breaks headless runs until the editor's class cache
	# rescans (see hud_skin.gd's scope contract).
	var skin: Resource = MenuStyle.hud
	var slot: Vector2 = GameSettings.hud.hotbar_slot_size
	var inset: Vector2 = GameSettings.hud.hotbar_inset
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	var bar := HBoxContainer.new()
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.add_theme_constant_override(&"separation", GameSettings.hud.hotbar_separation)
	bar.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	# Sit just inside the bottom-RIGHT corner, growing left + up from it. At the defaults the bar spans
	# x 210..788, y -36..-4 — clear of the ammo readout's left-aligned text at x=20 and below the
	# HP/stamina stack (y <= -35).
	bar.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	bar.grow_vertical = Control.GROW_DIRECTION_BEGIN
	bar.position = Vector2(-inset.x, -slot.y - inset.y)
	add_child(bar)
	for i in SLOTS:
		var panel := PanelContainer.new()
		panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
		panel.custom_minimum_size = slot
		panel.self_modulate = skin.hotbar_panel_modulate  # quiet, semi-transparent chrome under the HUD
		var v := VBoxContainer.new()
		v.mouse_filter = Control.MOUSE_FILTER_IGNORE
		v.add_theme_constant_override(&"separation", 0)
		panel.add_child(v)
		var key := Label.new()
		key.mouse_filter = Control.MOUSE_FILTER_IGNORE
		# The slot actions are REBINDABLE, so the caption queries the single binding seam instead of
		# hardcoding 1..9,0 — _refresh_display re-stamps it, so an Options rebind shows next use.
		key.text = InputManager.get_action_binding(InputManager.hotbar_actions[i])
		key.add_theme_font_size_override(&"font_size", GameSettings.hud.hotbar_key_font_size)
		key.add_theme_color_override(&"font_color", skin.hotbar_key_color)
		# Same guard as name_l below: a wide binding caption ("Mouse 1") must not beat the slot floor.
		key.clip_text = true
		v.add_child(key)
		_slot_keys.append(key)
		var name_l := Label.new()
		# Slot names paint item.label(), which can be a player-TYPED pet name (a befriended dog's Item takes
		# the typed name via DogPickup._capture_live_state) — typed text must never be looked up as a
		# translation msgid, so the label opts out of Godot's automatic Control-text translation (atr).
		name_l.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		name_l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		name_l.add_theme_font_size_override(&"font_size", GameSettings.hud.hotbar_name_font_size)
		name_l.add_theme_color_override(&"font_outline_color", skin.label_outline_color)
		name_l.add_theme_constant_override(&"outline_size", skin.hotbar_name_outline_size)
		name_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		# clip_text keeps the label from contributing its TEXT width as a minimum size: a wide-glyph item
		# name could otherwise push its PanelContainer past the slot floor and re-widen the whole bar.
		name_l.clip_text = true
		# Overlong names trim to an ellipsis instead of a hard mid-word chop at the clip edge.
		name_l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		v.add_child(name_l)
		var count_l := Label.new()
		count_l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		count_l.add_theme_font_size_override(&"font_size", GameSettings.hud.hotbar_count_font_size)
		count_l.add_theme_color_override(&"font_color", skin.hotbar_count_color)
		count_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		# Same guard as name_l above: without clip_text a pathological stack count ("x99999999") beats the
		# slot-size floor and the bottom-right-anchored bar re-expands LEFTWARD, sliding every slot mid-game.
		# Right-aligned, the clip eats leading digits while the right edge stays put — the right failure mode.
		count_l.clip_text = true
		v.add_child(count_l)
		bar.add_child(panel)
		_slot_panels.append(panel)
		_slot_names.append(name_l)
		_slot_counts.append(count_l)

## Redraw every slot: live key caption, ellipsised item name (empty slots show nothing), a stack count for
## consumables, and the gold tint on the drawn weapon's slot.
func _refresh_display() -> void:
	_wake()  # a contents/equip change pops the bar so you SEE the new item / the swapped highlight
	var inv := _player.inventory if _player != null else null
	var held: Item = _player.held_inventory_item() if _player != null else null
	for i in SLOTS:
		var it := _items[i]
		if i >= _slot_names.size():
			break
		# Key captions re-read the LIVE InputMap: refresh runs on every bag change/wake/activation, so an
		# Options rebind shows next use (ten string queries per refresh, not per frame — negligible).
		_slot_keys[i].text = InputManager.get_action_binding(InputManager.hotbar_actions[i])
		if it == null:
			_slot_names[i].text = ""
			_slot_counts[i].text = ""
			_slot_names[i].add_theme_color_override(&"font_color", GameSettings.hud.hotbar_empty_color)
			continue
		_slot_names[i].text = it.label()  # full name — clip_text + the ellipsis trim handle overflow
		# Gold "in hand / drawn" tint: the equipped weapon's slot OR the holdable prop currently pulled into your hands.
		var active := (inv != null and _is_equipped_kind(it, inv)) or (it == held)
		_slot_names[i].add_theme_color_override(&"font_color",
				GameSettings.hud.hotbar_equipped_color if active else GameSettings.hud.hotbar_filled_color)
		var count := inv.count_of(it) if (inv != null and it.is_consumable()) else 0
		_slot_counts[i].text = ("x%d" % count) if count > 1 else ""
