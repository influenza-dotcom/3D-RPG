extends GutTest

## DRIFT GUARD for the living System Map. docs/SYSTEM_MAP.md is GENERATED from the `## @system / @seam / @risk / @test`
## annotations in scripts/, managers/ + resources/ (scripts/tools/gen_arch_doc.gd). This test re-renders the map from the CURRENT
## source and fails if the committed file differs -- so the generated doc can never silently fall behind the code.
## The same check runs headless as `gen_arch_doc.gd -- --check` for CI / pre-commit.
##
## If this fails, you edited an annotation (or added/removed a class) without regenerating. Fix:
##   godot --headless --path . -s scripts/tools/gen_arch_doc.gd

const ArchScan := preload("res://scripts/tools/arch_scan.gd")


func test_system_map_is_in_sync_with_annotations() -> void:
	var rendered: String = ArchScan.render(ArchScan.scan())
	var committed: String = ArchScan.read_doc()
	assert_ne(committed, "", "docs/SYSTEM_MAP.md is missing -- generate it: godot --headless --path . -s scripts/tools/gen_arch_doc.gd")
	assert_eq(committed, rendered, "docs/SYSTEM_MAP.md is STALE vs the @system annotations -- regenerate: godot --headless --path . -s scripts/tools/gen_arch_doc.gd")
