extends CanvasLayer
## LootScreen — the transfer overlay for LOOTING a corpse or PICKPOCKETING a live NPC. Autoload,
## non-pausing, clones the InventoryScreen / OptionsMenu pattern (frees the mouse on open; player control
## is suppressed via the is_open() gates). Two columns: the SOURCE's items (click one to TAKE all of it
## into the player) and the PLAYER's items (shown for context — transfer is one-way in v1). Opened by
## LootableCorpse.start_talk (open_for) or Talkable.start_talk while sneaking (pickpocket).

signal opened
signal closed

const PANEL_MARGIN := 0.12  ## fraction of the screen left as a border around the panel (any resolution)
const _DEFAULT_HINT := "Click an item to take / deposit it · drag to rearrange your grid"  ## detail line when nothing is hovered

var _root: Control
var _title: Label
var _source_grid: GridInventoryView   ## the SOURCE bag as a grid (corpse / container / pockets) — click a tile to TAKE
var _player_grid: GridInventoryView   ## the PLAYER bag as a grid — click a tile to DEPOSIT into the source; drag to rearrange
var _detail: Label                    ## hovered-item breakdown shown under the grids (shared by both)
var _is_open := false
var _prev_mouse_mode: Input.MouseMode = Input.MOUSE_MODE_CAPTURED
var _player: Player = null
var _source_inv: CharacterInventory = null  ## the inventory being looted / pickpocketed
var _free_when_empty: Node = null           ## a corpse to free when emptied; null for a LIVE source (pickpocket)
var _source_heading: Label = null           ## the SOURCE column's heading, retitled per-open ("Corpse" / "Pockets")
## Whatever carries the lootable WALLET: a LootableCorpse (its copied money) or a LIVE pickpocketed NPC
## (Character.money — yes, you can lift the cash straight out of their pocket). Null = no money to offer
## (containers). Read/zeroed dynamically; the "Take N zm" button shows while it holds anything.
var _money_source: Node = null
var _money_btn: Button = null
## The CHARACTER whose carry limit caps what the player can GIVE (deposit): a live exchange / pickpocket
## target. Null (corpses, containers) = unlimited dumping, as before. Read dynamically (carry_capacity).
var _capacity_owner: Node = null

func _ready() -> void:
	layer = 121                                  # above the HUD / inventory, peer of the modal overlays
	process_mode = Node.PROCESS_MODE_ALWAYS      # keep working regardless of any pause
	_build_ui()
	_root.visible = false

func is_open() -> bool:
	return _is_open

# ---------------------------------------------------------------------------------------------------
# Open / close
# ---------------------------------------------------------------------------------------------------

## Open the loot transfer for `corpse`, looting into `player`. Refuses to stack over another modal /
## dialogue, and bails safely on an invalid corpse or no player (start-menu / test safety).
func open_for(corpse: LootableCorpse, player: Node) -> void:
	if not is_instance_valid(corpse) or corpse.inventory == null:
		return
	var who := "LOOTING %s" % corpse.corpse_name if not corpse.corpse_name.is_empty() else "LOOTING"
	_open(corpse.inventory, corpse, player, who, "Corpse", corpse)

## Pickpocket a LIVE character: loot their inventory WITHOUT freeing them. Opened by Talkable.start_talk
## when the player is crouched and the NPC is unaware (off-guard).
func pickpocket(npc: Node, player: Node) -> void:
	if not is_instance_valid(npc):
		return
	var inv: Variant = npc.get(&"inventory")
	if not (inv is CharacterInventory):
		return
	var name_v: Variant = npc.get(&"display_name")
	var nm: String = name_v if name_v is String else ""
	var who := "PICKPOCKETING %s" % nm if not nm.is_empty() else "PICKPOCKETING"
	# The live NPC's wallet is liftable too, and PLANTING items on them respects their carry limit.
	_open(inv, null, player, who, "Pockets", npc, npc)

## EXCHANGE GEAR with a FOLLOWING ALLY (the "Exchange Gear" dialogue option, offered only to companions
## actively following you — the gate lives in DialogueManager._speaker_exchange_npc): the same two-way
## transfer screen, no sneaking required — equipment only (no wallet button; robbing a friend's cash isn't
## "exchanging"), and what you GIVE is capped by their carry capacity.
func exchange(npc: Node, player: Node) -> void:
	if not is_instance_valid(npc):
		return
	var inv: Variant = npc.get(&"inventory")
	if not (inv is CharacterInventory):
		return
	var name_v: Variant = npc.get(&"display_name")
	var nm: String = name_v if name_v is String else ""
	var who := "EXCHANGING GEAR — %s" % nm if not nm.is_empty() else "EXCHANGING GEAR"
	_open(inv, null, player, who, "Their Gear", null, npc)

## Open a persistent CONTAINER's inventory (a crate / chest / locker). Like open_for, but the container is
## NEVER freed when emptied — it's a fixture you can also deposit into. Opened by Container.start_talk.
func open_container(container: Node, player: Node) -> void:
	if not is_instance_valid(container):
		return
	var inv: Variant = container.get(&"inventory")
	if not (inv is CharacterInventory):
		return
	var name_v: Variant = container.get(&"container_name")
	var nm: String = name_v if name_v is String else ""
	var who := "LOOTING %s" % nm if not nm.is_empty() else "CONTAINER"
	# Pass the container as the money source too -- a crate can stash zorkmids (ItemContainer.money), looted via
	# the same "Take N zm" row a corpse offers. A container with no `money` property just reads 0 (no row shown).
	_open(inv, null, player, who, "Container", container)

## Shared open: bind the source + player inventories, free the mouse, show the title + columns. Refuses to
## stack over another modal / dialogue, and bails on no source / no player.
func _open(source_inv: CharacterInventory, free_when_empty: Node, player: Node, title: String, source_heading: String, money_source: Node = null, capacity_owner: Node = null) -> void:
	if _is_open or DialogueManager.is_active() or OptionsMenu.is_open() or InventoryScreen.is_open() or ShopScreen.is_open() or HealScreen.is_open() or LevelUpScreen.is_open() or RespecScreen.is_open():
		return
	if source_inv == null:
		return
	_player = player as Player
	if not is_instance_valid(_player) or _player.inventory == null:
		return
	_source_inv = source_inv
	_free_when_empty = free_when_empty
	_money_source = money_source
	_capacity_owner = capacity_owner
	# Give the SOURCE a spatial grid (lazily, once) so it renders as a grid alongside the player's bag — the
	# Tetris-loot view. Generous size (InventorySettings.container_grid) so the whole loadout auto-places; guarded
	# so re-opening a persistent container keeps its layout. The player's bag is already grid-enabled by Player._ready.
	if not source_inv.grid_enabled():
		source_inv.enable_grid(GameSettings.inventory.container_grid_cols, GameSettings.inventory.container_grid_rows)
	_source_grid.bind(source_inv)
	_player_grid.bind(_player.inventory)
	_bind(true)
	_is_open = true
	_prev_mouse_mode = Input.mouse_mode
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_title.text = title
	if _source_heading != null:
		_source_heading.text = source_heading
	_detail.text = _DEFAULT_HINT
	_rebuild()
	_root.visible = true
	opened.emit()

func close() -> void:
	if not _is_open:
		return
	_bind(false)
	_is_open = false
	_root.visible = false
	Input.mouse_mode = _prev_mouse_mode
	# A LIVE NPC (pickpocket / exchange — marked by a capacity owner) only got its grid for THIS session's render;
	# turn it back off so its bag isn't permanently bounded (corpses/containers keep their layout). Corpses are
	# freed on empty anyway; persistent containers WANT the layout to persist, so they keep the grid.
	if _capacity_owner != null and is_instance_valid(_source_inv):
		_source_inv.disable_grid()
	_source_grid.bind(null)  # drop the bound inventories so the views never hold a stale ref after close
	_player_grid.bind(null)
	_source_inv = null
	_free_when_empty = null
	_money_source = null
	_capacity_owner = null
	_player = null
	closed.emit()

## (Dis)connect both inventories' `changed` so the two columns refresh on any transfer. is_instance_valid
## guards a corpse freed mid-loot; Godot also auto-drops the connection when a node frees.
func _bind(on: bool) -> void:
	var invs := [
		_source_inv if is_instance_valid(_source_inv) else null,
		_player.inventory if is_instance_valid(_player) else null,
	]
	for inv in invs:
		if inv == null:
			continue
		if on and not inv.changed.is_connected(_on_changed):
			inv.changed.connect(_on_changed)
		elif not on and inv.changed.is_connected(_on_changed):
			inv.changed.disconnect(_on_changed)

func _on_changed() -> void:
	if _is_open:
		_rebuild()

func _unhandled_input(event: InputEvent) -> void:
	# Close on the SAME Interact key that opens it (the ray consumes the OPENING press, so this only fires on
	# a later press — see ray_cast.gd, which skips interacting while we're open), or on Esc.
	if _is_open and (event.is_action_pressed(InputManager.action_pickup) or event.is_action_pressed(&"ui_cancel")):
		close()
		get_viewport().set_input_as_handled()

# ---------------------------------------------------------------------------------------------------
# Transfer + lists
# ---------------------------------------------------------------------------------------------------

## Take ALL of `item` from the corpse into the player. When the corpse is fully drained (no items AND no
## wallet left), close + free it — nothing left to loot.
func _take(item: Item) -> void:
	if not is_instance_valid(_source_inv) or not is_instance_valid(_player) or _player.inventory == null:
		return
	var want := _source_inv.count_of(item)
	var moved := _source_inv.transfer_to(_player.inventory, item, want)
	# A bounded (Tetris) bag may not fit everything — what didn't fit stays on the source (transfer_to rolls it
	# back). Say so rather than letting the click look like it silently did nothing.
	if moved < want and _player.has_method(&"notify_toast"):
		_player.notify_toast("No room for all of that", Color(0.85, 0.85, 0.85))
	_maybe_free_drained_corpse()

## Take the source's WALLET: the corpse's copied money, or a live pickpocket target's pocket cash. The
## nudge through on_wallet_drained lets the ragdoll's linger-until-drained fade see a cash-only loot end.
func _take_money() -> void:
	if not is_instance_valid(_player) or _money_source == null or not is_instance_valid(_money_source):
		return
	var amount := _source_money()
	if amount <= 0.0:
		return
	_money_source.set(&"money", 0.0)
	_player.add_money(amount)
	if _money_source is LootableCorpse:
		(_money_source as LootableCorpse).on_wallet_drained()
	_rebuild()
	_maybe_free_drained_corpse()

## The source's wallet, type-guarded: a vanished source, or one without a `money` property at all
## (a plain container / a test stub), reads as 0 instead of crashing float() on a null get().
func _source_money() -> float:
	if _money_source == null or not is_instance_valid(_money_source):
		return 0.0
	var raw: Variant = _money_source.get(&"money")
	return float(raw) if raw is float or raw is int else 0.0

## True once the source holds NOTHING — bag empty and no wallet cash left on the money source.
func _source_drained() -> bool:
	if is_instance_valid(_source_inv) and not _source_inv.is_empty():
		return false
	if _source_money() > 0.0:
		return false
	return true

## Close + free a fully drained temporary CORPSE (free_when_empty != null). A persistent CONTAINER (and a
## live pickpocket source) has free_when_empty == null: it STAYS OPEN showing "(empty)" so you can keep
## depositing — close it manually with Esc / the interact key.
func _maybe_free_drained_corpse() -> void:
	if not _source_drained():
		return
	var emptied := _free_when_empty
	if emptied != null:
		close()
		# A standalone corpse cleans itself up here; a skeleton-attached one is faded by its ragdoll.
		if is_instance_valid(emptied) and not (emptied.get_parent() is Ragdoll):
			emptied.queue_free()

## Deposit `item` from the player INTO the source (the reverse of _take) — the whole stack, except that a
## LIVE receiver (exchange / pickpocket-planting) takes only what fits under its CARRY CAPACITY: NPCs can't
## be given more than they can carry. Corpses / containers have no owner and accept anything, as before.
## Depositing the wielded weapon is allowed: you fall back to bare fists once it leaves the bag.
func _deposit(item: Item) -> void:
	if not is_instance_valid(_source_inv) or not is_instance_valid(_player) or _player.inventory == null:
		return
	var count := _player.inventory.count_of(item)
	if _capacity_owner != null and is_instance_valid(_capacity_owner):
		# .get(), not a direct access: the owner is duck-typed, and a receiver WITHOUT a
		# carry_capacity property (a stub / non-Character) is simply uncapped, like a container.
		var cap: Variant = _capacity_owner.get(&"carry_capacity")
		if cap is float or cap is int:
			count = _fits_under_capacity(item, count, _source_inv.total_weight(), float(cap))
			if count <= 0:
				if _player.has_method(&"notify_toast"):
					_player.notify_toast("They can't carry any more", Color(0.85, 0.85, 0.85))
				return
	# Depositing the weapon you're WIELDING is allowed: the transfer clears the backpack's equipped_item,
	# which fires equipped_item_lost -> the player falls back to bare fists. No need to swap first.
	var moved := _player.inventory.transfer_to(_source_inv, item, count)
	# The source now has a spatial grid (T4) — it can run out of room. transfer_to rolls back what didn't fit;
	# say so rather than letting a click look like it did nothing.
	if moved < count and _player.has_method(&"notify_toast"):
		_player.notify_toast("No room left in there", Color(0.85, 0.85, 0.85))

## How many of `item` (holding `have`) still FIT under `capacity` for a receiver already carrying
## `load_weight` — the give-cap math, pure + static for the tests. Weightless items always fit; an
## already-over-capacity receiver takes nothing.
static func _fits_under_capacity(item: Item, have: int, load_weight: float, capacity: float) -> int:
	if item == null or have <= 0:
		return 0
	if item.weight <= 0.0:
		return have
	return clampi(int(floor((capacity - load_weight) / item.weight)), 0, have)

func _rebuild() -> void:
	# Re-read both grids (the source you TAKE from, your bag you DEPOSIT from). The grid views render the tiles;
	# the transfer happens on a tile click (wired in _open: source -> _take, player -> _deposit).
	_source_grid.refresh()
	_player_grid.refresh()
	# The wallet row: shown while the source carries cash (a corpse's pocketed money, or a live pickpocket
	# target's). Hidden for containers / drained sources.
	if _money_btn != null:
		# Use the existing type-guarded _source_money() helper rather than re-reading `money` off the Node with
		# a dead null-branch (Node.get() returns null only when absent — already handled as 0.0 in the helper).
		var cash := _source_money()
		_money_btn.visible = cash > 0.0
		_money_btn.text = "Take %s zm" % Zorkmids.fmt(cash)

## Click a SOURCE tile -> take that whole stack into the player (the grid view emits activate_requested).
func _on_source_activate(item: Item) -> void:
	if item != null:
		_take(item)

## Click one of YOUR tiles -> deposit that stack into the source.
func _on_player_activate(item: Item) -> void:
	if item != null:
		_deposit(item)

## Either grid's hover changed -> show that item's breakdown under the grids (or the click/drag hint). The holder
## inventory (for a weapon's spare-ammo line) is whichever bag actually holds the item.
func _on_hover(item: Item) -> void:
	if item == null:
		_detail.text = _DEFAULT_HINT
		return
	var holder: CharacterInventory = null
	if is_instance_valid(_player) and _player.inventory != null and _player.inventory.has(item):
		holder = _player.inventory
	elif is_instance_valid(_source_inv):
		holder = _source_inv
	_detail.text = ItemInfo.tooltip(item, holder)

# ---------------------------------------------------------------------------------------------------
# UI construction
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
	vbox.add_theme_constant_override("separation", 8)
	panel.add_child(vbox)

	_title = MenuStyle.make_title("LOOTING")  # dynamic title; _open reassigns _title.text per-open
	vbox.add_child(_title)

	# The wallet row — gold like the HUD's zorkmid readout; hidden until _rebuild finds cash on the source.
	_money_btn = Button.new()
	_money_btn.focus_mode = Control.FOCUS_NONE
	_money_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_money_btn.add_theme_color_override(&"font_color", MenuStyle.gold())
	_money_btn.visible = false
	_money_btn.pressed.connect(_take_money)
	vbox.add_child(_money_btn)

	# The two grids are STACKED VERTICALLY (not side-by-side): at the 396px viewport a half-width column can't fit
	# a 10-wide grid, but a full-width one sizes its cells comfortably. Source on top, your bag below.
	var headers: Array = []
	_source_grid = _build_grid_section(vbox, "Source", headers)
	_source_heading = headers[0]  # remember the SOURCE heading so _open can retitle it ("Corpse" / "Pockets" / ...)
	_player_grid = _build_grid_section(vbox, "You", headers)
	_source_grid.activate_requested.connect(_on_source_activate)
	_source_grid.hover_changed.connect(_on_hover)
	_player_grid.activate_requested.connect(_on_player_activate)
	_player_grid.hover_changed.connect(_on_hover)

	# Detail line under both grids: the hovered item's breakdown, else the click/drag hint.
	_detail = MenuStyle.make_hint(_DEFAULT_HINT)
	_detail.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(_detail)

## A titled, scrollable GRID section added to `parent`; returns its GridInventoryView and appends its header Label
## to `headers` (so _build_ui can keep the SOURCE header for per-open retitling).
func _build_grid_section(parent: VBoxContainer, heading: String, headers: Array) -> GridInventoryView:
	var head := Label.new()
	head.text = heading
	head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	head.add_theme_font_size_override("font_size", MenuStyle.skin.header_size)
	parent.add_child(head)
	headers.append(head)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(scroll)
	var grid := GridInventoryView.new()
	scroll.add_child(grid)
	return grid
