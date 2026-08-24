# Third-party assets

Every asset in this repo that someone else made. One row per file: where it lives, where it came from,
who made it, what licence it carries, and the date that was checked.

**This file is not decoration — it is the thing that makes shipping legal.** A row whose `License` column
still reads `UNKNOWN` is an asset that cannot ship. Nothing here has been distributed yet
(`export_presets.cfg` has never produced a build outside this machine), so this is a cleanup, not a recall.

## How to work this list

1. Work top-down within each table — the rows are ordered by how much they cost you if they are wrong.
2. For each row, find the source page, then fill `Source`, `Author`, `License`, `URL` and `Checked`.
3. If you cannot find the source, the asset must be **replaced**, not documented. Mark it `REPLACE`.
4. A `CC-BY-NC` result also means **replace** — this project is not non-commercial.
5. When a row is fully filled and the licence permits use, drop the `⚠` marker.

Sizes are bytes on disk, measured 2026-08-13. `Marker` records why the file is suspected third-party.

---

## A. Audio — known commercial tracks (remove, do not attribute)

These are commercial releases. No attribution makes them shippable; they have to go. Order matters:
purge the music folder **before** unsetting any `Radio.track`, because `radio.gd:452-456` falls through to
a folder scan when `track` is null and would shuffle whatever is left.

| ⚠ | `res://` path | Size | Apparent origin | Wired at | Action |
| --- | --- | --- | --- | --- | --- |
| ⚠ | `resources/weapons/Secret Shop.flac` | 19,387,561 | Dota 2 OST (lossless) | nothing — orphan | DELETE. Read `tests/test_devtools_browser.gd:91` first; it references this file as a non-resource that must be filtered out. |
| ⚠ | `assets/audio/music/Secret Shop.mp3` | 2,724,237 | Dota 2 OST | `scenes/game.tscn:9,51` (autoplay), `resources/levels/TestLevel.tres:4` | DELETE + rewire both |
| ⚠ | `assets/audio/music/Secret Shop v3.mp3` | 4,122,178 | Dota 2 OST | nothing — orphan | DELETE, no rewire |
| ⚠ | `assets/audio/music/Jakub's Ladder.mp3` | 3,094,625 | commercial track | nothing — orphan | DELETE, no rewire |
| ⚠ | `assets/audio/sfx/hotline_miami_lr.mp3` | 128,517 | Hotline Miami OST | `resources/tuning/PlayerFeedbackSettings.tres:8` (`death_sting`) | DELETE. Set `death_sting = null`; `death_mix.gd:275-281` documents null as inert and `tests/test_death_mix.gd:157-165` covers it. |
| ⚠ | `assets/audio/music/RIP Granny 😔🙏.mp3` | 1,436,596 | unknown, non-original | `scenes/throwable/radiothrowable.tscn:6,37` (`track`) | DELETE **last**, and **repoint** `track` — do not merely unset it (see the warning below). |
| ⚠ | `assets/audio/music/station/Shop Radio 1.mp3` | 1,543,923 | Spelunky OST (Eirik Suhrke) — **knowing placeholder**, added 2026-08-22 | `resources/tuning/StationMusicSettings.tres` (`tracks`) | REPLACE with a licensed or original shop loop, then DELETE. Clearing `tracks` makes the whole station-radio layer inert BY DESIGN, so the purge is a pure resource edit — no code change, no broken build. |
| ⚠ | `assets/audio/music/station/Shop Radio 2.mp3` | 2,252,335 | Spelunky OST (Eirik Suhrke) — **knowing placeholder**, added 2026-08-22 | `resources/tuning/StationMusicSettings.tres` (`tracks`) | REPLACE, then DELETE — as above. |
| ⚠ | `assets/audio/music/station/Shop Radio 3.mp3` | 1,675,247 | Spelunky OST (Eirik Suhrke) — **knowing placeholder**, added 2026-08-22 | `resources/tuning/StationMusicSettings.tres` (`tracks`) | REPLACE, then DELETE — as above. |
| ⚠ | `assets/audio/music/station/Shop Radio 4.mp3` | 2,755,147 | Spelunky OST (Eirik Suhrke) — **knowing placeholder**, added 2026-08-22 | `resources/tuning/StationMusicSettings.tres` (`tracks`) | REPLACE, then DELETE — as above. |

> **The radio has no CLEARED repoint target.** After the deletions above, `assets/audio/music/` contains two
> files, neither of them cleared: `569856__danlucaz__hip-hop-loop-2.wav`, itself a Freesound export that still
> needs its own row filled in (table C), and `BEST OF CORY SONG (ORIGINAL VERSION).mp3`, added 2026-08-22 and
> pinned on the trenchboom level's radio — provenance UNKNOWN, also table C. The four `Shop Radio` tracks are not a repoint target either: they are §A material
> themselves, and they deliberately live in the `music/station/` SUBFOLDER, which
> `Radio._scan_audio_folder` (`radio.gd:553-566`) cannot see — its `dir.get_files()` walk is non-recursive.
> That placement is load-bearing, not tidiness: left in `music/`, every in-world radio and every thrown
> radio-grenade would start shuffling shop themes. (`music/wander/` exists for the same reason but is
> currently EMPTY — the wandering-bed layer ships with no playlist and is inert.) So "point `track` at another track in the folder" is not
> available. `track` is a plain
> `@export var track: AudioStream` (`radio.gd:38`) and a pinned track bypasses the folder scan entirely, so it
> may point anywhere under `res://`. Either commission one original loop, or point it at a cleared clip as a
> stopgap. Also set `fallback_audio` on `scenes/components/radio.tscn` so a future designer-placed Radio with
> no track is silent rather than scanning. Note `radio.gd:460-461` can also resolve the folder to
> `Settings.music_folder` — the player's own music directory — so an unset track can pull in arbitrary user audio.

## B. Models — Sketchfab-origin GLBs

All 22 verified by a literal `Sketchfab` marker inside the binary (2026-08-13). A meaningful share of
Sketchfab models are CC-BY-NC, which this project cannot use — so treat `License: UNKNOWN` as
"probably needs replacing" until proven otherwise.

| ⚠ | `res://` path | Size | Source | Author | License | URL | Checked |
| --- | --- | --- | --- | --- | --- | --- | --- |
| ⚠ | `assets/models/call_of_duty_black_ops_cold_war_-_war_machine.glb` | 7,272,568 | Call of Duty (rip) | Activision | **NOT LICENSABLE** | — | 2026-08-13 |
| ⚠ | `assets/models/shotgun/m500_shotgun_with_silencer.glb` | 22,709,544 | Sketchfab | TODO | UNKNOWN | TODO | |
| ⚠ | `assets/models/low-poly_anzio_20mm.glb` | 1,193,440 | Sketchfab | TODO | UNKNOWN | TODO | |
| ⚠ | `assets/models/utility_knife.glb` | 1,880,900 | Sketchfab | TODO | UNKNOWN | TODO | |
| ⚠ | `assets/models/claw_hammer_low-poly.glb` | 2,876,512 | Sketchfab | TODO | UNKNOWN | TODO | |
| ⚠ | `assets/models/low-poly_welrod_mk2.glb` | 324,244 | Sketchfab | TODO | UNKNOWN | TODO | |
| ⚠ | `assets/models/coffeeshop/coffee_shop_building.glb` | 46,547,016 | Sketchfab | TODO | UNKNOWN | TODO | |
| ⚠ | `assets/models/classic_street_light_pack.glb` | 25,134,968 | Sketchfab | TODO | UNKNOWN | TODO | |
| ⚠ | `assets/models/skeleton/lowpoly_human_skeleton_rigged.glb` | 8,714,096 | Sketchfab | TODO | UNKNOWN | TODO | |
| ⚠ | `assets/models/tower_crane.glb` | 8,183,364 | Sketchfab | TODO | UNKNOWN | TODO | |
| ⚠ | `assets/models/car/old_rusty_car.glb` | 5,626,704 | Sketchfab | TODO | UNKNOWN | TODO | |
| ⚠ | `assets/models/cliff_rock_one_fbx.glb` | 3,768,900 | Sketchfab | TODO | UNKNOWN | TODO | |
| ⚠ | `assets/models/rusty_house_satellite_dish.glb` | 3,247,032 | Sketchfab | TODO | UNKNOWN | TODO | |
| ⚠ | `assets/textures/truck_container_pack_low-poly_asia.glb` | 2,866,076 | Sketchfab | TODO | UNKNOWN | TODO | (a GLB filed under `textures/`) |
| ⚠ | `assets/models/no_entry_road_sign.glb` | 2,660,188 | Sketchfab | TODO | UNKNOWN | TODO | |
| ⚠ | `assets/models/brick_shop_building__lowpoly.glb` | 2,593,380 | Sketchfab | TODO | UNKNOWN | TODO | |
| ⚠ | `assets/models/parking_meter_scan_lowpoly.glb` | 2,250,992 | Sketchfab | TODO | UNKNOWN | TODO | |
| ⚠ | `assets/models/building_crane_low_poly.glb` | 1,486,492 | Sketchfab | TODO | UNKNOWN | TODO | |
| ⚠ | `assets/models/billboard/billboard.glb` | 1,081,820 | Sketchfab | TODO | UNKNOWN | TODO | |
| ⚠ | `assets/models/dumpster/free_dumpster.glb` | 867,604 | Sketchfab | TODO | UNKNOWN | TODO | |
| ⚠ | `assets/models/psx_style_tree.glb` | 469,952 | Sketchfab | TODO | UNKNOWN | TODO | |
| | `addons/gut/old_japanese_store__lowpoly.glb` | 1,612,028 | GUT addon test fixture | GUT | vendored — see `addons/gut/LICENSE.md` | — | 2026-08-13 |

### B2. Sketchfab geometry **baked into `.tscn` files** — deleting a GLB will not remove these

The hard tail. These scenes carry no `.glb` `ext_resource` at all; the mesh data is inlined as
`sub_resource` `ArrayMesh` blocks that still carry the origin in `resource_name`
(e.g. `silenced.tscn:9` → `resource_name = "Sketchfab_Scene_Cylinder_Material_004_0"`). No binary grep will
ever find them, and replacing them means re-authoring mesh data inside the scene.

| ⚠ | `res://` path | Note |
| --- | --- | --- |
| ⚠ | `scenes/weapons/silenced.tscn` | 30 `Sketchfab` strings, 0 GLB refs |
| ⚠ | `scenes/weapons/spraycan.tscn` | 7 `Sketchfab` strings, 0 GLB refs |
| ⚠ | `scenes/player/view_model.tscn` | **the player's default gun rig** — inherits `silenced.tscn` |

> **Do not rename the `Sketchfab_Scene` node in `view_model.tscn`.** It is a hardcoded NodePath in
> `gun_mesh.gd:56,128`, `muzzle_rig.gd:28,36` and `weapon_model_swapper.gd:71-72`. The mesh may be swapped;
> the node name must survive. (The identically-named node in `grenade_launcher.tscn` is unrelated — those
> paths resolve against the gun rig, not against an equipped view-model.)

## C. Audio — attributable, keep and credit

| ⚠ | `res://` path | Apparent origin | Wired at | Author | License | URL | Checked |
| --- | --- | --- | --- | --- | --- | --- | --- |
| ⚠ | `assets/audio/music/569856__danlucaz__hip-hop-loop-2.wav` | Freesound (id 569856, user `danlucaz`) | `resources/tuning/DialogueSettings.tres:4` — dialogue music bed | danlucaz | TODO — check CC0 vs CC-BY | `https://freesound.org/s/569856/` | |
| ⚠ | `assets/audio/music/BEST OF CORY SONG (ORIGINAL VERSION).mp3` (1,294,545 B) | unknown — added 2026-08-22 from `Downloads/`. Marker: the ID3v2.4 tag carries exactly one frame, `TSSE: Lavf60.16.100` (an FFmpeg/libavformat re-encode), and every title/artist/album frame is stripped — the signature of a download-and-convert, so assume third-party until proven otherwise | `scenes/levels/trenchboom_test_level.tscn` → `Radio/Radio.track` (the in-world radio's pinned song, set 2026-08-22); **and** it sits in `assets/audio/music/`, so it is also in the folder rotation every UNPINNED `Radio` shuffles | TODO | UNKNOWN | TODO | |
| ⚠ | `assets/audio/sfx/kai_audio-computer-hum-440742.mp3` | Pixabay (id 440742) | `scenes/computerroom.tscn` — **the first thing a player ever hears** | TODO | TODO | TODO | |
| ⚠ | `assets/audio/sfx/crt_monitor_startup.mp3` | unknown | `scenes/computerroom.tscn` | TODO | UNKNOWN | TODO | |
| ⚠ | `assets/audio/sfx/crt_static_noise.mp3` | unknown | `scenes/computerroom.tscn` | TODO | UNKNOWN | TODO | |
| ⚠ | `assets/audio/sfx/NpcHurtCry.wav` | unknown — added 2026-08-18 from `Downloads/sndInspectorHurtF.wav`. Marker: the RIFF `LIST/INFO` chunk carries `ITCH: Pro Tools` and `ICRD: 2014-04-23`, and `snd<Name><State><M|F>` is GameMaker asset naming — assume a game rip until proven otherwise | `scenes/characters/enemy.tscn` → `Damage.stream` (inherited by civilian / chip_mechanic / medicine_person), `scenes/levels/SliceTestLevel.tscn` → `Damage2.stream` | TODO | UNKNOWN | TODO | |
| ⚠ | `assets/audio/sfx/NpcDeathCry.wav` | same set, from `Downloads/sndInspectorDeadF.wav` — identical RIFF markers | `scenes/characters/enemy.tscn` → `Death.death_cry` (same inheritance), `scenes/levels/SliceTestLevel.tscn` → `Death2.death_cry` | TODO | UNKNOWN | TODO | |

## D. Textures

| ⚠ | `res://` path | Apparent origin | Wired at | Author | License | URL | Checked |
| --- | --- | --- | --- | --- | --- | --- | --- |
| ⚠ | `assets/textures/Ski_trail_rating_symbol_black_circle.png` | Wikimedia Commons | `scenes/player/Player.tscn` | TODO | TODO — check the Commons file page | TODO | |
| ⚠ | `resources/weapons/seamless-cracked-asphalt-texture-J009-03.avif` (1,347,411 B) | unknown stock (slug looks commercial) | nothing — orphan | TODO | UNKNOWN | TODO | |

## E. Orphans that still ship

`export_presets.cfg` uses `export_filter="all_resources"` with empty `include_filter` and `exclude_filter`
(`:8-10`), so **every file above lands in the `.pck` verbatim whether or not anything references it.**
Until `exclude_filter` is populated, deleting a reference is not the same as removing the asset.

The worst offenders are not even third-party problems — they are size problems:

| `res://` path | Size | Referenced? |
| --- | --- | --- |
| `assets/models/dog.glb` | 409,580,280 (409 MB) | no authored reference found |
| `assets/models/weirdlittleclayguy.obj` | ~452 MB | gitignored (`.gitignore:39`), still on disk |
| the 16 Call of Duty PNG sidecars (`assets/models/` + `assets/textures/`, duplicated sets) | ~11.7 MB | none — pure orphans |

## Vendored addons (already licensed, no action)

| Path | License file |
| --- | --- |
| `addons/gut/` | `addons/gut/LICENSE.md` |
| `addons/func_godot/` | `addons/func_godot/LICENSE` |
