# CYBER SUNDAY Plugin QA

This is the acceptance checklist for changes under `addons/cybersunday_tools/`.
Use it when adding, reviewing, or re-reviewing editor-plugin features. The goal
is simple: every tool should make editor authoring faster without hiding risk or
creating content drift.

## Global Gate

Every plugin change should satisfy these rules:

- **Designer-first:** the happy path is visible in the editor, not hidden behind
  a script edit.
- **No surprise writes:** anything that writes `.tscn`, `.tres`, `.gd`, `.cfg`,
  or project settings must preview the change, require an explicit command, and
  report which files changed.
- **Undo where Godot supports it:** scene mutations and inspector edits should
  use `EditorUndoRedoManager`. Disk rewrites should say they are disk rewrites
  and rely on version control for rollback.
- **Read-only means read-only:** Browse, Refs, Tuning, Graphs, Saves, Encounter,
  Stats, Scene Diff, Architecture, and Audit Re-scan/Auto must not write. (Scene Diff is a
  structural `.tscn` compare — it never merges/writes and fails soft on a
  missing or identical path; pinned by `tests/test_devtools_scenediff.gd`.) If a
  tool gains write behavior, rename or label the command so the designer knows
  exactly what writes.
- **Canonical paths:** generated or discovered content must use the resource
  folders documented in `docs/AUTHORING_GUIDE.md`.
- **Stable identity:** generated resources should seed stable ids from the
  filename when that type has an id field, and should refuse to overwrite an
  existing path.
- **Soft failure:** broken resources, missing scripts, unloaded scenes, absent
  folders, and malformed saves should show a finding/status row instead of
  throwing editor errors.
- **Selection-safe:** tools that require an open scene or selected node must
  show a clear disabled state or message.
- **Current docs:** any new tab, button, write path, generated folder, shortcut,
  or read/write behavior must update `docs/AUTHORING_GUIDE.md`; broad workflow
  changes also update `README.md` and `docs/CURRENT_ARCHITECTURE.md`.

## Audit And Batch Fixes

Audit fixers are allowed only for mechanical, unambiguous changes.

Acceptance:

- Findings distinguish `error`, `warning`, and `info` clearly.
- Fixable findings are labeled `[fixable]` only when the fixer is deterministic.
- The Fix action previews every file/property that will change.
- The confirmation dialog has a cancel path and does not write on preview.
- Each fixer is idempotent: running it twice should not create additional
  changes.
- Ambiguous issues stay findings only.
- After fixing, Re-scan should remove fixed findings or report why they remain.
- The result summary lists changed, skipped, and failed items.
- Resource and file writes preserve valid Godot serialization.

Useful test targets:

- Pure rule/fixer functions with sample Resources.
- Scene-walk checks using tiny instanced scenes.
- File-rewrite fixers against temp copies, not real project content.

## Custom Audit Rules

Custom rules let project-specific checks live outside the plugin core.

Acceptance:

- Missing `res://audit_rules/` is a no-op.
- A broken rule reports a rule error and does not stop the rest of the audit.
- Rules receive the current scene root and may return zero or more findings.
- Findings use the same shape as built-in findings.
- Rule execution should be defensive and editor-safe.
- The authoring guide documents the script base class, method signature, and
  finding shape.

## Content Generation

Generators should create valid starting points, not blank chores.

Acceptance:

- The generated resource lands in the canonical folder for that type.
- The filename, display name, and id fields are consistent where applicable.
- Required nested resources or arrays are seeded enough to pass validation.
- Existing paths are never overwritten.
- The generated file opens in the Inspector and is revealed when useful.
- New scene nodes set `owner` so they persist when the scene is saved.
- Scene placements are undoable.
- The tool works with no scene open by disabling placement commands cleanly.

## Browser, Graphs, And Dependencies

Navigation tools should help designers understand impact before editing or
deleting content.

Acceptance:

- Resource lists are grouped by actual content type and do not include unrelated
  resources from the same folder.
- Double-click opens the resource and reveals it in the FileSystem.
- Missing or broken references are visible as findings, not crashes.
- Back-reference and dependency views identify the referring file and property
  when practical.
- Delete or rename previews must list every affected resource/scene first.
- Large scans should show progress or stay responsive enough for editor use.

## Dialogue, Quest, And Loot Editors

Inline editors should preserve data shape while making content faster to author.

Acceptance:

- Add, remove, reorder, and edit operations preserve valid Resource arrays.
- Save writes only after the user clicks Save.
- Saving an EXISTING `.tres` first copies its prior bytes to a git-ignored `<path>.tres.bak` (a one-deep on-disk undo via `ContentSaveGuard.save_with_backup` — recover by renaming the `.bak` back over the `.tres`). A first-ever save writes no `.bak`, and a failed backup warns but never blocks the save.
- Invalid targets, dangling choices, impossible objective counts, and dead
  loot entries are visible before Save when practical.
- Dropdowns are populated from current project resources, not hardcoded lists,
  unless the enum itself is the source of truth.
- After Save, reopening the same resource shows the same data.

## Text Editor

The **Text** tab bulk-edits the game's player-facing prose over the same `.tres`
that are the single source of truth — a faster surface, never a second store.

Acceptance:

- Read-only until the user clicks **Save Changed**; nothing is written on edit or
  tab-switch.
- Save writes back ONLY the resources actually edited — non-dirty entries are
  skipped.
- Each edited `.tres` is copied to a git-ignored `<path>.tres.bak` via
  `ContentSaveGuard.save_with_backup` before overwrite (a first-ever save writes no
  `.bak`; a failed backup warns but never blocks the save).
- The save reports exactly which files were written and surfaces failures
  (e.g. `Saved N file(s): …` / `N FAILED`).
- The editable content types + fields are driven by the
  `addons/cybersunday_tools/dock_text/text_sources.gd` `SOURCES` registry, not a
  hardcoded per-tab list — add a row there to expose a new type's text.
- Stat wording resolves from `resources/stats/<id>.tres` (`StatText`), not a code
  table.
- Text nested inside ARRAYS (quest objectives, dialogue lines, bark lists) is out
  of scope here — it stays in the **Quest Edit** / **Dialogue Edit** tabs.

## Viewport Gizmos

Visualization is always safe; editing must be explicit.

Acceptance for visualizers:

- Gizmos draw only editor-time information and do not affect runtime.
- Missing shapes or unsupported shape types fail silently or show a lightweight
  status, not an editor error.
- Drawn ranges match serialized data.

Acceptance for editable gizmos:

- Editing mode is explicit, such as a toolbar toggle or modifier gesture.
- Drag operations use undo/redo.
- Serialized fields update immediately enough for visual feedback.
- Numeric edits clamp to the same ranges as Inspector edits.
- Selection, snapping, and transform tools remain predictable.
- The authoring guide names which gizmos are editable and which remain
  visualization-only.

## Save Inspector

Save tools are QA tools first.

Acceptance:

- The default save browser is read-only.
- The UI labels which `user://` location it is reading.
- Missing slots, malformed `ConfigFile` sections, and unknown keys are shown
  clearly.
- Displayed fields use current `GameState` names and save semantics.
- Any save-editing command must preview changed sections/keys and require
  confirmation.
- Save diff should compare semantic keys, not raw file ordering.

## Templates And Encounter Preview

Template and preview tools should make repeatable authored content without
secret runtime assumptions.

Acceptance:

- Templates list every resource and scene node they will create.
- Instantiation refuses to overwrite existing content unless the user chooses a
  new name/path.
- Encounter previews use the same authored fields as runtime spawning.
- Difficulty and loot summaries label themselves as estimates.
- Preview-only nodes are not saved into the scene unless the user explicitly
  creates real content.

## Shortcuts And UI Polish

Small speedups still need discoverability.

Acceptance:

- Shortcuts are documented in the authoring guide and visible in tooltips or
  menu labels.
- Shortcut actions do nothing destructive by themselves.
- Buttons that perform actions use clear verbs.
- Disabled buttons explain what is missing, such as "Open a scene first" or
  "Select a node".

## Scene Placement (Place Tab)

The Place tab drops whole prefab INSTANCES (NPC, PlayerSpawn, LevelDoor, Door,
Container) and built CSG blockout pieces into the edited level.

Acceptance:

- A placed prefab saves as a CLEAN instance: only its own root is owned by the
  level root; its internals are NOT re-owned as editable-children overrides.
  (`place_ops.own_recursive` stops at any node whose `scene_file_path != ""`.)
- Built (non-instanced) subtrees such as the CSG blockout still own every
  descendant so the whole piece saves.
- An `@tool` component that spawns unowned live-preview children — the NPC's
  `BodyModelSwap` (Torso/head/arms/legs) is the canonical case — must NEVER have
  those previews baked into the saved `.tscn`. A baked duplicate shows at runtime
  as a static, untextured (white), un-animated, un-outlined body UNDER the real
  swapped body. Pinned by `tests/test_devtools_placer.gd`.

## Icons (Inventory Icon Baker)

The Icons tab renders EVERY Item to a transparent
`res://resources/icons/<item.id>.png` sized to its grid footprint. The same
pipeline runs from the CLI: `godot --path <project> -s
scripts/tools/bake_item_icons.gd` (windowed — a renderer is required).

Acceptance:

- Items with NO model bake a procedural primitive stand-in (`icon_models.gd`):
  caliber-keyed cartridges/shells/grenades for ammo, a medkit for healing
  consumables, keyword-matched trinkets for the shipped MISC ids, a tinted
  pouch for unknown MISC — never a letter tile. An authored `world_model` or
  `Item.icon` on the `.tres` must win over the stand-in. Builders are pinned
  headless by `tests/test_devtools_icons.gd` (every shipped model-less id
  yields geometry).

- Items whose only model is a `world_prop` scene (the dog crate) bake too — the
  baker instantiates the prop with EVERY script stripped (plus RigidBodies
  frozen) so no gameplay `_ready` runs, and it applies the Throwable
  `data.mesh -> mesh_instance` swap FIRST (reading exports the strip discards),
  so an authored PlaceholderMesh still blanks throwable.tscn's default BoxMesh.
- The bake is TWO-PASS: an AABB framing pass, then a re-frame from the pixels
  that actually rendered (`icon_render.refit`), then an autocrop back to the
  footprint aspect (`icon_render.crop_rect`). A GLB with polluted bounds (extra
  lights/empties — the sniper) must still fill its icon, not bake as a sliver.
- The AABB measure is `item_mesh_view.measure_aabb` (geometry only — lights,
  particles, decals excluded) and is SHARED with the live tile so the two paths
  can't drift.
- Writes PNGs only; never mutates item `.tres` files. Freshly written PNGs need
  an editor scan (focus the editor) before a game launch loads them.
- Pure math (pixel_size / normalize / fit_ortho_size / refit / crop_rect) is
  pinned by `tests/test_devtools_icons.gd`.

## Architecture (System Map viewer)

The Architecture tab is a READ-ONLY viewer of the living System Map: it scans
scripts/, managers/ + resources/ for `## @system / @seam / @risk / @test` annotation blocks
and shows them grouped by system, plus whether the committed `docs/SYSTEM_MAP.md`
is in sync. It shares the pure `ArchScan` builder with the CLI generator and the
drift-guard test.

Acceptance:

- The tab NEVER writes a file — regeneration is the headless CLI
  (`scripts/tools/gen_arch_doc.gd`), which the status line prints. Read-only stays
  read-only, so there is no file-write guard to get wrong.
- The status line reports the system/entry counts and one of: in sync / STALE
  (with the regen command) / not generated yet.
- Rescan re-reads the source so a freshly-added annotation appears without
  reopening the panel.
- Constructs off-tree (compiles + scans in `_init`) — pinned by
  `tests/test_devtools_docks.gd` (`test_arch_view_constructs`).

## Verification

Before calling a plugin slice done:

- Run the narrowest relevant tests or scene/resource harness.
- Toggle the plugin off/on in Project Settings after editing plugin scripts.
- Manually smoke the changed editor path when practical.
- Run `rg` for moved/renamed paths or symbols.
- Run `git diff --check`.
- Summarize docs impact in the final response.
