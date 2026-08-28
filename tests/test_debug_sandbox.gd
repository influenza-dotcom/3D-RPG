extends GutTest

## GameState's dev SANDBOX (the console's `sandbox on|off|status|commit`) + disk-write telemetry (`saves`): the
## allowlist redirect resolve_save_path, enable/disable/commit, and the save_count / `saved` seam at the tail of
## _write_atomic. Tested on BARE off-tree GameState instances (load().new(), never the autoload) so the redirect
## flag can't leak into the real session, and against SCRATCH paths ONLY:
##   * the sandbox folder is user://test_sandbox_gs/ (wiped after every test);
##   * non-canonical writes go to user://test_sandbox_*.cfg;
##   * a CANONICAL path (user://gamestate.cfg …) is handed to a writer ONLY after _boxed_or_bail has PROVEN the
##     redirect points into the scratch box — that guard is what keeps a resolve regression from making this file
##     overwrite the developer's real save;
##   * and every test ends with a TRIPWIRE: the five real files and their .tmp/.bak siblings must be byte-identical
##     (md5 + existence) to what they were before the test.
## enable_sandbox READS the real files (it forks them into the box) — reads are fine; nothing here writes them.
## commit_sandbox() targets the five REAL paths, so it is only ever called here (a) with the sandbox OFF and (b) with
## an EMPTY box (a commit never touches a real file with no sandbox counterpart); the copy-back mechanics are driven
## through the path-explicit _commit_file on scratch paths instead.

const GAMESTATE_PATH := "res://managers/GameState.gd"
const BOX := "user://test_sandbox_gs"                       ## the scratch sandbox folder (no trailing slash: pinned by sandbox_dir())
const OTHER := "user://test_sandbox_other.cfg"              ## a non-canonical scratch cfg — must PASS THROUGH the redirect
const COMMIT_TARGET := "user://test_sandbox_commit_target.cfg"  ## the "real" side of a scratch commit
const ABSENT_DIR := "user://test_sandbox_absent_dir"        ## never created: a write under it fails deterministically
const FAIL_PATH := ABSENT_DIR + "/never.cfg"

## Every real path the sandbox protects, plus each one's recovery siblings — the tripwire's watch list.
var _watched: PackedStringArray = PackedStringArray()
var _real_before: Dictionary = {}


func before_each() -> void:
	var gs = load(GAMESTATE_PATH).new()
	_watched = PackedStringArray()
	for real in gs.sandbox_files():
		for p in [real, real + ".tmp", real + ".bak"]:
			_watched.append(p)
	gs.free()
	_real_before = _snapshot(_watched)
	_wipe_box()
	_remove_scratch()


func after_each() -> void:
	# THE TRIPWIRE. If this fires and no test above touched resolve_save_path, something ELSE wrote the real save
	# mid-run (a live game session) — but if it fires beside a sandbox failure, the redirect regressed and this file
	# just wrote the developer's real profile: treat that as the P0.
	var after := _snapshot(_watched)
	for p in _watched:
		assert_eq(after[p], _real_before[p], "TRIPWIRE: real save file '%s' must be untouched by this test" % p)
	_wipe_box()
	_remove_scratch()


# --- fixtures ---------------------------------------------------------------------------------------------------

## {path -> "missing" | md5} — md5 rather than mtime because a same-second rewrite is invisible to a 1 s mtime.
func _snapshot(paths: PackedStringArray) -> Dictionary:
	var out := {}
	for p in paths:
		out[p] = FileAccess.get_md5(p) if FileAccess.file_exists(p) else "missing"
	return out


func _wipe_box() -> void:
	if not DirAccess.dir_exists_absolute(BOX):
		return
	var d := DirAccess.open(BOX)
	if d != null:
		for f in d.get_files():
			DirAccess.remove_absolute(BOX.path_join(f))
	DirAccess.remove_absolute(BOX)


func _remove_scratch() -> void:
	for base in [OTHER, COMMIT_TARGET]:
		for p in [base, base + ".tmp", base + ".bak"]:
			if FileAccess.file_exists(p):
				DirAccess.remove_absolute(p)
	if DirAccess.dir_exists_absolute(ABSENT_DIR):
		DirAccess.remove_absolute(ABSENT_DIR)


## A minimal COMPLETE profile cfg: [player] satisfies load_from_disk's _cfg_is_profile gate and [eof] its
## completeness check. The marker matters — enable_sandbox forks the machine's REAL files into the box, and the
## first sandboxed write rotates that copy (which carries [eof]) into a sandbox .bak; a marker-LESS fixture primary
## would then lose to that complete .bak on the ladder and a test would read the developer's real profile back.
func _cfg(money: float, marker: String = "") -> ConfigFile:
	var cfg := ConfigFile.new()
	cfg.set_value("player", "money", money)
	if not marker.is_empty():
		cfg.set_value("player", "name", marker)
	cfg.set_value("eof", "complete", true)
	return cfg


func _boxed(real: String) -> String:
	return BOX.path_join(real.get_file())


## THE SAFETY GATE for handing a CANONICAL path to a writer: fails (and returns false so the caller skips the write)
## unless the redirect provably points at the scratch box. Never write a canonical path without this.
func _boxed_or_bail(gs: Node, real: String) -> bool:
	var resolved: String = gs.resolve_save_path(real)
	var ok := resolved == _boxed(real)
	assert_true(ok, "SAFETY: %s must resolve into the scratch box before any write (resolved to '%s')" % [real, resolved])
	return ok


func _money_in(path: String) -> float:
	var cfg := ConfigFile.new()
	if cfg.load(path) != OK:
		return -1.0
	return float(cfg.get_value("player", "money", -1.0))


# --- resolve_save_path / sandbox_files -----------------------------------------------------------------------

func test_resolve_is_identity_when_off() -> void:
	var gs = load(GAMESTATE_PATH).new()
	assert_false(gs.sandbox_active(), "a fresh GameState has no sandbox")
	assert_eq(gs.sandbox_dir(), "", "sandbox_dir() reads blank while off")
	for real in gs.sandbox_files():
		assert_eq(gs.resolve_save_path(real), real, "off -> identity for the canonical path %s" % real)
	assert_eq(gs.resolve_save_path(OTHER), OTHER, "off -> identity for a non-canonical path too")
	gs.free()


func test_sandbox_files_lists_exactly_the_five_canonical_paths() -> void:
	var gs = load(GAMESTATE_PATH).new()
	var files: PackedStringArray = gs.sandbox_files()
	assert_eq(files.size(), 5, "the autosave, the quicksave and the three slots — five files, no more")
	assert_true(files.has(gs.SAVE_PATH), "the autosave (SAVE_PATH) is redirected")
	assert_true(files.has(gs.QUICKSAVE_PATH), "the quicksave is redirected")
	for slot in range(1, gs.SLOT_COUNT + 1):
		assert_true(files.has(gs.slot_path(slot)), "slot %d is redirected" % slot)
	gs.free()


func test_enable_maps_only_the_canonical_paths_and_disable_restores_identity() -> void:
	var gs = load(GAMESTATE_PATH).new()
	assert_eq(gs.enable_sandbox(BOX), OK, "enabling on a scratch folder succeeds")
	assert_true(gs.sandbox_active(), "…and the redirect is armed")
	assert_eq(gs.sandbox_dir(), BOX, "sandbox_dir() reports the folder (normalised, no trailing slash)")
	assert_true(DirAccess.dir_exists_absolute(BOX), "the folder was created")
	for real in gs.sandbox_files():
		assert_eq(gs.resolve_save_path(real), _boxed(real), "%s resolves into the box under its own basename" % real)
	# The ALLOWLIST edge, pinned: ONLY the exact canonical paths move. A scratch cfg, a path that merely SHARES a
	# canonical basename in another folder, and an already-resolved sandbox path all pass through unchanged — the
	# redirect must be idempotent and must never hijack a caller's explicit path.
	assert_eq(gs.resolve_save_path(OTHER), OTHER, "a non-canonical path passes through while ON")
	var lookalike := "user://elsewhere/gamestate.cfg"
	assert_eq(gs.resolve_save_path(lookalike), lookalike, "a canonical BASENAME in another folder is NOT redirected (exact-path allowlist)")
	var boxed_auto := _boxed(gs.SAVE_PATH)
	assert_eq(gs.resolve_save_path(boxed_auto), boxed_auto, "a resolved sandbox path resolves to itself (idempotent)")
	gs.disable_sandbox()
	assert_false(gs.sandbox_active(), "off again")
	assert_eq(gs.sandbox_dir(), "", "sandbox_dir() blank again")
	for real in gs.sandbox_files():
		assert_eq(gs.resolve_save_path(real), real, "disable -> identity again for %s" % real)
	gs.free()


func test_enable_refuses_blank_and_the_real_folder() -> void:
	# Mapping into the real folder would resolve every file onto ITSELF, and a commit would then copy a file over
	# itself (truncate-then-read of the only checkpoint) — so it is refused before anything is created or armed.
	var gs = load(GAMESTATE_PATH).new()
	assert_ne(gs.enable_sandbox(""), OK, "a blank folder is refused")
	assert_false(gs.sandbox_active(), "…and nothing is armed")
	assert_ne(gs.enable_sandbox("user://"), OK, "the real user:// folder is refused")
	assert_false(gs.sandbox_active(), "…and nothing is armed")
	assert_ne(gs.enable_sandbox("user://."), OK, "…however it is spelled")
	assert_false(gs.sandbox_active(), "…and nothing is armed")
	for real in gs.sandbox_files():
		assert_eq(gs.resolve_save_path(real), real, "a refused enable leaves %s at identity" % real)
	gs.free()


func test_enable_is_idempotent_and_replaces_a_stale_sandbox() -> void:
	# A STALE box from a "previous session": a quicksave nobody's real profile backs, plus a leftover .bak rung.
	var gs = load(GAMESTATE_PATH).new()
	DirAccess.make_dir_recursive_absolute(BOX)
	var stale_quick := _boxed(gs.QUICKSAVE_PATH)
	assert_eq(_cfg(1.0, "STALE_SANDBOX_MARKER").save(stale_quick), OK, "fixture: a stale sandbox quicksave")
	assert_eq(_cfg(2.0, "STALE_BAK_MARKER").save(stale_quick + ".bak"), OK, "fixture: a stale sandbox .bak rung")
	assert_eq(gs.enable_sandbox(BOX), OK, "enable over a stale box succeeds")
	# ALWAYS OVERWRITE: after `on` the box mirrors the REAL five exactly. Whether or not this machine has a real
	# quicksave, the stale one is gone — either replaced by the real bytes or removed (no ghost has_quicksave()).
	assert_false(FileAccess.file_exists(stale_quick + ".bak"), "a stale sandbox .bak rung is cleared (the ladder must not resurrect a previous sandbox session)")
	var stale_survived := false
	if FileAccess.file_exists(stale_quick):
		var probe := ConfigFile.new()
		probe.load(stale_quick)
		stale_survived = str(probe.get_value("player", "name", "")) == "STALE_SANDBOX_MARKER"
	assert_false(stale_survived, "the stale sandbox quicksave was replaced by the real one or removed — never kept")
	assert_eq(FileAccess.file_exists(stale_quick), FileAccess.file_exists(gs.QUICKSAVE_PATH), "the box mirrors the real set: a sandbox quicksave exists iff the real one does")
	assert_eq(gs.has_quicksave(), FileAccess.file_exists(stale_quick), "has_quicksave() answers for the SANDBOX file while on")
	assert_eq(gs.has_save_file(), FileAccess.file_exists(_boxed(gs.SAVE_PATH)), "has_save_file() answers for the SANDBOX file while on")
	assert_eq(gs.has_slot(1), FileAccess.file_exists(_boxed(gs.slot_path(1))), "has_slot() answers for the SANDBOX file while on")
	# IDEMPOTENT: write into the live box, then `on` again — the sandboxed progress must NOT be clobbered by a re-fork.
	if _boxed_or_bail(gs, gs.QUICKSAVE_PATH):
		assert_eq(gs._write_atomic(_cfg(77.0, "LIVE_SANDBOX_MARKER"), gs.QUICKSAVE_PATH), OK, "a sandboxed quicksave write lands")
		assert_eq(gs.enable_sandbox(BOX), OK, "a second `on` for the SAME folder is OK…")
		assert_eq(gs.enable_sandbox(BOX + "/"), OK, "…and a trailing-slash spelling is the same folder…")
		assert_almost_eq(_money_in(stale_quick), 77.0, 0.001, "…and neither re-forked the real profile over the live sandbox (idempotent, not a clobber)")
		assert_eq(gs.sandbox_dir(), BOX, "the folder spelling stays normalised")
	gs.disable_sandbox()
	assert_true(FileAccess.file_exists(stale_quick), "disable leaves the sandbox files on disk (a crash/relaunch model: the hours sit in the box for a later commit)")
	gs.free()


# --- the write funnel: _write_atomic under the sandbox --------------------------------------------------------

func test_write_atomic_lands_in_the_sandbox_and_leaves_the_real_save_untouched() -> void:
	var gs = load(GAMESTATE_PATH).new()
	assert_eq(gs.enable_sandbox(BOX), OK, "enable on the scratch box")
	if not _boxed_or_bail(gs, gs.SAVE_PATH):
		gs.free()
		return
	var boxed := _boxed(gs.SAVE_PATH)
	# The autosave path (SAVE_PATH is what save_to_disk()/autosave() default to) — resolved INSIDE _write_atomic.
	assert_eq(gs._write_atomic(_cfg(42.0), gs.SAVE_PATH), OK, "a canonical write succeeds while sandboxed")
	assert_true(FileAccess.file_exists(boxed), "…and lands under the sandbox folder")
	assert_almost_eq(_money_in(boxed), 42.0, 0.001, "…with the written profile")
	assert_false(FileAccess.file_exists(boxed + ".tmp"), "no stray .tmp in the box (the atomic swap completed)")
	assert_eq(gs.last_save_path, boxed, "last_save_path is the RESOLVED path actually written, never the real one")
	assert_eq(gs.save_count, 1, "the write counted")
	assert_true(gs.has_save_file(), "has_save_file() sees the sandbox autosave")
	# The WHOLE rung set lives in the box: a second write rotates the sandbox primary into a sandbox .bak.
	assert_eq(gs._write_atomic(_cfg(43.0), gs.SAVE_PATH), OK, "second sandboxed write")
	assert_true(FileAccess.file_exists(boxed + ".bak"), "the prior sandbox write rotated to a SANDBOX .bak")
	assert_almost_eq(_money_in(boxed + ".bak"), 42.0, 0.001, "…holding the previous sandbox write")
	assert_almost_eq(_money_in(boxed), 43.0, 0.001, "…and the sandbox primary holds the newest")
	# The READ side resolves the same way: load_from_disk() at its SAVE_PATH default reads the sandbox autosave.
	assert_true(gs.load_from_disk(), "load_from_disk() (default SAVE_PATH) loads while sandboxed")
	assert_almost_eq(gs.money, 43.0, 0.001, "…and it read the SANDBOX file, not the real profile")
	# The quickload gate (_load_and_reload) resolves too — off-tree it loads and skips the scene reload.
	if _boxed_or_bail(gs, gs.QUICKSAVE_PATH):
		assert_eq(gs._write_atomic(_cfg(55.0), gs.QUICKSAVE_PATH), OK, "a sandboxed quicksave write")
		assert_true(gs.has_quicksave(), "has_quicksave() sees it")
		assert_true(gs._load_and_reload(gs.QUICKSAVE_PATH), "_load_and_reload passes its existence gate on the SANDBOX quicksave")
		assert_almost_eq(gs.money, 55.0, 0.001, "…and loaded the sandbox quicksave")
	# (The real files are asserted byte-identical by after_each's tripwire.)
	gs.free()


# --- load_autosave: the death-respawn reload seam -------------------------------------------------------------

func test_load_autosave_reads_the_autosave_through_the_reload_seam() -> void:
	# The Player's RELOAD_LAST_SAVE death branch routes through load_autosave() (-> _load_and_reload) so the
	# scene reload arms the _reload_pending autosave freeze — the same latch a quickload gets (the latch's
	# behaviour itself is pinned in test_world_snapshot.gd; the in-tree arm can't run under GUT because
	# _load_and_reload would reload the GUT scene). What IS testable off-tree, and what this pins: the seam
	# exists, it reads the AUTOSAVE (SAVE_PATH — the file the coalesced world-state autosave writes, NOT the
	# quicksave), and it returns false on a missing/unreadable file WITHOUT loading, so the Player's degrade
	# branch (a plain reload of the in-memory run) owns that case. Sandboxed so SAVE_PATH resolves into the
	# scratch box and this test never reads the developer's real profile.
	var gs = load(GAMESTATE_PATH).new()
	assert_eq(gs.enable_sandbox(BOX), OK, "enable on the scratch box")
	if not _boxed_or_bail(gs, gs.SAVE_PATH):
		gs.free()
		return
	var boxed := _boxed(gs.SAVE_PATH)
	# enable_sandbox forked the machine's real rung set into the box — clear it so "no autosave" is deterministic.
	for p in [boxed, boxed + ".tmp", boxed + ".bak"]:
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(p)
	assert_false(gs.load_autosave(), "no autosave on disk -> false (no load, no reload) — the caller owns the degrade")
	assert_false(gs.loaded, "…and the failed path never promoted `loaded`")
	assert_eq(gs._write_atomic(_cfg(66.0), gs.SAVE_PATH), OK, "fixture: a sandboxed autosave profile")
	assert_true(gs.load_autosave(), "with an autosave present, load_autosave() loads it (off-tree: skips the scene reload)")
	assert_almost_eq(gs.money, 66.0, 0.001, "…and it read the AUTOSAVE file (SAVE_PATH), not the quicksave")
	assert_true(gs.loaded, "…and promoted `loaded` so the fresh Player would apply the build after the reload")
	gs.free()


# --- telemetry: save_count / save_fail_count / last_save_* / `saved` -----------------------------------------

func test_save_count_and_saved_signal_on_a_scratch_path() -> void:
	var gs = load(GAMESTATE_PATH).new()
	assert_eq(gs.save_count, 0, "fresh: no writes")
	assert_eq(gs.save_fail_count, 0, "fresh: no failures")
	assert_eq(gs.last_save_msec, -1, "fresh: no attempt yet")
	assert_eq(gs.last_save_path, "", "fresh: no path yet")
	var got: Array = []
	gs.saved.connect(func(p: String, e: int) -> void: got.append([p, e]))
	assert_eq(gs._write_atomic(_cfg(9.0), OTHER), OK, "a scratch write succeeds (sandbox off -> identity path)")
	assert_true(FileAccess.file_exists(OTHER), "…and lands at the scratch path")
	assert_eq(gs.save_count, 1, "save_count counts the successful swap")
	assert_eq(gs.save_fail_count, 0, "no failure counted")
	assert_eq(gs.last_save_path, OTHER, "last_save_path is the path written")
	assert_eq(gs.last_save_err, OK, "last_save_err is OK")
	assert_gte(gs.last_save_msec, 0, "last_save_msec was stamped")
	assert_eq(got.size(), 1, "`saved` fired once")
	if got.size() == 1:
		assert_eq(got[0][0], OTHER, "…with the written path")
		assert_eq(got[0][1], OK, "…and OK")
	assert_eq(gs._write_atomic(_cfg(10.0), OTHER), OK, "a second write")
	assert_eq(gs.save_count, 2, "…increments the counter")
	assert_eq(got.size(), 2, "…and fires `saved` again")
	gs.free()


func test_save_fail_count_on_an_unwritable_path() -> void:
	# FileAccess.WRITE never creates parent directories on any platform, so a path under a folder that does not exist
	# fails deterministically (ConfigFile.save returns the open Error, prints nothing) — no fixture, no collision.
	assert_false(DirAccess.dir_exists_absolute(ABSENT_DIR), "precondition: the parent folder must not exist")
	var gs = load(GAMESTATE_PATH).new()
	var got: Array = []
	gs.saved.connect(func(p: String, e: int) -> void: got.append([p, e]))
	var err: int = gs._write_atomic(_cfg(1.0), FAIL_PATH)
	assert_ne(err, OK, "the write reports the failure (it did NOT persist)")
	assert_false(FileAccess.file_exists(FAIL_PATH), "nothing landed")
	assert_false(FileAccess.file_exists(FAIL_PATH + ".tmp"), "no partial temp stranded")
	assert_eq(gs.save_fail_count, 1, "save_fail_count counts it")
	assert_eq(gs.save_count, 0, "save_count does not")
	assert_eq(gs.last_save_path, FAIL_PATH, "last_save_path records the attempted path")
	assert_ne(gs.last_save_err, OK, "last_save_err records the Error")
	assert_gte(gs.last_save_msec, 0, "the attempt was time-stamped even though it failed")
	assert_eq(got.size(), 1, "`saved` fires on failure too")
	if got.size() == 1:
		assert_eq(got[0][0], FAIL_PATH, "…with the attempted path")
		assert_ne(got[0][1], OK, "…and the Error")
	gs.free()


# --- commit --------------------------------------------------------------------------------------------------

func test_commit_sandbox_refuses_when_off_and_touches_nothing_with_an_empty_box() -> void:
	var gs = load(GAMESTATE_PATH).new()
	assert_eq(gs.commit_sandbox(), ERR_UNCONFIGURED, "a commit with no sandbox is refused")
	assert_eq(gs.enable_sandbox(BOX), OK, "enable on the scratch box")
	# Empty the box: a commit copies ONLY sandbox files that exist, so with none it must return OK and leave every
	# real file exactly as it was (after_each's tripwire proves the second half). This is the ONLY active-sandbox
	# commit this file may run — any box file would be copied over a REAL save. So the emptiness is proven THROUGH
	# the redirect (resolve_save_path, the very path commit copies FROM), not through this file's own idea of the
	# box: if the two ever disagreed, the tripwire would only report the damage after the real .bak was rotated.
	var box_is_empty := true
	for real in gs.sandbox_files():
		var boxed: String = gs.resolve_save_path(real)
		if not _boxed_or_bail(gs, real):
			box_is_empty = false
			continue
		for p in [boxed, boxed + ".tmp", boxed + ".bak"]:
			if FileAccess.file_exists(p):
				DirAccess.remove_absolute(p)
		if FileAccess.file_exists(boxed):
			box_is_empty = false
	assert_true(box_is_empty, "SAFETY: every resolved sandbox path is inside the scratch box and absent before the commit")
	if box_is_empty:
		assert_eq(gs.commit_sandbox(), OK, "a commit from an empty box is OK (nothing to copy)")
	assert_true(gs.sandbox_active(), "the sandbox STAYS active after a commit")
	gs.free()


func test_commit_file_copies_the_sandbox_bytes_over_the_real_path_crash_safely() -> void:
	# The per-file copy-back on SCRATCH paths: box -> "real" goes through real+".tmp" and the shared swap, so the
	# pre-commit real rotates to .bak (a one-step undo) and no .tmp is stranded.
	DirAccess.make_dir_recursive_absolute(BOX)
	var boxed := BOX.path_join("commit_source.cfg")
	assert_eq(_cfg(500.0, "FROM_BOX").save(boxed), OK, "fixture: the sandbox file")
	assert_eq(_cfg(1.0, "PRE_COMMIT_REAL").save(COMMIT_TARGET), OK, "fixture: the pre-commit 'real' file")
	var gs = load(GAMESTATE_PATH).new()
	assert_eq(gs._commit_file(boxed, COMMIT_TARGET), OK, "the copy-back succeeds")
	assert_almost_eq(_money_in(COMMIT_TARGET), 500.0, 0.001, "the real path now holds the sandbox bytes")
	assert_true(FileAccess.file_exists(COMMIT_TARGET + ".bak"), "the pre-commit real rotated to .bak (undo)")
	assert_almost_eq(_money_in(COMMIT_TARGET + ".bak"), 1.0, 0.001, "…holding the pre-commit bytes")
	assert_false(FileAccess.file_exists(COMMIT_TARGET + ".tmp"), "no .tmp stranded beside the real file")
	assert_true(FileAccess.file_exists(boxed), "the sandbox file is left in place (commit copies, never moves)")
	assert_eq(gs.save_count, 0, "a commit is a copy, not a save — save_count does not move")
	# A missing sandbox counterpart is a no-op, never a delete.
	assert_eq(gs._commit_file(BOX.path_join("nope.cfg"), COMMIT_TARGET), OK, "no sandbox file -> OK…")
	assert_almost_eq(_money_in(COMMIT_TARGET), 500.0, 0.001, "…and the real file is left untouched")
	gs.free()


func test_commit_file_honours_the_fallback_recovered_guard_like_a_normal_write() -> void:
	# The rotate rules are SHARED with _write_atomic (_swap_into_place): while a real path is flagged
	# fallback-recovered, the rejected primary is DISCARDED (not rotated over the .bak the ladder recovered from) and
	# a landed swap clears the flag — a commit must not be the one write that buries a real .bak.
	DirAccess.make_dir_recursive_absolute(BOX)
	var boxed := BOX.path_join("commit_source.cfg")
	assert_eq(_cfg(900.0, "FROM_BOX").save(boxed), OK, "fixture: the sandbox file")
	assert_eq(_cfg(2.0, "REJECTED_PRIMARY").save(COMMIT_TARGET), OK, "fixture: the real primary the ladder refused")
	assert_eq(_cfg(3.0, "GOOD_BAK").save(COMMIT_TARGET + ".bak"), OK, "fixture: the intact .bak it recovered from")
	var gs = load(GAMESTATE_PATH).new()
	gs._recovered_from_fallback[COMMIT_TARGET] = true
	assert_eq(gs._commit_file(boxed, COMMIT_TARGET), OK, "the copy-back succeeds under the guard")
	assert_almost_eq(_money_in(COMMIT_TARGET), 900.0, 0.001, "the real primary now holds the sandbox bytes")
	assert_almost_eq(_money_in(COMMIT_TARGET + ".bak"), 3.0, 0.001, "the .bak the ladder recovered from is NOT overwritten by the rejected primary")
	assert_false(gs._recovered_from_fallback.has(COMMIT_TARGET), "a landed swap clears the flag: the real primary is trustworthy again")
	gs.free()


# --- status lines --------------------------------------------------------------------------------------------

func test_status_lines_name_the_folder_and_every_canonical_file() -> void:
	# Loose pins only (the wording is developer copy and free to change): the folder is named, and each of the five
	# basenames gets a line — the command prints these verbatim, so the shape is what matters.
	var gs = load(GAMESTATE_PATH).new()
	var off_lines: PackedStringArray = gs.sandbox_status_lines()
	assert_gte(off_lines.size(), 6, "off: a header plus one line per canonical file")
	assert_string_contains(off_lines[0], "OFF")
	assert_eq(gs.enable_sandbox(BOX), OK, "enable on the scratch box")
	var on_lines: PackedStringArray = gs.sandbox_status_lines()
	assert_gte(on_lines.size(), 6, "on: a header plus one line per canonical file")
	assert_string_contains(on_lines[0], "ON")
	assert_string_contains(on_lines[0], BOX)
	var joined := "\n".join(on_lines)
	for real in gs.sandbox_files():
		assert_string_contains(joined, String(real).get_file())
	gs.free()
