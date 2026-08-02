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

func test_require_scroll_defaults_on() -> void:
	# The wall-of-text dark pattern (must scroll to the end before Agree unlocks) ships ON by default.
	var tos := TermsOfService.new()
	assert_true(tos.require_scroll, "the player must scroll to the end before agreeing, by default")
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

func test_accept_tos_records_consent() -> void:
	# accept_tos() flips the flag. On a bare instance _loaded is false, so the save_settings() call inside is a
	# no-op — this asserts the in-memory contract without writing the real user://settings.cfg.
	var fresh = load("res://managers/Settings.gd").new()
	assert_false(fresh.tos_accepted, "starts unaccepted")
	fresh.accept_tos()
	assert_true(fresh.tos_accepted, "accept_tos records consent")
	fresh.free()

func test_debug_always_show_tos_default_off_and_toggles() -> void:
	# The replay toggle defaults OFF and is enabled only via the debug Options row. Its getter/setter names are also
	# cross-checked against the SettingsCatalog row by tests/test_settings_catalog.gd.
	var fresh = load("res://managers/Settings.gd").new()
	assert_false(fresh.debug_always_show_tos, "the TOS-replay toggle defaults OFF")
	fresh.set_debug_always_show_tos(true)
	assert_true(fresh.debug_always_show_tos, "the TOS-replay debug toggle can be enabled")
	fresh.set_debug_always_show_tos(false)
	assert_false(fresh.debug_always_show_tos, "the TOS-replay debug toggle can be disabled")
	fresh.free()


# ---------------------------------------------------------------------------------------------------
# The gate screen's MOUSE-FIRST focus contract (the start-menu policy): nothing pre-highlighted —
# especially not "Decline" on a consent gate with Enter wired to press the focused button.
# ---------------------------------------------------------------------------------------------------

func test_gate_screen_never_pre_focuses_decline() -> void:
	var screen: Control = load("res://scripts/ui/terms_of_service_screen.gd").new()
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
