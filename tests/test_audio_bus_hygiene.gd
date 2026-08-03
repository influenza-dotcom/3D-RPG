extends GutTest

## Ratchet test for the scene-authoring half of the long-standing audio @risk documented on
## managers/AudioManager.gd: "A sound spawned bare (not via play_sfx) lands on Master and silently ignores
## the SFX volume slider — no error."
##
## The code half is already safe (every AudioStreamPlayer*.new() site assigns a bus). This pins the SCENE
## half: an authored player with no `bus =` line lands on Master, where it escapes every Options volume
## slider — and, since the death cinematic moved its duck off Master and onto the world buses
## (scripts/player/death_mix.gd), such a sound now also plays at FULL VOLUME under the death card while
## everything else has drained away. That second symptom is what turns an old cosmetic bug into a loud one.
##
## Pure text scan over the .tscn files — no scene is instantiated, so no audio device or _ready() runs.

const SCAN_DIRS: Array[String] = ["res://scenes", "res://maps", "res://resources"]
## Vendor demo scenes are never instanced by the game and are not ours to re-author.
const SKIP_DIRS: Array[String] = ["res://addons"]

func _collect_scenes(dir_path: String, out: Array[String]) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return
	for skip in SKIP_DIRS:
		if dir_path.begins_with(skip):
			return
	dir.list_dir_begin()
	var name := dir.get_next()
	while name != "":
		var full := dir_path.path_join(name)
		if dir.current_is_dir():
			if not name.begins_with("."):
				_collect_scenes(full, out)
		elif name.ends_with(".tscn"):
			out.append(full)
		name = dir.get_next()
	dir.list_dir_end()

## Every authored AudioStreamPlayer / 2D / 3D whose node block carries no `bus = ` line, as "path:NodeName".
func _bus_less_players() -> Array[String]:
	var scenes: Array[String] = []
	for d in SCAN_DIRS:
		_collect_scenes(d, scenes)
	var offenders: Array[String] = []
	for path in scenes:
		var src := FileAccess.get_file_as_string(path)
		if src == "":
			continue
		# Split on node headers; each chunk is one node's property block, ending at the next `[` section.
		var chunks := src.split("\n[node ")
		for i in range(1, chunks.size()):
			var chunk: String = chunks[i]
			var header: String = chunk.get_slice("\n", 0)
			if not (header.contains('type="AudioStreamPlayer"')
					or header.contains('type="AudioStreamPlayer2D"')
					or header.contains('type="AudioStreamPlayer3D"')):
				continue
			# Properties run until the next section header (a line starting with "[").
			var body: String = chunk.get_slice("\n[", 0)
			if body.contains("bus = "):
				continue
			var node_name: String = header.get_slice('name="', 1).get_slice('"', 0)
			offenders.append("%s:%s" % [path, node_name])
	return offenders

func test_every_authored_audio_player_declares_a_bus() -> void:
	var offenders := _bus_less_players()
	assert_eq(offenders.size(), 0,
		("These authored AudioStreamPlayers have no `bus = ` line, so they play on Master: they ignore every "
		+ "Options volume slider AND stay at full volume through the death cinematic, which ducks the world "
		+ "buses rather than Master. Set a bus in the Inspector (ambient / sfx / music / voice / radio). "
		+ "Offenders: %s") % ", ".join(offenders))

func test_the_scan_actually_finds_audio_players() -> void:
	# Guard against the scan silently matching nothing (a .tscn format change would make the test above pass
	# vacuously forever). The project authors dozens of players; assert we can see a healthy number.
	var scenes: Array[String] = []
	for d in SCAN_DIRS:
		_collect_scenes(d, scenes)
	var seen := 0
	for path in scenes:
		var src := FileAccess.get_file_as_string(path)
		seen += src.count('type="AudioStreamPlayer')
	assert_gt(seen, 10, "the .tscn scan found almost no AudioStreamPlayers — the scan itself is broken, not the scenes")
