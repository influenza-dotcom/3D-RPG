class_name DialogueSettings
extends Resource

## Tuning for the conversation FLOW + presentation feel: the pre-talk pacing (NPC turn + buffer beat),
## the dialogue intro delay + speaker face-turn, the cinematic letterbox bars, the music duck while a
## conversation is up, the dialogue music bed + its talk duck, the face light, and the dialogue box's layout
## (panel margins, font sizes, label offsets). Consumed by DialogueManager / DialogueView / MusicDucker /
## DialogueMusicBed / DialogueFaceLight / DialogueNPC / Talkable / TalkApproach via GameSettings.dialogue.
## Pure pacing/feel/presentation — no logic depends on the exact values.

@export_group("Pacing")
## Seconds for an NPC to rotate to face the player when talked to — the "turns to face you" beat. Higher = a slower, more deliberate turn.
@export var npc_turn_to_face_duration: float = 0.35
## Beat (seconds) between the interact press and the NPC beginning to speak — it "gathers" first, so talking PROMPTS a response rather than instantly forcing the box open. Higher = a longer pause before speech.
@export var talk_prompt_buffer_duration: float = 0.4
## Delay (seconds) after interacting before the first line opens, so the NPC turn / camera swing finishes before the box appears. Higher = a longer cinematic intro beat.
@export var dialogue_intro_delay: float = 0.5
## Seconds for the speaker to turn and face the player as the box opens — timed to land within the intro delay. Higher = a slower face-turn.
@export var dialogue_speaker_face_duration: float = 0.3

@export_group("Auto-advance")
## Auto-continue to the next line when the current one finishes speaking (New Vegas style) instead of waiting for a click. The player can still click to skip ahead; the response menu still waits for input. Off = click every line.
@export var auto_advance: bool = true
## Estimated speaking time PER CHARACTER (seconds) for text-only fallback timing and talking head-bob / mouth-flap. TTS-enabled dialogue auto-advances from the generated audio completion instead.
@export var auto_advance_seconds_per_char: float = 0.07
## Floor (seconds) on a line's spoken time, so a very short line still reads/animates briefly.
@export var auto_advance_min_seconds: float = 1.6
## Cap (seconds) on estimated text-only spoken time and talking animation; real TTS audio is not capped.
@export var auto_advance_max_seconds: float = 9.0

@export_group("Letterbox")
## Each cinematic letterbox bar's height as a fraction of screen height — the top/bottom black bars during dialogue. Higher = thicker bars (more cinematic crop).
@export var letterbox_bar_height_fraction: float = 0.12
## Seconds for the letterbox bars to slide in/out — also the window the camera uses to time its dialogue zoom. Higher = a slower slide.
@export var letterbox_slide_in_duration: float = 0.4

@export_group("Music Duck")
## How far (dB) the music bus drops while a conversation is up — the cinematic quieting. More negative = quieter; 0 = no duck.
@export var music_duck_amount_db: float = -12.0
## Fade time (seconds) for the music duck down / restore up — higher = a slower, smoother dip.
@export var music_duck_fade_duration: float = 0.4

@export_group("Dialogue Music")
## A looping music bed played UNDER every conversation (fades in as the box opens, out when it ends), driven by
## the DialogueMusicBed child of DialogueManager. EMPTY = no bed, the old behaviour (conversations play dry).
## Any track works: the bed FORCES the loop flag on its own copy at runtime, so a .wav imported with Loop Mode
## Disabled still loops seamlessly. Setting the import correctly (a .wav's Loop Mode = Forward, an .mp3/.ogg's
## Loop tick) just skips that copy.
@export var dialogue_music: AudioStream = null
## Level (dB) of the dialogue music bed. NOTE: it plays on the bus below (default "music"), so the cinematic
## music_duck_amount_db dip ALSO applies to it while a conversation is up — a constant offset here, since the bed
## only ever plays during a conversation. Tune this by ear; changing the duck amount shifts this bed too.
@export var dialogue_music_volume_db: float = 0.0
## How far (dB) the bed dips BELOW dialogue_music_volume_db while a line is actually being SPOKEN — a slight
## extra duck that seats the loop under the voice, swelling back while the player reads the response menu (and
## once the spoken estimate elapses). More negative = a deeper dip; 0 = no talk duck (the bed holds one level
## for the whole conversation, the pre-duck behaviour).
@export var dialogue_music_talk_duck_db: float = -4.0
## Fade time (seconds) for the talk duck's dip down / swell back. Higher = a smoother, lazier dip.
@export var dialogue_music_talk_duck_fade: float = 0.25
## How far (dB) the conversation's bed steps aside while a STATION TERMINAL's own radio is playing — i.e. a
## dialogue-hosted Trade / Heal / Level Up / Install / Chess / Bank menu, driven by the StationMusic autoload.
## -60 (the default) is a FULL handover: you hear the machine's tinny bed alone, and the conversation's loop
## swells back when the sub-menu closes. Set about -8 to layer the two instead, or 0 to disable the handover
## and hear both at their authored levels. A positive value is clamped to 0 — a duck only ever pulls down.
@export var dialogue_music_menu_duck_db: float = -60.0
## Fade time (seconds) for the station-terminal handover down / swell back. Longer than the talk duck on
## purpose: this is a scene change between two music layers, not a dip under one spoken line.
@export var dialogue_music_menu_duck_fade: float = 0.8
## Fade time (seconds) from silence up to level as the conversation opens. Higher = a slower swell.
@export var dialogue_music_fade_in: float = 0.6
## Fade time (seconds) back down to silence as the conversation ends (the bed stops once it lands). Higher = a longer tail.
@export var dialogue_music_fade_out: float = 0.8
## Audio bus for the bed. "music" (default) is almost always right — it rides the Options Music volume slider and
## the dialogue duck. Bus routing is load-bearing: put it on "sfx" and the Music slider stops governing it.
@export var dialogue_music_bus: StringName = &"music"

@export_group("Text Panel")
## Left/right margin (px) of the bottom dialogue panel from the screen edges — bigger = a narrower, more inset box.
@export var panel_horizontal_margin: int = 80
## Bottom inset (px) of the dialogue panel from the screen edge — how far up off the bottom the box sits.
@export var panel_vertical_margin: int = 40
## Inner padding (px) on all sides between the panel edge and its text — the text's breathing room.
@export var panel_inner_padding: int = 16
## Vertical spacing (px) between the line text, the choices, and the continue hint inside the box.
@export var panel_vertical_element_spacing: int = 8
## Font size (px) of the spoken line text. Bigger = more readable, fewer words per line.
@export var dialogue_text_font_size: int = 18
## Outline width (px) on the line text. Load-bearing when the skin leaves MenuSkin.dialogue_panel empty —
## the box then has NO background and the line reads straight against the world. 0 = no outline.
@export var dialogue_text_outline_width: int = 6
## Fill colour of the spoken line text. Never the menu theme's text_color: that is PANEL ink and runs dark
## (the 08-12 plum palette), while this line either floats over the 3D WORLD inside its black outline
## (no dialogue_panel art) or sits on the artist's mid-dark olive box (with it) — light reads on both.
@export var dialogue_text_color: Color = Color(0.92, 0.92, 0.95)

@export_group("Choices")
## Font size (px) of the choice buttons (authored options + the synthesized Trade/Heal/Goodbye affordances).
@export var choice_button_font_size: int = 16
## Vertical spacing (px) between stacked choice buttons.
@export var choice_button_spacing: int = 6
## Max height of the scrollable choices area as a fraction of screen height — a many-option line SCROLLS past this instead of growing off the top. Higher = a taller menu before it scrolls.
@export var choices_scroll_max_height_fraction: float = 0.55
## Font size (px) of the "[F] / click to continue" hint (kept smaller than the choices for hierarchy).
@export var dialogue_continue_hint_font_size: int = 13
## Opacity (0..1) of the continue hint — deemphasized so it doesn't compete with the line. 1 = fully opaque.
@export var dialogue_continue_hint_opacity: float = 0.55

@export_group("Face Light")
## Key a soft light onto the face of the NPC you're talking to so it stays readable in a dark scene; it fades in as
## the conversation opens, then sits STATIC on the face (placed once, it doesn't follow the head-look), and fades out
## when it ends. Off = no face light.
@export var face_light_enabled: bool = true
## Peak brightness (energy) of the face key light at full fade-in. Higher = a brighter, more lit face.
@export var face_light_energy: float = 3.0
## Colour of the face light — a warm off-white reads as a soft key light; pure white is neutral.
@export var face_light_color: Color = Color(1.0, 0.96, 0.88)
## Spotlight cone angle (degrees, half-angle) — how wide the pool of light on the face is. Narrower = a tighter key.
@export var face_light_spot_angle: float = 32.0
## How far (m) the light sits IN FRONT of the face (toward the player, the side you see) before aiming back at it.
@export var face_light_distance: float = 1.2
## How far (m) ABOVE the face the light is raised, so it keys down at a slight angle instead of dead-on flat.
@export var face_light_height: float = 0.35
## Max throw (m) of the spotlight past the face — keeps the pool local to the NPC instead of lighting the whole room.
@export var face_light_range: float = 4.0
## How fast the light fades in/out as the conversation starts/ends (exponential rate; higher = snappier).
@export var face_light_fade_speed: float = 6.0

@export_group("Speaker Name")
## Font size (px) of the top-left speaker name label (Fallout-style). Bigger = a more prominent name.
@export var speaker_name_font_size: int = 26
## Outline width (px) on the speaker name so it reads against the letterbox bar / world. 0 = no outline.
@export var speaker_name_outline_width: int = 6
## Left screen offset (px) of the speaker name label from the top-left corner.
@export var speaker_name_screen_x_offset: int = 32
## Top screen offset (px) of the speaker name label from the top edge (clear of the letterbox bar).
@export var speaker_name_screen_y_offset: int = 60
