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
##
## AUTHORED SCENE: the layout lives in scenes/ui/character_inspect_screen.tscn (this autoload IS that
## scene — see project.godot [autoload]); this script binds its chrome by %unique name in _bind_ui and
## applies the skin-driven look (MenuStyle style_* adopters + skin reads) on top, so a designer rearranges
## the panel in the editor and the skin keeps owning colours/fonts/separations. NO text is authored in the
## scene — every string is set here from PlayerText (l10n + the text-debt ratchet own strings, never a
## .tscn). The CharacterPreview hero view stays CODE-instantiated into the authored %PreviewSlot (a runtime
## 3D stage, not chrome a designer lays out), and the six stat lines stay CODE-built into %StatList.
## tests/test_character_inspect_screen_scene.gd pins the wiring.
##
## NO POST-PROCESS OVERLAY (removed 2026-08-04, and don't re-add one per-screen). This screen used to carry a
## full-rect "RetroPass" ColorRect that BORROWED the live post-process material off the player's HUD rect
## (Player/UI/ColorRect) to re-run the PS1 posterize/dither/grain over the takeover, so it wouldn't be the one
## crisp render in a warped game. It was a legibility bug on two counts:
##   1. DOUBLE PASS. The world beneath is already processed by that HUD rect; this overlay sits at layer 121
##      ABOVE it and re-reads SCREEN_TEXTURE — so the whole frame (menu included) got posterized, dithered
##      and grained a SECOND time. That is the "static/CRT" mush.
##   2. GAMEPLAY UNIFORMS BLED IN. Sharing the material (deliberately, so death/NV stayed in lock-step) meant
##      the menu also wore `low_hp`'s vignette, `hurt`'s red tint, night vision's green, and the death fade —
##      i.e. the darker and less readable your character sheet got, the worse your HP was.
## No other menu does this: shop/inventory/stats/loot all render un-warped over the processed world, so the
## overlay also made this ONE screen inconsistent with the rest of the UI. If a PS1 pass over menus is ever
## wanted, it belongs on the skin as ONE opt-in for every screen (MenuSkin), never re-borrowed per screen.

signal opened
signal closed

const PANEL_MARGIN := 0.12  ## fraction of the screen left as a border — SAME margin as the inventory/loot/shop screens, so every inventory-style menu shares one chrome (authored on the scene's Panel anchors; the scene test pins the band)
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
	_bind_ui()
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
	# Return the cursor to gameplay unless some OTHER modal is still up (defensive — normally we close straight
	# to play) or a Pip-Boy tab hotkey is mid-SWITCH into its screen: PlayerMenus.enter() closes this takeover
	# inside its _switching window, and recapturing here would round-trip the cursor through CAPTURED
	# (recentering it) an instant before the incoming tab frees it again.
	if not PlayerMenus.switching() and not InputManager.any_modal_open(self):
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	closed.emit()

## Live-refresh the summary while open (non-pausing: the wallet / stat modifiers can shift under you as you read).
func _process(_delta: float) -> void:
	if _is_open and is_instance_valid(_player):
		_refresh_summary()

func _unhandled_input(event: InputEvent) -> void:
	# Esc OR the Interact key closes back to gameplay — ui_cancel has NO gamepad binding, so action_pickup
	# (pad Y) is the controller's exit, the same close idiom as the loot/shop screens. Consume it so nothing
	# behind us also reacts (OptionsMenu on Esc, the pickup ray on Interact).
	if _is_open and (event.is_action_pressed(InputManager.action_pickup) or event.is_action_pressed(&"ui_cancel")):
		close()
		get_viewport().set_input_as_handled()

## The human player, not a companion (companions join &"Player" for targeting but are NPCs).
func _find_real_player() -> Node:
	return Groups.human_player(get_tree())

# ---------------------------------------------------------------------------------------------------
# UI binding (the layout is AUTHORED in scenes/ui/character_inspect_screen.tscn — this adopts it)
# ---------------------------------------------------------------------------------------------------

## Bind the authored chrome by %unique name, style it from the skin, and wire behaviour. The scene owns
## STRUCTURE (the PANEL_MARGIN 0.12 anchor band, the hero/info HBox split with its 1.7-vs-1.0 stretch
## ratios, the info column's literal 4px leading, the stat scroll with horizontal scroll authored OFF,
## the stat list's literal 3px leading, the footer spacer that pins Back right); the skin keeps owning
## LOOK — every colour/font/separation/width below is a MenuStyle/skin read, so reskinning via
## resources/ui/menu_skin.tres restyles this screen with zero scene edits.
func _bind_ui() -> void:
	_root = %Root  # full-rect, MOUSE_FILTER_STOP authored — eats clicks so nothing falls through to gameplay behind
	MenuStyle.apply(_root)  # shared menu Theme (panel/buttons/tooltips/fonts) — reskin via resources/ui/menu_skin.tres
	MenuStyle.style_dim(%Dim)

	(%VBox as VBoxContainer).add_theme_constant_override("separation", MenuStyle.skin.content_separation)  # shared per-screen rhythm (skin Layout group)
	var title: Label = %Title
	MenuStyle.style_title(title)  # title font/size/colour + ellipsis (the make_title twin); centring is authored
	title.text = MenuStyle.title_text(PlayerText.CHARACTER_INSPECT_TITLE)

	# Body: the big hero view on the LEFT (most of the width), the read-only summary on the RIGHT.
	(%Body as HBoxContainer).add_theme_constant_override("separation", MenuStyle.skin.content_separation)

	# The hero view stays CODE-instantiated (a runtime 3D stage, not chrome a designer lays out) into the
	# authored %PreviewSlot, which carries the layout share (EXPAND_FILL both, stretch 1.7 — the model gets
	# the lion's share of the width); the preview just fills the slot.
	_preview = CharacterPreview.new()
	_preview.auto_start = false           # persistent autoload — build the stage on first open
	_preview.allow_interaction = true     # drag to rotate, wheel to zoom
	_preview.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_preview.size_flags_vertical = Control.SIZE_EXPAND_FILL
	%PreviewSlot.add_child(_preview)

	# cap_label: an uncapped Label reports its full text width as min size, which would widen the info column
	# (the stat scroll disables horizontal scroll, so nothing absorbs it) and SQUEEZE the hero preview —
	# a long string clips with "…" instead. Same treatment on the stat rows + weapon line below.
	# The scene also authors the label's auto_translate_mode = DISABLED: a player-TYPED name is never a
	# translation msgid (Control-text atr).
	_name_label = MenuStyle.cap_label(%NameLabel)
	_name_label.add_theme_color_override(&"font_color", MenuStyle.accent())
	_name_label.add_theme_font_size_override(&"font_size", MenuStyle.skin.header_size)

	_summary = %Summary
	MenuStyle.style_hint(_summary)  # dim wrap-friendly footnote look (the make_hint twin); centring is authored

	# The six stats, one compact "Title  value" line each (read-only; the Stats screen carries the full
	# blurbs) — CODE-built rows into the authored %StatList inside the authored scroll (h-scroll OFF so a
	# long line clips instead of widening the column).
	_stat_list = %StatList

	_weapon_label = MenuStyle.cap_label(%WeaponLabel)  # clip, don't squeeze the preview (see _name_label)
	_weapon_label.add_theme_color_override(&"font_color", MenuStyle.gold())

	# Footer: no how-to hint (drag/zoom on a 3D showcase is discoverable; instructional prose is
	# tutorializing — user call). The authored spacer keeps Back pinned to the footer's right edge.
	MenuStyle.style_button_row(%Footer)
	var back: Button = %BackButton
	back.text = PlayerText.BACK
	back.custom_minimum_size = Vector2(MenuStyle.skin.dialog_button_min_width, 0)  # skin width pin — never authored into the scene
	back.pressed.connect(close)

	# NO RETRO PASS HERE — see the header note. This screen renders like every other menu.

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
## as UNARMED here: fists.tres carries a FIRST-PERSON arms rig as its view_model, so without this special-case the
## "unarmed" character would stand gripping a pair of disembodied forearms in the two-handed hold, contradicting the "Weapon: Unarmed"
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
## than mounting the first-person arms rig fists.tres carries as its view_model. Compared by instance first (both sides are
## the same preloaded resource) with a resource_path fallback as a belt-and-braces net should a swap path ever hand
## back a duplicate. Static + host-free so it's unit-testable off-tree (test_character_inspect_weapon.gd).
static func _is_unarmed_fallback(wd: WeaponData) -> bool:
	if wd == null or Player.FISTS == null:
		return false
	return wd == Player.FISTS or wd.resource_path == Player.FISTS.resource_path

## The top line: character LEVEL, live wallet, and any unspent perk points (mirrors the Stats screen summary
## through the SAME composer, so the two screens can't disagree about spare points).
func _refresh_summary() -> void:
	if not is_instance_valid(_player):
		return
	_summary.text = PlayerText.stats_summary(_player.level, _player.money, _unspent_points())

## Unspent perk points on the player's PerkManager child (0 if none) — the same child lookup the Stats screen
## and the level-up screen use.
func _unspent_points() -> int:
	if not is_instance_valid(_player):
		return 0
	for c in _player.get_children():
		if c is PerkManager:
			return (c as PerkManager).skill_points
	return 0

## The six stat lines, "Title   value" (with any live status modifier folded into the number).
func _refresh_stats() -> void:
	for c in _stat_list.get_children():
		c.queue_free()
	var s: CharacterStats = _player.stats_or_default()
	for stat in STATS:
		var row := MenuStyle.cap_label(Label.new())  # clip, don't squeeze the preview (see _name_label)
		var base := s.get_stat(stat)
		var bonus := _stat_modifier(stat)
		row.text = PlayerText.character_inspect_stat_row(stat, base, bonus)
		_stat_list.add_child(row)

func _stat_modifier(stat: StringName) -> float:
	if is_instance_valid(_player) and _player.has_method(&"status_stat_modifier"):
		return float(_player.status_stat_modifier(stat))
	return 0.0

## The drawn-weapon line: the equipped backpack item's name (a weapon), else "Unarmed".
func _refresh_weapon_label() -> void:
	var name_txt := ""
	var armed := false
	var inv: Variant = _player.get(&"inventory") if is_instance_valid(_player) else null
	if inv != null:
		var it: Variant = inv.get(&"equipped_item")
		if it != null and it is Item and (it as Item).is_weapon():
			name_txt = (it as Item).display_name
			armed = true
	_weapon_label.text = PlayerText.character_inspect_weapon(name_txt, armed)
