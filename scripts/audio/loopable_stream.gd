class_name LoopableStream
extends RefCounted

## The ONE owner of "make this authored track loop, whatever its import settings say". Pure statics; never
## instantiated.
##
## Extracted from DialogueMusicBed on 2026-08-22, when the station-terminal music bed (managers/StationMusic.gd)
## became a second consumer. The knowledge in here is a SHIPPED-BUG SCAR — see the zero-length-range note in
## looping_copy — and a scar must not exist in two copies, because the copy that gets fixed is never the copy
## that gets read. DialogueMusicBed._looping_copy / ._stream_loops still exist under their old names and
## delegate here, so tests that call them on an instance are unaffected.
##
## WHY FORCE IT AT ALL: a bed that stops dead partway through is never what a designer meant by "background
## music", and a dropped-in .mp3 imports with Loop = Off by default. Rather than depend on every designer
## ticking the right box in the Import dock, the flag is forced at play time — on a DUPLICATE, so the shared
## resource other systems (or a Radio playlist) may be holding is never mutated.

## True when `s` is authored to loop seamlessly. Duck-typed rather than branched on class, because the loop
## flag lives under a different name per stream type (AudioStreamWAV's `loop_mode` enum vs the .mp3/.ogg
## `loop` bool) and a designer may drop in any of them. An unknown stream shape reports TRUE, so a caller only
## warns when we are actually sure the track won't loop.
static func loops(s: AudioStream) -> bool:
	if s == null:
		return false
	var loop_mode: Variant = s.get(&"loop_mode")  # AudioStreamWAV: 0 = Disabled
	if loop_mode != null:
		# ⭐The flag ALONE is not enough, and this is the shipped bug: a .wav imported with Loop Mode
		# Disabled carries loop_begin == loop_end == 0, and LOOP_FORWARD over a zero-length region plays
		# SILENCE. Every flag-level assertion passed while the user heard nothing at all. Require a real range.
		return int(loop_mode) != 0 and int(s.get(&"loop_end")) > int(s.get(&"loop_begin"))
	var l: Variant = s.get(&"loop")  # AudioStreamMP3 / AudioStreamOggVorbis
	if l != null:
		return bool(l)
	return true

## The authored track, GUARANTEED to loop. An already-looping track is returned AS-IS with no copy; otherwise
## the flag is forced on a duplicate. `who` names the caller in the give-up warning, so a designer reading the
## log knows which bed seams. Null in -> null out (an unauthored bed).
static func looping_copy(authored: AudioStream, who: String) -> AudioStream:
	if authored == null or loops(authored):
		return authored
	var copy: AudioStream = authored.duplicate() as AudioStream
	# The same two shapes the probe reads: the WAV's loop_mode enum, or the .mp3/.ogg `loop` bool.
	if copy.get(&"loop_mode") != null:
		copy.set(&"loop_mode", AudioStreamWAV.LOOP_FORWARD)
		# The RANGE matters as much as the flag (see loops() above). loop_end is in FRAMES:
		# seconds * mix_rate — get_length() already accounts for the compressed format, so this is exact for
		# QOA/IMA-ADPCM as well as raw PCM.
		if int(copy.get(&"loop_end")) <= int(copy.get(&"loop_begin")):
			copy.set(&"loop_begin", 0)
			copy.set(&"loop_end", int(copy.get_length() * float(copy.get(&"mix_rate"))))
	elif copy.get(&"loop") != null:
		copy.set(&"loop", true)
	if not loops(copy):
		# An unrecognised stream shape — the caller falls back to its `finished` restart backstop. Say so,
		# because that repeat has an audible gap at the join.
		push_warning("%s: could not force '%s' (%s) to loop — falling back to a restart-on-finish repeat, which seams audibly." % [who, authored.resource_path, authored.get_class()])
		return authored
	return copy

## The mirror of looping_copy: the authored track guaranteed NOT to loop, so the caller's `finished` signal is
## guaranteed to arrive. An already-non-looping track is returned AS-IS with no copy; otherwise the flag is
## cleared on a duplicate, never on the shared resource.
##
## WHY THIS EXISTS: a bed that rests between plays (WanderMusic) schedules its silence off `finished`, and an
## AudioStreamPlayer whose stream loops NEVER emits it — so one tick of the Import dock's Loop checkbox would
## silently convert "play, then leave the player alone for a while" into "loop this forever", with nothing
## logged and nothing to grep for. Forcing the flag at play time in BOTH directions is what keeps the
## behaviour decided by code (a designer knob) rather than by import metadata. Same argument as looping_copy,
## pointed the other way.
##
## `who` names the caller in the give-up warning. Null in -> null out (an unauthored bed).
static func non_looping_copy(authored: AudioStream, who: String) -> AudioStream:
	if authored == null or not loops(authored):
		return authored
	var copy: AudioStream = authored.duplicate() as AudioStream
	# The same two shapes loops() probes: the WAV's loop_mode enum, or the .mp3/.ogg `loop` bool. The RANGE is
	# deliberately left alone — loops() already reports a zero-length range as non-looping, so clearing the
	# mode is sufficient and rewriting loop_begin/loop_end would only destroy authored markers.
	if copy.get(&"loop_mode") != null:
		copy.set(&"loop_mode", AudioStreamWAV.LOOP_DISABLED)
	elif copy.get(&"loop") != null:
		copy.set(&"loop", false)
	if loops(copy):
		# An unrecognised stream shape. The caller's rest window will simply never fire and the track plays on
		# forever — audible, harmless, and confusing to debug, so say so here rather than leaving it a mystery.
		push_warning("%s: could not clear the loop flag on '%s' (%s) — it will play continuously and the rest window between tracks will never fire." % [who, authored.resource_path, authored.get_class()])
		return authored
	return copy
