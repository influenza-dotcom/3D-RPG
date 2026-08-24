class_name WanderMusicSettings
extends Resource

## The WANDERING BED — the quiet, non-diegetic music that plays while you are just exploring: nobody is
## hunting you, no radio is on, no terminal screen is up, nobody is talking. It is the EXACT COMPLEMENT of the
## dynamic combat score (scripts/components/music_director.gd), which is silent in exactly the moments this
## layer is audible and swells in exactly the moments this one stands down.
##
## Read live by the WanderMusic node (scripts/components/wander_music.gd, authored in scenes/game.tscn under
## Player); edit the values in the inspector on resources/tuning/WanderMusicSettings.tres (reached from
## GameSettings.wander_music). Never hardcode any of these at the seam — a designer must be able to retune the
## exploration mood without touching code.
##
## WHAT MAKES IT STAND DOWN IS NOT HERE. That is one shared scan (scripts/audio/soundscape.gd) plus two
## published flags the other layers already raise (StationMusic.is_bed_wanted, DialogueManager.is_engaged), so
## the combat score and this bed can never disagree about whose moment it is.

@export_group("Playlist")
## The wandering tracks. ONE is picked each time the bed starts, never the same one twice in a row (with a
## single-track playlist that degrades to "always that track", which is fine).
## EMPTY (or every slot null) makes the whole layer inert: nothing plays, and every other audio layer behaves
## exactly as it did before this feature existed. That is deliberate — it is also the safe post-ATTRIBUTION-purge
## state, so replacing a placeholder track is a pure resource edit that can neither break the build nor need a
## code change.
@export var tracks: Array[AudioStream] = []
## Master off switch, so a designer can A/B the whole layer without emptying (and having to re-author) the playlist.
@export var enabled: bool = true

@export_group("Level")
## The audible level while you are wandering. WELL under the combat score's authored level (0 dB on the `music`
## bus in game.tscn) because this bed is meant to be noticed only if you listen for it — the brief was "quietly
## plays while exploring", and a wandering theme that competes with footsteps and city ambience is a wandering
## theme the player will turn off. A REASONED starting point, not a measured one: raise it if the bed disappears
## under the ambience bed, lower it if it pulls focus. It also stacks under every `music`-bus writer for free —
## the Options Music slider, the dialogue duck, the ADS duck, and the death cinematic's world duck.
@export var volume_db: float = -14.0
## The "off" floor the fades run to. The stream is stop()ed only once a fade-out actually LANDS here, so the
## tail is never cut dead mid-phrase.
@export var silent_db: float = -60.0
## Seconds silence -> level. LONG on purpose: the bed should seep in unnoticed, the way an exploration score
## does, rather than announcing itself. Contrast fade_out.
@export var fade_in: float = 4.0
## Seconds level -> silence when something else takes the moment. SHORT on purpose, and it MUST stay under
## MusicDirector.fade_in_time (1.2 s): both layers notice the change on the same 0.3 s poll, so if this bed
## takes longer to leave than the combat score takes to arrive, the two overlap at audible levels and a fight
## starts on a muddy chord instead of a hit. 0.8 s leaves a real margin under that ceiling while still being a
## fade rather than a cut — and at this bed's quiet level a fast exit is inaudible anyway.
## ⭐This shipped at 1.5 s, i.e. ABOVE the ceiling, and tests/test_wander_music.gd is what caught it. If you
## raise it, raise MusicDirector.fade_in_time too, or that test will (correctly) fail.
@export var fade_out: float = 0.8

@export_group("Pacing")
## Seconds of UNBROKEN calm required before the bed comes back after anything took the moment from it. Sized
## against the combat score's own tail: MusicDirector holds FULL for `combat_linger` (2.5 s) and then fades out
## over `fade_out` (3.0 s), so anything under ~5.5 s would start creeping in UNDERNEATH the fight breathing out.
## It also stops the bed flapping back on during the lull between two rooms of the same firefight.
@export var resume_delay: float = 6.0
## The SILENCE between tracks. A wandering bed that never stops is the fastest way to make a good piece of music
## hateful — real exploration scores play, then leave you alone with the room tone for a while. After a track
## plays through, the bed rests for a random span in [rest_seconds_min, rest_seconds_max] before picking again.
## Set BOTH to 0 for back-to-back playback (with a one-track playlist that is a loop with a hard restart at the
## downbeat); for a genuinely gapless loop, tick `continuous` below instead.
## The rest counts down in REAL seconds whether or not the bed is currently allowed to play, so a long firefight
## spends the silence for you rather than banking it.
@export var rest_seconds_min: float = 45.0
@export var rest_seconds_max: float = 120.0
## Ignore the rest window and loop the picked track seamlessly forever (until something takes the moment). The
## loop flag is FORCED at play time via LoopableStream, so this does not depend on anyone having ticked Loop in
## the Import dock. OFF by default — see rest_seconds_min.
@export var continuous: bool = false

@export_group("Routing")
## `music` — plain and full-range, unlike the station bed's tinny `station_music` or the diegetic radio's
## band-limited `radio`. This is SCORE, not a sound coming out of an object in the world, so it gets no filter
## and no 3D position. Sending into `music` is also what puts it under the Options Music slider and inherits
## every existing duck. A bus that does not exist degrades to `music` with a warning — never `sfx` (that would
## silently re-file a music bed under the Effects slider) and never Master (which escapes every slider AND the
## death-cinematic duck).
@export var bus: StringName = &"music"
