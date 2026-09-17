extends RefCounted

## The AI — per-NPC verbs of the in-game debug console (`who`, `brain`, `npc <verb>`): one of the three command
## families split out of debug_actions_world.gd on 2026-09-11 (with debug_actions_world_story.gd and
## debug_actions_world_view.gd). `DebugActionsWorld.run()` still owns EVERY match arm — a registry row's case lives
## there and calls in here — so adding a command is still ONE registry row + ONE match case, plus the `_cmd_*`
## static in the family file it belongs to. Shared helpers live in debug_actions_world_common.gd (`Common.`).
## `notarget` deliberately stays in the main file: tests/test_debug_ai_seams.gd pins its meta writes there.
##
## CONTRACT (as the main file): a `_cmd_*` returns the lines to print — NEVER null, NEVER push_error.

const Common := preload("res://scripts/components/debug_actions_world_common.gd")
## `npc hostile|neutral|friendly` writes Disposition.Kind and `brain`/`npc` read Perception.State — both enums come
## off the preloaded scripts (never `Disposition.Kind` / `Perception.State` by class_name) for the same stale-cache
## reason as the two above; the inspector does the same for Disposition (debug_inspector.gd:40).
const DispositionScript := preload("res://scripts/npc/disposition.gd")
const PerceptionScript := preload("res://scripts/npc/perception.gd")
## `brain` re-runs the PURE planner (GoapPlanner.plan / select_goal are statics with no host, no tree, no side
## effect) over the executor's own goal + action library, so the "why this plan" readout can never disagree with
## what the executor would decide from the same facts.
const GoapPlannerScript := preload("res://scripts/npc/goap/goap_planner.gd")


# =============================================================================================================
# AI — the per-NPC verbs (brain / npc <verb> / notarget)
# =============================================================================================================

## The world POINT for `npc investigate` / `npc walkto`. When the crosshair is on the acted-on NPC itself, the
## hit is on ITS BODY — "walk to where you already stand" — so "here" resolves to YOUR position (walk to me /
## investigate me, the classic per-NPC poke) and the output says so. When the NPC is the sticky one, the crosshair
## is free to point at the floor across the room, and THAT hit is the point. Vector3.INF = no usable point; the
## caller prints the workflow hint. Reads the inspector's cached hit (hit_point(), physics-tick, INF when nothing
## was struck) — never a fresh raycast, for the reason on _resolve_aimed_npc.
static func _npc_point(ctx: Dictionary, pick: Dictionary) -> Dictionary:
	var out := {&"point": Vector3.INF, &"how": ""}
	var npc: Node = pick[&"npc"]
	var aimed: Node = pick[&"aimed"]
	if aimed != null and aimed == npc:
		var player := Common._player3d(ctx)
		if player == null or not player.is_inside_tree():
			out[&"how"] = "the crosshair is on the NPC itself and there is no player to stand in for \"here\""
			return out
		out[&"point"] = player.global_position
		out[&"how"] = "your position (the crosshair is on the NPC itself, so \"here\" means you)"
		return out
	var insp := Common._inspector(ctx)
	if insp == null or not insp.has_method(&"hit_point"):
		out[&"how"] = "DebugInspector has no hit_point() accessor"
		return out
	var raw: Variant = insp.call(&"hit_point")
	if raw is Vector3:
		var p: Vector3 = raw
		if p.is_finite():
			out[&"point"] = p
			out[&"how"] = "the crosshair hit at %s" % Common._vec3_text(p)
			return out
	out[&"how"] = "the crosshair is on nothing — aim at the floor / a wall where it should go and run it again"
	return out

## `brain` — the GOAP "why this plan" dump for the aimed NPC. The executor keeps ONLY the winner (decide() stores
## current_goal + plan and select_goal SHORT-CIRCUITS, so losing goals are never even planned) and the shipped
## "goal / action" label cannot show why a behaviour silently never runs (a sensed sentinel fact self-satisfies a
## goal -> plan() == [] -> skipped; goap_executor.gd @risk lines). So this re-runs the PURE planner over a FRESH
## world state and prints every candidate, then puts the executor's STICKY plan beside it, labelled — the two can
## legitimately differ, because tick() only replans when the stepped action is null or is_runtime_valid() fails.
## Everything here is read-only: _build_world_state is underscore-private but pure (host reads), plan()/
## select_goal() are side-effect-free statics, and is_runtime_valid() on every shipped action is a plain state read.
static func _cmd_brain(ctx: Dictionary) -> PackedStringArray:
	var pick := Common._resolve_aimed_npc(ctx)
	var err: String = pick[&"error"]
	if err != "":
		return Common._one("brain: " + err)
	var npc: Node = pick[&"npc"]
	var out := PackedStringArray()
	out.append("brain: %s%s" % [Common._npc_label(npc), "   (sticky: your last `npc` target — the crosshair is not on an NPC)" if bool(pick[&"sticky"]) else ""])
	if not _alive(npc):
		out.append("dead — the executor stopped ticking with the body; the plan below is whatever it last held")

	var executor: Object = npc.get(&"_executor")
	if executor == null or not is_instance_valid(executor):
		out.append("no _executor on this NPC (bare / partially built) — nothing plans for it")
		return out
	if not executor.has_method(&"_build_world_state"):
		out.append("the executor has no _build_world_state(host) — API drift between goap_executor.gd and this command")
		return out

	# --- the sensed facts (a FRESH snapshot, exactly what tick() would build this frame) ---
	var ws: Variant = executor.call(&"_build_world_state", npc)
	if ws == null or not is_instance_valid(ws):
		out.append("_build_world_state returned nothing")
		return out
	var facts_v: Variant = ws.get(&"facts")
	var facts: Dictionary = facts_v if facts_v is Dictionary else {}
	out.append("facts " + Common._facts_text(facts))
	var cutscene: Variant = npc.get(&"_cutscene_control")
	if cutscene is bool and bool(cutscene):
		out.append("! under cutscene control (freezeai / `npc walkto|freeze` / a CutsceneActor) — the executor is NOT ticking; its plan below is frozen where it was")

	var goals_v: Variant = executor.get(&"goals")
	var actions_v: Variant = executor.get(&"actions")
	var goals: Array = goals_v if goals_v is Array else []
	var actions: Array = actions_v if actions_v is Array else []
	if goals.is_empty() or actions.is_empty():
		out.append("library: %d goal(s), %d action(s) — an empty library never plans (setup() not run?)" % [goals.size(), actions.size()])
		return out

	# --- every goal, in priority order, each planned from the fresh facts ---
	var would_pick: Object = GoapPlannerScript.select_goal(ws, goals, actions)
	var ordered: Array = goals.duplicate()
	ordered.sort_custom(func(a: Variant, b: Variant) -> bool: return _goal_priority(a, ws) > _goal_priority(b, ws))
	out.append("-- goals by priority(ws)   (* = what select_goal would pick NOW: highest priority with a non-empty plan)")
	for g in ordered:
		if g == null or not is_instance_valid(g):
			continue
		var gname := _name_of(g)
		var mark := "*" if g == would_pick else " "
		var satisfied := bool(g.call(&"satisfied_by", ws)) if g.has_method(&"satisfied_by") else false
		var unmet := int(g.call(&"unmet_count", ws)) if g.has_method(&"unmet_count") else -1
		var plan: Array = GoapPlannerScript.plan(ws, actions, g)
		var plan_text := ""
		if not plan.is_empty():
			plan_text = "plan %s  (cost %.1f)" % [_plan_text(plan), _plan_cost(plan, ws)]
		elif satisfied:
			plan_text = "no plan — ALREADY SATISFIED, so select_goal skips it (a sensed sentinel fact would silence this goal for good)"
		else:
			plan_text = "no plan — " + _why_no_plan(g, actions, ws)
		out.append(" %s %-12s prio %5.2f  unmet %d  %s" % [mark, gname, _goal_priority(g, ws), unmet, plan_text])

	# --- every action against the same facts ---
	out.append("-- actions   (available = preconditions hold in the facts; runtime = is_runtime_valid(npc) this instant)")
	for a in actions:
		if a == null or not is_instance_valid(a):
			continue
		var avail := bool(a.call(&"available_in", ws)) if a.has_method(&"available_in") else false
		var cost := float(a.call(&"cost", ws)) if a.has_method(&"cost") else 0.0
		var runtime := bool(a.call(&"is_runtime_valid", npc)) if a.has_method(&"is_runtime_valid") else false
		var pre_v: Variant = a.get(&"preconditions")
		var eff_v: Variant = a.get(&"effects")
		out.append("   %-12s cost %4.1f  available %-3s  runtime %-3s  pre %s  eff %s" % [
			_name_of(a), cost, "yes" if avail else "no", "yes" if runtime else "no",
			Common._facts_text(pre_v if pre_v is Dictionary else {}), Common._facts_text(eff_v if eff_v is Dictionary else {})])

	# --- what the executor is ACTUALLY stepping (its sticky plan) vs the fresh pick ---
	var cur_goal: Object = executor.get(&"current_goal")
	var cur_plan_v: Variant = executor.get(&"plan")
	var cur_plan: Array = cur_plan_v if cur_plan_v is Array else []
	var index := Common._int_of(executor.get(&"index"))
	var stepping: Object = null
	if executor.has_method(&"current_action"):
		stepping = executor.call(&"current_action")
	var goal_text := _name_of(cur_goal) if cur_goal != null and is_instance_valid(cur_goal) else "-"
	var step_text := "-"
	if stepping != null and is_instance_valid(stepping):
		step_text = _name_of(stepping)
		if stepping.has_method(&"is_runtime_valid"):
			step_text += "  [runtime %s]" % ("valid" if bool(stepping.call(&"is_runtime_valid", npc)) else "INVALID — replans on its next think tick")
	out.append("-- executor NOW: goal %s   plan %s   index %d/%d   stepping %s" % [goal_text, _plan_text(cur_plan) if not cur_plan.is_empty() else "[]", index, cur_plan.size(), step_text])
	var pick_text := _name_of(would_pick) if would_pick != null and is_instance_valid(would_pick) else "- (NO feasible goal — Idle should always be; check the goals allow-list)"
	if would_pick != null and cur_goal != null and would_pick == cur_goal:
		out.append("   planner would pick NOW: %s — same goal the executor holds" % pick_text)
	else:
		out.append("   planner would pick NOW: %s — DIFFERS from the executor: tick() only replans when the stepped action is null or is_runtime_valid() fails, so the held plan is sticky until then" % pick_text)
	out.append("(re-run to watch it change; a distant UNAWARE NPC thinks on the AI-LOD cadence, so a poke can take ~0.25 s to land)")
	return out

## `npc <verb> [value]` — act on ONE NPC: the one under the crosshair, else the sticky last one. Every shipped AI
## verb is cast-wide (killall / peace / aggro / freezeai) and the only per-NPC surface was the read-only `who`;
## the bugs that needed "poke this one and watch" — the home-return leash, follow-blink, ledge-following, pacing
## on props, stairs — are all per-NPC. See each verb for the seam it drives and the trap it dodges.
static func _cmd_npc(ctx: Dictionary, args: PackedStringArray) -> PackedStringArray:
	var verb := args[0].strip_edges().to_lower()
	var pick := Common._resolve_aimed_npc(ctx)
	var err: String = pick[&"error"]
	if err != "":
		return Common._one("npc %s: %s" % [verb, err])
	var npc: Node = pick[&"npc"]
	var out := PackedStringArray()
	out.append("npc %s -> %s%s" % [verb, Common._npc_label(npc), "   (sticky: your last `npc` target — the crosshair is not on an NPC)" if bool(pick[&"sticky"]) else ""])
	# validate() has already checked the verb against the registry's word list; the value slot is a NUMBER only
	# `sight` reads — it is accepted (and ignored) on every other verb so `npc kill 3` is not an arity error.
	var value := args[1].to_float() if args.size() > 1 else NAN
	match verb:
		"kill": out.append_array(_npc_kill(ctx, npc))
		"heal": out.append_array(_npc_heal(npc))
		"restock": out.append_array(_npc_restock(npc))
		"hostile": out.append_array(_npc_disposition(npc, DispositionScript.Kind.HOSTILE))
		"neutral": out.append_array(_npc_disposition(npc, DispositionScript.Kind.NEUTRAL))
		"friendly": out.append_array(_npc_disposition(npc, DispositionScript.Kind.FRIENDLY))
		"provoke": out.append_array(_npc_provoke(ctx, npc))
		"alert": out.append_array(_npc_alert(ctx, npc))
		"investigate": out.append_array(_npc_investigate(ctx, pick))
		"walkto": out.append_array(_npc_walkto(ctx, pick))
		"release": out.append_array(_npc_control(npc, false, "release"))
		"freeze": out.append_array(_npc_control(npc, true, "freeze"))
		"unfreeze": out.append_array(_npc_control(npc, false, "unfreeze"))
		"home": out.append_array(_npc_home(npc))
		"panic": out.append_array(_npc_panic(npc))
		"sight": out.append_array(_npc_sight(npc, value))
		"rebrain": out.append_array(_npc_rebrain(npc))
		_:
			out.append("unknown verb \"%s\" (registry/actions drift — add a case in _cmd_npc)" % verb)
	return out

## kill: take_damage (NOT die()) so the kill is fully credited — XP, notify_kill, bounty, wallet bequeath, a
## lootable corpse — with the same hitstop suppression `killall` uses (FreezeFrame.pause_briefly and the per-body
## death freeze beat are both gated on allow_timescale_changes, and with the beat skipped the death completes
## synchronously inside this call, so restoring the flag right after is safe).
static func _npc_kill(ctx: Dictionary, npc: Node) -> PackedStringArray:
	if not _alive(npc):
		return Common._one("already dead — take_damage early-returns on the death latch, nothing to do")
	if not npc.has_method(&"take_damage"):
		return Common._one("no take_damage() on this node")
	var player := Common._player(ctx)
	var saved_allow := bool(GameSettings.allow_timescale_changes)
	GameSettings.allow_timescale_changes = false
	npc.call(&"take_damage", Common.KILL_DAMAGE, false, player)
	GameSettings.allow_timescale_changes = saved_allow
	var out := PackedStringArray()
	out.append("killed (%.0f damage, hitstop suppressed, allow_timescale_changes back to %s)" % [Common.KILL_DAMAGE, str(saved_allow)])
	if player == null:
		out.append("! no player passed as the attacker — no XP, no kill bounty, no quest notify_kill")
	else:
		out.append("credited to you: XP, notify_kill, bounty, wallet bequeath; gore/gibs, a lootable corpse, witness barks and the faction kill_penalty all fired")
	# The SAME predicate _record_snapshot_death (npc.gd) and WorldSnapshot use: pooled OR _dynamic_spawn = a dynamic
	# actor. EncounterSpawner stamps _dynamic_spawn on every body it produces (pooled ones included), so the _pool
	# half is belt-and-braces for a body pooled by some other route — mirroring the ledger's own gate rather than
	# half of it keeps this line true if that ever changes.
	var pool: Variant = npc.get(&"_pool")
	var pooled := pool != null and is_instance_valid(pool)
	if Common._bool_of(npc.get(&"_dynamic_spawn")) or pooled:
		out.append("a dynamic (spawner-produced%s) body — its death stays OUT of the save's death ledger" % (" / pooled" if pooled else ""))
	else:
		# _record_snapshot_death writes an authored NPC's node path into GameState's per-level death ledger, which the
		# world ledger folds into every save (autosave included) — so it stays dead on any load and on a door return.
		out.append("! an AUTHORED NPC — its death is recorded in the world ledger: it stays dead through a door return and in any save made from here (autosave included)")
	return out

## heal: prefer NpcHomeReturn.restore_full_health (the leash's own top-up: Character.heal() so `damaged` fires for
## any bound bar, plus heal_limbs so a crippled leg does not outlive the reset), else the same two seams by hand.
static func _npc_heal(npc: Node) -> PackedStringArray:
	if not _alive(npc):
		return Common._one("dead — heal restores survivors, it never revives a corpse (there is no path back past the death freeze)")
	var before := Common._float_of(npc.get(&"hp"))
	var max_hp := Common._float_of(npc.get(&"max_hp"))
	var out := PackedStringArray()
	var home: Object = npc.get(&"_home_return")
	if home != null and is_instance_valid(home) and home.has_method(&"restore_full_health"):
		var restored := bool(home.call(&"restore_full_health"))
		out.append("NpcHomeReturn.restore_full_health: %s  hp %.0f -> %.0f / %.0f (limbs cleared either way)" % [
			"restored" if restored else "already full", before, Common._float_of(npc.get(&"hp")), max_hp])
		return out
	if not npc.has_method(&"heal"):
		return Common._one("no heal() on this node")
	if npc.has_method(&"heal_limbs"):
		npc.call(&"heal_limbs")
	npc.call(&"heal", maxf(max_hp - before, 0.0))
	out.append("heal(): hp %.0f -> %.0f / %.0f, limbs cleared (no NpcHomeReturn on this NPC — healed by hand)" % [before, Common._float_of(npc.get(&"hp")), max_hp])
	return out

## restock: NPC.restore_spent_ammo — the AMMO half of the player-death encounter reset, driven by hand so you can
## watch it without dying. Refills the magazine and returns every spare clip this NPC's reloads BURNED; it never
## hands back ammo you PICKPOCKETED (the ledger only books clips as they are spent), so a guard you stripped to
## disarm him stays stripped no matter how often you run this. Prints the mag + reserve either side of the call,
## which is what makes the "stolen ammo did NOT come back" half visible.
static func _npc_restock(npc: Node) -> PackedStringArray:
	if not _alive(npc):
		return Common._one("dead — a corpse's backpack is the loot you earned; the restock only tops up survivors")
	if not npc.has_method(&"restore_spent_ammo"):
		return Common._one("no restore_spent_ammo() on this node")
	var weapon: Variant = npc.get(&"_weapon")
	if weapon == null or not is_instance_valid(weapon):
		return Common._one("no weapon hub — a CIVILIAN (weapon_data unset) has no magazine to fill and no caliber to stock")
	var caliber: StringName = &""
	var wd: Variant = weapon.get(&"equipped_weapon")
	if wd != null and is_instance_valid(wd):
		caliber = wd.caliber
	var bag: Variant = npc.get(&"inventory")
	var has_bag := bag != null and is_instance_valid(bag)
	var mag_before := Common._int_of(weapon.get(&"current_ammo"))
	var clips_before := int(bag.call(&"ammo_count", caliber)) if has_bag and caliber != &"" else 0
	var restored := bool(npc.call(&"restore_spent_ammo"))
	var out := PackedStringArray()
	out.append("NPC.restore_spent_ammo: %s  magazine %d -> %d" % [
		"gave ammo back" if restored else "nothing owed (it has fired nothing since the last restock)",
		mag_before, Common._int_of(weapon.get(&"current_ammo"))])
	if caliber == &"":
		out.append("  its weapon is caliber-less (melee / free-refill) — there is no reserve to restock")
	elif has_bag:
		out.append("  reserve %s: %d -> %d clips  (only clips its RELOADS spent; anything you pickpocketed stays yours)" % [
			caliber, clips_before, int(bag.call(&"ammo_count", caliber))])
	else:
		out.append("  no backpack on this body — the magazine free-refills and no reserve is tracked")
	return out

## hostile / neutral / friendly — the HostilityHelpers.resolved_kind composite, written as ONE attitude change:
## disposition + disposition_overrides_faction=true (so a factioned NPC reads its OWN disposition instead of the
## faction's rep — `peace` cannot pacify a predisposed raider precisely because the faction decides), then the
## REPEATABLE de-provoke (stand_down_on_player_death: drops _provoked and restores the exact rep the provoke took,
## no cue, does not spend the once-per-life holster pardon that forgive_provoke would), the rim recolour, and
## stand_down (drop target / forget / hide laser) so the AI re-scans against the NEW attitude. Live-only: neither
## save tier stores disposition, so a reload restores the authored attitude.
static func _npc_disposition(npc: Node, kind: int) -> PackedStringArray:
	if not _alive(npc):
		return Common._one("dead — a corpse has no attitude to change")
	var before_kind := int(npc.call(&"resolved_disposition")) if npc.has_method(&"resolved_disposition") else -1
	npc.set(&"disposition", kind)
	npc.set(&"disposition_overrides_faction", true)
	var settled := false
	if npc.has_method(&"stand_down_on_player_death"):
		settled = bool(npc.call(&"stand_down_on_player_death"))
	if npc.has_method(&"_apply_outline"):
		npc.call(&"_apply_outline")
	if npc.has_method(&"stand_down"):
		npc.call(&"stand_down")
	var after_kind := int(npc.call(&"resolved_disposition")) if npc.has_method(&"resolved_disposition") else kind
	var out := PackedStringArray()
	out.append("attitude %s -> %s  (disposition written, disposition_overrides_faction = true: its faction's rep no longer decides)" % [_disposition_text(before_kind), _disposition_text(after_kind)])
	if settled:
		out.append("its provoke was settled and the exact faction rep that provoke took was restored")
	out.append("target dropped + perception forgotten + laser hidden — it re-scans within ~%.1f s against the new attitude" % _retarget_interval())
	if after_kind == DispositionScript.Kind.HOSTILE:
		out.append("hostile: it re-acquires you by proximity (no LOS gate) inside sight_range — unless `notarget` is on")
	else:
		out.append("non-hostile: dialogue / pickpocket / trade are open on it now; a hit still provoke()s it back to HOSTILE")
	out.append("live-only — neither save tier stores disposition; a reload restores the authored attitude. Rim recoloured.")
	return out

## provoke: apply_rep MUST be false — the default true charges GameSettings.reputation.provoke_penalty, and a debug
## poke should aggro the body without souring the whole faction (the same GA-3 reasoning as `aggro`).
static func _npc_provoke(ctx: Dictionary, npc: Node) -> PackedStringArray:
	if not _alive(npc):
		return Common._one("dead — provoke() is not gated on the death latch and would flip a corpse's outline for nothing")
	if not npc.has_method(&"provoke"):
		return Common._one("no provoke() on this node")
	var player := Common._player(ctx)
	if player == null:
		return Common._one("no player to provoke it onto")
	var was: Variant = npc.get(&"_provoked")
	npc.call(&"provoke", player, false)
	var out := PackedStringArray()
	if was is bool and bool(was):
		out.append("already provoked — provoke() is idempotent, nothing changed")
	else:
		out.append("provoked onto you (apply_rep = false: NO faction reputation spent). Rim red, negative icon popped.")
	out.append("undo: `npc neutral` / `npc friendly` (settles the provoke), or `peace` for the whole cast")
	return out

## alert: Perception.alert_to(your position, you) — full lock-on at a known spot, the "just got shot" reaction. The
## second arg names YOU as what it noticed (Perception.noticed), so from UNAWARE the "!" is the 2D player-detection
## sting, exactly as a real shot from you would be.
## ⭐It only STICKS while the NPC holds a hostile target: with no target the no-target branch's _react_unaware
## either forget()s a stale ALERTED outright or winds it down through sense() (npc_distraction.gd:58-89), and
## Perception.can_see() is gated on is_hostile — which npc.gd:2529 rewrites every frame from _treats_as_enemy.
static func _npc_alert(ctx: Dictionary, npc: Node) -> PackedStringArray:
	if not _alive(npc):
		return Common._one("dead")
	var perception: Object = npc.get(&"_perception")
	if perception == null or not is_instance_valid(perception) or not perception.has_method(&"alert_to"):
		return Common._one("no Perception child (bare NPC) — nothing to alert")
	var player := Common._player3d(ctx)
	if player == null or not player.is_inside_tree():
		return Common._one("no player position to alert it to")
	var before := int(Common._float_of(perception.get(&"state"), -1.0))
	perception.call(&"alert_to", player.global_position, player)
	var out := PackedStringArray()
	out.append("Perception %s -> %s, detection pinned 1.0, last_known_position = you" % [_perception_state_text(before), _perception_state_text(int(Common._float_of(perception.get(&"state"), -1.0)))])
	# Read _target as a bare Variant, NOT into an Object-typed local: a typed assignment of a previously freed
	# instance is a script error ("Trying to assign invalid previously freed instance"), and an NPC legitimately
	# holds a freed _target for up to retarget_interval after a foe frees mid-fight (npc.gd _physics_process C8).
	var held: Variant = npc.get(&"_target")
	if held == null or not is_instance_valid(held):
		out.append("! it holds NO target — the no-target tick forget()s or decays this alert; it only sticks on a hostile that has you as _target (aim it with `npc hostile` first)")
	elif held == player:
		out.append("it holds you as _target, so sense() keeps this ALERTED while it can see/hear you (under `notarget` it drops next tick)")
	else:
		out.append("its _target is %s (not you) — the alert points at your spot but sense() tracks that target" % String((held as Node).name))
	return out

## investigate: NPC.investigate(point, alerted=true) -> Perception.investigate_point -> INVESTIGATING + the "!"
## sting; the no-target GOAP tick's Search action walks + sweeps the spot. No-op while DETECTING/ALERTED (a real
## target it can see outranks a hunch — perception.gd:258).
static func _npc_investigate(ctx: Dictionary, pick: Dictionary) -> PackedStringArray:
	var npc: Node = pick[&"npc"]
	if not _alive(npc):
		return Common._one("dead")
	if not npc.has_method(&"investigate"):
		return Common._one("no investigate() on this node")
	var pt := _npc_point(ctx, pick)
	var point: Vector3 = pt[&"point"]
	if not point.is_finite():
		return Common._one("needs a point — %s" % String(pt[&"how"]))
	var perception: Object = npc.get(&"_perception")
	var before := -1
	if perception != null and is_instance_valid(perception):
		before = int(Common._float_of(perception.get(&"state"), -1.0))
	npc.call(&"investigate", point, true)
	var after := before
	if perception != null and is_instance_valid(perception):
		after = int(Common._float_of(perception.get(&"state"), -1.0))
	var out := PackedStringArray()
	out.append("investigate %s — point = %s" % [Common._vec3_text(point), String(pt[&"how"])])
	if before == PerceptionScript.State.DETECTING or before == PerceptionScript.State.ALERTED:
		out.append("! no-op: it is %s — a target it can see outranks a hunch (Perception.investigate_point returns early)" % _perception_state_text(before))
	else:
		out.append("Perception %s -> %s; _scripted_investigating set so the no-target tick winds it down over forget_time instead of snapping to idle" % [_perception_state_text(before), _perception_state_text(after)])
		out.append("the GOAP Search action walks + sweeps it off last_known_position — `brain` shows Investigate winning")
	return out

## walkto: set_cutscene_control(true) + walk_to(point) — the ONLY movement input GOAP does not overwrite (the
## AI zeroes _desired_velocity every think). ⭐_tick_cutscene_movement clears the WALK on arrival but LEAVES CONTROL
## LATCHED (npc.gd:2967-2973), so the NPC stands frozen at the spot with perception/GOAP suppressed until `npc
## release` — and the cast-wide `freezeai` latch does not know about this one body.
static func _npc_walkto(ctx: Dictionary, pick: Dictionary) -> PackedStringArray:
	var npc: Node = pick[&"npc"]
	if not _alive(npc):
		return Common._one("dead")
	if not npc.has_method(&"set_cutscene_control") or not npc.has_method(&"walk_to"):
		return Common._one("no set_cutscene_control()/walk_to() on this node")
	var pt := _npc_point(ctx, pick)
	var point: Vector3 = pt[&"point"]
	if not point.is_finite():
		return Common._one("needs a point — %s" % String(pt[&"how"]))
	npc.call(&"set_cutscene_control", true)
	npc.call(&"walk_to", point)
	var body := npc as Node3D
	var dist := body.global_position.distance_to(point) if body != null else 0.0
	var out := PackedStringArray()
	out.append("walking to %s (%.1f m) — point = %s" % [Common._vec3_text(point), dist, String(pt[&"how"])])
	out.append("! cutscene control LATCHED on this NPC: perception, targeting and GOAP are suspended; arrival clears the walk but NOT the latch — `npc release` hands it back")
	out.append("navmesh move (_move_toward): a point off the mesh reads as arrived immediately; `send_home`/`npc home` refuses while controlled")
	return out

## release / freeze / unfreeze: set_cutscene_control per NPC. Releasing clears the scripted walk/face and the desired
## velocity so the AI resumes from a standstill (npc.gd:2947-2952). Per-body: the `freezeai` STATE_FREEZE_AI latch
## is cast-wide bookkeeping and is neither read nor written here.
static func _npc_control(npc: Node, on: bool, verb: String) -> PackedStringArray:
	if not npc.has_method(&"set_cutscene_control"):
		return Common._one("no set_cutscene_control() on this node")
	var was: Variant = npc.get(&"_cutscene_control")
	var before := was is bool and bool(was)
	npc.call(&"set_cutscene_control", on)
	var out := PackedStringArray()
	if on:
		out.append("%s: cutscene control ON%s — perception, targeting, GOAP and locomotion suppressed; only gravity + scripted movement run" % [verb, " (it already was)" if before else ""])
		out.append("undo with `npc release` / `npc unfreeze`; the cast-wide `freezeai` latch does not track this body")
	else:
		out.append("%s: cutscene control OFF%s — scripted walk/face cleared, desired velocity zeroed; the AI resumes from a standstill" % [verb, "" if before else " (it was not under control)"])
	return out

## home: NPC.send_home(force=true) -> NpcHomeReturn.return_home(ignore_view) — blink (if blink_home) or stand down
## and let the Idle floor walk it back. Returns false when exempt: dead, under cutscene control, following, a
## bodyguard, mid-talk approach, or the component disabled/missing.
static func _npc_home(npc: Node) -> PackedStringArray:
	if not npc.has_method(&"send_home"):
		return Common._one("no send_home() on this node")
	var sent := bool(npc.call(&"send_home", true))
	var out := PackedStringArray()
	if sent:
		var home: Object = npc.get(&"_home_return")
		var blink := home != null and is_instance_valid(home) and Common._bool_of(home.get(&"blink_home"))
		out.append("sent home (force = true, the on-screen guard skipped): %s" % ("BLINKED to its post (nav agent re-seeded, steering reset)" if blink else "stood down — the GOAP Idle floor walks it back to _spawn_position"))
		return out
	out.append("REFUSED — return_home only acts on an eligible NPC:")
	var cutscene: Variant = npc.get(&"_cutscene_control")
	if cutscene is bool and bool(cutscene):
		out.append("  it is under cutscene control (`npc walkto|freeze` / freezeai) — `npc release` first")
	if not _alive(npc):
		out.append("  it is dead")
	if npc.has_method(&"is_following") and bool(npc.call(&"is_following")):
		out.append("  it is a recruited companion (its home is you)")
	var vip: Variant = npc.get(&"_guarding")
	if vip != null and is_instance_valid(vip):
		out.append("  it is bodyguarding someone")
	# The two remaining _eligible() gates (npc_home_return.gd): a Talkable walk-up in progress, and an open
	# conversation anywhere (DialogueManager.is_engaged() — the tree is normally paused then, but the console runs
	# ALWAYS, so this IS reachable from here).
	var talk: Variant = npc.get(&"_talk")
	# is_instance_valid FIRST: `is` on a freed instance is a hard error, and _talk is a cached child handle.
	if talk != null and is_instance_valid(talk) and talk.has_method(&"is_approaching") and bool(talk.call(&"is_approaching")):
		out.append("  it is mid walk-up to a conversation (Talkable approach) — let it arrive or leave the talk range")
	if DialogueManager.is_engaged():
		out.append("  a dialogue is open (DialogueManager.is_engaged) — the leash never moves anyone mid-conversation")
	var home2: Object = npc.get(&"_home_return")
	if home2 == null or not is_instance_valid(home2):
		out.append("  no NpcHomeReturn child on this NPC")
	elif not Common._bool_of(home2.get(&"enabled")):
		out.append("  its NpcHomeReturn is disabled")
	if out.size() == 1:
		out.append("  (no gate visible from here — off-tree host, or a refusal inside return_home itself)")
	return out

## panic: break_and_flee — flip threat_response to FLEE + the "forget this!" bark. ⭐ONE-WAY within a life
## (npc.gd:1867-1870): nothing sets FIGHT back except NpcPool reuse restoring _pre_panic_threat_response, or a
## level reload. Say so, every time.
static func _npc_panic(npc: Node) -> PackedStringArray:
	if not _alive(npc):
		return Common._one("dead")
	if not npc.has_method(&"break_and_flee"):
		return Common._one("no break_and_flee() on this node")
	if npc.has_method(&"is_fleeing") and bool(npc.call(&"is_fleeing")):
		return Common._one("already fleeing (threat_response FLEE) — break_and_flee is re-entrant-safe and changed nothing")
	npc.call(&"break_and_flee")
	var out := PackedStringArray()
	out.append("threat_response FIGHT -> FLEE, flee bark played — the Survive goal now wins while it notices a threat (`brain` shows it)")
	out.append("! ONE-WAY for this life: nothing sets FIGHT back except pool reuse or a level reload")
	return out

## sight [r]: with no value, READ both knobs; with one, WRITE BOTH — the copied-once trap: NpcTargeting acquires by
## host.sight_range (npc_targeting.gd:31, with the ×retain hysteresis) while Perception.can_see uses ITS OWN
## sight_range copied at build (npc.gd:1977). Writing one alone moves the pick radius or the cone, never both.
static func _npc_sight(npc: Node, value: float) -> PackedStringArray:
	var perception: Object = npc.get(&"_perception")
	var has_perception := perception != null and is_instance_valid(perception)
	var npc_range := Common._float_of(npc.get(&"sight_range"))
	var per_range := Common._float_of(perception.get(&"sight_range")) if has_perception else NAN
	var out := PackedStringArray()
	if is_nan(value):
		out.append("sight_range: NPC (targeting pick radius) %.1f m   Perception (see cone) %s" % [npc_range, ("%.1f m" % per_range) if has_perception else "- (no Perception child)"])
		if has_perception and not is_equal_approx(npc_range, per_range):
			out.append("! the two knobs DIFFER — a live edit of one never reaches the other; `npc sight <r>` writes both")
		out.append("pass a value to set both: `npc sight 12`")
		return out
	var r := maxf(0.0, value)
	npc.set(&"sight_range", r)
	if has_perception:
		perception.set(&"sight_range", r)
	out.append("sight_range %.1f -> %.1f on the NPC (targeting) %s" % [npc_range, r, ("and %.1f -> %.1f on Perception (cone)" % [per_range, r]) if has_perception else "(no Perception child to mirror it onto)"])
	out.append("acquire radius = r; an already-held target is retained to the hysteresis multiple of r; the FOV cone and LOS are unchanged")
	out.append("live-only: the profile is not re-applied at runtime, so this holds until pool reuse or a reload")
	return out

## rebrain: rebuild the GOAP library from the NPC's CURRENT goap_profile + re-stamp the copied-once Perception
## fields. Both are DEAD KNOBS at runtime otherwise: priorities/costs are copied into GoapGoal/GoapAction at build
## (goap_library.gd build_goals/build_actions) and the Perception copies happen once in _build_perception — so a
## remote-inspector edit of goap_profile / sight_range / fov does nothing until this runs. setup() mid-plan MUST be
## followed by reset_for_reuse(): the old plan would keep stepping stale action objects from the previous library.
static func _npc_rebrain(npc: Node) -> PackedStringArray:
	var out := PackedStringArray()
	var executor: Object = npc.get(&"_executor")
	if executor == null or not is_instance_valid(executor) or not executor.has_method(&"setup"):
		out.append("no _executor (or no setup()) on this NPC — the GOAP library was not rebuilt")
	elif not npc.has_method(&"_build_goap_actions") or not npc.has_method(&"_build_goap_goals"):
		out.append("NPC has no _build_goap_actions/_build_goap_goals — API drift; the GOAP library was not rebuilt")
	else:
		var actions: Variant = npc.call(&"_build_goap_actions")
		var goals: Variant = npc.call(&"_build_goap_goals")
		executor.call(&"setup", actions, goals)
		if executor.has_method(&"reset_for_reuse"):
			executor.call(&"reset_for_reuse")  # drop the old plan: its action objects belong to the previous library
		var goal_bits := PackedStringArray()
		if goals is Array:
			var goal_list: Array = goals
			for g in goal_list:
				if g != null and is_instance_valid(g):
					goal_bits.append("%s %.2f" % [_name_of(g), Common._float_of(g.get(&"base_priority"))])
		var action_bits := PackedStringArray()
		if actions is Array:
			var action_list: Array = actions
			for a in action_list:
				if a != null and is_instance_valid(a):
					action_bits.append("%s %.1f" % [_name_of(a), Common._float_of(a.get(&"base_cost"))])
		out.append("GOAP library rebuilt from goap_profile — goals (base prio): %s" % (", ".join(goal_bits) if not goal_bits.is_empty() else "none"))
		out.append("  actions (base cost): %s" % (", ".join(action_bits) if not action_bits.is_empty() else "none"))
		out.append("  plan dropped (reset_for_reuse) — the next think tick replans from fresh facts")
	var perception: Object = npc.get(&"_perception")
	if perception == null or not is_instance_valid(perception):
		out.append("no Perception child — nothing to re-stamp")
	else:
		var stamped := PackedStringArray()
		for field: StringName in Common.PERCEPTION_COPIED_ONCE:
			var v: Variant = npc.get(field)
			if v == null:
				continue
			perception.set(field, v)
			stamped.append(String(field))
		out.append("Perception re-stamped from the NPC's live exports: %s" % ", ".join(stamped))
	return out

## is_alive() gate — take_damage early-returns on the dead latch and hp can be <= 0 while the body is still grouped.
static func _alive(n: Node) -> bool:
	return n != null and is_instance_valid(n) and n.has_method(&"is_alive") and bool(n.call(&"is_alive"))

static func _retarget_interval() -> float:
	var npc_ai: Object = GameSettings.get(&"npc_ai")
	if npc_ai == null or not is_instance_valid(npc_ai):
		return 0.5
	return Common._float_of(npc_ai.get(&"retarget_interval"), 0.5)

## GoapGoal.priority(ws) through a Variant handle; -INF for anything that is not a goal so it sorts last.
static func _goal_priority(g: Variant, ws: Variant) -> float:
	if g == null or not is_instance_valid(g) or not g.has_method(&"priority"):
		return -INF
	return float(g.call(&"priority", ws))

static func _plan_text(plan: Array) -> String:
	var names := PackedStringArray()
	for a in plan:
		names.append(_name_of(a) if a != null and is_instance_valid(a) else "?")
	return " -> ".join(names)

static func _plan_cost(plan: Array, ws: Variant) -> float:
	var total := 0.0
	for a in plan:
		if a != null and is_instance_valid(a) and a.has_method(&"cost"):
			total += float(a.call(&"cost", ws))
	return total

## Why plan() came back empty for an UNSATISFIED goal: for each desired fact, the actions whose effects would set
## it and the preconditions of theirs that do not hold in the facts. Today every goal is single-step (one action
## sets its sentinel), so this names the exact fact that gates the behaviour.
static func _why_no_plan(goal: Object, actions: Array, ws: Variant) -> String:
	var desired_v: Variant = goal.get(&"desired_state")
	var facts_v: Variant = ws.get(&"facts")
	var desired: Dictionary = desired_v if desired_v is Dictionary else {}
	var facts: Dictionary = facts_v if facts_v is Dictionary else {}
	var bits := PackedStringArray()
	for k in desired:
		var producers := 0
		for a in actions:
			if a == null or not is_instance_valid(a):
				continue
			var eff_v: Variant = a.get(&"effects")
			var eff: Dictionary = eff_v if eff_v is Dictionary else {}
			if not eff.has(k) or eff[k] != desired[k]:
				continue
			producers += 1
			var pre_v: Variant = a.get(&"preconditions")
			var pre: Dictionary = pre_v if pre_v is Dictionary else {}
			var missing := PackedStringArray()
			for pk in pre:
				if facts.get(pk) != pre[pk]:
					missing.append("%s=%s (is %s)" % [String(pk), str(pre[pk]), str(facts.get(pk, "unset"))])
			if not missing.is_empty():
				bits.append("%s needs %s" % [_name_of(a), ", ".join(missing)])
		if producers == 0:
			bits.append("no action produces %s=%s" % [String(k), str(desired[k])])
	return "; ".join(bits) if not bits.is_empty() else "unreachable within the iteration cap"

## `name` off a GoapGoal / GoapAction handle (StringName), "?" when absent.
static func _name_of(o: Variant) -> String:
	if o == null or not is_instance_valid(o):
		return "?"
	var n: Variant = o.get(&"name")
	return String(n) if n != null else "?"

## Perception.State -> its enum word via the enum's own find_key ("?" for -1 / unknown) — the same two lines as
## AiEventLog.state_name; an enum reached through a preloaded script const is a Dictionary at runtime.
static func _perception_state_text(state: int) -> String:
	var key: Variant = PerceptionScript.State.find_key(state)
	return String(key) if key != null else "?"

static func _disposition_text(kind: int) -> String:
	if kind == DispositionScript.Kind.HOSTILE:
		return "HOSTILE"
	if kind == DispositionScript.Kind.NEUTRAL:
		return "NEUTRAL"
	if kind == DispositionScript.Kind.FRIENDLY:
		return "FRIENDLY"
	return "?"

## True when `script` or ANY script it extends declares a constant named `const_name`. get_script_constant_map() is
## per-script (a subclass's map does not include its base's consts), so a guard declared on npc.gd must be looked
## for up the get_base_script() chain. Null-safe: no script -> false.
static func _script_chain_has_const(script: GDScript, const_name: String) -> bool:
	var s := script
	var depth := 0
	while s != null and depth < 16:  # a script chain is a handful deep; the cap only guards a malformed cycle
		if s.get_script_constant_map().has(const_name):
			return true
		s = s.get_base_script() as GDScript
		depth += 1
	return false
