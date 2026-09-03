@tool
extends RefCounted

## ONE-READ-PER-FILE cache shared by the audit panel's TEXT-READING scanners for the duration of a single Scan.
##
## WHY: a Scan runs scan_disk (which also runs scan_wiring), scan_text and scan_menu_sound, and every one of them
## does its own recursive res:// walk AND its own full-text read of the same .gd files — the same bytes pulled off
## disk and turned into a Godot String three or four times per scan. With the Auto toggle on, `filesystem_changed`
## replays all of it after every editor save, so the redundancy lands on the editor's main thread during ordinary
## script editing. The DIRECTORY walks stay per-scanner (each has its own SKIP_DIRS policy and they're cheap —
## DirAccess enumeration, no file contents); it's the READS this removes.
##
## CONTRACT: audit_panel._collect wraps those three in begin() ... end() (the content check and the designer's custom
## rules run AFTER end(): they load resources and may read files the scan just changed). Between those, text_of(path)
## returns the cached text, reading from disk only the first time each path is asked for. OUTSIDE that window the
## cache is INERT — text_of
## reads through to disk every time and stores nothing — so a scanner called on its own (a GUT test, a File→Run
## tool, the text_debt CLI) behaves exactly as it did before and never serves stale bytes. That inert default is
## why this is safe as a drop-in replacement for FileAccess.get_file_as_string at every scanner call site.
##
## The cache is a STATIC (one per editor session, not per instance) because the scanners are all static too. It is
## only ever alive inside one synchronous _collect() (audit_panel's `await` sits BEFORE it, never between begin and
## end), so it cannot outlive an edit: end() drops it unconditionally.

static var _texts: Dictionary = {}
static var _active := false


## Open a caching window. Called by audit_panel._collect before the text-reading scanners run. Idempotent — a second
## begin() without an end() just clears and keeps the window open (a re-entrant scan re-reads from disk).
static func begin() -> void:
	_texts.clear()
	_active = true


## Close the window and release every cached String. ALWAYS call this when the scan finishes, so an edit made after
## the scan is never served from a stale entry (and a big project's worth of source text isn't held for the session).
static func end() -> void:
	_texts.clear()
	_active = false


## True while a caching window is open (for tests / assertions).
static func is_active() -> bool:
	return _active


## The text of `path`. Inside a begin()/end() window this reads each path from disk AT MOST ONCE; outside one it is a
## plain read-through. A missing/unreadable file yields "" — the same soft failure the scanners already handle (they
## treat an empty text as "nothing to report"), so no call site needs a null check it didn't need before.
static func text_of(path: String) -> String:
	if not _active:
		return FileAccess.get_file_as_string(path)
	if _texts.has(path):
		return String(_texts[path])  # Dictionary reads are Variant; cast so the -> String return stays typed
	var text := FileAccess.get_file_as_string(path)
	_texts[path] = text
	return text
