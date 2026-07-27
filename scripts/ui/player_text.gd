class_name PlayerText
extends RefCounted

## Every player-facing English string lives here (or in an authored resource field) — the single
## chokepoint the deferred tr() sweep will wrap. Bodies follow the TextFormat RULE (see
## scripts/ui/text_format.gd): substitute values into ONE whole authored template via {named}
## tokens (TextFormat.subst — replace-based, so a literal '%' can never error), or SELECT between
## whole templates (bool/enum/key). Never concatenate prose pieces, never accept a prose fragment
## as an argument — fragments can't be translated. Counted things select whole singular/plural
## template variants through TextFormat.plural (the future tr_n() seam).

const PH_PREFIX := "[PH]"
const PH_PREFIX_SPACE := "[PH] "

## Perk / Faction registries (path-preloaded, no class_name — the build_gate idiom) so the requires_* deny
## toasts resolve authored display names BY ID right here: callers pass raw ids, never pre-resolved labels
## (a pre-resolved label would be re-capitalize()d — the exotic-authored-name mangle this seam removes).
const Perks := preload("res://scripts/player/perks.gd")
const Factions := preload("res://scripts/faction/factions.gd")

const BACK := "Back"
const BEGIN := "Begin"
const CANCEL := "Cancel"
const CLOSE := "Close"
const CONFIRM := "Confirm"
const DEFAULT := "Default"
const EMPTY_LIST := "(empty)"
## The shop sell-column row for the weapon you're wielding: the WHOLE composed row rides in as a value
## token and the "(equipped)" marker is authored inside the template (a locale may move or reword it) —
## replaced the old EQUIPPED_SUFFIX append at the ShopScreen call site (see equipped_row).
const EQUIPPED_ROW := "{row}   (equipped)"
const NEUTRAL_EFFECT := "neutral"

const PROMPT_PICK_UP := "[PH] Pick Up"
const PICK_UP := "Pick Up"
const PROMPT_READ := "[PH] Read"
const PROMPT_USE := "[PH] Use"
const PROMPT_BEFRIEND := "[PH] Befriend"
const PROMPT_PET := "[PH] Pet"
const PROMPT_RESPEC := "[PH] Respec"
const PROMPT_PLAY_CHESS := "[PH] Play Chess"
const PROMPT_REST_AT_BONFIRE := "[PH] Rest at bonfire"
const PROMPT_MECHANIC := "[PH] Mechanic"
const PROMPT_CONTAINER := "[PH] Container"
const PROMPT_LOCKED := "[PH] Locked"
const PROMPT_OPEN_DOOR := "[PH] Open door"
const PROMPT_CLOSE_DOOR := "[PH] Close door"

const DEFAULT_READABLE_TITLE := "[PH] Note"
const DEFAULT_UPGRADE_NAME := "Upgrade"
const DEFAULT_PERK_LABEL := "Perk"
const DEFAULT_MERCHANT_LABEL := "Merchant"
const DEFAULT_CHESS_OPPONENT := "Opponent"
const ENTER := "Enter"
const DOG := "Dog"
## Placeholder shown in place of an NPC's real name until they introduce themselves in dialogue (a line
## with reveals_name = true fires GameState.reveal_name). Read via GameState.public_name — the single seam
## every player-facing NPC-name surface (dialogue label, look-at readout, loot/death/takedown/cripple) routes
## through. Quest/kill matching keys on the stable identity (NPC.identity_key), never this. Edit here to re-label ("???").
const STRANGER := "Stranger"

const TOAST_ALREADY_FULL_HEALTH := "[PH] Already at full health"
const TOAST_ALREADY_LEARNED := "[PH] Already learned"
const TOAST_BACKPACK_FULL := "[PH] No room in your backpack"
const TOAST_BACKPACK_PARTIAL := "[PH] Backpack full — some items didn't fit"
const TOAST_CAUGHT := "[PH] Caught!"
const TOAST_CANT_LIFT_EQUIPPED := "[PH] Can't lift the weapon they're holding"
const TOAST_TOO_VALUABLE_TO_LIFT := "[PH] Too valuable to lift unnoticed"
const TOAST_NO_ROOM_FOR_ALL := "[PH] No room for all of that"
const TOAST_THEY_CANT_CARRY_MORE := "[PH] They can't carry any more"
const TOAST_NO_ROOM_IN_THERE := "[PH] No room left in there"
const TOAST_THEY_CANT_USE_WEAPON := "[PH] They can't use a weapon"
const TOAST_NO_ZORKMIDS_TO_DEPOSIT := "[PH] No zorkmids to deposit"
const TOAST_NO_ZORKMID_POCKET := "[PH] No pocket for zorkmids"
const TOAST_DEPOSITED_WHAT_FIT := "[PH] Deposited what fit"
const TOAST_LOCK_PICKED := "[PH] Lock picked"
const TOAST_UNLOCKED := "[PH] Unlocked"
const TOAST_LOCKED := "[PH] Locked"
const TOAST_NOT_OPEN_FOR_BUSINESS := "[PH] Not open for business"
const TOAST_IT_WONT_BUDGE := "[PH] It won't budge."
## A LevelDoor whose travel can't run (no GameRoot on the scene root) — the PLAYER-facing line only; the
## dev diagnostic ("attach game_root.gd…") goes to push_error at the call site, never onto the HUD.
const TOAST_DOOR_STUCK := "[PH] It won't open."
const TOAST_QUICKSAVED := "[PH] Quicksaved"
const TOAST_QUICKSAVE_FAILED := "[PH] Quicksave failed"
const TOAST_SNEAK_ATTACK := "[PH] Sneak Attack!"
const TOAST_TAKEDOWN := "[PH] Takedown"

const SAVE_WARN_ACTIVE_QUEST_MISSING := "[PH] Couldn't restore a saved quest — its data is missing, so its progress was lost."
const SAVE_WARN_COMPLETED_QUEST_MISSING := "[PH] Couldn't restore a completed quest record (its data is missing)."
const SAVE_WARN_FAILED_QUEST_MISSING := "[PH] Couldn't restore a failed quest record (its data is missing)."

const CHARACTER_CREATE_TITLE := "Create Character"
const CHARACTER_CREATE_NAME_LABEL := "Name"
const CHARACTER_CREATE_STATS_TAB := "Stats"
const CHARACTER_CREATE_LOOK_TAB := "Look"
const CHARACTER_CREATE_BODY_LABEL := "Body"
const CHARACTER_CREATE_HEAD_LABEL := "Head"
## Currently UNREFERENCED: the Look tab's skin-colour row was removed (no visible effect on the shipped
## materials — see character_creation._build_look_tab). Kept for the row's return.
const CHARACTER_CREATE_SKIN_LABEL := "Skin"
const CHARACTER_CREATE_ARMS_LABEL := "Arms"
const CHARACTER_CREATE_LEGS_LABEL := "Legs"
const CHARACTER_CREATE_FROM_BODY := "(from body)"
const CHARACTER_CREATE_EMPTY_PART := "—"
## The "Shirt" tab — the player paints their own torso texture (a blank tee they decorate).
const CHARACTER_CREATE_SHIRT_TAB := "Shirt"
const CHARACTER_CREATE_SHIRT_PAINT := "Paint"
const CHARACTER_CREATE_SHIRT_FILL := "Fill"
const CHARACTER_CREATE_SHIRT_ERASE := "Erase"
## Eyedropper tool: click the canvas to sample that pixel's colour into the brush.
const CHARACTER_CREATE_SHIRT_PICK := "Pick"
const CHARACTER_CREATE_SHIRT_MIRROR := "Mirror"
const CHARACTER_CREATE_SHIRT_UNDO := "Undo"
const CHARACTER_CREATE_SHIRT_RESET := "Reset"
## Label on the free-colour swatch (the HSV-wheel picker, like the spray can) beneath the preset chips.
const CHARACTER_CREATE_SHIRT_CUSTOM := "Custom"
## Label on the brush-size radio row (the 1/2/3/4 square-footprint chips).
const CHARACTER_CREATE_SHIRT_SIZE := "Size"
## The two-sided tee: which side the canvas is drawing (also spins the 3D preview to face it).
const CHARACTER_CREATE_SHIRT_FRONT := "Front"
const CHARACTER_CREATE_SHIRT_BACK := "Back"
## Closes the free-colour wheel overlay.
const CHARACTER_CREATE_SHIRT_PICK_DONE := "Done"
const CHARACTER_NAME_PLACEHOLDER := "[PH] Enter a name…"
## Shown under the name field (and gating Begin) while the name is blank — a run must be NAMED before it can start.
const CHARACTER_CREATE_NAME_REQUIRED := "[PH] Name your character to begin"
const NAME_DIALOG_HINT := "[PH] [Enter] Confirm     [Esc] Cancel"

const SHOP_TITLE := "TRADE"
const SHOP_FOR_SALE_HEADING := "[PH] For sale  (click to buy)"
const SHOP_YOUR_ITEMS_HEADING := "[PH] Your items  (click to sell)"
const SHOP_MERCHANT_WALLET := "[PH] Merchant: {money}"
const PLAYER_WALLET := "[PH] You: {money}"

const INSTALL_TITLE := "INSTALL"
const INSTALL_CARRIED_HEADING := "[PH] Install your chips  (click to install)"
const INSTALL_STOCK_HEADING := "[PH] For sale — buy & install  (click to fit)"

const LOOT_HINT := "[PH] Click an item to take / deposit it · drag to rearrange your grid"
const LOOT_TITLE := "[PH] LOOTING"
const LOOT_CORPSE_HEADING := "[PH] Corpse"
const LOOT_PICKPOCKET_TITLE := "[PH] PICKPOCKETING"
const LOOT_POCKETS_HEADING := "[PH] Pockets"
const LOOT_EXCHANGE_TITLE := "[PH] EXCHANGING GEAR"
const LOOT_THEIR_GEAR_HEADING := "[PH] Their Gear"
const LOOT_CONTAINER_TITLE := "[PH] CONTAINER"
const LOOT_CONTAINER_HEADING := "[PH] Container"
const LOOT_SOURCE_HEADING := "Source"
const LOOT_YOU_HEADING := "You"

const CHESS_MOVE_PLACEHOLDER := "[PH] your move…"
const CHESS_MOVE_BUTTON := "[PH] Move"
const CHESS_MOVES_HEADING := "[PH] Moves"
const CHESS_NO_MOVES := "[PH] (no moves yet)"
const CHESS_STALEMATE := "[PH] Stalemate — a draw."
const CHESS_DRAW_FIFTY_MOVE := "[PH] Draw — fifty-move rule."
const CHESS_DRAW_INSUFFICIENT := "[PH] Draw — not enough material to mate."
const CHESS_GAME_OVER := "[PH] Game over."
const CHESS_YOUR_MOVE := "[PH] Your move."
## Appended by ChessScreen's status line — a suffix-append FRAGMENT holdout (the shop's equivalent became
## the whole EQUIPPED_ROW template); the chess phase folds it into whole "your move" / "your move — check" templates.
const CHESS_CHECK_SUFFIX := "  (Check!)"
## Checkmate result — TWO whole templates selected by who won (never a spliced "you win/you lose" fragment).
const CHESS_CHECKMATE_WIN := "[PH] Checkmate — you win."
const CHESS_CHECKMATE_LOSS := "[PH] Checkmate — you lose."
const CHESS_EXIT_HINT := "[PH] Esc — leave the table"
const CHESS_INPUT_HINT := "[PH] Type a move (e2e4 or Nf3) · Enter to play · Esc to leave"
const CHESS_BLINDFOLD_HINT := "[PH] Blindfold: track the board from the move log · type e2e4 or Nf3 · Esc to leave"
const CHESS_BLINDFOLD_BADGE := "[ BLINDFOLD ]"
const CHESS_NO_BOARD_HINT := "[PH] No board — play it in your head.\nInstall the Board Visualizer chip to see the position."

const HEAL_FULLY_HEALED := "[PH] Fully healed"
## The heal card's status block — FOUR whole templates selected by (limb damage, affordability), so no
## caller ever assembles the block from line fragments. The limb line and the can't-afford note are
## authored INSIDE each variant; HealScreen pads the rendered block to a constant height (see heal_screen.gd).
const HEAL_STATUS := "[PH] HP  {hp} / {max_hp}\nYour zorkmids: {amount}"
const HEAL_STATUS_LIMB := "[PH] HP  {hp} / {max_hp}\n— limb damage\nYour zorkmids: {amount}"
const HEAL_STATUS_CANT_AFFORD := "[PH] HP  {hp} / {max_hp}\nYour zorkmids: {amount}\n— can't afford"
const HEAL_STATUS_LIMB_CANT_AFFORD := "[PH] HP  {hp} / {max_hp}\n— limb damage\nYour zorkmids: {amount}\n— can't afford"
const RESPEC_NO_PERKS := "[PH] (no perks unlocked)"
const RESPEC_NOTHING := "Nothing to respec"
## Keep this SHORT: it swaps onto a rebind button pinned to MenuSkin.rebind_button_width (120px English
## budget incl. margins, clip_text on) — a longer prompt clips rather than growing the button, so it must
## read whole at ~102px.
const OPTIONS_BIND_PROMPT := "[PH] Press key..."
const OPTIONS_MUSIC_FOLDER_DEFAULT := "[PH] Default (each radio's own folder)"
const OPTIONS_CHOOSE_MUSIC_FOLDER := "[PH] Choose a music folder"
const OPTIONS_WINDOWED := "[PH] Windowed"
const OPTIONS_BORDERLESS := "[PH] Borderless Fullscreen"
const OPTIONS_EXCLUSIVE_FULLSCREEN := "[PH] Exclusive Fullscreen"
## Player-menu tab-strip labels (the Deus Ex / Pip-Boy tab group). DISPLAY text only: PlayerMenus routes
## between the four screens on StringName keys (PlayerMenus.TABS); these are just what the strip's buttons
## paint (PlayerMenus.TAB_LABELS maps key -> label). Re-wording one here can never change routing.
const MENU_TAB_INVENTORY := "Inventory"
const MENU_TAB_STATS := "Stats"
const MENU_TAB_REPUTATION := "Reputation"
const MENU_TAB_JOURNAL := "Journal"
const QUEST_JOURNAL_HINT := "[PH] Your active and completed quests."
const QUEST_JOURNAL_EMPTY := "[PH] No quests yet."
const REPUTATION_HINT := "[PH] How each faction feels about you. Good deeds raise it; killing their own sinks it."
const REPUTATION_EMPTY := "[PH] No factions defined."
const STATS_SCREEN_HINT := "[PH] Spend points at a Level-Up station."

## Reputation-shift toast — TWO whole templates selected by direction (never a "gained"/"lost" fragment).
const REPUTATION_GAINED := "[PH] {faction} reputation gained!"
const REPUTATION_LOST := "[PH] {faction} reputation lost!"

## The three standing WORDS, painted standalone by the reputation screen's disposition column (a phase-2
## file) and doubling — for now — as alignment_changed's selection keys, because the phase-2-owned caller
## (ui.gd) passes the word it paints. Phase 2 moves callers onto Disposition.Kind and these stay display-only.
const ALIGNMENT_HOSTILE_WORD := "Hostile"
const ALIGNMENT_NEUTRAL_WORD := "Neutral"
const ALIGNMENT_FRIENDLY_WORD := "Friendly"
## Standing-crossed announcement — one whole template per alignment kind, SELECTED (see alignment_changed);
## the kind word is authored inside each template, never substituted in as a fragment.
const ALIGNMENT_NOW_HOSTILE := "[PH] {faction} is now Hostile!"
const ALIGNMENT_NOW_NEUTRAL := "[PH] {faction} is now Neutral!"
const ALIGNMENT_NOW_FRIENDLY := "[PH] {faction} is now Friendly!"
const ALIGNMENT_CHANGED_TEMPLATES := {
	ALIGNMENT_HOSTILE_WORD: ALIGNMENT_NOW_HOSTILE,
	ALIGNMENT_NEUTRAL_WORD: ALIGNMENT_NOW_NEUTRAL,
	ALIGNMENT_FRIENDLY_WORD: ALIGNMENT_NOW_FRIENDLY,
}

## The death-card copy. The killed-by variants keep LEGACY "%s" slots (not {named} tokens yet): they are
## @export defaults on PlayerFeedbackSettings (designer-authored), and the death-card formatter that fills
## them is phase-2 territory — migrate the resource seam and these together.
const DEATH_MESSAGE := "[PH] You were killed."
const DEATH_MESSAGE_KILLED_BY := "[PH] You were killed by %s."
const DEATH_MESSAGE_KILLED_BY_WEAPON := "[PH] You were killed by %s. They were using a %s."


static func prefixed(text: String) -> String:
	return PH_PREFIX_SPACE + text


static func strip_prefix(text: String) -> String:
	return text.substr(PH_PREFIX_SPACE.length()) if text.begins_with(PH_PREFIX_SPACE) else text


static func acquired(name: String) -> String:
	return TextFormat.subst("[PH] {name} acquired!", {"name": name})


static func installed(name: String) -> String:
	return TextFormat.subst("[PH] {name} installed", {"name": name})


static func take(name: String) -> String:
	return TextFormat.subst("[PH] Take {name}", {"name": name})


static func take_item(name: String) -> String:
	return TextFormat.subst("Take {name}", {"name": name})


static func pick_up(name: String) -> String:
	return TextFormat.subst("[PH] Pick Up {name}", {"name": name}) if not name.is_empty() else PROMPT_PICK_UP


static func pick_pocket(name: String) -> String:
	return TextFormat.subst("[PH] Pick Pocket {name}", {"name": name}) if not name.is_empty() else "[PH] Pick Pocket"


## The hover-tooltip odds line while pickpocketing a live target: the chance (0..100 %) of lifting the hovered item
## without being caught. Fed by LootScreen._pickpocket_success_percent (1 - catch chance).
static func pickpocket_success(pct: int) -> String:
	return TextFormat.subst("[PH] {pct}% to lift unnoticed", {"pct": pct})


static func talk_to(name: String) -> String:
	return TextFormat.subst("[PH] Talk to {name}", {"name": name})


static func trade_prompt(name: String) -> String:
	return TextFormat.subst("Trade: {name}", {"name": name}) if not name.is_empty() else DEFAULT_MERCHANT_LABEL


static func enter_prompt(name: String) -> String:
	return enter_level(name) if not name.is_empty() else ENTER


static func unlock(name: String) -> String:
	return TextFormat.subst("[PH] Unlock {name}", {"name": name})


static func loot(name: String) -> String:
	return TextFormat.subst("[PH] Loot {name}", {"name": name}) if not name.is_empty() else PROMPT_CONTAINER


static func accept(quest_title: String) -> String:
	return TextFormat.subst("[PH] Accept: {title}", {"title": quest_title})


static func quest_started(quest_title: String) -> String:
	return TextFormat.subst("[PH] Quest started: {title}", {"title": quest_title})


static func new_quest(quest_title: String) -> String:
	return TextFormat.subst("[PH] New quest: {title}", {"title": quest_title})


static func objective_complete(description: String) -> String:
	return TextFormat.subst("[PH] Objective complete: {objective}", {"objective": description})


static func quest_complete(quest_title: String) -> String:
	return TextFormat.subst("[PH] Quest complete: {title}", {"title": quest_title})


static func quest_failed(quest_title: String) -> String:
	return TextFormat.subst("[PH] Quest failed: {title}", {"title": quest_title})


## Two whole templates (with/without the progress counter), selected on `required` — the counter is
## authored into its variant, never appended.
static func quest_tracker_line(title: String, objective_desc: String, progress: int, required: int) -> String:
	var template := "[PH] ◈ {title} — {objective} ({progress}/{required})" if required > 1 else "[PH] ◈ {title} — {objective}"
	return TextFormat.subst(template, {"title": title, "objective": objective_desc, "progress": progress, "required": required})


## Quest-REWARD overflow (GameState._grant_quest_rewards) — names the loss as reward items. The generic
## non-quest overflow (a dialogue gift) is inventory_full below.
static func quest_rewards_full(lost_count: int) -> String:
	return TextFormat.subst(TextFormat.plural(lost_count,
			"[PH] Inventory full — {count} quest reward item couldn't fit",
			"[PH] Inventory full — {count} quest reward items couldn't fit"),
			{"count": lost_count})


## Neutral bag-overflow toast for a NON-quest item grant (the dialogue gift path in DialogueManager) —
## deliberately does not claim the lost items were quest rewards.
static func inventory_full(lost_count: int) -> String:
	return TextFormat.subst(TextFormat.plural(lost_count,
			"[PH] Inventory full — {count} item couldn't fit",
			"[PH] Inventory full — {count} items couldn't fit"),
			{"count": lost_count})


static func reputation_changed(faction_name: String, gained: bool) -> String:
	return TextFormat.subst(REPUTATION_GAINED if gained else REPUTATION_LOST, {"faction": faction_name})


## `kind_word` is a SELECTION KEY (one of ALIGNMENT_*_WORD — what ui.gd, the phase-2-owned caller,
## passes today), never spliced into the sentence; unknown keys fall back to the Neutral template.
static func alignment_changed(faction_name: String, kind_word: String) -> String:
	var template: String = ALIGNMENT_CHANGED_TEMPLATES.get(kind_word, ALIGNMENT_NOW_NEUTRAL)
	return TextFormat.subst(template, {"faction": faction_name})


## Deny toast for a stat gate. Takes the stat ID — the authored StatText title resolves HERE (StatInfo.title,
## capitalized-id fallback built in), so callers (BuildGate) never pre-resolve or re-capitalize the display name.
static func requires_stat(stat: StringName, value: int) -> String:
	return TextFormat.subst("[PH] Requires {stat} {value}", {"stat": StatInfo.title(stat), "value": value})


## Deny toast for a perk gate. Takes the perk ID: the authored Perk.display_name resolves HERE (Perks registry),
## [PH]-stripped since this template prepends its own marker; a missing/blank name degrades to the capitalized
## id (the pre-authoring look). Authored casing is used VERBATIM — never re-capitalize()d.
static func requires_perk(perk_id: StringName) -> String:
	var label := Perks.display_label(perk_id)  # authored display_name verbatim, else the raw id back
	label = strip_prefix(label) if label != String(perk_id) else label.capitalize()
	return TextFormat.subst("[PH] Requires the {perk} perk", {"perk": label})


static func requires_ability() -> String:
	return "[PH] Requires an ability"


## Deny toast for a faction-standing gate. Takes the faction ID: the authored Faction.display_name resolves HERE
## (Factions.by_id); an unresolved faction or blank authored name degrades to the capitalized id as before.
static func requires_standing(faction_id: String) -> String:
	var fac := Factions.by_id(faction_id)
	var label := fac.display_name if fac != null and not fac.display_name.is_empty() else faction_id.capitalize()
	return TextFormat.subst("[PH] Requires standing with {faction}", {"faction": label})


static func locked_requires(label: String) -> String:
	return TextFormat.subst("[PH] Locked — requires {label}", {"label": label})


## Deny toast for a lock that is BOTH keyed AND pickable but you have neither the key nor a lockpick — name both ways in.
static func locked_requires_either(key_label: String, pick_label: String) -> String:
	return TextFormat.subst("[PH] Locked — requires {key} or {pick}", {"key": key_label, "pick": pick_label})


static func lock_result(consumed_item: bool) -> String:
	return TOAST_LOCK_PICKED if consumed_item else TOAST_UNLOCKED


static func rest_prompt(place: String) -> String:
	return TextFormat.subst("[PH] Rest: {place}", {"place": place}) if not place.is_empty() else PROMPT_REST_AT_BONFIRE


static func rested_at(place: String) -> String:
	return TextFormat.subst("[PH] Rested at {place}", {"place": place})


static func respec_prompt(station_name: String) -> String:
	return TextFormat.subst("[PH] Respec: {name}", {"name": station_name}) if not station_name.is_empty() else PROMPT_RESPEC


static func respec_refunded(count: int) -> String:
	return TextFormat.subst(TextFormat.plural(count,
			"[PH] Respec: {count} perk refunded",
			"[PH] Respec: {count} perks refunded"),
			{"count": count})


static func respec_blurb(count: int) -> String:
	return TextFormat.subst(TextFormat.plural(count,
			"[PH] Refund {count} perk — skill points return to re-spend at a Level Up.",
			"[PH] Refund {count} perks — skill points return to re-spend at a Level Up."),
			{"count": count})


static func respec_status(cost: float, player_money: float) -> String:
	return TextFormat.subst("[PH] Cost: {cost}\nYour zorkmids: {amount}", {"cost": Zorkmids.fmt(cost), "amount": Zorkmids.fmt(player_money)})


static func respec_button(cost: float) -> String:
	return TextFormat.subst("Respec  —  {money}", {"money": Zorkmids.money_text(cost)})


static func bonfire_name(name: String) -> String:
	return name if not name.is_empty() else "bonfire"


## Radio on/off toasts — two whole templates (Radio._toast selects by the new state), replacing the old
## radio_state(name, state_word) fragment seam.
static func radio_on(name: String) -> String:
	return TextFormat.subst("[PH] {name} on", {"name": name})


static func radio_off(name: String) -> String:
	return TextFormat.subst("[PH] {name} off", {"name": name})


static func radio_prompt(name: String, playing: bool) -> String:
	return TextFormat.subst("[PH] Turn off {name}" if playing else "[PH] Turn on {name}", {"name": name})


static func container_prompt(container_name: String, locked: bool) -> String:
	var name := container_name if not container_name.is_empty() else "Container"
	return unlock(name) if locked else loot(container_name)


static func money_pickup(amount: float) -> String:
	return TextFormat.subst("[PH] Take {amount} zorkmids", {"amount": Zorkmids.fmt(amount)})


static func wallet_you(amount: float) -> String:
	return TextFormat.subst(PLAYER_WALLET, {"money": Zorkmids.money_text(amount)})


static func wallet_merchant(amount: float) -> String:
	return TextFormat.subst(SHOP_MERCHANT_WALLET, {"money": Zorkmids.money_text(amount)})


static func claim_name_dialog(name: String) -> String:
	return TextFormat.subst("[PH] Name your {name}", {"name": name})


static func befriend(name: String) -> String:
	return TextFormat.subst("[PH] Befriended {name}", {"name": name}) if not name.is_empty() else "[PH] Befriended"


static func released(name: String) -> String:
	return TextFormat.subst("[PH] Released {name}", {"name": name}) if not name.is_empty() else "[PH] Released"


static func hold_to_release(key: String, name: String) -> String:
	if name.is_empty():
		return TextFormat.subst("[PH] [{key}] Hold to Release", {"key": key})
	return TextFormat.subst("[PH] [{key}] Hold to Release {name}", {"key": key, "name": name})


## NOTE: the old key_prompt(key, verb, name) is GONE — a verb argument is a prose fragment the RULE
## forbids (and it had no callers left). Each interaction verb gets its own whole-template func
## (takedown_prompt / hold_to_release are the shape); add a new func here rather than resurrecting a
## verb parameter.
static func takedown_prompt(key: String, name: String) -> String:
	if name.is_empty():
		return TextFormat.subst("[PH] [{key}] Take Down", {"key": key})
	return TextFormat.subst("[PH] [{key}] Take Down {name}", {"key": key, "name": name})


static func learned(perk_label: String) -> String:
	return TextFormat.subst("[PH] Learned: {perk}", {"perk": perk_label})


static func learn_prompt(perk_label: String) -> String:
	return TextFormat.subst("[PH] Learn: {perk}", {"perk": perk_label})


static func enter_level(level_name: String) -> String:
	return TextFormat.subst("[PH] Enter {name}", {"name": level_name})


static func chip_installer_prompt(name: String) -> String:
	return TextFormat.subst("[PH] Upgrades: {name}", {"name": name}) if not name.is_empty() else PROMPT_MECHANIC


static func chess_prompt(opponent_name: String) -> String:
	return TextFormat.subst("[PH] Play Chess: {name}", {"name": opponent_name}) if not opponent_name.is_empty() else PROMPT_PLAY_CHESS


static func chess_title(opponent_name: String) -> String:
	return TextFormat.subst("CHESS — {name}", {"name": opponent_name}) if not opponent_name.is_empty() else "CHESS"


static func collateral_kill(pay: float) -> String:
	return TextFormat.subst("[PH] Collateral kill!  +{money}", {"money": Zorkmids.money_text(pay)})


static func confetti(pay: float) -> String:
	return TextFormat.subst("[PH] Confetti!  +{money}", {"money": Zorkmids.money_text(pay)})


static func long_range_kill(distance_m: int, pay: float) -> String:
	return TextFormat.subst("[PH] Long-range kill!  {distance} m  +{money}", {"distance": distance_m, "money": Zorkmids.money_text(pay)})


## The respawn toast for the half-wallet death loss (death_purse_loss_fraction) — placeholder medical-fee flavour.
## `amount` = the zorkmids actually deducted at death (Player._death_wallet_lost). Mirrors the chess_loss /
## long_range_kill money-toast style: one [PH] marker up front, the signed amount trailing.
static func hospital_bill(amount: float) -> String:
	return TextFormat.subst("[PH] Hospital bill!  -{money}", {"money": Zorkmids.money_text(amount)})


static func holster_forgiveness_tutorial(key: String) -> String:
	return TextFormat.subst("[PH] You provoked them. Hold [{key}] to holster your weapon and ask for forgiveness.", {"key": key})


static func gained_hp(amount: int) -> String:
	return TextFormat.subst("[PH] +{amount} HP", {"amount": amount})


static func head_crippled() -> String:
	return "[PH] Your head is crippled!"


static func crippled_target(target_name: String, part_name: String) -> String:
	return TextFormat.subst("Crippled {name}'s {part}", {"name": target_name, "part": part_name})


static func level_up(level: int, points: int) -> String:
	return TextFormat.subst(TextFormat.plural(points,
			"Level {level}! +{points} skill point",
			"Level {level}! +{points} skill points"),
			{"level": level, "points": points})


static func points_to_spend(spare: int) -> String:
	return TextFormat.subst("[PH] Points to spend: {points}", {"points": spare})


static func character_create_stat_hint(min_value: int, max_value: int) -> String:
	return TextFormat.subst("[PH] Lower a stat to earn points, then spend them raising another (range {min} to +{max}). A minus is a real weakness.", {"min": min_value, "max": max_value})


static func stat_effect_strength(melee: String, carry: String, max_hp: String) -> String:
	return TextFormat.subst("[PH] melee {melee}, {carry} carry, {max_hp} max HP", {"melee": melee, "carry": carry, "max_hp": max_hp})


static func stat_effect_endurance(stamina: String) -> String:
	return TextFormat.subst("[PH] {stamina} max stamina", {"stamina": stamina})


static func stat_effect_gunplay(damage: String, steadiness: String) -> String:
	return TextFormat.subst("[PH] {damage} gun damage, {steadiness} aim steadiness", {"damage": damage, "steadiness": steadiness})


static func stat_effect_agility(speed: String) -> String:
	return TextFormat.subst("[PH] {speed} move speed", {"speed": speed})


static func stat_effect_streetwise(buys: String, sales: String, rep: String) -> String:
	return TextFormat.subst("[PH] buys {buys}, sales {sales}, rep gains {rep}", {"buys": buys, "sales": sales, "rep": rep})


static func stat_effect_larceny(detection: String, takedown: String, risk: int, allowance: String) -> String:
	return TextFormat.subst("[PH] {detection} enemy detection speed, {takedown} takedown time, {risk}% caught risk, lift value <= {allowance}", {"detection": detection, "takedown": takedown, "risk": risk, "allowance": allowance})


static func shop_title(name: String) -> String:
	return TextFormat.subst("TRADE — {name}", {"name": name}) if not name.is_empty() else SHOP_TITLE


## A shop sell-row for the currently-wielded weapon — the whole EQUIPPED_ROW template wrapping the composed
## row text as a value token (replaces the old EQUIPPED_SUFFIX append in ShopScreen._fill).
static func equipped_row(row_text: String) -> String:
	return TextFormat.subst(EQUIPPED_ROW, {"row": row_text})


static func install_title(name: String) -> String:
	return TextFormat.subst("INSTALL — {name}", {"name": name}) if not name.is_empty() else INSTALL_TITLE


static func heal_title(name: String) -> String:
	return TextFormat.subst("HEAL — {name}", {"name": name}) if not name.is_empty() else "HEAL"


static func respec_title(name: String) -> String:
	return TextFormat.subst("RESPEC — {name}", {"name": name}) if not name.is_empty() else "RESPEC"


static func level_up_title(name: String) -> String:
	return TextFormat.subst("Level Up — {name}", {"name": name}) if not name.is_empty() else "Level Up"


## Selects one of the four HEAL_STATUS_* whole templates — HealScreen passes the two FACTS (limb damage,
## affordability) and never composes the lines itself.
static func heal_status(hp: int, max_hp: int, limb_damaged: bool, money: float, cant_afford: bool) -> String:
	var template := HEAL_STATUS
	if limb_damaged and cant_afford:
		template = HEAL_STATUS_LIMB_CANT_AFFORD
	elif limb_damaged:
		template = HEAL_STATUS_LIMB
	elif cant_afford:
		template = HEAL_STATUS_CANT_AFFORD
	return TextFormat.subst(template, {"hp": hp, "max_hp": max_hp, "amount": Zorkmids.fmt(money)})


static func heal_button(cost: int) -> String:
	return TextFormat.subst("[PH] Heal  —  {money}", {"money": Zorkmids.money_text(cost)})


static func level_label(level: int) -> String:
	return TextFormat.subst("[PH] Level {level}", {"level": level})


static func your_zorkmids(amount: float) -> String:
	return TextFormat.subst("[PH] Your zorkmids: {amount}", {"amount": Zorkmids.fmt(amount)})


static func perks_header(points: int) -> String:
	return TextFormat.subst(TextFormat.plural(points,
			"[PH] Perks — {points} point",
			"[PH] Perks — {points} points"),
			{"points": points})


## Two whole templates selected by the encumbered flag — the warning is authored into its variant, never
## appended. Weight/capacity keep the fixed one-decimal readout ("12.0"), so the token values are
## pre-formatted here (TextFormat.num would trim the ".0" the gauge look relies on).
static func inventory_weight(weight: float, capacity: float, encumbered: bool) -> String:
	var template := "[PH] Weight  {weight} / {capacity}   ENCUMBERED" if encumbered else "[PH] Weight  {weight} / {capacity}"
	return TextFormat.subst(template, {"weight": "%.1f" % weight, "capacity": "%.1f" % capacity})


## PHASE-2 DEBT: `kind` arrives as a heading fragment ("LOOTING" / "PICKPOCKETING" from LootScreen) — the
## loot-screen phase should replace this with one whole-template func per mode.
static func loot_title(kind: String, name: String) -> String:
	return TextFormat.subst("[PH] {kind} {name}", {"kind": kind, "name": name}) if not name.is_empty() else TextFormat.subst("[PH] {kind}", {"kind": kind})


static func loot_exchange_title(name: String) -> String:
	return TextFormat.subst("[PH] EXCHANGING GEAR — {name}", {"name": name}) if not name.is_empty() else LOOT_EXCHANGE_TITLE


static func chess_cant_cover(wager: float) -> String:
	return TextFormat.subst("[PH] You can't cover the {money} stake.", {"money": Zorkmids.money_text(wager)})


static func chess_forfeit_loss(delta_abs: float) -> String:
	return TextFormat.subst("[PH] -{money} — you forfeited the game.", {"money": Zorkmids.money_text(delta_abs)})


static func chess_illegal_move(text: String) -> String:
	# Truncate the echo: the typed entry is unbounded (the move field has no max_length) and this line lives
	# on the chess panel's single-line clipped hint — an untruncated echo would clip away the guidance suffix.
	var shown := text if text.length() <= 24 else text.left(24) + "…"
	return TextFormat.subst("[PH] “{move}” isn't a legal move. Try e2e4 or Nf3.", {"move": shown})


static func chess_win(delta: float) -> String:
	return TextFormat.subst("[PH] +{money} — you won the game.", {"money": Zorkmids.money_text(delta)})


static func chess_loss(delta_abs: float) -> String:
	return TextFormat.subst("[PH] -{money} — you lost the game.", {"money": Zorkmids.money_text(delta_abs)})


static func chess_checkmate(player_wins: bool) -> String:
	return CHESS_CHECKMATE_WIN if player_wins else CHESS_CHECKMATE_LOSS


static func chess_thinking(name: String) -> String:
	return TextFormat.subst("[PH] {name} is thinking…", {"name": name})


static func chess_to_move(name: String) -> String:
	return TextFormat.subst("[PH] {name} to move.", {"name": name})
