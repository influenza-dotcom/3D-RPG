extends GutTest

## Contract pins for the MENU SOUND system (MenuSkin's "Sounds" group + MenuStyle's play_* seams).
##
## What actually breaks in the field, and is therefore what's pinned here:
##  * a cue slot renamed on the skin -> that event goes silent with no error (every play_* treats a null
##    stream as a no-op ON PURPOSE, so audio can land one cue at a time);
##  * a voice built without PROCESS_MODE_ALWAYS or off the "sfx" bus -> silent inside the seven PAUSING
##    screens, or deaf to the SFX volume slider (see menu_style.gd's invariant 1);
##  * audio construction drifting from _build_sound() into rebuild() -> a bare .new() + rebuild() (the
##    idiom tests/test_menu_skin_art.gd uses, which never runs _ready) would start spawning players
##    off-tree, and a play_* reachable at boot would sting under the splash;
##  * set_button_sound losing its no-double-sound guarantee -> every re-pointed button sounds twice.
##
## MenuStyle is an autoload, so the live instance is used for the pool/bus assertions; the off-tree
## assertions deliberately build a BARE instance instead (never _ready()) to prove the structural guard.

const STYLE_SCRIPT := "res://scripts/ui/menu_style.gd"

## Every cue kind MenuStyle.play_ui understands, paired with the MenuSkin property it must resolve to.
## Keeping the pair list here is what catches a rename on either side.
const CUE_TO_SLOT := {
	&"open": &"open_sound",
	&"back": &"back_sound",
	&"tab": &"tab_sound",
	&"select": &"click_sound",
	&"commit": &"commit_sound",
	&"step_left": &"step_left_sound",
	&"step_right": &"step_right_sound",
}


# --- MenuSkin: the designer surface -------------------------------------------------------------------

## The declared property names of `obj`, as a lookup set. Used instead of the `in` operator, which cannot
## distinguish "property missing" from "property present but null" — exactly the case being asserted here.
func _property_names(obj: Object) -> Dictionary:
	var names: Dictionary = {}
	for p in obj.get_property_list():
		names[StringName(p.name)] = true
	return names


func test_skin_exposes_every_cue_slot() -> void:
	var skin := MenuSkin.new()
	var props := _property_names(skin)
	for slot in [&"hover_sound", &"click_sound", &"open_sound", &"back_sound", &"tab_sound",
			&"step_left_sound", &"step_right_sound", &"commit_sound"]:
		assert_true(props.has(slot), "MenuSkin must expose the '%s' cue slot — MenuStyle resolves cues by this exact name" % slot)
		assert_null(skin.get(slot), "'%s' must default to null so a bare skin is SILENT, not noisy" % slot)
	skin = null


func test_skin_exposes_volume_trims_and_retrigger_limits() -> void:
	var skin := MenuSkin.new()
	var props := _property_names(skin)
	for trim in [&"ui_sound_volume_db", &"hover_volume_db", &"click_volume_db", &"open_volume_db",
			&"back_volume_db", &"tab_volume_db", &"step_volume_db", &"commit_volume_db"]:
		assert_true(props.has(trim), "MenuSkin must expose the '%s' trim (per-cue levelling is a designer job)" % trim)
		assert_eq(float(skin.get(trim)), 0.0, "'%s' must default to 0 dB — the shipped level is the artist's, not a code guess" % trim)
	# The anti-machine-gun thresholds are designer knobs, not consts (CLAUDE.md: never hardcode a tunable).
	assert_eq(skin.hover_min_interval, 0.05, "hover_min_interval default")
	assert_eq(skin.step_min_interval, 0.08, "step_min_interval default")
	assert_eq(skin.slider_tick_count, 12, "slider_tick_count default")
	skin = null


func test_shipped_skin_assigns_every_cue() -> void:
	# The authored resource is what the player actually hears; an unassigned slot is the exact failure mode
	# that made the menus silent before this feature landed.
	var skin: Resource = load("res://resources/ui/menu_skin.tres")
	assert_not_null(skin, "resources/ui/menu_skin.tres must load")
	assert_not_null(skin.get(&"hover_sound"), "shipped skin must assign hover_sound")
	for cue in CUE_TO_SLOT:
		var slot: StringName = CUE_TO_SLOT[cue]
		assert_not_null(skin.get(slot), "shipped skin must assign %s (cue &\"%s\")" % [slot, cue])
	skin = null


# --- MenuStyle: the voices ----------------------------------------------------------------------------

func test_every_voice_is_always_mode_on_the_sfx_bus() -> void:
	# The two named players are pinned by tests/test_options_menu.gd as well — do not rename them.
	var voices: Array = [MenuStyle._hover_player, MenuStyle._click_player]
	voices.append_array(MenuStyle._ui_players)
	assert_eq(MenuStyle._ui_players.size(), 4,
		"the semantic pool is 4 voices — the open sting can overlap a tab swap and a commit, plus one spare")
	for v in voices:
		assert_not_null(v, "every menu voice must be built in _build_sound()")
		assert_eq(v.bus, &"sfx",
			"menu voices must sit on the SFX bus so the SFX volume slider applies (a bare player lands on Master)")
		assert_eq(v.process_mode, Node.PROCESS_MODE_ALWAYS,
			"menu voices must process ALWAYS — a station screen opened from DIALOGUE runs under the conversation's pause (as does anything reached through FreezeFrame on death), and an inherit-mode player silently drops the play()")


func test_play_seams_exist() -> void:
	for m in ["play_ui", "play_open", "play_back", "play_tab", "play_select", "play_commit",
			"play_step", "play_slider_step", "set_button_sound", "set_quiet", "quiet_next_back"]:
		assert_true(MenuStyle.has_method(m), "MenuStyle.%s() is the seam screens call — renaming it silently un-sounds them" % m)


# --- The boot / off-tree structural guard --------------------------------------------------------------

func test_bare_instance_builds_no_voices_and_survives_every_cue() -> void:
	# Mirrors test_menu_skin_art.gd's idiom: construct + rebuild() WITHOUT _ready(). If audio construction
	# ever migrates into rebuild(), this starts spawning AudioStreamPlayers off-tree — and, worse, a cue
	# would become reachable before the pool exists, i.e. during a screen autoload's boot-time _ready.
	var bare: Node = load(STYLE_SCRIPT).new()
	bare.rebuild()
	assert_eq((bare.get(&"_ui_players") as Array).size(), 0,
		"rebuild() must NOT build voices — audio construction belongs in _build_sound() only")
	# Every seam must no-op rather than error while the pool is empty (this is the boot-sting backstop).
	bare.play_open()
	bare.play_back()
	bare.play_tab()
	bare.play_commit()
	bare.play_select()
	bare.play_step(1)
	bare.play_step(-1)
	bare.play_ui(&"nonsense_kind")
	bare.play_ui(&"")
	assert_eq(bare.get_child_count(), 0, "a bare MenuStyle must add no children until _ready builds them")
	bare.free()


# --- set_button_sound: the no-double-sound contract -----------------------------------------------------

func test_set_button_sound_replaces_the_generic_click() -> void:
	var btn := Button.new()
	# Simulate the AUTHORED-scene order: apply()'s sweep click-wires the button BEFORE its screen's
	# _ready() gets a chance to re-point it.
	MenuStyle._wire_button(btn)
	assert_true(btn.pressed.is_connected(MenuStyle._play_click), "precondition: _wire_button connects the generic click")
	MenuStyle.set_button_sound(btn, &"commit")
	assert_false(btn.pressed.is_connected(MenuStyle._play_click),
		"set_button_sound must DISCONNECT the generic click — otherwise a re-pointed button sounds twice per press")
	assert_eq(StringName(btn.get_meta(&"_snd_semantic")), &"commit", "the cue kind is read from the meta at press time")
	btn.free()


func test_wire_button_skips_the_click_when_a_cue_was_set_first() -> void:
	# The RUNTIME-built order: a row is given its cue at construction, then enters the tree and the
	# node_added hook wires it. The guard has to work in this direction too.
	var btn := Button.new()
	MenuStyle.set_button_sound(btn, &"tab")
	MenuStyle._wire_button(btn)
	assert_false(btn.pressed.is_connected(MenuStyle._play_click),
		"_wire_button must skip the generic click for a button that already carries a semantic cue")
	assert_true(btn.mouse_entered.get_connections().size() > 0, "hover stays wired — only the CLICK is replaced")
	btn.free()


func test_muted_button_keeps_hover_but_never_clicks() -> void:
	# &"" is the mute used by the player-menu tab strip, whose cue comes from PlayerMenus.enter instead.
	var btn := Button.new()
	MenuStyle.set_button_sound(btn, &"")
	MenuStyle._wire_button(btn)
	assert_false(btn.pressed.is_connected(MenuStyle._play_click), "a muted button must not fire the generic click")
	assert_eq(StringName(btn.get_meta(&"_snd_semantic")), &"", "&\"\" is the explicit mute marker")
	btn.free()


func test_set_button_sound_is_idempotent_and_repointable() -> void:
	var btn := Button.new()
	MenuStyle.set_button_sound(btn, &"tab")
	var after_first: int = btn.pressed.get_connections().size()
	MenuStyle.set_button_sound(btn, &"commit")
	assert_eq(btn.pressed.get_connections().size(), after_first,
		"calling set_button_sound again must RE-POINT the cue, never stack a second handler")
	assert_eq(StringName(btn.get_meta(&"_snd_semantic")), &"commit", "the kind updates in place")
	btn.free()


# --- Slider quantising --------------------------------------------------------------------------------

func test_first_slider_call_only_seeds() -> void:
	# Menus write .value programmatically (loading settings, Revert, rebuilding a tab). The first call for a
	# slider must therefore be silent, or every Apply would tick.
	var s := HSlider.new()
	s.min_value = 0.0
	s.max_value = 100.0
	s.step = 1.0
	MenuStyle._step_last_ms = 0
	MenuStyle.play_slider_step(s, 50.0)
	assert_true(s.has_meta(&"_snd_last"), "the first call stashes the previous value on the slider")
	assert_eq(MenuStyle._step_last_ms, 0, "the seeding call must NOT play — it is bookkeeping, not a drag")
	s.free()


func test_slider_ticks_once_per_bucket_not_once_per_step() -> void:
	# A 0..360 step-1 slider has 360 steps; unquantised it would machine-gun. It must instead produce about
	# skin.slider_tick_count ticks across a full sweep, so every slider in the game feels the same.
	var s := HSlider.new()
	s.min_value = 0.0
	s.max_value = 360.0
	s.step = 1.0
	MenuStyle.play_slider_step(s, 0.0)  # seed
	var ticks := 0
	for v in range(1, 361):
		MenuStyle._step_last_ms = 0  # bypass the time throttle so this measures the BUCKET math alone
		MenuStyle.play_slider_step(s, float(v))
		if MenuStyle._step_last_ms != 0:
			ticks += 1
	var want: int = MenuStyle.skin.slider_tick_count
	assert_almost_eq(ticks, want, 1,
		"a full sweep should tick ~slider_tick_count (%d) times, got %d — the bucket quantiser drifted" % [want, ticks])
	s.free()


func test_step_throttle_drops_a_repeat_inside_the_window() -> void:
	# This is what tames keyboard AUTO-REPEAT on the Options cyclers, which deliberately allow echo.
	MenuStyle._step_last_ms = 0
	MenuStyle.play_step(1)
	var first: int = MenuStyle._step_last_ms
	assert_ne(first, 0, "the first step stamps the throttle clock")
	MenuStyle.play_step(1)
	assert_eq(MenuStyle._step_last_ms, first,
		"a second step inside skin.step_min_interval must be DROPPED, not queued")


func test_zero_direction_is_a_no_op() -> void:
	MenuStyle._step_last_ms = 0
	MenuStyle.play_step(0)
	assert_eq(MenuStyle._step_last_ms, 0, "dir == 0 means 'nothing moved' and must stay silent")


# --- The sweep latch and the back-eater ------------------------------------------------------------------

func test_quiet_latch_silences_cues() -> void:
	# InputManager.close_all_modals holds this across the death/quickload sweep.
	MenuStyle.set_quiet(true)
	MenuStyle._step_last_ms = 0
	MenuStyle.play_step(1)
	assert_eq(MenuStyle._step_last_ms, 0, "the quiet latch must suppress cues outright")
	MenuStyle.set_quiet(false)
	assert_false(MenuStyle._quiet, "the latch must be released — a stranded mute silences the whole UI")


func test_semantic_cue_cuts_the_generic_click_of_the_same_press() -> void:
	# The structural no-double-sound rule. Every standalone modal's Close button fires the auto-wired click
	# and then ModalMenu.restore_mouse's back cue in the same frame; muting each such button by hand across
	# twenty screens would drift, so the specific cue cuts the click instead.
	MenuStyle._play_click()
	assert_true(MenuStyle._click_player.playing, "precondition: the generic click voice is ringing")
	MenuStyle.play_back()
	assert_false(MenuStyle._click_player.playing,
		"a semantic cue fired within SAME_PRESS_MS must CUT the generic click — otherwise Close sounds twice")


func test_a_stale_click_is_not_cut_by_a_later_cue() -> void:
	# The window must be tight enough that an unrelated later cue never truncates a genuine click.
	MenuStyle._play_click()
	MenuStyle._click_started_ms = Time.get_ticks_msec() - (MenuStyle.SAME_PRESS_MS + 500)
	MenuStyle.play_back()
	assert_true(MenuStyle._click_player.playing,
		"a click from an EARLIER press must survive — the cut is scoped to one press, not 'any click'")
	MenuStyle._click_player.stop()


func test_quiet_next_back_eats_exactly_one_back() -> void:
	# For a commit that immediately closes its own screen (respec confirm, a save that reloads).
	MenuStyle.quiet_next_back()
	assert_eq(MenuStyle._quiet_backs, 1, "one token queued")
	MenuStyle.play_back()
	assert_eq(MenuStyle._quiet_backs, 0, "the next back cue consumes the token")
	MenuStyle.play_back()
	assert_eq(MenuStyle._quiet_backs, 0, "and only ONE back is eaten — later closes still speak")
