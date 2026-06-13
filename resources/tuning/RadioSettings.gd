class_name RadioSettings
extends Resource

## Global config for the OPTIONAL in-world Spotify radio — the network/OAuth layer, on one inspector page
## (resources/tuning/RadioSettings.tres), read as GameSettings.radio.<field>. The PER-RADIO feel (duck/settle
## timings, fallback track, name) stays on the Radio component's own @exports; this resource holds only what
## is inherently GLOBAL: the Spotify app credentials + the OAuth/refresh parameters the SpotifyController reads.
##
## client_id is the PUBLIC half of a Spotify Developer app — it ships in the export, which is fine for the PKCE
## flow (there is no client SECRET to protect). Leave it BLANK to keep the Spotify path off; radios then play
## only their shipped fallback track. validate() degrades gracefully (push_warning) on a bad config instead of
## letting the OAuth flow fail silently — mirrors MusicDirector's degenerate-config guard.

@export_group("Spotify App")
## The PUBLIC client_id of your Spotify Developer app. Blank = Spotify disabled (radios use their fallback only).
@export var client_id: String = ""
## Space-separated OAuth scopes requested at link time. Defaults cover reading playback + controlling it + a private playlist.
@export var scopes: String = "user-read-playback-state user-read-currently-playing user-modify-playback-state playlist-read-private"

@export_group("Loopback redirect")
## Low end of the local port range tried for the OAuth loopback redirect (http://127.0.0.1:PORT — Spotify allows plain http on a loopback IP).
@export var redirect_port_min: int = 8888
## High end of that port range — the first free port in [min, max] is used, so a busy port doesn't block linking.
@export var redirect_port_max: int = 8899

@export_group("Tokens & polling")
## Refresh the access token this many seconds BEFORE it expires, so an in-flight command never races the expiry.
@export var token_refresh_margin_s: float = 60.0
## Seconds between "now playing" metadata refreshes (kept long — the track name rarely needs sub-minute accuracy).
@export var now_playing_poll_interval: float = 30.0

## True when the config is coherent enough for the OAuth flow to run. Returns false (push_warning'ing the
## reason) on a degenerate config so SpotifyController can degrade to the fallback instead of failing auth
## silently. A BLANK client_id is NOT a warning — it's the supported "Spotify off" state, so it returns false
## quietly.
func validate() -> bool:
	if client_id.is_empty():
		return false  # Spotify intentionally off — not an error
	if scopes.strip_edges().is_empty():
		push_warning("RadioSettings: scopes is blank — the OAuth request needs at least one scope; Spotify radio disabled.")
		return false
	if redirect_port_min > redirect_port_max:
		push_warning("RadioSettings: redirect_port_min (%d) > redirect_port_max (%d) — no valid loopback port; Spotify radio disabled." % [redirect_port_min, redirect_port_max])
		return false
	if redirect_port_min < 1024 or redirect_port_max > 65535:
		push_warning("RadioSettings: redirect ports must be in 1024..65535; Spotify radio disabled.")
		return false
	return true
