@tool
class_name CyberAuditRule
extends RefCounted

## Base for a CUSTOM project audit rule. Drop a `@tool extends CyberAuditRule` script into res://audit_rules/ and the
## CYBER SUNDAY → Audit tab runs it with every Scan, alongside the built-in scene / disk / wiring / content scans — no
## edits to the plugin. Override run_audit() and return findings in the SAME shape the built-in scanners use:
##   { "severity": "ERROR" | "WARN", "source": "res://... or a label", "message": "...",
##     "node": <Node, optional>, "domain": "custom" | "scene" | "content" | "code" (optional) }
## so they render errors-first, jump on double-click (a "node" selects+opens it; a "res://" source opens the resource),
## and — if you tag a known `fix` kind — batch-fix like any built-in finding. `domain` drives the tab's Show filter:
## a missing key reads as "content"; the finding() helper stamps DOMAIN_CUSTOM. Only "code" rows are hidden under the
## designer's default "Scene + Content" view, so tag a programmer-facing check "code" to keep it out of their list.
##
## run_audit runs at EDIT time, so keep it DEFENSIVE: guard every get()/load(), never assume a node exists. GDScript
## has no try/catch, so a rule that crashes takes the scan with it (the loader can only skip STRUCTURAL problems — a
## missing method or a non-Array return). See scan_disk.gd / scan_scene.gd for the built-in patterns to mirror.

## The domain finding() stamps when the rule passes none.
const DOMAIN_CUSTOM := "custom"


func run_audit(_root: Node) -> Array:
	return []


## Build a finding in the standard shape. `node` (optional) makes the row jump to that node on double-click. `domain`
## (default DOMAIN_CUSTOM) is the Audit tab's row filter -- pass "code" for a check only a programmer acts on.
static func finding(severity: String, source: String, message: String, node: Node = null, domain: String = DOMAIN_CUSTOM) -> Dictionary:
	var f := {"severity": severity, "source": source, "message": message, "domain": domain}
	if node != null:
		f["node"] = node
	return f
