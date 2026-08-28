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
## Currently UNREFERENCED in production (the same "kept for the row's return" status as
## CHARACTER_CREATE_SKIN_LABEL): the shop's sell column became a GRID, and a tile marks the wielded weapon
## visually (GridTile's equipped chrome) instead of appending "(equipped)" to a row string. Kept because it is
## the correct whole-template shape for any future LIST that needs the marker — the "{row}" token carries the
## composed row in as a value, so a locale can move or reword the marker. Pinned by tests/test_player_text.gd.
const EQUIPPED_ROW := "{row}   (equipped)"

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
## Nouns for the body parts a character bursts into on death (the BodyPartGib flying limbs) — used as the
## gib's Throwable.display_name, so aiming at one reads "Pick Up Head" instead of a bare "Pick Up". BARE, no
## "[PH] " marker: they are substituted INTO pick_up(), whose template already carries exactly one marker,
## and doubling it is a pinned failure (see test_player_text). Read them through body_part(), never directly.
const BODY_PART_HEAD := "Head"
const BODY_PART_TORSO := "Torso"
const BODY_PART_ARM := "Arm"
const BODY_PART_LEG := "Leg"
## Placeholder shown in place of an NPC's real name until the player has SPOKEN to them — opening any
## conversation reveals the speaker (DialogueManager.start -> GameState.reveal_name); a line with
## reveals_name = true fires the same call. Read via GameState.public_name — the single seam
## every player-facing NPC-name surface (dialogue label, look-at readout, loot/death/takedown/cripple) routes
## through. Quest/kill matching keys on the stable identity (NPC.identity_key), never this. Edit here to re-label ("???").
const STRANGER := "Stranger"

const TOAST_ALREADY_FULL_HEALTH := "[PH] Already at full health"
const TOAST_ALREADY_LEARNED := "[PH] Already learned"
const TOAST_BACKPACK_FULL := "[PH] No room in your backpack"
const TOAST_BACKPACK_PARTIAL := "[PH] Backpack full — some items didn't fit"
const TOAST_CAUGHT := "[PH] Caught!"
const TOAST_CANT_LIFT_EQUIPPED := "[PH] Can't lift the weapon they're holding"
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
## The SYNTHESIZED dialogue response-menu options — the buttons DialogueManager splices on top of a line's
## authored choices when the speaker carries the matching component (Merchant / Healer / Bonfire / LevelUp /
## ChipInstaller / WeaponBench / ChessMatch / Atm / a following companion with a backpack), plus the
## always-present leave option.
## DISPLAY text only: each button binds its own handler Callable, so re-wording one here can never change which
## menu opens — the same label-is-never-a-key rule as MENU_TAB_* and CompanionRecruiter.label_for.
const DIALOGUE_OPTION_TRADE := "Trade"
const DIALOGUE_OPTION_HEAL := "Heal"
const DIALOGUE_OPTION_REST := "Rest"
const DIALOGUE_OPTION_LEVEL_UP := "Level Up"
const DIALOGUE_OPTION_INSTALL := "Install"
## The gunsmith bench's option (WeaponBench.DIALOGUE_ORDER 55, between the chip installer's 50 and chess's 60,
## which is why it sits HERE in the block). BARE, no "[PH] " marker — a verb label in the same fixed functional
## vocabulary as Install / Trade above, and DialogueManager splices it into a menu row that carries its own.
const DIALOGUE_OPTION_MODIFY := "Modify"
const DIALOGUE_OPTION_PLAY_CHESS := "Play Chess"
## One verb for BOTH directions and both signs of the account (deposit / withdraw / pay a debt down) — the
## terminal's own screen swaps its Deposit/Pay-down caption, so this button never has to know which you mean.
const DIALOGUE_OPTION_BANK := "Bank"
const DIALOGUE_OPTION_EXCHANGE_GEAR := "Exchange Gear"
## The companion follow/dismiss toggle pair — CompanionRecruiter.label_for picks by following(), and the
## handler binds the BEHAVIOUR predicate, so rewording either can never flip recruit into dismiss (the
## label-is-never-a-key rule this block's header states). RECRUIT_ACK is the spoken acknowledgement the
## box shows when "Follow me" lands — a full sentence like GOODBYE below, not a verb label.
const DIALOGUE_OPTION_FOLLOW := "Follow me"
const DIALOGUE_OPTION_WAIT_HERE := "Wait here"
const DIALOGUE_RECRUIT_ACK := "Alright."
## The generic leave option, always appended last. The trailing full stop is AUTHORED copy (it reads as a
## spoken line, unlike the verb-labelled service options above) — never punctuation the call site adds.
const DIALOGUE_OPTION_GOODBYE := "Goodbye."

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
## The Stats tab's per-stat steppers (character_creation._add_stat_row). The minus is U+2212 MINUS SIGN, NOT
## an ASCII hyphen — it is drawn at the "+" bar's width and height so the two chips read as a matched pair;
## keep the codepoint when re-skinning or re-fonting.
const CHARACTER_CREATE_STAT_MINUS := "−"
const CHARACTER_CREATE_STAT_PLUS := "+"
## The Stats tab's standing RULE line, under the points banner. The builder is ZERO-SUM and nothing else on
## the tab admits it: the screen opens with no spare points and every "+" painted disabled, which reads as a
## broken menu until you work out that a "−" somewhere else is what funds one. This line is the only thing
## teaching that, so it names the mechanic rather than describing the screen.
## ⭐ONE LINE, and keep any re-wording inside one: it paints into a fixed-height row above the stat list, and a
## second line would push the list down — the menus-must-not-resize-with-text rule that letterboxed the map.
const CHARACTER_CREATE_STAT_RULE := "Lower a stat to free points for another."
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
## The name field's placeholder. SHARED with NameEntryDialog (the same box claims a stray dog), which is why
## it says "a name" and not "your character's name" — one line has to sit honestly in both boxes. The trailing
## ellipsis is the authored affordance for "type here", the same convention WALLET_DROP uses for "opens a card".
const CHARACTER_NAME_PLACEHOLDER := "Enter a name…"
## Shown under the name field (and gating Begin) while the name is blank — a run must be NAMED before it can start.
const CHARACTER_CREATE_NAME_REQUIRED := "Name your character to begin."

## The implant-purchase step (implant_choice.gd) — New Game's SECOND screen, after character creation's
## Begin: fit starting chips ON CREDIT — each is billed at its authored Item.value against the starting
## wallet, and the balance is allowed to go NEGATIVE (start the run in debt). The Ledger rates the creation
## BUILD first (EconomySettings.credit_rating_for/credit_limit_for), and the cart can never bill past the
## limit that rating earns. THREE stacked lines: this standing explainer, then the VERDICT (a whole template
## per score band, implant_choice_verdict) and the FILED REASON (implant_choice_reason) below it. Buying
## nothing is the default. Chip rows paint Item.label() / AbilityRegistry.display_name_for /
## Zorkmids.money_text — only the chrome lives here; the tally line is composed by implant_choice_tally.
const IMPLANT_CHOICE_TITLE := "Starting Implants"
const IMPLANT_CHOICE_HINT := "Implants go on your tab — whatever you fit is billed against your starting zorkmids.\nThe Ledger rates the build, then sets the line."
## The PINNED footer tally under the roster: the running implant bill + the resulting starting balance +
## the credit still extendable (limit + starting money − bill; the roster greys rows that no longer fit it).
const IMPLANT_CHOICE_TALLY := "Implant bill: {cost}  ·  Starting zorkmids: {balance}  ·  Credit left: {credit}"

## THE LEDGER'S VERDICT on the creation build — one WHOLE template per score band, SELECTED by the key
## EconomySettings.credit_rating_for returns (never a prose fragment glued to a number; re-wording a band here
## can never change what the bank actually does). The creditor is "the Ledger", the same always-online thing
## the first-launch terms gate says keeps the Record — the entity financing your body-mods is the entity that
## remembers what you do with them. Keep every line under ~100 chars: it paints on an 11px autowrapped band.
const IMPLANT_CREDIT_BAND_NO_FILE := "No file — {score}. Nothing on record to price. The Ledger will advance you {money}."
const IMPLANT_CREDIT_BAND_DECLINED := "Declined — {score}. Nothing here we could repossess. You're good for {money}."
const IMPLANT_CREDIT_BAND_SUBPRIME := "Subprime — {score}. No trade, no assets, no notable features. You're good for {money}."
const IMPLANT_CREDIT_BAND_SERVICEABLE := "Serviceable — {score}. No enthusiasm, no objection. You're good for {money}."
const IMPLANT_CREDIT_BAND_BANKABLE := "Bankable — {score}. We can price this. You're good for {money}."
const IMPLANT_CREDIT_BAND_PREFERRED := "Preferred debtor — {score}. We like your odds of living long enough. You're good for {money}."

## The FILED REASON — the adverse-action notice parody: the one underwriting line the build falls furthest
## under, or a commendation when nothing is short. Whole templates keyed like the bands above. "Notable
## Cowardice" is a callback to the standing heading the terms gate files declined choices under.
const IMPLANT_CREDIT_REASON_NONE := "Noted in your favour: a specialty the Ledger can insure."
const IMPLANT_CREDIT_REASON_NO_FILE := "Filed reason: no established identity. The Ledger has no notes on you."
const IMPLANT_CREDIT_REASON_UNSPENT := "Filed reason: allocation left undrawn — see 'Notable Cowardice'."
const IMPLANT_CREDIT_REASON_THIN_TRADE := "Filed reason: no trade of record — allocation spread too thin to price."
const IMPLANT_CREDIT_REASON_NO_INCOME := "Filed reason: no visible means of support."
const IMPLANT_CREDIT_REASON_MORTALITY := "Filed reason: life expectancy under the repayment term."
const IMPLANT_CREDIT_REASON_EXPOSURE := "Filed reason: pledged attributes exceed recoverable value."
## The one reason you can fix TODAY — walk to a terminal and pay — so it outranks every build complaint.
const IMPLANT_CREDIT_REASON_DELINQUENT := "Filed reason: unsatisfactory payment history."
## The name-entry modal's BUILD-TIME card title. NameEntryDialog re-titles the card on every open() with the
## caller's composed prompt (claim_name_dialog, routed through MenuStyle.title_text for the skin's casing), so
## this is only what the card is CONSTRUCTED with. Deliberately not shared with CHARACTER_CREATE_NAME_LABEL —
## that one labels the character-creation name FIELD, and a locale may word the two differently.
const NAME_DIALOG_TITLE := "Name"

const SHOP_TITLE := "TRADE"
## The trade screen's two column headings. The parenthetical says what a CLICK does, because the two grids
## take OPPOSITE actions on tiles that look identical — the same shape as the INSTALL_* and BENCH_* heading
## pairs. Two spaces before it: this file's column breath, not padding.
const SHOP_FOR_SALE_HEADING := "For sale  (click to buy)"
const SHOP_YOUR_ITEMS_HEADING := "Your items  (click to sell)"
## The wallet readouts over those columns.
## ⭐PLAYER_WALLET IS SHARED — the shop, the chip installer and the gunsmith bench all paint it through
## wallet_you() — so it must stay SIDE-NEUTRAL. Folding the shop's verb in ("You · sell") would read as a
## lie on the two tills that only ever take money; giving the shop its verb back is a shop-side template.
const SHOP_MERCHANT_WALLET := "Merchant: {money}"
const PLAYER_WALLET := "You: {money}"

## THE WALLET ROW + its AmountPrompt — money is not an inventory item, so these are the whole vocabulary of
## the widget that replaced the backpack coin tile. WALLET_ROW is the readout (the backpack + loot screens
## both paint it); DROP / STASH caption the button that opens the prompt AND the prompt's own commit, so the
## verb the player pressed is the verb they confirm.
## TWO SPACES between the noun and the number — the readout's column look, not padding (inventory_weight and
## bench_gun space their columns the same way). The DROP / STASH verbs keep a trailing ELLIPSIS because they
## OPEN the amount card rather than committing anything; the card's own commit button is handed the same
## caption today, which is why the ellipsis reads oddly there (see the note on ask()'s confirm_caption).
const WALLET_ROW := "Zorkmids  {money}"
const WALLET_DROP := "Drop…"
const WALLET_STASH := "Stash…"
## The amount card's TITLE, in natural casing: AmountPrompt.ask routes it through MenuStyle.title_text, which
## is the one place casing is decided (skin.uppercase_titles paints these "DROP ZORKMIDS" today) — the
## INSTALL_SCREEN_TITLE rule. An uppercase_titles = false skin must still get the authored wording.
const WALLET_DROP_TITLE := "Drop Zorkmids"
const WALLET_STASH_TITLE := "Stash Zorkmids"
## The card's field placeholder and its two fill chips. One word each: the chips sit side by side in a row
## that shrink-wraps the card, so a longer caption widens the whole prompt rather than the button.
const AMOUNT_PLACEHOLDER := "amount"
const AMOUNT_ALL := "All"
const AMOUNT_HALF := "Half"
## The cap line under the title — what the prompt will actually let you commit, never the raw wallet.
const AMOUNT_AVAILABLE := "You have {money}"

const INSTALL_TITLE := "INSTALL"
## The two section headings, in the SHOP_FOR_SALE_HEADING mold: the heading names whose chips they are, the
## parenthetical says what a click does. ⭐ONE VERB across both — "install" — and the parentheticals differ
## only by the PAYMENT. They used to read "(click to install)" and "(click to fit)", which made a player work
## out whether fitting and installing were two different operations on one screen. They are not.
const INSTALL_CARRIED_HEADING := "Your chips  (click to install)"
const INSTALL_STOCK_HEADING := "For sale  (click to buy & install)"
## The ARMED caption a row swaps to on its first click, before the second click actually charges. Installing
## spends money AND consumes the chip, so the row states the price at the moment of commitment rather than
## letting one click do both — the em dash and money phrase match respec_button / heal_button, the other two
## captions in the game that are the last thing pressed before a debit. Read it through chip_install_confirm().
const CHIP_INSTALL_CONFIRM := "Confirm — {cost}"
## The empty-section line in BOTH install lists (you carry no installable chip / the mechanic stocks none).
## Deliberately NOT the shop's EMPTY_LIST "(empty)" — the install sections read "(none)" today and this is a pure
## move of that literal; unifying the two wordings is a copy call, not a refactor.
const INSTALL_NONE := "(none)"
## The install panel's CONSTRUCTION-time title, cased by make_title/title_text ("INSTALL" under the default
## skin); open_install re-titles with install_title(mechanic) before the panel is ever shown. Kept in natural
## casing — unlike the all-caps INSTALL_TITLE above — because title_text owns casing, and an
## uppercase_titles = false skin must still get the authored wording.
const INSTALL_SCREEN_TITLE := "Install"
## The Level-Up screen's build-time panel title, shown until open_level_up re-titles the Label with the
## station's name (level_up_title, whose blank-name branch is this same English). Same fallback-const idiom
## as SHOP_TITLE / INSTALL_TITLE.
const LEVEL_UP_TITLE := "Level Up"

## The loot screen's four MODES: a panel title (the blank-name fallback loot_title selects) and the SOURCE
## column's heading for each. The titles are the VERB the screen is doing to somebody, the headings are the
## NOUN the left grid holds — that pairing is the only thing distinguishing a corpse from a live pocket from
## a crate, since all four modes draw the identical two-grid layout. The all-caps titles are the SHOP_TITLE /
## INSTALL_TITLE idiom (a station's fallback title); the headings are title-case like LOOT_YOU_HEADING.
const LOOT_TITLE := "LOOTING"
const LOOT_CORPSE_HEADING := "Corpse"
const LOOT_PICKPOCKET_TITLE := "PICKPOCKETING"
const LOOT_POCKETS_HEADING := "Pockets"
const LOOT_EXCHANGE_TITLE := "EXCHANGING GEAR"
const LOOT_THEIR_GEAR_HEADING := "Their Gear"
const LOOT_CONTAINER_TITLE := "CONTAINER"
const LOOT_CONTAINER_HEADING := "Container"
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
const CHESS_INPUT_HINT := "[PH] Type a move (e2e4 or Nf3) · Enter to play · Esc to leave"
const CHESS_BLINDFOLD_HINT := "[PH] Blindfold: track the board from the move log · type e2e4 or Nf3 · Esc to leave"
const CHESS_BLINDFOLD_BADGE := "[ BLINDFOLD ]"
const CHESS_NO_BOARD_HINT := "[PH] No board — play it in your head.\nInstall the Board Visualizer chip to see the position."
## The chess panel's CONSTRUCTION-time title. MenuStyle.make_title cases it through title_text (so it paints
## "CHESS" under the default skin), and open_match re-titles with chess_title(opponent) before the panel is ever
## shown — this is only the pre-match placeholder. Natural casing on purpose: casing is title_text's job (the one
## chokepoint skin.uppercase_titles flips), never baked into the copy.
const CHESS_SCREEN_TITLE := "Chess"

const HEAL_FULLY_HEALED := "[PH] Fully healed"
## The heal card's status block — FOUR whole templates selected by (limb damage, affordability), so no
## caller ever assembles the block from line fragments. The limb line and the can't-afford note are
## authored INSIDE each variant; HealScreen pads the rendered block to a constant height (see heal_screen.gd).
const HEAL_STATUS := "[PH] HP  {hp} / {max_hp}\nYour zorkmids: {amount}"
const HEAL_STATUS_LIMB := "[PH] HP  {hp} / {max_hp}\n— limb damage\nYour zorkmids: {amount}"
const HEAL_STATUS_CANT_AFFORD := "[PH] HP  {hp} / {max_hp}\nYour zorkmids: {amount}\n— can't afford"
const HEAL_STATUS_LIMB_CANT_AFFORD := "[PH] HP  {hp} / {max_hp}\n— limb damage\nYour zorkmids: {amount}\n— can't afford"
## The heal card's CONSTRUCTION-time title, cased by make_title/title_text ("HEAL" under the default skin);
## open_heal re-titles with heal_title(healer) before the card is ever shown, so this is only the placeholder.
## Natural casing on purpose — title_text is the single casing chokepoint (skin.uppercase_titles).
const HEAL_SCREEN_TITLE := "Heal"
const RESPEC_NO_PERKS := "[PH] (no perks unlocked)"
const RESPEC_NOTHING := "[PH] Nothing to respec"
## The respec card's title as BUILT — make_title's constructor argument, title-case because
## MenuStyle.title_text applies the skin's casing. Distinct from respec_title(), which RE-titles the
## same Label with the station's name when the modal opens; only that runtime path carries the
## already-cased "RESPEC" fallback.
const RESPEC_CARD_TITLE := "Respec"
## Keep this SHORT: it swaps onto a rebind button pinned to MenuSkin.rebind_button_width (120px English
## budget incl. margins, clip_text on) — a longer prompt clips rather than growing the button, so it must
## read whole at ~100px (the shipped art button boxes carry 10+10 margins).
const OPTIONS_BIND_PROMPT := "Press a key…"
## The Music Folder row's button caption while no custom folder is chosen. Says what the DEFAULT actually
## does rather than printing an empty path: each in-world radio plays out of its own authored folder until
## you point them all at one of yours.
const OPTIONS_MUSIC_FOLDER_DEFAULT := "Default (each radio's own folder)"
## The OS folder-picker's window title (a real FileDialog, so this is chrome the desktop paints, not the skin).
const OPTIONS_CHOOSE_MUSIC_FOLDER := "Choose a music folder"
## Window-mode choice captions. DISPLAY text only, but the caller's ARRAY ORDER IS BEHAVIOUR — item INDEX
## maps straight to the window mode, so re-wording one can never select a different mode.
## ⭐ONE WORD EACH, and keep it that way: these paint into the cycler's value button, which is cap_button()'d
## between two arrows on the two-up Video page — it CLIPS rather than widening, and the shipped art seats about
## eleven English characters. "Borderless Fullscreen" shipped clipped to "[PH] Window"-length nonsense; the
## distinction that survives at this width is borderless-window versus exclusive, which these two words carry.
const OPTIONS_WINDOWED := "Windowed"
const OPTIONS_BORDERLESS := "Borderless"
const OPTIONS_EXCLUSIVE_FULLSCREEN := "Fullscreen"
## Presentation choice captions (options_menu _emit_presentation). DISPLAY text only, but the caller's ARRAY
## ORDER IS BEHAVIOUR — item INDEX maps straight to Settings.PRESENTATION_* (0 = native-res, 1 = the low-res
## PS1 buffer). Same one-word clip budget as the window modes above: "Retro (Pixelated)" shipped sliced to
## "Retro (Pix". Named for what the PICTURE looks like, not for the render path — "Crisp" is a thing a player
## can see, "High Fidelity" is a thing an engine does.
const OPTIONS_PRESENTATION_HIGH_FIDELITY := "Crisp"
const OPTIONS_PRESENTATION_RETRO := "Retro"
## The colourblind-mode choice captions (options_menu). DISPLAY text only, but the caller's ARRAY
## ORDER IS BEHAVIOUR — the cycler row maps item INDEX straight to the Settings mode, so the four stay
## listed None-first at the call site regardless of wording here.
const OPTIONS_CB_NONE := "None"
const OPTIONS_CB_PROTANOPIA := "Protanopia"
const OPTIONS_CB_DEUTERANOPIA := "Deuteranopia"
const OPTIONS_CB_TRITANOPIA := "Tritanopia"
## The Colour Depth cycler's captions (options_menu). Index-mapped to Settings.COLOR_QUANTIZE_LEVELS, so the
## ARRAY ORDER AT THE CALL SITE IS BEHAVIOUR — an index picks a row of that table, not a caption. Named for the
## HARDWARE depth rather than a colour count on purpose: "15-bit" is what a PlayStation framebuffer was called,
## and "32768 colours" is a number nobody recognises. Kept SHORT — the cycler's value button clips rather than
## widening the row (MenuStyle.cap_button), and the longest of these has to read whole beside two arrows.
const OPTIONS_CQ_AUTHORED := "Default"
const OPTIONS_CQ_24BIT := "24-bit (Off)"
const OPTIONS_CQ_16BIT := "16-bit"
const OPTIONS_CQ_15BIT := "15-bit (PS1)"
const OPTIONS_CQ_12BIT := "12-bit"
const OPTIONS_CQ_9BIT := "9-bit"
const OPTIONS_CQ_8BIT := "8-bit"
const OPTIONS_CQ_6BIT := "6-bit"
const OPTIONS_CQ_3BIT := "3-bit"
## The difficulty dropdown's captions — index-mapped to DifficultySettings.Level, the same order contract.
const OPTIONS_DIFFICULTY_EASY := "Easy"
const OPTIONS_DIFFICULTY_NORMAL := "Normal"
const OPTIONS_DIFFICULTY_HARD := "Hard"
## The resolution dropdown's row for a window size outside the preset list — {w}/{h} ride in as digit
## strings. The preset rows themselves ("1280 x 720") are digits-only non-prose and stay at the call site.
const OPTIONS_RESOLUTION_CUSTOM := "{w} x {h} (custom)"
## The resolution row's caption for a preset that only fits this screen once the caption + borders are dropped —
## the native size on its own monitor, placed as a borderless window covering the screen (Settings.needs_borderless).
## Said out loud because the title bar visibly disappearing otherwise reads as a bug rather than the chosen setting.
const OPTIONS_RESOLUTION_BORDERLESS := "{w} x {h} (borderless)"
## The Options overlay's own chrome — painted by scripts/ui/options_menu.gd's _bind_ui: the panel title plus
## the bottom button row (Save / Load / Main Menu / Apply / Revert / Close / Quit Game, in paint order; "Close"
## reuses the generic CLOSE above). The tab pages' ROW labels are authored SettingSpec.label / tab_label fields in
## resources/settings/SettingsCatalog.tres + resources/input/ActionCatalog.tres — never literals, and never here.
const OPTIONS_TITLE := "Settings"
## Shown only in-game (open() hides it at the start screen) — returns to the start menu without quitting the app.
const OPTIONS_MAIN_MENU := "Main Menu"
## Shown only in-game, like Main Menu — closes Options and opens the SaveLoadScreen (the manual slot menu).
## Deliberately NOT a reuse of SAVE_LOAD_TITLE: that const is the slot screen's own panel title, an independent
## surface, and re-wording one must never silently re-word the other.
const OPTIONS_SAVE_LOAD := "Save / Load"
const OPTIONS_APPLY := "Apply"
const OPTIONS_REVERT := "Revert"
const OPTIONS_QUIT_GAME := "Quit Game"

## The main menu's button column (StartMenu — an authored scene, captions painted in _bind_ui). "Continue" is
## only shown when a save file exists; "New Game" opens character creation before anything is overwritten. Deliberately separate from the
## in-game menus' same-word labels (MENU_TAB_*, CHARACTER_CREATE_*) — one surface can be reworded or
## translated without dragging the other with it.
const START_MENU_CONTINUE := "Continue"
const START_MENU_NEW_GAME := "New Game"
const START_MENU_SETTINGS := "Settings"
const START_MENU_QUIT := "Quit Game"
## "Load Game" — opens the SaveLoadScreen in its LOAD-only menu mode; only shown when a manual save exists
## (StartMenu._bind_ui checks has_quicksave / has_slot). Distinct from START_MENU_CONTINUE on purpose:
## Continue resumes the lean AUTOSAVE profile, this loads an exact-snapshot quicksave/slot file — the two-tier
## save language must stay visible in the copy (CLAUDE.md "Save semantics must be explicit").
const START_MENU_LOAD_GAME := "Load Game"

## The manual Save / Load slot screen (scripts/ui/save_load_screen.gd) — its own surface family, one const per
## painted element (the OPTIONS_* idiom). SAVE_LOAD_TITLE is the panel title (make_title cases it per skin);
## deliberately NOT shared with OPTIONS_SAVE_LOAD below — that one labels the Options BUTTON that opens this
## screen, an independent surface a locale may word differently (the QUEST_JOURNAL_TITLE / MENU_TAB_JOURNAL rule).
const SAVE_LOAD_TITLE := "Save / Load"
## The quicksave row's name — a LOAD-only row (F5 owns writing it); the Slot rows use the SAVE_LOAD_SLOT template.
const SAVE_LOAD_QUICKSAVE_ROW := "Quicksave"
## One manual slot's row name; {n} = the 1-based slot number (TextFormat.subst via save_slot_label, never %).
const SAVE_LOAD_SLOT := "Slot {n}"
## The caption on a row whose file doesn't exist yet. It sits in the same column an occupied row fills with
## its level name and timestamp (SAVE_SLOT_CAPTION), so one bare word is the whole difference between
## "nothing here" and a save — never a parenthesised "(empty)", which would read as a state of the SAVE.
const SAVE_LOAD_EMPTY := "Empty"
const SAVE_LOAD_SAVE := "Save"
const SAVE_LOAD_LOAD := "Load"
## The overwrite-confirm card's title (Save pressed on an OCCUPIED slot) — the card reuses CONFIRM / CANCEL.
const SAVE_LOAD_OVERWRITE_TITLE := "Overwrite this save?"
## Screen-local failure lines (the TOAST_QUICKSAVE_FAILED wording idiom, painted on the panel's status hint
## instead of toasted): a save that didn't persist (disk full / permission / no player), a load whose file
## vanished or won't parse.
const SAVE_LOAD_SAVE_FAILED := "Save failed"
const SAVE_LOAD_LOAD_FAILED := "Load failed"
## An existing slot's metadata caption — TWO whole templates SELECTED on whether the save carries a resolvable
## authored level name (save_slot_caption): level display name + modified time, or the time alone. The
## separator is a MIDDLE DOT (U+00B7) with three spaces each side — the character_inspect_summary idiom.
## Both tokens are VALUES (an authored LevelData.display_name and a formatted timestamp), never msgids of ours.
const SAVE_SLOT_CAPTION := "{level}   ·   {time}"
const SAVE_SLOT_CAPTION_NO_LEVEL := "{time}"
## Player-menu tab-strip labels (the Deus Ex / Pip-Boy tab group). DISPLAY text only: PlayerMenus routes
## between the six screens on StringName keys (PlayerMenus.TABS); these are just what the strip's buttons
## paint (PlayerMenus.TAB_LABELS maps key -> label). Re-wording one here can never change routing.
const MENU_TAB_INVENTORY := "Inventory"
const MENU_TAB_STATS := "Stats"
## Deliberately NOT a reuse of IMPLANT_CHOICE_TITLE's wording family: that titles New Game's implant-purchase
## (on-credit) step, an independent surface — this labels the in-game tab-strip button.
const MENU_TAB_IMPLANTS := "Implants"
const MENU_TAB_REPUTATION := "Reputation"
const MENU_TAB_JOURNAL := "Journal"
## The MAP tab (map_screen.gd — the sixth sibling, default M). Deliberately NOT shared with the Options ->
## Accessibility "Minimap" / "Map Zoom" row labels: those name SETTINGS rows and a locale may word a settings
## row differently from a tab chip (the MENU_TAB_JOURNAL / QUEST_JOURNAL_TITLE rule).
const MENU_TAB_MAP := "Map"
## The Journal's EMPTY STATE — the whole screen when nothing is tracked, so it is the one line that has to
## teach where quests come from. TWO LINES, the MAP_HINT shape: the state, then the action that ends it. A
## bare "No quests yet." is a status readout on a blank panel and answers nothing a player would ask next.
## The line break is authored (make_hint also autowraps, so a narrower panel simply reflows the second line —
## it never widens the tab).
const QUEST_JOURNAL_EMPTY := "No quests yet.\nAccept a job from someone in the city and its objectives are tracked here."
## The Journal panel's own title, painted by QuestJournal via MenuStyle.make_title (which routes it through
## title_text, so the SKIN owns the casing — keep this title-case). Deliberately NOT a reuse of
## MENU_TAB_JOURNAL: that const is the tab STRIP button's label, an independent surface, and re-wording one
## must never silently re-word the other.
const QUEST_JOURNAL_TITLE := "Journal"
const REPUTATION_EMPTY := "[PH] No factions defined."
## The Reputation screen's own heading. Deliberately NOT MENU_TAB_REPUTATION even though the English
## matches: that one labels the tab-strip BUTTON (PlayerMenus.TAB_LABELS) and a locale may want a shorter
## word on a tab than on the heading.
const REPUTATION_TITLE := "Reputation"
## The Stats screen's panel TITLE (MenuStyle.make_title cases it per skin.uppercase_titles). Deliberately
## its OWN const rather than reusing MENU_TAB_STATS / CHARACTER_CREATE_STATS_TAB: those label the tab-strip
## button and the creation tab, and a locale may want a different word for a heading than for a tab chip.
const STATS_SCREEN_TITLE := "Stats"
## The Stats screen's portrait-column button — hands off to the fullscreen CharacterInspectScreen
## (full body + the equipped weapon, drag to rotate).
const STATS_INSPECT_BUTTON := "Inspect"
## The Implants tab (implants_screen.gd — the fifth Pip-Boy tab): its two section headings (cased by
## MenuStyle.title_text, the chip-install heading idiom), the per-section empty line, the dim "click to
## switch an implant off" hint under the INSTALLED toggle rows, and the "how to get a carried chip fitted"
## hint under the carried rows. Deliberately NOT reuses of the INSTALL_* consts: those paint the
## ChipInstallScreen (the paid mechanic modal), an independent surface.
const IMPLANTS_INSTALLED_HEADING := "Installed"
## The toggle verb, under the installed rows. Switching one OFF keeps it installed (it just stops working)
## — the copy must not read as uninstalling, or a player will fear losing a chip they paid for. Names BOTH
## directions: the rows carry no on/off word of their own (an off row is only dimmer), so a player looking at
## a dim row needs this line to tell them the click that dimmed it is the click that brings it back.
const IMPLANTS_TOGGLE_HINT := "Click an implant to switch it on or off — it stays installed."
## Says NOT INSTALLED in the heading itself: a carried chip and a fitted one are the same row shape one
## section apart, and "In your bag" alone would leave the difference to be inferred from position.
const IMPLANTS_CARRIED_HEADING := "In your bag — not installed"
const IMPLANTS_CARRIED_HINT := "A chip mechanic can fit these."
## The per-section empty line. Reads like INSTALL_NONE's "(none)" but is deliberately its OWN const —
## one const per painted surface, so re-wording the install screen never re-words this tab.
const IMPLANTS_NONE := "(none)"

## The Map tab (map_screen.gd). MAP_HINT is the tab's WHOLE tutorial — it names the pointer gestures nothing
## on screen announces (a click pins, a drag pans, the wheel zooms) — and it is painted as an EMPTY STATE over
## the plan itself rather than in the footer. It lived in the footer once and never fitted: in the strip the
## row's buttons left over it shipped ellipsized to "Click to pi…", which teaches nothing. On the plan
## it has the whole panel width, and it earns its space by only appearing when there is nothing else to look at
## (no pins on this level, nothing selected) — the first pin the player drops takes it away, and an empty floor
## teaches again. The double space between its two sentences is the file's usual breath, not padding.
const MAP_HINT := "Click to drop a pin.   Drag to pan, scroll to zoom."
## What the FOOTER hint says instead, and the one fact the footer genuinely owes the player: this tab is
## NORTH-UP while the HUD minimap they already know is heading-up by default, and without saying so the two
## pictures disagreeing reads as a bug. Three words on purpose — the footer row is fixed-height, a wrapping
## hint would shove the zoom controls (menus-dont-shift-with-text), and this one fits the strip the buttons
## leave over at any panel width instead of being trimmed to nothing.
const MAP_NORTH_UP := "North is up."
## The three footer buttons. They exist so the zoom and the pan have a focusable pad/keyboard path at all (the
## atm_screen "a control a pad can never land on is not a path" rule) — a wheel-and-drag-only affordance is
## unreachable without a mouse. RECENTRE puts the view back on the player: panning is the one gesture that does
## not undo itself, since the caret can be dragged clean off the view with nothing left pointing home.
const MAP_ZOOM_IN := "Zoom In"
const MAP_ZOOM_OUT := "Zoom Out"
const MAP_RECENTRE := "Recentre"
## The current multiplier, a whole template with the number substituted as a VALUE (TextFormat.subst + num).
const MAP_ZOOM_READOUT := "{zoom}x"
## Shown in the map panel instead of the plan when there is no floor to draw: a level whose navmesh has not
## been baked (the whole map is one empty band) or a boot frame before the first slice. Deliberately its own
## const rather than a reuse of EMPTY_LIST's "(empty)" — this names a MISSING BAKE, which is a level-authoring
## fault a designer should recognise, not an empty collection.
const MAP_NO_DATA := "No map data for this floor."

## --- The player's own map pins (waypoints + notes) ---------------------------------------------------------
## Copy for the fourth marker channel: the Map tab's pin controls (the footer's two pad-path buttons and the
## floating card that carries the selection's details), the editor card a pin is RE-authored in, and the
## cues the in-world Mark Waypoint key answers with — one confirmation and two refusals.
##
## ⭐NOTHING HERE HOLDS A PIN'S OWN TEXT. A waypoint's name and note are typed by the PLAYER, so they are data,
## not copy: they are never looked up as a msgid (every Control that paints one sets
## auto_translate_mode = AUTO_TRANSLATE_MODE_DISABLED — the menu_style.gd translation-seam rule) and they
## never pass through this file. What lives here is the chrome AROUND that text.
## The two FOOTER buttons: the pad's selection path (cycles pin -> pin -> none, because Track/Edit/Delete all
## need a selected pin and a click is mouse-only) and its placement path (places at the VIEW CENTRE, which
## together with panning is what gives a pad the whole map to pin on). Captions must be real words, not
## icons: MenuStyle.cap_button clips a Button's text, so a caption is also the only thing giving these
## buttons a width in their row.
const MAP_PIN_NEXT := "Next Pin"
const MAP_PIN_ADD := "Place Pin"
## The floating pin card's button row, over the map's bottom-left corner while a pin is selected. TRACK and
## UNTRACK are ONE button whose caption swaps with the pin's state — two whole words rather than a "Track"
## with an appended negation, because a locale may not build the pair that way. All four are bare VERBS: the
## card is narrow (three buttons across ~220 px) and its subject is already named on the line above them, so
## "Edit Pin" would spend width restating what the card is about.
const MAP_PIN_EDIT := "Edit"
const MAP_PIN_DELETE := "Delete"
const MAP_PIN_TRACK := "Track"
const MAP_PIN_UNTRACK := "Untrack"
## The selected pin's name line on that card. The pin's own name is substituted as a VALUE — never
## concatenated — so a locale may put it anywhere in the line, and so player-typed text is never a msgid.
const MAP_PIN_SELECTED := "{name}"
## Shown under the selected pin's name when it carries no note, so the note row keeps its height and the
## card cannot resize as the selection moves between an annotated pin and a bare one.
const MAP_PIN_NO_NOTE := "No note."
## The editor card. It has ONE mode now — placement is instant (a click pins immediately with a seeded name),
## so the card is only ever opened on a pin that already exists. Title, then field captions, then commit.
## NAME is deliberately its own const rather than a reuse of NAME_DIALOG_TITLE / CHARACTER_CREATE_NAME_LABEL:
## those title a modal and label the creation field, and one surface must be re-wordable without the others.
const WAYPOINT_EDIT_TITLE := "Edit Pin"
const WAYPOINT_NAME_LABEL := "Name"
const WAYPOINT_NOTE_LABEL := "Note"
const WAYPOINT_NOTE_PLACEHOLDER := "What's here, or what you meant to do."
const WAYPOINT_ICON_LABEL := "Mark"
const WAYPOINT_TINT_LABEL := "Colour"
const WAYPOINT_SAVE := "Save"
## The seeded name for a pin the player has not named. A whole template with the ordinal as a VALUE, so the
## word order is the locale's; the number is the pin's position in this level's list, which is what makes two
## unnamed pins distinguishable at a glance instead of both reading the same.
##
## ⭐ITS TWO SEED SITES STILL RUN IT THROUGH PlayerText.strip_prefix (map_screen.gd::_pin_seed_name and
## waypoint_marker.gd), and that call is now a NO-OP. It is kept on purpose: this is the one const in the file
## whose rendering is SAVED as player data, so the guard against a `[PH] ` marker reaching a save file must not
## depend on this line staying authored — re-marking it during a copy pass would otherwise ship the marker into
## every profile silently.
const WAYPOINT_DEFAULT_NAME := "Pin {n}"
## The in-world Mark Waypoint key's confirmation toast. That key no longer opens a name box at all — it pins
## the aimed point (or your feet), names it from WAYPOINT_DEFAULT_NAME and TRACKS it in one press, so the
## toast is the only thing telling the player which pin the compass pip that just appeared belongs to. The
## name is substituted as a VALUE — it is player-typed data, never part of a msgid — and arrives with its
## `[PH] ` marker already stripped (PlayerText.strip_prefix), a no-op now that the seed is authored but kept
## for the reason spelled out on WAYPOINT_DEFAULT_NAME.
const WAYPOINT_MARKED := "Marked: {name}"
## The refusal when the level is already at WaypointBook.MAX_PER_LEVEL. It names the cap as a VALUE so the
## number and the sentence stay one template, and it is a REFUSAL rather than a silent drop because a pin that
## does not appear reads exactly like a broken map.
const WAYPOINT_FULL := "Map is full — {max} pins on this level."
## The OTHER refusal: a level that records no path (a code-built LevelData) has no ledger to file a pin
## into. Its own copy because telling that player "the map is full" over an empty map is a lie.
const WAYPOINT_NO_LEVEL := "Nowhere to file a pin here."

## The fullscreen "inspect your character" showcase (opened from the Stats screen, NOT a Pip-Boy tab): its
## panel title. Deliberately its own const rather than sharing CHARACTER_CREATE_TITLE — same surface family,
## different screen, and a locale may word them differently.
const CHARACTER_INSPECT_TITLE := "Character"

## The Fallout-style stealth badge painted top-centre by PlayerHud.set_stealth_level — ONE whole badge per
## StealthStatus.Level, SELECTED by the level (never "[ " + a state word + " ]": the brackets and the word are
## one authored unit a locale may reshape). Listed in StealthStatus.Level order (best -> worst). The spaces
## inside the brackets are part of the badge look — same shape as CHESS_BLINDFOLD_BADGE. Each state's COLOUR is
## a PlayerHud theme override, not text, so re-wording one of these can never change the readout's colouring.
const STEALTH_HIDDEN := "[ HIDDEN ]"
const STEALTH_DETECTED := "[ DETECTED ]"
const STEALTH_CAUTION := "[ CAUTION ]"
const STEALTH_DANGER := "[ DANGER ]"

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


## The player-facing noun for a BodyModelSwap part key (torso / head / arm_l / arm_r / leg_l / leg_r), used to
## name a flying body-part gib. Left and right share one noun — the prompt says "Arm", not "Left Arm", because
## a severed limb tumbling in the air has no side any more. An unrecognised key returns "", which pick_up()
## degrades to the plain "Pick Up" prompt.
static func body_part(key: String) -> String:
	match key:
		"head":
			return BODY_PART_HEAD
		"torso":
			return BODY_PART_TORSO
		"arm_l", "arm_r":
			return BODY_PART_ARM
		"leg_l", "leg_r":
			return BODY_PART_LEG
	return ""


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


## Quest-REWARD overflow (QuestTracker._grant_quest_rewards) — names the loss as reward items. The generic
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


## The backpack / loot-screen wallet ROW — the readout that took over from the coin tile, and the row whose
## button opens the AmountPrompt. Whole money phrase (never "<amount>" + a " zm" glued on at the call site).
static func wallet_row(amount: float) -> String:
	return TextFormat.subst(WALLET_ROW, {"money": Zorkmids.money_text(amount)})


## The AmountPrompt's cap line — how much the prompt will actually let you commit.
static func amount_available(amount: float) -> String:
	return TextFormat.subst(AMOUNT_AVAILABLE, {"money": Zorkmids.money_text(amount)})


## The Ledger's VERDICT line on the pending build: one whole band template SELECTED by key, carrying the
## score as a bare number and the limit as a whole money phrase. An unknown key degrades to the no-file
## wording rather than painting blank — a band added to EconomySettings without a template here still reads.
static func implant_choice_verdict(band: StringName, score: int, limit: float) -> String:
	var template := IMPLANT_CREDIT_BAND_NO_FILE
	match band:
		EconomySettings.BAND_DECLINED: template = IMPLANT_CREDIT_BAND_DECLINED
		EconomySettings.BAND_SUBPRIME: template = IMPLANT_CREDIT_BAND_SUBPRIME
		EconomySettings.BAND_SERVICEABLE: template = IMPLANT_CREDIT_BAND_SERVICEABLE
		EconomySettings.BAND_BANKABLE: template = IMPLANT_CREDIT_BAND_BANKABLE
		EconomySettings.BAND_PREFERRED: template = IMPLANT_CREDIT_BAND_PREFERRED
	return TextFormat.subst(template, {"score": score, "money": Zorkmids.money_text(limit)})


## The single FILED REASON under the verdict — one whole template per reason key, no substitution at all
## (the bank cites a line, it doesn't quote your numbers back at you). Unknown keys read as the commendation.
static func implant_choice_reason(reason: StringName) -> String:
	match reason:
		EconomySettings.REASON_NO_FILE: return IMPLANT_CREDIT_REASON_NO_FILE
		EconomySettings.REASON_UNSPENT: return IMPLANT_CREDIT_REASON_UNSPENT
		EconomySettings.REASON_THIN_TRADE: return IMPLANT_CREDIT_REASON_THIN_TRADE
		EconomySettings.REASON_NO_INCOME: return IMPLANT_CREDIT_REASON_NO_INCOME
		EconomySettings.REASON_MORTALITY: return IMPLANT_CREDIT_REASON_MORTALITY
		EconomySettings.REASON_EXPOSURE: return IMPLANT_CREDIT_REASON_EXPOSURE
		EconomySettings.REASON_DELINQUENT: return IMPLANT_CREDIT_REASON_DELINQUENT
	return IMPLANT_CREDIT_REASON_NONE


## The implant screen's footer tally: the running bill for the checked chips + the post-debit starting
## balance (negative = the run starts in debt; the balance label is tinted danger by the screen) + the
## credit still extendable under the bank's limit (what the roster's row-gating measures against).
static func implant_choice_tally(cost: float, balance: float, credit_left: float) -> String:
	return TextFormat.subst(IMPLANT_CHOICE_TALLY,
		{"cost": Zorkmids.money_text(cost), "balance": Zorkmids.money_text(balance),
		"credit": Zorkmids.money_text(credit_left)})


static func wallet_merchant(amount: float) -> String:
	return TextFormat.subst(SHOP_MERCHANT_WALLET, {"money": Zorkmids.money_text(amount)})


## The HUD's OWED row — shown under the zorkmid readout only while GameState.account is NEGATIVE, because a debt
## that compounds daily (LedgerAccrual, 2%/day vs savings' 0.5%) is the one balance the player must not be able to
## forget about. Solvent runs never see it, so the HUD stays clean by default. ⭐{owed} arrives as an ABSOLUTE
## value: Zorkmids.fmt prints its own minus and "Owed -240 zm" would read as a credit — the same trap the ATM
## statement documents.
const HUD_OWED := "[PH] Owed  {owed}"

static func hud_owed(owed_abs: float) -> String:
	return TextFormat.subst(HUD_OWED, {"owed": Zorkmids.money_text(owed_abs)})


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


## The respawn toast when a KILLER pocketed your wallet (death_purse_loss_fraction). `amount` = what they took
## (Player._death_wallet_lost); `killer` comes pre-masked from Player._killer_display_name, so an NPC you were never
## introduced to arrives as the lowercase indefinite "a stranger" — which is why the name sits MID-sentence and never
## opens it. Mirrors the chess_loss / long_range_kill money-toast style: one [PH] marker up front.
static func purse_taken(killer: String, amount: float) -> String:
	return TextFormat.subst("[PH] Robbed!  {money} taken by {killer}", {"money": Zorkmids.money_text(amount), "killer": killer})


## The respawn toast when NOBODY gets credit for the death (a fall, a hazard, your own grenade): the wallet spilled
## on the ground as a physics money bag at the spot you died and is still sitting there. Says WHERE, because with
## loot beacons off that line is the only thing telling the player their zorkmids are recoverable at all.
static func purse_dropped(amount: float) -> String:
	return TextFormat.subst("[PH] Purse dropped!  {money} where you fell", {"money": Zorkmids.money_text(amount)})


static func holster_forgiveness_tutorial(key: String) -> String:
	return TextFormat.subst("[PH] You provoked them. Hold [{key}] to holster your weapon and ask for forgiveness.", {"key": key})


static func gained_hp(amount: int) -> String:
	return TextFormat.subst("[PH] +{amount} HP", {"amount": amount})


static func head_crippled() -> String:
	return "[PH] Your head is crippled!"


## [PH]-marked: AI-lineage combat prose, unauthored — the release scrub must see it (it slipped through
## unmarked when the toast moved into this registry; the sibling crippled_self lines were always marked).
static func crippled_target(target_name: String, part_name: String) -> String:
	return TextFormat.subst("[PH] Crippled {name}'s {part}", {"name": target_name, "part": part_name})


static func level_up(level: int, points: int) -> String:
	return TextFormat.subst(TextFormat.plural(points,
			"Level {level}! +{points} skill point",
			"Level {level}! +{points} skill points"),
			{"level": level, "points": points})


## The character creator's points banner. Says TO SPEND rather than "remaining": the builder is zero-sum and
## opens at zero, so "remaining" would imply an allowance was handed out and then eaten. CHARACTER_CREATE_STAT_RULE
## is the line under it that explains how the number ever becomes non-zero.
static func points_to_spend(spare: int) -> String:
	return TextFormat.subst("Points to spend: {points}", {"points": spare})


## --- THE SIX LIVE-EFFECT LINES (the Stats screen's "Now:" row, and the same text inside a hover tooltip) ----
## One whole template per stat, filled with SIGNED readouts StatInfo already formatted ("+8%", "-2", "+0").
## They are the only place the sheet's derived numbers are put into words, so they name the EFFECT a player
## can feel ("aim steadiness"), never the multiplier behind it (`sway_mult`).
##
## ⭐DELIBERATELY BARE — no "[PH] " marker, and none may be re-marked. Both consumers PREFIX these: the Stats
## screen through stat_now() and StatInfo.tooltip through its own "Now: %s". A marker here therefore lands
## MID-SENTENCE ("Now: [PH] +0% gun damage"), which is exactly what shipped and what authoring these fixed.
## Same rule as the ATM_BAND_* short names and the BODY_PART_* nouns.
##
## Keep them SHORT. They paint into a stat block in a two-column grid (six blocks on one Pip-Boy tab), the
## block wraps to as many lines as it needs, and the grid has no scrollbar worth the name — the longest of
## these, larceny's four clauses, is the one that shipped clipped at the panel's bottom edge.
static func stat_effect_strength(melee: String, carry: String, max_hp: String) -> String:
	return TextFormat.subst("melee {melee}, {carry} carry, {max_hp} max HP", {"melee": melee, "carry": carry, "max_hp": max_hp})


static func stat_effect_endurance(stamina: String, regen: String) -> String:
	return TextFormat.subst("{stamina} max stamina, {regen} out-of-combat healing", {"stamina": stamina, "regen": regen})


static func stat_effect_gunplay(damage: String, steadiness: String) -> String:
	return TextFormat.subst("{damage} gun damage, {steadiness} aim steadiness", {"damage": damage, "steadiness": steadiness})


static func stat_effect_agility(speed: String) -> String:
	return TextFormat.subst("{speed} move speed", {"speed": speed})


static func stat_effect_streetwise(buys: String, sales: String, rep: String) -> String:
	return TextFormat.subst("buys {buys}, sales {sales}, rep gains {rep}", {"buys": buys, "sales": sales, "rep": rep})


## `allowance` is the priciest thing a pickpocket lift may be worth, as a bare number beside the three
## percentages. Worded "lift limit" rather than the shipped "lift value <= 50": a maths operator in player
## prose is a fragment nothing can translate, and the shorter clause is what keeps the four-clause larceny
## block inside its cell.
static func stat_effect_larceny(detection: String, takedown: String, risk: int, allowance: String) -> String:
	return TextFormat.subst("{detection} enemy detection speed, {takedown} takedown time, {risk}% caught risk, lift limit {allowance}", {"detection": detection, "takedown": takedown, "risk": risk, "allowance": allowance})


static func shop_title(name: String) -> String:
	return TextFormat.subst("TRADE — {name}", {"name": name}) if not name.is_empty() else SHOP_TITLE


## A shop sell-row for the currently-wielded weapon — the whole EQUIPPED_ROW template wrapping the composed
## row text as a value token (replaces the old EQUIPPED_SUFFIX append in ShopScreen._fill).
static func equipped_row(row_text: String) -> String:
	return TextFormat.subst(EQUIPPED_ROW, {"row": row_text})


static func install_title(name: String) -> String:
	return TextFormat.subst("INSTALL — {name}", {"name": name}) if not name.is_empty() else INSTALL_TITLE


## An ARMED chip row's caption — the second half of the two-click install. The money phrase resolves HERE
## through Zorkmids.money_text (the currency word lives there, never appended at the row), so a caller passes
## the raw charge exactly as heal_button and level_up_cost_cell take theirs.
static func chip_install_confirm(cost: float) -> String:
	return TextFormat.subst(CHIP_INSTALL_CONFIRM, {"cost": Zorkmids.money_text(cost)})


static func heal_title(name: String) -> String:
	return TextFormat.subst("HEAL — {name}", {"name": name}) if not name.is_empty() else "HEAL"


# --- THE LEDGER TERMINAL (the ATM: scripts/components/atm.gd + scripts/ui/atm_screen.gd) -------------------
# The account is ONE SIGNED number, so DEPOSIT and "settle your debt" are the same action — only the button
# caption differs, selected by sign (whole templates by state, never a fragment glued on). The creditor is
# "the Ledger", the same entity that financed your implants and that the first-launch terms gate says keeps
# the Record — never a second bank brand.

## Card title when the terminal is unnamed; open_atm re-titles per station through atm_title.
const ATM_CARD_TITLE := "[PH] LEDGER TERMINAL"
## Hover readout when the Atm carries no station_name.
const ATM_DEFAULT_PROMPT := "[PH] Ledger Terminal"
## The amount field's placeholder — the affordance that says "type a number here".
const ATM_AMOUNT_PLACEHOLDER := "[PH] amount"
## The controller-path fill chips (a pad player cannot type into a LineEdit).
const ATM_ALL_CASH := "[PH] All cash"
const ATM_HALF_CASH := "[PH] Half"
const ATM_ALL_SAVED := "[PH] All saved"
## Withdraw is one word in every state — only DEPOSIT swaps caption when you owe (see atm_deposit_button).
const ATM_WITHDRAW := "[PH] Withdraw"
const ATM_DEPOSIT := "[PH] Deposit"
const ATM_SETTLE := "[PH] Pay down"
## The five-line statement, TWO whole templates selected on whether anything is owed. ⭐The line COUNT is
## identical in both, so the fixed-width card can never hop mid-transaction (the heal-status padding lesson).
## {owed} arrives as an absolute value: Zorkmids.fmt prints its own minus, and "Owed  -240 zm" reads as a
## double negative.
const ATM_STATEMENT_SOLVENT := "[PH] Cash on hand   {cash}\nOn deposit   {saved}\nOwed   nothing\nCredit line   {left} of {limit}\nCredit score   {score}   ·   {band}"
const ATM_STATEMENT_OWING := "[PH] Cash on hand   {cash}\nOn deposit   {saved}\nOwed   {owed}\nCredit line   {left} of {limit}\nCredit score   {score}   ·   {band}"
## Short band names for the statement's score line and the score toast — the same KEYS the verdict templates
## use, worded tight enough to sit at the end of a line on a fixed-width card.
## ⭐DELIBERATELY BARE (no "[PH] "): these are VALUE tokens substituted into templates that already carry the
## marker, and a second marker landing mid-sentence ("rates you [PH] subprime") is the failure that convention
## exists to prevent. Same rule as the authored BODY_PART_* / archetype display names.
const ATM_BAND_NO_FILE := "no file"
const ATM_BAND_DECLINED := "declined"
const ATM_BAND_SUBPRIME := "subprime"
const ATM_BAND_SERVICEABLE := "serviceable"
const ATM_BAND_BANKABLE := "bankable"
const ATM_BAND_PREFERRED := "preferred"


## The short band name for the statement's score line, selected by KEY (never by the painted label).
static func atm_band_short(band: StringName) -> String:
	match band:
		EconomySettings.BAND_DECLINED: return ATM_BAND_DECLINED
		EconomySettings.BAND_SUBPRIME: return ATM_BAND_SUBPRIME
		EconomySettings.BAND_SERVICEABLE: return ATM_BAND_SERVICEABLE
		EconomySettings.BAND_BANKABLE: return ATM_BAND_BANKABLE
		EconomySettings.BAND_PREFERRED: return ATM_BAND_PREFERRED
	return ATM_BAND_NO_FILE


## Hover readout for a terminal: its authored name, else the default label (the trade_prompt mold).
static func atm_prompt(station_name: String) -> String:
	if station_name.is_empty():
		return ATM_DEFAULT_PROMPT
	return TextFormat.subst("[PH] Bank at {name}", {"name": station_name})


## Card title, re-stamped per terminal on open. MenuStyle.title_text owns the casing.
static func atm_title(station_name: String) -> String:
	if station_name.is_empty():
		return ATM_CARD_TITLE
	return TextFormat.subst("[PH] LEDGER — {name}", {"name": station_name})


## The statement: one whole template per state, five lines in both. Every amount rides in as a formatted
## money phrase; `owed` is passed already absolute by the screen.
static func atm_statement(cash: float, saved: float, owed: float, credit_left: float, credit_limit: float,
		score: int, band: StringName) -> String:
	var template := ATM_STATEMENT_OWING if owed > 0.0 else ATM_STATEMENT_SOLVENT
	return TextFormat.subst(template, {
		"cash": Zorkmids.money_text(cash),
		"saved": Zorkmids.money_text(saved),
		"owed": Zorkmids.money_text(owed),
		"left": Zorkmids.money_text(credit_left),
		"limit": Zorkmids.money_text(credit_limit),
		"score": score,
		"band": atm_band_short(band),
	})


## The standing explainer under the statement — the ONE place the economy is taught. Whole templates only,
## selected by state (owing × fee × rate), never fragment appends. SOLVENT: death-safety + the savings rate.
## OWING: the debt rate instead — the savings clause is dropped there because the one-signed-account invariant
## means you cannot hold growing savings while in the red (deposits retire debt first), so advertising growth
## would be a receipt the Ledger won't honour. A zeroed rate drops its clause rather than printing "0%", and a
## zeroed DEBT rate falls back to the solvent teaching wholesale (a debt that never grows needs no warning).
## `savings_rate`/`debt_rate` are the per-dawn fractions (EconomySettings.bank_*_interest_rate) — quoted HERE
## because the dawn toasts are the interest's only other surface, so a player who never happened to hold a
## balance across a dawn had no way to learn that either direction moves.
static func atm_hint(fee_fraction: float, savings_rate: float, debt_rate: float, owing: bool) -> String:
	var pct := TextFormat.num(snappedf(fee_fraction * 100.0, 0.1))
	if owing and debt_rate > 0.0:
		var drate := TextFormat.num(snappedf(debt_rate * 100.0, 0.1))
		if fee_fraction <= 0.0:
			return TextFormat.subst(
				"[PH] What you owe grows {rate}% at every dawn — deposits pay it down first. This terminal charges nothing to spend.",
				{"rate": drate})
		return TextFormat.subst(
			"[PH] What you owe grows {rate}% at every dawn — deposits pay it down first. Spending costs {pct}% — the cash in your pocket never does.",
			{"rate": drate, "pct": pct})
	var rate := TextFormat.num(snappedf(savings_rate * 100.0, 0.1))
	if fee_fraction <= 0.0:
		if savings_rate > 0.0:
			return TextFormat.subst(
				"[PH] Banked money is safe if you die and grows {rate}% at every dawn. This terminal charges nothing to spend it.",
				{"rate": rate})
		return "[PH] Banked money is safe if you die. This terminal charges nothing to spend it."
	if savings_rate > 0.0:
		return TextFormat.subst(
			"[PH] Banked money is safe if you die and grows {rate}% at every dawn. Spending it costs {pct}% — the cash in your pocket never does.",
			{"rate": rate, "pct": pct})
	return TextFormat.subst(
		"[PH] Banked money is safe if you die. Spending it costs {pct}% — the cash in your pocket never does.",
		{"pct": pct})


## DEPOSIT doubles as SETTLE: two whole captions selected by whether anything is owed.
static func atm_deposit_button(owing: bool) -> String:
	return ATM_SETTLE if owing else ATM_DEPOSIT


## Post-transaction toasts. Depositing while in the red is REPAYMENT, and saying so is the only way the
## player learns the two are the same operation.
static func atm_deposited(amount: float, was_owing: bool) -> String:
	var template := "[PH] {money} off your balance." if was_owing else "[PH] {money} deposited."
	return TextFormat.subst(template, {"money": Zorkmids.money_text(amount)})


static func atm_withdrew(amount: float) -> String:
	return TextFormat.subst("[PH] {money} withdrawn.", {"money": Zorkmids.money_text(amount)})


## The armed payment RAIL, as a button caption — TWO whole templates selected by the KEY (never by the painted
## label, the label-is-never-a-key rule). DEBIT spends what you have; CREDIT keeps going past zero onto the
## line, which is what the interest then compounds against.
##
## ⭐AT THE SIX TILLS THE PAINTED CAPTION IS WIDER THAN THIS STRING: the shared PaymentRailButton drop-in flanks
## it with the skin's cycler step glyphs ("< … >") so the control reads as something that CYCLES rather than as
## a status readout — which is how QA read the bare sentence on a full-width button, never discovering that
## Credit could be armed at a till at all. Those glyphs live on MenuSkin.cycler_prev_glyph / cycler_next_glyph
## (non-prose paint belongs to the skin, never here) and are joined at the button. So keep this a SENTENCE and
## keep it short: it has to fit inside that button's pinned width WITH the chevrons, and any shape added here
## would sit between two that already say "cycle". (The ATM's own rail button paints this string bare — it is
## not the drop-in, and a terminal whose whole subject is the account needs no discovery affordance.)
static func payment_rail_button(method: String) -> String:
	if method == "credit":
		return "Paying with: Credit"
	return "Paying with: Debit"


## The top-left CREDIT SCORE announcement (CreditWatch). FOUR whole templates selected by two booleans —
## direction, and whether the move crossed into a new band. Crossing a band is the moment that actually
## changes what the Ledger will lend you, so it earns the longer line; a plain drift gets the short one.
## The delta rides in pre-signed via "%+d" (TextFormat.num would drop the plus the readout depends on) and
## the band arrives as a KEY, resolved here through the same short-name selector the ATM statement uses.
static func credit_score_toast(score: int, delta: int, band: StringName, band_changed: bool) -> String:
	if band_changed:
		var crossed := "[PH] Credit score {score} ({delta}) — the Ledger now rates you {band}." if delta > 0 \
				else "[PH] Credit score {score} ({delta}) — the Ledger has downgraded you to {band}."
		return TextFormat.subst(crossed,
			{"score": score, "delta": "%+d" % delta, "band": atm_band_short(band)})
	return TextFormat.subst("[PH] Credit score {score} ({delta})",
		{"score": score, "delta": "%+d" % delta})


## The daily interest posting (LedgerAccrual). TWO whole templates selected by DIRECTION — the delta already
## carries its own sign from Zorkmids.fmt, so the debt variant takes the absolute value rather than printing
## a stray double minus.
static func ledger_interest(delta: float) -> String:
	if delta < 0.0:
		return TextFormat.subst("[PH] The Ledger added {money} to what you owe.",
			{"money": Zorkmids.money_text(absf(delta))})
	return TextFormat.subst("[PH] Your deposits earned {money}.", {"money": Zorkmids.money_text(delta)})


# --- THE GUNSMITH BENCH (scripts/components/weapon_bench.gd + scripts/ui/weapon_bench_screen.gd) -----------
# A dual-mode station in the ChipInstaller mold, so this block deliberately reads like the INSTALL_* one above:
# a fixed card title, two section headings, an empty-section line, and a per-row price column. What is NEW is
# the always-present NOTICE band — bench_notice() below — which is why the refusal wording lives here as one
# whole sentence per CAUSE KEY rather than as a tooltip the screen assembles.
#
# ⭐The bench hands the screen KEYS (WeaponBench.refusal_reason -> &"slot_taken", &"afford", …), never labels.
# Re-wording any sentence below can therefore never change which row dims or what a guard does — the
# display-strings-are-never-behaviour-keys rule, in the one place in this file where the two most look alike.

## The card title when the bench is unnamed — the all-caps blank-name fallback bench_title() selects, exactly
## as INSTALL_TITLE / SHOP_TITLE do for their stations.
const BENCH_TITLE := "WEAPON BENCH"
## The panel's CONSTRUCTION-time title, in NATURAL casing because MenuStyle.title_text owns the casing (an
## uppercase_titles = false skin must still get the authored wording). open_bench re-titles with
## bench_title(bench_name) before the card is ever shown. The INSTALL_SCREEN_TITLE / INSTALL_TITLE pairing,
## one for one — see that const's note for why both halves exist.
const BENCH_SCREEN_TITLE := "Weapon Bench"
## The two section headings. The parenthetical says what a CLICK does, because the two lists take opposite
## actions on rows that look identical (the shop's buy/sell heading pair is the same shape).
const BENCH_FITTED_HEADING := "[PH] Fitted  (click to remove)"
const BENCH_PARTS_HEADING := "[PH] Parts  (click to fit)"
## The GUN CYCLER row's heading, left of the cycling Button. A third heading in the same voice as the two above,
## but with no parenthetical: the button beside it carries its own caption (bench_gun — the weapon's name and
## filled-slot count), so the heading only has to name what the row is ABOUT. It exists because the card's rows
## all describe ONE weapon and a player arriving at a bench with four guns in the pack needs the row that
## chooses between them labelled, not merely captioned.
const BENCH_GUN_HEADING := "[PH] Weapon"
## The empty-section line in the PARTS list (you carry no fitting part and the bench stocks none). Deliberately
## the install screen's "(none)" rather than the shop's EMPTY_LIST "(empty)" — the two service screens read
## alike today, and unifying the three wordings is a copy call, not a refactor.
const BENCH_NO_PARTS := "(none)"
## The Notice band's &"no_weapons" sentence — nothing in the pack a bench could work on. Says PACK, not
## "inventory": a gun in your HANDS is in the pack too (the bench cycles the drawn weapon first).
const BENCH_NO_GUN := "[PH] No modifiable weapon in your pack."
## An offered-but-empty slot's NAME column in the Fitted list. The section paints one row per offered slot
## ALWAYS, so this is what most rows say on a stock gun — the fixed arity that stops the card hopping as parts
## come and go. An EM DASH (U+2014) each side.
const BENCH_EMPTY_SLOT := "[PH] — empty —"
## The PRICE column when a labour fee rounds away to nothing. Only reachable on a REMOVAL: fitting refuses a
## zero fee outright (a permanently-disabled "0 zm" row is the ChipInstaller lesson), while handing a part
## back that the player already owns must never be blocked by a rounding edge.
const BENCH_FREE := "[PH] free"

## The SIX slot names — the FO4 vocabulary, in WeaponData.ModSlot ordinal order.
## ⭐DELIBERATELY BARE (no "[PH] "): these are VALUE tokens substituted into templates that already carry the
## marker (a row's SLOT column sits beside a marked NAME, and mod_slot_name feeds tooltips built from marked
## sentences), and a second marker landing mid-line is the failure that convention exists to prevent. Same
## rule as the ATM_BAND_* short names and the BODY_PART_* nouns. They are also a fixed FUNCTIONAL vocabulary,
## like the stat titles: the six slots are the save vocabulary (WeaponData.MOD_SLOT_PROPS), so a locale
## re-words them but nothing may key on the wording.
const MOD_SLOT_RECEIVER := "Receiver"
const MOD_SLOT_BARREL := "Barrel"
const MOD_SLOT_MAGAZINE := "Magazine"
const MOD_SLOT_SIGHT := "Sight"
const MOD_SLOT_MUZZLE := "Muzzle"
const MOD_SLOT_STOCK := "Stock"


## The card title, re-stamped per bench on open (the install_title mold). MenuStyle.title_text owns the casing.
static func bench_title(name: String) -> String:
	return TextFormat.subst("WEAPON BENCH — {name}", {"name": name}) if not name.is_empty() else BENCH_TITLE


## The hover readout over a standalone bench: its authored `bench_name`, else the bare trade word. The
## chip_installer_prompt / atm_prompt mold — a station that names itself gets named, one that does not still
## says what it IS rather than falling back to a generic "Interact".
static func bench_prompt(name: String) -> String:
	if name.is_empty():
		return "[PH] Gunsmith"
	return TextFormat.subst("[PH] Gunsmith: {name}", {"name": name})


## The gun cycler's caption: the selected weapon's authored label beside its filled-slot count ("Pistol   2/6").
## Both halves are VALUES — the name is the Item's own display_name and the counts are numbers — so the whole
## line is prose-free and carries no marker (the character_inspect_summary precedent). THREE spaces separate
## the columns; keep them when re-wording.
static func bench_gun(name: String, fitted: int, total: int) -> String:
	return TextFormat.subst("{name}   {fitted}/{total}", {"name": name, "fitted": fitted, "total": total})


## One slot's display name, SELECTED by the WeaponData.ModSlot ordinal — never indexed out of an array, so a
## seventh slot added to the enum lands here as a compile-visible gap rather than an out-of-range read. An
## unknown ordinal degrades to the Receiver name (slot 0, the enum's own default) rather than a blank column.
static func mod_slot_name(slot: int) -> String:
	match slot:
		WeaponData.ModSlot.BARREL: return MOD_SLOT_BARREL
		WeaponData.ModSlot.MAGAZINE: return MOD_SLOT_MAGAZINE
		WeaponData.ModSlot.SIGHT: return MOD_SLOT_SIGHT
		WeaponData.ModSlot.MUZZLE: return MOD_SLOT_MUZZLE
		WeaponData.ModSlot.STOCK: return MOD_SLOT_STOCK
	return MOD_SLOT_RECEIVER


## The success toasts, one per direction (WeaponBench._fitted / _removed). `part` and `gun` arrive as authored
## Item.label() display names — content VALUES, never msgids of ours — which is why the marker sits once at
## the front and the names ride mid-sentence.
static func mod_fitted(part: String, gun: String) -> String:
	return TextFormat.subst("[PH] Fitted {part} to {gun}.", {"part": part, "gun": gun})


static func mod_removed(part: String, gun: String) -> String:
	return TextFormat.subst("[PH] Removed {part} from {gun}.", {"part": part, "gun": gun})


## The always-present Notice band under the bench's lists: WHY the thing you are looking at would refuse.
## SELECTS one whole sentence per CAUSE KEY — the exact StringNames WeaponBench.refusal_reason returns, which
## is the whole point of that function answering in keys: this table can be re-worded or translated without a
## single branch there changing. Cover every key it can return; a key with no row here would silently blank
## the band, which reads as "nothing is wrong" at precisely the moment something is.
##
## `n` is the gate's required rating, read ONLY by the &"stat_gate" row (0 elsewhere, and the parameter
## defaults so the gun-level caller — which asks with no part in hand and can only get &"no_weapons",
## &"draw_locked" or &"" back — need not pass a number it does not have). The stat title resolves HERE through
## StatInfo.title, the requires_stat idiom, so renaming the stat in resources/stats/gunplay.tres reaches this
## sentence; the stat ID is fixed because WeaponMod's gate field is (min_gunplay).
##
## &"" is the NO-NOTICE case and returns "" on purpose: the band keeps its height and simply says nothing, so
## the card never re-flows under the player's cursor mid-transaction.
static func bench_notice(reason_key: StringName, n: int = 0) -> String:
	match reason_key:
		&"draw_locked": return "[PH] Put down what you're carrying first."
		&"no_weapons": return BENCH_NO_GUN
		&"slot_taken": return "[PH] That slot is filled — remove the fitted part first."
		&"stat_gate": return TextFormat.subst("[PH] Requires {stat} {n}.", {"stat": StatInfo.title(&"gunplay"), "n": n})
		&"bag_full": return "[PH] No room in your pack for the part."
		&"afford": return "[PH] You can't afford that."
		&"unfit": return "[PH] That part doesn't fit this weapon."
	return ""


## The weapon row's right-hand column ("2/6 fitted") — the same two numbers bench_gun paints in the cycler,
## worded for a surface that has no header explaining what the fraction counts.
static func mod_slots_fitted(n: int, total: int) -> String:
	return TextFormat.subst("[PH] {n}/{total} fitted", {"n": n, "total": total})


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


## `cost` is a float because HealScreen paints the ALL-IN charge_total (the rail's service charge can land on
## a fraction), not the healer's integer sticker price; fmt inside money_text still prints whole amounts bare.
static func heal_button(cost: float) -> String:
	return TextFormat.subst("[PH] Heal  —  {money}", {"money": Zorkmids.money_text(cost)})


static func level_label(level: int) -> String:
	return TextFormat.subst("[PH] Level {level}", {"level": level})


static func your_zorkmids(amount: float) -> String:
	return TextFormat.subst("[PH] Your zorkmids: {amount}", {"amount": Zorkmids.fmt(amount)})


## The Level Up card's payment TERMS, painted where the DEBIT/CREDIT selector would sit on a station whose
## `accepts_credit` is off. Serving the terms is the point (the RentCollector notice doctrine): the armed rail
## is global persisted state, so a player can arm CREDIT at an ATM and walk in here — without this line the
## selector has silently vanished and the rows just cost more than they can reach, which reads as a bug.
## THREE WHOLE templates selected by the facts the caller passes, never a fragment append (the TextFormat
## rule): naming banked money to a player who has none advertises a purse they cannot open, and a debtor needs
## the OTHER half of the rule (`requires_settled_account`) rather than a lecture about rails. ⭐Deliberately
## names no station NOUN — a LevelUp is a trainer, a shrine or a bonfire depending on where a designer dropped
## it, and the one in shipped content rides a Medicine Person.
static func level_up_no_credit(owing: bool, has_savings: bool) -> String:
	if owing:
		return "[PH] The Ledger holds this counter until you are square. Settle what you owe before buying a level."
	if has_savings:
		return "[PH] No credit here — pay with the cash you carry, or the money you have banked."
	return "[PH] No credit here — pay with the cash you carry."


static func perks_header(points: int) -> String:
	return TextFormat.subst(TextFormat.plural(points,
			"[PH] Perks — {points} point",
			"[PH] Perks — {points} points"),
			{"points": points})


## Two whole templates selected by the encumbered flag — the warning is authored into its variant, never
## appended. Weight/capacity keep the fixed one-decimal readout ("12.0"), so the token values are
## pre-formatted here (TextFormat.num would trim the ".0" the gauge look relies on).
static func inventory_weight(weight: float, capacity: float, encumbered: bool) -> String:
	var template := "Weight  {weight} / {capacity}   ENCUMBERED" if encumbered else "Weight  {weight} / {capacity}"
	return TextFormat.subst(template, {"weight": "%.1f" % weight, "capacity": "%.1f" % capacity})


## PHASE-2 DEBT: `kind` arrives as a heading fragment ("LOOTING" / "PICKPOCKETING" from LootScreen) — the
## loot-screen phase should replace this with one whole-template func per mode.
static func loot_title(kind: String, name: String) -> String:
	return TextFormat.subst("{kind} {name}", {"kind": kind, "name": name}) if not name.is_empty() else TextFormat.subst("{kind}", {"kind": kind})


static func loot_exchange_title(name: String) -> String:
	return TextFormat.subst("EXCHANGING GEAR — {name}", {"name": name}) if not name.is_empty() else LOOT_EXCHANGE_TITLE


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


# --- Screen composers migrated off paint sites (the PlayerText ratchet's final sweep) -------------------------
# These were `%`-formatted or fragment-appended literals living in the screens themselves. They follow THE RULE
# (TextFormat): ONE whole template per rendered result, values substituted by {named} token, whole templates
# SELECTED by bool/enum — never a prose fragment passed in or glued on.


## The Character inspect showcase's summary line — character level + the live wallet in ONE whole template;
## the level number and the Zorkmids-formatted purse ride in as VALUE tokens, never concatenated. The
## separator is a MIDDLE DOT (U+00B7) with three spaces each side.
static func character_inspect_summary(level: int, money: float) -> String:
	return TextFormat.subst("Level {level}   ·   {amount} zorkmids", {"level": level, "amount": Zorkmids.fmt(money)})


## One compact "Title   value" row on the Character inspect showcase. TWO whole templates selected on whether
## a live status modifier applies — the "(+2)" delta is authored INSIDE its variant, never appended as a
## fragment. Callers pass the raw stat ID (the requires_stat idiom) so the authored StatText title resolves
## HERE, plus the base value and the RAW float modifier; the round-and-zero-threshold is display policy and
## belongs here too. The signed delta is formatted as a VALUE ("%+d" keeps the explicit plus sign the readout
## relies on — TextFormat.num would drop it), the inventory_weight precedent. Three spaces separate the
## columns; a modifier that rounds to zero still prints "(+0)", matching the historic readout.
static func character_inspect_stat_row(stat: StringName, base: int, bonus: float) -> String:
	if is_zero_approx(bonus):
		return TextFormat.subst("{stat}   {value}", {"stat": StatInfo.title(stat), "value": base})
	var delta := int(roundf(bonus))
	return TextFormat.subst("{stat}   {value} ({delta})", {"stat": StatInfo.title(stat), "value": base + delta, "delta": "%+d" % delta})


## The showcase's drawn-weapon line — TWO whole templates selected on `armed`, so the word "Unarmed" is
## authored INSIDE its variant instead of riding in as a prose fragment (THE RULE). `weapon_name` is the
## equipped Item's AUTHORED display_name (a value, never a msgid) and is read only in the armed variant.
## Two spaces follow the colon in both variants — the column look the panel relies on.
static func character_inspect_weapon(weapon_name: String, armed: bool) -> String:
	if not armed:
		return "Weapon:  Unarmed"
	return TextFormat.subst("Weapon:  {name}", {"name": weapon_name})


## The boot quote card's attribution byline — ONE whole template wrapping the DESIGNER-AUTHORED source name
## (BootQuotes.attribution, blank for StartMenu's FALLBACK_QUOTE) as a value token; replaces the old "— %s"
## at the StartMenu paint site. The dash is an EM DASH (U+2014) plus one space.
static func boot_quote_attribution(attribution: String) -> String:
	return TextFormat.subst("— {name}", {"name": attribution})


## The floating +N / -N money delta that rises off the top-left zorkmid readout (UI._on_money_changed) — TWO
## whole templates SELECTED by direction, never a "+" glued onto a formatted number (sign placement is a locale
## decision, and this replaces the last `%` format operator on a player-facing string in the HUD). A negative
## delta already carries its own minus from Zorkmids.fmt, so the loss variant is the bare amount. Raw fmt, not
## money_text: this float is a bare number beside the "zm" readout it modifies.
static func money_delta(delta: float) -> String:
	return TextFormat.subst("+{amount}" if delta > 0.0 else "{amount}", {"amount": Zorkmids.fmt(delta)})


## One stat block's header on the Stats screen ("Strength   —   4 (+1)"): the authored StatText title beside
## the live value. Takes the stat ID so the title resolves HERE (StatInfo.title, capitalized-id fallback built
## in) exactly like requires_stat — a caller never pre-resolves a display name. `value` is the numeric readout
## StatsScreen._stat_value_text builds ("4", "4.5 (+1)"), a VALUE token, never prose.
static func stat_header(stat: StringName, value: String) -> String:
	return TextFormat.subst("{title}   —   {value}", {"title": StatInfo.title(stat), "value": value})


## The Stats screen's live-effect line under a stat block ("Now: +8% gun damage, …"). PHASE-2 DEBT: the
## effect arrives as a prose FRAGMENT (StatInfo._effect, itself assembled from the stat_effect_* whole
## templates), so a locale cannot move the label relative to it — the loot_title situation. Folding "Now:"
## into those six templates is the real fix, but StatInfo.tooltip prefixes the SAME "Now:" from its own
## format string, so the two must migrate together in the stats phase.
## The VISIBLE half of that debt is paid: the six templates are authored, so the prefix no longer lands in
## front of a "[PH] " marker ("Now: [PH] +0% gun damage" is what shipped). ⭐Re-marking any of them puts it
## straight back — see the block header on stat_effect_strength.
static func stat_now(effect_text: String) -> String:
	return TextFormat.subst("Now: {effect}", {"effect": effect_text})


## The Stats screen's top summary line — level + wallet, with the unspent-perk-point tail as a real
## singular/plural template PAIR when any points are spare (never a "(s)" or a fragment append). The
## separators are MIDDLE DOTS (U+00B7) with THREE spaces each side — the character_inspect_summary idiom;
## keep the spacing when re-wording. The wallet rides in as raw Zorkmids.fmt (a bare number before the
## authored word "zorkmids"), matching the historic readout byte-for-byte.
static func stats_summary(level: int, money: float, points: int) -> String:
	if points <= 0:
		return TextFormat.subst("Level {level}   ·   {amount} zorkmids", {"level": level, "amount": Zorkmids.fmt(money)})
	return TextFormat.subst(TextFormat.plural(points,
			"Level {level}   ·   {amount} zorkmids   ·   {points} perk point to spend",
			"Level {level}   ·   {amount} zorkmids   ·   {points} perk points to spend"),
			{"level": level, "amount": Zorkmids.fmt(money), "points": points})


## One quest's HEADER row in the journal — three whole templates SELECTED by state, so the "(done)" /
## "(failed)" marker is authored INSIDE its variant (a locale may move or reword it) instead of being
## appended at the QuestJournal call site; it also drops the old '%' operator, which would error on a
## designer title containing a literal '%'. The active row returns the authored quest title VERBATIM — a
## content value, never a msgid of ours.
static func quest_entry_title(title: String, done: bool, failed: bool) -> String:
	if failed:
		return TextFormat.subst("{title}   (failed)", {"title": title})
	if done:
		return TextFormat.subst("{title}   (done)", {"title": title})
	return title


## One objective row in the quest Journal — EIGHT whole templates (the HEAL_STATUS_* multi-variant
## precedent) selected by (done, counted, optional): the checkbox, the " ({progress}/{required})" counter
## (counted = required > 1), and the "  (optional)" tag are each authored INSIDE their variants, never
## appended. Output is byte-identical to QuestJournal.objective_line for every state — the pins in
## tests/test_quest_journal.gd hold verbatim.
static func journal_objective(desc: String, done: bool, progress: int, required: int, optional: bool) -> String:
	var counted := required > 1
	var template: String
	if done:
		if counted:
			template = "[x] {desc} ({progress}/{required})  (optional)" if optional else "[x] {desc} ({progress}/{required})"
		else:
			template = "[x] {desc}  (optional)" if optional else "[x] {desc}"
	else:
		if counted:
			template = "[ ] {desc} ({progress}/{required})  (optional)" if optional else "[ ] {desc} ({progress}/{required})"
		else:
			template = "[ ] {desc}  (optional)" if optional else "[ ] {desc}"
	return TextFormat.subst(template, {"desc": desc, "progress": progress, "required": required})


## One refunded-perk row in the RespecScreen preview list — the bullet lives INSIDE the template (a locale
## may swap the glyph or drop it) instead of being prepended at the call site, and subst replaces the old '%'
## operator. `perk_label` is the already-resolved authored Perk.display_name (or the raw id) — a content
## value the caller passes in, never a msgid of ours.
static func respec_perk_row(perk_label: String) -> String:
	return TextFormat.subst("•  {perk}", {"perk": perk_label})


## An already-owned perk's row on the Level-Up screen — the marker wraps the row as a whole template (the
## EQUIPPED_ROW / quest_entry_title THREE-space idiom; a deliberate one-space widening of the old two-space
## append). `perk_label` is the resolved authored Perk.display_name — a content value, never a msgid of ours.
static func perk_owned_row(perk_label: String) -> String:
	return TextFormat.subst("{perk}   (owned)", {"perk": perk_label})


## The Level-Up screen's right-aligned cost cell — the whole parenthesised money phrase, with the amount
## riding in via Zorkmids.money_text (the currency word lives there, never appended here).
static func level_up_cost_cell(cost: float) -> String:
	return TextFormat.subst("({money})", {"money": Zorkmids.money_text(cost)})


## The reputation screen's standing column ("+12", "-5", and a zero standing as "+0"). TWO whole templates
## SELECTED on sign — the explicit plus is a DISPLAY convention a locale may drop or move, never a fragment the
## screen appends. Replaces the in-screen `"%+d" % …` paint-site literal (and its % operator, which the
## TextFormat RULE forbids); rendering is byte-identical, signed zero included.
static func reputation_standing(standing: int) -> String:
	return TextFormat.subst("+{value}" if standing >= 0 else "{value}", {"value": standing})


## The shop's hovered-item line: the item breakdown with the PRICE this deal would trade at appended on its own
## line. Prices moved here when the shop's rows became grid tiles (a cell has no price column), so this line is
## now the ONLY place a price is shown — it must never silently drop one. FOUR whole templates selected by
## side (buying from the stock vs selling from your bag) and affordability, so the "can't afford" / "won't pay"
## wording is authored INSIDE its variant rather than appended as a fragment. `body` is the composed
## ItemInfo.tooltip (a value, never a msgid of ours) and the money phrase comes from Zorkmids.money_text.
static func shop_price_line(body: String, price: float, buying: bool, affordable: bool) -> String:
	var money := Zorkmids.money_text(price)
	if buying:
		return TextFormat.subst("{body}\nBuy — {amount}" if affordable else "{body}\nBuy — {amount}  (you can't afford it)",
				{"body": body, "amount": money})
	return TextFormat.subst("{body}\nSell — {amount}" if affordable else "{body}\nSell — {amount}  (they won't pay for it)",
			{"body": body, "amount": money})


## The dialogue panel's advance-the-line cue: JUST the live key binding, no prose. The old
## "click to continue" tail was UI tutorializing (and unmarked AI prose the release scrub could not
## catch) — the bound-key glyph is affordance enough, and a rebind still repaints it (DialogueView
## re-queries InputManager.get_action_binding on every show).
static func dialogue_continue_hint(key: String) -> String:
	return TextFormat.subst("[{key}]", {"key": key})


## The response-menu header hint: which keys select a reply and which backs out. Pure bindings-as-glyphs,
## no prose (the dialogue_continue_hint rule) — the keys come from the LIVE hotbar-slot bindings the
## digit selection rides (DialogueManager passes get_action_binding results, never literals).
static func dialogue_menu_hint(first_key: String, last_key: String, exit_key: String) -> String:
	return TextFormat.subst("[{first}–{last}] · [{exit}]", {"first": first_key, "last": last_key, "exit": exit_key})


## The menu hint when only synthesized rows are up (no digit-selectable authored replies): just the exit key.
static func dialogue_menu_hint_exit_only(exit_key: String) -> String:
	return TextFormat.subst("[{exit}]", {"exit": exit_key})


## The digit gutter painted inside a response row ("1." / "0." — the row's live selection-key binding).
static func dialogue_choice_number(key: String) -> String:
	return TextFormat.subst("{key}.", {"key": key})


## One manual save slot's row name on the SaveLoadScreen ("Slot 1"). The number is a VALUE token in the one
## whole SAVE_LOAD_SLOT template — a locale may move it ("1. mentés") but never assembles the label from parts.
static func save_slot_label(n: int) -> String:
	return TextFormat.subst(SAVE_LOAD_SLOT, {"n": n})


## An existing save file's metadata caption on the SaveLoadScreen — TWO whole templates SELECTED on whether the
## save resolves an authored level display name (blank/deleted LevelData degrades to the time-only variant,
## never a dangling separator). Both arguments are VALUES: `level_name` is the authored LevelData.display_name
## verbatim and `time_text` the pre-formatted modified timestamp (SaveLoadScreen.slot_metadata builds both).
static func save_slot_caption(level_name: String, time_text: String) -> String:
	if level_name.is_empty():
		return TextFormat.subst(SAVE_SLOT_CAPTION_NO_LEVEL, {"time": time_text})
	return TextFormat.subst(SAVE_SLOT_CAPTION, {"level": level_name, "time": time_text})


## The HUD clock's face (scripts/ui/hud_clock.gd) — THREE whole templates SELECTED on the player's Options
## choice and, in 12-hour mode, on the half of the day. The AM/PM marker is baked INTO its own whole template
## rather than appended as a suffix argument, because a bare "AM" is exactly the untranslatable prose fragment
## TextFormat's rule forbids: locales that use a 12-hour face place their marker differently (before the
## digits, with a space or without, or not at all), and only a whole template lets a translator move it.
## The SEPARATOR lives in the template too — several locales write "14h35" or "14.35", not "14:35".
const CLOCK_24_HOUR := "{hours}:{minutes}"
const CLOCK_12_HOUR_AM := "{hours}:{minutes} AM"
const CLOCK_12_HOUR_PM := "{hours}:{minutes} PM"

## The 24-hour face ("14:35"). Both arguments are pre-formatted VALUE strings (HudClock zero-pads them
## through TextFormat.pad2) — never prose.
static func clock_24_hour(hours: String, minutes: String) -> String:
	return TextFormat.subst(CLOCK_24_HOUR, {"hours": hours, "minutes": minutes})

## The 12-hour face ("2:35 PM"). `pm` SELECTS between two whole templates; the hour is unpadded on purpose,
## which is the English 12-hour convention ("2:35 PM", not "02:35 PM").
static func clock_12_hour(hours: String, minutes: String, pm: bool) -> String:
	return TextFormat.subst(CLOCK_12_HOUR_PM if pm else CLOCK_12_HOUR_AM,
			{"hours": hours, "minutes": minutes})


## The HUD compass's rose (scripts/ui/hud_compass.gd) — the eight bearing letters on the top-centre heading
## tape, in bearing order from north: N, NE, E, SE, S, SW, W, NW.
##
## THESE ARE COPY, NOT GEOMETRY, which is the whole reason they live here rather than as a const array in the
## widget. A compass rose is initialled from the LOCAL words for the directions, and the initials are not
## shared: French writes O for ouest where English writes W, and every intercardinal built on it moves with
## it (NO/SO, not NW/SW). Hardcoding "W" in a _draw would make the tape the one HUD surface a translator
## cannot reach. Contrast the minimap's north tick, which is a drawn SPOKE precisely so it owes nothing here.
##
## Each is its own whole const rather than one packed "N,NE,E,..." string: a locale must be able to reword
## any single point without re-parsing a list, and a compass has exactly eight — an enumerable set, not data.
const COMPASS_N := "N"
const COMPASS_NE := "NE"
const COMPASS_E := "E"
const COMPASS_SE := "SE"
const COMPASS_S := "S"
const COMPASS_SW := "SW"
const COMPASS_W := "W"
const COMPASS_NW := "NW"

## The rose letter for a cardinal INDEX (0 = N, 1 = NE, ... 7 = NW — HudCompass.cardinal_index's output).
## SELECTS between the eight whole templates above; an out-of-range index wraps rather than degrading to a
## blank, because a compass point that silently vanishes reads as a broken instrument, not as missing copy.
static func compass_cardinal(index: int) -> String:
	match posmod(index, 8):
		1: return COMPASS_NE
		2: return COMPASS_E
		3: return COMPASS_SE
		4: return COMPASS_S
		5: return COMPASS_SW
		6: return COMPASS_W
		7: return COMPASS_NW
	return COMPASS_N


## The WAIT screen (scripts/ui/wait_screen.gd) — the Fallout-style "let some hours pass" panel on T.
const WAIT_TITLE := "Wait"
## The two clock readouts flanking the selector: the hour it is now, and the hour the wait would end at.
const WAIT_NOW_LABEL := "Now"
const WAIT_UNTIL_LABEL := "Until"
## The confirm button. Deliberately the same word as the title — it is the verb, and "Confirm"/"OK" would be
## vaguer at the moment of committing hours you cannot get back.
const WAIT_CONFIRM := "Wait"
## The selector's duration, as a real singular/plural PAIR through TextFormat.plural (never a bare "(s)").
const WAIT_HOURS_ONE := "{n} hour"
const WAIT_HOURS_MANY := "{n} hours"
## REFUSALS. Whole sentences, one per reason — never a shared stem with the cause appended, which is the
## fragment TextFormat's rule forbids. Shown on the screen itself rather than as a toast, because the player
## pressed a key expecting a panel and silence would read as a broken keybind.
const WAIT_BLOCKED_HOSTILE := "Not while someone is hunting you."
const WAIT_BLOCKED_AIRBORNE := "Not in mid-air."
## Shown on a level whose designer pinned the clock (WorldClock.day_length_seconds = 0). Deliberately phrased
## as a property of the PLACE, not as an error: nothing is broken, time genuinely does not move here.
const WAIT_BLOCKED_FROZEN := "Time doesn't pass here."
## The receipt after the hours pass, so a wait that changed nothing visible still confirms it happened.
const WAIT_ELAPSED_ONE := "{n} hour passes."
const WAIT_ELAPSED_MANY := "{n} hours pass."

## The selector's duration line ("1 hour" / "6 hours") — whole singular/plural templates, the tr_n() seam.
static func wait_hours(n: int) -> String:
	return TextFormat.subst(TextFormat.plural(n, WAIT_HOURS_ONE, WAIT_HOURS_MANY), {"n": n})

## The post-wait receipt ("6 hours pass."). Same whole-template pair rule as above.
static func wait_elapsed(n: int) -> String:
	return TextFormat.subst(TextFormat.plural(n, WAIT_ELAPSED_ONE, WAIT_ELAPSED_MANY), {"n": n})
