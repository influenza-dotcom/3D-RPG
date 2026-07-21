@tool
class_name TutorialPrompt
extends TriggerVolume

## A drop-in TUTORIAL TOOLTIP volume — walk into it and a one-time prompt teaches a verb, with LIVE key labels
## so it always shows the player's CURRENT binding. It shows ONCE and remembers that across saves via a
## persistent flag: re-entering, reloading, or a fresh session never repeats a prompt already seen.
##
## Write {action} tokens into the message and each is replaced with the key currently bound to that input action:
## "Press {interact} to open doors" -> "Press [E] to open doors" (and it updates if the player rebinds). Unknown
## actions render as "(none)".
##
## Subclasses TriggerVolume, so every base action (set_flag, audio, start_dialogue, quest hooks) still fires
## alongside the prompt if you also configure them. INERT until you set prompt_text.
##
## SETUP: drop it where the player first needs the verb, size its CollisionShape3D, set prompt_text (with
## {action} tokens) and a UNIQUE seen_flag.

## The tutorial text shown on entry. {action} tokens (e.g. {interact}, {jump}) are replaced with the live bound
## key. Multi-line is fine. Empty = nothing is taught (inert).
@export_multiline var prompt_text: String = ""
## Colour of the prompt toast.
@export var prompt_color: Color = Color(0.85, 0.95, 1.0)
## Persistent "already shown" flag (GameState). Once shown, this is set so the prompt never repeats — across
## re-entry, reload, and new sessions. Blank = NON-persistent (shows on every entry). Give each prompt a UNIQUE flag.
@export var seen_flag: StringName = &""

## Fire the tutorial: skip entirely if already shown, else run the base TriggerVolume actions, show the prompt
## with live key labels, and mark it seen (persisted). Overrides TriggerVolume.fire.
func fire(activator: Node) -> void:
	if _already_seen():
		return  # shown in a prior entry/session — never repeat
	super.fire(activator)  # any base actions the designer also configured (set_flag, audio, dialogue, quest)
	if not prompt_text.is_empty():
		UI.toast(_resolve_keys(prompt_text), prompt_color)
	if seen_flag != &"":
		GameState.set_flag(seen_flag, true)  # persisted -> survives a save/reload, so the prompt shows exactly once

## Whether this prompt's persistent seen_flag is already set (so it must not show again). Pure + testable.
## A blank seen_flag is never "seen" (a deliberately repeating reminder).
func _already_seen() -> bool:
	return seen_flag != &"" and GameState.get_flag_bool(seen_flag, false)

## Replace each {action} token in `text` with the key currently bound to that input action
## (InputManager.get_action_binding). Pure (no tree) — text with no tokens returns unchanged.
func _resolve_keys(text: String) -> String:
	var re := RegEx.new()
	re.compile("\\{([A-Za-z0-9_]+)\\}")
	var result := ""
	var last := 0
	for m in re.search_all(text):
		result += text.substr(last, m.get_start() - last)
		result += InputManager.get_action_binding(StringName(m.get_string(1)))
		last = m.get_end()
	result += text.substr(last)
	return result

func _get_configuration_warnings() -> PackedStringArray:
	var w := super._get_configuration_warnings()
	if prompt_text.is_empty():
		w.append("TutorialPrompt has no prompt_text — it teaches nothing. Set the message (use {action} for live key labels).")
	if seen_flag == &"":
		w.append("seen_flag is empty — this prompt repeats on EVERY entry. Give it a unique flag to show once and persist across saves.")
	return w
