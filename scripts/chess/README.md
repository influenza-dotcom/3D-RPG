# Blindfold chess (`scripts/chess/`)

A self-contained chess minigame you play against NPCs — **blindfold by default** (moves typed as text, the position
tracked in your head) with a **Board Visualizer microchip** that flips it to sighted play. It plugs into the same
dialogue seam as Trade / Heal / Install: an NPC (or a table) carrying a `ChessMatch` component offers a **"Play
Chess"** option that opens the board.

## The pieces

| File | Role |
|------|------|
| `scripts/chess/chess_game.gd` (`class_name ChessGame`) | The rules engine. **Pure logic** — no tree/UI/autoload deps, so it unit-tests off-tree and the AI searches on a `clone()`. Board = a 64-int `Array` (a1=0…h8=63; piece = type×colour). Full legality: castling (incl. through-check), en passant, promotion, check/checkmate/stalemate, plus 50-move & insufficient-material draws. `make_move`/`undo_move` are the search primitive. Parses SAN **and** coordinate input; formats SAN for the log. |
| `scripts/chess/chess_ai.gd` (`class_name ChessAi`) | The opponent. Negamax + alpha-beta over a material + piece-square eval. Two difficulty knobs: `depth` (plies) and `blunder_chance` (0..1 — probability of playing a random legal move, which is what makes a weak NPC feel human/beatable). |
| `scripts/ui/chess_screen.gd` (autoload `ChessScreen`) | The play overlay. Mirrors `ChipInstallScreen` (layer 121, `PROCESS_MODE_ALWAYS`, pauses the world). Typed move input; a rendered 8×8 board **only** when `Player.has_mechanic(&"chess_visualizer")`, else a "BLINDFOLD" placeholder. Runs the turn loop and settles the wager. |
| `scripts/components/chess_match.gd` (`class_name ChessMatch`) | The drop-in NPC/table component (`extends LookAtInteractable`). Standalone (aim+interact) or dialogue-hosted (`standalone = false`). Exports the opponent's name, `ai_depth`, `ai_blunder_chance`, `player_plays_white`, and a `wager`. |
| `scripts/components/abilities/chess_visualizer.gd` (`class_name ChessVisualizer`) | The Board Visualizer as a flag `Ability` (`ability_id()` → `&"chess_visualizer"`). No behaviour — its presence IS the grant. Rides the normal chip pipeline. |
| `resources/items/chip_chess_visualizer.tres` | The microchip `Item` (`installs_ability = &"chess_visualizer"`). Found/bought, then fitted at any `ChipInstaller` like every other chip. |

## The design hook — the chip *is* the difference

Blindfold play is the raw challenge; the chip is the upgrade that overcomes it. It reuses the existing chip-install
pipeline with **zero new install code**: `installs_ability` → `Player.unlock_mechanic(&"chess_visualizer")` →
`has_mechanic()`. Because it's a real `Ability`, it serializes in `GameState.unlocks` and survives a reload for free.
The `ChessScreen` is the only consumer — it reads `has_mechanic` at open time to decide whether to render the board.

## Authoring an opponent

**On a dialogue NPC** (adds a "Play Chess" option): add a `ChessMatch` child, set `standalone = false`, fill in
`opponent_name` + difficulty. Nothing else — the dialogue finds it by duck-type (`ai_search_depth` +
`display_opponent_name`).

**As a standalone table**: add a `ChessMatch` (leave `standalone = true`), size its `CollisionShape3D` (or set
`auto_fit_collider`). Aim + Interact opens the match.

Difficulty: `ai_depth` 1 = pushover, 2 = solid club player, 3+ = sharp but slower. `ai_blunder_chance` 0 = never
slips, 0.4 = hangs pieces often. `wager` 0 = friendly; > 0 stakes zorkmids (win +, lose −, draw even; refuses to
start if the player can't cover it). A wager is forfeited only once the **PLAYER has actually moved** — opening a
table (including an opponent-White one whose AI has already auto-played move 1) and leaving before your first move
costs nothing. `player_plays_white` false = the opponent opens and you reply blindfold.

## Contracts (what a rename would silently break)

- **Dialogue seam** — `DialogueManager._speaker_chess()` duck-scans the speaker's children for `ai_search_depth` +
  `display_opponent_name`, and `_on_chess_pressed()` suspends into `ChessScreen.open_match(...)`, awaiting its
  `closed` signal to restore the box. Pinned by `tests/test_dialogue_speaker_contracts.gd`.
- **Ability registry** — `ChessVisualizer.tscn`'s filename snake-cases to its `ability_id()` (`chess_visualizer`),
  the convention `AbilityRegistry` + the drift test in `tests/test_upgrades.gd` enforce. The same snake_case
  convention resolves the ability SCRIPT (`chess_visualizer.gd`), so a save/load or a fresh install can rebuild the
  node with no hand-maintained id→script table — `tests/test_upgrades.gd::test_ability_scripts_covers_registry_ids`
  pins that EVERY `AbilityRegistry` id is buildable (`AbilityRegistry.can_build`), and `ChipInstaller` gates its
  charge on `Player.can_grant_mechanic()` first, so a chip whose ability can't be built is refused with no money taken.
- **Chip authoring** — `tests/test_chip_install.gd` requires every `resources/items/chip_*.tres` to install a real
  ability on disk and carry a `world_model`.

## Tests

- `tests/test_chess_game.gd` — the load-bearing one. **Perft** (move-tree node counts) against the universally
  agreed numbers from the standard position (perft(3)=8902) and "Kiwipete" (perft(2)=2039) proves legality,
  castling, en passant, promotion, and check handling all at once. Plus explicit mate/stalemate/castling-through-
  check/ep/promo/SAN/parse cases.
- `tests/test_chess_ai.gd` — the AI returns a legal move, finds a forced mate-in-1, grabs hanging material, and
  never returns an illegal/empty move even at `blunder_chance` 1.0. Also pins the `HALF_PAWN` (50 cp) tie window.
- `tests/test_chess_wager.gd` — the pure wager-settlement statics: `forfeit_delta` charges the stake only after
  the player has actually moved (leaving is free before that, incl. an opponent-White auto-opening move);
  `decided_delta` pays win `+wager` / loss `-wager` / draw `0`. (Refuse-when-broke is NOT one of the statics —
  it's the inline guard in `ChessScreen.open_match()`, currently untested.)

Run just these: `& "C:\Users\dalla\bin\godot.cmd" --headless --path . -s addons/gut/gut_cmdln.gd -gselect=chess -gexit`
(after adding a `class_name`, run `--import` first so the global class cache picks it up).

## Known limitations (deferred, by design for the slice)

- **Draw by threefold repetition is not implemented** (50-move and insufficient-material ARE). Positions repeat
  silently; only the mate/stalemate/50-move/material outcomes end a game.
- The match is **session-only** — an in-progress game is not saved (closing the board abandons it). Only the
  Visualizer *unlock* persists, via the normal ability save.
- The AI is a modest club-strength engine (material + piece-square, shallow search). It is meant to be beatable and
  characterful, not strong; tune `ai_depth`/`ai_blunder_chance` per opponent.
