extends GutTest

## SpotifyAuth — the pure OAuth/PKCE logic (no network). Pinned against the RFC 7636 reference vector and
## Spotify's URL/param shapes. RefCounted -> .new() off-tree, release with = null.

const SPOTIFY_AUTH := "res://scripts/spotify/spotify_auth.gd"

func _make() -> SpotifyAuth:
	return load(SPOTIFY_AUTH).new()

func test_pkce_challenge_matches_rfc7636_vector() -> void:
	# RFC 7636 Appendix B canonical example: verifier -> S256 challenge.
	var a := _make()
	var verifier := "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk"
	assert_eq(a.challenge_for(verifier), "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM",
		"S256 challenge must equal the RFC 7636 reference vector")
	a = null

func test_challenge_is_base64url_without_padding() -> void:
	var a := _make()
	var c := a.challenge_for("any-verifier-string")
	assert_false(c.contains("+"), "base64url uses - not +")
	assert_false(c.contains("/"), "base64url uses _ not /")
	assert_false(c.contains("="), "no padding in base64url")
	a = null

func test_verifier_length_in_pkce_range() -> void:
	var a := _make()
	assert_between(a.make_verifier().length(), 43, 128, "RFC 7636 requires a 43–128 char verifier")
	a = null

func test_two_verifiers_differ() -> void:
	var a := _make()
	assert_ne(a.make_verifier(), a.make_verifier(), "each verifier is freshly random")
	a = null

func test_redirect_uri_is_loopback_ip_not_localhost() -> void:
	var a := _make()
	var uri := a.redirect_uri_for(8888)
	assert_eq(uri, "http://127.0.0.1:8888/", "must use the 127.0.0.1 loopback IP (Spotify dropped localhost)")
	assert_false(uri.contains("localhost"), "localhost is no longer accepted by Spotify")
	a = null

func test_authorize_url_carries_pkce_and_params() -> void:
	var a := _make()
	var url := a.authorize_url("CID", "http://127.0.0.1:8888/", "scope-a scope-b", "CHAL", "STATE")
	assert_true(url.begins_with("https://accounts.spotify.com/authorize?"), "hits the authorize endpoint")
	assert_true(url.contains("client_id=CID"), "carries the client id")
	assert_true(url.contains("response_type=code"), "auth-code flow")
	assert_true(url.contains("code_challenge_method=S256"), "S256 PKCE method")
	assert_true(url.contains("code_challenge=CHAL"), "carries the challenge")
	assert_true(url.contains("state=STATE"), "carries the CSRF state")
	assert_true(url.contains("scope-a%20scope-b"), "scopes are url-encoded (space -> %20)")
	a = null

func test_token_exchange_body_fields() -> void:
	var a := _make()
	var body := a.token_exchange_body("CID", "CODE", "VERIFIER", "http://127.0.0.1:8888/")
	assert_true(body.contains("grant_type=authorization_code"), "auth-code grant")
	assert_true(body.contains("code=CODE"), "carries the code")
	assert_true(body.contains("code_verifier=VERIFIER"), "PKCE verifier proves possession — no client secret")
	assert_true(body.contains("client_id=CID"))
	assert_true(body.contains("redirect_uri="), "the auth-code grant requires the redirect_uri")
	a = null

func test_token_refresh_body_fields() -> void:
	var a := _make()
	var body := a.token_refresh_body("CID", "REFRESH")
	assert_true(body.contains("grant_type=refresh_token"), "refresh grant")
	assert_true(body.contains("refresh_token=REFRESH"))
	assert_true(body.contains("client_id=CID"))
	a = null

func test_parse_redirect_extracts_code_and_state() -> void:
	var a := _make()
	var out := a.parse_redirect_request("GET /?code=AQB123&state=xyz HTTP/1.1")
	assert_eq(out["code"], "AQB123", "pulls the auth code")
	assert_eq(out["state"], "xyz", "pulls the CSRF state to validate")
	assert_eq(out["error"], "", "no error on a success redirect")
	a = null

func test_parse_redirect_surfaces_error() -> void:
	var a := _make()
	var out := a.parse_redirect_request("GET /?error=access_denied&state=xyz HTTP/1.1")
	assert_eq(out["error"], "access_denied", "a denied consent surfaces the error")
	assert_eq(out["code"], "", "and carries no code")
	a = null

func test_parse_redirect_url_decodes_values() -> void:
	var a := _make()
	var out := a.parse_redirect_request("GET /?code=a%2Fb%2Bc&state=s HTTP/1.1")
	assert_eq(out["code"], "a/b+c", "a percent-encoded code is decoded")
	a = null

func test_parse_redirect_handles_no_query() -> void:
	var a := _make()
	var out := a.parse_redirect_request("GET / HTTP/1.1")
	assert_eq(out["code"], "", "a bare request yields empty fields, not a crash")
	a = null

func test_should_refresh_boundary() -> void:
	var a := _make()
	assert_false(a.should_refresh(0.0, 3600.0, 60.0), "fresh token: no refresh")
	assert_true(a.should_refresh(3540.0, 3600.0, 60.0), "exactly at the margin boundary: refresh")
	assert_true(a.should_refresh(3600.0, 3600.0, 60.0), "past expiry: refresh")
	assert_false(a.should_refresh(3539.0, 3600.0, 60.0), "just before the margin: not yet")
	a = null
