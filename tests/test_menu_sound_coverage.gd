extends GutTest

## The MENU-SOUND BLINDSPOT ratchet, shipped at its floor. A "blindspot" here is precise: a function that
## fires a SUCCESS cue from inside a branch and never calls MenuStyle.play_denied() — i.e. the code took a
## decision about the player's action and answered the losing branch with silence. That was the shape of the
## whole gap: ~20 screens gated a commit on a success bool (`if merchant.buy(...): play_commit()`) and said
## nothing on false, because until the `denied` cue existed there was nothing honest to say. A refused
## purchase, a heal you can't afford, a full backpack, a failed SAVE — all indistinguishable from a dead
## button.
##
## BASELINE is EMPTY and BASELINE_HIGH_WATER is 0: every such site was paired when the cue landed, so this is
## not "the debt may only shrink" but "there is no debt". A new offender fails the suite outright.
##
## Reuses the audit panel's own scanner (addons/cybersunday_tools/panel_audit/scan_menu_sound.gd), so this
## guard, the CYBER SUNDAY Audit tab and `godot --headless -s scripts/tools/menu_sound_debt.gd` can never
## disagree — including its SKIP_FILES and EXEMPT_FUNCS entries. Deliberately the tests/test_player_text.gd
## shape, because it is the same KIND of problem: an invisible, non-erroring omission spread across every
## screen, which only a scanner can hold at zero.
##
## WHAT THIS CANNOT SEE (so don't read a pass as "every menu is fully audible"): a screen that never had a
## cue at all is invisible to a rule about cue PAIRS, and so is a non-BaseButton surface that reports nothing.
## Those are covered by construction instead — ModalMenu.grab_mouse/restore_mouse, PlayerMenus.enter/leave,
## MenuStyle's node_added hook, and GridInventoryView's own motion cues. tests/test_menu_sound.gd pins the
## vocabulary those rest on.

const ScanMenuSound := preload("res://addons/cybersunday_tools/panel_audit/scan_menu_sound.gd")

## Scope mirrors tests/test_player_text.gd exactly (production roots + every top-level res://*.gd, minus
## scripts/tools) — the same reasoning applies verbatim, including computerroom.gd being the main scene's
## script and sitting outside the roots.
const PRODUCTION_ROOTS := ["res://scripts", "res://managers", "res://scenes", "res://resources"]
const EXCLUDED_DIRS := ["res://scripts/tools"]

## res:// path -> the EXACT number of unpaired branch-gated success cues that file currently carries.
## Per-file COUNTS, not file:line pins — line numbers churn on unrelated edits; a count only moves when a
## blindspot is added (forbidden) or paired (then ratchet the entry down; at 0, prune it).
##
## **EMPTY, and it must stay that way.** Do not add a file here to admit a new unpaired cue: pair it
## (`if act(): play_commit() else: play_denied()`), or — when the act genuinely cannot be refused — hoist the
## cue to the function's base indent so it reads as unconditional (the TermsOfServiceScreen._on_decline
## early-return shape). When the losing branch is an ABORT rather than a refusal and already cues correctly,
## the judgement goes in ScanMenuSound.EXEMPT_FUNCS with its reason written out, never here as a number.
## Re-measure with `godot --headless -s scripts/tools/menu_sound_debt.gd`, which prints this table's shape.
const BASELINE := {}

## The ratchet's second tooth: the TOTAL across the whole scope, backstopping the per-file table so a new
## blindspot fails even if someone (wrongly) grows a BASELINE entry to admit it. Only ever edited DOWNWARD,
## and it is already at the floor — there is no legitimate edit to this const any more.
const BASELINE_HIGH_WATER := 0


func test_no_new_silent_refusal_paths() -> void:
	var unreadable: Array = []
	var offenders := _collect_offenders(unreadable)
	assert_eq(unreadable, [], "every scoped .gd should be readable: %s" % [unreadable])
	var by_file := {}
	for o: Dictionary in offenders:
		var src := String(o["source"])
		if not by_file.has(src):
			by_file[src] = []
		(by_file[src] as Array).append("line %d (%s in %s)" % [int(o["line"]), String(o["cue"]), String(o["func_name"])])
	# (1) no file may exceed its baseline allowance (a file absent from BASELINE has allowance 0).
	for src: String in by_file:
		var found: int = (by_file[src] as Array).size()
		var allowed := int(BASELINE.get(src, 0))
		assert_lte(found, allowed,
			"%s has %d branch-gated success cue(s) with no MenuStyle.play_denied() in the same function, but the baseline allows %d — the refused press is SILENT. Pair the cue, or hoist it out of the branch if it can never be refused:\n  %s"
			% [src, found, allowed, "\n  ".join(PackedStringArray(by_file[src]))])
	# (2) no stale BASELINE entry: fewer offenders than allowed means a blindspot was paid off — ratchet the
	# entry down so the improvement can't silently regress.
	for src: String in BASELINE:
		var found: int = (by_file.get(src, []) as Array).size()
		assert_eq(found, int(BASELINE[src]),
			"BASELINE says %d blindspot(s) in %s but the scanner found %d — if fewer, shrink (or prune) the entry; if more, pair the new cue." % [int(BASELINE[src]), src, found])
	# (3) the global high-water mark — a const only ever edited DOWNWARD.
	assert_lte(offenders.size(), BASELINE_HIGH_WATER,
		"total silent-refusal paths (%d) exceeds BASELINE_HIGH_WATER (%d) — pair the cue with play_denied(); this const only moves down." % [offenders.size(), BASELINE_HIGH_WATER])


## The scanner's own core, exercised on SYNTHETIC source. Pins the three judgements the ratchet rests on, so
## a future edit to scan_menu_sound.gd can't quietly turn the guard into a no-op that "passes" at zero
## because it stopped detecting anything.
func test_scanner_detects_the_shape_it_claims_to() -> void:
	# (a) THE BUG: commit nested under a success gate, nothing on the false branch.
	var bad := "func _buy() -> void:\n\tif merchant.buy(item):\n\t\tMenuStyle.play_commit()\n"
	var hits := ScanMenuSound.scan_gd_text(bad, "res://synthetic.gd")
	assert_eq(hits.size(), 1, "an unpaired branch-gated commit is the offending shape: %s" % [hits])
	assert_eq(String((hits[0] as Dictionary)["func_name"]), "_buy", "the offender names its enclosing function")

	# (b) THE FIX: the same function with the pair. Must go quiet, or nobody could ever clear a finding.
	var good := "func _buy() -> void:\n\tif merchant.buy(item):\n\t\tMenuStyle.play_commit()\n\telse:\n\t\tMenuStyle.play_denied()\n"
	assert_eq(ScanMenuSound.scan_gd_text(good, "res://synthetic.gd"), [],
		"pairing the cue with play_denied() clears the finding")

	# (c) NOT THE BUG: an UNCONDITIONAL cue at the function's base indent. It already fires on every path, so
	# there is no other branch to cover — this is what exempts a shared success tail (ChipInstaller._grant)
	# and a never-gated act (StartMenu's run stamp) without any exemption list.
	var uncond := "func _grant() -> void:\n\tplayer.unlock()\n\tMenuStyle.play_commit()\n"
	assert_eq(ScanMenuSound.scan_gd_text(uncond, "res://synthetic.gd"), [],
		"an unconditional cue is not a blindspot — it fires on every path through the function")

	# (d) COMMENTS ARE MASKED. Every cue site in this codebase carries a paragraph ABOUT the cue, and those
	# paragraphs name play_denied constantly — unmasked, prose alone would look like coverage.
	var commented := "func _buy() -> void:\n\t# see MenuStyle.play_denied() for the refusal cue\n\tif merchant.buy(item):\n\t\tMenuStyle.play_commit()\n"
	assert_eq(ScanMenuSound.scan_gd_text(commented, "res://synthetic.gd").size(), 1,
		"a play_denied mentioned only in a COMMENT must not discharge the obligation")


## Every exemption must still name a function that exists, at the path it claims. An EXEMPT_FUNCS entry that
## has rotted (file moved, function renamed) is worse than no entry: it silently stops covering the site it
## was written for while still reading as a deliberate decision.
func test_exemptions_still_point_at_real_functions() -> void:
	var stale: Array = []
	for entry: String in ScanMenuSound.EXEMPT_FUNCS:
		var parts := entry.split("::")
		if parts.size() != 2:
			stale.append("%s (not <path>::<func>)" % entry)
			continue
		var src := FileAccess.get_file_as_string(parts[0])
		if src.is_empty():
			stale.append("%s (file unreadable)" % entry)
		elif not (src.contains("func %s(" % parts[1]) or src.contains("static func %s(" % parts[1])):
			stale.append("%s (no such function)" % entry)
	assert_eq(stale, [], "every ScanMenuSound.EXEMPT_FUNCS entry must name a live function: %s" % [stale])


func _collect_offenders(unreadable: Array) -> Array:
	var offenders: Array = []
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
	# Honour the scanner's own per-file skips — this walk calls scan_gd_text directly, so the const stays the
	# one source of truth all three consumers (panel, tool, this guard) read.
	if ScanMenuSound.SKIP_FILES.has(path):
		return
	var src := FileAccess.get_file_as_string(path)
	if src.is_empty():
		unreadable.append(path)
		return
	offenders.append_array(ScanMenuSound.scan_gd_text(src, path))
