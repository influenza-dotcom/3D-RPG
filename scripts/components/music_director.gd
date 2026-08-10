@tool
class_name MusicDirector
extends Node

## Drop-in DYNAMIC MUSIC director. The track PLAYS CONSTANTLY (the parent player's autoplay + loop keep its
## position advancing) but sits SILENT during normal exploration — it fades IN when combat starts and fades
## back OUT when the fight ends. Because the underlying stream never stops, a fade-in joins the music mid-track
## instead of restarting it. (A conversation does NOT swell the score by default — dialogue plays with no music
## bed; opt back into scored conversations with swell_for_dialogue.)
##
## SETUP: drop this node as a CHILD of the music AudioStreamPlayer / AudioStreamPlayer3D (the game scene's
## Player/Music node). The parent's authored volume_db is captured as the AUDIBLE level; this only ever
## moves the NODE volume, so it stacks cleanly with the bus-level writers (the Settings music slider, the
## dialogue ducker — which keeps conversation music a touch under the voices — and the ADS duck).
##
## COMBAT = any NPC in the "npc" group reporting is_in_combat(), polled on an interval, plus a short linger
## so music doesn't flap at a fight's ragged edge. DIALOGUE (opt-in via swell_for_dialogue) = DialogueManager.is_active().
## The dialogue tree-pause doesn't stall the fade — this node runs PROCESS_MODE_ALWAYS, like the music player itself.
## The station screens (shop / heal / level-up / atm / …) no longer pause at all, so a mid-fight shop visit is
## just gameplay as far as this node is concerned: NPC combat state keeps updating underneath and the score
## follows the real fight, instead of holding a frozen snapshot. Only a conversation still freezes the world,
## and an already-running fade simply finishes through it.

@export var fade_in_time: float = 1.2    ## seconds, silence -> audible (combat hits fast)
@export var fade_out_time: float = 3.0   ## seconds, audible -> silence (the fight's end breathes out)
@export var combat_linger: float = 2.5   ## seconds combat music holds after the last enemy disengages
@export var silent_db: float = -60.0     ## the "off" floor; effectively inaudible but still playing
## A diegetic in-world Radio the player can actually HEAR takes precedence over the dynamic score: while you stand
## within a playing Radio's audible_radius, the bed stays SILENT so the radio's own music carries the moment (for
## combat, and for dialogue when swell_for_dialogue is on; radio.gd likewise plays straight through both, its ducks
## default OFF). Distance-gated (see _radio_audible_to_player): a radio across the map won't mute the score over there.
@export var yield_to_radio: bool = true
## Opt IN to swelling the dynamic score during a conversation too (DialogueManager.is_active()), the way combat does.
## OFF by default: dialogue plays WITHOUT a music bed — talking is not a fight, and a second score layer competes with
## the voices (the dialogue MusicDucker already dips whatever music IS playing, e.g. a diegetic radio, under the lines).
## Turn this on for a scored, cinematic conversation; the same yield_to_radio precedence then applies to it too.
@export var swell_for_dialogue: bool = false

const POLL_INTERVAL: float = 0.3  ## seconds between combat scans (a per-frame group scan would be waste)

var _music: Node = null         ## the parent player — loose-typed; AudioStreamPlayer and ...3D both expose volume_db
var _audible_db: float = 0.0    ## the parent's authored volume = the fade-in target
var _poll_t: float = 0.0
var _linger_t: float = 0.0
var _in_combat: bool = false

func _ready() -> void:
	if Engine.is_editor_hint():
		return  # @tool: only _get_configuration_warnings runs in the editor; never mutate the parent's volume there
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
	# RADIO precedence: a diegetic Radio the player can hear OWNS the soundscape, so the dynamic bed stands down and
	# the radio's music carries the moment (radio.gd likewise plays through combat and dialogue). The score fades in
	# for combat (and, only when swell_for_dialogue is on, an open conversation); an audible radio yields it either way.
	var want: bool = _in_combat or _linger_t > 0.0 or (swell_for_dialogue and _dialogue_active())
	if want and yield_to_radio and _radio_audible_to_player():
		want = false
	var target: float = _audible_db if want else silent_db
	var span: float = maxf(absf(_audible_db - silent_db), 0.001)
	var time: float = fade_in_time if want else fade_out_time
	_music.volume_db = move_toward(_music.volume_db, target, span / maxf(time, 0.001) * delta)

## True while any NPC is actively ENGAGED (is_in_combat = ALERTED with a live target) — the signal that pulls the
## music in. COMBAT ONLY: a guard that merely SEARCHES your last-known spot (INVESTIGATING / the HUD's [CAUTION])
## does NOT keep the music up — combat_linger bridges the brief LOS gaps WITHIN a fight so it doesn't flap, then
## the music fades as the fight truly ends and the hunt begins (so searching plays out in tense silence, not score).
## Null-guarded for a bare off-tree instance (no tree -> no combat).
func _any_npc_in_combat() -> bool:
	var tree := get_tree()
	if tree == null:
		return false
	for n in tree.get_nodes_in_group(Groups.NPC):
		if n is NPC and (n as NPC).is_in_combat():
			return true
	return false

## True while a conversation is open (DialogueManager.is_active()) — the dialogue trigger, read ONLY when
## swell_for_dialogue is on (off by default, so dialogue plays with no music bed). Wrapped in one overridable
## method so a unit test can force it without driving a live DialogueManager conversation in a headless run
## (mirrors the test-double seams on Radio). Also the single place the dialogue trigger is read.
func _dialogue_active() -> bool:
	return DialogueManager.is_active()

## True when the human player stands within the audible_radius of any PLAYING in-world Radio — the cue that makes
## the combat bed yield (yield_to_radio). Duck-typed over the Groups.MUSIC group (a Radio joins it while on) so this
## never hard-references the Radio class; mirrors NPC._nearest_audible_radio (npc.gd). DISTANCE-GATED on purpose: a
## radio across the map (out of earshot, already near-silent from its AudioStreamPlayer3D's 3D attenuation) must NOT
## mute the combat score for a fight happening over there. No player / off-tree -> false (the bed plays as before).
func _radio_audible_to_player() -> bool:
	var player := _real_player()
	if player == null:
		return false
	var here := player.global_position
	for n in get_tree().get_nodes_in_group(Groups.MUSIC):
		if not (n is Node3D) or not n.has_method(&"is_playing"):
			continue
		var radio := n as Node3D
		if not bool(radio.call(&"is_playing")):
			continue
		var radius_v: Variant = radio.get(&"audible_radius")  # duck-typed: a music-group node may lack it -> skip
		if not (radius_v is float or radius_v is int):
			continue
		if here.distance_to(radio.global_position) <= float(radius_v):
			return true
	return false

## The HUMAN player (the non-NPC member of the Player group), or null — recruited companions join the same group
## for targeting but are NPCs. Mirrors PropFollow._real_player / RewardStinger. Tree-guarded for a bare instance.
func _real_player() -> Node3D:
	return Groups.human_player(get_tree())  # M6: centralized human-player lookup (null tree -> null)

## Editor warning: MusicDirector only works as a child of the music AudioStreamPlayer (it fades that parent's
## volume). Under any other parent it no-ops -- surface that at edit time, not just the runtime push_warning.
func _get_configuration_warnings() -> PackedStringArray:
	var p := get_parent()
	if p == null or not (p is AudioStreamPlayer or p is AudioStreamPlayer3D or p is AudioStreamPlayer2D):
		return PackedStringArray([
			"Parent isn't an audio player — drop MusicDirector UNDER the music AudioStreamPlayer (2D/3D); otherwise it does nothing.",
		])
	return PackedStringArray()
