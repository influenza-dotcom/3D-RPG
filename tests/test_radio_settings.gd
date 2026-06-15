extends GutTest

## RadioSettings — the optional Spotify radio's global/network config + its degenerate-config guard.
## Pure Resource, so .new() off-tree and release with = null.

const RADIO_SETTINGS := "res://resources/tuning/RadioSettings.gd"

func _make() -> RadioSettings:
	return load(RADIO_SETTINGS).new()

func test_defaults() -> void:
	var s := _make()
	assert_eq(s.client_id, "", "ships with no client_id (Spotify off until the dev fills it in)")
	assert_eq(s.redirect_port_min, 8888, "loopback port range low end")
	assert_eq(s.redirect_port_max, 8899, "loopback port range high end")
	assert_almost_eq(s.token_refresh_margin_s, 60.0, 0.001, "refresh margin default")
	assert_almost_eq(s.now_playing_poll_interval, 5.0, 0.001, "now-playing poll default (tightened so the now-playing toast lines up)")
	assert_true(s.scopes.contains("user-modify-playback-state"), "default scopes can control playback")
	s = null

func test_blank_client_id_is_off_not_an_error() -> void:
	var s := _make()
	assert_false(s.validate(), "A blank client_id means Spotify is OFF — validate() is false (quietly)")
	s = null

func test_valid_config_validates() -> void:
	var s := _make()
	s.client_id = "abc123"
	assert_true(s.validate(), "A filled client_id + sane defaults validates")
	s = null

func test_blank_scopes_fails_validation() -> void:
	var s := _make()
	s.client_id = "abc123"
	s.scopes = "   "
	assert_false(s.validate(), "Blank scopes can't build an OAuth request")
	s = null

func test_inverted_port_range_fails_validation() -> void:
	var s := _make()
	s.client_id = "abc123"
	s.redirect_port_min = 9000
	s.redirect_port_max = 8000
	assert_false(s.validate(), "An inverted port range has no valid loopback port")
	s = null

func test_out_of_range_ports_fail_validation() -> void:
	var s := _make()
	s.client_id = "abc123"
	s.redirect_port_min = 80
	assert_false(s.validate(), "Privileged/low ports are rejected")
	s = null
