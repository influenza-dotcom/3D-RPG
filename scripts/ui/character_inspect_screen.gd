extends CanvasLayer
## CharacterInspectScreen — a dedicated FULLSCREEN "inspect your character" view (the Dota-2 hero-showcase idea):
## a large, studio-lit, drag-to-rotate 3D character on a pedestal with the EQUIPPED WEAPON in hand, alongside a
## read-only summary (name / level / wallet / the six stats / the drawn weapon). Opened from the Stats screen's
## "Inspect" button; it is NOT part of the Pip-Boy tab group (it's a full takeover), just a standalone overlay.
##
## Like the other player menus it does NOT pause the world (real-time, Deus Ex style — you stay vulnerable while
## admiring your guy) and runs PROCESS_MODE_ALWAYS. It frees the mouse for the UI (so you can drag/zoom the model)
## and restores gameplay capture on close. Registered in InputManager's modal registry (pausing = false) so the
## don't-stack guard and the death/quickload sweep cover it automatically; it has NO hotkey of its own — it's only
## reached programmatically from Stats (mirroring how the station screens open without a key).

signal opened
signal closed

const PANEL_MARGIN := 0.06
## Same six stats, in the same order, as the Stats screen — the compact summary mirrors it.
const STATS: Array[StringName] = [&"strength", &"endurance", &"gunplay", &"agility", &"streetwise", &"larceny"]
const PlayerMenus := preload("res://scripts/ui/player_menus.gd")  ## tab-group helper — used only to close an open sibling tab

var _root: Control
var _preview: CharacterPreview   ## the big full-body hero view (drag/zoom + weapon in hand)
var _name_label: Label
var _summary: Label
var _stat_list: VBoxContainer
var _weapon_label: Label
var _is_open := false
var _player: Player = null

func _ready() -> void:
	layer = 121                                  # just above the Stats screen (120), below OptionsMenu (128)
	process_mode = Node.PROCESS_MODE_ALWAYS      # real-time overlay — keep rendering/input while the world runs beneath
	_build_ui()
	_root.visible = false

func is_open() -> bool:
	return _is_open

## Open the inspect view over the live human player. Refuses in the same cases the Stats screen does (a conversation,
## the settings/loot overlays, any pausing modal, mid-death), and when there's no player to show. Closes any open
## Pip-Boy tab first — this is a fullscreen takeover, not a sibling tab.
func open() -> void:
	if _is_open or DialogueManager.is_active() or OptionsMenu.is_open() \
			or LootScreen.is_open() or InputManager.any_pausing_open() \
			or not PlayerMenus.player_alive(get_tree()):
		return
	_player = _find_real_player() as Player
	if not is_instance_valid(_player):
		return
	# Full takeover: switch off any open real-time tab (Inventory/Stats/Reputation/Journal) before we cover the screen.
	PlayerMenus.close_others(null)
	_is_open = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE  # free the cursor so the player can drag/zoom the model
	_rebuild()
	_preview.set_active(true)  # start the live render + turntable only while up
	_root.visible = true
	opened.emit()

func close() -> void:
	if not _is_open:
		return
	_is_open = false
	_root.visible = false
	_preview.set_active(false)  # stop rendering the model off-screen while closed
	# Return the cursor to gameplay unless some OTHER modal is still up (defensive — normally we close straight to play).
	if not InputManager.any_modal_open(self):
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	closed.emit()

## Live-refresh the summary while open (non-pausing: the wallet / stat modifiers can shift under you as you read).
func _process(_delta: float) -> void:
	if _is_open and is_instance_valid(_player):
		_refresh_summary()

func _unhandled_input(event: InputEvent) -> void:
	if _is_open and event.is_action_pressed(&"ui_cancel"):
		close()  # Esc closes back to gameplay (consume it so OptionsMenu doesn't also open behind us)
		get_viewport().set_input_as_handled()

## The human player, not a companion (companions join &"Player" for targeting but are NPCs).
func _find_real_player() -> Node:
	return Groups.human_player(get_tree())

# ---------------------------------------------------------------------------------------------------
# UI
# ---------------------------------------------------------------------------------------------------

func _build_ui() -> void:
	_root = Control.new()
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP  # eat clicks so nothing falls through to gameplay behind
	MenuStyle.apply(_root)
	add_child(_root)
	_root.add_child(MenuStyle.make_dim())

	var panel := PanelContainer.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	panel.anchor_left = PANEL_MARGIN
	panel.anchor_top = PANEL_MARGIN
	panel.anchor_right = 1.0 - PANEL_MARGIN
	panel.anchor_bottom = 1.0 - PANEL_MARGIN
	_root.add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", MenuStyle.skin.content_separation)
	panel.add_child(vbox)
	vbox.add_child(MenuStyle.make_title("Character"))

	# Body: the big hero view on the LEFT (most of the width), the read-only summary on the RIGHT.
	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", MenuStyle.skin.content_separation)
	vbox.add_child(body)

	_preview = CharacterPreview.new()
	_preview.auto_start = false           # persistent autoload — build the stage on first open
	_preview.allow_interaction = true     # drag to rotate, wheel to zoom
	_preview.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_preview.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_preview.size_flags_stretch_ratio = 1.7  # the model gets the lion's share of the width
	body.add_child(_preview)

	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.size_flags_vertical = Control.SIZE_EXPAND_FILL
	info.size_flags_stretch_ratio = 1.0
	info.add_theme_constant_override("separation", 4)
	body.add_child(info)

	_name_label = Label.new()
	_name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_name_label.add_theme_color_override(&"font_color", MenuStyle.accent())
	_name_label.add_theme_font_size_override(&"font_size", MenuStyle.skin.header_size)
	info.add_child(_name_label)

	_summary = MenuStyle.make_hint("")
	_summary.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	info.add_child(_summary)

	info.add_child(MenuStyle.make_separator())

	# The six stats, one compact "Title  value" line each (read-only; the Stats screen carries the full blurbs).
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.add_child(scroll)
	_stat_list = VBoxContainer.new()
	_stat_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_stat_list.add_theme_constant_override("separation", 3)
	scroll.add_child(_stat_list)

	info.add_child(MenuStyle.make_separator())
	_weapon_label = Label.new()
	_weapon_label.add_theme_color_override(&"font_color", MenuStyle.gold())
	info.add_child(_weapon_label)

	# Footer: the drag/zoom hint on the left, Back on the right.
	var footer := HBoxContainer.new()
	footer.add_theme_constant_override("separation", MenuStyle.skin.button_row_separation)
	vbox.add_child(footer)
	var hint := MenuStyle.make_hint("Drag to rotate  ·  Scroll to zoom")
	hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	footer.add_child(hint)
	var back := Button.new()
	back.text = "Back"
	back.custom_minimum_size = Vector2(MenuStyle.skin.dialog_button_min_width, 0)
	back.pressed.connect(close)
	footer.add_child(back)

## Stamp identity + appearance + weapon into the view, then refresh the summary lines.
func _rebuild() -> void:
	_name_label.text = _player.player_name
	_name_label.visible = not _player.player_name.is_empty()
	_preview.set_appearance(_player.appearance)     # the saved head/body/colours (empty -> the catalog default look)
	_preview.set_weapon(_equipped_weapon_data())    # the currently-drawn weapon, in hand
	_refresh_stats()
	_refresh_weapon_label()
	_refresh_summary()

## The WeaponData to render in the showcase's hand, or null for unarmed. Read defensively off the Weapon system's
## equipped_weapon — BUT the bare-hands FISTS fallback (what the hub wields whenever nothing is drawn) is reported
## as UNARMED here: fists.tres carries the melee hammer as its view_model, so without this special-case the
## "unarmed" character would stand gripping a hammer in the two-handed hold, contradicting the "Weapon: Unarmed"
## summary beside it. Null (no hub, no weapon, or the FISTS fallback) -> the preview shows the character
## empty-handed with the arms resting at their sides (CharacterPreview drops `holding` when the weapon is null).
func _equipped_weapon_data() -> WeaponData:
	var ws: Variant = _player.get(&"weapon_system") if is_instance_valid(_player) else null
	if ws == null:
		return null
	var wd: Variant = ws.get(&"equipped_weapon")
	if wd is WeaponData and not _is_unarmed_fallback(wd):
		return wd
	return null

## True when `wd` is the bare-hands FISTS fallback — the shared preloaded resource (Player.FISTS) the weapon hub
## equips whenever nothing else is drawn. The showcase renders it as unarmed (see _equipped_weapon_data), rather
## than mounting the melee hammer fists.tres carries as its view_model. Compared by instance first (both sides are
## the same preloaded resource) with a resource_path fallback as a belt-and-braces net should a swap path ever hand
## back a duplicate. Static + host-free so it's unit-testable off-tree (test_character_inspect_weapon.gd).
static func _is_unarmed_fallback(wd: WeaponData) -> bool:
	if wd == null or Player.FISTS == null:
		return false
	return wd == Player.FISTS or wd.resource_path == Player.FISTS.resource_path

## The top line: character LEVEL, live wallet, and any unspent perk points (mirrors the Stats screen summary).
func _refresh_summary() -> void:
	if not is_instance_valid(_player):
		return
	var txt := "Level %d   ·   %s zorkmids" % [_player.level, Zorkmids.fmt(_player.money)]
	_summary.text = txt

## The six stat lines, "Title   value" (with any live status modifier folded into the number).
func _refresh_stats() -> void:
	for c in _stat_list.get_children():
		c.queue_free()
	var s: CharacterStats = _player.stats_or_default()
	for stat in STATS:
		var row := Label.new()
		var base := s.get_stat(stat)
		var bonus := _stat_modifier(stat)
		var val := str(base) if is_zero_approx(bonus) else "%s (%+d)" % [base + int(roundf(bonus)), int(roundf(bonus))]
		row.text = "%s   %s" % [StatInfo.title(stat), val]
		_stat_list.add_child(row)

func _stat_modifier(stat: StringName) -> float:
	if is_instance_valid(_player) and _player.has_method(&"status_stat_modifier"):
		return float(_player.status_stat_modifier(stat))
	return 0.0

## The drawn-weapon line: the equipped backpack item's name (a weapon), else "Unarmed".
func _refresh_weapon_label() -> void:
	var name_txt := "Unarmed"
	var inv: Variant = _player.get(&"inventory") if is_instance_valid(_player) else null
	if inv != null:
		var it: Variant = inv.get(&"equipped_item")
		if it != null and it is Item and (it as Item).is_weapon():
			name_txt = (it as Item).display_name
	_weapon_label.text = "Weapon:  %s" % name_txt
