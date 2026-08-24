extends GutTest

## The MGS "!" detection sting's PLAYER-vs-AMBIENT split (NpcAudioCues.on_spotted + NPC._on_spotted +
## Perception.noticed). When what the NPC noticed is the PLAYER, the sting is a 2D (AudioStreamPlayer, in-your-ear,
## no distance attenuation) one-shot so being detected is heard PERFECTLY from ANY distance — a roof sniper 500 m out
## is as loud as a guard at your back. When it noticed something else (another NPC, a thrown decoy, a scripted point)
## it stays POSITIONAL (AudioStreamPlayer3D at the spotter, faint from afar). The classification comes from
## Perception.noticed — WHAT the just_spotted edge was about — NOT from NPC._target, which is a PROXIMITY lock
## (NpcTargeting binds the nearest hostile by range while still UNAWARE, and NPC.tscn ships sight_range 500) and would
## make a guard that merely heard a can rattle sting "you've been seen".
##
## Driven off-tree: a bare NPC via load(...).new() (NO add_child -> no _ready, per CLAUDE.md), with a bare Perception
## + NpcAudioCues childed to it so the REAL NPC._on_spotted runs (its other calls, _popup_icon / _try_detection_bark,
## null-guard their off-tree children). AudioManager spawns its one-shot under the tree ROOT; we diff root's audio
## players before/after (the test_audio_manager_spawn.gd idiom — the headless dummy driver never emits `finished`, so
## we free the spawned player ourselves). The two npc_audio volume knobs are set to SENTINELS for the run (both ship
## at 0.0, which is also the old hardcoded value — a pin against 0.0 could not catch a hardcode or a knob swap).

const NPC_SCRIPT := "res://scripts/npc/npc.gd"
const FAR_AWAY := Vector3(500.0, 0.0, 500.0)  ## far beyond AudioManager.DEFAULT_3D_MAX_DISTANCE (30 m) — inaudible positionally
const PLAYER_VOL := -12.5   ## sentinel for npc_audio.alert_volume_db (2D player-detection sting)
const AMBIENT_VOL := -27.0  ## sentinel for npc_audio.alert_volume_db_vs_npc (positional ambient sting)

var _saved_player_stamp: int = 0
var _saved_ambient_stamp: int = 0
var _saved_player_vol: float = 0.0
var _saved_ambient_vol: float = 0.0


func before_each() -> void:
	# Both spot cooldowns are STATICS shared across every NPC; defeat them per test so each case gets its own sting,
	# and restore afterwards so we don't leak state into other suites. Same save/restore for the two tuning knobs.
	_saved_player_stamp = NpcAudioCues._last_alert_msec
	_saved_ambient_stamp = NpcAudioCues._last_ambient_alert_msec
	_reset_cooldowns()
	_saved_player_vol = GameSettings.npc_audio.alert_volume_db
	_saved_ambient_vol = GameSettings.npc_audio.alert_volume_db_vs_npc
	GameSettings.npc_audio.alert_volume_db = PLAYER_VOL
	GameSettings.npc_audio.alert_volume_db_vs_npc = AMBIENT_VOL


func after_each() -> void:
	NpcAudioCues._last_alert_msec = _saved_player_stamp
	NpcAudioCues._last_ambient_alert_msec = _saved_ambient_stamp
	GameSettings.npc_audio.alert_volume_db = _saved_player_vol
	GameSettings.npc_audio.alert_volume_db_vs_npc = _saved_ambient_vol


# --- NpcAudioCues.on_spotted: the two branches ------------------------------------------------------------------

func test_player_detected_stings_2d_from_any_distance() -> void:
	var rig := _rig()
	var before := _audio_players(get_tree().root)
	var played: bool = rig.cues.on_spotted(FAR_AWAY, true)
	var spawned := _newly_spawned(before)
	assert_true(played, "on_spotted(…, targeting_player = true) must report that it stung (the host gates the '!' popup on it)")
	assert_eq(spawned.size(), 1, "exactly ONE one-shot player spawns for a player-detection sting")
	if spawned.size() == 1:
		var p: Node = spawned[0]
		assert_true(p is AudioStreamPlayer,
			"YOU were detected -> the sting is a 2D AudioStreamPlayer (no distance falloff), NOT a positional 3D player — the spotter was %s away and must still be heard perfectly" % FAR_AWAY.length())
		assert_false(p is AudioStreamPlayer3D, "a 3D player would attenuate to silence past 30 m — the exact bug this split fixes")
		assert_eq(p.stream, NpcAudioCues.MGS_ALERT, "the 2D player plays the MGS '!' clip (Detected.wav)")
		assert_eq(p.bus, &"sfx", "the sting rides the SFX bus so the SFX volume slider still governs it")
		assert_almost_eq(float(p.volume_db), PLAYER_VOL, 0.001,
			"the 2D sting carries npc_audio.alert_volume_db (sentinel %s) — not a hardcode, not the vs-NPC knob" % PLAYER_VOL)
	_free_all(spawned)
	_teardown(rig)


func test_npc_detected_stings_positionally_at_the_spotter() -> void:
	var rig := _rig()
	var before := _audio_players(get_tree().root)
	var played: bool = rig.cues.on_spotted(FAR_AWAY, false)
	var spawned := _newly_spawned(before)
	assert_true(played, "on_spotted(…, targeting_player = false) still stings (the ambient NPC-vs-NPC cue)")
	assert_eq(spawned.size(), 1, "exactly ONE one-shot player spawns for an ambient contact")
	if spawned.size() == 1:
		var p: Node = spawned[0]
		assert_true(p is AudioStreamPlayer3D,
			"an NPC noticing ANOTHER NPC / a decoy stays POSITIONAL (AudioStreamPlayer3D at the spotter — faint from afar, an atmospheric cue not a warning)")
		if p is AudioStreamPlayer3D:
			assert_eq((p as AudioStreamPlayer3D).global_position, FAR_AWAY, "the positional sting sounds FROM the spotter's world position")
		assert_eq(p.stream, NpcAudioCues.MGS_ALERT, "the positional player plays the same MGS '!' clip")
		assert_eq(p.bus, &"sfx", "the positional sting rides the SFX bus too")
		assert_almost_eq(float(p.volume_db), AMBIENT_VOL, 0.001,
			"the positional sting carries npc_audio.alert_volume_db_vs_npc (sentinel %s) — not a hardcode, not the player knob" % AMBIENT_VOL)
	_free_all(spawned)
	_teardown(rig)


func test_fleer_never_stings_in_either_branch() -> void:
	var rig := _rig()
	rig.npc.threat_response = NPC.ThreatResponse.FLEE
	var before := _audio_players(get_tree().root)
	assert_false(rig.cues.on_spotted(FAR_AWAY, true), "a fleeing civilian noticing the player isn't a combat '!' alert (2D branch muted)")
	assert_false(rig.cues.on_spotted(FAR_AWAY, false), "…nor when it notices another NPC (positional branch muted)")
	assert_eq(_newly_spawned(before).size(), 0, "a FLEE host must spawn no audio at all")
	_teardown(rig)


# --- the two cooldowns: asymmetric on purpose --------------------------------------------------------------------

func test_ambient_sting_never_masks_the_player_detection_sting() -> void:
	# Two factions trade "!"s across the street (positional, faint) 1.5 s before a guard spots YOU: your 2D warning
	# (and its "!" popup, gated on the return) must still fire — the ambient throttle is NOT the player throttle.
	var rig := _rig()
	var before := _audio_players(get_tree().root)
	assert_true(rig.cues.on_spotted(FAR_AWAY, false), "an ambient contact stings first")
	assert_true(rig.cues.on_spotted(FAR_AWAY, true), "the PLAYER-detection sting right after it is NOT swallowed by the ambient stamp")
	var spawned := _newly_spawned(before)
	assert_eq(spawned.size(), 2, "both played: one positional, then one 2D")
	var kinds := spawned.map(func(p: Node) -> String: return "3d" if p is AudioStreamPlayer3D else "2d")
	assert_true(kinds.has("3d") and kinds.has("2d"), "one of each kind spawned (ambient positional + player 2D), got %s" % [kinds])
	_free_all(spawned)
	_teardown(rig)


func test_player_sting_dedups_a_swarm_and_silences_following_ambience() -> void:
	# A swarm spotting YOU at once = ONE 2D sting (the swarm de-dup the old shared cooldown always gave), and an
	# ambient contact right after a player sting yields to it (a caught-pickpocket victim's 2D "!" is not echoed by
	# its witnesses' positional ones a frame later).
	var rig := _rig()
	var before := _audio_players(get_tree().root)
	assert_true(rig.cues.on_spotted(FAR_AWAY, true), "first player-detection sting plays")
	assert_false(rig.cues.on_spotted(FAR_AWAY, true), "a second NPC spotting you in the same window is de-duped (swarm = one sting)")
	assert_false(rig.cues.on_spotted(FAR_AWAY, false), "an ambient sting inside the player window yields to it (no positional echo)")
	assert_eq(_newly_spawned(before).size(), 1, "only the first sting spawned a player")
	_free_all(_newly_spawned(before))
	_teardown(rig)


func test_ambient_stings_dedup_among_themselves() -> void:
	var rig := _rig()
	var before := _audio_players(get_tree().root)
	assert_true(rig.cues.on_spotted(FAR_AWAY, false), "first ambient sting plays")
	assert_false(rig.cues.on_spotted(FAR_AWAY, false), "a second ambient contact in the window is de-duped (a squad noticing a decoy = one sting)")
	assert_eq(_newly_spawned(before).size(), 1, "only the first ambient sting spawned a player")
	_free_all(_newly_spawned(before))
	_teardown(rig)


# --- Perception publishes WHAT it noticed --------------------------------------------------------------------------

func test_perception_publishes_what_each_spot_edge_was_about() -> void:
	var p := Perception.new()
	var who := Node.new()
	var src := Node.new()
	assert_null(p.noticed, "a fresh Perception has noticed nobody")

	p.alert_to(Vector3(1, 0, 1), who)
	assert_eq(p.noticed, who, "alert_to(pos, who) publishes WHO the forced alert is about (the attacker / the caught thief)")
	p.forget()
	assert_null(p.noticed, "forget() clears the last stimulus (a stale, possibly freed node must not leak into the next edge / a pooled life)")

	p.alert_to(Vector3(1, 0, 1))
	assert_null(p.noticed, "alert_to(pos) with no `who` = a hit we couldn't attribute -> nobody in particular")
	p.forget()

	p.investigate_point(Vector3(2, 0, 2), true, 0.0, NAN, src)
	assert_eq(p.noticed, src, "investigate_point(…, source) publishes the noise's emitter as what was noticed")
	p.forget()

	p.investigate_point(Vector3(2, 0, 2), true)
	assert_null(p.noticed, "a bare point (a decoy, a scripted 'go look here') is nobody in particular")
	p.forget()

	# Only the UNAWARE -> aware EDGE writes it: re-pointing an already-aware Perception must not rewrite the stimulus.
	p.investigate_point(Vector3(2, 0, 2), true, 0.0, NAN, src)
	p.investigate_point(Vector3(3, 0, 3), true, 0.0, NAN, who)
	assert_eq(p.noticed, src, "a second investigate_point while already INVESTIGATING (no edge, no sting) leaves `noticed` on the first stimulus")

	who.free()
	src.free()
	p.free()


# --- NPC.noticed_player() classifies by Perception.noticed, NOT by the proximity-locked _target ---------------------

func test_noticed_player_reads_what_was_noticed_not_the_proximity_target() -> void:
	# The trap this guards: every hostile in range holds the player as _target while still UNAWARE, so a guard that
	# hears a can rattle would sting "you've been seen" if the split keyed on _target. (The verdict lives in its own
	# pure method because the REAL _on_spotted reads global_position — an engine error off-tree — right after it.)
	var rig := _npc_rig()
	var player_stub := Node3D.new()  # Node3D: NPC._target is Node3D-typed
	player_stub.add_to_group(Groups.PLAYER)  # a stand-in for the Player (or a companion) — group membership is what's read
	var decoy := Node3D.new()  # e.g. an NPC's gunfire-pulse emitter — "something that isn't the player"

	# (A) proximity-locked on the player, but what it NOTICED is nobody (a decoy / a bare point) -> NOT the player
	rig.npc._target = player_stub
	rig.npc._perception.noticed = null
	assert_false(rig.npc.noticed_player(),
		"(A) _target is the player but Perception noticed NOBODY (a decoy) -> false -> the sting stays POSITIONAL; the proximity lock must not decide")

	# (B) no target at all, but what it NOTICED is the player (heard your footsteps / shot from nowhere) -> the player
	rig.npc._target = null
	rig.npc._perception.noticed = player_stub
	assert_true(rig.npc.noticed_player(),
		"(B) Perception noticed the PLAYER (no _target needed) -> true -> the 2D sting, heard from any distance")

	# (C) noticed some other node -> not the player
	rig.npc._target = player_stub
	rig.npc._perception.noticed = decoy
	assert_false(rig.npc.noticed_player(), "(C) noticed a non-player node -> false -> positional")

	# (D) the stimulus was FREED under us (a decoy expired, an attacker died before the edge was read) -> false, no error
	var doomed := Node3D.new()
	doomed.add_to_group(Groups.PLAYER)
	rig.npc._perception.noticed = doomed
	doomed.free()
	assert_false(rig.npc.noticed_player(), "(D) a freed stimulus reads false (is_instance_valid, Variant read) rather than erroring")

	player_stub.free()
	decoy.free()
	_teardown_npc_rig(rig)


func test_noticed_player_and_on_spotted_are_null_safe_off_tree() -> void:
	# A bare NPC (.new(), no _ready) has no _perception and no _audio_cues: both must be inert, not crash.
	var npc = load(NPC_SCRIPT).new()
	assert_false(npc.noticed_player(), "no Perception -> noticed nobody")
	npc.hp = 4.0
	npc._on_spotted()  # must not error (Perception read null-guarded; the cue child null-guarded, so global_position is never reached)
	npc.free()


func test_on_spotted_routes_the_verdict_into_the_cue() -> void:
	# _on_spotted itself is in-tree only (it reads global_position for the positional branch), so pin the routing by
	# source: the cue's second arg must be noticed_player(), never a _target read (the proximity-lock trap above).
	var src := FileAccess.get_file_as_string(NPC_SCRIPT)
	var start := src.find("func _on_spotted()")
	assert_gt(start, -1, "NPC defines _on_spotted (the just_spotted handler)")
	if start < 0:
		return
	var end := src.find("\n## ", start + 1)  # the handler's body ends where the next doc-commented member begins
	var body := src.substr(start, (end - start) if end > start else -1)
	assert_true(body.contains("_audio_cues.on_spotted(global_position, noticed_player())"),
		"_on_spotted hands the cue noticed_player() as its 2D-vs-positional verdict")
	assert_false(body.contains("_target.is_in_group"),
		"_on_spotted must NOT classify by _target (a proximity lock names the player even when what was noticed was a decoy)")


# --- the noise channel names its emitter -----------------------------------------------------------------------------

func test_noise_source_exposes_emitter_and_the_pulser_stamps_its_host() -> void:
	var src_bare := NoiseSource.new()
	assert_true("emitter" in src_bare, "NoiseSource exposes `emitter` (WHO made the sound — the node an investigating NPC noticed)")
	assert_null(src_bare.emitter, "a bare / authored NoiseSource is nobody in particular (a decoy, a beeper) until a spawner stamps it")
	src_bare.free()

	# NoisePulser (an NPC's gunfire / death pulse) stamps its HOST — an in-tree seam (pulse() places the source under
	# the host's parent). The channel is inert unless NPCs listen; if a designer switched hearing_initiates off this
	# spawns nothing, which is that feature's contract, not this one's.
	if not GameSettings.npc_ai.hearing_initiates:
		pass_test("hearing_initiates is off in the shipped tuning — NoisePulser deliberately spawns nothing; emitter stamping is unobservable here")
		return
	var holder := Node3D.new()
	add_child_autofree(holder)
	var host := Node3D.new()
	holder.add_child(host)
	var pulser := NoisePulser.new()
	host.add_child(pulser)
	var src: NoiseSource = pulser.pulse(5.0, false)
	assert_not_null(src, "an un-throttled, audible pulse spawns a NoiseSource")
	if src != null:
		assert_eq(src.emitter, host, "NoisePulser stamps the HOST as the pulse's emitter (a listener that investigates it noticed the host, not a bare point)")
		src.queue_free()


func test_player_noise_and_distraction_scan_carry_the_emitter() -> void:
	# NoiseEmitter.tick lazily builds the player's live source IN-TREE (a real Player's _ready is off-limits in a unit
	# test), and NpcDistraction.scan_distractions is a live &"noise"-group scan — pin both seams by source text.
	var emitter_src := FileAccess.get_file_as_string("res://scripts/player/noise_emitter.gd")
	assert_true(emitter_src.contains("_source.emitter = host"),
		"NoiseEmitter stamps the PLAYER as its live source's emitter — an NPC that investigates your footsteps/gunfire noticed YOU (2D sting)")
	var scan_src := FileAccess.get_file_as_string("res://scripts/npc/npc_distraction.gd")
	assert_true(scan_src.contains("is_instance_valid(src.emitter)"),
		"the distraction scan reads the source's emitter, sanitized (a one-shot source can outlive its emitter; a typed Node param rejects a freed handle)")
	assert_true(scan_src.contains(", NAN, who)"),
		"…and hands it to Perception.investigate_point as `source` (5th arg) so the '!' handler can tell 'I heard YOU' from 'I heard a can rattle'")


# --- tuning ------------------------------------------------------------------------------------------------------------

func test_tuning_group_exposes_both_alert_volumes() -> void:
	# Designer-first: the two volumes are @exports on the npc_audio tuning group (resources/tuning/NpcAudioSettings),
	# never hardcoded in the cue. Script defaults checked as a RANGE (the repo idiom — a designer retune survives).
	var s := NpcAudioSettings.new()
	assert_true("alert_volume_db" in s, "NpcAudioSettings exposes alert_volume_db (the 2D player-detection sting volume)")
	assert_true("alert_volume_db_vs_npc" in s, "NpcAudioSettings exposes alert_volume_db_vs_npc (the positional ambient sting volume)")
	assert_eq(typeof(s.get("alert_volume_db")), TYPE_FLOAT, "alert_volume_db is a float (dB)")
	assert_eq(typeof(s.get("alert_volume_db_vs_npc")), TYPE_FLOAT, "alert_volume_db_vs_npc is a float (dB)")
	assert_between(float(s.get("alert_volume_db")), -40.0, 24.0, "the player-detection sting defaults to an audible dB level (not muted, not clipping)")
	assert_between(float(s.get("alert_volume_db_vs_npc")), -40.0, 24.0, "the ambient sting defaults to an audible dB level too")
	assert_true(GameSettings.npc_audio is NpcAudioSettings, "GameSettings.npc_audio is the NpcAudioSettings group the cue reads")
	s = null


# --- rigs -----------------------------------------------------------------------------------------------------------

## A bare NPC (no _ready) as the typed host + a bare NpcAudioCues bound to it. Both freed by _teardown.
func _rig() -> Dictionary:
	var npc = load(NPC_SCRIPT).new()
	var cues := NpcAudioCues.new()
	cues.host = npc
	return {"npc": npc, "cues": cues}


func _teardown(rig: Dictionary) -> void:
	rig.cues.free()
	rig.npc.free()


## A bare NPC wired just enough for the REAL _on_spotted to run: a Perception (whose `noticed` we set by hand — the
## emit sites are pinned separately above) and an NpcAudioCues, both childed to the off-tree NPC so one free cleans up.
func _npc_rig() -> Dictionary:
	var npc = load(NPC_SCRIPT).new()
	npc.hp = 4.0  # a bare Character's hp is 0.0 and _on_spotted early-outs on a dead/zero-HP NPC
	var perception := Perception.new()
	npc.add_child(perception)
	npc._perception = perception
	var cues := NpcAudioCues.new()
	cues.host = npc
	npc.add_child(cues)
	npc._audio_cues = cues
	return {"npc": npc, "perception": perception, "cues": cues}


func _teardown_npc_rig(rig: Dictionary) -> void:
	rig.npc.free()  # frees the childed Perception + cues with it


func _reset_cooldowns() -> void:
	NpcAudioCues._last_alert_msec = -1000000
	NpcAudioCues._last_ambient_alert_msec = -1000000


func _free_all(players: Array) -> void:
	for p in players:
		if is_instance_valid(p):
			p.queue_free()


func _newly_spawned(before: Dictionary) -> Array:
	var out: Array = []
	for p in _audio_players(get_tree().root):
		if not before.has(p) and not p.is_queued_for_deletion():
			out.append(p)
	return out


func _audio_players(node: Node) -> Dictionary:
	var out := {}
	_collect_audio_players(node, out)
	return out


func _collect_audio_players(node: Node, out: Dictionary) -> void:
	if node is AudioStreamPlayer3D or node is AudioStreamPlayer or node is AudioStreamPlayer2D:
		out[node] = true
	for child in node.get_children():
		_collect_audio_players(child, out)
