class_name StationSpeaker
extends Node3D

## @system Audio
## @seam chirp(station) is THE open cue for every station screen (shop/heal/level-up/respec/install/chess/atm): the screen calls it at its commit point and feeds the RESULT to ModalMenu.grab_mouse(not chirped), so a machine with a voice REPLACES the generic UI sting instead of doubling it and a mute one still gets the sting. Static, type-agnostic and null-safe, so no screen branches or duck-types.
## @seam applaud(station) is the REWARD cue, same static shape as chirp: the machine claps for you out of its own panel. Its ONE caller today is Atm.deposit on the portion that actually RETIRES DEBT — the same predicate that scores credit standing — so a repayment is celebrated and a plain saving deposit is not. Unlike chirp it does NOT suppress the caller's UI cue: the crisp commit click confirms the press, the applause celebrates the milestone, and they are different layers.
## @seam ensure(station) is the auto-build seam the station components call in _ready (gated on `standalone`); it never replaces an AUTHORED StationSpeaker child, which is what makes a hand-placed one the tuning AND the mute switch.
## @risk A PAUSABLE AudioStreamPlayer3D silences itself on NOTIFICATION_PAUSED ~15 ms in, with no error and nothing logged — a dialogue-hosted station opens under the conversation's pause, so the built players MUST stay PROCESS_MODE_ALWAYS.
## @risk find_speaker matches by TYPE, not name: a station that exported a NodePath or looked for "Speaker" would go silent the first time a designer renamed the node in their own scene.
## @test res://tests/test_station_speaker.gd
##
## Drop-in PANEL SPEAKER — the cheap plastic voice of a self-serve machine. Child one under any station prop
## (or let the station build its own; see `ensure`) and the machine answers you in the WORLD when its screen
## wakes: panned, attenuated, coming out of the panel you are standing at, instead of a 2D blip in your ear.
##
## ⭐THE BUS *IS* THE TINNY SOUND. `speaker` (default_bus_layout.tres) is a high-pass + lo-fi crunch + low-pass
## chain that sends into `sfx` — no bass, no air. Point `bus` at `sfx` instead for a clean, expensive-sounding
## machine. A bus that does not exist falls back to `sfx` with a warning rather than landing on Master, where
## no Options slider (and no death-cinematic duck) would reach it.
##
## TWO CUES, TWO VOICES: the wake-up `chirp` and the `applaud` reward clap. They get SEPARATE
## AudioStreamPlayer3Ds on purpose — one player would mean each cue cut the other mid-clip (play() restarts),
## so re-opening the terminal mid-applause would chop the celebration off. Within one cue that self-cutting is
## still the wanted behaviour (a second repayment restarts the clap rather than stacking a crowd).
##
## SETUP: drag it under the station (Merchant / Healer / LevelUp / RespecStation / ChipInstaller / ChessMatch /
## Atm). Nothing else — the station finds it by TYPE, not by name or an exported path. The stations that ship
## a default kiosk voice build one for themselves at _ready, so authoring one is how you TUNE or SILENCE the
## machine (a `StationSpeaker` with `open_sound` cleared is a deliberately mute terminal).

## The shipped default: the ATM's deposit tone, now the house voice of every self-serve machine.
const DEFAULT_CHIRP := preload("res://assets/audio/sfx/deposit.wav")
## The shipped reward clap. Canned crowd applause, squeezed through the `speaker` bus's forty-cent cone — the
## joke is that the machine is *pleased with you* for paying it back, in the cheapest way a machine can be.
const DEFAULT_APPLAUSE := preload("res://assets/audio/sfx/Applause.mp3")

## The clip the machine plays when its screen wakes up. Clear it for a silent station.
@export var open_sound: AudioStream = DEFAULT_CHIRP
## Loudness in dB (0 = the clip's own level, less whatever the bus's filters strip).
@export var volume_db: float = 0.0
## The clip the machine plays to CONGRATULATE you — today, paying down what you owe at an `Atm`. Clear it for a
## terminal that takes your money without the fanfare. Independent of `open_sound`: a machine can clap and not
## chirp, or the reverse.
@export var applause_sound: AudioStream = DEFAULT_APPLAUSE
## Level trim for the applause alone, so the celebration can sit under (or over) the wake-up chirp without
## re-levelling the clip. Its own knob because the two clips come from different places and rarely match.
@export var applause_volume_db: float = 0.0
## ⭐The tinny filter chain (see the header). `sfx` for a clean machine; a missing bus degrades to `sfx`.
@export var bus: StringName = &"speaker"
## How far (m) the sound carries. A panel speaker is not a PA — keep it short so it stays the machine's voice.
@export var max_distance: float = 10.0
## Distance falloff (AudioStreamPlayer3D.unit_size) — smaller drops off faster.
@export var unit_size: float = 4.0

## The wake-up chirp's voice. ⭐Its node name "Player" is PINNED by tests/test_station_speaker.gd.
var _player: AudioStreamPlayer3D = null
## The reward clap's own voice — see the header on why the two cues never share one.
var _applause_player: AudioStreamPlayer3D = null


## Build the actual players at _ready — NOT lazily at the first cue — so the listener is already resolved and
## nothing has to warm up in the frame a screen opens.
func _ready() -> void:
	# Resolve the bus ONCE and hand it to both voices: _resolved_bus() push_warning()s on a missing bus, and
	# calling it per voice would print the same authoring mistake twice for one speaker.
	var routed := _resolved_bus()
	_player = _build_voice("Player", open_sound, volume_db, routed)
	_applause_player = _build_voice("Applause", applause_sound, applause_volume_db, routed)


## One configured, in-tree AudioStreamPlayer3D. ⭐PROCESS_MODE_ALWAYS is load-bearing: a station opened from a
## CONVERSATION opens under DialogueManager's pause, and a pausable player fades itself to silence on
## NOTIFICATION_PAUSED — the cue would die in the same frame it started, with no error and nothing logged.
func _build_voice(voice_name: String, stream: AudioStream, trim_db: float, routed_bus: StringName) -> AudioStreamPlayer3D:
	var voice := AudioStreamPlayer3D.new()
	voice.name = voice_name
	voice.process_mode = Node.PROCESS_MODE_ALWAYS
	voice.stream = stream
	voice.bus = routed_bus
	voice.volume_db = trim_db
	voice.unit_size = unit_size
	voice.max_distance = max_distance
	add_child(voice)
	return voice


## The configured bus if it exists, else `sfx`. A renamed or deleted bus would otherwise drop the chirp onto
## Master, where no volume slider reaches it (the AudioManager @risk, in its authored-node form).
func _resolved_bus() -> StringName:
	if AudioServer.get_bus_index(bus) >= 0:
		return bus
	push_warning("StationSpeaker '%s': audio bus '%s' does not exist — falling back to 'sfx'." % [name, bus])
	return &"sfx"


## Sound the machine. Returns whether anything actually played, which is what lets the calling screen decide
## between this cue and the generic UI sting. play() restarts, so re-opening re-chirps instead of layering.
## No-ops (false) off-tree or with the clip cleared — a mute terminal is a supported authoring choice.
func play_open_sound() -> bool:
	if _player == null or open_sound == null:
		return false
	_player.stream = open_sound  # honour a clip swapped at runtime (a cutscene, a hacked terminal)
	# Plain play(): this chirp is the terminal's UI feedback for a SCREEN opening, so it stays exact like every
	# other menu cue — it just happens to be rendered through a diegetic speaker. See AudioManager.vary_pitch.
	_player.play()
	return true


## Clap for the player out of the panel. Same shape and same no-op rules as play_open_sound (mute with a
## cleared `applause_sound`, silent off-tree), on its OWN voice so it neither cuts nor is cut by the chirp.
## play() restarts, so a second repayment re-claps instead of layering a second crowd on the first.
func play_applause() -> bool:
	if _applause_player == null or applause_sound == null:
		return false
	_applause_player.stream = applause_sound
	_applause_player.play()  # exact, like the chirp above and AudioManager.play_applause — a reward cue, not a world sound
	return true


# --- The static seam the station SCREENS use ---------------------------------------------------------------

## The speaker for `station`: the node itself if it IS one, else its first StationSpeaker child. By TYPE, never
## by name — a designer renaming the node in their scene tree must not silence the machine.
static func find_speaker(station: Node) -> StationSpeaker:
	if not is_instance_valid(station):
		return null
	if station is StationSpeaker:
		return station
	for c in station.get_children():
		if c is StationSpeaker:
			return c
	return null


## ⭐THE SCREEN-SIDE SEAM. Sound `station`'s speaker and report whether it spoke, so the caller can suppress the
## generic menu sting for a machine that has its own voice:
##     _prev_mouse_mode = ModalMenu.grab_mouse(not StationSpeaker.chirp(healer))
## Call it at the point the open is COMMITTED (past every refuse guard) — a machine that beeps at an open that
## never happened reads as broken. Null-safe and station-type-agnostic, so no screen needs a has_method() dance.
static func chirp(station: Node) -> bool:
	var sp := find_speaker(station)
	return sp.play_open_sound() if sp != null else false


## ⭐THE REWARD SEAM — the machine applauds you, out of the same crappy panel speaker, for doing the thing it
## wanted. Its one caller today is `Atm.deposit`, on the portion of a deposit that actually RETIRES DEBT: the
## SAME predicate that scores credit standing, so "the terminal claps when you pay something off" and "paying
## something off improves your record" can never drift apart, and merely banking savings stays unremarkable.
##
## ⭐IT DELIBERATELY DOES NOT FOLLOW THE "one cue, never two" RULE `chirp` DOES, and that is not an oversight.
## There, both sounds answered the same instant of the same event on the same layer, so one had to yield. Here
## they do not: the caller's crisp UI commit click confirms THE PRESS registered (immediate, 2D, every till in
## the game makes it), while this is a several-second diegetic flourish from the machine for a milestone only
## some presses reach. Suppressing the click would make a repayment feel mushier than an ordinary deposit —
## exactly backwards. Callers therefore ignore the return value; it exists for symmetry and for tests.
##
## Null-safe and station-type-agnostic like chirp, so a station with no speaker at all (a data-only terminal
## riding a talking teller — a person who applauds themselves is a bug) is a quiet no-op, never a crash.
static func applaud(station: Node) -> bool:
	var sp := find_speaker(station)
	return sp.play_applause() if sp != null else false


## Give `station` a default kiosk voice unless a designer already authored one. Called from a standalone
## station's _ready so a bare prefab dropped in the level already answers when you use it; an AUTHORED
## StationSpeaker child always wins (that is the tuning AND the mute switch — see the header). Runtime only:
## a @tool station must never spawn nodes into a scene the designer is editing.
static func ensure(station: Node) -> StationSpeaker:
	if not is_instance_valid(station) or Engine.is_editor_hint():
		return null
	var existing := find_speaker(station)
	if existing != null:
		return existing
	var sp := StationSpeaker.new()
	sp.name = "Speaker"
	station.add_child(sp)
	return sp
