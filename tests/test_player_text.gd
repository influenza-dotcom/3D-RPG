extends GutTest

## The PlayerText / localization RATCHET, now at its floor: EVERY raw string literal at a player-facing paint
## site (ScanText.PATTERNS: label/placeholder/tooltip assignment, the toast calls, the MenuStyle text
## factories, dialogue extra-choices, start-menu buttons) has been moved into PlayerText, so the guard is no
## longer "the debt may only shrink" but "there is no debt" — BASELINE is empty and BASELINE_HIGH_WATER is 0.
## The tr() sweep proper is still deferred; what this guarantees is that when it happens, PlayerText is the
## ONLY file it has to touch. Reuses the audit panel's own scanner
## (addons/cybersunday_tools/panel_audit/scan_text.gd, which reuses ScanDisk.mask_comments), so this guard
## and the CYBER SUNDAY Audit tab can never disagree — including its SKIP_FILES dev-surface exemptions.

const ScanText := preload("res://addons/cybersunday_tools/panel_audit/scan_text.gd")
const Factions := preload("res://scripts/faction/factions.gd")  ## for the requires_standing authored-name pin

## Scope: the production roots (mirrors tests/test_groups.gd) PLUS every top-level res://*.gd file —
## computerroom.gd is the main scene's script and sits OUTSIDE the roots (a verified blind spot the group
## guard has). addons/ (editor tooling), tests/ + tests_soak/ (synthetic fixtures), and .claude/ are out of
## scope by never being walked; scripts/tools/ (File→Run editor tools whose strings print to the Output
## panel, never the HUD) is excluded explicitly since it lives under a walked root.
const PRODUCTION_ROOTS := ["res://scripts", "res://managers", "res://scenes", "res://resources"]
const EXCLUDED_DIRS := ["res://scripts/tools"]

## BASELINE: res:// path -> the EXACT number of paint-site literals that file currently carries. Shape
## choice: per-file COUNTS, not "file:line" pins — unrelated edits shift line numbers constantly, while a
## count only moves when a literal is added (forbidden) or moved into PlayerText (then ratchet the entry
## down; at 0, prune it). NEVER add a file or raise a count — put the new string in PlayerText instead.
##
## **The debt is PAID: this table is EMPTY and must stay that way.** 2026-07-27 moved the last 53 literals
## into PlayerText and resolved the 3 non-prose stragglers at their roots (the chess move-log's "\n" line
## SEPARATOR composes into a local; the bark bubble's tail glyph became the `bubble_tail_glyph` @export —
## art, not copy; the F3 developer HUD joined ScanText.SKIP_FILES, the dev-surface twin of the existing
## scripts/tools skip). An entry reappearing here is not "the baseline moved" — it is a new hardcoded string
## that belongs in PlayerText. Re-measure any time with `godot --headless -s scripts/tools/text_debt.gd`,
## which prints this table's exact shape.
const BASELINE := {}

## The ratchet's second tooth: the TOTAL offender count across the whole scope. Only ever edit this
## DOWNWARD (when literals move into PlayerText) — never up. It backstops the per-file table: a new literal
## must fail the suite even if someone (wrongly) grows a BASELINE entry to admit it. At ZERO since
## 2026-07-27 — the floor. There is no legitimate edit to this const any more.
const BASELINE_HIGH_WATER := 0


## (1)+(2)+(3): the ratchet proper — per-file growth check, stale-entry (shrink) signal, and the global
## high-water mark, all over ONE walk with the audit's own scanner.
func test_no_new_hardcoded_player_strings() -> void:
	var unreadable: Array = []
	var offenders := _collect_offenders(unreadable)
	assert_eq(unreadable, [], "every scoped .gd should be readable (a truly empty .gd would need this loosened): %s" % [unreadable])
	var by_file := {}
	for o: Dictionary in offenders:
		var src := String(o["source"])
		if not by_file.has(src):
			by_file[src] = []
		(by_file[src] as Array).append("line %d (%s): %s" % [int(o["line"]), String(o["pattern"]), String(o["excerpt"])])
	# (1) no file may exceed its baseline allowance (a file absent from BASELINE has allowance 0).
	for src: String in by_file:
		var found: int = (by_file[src] as Array).size()
		var allowed := int(BASELINE.get(src, 0))
		assert_lte(found, allowed,
			"%s has %d hardcoded player-facing literal(s) but the baseline allows %d — put the new string in PlayerText (scripts/ui/player_text.gd); the baseline never grows:\n  %s"
			% [src, found, allowed, "\n  ".join(PackedStringArray(by_file[src]))])
	# (2) no stale BASELINE entry: fewer offenders than allowed means debt was paid — ratchet the entry down
	# so the improvement can't silently regress. (On growth this fails too; the loop-1 failure above names
	# the offending lines.)
	for src: String in BASELINE:
		var found: int = (by_file.get(src, []) as Array).size()
		assert_eq(found, int(BASELINE[src]),
			"BASELINE says %d literal(s) in %s but the scanner found %d — if fewer, shrink (or prune) the entry to lock in the paid-down debt; if more, move the new string into PlayerText." % [int(BASELINE[src]), src, found])
	# (3) the global high-water mark — a const only ever edited DOWNWARD.
	assert_lte(offenders.size(), BASELINE_HIGH_WATER,
		"total hardcoded player-facing literals (%d) exceeds BASELINE_HIGH_WATER (%d) — move strings into PlayerText; this const only moves down." % [offenders.size(), BASELINE_HIGH_WATER])


## (4)+(5): the PlayerText contract, plus the property the whole deferred-sweep strategy licenses: with no
## translation catalog loaded, tr() is IDENTITY on the fallback locale — so wrapping every PlayerText read in
## tr() later is a pure no-op until real catalogs land, which is why the sweep can stay deferred. Also pins:
## every const non-empty (an empty const paints an invisible blank); every [PH]-marked const carries the
## marker as exactly "[PH] " (the Steam AI-text scrub greps/strips on that exact prefix — see
## PlayerText.strip_prefix); and no const contains ".gd" — dev diagnostics parked in player copy. The old
## PlayerText.no_game_root() helper embedded "attach game_root.gd" into a HUD toast; the just-landed hygiene
## slice removed it (rg finds no no_game_root anywhere — TOAST_DOOR_STUCK + a push_error at the LevelDoor
## call site is the current shape), and this pin keeps that class of leak from returning.
func test_player_text_contract() -> void:
	var script: GDScript = load("res://scripts/ui/player_text.gd")
	assert_not_null(script, "player_text.gd should load")
	var consts: Dictionary = script.get_script_constant_map()
	assert_gt(consts.size(), 0, "PlayerText reflected at least one const")
	var empties: Array = []
	var bad_ph: Array = []
	var gd_leaks: Array = []
	for cname: String in consts:
		var v: Variant = consts[cname]
		if not (v is String):
			continue
		var s := String(v)
		if s.is_empty():
			empties.append(cname)
		if s.contains(".gd"):
			gd_leaks.append(cname)
		if cname == "PH_PREFIX" or cname == "PH_PREFIX_SPACE":
			continue  # the marker DEFINITIONS themselves, not player copy — "[PH]" alone is their whole point
		if s.begins_with(PlayerText.PH_PREFIX) and not s.begins_with(PlayerText.PH_PREFIX_SPACE):
			bad_ph.append(cname)
	assert_eq(empties, [], "every PlayerText const must be non-empty — an empty const paints an invisible blank: %s" % [empties])
	assert_eq(bad_ph, [], "every [PH]-marked PlayerText const must start with exactly \"[PH] \" (marker + one space) so the scrub can strip it: %s" % [bad_ph])
	assert_eq(gd_leaks, [], "no PlayerText const may contain \".gd\" — that's a dev diagnostic leaking into player copy (the removed no_game_root class of bug): %s" % [gd_leaks])
	assert_eq(tr(PlayerText.BACK), PlayerText.BACK,
		"tr() must be identity with no translation catalog loaded — the fallback-locale property that lets the tr() sweep stay deferred")


## (6): the TextFormat-rule refactor of PlayerText's bodies — whole-template SELECTION (bool/enum/key)
## and TextFormat.plural whole singular/plural variants, replacing spliced fragments ("gained"/"lost",
## "you win", "(s)", the "   ENCUMBERED" append, HealScreen's limb/note lines). These pin the RENDERED
## output: identical to the pre-refactor strings everywhere except the sanctioned wording changes —
## "item(s)" became real singular/plural pairs, and the heal card's can't-afford note dropped its
## interior "[PH] " marker (the whole template is [PH]-marked once, up front).
func test_whole_template_selection_and_plurals() -> void:
	# Plural pairs (TextFormat.plural picks a WHOLE template, never appends an "s").
	assert_eq(PlayerText.level_up(3, 1), "Level 3! +1 skill point", "singular level-up toast")
	assert_eq(PlayerText.level_up(3, 2), "Level 3! +2 skill points", "plural level-up toast")
	assert_eq(PlayerText.respec_refunded(1), "[PH] Respec: 1 perk refunded", "singular respec toast")
	assert_eq(PlayerText.respec_refunded(2), "[PH] Respec: 2 perks refunded", "plural respec toast")
	assert_eq(PlayerText.respec_blurb(1), "[PH] Refund 1 perk — skill points return to re-spend at a Level Up.",
		"singular respec blurb")
	assert_eq(PlayerText.respec_blurb(4), "[PH] Refund 4 perks — skill points return to re-spend at a Level Up.",
		"plural respec blurb")
	assert_eq(PlayerText.perks_header(1), "[PH] Perks — 1 point", "singular perks header")
	assert_eq(PlayerText.perks_header(3), "[PH] Perks — 3 points", "plural perks header")
	assert_eq(PlayerText.quest_rewards_full(1), "[PH] Inventory full — 1 quest reward item couldn't fit",
		"the old 'item(s)' is now a real singular")
	assert_eq(PlayerText.quest_rewards_full(3), "[PH] Inventory full — 3 quest reward items couldn't fit",
		"…and a real plural")
	assert_eq(PlayerText.inventory_full(1), "[PH] Inventory full — 1 item couldn't fit",
		"the neutral (non-quest) overflow line, singular — the dialogue-gift path uses this")
	assert_eq(PlayerText.inventory_full(2), "[PH] Inventory full — 2 items couldn't fit",
		"the neutral overflow line, plural")
	# Whole-template selection replacing fragment arguments.
	assert_eq(PlayerText.reputation_changed("Raiders", true), "[PH] Raiders reputation gained!",
		"reputation gain selects its own whole template")
	assert_eq(PlayerText.reputation_changed("Raiders", false), "[PH] Raiders reputation lost!",
		"reputation loss selects its own whole template")
	assert_eq(PlayerText.alignment_changed("Raiders", PlayerText.ALIGNMENT_HOSTILE_WORD),
		"[PH] Raiders is now Hostile!", "alignment templates are selected by the kind KEY")
	assert_eq(PlayerText.alignment_changed("Raiders", PlayerText.ALIGNMENT_FRIENDLY_WORD),
		"[PH] Raiders is now Friendly!", "…friendly variant")
	assert_eq(PlayerText.alignment_changed("Raiders", "???"),
		"[PH] Raiders is now Neutral!", "an unknown kind key fails safe to the Neutral template")
	assert_eq(PlayerText.chess_checkmate(true), "[PH] Checkmate — you win.", "win selects its whole template")
	assert_eq(PlayerText.chess_checkmate(false), "[PH] Checkmate — you lose.", "loss selects its whole template")
	assert_eq(PlayerText.radio_on("Jukebox"), "[PH] Jukebox on", "radio-on whole template (was radio_state + a state-word fragment)")
	assert_eq(PlayerText.radio_off("Jukebox"), "[PH] Jukebox off", "radio-off whole template")
	assert_eq(PlayerText.inventory_weight(12.0, 30.0, false), "[PH] Weight  12.0 / 30.0",
		"weight line keeps its fixed one-decimal readout")
	assert_eq(PlayerText.inventory_weight(31.5, 30.0, true), "[PH] Weight  31.5 / 30.0   ENCUMBERED",
		"the encumbered warning is its own whole template, not an append")
	# The heal card's four-way status block (HealScreen passes FACTS; the lines live here).
	assert_eq(PlayerText.heal_status(50, 100, false, 12.5, false),
		"[PH] HP  50 / 100\nYour zorkmids: 12.5", "base heal status")
	assert_eq(PlayerText.heal_status(50, 100, true, 12.5, false),
		"[PH] HP  50 / 100\n— limb damage\nYour zorkmids: 12.5", "limb-damage variant carries its own line")
	assert_eq(PlayerText.heal_status(50, 100, false, 12.5, true),
		"[PH] HP  50 / 100\nYour zorkmids: 12.5\n— can't afford", "can't-afford variant carries its own note line")
	assert_eq(PlayerText.heal_status(50, 100, true, 12.5, true),
		"[PH] HP  50 / 100\n— limb damage\nYour zorkmids: 12.5\n— can't afford", "both-facts variant")
	# Money phrases route through the single Zorkmids.money_text template (the currency word lives there).
	assert_eq(PlayerText.heal_button(40), "[PH] Heal  —  40 zm", "heal button substitutes the whole money phrase")
	assert_eq(PlayerText.respec_button(100.0), "Respec  —  100 zm", "respec button substitutes the whole money phrase")
	assert_eq(PlayerText.wallet_you(12.5), "[PH] You: 12.5 zm", "wallet readout substitutes the whole money phrase")


## (7): the requires_* deny toasts take RAW IDS and resolve authored display names internally (StatInfo.title /
## Perks.display_label / Factions.by_id) — BuildGate passes ids, so an authored rename reaches the toast with no
## caller change and authored casing is never re-capitalize()d. Fallback shapes (unknown ids) are pinned as
## literal bytes; authored names are asserted against the resources (the wording belongs to the designer).
## Plus the shop's (equipped) marker, now a whole template wrapping the composed row as a value token.
func test_requires_toasts_resolve_authored_names_by_id() -> void:
	# Stat: the same authored StatText title the stats screen paints; unauthored ids keep the capitalized look.
	assert_eq(PlayerText.requires_stat(&"strength", 5),
		"[PH] Requires %s 5" % StatInfo.title(&"strength"),
		"requires_stat resolves the stat id through StatInfo.title (one stat name game-wide)")
	assert_eq(PlayerText.requires_stat(&"charisma", 3), "[PH] Requires Charisma 3",
		"an unauthored stat id degrades to the capitalized id inside StatInfo.title")
	# Perk: the authored Perk.display_name, [PH]-stripped (the template prepends its own marker — never doubled).
	var perk := load("res://resources/perks/tough_hide.tres") as Perk
	assert_not_null(perk, "the shipped tough_hide perk exists for the label lookup")
	if perk != null:
		var toast := PlayerText.requires_perk(&"tough_hide")
		assert_eq(toast, "[PH] Requires the %s perk" % PlayerText.strip_prefix(perk.display_name),
			"requires_perk resolves the authored ([PH]-stripped) display_name from the raw id")
		assert_eq(toast.count(PlayerText.PH_PREFIX), 1,
			"an interim '[PH] ' on the authored perk name must not double the marker mid-sentence")
	assert_eq(PlayerText.requires_perk(&"ghost_perk_xyz"), "[PH] Requires the Ghost Perk Xyz perk",
		"a perk id with no .tres keeps the pre-authoring capitalized-id toast")
	# Standing: neutral_wildlife authors "Wildlife" — NOT the capitalized id "Neutral Wildlife" — so this
	# genuinely distinguishes authored-name routing from the old capitalize-the-id path.
	var fac := Factions.by_id("neutral_wildlife")
	assert_not_null(fac, "the shipped neutral_wildlife faction exists for the label lookup")
	if fac != null:
		assert_eq(PlayerText.requires_standing("neutral_wildlife"),
			"[PH] Requires standing with %s" % fac.display_name,
			"requires_standing resolves the authored Faction.display_name from the raw id")
	assert_eq(PlayerText.requires_standing("no_such_faction_xyz"),
		"[PH] Requires standing with No Such Faction Xyz",
		"an unresolvable faction id keeps the pre-authoring capitalized-id toast (by_id warns, degrade never blanks)")
	assert_eq(PlayerText.equipped_row("Pistol  x1"), "Pistol  x1   (equipped)",
		"equipped_row wraps the composed row in the whole EQUIPPED_ROW template (the old suffix append is gone)")


## (8): the shared-registry composers that pulled the last screen-composed strings off their paint sites —
## the Stats summary line, the Level-Up perk rows, the Journal objective rows, the dialogue continue hint —
## plus the Options dropdown captions. Pinned as literal BYTES: the Stats separators are three-space middle
## dots, and the journal_objective strings must stay identical to tests/test_quest_journal.gd's
## objective_line pins (QuestJournal migrates onto this composer with zero rendered change).
func test_screen_composer_registry() -> void:
	# Stats summary: the '   ·   ' (three spaces each side of U+00B7) separators are the readout's look.
	assert_eq(PlayerText.stats_summary(3, 12.5, 0), "Level 3   ·   12.5 zorkmids",
		"summary without spare points — level + wallet only")
	assert_eq(PlayerText.stats_summary(3, 12.5, 1), "Level 3   ·   12.5 zorkmids   ·   1 perk point to spend",
		"singular perk-point tail selects its whole template")
	assert_eq(PlayerText.stats_summary(10, 1500.0, 3), "Level 10   ·   1500 zorkmids   ·   3 perk points to spend",
		"plural perk-point tail")
	# Level-Up screen rows.
	assert_eq(PlayerText.perk_owned_row("Tough Hide"), "Tough Hide   (owned)",
		"owned-perk marker wraps the label as a whole template (three-space idiom, like EQUIPPED_ROW)")
	assert_eq(PlayerText.level_up_cost_cell(100.0), "(100 zm)",
		"cost cell substitutes the whole money phrase from Zorkmids.money_text")
	assert_eq(PlayerText.level_up_cost_cell(9999.5), "(9999.5 zm)",
		"fractional costs keep the trimmed Zorkmids.fmt readout")
	# Journal objective rows — all EIGHT variants; bytes match test_quest_journal's objective_line pins.
	assert_eq(PlayerText.journal_objective("Kill the boss", false, 0, 1, false), "[ ] Kill the boss",
		"open single objective")
	assert_eq(PlayerText.journal_objective("Kill the boss", true, 1, 1, false), "[x] Kill the boss",
		"done -> checked box")
	assert_eq(PlayerText.journal_objective("Collect parts", false, 2, 5, false), "[ ] Collect parts (2/5)",
		"a counted objective shows progress")
	assert_eq(PlayerText.journal_objective("Collect parts", true, 5, 5, false), "[x] Collect parts (5/5)",
		"counted + done")
	assert_eq(PlayerText.journal_objective("Find the cache", false, 0, 1, true), "[ ] Find the cache  (optional)",
		"optional tag lives inside its template")
	assert_eq(PlayerText.journal_objective("Find the cache", true, 1, 1, true), "[x] Find the cache  (optional)",
		"optional + done")
	assert_eq(PlayerText.journal_objective("Collect parts", false, 2, 5, true), "[ ] Collect parts (2/5)  (optional)",
		"counted + optional")
	assert_eq(PlayerText.journal_objective("Collect parts", true, 5, 5, true), "[x] Collect parts (5/5)  (optional)",
		"counted + optional + done — the eighth variant")
	# Dialogue continue hint — the live binding rides in as a value token.
	assert_eq(PlayerText.dialogue_continue_hint("E"), "[E] / click to continue",
		"continue hint wraps the bound key in one whole template")
	# Options dropdown captions — display text whose ARRAY ORDER at the call site is the behaviour contract.
	assert_eq(PlayerText.OPTIONS_CB_NONE, "None", "colourblind mode: none")
	assert_eq(PlayerText.OPTIONS_CB_PROTANOPIA, "Protanopia", "colourblind mode: protanopia")
	assert_eq(PlayerText.OPTIONS_CB_DEUTERANOPIA, "Deuteranopia", "colourblind mode: deuteranopia")
	assert_eq(PlayerText.OPTIONS_CB_TRITANOPIA, "Tritanopia", "colourblind mode: tritanopia")
	assert_eq(PlayerText.OPTIONS_DIFFICULTY_EASY, "Easy", "difficulty: easy")
	assert_eq(PlayerText.OPTIONS_DIFFICULTY_NORMAL, "Normal", "difficulty: normal")
	assert_eq(PlayerText.OPTIONS_DIFFICULTY_HARD, "Hard", "difficulty: hard")
	assert_eq(TextFormat.subst(PlayerText.OPTIONS_RESOLUTION_CUSTOM, {"w": "1920", "h": "1080"}),
		"1920 x 1080 (custom)", "the custom-resolution row renders w x h with the (custom) tag")


# --- the walk (clone of test_groups' recursive collector + the top-level file pass it lacks) ---------------

func _collect_offenders(unreadable: Array) -> Array:
	var offenders: Array = []
	# Top-level res://*.gd FILES only (no recursion — subdirs are either walked roots or out of scope).
	var d := DirAccess.open("res://")
	if d != null:
		d.list_dir_begin()
		var entry := d.get_next()
		while entry != "":
			if not entry.begins_with(".") and not d.current_is_dir() and entry.get_extension() == "gd":
				_scan_file("res://".path_join(entry), offenders, unreadable)
			entry = d.get_next()
		d.list_dir_end()
	for root: String in PRODUCTION_ROOTS:
		_walk(root, offenders, unreadable)
	return offenders


func _walk(dir: String, offenders: Array, unreadable: Array) -> void:
	if EXCLUDED_DIRS.has(dir):
		return
	var d := DirAccess.open(dir)
	if d == null:
		return
	d.list_dir_begin()
	var entry := d.get_next()
	while entry != "":
		if entry.begins_with("."):
			entry = d.get_next()
			continue
		var full: String = dir.path_join(entry)
		if d.current_is_dir():
			_walk(full, offenders, unreadable)
		elif entry.get_extension() == "gd":
			_scan_file(full, offenders, unreadable)
		entry = d.get_next()
	d.list_dir_end()


func _scan_file(path: String, offenders: Array, unreadable: Array) -> void:
	# Honour the scanner's own per-file skips (dev-only surfaces like the F3 debug overlay). This walk calls
	# scan_gd_text directly rather than ScanText.run()'s _scan_dir, so without this the guard and the panel
	# would disagree — the exact drift the "reuse the audit's scanner" design exists to prevent.
	if ScanText.SKIP_FILES.has(path):
		return
	var src := FileAccess.get_file_as_string(path)
	if src.is_empty():
		unreadable.append(path)
		return
	offenders.append_array(ScanText.scan_gd_text(src, path))
