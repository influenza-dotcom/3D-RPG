extends GutTest

## HudSkin (resources/ui/hud_skin.tres, scripts/ui/hud_skin.gd): the MenuSkin twin for the IN-GAME HUD —
## the one artist resource for the combat indicators (hitmarker, damage/aim arcs, sniper glints),
## compass/minimap fallback tints, optional crosshair/marker art, and the label/hotbar chrome those
## scripts previously hardcoded. Exposed as MenuStyle.hud (preloaded beside MenuStyle.skin, same
## null-fallback + set_hud_skin seam). Defaults must equal the former hardcoded literals so the shipped
## game is pixel-identical until an artist edits the .tres. Gameplay-tuning numbers stay on
## GameSettings.hud (HudSettings) — pinned here by the scope check.

## Loaded by PATH, not class_name, so this suite survives a stale global class cache (the ui.gd
## STAMINA_RING_SCRIPT idiom).
const SKIN_SCRIPT := "res://scripts/ui/hud_skin.gd"
const SKIN_RES := "res://resources/ui/hud_skin.tres"

func _fresh() -> Resource:
	return load(SKIN_SCRIPT).new()

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
		# Label + hotbar chrome
		"label_outline_color", "toast_outline_size", "look_name_outline_size",
		"corner_label_outline_size", "corner_label_outline_color", "corner_label_color",
		"hotbar_panel_modulate", "hotbar_key_color", "hotbar_count_color", "hotbar_name_outline_size",
	]:
		assert_true(field in s, "HudSkin exposes %s" % field)
	s = null

## Representative defaults must equal the literals the consumer scripts shipped with (byte-identical HUD
## until an artist edits the .tres).
func test_defaults_match_the_former_literals() -> void:
	var s := _fresh()
	# hitmarker.gd
	assert_almost_eq(float(s.hitmarker_duration), 0.25, 0.001, "hitmarker duration preserved")
	assert_eq(s.hitmarker_color, Color(1.0, 1.0, 1.0, 0.9), "hitmarker body colour preserved")
	assert_eq(s.hitmarker_headshot_color, Color(1.0, 0.22, 0.12, 0.95), "headshot colour preserved")
	assert_almost_eq(float(s.hitmarker_headshot_scale), 1.9, 0.001, "headshot scale preserved")
	assert_almost_eq(float(s.hitmarker_pop_px), 3.0, 0.001, "hitmarker pop offset preserved")
	# damage_indicators.gd
	assert_almost_eq(float(s.damage_arc_radius), 120.0, 0.001, "damage arc radius preserved")
	assert_almost_eq(float(s.damage_arc_degrees), 55.0, 0.001, "damage arc wedge preserved")
	assert_eq(s.damage_arc_color, Color(0.85, 0.08, 0.08), "damage arc red preserved")
	# aim_indicators.gd (@exports + the old EXPIRY-adjacent look consts)
	assert_almost_eq(float(s.aim_arc_base_radius), 28.0, 0.001, "aim arc base radius preserved")
	assert_almost_eq(float(s.aim_arc_thickness), 6.0, 0.001, "aim arc thickness preserved")
	assert_eq(s.aim_arc_color, Color(0.9, 0.1, 0.1), "aim arc red preserved")
	assert_almost_eq(float(s.aim_arc_min_alpha), 0.35, 0.001, "aim arc charge-0 alpha preserved")
	assert_almost_eq(float(s.aim_arc_blink_period), 0.12, 0.001, "warning blink period preserved (BLINK_PERIOD)")
	assert_almost_eq(float(s.aim_arc_blink_dim_alpha), 0.15, 0.001, "blink dim phase preserved")
	assert_almost_eq(float(s.aim_ping_radius), 84.0, 0.001, "damage ping radius preserved (PING_RADIUS)")
	assert_almost_eq(float(s.aim_ping_ttl), 0.6, 0.001, "damage ping lifetime preserved (PING_TTL)")
	# sniper_glints.gd
	assert_almost_eq(float(s.glint_core_radius), 6.0, 0.001, "glint core radius preserved")
	assert_almost_eq(float(s.glint_streak_length), 22.0, 0.001, "glint streak length preserved")
	assert_eq(s.glint_color, Color(0.7, 0.85, 1.0), "glint blue-white preserved")
	assert_almost_eq(float(s.glint_min_alpha), 0.4, 0.001, "glint charge-0 alpha preserved")
	assert_almost_eq(float(s.glint_min_scale), 0.45, 0.001, "glint charge-0 scale preserved")
	# compass.gd / minimap.gd fallbacks
	assert_eq(s.compass_fallback_color, Color(1.0, 0.85, 0.3), "compass fallback gold preserved")
	assert_eq(s.minimap_player_color, Color(0.4, 0.8, 1.0), "minimap player blue preserved")
	assert_eq(s.minimap_npc_color, Color(1.0, 0.4, 0.4), "minimap NPC red preserved")
	# ui.gd label chrome
	assert_eq(s.label_outline_color, Color(0.0, 0.0, 0.0, 1.0), "label outline = Color.BLACK preserved")
	assert_eq(int(s.toast_outline_size), 4, "toast outline width preserved")
	assert_eq(int(s.look_name_outline_size), 5, "look-name outline width preserved")
	assert_eq(int(s.corner_label_outline_size), 6, "corner readout outline width preserved")
	assert_eq(s.corner_label_outline_color, Color(0.0, 0.0, 0.0, 0.9), "corner outline colour preserved")
	assert_eq(s.corner_label_color, Color.WHITE, "corner readout resting white preserved")
	# hotbar.gd chrome
	assert_eq(s.hotbar_panel_modulate, Color(1, 1, 1, 0.55), "hotbar panel modulate preserved")
	assert_eq(s.hotbar_key_color, Color(1, 1, 1, 0.5), "hotbar key caption tint preserved")
	assert_eq(s.hotbar_count_color, Color(1, 1, 1, 0.6), "hotbar count tint preserved")
	assert_eq(int(s.hotbar_name_outline_size), 2, "hotbar name outline width preserved")
	s = null

## Optional artist drop-in slots default NULL = keep the code-drawn look (the MenuSkin widget-art rule).
func test_artist_texture_slots_default_null() -> void:
	var s := _fresh()
	assert_null(s.crosshair_texture, "crosshair art defaults null (code-drawn dot)")
	assert_null(s.hitmarker_texture, "hitmarker art defaults null (code-drawn ticks)")
	assert_null(s.compass_marker_texture, "compass marker art defaults null (code-drawn dot)")
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

## ui.gd wiring (stage: main HUD): its label-chrome paint sites and the crosshair-art slot must read
## MenuStyle.hud, not literals. UI._ready can't run off-tree (viewport + autoload signal wiring), so
## this pins the wiring at the SOURCE level — each consumed field must appear in ui.gd, and the old
## hardcoded outline dialect (Color.BLACK at a font_outline_color site) must be gone.
func test_ui_gd_reads_the_hud_skin() -> void:
	var src: String = FileAccess.get_file_as_string("res://scripts/ui/ui.gd")
	assert_true(src.length() > 0, "ui.gd source readable")
	for field in [
		"label_outline_color", "toast_outline_size", "look_name_outline_size",
		"corner_label_outline_size", "corner_label_outline_color", "corner_label_color",
		"crosshair_texture",
	]:
		assert_true(src.contains("MenuStyle.hud.%s" % field), "ui.gd reads MenuStyle.hud.%s" % field)
	assert_false(src.contains("font_outline_color\", Color.BLACK"),
			"no hardcoded Color.BLACK label outline remains in ui.gd")
	assert_false(src.contains("font_outline_color\", Color(0.0, 0.0, 0.0"),
			"no hardcoded translucent corner outline remains in ui.gd")

## hotbar.gd wiring (stage: hotbar + enemy health bar): the slot CHROME (panel modulate, key/count
## tints, name outline colour + width) must read MenuStyle.hud, not literals. _build_bar can't run
## off-tree cheaply (autoload reads + a live InputMap), so this pins the wiring at the SOURCE level,
## same as the ui.gd check above — and pins that the old literals are gone. enemy_health_bar.gd is
## deliberately NOT wired: every look value there was already a HudSettings knob (its own comment says
## so), so there is nothing for the skin to own.
func test_hotbar_gd_reads_the_hud_skin() -> void:
	var src: String = FileAccess.get_file_as_string("res://scripts/ui/hotbar.gd")
	assert_true(src.length() > 0, "hotbar.gd source readable")
	for field in [
		"hotbar_panel_modulate", "hotbar_key_color", "hotbar_count_color",
		"hotbar_name_outline_size", "label_outline_color",
	]:
		assert_true(src.contains(field), "hotbar.gd reads the skin's %s" % field)
	assert_true(src.contains("MenuStyle.hud"), "hotbar.gd sources its chrome from MenuStyle.hud")
	assert_false(src.contains("Color(1, 1, 1, 0.55)"), "old panel-modulate literal gone from hotbar.gd")
	assert_false(src.contains("font_outline_color\", Color.BLACK"),
			"no hardcoded Color.BLACK name outline remains in hotbar.gd")

## compass.gd / minimap.gd wiring (stage: nav widgets): the fallback marker tints + the compass's optional
## marker-art slot come from MenuStyle.hud; geometry (@export edge_margin/marker_size/marker_radius) stays
## per-scene. Both scripts factor the colour pick into a callable `marker_color`, so this is FUNCTIONAL —
## no _draw needed. Compass's own-colour branch is pinned in test_compass.gd.
func test_minimap_and_compass_read_the_hud_skin() -> void:
	var mm = load("res://scripts/ui/minimap.gd").new()
	autofree(mm)
	var bare := Node3D.new()  # no `color` property -> the skin's NPC red
	autofree(bare)
	assert_eq(mm.marker_color(bare), MenuStyle.hud.minimap_npc_color,
			"minimap colourless marker falls back to MenuStyle.hud.minimap_npc_color")
	# The player dot tint + compass art slot have no off-tree seam (painted inside _draw), so pin at the
	# SOURCE level like the ui.gd/hotbar.gd checks above.
	var mm_src: String = FileAccess.get_file_as_string("res://scripts/ui/minimap.gd")
	assert_true(mm_src.contains("MenuStyle.hud.minimap_player_color"), "minimap player dot reads the skin")
	assert_false(mm_src.contains("Color(0.4, 0.8, 1.0)"), "old player-blue literal gone from minimap.gd")
	assert_false(mm_src.contains("Color(1.0, 0.4, 0.4)"), "old NPC-red literal gone from minimap.gd")
	var c_src: String = FileAccess.get_file_as_string("res://scripts/ui/compass.gd")
	assert_true(c_src.contains("MenuStyle.hud.compass_marker_texture"), "compass honours the marker-art slot")
	assert_false(c_src.contains("Color(1.0, 0.85, 0.3)"), "old fallback-gold literal gone from compass.gd")

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
