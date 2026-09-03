@tool
extends RefCounted

## Pure model for the Encounter preview tab: summarize what an EncounterSpawner WOULD spawn, reading the SAME
## authored fields runtime uses (spawn_definitions / spawn_points / attach_scenes), so the preview can't drift from
## the real spawn. PREVIEW ONLY — it spawns nothing and writes nothing. Counts shown are AUTHORED; runtime multiplies
## each by difficulty (scaled_count below mirrors EncounterSpawner._scaled_count), so the tab labels them estimates.

## Mirror of EncounterSpawner._scaled_count(base): base<=0 -> 0; else at least 1, rounded. Pure + tested so the
## preview's difficulty estimate stays in lockstep with the runtime formula.
static func scaled_count(base: int, mult: float) -> int:
	if base <= 0:
		return 0
	return maxi(1, roundi(float(base) * mult))


## Total NPCs runtime would spawn at difficulty `mult`: the sum of per-definition scaled_count over SPAWNABLE rows
## (runtime rounds each definition independently and skips npc_scene-less ones). Equals the authored total at mult
## 1.0. Pass DifficultySettings.easy/hard_enemy_count_mult to estimate the Easy/Hard ends. Pure + tested.
static func scaled_total(rows: Array, mult: float) -> int:
	var t := 0
	for r in rows:
		if bool(r.get("spawns", false)):
			t += scaled_count(int(r["count"]), mult)
	return t


## Summarize a duck-typed EncounterSpawner into {rows, total, marker_count, attach_count, placement}. Each row:
## {index, npc, count, radius, delay, archetype, faction, weapon, aggro}. Reads authored exports only — no spawning,
## no difficulty (that's the caller's estimate). Null/empty definitions surface as a row, not a crash.
static func summarize(spawner) -> Dictionary:
	var rows: Array = []
	var total := 0
	var defs: Variant = spawner.get(&"spawn_definitions") if spawner != null else null
	if defs is Array:
		var i := 0
		for d in defs:
			var def := d as SpawnDefinition
			if def == null:
				rows.append({"index": i, "npc": "(empty definition)", "count": 0, "spawns": false, "radius": 0.0, "delay": 0.0, "archetype": "", "faction": "", "weapon": "", "aggro": false})
			else:
				var spawns := def.npc_scene != null  # mirror EncounterSpawner.trigger_spawn_wave: a null npc_scene spawns NOTHING
				if spawns:
					total += def.count
				rows.append({
					"index": i,
					"npc": _scene_name(def.npc_scene),
					"count": def.count,
					"spawns": spawns,
					"radius": def.spawn_radius,
					"delay": def.spawn_delay,
					"archetype": _res_name(def.profile),
					"faction": _res_name(def.faction_override),
					"weapon": _res_name(def.weapon_override),
					"aggro": def.auto_aggro,
				})
			i += 1
	var markers: Variant = spawner.get(&"spawn_points") if spawner != null else null
	var attach: Variant = spawner.get(&"attach_scenes") if spawner != null else null
	var marker_count: int = (markers as Array).size() if markers is Array else 0
	var attach_count: int = (attach as Array).size() if attach is Array else 0
	var placement := "markers (%d, cycled in order)" % marker_count if marker_count > 0 else "random scatter (per-definition radius)"
	return {"rows": rows, "total": total, "marker_count": marker_count, "attach_count": attach_count, "placement": placement}


## A PackedScene's file basename (e.g. "NPC.tscn"), or a bracketed placeholder — the resource_path may be empty for a
## scene built in memory. The placeholders are DESIGNER words (no field names, no engine spelling): encounter_view
## renders them straight into a row, and "(no NPC scene set)" is what that row has to read.
static func _scene_name(scene: PackedScene) -> String:
	if scene == null:
		return "(no NPC scene set)"
	var p := scene.resource_path
	return p.get_file() if not p.is_empty() else "(unsaved scene)"


## A Resource's file basename, or "" when unset — used for the profile / faction / weapon override columns.
static func _res_name(res: Resource) -> String:
	if res == null:
		return ""
	var p := res.resource_path
	return p.get_file() if not p.is_empty() else "(unsaved)"
