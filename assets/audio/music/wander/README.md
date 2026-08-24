# Wandering (exploration) music

Drop exploration tracks here, then add them to **Tracks** on
`res://resources/tuning/WanderMusicSettings.tres`. Until that array has something in it the whole
wandering-bed layer is inert by design - nothing plays, and every other audio layer behaves exactly as it
did before the feature existed. See `docs/AUTHORING_GUIDE.md` section 1e.

## Why this subfolder exists (load-bearing, not tidiness)

`Radio.music_folder` defaults to `res://assets/audio/music` and `Radio._scan_audio_folder` walks it with a
**non-recursive** `dir.get_files()`. A track left FLAT in `music/` is therefore picked up by every in-world
radio and every thrown radio-grenade, which is not what an exploration cue is for. The station shop themes
live in `music/station/` for exactly the same reason.

`tests/test_wander_music.gd` asserts every authored wandering track resolves to this directory - that check
passes vacuously while the playlist is empty and re-arms the moment you author one.
