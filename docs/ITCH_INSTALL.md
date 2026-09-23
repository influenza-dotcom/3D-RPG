# CYBERSUNDAY — itch.io install instructions

Paste-ready copy for the itch.io page's "Install instructions" field (and the top of the
description, if you want the requirements visible before the download button). Everything below
describes the `Windows Desktop` preset in `export_presets.cfg` — if that preset changes, change
this too.

---

## Install (Windows)

1. **Download** `CYBERSUNDAY-win64.zip`.
2. **Extract it** to a real folder — right-click → *Extract All…*, somewhere like
   `C:\Games\CYBERSUNDAY` or your Desktop. **Do not run the game from inside the zip.** Windows
   opens a zip like a folder, but double-clicking the `.exe` there copies only that one file to a
   temp directory and the game will fail to start.
3. **Run `CYBERSUNDAY.exe`.**

There is no installer. Nothing is written to Program Files or the registry.

### Keep all four files in the same folder

| File | What it is |
| --- | --- |
| `CYBERSUNDAY.exe` | The game. This is the one you run. |
| `CYBERSUNDAY.pck` | Every asset in the game. Without it, the game will not start. |
| `libgodot_text_to_speech.dll` | The voice extension. Without it, the game will not start. |
| `CYBERSUNDAY.console.exe` | The same game with a console window attached. You only need this if you are reporting a bug — see *Troubleshooting*. |

### "Windows protected your PC"

This build is not code-signed, so Windows SmartScreen will warn about it the first time.
Click **More info → Run anyway**. Some antivirus tools also quarantine unsigned indie builds on
sight; if the `.exe` vanishes after extracting, restore it and add the folder to your exclusions.

## Requirements

- **Windows 10 or 11, 64-bit.**
- A GPU that supports **Direct3D 12** — the game renders through D3D12 by default. Anything from
  roughly 2016 onward qualifies; keep your graphics drivers current.
- **Keyboard and mouse.** Controllers are not supported yet.
- About **[FILL IN] GB** of disk space once extracted. *(Fill this from the actual export — the
  zip and its extracted size are both worth listing, since the download is compressed.)*

## First launch

The game opens in **exclusive fullscreen** at your desktop resolution and starts in the computer
room, which hosts the start menu. Prefer a window? **Options → Video → Window Mode** offers
*Windowed*, *Borderless Fullscreen*, and *Exclusive Fullscreen*. In-game, **Esc** opens the same
menu. Movement is `WASD`, look is the mouse, `F` interacts — every binding is listed and
rebindable under **Options → Controls**.

## Where saves and settings live

Paste this into the Explorer address bar:

    %APPDATA%\Godot\app_userdata\CYBERSUNDAY

You'll find the autosave (`gamestate.cfg`), the quicksave, the three manual save slots, your
settings (`settings.cfg`), and the `logs\` and `crash_reports\` folders.

**Updating to a newer build:** extract the new zip over the old folder (or into a fresh one).
Saves live in the AppData folder above, not next to the game, so they survive either way.

**Uninstalling:** delete the folder you extracted. To remove your saves and settings as well,
delete the AppData folder above.

## Troubleshooting

**The game closes instantly, or nothing happens.** Check that all four files from the table above
are sitting next to each other — a partial extract is the usual cause. Then run
`CYBERSUNDAY.console.exe`: it keeps a window open with the engine's output, and whatever it prints
before closing is the answer. The same text is saved to `logs\godot.log` in the AppData folder.

**Black screen, driver crash, or a GPU that dislikes D3D12.** Try the Vulkan renderer: make a
shortcut to `CYBERSUNDAY.exe`, open its Properties, and add ` --rendering-driver vulkan` to the end
of the Target field, then launch from the shortcut.

**A crash report card appears when you relaunch.** That's intentional — the game noticed the
previous run died and wrote a report for you. **Copy report** puts it on the clipboard,
**Open report folder** shows the file, and **Report online** opens the issue tracker. Pasting that
report into a bug report tells me the build, your GPU, what the game was doing, and the errors that
led up to it.

**Anything else:** https://github.com/influenza-dotcom/3D-RPG/issues
