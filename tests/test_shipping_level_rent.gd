extends GutTest

## The shipping level ARMS the rent. RentCollector is inert by default (`rent_amount = 0` -> `collect()`
## returns immediately), so the entire debt clock's only recurring non-interest sink is a scene-authored
## export — exactly the class of state that silently reverts when a level is re-saved, and that no unit test
## of the component itself can see. The component's own behaviour is covered by tests/test_rent_collector.gd;
## this pins that a level actually TURNS IT ON.
##
## Pinned against the PackedScene's STATE, never instantiated — the shipping level is ~590 nodes of func_godot
## brush geometry, NPCs and lights, and building it (plus its _ready cascade) to read four exports would be
## absurd. SceneState is the same read the FirstPersonBody / payment-rail wiring tests use.
##
## ⭐The `{amount}` pin is not pedantry: RentCollector._fmt_paid() substitutes by REPLACE, so a paid_message
## that lost its token still renders — as a toast with no number in it. A designer retyping the line is the
## likely way that breaks, and it degrades silently in play.

const LEVEL_SCENE := "res://scenes/levels/trenchboom_test_level.tscn"


func _level_state() -> SceneState:
	var ps := load(LEVEL_SCENE) as PackedScene
	assert_not_null(ps, "the shipping level scene must load: %s" % LEVEL_SCENE)
	return ps.get_state() if ps != null else null


## Find a node by name in a SceneState; -1 when absent.
func _node_index(state: SceneState, node_name: String) -> int:
	for i in range(state.get_node_count()):
		if state.get_node_name(i) == node_name:
			return i
	return -1


## Read a property off a SceneState node by name; null when the node doesn't author it.
func _node_prop(state: SceneState, idx: int, prop: String) -> Variant:
	for p in range(state.get_node_property_count(idx)):
		if state.get_node_property_name(idx, p) == prop:
			return state.get_node_property_value(idx, p)
	return null


func test_shipping_level_has_a_rent_collector() -> void:
	var state := _level_state()
	if state == null:
		return
	assert_gte(_node_index(state, "RentCollector"), 0,
		"the shipping level must carry a RentCollector — it is the debt clock's only recurring sink, and without it an unpaid balance has no pressure behind it")


func test_the_rent_is_actually_armed() -> void:
	var state := _level_state()
	if state == null:
		return
	var idx := _node_index(state, "RentCollector")
	assert_gte(idx, 0, "RentCollector must exist before its rent can be checked")
	if idx < 0:
		return
	var amount: Variant = _node_prop(state, idx, "rent_amount")
	assert_not_null(amount,
		"the level must AUTHOR rent_amount — falling back to the script default (0.0) makes collect() a no-op and the landlord silently disappears")
	if amount == null:
		return
	assert_gt(float(amount), 0.0,
		"rent_amount must be > 0 to arm the collector; 0 is the component's documented off-switch")


## A RentCollector carrying exactly what the shipping level authors (script defaults for anything it leaves out),
## built OFF-TREE so neither the WorldClock connection nor a Player lookup runs — only the dawn schedule.
func _shipped_collector(state: SceneState, idx: int) -> RentCollector:
	var rc := RentCollector.new()
	for p in range(state.get_node_property_count(idx)):
		var prop := state.get_node_property_name(idx, p)
		if prop == "script":
			continue
		rc.set(prop, state.get_node_property_value(idx, p))
	return rc


func test_the_shipped_rent_recurs_after_a_one_time_notice_dawn() -> void:
	# Drives the level's own configuration through its notice dawn, its grace window and then THREE rent periods
	# of dawns (the notice -> grace -> period schedule in RentCollector._consume_dawn), so whatever combination of
	# period_days / grace_days the level authors — or leaves at the script default — is judged by the schedule the
	# player actually lives. The horizon is sized from those same authored knobs, so a retune (weekly rent, a
	# longer grace) still gets three periods to prove the rent recurs instead of tripping a hidden dawn cap.
	var state := _level_state()
	if state == null:
		return
	var idx := _node_index(state, "RentCollector")
	assert_gte(idx, 0, "RentCollector must exist before its schedule can be driven")
	if idx < 0:
		return
	var rc := _shipped_collector(state, idx)
	var horizon := 1 + maxi(0, rc.grace_days) + 3 * maxi(1, rc.period_days)
	watch_signals(rc)
	var charge_dawns: Array[int] = []
	var charged_before_notice := false
	for dawn in range(1, horizon + 1):
		if rc._consume_dawn():
			charge_dawns.append(dawn)
			if get_signal_emit_count(rc, "notice_served") == 0:
				charged_before_notice = true
	assert_signal_emit_count(rc, "notice_served", 1,
		"the shipped collector states its terms exactly ONCE — a notice that repeats every dawn is a nag, one that never fires leaves 'what rent?' unanswered")
	assert_false(charged_before_notice, "no charge may land before the notice has been served")
	assert_false(charge_dawns.has(1),
		"dawn 1 is the notice dawn — money moving on the same dawn the terms are first stated reads as a charge with no referent")
	assert_gt(charge_dawns.size(), 1,
		"within three rent periods after the notice dawn and grace window (%d dawns) the shipped rent must come due more than once — a debt clock that bills once (or never) puts no recurring pressure on an unpaid balance (charges on dawns %s)" % [horizon, charge_dawns])
	for i in range(2, charge_dawns.size()):
		assert_eq(charge_dawns[i] - charge_dawns[i - 1], charge_dawns[1] - charge_dawns[0],
			"rent must come due on a steady cadence once the meter starts (charges on dawns %s)" % [charge_dawns])
	rc.free()


func test_the_charge_is_never_silent() -> void:
	var state := _level_state()
	if state == null:
		return
	var idx := _node_index(state, "RentCollector")
	if idx < 0:
		return
	var paid: Variant = _node_prop(state, idx, "paid_message")
	var missed: Variant = _node_prop(state, idx, "missed_message")
	assert_false(paid == null or String(paid).is_empty(),
		"paid_message must be authored — a blank message is the component's SILENT mode, and money leaving the wallet with no toast reads to a player as a bug")
	assert_false(missed == null or String(missed).is_empty(),
		"missed_message must be authored — missing rent is the moment the debt clock is supposed to bite, and it is the one beat the player must not miss")


func test_the_paid_toast_can_show_the_amount() -> void:
	var state := _level_state()
	if state == null:
		return
	var idx := _node_index(state, "RentCollector")
	if idx < 0:
		return
	var paid: Variant = _node_prop(state, idx, "paid_message")
	if paid == null:
		return
	var text := String(paid)
	assert_true(text.contains("{amount}") or text.contains("%s"),
		"paid_message must carry the {amount} token (or the legacy %s) — _fmt_paid substitutes by replace, so a line without it renders a rent toast that never says how much was taken")


## ⭐The rest of this file pins the ANSWER TO "WHAT RENT?".
##
## The shipping clock is 600 s/day starting at noon, so the first dawn lands 7m30s into a fresh run, and
## `EconomySettings.player_starting_money` is 0 — so an un-graced, un-noticed collector is GUARANTEED to make
## its first and only impression a red "you failed to pay" toast for a charge the game never mentioned. That is
## not a difficulty tuning question, it is a charge arriving with no referent. These four tests pin the level's
## side of the fix: the terms are stated, they name the money, and the statement lands a full in-game day
## before the first zorkmid moves.

func test_the_terms_are_stated_before_any_money_moves() -> void:
	var state := _level_state()
	if state == null:
		return
	var idx := _node_index(state, "RentCollector")
	if idx < 0:
		return
	var notice: Variant = _node_prop(state, idx, "notice_message")
	assert_false(notice == null or String(notice).is_empty(),
		"notice_message must be authored — without it the FIRST thing the game ever says about rent is that the player failed to pay it, for a charge nothing in the level establishes. There is no landlord, no lease and no home anywhere in the project; this toast is the only thing that can answer 'what rent?'")


func test_the_notice_names_the_money() -> void:
	var state := _level_state()
	if state == null:
		return
	var idx := _node_index(state, "RentCollector")
	if idx < 0:
		return
	var notice: Variant = _node_prop(state, idx, "notice_message")
	if notice == null:
		return
	assert_true(String(notice).contains("{amount}"),
		"the notice must carry {amount} — a statement of terms that does not say how much is owed is not a statement of terms, and substitution is by replace so a retyped line degrades silently to prose with no number in it")


func test_the_player_gets_a_grace_day_before_the_first_charge() -> void:
	var state := _level_state()
	if state == null:
		return
	var idx := _node_index(state, "RentCollector")
	if idx < 0:
		return
	var grace: Variant = _node_prop(state, idx, "grace_days")
	assert_not_null(grace,
		"grace_days must be AUTHORED on the shipping level — the script default is 0, which serves the notice and the bill on the same dawn and puts the first charge 7m30s into a fresh run against a wallet that starts at 0")
	if grace == null:
		return
	assert_gte(int(grace), 1,
		"grace_days must be >= 1 so the notice lands a full in-game day before the meter starts — the player must have had a chance to earn the rent before being told they are short of it")


func test_the_missed_toast_can_show_the_shortfall() -> void:
	var state := _level_state()
	if state == null:
		return
	var idx := _node_index(state, "RentCollector")
	if idx < 0:
		return
	var missed: Variant = _node_prop(state, idx, "missed_message")
	if missed == null:
		return
	var text := String(missed)
	assert_true(text.contains("{shortfall}") or text.contains("{amount}"),
		"missed_message must name a number ({shortfall} and/or {amount}) — this line used to reach notify_toast RAW, and a miss toast that cannot say how much was missed is how it decayed into 'the shortfall has been noted'")
