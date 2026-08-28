extends Ability

## The LONG-RANGE BODY SCANNER, granted by the Deep-Scan microchip (resources/items/chip_deep_scanner.tres) —
## the same mechanic as BioScanner at a much longer reach, and priced accordingly. See bio_scanner.gd for what
## the mechanic does, why the map draws no bodies at all without one, and why the range lives on the SCRIPT.
##
## A SEPARATE ABILITY ID rather than an upgrade to the first, because that is what this codebase's chip economy
## can express: a chip installs ONE ability id, an id resolves to ONE scene/script pair by name, and the range
## is a property of that pair. Owning both is harmless — AbilityManager.scan_range takes the WIDEST ENABLED one
## — and it is also useful: the Implants tab can switch the deep one off to fall back to the quiet short read.
##
## The two scripts deliberately do NOT share a base class. The obvious one would have to declare `scan_range`,
## and GDScript cannot redeclare an inherited export to change its default — so each tier's number would have
## to be set from _init and the "what does a bare .new() grant" question (the one that decides whether a paid
## chip install works, see bio_scanner.gd) would get harder to answer, not easier. Two four-line scripts and a
## test that pins built-vs-authored is the cheaper honesty.

## This tier's reach in metres. The script default IS the number a chip install grants — see bio_scanner.gd.
@export var scan_range: float = 55.0


func ability_id() -> StringName:
	return &"deep_scanner"


## The contract AbilityManager.scan_range() duck-types on — see bio_scanner.gd.
func scan_range_m() -> float:
	return maxf(0.0, scan_range)
