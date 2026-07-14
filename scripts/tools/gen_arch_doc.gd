extends SceneTree

## GENERATE the living System Map (docs/SYSTEM_MAP.md) from the `## @system / @seam / @risk / @test` annotation blocks
## in the game source. This is the "docs stay synced" piece: the map is DERIVED from the code, so a system's seam or
## risk can't silently drift out of the doc -- change the annotation at the code seam and regenerate.
##
## Run it (headless, no editor needed):
##   godot --headless --path . -s scripts/tools/gen_arch_doc.gd              # write docs/SYSTEM_MAP.md
##   godot --headless --path . -s scripts/tools/gen_arch_doc.gd -- --check   # DON'T write; exit 1 if the file is stale
##
## The `--check` mode is the CI / pre-commit gate (also enforced in-suite by tests/test_arch_doc_sync.gd). It renders
## the map in-memory and compares it to the committed file: exit 0 if identical, exit 1 (with a diff hint) if stale.
##
## ArchScan is PURE (no autoload deps -- it only reads .gd text + project.godot), so preloading it at compile time is
## safe here, unlike validators that touch ItemDb/GameSettings (cf. validate_all.gd's runtime-load note).

const ArchScan := preload("res://scripts/tools/arch_scan.gd")

var _done := false


func _process(_delta: float) -> bool:
	if not _done:
		_done = true
		quit(_run())
	return false


func _run() -> int:
	var check := false
	for a in OS.get_cmdline_user_args():
		if a == "--check":
			check = true

	var rendered: String = ArchScan.render(ArchScan.scan())
	var existing: String = ArchScan.read_doc()
	var system_count := _count_headings(rendered)

	if check:
		if rendered == existing:
			print("arch doc: in sync (%s)" % ArchScan.DOC_PATH)
			return 0
		print("arch doc: STALE -- %s does not match the annotations." % ArchScan.DOC_PATH)
		print("  regenerate: godot --headless --path . -s scripts/tools/gen_arch_doc.gd")
		return 1

	var f := FileAccess.open(ArchScan.DOC_PATH, FileAccess.WRITE)
	if f == null:
		push_error("gen_arch_doc: cannot open %s for writing (err %d)" % [ArchScan.DOC_PATH, FileAccess.get_open_error()])
		return 1
	f.store_string(rendered)
	f.close()
	print("arch doc: wrote %s (%d system section(s))" % [ArchScan.DOC_PATH, system_count])
	return 0


## Count "## " (level-2) headings = one per system section; a cheap sanity number for the write log.
static func _count_headings(text: String) -> int:
	var n := 0
	for line in text.split("\n"):
		if line.begins_with("## ") and not line.begins_with("###"):
			n += 1
	return n
