extends GutTest

## Subsystem README enforcement — the CI-gateable version of "every major system is documented".
##
## WHY A TEST, not an editor config-warning: the yellow Scene-dock triangle from `_get_configuration_warnings()`
## is EDITOR-ONLY and NODE-ONLY. It never runs in the headless import/CI pass (scripts/components/radio.gd:172
## documents this; scripts/tools/validate_all.gd:15 deliberately skips "Domain A config-warnings" as editor-time
## guidance), and it does not exist on Resource/RefCounted — so it can't cover the Resource-based subsystems like
## combat/ (WeaponData), items/ (Item), faction/ (Faction), or npc/goap/ (GoapProfile extends Resource). A missing
## README would sail through CI unseen. This GUT test runs in the fast suite (.github/workflows/ci.yml -> -gexit),
## so a deleted or empty subsystem README fails the build for real — across Nodes AND Resources alike.
##
## The docs-hygiene contract this backs (CLAUDE.md): "Subsystem READMEs such as scripts/npc/goap/README.md or
## scripts/components/README.md for local invariants an agent must read before editing that subsystem."
##
## TO ADD A SUBSYSTEM: author a real README.md first (NO filler prose — this repo ships content unauthored on
## purpose; a README is real doc, so write it for real), then add its res:// dir to REQUIRED_README_DIRS below.
## The manifest is CURATED by design: it pins the docs a MAJOR subsystem must carry, without spamming every thin
## folder (camera/, input/, projectiles/) with a README nobody needs.

## Major subsystems that MUST carry a README.md. Seeded with the dirs that already have one, so the suite is GREEN
## on commit AND this becomes a regression guard: deleting or gutting any of these READMEs now fails CI.
## Backlog — major subsystems still lacking a README; author real content, then promote them into this list:
##   scripts/combat, scripts/items, scripts/dialogue, scripts/player, scripts/ui, scripts/world.
const REQUIRED_README_DIRS: Array[String] = [
	"res://scripts/components",
	"res://scripts/npc",
	"res://scripts/npc/goap",
	"res://scripts/chess",
]

## A README must clear this floor (stripped char count) so an empty file or a one-line stub can't game the check.
## The real subsystem READMEs here run 1-8 KB; 200 is a deliberately low, non-fussy bar — content QUALITY stays a
## code-review concern, this test only guarantees a non-trivial doc FILE exists.
const MIN_README_CHARS := 200


## Guards the manifest against drift: a renamed or moved subsystem must trip THIS test loudly, instead of the
## README check quietly passing because it's pointed at a path that no longer exists. DirAccess.open(dir) == null
## is the repo's headless-safe "does this dir exist" idiom (cf. func_godot_util.gd, validate_all.gd).
func test_required_subsystem_dirs_exist() -> void:
	for dir in REQUIRED_README_DIRS:
		assert_true(DirAccess.open(dir) != null,
			"REQUIRED_README_DIRS lists '%s', but that directory doesn't exist — fix the manifest after a rename/move." % dir)


func test_every_required_subsystem_has_a_real_readme() -> void:
	for dir in REQUIRED_README_DIRS:
		var path := dir + "/README.md"
		# Exact-case "README.md" on purpose: CI runs on case-sensitive ubuntu-latest while the win32 dev box is
		# case-insensitive, so a stray "readme.md" would pass locally and fail CI. Enforce the committed casing.
		assert_true(FileAccess.file_exists(path),
			"%s is a major subsystem with no README.md — document its local invariants before it's edited blind." % dir)
		if not FileAccess.file_exists(path):
			continue  # already failed above; skip the read so we don't also report a spurious empty body
		# README.md is plain text (never imported), so there's no mid-reimport transient to guard against here —
		# get_file_as_string reads the committed bytes directly. strip_edges() defeats the whitespace-only dodge.
		var body := FileAccess.get_file_as_string(path).strip_edges()
		assert_gte(body.length(), MIN_README_CHARS,
			"%s/README.md is a %d-char stub — write a real README, not an empty placeholder." % [dir, body.length()])
		assert_true(body.contains("#"),
			"%s/README.md has no Markdown heading — it should read as a real doc." % path)
