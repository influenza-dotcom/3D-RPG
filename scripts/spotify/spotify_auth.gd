class_name SpotifyAuth
extends RefCounted

## Pure, network-free OAuth helpers for the optional Spotify radio — PKCE derivation, the authorize/redirect
## URL building, the token request bodies, the redirect-callback parse, and the access-token refresh-timing
## decision. NO HTTPRequest, NO TCPServer, NO Node — so the whole auth core is unit-testable headless.
## SpotifyController (the autoload, next milestone) owns the live I/O and merely drives these helpers; keeping
## the logic here means the fiddly, error-prone, can't-run-in-tests crypto/encoding is pinned by GUT against
## known vectors (RFC 7636) instead of being discovered broken at runtime.
##
## PKCE (RFC 7636) is mandatory for a native desktop client: the verifier proves possession of the auth
## request without a client SECRET, so nothing secret ships in the binary (only the public client_id does).

const AUTHORIZE_URL := "https://accounts.spotify.com/authorize"
const TOKEN_URL := "https://accounts.spotify.com/api/token"

## A high-entropy PKCE code_verifier (RFC 7636 §4.1: 43–128 unreserved chars). base64url of 64 random bytes
## is ~86 chars, comfortably in range. Uses the Crypto RNG (available in exported templates).
func make_verifier() -> String:
	var crypto := Crypto.new()
	return _base64url(crypto.generate_random_bytes(64))

## The S256 code_challenge for a verifier: base64url(sha256(ascii(verifier))) (RFC 7636 §4.2). Deterministic,
## so it's pinned in tests against the RFC reference vector.
func challenge_for(verifier: String) -> String:
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	ctx.update(verifier.to_utf8_buffer())
	return _base64url(ctx.finish())

## The loopback redirect URI for a bound port. MUST be the IP literal 127.0.0.1 (the always-accepted loopback
## form — Spotify deprecated the bare "localhost" alias), and plain http IS allowed on a loopback IP, so no
## TLS is needed. NOTE: this exact string — INCLUDING the trailing slash — must be registered byte-for-byte as
## a Redirect URI in your Spotify app dashboard, or the /authorize call is rejected.
func redirect_uri_for(port: int) -> String:
	return "http://127.0.0.1:%d/" % port

## The full /authorize URL the system browser opens (response_type=code + S256 PKCE).
func authorize_url(client_id: String, redirect_uri: String, scopes: String, challenge: String, state: String) -> String:
	var params := {
		"client_id": client_id,
		"response_type": "code",
		"redirect_uri": redirect_uri,
		"scope": scopes,
		"code_challenge_method": "S256",
		"code_challenge": challenge,
		"state": state,
	}
	return "%s?%s" % [AUTHORIZE_URL, _query_string(params)]

## x-www-form-urlencoded body to EXCHANGE an auth code for tokens (grant_type=authorization_code + PKCE verifier).
func token_exchange_body(client_id: String, code: String, verifier: String, redirect_uri: String) -> String:
	return _query_string({
		"grant_type": "authorization_code",
		"code": code,
		"redirect_uri": redirect_uri,
		"client_id": client_id,
		"code_verifier": verifier,
	})

## x-www-form-urlencoded body to REFRESH an access token from a stored refresh token.
func token_refresh_body(client_id: String, refresh_token: String) -> String:
	return _query_string({
		"grant_type": "refresh_token",
		"refresh_token": refresh_token,
		"client_id": client_id,
	})

## Parse the browser's redirect GET request line ("GET /?code=…&state=… HTTP/1.1") into {code, state, error}.
## Fields are empty when absent — the caller validates `state` and bails on a non-empty `error`.
func parse_redirect_request(request_line: String) -> Dictionary:
	var out := {"code": "", "state": "", "error": ""}
	var parts := request_line.split(" ", false)
	if parts.size() < 2:
		return out
	var path: String = parts[1]
	var qpos := path.find("?")
	if qpos < 0:
		return out
	for pair in path.substr(qpos + 1).split("&", false):
		var eq := pair.find("=")
		if eq < 0:
			continue
		var key := pair.substr(0, eq)
		var val := pair.substr(eq + 1).uri_decode()
		if out.has(key):
			out[key] = val
	return out

## True when an access token expiring at `expiry_unix` should be refreshed `margin_s` early at time `now_unix`.
func should_refresh(now_unix: float, expiry_unix: float, margin_s: float) -> bool:
	return now_unix >= expiry_unix - margin_s

func _query_string(params: Dictionary) -> String:
	var parts: PackedStringArray = []
	for k in params:
		parts.append("%s=%s" % [String(k).uri_encode(), String(params[k]).uri_encode()])
	return "&".join(parts)

## base64url (RFC 4648 §5) of raw bytes: standard base64, then +/ -> -_ and strip the = padding.
func _base64url(data: PackedByteArray) -> String:
	return Marshalls.raw_to_base64(data).replace("+", "-").replace("/", "_").rstrip("=")
