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
  Stats, Scene Diff, Architecture, and Audit Scan/Auto must not write. (Scene Diff is a
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
- **Panel identity is pinned:** every tool `Control` keeps its own `name`
  ("Quest Edit", "Dialogue Edit", "Loot Edit", "Items", "Content", "Level",
  "Bridge", "Scene Diff", …). Tests pin those names and `cyber_panel.gd`'s
  `_tabs` registry keys on them, so `show_tab` / `open_in_editor` /
  `on_scene_changed` all break if one is renamed. The title a DESIGNER reads is
  set separately by `cyber_panel.gd` with `set_tab_title` — **retitle there, never
  by renaming the Control** — and the job group a tool sits in (Build / Create /
  Tune / Check / Advanced) is likewise one `_group(...)` row in that file.
- **Tabs reach the panel ONLY through `core/host.gd`:** `Host.find(self)`,
  `Host.show_tab(self, name)`, `Host.open_in_editor(self, path)`. Never a
  `get_parent()` chain or a hard-coded node path — the nesting depth has already
  changed once (flat strip → job groups) and is a private layout detail. All three
  are null-safe off-tree, which is exactly what keeps every handoff button
  harmless under GUT. A tab may implement `select_path(path) -> bool` (the panel
  hands it a content file to open) and `on_scene_changed(root) -> void`
  (forwarded from `EditorPlugin.scene_changed`, and once at enable); both are
  duck-typed and optional.

### Height and width contract (every tab)

The bottom panel is SHARED, so a tab that is tall when SELECTED stretches the
panel for every tab after it. This plugin has twice shipped a dock that grew past
a short display.

- **The real mechanism:** a `TabContainer`'s minimum height tracks the **CURRENT**
  tab, not the tallest one (`use_hidden_tabs_for_min_size = false`, set explicitly
  on the panel and on every job group), and the editor's bottom splitter **KEEPS
  the height it grew to** once a tall tab has been shown. "It averages out" is not
  a defence: every tab must be short **while it is selected**. Any comment
  claiming the TabContainer "sizes to its tallest tab" is FALSE — correct or
  delete it.
- **Shape:** the head/action bar and **ONE** status `Label` sit OUTSIDE a
  `ScrollContainer`; everything that grows (form rows, lists, trees, reports) sits
  INSIDE it, so the head and Save never scroll away. A control that already
  scrolls itself (`ItemList`, `Tree`, a `RichTextLabel` with `scroll_active`) may
  stand alone rather than be wrapped in a second scroller.
- **Floors:** the scrolled body / list / tree floor is **90–120 px**, and nothing
  in a TAB body goes above 120 (`BODY_MIN_HEIGHT` / `TREE_MIN_HEIGHT` /
  `REPORT_MIN_HEIGHT` are the named constants; today they run 90–110). A control
  inside a POPUP (the Audit tab's "Fix results" `AcceptDialog` is the only one)
  is not part of the tab's minimum and may be as tall as the window needs — do
  not "fix" it down. Set `horizontal_scroll_mode = SCROLL_MODE_DISABLED` on the
  scroller so a long line wraps instead of widening the whole editor. (The
  Factions grid is the one deliberate exception — it keeps horizontal scrolling,
  because an N × N matrix is legitimately wider than a narrow dock.)
- **Status Label:** `autowrap_mode = AUTOWRAP_WORD_SMART`,
  `max_lines_visible = 2`, and `tooltip_text` mirrored with the FULL text on
  **every** write, so a long save report or refusal stays readable but can never
  push the form off a short panel. Default font size — no font-size override on a
  status row. When a warning MUST survive that two-line clamp, repeat it as the
  first row INSIDE the scrolled body (`dock_reach/reach_view.gd`'s "Scan
  incomplete" is the worked example).
- **Every `OptionButton` a PANEL TAB builds in `_init`** sets
  `fit_to_longest_item = false` and `clip_text = true`. `fit_to_longest_item`
  defaults TRUE, so one long row label (a file name, a quest id) drags the
  control's minimum width past the dock and widens the panel for everyone. Fill
  pickers through `core/picker_rows.gd` (`PickerRows.apply`), which applies both
  guards plus a readable width floor; a hand-built dropdown must set them itself.
  (`inspectors/npcdata_inspector.gd` is outside this rule on purpose — it lives in
  the Inspector dock, not the shared bottom panel, and `picker_rows.gd` records
  that it is deliberately not refactored onto these statics.)

### Disabled states and long scans

- **A button that cannot apply is DISABLED, and its tooltip names what is
  missing** — "Open a scene first", "Pick an item in the list first", "Change a
  cell first", "No backup exists yet -- Save Factions makes one". Grey it from the
  state signal (`on_scene_changed`, the editor selection, the dirty flag) BEFORE
  the click, not after it.
- **Keep the post-click message as a fallback.** A double-click on a list row, a
  keyboard activation, or a click that lands between two scene switches bypasses
  the disabled button, so the handler must still refuse in words. Share the
  literal between tooltip and status so the two can never drift
  (`placer/item_placer_dock.gd`'s `MSG_NO_SCENE` / `MSG_NO_PICK` is the idiom).
- **Long scans:** set a `Scanning...` status, disable the button, `await
  get_tree().process_frame` so the editor actually paints it, run the walk, then
  re-enable. **Every** exit path re-enables — an early `return` that leaves a
  button disabled forever is a defect, and so is an ASYNC completion with no
  watchdog (the navmesh bake reports on `bake_finished`; a scene closed mid-bake
  means that signal never arrives, so `dock_level/level_dock.gd` carries a
  timeout that releases the latch and a token so a stale timer identifies itself
  without holding a Node reference).

### Vocabulary and status grammar

A designer reads these words, not the code. Each means one thing, panel-wide.

| Word | Means | Never |
| --- | --- | --- |
| **Refresh** | Re-read a LIST from disk and rebuild it, keeping what is open BY PATH. | Never replaces or discards the open document. |
| **Reload** | Re-read AND replace the OPEN document. Asks first when there are unsaved changes. | Never silent. |
| **Scan** | Run a read-only report. | Never writes. |
| **Check** | Run a read-only report over the open scene or project (Check Navmesh, Check Reach). | Never writes. |
| **Compare** | Show the differences between two things. | Never merges. |
| **Show Graph** | Draw the open document as a graph. | Never edits. |
| **Open** | Hand a file to the Inspector, the scene editor, or the tab that edits it. | Never writes. |
| **Save `<Thing>`** | The ONE write, named for what it writes: "Save Quest", "Save Loot Table", "Save Factions (3)". | Never a bare "Save". |
| **Place / Add** | Put a node into the OPEN SCENE as one undoable step. | Nothing reaches disk until the designer saves the scene. |

Status line grammar, on the one status Label:

- **idle** — one imperative next step. "Pick an item, then Place Selected -- it
  lands in front of the camera as a world pickup."
- **done** — `<Past verb> <Name> -- <detail>.` "Saved clear_the_block.tres --
  previous version kept as clear_the_block.tres.bak."
- **refused** — `Couldn't <verb> <Name>: <plain reason>.` "Couldn't restore the
  last backup: there are unsaved changes -- Save Factions or Refresh (Discard)
  first."
- CAPITALS are reserved for verdict tokens (**OK** / **WARN** / **ERROR**) on
  report rows. Nothing else shouts.
- **No engine words anywhere a designer reads**: no `res://`, `.tres`, `uid`,
  `ext_resource`, `class_name`, `PackedScene`, `null`, `<null>`, raw error codes,
  `JSON`, or `token`. Name a file by its FILE NAME and put the full path on the
  tooltip; report a failure with `error_string(err)`.
- Every action `Button` carries a `tooltip_text` of at most two sentences: what it
  does, then whether it writes.

## Two engine facts that produced real bugs here

Both were live defects in this plugin, and neither is visible to a compile check
or to a green test suite.

### An OFF-TREE `Range` or `OptionButton` emits NOTHING on assignment

Verified in Godot 4.7: a `SpinBox` / `HSlider` that is NOT inside the tree does
**not** emit `value_changed` when `.value` is assigned, and an off-tree
`OptionButton` does **not** emit `item_selected` when `.selected` is assigned.

- **For tests:** GUT constructs every tab bare and off-tree, so a test that
  assigns a widget value and then asserts the model changed is testing NOTHING —
  it passes only because the assert is also weak. After setting the widget, DRIVE
  the handler the editor's signal would have called (`_on_chance_changed(v)`,
  `_on_type_picked(idx)`) and assert against the RESOURCE.
- **For production code:** never rely on "assigning the widget will fire my
  handler" to push a value into the model. Push the model explicitly. The
  model→widget direction uses the no-signal setters (`set_value_no_signal` /
  `set_pressed_no_signal` / plain `.text =`) so an IN-TREE push cannot re-enter the
  write path either.
- Related `Range` trap, same family: a `Range` SNAPS every value it is handed to
  `step` and CLAMPS it to `min_value`/`max_value` — on the way IN too,
  `set_value_no_signal` included. So a widget can silently misrepresent an
  authored value, and the next unrelated edit writes the misrepresentation back.
  Give each widget its OWN handler that writes only its own field, and set `step`
  / `allow_greater` so the tab can represent what the resource legitimately holds.

### `OptionButton.add_item(text, id)` treats `id == -1` as "auto-assign"

`-1` is the API's "use the item index as the id" sentinel, not a storable value.
`dialogue_editor.gd` passed `DialogueLine.END` (which IS `-1`) as that argument,
so the "End conversation" row silently carried id `1`, and picking it wrote "jump
to line 1" — a conversation that looped instead of ending. **Any `add_item(...)`
whose id can be negative is suspect:** add the row, then stamp the real id with
`set_item_id(idx, real_id)`. For anything richer than a small non-negative enum,
carry the value as row METADATA (`set_item_metadata`) or fill the picker through
`PickerRows`, which is metadata-based and refuses an unrepresentable pick instead
of guessing.

## Audit And Batch Fixes

The Audit tab is **Scan** (read-only) / **Auto** (re-scan on save, read-only) /
**Fix (N)** (the one writer) plus a **Show** filter. Its scan covers Domain A (the
open scene's config warnings + typed level checks), Domain B (a `res://` file scan
— dead group literals, missing files, dead LootTable and out-of-range dialogue
entries), Domain C (wiring — dead story flags, dangling quest/faction ids),
Domain D (the hardcoded player-facing text ratchet), Domain E (menu-sound
blindspots), Domain F (**the content check** — `ContentValidator` over the shared
`core/item_scan.gd` folder scan, the same rules the Level tab's Validate Content
runs), and the designer's own rules in `res://audit_rules/`.

Audit fixers are allowed only for mechanical, unambiguous changes.

Acceptance:

- Findings distinguish `error`, `warning`, and `info` clearly.
- Fixable findings are labeled `[fixable]` only when the fixer is deterministic.
- The Fix action previews every file/property that will change.
- The confirmation dialog has a cancel path and does not write on preview.
- **Every file Fix rewrites is copied to a `.bak` beside it FIRST** — including
  the two `.gd` rewrites, which use the `ContentSaveGuard` idiom directly
  (`DirAccess.copy_absolute` to `<path>.bak`) rather than `ResourceSaver`; the
  LootTable resave goes through `ContentSaveGuard.save_with_backup`. The
  confirmation dialog says so in words, so the sentence must stay literally true.
  A failed backup warns but does not block the fix, and a second fix of the same
  file overwrites the `.bak` (one-deep, like every other content editor here).
- Each fixer is idempotent: running it twice should not create additional
  changes.
- Ambiguous issues stay findings only.
- **The Show filter must never hide a row from the Fix plan.** Every finding
  carries a `domain` — `scene`, `content`, `code`, or `custom`; a finding with no
  `domain` key counts as `content`, so nothing a designer authored can be hidden
  by accident. The default view (**Show: Scene + Content**) hides the `code` rows
  — group-name tidy-ups in scripts, `PlayerText` literals, silent menu cues — which
  are a programmer's job and were most of what made this tab look broken to the
  designer. The filter touches ONLY the Tree: the findings list, the counts and
  the Fix plan stay UNFILTERED, `Fix (N)` still covers every row in whichever view
  is on (its tooltip says so), and the summary reports how many rows are hidden.
  A phantom "Found N problems" the designer cannot find in the list is the exact
  defect this rule exists to prevent, so the hidden count is derived from the
  filter's own decision, never recomputed by a parallel rule.
- A finding row that is not a Dictionary is dropped from BOTH the list and the
  counts — a designer's custom rule returning a stray value must not inflate the
  total.
- The hardcoded player-facing-text domain (`panel_audit/scan_text.gd`) is
  findings-only — no fixer, since moving a literal into `PlayerText` is a
  judgement change. The same scanner backs the shrink-only baseline in
  `tests/test_player_text.gd`, so any change to its paint-site regexes must
  keep that suite green.
- The menu-sound blindspot domain (`panel_audit/scan_menu_sound.gd`) is
  findings-only for the same reason: whether a refused branch wants
  `play_denied()`, a restructure, or an `EXEMPT_FUNCS` entry is a judgement
  call, and an auto-inserted cue would fire in the wrong place. It backs
  `tests/test_menu_sound_coverage.gd`, whose baseline is EMPTY and whose
  high-water mark is 0 — so any change to the nesting rule, `SUCCESS_CUES`,
  `DENIAL_CUE` or `EXEMPT_FUNCS` must keep that suite green, and the suite's
  synthetic-source tests exist to catch a "passes at zero because it stopped
  detecting anything" regression. Re-measure headlessly with
  `godot --headless -s scripts/tools/menu_sound_debt.gd`.
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
- **When many generator rows share ONE status line, every refusal NAMES the thing
  it refused.** The New tab has seventeen rows and one status Label, so a bare
  "Type a name first." leaves the designer guessing which row complained. Refuse
  in status grammar with the noun: "Couldn't create a Cutscene: its name box is
  empty -- type a name first."
- A generator that writes a PAIR of files and fails halfway rescans the editor's
  FileSystem before it refuses. Otherwise the message says "delete the stray file"
  while naming a file the FileSystem dock has not imported yet and therefore does
  not show.
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
- **Dirty state is visible, and it guards every switch.** Every write-through
  handler and every add/remove/move marks the open document dirty; a successful
  Save and every load clear it. It renders as a `*` on the Save button ("Save
  Quest\*") and "(unsaved changes)" appended to the status line. Each chokepoint
  that would SWAP the open document — a picker change, `select_path` from the
  panel, a Refresh whose rescan lost the open file — first pops the
  unsaved-changes prompt: **"Save changes to `<file>` first?" (Save / Discard /
  Cancel)**. Cancel restores the picker to the row it was on, by PATH.
- **Discard must actually discard.** A `.tres` OMITS default-valued fields, so a
  bare `ResourceLoader.load(..., CACHE_MODE_REPLACE)` re-assigns only the fields
  the file happens to carry and leaves every edit that filled in a default sitting
  on the cached instance — with the dirty flag cleared. Discard therefore resets
  the resource (and its sub-resources, CHILDREN BEFORE PARENTS) to its script
  defaults FIRST, then reloads. A file that has vanished from disk is refused
  rather than blanked.
- **`select_path(path) -> bool`** is the panel's handoff (Browse / Refs / Audit /
  New double-click, and the Blueprints scaffold). It rescans, finds the path in
  the tab's parallel path array, and opens it through the SAME dirty guard a
  picker click takes; it returns `false` off-tree (no host, no viewport for the
  dialog) so the panel falls back to the Inspector. **Rescan and picker refill
  happen in the same breath** — a dialog popped between a rescan and the refill
  leaves the widget holding the OLD scan's rows in front of the NEW array, and the
  next pick opens the wrong file.
- **After a successful Save the tab reports who USES the file**, because "it saved"
  is not the question a designer has. Quest Edit lists the scenes and resources
  that reference the quest (its start sites) and warns when there are none;
  Dialogue Edit appends "Used by N scene(s): …" or the not-attached hint. That
  walk reads every scene file, so it runs once per Save and NEVER per keystroke.
- The editor's `filesystem_changed` only RAISES a stale flag; the rescan waits for
  the tab's next reveal (never under the designer's hands, never mid-edit) and
  re-points the picker BY PATH, never by row index. Refresh is the explicit
  fallback.
- An open file that has left the folder is kept as a DISABLED trailing row in the
  picker rather than silently swapped out — the `PickerRows` anti-clobber idiom.

### Choice consequences (Dialogue Edit)

The Consequences group makes a choice able to start a quest, give an item or
money, reward reputation, and aggro the speaker. It is the seam that lets a
conversation hand out a quest at all, so its failure modes are data loss rather
than inconvenience.

- **Every field written back on edit must also be pushed on select.**
  `_write_choice()` is wired to `_c_text.text_changed` and fires on EVERY
  KEYSTROKE, so a widget that is written back without a matching
  model→widget push in `_on_choice_selected` stamps its CONSTRUCTION DEFAULT
  onto the live `DialogueChoice` the moment the designer types a character.
  `ContentSaveGuard` is one-deep, so a clobber plus one more Save loses the
  original bytes too. Check by diffing the two field lists, not by eye.
- Every push uses a no-signal setter (`set_value_no_signal` /
  `set_pressed_no_signal` / plain `.text =`). A bare `.value =` re-enters the
  write path.
- **`start_quest_on_choice` has exactly ONE writer** (`_on_start_quest_picked`)
  and is deliberately NOT assigned in `_write_choice`. It is a Resource
  REFERENCE; a keystroke in an unrelated field must never re-resolve it.
- That writer routes every branch through `PickerRows.resolve_pick`: index 0 →
  clear (the one intended clear), an out-of-range index → keep (a stale index
  from a dropdown rebuilt under a queued signal is refused, never guessed), and
  a row whose value is blank at index > 0 → keep (re-picking the
  "(inline / unsaved)" row must not wipe an in-memory quest).
- The Start-quest picker rebuilds its rows from the canonical scan BEFORE
  applying, so a transient row left over from a previously selected choice can
  never be clicked into a different choice.
- Rows are labelled by `Quest.id`, never the filename —
  `recover_the_package.tres` carries `id = "recover_package"`, and the fields
  three rows below key on the id. A filename label manufactures a silent
  runtime no-op.
- Id fields keep their LineEdit and gain a stamp picker; they are NOT converted
  to closed dropdowns. `dialogue_choice.gd` uses
  `PROPERTY_HINT_ENUM_SUGGESTION` precisely so blanks stay valid and ids for
  not-yet-authored content stay typable.
- Picking a quest surfaces the states where `QuestTracker.start_quest` returns
  SILENTLY (blank `Quest.id`, unmet `prereq_quest_id`). Without that, the tab's
  highest-value write reports success for a choice that starts nothing.
- New rows live INSIDE the tab's existing `ScrollContainer` — the bottom-panel
  TabContainer's minimum tracks the CURRENT tab and the editor's bottom splitter
  keeps the height it grew to, so a row added outside the scroller makes the whole
  panel permanently taller (see the Height and width contract). Dropdowns are
  filled through `PickerRows.apply`, which sets `fit_to_longest_item = false` +
  `clip_text` — this tab disables horizontal scroll, so an unclamped dropdown
  widens the whole editor.

### The three-site round-trip rule (Quest Edit, and every editor after it)

Quest Edit gained `auto_complete`, `expire_on_flag`, item `rewards[]` and the
per-objective marker group. Adding a widget to one of these editors is the
operation most likely to DESTROY authored data, so it has one acceptance rule.

- **Every widget must touch THREE sites.** (1) PUSH — `_load_quest` /
  `_load_obj_editor` / `_load_reward_row` copy the model into the widget.
  (2) RESET — `_clear_loaded` / `_load_*_row(null)` return it to the
  **RESOURCE's** default. (3) WRITE — the write-through handler and `_on_save`
  push it back. A widget written but never pushed persists its CONSTRUCTION
  DEFAULT over the designer's authored value, and `ContentSaveGuard` keeps only
  ONE `.bak`, so a clobber plus one more Save loses the original bytes too.
  Verify by diffing the widget list against each site, not by eye.
- **Reset to the resource default, not the widget default.**
  `_clear_loaded` restores `auto_complete` to **`true`** (`quest.gd:27`).
  "Tidying" that to `false` would silently flip every quest to self-completing
  after a failed load.
- **Every push uses a no-signal setter.** The marker is three SpinBoxes each
  writing one component of a `Vector3`, so a plain `.value =` fires three
  write-throughs.
- `_clear_loaded` must also clear the reward `ItemList` and call
  `_load_reward_row(null)` — otherwise a failed load leaves the previous
  quest's rows on screen pointed at a foreign `ItemStack`.
- `_on_save` normalizes BEFORE `save_with_backup`, then re-renders so the
  widgets show what was actually written.
- **`Quest.id` and `QuestObjective.id` are deliberately NOT editable here.**
  They are primary keys: saves key quest sections by `String(quest.id)` and
  seed progress as `progress[String(obj.id)]`, and dialogue matches them by
  value. `QuestOps.normalize` leaves them alone for the same reason, and the
  test suite pins the omission as intended rather than missing.

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

## Templates And Encounter Preview (Blueprints + Encounter Tabs)

Template and preview tools should make repeatable authored content without
secret runtime assumptions. This covers the **Blueprints** tab (multi-resource
content packs — today the Enemy Pack: Faction + Weapon+Item + LootTable +
NpcData, cross-wired) and the read-only **Encounter** preview. The Level tab's
New Level template clone follows the same refuse-overwrite rule (see Level
Tools below).

Acceptance:

- Templates list every resource and scene node they will create — Blueprints
  shows a live "Will create:" file list as the name is typed, marking any
  path that already `(exists!)`.
- Instantiation refuses to overwrite existing content unless the user chooses a
  new name/path — **Scaffold Enemy Pack** aborts before writing anything if ANY
  planned path exists.
- The result reports every created path (the Enemy Pack lists all 5 files);
  pack planning/wiring is pure (`dock_blueprint/blueprint_ops.gd`), pinned by
  `tests/test_devtools_blueprint.gd`.
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
- **SIBLING RULE — every tab that places and then SELECTS what it placed needs
  it.** Placing selects the new node so the designer can nudge it, which means the
  NEXT press would parent the new piece INSIDE the previous one (NPC inside NPC,
  wall inside floor, QuestStarter under Talkable). Each placing tab therefore
  remembers (weakly) what it placed last, and when the current selection IS that
  node the new piece goes under its PARENT — a sibling — with the status saying so
  ("beside X, under Y"). Any OTHER selection is a deliberate parent and is honoured
  unchanged. Place, Place Item and Palette each carry this guard (`_parent_for`);
  a new placing tab without one is a defect, not a nicety.
- **GROUND probe:** the four CSG blockout pieces raycast straight down from 5 m
  above the camera-focus point and land on whatever they hit (the level floor, an
  earlier slab); a miss lands the piece at height 0, the template's ground plane.
  Prefabs keep the camera-focus height, since an NPC or a door is dragged into
  place anyway. The probe reads the edited scene's `World3D` from a BUTTON
  HANDLER — that call RAISES off-tree, so it may never move into `_init`.
- Handoff: `select_path(path)` re-points the NpcData archetype dropdown after the
  New / Blueprints tabs create an archetype (`cyber_panel.editor_tab_for` maps
  `NpcData` to "Place", because "open the archetype" for a designer means "put one
  in the level").

## Component Palette (Palette Tab)

The Palette tab lists every drop-in component from `core/catalog.gd`
(searchable, grouped by category) and adds the selected one under the selected
node via **Add to selected node** (double-click also adds).

Acceptance:

- Adds go through `EditorUndoRedoManager` ("Add <name>") — undoable, and
  nothing touches disk until the designer saves the scene.
- The new node parents under the selected node (scene root when nothing is
  selected) and sets `owner` to the scene root so it persists on save.
- The Palette selects the component it just added (so the designer can configure
  it in the Inspector), which means it needs the **SIBLING RULE** exactly as the
  Place tab does: adding a second component to the same node must put it BESIDE
  the first, not INSIDE it. Its `_parent_for` mirrors `scene_placer`'s, and the
  status says "beside X, under Y" whenever the rule redirects.
- No scene open refuses with "Open a scene first, then add." and frees the
  built node — no leak, no editor error.
- `add_mode` "instance" instantiates the prefab; "child" builds the script's
  native base type and attaches the script; a missing scene/script reports
  "Couldn't build …" instead of throwing.
- The list is driven by `Catalog.COMPONENTS` — add a row there to expose a new
  component; the dock keeps no hardcoded twin list.
- Constructs off-tree — pinned by `tests/test_devtools_docks.gd`.

## Item Placer (Items Tab)

The Items tab scans `resources/items/` and drops the world object for any
authored Item into the edited scene, built by the same `WorldItem.build` the
runtime inventory drop uses — so the placement is identical to a runtime drop.
Usually that is a ready DUAL ITEM (a Throwable for carry/throw with a CanPickUp
child for loot); an Item that declares a `world_prop` instead spawns that
authored prop scene AS-IS, which may root any Node3D (the dog crate roots a
plain Node3D WRAPPING the Throwable).

Acceptance:

- **Place Selected** (double-click a row also places) is one undoable
  `EditorUndoRedoManager` action; disk changes only when the designer saves
  the scene.
- The placed subtree is owned via the shared `place_ops.own_recursive` — the
  ONE tested owner static, so the instanced-node stop-guard from the Place tab
  applies here too (pinned by `tests/test_devtools_placer.gd`).
- The build is `WorldItem.build`, identical to a runtime drop, so editor
  placement can't drift from in-game behavior (pinned by
  `tests/test_devtools_docks.gd`).
- No scene open → "Open a scene first, then Place Selected."; no selection →
  "Pick an item in the list first." One literal per guard, SHARED between the
  disabled button's tooltip and the post-click status (a double-click on a row
  bypasses the disabled button, so the click must never be silent). Status label,
  never an editor error.
- **Rows read as a designer names things**: `"<display name>  (<id>)"`, sorted by
  that label, with the file path on the ROW TOOLTIP — never a raw `res://` path in
  the row text. A **Search** field narrows the list by name, id or file name, and
  `_items` stays index-parallel with the rows currently SHOWN, so a row index is a
  valid item index even while the filter is narrowing. `select_path` clears the
  filter when it hid the row it was asked to pick.
- The dock scans `resources/items/` through the shared `core/item_scan.gd`
  (`ItemDb` is a non-`@tool` autoload and is EMPTY in-editor), lazily on first
  reveal; **Refresh** rescans and keeps the picked item BY PATH. Files that exist
  but fail to load are NAMED in the status instead of silently vanishing.
- The item drops ~3 m in front of the 3D editor camera (origin fallback) and
  is selected so the designer can fine-tune, then SAVE. Because it is selected,
  the SIBLING RULE applies: the next Place lands BESIDE it, not inside it.

## Level Tools (Level Tab)

The Level tab is one-click **New Level** / **Check Navmesh** / **Bake + Check
Navmesh** / **Validate Level** / **Validate Content**, reusing the existing
tooling (`NavMeshAudit.analyze`, the LevelRoot configuration warnings reached
through `SceneWalk.config_warnings`, `ContentValidator.run` fed by the shared
`core/item_scan.gd`) against the edited scene. The buttons say **Check**, not
"Audit", so the word "Audit" means exactly one thing in this panel: the Audit
tab. **New Level** is the one exception to the read-only rule — a PORT of
`scripts/tools/new_level.gd` that re-implements the template-clone + `LevelData`
write inline instead of calling that script.

Acceptance:

- Check and Validate buttons are read-only reporters — results render in the
  report panel; they never write.
- The three scene-bound buttons grey with "Open a scene first" from the host's
  `on_scene_changed(root)` BEFORE a click; the handlers re-read the live edited
  scene root themselves as the fallback for a click that lands between two scene
  switches. The region and the LevelRoot are found by an explicit `SceneWalk`,
  never a `get_tree()` group query (which at edit time spans the whole open
  editor scene).
- **Bake + Check Navmesh is ASYNCHRONOUS.** The bake runs on a thread, so the
  button sets "Baking navmesh... wait for the report", greys BOTH navmesh
  buttons, and the report lands when the region's `bake_finished` fires. Every
  way out releases the latch: a watchdog timeout, a scene closed mid-bake (the
  freed region is detected through `is_instance_valid`, and the timer carries an
  int TOKEN rather than the Node so a stale timer holds no dangling reference),
  and a re-press that would otherwise re-connect an identical one-shot Callable.
  A bake left "in progress" forever with two dead buttons is a defect.
- The bake mutates the OPEN scene's `NavigationMesh` — a scene mutation the
  designer persists with Ctrl+S or discards; the button itself writes no file.
- **New Level** clones `scenes/levels/LevelTemplate.tscn` to
  `scenes/levels/<name>.tscn`, writes a matching `LevelData` at
  `resources/levels/<name>.tres`, then **OPENS the new scene**, selects
  `Geometry/Blockout` (so the Place tab's blockout pieces land there) and reveals
  the level file in the FileSystem dock. The result line reports both files plus
  the next authoring steps. Creating a level and leaving the designer staring at
  the old scene was the failure this hand-off fixes.
- New Level SLUGIFIES the typed name through `ContentScaffold.slugify` (the
  same seam every Content generator uses), so "Raider Camp" becomes
  `raider_camp.tscn` / `raider_camp.tres` and the raw text is kept as the
  `LevelData.display_name`. A name with no letters or digits is refused with a
  message — designer text never reaches a `res://` path unsanitised.
- New Level REFUSES to overwrite: an existing scene OR level file under that name
  aborts before anything is written, naming the two files by their FILE NAMES
  ("Couldn't make Raider Camp: raider_camp.tscn or raider_camp.tres already
  exists -- try another name."). A half-written pair is reported the same way,
  naming the file that WAS written so the designer can delete it.
- New Level's writes are disk writes with no editor undo — but it only ever
  creates new paths, so rollback is deleting the two reported files.
- Missing region / LevelRoot / empty name refuse in status grammar — "Couldn't
  check the navmesh: `<scene>` has no NavigationRegion3D -- levels made from the
  template have one.", "Couldn't make a level: type a name for it first." — never
  an editor error. Node and script names a designer sees in the Scene dock
  (`NavigationRegion3D`, `LevelRoot`, `Geometry/Blockout`) are allowed in that
  wording; `res://` paths, `.tres`, and raw error codes are not — a file is named
  by its file name and a failure is reported with `error_string(err)`.

## Faction Matrix (Factions Tab)

The Factions tab is an N x N grid of Enemy/Neutral/Ally cells editing
`Faction.relations` (row = from, column = toward). Its action row is
**Refresh** / **Save Factions (N)** / **Restore Last Backup**.

Acceptance:

- **Editing a cell is STAGED, never committed.** This tab used to write the
  faction file on every cell change — a disk rewrite per mis-click, with no
  preview and no way to back out except renaming a `.bak`. It now follows the same
  contract as Dialogue / Quest / Loot / Text: the change goes onto the in-memory
  `Faction`, the cell and its row label tint, the Save button counts it
  ("Save Factions (3)"), the status carries "(unsaved changes)" — and **NOTHING
  reaches disk until the designer presses Save Factions**. Any bullet or hint
  claiming a cell edit saves the file is stale and must go.
- **Save Factions** writes each DIRTY faction through
  `ContentSaveGuard.save_with_backup` (prior bytes → `<path>.tres.bak` first, a
  one-deep on-disk undo) and NAMES every file it changed. It is greyed with
  "Change a cell first." when nothing is staged.
- **Restore Last Backup** is the explicit undo for a mistaken Save: it copies each
  faction's `.bak` back over its file and rebuilds the grid. It is a disk write,
  labelled as one on its tooltip, greyed with "No backup exists yet -- Save
  Factions makes one." until a `.bak` exists, and REFUSED while there are unsaved
  changes ("Save Factions or Refresh (Discard) first.") — restoring under staged
  edits would silently mix disk and memory.
- **Refresh** asks before rebuilding while there are unsaved changes (Save /
  Discard / Cancel); Discard re-reads each dirty faction from disk INTO the cached
  instance, so the Inspector sees the disk state too. The editor's
  `filesystem_changed` only raises a stale flag — the rescan waits for the next
  reveal, and is KEPT (never applied) while anything is unsaved, because a rebuild
  drops the staged cells.
- **The shared-cache caveat is deliberate and must stay visible.** The staged edit
  lives on the SAME cached `Faction` the Inspector and every other tab hold, so an
  unsaved cell change IS visible in the Inspector and a Ctrl+S there persists it.
  The dirty count on Save and the "(unsaved changes)" suffix exist precisely so the
  designer always knows something is pending.
- A failed save reports the failure by file name with `error_string(err)` on the
  status label, never silently.
- Storage matches runtime exactly: `Faction.relations` keyed by the OTHER
  faction's `id` -> float score (Enemy -1 / Neutral 0 / Ally +1, read by
  `Faction.relation_to`); a Neutral edit ERASES the key so the file stays clean.
  Pinned by `tests/test_devtools_faction.gd`.
- The dock edits ONLY `relations` — never `id`, `display_name`, or
  `default_disposition`. The idle status says where the OTHER hostility switch
  lives (whether a faction attacks the PLAYER is `Faction.default_disposition` in
  the Inspector), because that is the switch designers reach for here by mistake.
- Diagonal (self) cells are disabled Ally with a tooltip saying so; zero factions
  under `resources/factions/` shows an in-grid "No factions yet." row, not an
  error. A file that enumerates but does not load as a `Faction` is NAMED in the
  status ("skipped: …") instead of silently vanishing from the grid.
- **The grid is the one deliberate exception to the horizontal-scroll rule** — it
  keeps `horizontal_scroll_mode` AUTO, because clipping an N × N matrix would hide
  whole factions. Its cells drop `fit_to_longest_item` and carry a width floor
  instead, so the columns stay uniform.

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

## AI Bridge (Bridge Tab) + the `cyber` CLI

Two surfaces that let an external AI client read this project. They are
deliberately split by what needs the live editor:

- **`scripts/tools/cyber.gd`** — a headless read-only CLI over the plugin's PURE
  modules. Seven verbs (`catalog`, `audit`, `refs`, `graph`, `balance`, `list`,
  `describe`). Needs no editor. Writes nothing.
- **The Bridge tab** — an OPT-IN localhost command server for the three things
  that are impossible headless: refreshing the editor's FileSystem cache after an
  external write, reading the open scene / selection, and revealing a resource.

`tools/mcp/cyber_mcp.py` is a zero-dependency stdio MCP server exposing all ten
as tools. It imports nothing outside the Python standard library on purpose — no
`mcp` package, no SDK version to drift.

Acceptance — the CLI:

- Payload is framed between `<<<CYBER-JSON` and `CYBER-JSON>>>` sentinels.
  Godot's banner and ~20 UI autoloads print into stdout, so an unframed parse is
  not merely fragile, it is wrong. `--out=<abs>` writes the JSON to a file and
  the sentinels then carry only a summary — so a caller always parses the same way.
- Exit code: 0 all-ok, 1 at least one verb returned `ok:false`, 2 usage error.
- Every verb degrades to `{"ok": false, "error": "..."}` — an unknown verb or a
  missing required argument is never a crash and never a stack trace.
- It NEVER writes a project file and never runs `--import`. Read-only means the
  tool cannot damage the project even when driven by an AI that misunderstands it.
- Modules are reached by RUNTIME `load()`, never `preload` — a `-s` script's
  compile chain runs before autoloads register, so a compile-time preload of
  anything touching `ItemDb`/`GameSettings` fails at boot. Same trap, same fix as
  `validate_all.gd:31-39`.
- A batch (`--batch=<abs .json>`) runs many verbs in ONE boot. This matters: a
  headless boot on this project measures ~7.6s, so five separate calls cost ~38s
  and one batch costs ~15s. Prefer batching.
- `cyber audit` and `validate_all` must not disagree — both call the SAME
  `scan_disk` / `scan_text` scanners rather than reimplementing them. Verified
  agreeing at disk=5 / text=0. Note `cyber audit` also runs Domain E
  (menu-sound) which `validate_all` does not, and does NOT cover navmesh, which
  `validate_all` does. Neither is a superset of the other; `validate_all` remains
  the CI gate.

Acceptance — the Bridge tab:

- **OFF by default.** The server never auto-starts; the user presses Start. The
  tab shows an unmistakable listening/not-listening state, the port, and the
  handshake path, so a glance answers "is a port open right now?".
- Binds `127.0.0.1` EXPLICITLY. Godot's `TCPServer` default binds all
  interfaces — leaving it unset would put a command port on the LAN. Do not
  "simplify" the bind address away.
- Token-gated: a random `Crypto`-generated token in
  `res://.godot/cyber_bridge.json` (gitignored via `.godot/`, so it can never be
  committed) alongside the port and owning pid. A request with a wrong token is
  refused.
- One connect / one line / one response / close per call. No persistent
  connection, no heartbeat, no reconnect — which deletes the whole stale-listener
  bug family rather than managing it.
- On a busy port it FAILS LOUDLY and stays off. It must never silently fall back
  to port+1: the external proxy would then talk to a dead listener forever (a
  real reported bug in comparable Unity/Unreal bridges).
- `poll()` never blocks the editor; a peer that has not sent a full line is
  dropped on a short deadline.
- `_exit_tree` stops the server and deletes the handshake file. The user toggles
  this plugin off/on after every plugin script edit — dozens of times a day — so
  an unpaired listener strands the port and the next Start fails.
- All three tools are READ-ONLY with respect to project content. `godot_fs_sync`
  refreshes the editor's cache; it does not write resources. Placement, baking
  and any mutation are deliberately NOT exposed yet.

Acceptance — the MCP proxy:

- stdout is protocol-sacred: ONLY JSON-RPC responses. Every log line goes to
  stderr. One stray `print` corrupts the stream and hangs the client.
- A JSON-RPC notification (a request with no `id`) gets NO response, ever. That
  is the single most common way a hand-rolled MCP server hangs.
- `python tools/mcp/cyber_mcp.py --selftest` prints the resolved environment and
  the tool table to STDERR and exits 0. Run it after touching either transport.
- Registered in `.mcp.json` at the Claude Code project root (`C:\Users\dalla\3D
  RPG\`), which is OUTSIDE this git repo — so it holds machine-specific absolute
  paths and is not version-controlled. `CYBER_GODOT` / `CYBER_PROJECT` override them.

## Verification

Before calling a plugin slice done:

- Run the narrowest relevant tests or scene/resource harness. A widget test must
  DRIVE the handler, not just assign the widget — off-tree, `Range` and
  `OptionButton` emit nothing on assignment, so an assign-and-assert test is
  testing nothing (see Two engine facts, above).
- Toggle the plugin off/on in Project Settings after editing plugin scripts.
- Manually smoke the changed editor path when practical.
- Run `rg` for moved/renamed paths or symbols.
- Run `git diff --check`.
- Summarize docs impact in the final response.

## Reach (player-reachability report)

The **Reach** tab walks the real boot chain — `project.godot`'s main scene →
the menu scenes → `game.tscn` → its `LevelData` → that level — and reports what
a PLAYER can actually get to. It exists because every other check stays green on
a quest nothing starts: Stats asks "is it referenced?", the Audit asks "do its
ids resolve?", and a perfectly-authored unreachable quest passes both.

Acceptance:

- **An empty or all-green report is a FAILURE, not a pass.** It means the
  folder-scan exclusion over-fired and swallowed the real orphans. This project
  has a scar exactly here — `text_debt.gd` read `TOTAL: 0` while 132 of 267
  `PlayerText` strings were unauthored placeholders. Diff a Rescan against the
  hand-verified ground truth below before believing a clean result.
- Ground truth as of 2026-08-14, which the report must reproduce:
  `resources/quests/clear_the_block.tres` is referenced by NOTHING project-wide;
  `recover_the_package.tres` has a `QuestStarter` only in
  `scenes/levels/SliceTestLevel.tscn`, and `SliceTestLevel.tres` is itself
  referenced by nothing — so it is NOT in the boot chain. Neither quest is
  player-reachable today.
- The status line reports what was SCANNED as well as what was FOUND — files
  scanned, files walked, boot roots, folders loaded whole, unreadable files,
  unmatched start sites — so "0 problems out of 0 things looked at" and "0
  problems out of 378 things looked at" can never read the same. When a
  denominator is degenerate it LEADS with "Scan incomplete".
- **That warning is repeated as the first row INSIDE the scrolled body.** The
  status Label is clamped to two lines (the panel-wide contract), so on a narrow
  panel it is the one control that gets squeezed — the warning has to survive
  that. Any tab whose most important message could be the one that gets clipped
  owes the same treatment.
- Double-clicking a row whose file is a scene OPENS that scene in the editor
  (`open_scene_from_path`), so the designer lands in the level that holds the
  starter; any other file opens in the Inspector / script editor. Both then reveal
  the file in the FileSystem dock. Those are the only editor calls in the file and
  they write nothing.
- `rescan()` is public because the Quest / Dialogue tabs' **Check Reach** buttons
  call it after `Host.show_tab(self, "Reach")` — the same routine the Scan button
  and the lazy first reveal run, so there is no second code path to drift.
- **It never materialises the project.** `closure()` takes a `text_of` Callable
  and pulls text only for the paths its BFS pops. A `{path: text}` map of the
  tree is a memory bomb — `RefScan.SCANNED_EXTS` includes `"res"` and
  `addons/text_to_speech/voices/` alone is ~59 MB of `.flitevox.res`, and Godot
  Strings are UTF-32 internally. This tab drops `"res"` from its ext list: a
  binary voice blob carries no `res://` edges.
- **It must NOT call `ScanCache.begin()` / `end()`.** That singleton has ONE
  window; a Reach `end()` landing inside an Audit window would wipe the audit's
  cache. Pass `ScanCache.text_of` directly — it is read-through when no window
  is open, which is the correct standalone default.
- The ext_resource id regex is anchored (`\bid="`). Godot writes
  `uid="uid://…"` BEFORE `id="…"`, and the literal `id="` occurs inside `uid="`
  — an unanchored pattern takes the leftmost match and keys every row by its
  uid, so `ExtResource("9_quest")` resolves to `""`, `LevelData.scene` never
  resolves, and the level roster comes back empty. The tab degrades to a wrong
  verdict that still LOOKS like a finding, which is worse than crashing.
- Read-only: the tab writes no file.
- Height-bounded body in a `ScrollContainer`, head/status outside; lazy first
  reveal behind `_revealed` + `_on_visibility_changed`.

## Scene Diff (Scene Diff Tab)

A READ-ONLY structural comparison of two scene files, for "what did this scene
edit actually touch?" without eyeballing the raw text. The designer's flow, which
the idle status spells out: before a risky edit, duplicate the scene in the
FileSystem dock; afterwards put the copy in **Before** and the edited scene in
**After**, then **Compare**.

Acceptance:

- The two fields are named **Before** and **After** — not "A"/"B", not "left"/
  "right". Each has a **Use Selected** button that fills it from the FileSystem
  dock selection (selecting two scenes fills both at once), and After also has
  **Use Open Scene**, which fills it from the scene currently open in the editor.
- **Use Open Scene** is greyed with "Open a scene first" from the host's
  `on_scene_changed(root)` BEFORE the click, with the post-click refusal kept as
  the fallback.
- The tree lists nodes NEW in After, GONE in After, and CHANGED (type or
  properties), with the per-property differences under each changed node.
  Double-clicking a row opens the scene that holds that node and selects the node.
- It never merges and never writes; a missing, unreadable or identical path fails
  soft with a refusal in status grammar, never an editor error. Pinned by
  `tests/test_devtools_scenediff.gd`.
- Rows and statuses name files by their FILE NAME with the full path on the row
  tooltip. The two path FIELDS do show a path, because that is the field's value —
  the designer fills them from the FileSystem dock, never by typing.
- The deciding is pure (`dock_scenediff/scene_diff.gd`), including the refusal
  wording and the row labels (`plan_selection` / `field_problem` /
  `compare_refusal` / `node_label`), so what the designer reads is unit-tested
  without an editor.

## Editor Toolbar (Play From Spawn)

Two buttons added to the 3D viewport toolbar: **▶ Play** (the project's main
scene) and **▶ Play From Spawn** (writes the SELECTED `PlayerSpawn`'s `entry_id`
where `GameRoot` consumes it once, then plays), so a designer can iterate on one
area without walking there.

Acceptance:

- **Play From Spawn is DISABLED until a `PlayerSpawn` is selected**, and its
  tooltip says what is missing ("Select a PlayerSpawn in the scene to enable…").
  It used to look live at all times, and with nothing selected its only feedback
  was a `push_warning` into the Output dock — which a designer does not watch, so
  the click looked like it had launched the game and then nothing happened. The
  enabled state is driven by the editor's `selection_changed`, connected on
  `_enter_tree` and RELEASED on `_exit_tree` (the editor reloads plugins on every
  script change; an unreleased connection leaks one per reload).
- **Every refusal goes to the editor TOASTER** (the transient banner over the
  viewport), never only to the Output dock; `push_warning` stays as the
  headless / no-toaster fallback. Refusals return WITHOUT launching, so the
  designer never watches the game boot at the wrong place and wonders why. A
  spawn with a blank `entry_id` still launches but SAYS it is the level's default
  arrival, so an identical-to-Play run does not read as a broken button.
- The Play tooltip NAMES the main scene by reading `application/run/main_scene`
  back from `ProjectSettings` rather than hardcoding a filename — it once said
  "game.tscn" long after the setting had changed, so the button was right and the
  label lied.
- The selection read tests `is_instance_valid(n)` BEFORE `n is PlayerSpawn`. The
  editor's selection can still hold a node freed under it (a scene closed between
  the signal and the read) and `is` on a freed instance HARD-CRASHES the editor —
  validity FIRST, always.
- Every `EditorInterface` call sits behind `Engine.is_editor_hint()` so the whole
  control is constructed bare and its handler driven off-tree by
  `tests/test_devtools_toolbar.gd`.
