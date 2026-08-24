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

## The DIEGETIC-SPEAKER bus: the tinny high-pass + lo-fi crunch + low-pass chain every self-serve station's panel
## speaker plays through (StationSpeaker.bus). Two things are pinned, and both are the same failure the scan above
## guards in its authored form — a sound that escapes the volume sliders:
##  * it EXISTS. StationSpeaker falls back to `sfx` with a warning if it doesn't, so a deleted bus degrades to a clean
##    full-range chirp rather than silence — you would hear a wrong sound, not a missing one, which is exactly
##    the kind of drift a test should catch instead of a playtest.
##  * it SENDS INTO `sfx`, not Master. That is what keeps it under the SFX volume slider and inside the death
##    cinematic's world duck (death_mix.gd ducks the four world buses; a child bus inherits its parent's
##    volume). Re-pointing it at Master in the editor's Audio panel would silently undo both.
func test_the_speaker_bus_exists_and_routes_through_sfx() -> void:
	var idx := AudioServer.get_bus_index(&"speaker")
	assert_gte(idx, 0,
		"the `speaker` bus is missing from default_bus_layout.tres — the Atm's panel speaker loses its tinny "
		+ "treatment and falls back to a clean `sfx` chirp")
	if idx < 0:
		return
	assert_eq(AudioServer.get_bus_send(idx), &"sfx",
		"the `speaker` bus must send into `sfx` so the SFX volume slider and the death-cinematic duck both "
		+ "still reach it — sending it to Master escapes every slider")
	assert_gt(AudioServer.get_bus_effect_count(idx), 0,
		"the `speaker` bus with no effects IS a clean bus — the filters are the whole point of it existing")


## The STATION-RADIO bus — `speaker`'s twin, and the pair has to stay a pair.
## `station_music` carries a byte-identical clone of the chirp's filter chain, because the whole brief was
## "the shop music sounds like it comes out of the same crappy panel speaker the ATM chirps from". What it
## does NOT clone is the SEND: it goes into `music`, not `sfx`.
##  * the SEND is the deliberate divergence. A 50-90 second loop is MUSIC by every definition the Options menu
##    uses, so the Music slider must govern it — a player who drags Music to 0 to run their own playlist must
##    not still be hearing shop themes, and one who drags Effects to 0 to quiet gunfire must not lose them.
##    Sending into `music` also inherits the dialogue duck, the ADS duck and the death-cinematic world duck
##    for free; sending to Master would escape all four.
##  * the CHAIN is the thing that must NOT diverge, and a hand-copied chain is exactly what drifts silently:
##    somebody retunes the chirp's low-pass in the editor's Audio panel and the shop radio quietly stops
##    matching it. Nothing audible fails, so only a pairwise assert catches it. Gain is deliberately NOT
##    compared — `speaker` is +4 dB into an `sfx` bus that is ~6.6 dB down, so equal gain would be unequal
##    loudness.
func test_the_station_music_bus_clones_the_speaker_chain_but_routes_through_music() -> void:
	var idx := AudioServer.get_bus_index(&"station_music")
	assert_gte(idx, 0,
		"the `station_music` bus is missing from default_bus_layout.tres — the station radio falls back to a "
		+ "clean `music` bed and loses the tinny panel-speaker character that is the whole feature")
	var spk := AudioServer.get_bus_index(&"speaker")
	if idx < 0 or spk < 0:
		return
	assert_eq(AudioServer.get_bus_send(idx), &"music",
		"the `station_music` bus must send into `music` so the MUSIC volume slider governs it — sending it "
		+ "into `sfx` files a music bed under the Effects slider, and Master escapes every slider")
	assert_eq(AudioServer.get_bus_effect_count(idx), AudioServer.get_bus_effect_count(spk),
		"`station_music` must carry the same NUMBER of effects as `speaker` — the two chains are a matched "
		+ "pair and a dropped stage is inaudible until someone A/Bs them")
	for i in mini(AudioServer.get_bus_effect_count(idx), AudioServer.get_bus_effect_count(spk)):
		var a := AudioServer.get_bus_effect(spk, i)
		var b := AudioServer.get_bus_effect(idx, i)
		assert_eq(b.get_class(), a.get_class(),
			"`station_music` effect %d is a %s but `speaker`'s is a %s — the chains have drifted apart"
			% [i, b.get_class(), a.get_class()])
		# Duck-typed rather than branched on class: each stage only carries one of these parameter sets, and
		# a null on both sides simply compares equal, so this covers filters and the distortion in one loop.
		for prop in [&"cutoff_hz", &"resonance", &"mode", &"drive"]:
			assert_eq(b.get(prop), a.get(prop),
				"`station_music` effect %d (%s) has %s = %s but `speaker` has %s — retune BOTH buses or the "
				% [i, a.get_class(), prop, str(b.get(prop)), str(a.get(prop))]
				+ "shop radio stops sounding like the machine that just chirped at you")


## The ROOF-DUCK bus. `IndoorAmbienceDucker` muffles the outdoor bed by sweeping a low-pass on `ambient_bed`,
## and a low-pass is a per-BUS effect — so that bus is the duck's blast radius. Two things keep it honest, and
## both are one-line edits in the editor's Audio panel away from silently going wrong:
##  * `ambient_bed` SENDS INTO `ambient` (not the reverse, and not straight to Master). Because audio flows
##    child -> parent, that routing is exactly what confines the muffle to the bed: everything authored on
##    `ambient` itself — a light fixture's electrical buzz, a machine hum, the player's fall-wind — is
##    UPSTREAM of the filter and cannot be dulled by it. Flip the send and the roof duck would start muffling
##    every local sound in the world, which is precisely the "why does the buzzing light sound like it's
##    outside" complaint this pins against.
##  * it still CARRIES a low-pass. Without one the muffle silently degrades to a pure volume duck (the ducker
##    no-ops rather than erroring), so "the indoors treatment stopped working" would only show up in a playtest.
func test_the_roof_ducks_muffle_bus_cannot_reach_local_sounds() -> void:
	var bed := AudioServer.get_bus_index(&"ambient_bed")
	assert_gte(bed, 0, "the `ambient_bed` bus is missing — IndoorAmbienceDucker's muffle has nothing to sweep")
	if bed < 0:
		return
	assert_eq(AudioServer.get_bus_send(bed), &"ambient",
		"`ambient_bed` must send INTO `ambient`. That direction is what scopes the roof duck's low-pass to the "
		+ "outdoor bed and keeps every `ambient`-bus local sound (light buzz, machine hum) out of it")
	var has_lowpass := false
	for i in AudioServer.get_bus_effect_count(bed):
		has_lowpass = has_lowpass or AudioServer.get_bus_effect(bed, i) is AudioEffectLowPassFilter
	assert_true(has_lowpass,
		"`ambient_bed` has no AudioEffectLowPassFilter — IndoorAmbienceDucker silently degrades to a volume-only "
		+ "duck and the 'stepped indoors' muffle just stops happening")

## The other half of that contract, from the emitter side: a light fixture's hum is a LOCAL sound and must stay
## off the muffled bus. If someone re-routes `Light.tscn`'s emitter to `ambient_bed` it would start ducking and
## muffling whenever the player walks under a roof — i.e. the buzz of the strip light you are standing beneath
## would go dull the moment you step inside, which is backwards.
func test_the_light_fixture_buzz_stays_off_the_muffled_bus() -> void:
	var src := FileAccess.get_file_as_string("res://scenes/levels/Light.tscn")
	assert_ne(src, "", "scenes/levels/Light.tscn is unreadable — the fixture prefab moved or was renamed")
	assert_true(src.contains('bus = &"ambient"'),
		"Light.tscn's LightBuzz must play on the plain `ambient` bus")
	assert_false(src.contains('bus = &"ambient_bed"'),
		"Light.tscn's LightBuzz is on `ambient_bed`, the bus IndoorAmbienceDucker muffles under a roof — a "
		+ "fixture you are standing next to indoors would lose its high end exactly when it should be clearest. "
		+ "Keep fixture-local sound on `ambient`; `ambient_bed` is for the outdoor bed only")

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
