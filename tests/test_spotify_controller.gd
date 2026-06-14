extends GutTest

## SpotifyController — the OAuth/playback autoload. The OAuth + playback I/O is manual-playtest (it needs the
## network, a real Premium account, and your dev-app client_id). The PURE, self-contained piece is the
## multi-radio OWNER-TOKEN arbitration, tested here on a bare instance (no _ready, no network). Loading the
## script here also compile-checks the whole controller under GUT without registering it as a boot autoload.

const CONTROLLER := "res://managers/SpotifyController.gd"

# Untyped (the autoload has no class_name) so acquire/owns/release dispatch dynamically.
func _make():
	return load(CONTROLLER).new()

func test_first_radio_acquires_ownership() -> void:
	var c = _make()
	var a := Node.new()
	assert_true(c.acquire(a), "the first radio to ask gets the token")
	assert_true(c.owns(a), "and is recorded as the owner")
	a.free()
	c.free()

func test_second_radio_cannot_steal_ownership() -> void:
	var c = _make()
	var a := Node.new()
	var b := Node.new()
	assert_true(c.acquire(a))
	assert_false(c.acquire(b), "a second radio can't take the token while another owns it")
	assert_false(c.owns(b), "and isn't the owner")
	assert_true(c.owns(a), "the original owner still holds it")
	a.free()
	b.free()
	c.free()

func test_owner_can_reacquire() -> void:
	var c = _make()
	var a := Node.new()
	assert_true(c.acquire(a))
	assert_true(c.acquire(a), "the current owner re-acquiring is a no-op success")
	a.free()
	c.free()

func test_release_frees_the_token_for_another() -> void:
	var c = _make()
	var a := Node.new()
	var b := Node.new()
	assert_true(c.acquire(a))
	c.release(a)
	assert_false(c.owns(a), "releasing drops ownership")
	assert_true(c.acquire(b), "so another radio can now take it")
	a.free()
	b.free()
	c.free()

func test_non_owner_release_is_ignored() -> void:
	var c = _make()
	var a := Node.new()
	var b := Node.new()
	assert_true(c.acquire(a))
	c.release(b)  # b doesn't own it — must not steal it away from a
	assert_true(c.owns(a), "a stale release from a non-owner can't drop the real owner's token")
	a.free()
	b.free()
	c.free()

func test_invalid_radio_never_owns() -> void:
	var c = _make()
	assert_false(c.acquire(null), "a null radio can't acquire")
	assert_false(c.owns(null), "and never reads as owner")
	c.free()

func test_is_premium_reflects_product() -> void:
	var c = _make()
	assert_false(c.is_premium(), "no product known yet -> not premium")
	c._product = "free"
	assert_false(c.is_premium(), "a free account is not premium")
	c._product = "premium"
	assert_true(c.is_premium(), "a premium account is premium")
	c.free()

func test_store_tokens_sets_access_and_future_expiry() -> void:
	var c = _make()
	var before := Time.get_unix_time_from_system()
	c._store_tokens({"access_token": "tok-abc", "expires_in": 3600})
	assert_eq(c._access_token, "tok-abc", "captures the access token from the response")
	assert_gt(c._token_expiry_unix, before, "and sets the expiry into the future")
	c.free()

func test_store_tokens_defaults_when_fields_missing() -> void:
	var c = _make()
	c._store_tokens({})
	assert_eq(c._access_token, "", "a response with no access_token leaves it empty, not crashing")
	c.free()

func test_unlinked_session_never_needs_refresh() -> void:
	# With no linked account (no refresh token on file), the controller must never schedule a refresh — even
	# with an empty access token — so it can't fire a pointless/erroring refresh on boot. Force UNLINKED by
	# clearing the refresh token for the test, regardless of a real token persisted in the env's settings.cfg
	# (a playtest link writes one). Set the var directly (not the persisting setter) and restore.
	var prev_token := Settings.spotify_refresh_token
	Settings.spotify_refresh_token = ""
	var c = _make()
	assert_false(c._needs_refresh(), "an unlinked controller never thinks a refresh is due")
	Settings.spotify_refresh_token = prev_token
	c.free()

func test_parse_now_playing_extracts_title_and_first_artist() -> void:
	var c = _make()
	var np = c._parse_now_playing({"item": {"name": "Song A", "artists": [{"name": "Artist X"}, {"name": "Artist Y"}]}})
	assert_eq(np["title"], "Song A", "pulls the track name")
	assert_eq(np["artist"], "Artist X", "uses the first artist")
	c.free()

func test_parse_now_playing_handles_missing_item() -> void:
	var c = _make()
	var np = c._parse_now_playing({})
	assert_eq(np["title"], "", "no item -> empty, no crash")
	assert_eq(np["artist"], "")
	c.free()

func test_parse_now_playing_handles_no_artists() -> void:
	var c = _make()
	var np = c._parse_now_playing({"item": {"name": "Solo"}})
	assert_eq(np["title"], "Solo")
	assert_eq(np["artist"], "", "no artists array -> empty artist, not a crash")
	c.free()


# --- _play_body: a single TRACK plays via "uris"; a playlist/album/artist via "context_uri" ---

func test_play_body_track_uses_uris_not_context() -> void:
	var c = _make()
	var parsed: Dictionary = JSON.parse_string(c._play_body("spotify:track:7ccI9cStQbQdystvc6TvxD"))
	assert_true(parsed.has("uris"), "a TRACK uri must go in 'uris' — Spotify rejects a track as a context_uri (silent no-play)")
	assert_false(parsed.has("context_uri"), "a track must NOT be sent as context_uri")
	assert_eq(parsed["uris"][0], "spotify:track:7ccI9cStQbQdystvc6TvxD", "the track is the single item in 'uris'")
	c.free()

func test_play_body_context_uri_for_playlist_album_artist() -> void:
	var c = _make()
	for ctx in ["spotify:playlist:37i9dQZF1DXcBWIGoYBM5M", "spotify:album:1DFixLWuPkv3KT3TnV35m3", "spotify:artist:4Z8W4fKeB5YxbusRsdQVPb"]:
		var parsed: Dictionary = JSON.parse_string(c._play_body(ctx))
		assert_eq(parsed.get("context_uri", ""), ctx, "a playlist/album/artist plays as a context_uri: %s" % ctx)
		assert_false(parsed.has("uris"), "a context uri must NOT use 'uris'")
	c.free()

func test_repeat_state_track_loops_itself_else_context() -> void:
	var c = _make()
	assert_eq(c._repeat_state_for("spotify:track:7ccI9cStQbQdystvc6TvxD"), "track", "a single track loops itself (repeat=track)")
	assert_eq(c._repeat_state_for("spotify:playlist:37i9dQZF1DXcBWIGoYBM5M"), "context", "a playlist loops the whole context in order")
	assert_eq(c._repeat_state_for("spotify:album:1DFixLWuPkv3KT3TnV35m3"), "context", "an album loops the whole context")
	c.free()
