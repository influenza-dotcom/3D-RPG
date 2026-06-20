@tool
extends EditorScript

## Designer content validator — in the editor, File > Run this script (or the Cyber Sunday dock's Validate
## button, later) to print a content sanity report to the Output panel: duplicate / blank item ids, ammo without
## a caliber, faction internal-id != filename, and Perk / GoapProfile authoring errors. The checks live in
## ContentValidator.run() (reused + unit-tested), so this wrapper is just the editor entry point.

func _run() -> void:
	var problems := ContentValidator.run()
	if problems.is_empty():
		print("[ContentValidator] PASS — no content problems found.")
		return
	print("[ContentValidator] %d problem(s):" % problems.size())
	for p in problems:
		print("   - ", p)
