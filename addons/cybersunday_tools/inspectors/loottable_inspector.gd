@tool
extends EditorInspectorPlugin

## LootTable inspector add-on: injects a drop-probability summary + a "Roll 1000x" Monte-Carlo card under a
## LootTable's entries, so a designer sees what the table actually yields (and catches null items / chance<=0 /
## max<min) without playtesting drops.
##
## STUB: handles nothing yet. The summary card + Monte-Carlo land in the inspector build step.


func _can_handle(_object: Object) -> bool:
	return false  # stub: real check is `object is LootTable`
