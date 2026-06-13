class_name NowPlayingHud
extends Label

## Drop-in HUD readout for the optional Spotify radio: shows "♪ Title — Artist" while the linked Spotify is
## playing, and hides when nothing is. Drop it into your HUD scene and position/anchor it; it wires itself to
## SpotifyController.now_playing_changed in _ready. Purely cosmetic — the radio works without it, and it stays
## blank/hidden unless a linked-Spotify radio is the active source.

## Prefix shown before the track (e.g. a note glyph).
@export var prefix: String = "♪ "

func _ready() -> void:
	visible = false
	if not SpotifyController.now_playing_changed.is_connected(_on_now_playing):
		SpotifyController.now_playing_changed.connect(_on_now_playing)

func _on_now_playing(title: String, artist: String) -> void:
	text = format_line(prefix, title, artist)
	visible = not text.is_empty()

## Format a now-playing line: "<prefix><title> — <artist>" (title only when there's no artist; "" when there's
## no title, which hides the readout). Pure — shared by _on_now_playing and the tests.
static func format_line(prefix_str: String, title: String, artist: String) -> String:
	if title.is_empty():
		return ""
	if artist.is_empty():
		return prefix_str + title
	return "%s%s — %s" % [prefix_str, title, artist]
