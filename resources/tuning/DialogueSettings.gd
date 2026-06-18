class_name DialogueSettings
extends Resource

## Tuning for the conversation FLOW + presentation feel: the pre-talk pacing (NPC turn + buffer beat),
## the dialogue intro delay + speaker face-turn, the cinematic letterbox bars, the music duck while a
## conversation is up, and the dialogue box's layout (panel margins, font sizes, label offsets). Consumed by
## TalkHelpers / DialogueManager / DialogueView / MusicDucker via GameSettings.dialogue. Pure pacing/feel/
## presentation — no logic depends on the exact values.

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
## Estimated speaking time PER CHARACTER (seconds) — how long a line is "spoken" before it auto-advances AND how long the talking head-bob / mouth-flap runs. Tune to match the TTS pace (~0.07 ≈ 14 chars/sec). Higher = slower delivery.
@export var auto_advance_seconds_per_char: float = 0.07
## Floor (seconds) on a line's spoken time, so a very short line still reads/animates briefly.
@export var auto_advance_min_seconds: float = 1.6
## Cap (seconds) on a line's spoken time, so a very long line doesn't stall.
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
## Outline width (px) on the line text so it reads against the world (the panel has no background). 0 = no outline.
@export var dialogue_text_outline_width: int = 6

@export_group("Choices")
## Font size (px) of the choice buttons (authored options + the synthesized Trade/Heal/Goodbye affordances).
@export var choice_button_font_size: int = 16
## Vertical spacing (px) between stacked choice buttons.
@export var choice_button_spacing: int = 6
## Max height of the scrollable choices area as a fraction of screen height — a many-option line SCROLLS past this instead of growing off the top. Higher = a taller menu before it scrolls.
@export var choices_scroll_max_height_fraction: float = 0.55
## Font size (px) of the "[E] / click to continue" hint (kept smaller than the choices for hierarchy).
@export var dialogue_continue_hint_font_size: int = 13
## Opacity (0..1) of the continue hint — deemphasized so it doesn't compete with the line. 1 = fully opaque.
@export var dialogue_continue_hint_opacity: float = 0.55

@export_group("Speaker Name")
## Font size (px) of the top-left speaker name label (Fallout-style). Bigger = a more prominent name.
@export var speaker_name_font_size: int = 26
## Outline width (px) on the speaker name so it reads against the letterbox bar / world. 0 = no outline.
@export var speaker_name_outline_width: int = 6
## Left screen offset (px) of the speaker name label from the top-left corner.
@export var speaker_name_screen_x_offset: int = 32
## Top screen offset (px) of the speaker name label from the top edge (clear of the letterbox bar).
@export var speaker_name_screen_y_offset: int = 60
