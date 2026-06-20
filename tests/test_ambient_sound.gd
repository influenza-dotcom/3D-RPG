extends GutTest

## Rank 16 (AmbientSound): a drop-in looping bed that auto-builds a child AudioStreamPlayer3D on the `ambient`
## bus (not Master). Verifies the bus default, the runtime player build, and the stream setter forwarding.

const AmbientSoundScript = preload("res://scripts/components/ambient_sound.gd")

func test_defaults_to_ambient_bus() -> void:
	var amb = AmbientSoundScript.new()
	assert_eq(amb.bus, StringName("ambient"), "routes to the ambient bus, not Master")
	amb.free()

func test_config_warning_without_stream() -> void:
	var amb = AmbientSoundScript.new()
	var w := amb._get_configuration_warnings()
	assert_gt(w.size(), 0, "no stream => a configuration warning")
	amb.free()

func test_creates_player_on_ambient_bus_at_runtime() -> void:
	var amb = AmbientSoundScript.new()
	amb.autoplay = false  # don't auto-play in a headless test
	add_child_autofree(amb)  # not editor hint => _ready builds the player
	assert_not_null(amb._player, "a child AudioStreamPlayer3D is created at runtime")
	assert_eq(amb._player.bus, StringName("ambient"), "the player routes to the ambient bus")
	assert_false(amb.is_playing(), "nothing plays with no stream / autoplay off")

func test_stream_setter_forwards_to_player() -> void:
	var amb = AmbientSoundScript.new()
	amb.autoplay = false
	add_child_autofree(amb)
	var s := AudioStreamWAV.new()
	amb.stream = s
	assert_eq(amb._player.stream, s, "assigning stream forwards to the live player")
