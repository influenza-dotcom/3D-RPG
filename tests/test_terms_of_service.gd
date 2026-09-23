extends GutTest

## Contract tests for the first-launch Terms-of-Service gate: the TermsOfService content resource
## (resources/ui/terms_of_service.gd) and the persisted Settings.tos_accepted consent flag.
##
## TermsOfService extends Resource (RefCounted): instances are made with .new() and released with `= null`.
## Settings extends Node: a bare instance is made with load(...).new() (NO add_child, so _ready never runs and
## nothing touches user://settings.cfg) and released with .free().

# ---------------------------------------------------------------------------------------------------
# The content resource defaults (the shipping document lives in the script's @export defaults)
# ---------------------------------------------------------------------------------------------------

func test_defaults_are_authored() -> void:
	var tos := TermsOfService.new()
	assert_ne(tos.title.strip_edges(), "", "the banner has a title")
	assert_eq(tos.subtitle, "", "the subtitle (subheader) is blank by default — no subheader is shown")
	assert_ne(tos.accept_label.strip_edges(), "", "the accept button is captioned")
	assert_ne(tos.decline_label.strip_edges(), "", "the decline button is captioned")
	assert_ne(tos.reconsider_label.strip_edges(), "", "the back button is captioned")
	assert_ne(tos.quit_label.strip_edges(), "", "the quit button is captioned")
	tos = null

func test_body_is_a_long_wall_of_text() -> void:
	# The whole joke is an impenetrable, unreadable agreement — assert it is substantial, not a stub.
	var tos := TermsOfService.new()
	assert_gt(tos.body.length(), 800, "the agreement is a long wall of text, not a placeholder")
	tos = null

func test_require_scroll_defaults_off() -> void:
	# The scroll-to-the-end gate (and its footnote) shipped as friction, not as the joke: OFF by default, and the
	# two footnote strings ship blank so the screen paints no "scroll to continue" line at all.
	var tos := TermsOfService.new()
	assert_false(tos.require_scroll, "Agree is live at once — nobody is made to scroll a joke to its end")
	assert_eq(tos.scroll_hint_unread, "", "no unread footnote")
	assert_eq(tos.scroll_hint_read, "", "no read footnote")
	tos = null

func test_load_default_returns_a_valid_document() -> void:
	# load_default() must ALWAYS hand back a usable document with a non-empty body — the designer .tres when it
	# exists, else the baked defaults — so the first-launch gate can never come up blank.
	var tos := TermsOfService.load_default()
	assert_not_null(tos, "load_default never returns null")
	assert_true(tos is TermsOfService, "load_default returns a TermsOfService")
	assert_ne(tos.body.strip_edges(), "", "the loaded document has a body")
	tos = null

# ---------------------------------------------------------------------------------------------------
# Settings.tos_accepted — the persisted first-launch consent flag
# ---------------------------------------------------------------------------------------------------

func test_tos_not_accepted_by_default() -> void:
	# A fresh install (a bare Settings, no cfg loaded) has NOT accepted — so the gate shows on first launch.
	var fresh = load("res://managers/Settings.gd").new()
	assert_false(fresh.tos_accepted, "the Terms are not accepted by default (the gate shows on first launch)")
	fresh.free()

func test_consent_is_one_way_and_the_replay_toggle_never_grants_or_revokes_it() -> void:
	# The dev replay toggle (debug_always_show_tos) is INDEPENDENT of the recorded consent: StartMenu ORs it into the
	# gate check, so it must neither stand in for consent nor erase it. On a bare instance _loaded is false, so every
	# save_settings() inside these setters is a no-op — the real user://settings.cfg is never written.
	var fresh = load("res://managers/Settings.gd").new()
	fresh.set_debug_always_show_tos(true)
	fresh.set_debug_always_show_tos(false)
	assert_false(fresh.tos_accepted,
		"flipping the replay toggle is not consent — a player who never clicked Agree still gets the gate")
	fresh.accept_tos()
	assert_true(fresh.tos_accepted, "Agree records consent")
	assert_false(fresh.debug_always_show_tos, "…without arming the replay, so the gate doesn't come back next launch")
	fresh.set_debug_always_show_tos(true)
	fresh.set_debug_always_show_tos(false)
	assert_true(fresh.tos_accepted, "cycling the replay toggle keeps the recorded consent — it never un-accepts")
	fresh.accept_tos()
	assert_true(fresh.tos_accepted, "accepting again is harmless — consent stays recorded")
	fresh.free()

func test_replay_toggle_ships_off_and_a_release_build_drops_it_but_keeps_consent() -> void:
	# The toggle's getter/setter names are cross-checked against the SettingsCatalog row by
	# tests/test_settings_catalog.gd; tests/test_settings.gd pins that a release build clears both debug toggles.
	var fresh = load("res://managers/Settings.gd").new()
	assert_false(fresh.debug_always_show_tos,
		"SHIP DECISION: the TOS-replay toggle defaults OFF — a fresh install shows the gate once, not every launch")
	fresh.accept_tos()
	fresh.set_debug_always_show_tos(true)
	fresh._sanitize_debug_flags(true)
	assert_true(fresh.debug_always_show_tos, "control: a debug build keeps the replay exactly as persisted")
	fresh._sanitize_debug_flags(false)
	assert_false(fresh.debug_always_show_tos, "a release build drops a persisted replay toggle")
	assert_true(fresh.tos_accepted,
		"…but never the player's recorded consent — a release boot must not re-show the gate to someone who already agreed")
	fresh.free()


# ---------------------------------------------------------------------------------------------------
# The gate screen's MOUSE-FIRST focus contract (the start-menu policy): nothing pre-highlighted —
# especially not "Decline" on a consent gate with Enter wired to press the focused button.
# ---------------------------------------------------------------------------------------------------

func test_gate_screen_never_pre_focuses_decline() -> void:
	# The screen is now an AUTHORED SCENE (scenes/ui/terms_of_service_screen.tscn — _bind_ui binds %nodes), so the
	# in-tree instance MUST come from the scene, never a bare-script .new() (whose _ready would null-deref).
	var screen: Control = (load("res://scenes/ui/terms_of_service_screen.tscn") as PackedScene).instantiate()
	add_child_autofree(screen)
	await get_tree().process_frame  # let the deferred first-layout work settle
	assert_null(screen.get_viewport().gui_get_focus_owner(),
		"the gate opens with NOTHING focused — an auto-focused Decline wore the skin's focus chrome as a permanent highlight")
	# The scroll axis must never seed focus: ui_down reads the agreement, it doesn't pick buttons.
	var down := InputEventAction.new()
	down.action = &"ui_down"
	down.pressed = true
	screen._input(down)
	assert_null(screen.get_viewport().gui_get_focus_owner(), "ui_down scrolls; it must not light a button as a side effect")
	# The button-row axis seeds on demand — a pad/keyboard player's first ui_right lands on the always-enabled Decline.
	var right := InputEventAction.new()
	right.action = &"ui_right"
	right.pressed = true
	screen._input(right)
	assert_eq(screen.get_viewport().gui_get_focus_owner(), screen._decline_btn,
		"the first ui_left/right press seeds focus on Decline (always enabled; Enter there only raises the nag, never consents)")
