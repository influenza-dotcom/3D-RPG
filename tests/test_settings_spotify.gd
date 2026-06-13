extends GutTest

## The Settings autoload's [spotify] persistence layer. We build a BARE Settings.new() (NOT the live
## autoload): its _loaded flag stays false, so the setters' save_settings() no-ops and we never touch the
## real user://settings.cfg — we assert the in-memory field updates only. (Round-trip through a real cfg is
## manual-playtest territory; load_settings reads CONFIG_PATH directly.)

const SETTINGS_SCRIPT := "res://managers/Settings.gd"

func _make() -> Node:
	return load(SETTINGS_SCRIPT).new()

func test_spotify_defaults_off_and_unlinked() -> void:
	var s := _make()
	assert_false(s.spotify_enabled, "Spotify is opt-in — off by default")
	assert_eq(s.spotify_refresh_token, "", "no token on a fresh profile")
	assert_false(s.spotify_is_linked(), "not linked without a refresh token")
	s.free()

func test_set_enabled_updates_field() -> void:
	var s := _make()
	s.set_spotify_enabled(true)
	assert_true(s.spotify_enabled, "the enable toggle flips the stored flag")
	s.free()

func test_set_account_stores_token_and_marks_linked() -> void:
	var s := _make()
	s.set_spotify_account("refresh-xyz", "user-1", "Ada")
	assert_eq(s.spotify_refresh_token, "refresh-xyz", "stores the long-lived refresh token")
	assert_eq(s.spotify_user_id, "user-1")
	assert_eq(s.spotify_user_name, "Ada")
	assert_true(s.spotify_is_linked(), "a stored refresh token = linked")
	s.free()

func test_clear_unlinks_and_wipes_account() -> void:
	var s := _make()
	s.set_spotify_account("refresh-xyz", "user-1", "Ada")
	s.clear_spotify()
	assert_eq(s.spotify_refresh_token, "", "unlink wipes the token")
	assert_eq(s.spotify_user_id, "")
	assert_eq(s.spotify_user_name, "")
	assert_false(s.spotify_is_linked(), "no longer linked after unlink")
	s.free()
