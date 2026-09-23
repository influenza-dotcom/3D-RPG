extends GutTest

## HudSkin (resources/ui/hud_skin.tres, scripts/ui/hud_skin.gd): the MenuSkin twin for the IN-GAME HUD —
## the one artist resource for the combat indicators (hitmarker, damage/aim arcs, sniper glints),
## compass/minimap fallback tints, optional crosshair/marker art, and the label/hotbar chrome those
## scripts previously hardcoded. Exposed as MenuStyle.hud (preloaded beside MenuStyle.skin, same
## null-fallback + set_hud_skin seam). Gameplay-tuning numbers stay on GameSettings.hud (HudSettings) —
## pinned here by the scope check.
##
## What is pinned, and how:
## - The PROMISES an artist's retune must keep (the combat rings each stay in their own band around the
##   crosshair, charge ramps start faint and end bright, HUD text keeps a legible outline, the minimap's
##   walls out-ink their ground) — checked on BOTH the bare script defaults (the null-fallback skin) and the
##   authored .tres (what ships), never as copies of the default literals.
## - That the CONSUMERS paint from the LIVE skin: a distinctive skin is swapped in and the real ui.gd /
##   hotbar.gd / minimap.gd / compass.gd code is driven, so a paint site that regressed to a literal (or
##   cached the skin) fails here. Per-consumer timing contracts live beside those widgets
##   (test_camera_input_ui.gd, test_hotbar.gd, test_minimap.gd, test_compass.gd).
## - The SHIP DECISION that no art is delivered yet: the shipped skin leaves the reticle, the hit-confirm, the map
##   rim and every minimap marker to their drawn primitives — driven through ui.gd and MinimapArt where observable.

## Loaded by PATH, not class_name, so this suite survives a stale global class cache (the ui.gd
## STAMINA_RING_SCRIPT idiom).
const SKIN_SCRIPT := "res://scripts/ui/hud_skin.gd"
const SKIN_RES := "res://resources/ui/hud_skin.tres"

var _saved_hud: Resource

func before_each() -> void:
	_saved_hud = MenuStyle.hud

func after_each() -> void:
	# MenuStyle.hud is process-wide: a swapped-in test skin must never leak into a later suite.
	if MenuStyle.hud != _saved_hud:
		MenuStyle.set_hud_skin(_saved_hud)
	_saved_hud = null

func _fresh() -> Resource:
	return load(SKIN_SCRIPT).new()

## The two skins every promise must hold for: the bare script defaults (what MenuStyle falls back to when the
## .tres is missing) and the authored resource the game actually ships.
func _skins() -> Dictionary:
	return {"bare HudSkin defaults": _fresh(), "authored hud_skin.tres": load(SKIN_RES)}

## One field per component group must exist (absence = a consumer wire in a later stage has nothing to
## read). Checked on the script's property list so a rename fails loudly here, not at a paint site.
func test_fields_exist_per_component_group() -> void:
	var s := _fresh()
	for field in [
		# Crosshair
		"crosshair_texture",
		# Hitmarker
		"hitmarker_duration", "hitmarker_tick_length", "hitmarker_gap", "hitmarker_thickness",
		"hitmarker_pop_px", "hitmarker_color", "hitmarker_headshot_color", "hitmarker_headshot_scale",
		"hitmarker_texture",
		# Damage direction arcs
		"damage_arc_duration", "damage_arc_radius", "damage_arc_degrees", "damage_arc_thickness",
		"damage_arc_color",
		# Aim warning arcs
		"aim_arc_base_radius", "aim_arc_damage_to_pixels", "aim_arc_max_radius", "aim_arc_degrees",
		"aim_arc_thickness", "aim_arc_color", "aim_arc_min_alpha", "aim_arc_blink_period",
		"aim_arc_blink_dim_alpha", "aim_ping_radius", "aim_ping_ttl",
		# Sniper glints
		"glint_core_radius", "glint_streak_length", "glint_color", "glint_min_alpha", "glint_min_scale",
		# Compass / minimap
		"compass_fallback_color", "compass_marker_texture", "minimap_player_color", "minimap_npc_color",
		# Top-centre heading tape (2026-08-26, scripts/ui/hud_compass.gd) — shares the group above because it
		# reads the SAME marker channel and the same compass_fallback_color; these are its own ink.
		"compass_track_color", "compass_major_color", "compass_minor_color", "compass_tick_px",
		"compass_tick_width_px", "compass_label_baseline_px", "compass_outline_size", "compass_rim_px",
		"compass_edge_fade_px", "compass_marker_px", "compass_index_px", "compass_index_color",
		"minimap_wall_color", "minimap_walkable_color", "minimap_backing_color", "minimap_outline_color",
		"clock_color",
		"minimap_frame_texture",
		# Marker glyph paint (2026-08-13): the neutral body tint split OFF minimap_npc_color (which stays the
		# POI-beacon fallback), the hostile alert ring, the station family + its exit exception, the north tick.
		"minimap_neutral_color", "minimap_alert_color", "minimap_station_color", "minimap_exit_color",
		"minimap_north_color",
		# The player's own noise footprint (2026-08-26): the ring around the caret at the radius enemy hearing
		# tests against — the one thing this widget inks in world METRES rather than at a fixed pixel size.
		"minimap_noise_color", "minimap_noise_fill_color",
		# Minimap ART (2026-08-19): the drop-in marker slots that landed with the authored-scene conversion —
		# the caret, the POI beacon and the station alphabet, the three families a %MapOver scene node cannot
		# draw because their positions are recomputed every frame. See scripts/ui/minimap_art.gd.
		"minimap_player_texture", "minimap_poi_texture", "minimap_station_texture",
		"minimap_station_shop_texture", "minimap_station_bank_texture", "minimap_station_heal_texture",
		"minimap_station_train_texture", "minimap_station_tech_texture",
		"minimap_station_leisure_texture", "minimap_station_exit_texture",
		# Label + hotbar chrome
		"label_outline_color", "toast_outline_size", "look_name_outline_size",
		"corner_label_outline_size", "corner_label_outline_color", "corner_label_color",
		"hotbar_panel_modulate", "hotbar_key_color", "hotbar_count_color", "hotbar_name_outline_size",
	]:
		assert_true(field in s, "HudSkin exposes %s" % field)
	s = null

## THE CROSSHAIR ANNULUS BUDGET (stamina_ring.gd's note, hud_skin.gd's aim_arc_base_radius doc): every combat
## ring shares the crosshair's centre and is separated ONLY by radius. The headshot hit-confirm ticks at full
## pop must stay inside the aim-warning ring's inner edge, a fully charged aim ring (and the damage ping) must
## stay inside the hit-direction wedges, and the aim ring needs room to grow with the charge. An artist retune
## that breaks one of these paints two indicators over each other — this is what the old literal pins
## actually protected.
func test_combat_rings_keep_to_their_own_bands_around_the_crosshair() -> void:
	var skins := _skins()
	for label in skins:
		var s: Resource = skins[label]
		if s.hitmarker_texture == null:  # the drawn X: hitmarker.gd scales gap, pop AND tick length by the headshot mult
			var headshot_reach: float = (s.hitmarker_gap + s.hitmarker_pop_px + s.hitmarker_tick_length) \
				* s.hitmarker_headshot_scale
			assert_lt(headshot_reach, s.aim_arc_base_radius - s.aim_arc_thickness * 0.5,
				"%s: a headshot confirm's ticks (%.1f px) must end inside the aim-warning ring's inner edge, or a head hit paints over the red warning" % [label, headshot_reach])
		assert_gt(s.aim_arc_damage_to_pixels, 0.0, "%s: a bigger hit must grow a bigger aim ring" % label)
		assert_lte(s.aim_arc_base_radius, s.aim_arc_max_radius,
			"%s: the aim ring's cap must sit at or above its charge-0 radius, or every warning is pinned at the cap and never grows" % label)
		var wedge_inner: float = s.damage_arc_radius - s.damage_arc_thickness * 0.5
		assert_lt(s.aim_arc_max_radius + s.aim_arc_thickness * 0.5, wedge_inner,
			"%s: a fully charged aim ring must stay inside the hit-direction wedges it shares the centre with" % label)
		assert_lt(s.aim_ping_radius + s.aim_arc_thickness * 0.5, wedge_inner,
			"%s: the 'shot from here' ping must stay inside the hit-direction wedges" % label)
		s = null

## Every charge-driven look ramps linearly from its charge-0 value to 1.0 (aim_indicators.gd / sniper_glints.gd):
## the start value must be VISIBLE (a just-noticing enemy still shows) and BELOW full, or the ramp runs backwards
## and a locked-in shot reads fainter/smaller than a glance. The warning blink alternates 1.0 with its dim phase,
## so a dim phase at 1.0 is no blink at all.
func test_charge_ramps_start_faint_and_finish_bright() -> void:
	var skins := _skins()
	for label in skins:
		var s: Resource = skins[label]
		assert_between(s.aim_arc_min_alpha, 0.01, 0.99,
			"%s: aim_arc_min_alpha must be visible at charge 0 and still have room to brighten as the aim locks" % label)
		assert_between(s.aim_arc_blink_dim_alpha, 0.0, 0.99,
			"%s: the final-warning blink's dim phase must be dimmer than its 1.0 bright phase or the warning never blinks" % label)
		assert_gt(s.aim_arc_blink_period, 0.0, "%s: the warning blink needs a real period to flash with the beep" % label)
		assert_gt(s.aim_ping_ttl, 0.0, "%s: the damage ping must live long enough to be seen" % label)
		assert_between(s.glint_min_alpha, 0.01, 0.99,
			"%s: a sniper glint must show the instant an enemy starts aiming and brighten as the shot locks" % label)
		assert_between(s.glint_min_scale, 0.01, 0.99,
			"%s: a sniper glint must GROW as the shot locks — a start scale at or past 1 shrinks it toward the kill" % label)
		assert_gt(s.glint_streak_length, s.glint_core_radius,
			"%s: the anamorphic streaks must reach past the core, or the glint reads as a dot, not a lens flare" % label)
		assert_ne(s.hitmarker_headshot_color, s.hitmarker_color,
			"%s: a headshot confirm must flash a different colour from a body hit so head hits read instantly" % label)
		s = null

## The shared label chrome exists so HUD text "reads over any scene" (hud_skin.gd Label chrome group, ui.gd's
## corner readouts): every tier keeps a real outline, and the big corner readout's fill must contrast with its
## outline. Each hotbar slot sits on a quiet, semi-transparent PanelContainer plate over the live world, so the
## plate modulate and the key/count tints must each stay visible too.
func test_hud_text_chrome_stays_legible_over_any_scene() -> void:
	var skins := _skins()
	for label in skins:
		var s: Resource = skins[label]
		assert_gt(s.label_outline_color.a, 0.0, "%s: the shared label outline must not be transparent" % label)
		for field in ["toast_outline_size", "look_name_outline_size", "corner_label_outline_size",
				"hotbar_name_outline_size"]:
			assert_gt(int(s.get(field)), 0, "%s: %s must be a real outline width — 0 leaves that text bare over a bright scene" % [label, field])
		assert_gt(s.corner_label_outline_color.a, 0.0, "%s: the corner readout outline must not be transparent" % label)
		var contrast: float = absf(s.corner_label_color.get_luminance() - s.corner_label_outline_color.get_luminance())
		assert_gt(contrast, 0.5,
			"%s: the ammo readout's fill must contrast with its outline (luminance gap %.2f) or the digits smear into their rim" % [label, contrast])
		for field in ["hotbar_panel_modulate", "hotbar_key_color", "hotbar_count_color"]:
			var tint: Color = s.get(field)
			assert_gt(tint.a, 0.0, "%s: %s at alpha 0 makes that slot chrome invisible" % [label, field])
		assert_ne(s.minimap_player_color, s.minimap_npc_color,
			"%s: the player's caret must not share the fallback beacon tint, or 'where am I' reads as a marker" % label)
		s = null

## SHIP DECISION: the game ships the CODE-DRAWN HUD. Every artist art slot is optional (the MenuSkin widget-art
## rule: a null slot keeps the drawn look), and today no art is delivered — so the skin the game actually loads
## (hud_skin.tres) and the fallback MenuStyle wears without it must leave the reticle, the hit-confirm and the
## minimap rim to their drawn primitives. A placeholder PNG left in a slot (or preloaded as a script default)
## would ship to players, which is what this catches. (compass_marker_texture is not pinned: its only reader is
## compass.gd, a retired overlay nothing instantiates, so no player sees that slot.) The reticle half is DRIVEN:
## a real HUD built on the shipped skin shows the drawn dot (test_hud_labels_and_reticle_wear_the_live_skin_when_built
## is the control that the same HUD does show art when a skin carries it). When art IS delivered into
## hud_skin.tres, that delivery changes the decision this test records — update it in the same change.
func test_the_shipped_hud_draws_its_own_reticle_hit_confirm_and_map_rim() -> void:
	var skins := _skins()
	for label in skins:
		var s: Resource = skins[label]
		assert_null(s.crosshair_texture,
			"SHIP DECISION: %s carries no crosshair art, so players aim with the drawn flat dot" % label)
		assert_null(s.hitmarker_texture,
			"SHIP DECISION: %s carries no hit-confirm art, so a hit flashes the four drawn ticks" % label)
		assert_null(s.minimap_frame_texture,
			"SHIP DECISION: %s carries no minimap frame art, so the box wears its drawn rim" % label)
		s = null
	MenuStyle.set_hud_skin(load(SKIN_RES))
	var ui = load("res://scripts/ui/ui.gd").new()
	add_child_autofree(ui)
	await wait_process_frames(2)
	var reticle_art: TextureRect = ui._crosshair_art
	assert_false(reticle_art.visible, "SHIP DECISION: a HUD built on the shipped skin shows no artist reticle")
	assert_eq(ui.crosshair.material, ui._flat_reticle_mat, "...it wears the shader-drawn flat dot instead")
	assert_eq(ui.crosshair.color, Color.WHITE, "...painted opaque white rather than zeroed out under art")


## SHIP DECISION, the minimap half: the map ships its STROKED glyph alphabet. The ten marker art slots are the
## artist's drop-in surface (a delivered PNG lands ONE AT A TIME), and none is filled today. Resolved through
## MinimapArt exactly as minimap.gd's paint sites resolve them for a level with no MapData art of its own, the
## caret, the POI beacon and every station kind (its own slot, then the family badge) must come back null, which
## is the paint sites' "draw the primitive" answer. Walking StationMarker.Kind rather than listing slot names
## means a new station kind is walked here the day it is added to the enum.
func test_the_shipped_minimap_strokes_every_marker_glyph() -> void:
	var art = load("res://scripts/ui/minimap_art.gd")
	var skins := _skins()
	for label in skins:
		var s: Resource = skins[label]
		assert_null(art.pick(null, s.minimap_player_texture),
			"SHIP DECISION: on %s the player caret is the drawn triangle, not art" % label)
		assert_null(art.pick(null, s.minimap_poi_texture),
			"SHIP DECISION: on %s a POI beacon is the drawn dot, not art" % label)
		for kind_name in StationMarker.Kind:
			assert_null(art.station_texture(s, StationMarker.Kind[kind_name]),
				"SHIP DECISION: on %s a %s station strokes its glyph (no own slot art, no family badge)" % [label, kind_name])
		s = null


## The minimap PLAN's paint (walls / walkable fill / backing). The walls are the ink the plan is actually read
## from: the walkable fill drawn under them must stay dimmer than the strokes, and the strokes must stand out
## from the void backing, or the room shapes drown in their own ground.
func test_minimap_plan_walls_out_ink_their_ground() -> void:
	var skins := _skins()
	for label in skins:
		var s: Resource = skins[label]
		assert_lte(s.minimap_walkable_color.a, s.minimap_wall_color.a,
			"%s: the ground fill never out-inks the wall strokes drawn on top of it" % label)
		assert_gt(s.minimap_wall_color.a, 0.0, "%s: the wall strokes are the map's primary read and must be visible" % label)
		assert_gt(s.minimap_wall_color.get_luminance(), s.minimap_backing_color.get_luminance(),
			"%s: the wall strokes must be brighter than the void backing they are drawn over" % label)
		s = null

## The HUD clock's one paint slot (the time readout under the map). Its doc: it ships on the map's own wall ink
## so the map and its caption read as one instrument, until a skin deliberately parts them. Only the SCRIPT
## default is checked, on purpose: hud_skin.gd invites an artist to retint clock_color alone, so the authored
## .tres (or any other skin) parting the clock from the walls is a sanctioned look, not a regression.
func test_clock_ink_tracks_the_minimap_walls() -> void:
	var s := _fresh()
	assert_eq(s.clock_color, s.minimap_wall_color,
		"shipped default: the clock's digits wear the minimap wall ink so the map and its caption read as one instrument (a skin may retint clock_color alone, see hud_skin.gd)")
	s = null

## MenuStyle exposes the skin (the MenuStyle.skin twin): preloaded from the authored .tres, never null
## after rebuild(), and set_hud_skin swaps it (a null swap is refused, mirroring set_skin).
func test_menu_style_exposes_hud() -> void:
	assert_not_null(MenuStyle.hud, "MenuStyle.hud is preloaded")
	assert_eq(MenuStyle.hud.resource_path, SKIN_RES, "MenuStyle.hud is the authored hud_skin.tres")
	var original: Resource = MenuStyle.hud
	var other: Resource = _fresh()
	MenuStyle.set_hud_skin(other)
	assert_eq(MenuStyle.hud, other, "set_hud_skin swaps the live skin")
	MenuStyle.set_hud_skin(null)
	assert_eq(MenuStyle.hud, other, "a null swap is refused (set_skin parity)")
	MenuStyle.set_hud_skin(original)  # restore for the rest of the suite
	other = null

## A skin whose every consumer-read field differs from the shipped defaults, so a paint site that reads a
## literal (or a cached skin) instead of MenuStyle.hud cannot pass by coincidence.
func _distinctive_skin() -> Resource:
	var s := _fresh()
	s.label_outline_color = Color(0.3, 0.0, 0.5, 1.0)
	s.toast_outline_size = 7
	s.look_name_outline_size = 9
	s.corner_label_outline_size = 3
	s.corner_label_outline_color = Color(0.0, 0.25, 0.1, 0.8)
	s.corner_label_color = Color(1.0, 0.8, 0.1, 1.0)
	s.clock_color = Color(0.9, 0.2, 0.6, 1.0)
	s.hotbar_panel_modulate = Color(0.2, 0.9, 0.4, 0.7)
	s.hotbar_key_color = Color(0.9, 0.5, 0.1, 0.8)
	s.hotbar_count_color = Color(0.1, 0.6, 0.9, 0.9)
	s.hotbar_name_outline_size = 5
	s.compass_fallback_color = Color(0.2, 0.4, 0.9, 1.0)
	s.minimap_npc_color = Color(0.6, 0.9, 0.2, 1.0)
	var defaults := _fresh()
	for field in ["label_outline_color", "toast_outline_size", "look_name_outline_size", "corner_label_outline_size",
			"corner_label_outline_color", "corner_label_color", "clock_color", "hotbar_panel_modulate",
			"hotbar_key_color", "hotbar_count_color", "hotbar_name_outline_size", "compass_fallback_color",
			"minimap_npc_color"]:
		assert_ne(s.get(field), defaults.get(field), "precondition: the test skin's %s differs from the shipped default" % field)
	defaults = null
	return s

## ui.gd: the label chrome it stamps while BUILDING the HUD (look-name, clock, quest tracker, money, the corner
## ammo readout, every toast) and the optional reticle art must come from the LIVE skin. A real HUD is built
## in-tree with no player (the test_hud_curve_input.gd harness), so this watches the actual paint sites.
func test_hud_labels_and_reticle_wear_the_live_skin_when_built() -> void:
	var skin := _distinctive_skin()
	var art := ImageTexture.create_from_image(Image.create(8, 8, false, Image.FORMAT_RGBA8))
	skin.crosshair_texture = art
	MenuStyle.set_hud_skin(skin)
	assert_eq(MenuStyle.hud, skin, "precondition: the distinctive skin is live before the HUD builds")
	var ui = load("res://scripts/ui/ui.gd").new()
	add_child_autofree(ui)
	await wait_process_frames(2)
	var look: Label = ui._look_name
	assert_eq(look.get_theme_color(&"font_outline_color"), skin.label_outline_color,
		"the look-at name under the crosshair wears the skin's label outline colour")
	assert_eq(look.get_theme_constant(&"outline_size"), skin.look_name_outline_size,
		"the look-at name wears the skin's look_name_outline_size")
	var clock: Label = ui._clock
	assert_eq(clock.get_theme_color(&"font_color"), skin.clock_color, "the HUD clock's digits wear the skin's clock_color")
	assert_eq(clock.get_theme_color(&"font_outline_color"), skin.label_outline_color, "the clock wears the shared label outline")
	assert_eq(clock.get_theme_constant(&"outline_size"), skin.toast_outline_size, "the clock wears the small-text outline width")
	for pair in [["quest tracker", ui._quest_tracker], ["money readout", ui._money_label], ["owed readout", ui._owed_label]]:
		var l: Label = pair[1]
		assert_eq(l.get_theme_color(&"font_outline_color"), skin.label_outline_color,
			"the %s wears the skin's label outline colour" % pair[0])
		assert_eq(l.get_theme_constant(&"outline_size"), skin.toast_outline_size,
			"the %s wears the skin's toast_outline_size" % pair[0])
	var ammo: Label = ui._hud_ammo
	assert_eq(ammo.get_theme_color(&"font_color"), skin.corner_label_color, "the corner ammo readout rests on corner_label_color")
	assert_eq(ammo.get_theme_color(&"font_outline_color"), skin.corner_label_outline_color,
		"the corner ammo readout wears corner_label_outline_color")
	assert_eq(ammo.get_theme_constant(&"outline_size"), skin.corner_label_outline_size,
		"the corner ammo readout wears corner_label_outline_size")
	ui.push_toast(PlayerText.BACK, Color.WHITE)
	var toasts: VBoxContainer = ui._rep_toasts
	var toast: Label = toasts.get_child(0)  # newest on top
	assert_eq(toast.get_theme_color(&"font_outline_color"), skin.label_outline_color, "a toast wears the skin's label outline colour")
	assert_eq(toast.get_theme_constant(&"outline_size"), skin.toast_outline_size, "a toast wears the skin's toast_outline_size")
	# The +N/-N money float is built lazily on the first wallet change (not at HUD build), so drive one: with no
	# player wired, _on_money_changed only re-stamps the readout (GameState.account) and floats the indicator.
	ui._on_money_changed(5.0, 5.0)
	var float_l: Label = ui._money_delta_label
	assert_true(float_l != null, "precondition: a money change floats a +N indicator")
	assert_eq(float_l.get_theme_color(&"font_outline_color"), skin.label_outline_color,
		"the +N money float wears the skin's label outline colour")
	assert_eq(float_l.get_theme_constant(&"outline_size"), skin.toast_outline_size,
		"the +N money float wears the skin's toast_outline_size")
	# The reticle: authored art replaces the flat dot while unscoped, and the ColorRect paints nothing under it.
	var reticle_art: TextureRect = ui._crosshair_art
	var dot: ColorRect = ui.crosshair
	assert_eq(reticle_art.texture, art, "the skin's crosshair_texture is what the reticle shows")
	assert_true(reticle_art.visible, "with art authored, the artist reticle is up while unscoped")
	assert_almost_eq(dot.color.a, 0.0, 0.001, "under the art the flat dot paints nothing (no double reticle)")
	# Control: the SAME HUD, re-resolved after a swap to a skin with no art, falls back to the drawn dot — so the
	# look above came from the skin, and the next scope transition adopts a runtime swap without a rebuild.
	MenuStyle.set_hud_skin(_fresh())
	ui.set_scoped(true)
	ui.set_scoped(false)
	assert_false(reticle_art.visible, "a skin with no crosshair art hides the artist reticle on the next scope transition")
	assert_eq(dot.color, Color.WHITE, "...and the drawn flat dot comes back")
	skin = null

## hotbar.gd: every slot's chrome (panel modulate, key/count tints, the shared outline colour + width) is read
## from the LIVE skin when the bar builds. setup(null) builds the chrome off-tree with no player.
func test_hotbar_slot_chrome_wears_the_live_skin() -> void:
	var skin := _distinctive_skin()
	MenuStyle.set_hud_skin(skin)
	var hb := Hotbar.new()
	hb.setup(null)
	assert_eq(hb._slot_panels.size(), Hotbar.SLOTS, "precondition: setup built every slot")
	for i in hb._slot_panels.size():
		assert_eq(hb._slot_panels[i].self_modulate, skin.hotbar_panel_modulate, "slot %d's panel wears hotbar_panel_modulate" % i)
		assert_eq(hb._slot_keys[i].get_theme_color(&"font_color"), skin.hotbar_key_color, "slot %d's key caption wears hotbar_key_color" % i)
		assert_eq(hb._slot_counts[i].get_theme_color(&"font_color"), skin.hotbar_count_color,
			"slot %d's stack count wears hotbar_count_color" % i)
		for l: Label in [hb._slot_keys[i], hb._slot_names[i], hb._slot_counts[i]]:
			assert_eq(l.get_theme_color(&"font_outline_color"), skin.label_outline_color,
				"slot %d's lines wear the skin's shared label outline colour" % i)
			assert_eq(l.get_theme_constant(&"outline_size"), skin.hotbar_name_outline_size,
				"slot %d's lines wear the skin's hotbar_name_outline_size" % i)
	hb.free()
	skin = null

## compass.gd / minimap.gd: a marker with no `color` of its own takes the fallback tint from the LIVE skin at
## call time (both factor the pick into `marker_color`), while a marker that carries a colour keeps it. Both
## widgets are BUILT before the distinctive skin goes live, then asked again after a SECOND swap, so a consumer
## that captured MenuStyle.hud when it was constructed (or on its first call) fails here, not only one that
## regressed to a literal.
func test_nav_marker_fallback_tints_follow_the_live_skin() -> void:
	var mm = load("res://scripts/ui/minimap.gd").new()
	autofree(mm)
	var compass = load("res://scripts/ui/compass.gd").new()
	autofree(compass)
	var bare := Node3D.new()  # no `color` property -> the skin's fallback
	autofree(bare)
	var skin := _distinctive_skin()
	assert_ne(MenuStyle.hud.minimap_npc_color, skin.minimap_npc_color,
		"precondition: the skin live while the widgets were built has a different minimap fallback tint")
	assert_ne(MenuStyle.hud.compass_fallback_color, skin.compass_fallback_color,
		"precondition: the skin live while the widgets were built has a different compass fallback tint")
	MenuStyle.set_hud_skin(skin)
	assert_eq(mm.marker_color(bare), skin.minimap_npc_color,
		"a colourless minimap marker falls back to the minimap_npc_color of a skin swapped in AFTER the widget was built")
	assert_eq(compass.marker_color(bare), skin.compass_fallback_color,
		"a colourless compass marker falls back to the compass_fallback_color of a skin swapped in AFTER the widget was built")
	var second := _fresh()
	second.minimap_npc_color = Color(0.9, 0.1, 0.8, 1.0)
	second.compass_fallback_color = Color(0.1, 0.9, 0.7, 1.0)
	assert_ne(second.minimap_npc_color, skin.minimap_npc_color, "precondition: the second skin's minimap tint differs from the first's")
	assert_ne(second.compass_fallback_color, skin.compass_fallback_color, "precondition: the second skin's compass tint differs from the first's")
	MenuStyle.set_hud_skin(second)
	assert_eq(mm.marker_color(bare), second.minimap_npc_color,
		"a second swap re-tints the minimap fallback on the very next call: the skin is read per call, never remembered")
	assert_eq(compass.marker_color(bare), second.compass_fallback_color,
		"a second swap re-tints the compass fallback on the very next call: the skin is read per call, never remembered")
	second = null
	var own = load("res://scripts/components/world_marker.gd").new()
	autofree(own)
	own.color = Color(0.05, 0.1, 0.15)
	assert_eq(mm.marker_color(own), own.color, "control: a minimap marker with its own colour ignores the skin fallback")
	assert_eq(compass.marker_color(own), own.color, "control: a compass marker with its own colour ignores the skin fallback")
	skin = null

## Scope contract: gameplay-tuning stays on GameSettings.hud (HudSettings) — the skin must not grow a
## duplicate of a HudSettings field name, or two sources of truth drift (the cb_palette exclusion's
## sibling rule).
func test_no_field_collides_with_hud_settings() -> void:
	var skin_props := {}
	for p in (load(SKIN_SCRIPT) as Script).get_script_property_list():
		if p.usage & PROPERTY_USAGE_SCRIPT_VARIABLE:
			skin_props[p.name] = true
	var overlap: Array[String] = []
	for p in (HudSettings as Script).get_script_property_list():
		if (p.usage & PROPERTY_USAGE_SCRIPT_VARIABLE) and skin_props.has(p.name):
			overlap.append(p.name)
	assert_eq(overlap, [] as Array[String], "no HudSkin field shadows a HudSettings tuning field")
