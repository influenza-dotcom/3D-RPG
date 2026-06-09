class_name CBPalette
## Central source for gameplay-cue colours, so a colorblind-safe palette can be swapped in ONE place
## (toggled by Settings.colorblind_safe_cues). The "safe" set avoids the red/green confusion that trips
## the most common colour blindness — orange for hostile, cyan for friendly — while keeping the normal
## red/green when the toggle is off. Allies (companions) are blue in both sets — outside the red/green axis.
## Read by the NPC outline/laser, the dialogue + hover name colours, and rep toasts.

const NORMAL_HOSTILE := Color(0.9, 0.1, 0.1)    # red
const NORMAL_FRIENDLY := Color(0.1, 0.8, 0.2)   # green
const NORMAL_ALLY := Color(0.3, 0.55, 1.0)      # blue — a recruited companion
const SAFE_HOSTILE := Color(0.95, 0.55, 0.0)    # orange
const SAFE_FRIENDLY := Color(0.0, 0.7, 0.9)     # cyan
const SAFE_ALLY := Color(0.55, 0.45, 1.0)       # periwinkle (stays distinct from the cyan "friendly")

static func hostile() -> Color:
	return SAFE_HOSTILE if _safe() else NORMAL_HOSTILE

static func friendly() -> Color:
	return SAFE_FRIENDLY if _safe() else NORMAL_FRIENDLY

## A recruited COMPANION (an ally fighting alongside you) — blue, kept distinct from a merely-FRIENDLY NPC.
static func ally() -> Color:
	return SAFE_ALLY if _safe() else NORMAL_ALLY

## The name/cue colour for an NPC by allegiance: a recruited COMPANION (is_ally) is blue and WINS over
## disposition; otherwise FRIENDLY -> green, HOSTILE -> red, and anything else (NEUTRAL / non-NPC) falls to the
## caller's `neutral` (white in dialogue, near-white on the hover readout). Centralised so the hover name and
## the dialogue speaker name stay in lockstep, and the mapping is unit-testable off-tree.
static func disposition_color(is_ally: bool, disposition: int, neutral: Color) -> Color:
	if is_ally:
		return ally()
	match disposition:
		Disposition.Kind.FRIENDLY:
			return friendly()
		Disposition.Kind.HOSTILE:
			return hostile()
	return neutral

## Reputation gain reads as "friendly", loss as "hostile" — same palette so the cues stay consistent.
static func gain() -> Color:
	return friendly()

static func loss() -> Color:
	return hostile()

static func _safe() -> bool:
	# Settings is an autoload; the field defaults to false even before its _ready, so this is always safe.
	return Settings.colorblind_safe_cues
