@tool
extends RefCounted

## Recoverable saves for the CYBER SUNDAY content editors (Dialogue / Quest / Loot). Those editors mutate the loaded
## Resource live and write it back with a bare ResourceSaver.save on Save — so an accidental Save (a bad edit, the
## wrong resource left in the picker) overwrites the .tres with NO recovery except version control. This wraps the
## write: before overwriting an EXISTING file, it copies the current bytes to "<path>.bak" (a one-deep on-disk undo),
## THEN saves. A mis-save is then recoverable by renaming the .bak back over the .tres. A first-ever save (no existing
## file) makes no .bak.
##
## Why NOT EditorUndoRedoManager (per the plugin review): that undoes scene/property changes on the undo stack, not a
## file-byte overwrite of a .tres already written to disk. The .bak is the right tool for "the file I just saved is
## wrong — give me the previous bytes back." The ".bak" copies are throwaway LOCAL safety files (git-ignored), never
## committed content.

const BAK_SUFFIX := ".bak"


## Back up an existing target to "<path>.bak", then ResourceSaver.save(res, path). Returns the save's Error. The
## backup is best-effort: a failed copy is warned but does NOT block the save (a recoverable-save aid must never turn
## into a save-blocker). No backup is made on a first-ever save (nothing to preserve). Rejects a null res / blank path.
static func save_with_backup(res: Resource, path: String) -> Error:
	if res == null or path == "":
		return ERR_INVALID_PARAMETER
	if FileAccess.file_exists(path):
		var bak := path + BAK_SUFFIX
		var cp := DirAccess.copy_absolute(path, bak)  # prior bytes -> .bak (copy OVERWRITES an older .bak, unlike rename)
		if cp != OK:
			push_warning("ContentSaveGuard: couldn't back up %s -> %s (err %d); saving anyway." % [path, bak, cp])
	return ResourceSaver.save(res, path)


## The ".bak" sibling path for a target (for a future "Restore backup" affordance / the drift test).
static func backup_path(path: String) -> String:
	return path + BAK_SUFFIX
