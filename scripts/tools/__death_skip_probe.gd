extends Node
## Death-skip runtime probe — boots the REAL game, kills the REAL player and CLICKS through the death
## cinematic, then measures what the skip actually did.
##
## WHY: Player cannot be built in-tree in a GUT run (test_player_core.gd's construction note), so the unit
## tests can only pin the skip's data contract and its source shape. The two things that can only fail live
## are exactly the two this drives end to end:
##   1. THE INPUT REACHES US. The click is fed through Input.parse_input_event, so it takes the real viewport
##      route — GUI picking, the full-screen post-process ColorRect, the HUD — before reaching the dying
##      Player's _unhandled_input. A Control that swallowed it would be invisible to any off-tree test.
##   2. THE CINEMATIC IS SPED UP, NOT CUT. It checks that the world-reset cue (GameState.player_died) still
##      fires exactly once and that the revive lands FAR earlier than the ~6.5 s scored cinematic — i.e. the
##      tween's whole callback chain still ran, just faster.
##
## Run from the project root (headless is enough — nothing here needs a pixel):
##   godot --headless --path . res://scripts/tools/__death_skip_probe.tscn
##
## Driver-copy pattern (the __kill_shake_probe.gd idiom): this scene is the boot scene, but the run switches
## current_scene to game.tscn, which frees it — so _ready re-attaches a COPY of this script on a bare Node
## parented to root, which survives the scene change and drives the probe.

var _player_died_cue := 0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if get_tree().current_scene == self:
		var d := Node.new()
		d.name = "DeathSkipProbeDriver"
		d.set_script(get_script())
		get_tree().root.add_child.call_deferred(d)
		return
	_run()


func _run() -> void:
	await _frames(5)
	get_tree().change_scene_to_file("res://scenes/game.tscn")
	await _frames(150)

	var player: Node3D = Groups.human_player(get_tree())
	if player == null:
		print("PROBE_FAIL no Player"); get_tree().quit(1); return
	GameState.player_died.connect(func() -> void: _player_died_cue += 1)

	var fb: PlayerFeedbackSettings = GameSettings.player_feedback
	print("PROBE_KNOB enabled=", fb.death_skip_enabled, " delay=", fb.death_skip_delay,
			" speed=", fb.death_skip_speed, " sting_release=", fb.death_skip_sting_release)
	var unskipped: float = fb.death_sequence_time + fb.death_card_delay + fb.death_card_fade_time * 2.0 \
			+ fb.death_card_gap + player._death_mix.card_hold_seconds()
	print("PROBE_BASELINE unskipped cinematic = %.2fs" % unskipped)

	# --- die -----------------------------------------------------------------------------------------
	var t0 := Time.get_ticks_msec()
	player.die()
	await _wait(0.15)
	if not player._dying:
		print("PROBE_FAIL die() did not start the cinematic"); get_tree().quit(1); return
	# Inside the watch window: a click must be REFUSED (this is the anti-mash guard).
	_click()
	await _frames(2)
	if player._death_skipped:
		print("PROBE_FAIL a click was accepted inside death_skip_delay"); get_tree().quit(1); return
	print("PROBE_OK early click refused (still inside death_skip_delay)")

	# --- beat one: click past the keel-over, land on the card -----------------------------------------
	await _wait(maxf(fb.death_skip_delay, 0.0) + 0.15)
	_click()
	await _frames(3)
	if not player._death_skipped:
		print("PROBE_FAIL the click never reached the dying Player (_unhandled_input / GUI swallow?)")
		get_tree().quit(1); return
	print("PROBE_OK beat 1 skipped at +%.2fs" % ((Time.get_ticks_msec() - t0) / 1000.0))

	# The card should be UP (full alpha) long before the unskipped timeline would have raised it.
	await _wait(0.9)
	var card = player._death_card
	if card == null or not card.visible or card.modulate.a < 0.99:
		print("PROBE_FAIL the card is not fully up after the first skip: ", card)
		get_tree().quit(1); return
	var card_at := (Time.get_ticks_msec() - t0) / 1000.0
	print("PROBE_OK card fully up at +%.2fs (unskipped: %.2fs)" % [card_at, fb.death_sequence_time + fb.death_card_delay + fb.death_card_fade_time])
	if player._death_skip_ready_msec < 0:
		print("PROBE_FAIL the skip did not re-arm on the card"); get_tree().quit(1); return

	# --- beat two: click the card away ---------------------------------------------------------------
	await _wait(maxf(fb.death_skip_delay, 0.0) + 0.1)
	_click()
	await _wait(1.5)
	if player._dying:
		print("PROBE_FAIL still dying 1.5s after the second skip"); get_tree().quit(1); return
	var total := (Time.get_ticks_msec() - t0) / 1000.0
	print("PROBE_OK revived at +%.2fs (unskipped cinematic is %.2fs)" % [total, unskipped])
	if total >= unskipped:
		print("PROBE_FAIL the skip saved no time"); get_tree().quit(1); return
	if _player_died_cue != 1:
		print("PROBE_FAIL the world-reset cue fired %d times, expected exactly 1" % _player_died_cue)
		get_tree().quit(1); return
	print("PROBE_OK GameState.player_died fired exactly once — the chain ran, it just ran faster")
	# THE SONG PLAYS OUT IN FULL THROUGH A SKIP (death_skip_sting_release = 0): the click fast-forwards the
	# cinematic's tween, and an audio stream is the one beat that cannot ride it. Only checkable when a sting
	# was ever going to sound, and only before the clip's own natural end.
	var mix = player._death_mix
	if mix._sting_will_play() and fb.death_skip_sting_release <= 0.0 and total < mix.sting_end_time():
		if not mix.playing:
			print("PROBE_FAIL the sting stopped at +%.2fs — a skip must let the song play out in full (natural end %.2fs)"
					% [total, mix.sting_end_time()])
			get_tree().quit(1); return
		print("PROBE_OK the song is still playing at +%.2fs into the new life (natural end %.2fs)"
				% [total, mix.sting_end_time()])
	print("PROBE_OK skip path done")

	# --- and the REGRESSION: a death nobody touches must still run at its authored, sting-scored length --
	# The skip added a callback to the cinematic's chain (_on_death_card_shown). A tween_callback is
	# zero-duration, so the respawn must still land on death_sting_sync_point exactly as before.
	await _wait(1.5)
	_player_died_cue = 0
	var t1 := Time.get_ticks_msec()
	player.die()
	await _wait(unskipped + 0.6)
	var untouched := (Time.get_ticks_msec() - t1) / 1000.0
	if player._dying:
		print("PROBE_FAIL an unskipped death did not finish in %.2fs" % untouched); get_tree().quit(1); return
	if player._death_skipped:
		print("PROBE_FAIL an unskipped death set the skip latch"); get_tree().quit(1); return
	if _player_died_cue != 1:
		print("PROBE_FAIL unskipped: the world-reset cue fired %d times" % _player_died_cue); get_tree().quit(1); return
	print("PROBE_OK an untouched death still ran its full %.2fs cinematic" % unskipped)
	print("PROBE_PASS click-to-skip works end to end, and leaves the unskipped death alone")
	get_tree().quit(0)


## A real left-click, through the real input pipeline.
func _click() -> void:
	var down := InputEventMouseButton.new()
	down.button_index = MOUSE_BUTTON_LEFT
	down.pressed = true
	Input.parse_input_event(down)
	var up := InputEventMouseButton.new()
	up.button_index = MOUSE_BUTTON_LEFT
	up.pressed = false
	Input.parse_input_event(up)


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


## Wall-clock wait: the cinematic drops the world into slow-mo, so a scaled timer would drift.
func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds, true, false, true).timeout
