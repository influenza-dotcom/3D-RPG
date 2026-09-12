extends GutTest

## Pins the STAT-TEXT extraction PLUMBING: the stat titles + blurbs used to be a hardcoded const table in
## stat_info.gd (TITLES / BLURB); they now live as authored resources/stats/<id>.tres (StatText), read back by
## StatInfo, so a designer edits them in the CYBER SUNDAY Text tab. This asserts the resources exist, key
## correctly, and that StatInfo reads THROUGH them — it deliberately does NOT pin the description PROSE (content
## or even non-emptiness): the wording belongs to the designer now (they blanked the migrated blurbs on purpose to
## rewrite them in the Text tab), and a test that fails on an authored rewrite would fight the whole point.
##
## Duck-typed on purpose (load() + .get(), no StatText class_name) — mirroring stat_info.gd, which preloads the
## script by path so it never depends on the brand-new class_name being registered in the global cache.

const STATS_DIR := "res://resources/stats/"
const STAT_IDS := [&"strength", &"endurance", &"gunplay", &"agility", &"streetwise", &"larceny"]


func test_every_stat_has_an_authored_text_resource() -> void:
	for id in STAT_IDS:
		var path := STATS_DIR + String(id) + ".tres"
		var res = load(path)
		assert_not_null(res, "each stat has a StatText .tres at %s (the Text tab edits these)" % path)
		if res == null:
			continue
		assert_eq(StringName(str(res.get("id"))), id,
			"%s carries its own id so StatText.by_id / the Text tab key it correctly" % path)
		assert_false(String(res.get("display_name")).is_empty(),
			"%s has a title — an empty one would blank the stat name on the sheet (the blurb MAY be empty: prose is the designer's)" % path)


func test_stat_info_reads_through_the_authored_resources() -> void:
	# title() proves the read-through: the authored display_name ("Strength"), not merely the capitalized-id
	# fallback (which happens to match for one-word ids — so also check blurb() returns the resource's field
	# VERBATIM, empty included, rather than pinning any particular wording).
	assert_eq(StatInfo.title(&"strength"), "Strength",
		"StatInfo.title reads the authored display_name (the stats screen + creation both read through here)")
	for id in STAT_IDS:
		var res = load(STATS_DIR + String(id) + ".tres")
		if res == null:
			continue  # covered (failed) by the existence test above
		assert_eq(StatInfo.blurb(id), String(res.get("description")),
			"StatInfo.blurb(%s) returns resources/stats/%s.tres `description` verbatim — whatever the designer wrote (or blank), never a stale fallback" % [id, id])


func test_stat_info_falls_back_cleanly_for_an_unknown_stat() -> void:
	assert_eq(StatInfo.title(&"charisma"), "Charisma",
		"an unauthored stat id degrades to a bare capitalized title — a missing/renamed .tres can't blank the sheet")
	assert_eq(StatInfo.blurb(&"charisma"), "",
		"…and its blurb is empty, not an error — the tooltip just loses its 'what it does' line")


func test_scan_accepts_the_exported_remap_name() -> void:
	# An exported pck lists packed resources as `<id>.tres.remap`, never the bare `.tres` — the 08-28 build
	# filtered on the raw extension and shipped every stat name/blurb blank. The filter must see through the
	# sidecar and hand `load()` the bare name (which the remap resolves), and still reject non-resources.
	var ST = load("res://scripts/ui/stat_text.gd")
	assert_eq(ST.tres_name("agility.tres"), "agility.tres", "an editor listing's bare .tres is loadable as-is")
	assert_eq(ST.tres_name("agility.tres.remap"), "agility.tres",
		"an exported pck's .tres.remap resolves to the bare .tres that load() remaps")
	assert_eq(ST.tres_name("agility.tres.uid"), "", "a .uid sidecar is not a resource")
	assert_eq(ST.tres_name("notes.txt"), "", "a stray non-resource file is skipped")
	assert_eq(ST.tres_name("agility.remap"), "", "a .remap with no .tres underneath is not a resource")
