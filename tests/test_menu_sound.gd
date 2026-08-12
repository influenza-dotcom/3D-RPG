extends GutTest

## Contract pins for the MENU SOUND system (MenuSkin's "Sounds" group + MenuStyle's play_* seams).
##
## What actually breaks in the field, and is therefore what's pinned here:
##  * a cue slot renamed on the skin -> that event goes silent with no error (every play_* treats a null
##    stream as a no-op ON PURPOSE, so audio can land one cue at a time);
##  * a voice built without PROCESS_MODE_ALWAYS or off the "sfx" bus -> silent under the only tree-pause
##    left in the game (DialogueManager's — which a station screen opened FROM a conversation runs under,
##    as does anything reached through FreezeFrame on death), or deaf to the SFX volume slider (see
##    menu_style.gd's invariant 1);
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
## &"denied" is deliberately ABSENT from CUE_TO_SLOT: it is the one cue whose slot may be null and still
## SOUND, because _stream_for falls back to back_sound (detuned by denied_pitch_scale). Its own contract is
## pinned by test_denied_cue_* below, and keeping it out of this table is what stops
## test_shipped_skin_assigns_every_cue from demanding a ninth clip that deliberately does not exist.


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
			&"step_left_sound", &"step_right_sound", &"commit_sound", &"denied_sound"]:
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
	# denied_volume_db is the ONE trim with a non-zero default, and deliberately so: its default voice is a
	# BORROWED clip (back_sound), levelled for a different job, so it needs pulling down out of the box.
	assert_true(props.has(&"denied_volume_db"), "MenuSkin must expose denied_volume_db")
	assert_eq(skin.denied_volume_db, -2.0, "denied_volume_db default (the derived cue borrows a clip levelled for 'close')")
	assert_true(props.has(&"denied_pitch_scale"), "MenuSkin must expose denied_pitch_scale")
	assert_lt(skin.denied_pitch_scale, 1.0,
		"the denial must default BELOW unity pitch — detuning is the only thing separating a derived refusal from the close cue it borrows")
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
	# The first two named players are pinned by tests/test_options_menu.gd as well — do not rename them.
	var voices: Array = [MenuStyle._hover_player, MenuStyle._click_player, MenuStyle._denied_player]
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
	for m in ["play_ui", "play_open", "play_back", "play_tab", "play_select", "play_commit", "play_denied",
			"play_hover", "play_step", "play_slider_step", "set_button_sound", "set_quiet", "quiet_next_back"]:
		assert_true(MenuStyle.has_method(m), "MenuStyle.%s() is the seam screens call — renaming it silently un-sounds them" % m)


# --- the denial cue: the refusal half of every gated commit ---------------------------------------------

## The DERIVED fallback, which is the whole reason a refusal is audible at all today: with denied_sound
## unassigned (as the shipped skin leaves it — there is no ninth clip), the cue must still resolve, to
## back_sound. If this ever returns null, ~30 refusal sites across the UI go quiet again in one stroke and
## nothing errors.
## Asserted on a BARE instance carrying a FIXTURE skin (never the autoload's), so the pin is about the
## resolution RULE and not about what the artist happens to have assigned today.
func test_denied_cue_falls_back_to_the_back_clip() -> void:
	var bare: Node = load(STYLE_SCRIPT).new()
	var skin := MenuSkin.new()
	var back_clip := AudioStreamWAV.new()
	skin.back_sound = back_clip
	assert_null(skin.denied_sound, "the fixture leaves the denial slot unassigned — the shipped state")
	bare.skin = skin
	assert_eq(bare._stream_for(&"denied"), back_clip,
		"an unassigned denied_sound must DERIVE from back_sound — otherwise every refusal site in the UI goes quiet at once, with no error")
	# ...and an AUTHORED clip still wins, so the fallback is a floor and not a ceiling.
	var own_clip := AudioStreamWAV.new()
	skin.denied_sound = own_clip
	assert_eq(bare._stream_for(&"denied"), own_clip, "an authored denied_sound overrides the fallback")
	bare.free()
	skin = null
	back_clip = null
	own_clip = null


## The same contract asserted against the LIVE autoload skin, which is the one that actually plays: whatever
## the artist has (or hasn't) assigned, &"denied" must resolve to a real stream.
func test_denied_cue_resolves_on_the_shipped_skin() -> void:
	assert_not_null(MenuStyle._stream_for(&"denied"),
		"the shipped skin must be able to SPEAK a refusal — either an authored denied_sound or the back_sound fallback")


## The pitch table. Two things break if this drifts: a denial detuned to 1.0 becomes indistinguishable from
## "menu closed" (the confusion the cue exists to end), and — the nastier one — a non-denial reported as
## pitched would mean play_ui leaves a detune on a POOL voice, silently transposing whatever cue reuses it.
func test_only_the_denial_is_pitched() -> void:
	assert_lt(MenuStyle._pitch_for(&"denied"), 1.0, "the denial is transposed down")
	for kind in [&"open", &"back", &"tab", &"select", &"commit", &"step_left", &"step_right", &""]:
		assert_eq(MenuStyle._pitch_for(kind), 1.0,
			"'%s' must play at unity — play_ui writes pitch_scale on EVERY play, so a stray non-1.0 here detunes a reused pool voice" % kind)


## The denial owns a DEDICATED voice instead of a pool slot, so spam-clicking a button the game keeps
## refusing restarts one buzz rather than stacking four and then stealing the open sting's voice.
func test_denial_has_its_own_voice_outside_the_pool() -> void:
	assert_not_null(MenuStyle._denied_player, "the denial voice must be built in _build_sound()")
	assert_false(MenuStyle._ui_players.has(MenuStyle._denied_player),
		"the denial voice must sit OUTSIDE the semantic pool — self-cutting is the point")


# --- play_hover: the non-Button surface seam ------------------------------------------------------------

## Tile hovers reach the SAME throttles as button hovers. The id argument is what makes the same-target gate
## work for a list that repaints under a stationary cursor; passing 0 opts out of that gate (but not the
## interval floor). Asserted through the public seam only — the internals are free to move.
func test_play_hover_accepts_a_target_id_and_stays_silent_while_quiet() -> void:
	MenuStyle.set_quiet(true)
	MenuStyle.play_hover(12345)   # must be a no-op, not an error, during the close-everything sweep
	MenuStyle.set_quiet(false)
	assert_false(MenuStyle._hover_player.playing,
		"a hover fired under the quiet latch must not sound — close_all_modals holds it across ~17 screens")


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
	bare.play_denied()   # the denial voice is built alongside the pool, so it must no-op here too
	bare.play_hover(1)   # the non-Button hover seam has its own null guard
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
