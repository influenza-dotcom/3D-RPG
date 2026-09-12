# Contributing to CYBERSUNDAY

This is the setup-and-process guide for a person joining the project: an artist, writer, level
designer, sound designer, or programmer. It covers getting a working copy, how changes are
proposed and merged, and the handful of house rules that bite newcomers. Everything about
*making* content lives in the [authoring guide](docs/AUTHORING_GUIDE.md); start there once the
project runs.

## 1. Set up a working copy

Do these **in this order**. Step 1 and step 3 are not optional and cannot be done late.

1. **Install Git LFS, then clone.** Run `git lfs install` once, then clone. Textures, models and
   sounds live in LFS. If you clone first, every one of them arrives as a 130-byte pointer file.
   **Do not open the project on pointer files.** Godot imports the pointers, rewrites every tracked
   `.import` file to `valid=false`, and pulling LFS afterwards does not undo that. If it already
   happened: `git lfs pull`, then `git checkout -- '*.import'`, then reopen. Never commit those
   rewritten `.import` files.
2. **Install Godot 4.7** (the standard build, not the .NET one) from
   [godotengine.org/download](https://godotengine.org/download). CI runs 4.7.1; any 4.7.x is fine.
   Put the executable on your `PATH` as `godot`, or make a `godot.cmd` wrapper that is. The test and
   validate scripts below call a bare `godot`.
3. **Install Blender 5.2 and point Godot at it before the first import.** Editor → Editor Settings →
   FileSystem → Import → Blender → *Blender Path*. Four models are `.blend` files and Godot
   imports them by running Blender. Without it the first import stops early, no uid cache is written,
   and nothing runs or tests.
4. **Open `project.godot`** and let the first import finish. It takes a few minutes and creates a
   `.godot/` cache of about 1.6 GB. Budget roughly 4.5 GB on disk for the whole working copy.
5. **Enable the editor plugin** if it is not already on: Project → Project Settings → Plugins →
   *CYBER SUNDAY Tools*. It adds a bottom panel with the content editors the authoring guide refers to.
6. **Press F5.** The game boots into the computer-room intro that hosts the start menu. Start a
   **New Game** to see the shipping level. A saved game boots into the saved level, so if you change
   which level is the boot level and see no difference, that is why.

Windows note: the project path may contain a space. If a bare `godot --headless --path .` ever
fails silently, call the executable by its full quoted path instead.

## 2. Which documents to trust

| Read this | For |
| --- | --- |
| [README.md](README.md) | Overview, controls, project layout, common workflows |
| [DESIGN.md](DESIGN.md) | What the game is, the scope fence, and the ranked writing backlog |
| [docs/AUTHORING_GUIDE.md](docs/AUTHORING_GUIDE.md) | Every content task, field by field. Read "Your first 10 minutes" first, then use the Contents |
| [docs/SLICE_TEST_LEVEL_GUIDE.md](docs/SLICE_TEST_LEVEL_GUIDE.md) | A start-to-finish worked example of building a level with a quest and dialogue |
| [docs/CURRENT_ARCHITECTURE.md](docs/CURRENT_ARCHITECTURE.md) | System contracts and the save model (programmers) |
| [docs/CYBER_SUNDAY_PLUGIN_QA.md](docs/CYBER_SUNDAY_PLUGIN_QA.md) | Required checks before editing the editor plugin (programmers) |
| [ATTRIBUTION.md](ATTRIBUTION.md) | Third-party asset provenance. Add a row for anything you bring in |

Treat with care:

- `CLAUDE.md` is written for AI coding agents, not people. The house rules in it are repeated below.
- `REMEDIATION_PLAN.md` and `ARCHITECTURE_REVIEW.md` are working plans. Sections marked as history are
  history. Do not pick up a task from them without checking with the owner.
- The "Shipping-level content reachability" block at the end of `docs/CURRENT_ARCHITECTURE.md` is a source
  audit; nothing in it was verified by running the game.
- `docs/SYSTEM_MAP.md` is generated. Do not edit it by hand.

## 3. How changes get in

- **Work on a branch, open a pull request.** The owner works directly on `main`; contributors do not.
  Name branches by area: `content/market-district`, `writing/barks-raiders`, `fix/door-prompt`.
- **Keep pull requests small and single-purpose.** One level, one quest chain, one asset batch.
  Large scene files do not merge, so two people editing the same `.tscn` or `.map` at once will lose
  work. Say which level you are editing before you start.
- **CI runs on every pull request**: the unit suite, the content validator, and a short soak that
  boots a real level. A red run blocks the merge. Section 5 explains what content can trip it.
- **Commit only the paths you changed.** Do not `git add .` or `git add -A`. The owner often has
  unfinished scene edits in the tree, and other people's half-done work may be there too.
- **Never push to `main`, never force-push, never rewrite history.**
- **Write commit messages that say what changed for a player or a designer**, not which files moved.

What to commit and what not to:

| Commit | Do not commit |
| --- | --- |
| Your `.tscn`, `.tres`, `.map`, `.gd` changes | `.godot/` (ignored) |
| The `.gd.uid` sidecar next to every new script | `build/` — your local export output (ignored; only its `.gdignore` is tracked) |
| `export_presets.cfg` when you change the build recipe (filters, includes) | `.godot/export_credentials.cfg` (signing secrets — ignored with `.godot/`) |
| The `.import` sidecar next to every new asset | `*.tres.bak` recovery files (ignored) |
| A new row in `ATTRIBUTION.md` for any asset you brought in | `.import` files that Godot rewrote on a pointer checkout |
| | TrenchBroom autosaves under `maps/autosave/` (ignored) |

Binary assets: `.png`, `.jpg`, `.avif`, `.glb`, `.wav`, `.ogg`, `.mp3` and `.flac` go through LFS
automatically. For any other binary type, add an LFS rule to `.gitattributes` in the same pull request.

## 4. House rules

**Assets and licensing**

- Bring in only assets whose license you can name, and record the source, author and license in
  `ATTRIBUTION.md` in the same change. Nothing with a non-commercial or no-derivatives license.
  The export ships every file in the tree, so an unreferenced rip still ships.
- Keep the source file names sane: lowercase, underscores, no spaces or emoji.

**Content**

- Tune numbers in the Inspector or in a `resources/tuning/*.tres` file. If the knob you want does
  not exist, ask for it rather than editing a script.
- Player-facing text goes in an authored resource field or in `scripts/ui/player_text.gd`, never as a
  literal in gameplay code. A test enforces this with zero tolerance.
- Prefix unfinished copy with `[PH] ` so it can be found. It stays in the source until replaced, but a running
  game strips the marker from everything the player sees (a runtime `Translation` plus `PlayerText.display`), so
  look in the editor or run `text_debt`, not the screen, to find what is still unauthored.
- After adding a script or a new exported field, **Project → Reload Current Project** before
  assuming the Inspector is broken.
- Every plugin tab labels what it writes to disk in its tooltip. Read-only tabs stay read-only.
  Tabs that write make a `.tres.bak` first.
- `scripts/tools/generate_nav_links.gd` writes into the open scene the moment you run it and
  **Ctrl+Z cannot undo it.** Close the scene without saving to recover. Edit its `APPLY` constant
  to `false` for a print-only pass.
- Do not run a headless `--import` while the editor is open. Do not point Godot at the
  `.claude/worktrees/` folder if one exists in your checkout; it is not part of the project.

**Code (programmers)**

- Tabs for indentation, never spaces. `class_name` is global.
- Behaviour is a drag-drop component with `@export` config, never a branch in a big script.
- New keybinds have three name surfaces: the `[input]` map, `InputManager`, and `ActionCatalog.tres`.
  New settings need a typed field plus setter on `Settings` and a `SettingSpec` row. Details in
  `CLAUDE.md`.
- Before touching `addons/cybersunday_tools/`, read the plugin QA doc. Never rename a tool's Control
  `name`. Toggle the plugin off and on after editing it.
- Docs are part of done. If a change affects authoring, resources, saves, settings, inputs or level
  flow, update the matching doc in the same pull request.

## 5. Tests and validation

Run the fast unit suite from anywhere:

```bash
tests\run.cmd
```

Run one test file by filename prefix (much faster while iterating):

```bash
godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests -gprefix=test_level_door -gexit
```

Validate content, wiring and navmesh health without opening the editor:

```bash
scripts\tools\validate.cmd
```

Add `--strict` to fail on warnings, or a level path to audit one level. The opt-in soak suite is
`tests_soak\run_soak.cmd`; it boots a real level with wandering NPCs and takes under a minute.

Content changes that fail CI, and what to do:

- **An audio player with no bus.** Every `AudioStreamPlayer` in a scene needs its `bus` set. Never
  leave one on `Master`.
- **A raw string literal at a paint site.** Move the text to the resource field or `PlayerText`.
- **A weapon resource missing a required field.** The completeness test scans every weapon file.
  Some numeric values are pinned by tests too, so a balance pass may need a test update; say so in
  the pull request.
- **A new `@system` annotation without regenerating the system map.** Run
  `godot --headless --path . -s scripts/tools/gen_arch_doc.gd` and commit the result.
- **A dangling quest, faction or item id.** The Audit tab's wiring check finds these in the editor
  before CI does.

## 6. Debug tools you will use

All of these are on in editor and debug builds. Details are in the authoring guide under
"In-game debug tools".

| Key | Tool |
| --- | --- |
| `` ` `` | Console with about 90 commands. Type `help`. `sandbox on` first, so you do not overwrite the real save files |
| `F1` | The same commands as a clickable menu, with a search bar. Destructive rows ask twice |
| `F2` | Noclip |
| `F3` | Performance and state overlay |
| `F4` | Aim at an NPC to see its health, goal, perception and navigation state |
| `End` | Reload the current scene |

## 7. Asking for help

Open an issue or ask the owner directly. Say which level or resource you were editing, what you
clicked, and paste the Output panel text. If a tool script or plugin tab did something you did not
expect, say so even if you recovered; those are bugs in the tool, not in you.
