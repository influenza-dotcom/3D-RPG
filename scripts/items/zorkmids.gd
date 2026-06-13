class_name Zorkmids
extends RefCounted

## The money system's units + formatting. Zorkmids are FRACTIONAL: amounts run in hundredths (half a
## zorkmid = 0.5), stored as floats but QUANTIZED to QUANTUM on every mutation (Character.add_money snaps),
## so binary-float drift can never accumulate into the economy. Display through fmt(), which prints whole
## amounts bare ("12"), fractions trimmed ("12.5", "0.75") — never a noisy "12.00".

const QUANTUM: float = 0.01  ## the smallest coin — every wallet/price lands on a multiple of this

## "12" / "12.5" / "0.75" / "-0.5" — quantized, with trailing zeros (and a bare trailing dot) trimmed.
static func fmt(amount: float) -> String:
	var q := snappedf(amount, QUANTUM)
	if is_equal_approx(q, roundf(q)):
		return str(int(roundf(q)))
	return ("%.2f" % q).rstrip("0").rstrip(".")
