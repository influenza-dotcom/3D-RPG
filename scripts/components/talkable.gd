@tool
class_name Talkable
extends Area3D


## A reusable "this thing can be spoken to" component. Drop talkable.tscn (an Area3D + a
## CollisionShape3D sized to the thing's body) under ANY node that has a mesh -- a friendly
## villager, an enemy you can parley with, or an inanimate object you "interface" with (a
## car, a terminal, a vending machine).
##
## It works as a LOOK-AT target, not a proximity trigger: the component sits on the dedicated
## talk physics layer, and the player's interaction ray (ray_cast.gd) detects it when aimed at.
## The ray highlights the host while you look, and pressing the interact key (E / PickUp) turns
## the host to face you (if turn_to_face) and starts `dialogue` through DialogueManager. Looking
## decides WHICH target you talk to, so two NPCs in the same spot are no longer ambiguous.
##
## SETUP: instance talkable.tscn as a child of the NPC, assign a DialogueResource to `dialogue`,
## and size the CollisionShape3D to roughly cover the body you aim at. The outline + turn apply
## to `highlight_target` (defaults to this component's parent).

@export_group("Dialogue")
## The conversation that opens when the player interacts. Leave unset and this host can't be talked to.
@export var dialogue: DialogueResource:
	set(value):
		dialogue = value
		update_configuration_warnings()
## OPTIONAL: pick the conversation by world state (flags / quests) instead of the single `dialogue` above — the
## first matching DialogueSelector row wins, else its default. When set, it OVERRIDES `dialogue`.
@export var dialogue_selector: DialogueSelector:
	set(value):
		dialogue_selector = value
		update_configuration_warnings()
@export var voice: VoiceData  ## how the OS text-to-speech reads this NPC's lines (optional)
## Speaker name for the dialogue box. Leave blank to use the host's NPC display_name (so a talkable
## NPC is named once, on the NPC); set it to name an inanimate host (a car, terminal, sign).
@export var display_name: String = ""

@export_group("Look-At Highlight")
## Node whose MeshInstance3D descendants get the white outline + the turn. Null -> our parent.
@export var highlight_target: Node3D
## Colour of the look-at outline drawn over the host while you aim at it. Default white.
@export var highlight_color: Color = Color(1.0, 1.0, 1.0, 1.0)
## Thickness of that look-at outline (shader units). Higher = bolder outline.
@export var highlight_width: float = 1.0

@export_group("Interaction")
## Characters should rotate to face the player on talk; leave off for inanimate objects.
@export var turn_to_face: bool = true

var _outline_mat: ShaderMaterial
var _meshes: Array[MeshInstance3D] = []
var _meshes_collected: bool = false  ## gathered lazily on first highlight (the NPC head attaches after our _ready)

func _ready() -> void:
	if Engine.is_editor_hint():
		return  # @tool: in the editor we only evaluate _get_configuration_warnings, never the runtime hitbox setup
	# Become a look-at hitbox: sit on the talk layer so the interaction ray can hit us, and
	# detect nothing ourselves (mask 0 -- we're aimed at, we don't sense bodies).
	collision_layer = TalkHelpers.TALK_LAYER
	collision_mask = 0
	_outline_mat = TalkHelpers.make_outline_material(highlight_color, highlight_width)
	# Meshes are gathered LAZILY on first highlight (see _ensure_meshes), NOT here: an NPC's modular head is
	# attached in NPC._ready, which runs AFTER this child component's _ready, so collecting now would miss it.

## Editor warning: a Talkable with no `dialogue` AND a non-NPC host does nothing — an inanimate host
## (car / terminal / sign) needs a DialogueResource to be interfaced with. A dialogue-less Talkable on an
## NPC is intentionally allowed: it still enables crouch-pickpocketing (see start_talk), so we don't warn there.
func _get_configuration_warnings() -> PackedStringArray:
	if dialogue == null and dialogue_selector == null and (_host() as NPC) == null:
		return PackedStringArray([
			"No `dialogue` assigned and the host isn't an NPC — this Talkable does nothing. Assign a DialogueResource so the host can be talked to / interfaced with."
		])
	return PackedStringArray()

## The node this component represents (highlight + turn target): the configured target, else
## our parent (the node we sit under).
func _host() -> Node3D:
	if highlight_target != null:
		return highlight_target
	return get_parent() as Node3D

## Whether this host has ANY conversation to offer — a direct `dialogue` or a `dialogue_selector`.
func _has_dialogue() -> bool:
	return dialogue != null or dialogue_selector != null

## The conversation to actually open right now: the selector's pick (by world state) if one's assigned, else
## the single `dialogue`. May be null (a selector whose rows don't match and that has no default).
func _dialogue() -> DialogueResource:
	return dialogue_selector.pick() if dialogue_selector != null else dialogue

## The player may only talk to a non-hostile host that ISN'T mid-fight — a hostile NPC won't parley,
## and a busy-fighting one only fights (it doesn't talk). The ray reads this via TalkHelpers.is_talkable_now
## to drop the look-at highlight AND refuse the interact, so a fighting/hostile enemy shows no talk cue.
## An inanimate host (no NPC) is always talkable, so a car / terminal under a Talkable is unaffected.
func can_be_talked_to() -> bool:
	var npc := _host() as NPC
	return npc == null or (not npc.is_hostile() and not npc.is_in_combat())

## Whether `player` can PICKPOCKET this host right now: crouched, and the host is an off-guard NPC (hasn't
## locked onto a threat). Offered EVEN on a hostile NPC — unlike can_be_talked_to, which refuses one — so the
## interaction ray lets you lift an unaware enemy's pockets. Resolves to _can_pickpocket (the same test
## start_talk uses), so the highlight/prompt and the actual interact always agree on what Interact will do.
func can_pickpocket(player: Node) -> bool:
	var npc := _host() as NPC
	return npc != null and _can_pickpocket(player, npc)

## Toggled by the interaction ray as the player's aim enters/leaves this target.
func set_look_highlight(on: bool) -> void:
	_ensure_meshes()
	TalkHelpers.set_overlay(_meshes, _outline_mat if on else null)

## Gather the host's MeshInstance3D descendants ONCE, on first highlight. Deferred from _ready so an NPC's
## runtime-attached modular head (added in NPC._ready, AFTER this child readies) is included — fixing the
## white talk-highlight outlining only the body, not the head.
func _ensure_meshes() -> void:
	if _meshes_collected:
		return
	_meshes_collected = true
	var host := _host()
	if host != null:
		_meshes = TalkHelpers.collect_meshes(host, self)

## The name to show on the look-at hover readout — this component's display_name, else the host NPC's. Masked to
## "Stranger" until introduced when the host is a real NPC (GameState.public_name), so an un-met person reads
## "Talk to Stranger" / "Pick Pocket Stranger"; an inanimate host (car / terminal / sign) is shown outright.
func look_name() -> String:
	var raw := TalkHelpers.speaker_name(display_name, _host())
	return GameState.public_name(raw) if _host() is NPC else raw

## The look-at readout label for whoever is looking. Reads "Pick Pocket <name>" when this host can be
## PICKPOCKETED by `player` right now (crouched + the NPC off-guard — the SAME test start_talk uses);
## "Talk to <name>" when it's an NPC you can actually converse with (non-hostile, out of combat, and it
## has dialogue); otherwise the bare speaker name.
## A HOSTILE NPC you HAVEN'T been introduced to is an anonymous threat: its name is HIDDEN entirely (empty
## readout — the ray shows nothing under the crosshair). If it's still pickpocketable the verb alone shows
## ("Pick Pocket", no name). Once introduced (its name revealed in dialogue) a hostile NPC reads out its real
## name again — you now know who's shooting at you.
func look_name_for(player: Node) -> String:
	var npc := _host() as NPC
	var hostile_stranger := npc != null and npc.is_hostile() \
		and not GameState.name_is_revealed(TalkHelpers.speaker_name(display_name, npc))
	if npc != null and _can_pickpocket(player, npc):
		return PlayerText.pick_pocket("" if hostile_stranger else look_name())
	if hostile_stranger:
		return ""
	var label := look_name()
	if npc != null and _has_dialogue() and can_be_talked_to() and not label.is_empty():
		return PlayerText.talk_to(label)
	return label

## The NPC this represents (for a hover greeting), or null for an inanimate host (car / terminal / sign).
func host_npc() -> NPC:
	return _host() as NPC

## Called by the interaction ray when the player presses interact while aimed at us. Talking is a
## PROMPT, not a force: an NPC host acknowledges, walks into framing range, then speaks after a short
## buffer (prompt_talk -> _begin_dialogue); a busy-fighting NPC ignores the request entirely; an
## inanimate host (a car, terminal) keeps the old immediate behaviour via the fallback path.
func start_talk(player: Node3D) -> void:
	var host := _host()
	var npc := host as NPC
	# Pickpocket: a crouched player interacting with an NPC that's unaware (off-guard) lifts their pockets
	# instead of talking — opens the loot transfer on the LIVE NPC's inventory.
	if npc != null and _can_pickpocket(player, npc):
		LootScreen.pickpocket(npc, player)
		return
	if not _has_dialogue():
		return
	if npc != null and npc.is_in_combat():
		return  # fighting NPC: it only fights, it doesn't talk — drop the request, no dialogue
	if npc != null and npc.has_method(&"prompt_talk") and not npc.is_hostile():
		# Hand the NPC the cue and let IT decide when to speak: it turns + walks into frame itself
		# (so we must NOT also face_player here — that would fight the approach), then opens dialogue.
		# The camera focus + zoom now fire in _begin_dialogue (with the letterbox bars), NOT here, so the
		# cinematic only begins once the NPC has actually walked into frame and starts speaking.
		npc.prompt_talk(player, _begin_dialogue.bind(host, player))
	else:
		# Inanimate / non-NPC host (or a hostile one slipping past the ray): turn in place, then begin
		# after the same buffer beat so the camera swing / turn read before the box opens.
		if turn_to_face and player != null and host != null:
			TalkHelpers.face_player(host, player, GameSettings.dialogue.npc_turn_to_face_duration)
		await get_tree().create_timer(GameSettings.dialogue.talk_prompt_buffer_duration).timeout
		_begin_dialogue(host, player)

## Pickpocketable when the player is CROUCHED (sneaking) AND this NPC is OFF-GUARD (hasn't locked onto a
## threat — see NPC.is_off_guard). The interaction ray already refuses hostile / in-combat NPCs via
## can_be_talked_to, so only calm, unaware NPCs ever reach here.
func _can_pickpocket(player: Node, npc: NPC) -> bool:
	if player == null or not player.has_method(&"is_crouching") or not player.is_crouching():
		return false
	# One strike: if the player was CAUGHT lifting this NPC's pockets before, it never lets them back in — even
	# after it calms down / is forgiven (NPC.pickpocket_allowed latches false in LootScreen._on_pickpocket_caught).
	if not npc.pickpocket_allowed():
		return false
	# A NON-hostile NPC (friendly / neutral) never guards against YOU, so crouch-sneaking alone is enough to
	# lift its pockets. A HOSTILE one is only pickpocketable while it hasn't locked onto you (off-guard) —
	# once it's fighting you (ALERTED) there are no more idle hands to reach past.
	if not npc.is_hostile():
		return true
	return npc.is_off_guard()

## Open the actual conversation. Deferred until the NPC has acknowledged + walked into frame (or the
## fallback buffer elapsed). Guards against the component being freed mid-buffer (scene reload / death),
## a dialogue cleared since the prompt, and the HOST dying inside that buffer. Passes the host as speaker
## so DialogueManager freezes it, plus the resolved speaker name (this component's display_name, else the
## host NPC's).
func _begin_dialogue(host: Node3D, player: Node3D) -> void:
	var convo := _dialogue()
	if not is_instance_valid(self) or convo == null:
		return
	# Buffered-open window: prompt_talk's in-range shortcut arms a TREE-owned SceneTreeTimer, so this
	# delivery still lands after the host was KILLED in the beat (the death freeze only disables the body's
	# process_mode — the timer fires regardless). A dead host must not open a conversation: DialogueManager.start
	# would fire GameState.notify_talk and complete a TALK objective on the corpse. is_instance_valid runs
	# FIRST (`as`/`is` on a freed instance crashes); a non-Character host (car / terminal) can't be dead and
	# passes through — the same duck-tolerant liveness rule as NpcTargeting._is_live.
	if not is_instance_valid(host):
		return
	var character := host as Character  # null for an inanimate host -> nothing to be dead
	if character != null and not character.is_alive():
		return
	# Swing + zoom the player's camera onto the speaker AS the box opens, so the focus/zoom land
	# together with the letterbox bars (DialogueManager.start) — not back when the player interacted.
	if is_instance_valid(player) and player.has_method(&"focus_camera_on"):
		player.focus_camera_on(global_position)
	DialogueManager.start(convo, host, voice, TalkHelpers.speaker_name(display_name, host))
