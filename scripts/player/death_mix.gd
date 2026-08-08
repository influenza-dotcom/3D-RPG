class_name DeathMix
extends AudioStreamPlayer

## @system Effect And Audio Seams
## @seam Owns everything you HEAR while dying: begin() / set_world_duck(t) / restore_world() / begin_revive() are the four seams Player's death cinematic delegates to, and the sting plays on this very node.
## @risk Listing death_sting_bus INSIDE death_cinematic_buses ducks the sting along with the world — the one wiring mistake that silently un-does the whole feature; _ready() push_warning's it and tests/test_death_mix.gd pins it.
## @risk The duck writes GLOBAL bus volumes, so any teardown that frees the Player without reaching a death branch would leave the world silent into the next life; _exit_tree() is the backstop (and fixes the same pre-existing hole for the Options -> Main Menu / Load-game escapes).
## @risk An authored AudioStreamPlayer with no `bus =` line lands on Master, which the cinematic deliberately no longer ducks — such a sound now plays at FULL volume under the death card; tests/test_audio_bus_hygiene.gd guards the scene side.
## @test res://tests/test_death_mix.gd

## The death cinematic's MIX, in one object: the world ducks out while the death sting rides over the top.
##
## WHY THIS EXISTS AT ALL. The cinematic used to fade the global **Master** bus to silence, which is the one
## thing that cannot coexist with a death sting: in Godot every bus chain terminates at Master (`ambient`,
## `sfx`, `music`, `voice` all send there; `radio` -> `music`, `ambient_bed` -> `ambient`), so there is no
## route around a Master fade and no gain trick that survives it. The fade therefore moved down one level
## onto the four WORLD buses (GameSettings.player_feedback.death_cinematic_buses) and the sting got a bus
## that is deliberately absent from that list (`death_sting_bus`, default `sting` — straight to Master, no
## effects). The world drains, the sting doesn't. That is the entire mechanism.
##
## NO CAPTURED BASE dB ANYWHERE — that is load-bearing, not an accident. Every write recomputes the target
## from `Settings.current_bus_db(bus)` (authored base + the player's slider — the exact value apply_audio
## writes) scaled by one `_duck_k` multiplier. Because nothing ever samples the LIVE bus, the "rapid
## re-trigger snapshots the already-ducked level and ratchets the mix permanently quieter" bug is not
## expressible here; each bus also keeps its own authored level (ambient +6.0, sfx -6.6, music 0, voice 0)
## because a uniform multiplier is relative, and a slider dragged mid-cinematic is honoured within a frame.
##
## A code-built child of the Player (the HurtFeedback / ScopeCoordinator idiom), given a host ref right
## after .new(). PROCESS_MODE_ALWAYS because a pausing screen is reachable while dead and the duck must hold
## through it — the DialogueMusicBed precedent.
##
## NOT an AudioManager.play_2d_sfx() one-shot, deliberately: those are parented to get_tree().root with no
## process_mode, so an 8-second sting would be pausable AND would outlive a RELOAD_* scene reload into the
## fresh life with nothing left alive to stop it. The sting's lifetime must be the dying Player's.
##
## Leave `death_sting` null and this whole component is inert in the only way that matters — the world still
## ducks (identical to the old Master fade in effect), nothing plays. That is the one-field rollback.

var host: Node

## The world buses the death cinematic currently OWNS — a GLOBAL fact, because the buses themselves are
## global singletons. While a bus is listed here DeathMix re-asserts its level every frame, so any other
## ducker writing that same bus would be fighting it: both write absolute dB, the last writer of the frame
## wins, and the mix audibly slams. Those duckers stand down instead — see ScopeCoordinator's
## _duck_music_for_scope and MusicDucker.set_ducked, which is why this is public API and not an internal.
##
## THE WINDOW THIS EXISTS FOR is the revive, not the death: _respawn_at_checkpoint hands the player back
## physics + mouse input BEFORE calling begin_revive(), so they are alive and free to ADS (or start a
## conversation) for the whole spawn_fade_in_time swell while these buses are still being animated.
##
## Static because there is exactly one dying player, and because a Player freed mid-cinematic must still be
## able to release the buses on its way out. Cleared on EVERY exit — restore_world, _end_world_fade and
## _exit_tree — since a leaked `true` would silence every music duck in the game permanently.
static var _owned_buses: Array[StringName] = []

## True while the death cinematic is animating this bus and nothing else may write it.
static func owns_bus(bus: StringName) -> bool:
	return _owned_buses.has(bus)

## True between begin() and restore_world()/begin_revive()'s end — gates the per-frame re-assert and tells
## _exit_tree() whether it still owes the world a restore.
var _ducked: bool = false
## The world's level as a FRACTION of configured (1 = untouched, death_world_residue = fully ducked). One
## scalar is the whole duck state; see the class comment on why there is no captured dB beside it.
var _duck_k: float = 1.0
var _revive_tween: Tween    ## world coming back up on the in-place revive
var _sting_tween: Tween     ## the sting's start DELAY, and later the optional death_sting_release fade (never both at once)

## Where the sting's release fade lands before it stops. Not a designer knob: it is "inaudible" expressed in
## dB, not a mix choice — the tunable is death_sting_release (how long it takes to get here).
const SILENT_DB: float = -60.0


func _ready() -> void:
	# A pausing modal is reachable while dead (Player._close_open_modals runs again on the revive precisely
	# because of that), and FreezeFrame pauses too. The duck's per-frame re-assert and the sting both have to
	# survive it — same reason DialogueMusicBed and the level's Music/Ambience players are ALWAYS.
	process_mode = Node.PROCESS_MODE_ALWAYS
	autoplay = false
	set_process(false)  # only ticks between begin() and the restore; nothing to re-assert otherwise
	_warn_on_bad_wiring()


## Fail LOUD in the editor/dev run for the two wiring mistakes that would otherwise degrade silently: a sting
## bus that isn't in default_bus_layout.tres (the player falls back to Master and gets ducked... except Master
## is no longer ducked, so it would blare instead), and a sting bus that the cinematic itself ducks.
func _warn_on_bad_wiring() -> void:
	var fb := GameSettings.player_feedback
	if AudioServer.get_bus_index(fb.death_sting_bus) < 0:
		push_warning("DeathMix: death_sting_bus '%s' is not a bus in default_bus_layout.tres." % fb.death_sting_bus)
	if fb.death_cinematic_buses.has(fb.death_sting_bus):
		push_warning("DeathMix: death_sting_bus '%s' is also in death_cinematic_buses — the cinematic would duck its own soundtrack." % fb.death_sting_bus)


# ---------------------------------------------------------------------------------------------------
# The four seams the death cinematic drives (Player._run_death_sequence / _death_step /
# _restore_death_audio / the in-place revive)
# ---------------------------------------------------------------------------------------------------

## Death starts. Snap the world to its configured level (so the duck always begins from a known reference,
## never from whatever a half-finished ducker left behind) and start the sting.
func begin() -> void:
	_kill_tweens()
	_ducked = true
	_duck_k = 1.0
	# Claim the buses BEFORE the first write. Player.die() has already hard-settled the ADS duck
	# (ScopeCoordinator.reset) and the conversation duck (DialogueManager.reset_music_duck), so no other
	# ducker holds a latch at this moment — that invariant is what makes standing them down safe.
	_owned_buses = GameSettings.player_feedback.death_cinematic_buses.duplicate()
	_apply_duck()
	set_process(true)
	# Silence any previous sting FIRST, unconditionally. _start_sting() can decline to play (no clip authored,
	# or the governing slider is at 0), and a re-death landing during the previous sting's release fade would
	# otherwise have just had that fade killed above — leaving the old clip audibly running with no owner.
	stop()
	_start_sting_sequence()


## Hold the sting back, start it, and SWELL it in — one wall-clock tween, so the death slow-mo cannot stretch
## any of it. Three beats, each optional:
##   1. death_sting_start_delay — the sting is deliberately NOT on the killing blow, so the world drains a
##      moment first and the sting arrives as a reaction rather than as part of the gunshot.
##   2. play() at silence.
##   3. death_sting_fade_in — swell up to level. Starting at full volume is a hard edge against a world that
##      is ducking AWAY, which reads as a jolt; the swell hands the mix over instead of snatching it.
## Re-uses _sting_tween: this always resolves long before begin_revive() could start a release, and sharing
## the handle means a re-death's _kill_tweens() cancels a pending start it no longer wants.
func _start_sting_sequence() -> void:
	var fb := GameSettings.player_feedback
	if not _sting_will_play() or not is_inside_tree():
		return
	var delay: float = maxf(fb.death_sting_start_delay, 0.0)
	var swell: float = maxf(fb.death_sting_fade_in, 0.0)
	_sting_tween = create_tween().set_ignore_time_scale(true)
	if delay > 0.0:
		_sting_tween.tween_interval(delay)
	_sting_tween.tween_callback(_start_sting)
	if swell > 0.0:
		# Tween a 0..1 LINEAR-AMPLITUDE factor, not volume_db directly. A straight dB ramp from silence spends
		# most of its length inaudible and then rushes in — the same reason the release fade was dropped.
		_sting_tween.tween_method(_set_sting_gain, 0.0, 1.0, swell)


## Phase 1 of the cinematic, 0..1 over death_sequence_time: the world ducks out in lockstep with the closing
## vignette — making ROOM for the sting rather than silencing it too.
func set_world_duck(t: float) -> void:
	var residue: float = clampf(GameSettings.player_feedback.death_world_residue, 0.0, 1.0)
	_duck_k = lerpf(1.0, residue, clampf(t, 0.0, 1.0))
	_apply_duck()


## Hard-restore every ducked bus and cut the sting. The RELOADING death exits call this (through the Player's
## _restore_death_audio facade) because a reload does NOT reset a bus — the buses are global, so a reload with
## them still ducked boots the next life near-silent.
##
## Restores by iterating the DESIGNER list rather than a captured dict, which is why adding a bus to
## death_cinematic_buses can never leave one death mode stale — historically the nastiest shape this bug takes,
## since it reproduces on exactly one branch.
func restore_world() -> void:
	_kill_tweens()
	_ducked = false
	_owned_buses = []  # release the buses before writing them, so nothing is left locked out
	_duck_k = 1.0
	set_process(false)
	for b: StringName in GameSettings.player_feedback.death_cinematic_buses:
		var idx := AudioServer.get_bus_index(b)
		if idx >= 0:
			AudioServer.set_bus_volume_db(idx, Settings.current_bus_db(b))
	stop()


## The in-place revive (CHECKPOINT_RESPAWN): the world swells back up over spawn_fade_in_time.
##
## THE STING IS DELIBERATELY LEFT ALONE HERE. By default (death_sting_release = 0) it simply keeps playing
## and ends when the clip ends — death_sting_sync_point has already timed the respawn onto its final chord, so
## the tail rings on over the world fading in, which is the whole effect. Forcing a fade SOUNDS LIKE A CUT: a ramp to
## silence is perceptually over long before it mathematically finishes (a linear-dB fade is ~inaudible after
## the first third), so it amputates the clip's own decay rather than blending with it.
##
## A designer can still ask for the forced fade by setting death_sting_release > 0, for a clip that outstays
## its welcome. That path stops the player at the end; the ring-out path never needs to, because the stream
## finishes on its own — and begin() / restore_world() both stop() unconditionally anyway, so a re-death or a
## reloading death mode still cuts it dead.
func begin_revive() -> void:
	_kill_tweens()
	var fb := GameSettings.player_feedback
	if not is_inside_tree():
		restore_world()  # off-tree there is no clock to fade on; land on the correct levels immediately
		return
	_revive_tween = create_tween().set_ignore_time_scale(true)
	_revive_tween.tween_method(_set_duck_k, _duck_k, 1.0, fb.spawn_fade_in_time)
	_revive_tween.tween_callback(_end_world_fade)
	if playing and fb.death_sting_release > 0.0:
		_sting_tween = create_tween().set_ignore_time_scale(true)
		_sting_tween.tween_property(self, ^"volume_db", SILENT_DB, fb.death_sting_release)
		_sting_tween.tween_callback(stop)


# ---------------------------------------------------------------------------------------------------
# Internals
# ---------------------------------------------------------------------------------------------------

## THE SINGLE WRITE PATH for the ducked buses. Re-derives every level from Settings each time — see the class
## comment for why there is no captured base dB to go stale or ratchet.
func _apply_duck() -> void:
	for b: StringName in GameSettings.player_feedback.death_cinematic_buses:
		var idx := AudioServer.get_bus_index(b)
		if idx < 0:
			continue
		var lin: float = db_to_linear(Settings.current_bus_db(b)) * _duck_k
		AudioServer.set_bus_volume_db(idx, linear_to_db(maxf(lin, 0.0001)))


## Re-assert the duck every frame while it is held. This is the self-healing guard, and it earns its keep in
## two places: Settings.apply_audio() writes all five slider buses ABSOLUTELY and is reachable from an Options
## slider dragged behind the death card, and the plateau between the end of phase 1 and the respawn has no
## other writer at all.
func _process(_delta: float) -> void:
	if _ducked:
		_apply_duck()


func _set_duck_k(k: float) -> void:
	_duck_k = k
	_apply_duck()


## The revive's world fade reached full — drop the duck and land on the exact configured levels (the tween's
## last step is a lerp, not necessarily the precise value).
func _end_world_fade() -> void:
	_ducked = false
	_owned_buses = []  # the swell is over — the ADS / conversation ducks may have the music bus back
	set_process(false)
	_duck_k = 1.0
	for b: StringName in GameSettings.player_feedback.death_cinematic_buses:
		var idx := AudioServer.get_bus_index(b)
		if idx >= 0:
			AudioServer.set_bus_volume_db(idx, Settings.current_bus_db(b))


## Start (or RE-start) the sting. play() from the top is deliberate: a second death during the tail of the
## first must not layer a second copy of an 8-second clip over itself.
## The sting's level once fully swelled in. `sting` has no Options slider of its own (it is not in
## Settings.VOLUME_BUSES), so the nominated slider is folded into this player's own level instead of adding a
## sixth slider nobody asked for. A muted slider never reaches here — _sting_will_play() refuses first.
func _sting_target_db() -> float:
	var fb := GameSettings.player_feedback
	var slider: float = 1.0
	if fb.death_sting_slider_bus != &"":
		slider = clampf(Settings.get_volume(fb.death_sting_slider_bus), 0.0, 1.0)
	return fb.death_sting_volume_db + linear_to_db(maxf(slider, 0.0001))


## Drive the swell from a 0..1 linear-amplitude factor. Re-reads the target each frame so a volume slider
## dragged mid-cinematic is honoured, exactly like the world duck.
func _set_sting_gain(k: float) -> void:
	volume_db = _sting_target_db() + linear_to_db(maxf(k, 0.0001))


## Mount and start the clip. Opens at SILENCE when a swell is authored (the tween takes it up from there);
## with no swell it starts at level, which is the old instant-on behaviour.
func _start_sting() -> void:
	var fb := GameSettings.player_feedback
	if not _sting_will_play() or not is_inside_tree():
		return
	stream = fb.death_sting
	bus = fb.death_sting_bus
	volume_db = SILENT_DB if fb.death_sting_fade_in > 0.0 else _sting_target_db()
	play()


## Whether a sting will actually sound at all this death — false if none is authored, or if the player has
## muted the slider governing it. Both timing helpers below return 0.0 in that case, so the cinematic never
## stretches itself around audio nobody is going to hear.
func _sting_will_play() -> bool:
	var fb := GameSettings.player_feedback
	if fb.death_sting == null:
		return false
	if fb.death_sting_slider_bus != &"" and Settings.get_volume(fb.death_sting_slider_bus) <= 0.0:
		return false
	return true


## Wall-clock seconds from the moment of death to the sting's LAST SAMPLE — start delay + the clip's real
## length, read off the stream so it re-derives itself whenever a designer swaps the clip. 0.0 when nothing
## will play. Not used for timing the cinematic (sting_sync_time is); this is how far the sting rings on.
func sting_end_time() -> float:
	if not _sting_will_play():
		return 0.0
	var fb := GameSettings.player_feedback
	return maxf(fb.death_sting_start_delay, 0.0) + maxf(fb.death_sting.get_length(), 0.0)


## Wall-clock seconds from the moment of death to the instant in the clip the respawn should land ON — the
## sting's own `death_sting_sync_point` (its final chord) offset by the start delay. This is what the death
## card's hold is solved against, so the chord attacks exactly as the screen starts fading back in.
##
## Clamped to the clip's real length: an over-long sync point could otherwise push the respawn past the end
## of the audio, holding the player on a black screen listening to nothing. 0.0 when nothing will play, or
## when the designer set the sync point to 0 to opt out of aligning entirely.
func sting_sync_time() -> float:
	if not _sting_will_play():
		return 0.0
	var fb := GameSettings.player_feedback
	if fb.death_sting_sync_point <= 0.0:
		return 0.0
	var cue: float = minf(fb.death_sting_sync_point, maxf(fb.death_sting.get_length(), 0.0))
	return maxf(fb.death_sting_start_delay, 0.0) + cue


## How long the death card should hold FULLY VISIBLE: `respawn_delay`, stretched so the screen starts fading
## back in exactly ON the sting's sync point — its final chord (death_card_holds_for_sting).
##
## THE CINEMATIC IS SCORED TO THE CLIP, not merely long enough for it. The card's hold is the only beat that
## can absorb the difference, so it is what we solve for:
##
##     death_sequence_time + death_card_delay + fade_in + HOLD + fade_out + death_card_gap  ==  sting_sync_time()
##
## Everything before the hold is the keel-over, the settle-on-black beat and the card's own fade-in;
## everything after it is the card fading out and the black gap. Land that sum on the sync point and the chord attacks on the same frame
## _fade_in_from_black() starts, then rings out underneath the fade-up. Solved rather than authored, because a
## hold baked into the .tres goes stale the moment anyone touches another timing — and because
## tests/test_player_core.gd pins `respawn_delay` at 1.0.
##
## `respawn_delay` stays the FLOOR: this only ever lengthens the beat, never shortens it, so a short clip
## (or none, or a sync point of 0) plays the original snappy cinematic with nothing changed.
func card_hold_seconds() -> float:
	var fb := GameSettings.player_feedback
	if not fb.death_card_holds_for_sting:
		return fb.respawn_delay
	var sync := sting_sync_time()
	if sync <= 0.0:
		return fb.respawn_delay  # nothing to align to (no clip, muted slider, or sync point opted out of)
	# Everything in the cinematic that is NOT the hold, i.e. what plays before and after it.
	var fixed := fb.death_sequence_time + maxf(fb.death_card_delay, 0.0) + fb.death_card_fade_time * 2.0 + fb.death_card_gap
	return maxf(fb.respawn_delay, sync - fixed)


func _kill_tweens() -> void:
	if _revive_tween != null and _revive_tween.is_valid():
		_revive_tween.kill()
	if _sting_tween != null and _sting_tween.is_valid():
		_sting_tween.kill()


## Safety net: the buses are GLOBAL, so a teardown that frees the Player mid-cinematic without going through
## any death branch would leave the world ducked forever with nobody left to restore it. Reachable today via
## Options -> Main Menu and Options -> Load Game, both of which change scene straight out from under a dying
## player — so this also closes that hole for the pre-existing fade.
func _exit_tree() -> void:
	if _ducked:
		restore_world()
	_owned_buses = []  # belt-and-braces: static state must never outlive the node that set it
