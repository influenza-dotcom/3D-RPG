class_name StationSpeaker
extends Node3D

## @system Audio
## @seam chirp(station) is THE open cue for every station screen (shop/heal/level-up/respec/install/chess/atm): the screen calls it at its commit point and feeds the RESULT to ModalMenu.grab_mouse(not chirped), so a machine with a voice REPLACES the generic UI sting instead of doubling it and a mute one still gets the sting. Static, type-agnostic and null-safe, so no screen branches or duck-types.
## @seam ensure(station) is the auto-build seam the station components call in _ready (gated on `standalone`); it never replaces an AUTHORED StationSpeaker child, which is what makes a hand-placed one the tuning AND the mute switch.
## @risk A PAUSABLE AudioStreamPlayer3D silences itself on NOTIFICATION_PAUSED ~15 ms in, with no error and nothing logged — a dialogue-hosted station opens under the conversation's pause, so the built player MUST stay PROCESS_MODE_ALWAYS.
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
## SETUP: drag it under the station (Merchant / Healer / LevelUp / RespecStation / ChipInstaller / ChessMatch /
## Atm). Nothing else — the station finds it by TYPE, not by name or an exported path. The stations that ship
## a default kiosk voice build one for themselves at _ready, so authoring one is how you TUNE or SILENCE the
## machine (a `StationSpeaker` with `open_sound` cleared is a deliberately mute terminal).

## The shipped default: the ATM's deposit tone, now the house voice of every self-serve machine.
const DEFAULT_CHIRP := preload("res://assets/audio/sfx/deposit.wav")

## The clip the machine plays when its screen wakes up. Clear it for a silent station.
@export var open_sound: AudioStream = DEFAULT_CHIRP
## Loudness in dB (0 = the clip's own level, less whatever the bus's filters strip).
@export var volume_db: float = 0.0
## ⭐The tinny filter chain (see the header). `sfx` for a clean machine; a missing bus degrades to `sfx`.
@export var bus: StringName = &"speaker"
## How far (m) the sound carries. A panel speaker is not a PA — keep it short so it stays the machine's voice.
@export var max_distance: float = 10.0
## Distance falloff (AudioStreamPlayer3D.unit_size) — smaller drops off faster.
@export var unit_size: float = 4.0

var _player: AudioStreamPlayer3D = null


## Build the actual player at _ready — NOT lazily at the first chirp — so the listener is already resolved and
## nothing has to warm up in the frame a screen opens. ⭐PROCESS_MODE_ALWAYS is load-bearing: a station opened
## from a CONVERSATION opens under DialogueManager's pause, and a pausable player fades itself to silence on
## NOTIFICATION_PAUSED — the chirp would die in the same frame it started, with no error and nothing logged.
func _ready() -> void:
	_player = AudioStreamPlayer3D.new()
	_player.name = "Player"
	_player.process_mode = Node.PROCESS_MODE_ALWAYS
	_player.stream = open_sound
	_player.bus = _resolved_bus()
	_player.volume_db = volume_db
	_player.unit_size = unit_size
	_player.max_distance = max_distance
	add_child(_player)


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
	_player.play()
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
