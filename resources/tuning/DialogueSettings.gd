class_name DialogueSettings
extends Resource

## Tuning for the conversation FLOW + presentation feel: the pre-talk pacing (NPC turn + buffer beat),
## the dialogue intro delay + speaker face-turn, the cinematic letterbox bars, and the music duck while a
## conversation is up. Consumed by TalkHelpers / DialogueManager / DialogueView / MusicDucker via
## GameSettings.dialogue. Pure pacing/feel — no logic depends on the exact values. (The dialogue box's
## font sizes / panel margins / label offsets are still inline in dialogue_view.gd; not yet migrated.)

@export_group("Pacing")
## Seconds for an NPC to rotate to face the player when talked to — the "turns to face you" beat. Higher = a slower, more deliberate turn.
@export var npc_turn_to_face_duration: float = 0.35
## Beat (seconds) between the interact press and the NPC beginning to speak — it "gathers" first, so talking PROMPTS a response rather than instantly forcing the box open. Higher = a longer pause before speech.
@export var talk_prompt_buffer_duration: float = 0.4
## Delay (seconds) after interacting before the first line opens, so the NPC turn / camera swing finishes before the box appears. Higher = a longer cinematic intro beat.
@export var dialogue_intro_delay: float = 0.5
## Seconds for the speaker to turn and face the player as the box opens — timed to land within the intro delay. Higher = a slower face-turn.
@export var dialogue_speaker_face_duration: float = 0.3

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
