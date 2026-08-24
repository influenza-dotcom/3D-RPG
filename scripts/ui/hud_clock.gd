class_name HudClock
extends Label

## @system HUD Clock
## @seam Code-built by ui.gd into the top-right stack directly UNDER the minimap and ABOVE the quest tracker; layout comes from GameSettings.hud.clock_*, paint from MenuStyle.hud.clock_color, and the player's choices are polled LIVE off Settings.clock_enabled / Settings.clock_24_hour so an Options change bites the same frame with no HUD rebuild (the minimap_enabled idiom).
## @seam Reads WorldClock.time_of_day — the SAME 0..1 fraction DayNightSky drives the sun from, so the digits and the daylight can never disagree. It is a READER only: nothing here writes the clock.
## @seam The readout survives save/load for free — GameState.time_of_day snapshots WorldClock and re-applies it on load, so the face shows the hour the save was taken at with no persistence of its own.
## @risk The face pauses with the tree, so it freezes during a dialogue (DialogueManager pauses) — correct, because in-game time genuinely is not advancing, but it does mean a player watching the clock through a long conversation sees no movement.
## @risk A level running WorldClock.day_length_seconds = 0 (a deliberately frozen clock) shows one constant time forever. That is the designer's chosen state, not a fault, and this widget cannot tell the two apart.
## @test res://tests/test_hud_clock.gd
##
## The HUD's TIME OF DAY readout: a plain digits line under the minimap, so the player can tell the hour
## without inferring it from how dark the street looks.
##
## WHY IT EXISTS. The day/night cycle's lighting is the only other time signal, and lighting is a terrible
## instrument: the moon keeps the street readable at midnight (DayNightSky's whole point), interiors are lit
## by their own fixtures around the clock, and a player who just wants to know whether a shop is open has to
## walk outside and squint. Sun-position guessing is atmosphere; it is not a readout. This is the readout.
##
## WHY A `Label` AND NOT A DRAWN FACE. A round analogue clock at this canvas size (792x444, nearest-upscaled
## ~2.4x to the window) is four legible pixels of hand — the same reasoning minimap.gd records for choosing
## hairline vector strokes over a downscaled 3D render. Digits read at any size and cost one text stamp.
##
## THE MINUTE GATE. `time_of_day` moves every frame, but the FACE only changes 1440 times a day. Stamping a
## Label's `text` per frame would re-shape the glyph run 60x a second to draw the same "14:35", so the widget
## caches the last minute-of-day it painted and re-stamps only when that integer actually changes — the
## minimap's idle-gate idiom, one int compare per frame. `_last_minute` is seeded to a value no real
## minute-of-day can hold, so the FIRST processed frame always paints (a fresh clock at exactly 00:00 must
## not be mistaken for "unchanged since boot").

## Minutes in one in-game day. Not a designer knob: it is the definition of the 0..1 `time_of_day` fraction
## this widget renders, and a 90-minute "day" would be a different clock face, not a retuned one.
const MINUTES_PER_DAY := 1440

## Minute-of-day last painted. -1 is the "nothing painted yet" seed — outside 0..1439, so the first frame
## always stamps even at midnight sharp. Also re-seeded whenever the 12/24-hour choice flips, because the
## same minute has two different faces and the gate would otherwise hold the stale one.
var _last_minute: int = -1
var _last_24_hour: bool = true


func _ready() -> void:
	# Every HUD element in this project is explicitly IGNORE: the default MOUSE_FILTER_STOP would make this
	# line eat clicks in the corner of the screen.
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _process(_delta: float) -> void:
	# A HIDDEN CLOCK COSTS NOTHING — not a read, not a compare (the minimap's opening line, same reasoning).
	# ui.gd owns the hiding; this just makes OFF genuinely free rather than a hidden node still working.
	if not is_inside_tree() or not is_visible_in_tree():
		return
	var use_24: bool = Settings.clock_24_hour
	var minute := minute_of_day(WorldClock.time_of_day)
	if minute == _last_minute and use_24 == _last_24_hour:
		return
	_last_minute = minute
	_last_24_hour = use_24
	text = face_text(minute, use_24)


## Minute-of-day (0..1439) for a `time_of_day` fraction. FLOORS rather than rounds: rounding would let
## 23:59:40 read as "24:00", an hour no clock face has. fposmod first, so a wrapped or slightly negative
## fraction (the WorldClock's own wrap idiom) lands in range instead of going negative. Pure — unit-tested.
static func minute_of_day(t: float) -> int:
	return posmod(int(floorf(fposmod(t, 1.0) * float(MINUTES_PER_DAY))), MINUTES_PER_DAY)


## The 12-hour face's hour for a 24-hour hour: midnight and noon both read 12, never 0. Pure — unit-tested.
static func hour_12(hour_24: int) -> int:
	var h := posmod(hour_24, 24) % 12
	return 12 if h == 0 else h


## The painted face for a minute-of-day. Zero-pads through TextFormat.pad2 and composes through PlayerText's
## whole templates, so the separator and the AM/PM marker stay translatable and no prose is assembled here.
## The 24-hour face pads the hour ("09:05"); the 12-hour face does NOT ("9:05 AM") — the English convention,
## and the reason these are two templates rather than one with a conditional tail. Pure — unit-tested.
static func face_text(minute: int, use_24_hour: bool) -> String:
	var m := posmod(minute, MINUTES_PER_DAY)
	@warning_ignore("integer_division")
	var h24 := m / 60
	var mm := TextFormat.pad2(m % 60)
	if use_24_hour:
		return PlayerText.clock_24_hour(TextFormat.pad2(h24), mm)
	return PlayerText.clock_12_hour(str(hour_12(h24)), mm, h24 >= 12)


## The face for a raw `time_of_day` fraction — the two pure steps above composed, for callers that hold a
## fraction rather than a minute (a test, a future diegetic wall clock, a save-slot caption). Pure.
static func time_text(t: float, use_24_hour: bool) -> String:
	return face_text(minute_of_day(t), use_24_hour)
