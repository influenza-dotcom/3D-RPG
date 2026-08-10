extends GutTest

## THE SHARED TOP-RIGHT CORNER. The minimap and the quest tracker now both live there, and neither can see
## the other at runtime — the tracker's column is right-anchored and wraps DOWNWARD with no bound, so if the
## map's footprint and the tracker's top ever disagree, objective text silently draws over the map (or the
## map over the text) and nothing errors.
##
## ui.gd cannot be constructed here (its _ready needs a viewport, autoload signals and a live InputMap), so
## the reflow rule is factored out as a pure static and pinned off-tree — the hp_segment_fill /
## stamina_bar_fill / crosshair_shown idiom. The pixel LOOK is playtest-verified; the invariants are not.

const BAR := preload("res://scripts/ui/enemy_health_bar.gd")

## The 792-wide UI canvas (project.godot viewport_width 396 x stretch scale 0.5), matching
## tests/test_enemy_health_bar.gd's own constant. Everything here anchors at the TOP, so height is irrelevant.
const CANVAS_W := 792.0


func test_quest_tracker_top_sits_below_the_minimap() -> void:
	assert_almost_eq(UI.quest_tracker_top_for(true, 8.0, 108.0, 6.0, 8.0), 122.0, 0.0001,
			"with the map up the tracker starts below it: inset 8 + box 108 + gap 6")

func test_quest_tracker_top_returns_to_the_bare_inset_when_off() -> void:
	assert_almost_eq(UI.quest_tracker_top_for(false, 8.0, 108.0, 6.0, 8.0), 8.0, 0.0001,
			"map OFF returns the tracker to the historical literal 8.0 — no hole where the map used to be")

func test_quest_tracker_top_tracks_the_live_knobs() -> void:
	# Derived, not hardcoded: a designer nudging the box size or inset must move the tracker with it, or the
	# two drift into each other with no error.
	var h := HudSettings.new()
	var want: float = h.minimap_inset.y + h.minimap_size.y + h.minimap_tracker_gap
	assert_almost_eq(UI.quest_tracker_top_for(true, h.minimap_inset.y, h.minimap_size.y,
			h.minimap_tracker_gap, h.minimap_tracker_bare_top), want, 0.0001,
			"the shipped knobs compose to the shipped tracker top")
	assert_gt(want, h.minimap_tracker_bare_top,
			"the map-on top must be BELOW the map-off top, or the reflow is backwards")
	h = null


func test_minimap_column_never_reaches_past_the_quest_tracker() -> void:
	# Keeps tests/test_enemy_health_bar.gd's x-clearance pin meaningful: that test proves the health bar
	# clears the TRACKER's column, which only bounds this corner while the map stays inside that same column.
	var h := HudSettings.new()
	assert_lte(h.minimap_inset.x + h.minimap_size.x, 8.0 + h.quest_tracker_width,
			"the map must not overhang the tracker column the enemy-health-bar clearance is measured against")
	h = null


func test_minimap_ink_clears_the_enemy_health_bar_at_full_hud_sway() -> void:
	# Mirrors test_enemy_health_bar.gd's own worst-case reasoning, from the other side. The bar is PINNED to
	# the HUD layer; the minimap rides the HUD-weight carrier, which springs up to hud_sway_max px and also
	# scales toward screen centre by hud_fov_scale_max. The static gap is not the promise — the gap after the
	# carrier has travelled as far left as it can is.
	var h := HudSettings.new()
	var ink: Rect2 = BAR.ink_rect(CANVAS_W, h.enemy_hp_top, h.enemy_hp_size, h.enemy_hp_outline_width)
	var map_left := CANVAS_W - h.minimap_inset.x - h.minimap_size.x - h.minimap_outline_width
	var swayed := map_left - h.hud_sway_max
	swayed -= (map_left - CANVAS_W * 0.5) * h.hud_fov_scale_max
	assert_lte(ink.end.x, swayed,
			"the enemy health bar's ink (%s) must clear the minimap's left edge even at worst-case sway (%s)" \
				% [ink.end.x, swayed])
	h = null


func test_minimap_box_is_whole_pixel() -> void:
	# The ragged-comb rule: a fractional size rasterizes unevenly under the 792x444 canvas's ~2.4x nearest
	# upscale, exactly as ui.gd.hp_display_seg_width documents for the HP segments.
	var h := HudSettings.new()
	assert_eq(h.minimap_size.x, floorf(h.minimap_size.x), "whole-pixel width")
	assert_eq(h.minimap_size.y, floorf(h.minimap_size.y), "whole-pixel height")
	assert_eq(h.minimap_inset.x, floorf(h.minimap_inset.x), "whole-pixel inset x")
	assert_eq(h.minimap_inset.y, floorf(h.minimap_inset.y), "whole-pixel inset y")
	h = null
