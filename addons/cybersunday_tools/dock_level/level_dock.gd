@tool
extends VBoxContainer

## Level-tools dock: one-click Audit Navmesh / Bake+Audit / Validate Content / Validate Level / New Level,
## with results in a panel and (for the audit) the islands/elevation verdict. Folds the existing File->Run
## scripts (NavMeshAudit, ContentValidator, LevelRoot's validator, new_level) into real buttons.
##
## STUB: shows a placeholder. The buttons + API wiring land in the level-tools build step.


func _init() -> void:
	name = "Level"
	var l := Label.new()
	l.text = "Level Tools — coming soon"
	add_child(l)
