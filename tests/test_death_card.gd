extends GutTest

## Death-meaning knob + the editable death card (ML-2). The death_mode enum is branched in
## Player._on_death_sequence_done (CHECKPOINT_RESPAWN = today's Dark-Souls revive / RELOAD_LAST_SAVE /
## RELOAD_CHECKPOINT_FRESH); the card's text is a designer-editable death_message on the player_feedback tuning
## resource, NOT a hardcoded string. The in-scene card draw and the reload itself are in-tree behaviour (a Player's
## _ready cannot run under GUT) and playtested. Driven off-tree here: the card line read from the LIVE resource, the
## killer-name ladder, and the click-to-skip against a real Tween. Pinned: the enum's serialized ordinals, the shipped
## default mode (a ship decision), and the RELOAD_LAST_SAVE routing, which only exists inside the tree.

## Live player_feedback fields a test below writes, restored after every test so no other file sees the edit.
const FEEDBACK_FIELDS_TOUCHED := ["death_message", "death_skip_enabled", "death_skip_speed"]
var _feedback_before := {}


func before_each() -> void:
	var fb: PlayerFeedbackSettings = GameSettings.player_feedback
	_feedback_before.clear()
	for field in FEEDBACK_FIELDS_TOUCHED:
		_feedback_before[field] = fb.get(field)


func after_each() -> void:
	var fb: PlayerFeedbackSettings = GameSettings.player_feedback
	for field in _feedback_before:
		fb.set(field, _feedback_before[field])


func test_death_mode_enum_has_three_modes() -> void:
	assert_eq(PlayerFeedbackSettings.DeathMode.CHECKPOINT_RESPAWN, 0, "CHECKPOINT_RESPAWN is the first (default) mode")
	assert_eq(PlayerFeedbackSettings.DeathMode.RELOAD_LAST_SAVE, 1, "RELOAD_LAST_SAVE is the second mode")
	assert_eq(PlayerFeedbackSettings.DeathMode.RELOAD_CHECKPOINT_FRESH, 2, "RELOAD_CHECKPOINT_FRESH is the third mode")
	assert_eq(PlayerFeedbackSettings.DeathMode.size(), 3, "exactly three death modes")


func test_an_unmet_killer_reads_by_the_live_in_sentence_stranger_form() -> void:
	# The death card is a SENTENCE ("You were killed by ___."), so an un-introduced killer must read by an indefinite,
	# lowercase form — never the label-case "Stranger" placeholder the hover/corpse/loot labels use ("killed by
	# Stranger." is the bug this knob exists to fix). Driven through _compose_death_message against the LIVE
	# player_feedback resource, so the slot wiring (stranger form vs. unknown-killer fallback) and the shipped copy
	# are both on the line. The shipped death MODE is pinned by the .tres test below; the unattributed line by
	# test_an_unattributed_death_reads_the_designers_live_death_message.
	var fb: PlayerFeedbackSettings = GameSettings.player_feedback
	var stranger_form := fb.death_stranger_killer
	assert_ne(stranger_form.strip_edges(), "", "the shipped stranger form is authored (a blank one reads 'You were killed by .')")
	assert_eq(stranger_form, stranger_form.to_lower(), "the shipped stranger form is lowercase — it sits mid-sentence: '%s'" % stranger_form)
	assert_true(stranger_form.begins_with("a ") or stranger_form.begins_with("an "),
		"the shipped stranger form carries its own indefinite article, so the line stays grammatical: '%s'" % stranger_form)
	assert_gt(fb.death_message_size, 0, "the shipped card font size is positive — a zero size paints no card at all")
	var prev_mask: bool = GameState.stranger_names_enabled
	GameState.stranger_names_enabled = true
	var p = load("res://scripts/player/player.gd").new()
	var k := StubNpcKiller.new()   # UNALIGNED (faction null) and job-less, so the ladder falls through to the stranger form
	k.display_name = "Zz Unmet Stranger Form Card Tester"  # unique — never revealed by any test
	p._credit_attacker = k
	var masked: String = p._compose_death_message()
	assert_true(masked.contains(stranger_form),
		"an un-introduced killer is named by the live stranger form on the card: %s" % masked)
	assert_false(masked.contains(PlayerText.STRANGER),
		"the label-case '%s' placeholder never reaches the death sentence: %s" % [PlayerText.STRANGER, masked])
	assert_false(masked.contains(k.display_name), "the unmet killer's real name stays hidden: %s" % masked)
	# CONTROL: the same killer with the stranger mask OFF is named outright, so the form above is the mask's doing.
	GameState.stranger_names_enabled = false
	var named: String = p._compose_death_message()
	assert_true(named.contains(k.display_name) and not named.contains(stranger_form),
		"with names unmasked the card names the killer instead of the stranger form: %s" % named)
	GameState.stranger_names_enabled = prev_mask
	p._credit_attacker = null
	k.free()
	p.free()


func test_shipped_death_mode_is_the_in_place_revive() -> void:
	# The LIVE .tres (GameSettings.player_feedback) is what the Player branches on in _on_death_sequence_done -- the
	# effective value, whether the .tres authors death_mode or inherits the script default.
	var fb = GameSettings.player_feedback
	assert_true(fb is PlayerFeedbackSettings, "player_feedback is a PlayerFeedbackSettings")
	assert_eq(fb.death_mode, PlayerFeedbackSettings.DeathMode.CHECKPOINT_RESPAWN,
		("SHIP DECISION: death is the non-destructive in-place revive. A shipped resource flipped to RELOAD_LAST_SAVE "
		+ "would make every death throw away everything the player did since the last autosave"))


func test_an_unattributed_death_reads_the_designers_live_death_message() -> void:
	# A fall, a stray blast or a self-inflicted death has no killer to name, so the card shows death_message -- read
	# from the LIVE tuning resource at the moment of death, so a designer's Inspector edit reaches the card. Off-tree:
	# _compose_death_message only reads the killer credit and that resource.
	var fb: PlayerFeedbackSettings = GameSettings.player_feedback
	fb.death_message = "Zz designer-authored death line"   # restored in after_each
	var p = load("res://scripts/player/player.gd").new()
	assert_eq(p._compose_death_message(), "Zz designer-authored death line",
		"with nobody credited for the kill the card shows the designer's death_message, not a line baked into the Player")
	# CONTROL: a credited killer composes the killed-by line instead, so the equality above really is the unattributed
	# branch reading the resource rather than every death echoing death_message.
	var hazard := Node.new()   # no display_name: the card falls back to death_unknown_killer
	p._credit_attacker = hazard
	var killed_by: String = p._compose_death_message()
	assert_ne(killed_by, "Zz designer-authored death line", "a death with a credited killer does not read the generic line")
	assert_true(killed_by.contains(fb.death_unknown_killer),
		"it names the killer instead -- here the unknown-killer fallback: %s" % killed_by)
	p._credit_attacker = null
	hazard.free()
	p.free()


func test_player_exposes_death_card_hooks() -> void:
	# The card show/hide + the mode branch exist on the Player (off-tree method-surface check; the draw is in-tree).
	var p = load("res://scripts/player/player.gd").new()
	assert_true(p.has_method(&"_show_death_card"), "the Player can raise the death card")
	assert_true(p.has_method(&"_hide_death_card"), "the Player can clear the death card on revive")
	assert_true(p.has_method(&"_on_death_sequence_done"), "the death-mode branch lives here")
	p.free()


# --- Clicking through the cinematic (the death skip) -------------------------------------------------

func test_death_skip_defaults_ship_on_and_sane() -> void:
	var s := PlayerFeedbackSettings.new()
	assert_true(s.death_skip_enabled, "a death you cannot click through is the behaviour the skip exists to fix")
	assert_gt(s.death_skip_delay, 0.0,
		("the skip must not arm on the frame you die — dying while mashing the fire button at your killer would "
		+ "skip the death card with the same clicks that got you killed"))
	assert_gt(s.death_skip_speed, 1.0, "a skip speed of 1 or less would not fast-forward anything")
	s = null

func test_player_exposes_the_death_skip_seams() -> void:
	var p = load("res://scripts/player/player.gd").new()
	for seam in ["_unhandled_input", "_is_death_skip_press", "_try_skip_death_beat", "_arm_death_skip", "_on_death_card_shown"]:
		assert_true(p.has_method(seam), "the death skip needs %s() on the Player" % seam)
	p.free()

func test_the_skip_refuses_when_no_cinematic_is_running() -> void:
	# _unhandled_input fires on every event in normal play; with no death tween there is nothing to skip and
	# the click must fall through to the game rather than being swallowed. The skip is ENABLED and ARMED with its
	# watch window already over, so the missing tween is the only thing left to refuse it.
	var fb: PlayerFeedbackSettings = GameSettings.player_feedback
	fb.death_skip_enabled = true   # restored in after_each
	var p = load("res://scripts/player/player.gd").new()
	p._death_skip_ready_msec = Time.get_ticks_msec()
	assert_false(p._try_skip_death_beat(), "an armed click with no death cinematic running must not be consumed")
	assert_true(p._death_skip_ready_msec >= 0, "...and a refused click does not spend the arm")
	# CONTROL: the SAME armed player with a cinematic tween running accepts the click, so the refusal above is the
	# missing tween and not the arm or the setting.
	var fired: Array = []
	var cinematic := _paused_cinematic(fired)
	p._death_tween = cinematic
	assert_true(p._try_skip_death_beat(), "with a cinematic running the same armed click is consumed")
	cinematic.kill()
	p.free()

func test_arming_the_skip_uses_a_future_wall_clock_deadline() -> void:
	# Wall-clock (Time.get_ticks_msec), NOT a tween or a physics count: the cinematic drops the world into
	# slow-mo and stops the player's physics step, either of which would stretch or freeze the wait.
	var fb: PlayerFeedbackSettings = GameSettings.player_feedback
	var p = load("res://scripts/player/player.gd").new()
	var before := Time.get_ticks_msec()
	p._arm_death_skip()
	var armed_at: int = p._death_skip_ready_msec
	p.free()
	if fb.death_skip_enabled:
		assert_gte(armed_at, before + int(fb.death_skip_delay * 1000.0),
			"the beat must be watchable for death_skip_delay before a click is accepted")
	else:
		assert_eq(armed_at, -1, "a disabled skip must never arm")

func test_only_a_click_or_accept_skips_the_cinematic() -> void:
	# Deliberately narrower than the start menu's "press anything": dying with a movement key half-pressed is
	# normal, and a stray WASD tap must not spend a beat of the cinematic.
	var p = load("res://scripts/player/player.gd").new()
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	assert_true(p._is_death_skip_press(click), "a left-click skips the beat — the whole point of the feature")
	var released := InputEventMouseButton.new()
	released.button_index = MOUSE_BUTTON_LEFT
	released.pressed = false
	assert_false(p._is_death_skip_press(released), "the RELEASE of a click must not spend a second beat")
	var walk := InputEventKey.new()
	walk.keycode = KEY_W
	walk.pressed = true
	assert_false(p._is_death_skip_press(walk), "a movement key must not skip the death cinematic")
	click = null
	released = null
	walk = null
	p.free()


## A stand-in for the death cinematic with the shape _run_death_sequence builds: ONE tween whose beats each end in a
## callback (the world-reset cue on the black frame, the card, the death-mode branch), here three one-second beats that
## log their names. PAUSED, so only custom_step advances it: the test owns the clock, and custom_step applies the
## tween's speed scale exactly as the tree's own per-frame step does. The caller kills it.
func _paused_cinematic(fired: Array) -> Tween:
	var tw := create_tween()
	tw.pause()
	for beat in ["covered", "card", "done"]:
		tw.tween_interval(1.0)
		tw.tween_callback(func() -> void: fired.append(beat))
	return tw


func test_the_skip_speeds_the_cinematic_up_rather_than_cutting_it_short() -> void:
	# THE invariant. The cinematic is ONE tween whose callbacks fire the world-reset cue on the black frame, the card,
	# and the death-mode branch that respawns or reloads. A skip that killed the tween and jumped to the end would have
	# to re-implement all three -- and would silently drop whichever beat is added next. So a skip must SCALE the tween:
	# nothing fires on the click, the beats arrive death_skip_speed times sooner, and every one still fires, in order.
	var fb: PlayerFeedbackSettings = GameSettings.player_feedback
	fb.death_skip_enabled = true   # restored in after_each
	fb.death_skip_speed = 4.0
	var p = load("res://scripts/player/player.gd").new()
	var fired: Array = []
	var cinematic := _paused_cinematic(fired)
	var unskipped_fired: Array = []
	var unskipped := _paused_cinematic(unskipped_fired)
	p._death_tween = cinematic
	p._death_skip_ready_msec = Time.get_ticks_msec()   # armed, and its watch window already over
	assert_true(p._try_skip_death_beat(), "an armed click during the cinematic is consumed")
	assert_true(cinematic.is_valid(), "the skip leaves the cinematic tween alive -- a killed tween never fires the rest of its chain")
	assert_eq(fired, [], "nothing fires on the click itself: a skip that jumped to the end would run every beat on this frame")
	assert_eq(p._death_skip_ready_msec, -1, "the click spends this beat's skip, so a mashed second click cannot spend the next beat too")
	cinematic.custom_step(0.3)
	unskipped.custom_step(0.3)
	assert_eq(unskipped_fired, [], "control: 0.3 s into an unskipped cinematic no one-second beat has ended yet")
	assert_eq(fired, ["covered"], "the skipped cinematic runs at death_skip_speed (4x here): 0.3 s covered the first 1.2 s of beats")
	cinematic.custom_step(0.5)
	assert_eq(fired, ["covered", "card", "done"],
		"every beat still fires, exactly once and in order -- the world-reset cue, the card, then the death-mode branch")
	cinematic.kill()
	unskipped.kill()
	p.free()


func test_the_card_hands_the_cinematic_back_to_its_authored_pace_and_rearms_the_skip() -> void:
	# TWO BEATS, ONE RULE: the first click fast-forwards TO the card, not THROUGH it. When the card reaches full opacity
	# the cinematic drops back to its authored pace (so the card can be read) and the skip re-arms for the card's own
	# beat. A designer who blanked the death line left nothing to read, so there the skip runs straight on.
	var fb: PlayerFeedbackSettings = GameSettings.player_feedback
	fb.death_skip_enabled = true   # restored in after_each
	fb.death_skip_speed = 4.0
	var p = load("res://scripts/player/player.gd").new()
	var fired: Array = []
	var cinematic := _paused_cinematic(fired)
	p._death_tween = cinematic
	p._death_card_text = "You were killed."
	p._death_skip_ready_msec = Time.get_ticks_msec()
	assert_true(p._try_skip_death_beat(), "the first click is consumed")
	var shown_at := Time.get_ticks_msec()
	p._on_death_card_shown()
	cinematic.custom_step(0.3)
	assert_eq(fired, [], "once the card is up the cinematic runs at its authored pace again: 0.3 s does not end a one-second beat")
	assert_gte(p._death_skip_ready_msec, shown_at,
		"and the skip is re-armed for the card's own beat (-1 would mean the card could never be clicked away)")
	# CONTROL: the same sequence with a BLANK card keeps the fast-forward, so the pace drop above is the card's doing.
	p._death_card_text = ""
	p._death_skip_ready_msec = Time.get_ticks_msec()
	assert_true(p._try_skip_death_beat(), "a click on the next beat is consumed")
	p._on_death_card_shown()
	cinematic.custom_step(0.3)
	assert_eq(fired, ["covered"], "with no card to stop for, the skip keeps fast-forwarding instead of parking on a blank screen")
	cinematic.kill()
	p.free()


## Duck-typed stand-in for an NPC killer: a display_name plus the resolved_disposition method that
## _killer_display_name uses as its "is a real person" gate (so the Stranger mask applies), plus the
## `faction` slot the NPC resolves its faction_id dropdown into (null == UNALIGNED, as on a real NPC).
class StubNpcKiller:
	extends Node
	var display_name := ""
	var faction: Faction = null
	func resolved_disposition() -> int:
		return 0


func _faction_with_noun(id: StringName, noun: String) -> Faction:
	var f := Faction.new()
	f.id = id
	f.display_name = String(id).capitalize()
	f.member_noun = noun
	return f


func test_killer_display_name_swaps_stranger_mask_for_indefinite_form() -> void:
	# The death card is a SENTENCE, so an un-introduced killer must read "killed by a stranger", never
	# "killed by Stranger" (the proper-noun placeholder is for label contexts: hover, corpse, loot title).
	# Off-tree: _killer_display_name only reads the live GameState name ledger, no scene needed.
	var prev_mask: bool = GameState.stranger_names_enabled
	GameState.stranger_names_enabled = true
	var p = load("res://scripts/player/player.gd").new()
	var k := StubNpcKiller.new()
	k.display_name = "Zz Unmet Card Tester"  # unique — never revealed by any other test
	assert_eq(p._killer_display_name(k, "someone", "a stranger"), "a stranger",
		"an un-introduced NPC killer masks to the indefinite 'a stranger' on the death card")
	GameState.reveal_name(k.display_name)
	assert_eq(p._killer_display_name(k, "someone", "a stranger"), "Zz Unmet Card Tester",
		"once introduced, the real name shows on the death card")
	var hazard := Node.new()  # no display_name / no resolved_disposition -> blank-name fallback path
	assert_eq(p._killer_display_name(hazard, "someone", "a stranger"), "someone",
		"a nameless killer still falls back to death_unknown_killer, not the stranger form")
	GameState.stranger_names_enabled = prev_mask
	hazard.free()
	k.free()
	p.free()


func test_faction_member_noun_names_an_unknown_killer_better_than_a_stranger() -> void:
	# THE REQUESTED BEHAVIOUR: an UNALIGNED killer stays "a stranger"; a killer who belongs to a faction
	# reads by that faction's in-sentence member_noun instead ("You were killed by a raider."). Same NPC,
	# same un-introduced state — the faction is the ONLY difference between the two lines.
	var prev_mask: bool = GameState.stranger_names_enabled
	GameState.stranger_names_enabled = true
	var p = load("res://scripts/player/player.gd").new()
	var k := StubNpcKiller.new()
	k.display_name = "Zz Unmet Faction Card Tester"  # unique — never revealed by any other test
	assert_eq(p._killer_display_name(k, "someone", "a stranger"), "a stranger",
		"UNALIGNED (faction == null) keeps the generic form — this is the case the design deliberately preserves")
	k.faction = _faction_with_noun(&"raiders", "a raider")
	assert_eq(p._killer_display_name(k, "someone", "a stranger"), "a raider",
		"a faction member the player never met is named by their faction, not by the faceless generic")
	# A NAME YOU KNOW OUTRANKS THE FACTION: being introduced tells you strictly more than the uniform does,
	# so the faction noun must NOT hijack an unmasked name.
	GameState.reveal_name(k.display_name)
	assert_eq(p._killer_display_name(k, "someone", "a stranger"), "Zz Unmet Faction Card Tester",
		"once introduced, the real name still wins over the faction noun")
	GameState.stranger_names_enabled = prev_mask
	k.free()
	p.free()


func test_faction_without_an_authored_noun_falls_back_instead_of_reading_blank() -> void:
	# member_noun is OPTIONAL. A half-authored faction (or one deliberately left anonymous) must fall through
	# to the old wording — never emit "You were killed by ." — and whitespace must not count as authored.
	var prev_mask: bool = GameState.stranger_names_enabled
	GameState.stranger_names_enabled = true
	var p = load("res://scripts/player/player.gd").new()
	var k := StubNpcKiller.new()
	k.display_name = "Zz Unmet Nounless Card Tester"  # unique — never revealed by any other test
	k.faction = _faction_with_noun(&"zz_nounless", "")
	assert_eq(p._killer_display_name(k, "someone", "a stranger"), "a stranger",
		"a faction with no authored member_noun leaves the stranger fallback standing")
	k.faction.member_noun = "   "
	assert_eq(p._killer_display_name(k, "someone", "a stranger"), "a stranger",
		"whitespace is not an authored noun — it would render as 'You were killed by  .'")
	GameState.stranger_names_enabled = prev_mask
	k.free()
	p.free()


func test_nameless_faction_killer_reads_by_faction_not_someone() -> void:
	# The OTHER anonymous rung: an NPC with no authored display_name at all used to read "someone". If it
	# has a faction, that is a strictly better name for it. A faction-less nameless killer still reads "someone".
	var p = load("res://scripts/player/player.gd").new()
	var k := StubNpcKiller.new()   # display_name deliberately left blank
	assert_eq(p._killer_display_name(k, "someone", "a stranger"), "someone",
		"a nameless, faction-less killer keeps the unknown-killer fallback")
	k.faction = _faction_with_noun(&"raiders", "a raider")
	assert_eq(p._killer_display_name(k, "someone", "a stranger"), "a raider",
		"a nameless killer with a faction is named by it")
	k.free()
	p.free()


func test_faction_noun_lookup_survives_a_killer_with_no_faction_property() -> void:
	# The death path is loosely typed (an NPC, a test double, a TITLED HAZARD) and must not crash on a killer
	# that has no `faction` member at all — the duck-typed .get() returns null and we fall through.
	var p = load("res://scripts/player/player.gd").new()
	var hazard := Node.new()
	assert_eq(p._killer_faction_noun(hazard), "",
		"a killer with no faction property resolves to no noun rather than erroring")
	assert_eq(p._killer_display_name(hazard, "someone", "a stranger"), "someone",
		"...and the card still composes its normal fallback line")
	hazard.free()
	p.free()


func test_shipped_factions_author_an_in_sentence_member_noun() -> void:
	# The three factions on disk are what the player actually meets, so their nouns are part of the copy, not
	# just a schema slot. Lowercase + article included, because they sit MID-SENTENCE ("You were killed by
	# a raider.") — a capitalized "Raiders" here would reproduce the exact "killed by Stranger" bug the
	# stranger fallback exists to fix.
	var Factions = load("res://scripts/faction/factions.gd")
	for id in ["raiders", "townsfolk", "neutral_wildlife"]:
		var f = Factions.by_id(id)
		assert_true(f is Faction, "%s resolves to a Faction" % id)
		var noun: String = f.member_noun
		assert_ne(noun, "", "%s authors an in-sentence member noun" % id)
		assert_eq(noun, noun.to_lower(), "%s's member noun is lowercase — it sits inside a sentence" % id)
		assert_true(noun.begins_with("a ") or noun.begins_with("an "),
			"%s's member noun carries its own indefinite article ('a raider'), so the line stays grammatical" % id)
	assert_eq(Factions.by_id("raiders").member_noun, "a raider",
		"the requested line: 'You were killed by a raider.'")


func test_a_faction_that_never_authors_a_member_noun_keeps_the_anonymous_wording() -> void:
	# member_noun is OPT-IN: a faction nobody gave a noun (a fresh .tres, a half-authored one) reads exactly as before
	# the feature. The faction here never has member_noun ASSIGNED -- its default is the thing under test, and the
	# ladder treats any non-blank value as authored, so a non-blank default would name every such killer by it.
	var prev_mask: bool = GameState.stranger_names_enabled
	GameState.stranger_names_enabled = true
	var p = load("res://scripts/player/player.gd").new()
	var fresh := Faction.new()
	fresh.id = &"zz_fresh_faction"
	fresh.display_name = "Zz Fresh Faction"
	var nameless := StubNpcKiller.new()   # no display_name
	nameless.faction = fresh
	assert_eq(p._killer_display_name(nameless, "someone", "a stranger"), "someone",
		"a nameless member of a faction with no authored noun keeps the unknown-killer fallback")
	var unmet := StubNpcKiller.new()
	unmet.display_name = "Zz Unmet Fresh Faction Tester"  # unique -- never revealed by any other test
	unmet.faction = fresh
	assert_eq(p._killer_display_name(unmet, "someone", "a stranger"), "a stranger",
		"an un-introduced member of a faction with no authored noun keeps 'a stranger'")
	GameState.stranger_names_enabled = prev_mask
	nameless.free()
	unmet.free()
	fresh = null
	p.free()


func test_reload_last_save_routes_through_the_autosave_freeze_seam() -> void:
	# THE RACE THIS PINS (2026-08-26 review find): autosave_world_state() coalesces to a one-frame-DEFERRED
	# flush. When the death frame also queued one (a door, a pickup, a kill bounty), a bare
	# GameState.load_from_disk() + reload_current_scene() in the RELOAD_LAST_SAVE branch let that flush run
	# AFTER the load, capture the still-in-tree OLD player, and autosave the abandoned timeline over the
	# checkpoint it had just loaded — silently destroying the save it was reverting to. The branch must route
	# through GameState.load_autosave() (-> _load_and_reload), which arms the _reload_pending freeze that
	# autosave() checks (latch behaviour: test_world_snapshot.gd; seam behaviour: test_debug_sandbox.gd).
	# KEPT AS A SOURCE PIN because it cannot be driven: _on_death_sequence_done returns before the branch unless the
	# Player is in the tree, and a Player's _ready must never run under GUT. Scoped to the RELOAD_LAST_SAVE arm and to
	# CODE (comments dropped), so a load_autosave() call elsewhere cannot satisfy it and the comment explaining the race
	# cannot trip it. If it fails after a refactor, re-route through the latch seam and re-pin the new spelling — never
	# satisfy it by restoring a bare load.
	assert_true(GameState.has_method(&"load_autosave"), "the death-reload seam exists on GameState")
	var src := FileAccess.get_file_as_string("res://scripts/player/player.gd")
	var death_done := _between(src, "func _on_death_sequence_done(", "\nfunc ")
	var reload_arm := _code_only(_between(death_done, "DeathMode.RELOAD_LAST_SAVE:", "DeathMode.RELOAD_CHECKPOINT_FRESH:"))
	assert_ne(reload_arm.strip_edges(), "", "the RELOAD_LAST_SAVE arm of _on_death_sequence_done was found (re-pin if the branch moved)")
	assert_true(reload_arm.contains("GameState.load_autosave()"),
		"the RELOAD_LAST_SAVE death branch loads the checkpoint through load_autosave() (arms _reload_pending)")
	assert_false(_code_only(src).contains("load_from_disk("),
		"no direct load_from_disk call in player.gd — outside _load_and_reload the loaded profile has no autosave-freeze protection")


## The text between the first `from` and the next `to` after it ("" when `from` is missing; to the end when `to` is).
func _between(text: String, from: String, to: String) -> String:
	var at := text.find(from)
	if at < 0:
		return ""
	var begin := at + from.length()
	var stop := text.find(to, begin)
	return text.substr(begin) if stop < 0 else text.substr(begin, stop - begin)


## `text` with every `#` comment removed (a `#` inside a double-quoted string is kept). Only lines that contain a `#`
## are walked character by character, so a whole-script pass stays cheap.
func _code_only(text: String) -> String:
	var lines := text.split("\n")
	for i in lines.size():
		var line := lines[i]
		if not line.contains("#"):
			continue
		var in_string := false
		for c in line.length():
			var ch := line[c]
			if ch == "\"" and (c == 0 or line[c - 1] != "\\"):
				in_string = not in_string
			elif ch == "#" and not in_string:
				lines[i] = line.substr(0, c)
				break
	return "\n".join(lines)
