extends GutTest

## The WAIT screen (scripts/ui/wait_screen.gd) — the Fallout-style "let some hours pass" panel on T.
##
## The two rules worth pinning are PURE statics, so they test off-tree: how much HP a wait pays out, and when
## waiting is refused. The clock advance itself is pinned in tests/test_world_clock.gd (it belongs to
## WorldClock, not to this screen), and the scene wiring is pinned at the bottom the way the other authored
## screens do it — a modal whose %unique names drift binds null at runtime and dies on the first open.

const WAIT := preload("res://scripts/ui/wait_screen.gd")
const SCENE := "res://scenes/ui/wait_screen.tscn"


# --- the HP trickle -----------------------------------------------------------------------------------

func test_recovery_pays_the_rate_per_hour() -> void:
	assert_almost_eq(WAIT.recovery_for(50.0, 100.0, 2.0, 1.0, 6), 12.0, 0.001, "6 hours at 2/hour = 12 HP")
	assert_almost_eq(WAIT.recovery_for(50.0, 100.0, 2.0, 1.0, 24), 48.0, 0.001,
			"a full 24-hour wait returns 48 HP — real help on a long walk, still nothing like a Bonfire's full heal")

func test_recovery_never_overshoots_the_cap() -> void:
	assert_almost_eq(WAIT.recovery_for(95.0, 100.0, 2.0, 1.0, 24), 5.0, 0.001,
			"the trickle stops at max HP, it does not overheal")
	assert_almost_eq(WAIT.recovery_for(50.0, 100.0, 2.0, 0.6, 24), 10.0, 0.001,
			"a 0.6 cap tops out at 60 HP, so a half-dead player wakes wounded-but-walking")

func test_recovery_never_removes_health() -> void:
	# The boundary that matters if a designer lowers hp_cap_fraction below the player's CURRENT health: the
	# wait must pay nothing, never subtract.
	assert_almost_eq(WAIT.recovery_for(90.0, 100.0, 2.0, 0.5, 24), 0.0, 0.001,
			"already past the cap -> gains nothing, and is NOT damaged down to it")

func test_recovery_is_zero_when_switched_off_or_pointless() -> void:
	assert_almost_eq(WAIT.recovery_for(50.0, 100.0, 0.0, 1.0, 24), 0.0, 0.001,
			"hp_per_hour 0 is the strict New Vegas rule — waiting never heals")
	assert_almost_eq(WAIT.recovery_for(50.0, 100.0, 2.0, 1.0, 0), 0.0, 0.001, "zero hours pays nothing")
	assert_almost_eq(WAIT.recovery_for(50.0, 0.0, 2.0, 1.0, 6), 0.0, 0.001,
			"a zero-max-HP host (a stub, a corpse) pays nothing rather than dividing into nonsense")


# --- the refusal threshold ----------------------------------------------------------------------------

func test_waiting_is_refused_once_something_is_hunting_you() -> void:
	assert_true(WAIT.hostile_blocks(StealthStatus.Level.DANGER),
			"in combat -> refused; waiting must never be a free exit from a firefight")
	assert_true(WAIT.hostile_blocks(StealthStatus.Level.CAUTION),
			"actively searching for you -> refused; they have not lost interest yet")

func test_waiting_is_allowed_while_merely_noticed() -> void:
	assert_false(WAIT.hostile_blocks(StealthStatus.Level.HIDDEN), "unseen -> allowed")
	assert_false(WAIT.hostile_blocks(StealthStatus.Level.DETECTED),
			"a meter that has merely STARTED filling is a guard glancing over, not a hunt — refusing here would make waiting impossible anywhere patrolled")

## A stand-in NPC reporting a fixed Perception.State toward ONE target and UNAWARE toward anyone else — the duck
## type StealthStatus.of_player aggregates. Keyed on the target so a refusal that asks the NPCs about the wrong
## node (or about nobody) reads as a calm world instead of agreeing by accident. RefCounted, never in the tree.
class _AwareNpc:
	var _state: int
	var _target: Object
	func _init(s: int, target: Object) -> void:
		_state = s
		_target = target
	func awareness_of(who: Node) -> int:
		return _state if who == _target else Perception.State.UNAWARE

## The refusal the screen's own rule (WaitScreen.refusal_for, what _blocked_reason applies to the live tree) gives
## for a grounded player on a running clock with NPCs in these awareness states around them.
func _refusal_with(states: Array, cfg: WaitSettings) -> int:
	var player := Node.new()  # a bare Node has no is_on_floor, so the airborne clause reads it as grounded
	var npcs: Array = []
	for s in states:
		npcs.append(_AwareNpc.new(s, player))
	var got: int = WAIT.refusal_for(600.0, player, npcs, cfg)
	player.free()
	return got

func test_an_npc_hunting_you_refuses_the_wait_but_a_glance_does_not() -> void:
	# The rule in the terms the player lives it — what the NPCs around you are DOING — driven through the screen's
	# own refusal rule, so dropping the hunt check, asking the NPCs about the wrong node, reading the wrong field
	# off the stealth aggregate, or a reordered Level ladder all show up here as a changed answer.
	var cfg := WaitSettings.new()
	cfg.hostile_awareness_blocks = true
	assert_eq(_refusal_with([], cfg), WaitScreen.Block.NONE, "an empty world never refuses a wait")
	assert_eq(_refusal_with([Perception.State.UNAWARE, Perception.State.UNAWARE], cfg), WaitScreen.Block.NONE,
			"nobody aware of you -> the wait is allowed")
	assert_eq(_refusal_with([Perception.State.DETECTING], cfg), WaitScreen.Block.NONE,
			"a guard whose meter is merely filling is a glance, not a hunt -> the wait is allowed")
	assert_eq(_refusal_with([Perception.State.INVESTIGATING], cfg), WaitScreen.Block.HOSTILE,
			"a guard SEARCHING for you -> refused as a hunt; they have not lost interest yet")
	assert_eq(_refusal_with([Perception.State.ALERTED], cfg), WaitScreen.Block.HOSTILE,
			"a guard fighting you -> refused as a hunt; waiting is never a combat exit")
	assert_eq(_refusal_with([Perception.State.UNAWARE, Perception.State.DETECTING, Perception.State.INVESTIGATING], cfg),
			WaitScreen.Block.HOSTILE,
			"one hunter among idle and glancing NPCs still refuses — the WORST awareness decides, not the majority")
	# Control: the same fighting guard with the designer's switch off lets the wait through, so the refusals above
	# come from the hunt check itself and not from anything else about this setup.
	cfg.hostile_awareness_blocks = false
	assert_eq(_refusal_with([Perception.State.ALERTED], cfg), WaitScreen.Block.NONE,
			"hostile_awareness_blocks = false turns the hunt refusal off — a guard fighting you no longer blocks the wait")
	cfg = null


func test_a_frozen_clock_refuses_the_wait() -> void:
	# day_length_seconds = 0 is the authored way to pin a level to one hour, and the day/night docs promise no
	# dawn (and so no rent) ever fires there. Waiting must not be the hole in that promise.
	var prev: float = WorldClock.day_length_seconds
	WorldClock.day_length_seconds = 0.0
	var frozen: int = WaitScreen._blocked_reason()
	WorldClock.day_length_seconds = prev   # restored BEFORE asserting, so a failure cannot leak a frozen clock
	assert_eq(frozen, WaitScreen.Block.CLOCK_FROZEN,
			"a frozen clock refuses the wait outright — time genuinely does not pass on that level")

func test_a_running_clock_does_not_refuse_on_the_frozen_path() -> void:
	# The CONTROL for the guard above: the same call with a running day and nothing else in play (no Player in
	# the tree, so no hostile/airborne check applies) must come back NONE — the guard keys on the frozen clock
	# alone, not on anything else about this setup.
	# The shipped default comes first: a fresh WorldClock (script default, no level override) must run, or every
	# level would freeze and the guard above would refuse T everywhere.
	var fresh: Node = load("res://managers/WorldClock.gd").new()
	var shipped: float = fresh.day_length_seconds
	fresh.free()
	assert_gt(shipped, 0.0,
			"SHIP DECISION: the day/night clock ships RUNNING - a 0 default would freeze every level and make T refuse everywhere")
	var prev: float = WorldClock.day_length_seconds
	WorldClock.day_length_seconds = 600.0
	var running: int = WaitScreen._blocked_reason()
	WorldClock.day_length_seconds = prev
	assert_eq(running, WaitScreen.Block.NONE, "a running clock does not refuse the wait — the frozen guard trips only on a stopped day")

func test_every_refusal_has_its_own_sentence() -> void:
	# Whole templates per reason, never a shared stem with the cause appended (the TextFormat fragment rule) —
	# so a locale can reword each independently.
	var seen := {}
	for reason in [WaitScreen.Block.HOSTILE, WaitScreen.Block.AIRBORNE, WaitScreen.Block.CLOCK_FROZEN]:
		var s: String = WaitScreen._block_text(reason)
		assert_false(s.is_empty(), "refusal %d has a message" % reason)
		assert_false(seen.has(s), "refusal %d reuses another reason's sentence: %s" % [reason, s])
		seen[s] = true


# --- tuning defaults ----------------------------------------------------------------------------------

func test_wait_settings_ship_sane() -> void:
	# Held for BOTH the script defaults and the shipped WaitSettings.tres the screen actually reads.
	for src in [WaitSettings.new(), GameSettings.wait]:
		var w: WaitSettings = src
		assert_between(w.default_hours, w.min_hours, w.max_hours, "the opening selection is inside its own range")
		assert_gt(w.hp_per_hour, 0.0, "SHIP DECISION: the trickle is on (0 would be the strict New Vegas rule)")
		assert_lt(w.hp_per_hour * float(w.max_hours), 100.0,
				"the longest wait must not out-heal a Bonfire rest, or fires stop being worth finding")
		assert_false(w.heals_limbs, "SHIP DECISION: waiting never mends limbs — that stays the Healer's and the Bonfire's job")
		assert_true(w.hostile_awareness_blocks, "SHIP DECISION: waiting is refused mid-hunt (the Fallout rule)")

func test_the_hour_stepper_clamps_a_mis_authored_range() -> void:
	# A designer can type anything into the inspector; the stepper must still offer a sane span. A 0-hour floor
	# would let the player "wait" no time at all, and a ceiling below the floor would leave no valid choice.
	var cfg: WaitSettings = GameSettings.wait
	var prev_min := cfg.min_hours
	var prev_max := cfg.max_hours
	cfg.min_hours = 0
	cfg.max_hours = 0
	var lo_bad: int = WaitScreen._min_hours()
	var hi_bad: int = WaitScreen._max_hours()
	cfg.min_hours = 3   # the control: a sane authored range comes through untouched
	cfg.max_hours = 12
	var lo_ok: int = WaitScreen._min_hours()
	var hi_ok: int = WaitScreen._max_hours()
	cfg.min_hours = 5   # an inverted span: the ceiling must lift to THIS floor, not to the hard 1-hour minimum
	cfg.max_hours = 2
	var lo_inv: int = WaitScreen._min_hours()
	var hi_inv: int = WaitScreen._max_hours()
	cfg.min_hours = prev_min   # restored BEFORE asserting, so a failure cannot leak a broken shipped resource
	cfg.max_hours = prev_max
	assert_eq(lo_bad, 1, "an authored 0-hour floor is raised to one hour — a wait always passes some time")
	assert_eq(hi_bad, 1, "a ceiling below the floor is lifted to the floor — the stepper always has one valid choice")
	assert_eq(lo_ok, 3, "a sane authored floor is honoured as-is")
	assert_eq(hi_ok, 12, "a sane authored ceiling is honoured as-is")
	assert_eq(lo_inv, 5, "an authored floor above the ceiling is honoured")
	assert_eq(hi_inv, 5,
			"a ceiling below an authored floor of 5 is lifted to that floor, not to 1 - the stepper keeps exactly one valid choice")

func test_wait_settings_are_registered_on_gamesettings() -> void:
	assert_not_null(GameSettings.wait, "GameSettings.wait resolves the authored WaitSettings.tres")
	assert_true(GameSettings.wait is WaitSettings, "...and it is the right resource type")


# --- scene wiring -------------------------------------------------------------------------------------

func test_scene_carries_every_bound_unique_name() -> void:
	# _bind_ui resolves these by %unique name; a rename in the editor binds null and the first open crashes.
	var packed: PackedScene = load(SCENE)
	assert_not_null(packed, "wait_screen.tscn loads")
	if packed == null:
		return
	var inst := packed.instantiate()
	add_child_autofree(inst)
	for nm in ["Root", "Dim", "Card", "Title", "NowLabel", "NowValue", "UntilLabel", "UntilValue",
			"Minus", "HoursLabel", "Plus", "Status", "WaitButton", "CloseButton"]:
		assert_not_null(inst.get_node_or_null("%" + nm), "scene exposes %%%s" % nm)

func test_scene_ships_with_no_authored_text() -> void:
	# Every string is set from PlayerText in _bind_ui — a string authored in the .tscn would be invisible to
	# the l10n sweep and to the text-debt scanner alike.
	# Read the SOURCE, not an instance: instantiating runs _ready -> _bind_ui, which has already stamped every
	# caption by the time a live node could be inspected (the mistake this test was written with first).
	var src: String = FileAccess.get_file_as_string(SCENE)
	assert_gt(src.length(), 0, "wait_screen.tscn source readable")
	assert_false(src.contains("\ntext = \""),
			"no `text = \"...\"` may be authored in wait_screen.tscn — every string comes from PlayerText at bind time")

func test_buttons_stay_pad_reachable() -> void:
	# The atm_screen must-not-recur rule: an authored focus_mode = 0 makes every button unreachable on a pad.
	var inst := (load(SCENE) as PackedScene).instantiate()
	add_child_autofree(inst)
	for nm in ["WaitButton", "CloseButton", "Minus", "Plus"]:
		var b := inst.get_node_or_null("%" + nm) as Button
		assert_not_null(b, "%s is a Button" % nm)
		if b != null:
			assert_ne(b.focus_mode, Control.FOCUS_NONE, "%s must stay focusable for controller navigation" % nm)

func test_changing_values_have_reserved_slots() -> void:
	# The card must not resize as the hours change or a refusal appears — every value that moves has a
	# minimum reserved in the scene (the status line is additionally hidden with ALPHA, not `visible`).
	var inst := (load(SCENE) as PackedScene).instantiate()
	add_child_autofree(inst)
	for nm in ["NowValue", "UntilValue"]:
		var l := inst.get_node_or_null("%" + nm) as Control
		assert_gt(l.custom_minimum_size.x, 0.0, "%s reserves width so a wider clock face cannot shift the row" % nm)
	assert_gt((inst.get_node("%HoursLabel") as Control).custom_minimum_size.x, 0.0,
			"the hour label reserves width, or '1 hour' -> '24 hours' slides the +/- buttons")
	assert_gt((inst.get_node("%Status") as Control).custom_minimum_size.y, 0.0,
			"the status line reserves height, or a refusal appearing re-centres the whole card")


# --- the keybind --------------------------------------------------------------------------------------

func test_wait_is_bound_and_rebindable() -> void:
	assert_true(InputMap.has_action(InputManager.action_wait), "the Wait action exists in the InputMap")
	var cat: ActionCatalog = load("res://resources/input/ActionCatalog.tres")
	var found := false
	for a in cat.actions:
		if a != null and a.action == InputManager.action_wait:
			found = true
			assert_ne(a.label, "", "the Wait row carries a visible label in Options -> Controls")
	assert_true(found, "ActionCatalog.tres must carry a Wait row — a keybind with no Options row is unrebindable")

func test_wait_and_claim_do_not_share_a_key() -> void:
	# Claim moved off T so Wait could take it (the Fallout muscle memory). Both are bare TAP verbs with no
	# modifier, so a shared default would make one of them unreachable.
	var wait_events := InputMap.action_get_events(InputManager.action_wait)
	var claim_events := InputMap.action_get_events(InputManager.action_claim)
	assert_false(wait_events.is_empty(), "Wait ships with a default binding")
	assert_false(claim_events.is_empty(), "Claim still ships with a default binding")
	for w in wait_events:
		for c in claim_events:
			if w is InputEventKey and c is InputEventKey:
				assert_ne((w as InputEventKey).physical_keycode, (c as InputEventKey).physical_keycode,
						"Wait and Claim must not default to the same physical key")
