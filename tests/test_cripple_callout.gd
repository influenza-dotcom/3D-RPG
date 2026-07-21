extends GutTest

## Off-tree logic tests for CrippleCallout (scripts/components/cripple_callout.gd): the pure part-name mapping and
## the react() branches — the player-attacker toast ("Crippled X's arm"), the self-bark ("My arm!"), the lethal-hit
## suppression, the non-player-attacker path, the disabled / unmapped-part gates, and the @export toast colour.
## Built bare (.new(), no NPC) per CLAUDE.md with duck-typed stubs; everything here is deterministic (no random).
##
## NOTE: references CrippleCallout + Character.BodyPart by class_name — both must be in the class cache, so run this
## only AFTER the editor has re-imported the new cripple_callout.gd (a fresh class_name isn't cached until then).

class StubTalkable:
	var voice = null  # a VoiceData in-game; the stub only needs the property to exist for _emit_bark(text, voice)

class StubPlayer extends Node:
	var last_toast: String = ""
	var last_color: Color = Color.BLACK
	var toast_count: int = 0
	func notify_toast(text: String, color: Color) -> void:
		last_toast = text
		last_color = color
		toast_count += 1

class StubHost:
	var display_name: String = "Kyle"
	var _dead: bool = false
	var hp: float = 10.0
	var player: Node = null       # what _real_player() returns (the toast target)
	var talkable := StubTalkable.new()
	var last_bark: String = ""
	var bark_count: int = 0
	func _real_player() -> Node:
		return player
	func _find_talkable() -> StubTalkable:
		return talkable
	func _emit_bark(line: String, _voice: Variant) -> void:
		last_bark = line
		bark_count += 1

## A player Node in the &"Player" group (so the attacker gate + notify_toast path fire), wired as the host's
## _real_player(). Added to the tree + autofreed so is_in_group is unambiguous and no leak survives the test.
func _host_and_player() -> Array:
	var h := StubHost.new()
	var pl := StubPlayer.new()
	add_child_autofree(pl)
	pl.add_to_group(&"Player")
	h.player = pl
	return [h, pl]

## This file pins the toast/bark FORMATTING ("Crippled Kyle's arm"), not the "Stranger until introduced" masking
## (that's test_stranger_names.gd). Run with masking OFF so host.display_name flows through GameState.public_name
## unchanged; restored after each test so no state leaks to other files.
func before_each() -> void:
	GameState.stranger_names_enabled = false

func after_each() -> void:
	GameState.stranger_names_enabled = true

func test_part_name_mapping() -> void:
	assert_eq(CrippleCallout._cripple_part_name(Character.BodyPart.HEAD), "head", "HEAD -> head")
	assert_eq(CrippleCallout._cripple_part_name(Character.BodyPart.ARMS), "arm", "ARMS -> arm")
	assert_eq(CrippleCallout._cripple_part_name(Character.BodyPart.LEGS), "leg", "LEGS -> leg")
	assert_eq(CrippleCallout._cripple_part_name(Character.BodyPart.TORSO), "", "TORSO -> no callout")

func test_player_cripple_toasts_and_barks() -> void:
	var cc := CrippleCallout.new()
	var pair := _host_and_player()
	var h: StubHost = pair[0]
	var pl: StubPlayer = pair[1]
	cc.react(h, Character.BodyPart.LEGS, pl)
	assert_eq(pl.last_toast, "Crippled Kyle's leg", "the player who crippled us gets a named + part toast")
	assert_eq(pl.toast_count, 1, "exactly one toast")
	assert_eq(h.last_bark, "", "the NPC cries out the crippled part")  # bark pool ships EMPTY (silent) per the scrub — no authored callout text yet
	cc.free()

func test_lethal_hit_toasts_but_no_bark() -> void:
	var cc := CrippleCallout.new()
	var pair := _host_and_player()
	var h: StubHost = pair[0]
	var pl: StubPlayer = pair[1]
	h._dead = true  # the crippling hit was lethal
	cc.react(h, Character.BodyPart.ARMS, pl)
	assert_eq(pl.toast_count, 1, "a lethal cripple still toasts the player")
	assert_eq(h.bark_count, 0, "but a dying NPC doesn't cry out 'My arm!'")
	cc.free()

func test_non_player_attacker_no_toast_still_barks() -> void:
	var cc := CrippleCallout.new()
	var pair := _host_and_player()
	var h: StubHost = pair[0]
	var pl: StubPlayer = pair[1]
	var other := Node.new()  # a NON-player crippled us (not in the &"Player" group)
	add_child_autofree(other)
	cc.react(h, Character.BodyPart.ARMS, other)
	assert_eq(pl.toast_count, 0, "a non-player cripple doesn't toast the player")
	assert_eq(h.last_bark, "", "the NPC still cries out regardless of who crippled it")  # bark pool ships EMPTY (silent) per the scrub — no authored callout text yet
	cc.free()

func test_disabled_no_callouts() -> void:
	var cc := CrippleCallout.new()
	cc.enabled = false
	var pair := _host_and_player()
	var h: StubHost = pair[0]
	var pl: StubPlayer = pair[1]
	cc.react(h, Character.BodyPart.LEGS, pl)
	assert_eq(pl.toast_count, 0, "enabled=false -> no toast")
	assert_eq(h.bark_count, 0, "enabled=false -> no bark")
	cc.free()

func test_unmapped_part_no_callout() -> void:
	var cc := CrippleCallout.new()
	var pair := _host_and_player()
	var h: StubHost = pair[0]
	var pl: StubPlayer = pair[1]
	cc.react(h, Character.BodyPart.TORSO, pl)
	assert_eq(pl.toast_count, 0, "TORSO has no part word -> no toast")
	assert_eq(h.bark_count, 0, "TORSO has no part word -> no bark")
	cc.free()

func test_empty_name_uses_enemy() -> void:
	var cc := CrippleCallout.new()
	var pair := _host_and_player()
	var h: StubHost = pair[0]
	var pl: StubPlayer = pair[1]
	h.display_name = ""
	cc.react(h, Character.BodyPart.HEAD, pl)
	assert_eq(pl.last_toast, "Crippled Enemy's head", "a nameless NPC toasts as 'Enemy'")
	cc.free()

func test_toast_color_uses_export() -> void:
	var cc := CrippleCallout.new()
	cc.toast_color = Color(0.1, 0.2, 0.3)
	var pair := _host_and_player()
	var h: StubHost = pair[0]
	var pl: StubPlayer = pair[1]
	cc.react(h, Character.BodyPart.LEGS, pl)
	assert_eq(pl.last_color, Color(0.1, 0.2, 0.3), "the toast uses the @export toast_color, not a hardcoded literal")
	cc.free()
