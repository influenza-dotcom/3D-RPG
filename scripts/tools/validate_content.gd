@tool
extends EditorScript

## Designer content validator -- in the editor, File > Run this script (or press Validate Content on the CYBER
## SUNDAY Level tab) to print a content sanity report to the Output panel: duplicate / blank item ids, ammo without
## a caliber, faction internal-id != filename, and Perk / GoapProfile authoring errors. The checks live in
## ContentValidator.run() (reused + unit-tested), so this wrapper is just the editor entry point.
##
## The item list is handed over from the SHARED folder scan (addons/cybersunday_tools/core/item_scan.gd). ItemDb is
## a non-@tool autoload, so inside the editor it is an EMPTY Node -- the old bare `ContentValidator.run()` therefore
## ran the item rules over nothing and printed PASS for every File > Run. Files under resources/items that exist but
## did not load as an Item are printed by name rather than silently dropped (the mid-reimport / broken-script case).

const ItemScan := preload("res://addons/cybersunday_tools/core/item_scan.gd")

func _run() -> void:
	var rep := ItemScan.scan_report()
	var items: Array = rep["items"]
	var skipped: PackedStringArray = rep["skipped"]
	var problems := ContentValidator.run(items)
	if problems.is_empty():
		print("[ContentValidator] OK -- no content problems found (%d item(s) checked)." % items.size())
	else:
		print("[ContentValidator] %d problem(s) (%d item(s) checked):" % [problems.size(), items.size()])
		for p in problems:
			print("   - ", p)
	if items.is_empty():
		print("[ContentValidator] WARN: no item files were found in resources/items -- the item checks ran over nothing.")
	if not skipped.is_empty():
		var names := PackedStringArray()
		for p in skipped:
			names.append(String(p).get_file())
		print("[ContentValidator] WARN: %d item file(s) could not be read and went unchecked: %s -- reimport in progress? run again." % [skipped.size(), ", ".join(names)])
