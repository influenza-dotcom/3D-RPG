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
- **Read-only means read-only:** Browse, Tuning, Graphs, Saves, and Audit
  Re-scan/Auto must not write. If a tool gains write behavior, rename or label
  the command so the designer knows exactly what writes.
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
- Invalid targets, dangling choices, impossible objective counts, and dead
  loot entries are visible before Save when practical.
- Dropdowns are populated from current project resources, not hardcoded lists,
  unless the enum itself is the source of truth.
- After Save, reopening the same resource shows the same data.

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

## Verification

Before calling a plugin slice done:

- Run the narrowest relevant tests or scene/resource harness.
- Toggle the plugin off/on in Project Settings after editing plugin scripts.
- Manually smoke the changed editor path when practical.
- Run `rg` for moved/renamed paths or symbols.
- Run `git diff --check`.
- Summarize docs impact in the final response.
