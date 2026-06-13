extends GutTest

## NowPlayingHud — the drop-in Spotify now-playing readout. format_line() is pure; _on_now_playing() runs
## off-tree (it only sets Label.text/visible, no _ready / tree needed).

func test_format_line_title_and_artist() -> void:
	assert_eq(NowPlayingHud.format_line("♪ ", "Song", "Artist"), "♪ Song — Artist")

func test_format_line_title_only() -> void:
	assert_eq(NowPlayingHud.format_line("♪ ", "Song", ""), "♪ Song", "no artist -> just the title")

func test_format_line_empty_when_no_title() -> void:
	assert_eq(NowPlayingHud.format_line("♪ ", "", "Artist"), "", "no title -> empty (the readout hides)")

func test_on_now_playing_shows_then_hides() -> void:
	var hud := NowPlayingHud.new()
	hud._on_now_playing("Song", "Artist")
	assert_true(hud.visible, "a track shows the readout")
	assert_true(hud.text.contains("Song"), "and the title is shown")
	hud._on_now_playing("", "")
	assert_false(hud.visible, "nothing playing -> hidden")
	hud.free()
