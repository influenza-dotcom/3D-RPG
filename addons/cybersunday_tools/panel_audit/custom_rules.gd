@tool
extends RefCounted

## Discovers + runs the project's CUSTOM audit rules (CyberAuditRule scripts in res://audit_rules/) and merges their
## findings into the Audit panel. The folder is a designer-owned extension point: until it exists this is a pure
## no-op (zero scan cost), so the plugin ships with no rules and adds none of its own.
##
## DISCOVERY is a flat folder scan (the project's registry idiom). LOADING + RUNNING fail SOFT: a missing folder, a
## non-script file, a script that can't instantiate or lacks run_audit(), or a run_audit() that returns a non-Array
## are all SKIPPED — never fatal. (A rule that throws at RUNTIME is the author's bug; GDScript can't catch it, hence
## the CyberAuditRule doc's "keep run_audit defensive".) run_rules() is split out so a test can drive it with
## hand-built rule Scripts and no filesystem.

const RULES_DIR := "res://audit_rules"


## Discover every rule script in res://audit_rules/ and run each against the edited scene `root` (may be null).
## Returns merged findings in the standard {severity, source, message, node?} shape.
static func run(root: Node) -> Array:
	return run_rules(discover(), root)


## Instantiate each rule Script + call run_audit(root), merging the Array findings. Skips anything that isn't an
## instantiable Script with a run_audit() returning an Array. Pure w.r.t. the filesystem (takes the scripts in).
static func run_rules(scripts: Array, root: Node) -> Array:
	var out: Array = []
	for s in scripts:
		if not (s is Script) or not (s as Script).can_instantiate():
			continue
		var inst: Variant = (s as Script).new()
		if inst == null or not inst.has_method(&"run_audit"):
			continue
		var res: Variant = inst.run_audit(root)
		if res is Array:
			out.append_array(res)
	return out


## The rule scripts found in res://audit_rules/ (flat, *.gd). Empty when the folder is absent — the common case.
static func discover() -> Array:
	var out: Array = []
	var d := DirAccess.open(RULES_DIR)
	if d == null:
		return out
	d.list_dir_begin()
	var e := d.get_next()
	while e != "":
		if not d.current_is_dir() and e.get_extension() == "gd":
			var s: Variant = load(RULES_DIR.path_join(e))
			if s is Script:
				out.append(s)
		e = d.get_next()
	d.list_dir_end()
	return out
