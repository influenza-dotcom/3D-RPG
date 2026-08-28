extends CanvasLayer
## InventoryScreen — the player's backpack overlay, opened with Tab. Registered as an autoload so ONE
## instance survives scene changes, mirroring OptionsMenu.
##
## Like OptionsMenu it does NOT pause the SceneTree: the world keeps simulating and the player stays
## vulnerable. It frees the mouse for the UI on open (restored on close), and player CONTROL is suppressed
## via is_open() gates (player move/jump, MouseInput fire, ScopeIn aim) so menu clicks/keys don't drive
## the character. Lists the player's items; clicking a weapon equips it through the backpack's equip
## bridge (CharacterInventory.equip_item -> Player._on_equip_weapon_requested -> the swap animation).
##
## AUTHORED SCENE: the layout lives in scenes/ui/inventory_screen.tscn (this autoload IS that scene — see
## project.godot [autoload]); this script binds its chrome by %unique name in _bind_ui and applies the
## skin-driven look (MenuStyle style_* adopters + skin reads) on top, so a designer rearranges the panel
## in the editor and the skin keeps owning colours/fonts/separations/height budgets. NO text is authored
## in the scene — every string is set here from PlayerText (l10n + the text-debt ratchet own strings,
## never a .tscn). The Tetris GridInventoryView stays CODE-instantiated into the authored %Scroll slot,
## and the PlayerMenus tab strip stays CODE-BUILT into the authored %TabSlot (the strip's one-Button-per-tab
## structure is a cross-screen contract owned by player_menus.gd, not this scene).
## tests/test_inventory_screen_scene.gd pins the wiring.

signal opened
signal closed


const PANEL_MARGIN := 0.12  ## fraction of the screen left as a border — SAME margin as the loot/shop screens, so every inventory-style menu shares one chrome; AUTHORED into the scene's Panel anchors (0.12..0.88), this const documents the contract (test-pinned)
const PlayerMenus := preload("res://scripts/ui/player_menus.gd")  ## tab-group helper (Inventory/Stats/Implants/Map/Reputation/Journal)

var _root: Control
var _grid_view: GridInventoryView  ## the Tetris grid of the backpack (drag to move, R to rotate, click to equip/use)
var _detail: Label                 ## hovered-item breakdown shown under the grid (replaces the per-row tooltip)
var _wallet: Label                 ## the zorkmid readout above the grid — money is NOT a grid tile (see _bind_ui)
var _drop_money_btn: Button        ## opens the AmountPrompt that spills part of the purse as a physics money bag
var _amount_prompt: AmountPrompt   ## "how much?" card, parented over our own panel (code-built, like the grid)
var _is_open := false
var _player: Player = null
var _bound_inventory: CharacterInventory = null
var _bound_player: Player = null   ## whose money_changed the wallet row is currently listening to

func _ready() -> void:
	layer = 120                                  # above the HUD, just under OptionsMenu (128)
	process_mode = Node.PROCESS_MODE_ALWAYS      # keep working regardless of any pause
	_bind_ui()
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
	# Yield to dialogue and to any screen that owns the player's hands (settings / loot / the station screens —
	# the registry's `blocks_tabs` rows) — never stack over a NON-player modal. Our input runs PROCESS_MODE_ALWAYS,
	# so without these checks Tab would open us OVER an open shop, and the two would then fight over Escape and
	# the cursor. The sibling player menus (Stats/Reputation) are NOT blocked: opening us SWITCHES
	# off an open sibling (PlayerMenus.close_others below), so the three act as one Deus Ex / Pip-Boy tab group.
	if _is_open or DialogueManager.is_active() or InputManager.any_tab_blocking_open() or not PlayerMenus.player_alive(get_tree()):  # M5/T1: the WHOLE refusal set (options/loot/the station screens) comes from the modal registry — never hand-name a screen here; refuse mid-death (we run PROCESS_MODE_ALWAYS, so the Tab hotkey would otherwise re-open us over the death cinematic)
		return
	_player = _find_real_player() as Player
	if not is_instance_valid(_player) or _player.inventory == null:
		return  # no player / no backpack -> nothing to show (e.g. the start menu)
	PlayerMenus.enter(self)  # switch off a sibling + free the cursor (preserves cursor position across switches)
	_bind_inventory(_player.inventory)
	_bind_wallet(_player)
	_is_open = true
	_rebuild()
	_root.visible = true
	opened.emit()

func close() -> void:
	if not _is_open:
		return
	if _amount_prompt != null:
		_amount_prompt.close()  # never leave a half-answered "how much?" card to reappear over the next open
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

## The wallet row reads `money`, which the BAG's `changed` never fires for (a bounty, a sale, a pickup, an
## interest posting). Bind the float's own signal so the row can't sit stale while the screen is open. Bound
## per-open like the inventory; a respawned player is a new node, so its predecessor's connection dies with it.
func _bind_wallet(p: Player) -> void:
	if _bound_player == p:
		return
	if is_instance_valid(_bound_player) and _bound_player.money_changed.is_connected(_on_money_changed):
		_bound_player.money_changed.disconnect(_on_money_changed)
	_bound_player = p
	if p != null and not p.money_changed.is_connected(_on_money_changed):
		p.money_changed.connect(_on_money_changed)


func _on_money_changed(_total: float, _delta: float) -> void:
	if _is_open:
		_paint_wallet()


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
# UI binding + the item grid (the layout is AUTHORED in scenes/ui/inventory_screen.tscn — this adopts it)
# ---------------------------------------------------------------------------------------------------

## Bind the authored chrome by %unique name, style it from the skin, and wire behaviour. The scene owns
## STRUCTURE (the PANEL_MARGIN 0.12 anchor band, the tab slot, the grid's scroll slot, the clip footer);
## the skin keeps owning LOOK — every colour/font/separation/height budget below is a MenuStyle/skin read,
## so reskinning via resources/ui/menu_skin.tres restyles this screen with zero scene edits.
func _bind_ui() -> void:
	_root = %Root  # full-rect, MOUSE_FILTER_STOP authored — eats clicks so nothing falls through to gameplay behind
	MenuStyle.apply(_root)  # shared menu Theme (panel/buttons/tooltips/fonts) — reskin via resources/ui/menu_skin.tres
	MenuStyle.style_dim(%Dim)

	var vbox: VBoxContainer = %VBox
	vbox.add_theme_constant_override("separation", MenuStyle.skin.content_separation)  # shared rhythm across every panel screen

	# The tab strip is the only header — it already labels the screen, so no separate title. Stats aren't shown
	# here (dedicated Stats screen, one tab away). The strip stays CODE-BUILT by PlayerMenus into the authored
	# %TabSlot: its one-Button-per-tab EXPAND_FILL structure is a cross-screen contract
	# (tests/test_player_menus.gd), so the scene authors only the slot.
	%TabSlot.add_child(PlayerMenus.build_tab_strip(&"inventory"))  # [Inventory | Stats | Implants | Reputation | Journal] — click to switch (routing KEY, not the painted label)

	# THE WALLET ROW — money is NOT an inventory item. Zorkmids spent a while mirrored into a real coin tile
	# inside the grid, which meant a fat purse ate 1x1..3x3 backpack cells you'd rather have filled with
	# loot. The wallet is a plain readout again — `Character.money`, the authoritative
	# float, painted here and on the HUD — and the two gestures the tile carried moved onto this row: the
	# button opens the AmountPrompt, which spills a CHOSEN slice of the purse as a physics money bag (the tile
	# could only ever dump the whole lot). The Label EXPAND_FILLs and clips, so the amount can grow to any
	# width without shifting the button (menus never re-lay-out on text).
	_wallet = MenuStyle.cap_label(%Wallet)
	_wallet.add_theme_font_size_override("font_size", MenuStyle.skin.header_size)
	# NOT cap_button: clip_text drops a Button's horizontal MINIMUM to ~0, and beside an EXPAND_FILL Label that
	# collapses it to a sliver with no caption (cap_button is for a card whose width is PINNED — see
	# MenuStyle.make_dialog). This caption is a fixed PlayerText const, so its natural width is the right width.
	_drop_money_btn = %DropMoneyButton
	_drop_money_btn.text = PlayerText.WALLET_DROP
	MenuStyle.set_button_sound(_drop_money_btn, &"")  # the prompt plays its own open cue — don't stack a click on top
	_drop_money_btn.pressed.connect(_on_drop_money_pressed)
	(%WalletRow as HBoxContainer).add_theme_constant_override("separation", MenuStyle.skin.button_row_separation)

	# The "how much?" card, parented over the whole screen (LAST child of the root, so it draws above the
	# panel and eats the clicks that miss it). Code-built for the same reason the grid view is: it's live
	# runtime chrome, not layout an artist arranges.
	_amount_prompt = AmountPrompt.new()
	_root.add_child(_amount_prompt)

	# The Tetris grid itself — drag a tile to move it, R to rotate the held tile, click to equip/use, right-click
	# to drop. Cells size to the SLOT: the resized hook below feeds the grid the scroll slot's height as its
	# max_view_height budget, so all rows fit whole at the real 792x444 canvas (6x5 backpack ≈ 41px cells, no
	# scrollbar) — the old width-only sizing guaranteed a permanent scrollbar hiding most of the bottom row.
	# The scroll (vertical only; horizontal off — both authored in the scene, so the grid sizes its cells to the
	# width) is just the fallback for windows too short to fit even MIN_CELL-sized rows. The grid view itself
	# stays CODE-instantiated into the authored slot (dynamic content, never scene chrome).
	var scroll: ScrollContainer = %Scroll
	_grid_view = GridInventoryView.new()
	scroll.add_child(_grid_view)
	scroll.resized.connect(_on_grid_slot_resized.bind(scroll))  # bound method, not a lambda (freed-capture safety)
	_grid_view.activate_requested.connect(_on_grid_activate)
	_grid_view.drop_requested.connect(_on_grid_drop)
	_grid_view.hover_changed.connect(_on_grid_hover_changed)

	# Footer status line under the grid (footer + label authored in the scene): the carry weight when idle, the
	# hovered item's breakdown on hover. (Cash is NOT here — it reads on the wallet row above the grid, and on
	# the top-left HUD.) The detail Label lives inside a FIXED-HEIGHT clip host (the make_hint_footer
	# construct, shared with LootScreen — the height math below mirrors it): reserving a min height on the Label
	# alone was not enough — an unusually long tooltip (a weapon's full stat block) exceeds it, and because a
	# Label reports its full wrapped height as its min size, the VBox grew the footer and SHRANK the EXPAND_FILL
	# grid above, which recomputed its cell size — the whole grid pumped on hover. The height snaps to a whole
	# number of RENDERED lines, so an overflow clips between lines rather than through the last row's glyphs.
	# Budget = MenuSkin.footer_hint_lines.
	_detail = %Detail
	MenuStyle.style_hint(_detail)  # dim wrap-friendly footnote styling from the skin
	var line_h: float = _detail.get_line_height()
	if line_h <= 0.0:
		line_h = float(MenuStyle.skin.hint_size + 4)  # font not resolvable yet — the pre-measurement estimate
	(%Footer as Control).custom_minimum_size.y = float(maxi(MenuStyle.skin.footer_hint_lines, 1)) * line_h

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
	_paint_wallet()
	_show_weight()


## Paint the wallet row from the LIVE `money` float (the single source of truth — there is no derived stack to
## read any more). Gold while solvent, danger when a wallet somehow reads negative, matching the HUD readout.
## The Drop button dims on an empty purse so the row states up-front whether a press can do anything.
func _paint_wallet() -> void:
	if not is_instance_valid(_player):
		return
	var cash: float = _player.money
	_wallet.text = PlayerText.wallet_row(cash)
	_wallet.add_theme_color_override(&"font_color", MenuStyle.wallet_color(cash))
	_drop_money_btn.disabled = cash <= 0.0


## The wallet row's button — ask how much, then spill exactly that as a physics money bag. The prompt clamps
## to the cap we hand it (and drop_money clamps again), so _drop_money can never be given more than we carry.
func _on_drop_money_pressed() -> void:
	if not is_instance_valid(_player):
		return
	_amount_prompt.ask(PlayerText.WALLET_DROP_TITLE, _player.money, PlayerText.WALLET_DROP, _drop_money)


## Commit the prompt's answer. Gated on the wallet ACTUALLY shrinking: drop_money returns void but no-ops when
## the player is off-tree (nowhere to spawn the bag), and a spill that never happened must not sound like one.
func _drop_money(amount: float) -> void:
	if not is_instance_valid(_player):
		return
	var before := _player.money
	_player.drop_money(amount)
	if _player.money < before:
		MenuStyle.play_commit()  # HEAVY: cash leaving the wallet for the floor
	else:
		MenuStyle.play_denied()
	_paint_wallet()

## Put the carry-weight readout on the footer status line (the idle state; hovering an item overrides it).
func _show_weight() -> void:
	if not is_instance_valid(_player) or _player.inventory == null:
		return
	var enc: bool = _player.is_encumbered()
	_detail.text = PlayerText.inventory_weight(_player.inventory.total_weight(), _player.carry_capacity, enc)
	_detail.add_theme_color_override(&"font_color", MenuStyle.danger() if enc else MenuStyle.dim_color())

## A grid tile was clicked (no drag) — route by type: equip/unequip a weapon, use a consumable, refuse the rest.
func _on_grid_activate(item: Item) -> void:
	if item == null:
		return
	if item.is_weapon():
		_on_item_pressed(item)
	elif item.is_consumable():
		_on_use_pressed(item)
	else:
		# "ignore the rest" used to mean ignore it SILENTLY — clicking junk, a quest item or a holdable prop
		# was the one tile press in the bag that produced nothing at all, which reads as the grid being broken
		# rather than the item being inert. Both branches above answer on every path, so this is the last one.
		MenuStyle.play_denied()

## A grid tile was right-clicked — drop JUST THE CLICKED STACK to the world (dropping the wielded weapon falls
## back to fists). Passes the stack's `key` so the player removes THAT exact stack (remove-BY-KEY) — NOT
## count_of(item) or newest-first: two dog crates no longer drop both, and the tile that empties is the one clicked.
func _on_grid_drop(item: Item, key: int) -> void:
	if item == null or not is_instance_valid(_player) or _player.inventory == null:
		return
	if item.id == Zorkmids.ITEM_ID:
		# DEFENSIVE, not a live path: cash converts to `money` at every seam that could hand the player coins
		# (LootScreen._take, MoneyPickUp, the debug `give` refusal), so a zorkmids stack can no longer reach the
		# backpack. If one ever does, route it to the wallet's own gesture rather than drop_stack — that would
		# mint a money-bag world object holding NO money while the wallet float sat untouched.
		_on_drop_money_pressed()
		return
	_player.drop_stack(item, key)  # removes THAT stack from the bag -> inventory.changed -> _rebuild refreshes
	# A grid tile is a plain Control (GridInventoryView/GridTile extend Control, not BaseButton), so the auto-wired
	# button click never reaches it — this is the ONLY cue on the press, no double.
	MenuStyle.play_select()

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
		MenuStyle.play_back()               # putting the gun AWAY is a de-escalation, so it wears the back cue rather than a confirm
	elif _player.inventory.equip_item(item):  # -> equip_weapon_requested -> Player draws it (swap anim)
		MenuStyle.play_select()             # gated on equip_item's own bool
	else:
		MenuStyle.play_denied()             # a refused equip (non-weapon, or a bag that won't hand it over)
	_rebuild()                              # refresh the (equipped) marker

func _on_use_pressed(item: Item) -> void:
	# Gated on use_consumable's success bool: it refuses (and consumes nothing) at FULL HP. The confirm cue must
	# not fire there — it would tell the player they'd just spent a health pack — but the press can't be silent
	# either, or a medkit click at full health is indistinguishable from a broken tile. The denial says "kept it".
	if is_instance_valid(_player) and _player.use_consumable(item):  # heals + consumes one -> inventory.changed -> _rebuild refreshes the stack
		MenuStyle.play_select()
	else:
		MenuStyle.play_denied()
