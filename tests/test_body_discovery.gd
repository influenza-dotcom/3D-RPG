extends GutTest

## Stealth body-discovery (flag-gated): a dead NPC leaves a discoverable Corpse marker, and a nearby UNAWARE NPC that
## SEES it investigates + calls out. Covers:
##  - Corpse: joining the scan group, the persisted `discovered` marker + its authored save key, and noticeable()
##    (the pure range gate).
##  - The scan (NpcSenses.nearest_visible_corpse), driven on a stand-in host in a clear stretch of world: the
##    body-discovery gate, the observer's OWN sight range, the dead/fleeing guard and one-investigator-per-body.
##  - The call-out (NpcVoice.bark_check_body), driven on a stand-in host: which pool it speaks from, and the dead /
##    earshot / cooldown gates — plus the dead guard on the real npc.gd (bare, listener lookup counted) so the host API
##    the stand-ins imitate can't drift.
## Still manual-playtest (they need real level geometry, a live NPC or an autosave): the WALL-occlusion half of the
## line-of-sight ray, spawn-on-death (NpcMortality.spawn_corpse_marker) and the investigate reaction
## (NpcDistraction.discover_corpse). Pinned elsewhere: the NpcAiSettings.body_discovery script default
## (test_managers_tuning.gd), the value the shipped .tres carries (test_settings_load.gd), the global-OR-per-NPC opt-in
## (test_stealth_sense_optin.gd), the legacy re-key of a corpse that gains a save_id (test_save_identity.gd) and
## _pick_bark's override-over-default precedence with non-empty pools (test_npc_data.gd).

## Far from anything another test might leave behind, so the scan's line-of-sight ray sees open air.
const SCAN_ORIGIN := Vector3(0.0, -2000.0, 6000.0)


## Stand-in for the NPC members NpcSenses.nearest_visible_corpse reads (its host is a duck-typed Node). _perception is
## a REAL Perception, so the sight_range / eye_height names the scan reads are the shipped ones.
class ScanHost extends Node3D:
	var discovery_on := true
	var _perception: Perception = null
	var _dead := false
	var hp := 10.0
	var fleeing := false

	func _body_discovery_on() -> bool:
		return discovery_on

	func is_fleeing() -> bool:
		return fleeing


## Stand-in for the NPC members NpcVoice.bark_check_body reads. CHECK_BODY_LINES is AUTHORED here (the shipped const is
## empty) so the emitted line names the pool it came from, and _pick_bark is the REAL NPC resolution.
class BarkHost extends Node3D:
	var CHECK_BODY_LINES: Array[String] = ["Hey -- a body!"]
	var _dead := false
	var hp := 10.0
	var player: Node3D = null
	var emitted: Array = []

	func is_hostile() -> bool:
		return false

	func _find_talkable():
		return null

	func _real_player():
		return player

	func _pick_bark(fallback: Array[String], override: Array[String]) -> String:
		return NPC._pick_bark(fallback, override)

	func _emit_bark(line: String, _voice) -> void:
		emitted.append(line)


## Counts bark REQUESTS reaching NpcVoice.emit (the body behind the real NPC._emit_bark facade) without starting the
## awaited bubble / TTS path, so a bare off-tree NPC can be the host.
class _RequestCountingVoice extends NpcVoice:
	var requested := 0

	func emit(_line: String, _voice: VoiceData) -> void:
		requested += 1


## The REAL npc.gd host with ONE seam swapped: the listener lookup. npc.gd's own _real_player reads get_tree(), which
## a bare NPC (never in the tree, _ready never run) cannot do, so this answers "no player in the world" and COUNTS the
## ask. Every other member bark_check_body reads — _dead, hp, _find_talkable, is_hostile, CHECK_BODY_LINES, _pick_bark,
## _emit_bark — is npc.gd's own.
class _ListenerCountingNpc extends NPC:
	var listener_lookups := 0

	func _real_player() -> Node3D:
		listener_lookups += 1
		return null


# --- Corpse marker ---

func test_corpse_ready_joins_the_scan_group() -> void:
	var c := Corpse.new()
	add_child_autofree(c)  # in-tree so _ready runs
	assert_true(c.is_in_group(&"corpse"), "_ready registers the marker in the &\"corpse\" scan group")

func test_corpse_save_id_key_prefers_authored_id() -> void:
	var c := Corpse.new()
	c.save_id = &"alley_body"
	assert_eq(c.save_key(), "id:alley_body", "an authored save_id is the stable corpse discovery key")
	c.free()

func test_corpse_ready_restores_discovered_marker() -> void:
	var old_corpses: Dictionary = GameState.discovered_corpses.duplicate()
	GameState.discovered_corpses = {"id:alley_body": true}
	var c := Corpse.new()
	c.save_id = &"alley_body"
	add_child_autofree(c)
	assert_true(c.discovered, "_ready restores an already-discovered authored corpse marker from GameState")
	GameState.discovered_corpses = old_corpses

func test_noticeable_is_a_range_gate() -> void:
	var body := Vector3(10.0, 0.0, 0.0)
	var near := Vector3(2.0, 0.0, 0.0)   # 8 m away
	var far := Vector3(40.0, 0.0, 0.0)   # 30 m away
	assert_true(Corpse.noticeable(body, near, 25.0), "a body 8 m off, 25 m sight -> noticed")
	assert_false(Corpse.noticeable(body, far, 25.0), "a body 30 m off, 25 m sight -> unnoticed")

func test_noticeable_includes_the_exact_edge_and_guards_zero_range() -> void:
	var body := Vector3.ZERO
	var at_edge := Vector3(25.0, 0.0, 0.0)
	assert_true(Corpse.noticeable(body, at_edge, 25.0), "exactly at sight range still counts (<=)")
	assert_false(Corpse.noticeable(body, Vector3(0.1, 0.0, 0.0), 0.0), "zero sight range -> never (a blind/edge NPC)")


# --- The scan: NpcSenses.nearest_visible_corpse ---

func _scan_host() -> ScanHost:
	var h := ScanHost.new()
	h._perception = Perception.new()
	autofree(h._perception)
	add_child_autofree(h)
	h.global_position = SCAN_ORIGIN
	return h


## A marker that has run its real _ready (joined the scan group, consulted the discovery ledger), lying `offset` from
## the scan host.
func _body_at(offset: Vector3) -> Corpse:
	var c := Corpse.new()
	add_child_autofree(c)
	c.global_position = SCAN_ORIGIN + offset
	return c


func _senses_for(h: Node) -> NpcSenses:
	var s := NpcSenses.new()
	s.host = h
	autofree(s)
	return s


func test_scan_notices_a_fresh_body_only_within_the_observers_own_sight_range() -> void:
	var h := _scan_host()
	h._perception.sight_range = 10.0
	var body := _body_at(Vector3(6.0, 0.0, 0.0))
	var senses := _senses_for(h)
	assert_eq(senses.nearest_visible_corpse(), body,
		"an unaware NPC must notice a fresh body lying in plain view 6 m away, inside its 10 m sight range")
	body.global_position = SCAN_ORIGIN + Vector3(14.0, 0.0, 0.0)
	assert_null(senses.nearest_visible_corpse(),
		"the same body 14 m away is past THIS NPC's 10 m sight range, so it must go unnoticed")


func test_scan_skips_a_body_another_npc_already_investigated() -> void:
	var h := _scan_host()
	var body := _body_at(Vector3(3.0, 0.0, 0.0))
	var senses := _senses_for(h)
	assert_eq(senses.nearest_visible_corpse(), body,
		"control: a freshly spawned body 3 m away (unknown to the discovery ledger) is noticed")
	body.discovered = true
	assert_null(senses.nearest_visible_corpse(),
		"once one NPC has claimed a body the next passer-by must ignore it: one investigation per corpse, not a crowd")


func test_scan_finds_no_body_while_body_discovery_is_off() -> void:
	var h := _scan_host()
	h.discovery_on = false
	var body := _body_at(Vector3(3.0, 0.0, 0.0))
	var senses := _senses_for(h)
	assert_null(senses.nearest_visible_corpse(),
		"with body discovery off for this NPC, a body in plain view must not be noticed (a stealth kill stays free)")
	h.discovery_on = true
	assert_eq(senses.nearest_visible_corpse(), body,
		"control: the same NPC and body with body discovery on -> noticed")


func test_a_dead_or_fleeing_npc_notices_no_body() -> void:
	var h := _scan_host()
	var body := _body_at(Vector3(3.0, 0.0, 0.0))
	var senses := _senses_for(h)
	h._dead = true
	assert_null(senses.nearest_visible_corpse(), "a dead NPC must not notice (and so claim) a body")
	h._dead = false
	h.hp = 0.0
	assert_null(senses.nearest_visible_corpse(), "an NPC at 0 hp (dying this frame) must not claim a body")
	h.hp = 10.0
	h.fleeing = true
	assert_null(senses.nearest_visible_corpse(), "an NPC running for its life must not stop to investigate a body")
	h.fleeing = false
	assert_eq(senses.nearest_visible_corpse(), body, "control: the same NPC alive and standing its ground notices it")


# --- The call-out: NpcVoice.bark_check_body ---

## A BarkHost in-tree (the earshot check reads global_position) with the listening player `listener_distance` away.
func _bark_host(listener_distance: float) -> BarkHost:
	var h := BarkHost.new()
	add_child_autofree(h)
	var listener := Node3D.new()
	add_child_autofree(listener)
	listener.global_position = h.global_position + Vector3(listener_distance, 0.0, 0.0)
	h.player = listener
	return h


func _voice_for(h: Node, bark_set: BarkSet) -> NpcVoice:
	var v := NpcVoice.new()
	v.host = h
	v._bark_set = bark_set
	autofree(v)
	return v


func test_check_body_pool_ships_unauthored() -> void:
	# SHIP DECISION (the AI-text scrub, see REMEDIATION_PLAN "Do not fill the empty bark arrays"): bark text is authored
	# content that belongs in a BarkSet .tres, never in the npc.gd const.
	assert_eq(NPC.CHECK_BODY_LINES.size(), 0,
		"CHECK_BODY_LINES ships EMPTY: an NPC finds a body in silence until a designer authors BarkSet.check_body")


func test_body_call_out_speaks_the_archetype_line_over_the_default() -> void:
	var plain := _bark_host(2.0)
	_voice_for(plain, BarkSet.new()).bark_check_body()
	assert_eq(plain.emitted, ["Hey -- a body!"],
		"an NPC whose BarkSet leaves check_body empty must call out the NPC's default body line")
	var raider := _bark_host(2.0)
	var raider_set := BarkSet.new()
	var body_lines: Array[String] = ["Stay sharp -- a corpse."]
	var spot_lines: Array[String] = ["Contact!"]
	raider_set.check_body = body_lines
	raider_set.spot = spot_lines
	_voice_for(raider, raider_set).bark_check_body()
	assert_eq(raider.emitted, ["Stay sharp -- a corpse."],
		"an archetype that authored check_body must say ITS body line: not the default, and not its combat 'spot' call-out")


func test_body_call_out_needs_a_living_npc_with_the_player_in_earshot() -> void:
	var bark_distance: float = GameSettings.npc_bark.bark_distance
	var control := _bark_host(1.0)
	_voice_for(control, BarkSet.new()).bark_check_body()
	assert_eq(control.emitted, ["Hey -- a body!"], "control: a living NPC with the player 1 m away calls out the body")
	var dead := _bark_host(1.0)
	dead._dead = true
	_voice_for(dead, BarkSet.new()).bark_check_body()
	assert_eq(dead.emitted, [], "a dead NPC must not call out a body")
	var dying := _bark_host(1.0)
	dying.hp = 0.0
	_voice_for(dying, BarkSet.new()).bark_check_body()
	assert_eq(dying.emitted, [], "an NPC at 0 hp must not call out a body")
	var far := _bark_host(bark_distance + 5.0)
	_voice_for(far, BarkSet.new()).bark_check_body()
	assert_eq(far.emitted, [], "an NPC farther than bark_distance from the player stays quiet: nobody is there to hear it")
	var alone := _bark_host(1.0)
	alone.player = null
	_voice_for(alone, BarkSet.new()).bark_check_body()
	assert_eq(alone.emitted, [], "with no player in the world there is no listener, so no call-out")


func test_body_call_out_is_paced_by_the_bark_cooldown() -> void:
	var h := _bark_host(1.0)
	var v := _voice_for(h, BarkSet.new())
	v.bark_check_body()
	v.bark_check_body()
	assert_eq(h.emitted, ["Hey -- a body!"],
		"two bodies spotted in the same beat must draw ONE call-out, not a stutter (the shared bark cooldown)")


## One bark_check_body on the real npc.gd host posed at `hp` / `dead`: how often it went looking for a listener, and how
## many call-outs it requested through NPC._emit_bark -> NpcVoice.emit.
func _real_npc_body_bark(hp: float, dead: bool) -> Dictionary:
	var npc := _ListenerCountingNpc.new()
	npc.hp = hp
	npc._dead = dead
	var voice := _RequestCountingVoice.new()
	voice.host = npc
	npc._voice = voice
	voice.bark_check_body()
	var out := {"lookups": npc.listener_lookups, "requested": voice.requested}
	npc._voice = null
	voice.free()
	npc.free()
	return out


func test_a_dead_real_npc_does_not_call_out_a_body() -> void:
	# The dead guard on the REAL host, so the member names the BarkHost stand-in imitates (_dead, hp) cannot drift from
	# npc.gd. A bare NPC has no player to hear it, so "no call-out" alone cannot tell the guard from the empty world;
	# what CAN is how far the trigger got. The guard is the first thing bark_check_body checks, so a dead NPC stops
	# before it ever looks for a listener, and the control — the same bare host, alive — gets past it and does look.
	var control := _real_npc_body_bark(10.0, false)
	assert_eq(control["lookups"], 1,
		"control: a living npc.gd gets past the dead guard and looks for a listener in earshot")
	assert_eq(control["requested"], 0, "control: ...and with no player in the world it still requests no call-out")
	var dying := _real_npc_body_bark(0.0, false)
	assert_eq(dying["lookups"], 0,
		"an npc.gd at 0 hp (dying this frame) is refused by the guard before it ever looks for a listener")
	assert_eq(dying["requested"], 0, "...so it requests no body call-out through NPC._emit_bark")
	var corpse := _real_npc_body_bark(10.0, true)
	assert_eq(corpse["lookups"], 0,
		"an npc.gd flagged _dead is refused by the guard even with hp left on it (the death latch, not just the hp read)")
	assert_eq(corpse["requested"], 0, "...so a corpse requests no body call-out either")
