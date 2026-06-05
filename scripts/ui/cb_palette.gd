class_name CBPalette
## Central source for gameplay-cue colours, so a colorblind-safe palette can be swapped in ONE place
## (toggled by Settings.colorblind_safe_cues). The "safe" set avoids the red/green confusion that trips
## the most common colour blindness — orange for hostile, cyan for friendly — while keeping the normal
## red/green when the toggle is off. Read by the NPC outline/laser, dialogue name colour, and rep toasts.

const NORMAL_HOSTILE := Color(0.9, 0.1, 0.1)    # red
const NORMAL_FRIENDLY := Color(0.1, 0.8, 0.2)   # green
const SAFE_HOSTILE := Color(0.95, 0.55, 0.0)    # orange
const SAFE_FRIENDLY := Color(0.0, 0.7, 0.9)     # cyan

static func hostile() -> Color:
	return SAFE_HOSTILE if _safe() else NORMAL_HOSTILE

static func friendly() -> Color:
	return SAFE_FRIENDLY if _safe() else NORMAL_FRIENDLY

## Reputation gain reads as "friendly", loss as "hostile" — same palette so the cues stay consistent.
static func gain() -> Color:
	return friendly()

static func loss() -> Color:
	return hostile()

static func _safe() -> bool:
	# Settings is an autoload; the field defaults to false even before its _ready, so this is always safe.
	return Settings.colorblind_safe_cues
