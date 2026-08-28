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
		+ "buses rather than Master. Set a bus in the Inspector — `world` for anything the game world "
		+ "physically makes (it carries the indoor room echo), `sfx` for non-world cues, or ambient / music / "
		+ "voice / radio. Offenders: %s") % ", ".join(offenders))

## The DIEGETIC-SPEAKER bus: the tinny high-pass + lo-fi crunch + low-pass chain every self-serve station's panel
## speaker plays through (StationSpeaker.bus). Two things are pinned, and both are the same failure the scan above
## guards in its authored form — a sound that escapes the volume sliders:
##  * it EXISTS. StationSpeaker falls back to `sfx` with a warning if it doesn't, so a deleted bus degrades to a clean
##    full-range chirp rather than silence — you would hear a wrong sound, not a missing one, which is exactly
##    the kind of drift a test should catch instead of a playtest.
##  * it SENDS INTO `world` (the diegetic trunk, which sends into `sfx`), not Master. That routing is what
##    keeps it under the SFX volume slider and inside the death cinematic's world duck (death_mix.gd ducks the
##    world buses; a child bus inherits its parent's volume) — and what gives the panel chirp the indoor room
##    echo, since a speaker is a physical object. Re-pointing it at Master in the Audio panel undoes all three.
func test_the_speaker_bus_exists_and_routes_through_sfx() -> void:
	var idx := AudioServer.get_bus_index(&"speaker")
	assert_gte(idx, 0,
		"the `speaker` bus is missing from default_bus_layout.tres — the Atm's panel speaker loses its tinny "
		+ "treatment and falls back to a clean `sfx` chirp")
	if idx < 0:
		return
	assert_eq(AudioServer.get_bus_send(idx), &"world",
		"the `speaker` bus must send into `world` — a panel speaker is a physical object, so its chirp takes "
		+ "the indoor room echo like every world sound, and `world` sends into `sfx`, which keeps the SFX "
		+ "volume slider and the death-cinematic duck reaching it transitively. Master escapes every slider")
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

## The GUNSHOT-ECHO bus: the delay + reverb chain every weapon's fire sound plays through. Same two silent
## failure modes the `speaker` test pins:
##  * it EXISTS. weapon.tscn's `Attack Audio` names it, and an AudioStreamPlayer3D whose bus name doesn't
##    resolve falls back to Master — every fire sound (player AND NPC, they share the prefab) would escape
##    the Effects slider and play at full volume through the death cinematic's world duck.
##  * it SENDS INTO `world` (the diegetic bus, which sends into `sfx`) — the Effects slider, the death duck
##    and the `sfx` Distortion crunch all still reach gunfire transitively, and a billow tail that is still
##    ringing when you duck through a door picks up the indoor room like every other world sound.
##  * it CARRIES the delay (the discrete echo repeats) AND the reverb (the tail). A bare bus is a clean
##    bus — the echo would stop being a feature without anything erroring.
func test_the_gunshots_bus_exists_routes_through_world_and_echoes() -> void:
	var idx := AudioServer.get_bus_index(&"gunshots")
	assert_gte(idx, 0,
		"the `gunshots` bus is missing from default_bus_layout.tres — weapon.tscn's `Attack Audio` names it, "
		+ "so every fire sound lands on Master and escapes the Effects slider + the death-cinematic duck")
	if idx < 0:
		return
	assert_eq(AudioServer.get_bus_send(idx), &"world",
		"the `gunshots` billow bus must send into `world` (which sends into `sfx`) so the Effects slider and "
		+ "the death-cinematic duck still reach gunfire — Master escapes both, and `sfx` directly would skip "
		+ "the indoor room a lingering billow tail should pick up when you step inside")
	var has_delay := false
	var has_reverb := false
	for i in AudioServer.get_bus_effect_count(idx):
		var fx := AudioServer.get_bus_effect(idx, i)
		has_delay = has_delay or fx is AudioEffectDelay
		has_reverb = has_reverb or fx is AudioEffectReverb
	assert_true(has_delay and has_reverb,
		"the `gunshots` bus must carry an AudioEffectDelay (the discrete echo repeats) and an "
		+ "AudioEffectReverb (the tail) — retuning them in the Audio panel is fine, deleting them is not")

## The emitter side of that contract: the weapon prefab's fire-sound player is the ONE node routed through
## the billow bus. The other five players (impacts, shell tink, reload, dry-fire) ride `world` with the rest
## of the diegetic foley — the BILLOW is a gunSHOT treatment, while the indoor room (the `world` chain) is a
## whole-world treatment. The authored `gunshots` here is only the outdoor-GUN default: the node is shared by
## every weapon's trigger sound, so WeaponAudio.fire_bus_for re-picks the bus per play (next test).
func test_the_weapon_fire_sound_plays_on_the_gunshots_bus() -> void:
	var src := FileAccess.get_file_as_string("res://scenes/weapons/weapon.tscn")
	assert_ne(src, "", "scenes/weapons/weapon.tscn is unreadable — the weapon prefab moved or was renamed")
	var chunk := src.get_slice('name="Attack Audio"', 1).get_slice("\n[", 0)
	assert_true(chunk.contains('bus = &"gunshots"'),
		"weapon.tscn's `Attack Audio` (the fire sound — player and NPC gunfire alike) must play on the "
		+ "`gunshots` echo bus: on plain `sfx` the shot loses its echo, and with no bus line it lands on Master")

## The per-weapon half of the routing: ONE shared `Attack Audio` node carries every weapon's trigger sound,
## so the bus is re-picked per play by WeaponAudio.fire_bus_for. Only an outdoor GUN gets the city billow;
## everything else is a world ACTION on the `world` bus — clean under open sky, the tight indoor room under
## a roof, exactly like a footstep. "why the FUCK does the fists echo" (the fists billowing across the map)
## was a real shipped bug: the node kept whatever bus it was authored with, for every weapon.
func test_fire_bus_gives_only_outdoor_guns_the_billow() -> void:
	var gun := WeaponData.new()
	assert_eq(WeaponAudio.fire_bus_for(gun), &"gunshots",
		"a ranged weapon fired under open sky must route to the `gunshots` city-billow bus")
	assert_eq(WeaponAudio.fire_bus_for(gun, true), &"world",
		"a gun fired while the listener is under a roof (Player.is_indoors, the IndoorAmbienceDucker seam) "
		+ "must skip the billow and ride `world`, whose indoor room chain the ducker has switched on")
	var fists := WeaponData.new()
	fists.is_melee = true
	assert_eq(WeaponAudio.fire_bus_for(fists), &"world",
		"a melee swing whoosh is a world ACTION, never a gunshot — it rides `world` (clean outdoors, the "
		+ "same indoor room as a footstep under a roof), and must never get the city billow")
	assert_eq(WeaponAudio.fire_bus_for(fists, true), &"world",
		"a melee swing whoosh indoors stays on `world` — the room it gets there is the ducker's world-chain "
		+ "toggle, identical to every other action sound, not a gun treatment")
	var spray := WeaponData.new()
	spray.is_spray_paint = true
	assert_eq(WeaponAudio.fire_bus_for(spray), &"world",
		"the spray can's hiss is a world action — `world`, never the `gunshots` billow")
	assert_eq(WeaponAudio.fire_bus_for(spray, true), &"world",
		"the spray can's hiss indoors stays on `world`, taking the same room as a footstep")
	gun = null
	fists = null
	spray = null

## The WORLD bus — the diegetic trunk every world sound rides (footsteps, weapon foley, doors, impacts, gore,
## the echo-bus sends), and the home of the indoor ROOM ECHO:
##  * it EXISTS and SENDS INTO `sfx` — that routing is what keeps the whole world mix under the Effects
##    slider, inside the death-cinematic duck, and running through the `sfx` Distortion crunch, while UI
##    cues / stings / jingles on plain `sfx` never pass through it (they must never take room reverb).
##  * it CARRIES the indoor chain — an AudioEffectDelay (the tight wall slap) and an AudioEffectReverb (the
##    small bright room) — authored DISABLED: the resting state IS outdoors. IndoorAmbienceDucker switches
##    them on under a roof and back off under sky, and restores OFF in _exit_tree, so a bare scene with no
##    ducker plays the authored dry mix. Values are free to retune in the Audio panel; the class pair is not.
func test_the_world_bus_carries_the_disabled_indoor_room_chain() -> void:
	var idx := AudioServer.get_bus_index(&"world")
	assert_gte(idx, 0,
		"the `world` bus is missing from default_bus_layout.tres — every diegetic emitter names it, so the "
		+ "whole world mix lands on Master, escaping the Effects slider and the death-cinematic duck")
	if idx < 0:
		return
	assert_eq(AudioServer.get_bus_send(idx), &"sfx",
		"the `world` bus must send into `sfx` so the Effects slider / death duck / Distortion crunch still "
		+ "govern the whole diegetic mix — Master escapes all three")
	var delay_i := -1
	var reverb_i := -1
	for i in AudioServer.get_bus_effect_count(idx):
		var fx := AudioServer.get_bus_effect(idx, i)
		if fx is AudioEffectDelay:
			delay_i = i
		elif fx is AudioEffectReverb:
			reverb_i = i
	assert_true(delay_i >= 0 and reverb_i >= 0,
		"the `world` bus must carry an AudioEffectDelay + AudioEffectReverb (the indoor room chain the "
		+ "IndoorAmbienceDucker switches on under a roof) — without them 'indoors sounds indoor' silently dies")
	if delay_i >= 0 and reverb_i >= 0:
		assert_false(AudioServer.is_bus_effect_enabled(idx, delay_i) or AudioServer.is_bus_effect_enabled(idx, reverb_i),
			"the `world` indoor chain must be authored DISABLED — outdoors is the resting state, and a scene "
			+ "with no IndoorAmbienceDucker must play the dry mix. If this fails, the .tres was saved with the "
			+ "chain stuck on (e.g. from the editor's Audio panel while testing indoors)")

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
