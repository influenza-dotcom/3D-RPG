extends GutTest

## Top-centre enemy health bar (scripts/ui/enemy_health_bar.gd) + the damage seam that raises it.
## Covers the PURE parts off-tree — the fill fraction, the hold-then-fade opacity ramp, the chip-trail step,
## the shipped HudSettings defaults and their layout invariant, and the Options toggle round-trip — plus the
## METHOD-SURFACE contract of the push chain (Character.take_damage -> attacker.on_damaged_target ->
## Player.on_damaged_target -> PlayerHud.show_enemy_health). The on-screen look (the bar clearing the stealth
## badge, the shard reading as damage) is playtest territory.

## Loaded BY PATH (not the class_name) so the suite parses even before the editor registers the new global
## class — the same cache-cascade guard the runtime wiring uses (player_hud.gd ENEMY_HEALTH_BAR_SCRIPT).
const BAR := preload("res://scripts/ui/enemy_health_bar.gd")

var _prev_loaded: bool
var _prev_enabled: bool

func before_each() -> void:
	# Never let a setter round-trip clobber the real user://settings.cfg (the test_settings.gd idiom).
	_prev_loaded = Settings._loaded
	_prev_enabled = Settings.enemy_health_bar_enabled
	Settings._loaded = false

func after_each() -> void:
	Settings.enemy_health_bar_enabled = _prev_enabled
	Settings._loaded = _prev_loaded

# --- fill fraction ------------------------------------------------------------------------------------

func test_fill_fraction_maps_hp_over_max() -> void:
	var f: float = BAR.fill_fraction(5.0, 10.0)
	assert_almost_eq(f, 0.5, 0.0001, "half HP fills half the bar")

func test_fill_fraction_clamps_negative_hp_to_empty() -> void:
	# Character.take_damage floors nothing (hp -= amount), so an overkill hit really does leave hp below 0 —
	# the value this bar is handed on the killing blow.
	var f: float = BAR.fill_fraction(-40.0, 10.0)
	assert_almost_eq(f, 0.0, 0.0001, "an overkilled target draws an EMPTY bar, never a negative-width fill")

func test_fill_fraction_degrades_on_zero_max_hp_instead_of_dividing() -> void:
	var f: float = BAR.fill_fraction(1.0, 0.0)
	assert_almost_eq(f, 0.0, 0.0001, "a zero/invalid max HP must not divide — it degrades to empty")

# --- hold then fade -----------------------------------------------------------------------------------

func test_plate_alpha_is_fully_lit_through_the_hold() -> void:
	var a: float = BAR.plate_alpha(2000, 3.0, 0.6)
	assert_almost_eq(a, 1.0, 0.0001, "inside the hold window the bar sits at full opacity")

func test_plate_alpha_ramps_across_the_fade() -> void:
	var a: float = BAR.plate_alpha(3300, 3.0, 0.6)  # 0.3 s into a 0.6 s fade == half way
	assert_almost_eq(a, 0.5, 0.0001, "the fade is a linear ramp from the end of the hold")

func test_plate_alpha_is_zero_once_the_fade_elapses() -> void:
	var a: float = BAR.plate_alpha(9999, 3.0, 0.6)
	assert_almost_eq(a, 0.0, 0.0001, "a long-expired plate is fully transparent — the bar then hides itself")

func test_plate_alpha_survives_a_clock_that_reads_backwards() -> void:
	# Defensive: the elapsed value is a wall-clock subtraction, so a negative must read as "just happened",
	# never as a wrapped-around expiry that blinks the bar out mid-fight.
	var a: float = BAR.plate_alpha(-500, 3.0, 0.6)
	assert_almost_eq(a, 1.0, 0.0001, "a negative elapsed clamps to 0 — fully lit, not expired")

func test_plate_alpha_with_no_fade_time_snaps_off() -> void:
	var a: float = BAR.plate_alpha(3001, 3.0, 0.0)
	assert_almost_eq(a, 0.0, 0.0001, "fade 0 must snap off rather than divide by zero")

# --- chip trail ---------------------------------------------------------------------------------------

func test_chip_holds_still_during_the_delay() -> void:
	var g: float = BAR.chip_step(0.9, 0.4, 0.1, 0.25, 0.9, 0.016)
	assert_almost_eq(g, 0.9, 0.0001, "inside the delay the shard is frozen — that pause is what makes it readable")

func test_chip_slides_toward_the_fill_after_the_delay() -> void:
	var g: float = BAR.chip_step(0.9, 0.4, 0.5, 0.25, 1.0, 0.1)
	assert_almost_eq(g, 0.8, 0.0001, "past the delay the shard slides at speed * dt (1.0 * 0.1 = 0.1 of the bar)")

func test_chip_never_slides_past_the_live_fill() -> void:
	var g: float = BAR.chip_step(0.45, 0.4, 5.0, 0.25, 1.0, 1.0)
	assert_almost_eq(g, 0.4, 0.0001, "the shard lands exactly ON the fill — a slide past it would draw backwards")

func test_chip_below_the_fill_snaps_up_to_it() -> void:
	# A heal (or a fresh target seeded at a higher fraction) must not leave an INVERTED trail — a bright
	# shard sitting under the fill would read as damage that never happened.
	var g: float = BAR.chip_step(0.2, 0.7, 5.0, 0.25, 1.0, 0.1)
	assert_almost_eq(g, 0.7, 0.0001, "a ghost below the fill snaps to it, never draws an inverted shard")

# --- layout geometry ----------------------------------------------------------------------------------

func test_bar_rect_is_centred_and_whole_pixel() -> void:
	var r: Rect2 = BAR.bar_rect(792.0, 4.0, Vector2(145, 8))
	assert_almost_eq(r.position.x, 323.0, 0.0001,
		"an odd width still lands on a whole pixel — a fractional edge rasterizes ragged on the 2.4x-upscaled canvas")
	assert_almost_eq(r.position.y, 4.0, 0.0001, "the top comes straight from enemy_hp_top")

func test_ink_rect_grows_the_track_by_the_rim_on_every_side() -> void:
	var track: Rect2 = BAR.bar_rect(792.0, 4.0, Vector2(144, 8))
	var ink: Rect2 = BAR.ink_rect(792.0, 4.0, Vector2(144, 8), 1.0)
	assert_almost_eq(ink.position.y, track.position.y - 1.0, 0.0001, "the rim is drawn OUTSIDE the track, above it")
	assert_almost_eq(ink.end.y, track.end.y + 1.0, 0.0001, "...and below it — this is why the layout tests measure ink, not size")
	assert_almost_eq(ink.size.x, track.size.x + 2.0, 0.0001, "one rim width on EACH horizontal side")

func test_ink_rect_with_no_rim_is_the_track() -> void:
	var track: Rect2 = BAR.bar_rect(792.0, 4.0, Vector2(144, 8))
	var ink: Rect2 = BAR.ink_rect(792.0, 4.0, Vector2(144, 8), 0.0)
	assert_eq(ink, track, "rim 0 must not inflate the footprint")

# --- shipped defaults + the layout invariant ----------------------------------------------------------

## The 792-wide UI canvas (project.godot viewport_width 396 x stretch scale 0.5). Height varies with aspect;
## every widget in this band anchors at the TOP, so the vertical numbers below are height-independent.
const CANVAS_W := 792.0
## First ink in the centre-top column below the bar: the [ HIDDEN ] stealth badge's rect starts at offset_top
## 18 (player_hud.gd) and its outline_size 6 reaches ~3 px above that line box.
const STEALTH_BADGE_INK_TOP := 15.0

func test_bar_ink_clears_the_stealth_badge() -> void:
	# THE tight one, and the reason it measures ink_rect() rather than the size knob: the contrast rim is drawn
	# OUTSIDE the track, so `enemy_hp_top + enemy_hp_size.y` UNDER-COUNTS the real footprint by the rim width
	# and would wave through a bar that actually overlaps the badge.
	var h := HudSettings.new()
	var ink: Rect2 = BAR.ink_rect(CANVAS_W, h.enemy_hp_top, h.enemy_hp_size, h.enemy_hp_outline_width)
	assert_lte(ink.end.y, STEALTH_BADGE_INK_TOP,
		"the bar's INK (rim included) ends at y %s and must clear the stealth badge's ink at y %s — see enemy_hp_top's note" \
			% [ink.end.y, STEALTH_BADGE_INK_TOP])
	h = null

func test_bar_ink_clears_the_quest_tracker_even_at_full_hud_sway() -> void:
	# The bar is PINNED to the HUD layer; the quest tracker rides the HUD-weight carrier (ui.gd `_weighted`),
	# which springs up to hud_sway_max px and additionally scales toward screen centre by hud_fov_scale_max.
	# So the static gap is not the promise — the gap AFTER the carrier has moved as far left as it can is.
	var h := HudSettings.new()
	var ink: Rect2 = BAR.ink_rect(CANVAS_W, h.enemy_hp_top, h.enemy_hp_size, h.enemy_hp_outline_width)
	var tracker_left := CANVAS_W - 8.0 - h.quest_tracker_width       # ui.gd: anchored right, 8px inset
	var swayed := tracker_left - h.hud_sway_max                       # the spring can push the whole panel left
	swayed -= (tracker_left - CANVAS_W * 0.5) * h.hud_fov_scale_max   # the lens breath pulls it toward centre
	assert_lte(ink.end.x, swayed,
		"the bar's INK right edge (%s) must clear the quest tracker column even at worst-case sway (%s)" % [ink.end.x, swayed])
	h = null

func test_hold_outlasts_the_fade() -> void:
	var h := HudSettings.new()
	assert_gt(h.enemy_hp_hold_time, h.enemy_hp_fade_time,
		"the bar must READ for longer than it fades — a fade longer than the hold is a permanent smear")
	h = null

# --- the Options toggle -------------------------------------------------------------------------------

func test_toggle_defaults_on() -> void:
	# Off a BARE instance, never the live autoload: Settings._ready runs load_settings(), which overwrites the
	# field from user://settings.cfg — asserting on the autoload would test the developer's saved preference
	# instead of the shipped default (the tests/test_settings.gd + test_stamina_ring.gd idiom).
	var fresh = load("res://managers/Settings.gd").new()
	assert_true(fresh.enemy_health_bar_enabled,
		"the enemy health bar ships ON — the Options row is an opt-OUT declutter, like Show Detection Meter")
	fresh.free()

func test_toggle_round_trips() -> void:
	Settings.set_enemy_health_bar_enabled(false)
	assert_false(Settings.enemy_health_bar_enabled, "set_enemy_health_bar_enabled(false) hides the bar")
	Settings.set_enemy_health_bar_enabled(true)
	assert_true(Settings.enemy_health_bar_enabled, "and back on")

func test_toggle_is_an_options_row() -> void:
	# The row is DATA (a SettingSpec in SettingsCatalog.tres), not hand-built UI — CLAUDE.md's settings rule.
	var catalog: SettingsCatalog = load("res://resources/settings/SettingsCatalog.tres")
	var found := false
	for spec in catalog.specs:
		if spec != null and spec.key == &"enemy_health_bar":
			found = true
			assert_eq(spec.tab, &"Accessibility", "the enemy health bar row lives on the Accessibility tab")
			assert_eq(spec.getter, &"enemy_health_bar_enabled", "bound to the Settings field")
			assert_eq(spec.setter, &"set_enemy_health_bar_enabled", "bound to the Settings setter")
	assert_true(found, "SettingsCatalog.tres must carry an 'enemy_health_bar' spec — an Options row is not optional for a player-facing HUD element")

# --- the push chain's method surface ------------------------------------------------------------------

func test_player_exposes_the_damaged_target_hook() -> void:
	# Character.take_damage calls this duck-typed (has_method-gated) on the attacker; renaming it here without
	# renaming it there would silently kill the whole feature with no error anywhere.
	# Plain `=`, not `:=` — here and at the other two off-tree `.new()` loads below. `load()` itself is typed
	# (Resource), but `.new()` on it has NO static return type, so `:=` is a hard PARSE error ("cannot infer the
	# type") that kills the whole script. Annotate or use plain `=`; never "tidy" these into `:=`.
	var p = load("res://scripts/player/player.gd").new()
	assert_true(p.has_method("on_damaged_target"),
		"Player must expose on_damaged_target — the seam Character.take_damage notifies to raise the enemy bar")
	p.on_damaged_target(null, 1.0, 10.0)  # safe off-tree (no HUD built -> no-op)
	assert_true(true, "on_damaged_target must be safe with no UI")
	p.free()

func test_base_character_does_not_implement_the_hook() -> void:
	# The gate is has_method, so an NPC attacker must NOT answer to it — otherwise an NPC-vs-NPC trade would
	# try to paint a HUD that isn't theirs.
	var c = load("res://scripts/player/character.gd").new()
	assert_false(c.has_method("on_damaged_target"),
		"only the Player implements on_damaged_target — the Character base must stay silent so NPC attackers no-op")
	c.free()

func test_player_hud_exposes_the_bar_facades() -> void:
	var hud = load("res://scripts/player/player_hud.gd").new()
	assert_true(hud.has_method("show_enemy_health"),
		"PlayerHud.show_enemy_health is the Player's forwarding target")
	assert_true(hud.has_method("clear_enemy_health"),
		"PlayerHud.clear_enemy_health must exist — Player.die() calls it BEFORE ui.hide_hud_for_death() takes its snapshot")
	hud.clear_enemy_health()  # safe before build() (no bar yet -> no-op)
	assert_true(true, "clear_enemy_health must be safe before build()")
	hud.free()
