extends CanvasLayer
## InventoryScreen — the player's backpack overlay, opened with Tab. Code-built and registered as an
## autoload so ONE instance survives scene changes, mirroring OptionsMenu.
##
## Like OptionsMenu it does NOT pause the SceneTree: the world keeps simulating and the player stays
## vulnerable. It frees the mouse for the UI on open (restored on close), and player CONTROL is suppressed
## via is_open() gates (player move/jump, MouseInput fire, ScopeIn aim) so menu clicks/keys don't drive
## the character. Lists the player's items; clicking a weapon equips it through the backpack's equip
## bridge (CharacterInventory.equip_item -> Player._on_equip_weapon_requested -> the swap animation).

signal opened
signal closed

const PANEL_MARGIN := 0.12  ## fraction of the screen left as a border — SAME margin as the loot/shop screens, so every inventory-style menu shares one chrome
const PlayerMenus := preload("res://scripts/ui/player_menus.gd")  ## tab-group helper (Inventory/Stats/Reputation)

var _root: Control
var _grid_view: GridInventoryView  ## the Tetris grid of the backpack (drag to move, R to rotate, click to equip/use)
var _detail: Label                 ## hovered-item breakdown shown under the grid (replaces the per-row tooltip)
var _is_open := false
var _player: Player = null
var _bound_inventory: CharacterInventory = null

func _ready() -> void:
	layer = 120                                  # above the HUD, just under OptionsMenu (128)
	process_mode = Node.PROCESS_MODE_ALWAYS      # keep working regardless of any pause
	_build_ui()
	_root.visible = false

func is_open() -> bool:
	return _is_open

## The item the cursor is currently over in the grid (the hotbar reads this to assign it to a slot). Delegates to
## the grid view, then guards against a stale reference (the item left the bag since the cursor last moved).
func hovered_item() -> Item:
	var it: Item = _grid_view.hovered_item() if _grid_view != null else null
	if it != null and is_instance_valid(_player) and _player.inventory != null and _player.inventory.has(it):
		return it
	return null

# ---------------------------------------------------------------------------------------------------
# Open / close — free the mouse, no SceneTree pause (control is suppressed via the is_open() gates)
# ---------------------------------------------------------------------------------------------------

func toggle() -> void:
	if _is_open:
		close()
	else:
		open()

func open() -> void:
	# Yield to dialogue, the settings menu, and the pausing screens (shop/heal/level-up) — never stack over a
	# NON-player modal. Our input runs PROCESS_MODE_ALWAYS, so without these checks the inventory key would open
	# us OVER a paused shop. The sibling player menus (Stats/Reputation) are NOT blocked: opening us SWITCHES
	# off an open sibling (PlayerMenus.close_others below), so the three act as one Deus Ex / Pip-Boy tab group.
	if _is_open or DialogueManager.is_active() or OptionsMenu.is_open() or LootScreen.is_open() or InputManager.any_pausing_open() or not PlayerMenus.player_alive(get_tree()):  # M5: pausing modals via the shared helper; refuse mid-death (we run PROCESS_MODE_ALWAYS, so the Tab hotkey would otherwise re-open us over the death cinematic)
		return
	_player = _find_real_player() as Player
	if not is_instance_valid(_player) or _player.inventory == null:
		return  # no player / no backpack -> nothing to show (e.g. the start menu)
	PlayerMenus.enter(self)  # switch off a sibling + free the cursor (preserves cursor position across switches)
	_bind_inventory(_player.inventory)
	_is_open = true
	_rebuild()
	_root.visible = true
	opened.emit()

func close() -> void:
	if not _is_open:
		return
	_is_open = false
	_root.visible = false
	PlayerMenus.leave()
	closed.emit()

## Keep the list live: rebind to the player's backpack and refresh whenever its contents change (loot
## arriving, a weapon removed). Disconnects the previous binding so a respawned player doesn't double-fire.
func _bind_inventory(inv: CharacterInventory) -> void:
	if _bound_inventory == inv:
		return
	if is_instance_valid(_bound_inventory) and _bound_inventory.changed.is_connected(_on_inventory_changed):
		_bound_inventory.changed.disconnect(_on_inventory_changed)
	_bound_inventory = inv
	if inv != null and not inv.changed.is_connected(_on_inventory_changed):
		inv.changed.connect(_on_inventory_changed)

func _on_inventory_changed() -> void:
	if _is_open:
		_rebuild()

## The human player, not a companion (companions join &"Player" for targeting but are NPCs).
func _find_real_player() -> Node:
	return Groups.human_player(get_tree())  # M6: the one non-companion human-player filter lives on Groups (no local NPC dep)

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(InputManager.action_inventory):
		toggle()
		get_viewport().set_input_as_handled()
	elif _is_open and event.is_action_pressed(&"ui_cancel"):
		close()  # Esc closes the backpack (OptionsMenu.open() also refuses while we're open, so it won't stack)
		get_viewport().set_input_as_handled()

# ---------------------------------------------------------------------------------------------------
# UI construction + the item list
# ---------------------------------------------------------------------------------------------------

func _build_ui() -> void:
	_root = Control.new()
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP  # eat clicks so nothing falls through to gameplay behind
	MenuStyle.apply(_root)  # shared menu Theme (panel/buttons/tooltips/fonts) — reskin via resources/ui/menu_skin.tres
	add_child(_root)

	_root.add_child(MenuStyle.make_dim())

	var panel := PanelContainer.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	panel.anchor_left = PANEL_MARGIN
	panel.anchor_top = PANEL_MARGIN
	panel.anchor_right = 1.0 - PANEL_MARGIN
	panel.anchor_bottom = 1.0 - PANEL_MARGIN
	panel.offset_left = 0
	panel.offset_top = 0
	panel.offset_right = 0
	panel.offset_bottom = 0
	_root.add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", MenuStyle.skin.content_separation)  # shared rhythm across every panel screen
	panel.add_child(vbox)

	# The tab strip is the only header — it already labels the screen, so no separate title. Stats aren't shown
	# here (dedicated Stats screen, one tab away); zorkmids ride INSIDE the grid as their own coin tile now
	# (MoneyPurse mirrors the wallet into a real backpack stack), so there's no separate money widget to place.
	vbox.add_child(PlayerMenus.build_tab_strip("Inventory"))  # [Inventory | Stats | Reputation] — click to switch

	# The Tetris grid itself — drag a tile to move it, R to rotate the held tile, click to equip/use, right-click
	# to drop. Cells size to the SLOT: the resized hook below feeds the grid the scroll slot's height as its
	# max_view_height budget, so all rows fit whole at the real 792x444 canvas (6x5 backpack ≈ 41px cells, no
	# scrollbar) — the old width-only sizing guaranteed a permanent scrollbar hiding most of the bottom row.
	# The scroll (vertical only; horizontal off so the grid sizes its cells to the width) is just the fallback
	# for windows too short to fit even MIN_CELL-sized rows.
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_child(scroll)
	_grid_view = GridInventoryView.new()
	scroll.add_child(_grid_view)
	scroll.resized.connect(_on_grid_slot_resized.bind(scroll))  # bound method, not a lambda (freed-capture safety)
	_grid_view.activate_requested.connect(_on_grid_activate)
	_grid_view.drop_requested.connect(_on_grid_drop)
	_grid_view.hover_changed.connect(_on_grid_hover_changed)

	# Footer status line under the grid: the carry weight when idle, the hovered item's breakdown on hover.
	# (Zorkmids now live INSIDE the grid as their own coin tile — MoneyPurse mirrors the wallet into a real
	# stack — so the old footer coin widget is gone; the wallet total still reads on the top-left HUD.)
	# The detail Label lives inside a FIXED-HEIGHT clip host: reserving a min height on the Label alone was not
	# enough — an unusually long tooltip (a weapon's full stat block) exceeds it, and because a Label reports
	# its full wrapped height as its min size, the VBox grew the footer and SHRANK the EXPAND_FILL grid above,
	# which recomputed its cell size — the whole grid pumped on hover. A plain Control host with clip_contents
	# does NOT take its (anchored) child's size into its own minimum, so the footer stays exactly this tall and
	# an over-long tooltip clips at the bottom instead of reflowing the grid. ~4 hint lines (skin.hint_size +
	# ~4px leading each) fits a typical tooltip; top-aligned so shorter text leaves dead space below.
	var footer := Control.new()
	footer.clip_contents = true
	footer.custom_minimum_size.y = 4 * (MenuStyle.skin.hint_size + 4)
	footer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_child(footer)
	_detail = MenuStyle.make_hint("")
	_detail.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)  # fill the fixed host; overflow is clipped, not laid out
	_detail.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_detail.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	footer.add_child(_detail)

## The grid's scroll slot changed size (first layout, window resize, panel reflow) — hand the grid its exact
## height budget so _recompute_cell can fit cells by HEIGHT as well as width, then refresh so the new cell size
## applies immediately. Safe while closed / unbound: refresh() on an unbound grid just clears its rows.
func _on_grid_slot_resized(scroll: ScrollContainer) -> void:
	if _grid_view == null or not is_instance_valid(scroll):
		return
	_grid_view.max_view_height = int(scroll.size.y)
	_grid_view.refresh()

## Refresh the grid + the weight header from the player's backpack. The grid view does the per-stack rendering;
## here we just (re)bind it and update the carry-weight line. Called on open and on every inventory.changed.
func _rebuild() -> void:
	if not is_instance_valid(_player) or _player.inventory == null:
		return
	_grid_view.bind(_player.inventory)  # bind() also refreshes the tiles
	_show_weight()

## Put the carry-weight readout on the footer status line (the idle state; hovering an item overrides it).
func _show_weight() -> void:
	if not is_instance_valid(_player) or _player.inventory == null:
		return
	var enc: bool = _player.is_encumbered()
	_detail.text = "[PH] Weight  %.1f / %.1f%s" % [_player.inventory.total_weight(), _player.carry_capacity, "   ENCUMBERED" if enc else ""]
	_detail.add_theme_color_override(&"font_color", MenuStyle.danger() if enc else MenuStyle.dim_color())

## A grid tile was clicked (no drag) — route by type: equip/unequip a weapon, use a consumable, ignore the rest.
func _on_grid_activate(item: Item) -> void:
	if item == null:
		return
	if item.is_weapon():
		_on_item_pressed(item)
	elif item.is_consumable():
		_on_use_pressed(item)

## A grid tile was right-clicked — drop JUST THE CLICKED STACK to the world (dropping the wielded weapon falls
## back to fists). Passes the stack's `key` so the player removes THAT exact stack (remove-BY-KEY) — NOT
## count_of(item) or newest-first: two dog crates no longer drop both, and the tile that empties is the one clicked.
func _on_grid_drop(item: Item, key: int) -> void:
	if item == null or not is_instance_valid(_player) or _player.inventory == null:
		return
	if item.id == Zorkmids.ITEM_ID:
		# The coin pile IS the wallet, not an ordinary stack — spill the WHOLE purse as a collectable MoneyPickUp
		# (drop_money debits the wallet, then MoneyPurse clears the tile). A plain drop_stack would remove the
		# mirror stack without moving `money`, and the purse would just re-assert it a frame later.
		_player.drop_money(_player.money)
		return
	_player.drop_stack(item, key)  # removes THAT stack from the bag -> inventory.changed -> _rebuild refreshes

## The hovered tile changed — show that item's name on the status line (its full breakdown), or fall back to the
## carry weight when nothing is hovered.
func _on_grid_hover_changed(item: Item) -> void:
	if item != null and is_instance_valid(_player):
		_detail.add_theme_color_override(&"font_color", MenuStyle.text_color())
		_detail.text = ItemInfo.tooltip(item, _player.inventory)
	else:
		_show_weight()

func _on_item_pressed(item: Item) -> void:
	if not is_instance_valid(_player) or _player.inventory == null:
		return
	if item == _player.inventory.equipped_item:
		_player.inventory.unequip()         # clicking the wielded weapon puts it away -> player falls back to fists
	else:
		_player.inventory.equip_item(item)  # -> equip_weapon_requested -> Player draws it (swap anim)
	_rebuild()                              # refresh the (equipped) marker

func _on_use_pressed(item: Item) -> void:
	if is_instance_valid(_player):
		_player.use_consumable(item)  # heals + consumes one -> inventory.changed -> _rebuild refreshes the stack
