@tool
class_name MusicDirector
extends Node

## Drop-in DYNAMIC MUSIC director. The track PLAYS CONSTANTLY (the parent player's autoplay + loop keep its
## position advancing) but sits SILENT during normal exploration — it fades IN when combat starts and fades
## back OUT once the coast is genuinely clear. Because the underlying stream never stops, a fade-in joins the
## music mid-track instead of restarting it. (A conversation does NOT swell the score by default — dialogue
## plays with no music bed; opt back into scored conversations with swell_for_dialogue.)
##
## A THREE-TIER LADDER, worst-first — the mix tracks the same escalation the stealth HUD prints:
##   FULL    — a live firefight (an NPC ALERTED on a target), the post-fight combat_linger, or the opt-in
##             dialogue swell. Target = the parent's authored volume.
##   CAUTION — nobody is shooting, but somebody is HUNTING: an NPC sweeping your last-known spot (Perception
##             INVESTIGATING — what the HUD prints as [CAUTION]). The score does NOT drop out; it SUSTAINS,
##             ducked by caution_duck_db, so the search keeps its pulse. The hunt is still the fight, quieter.
##   SILENT  — nobody is aware of anything. Target = silent_db (still playing, inaudible).
## An audible diegetic Radio (yield_to_radio), or an open station terminal playing its own bed
## (yield_to_station_music), collapses either of the top two tiers straight to SILENT.
##
## SETUP: drop this node as a CHILD of the music AudioStreamPlayer / AudioStreamPlayer3D (the game scene's
## Player/Music node). The parent's authored volume_db is captured as the AUDIBLE level; this only ever
## moves the NODE volume, so it stacks cleanly with the bus-level writers (the Settings music slider, the
## dialogue ducker — which keeps conversation music a touch under the voices — and the ADS duck).
##
## COMBAT = any NPC in the "npc" group reporting is_in_combat(), polled on an interval, plus a short linger
## so music doesn't flap at a fight's ragged edge. CAUTION = any NPC reporting is_hunting() while none is in
## combat — one group scan reads both. DIALOGUE (opt-in via swell_for_dialogue) = DialogueManager.is_active().
## The dialogue tree-pause doesn't stall the fade — this node runs PROCESS_MODE_ALWAYS, like the music player itself.
## The station screens (shop / heal / level-up / atm / …) no longer pause at all, so NPC combat state keeps
## updating under an open shop menu and the score follows the real fight instead of holding a frozen snapshot.
## The score does, however, STAND DOWN while one of those screens is up (yield_to_station_music): the machine
## is playing its own tinny radio out of its panel, and that owns the moment the way a diegetic Radio does.
## Only a conversation still freezes the world, and an already-running fade simply finishes through it.

@export var fade_in_time: float = 1.2    ## seconds for any RISE up the ladder (silent/caution -> full); combat hits fast
@export var fade_out_time: float = 3.0   ## seconds for any FALL down it (full -> caution -> silent); the fight breathes out
## Seconds the FULL tier holds after the last ALERTED enemy disengages, so the music doesn't flap at a fight's
## ragged edge — then it settles to CAUTION if somebody is still hunting, or to silence if nobody is. REUSED as
## the CAUTION tier's own hold at the tail of a search, for the same reason and against the same 0.3 s poll.
@export var combat_linger: float = 2.5
@export var silent_db: float = -60.0     ## the "off" floor; effectively inaudible but still playing
## How far UNDER the authored level the score sits while the enemy is merely HUNTING you (Perception
## INVESTIGATING — the HUD's [CAUTION]) rather than shooting at you. A NEGATIVE offset, like the dialogue
## ducker's music_duck_amount_db: the search keeps the music alive but pulls it back, so the firefight still
## has somewhere to go. Clamped into [silent_db, authored] every frame, so a positive value can't make the
## search LOUDER than the fight and an over-deep one can't sink below the floor — which doubles as the OFF
## SWITCH: set this to -60 (anything reaching the silent floor) and searching plays out in silence again,
## the pre-caution-tier behaviour. Note the duck's DURATION rides the authored volume, not this knob: the fade
## step is normalised over the whole silent->audible span, so an absolute 6 dB duck takes ~0.3 s from a 0 dB
## authored level but ~0.9 s from -40 dB.
@export var caution_duck_db: float = -6.0
## A diegetic in-world Radio the player can actually HEAR takes precedence over the dynamic score: while you stand
## within a playing Radio's audible_radius, the bed stays SILENT so the radio's own music carries the moment (for
## combat AND the ducked caution hunt, and for dialogue when swell_for_dialogue is on; radio.gd likewise plays
## straight through all of them, its ducks
## default OFF). Distance-gated (see _radio_audible_to_player): a radio across the map won't mute the score over there.
@export var yield_to_radio: bool = true
## A station TERMINAL's own radio takes precedence over the dynamic score, on exactly the reasoning above: while
## a shop / heal / level-up / respec / install / chess / atm screen is up, that machine's tinny bed is carrying
## the moment, so the score stands down instead of stacking under it. Collapses BOTH tiers, like the radio.
## OFF = a mid-firefight shop visit keeps the combat score playing UNDERNEATH the shop radio.
@export var yield_to_station_music: bool = true
## Opt IN to swelling the dynamic score during a conversation too (DialogueManager.is_active()), the way combat does.
## OFF by default: dialogue plays WITHOUT a music bed — talking is not a fight, and a second score layer competes with
## the voices (the dialogue MusicDucker already dips whatever music IS playing, e.g. a diegetic radio, under the lines).
## Turn this on for a scored, cinematic conversation; the same yield_to_radio precedence then applies to it too.
@export var swell_for_dialogue: bool = false

const POLL_INTERVAL: float = 0.3  ## seconds between awareness scans, both tiers (a per-frame group scan would be waste)

var _music: Node = null         ## the parent player — loose-typed; AudioStreamPlayer and ...3D both expose volume_db
var _audible_db: float = 0.0    ## the parent's authored volume = the FULL-tier target, and what caution_duck_db is measured from
var _poll_t: float = 0.0
var _linger_t: float = 0.0    ## FULL-tier hold after the last ALERTED enemy disengages
var _caution_t: float = 0.0   ## CAUTION-tier hold after the last searcher gives up (same seconds as combat_linger)
var _in_combat: bool = false
var _in_caution: bool = false ## somebody is HUNTING and nobody is ALERTED — see _scan_alert_levels

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
	# ONE awareness scan on an interval feeds BOTH tiers; each gets a linger so the music doesn't flap at a
	# fight's ragged edge or at the tail of a search (the scan is POLL_INTERVAL coarse).
	_poll_t -= delta
	if _poll_t <= 0.0:
		_poll_t = POLL_INTERVAL
		_scan_alert_levels()
	_linger_t = combat_linger if _in_combat else maxf(0.0, _linger_t - delta)
	_caution_t = combat_linger if _in_caution else maxf(0.0, _caution_t - delta)
	# The ladder, worst-first. FULL outranks CAUTION, so a mixed crowd (one shooter, one searcher) scores as a
	# fight; and combat_linger holds FULL right through the ALERTED <-> INVESTIGATING flicker of a broken line of
	# sight, so a firefight never audibly dips to the search level and back.
	var full: bool = _in_combat or _linger_t > 0.0 or (swell_for_dialogue and _dialogue_active())
	var caution: bool = _in_caution or _caution_t > 0.0
	# RADIO precedence: a diegetic Radio the player can hear OWNS the soundscape, so the dynamic bed stands down and
	# the radio's music carries the moment (radio.gd likewise plays through combat and dialogue). It collapses BOTH
	# tiers — there is no point sustaining a ducked search bed under a radio that is already carrying the scene.
	if (full or caution) and yield_to_radio and _radio_audible_to_player():
		full = false
		caution = false
	# STATION-TERMINAL precedence, the same reasoning as the radio above: the machine you are standing at is
	# already playing music out of its panel, so the dynamic score stands down for both tiers rather than
	# stacking a second layer under a shop menu. Reads the bed's WANTED flag, not its volume, so the two fades
	# run concurrently and the handover is a real crossfade in both directions.
	if (full or caution) and yield_to_station_music and _station_music_wanted():
		full = false
		caution = false
	# DIALOGUE SUPPRESSION — and it is a CORRECTNESS gate, not a taste one. A conversation FREEZES THE WORLD
	# (DialogueManager pauses the tree; a suspending sub-menu keeps it paused), and NPCs are pausable, so
	# Perception stops sensing entirely: an INVESTIGATING searcher can never CLEAR while the box is up. A polled
	# tier would therefore LATCH for the whole conversation and stack a second score under DialogueMusicBed.
	# swell_for_dialogue OFF has always MEANT "dialogue plays with no music bed"; nothing enforced it before
	# because Talkable already refuses a talk while an NPC is_in_combat() — but it does NOT refuse while one is
	# merely is_hunting(), which is exactly the new tier. (This also closes the old combat_linger tail bleeding
	# into a conversation's first seconds.) No live firefight is silenced by this: you cannot start one.
	if not swell_for_dialogue and _dialogue_active():
		full = false
		caution = false
	var target: float = silent_db
	if full:
		target = _audible_db
	elif caution:
		target = caution_db()
	# The step is normalised over the WHOLE silent->audible span, so a tier change moves at the same dB/second as a
	# full fade. DIRECTION picks the time — not the old "is anything wanted" boolean, which was equivalent while
	# there were only two levels but would run the FULL->CAUTION duck at the fade-IN rate.
	var span: float = maxf(absf(_audible_db - silent_db), 0.001)
	var time: float = fade_in_time if target > _music.volume_db else fade_out_time
	_music.volume_db = move_toward(_music.volume_db, target, span / maxf(time, 0.001) * delta)

## Sets BOTH tier flags from ONE pass over the "npc" group:
##   _in_combat  — somebody is actively ENGAGED (is_in_combat = ALERTED with a live target)
##   _in_caution — nobody is engaged, but somebody is HUNTING (is_hunting = ALERTED *or* INVESTIGATING, so
##                 with no ALERTED NPC in the group it means INVESTIGATING: sweeping a last-known spot,
##                 chasing a heard noise, standing over a found body — the HUD's [CAUTION])
##
## The WALK now lives in Soundscape.scan (scripts/audio/soundscape.gd), which returns exactly this pair and
## carries the reasoning that shaped it (one scan not two, a full walk not an early-out, target-agnostic).
## It was lifted out on 2026-08-22 when the wandering exploration bed (scripts/components/wander_music.gd)
## became a second reader — and that bed is this score's EXACT COMPLEMENT, audible in precisely the moments
## this one is silent. Two copies of this scan would not drift into a cosmetic bug; they would drift into a
## gap where neither layer plays or an overlap where both do. This method keeps its name and its two fields
## so the tests that force them on an instance are untouched.
func _scan_alert_levels() -> void:
	var seen: Dictionary = Soundscape.scan(get_tree())
	_in_combat = bool(seen["combat"])
	_in_caution = bool(seen["caution"])


## The CAUTION tier's absolute level: the authored volume pulled back by caution_duck_db, clamped into
## [silent_db, _audible_db]. The clamp is what makes the knob safe in both directions — a positive offset can't
## make a search louder than a firefight, and an over-deep one lands ON the floor (searching in silence, the
## pre-caution behaviour). Computed per frame, never cached, so silent_db's degenerate-config adjustment in
## _ready and any live retune both land. Public so a test or debug readout can name the level without
## re-deriving it.
func caution_db() -> float:
	return clampf(_audible_db + caution_duck_db, silent_db, _audible_db)

## True while a conversation EXISTS AT ALL — is_engaged(), deliberately NOT is_active(). Read for BOTH dialogue
## paths: the opt-in swell (swell_for_dialogue on) and the suppression gate that keeps the bed down otherwise.
##
## ⭐ is_active() reports a conversation SUSPENDED behind a sub-menu (Trade / Heal / Level Up / Install /
## Exchange) as INACTIVE so that menu is allowed to open — but the TREE IS STILL PAUSED through it. Gating on
## is_active() would hand the bed back mid-shop with the world frozen and every NPC's Perception stopped, which
## is the whole failure the suppression gate exists to prevent. is_engaged() is also the lifecycle
## DialogueMusicBed itself rides (it deliberately keeps playing across a suspension rather than stuttering), so
## the two music layers now agree on when a conversation is happening.
##
## Wrapped in one overridable method so a unit test can force it without driving a live DialogueManager
## conversation in a headless run (mirrors the test-double seams on Radio).
func _dialogue_active() -> bool:
	return DialogueManager.is_engaged()

## True while a station terminal's own radio is playing (or about to be) — see yield_to_station_music. Wrapped
## in one overridable method, not inlined, for the same reason as _dialogue_active(): a bare off-tree instance
## in a unit test can stub it without standing up the autoload and a live station screen.
func _station_music_wanted() -> bool:
	return StationMusic.is_bed_wanted()

## True when the human player stands within the audible_radius of any PLAYING in-world Radio — the cue that
## makes the dynamic bed yield (yield_to_radio). The scan itself is Soundscape.radio_audible_to, shared with
## the wandering bed so the two can never disagree about whether a radio owns the moment; the seam kept HERE
## is _real_player, which the tests override to stand up a stub listener beside a stub radio.
func _radio_audible_to_player() -> bool:
	return Soundscape.radio_audible_to(get_tree(), _real_player())


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
