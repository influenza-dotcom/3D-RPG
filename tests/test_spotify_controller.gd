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
	# with an empty access token — so it can't fire a pointless/erroring refresh on boot.
	var c = _make()
	assert_false(c._needs_refresh(), "an unlinked controller never thinks a refresh is due")
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
