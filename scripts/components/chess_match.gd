@tool
class_name ChessMatch
extends LookAtInteractable


## Drop-in MINIGAME component: an NPC (or a table / terminal) you can sit down and play BLINDFOLD CHESS against.
## Moves are typed as text in the ChessScreen — a rendered board only appears once the player installs the Board
## Visualizer chip (Player.has_mechanic(&"chess_visualizer")). The opponent is a ChessAi tuned by the exports
## below, so a back-alley hustler and a grandmaster are the same component with different `ai_depth`.
##
## Two ways to use it, exactly like ChipInstaller / Merchant:
##   1. STANDALONE (a lone chess table, or an NPC with no Talkable): leave `standalone` on (default) — it sits on
##      the talk layer, so aiming at it and pressing Interact opens the match directly.
##   2. ON A DIALOGUE NPC: set `standalone` = false so the ray IGNORES it (the NPC's Talkable drives the
##      conversation); the dialogue then offers a "Play Chess" option that opens THIS match (open_match).
##
## DUCK-TYPED SURFACE: DialogueManager finds this by `opponent_name` + `ai_search_depth` (see _speaker_chess in
## dialogue_manager.gd), and ChessScreen reads its config through the same getters — Node-typed on both sides to
## avoid a ChessMatch <-> ChessScreen <-> DialogueManager class-compile cycle. A rename here silently drops the
## dialogue option, so the pairing is pinned by tests/test_dialogue_speaker_contracts.gd.
##
## SETUP: drop it under the opponent (or assign highlight_target), size its CollisionShape3D (or set
## auto_fit_collider), and tune the exports. For a dialogue NPC, set `standalone` = false and wire nothing else —
## the "Play Chess" option appears automatically.

@export_group("Opponent")
## Shown on the look-at hover, the match title, and (as the speaker) in the move log. Blank -> just "Opponent".
@export var opponent_name: String = ""
## Search depth in plies for the ChessAi. 1 = only sees immediate captures (a pushover); 2 = a solid club player;
## 3+ = sharp but slower to move. Each extra ply multiplies think time, so keep it modest for snappy turns.
@export_range(1, 4) var ai_depth: int = 2
## Probability (0..1) the opponent throws a move away and plays randomly — the "human" knob. Higher = more
## blunders = easier + more characterful (a drunk at 0.4 hangs pieces; a master at 0.0 never slips).
@export_range(0.0, 1.0, 0.05) var ai_blunder_chance: float = 0.15
## When true the PLAYER is White and opens the game; false = the opponent is White and moves first (the player
## replies blindfold to an opening move, the harder, hustler-favoured way to start).
@export var player_plays_white: bool = true

@export_group("Stakes")
## Zorkmids staked on the game. On a win the player GAINS this, on a loss LOSES it, a draw is even. 0 = a friendly
## game (no wager, always playable). A wagered match refuses to start unless the player can cover the stake.
@export var wager: int = 0

@export_group("Behavior")
## STANDALONE (default): sit on the talk layer so Interact opens the match directly. Off -> DATA-ONLY: the ray
## won't detect us, and a dialogue NPC drives access via its "Play Chess" option.
@export var standalone: bool = true

## Editor warning: a standalone match on a dialogue NPC steals the interaction ray from the NPC's Talkable.
func _get_configuration_warnings() -> PackedStringArray:
	if standalone and _on_dialogue_host():
		return PackedStringArray([
			"`standalone` is on but this ChessMatch is a child of a dialogue NPC — its talk-layer hitbox steals the interaction ray from the NPC's Talkable. Set `standalone` = false and open the match from the dialogue's \"Play Chess\" option.",
		])
	return PackedStringArray()

func _ready() -> void:
	if Engine.is_editor_hint():
		_editor_fit_hitbox()  # preview the auto-fit hitbox in-editor (resizes an existing collider; safe)
		return                # @tool: only _get_configuration_warnings runs in-editor; runtime wiring is below
	# Standalone = a look-at hitbox on the talk layer (the ray detects it); data-only matches sense nothing.
	collision_layer = TalkHelpers.TALK_LAYER if standalone else 0
	collision_mask = 0
	_build_outline()  # look-at outline over the host's meshes (LookAtInteractable helper)
	if auto_fit_collider:
		_fit_hitbox_to_host()

# ---------------------------------------------------------------------------------------------------
# Duck-typed config surface (read by DialogueManager's finder + ChessScreen)
# ---------------------------------------------------------------------------------------------------

## The opponent's display name for the match title / move log ("Opponent" when unnamed).
func display_opponent_name() -> String:
	return opponent_name if not opponent_name.is_empty() else "Opponent"

## The AI search depth this opponent plays at (>= 1). Also the primary duck-type key DialogueManager scans for.
func ai_search_depth() -> int:
	return maxi(1, ai_depth)

func ai_blunder() -> float:
	return clampf(ai_blunder_chance, 0.0, 1.0)

func player_is_white() -> bool:
	return player_plays_white

func wager_amount() -> int:
	return maxi(0, wager)

# ---------------------------------------------------------------------------------------------------
# Behaviour (talk-handler surface — used only when standalone, a direct-interact table)
# ---------------------------------------------------------------------------------------------------

## Interact pressed while aimed at us: open the chess match for this opponent.
func start_talk(player: Node) -> void:
	ChessScreen.open_match(self, player)

## Always interactable — you can always sit down for a game (the wallet check for a wager happens on start).
func can_be_talked_to() -> bool:
	return true

## Hover readout: "Play Chess: <name>" (or just "Play Chess" when unnamed).
func look_name() -> String:
	return PlayerText.chess_prompt(opponent_name)
