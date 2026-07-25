class_name PlayerText
extends RefCounted

const PH_PREFIX := "[PH]"
const PH_PREFIX_SPACE := "[PH] "

const BACK := "Back"
const BEGIN := "Begin"
const CANCEL := "Cancel"
const CLOSE := "Close"
const CONFIRM := "Confirm"
const DEFAULT := "Default"
const EMPTY_LIST := "(empty)"
const EQUIPPED_SUFFIX := "   (equipped)"
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
## through. Quest/kill matching still keys on the true display_name, never this. Edit here to re-label ("???").
const STRANGER := "Stranger"

const TOAST_ALREADY_FULL_HEALTH := "[PH] Already at full health"
const TOAST_ALREADY_LEARNED := "[PH] Already learned"
const TOAST_BACKPACK_FULL := "[PH] No room in your backpack"
const TOAST_BACKPACK_PARTIAL := "[PH] Backpack full — some items didn't fit"
const TOAST_CAUGHT := "[PH] Caught!"
const TOAST_CANT_AFFORD_HEAL_SUFFIX := "\n[PH] — can't afford"
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
const SHOP_MERCHANT_WALLET := "[PH] Merchant: %s zm"
const PLAYER_WALLET := "[PH] You: %s zm"

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
const CHESS_CHECK_SUFFIX := "  (Check!)"
const CHESS_EXIT_HINT := "[PH] Esc — leave the table"
const CHESS_INPUT_HINT := "[PH] Type a move (e2e4 or Nf3) · Enter to play · Esc to leave"
const CHESS_BLINDFOLD_HINT := "[PH] Blindfold: track the board from the move log · type e2e4 or Nf3 · Esc to leave"
const CHESS_BLINDFOLD_BADGE := "[ BLINDFOLD ]"
const CHESS_NO_BOARD_HINT := "[PH] No board — play it in your head.\nInstall the Board Visualizer chip to see the position."

const HEAL_FULLY_HEALED := "[PH] Fully healed"
const RESPEC_NO_PERKS := "[PH] (no perks unlocked)"
const RESPEC_NOTHING := "Nothing to respec"
## Keep this SHORT: it swaps onto a rebind button pinned to REBIND_BTN_MIN_WIDTH (120px incl. margins,
## clip_text on) — a longer prompt clips rather than growing the button, so it must read whole at ~102px.
const OPTIONS_BIND_PROMPT := "[PH] Press key..."
const OPTIONS_MUSIC_FOLDER_DEFAULT := "[PH] Default (each radio's own folder)"
const OPTIONS_CHOOSE_MUSIC_FOLDER := "[PH] Choose a music folder"
const OPTIONS_WINDOWED := "[PH] Windowed"
const OPTIONS_BORDERLESS := "[PH] Borderless Fullscreen"
const OPTIONS_EXCLUSIVE_FULLSCREEN := "[PH] Exclusive Fullscreen"
const QUEST_JOURNAL_HINT := "[PH] Your active and completed quests."
const QUEST_JOURNAL_EMPTY := "[PH] No quests yet."
const REPUTATION_HINT := "[PH] How each faction feels about you. Good deeds raise it; killing their own sinks it."
const REPUTATION_EMPTY := "[PH] No factions defined."
const STATS_SCREEN_HINT := "[PH] Spend points at a Level-Up station."

const DEATH_MESSAGE := "[PH] You were killed."
const DEATH_MESSAGE_KILLED_BY := "[PH] You were killed by %s."
const DEATH_MESSAGE_KILLED_BY_WEAPON := "[PH] You were killed by %s. They were using a %s."


static func prefixed(text: String) -> String:
	return PH_PREFIX_SPACE + text


static func strip_prefix(text: String) -> String:
	return text.substr(PH_PREFIX_SPACE.length()) if text.begins_with(PH_PREFIX_SPACE) else text


static func acquired(name: String) -> String:
	return "[PH] %s acquired!" % name


static func installed(name: String) -> String:
	return "[PH] %s installed" % name


static func take(name: String) -> String:
	return "[PH] Take %s" % name


static func take_item(name: String) -> String:
	return "Take %s" % name


static func pick_up(name: String) -> String:
	return "[PH] Pick Up %s" % name if not name.is_empty() else PROMPT_PICK_UP


static func pick_pocket(name: String) -> String:
	return "[PH] Pick Pocket %s" % name if not name.is_empty() else "[PH] Pick Pocket"


## The hover-tooltip odds line while pickpocketing a live target: the chance (0..100 %) of lifting the hovered item
## without being caught. Fed by LootScreen._pickpocket_success_percent (1 - catch chance).
static func pickpocket_success(pct: int) -> String:
	return "[PH] %d%% to lift unnoticed" % pct


static func talk_to(name: String) -> String:
	return "[PH] Talk to %s" % name


static func trade_prompt(name: String) -> String:
	return "Trade: %s" % name if not name.is_empty() else DEFAULT_MERCHANT_LABEL


static func enter_prompt(name: String) -> String:
	return enter_level(name) if not name.is_empty() else ENTER


static func unlock(name: String) -> String:
	return "[PH] Unlock %s" % name


static func loot(name: String) -> String:
	return "[PH] Loot %s" % name if not name.is_empty() else PROMPT_CONTAINER


static func accept(quest_title: String) -> String:
	return "[PH] Accept: %s" % quest_title


static func quest_started(quest_title: String) -> String:
	return "[PH] Quest started: %s" % quest_title


static func new_quest(quest_title: String) -> String:
	return "[PH] New quest: %s" % quest_title


static func objective_complete(description: String) -> String:
	return "[PH] Objective complete: %s" % description


static func quest_complete(quest_title: String) -> String:
	return "[PH] Quest complete: %s" % quest_title


static func quest_failed(quest_title: String) -> String:
	return "[PH] Quest failed: %s" % quest_title


static func quest_tracker_line(title: String, objective_desc: String, progress: int, required: int) -> String:
	var prog := " (%d/%d)" % [progress, required] if required > 1 else ""
	return "[PH] ◈ %s — %s%s" % [title, objective_desc, prog]


static func quest_rewards_full(lost_count: int) -> String:
	return "[PH] Inventory full — %d quest reward item(s) couldn't fit" % lost_count


static func reputation_changed(faction_name: String, gained: bool) -> String:
	return "[PH] %s reputation %s!" % [faction_name, "gained" if gained else "lost"]


static func alignment_changed(faction_name: String, kind_text: String) -> String:
	return "[PH] %s is now %s!" % [faction_name, kind_text]


static func requires_stat(stat: StringName, value: int) -> String:
	return "[PH] Requires %s %d" % [String(stat).capitalize(), value]


static func requires_perk(perk_id: StringName) -> String:
	return "[PH] Requires the %s perk" % String(perk_id).capitalize()


static func requires_ability() -> String:
	return "[PH] Requires an ability"


static func requires_standing(faction_id: String) -> String:
	return "[PH] Requires standing with %s" % faction_id.capitalize()


static func locked_requires(label: String) -> String:
	return "[PH] Locked — requires %s" % label


## Deny toast for a lock that is BOTH keyed AND pickable but you have neither the key nor a lockpick — name both ways in.
static func locked_requires_either(key_label: String, pick_label: String) -> String:
	return "[PH] Locked — requires %s or %s" % [key_label, pick_label]


static func lock_result(consumed_item: bool) -> String:
	return TOAST_LOCK_PICKED if consumed_item else TOAST_UNLOCKED


static func rest_prompt(place: String) -> String:
	return "[PH] Rest: %s" % place if not place.is_empty() else PROMPT_REST_AT_BONFIRE


static func rested_at(place: String) -> String:
	return "[PH] Rested at %s" % place


static func respec_prompt(station_name: String) -> String:
	return "[PH] Respec: %s" % station_name if not station_name.is_empty() else PROMPT_RESPEC


static func respec_refunded(count: int) -> String:
	return "[PH] Respec: %d perk%s refunded" % [count, "" if count == 1 else "s"]


static func respec_blurb(count: int) -> String:
	return "[PH] Refund %d perk%s — skill points return to re-spend at a Level Up." % [count, "" if count == 1 else "s"]


static func respec_status(cost: float, player_money: float) -> String:
	return "[PH] Cost: %s\nYour zorkmids: %s" % [Zorkmids.fmt(cost), Zorkmids.fmt(player_money)]


static func respec_button(cost: float) -> String:
	return "Respec  —  %s zm" % Zorkmids.fmt(cost)


static func bonfire_name(name: String) -> String:
	return name if not name.is_empty() else "bonfire"


static func radio_state(name: String, state_word: String) -> String:
	return "[PH] %s %s" % [name, state_word]


static func radio_prompt(name: String, playing: bool) -> String:
	return ("[PH] Turn off %s" if playing else "[PH] Turn on %s") % name


static func container_prompt(container_name: String, locked: bool) -> String:
	var name := container_name if not container_name.is_empty() else "Container"
	return unlock(name) if locked else loot(container_name)


static func money_pickup(amount: float) -> String:
	return "[PH] Take %s zorkmids" % Zorkmids.fmt(amount)


static func wallet_you(amount: float) -> String:
	return PLAYER_WALLET % Zorkmids.fmt(amount)


static func wallet_merchant(amount: float) -> String:
	return SHOP_MERCHANT_WALLET % Zorkmids.fmt(amount)


static func claim_name_dialog(name: String) -> String:
	return "[PH] Name your %s" % name


static func befriend(name: String) -> String:
	return "[PH] Befriended %s" % name if not name.is_empty() else "[PH] Befriended"


static func released(name: String) -> String:
	return "[PH] Released %s" % name if not name.is_empty() else "[PH] Released"


static func hold_to_release(key: String, name: String) -> String:
	return "[PH] [%s] Hold to Release %s" % [key, name] if not name.is_empty() else "[PH] [%s] Hold to Release" % key


static func key_prompt(key: String, verb: String, name: String) -> String:
	return "[%s] %s %s" % [key, verb, name] if not name.is_empty() else "[%s] %s" % [key, verb]


static func takedown_prompt(key: String, name: String) -> String:
	return "[PH] [%s] Take Down %s" % [key, name] if not name.is_empty() else "[PH] [%s] Take Down" % key


static func learned(perk_label: String) -> String:
	return "[PH] Learned: %s" % perk_label


static func learn_prompt(perk_label: String) -> String:
	return "[PH] Learn: %s" % perk_label


static func enter_level(level_name: String) -> String:
	return "[PH] Enter %s" % level_name


static func no_game_root() -> String:
	return "No GameRoot — attach game_root.gd to the scene root"


static func chip_installer_prompt(name: String) -> String:
	return "[PH] Upgrades: %s" % name if not name.is_empty() else PROMPT_MECHANIC


static func chess_prompt(opponent_name: String) -> String:
	return "[PH] Play Chess: %s" % opponent_name if not opponent_name.is_empty() else PROMPT_PLAY_CHESS


static func chess_title(opponent_name: String) -> String:
	return "CHESS — %s" % opponent_name if not opponent_name.is_empty() else "CHESS"


static func collateral_kill(pay: float) -> String:
	return "[PH] Collateral kill!  +%s zm" % Zorkmids.fmt(pay)


static func confetti(pay: float) -> String:
	return "[PH] Confetti!  +%s zm" % Zorkmids.fmt(pay)


static func long_range_kill(distance_m: int, pay: float) -> String:
	return "[PH] Long-range kill!  %d m  +%s zm" % [distance_m, Zorkmids.fmt(pay)]


## The respawn toast for the half-wallet death loss (death_purse_loss_fraction) — placeholder medical-fee flavour.
## `amount` = the zorkmids actually deducted at death (Player._death_wallet_lost). Mirrors the chess_loss /
## long_range_kill money-toast style: one [PH] marker up front, the signed amount trailing.
static func hospital_bill(amount: float) -> String:
	return "[PH] Hospital bill!  -%s zm" % Zorkmids.fmt(amount)


static func holster_forgiveness_tutorial(key: String) -> String:
	return "[PH] You provoked them. Hold [%s] to holster your weapon and ask for forgiveness." % key


static func gained_hp(amount: int) -> String:
	return "[PH] +%d HP" % amount


static func head_crippled() -> String:
	return "[PH] Your head is crippled!"


static func crippled_target(target_name: String, part_name: String) -> String:
	return "Crippled %s's %s" % [target_name, part_name]


static func level_up(level: int, points: int) -> String:
	return "Level %d! +%d skill point%s" % [level, points, "" if points == 1 else "s"]


static func points_to_spend(spare: int) -> String:
	return "[PH] Points to spend: %d" % spare


static func character_create_stat_hint(min_value: int, max_value: int) -> String:
	return "[PH] Lower a stat to earn points, then spend them raising another (range %d to +%d). A minus is a real weakness." % [min_value, max_value]


static func stat_effect_strength(melee: String, carry: String, max_hp: String) -> String:
	return "[PH] melee %s, %s carry, %s max HP" % [melee, carry, max_hp]


static func stat_effect_endurance(stamina: String) -> String:
	return "[PH] %s max stamina" % stamina


static func stat_effect_gunplay(damage: String, steadiness: String) -> String:
	return "[PH] %s gun damage, %s aim steadiness" % [damage, steadiness]


static func stat_effect_agility(speed: String) -> String:
	return "[PH] %s move speed" % speed


static func stat_effect_streetwise(buys: String, sales: String, rep: String) -> String:
	return "[PH] buys %s, sales %s, rep gains %s" % [buys, sales, rep]


static func stat_effect_larceny(detection: String, takedown: String, risk: int, allowance: String) -> String:
	return "[PH] %s enemy detection speed, %s takedown time, %d%% caught risk, lift value <= %s" % [detection, takedown, risk, allowance]


static func shop_title(name: String) -> String:
	return "%s — %s" % [SHOP_TITLE, name] if not name.is_empty() else SHOP_TITLE


static func install_title(name: String) -> String:
	return "%s — %s" % [INSTALL_TITLE, name] if not name.is_empty() else INSTALL_TITLE


static func heal_title(name: String) -> String:
	return "HEAL — %s" % name if not name.is_empty() else "HEAL"


static func respec_title(name: String) -> String:
	return "RESPEC — %s" % name if not name.is_empty() else "RESPEC"


static func level_up_title(name: String) -> String:
	return "Level Up — %s" % name if not name.is_empty() else "Level Up"


static func heal_status(hp: int, max_hp: int, limb_text: String, money: float, note: String) -> String:
	return "[PH] HP  %d / %d%s\nYour zorkmids: %s%s" % [hp, max_hp, limb_text, Zorkmids.fmt(money), note]


static func heal_button(cost: int) -> String:
	return "[PH] Heal  —  %d zm" % cost


static func level_label(level: int) -> String:
	return "[PH] Level %d" % level


static func your_zorkmids(amount: float) -> String:
	return "[PH] Your zorkmids: %s" % Zorkmids.fmt(amount)


static func perks_header(points: int) -> String:
	return "[PH] Perks — %d point%s" % [points, "" if points == 1 else "s"]


static func inventory_weight(weight: float, capacity: float, encumbered: bool) -> String:
	return "[PH] Weight  %.1f / %.1f%s" % [weight, capacity, "   ENCUMBERED" if encumbered else ""]


static func loot_title(kind: String, name: String) -> String:
	return "[PH] %s %s" % [kind, name] if not name.is_empty() else "[PH] %s" % kind


static func loot_exchange_title(name: String) -> String:
	return "[PH] EXCHANGING GEAR — %s" % name if not name.is_empty() else LOOT_EXCHANGE_TITLE


static func chess_cant_cover(wager: float) -> String:
	return "[PH] You can't cover the %s zm stake." % Zorkmids.fmt(wager)


static func chess_forfeit_loss(delta_abs: float) -> String:
	return "[PH] -%s zm — you forfeited the game." % Zorkmids.fmt(delta_abs)


static func chess_illegal_move(text: String) -> String:
	# Truncate the echo: the typed entry is unbounded (the move field has no max_length) and this line lives
	# on the chess panel's single-line clipped hint — an untruncated echo would clip away the guidance suffix.
	var shown := text if text.length() <= 24 else text.left(24) + "…"
	return "[PH] “%s” isn't a legal move. Try e2e4 or Nf3." % shown


static func chess_win(delta: float) -> String:
	return "[PH] +%s zm — you won the game." % Zorkmids.fmt(delta)


static func chess_loss(delta_abs: float) -> String:
	return "[PH] -%s zm — you lost the game." % Zorkmids.fmt(delta_abs)


static func chess_checkmate(player_wins: bool) -> String:
	return "[PH] Checkmate — %s." % ("you win" if player_wins else "you lose")


static func chess_thinking(name: String) -> String:
	return "[PH] %s is thinking…" % name


static func chess_to_move(name: String) -> String:
	return "[PH] %s to move." % name
