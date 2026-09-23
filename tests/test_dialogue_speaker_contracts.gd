extends GutTest

## M14: DialogueManager reaches its collaborators via DUCK-TYPING (has_method / has_signal scans) rather than typed
## refs, deliberately — a typed `Merchant`/`Healer`/… would recreate the Merchant <-> ShopScreen <-> DialogueManager
## compile cycle (the typed-interface remedy was REFUTED for that reason). Since the station-contract extraction,
## the dialogue's station OPTIONS (Trade / Heal / Rest / Level Up / Install / Modify / Play Chess / Bank) ride ONE
## method pair on every dual-mode component — dialogue_station_option() (label / order / reason / closed) +
## open_dialogue_station(player) — discovered by a direct-children has_method scan of BOTH names
## (dialogue_manager.gd _station_options); the transaction SCREENS keep their own duck-typed reads of the same
## components (COMPONENT_CONTRACTS below). The cost of duck-typing is unchanged: a rename silently DROPS the
## option / kills the screen with NO compile error. This file is the guard — labels, reasons, the roster itself,
## and the painted menu ORDER (driven through DialogueManager's own sort, not transcribed as numbers) are pinned.
## Scripts are loaded + instantiated OFF-TREE (no add_child -> no _ready), so it's
## headless-safe; dialogue_station_option() reads only consts + autoload signal handles (GUT runs with autoloads,
## exactly as tests/test_dialogue_suspend_closed.gd already relies on).

# THE STATION ROSTER — roster-as-spec for the dialogue-station contract. One row per dual-mode component: the
# label (referenced as the PlayerText const, never a string literal — the pin is "the component paints THIS
# authored const", not a copy of its text), _suspend_for_menu's reason string, and whether the station suspends
# (carries a `closed` resume Signal) or is act-and-close (Bonfire only). The DIALOGUE_ORDER numbers are NOT copied
# here: only their relative order is player-visible, and that is proven through the real sort below.
# The row order here IS the player-visible menu order; a NEW station adds one row here + one component —
# DialogueManager itself needs no edit.
const STATION_CONTRACTS := {
	"res://scripts/components/merchant.gd": {"label": PlayerText.DIALOGUE_OPTION_TRADE, "reason": "trade", "suspends": true},
	"res://scripts/components/healer.gd": {"label": PlayerText.DIALOGUE_OPTION_HEAL, "reason": "heal", "suspends": true},
	"res://scripts/components/bonfire.gd": {"label": PlayerText.DIALOGUE_OPTION_REST, "reason": "", "suspends": false},
	"res://scripts/components/level_up.gd": {"label": PlayerText.DIALOGUE_OPTION_LEVEL_UP, "reason": "level_up", "suspends": true},
	"res://scripts/components/chip_installer.gd": {"label": PlayerText.DIALOGUE_OPTION_INSTALL, "reason": "install", "suspends": true},
	"res://scripts/components/weapon_bench.gd": {"label": PlayerText.DIALOGUE_OPTION_MODIFY, "reason": "modify", "suspends": true},
	"res://scripts/components/chess_match.gd": {"label": PlayerText.DIALOGUE_OPTION_PLAY_CHESS, "reason": "chess", "suspends": true},
	"res://scripts/components/atm.gd": {"label": PlayerText.DIALOGUE_OPTION_BANK, "reason": "bank", "suspends": true},
}

# The explicit spine of the roster order (a GDScript Dictionary does preserve insertion order, but the ordering
# contract deserves its own explicit, greppable list): THIS is the player-visible menu order — Trade, Heal, Rest,
# Level Up, Install, Modify, Play Chess, Bank. Modify sits between Install and Play Chess — chrome for your gear
# right after chrome for yourself.
const STATION_ROSTER: Array[String] = [
	"res://scripts/components/merchant.gd",
	"res://scripts/components/healer.gd",
	"res://scripts/components/bonfire.gd",
	"res://scripts/components/level_up.gd",
	"res://scripts/components/chip_installer.gd",
	"res://scripts/components/weapon_bench.gd",
	"res://scripts/components/chess_match.gd",
	"res://scripts/components/atm.gd",
]

# SCREEN-side duck-called surfaces on the same components. These are no longer what paints the dialogue option
# (that's the station contract above) — they are what the transaction screen calls once it is open, and a rename
# still fails silently at press/paint time, so they stay pinned. The chess row pins the FULL open_match getter
# surface: ai_search_depth is also ChessScreen's open guard key, and ai_blunder/player_is_white/wager_amount are
# read at match start — a rename passes discovery yet crashes the sit-down.
const COMPONENT_CONTRACTS := {
	"res://scripts/components/merchant.gd": ["buy", "sell"],                     # ShopScreen's row transactions
	"res://scripts/components/healer.gd": ["do_heal", "heal_cost"],             # HealScreen's price + heal press
	"res://scripts/components/bonfire.gd": ["rest"],                            # the act-and-close press (open_dialogue_station and standalone start_talk both call it)
	"res://scripts/components/level_up.gd": ["level_up_stat", "level_up_cost"], # LevelUpScreen's raise rows
	"res://scripts/components/chess_match.gd": ["ai_search_depth", "display_opponent_name", "ai_blunder", "player_is_white", "wager_amount"], # ChessScreen.open_match (guard key + 4 config reads)
	"res://scripts/components/atm.gd": ["deposit", "withdraw"],                 # AtmScreen's transaction buttons
	"res://scripts/components/weapon_bench.gd": ["fit_mod", "fit_fee", "remove_mod"], # WeaponBenchScreen's two row verbs + the price column that dims them
}

# Transaction screens the stations open from dialogue: script path -> the open method each component's
# open_dialogue_station calls (DialogueManager suspends on the screen's `closed`, one step removed).
const SCREEN_CONTRACTS := {
	"res://scripts/ui/shop_screen.gd": "open_shop",
	"res://scripts/ui/heal_screen.gd": "open_heal",
	"res://scripts/ui/level_up_screen.gd": "open_level_up",
	"res://scripts/ui/chess_screen.gd": "open_match",
	"res://scripts/ui/chip_install_screen.gd": "open_install",  # DialogueManager suspends into open_install, awaiting `closed`
	"res://scripts/ui/atm_screen.gd": "open_atm",               # ditto for the ledger terminal's "Bank" option
	"res://scripts/ui/weapon_bench_screen.gd": "open_bench",    # and for the gunsmith's "Modify" option
}

# NPC speaker methods DialogueManager duck-scans (set_in_dialogue/note_speaking/note_speaking_stop/provoke/
# is_following/resolved_disposition + head_world_position for the dialogue face light), plus the `died` signal it
# connects. note_speaking_stop cuts the head-bob when the NPC stops delivering a line; head_world_position keys the
# face light. Player methods it calls from a dialogue choice.
const SPEAKER_METHODS := ["set_in_dialogue", "note_speaking", "note_speaking_stop", "provoke", "is_following", "resolved_disposition", "head_world_position"]
const PLAYER_METHODS := ["add_money", "notify_toast"]

const DIALOGUE_MANAGER_PATH := "res://scripts/dialogue/dialogue_manager.gd"


func test_station_contract_pairs_exist_and_match_roster() -> void:
	# The load-bearing pin of the extraction: each dual-mode component must carry BOTH contract methods (the
	# scan keys on the pair, so losing either silently drops the button), and dialogue_station_option() must
	# return exactly the authored label / order / reason / closed shape. Invoked on a bare .new() instance —
	# a pure dict build reading consts + autoload signal handles, so it is headless-safe.
	for path: String in STATION_ROSTER:
		var expected: Dictionary = STATION_CONTRACTS[path]
		var c: Node = load(path).new()
		assert_true(c.has_method(&"dialogue_station_option"), "%s must keep dialogue_station_option() — DialogueManager discovers stations by the method PAIR (a rename silently drops the dialogue option)" % path)
		assert_true(c.has_method(&"open_dialogue_station"), "%s must keep open_dialogue_station() — the other half of the discovery pair (a half-implemented station paints no button, by design)" % path)
		if not (c.has_method(&"dialogue_station_option") and c.has_method(&"open_dialogue_station")):
			c.free()
			continue
		var opt: Dictionary = c.dialogue_station_option()
		assert_false(opt.is_empty(), "%s must offer its option unconditionally on a bare instance — none of the shipped seven ever withholds ({} is the future-gating seam only)" % path)
		assert_eq(str(opt.get("label", "")), str(expected.label), "%s: the option label must be the authored PlayerText const, verbatim (labels are never raw literals)" % path)
		assert_eq(typeof(opt.get("order")), TYPE_INT, "%s: `order` must be an int — DialogueManager sorts the painted menu on it, and a missing order sorts as 0 (ahead of Trade)" % path)
		assert_eq("closed" in opt, bool(expected.suspends), "%s: `closed` present iff the station suspends (absent = act-and-close; Bonfire is the only one)" % path)
		assert_eq("reason" in opt, bool(expected.suspends), "%s: `reason` present iff `closed` is — reason-without-closed is the strand-risk shape DialogueManager warns on" % path)
		if bool(expected.suspends):
			assert_eq(str(opt.get("reason", "")), str(expected.reason), "%s: the reason feeds dialogue_suspended and must stay byte-identical to the pre-contract handler's string" % path)
			assert_eq(typeof(opt.get("closed")), TYPE_SIGNAL, "%s: `closed` must be the sub-menu's resume Signal (TYPE_SIGNAL) or _suspend_for_menu cannot connect the one-shot resume" % path)
		c.free()


func test_dialogue_paints_the_stations_in_roster_order_whatever_the_authored_child_order() -> void:
	# The executable ordering guarantee, driven through the REAL sort: every roster station hangs under ONE speaker in
	# REVERSE roster order (the worst authored scene order), and DialogueManager._station_options() — the list the
	# dialogue box paints — must still come back Trade, Heal, Rest, Level Up, Install, Modify, Play Chess, Bank. The
	# sort reads each component's own DIALOGUE_ORDER, so a station moved to the wrong slot comes out of place, and two
	# stations sharing an order fall to the child-index tie-break and come out REVERSED under this child order.
	# Off-tree .new() instances throughout (no _ready anywhere), the same idiom tests/test_stranger_names.gd uses.
	var manager = load(DIALOGUE_MANAGER_PATH).new()
	var speaker := Node.new()
	var authored := STATION_ROSTER.duplicate()
	authored.reverse()
	for path: String in authored:
		speaker.add_child(load(path).new())
	manager._speaker = speaker
	var painted: Array = manager._station_options()
	var labels: Array[String] = []
	var orders: Array[int] = []
	for entry: Dictionary in painted:
		labels.append(str(entry.label))
		orders.append(int(entry.order))
	var expected: Array[String] = []
	for path: String in STATION_ROSTER:
		expected.append(str(STATION_CONTRACTS[path].label))
	assert_eq(labels, expected,
		"the dialogue menu must paint Trade, Heal, Rest, Level Up, Install, Modify, Play Chess, Bank regardless of the order the stations were authored under the speaker")
	for i in range(1, orders.size()):
		assert_true(orders[i] > orders[i - 1],
			"%s (order %d) must sort strictly after %s (order %d): a shared order leaves the menu at the mercy of authored child order" % [labels[i], orders[i], labels[i - 1], orders[i - 1]])
	manager._speaker = null
	speaker.free()
	manager.free()


func test_station_roster_is_the_spec() -> void:
	# Roster-as-spec (the README-roster idiom made executable): the set of scripts/components/*.gd sources that
	# implement `func dialogue_station_option` must EQUAL the roster. Catches both drift directions — a renamed
	# component drops out of the found set, and a NEW dual-mode component authored with the contract but never
	# added to STATION_CONTRACTS fails here (the label/reason/order pins only guard what they know about).
	var found := {}
	var dir := DirAccess.open("res://scripts/components")
	assert_not_null(dir, "the components folder must exist")
	if dir == null:
		return
	for f in dir.get_files():
		var fn := f.trim_suffix(".remap")
		if fn.get_extension() != "gd":
			continue
		var path := "res://scripts/components/" + fn
		if FileAccess.get_file_as_string(path).contains("func dialogue_station_option"):
			found[path] = true
	for path: String in STATION_ROSTER:
		assert_true(found.has(path), "%s is in the station roster but does not implement dialogue_station_option() on disk" % path)
		found.erase(path)
	assert_eq(found.size(), 0, "component(s) implement dialogue_station_option() but have no STATION_CONTRACTS roster row — add the pin(s): %s" % [found.keys()])


func test_component_speaker_contracts_exist() -> void:
	for path in COMPONENT_CONTRACTS:
		var c = load(path).new()
		for m in COMPONENT_CONTRACTS[path]:
			assert_true(c.has_method(m), "%s must keep method '%s' — the transaction screen duck-calls it (a rename silently breaks the screen with no compile error)" % [path, m])
		c.free()


func test_screen_open_and_closed_contracts_exist() -> void:
	for path in SCREEN_CONTRACTS:
		var s = load(path).new()
		assert_true(s.has_method(SCREEN_CONTRACTS[path]), "%s must keep %s() — the station's open_dialogue_station calls it to open the transaction screen" % [path, SCREEN_CONTRACTS[path]])
		assert_true(s.has_signal("closed"), "%s must keep the `closed` signal — DialogueManager awaits it to restore the dialogue box" % path)
		s.free()


func test_npc_speaker_contract_exists() -> void:
	var npc = load("res://scripts/npc/npc.gd").new()
	for m in SPEAKER_METHODS:
		assert_true(npc.has_method(m), "NPC (speaker) must keep method '%s' — DialogueManager duck-scans it" % m)
	assert_true(npc.has_signal("died"), "NPC (speaker) must keep the `died` signal — DialogueManager connects it to end the box if the speaker dies")
	npc.free()


func test_player_contract_exists() -> void:
	var p = load("res://scripts/player/player.gd").new()
	for m in PLAYER_METHODS:
		assert_true(p.has_method(m), "Player must keep method '%s' — DialogueManager calls it from a dialogue choice" % m)
	p.free()
