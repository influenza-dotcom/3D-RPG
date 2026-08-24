class_name StationMusicSettings
extends Resource

## The music a SELF-SERVE MACHINE plays out of its own panel speaker while its screen is awake — the shop
## counter, the ATM, the clinic kiosk, the trainer terminal. Read live by the StationMusic autoload
## (managers/StationMusic.gd); edit the values in the inspector on
## resources/tuning/StationMusicSettings.tres (reached from GameSettings.station_music). Never hardcode any
## of these at the seam — the whole point of this group is that a designer retunes the shop's radio without
## touching code.
##
## THE SET OF SCREENS IT PLAYS UNDER IS NOT HERE — it is one `station_music = true` flag per row of the
## modal registry in managers/InputManager.gd, beside `blocks_tabs`. That registry is the single place every
## "which screens count?" question is answered, and splitting the answer across two files is exactly the
## drift it exists to kill.

@export_group("Playlist")
## The shop themes. ONE is picked at random each time the bed starts, never the same one twice in a row.
## Loops are FORCED at play time (LoopableStream), so a track imported with Loop = Off still loops — you do
## not have to remember the Import dock.
## EMPTY (or every slot null) makes the whole layer inert: no bed, no tier flag, and every other audio layer
## behaves exactly as it did before this feature existed. That is deliberate — it is also the safe
## post-ATTRIBUTION-purge state, so replacing the placeholder tracks is a pure resource edit that can neither
## break the build nor need a code change.
@export var tracks: Array[AudioStream] = []
## Master off switch, so a designer can A/B the feature without emptying (and having to re-author) the playlist.
@export var enabled: bool = true

@export_group("Level")
## The audible level while a station screen is up. Sits under the authored clip level, because these are full
## commercial-loudness music tracks arriving on a bus whose parent (`music`) is at 0 dB, whereas the chirp's
## `speaker` bus feeds an `sfx` bus that is already ~6.6 dB down — same chain, different gain staging.
@export var volume_db: float = -6.0
## The "off" floor the fades run to. The stream is stop()ed only once a fade-out actually LANDS here, so the
## tail is never cut dead.
@export var silent_db: float = -60.0
## Seconds silence -> level. Short on purpose: the tune should arrive WITH the machine's StationSpeaker chirp
## so the two read as one event (the machine waking up), not as a sound and then, separately, some music.
@export var fade_in: float = 0.6
## Seconds level -> silence once you walk away.
@export var fade_out: float = 1.2
## Seconds the bed keeps playing at FULL level after the last station screen closes, before the fade-out
## starts. This is the "closed the shop, stepped to the ATM beside it" window: within it the bed never dips,
## so two back-to-back terminals are ONE continuous track instead of two stutters. Together with fade_out it
## is also the window in which re-opening keeps the SAME track at the SAME position instead of re-picking —
## the MusicDirector `combat_linger` idiom, applied to menus. 0 = fade the instant the last screen closes.
@export var hold_seconds: float = 3.0

@export_group("Routing")
## ⭐THE BUS IS THE TINNY SOUND. `station_music` clones the ATM chirp's speaker cone parameter-for-parameter
## (HighPass 900 Hz / resonance 0.7 -> Distortion LOFI drive 0.25 -> LowPass 4200 Hz) but SENDS INTO `music`
## rather than `sfx`, so the Options **Music** slider governs it — a 90-second loop is music by every
## definition that menu uses, and a player who pulls Music to 0 to run their own playlist must not still hear
## shop themes. Sending into `music` also inherits the dialogue duck, the ADS duck and the death-cinematic
## world duck for free. Point it at `sfx` for a clean, expensive-sounding machine, or at `speaker` to share
## the chirp's exact bus (and its Effects-slider fate). A bus that does not exist degrades to `music` with a
## warning — never `sfx` (that would silently re-categorise a music bed) and never Master (which escapes
## every slider AND the death duck).
@export var bus: StringName = &"station_music"
