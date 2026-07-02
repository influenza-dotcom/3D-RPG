extends GutTest

## PL5: the CYBER SUNDAY content editors (Dialogue / Quest / Loot) save through ContentSaveGuard, which backs up the
## prior .tres bytes to "<path>.bak" before overwriting — so a mis-save (a bad edit, the wrong resource in the picker)
## is recoverable by restoring the .bak. A first-ever save makes no backup; a null resource / blank path is a no-op.

const Guard := preload("res://addons/cybersunday_tools/core/content_save_guard.gd")
const TMP := "user://test_content_save_guard.tres"


func after_each() -> void:
	for f in [TMP, TMP + ".bak"]:
		if FileAccess.file_exists(f):
			DirAccess.remove_absolute(f)


func test_first_save_makes_no_backup() -> void:
	var q := Quest.new()
	q.id = &"alpha"
	var err := Guard.save_with_backup(q, TMP)
	assert_eq(err, OK, "the first save should succeed")
	assert_true(FileAccess.file_exists(TMP), "the target .tres is written")
	assert_false(FileAccess.file_exists(TMP + ".bak"), "a first-ever save has no prior bytes to back up -> no .bak")
	q = null


func test_overwrite_backs_up_prior_bytes() -> void:
	var first := Quest.new()
	first.id = &"alpha"
	Guard.save_with_backup(first, TMP)            # writes the target (id = alpha)
	var second := Quest.new()
	second.id = &"beta"
	var err := Guard.save_with_backup(second, TMP)  # overwrites -> the alpha bytes go to .bak first
	assert_eq(err, OK, "the overwrite save should succeed")
	assert_true(FileAccess.file_exists(TMP + ".bak"), "overwriting an existing file backs the prior bytes up to .bak")
	var bak_text := FileAccess.get_file_as_string(TMP + ".bak")
	assert_string_contains(bak_text, "alpha", "the .bak holds the PRIOR content (id = alpha), not the new one")
	assert_false(bak_text.contains("beta"), "the .bak must NOT contain the new content — it's the pre-overwrite copy")
	var live_text := FileAccess.get_file_as_string(TMP)
	assert_string_contains(live_text, "beta", "the live .tres holds the NEW content")
	first = null
	second = null


func test_null_or_blank_is_a_noop() -> void:
	assert_eq(Guard.save_with_backup(null, TMP), ERR_INVALID_PARAMETER, "a null resource is rejected, not written")
	assert_false(FileAccess.file_exists(TMP), "nothing is written for a null resource")
	var q := Quest.new()
	assert_eq(Guard.save_with_backup(q, ""), ERR_INVALID_PARAMETER, "a blank path is rejected")
	q = null


func test_backup_path_helper() -> void:
	assert_eq(Guard.backup_path("res://a/b.tres"), "res://a/b.tres.bak", "backup_path appends the .bak suffix")
