@tool
class_name Readable
extends LookAtInteractable

## Aim-and-press READABLE — a note / sign / datapad / terminal. On Interact it shows `text` through the existing
## dialogue UI (paginated into pages on blank lines), titled `title`. The FIRST read can optionally set a story
## flag, advance a quest objective, and/or grant XP — so lore discovery pays off. Environmental storytelling
## without an NPC. Inert (warns) with no text.
##
## SETUP: attach to an Area3D over a note / terminal / sign mesh (add a CollisionShape3D, or enable
## auto_fit_collider), then type the body into `text`. PickupRay sees it via the LookAtInteractable base.

signal was_read(activator: Node)

## The source name shown while reading (the dialogue "speaker" name). e.g. "Terminal", "Scrawled note", "Sign".
@export var title: String = "Note"
## The note body (multiline). Split into pages on BLANK LINES, so a long note paginates through the dialogue box.
@export_multiline var text: String = ""
## Hover label shown while aimed at it.
@export var verb: String = "Read"

@export_group("First-read reward (once)")
## Set this story flag the FIRST time it's read (e.g. "read_intro_note"). Empty = none.
@export var set_flag_on_read: StringName = &""
## Advance objective `advance_objective_id` of quest `advance_quest_id` on first read. BOTH are needed.
@export var advance_quest_id: StringName = &""
@export var advance_objective_id: StringName = &""
## Grant this much XP the first time it's read (lore discovery). 0 = none.
@export var xp_on_read: float = 0.0

var _has_read: bool = false  ## first-read latch for the one-time reward

func _ready() -> void:
	if Engine.is_editor_hint():
		_editor_fit_hitbox()  # @tool: preview the auto-fit hitbox in-editor; no runtime wiring
		return
	super()  # LookAtInteractable: talk-layer hitbox + look-at outline

## Interact pressed while aimed at us: show the note through the dialogue UI, then (first time only) pay out.
func start_talk(player: Node) -> void:
	if text.strip_edges() == "":
		return
	DialogueManager.start(_build_pages(), null, null, title)
	if not _has_read:
		_has_read = true
		_grant_first_read(player)
	was_read.emit(player)

## A transient one-conversation DialogueResource from `text` — one DialogueLine per blank-line-separated paragraph
## so a long note paginates (advance with the same key as dialogue). Pure, so it's unit-testable.
func _build_pages() -> DialogueResource:
	var res := DialogueResource.new()
	var normalized := text.replace("\r\n", "\n").replace("\r", "\n")  # so blank-line paging works on CRLF text too
	for p in normalized.split("\n\n", false):  # blank line = page break
		var s := p.strip_edges()
		if s == "":
			continue  # a whitespace-only separator chunk — don't emit a blank page mid-note
		var line := DialogueLine.new()
		line.text = s
		res.lines.append(line)
	if res.lines.is_empty():
		var line := DialogueLine.new()  # whole-note fallback (start_talk already guards the all-blank case)
		line.text = normalized.strip_edges()
		res.lines.append(line)
	return res

func _grant_first_read(player: Node) -> void:
	if set_flag_on_read != &"":
		GameState.set_flag(set_flag_on_read)
	if advance_quest_id != &"" and advance_objective_id != &"":
		GameState.advance_objective(advance_quest_id, advance_objective_id)
	if xp_on_read > 0.0 and player != null and player.has_method(&"add_xp"):
		player.add_xp(xp_on_read)

func look_name() -> String:
	return verb

func _get_configuration_warnings() -> PackedStringArray:
	var w := PackedStringArray()
	if text.strip_edges() == "":
		w.append("Readable has no `text` — it does nothing when read. Type the note body into `text`.")
	if (advance_quest_id != &"") != (advance_objective_id != &""):
		w.append("First-read quest advance needs BOTH `advance_quest_id` and `advance_objective_id` — one is set without the other.")
	return w
