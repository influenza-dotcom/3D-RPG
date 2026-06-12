class_name MusicDirector
extends Node

## Drop-in DYNAMIC MUSIC director. The track PLAYS CONSTANTLY (the parent player's autoplay + loop keep its
## position advancing) but sits SILENT during normal exploration — it fades IN when combat starts or a
## conversation opens, and fades back OUT when the fight ends. Because the underlying stream never stops,
## a fade-in joins the music mid-track instead of restarting it.
##
## SETUP: drop this node as a CHILD of the music AudioStreamPlayer / AudioStreamPlayer3D (the game scene's
## Player/Music node). The parent's authored volume_db is captured as the AUDIBLE level; this only ever
## moves the NODE volume, so it stacks cleanly with the bus-level writers (the Settings music slider, the
## dialogue ducker — which keeps conversation music a touch under the voices — and the ADS duck).
##
## COMBAT = any NPC in the "npc" group reporting is_in_combat(), polled on an interval, plus a short linger
## so music doesn't flap at a fight's ragged edge. DIALOGUE = DialogueManager.is_active(). The dialogue
## tree-pause doesn't stall the fade — this node runs PROCESS_MODE_ALWAYS, like the music player itself.
## That also means fades keep moving while a PAUSING screen (shop / heal / level-up) is open — which is
## correct: the NPCs' combat state freezes with the pause, so combat music HOLDS through a mid-fight shop
## visit instead of dropping out, and an already-running fade simply finishes.

@export var fade_in_time: float = 1.2    ## seconds, silence -> audible (combat hits fast)
@export var fade_out_time: float = 3.0   ## seconds, audible -> silence (the fight's end breathes out)
@export var combat_linger: float = 2.5   ## seconds combat music holds after the last enemy disengages
@export var silent_db: float = -60.0     ## the "off" floor; effectively inaudible but still playing

const POLL_INTERVAL: float = 0.3  ## seconds between combat scans (a per-frame group scan would be waste)

var _music: Node = null         ## the parent player — loose-typed; AudioStreamPlayer and ...3D both expose volume_db
var _audible_db: float = 0.0    ## the parent's authored volume = the fade-in target
var _poll_t: float = 0.0
var _linger_t: float = 0.0
var _in_combat: bool = false

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS  # keep fading through the dialogue tree-pause (the player node already does)
	var parent := get_parent()
	if not (parent is AudioStreamPlayer or parent is AudioStreamPlayer3D or parent is AudioStreamPlayer2D):
		push_warning("MusicDirector: parent isn't an audio player — drop this under the Music node; doing nothing")
		return
	_music = parent
	_audible_db = _music.volume_db  # the authored level IS the audible target
	# Degenerate config guard: the audible level must sit ABOVE the silent floor or "fading in" is a no-op
	# (equal) or actually fades DOWN (authored below the floor). Keep the feature working by dropping the
	# floor under the authored level, and tell the designer.
	if _audible_db <= silent_db + 1.0:
		push_warning("MusicDirector: the music node's authored volume (%.1f dB) sits at/below silent_db (%.1f dB) — lowering the silent floor to keep the fade meaningful; raise the node's volume or lower silent_db." % [_audible_db, silent_db])
		silent_db = _audible_db - 20.0
	_music.volume_db = silent_db    # start silent; the track keeps playing underneath

func _process(delta: float) -> void:
	if _music == null:
		return
	# Combat scan on an interval; the linger keeps the music up through a fight's brief lulls.
	_poll_t -= delta
	if _poll_t <= 0.0:
		_poll_t = POLL_INTERVAL
		_in_combat = _any_npc_in_combat()
	if _in_combat:
		_linger_t = combat_linger
	else:
		_linger_t = maxf(0.0, _linger_t - delta)
	var want: bool = _in_combat or _linger_t > 0.0 or DialogueManager.is_active()
	var target: float = _audible_db if want else silent_db
	var span: float = maxf(absf(_audible_db - silent_db), 0.001)
	var time: float = fade_in_time if want else fade_out_time
	_music.volume_db = move_toward(_music.volume_db, target, span / maxf(time, 0.001) * delta)

## True while any NPC is engaged OR actively hunting (is_hunting = ALERTED or INVESTIGATING) — the signal
## that pulls the music in. Using the hunt predicate keeps the music up through a broken line of sight
## while an enemy sweeps your last-known position, instead of flapping out mid-search and back in on the
## re-spot. Null-guarded for a bare off-tree instance (no tree -> no combat).
func _any_npc_in_combat() -> bool:
	var tree := get_tree()
	if tree == null:
		return false
	for n in tree.get_nodes_in_group(&"npc"):
		if n is NPC and (n as NPC).is_hunting():
			return true
	return false
