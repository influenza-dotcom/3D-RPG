class_name TextFormat
extends RefCounted

## The substitution / number / plural seams every player-facing string builder routes through.
##
## THE RULE: code may (a) substitute values into ONE whole authored template via named tokens, or
## (b) SELECT between whole authored templates — it must never concatenate prose pieces or accept a
## prose fragment as an argument. Fragments cannot be translated: word order, inflection, and
## agreement all differ per language, so a sentence assembled from parts in code is a sentence a
## translator can never fix. Values (names, numbers, formatted money) are fine as tokens; words,
## verbs, suffixes, and clauses are not — they belong inside the template (or as one template per
## variant, selected by a bool/enum/key).
##
## PlayerText (scripts/ui/player_text.gd) owns the English templates; designer-authored resource
## strings (TutorialPrompt, CrippleCallout {part}, RentCollector {amount}) follow the same token
## convention at their own call sites. This class is pure statics — no state, no locale yet.


## {name}-token replacement via String.replace — the translator-safe seam: a translation may reorder
## tokens freely ("{count} items" -> "items: {count}") because replacement is positional-free, and a
## literal '%' anywhere in the template can never error (we never touch the '%' format operator).
## Token values are str()-converted, so ints/floats can be passed raw. A token present in the
## template but MISSING from `tokens` is left visible ("{name}") — a loud authoring bug, never a
## silent blank (pinned by tests/test_text_format.gd). Extra dictionary entries are no-ops. Values
## are inserted verbatim; don't nest one token's brace-pattern inside another value.
static func subst(template: String, tokens: Dictionary) -> String:
	var out := template
	for key in tokens:
		out = out.replace("{" + str(key) + "}", str(tokens[key]))
	return out


## THE number formatter — the one copy of the "%.*f" + rstrip("0").rstrip(".") idiom ("12", "12.5",
## "0.75", "-0.5"; never a noisy "12.00"). Future seam: per-locale decimal separators land HERE
## (many locales print "12,5"); today's behaviour is byte-identical to the historic per-file copies,
## ALL of which now delegate (Zorkmids.fmt, StatInfo._num, ItemInfo._num, StatsScreen._stat_num — the
## last three at decimals=1). decimals <= 0 skips the trim — rstrip("0") on a dot-less "120" would eat
## real integer zeros. The "-0" guard keeps a negative value that rounds to zero printing "0",
## matching the old int() display path.
static func num(value: float, decimals: int = 2) -> String:
	var out := "%.*f" % [decimals, value]
	if decimals > 0:
		out = out.rstrip("0").rstrip(".")
	return "0" if out == "-0" else out


## Whole-WORD (or whole-template) selection by count — the future tr_n() seam. The two-form
## signature is deliberately the ENGLISH source shape (singular / everything-else); languages with
## richer agreement (Russian needs 3 forms, Arabic 6) will be served by widening this behind
## tr_n()/TranslationServer plurals later, at which point `plural_form` becomes the English source
## string a catalog keys on. Callers pass whole variants ("{count} item" / "{count} items"), never
## a bare suffix ("s") — the suffix is exactly the untranslatable fragment THE RULE forbids.
static func plural(count: int, singular: String, plural_form: String) -> String:
	return singular if count == 1 else plural_form
