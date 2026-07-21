extends GutTest

## M14: DialogueManager reaches into ~8 subsystems via DUCK-TYPING (has_method / has_signal scans) rather than typed
## refs, deliberately — a typed `Merchant`/`Healer`/… would recreate the Merchant <-> ShopScreen <-> DialogueManager
## compile cycle (the typed-interface remedy was REFUTED for that reason). The cost: renaming e.g. Healer.heal_cost
## silently DROPS the "Heal" dialogue option with NO compile error. This test is the guard — every method/signal
## DialogueManager scans for must still exist on the real class. Scripts are loaded + instantiated OFF-TREE (no
## add_child -> no _ready), so it's headless-safe and touches no live autoload state.

# Speaker-child components: script path -> the methods scanned/called on it. Most rows are the finder's has_method
# duck-scan (dialogue_manager.gd); the chess_match row also pins the getters ChessScreen.open_match reads directly
# (ai_blunder/player_is_white/wager_amount) — NOT scanned by the DM finder, so a rename passes the DM contract yet
# crashes at match start. The chess row therefore pins the full open_match getter surface.
const COMPONENT_CONTRACTS := {
	"res://scripts/components/merchant.gd": ["buy", "sell"],                     # _find_merchant
	"res://scripts/components/healer.gd": ["do_heal", "heal_cost"],             # _find_healer
	"res://scripts/components/bonfire.gd": ["rest"],                            # _find_bonfire
	"res://scripts/components/level_up.gd": ["level_up_stat", "level_up_cost"], # _find_levelup_station
	"res://scripts/components/chess_match.gd": ["ai_search_depth", "display_opponent_name", "ai_blunder", "player_is_white", "wager_amount"], # _speaker_chess (2) + ChessScreen.open_match (5)
}

# Transaction screens DialogueManager opens: script path -> the open method it calls (+ each awaits a `closed` signal).
const SCREEN_CONTRACTS := {
	"res://scripts/ui/shop_screen.gd": "open_shop",
	"res://scripts/ui/heal_screen.gd": "open_heal",
	"res://scripts/ui/level_up_screen.gd": "open_level_up",
	"res://scripts/ui/chess_screen.gd": "open_match",
	"res://scripts/ui/chip_install_screen.gd": "open_install",  # DialogueManager suspends into open_install, awaiting `closed`
}

# NPC speaker methods DialogueManager duck-scans (set_in_dialogue/note_speaking/note_speaking_stop/provoke/
# is_following/resolved_disposition + head_world_position for the dialogue face light), plus the `died` signal it
# connects. note_speaking_stop cuts the head-bob when the NPC stops delivering a line; head_world_position keys the
# face light. Player methods it calls from a dialogue choice.
const SPEAKER_METHODS := ["set_in_dialogue", "note_speaking", "note_speaking_stop", "provoke", "is_following", "resolved_disposition", "head_world_position"]
const PLAYER_METHODS := ["add_money", "notify_toast"]


func test_component_speaker_contracts_exist() -> void:
	for path in COMPONENT_CONTRACTS:
		var c = load(path).new()
		for m in COMPONENT_CONTRACTS[path]:
			assert_true(c.has_method(m), "%s must keep method '%s' — DialogueManager duck-scans for it (a rename silently drops the dialogue option)" % [path, m])
		c.free()


func test_screen_open_and_closed_contracts_exist() -> void:
	for path in SCREEN_CONTRACTS:
		var s = load(path).new()
		assert_true(s.has_method(SCREEN_CONTRACTS[path]), "%s must keep %s() — DialogueManager calls it to open the transaction screen" % [path, SCREEN_CONTRACTS[path]])
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
