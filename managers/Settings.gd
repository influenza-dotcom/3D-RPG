extends Node
## @system Options Settings
## @seam Each option = a typed var + a set_* setter that applies live (DisplayServer/AudioServer/GameSettings) and re-saves settings.cfg; gameplay reads Settings.<field> directly.
## @risk A field left out of apply_all (or a setter skipping apply) persists but never takes effect on boot; nothing round-trips save->load (tests set _loaded=false).
## @risk A bus fade/duck that samples the live AudioServer bus instead of current_bus_db() ratchets volume down on rapid re-trigger — silent audio drift; every duck in the project (death world duck, dialogue, ADS) now derives its restore target from current_bus_db, so re-introducing a live-bus snapshot is the regression to watch for.
## @risk Moving a typed field into a Variant dict silently breaks gameplay's direct Settings.<field> reads and the bare-instance test that reads them.
## @risk project.godot `display/window/size/no_focus=true` makes the game window VANISH the moment apply_video enters WINDOWED (Godot's Windows DisplayServer drops WS_VISIBLE + refuses click-activation for a no_focus main window; fullscreen masks it entirely) — pinned by tests/test_windowed_mode.gd, cleared at runtime by apply_video (dev builds also warn once).
## @risk Windowed placement is measured, not assumed: apply_video fits the DECORATED frame to the screen's usable rect (largest preset that fits, else clamp — windowed_size is MUTATED to the effective size) and centres it; a frame-counted guard undoes the OS's occasional post-fullscreen restore jump. Re-centring happens only when the mode or size actually changes, so VSync/FPS/scale never yank a dragged window.
## @risk mouse_sensitivity is radians per SCREEN pixel (MouseInput reads screen_relative; `relative` is pre-scaled by canvas/window width under the viewport stretch mode, so it made look speed ride the window size). It persists under the cfg key mouse_sensitivity_screen; a pre-switch cfg carries the OLD key mouse_sensitivity in canvas-px units and read_mouse_sensitivity rescales it ONCE by LEGACY_MOUSE_SENS_SCALE (792/1920). Writing the old key again, or reading `relative` again, hands returning players a ~2.4x faster look. Since the 08-31 default retune (0.000825 -> 0.00115) a migrated legacy value no longer lands on the fresh-install default — the migration preserves the RETURNING player's feel, it does not chase the design number.
## @risk presentation decides the ROOT render target (HIGH FIDELITY = canvas_items stretch at native res, RETRO = the classic ~792x444 viewport stretch), applied by apply_video. native_scale() / render_size() are the ONLY sanctioned unit converters for pixel-unit effect knobs and screen-matching buffers, and consumers must call them LIVE per frame — caching the factor (or hardcoding 792/2.4x) breaks the mid-session toggle and re-introduces the low-res assumption this split removed.
## @test res://tests/test_settings.gd
## @test res://tests/test_difficulty.gd
## @test res://tests/test_windowed_mode.gd
## Settings — the player-facing OPTIONS layer + persistence. Distinct from GameSettings (the live
## gameplay-tuning registry of .tres resources): this autoload owns only what the Options menu can
## change and is responsible for SAVING those choices to user://settings.cfg and APPLYING each one to
## the right place — the Window/DisplayServer (video), the AudioServer buses (volume), and a few
## GameSettings.camera / .screen_shake fields (FOV, sensitivity, shake). It loads + applies on boot
## (before the main scene, since it's an autoload) so a returning player's choices are live immediately,
## and re-saves on every setter. Available from BOTH the start menu and in-game.
##
## Percentage/scale models are anchored to the AUTHORED design: at boot we capture each bus's layout dB
## and the shake/bob baselines, so a slider at 100% reproduces the mix the game shipped with rather than
## flattening it to 0 dB.

const CONFIG_PATH := "user://settings.cfg"

## Window-mode menu index -> Window.Mode. Order matches the Video tab dropdown.
const WINDOW_MODES: Array[int] = [
	Window.MODE_WINDOWED,             # 0 Windowed
	Window.MODE_FULLSCREEN,           # 1 Borderless fullscreen
	Window.MODE_EXCLUSIVE_FULLSCREEN, # 2 Exclusive fullscreen
]
## Resolution presets offered while in Windowed mode, ASCENDING. All ~16:9 — the canvas's own shape: the fit rule
## below swaps between presets when the chosen one does not fit the screen, and project.godot stretches
## "viewport"/"expand", so a preset of another aspect would change the PICTURE (more/less world), not just its size.
## The ladder is deliberately dense. It used to be six rungs starting at 1280x720, and available_resolutions() hides
## every preset whose DECORATED frame overflows the screen — so on the common 1080p monitor the Options row offered
## exactly three sizes and no native one (reported 2026-08-20). The top of the ladder stays reachable because a
## preset that only fits once the caption + borders are dropped is placed BORDERLESS — see needs_borderless().
const RESOLUTIONS: Array[Vector2i] = [
	Vector2i(640, 360), Vector2i(854, 480), Vector2i(960, 540), Vector2i(1024, 576),
	Vector2i(1152, 648), Vector2i(1280, 720), Vector2i(1366, 768), Vector2i(1600, 900),
	Vector2i(1920, 1080), Vector2i(2560, 1440), Vector2i(3200, 1800), Vector2i(3840, 2160),
]
## Audio buses exposed as volume sliders, in display order. "Master" is the implicit bus 0.
const VOLUME_BUSES: Array[StringName] = [&"Master", &"music", &"sfx", &"ambient", &"voice"]
## Fresh-install slider defaults per bus, 0..1 of the authored mix — a bus absent here ships at 1.0 (= the authored
## level). ambient ships at 0.34 (~-9.4 dB under the authored bed; the 08-31 defaults retune — the ambience sat too
## loud over dialogue/SFX out of the box). THE one answer to "what does a missing volume mean": _ready seeds
## `volumes` from it, and the bare-instance fallbacks in apply_audio / current_bus_db / get_volume / save_settings
## read it too, so an off-tree Settings.new() agrees with a fresh install instead of quietly answering 1.0.
const DEFAULT_VOLUMES: Dictionary = {&"ambient": 0.34}

const FOV_MIN := 60.0
const FOV_MAX := 120.0
const RENDER_SCALE_MIN := 0.5
const RENDER_SCALE_MAX := 2.0
## Presentation (Options -> Video): HOW the finished frame reaches the screen. Index order = the Video cycler
## (OptionsMenu._emit_presentation) — ARRAY ORDER IS BEHAVIOUR.
##  0 HIGH_FIDELITY — canvas_items stretch: the root viewport renders at the NATIVE window resolution while every
##    Control keeps laying out against the same logical ~792x444 canvas (Godot's size-2d override, so no menu
##    moves), text/vector UI rasterise crisp (per-viewport font oversampling), and 3D renders at native x
##    render_scale. The shipped default.
##  1 RETRO — the original pipeline: viewport stretch renders everything into the ~792x444 buffer and the window
##    nearest-upscales it (the chunky pixel look). Bit-identical to the pre-presentation-setting game.
## Effects with knobs authored in canvas px convert through native_scale(); buffers that must match the screen
## size from render_size(). Both must be read LIVE per frame — a cached factor goes stale on a mid-session flip
## (the cached-base_fov lesson).
const PRESENTATION_HIGH_FIDELITY := 0
const PRESENTATION_RETRO := 1
const PRESENTATION_COUNT := 2
## Mouse look range, in radians per SCREEN pixel: MouseInput reads InputEventMouseMotion.screen_relative (raw OS
## pixels), never `relative`, which the project's `viewport` stretch mode pre-scales by canvas/window width (792/1920
## = 0.41 in 1080p fullscreen, 792/1280 = 0.62 in a 720p window, 792/3840 = 0.21 at 4K — the same hand motion used
## to turn the view 1.5x further in a small window and half as far at 4K). This is the old canvas-px range
## (0.0005..0.01) re-expressed at the 1080p-fullscreen factor and rounded, so the Options slider's 1..100 readout
## (OptionsMenu remaps SENS_MIN..SENS_MAX) means what it always did — the 08-31 design default 0.00115 reads "26"
## (the pre-retune 0.000825 read "17"). Keep the SettingsCatalog.tres row's min/max the SAME numbers
## (tests/test_settings.gd pins it).
const SENS_MIN := 0.0002
const SENS_MAX := 0.004
## Canvas pixels per screen pixel at 1080p fullscreen — the scaling every pre-screen_relative sensitivity was tuned
## against (792 = the 396 px base viewport / stretch scale 0.5; 1920 = the fullscreen width). A legacy settings.cfg
## value (the OLD `mouse_sensitivity` key, canvas-px units) is multiplied by this ONCE on load, see
## read_mouse_sensitivity. A CONSTANT on purpose: it describes the historical config those values were tuned
## against, so it must not follow a later viewport/stretch change.
const LEGACY_MOUSE_SENS_SCALE := 792.0 / 1920.0
## settings.cfg [input] keys for mouse look. The unit change re-KEYED the row rather than versioning the file: the
## new key holds screen-px values verbatim, the old key is only ever READ (and rescaled) — save_settings writes a
## fresh file with just the new key, so the migration is one-shot by construction and can never compound, even if
## an older build (which knows only the old key) runs in between.
const MOUSE_SENS_KEY := "mouse_sensitivity_screen"
const MOUSE_SENS_LEGACY_KEY := "mouse_sensitivity"
const CONTRAST_MIN := 0.5
const CONTRAST_MAX := 1.5
## Colour Depth menu index -> the per-channel STEP COUNT the screen post-process snaps the finished frame to
## (`post_process.gdshader`'s `quantize_levels`). A channel lands on one of `steps + 1` values, so 31 means 32
## levels means 5 bits — the depths are named here the way the hardware named them, because "15-bit" is what a
## PlayStation framebuffer actually was and "32 steps of green" is not what anyone recognises.
##
## The unequal rows are the point of storing a Vector3 and not a second scalar: 16-bit spends its odd bit on
## GREEN (the eye resolves green detail finest, so 565 beats 555 for free), and 8-bit starves BLUE for the same
## reason (332). A single `color_steps` cannot say either, which is why this table exists rather than a range.
##
## Index 0 is Vector3.ZERO — the "leave it as authored" sentinel the shader falls back on, NOT a depth. It maps
## to the material's own `color_steps` (16 on the player's overlay, 32 on the CRT wall) — the pre-08-31 out-of-box
## frame. It is no longer the shipped default: fresh installs boot on index 4 (12-bit RGB444, the dev-authored
## look), with Authored kept as the one-click opt-out back to the untouched materials. Order = the Video dropdown,
## coarsest LAST.
const COLOR_QUANTIZE_LEVELS: Array[Vector3] = [
	Vector3.ZERO,               # 0 Authored — the material's own color_steps (the sentinel; no longer the default)
	Vector3(255, 255, 255),     # 1 24-bit    — 8 bits a channel = what the buffer already holds, i.e. off
	Vector3(31, 63, 31),        # 2 16-bit    — RGB565, the extra bit to green
	Vector3(31, 31, 31),        # 3 15-bit    — RGB555, the PlayStation's own framebuffer
	Vector3(15, 15, 15),        # 4 12-bit    — RGB444 (the shipped default since 08-31)
	Vector3(7, 7, 7),           # 5 9-bit     — RGB333
	Vector3(7, 7, 3),           # 6 8-bit     — RGB332, blue starved
	Vector3(3, 3, 3),           # 7 6-bit     — RGB222
	Vector3(1, 1, 1),           # 8 3-bit     — RGB111, eight colours; only legible BECAUSE of the dither
]
## Minimap zoom range. >1 shows FEWER metres (zooms IN); the span it divides is the author-time
## GameSettings.hud.minimap_world_span, so this stays a player-facing multiplier and never a metre count.
## SHARED WITH THE MAP TAB (map_zoom below, dividing GameSettings.hud.map_world_span instead): the two rows
## are the same kind of value on the same widget at two sizes, and one range keeps the Options sliders, the
## authored minimap_zoom_steps and both clamps describing ONE scale. Widen it and both maps widen together.
const MINIMAP_ZOOM_MIN := 0.5
const MINIMAP_ZOOM_MAX := 3.0

# --- Stored settings (defaults; seeded from the live design then overwritten by load_settings) ---
var window_mode: int = 2                       ## index into WINDOW_MODES
var windowed_size: Vector2i = Vector2i(1280, 720)
var vsync: bool = false
var max_fps: int = 144
var render_scale: float = 2.0                  ## Viewport.scaling_3d_scale — a fraction of the CURRENT presentation's render target (native in HIGH FIDELITY, the ~792x444 canvas in RETRO); _ready re-seeds 1.0 for HIGH FIDELITY
var presentation: int = PRESENTATION_HIGH_FIDELITY  ## PRESENTATION_* index: native-res canvas_items stretch (0, the shipped default) vs the classic ~792x444 viewport-stretch pixel look (1). Applied by apply_video (Window.content_scale_mode); pixel-unit effects read native_scale()/render_size() live each frame, so a flip bites without a level reload
var fov: float = 120.0                         ## -> GameSettings.camera.default_fov (the 08-31 retune — sits exactly ON FOV_MAX; _ready reseeds this from the CameraSettings script default, the true owner)
var contrast: float = 1.0                      ## post-process contrast around mid-gray; 1.0 = the authored look (read live by the player's post-process driver, like colorblind_mode)
var ink_outline_intensity: float = 0.5         ## 0..1 scale on the Borderlands-style black ink outline over the whole frame — world, NPCs and view model alike (InkOutline on the player camera). 1 = the authored line, lower FADES and THINS it, 0 = no ink (the quad is hidden, so off is free). Ships at 0.5 since the 08-31 defaults retune — half-strength line work IS the intended out-of-box look, not a degraded one. A SCALE not a bool, the ps1_warp_intensity idiom: it is an art-style dial, so half-strength line work is a real preference and not just "on or off". Lives on VIDEO rather than Accessibility because it is a look, not a comfort setting — nothing about it moves. Polled live by InkOutline each frame, so the slider bites the same frame with no level reload
var muzzle_smoke_scale: float = 0.35           ## 0..1 scale on the white barrel-smoke TRAIL a gun streams while it is hot (MuzzleSmoke, on the player's view model AND on every armed NPC's gun). 1 = the authored wisp, lower = a thinner thread, 0 = no smoke at all (the emitter never fires, so off is free). Ships at 0.35 since the 08-31 defaults retune — a thin thread out of the box, so full-auto stops smearing the reticle; 1 restores the full authored wisp. A SCALE not a bool, the ps1_warp_intensity / ink_outline_intensity idiom: it is an art-style dial AND a visibility one — the trail drifts across the reticle on full-auto — so half-strength is a real preference. Lives on VIDEO rather than Accessibility because it is a look, not a comfort setting; it does not flash and it does not move the camera. Multiplies the per-weapon WeaponData.muzzle_smoke_scale, and is polled live at each shot, so the slider bites the very next round with no level reload
var dither_strength: float = 1.0               ## 0..1 scale on the ORDERED (Bayer) DITHER the screen post-process quantises through — the retro "pattern instead of a colour band" texture over every gradient in the frame (sky, fog, lit walls, skin). 1 = the authored full-strength matrix; 0 = the same palette quantised by plain round-to-nearest, i.e. hard banding and no pattern. A SCALE not a bool, the ps1_warp_intensity / ink_outline_intensity idiom: it is an art-style dial, so a half-strength dither is a real preference. Lives on VIDEO rather than Accessibility because it is a look, not a comfort setting — nothing about it moves or flashes. The matrix SIZE (2x2/4x4/8x8) is deliberately NOT here: that is `bayer_order`, authored per material in the .tscn alongside `color_steps`, because it is a palette decision rather than a preference. Read live each frame by the player's post-process driver (player.gd _update_low_hp), like contrast / colorblind_mode, so the slider bites with no level reload
var color_quantization: int = 4                ## index into COLOR_QUANTIZE_LEVELS: how many COLOURS the screen post-process is allowed to use, per channel. 0 = Authored (the material's own `color_steps` — the pre-08-31 out-of-box frame); the rest are named colour depths, 24-bit (off) down to 3-bit. Ships at index 4 (12-bit RGB444) since the 08-31 defaults retune — the dev-authored look; a stored cfg index always wins, so only fresh installs see the change. An INDEX rather than a scale because the useful values are not a continuum: they are hardware formats, and the gap between RGB555 and RGB565 is a bit on ONE channel, not a slider position. Pairs with `dither_strength`: the quantiser decides which colours exist, the dither decides how the ones in between are faked, and at the coarse end the dither is the only thing keeping the image readable at all. Lives on VIDEO rather than Accessibility because it is a look, not a comfort setting. Read live each frame by the player's post-process driver (player.gd _update_low_hp), like contrast / colorblind_mode, so the dropdown bites with no level reload
var volumes: Dictionary = {}                   ## StringName bus -> float (0..1; 1.0 = authored level)
var music_folder: String = ""                  ## the player's OWN music folder (user:// or an OS path) for in-world radios; blank = each radio uses its curated res:// folder. Read live by Radio to override its music_folder export.
var mouse_sensitivity: float = 0.00115         ## -> GameSettings.camera.mouse_sensitivity; radians per SCREEN pixel (see SENS_MIN); _ready reseeds this from the CameraSettings script default, the true owner
var controller_look_sensitivity: float = 3.0   ## right-stick look speed (rad/s-ish), read live by MouseInput
var invert_look_y: bool = false                ## invert vertical look (mouse + controller)
var keybinds: Dictionary = {}                  ## action name (String) -> Array of serialized event dicts (rebinds only)
var screen_shake_scale: float = 2.0            ## scales GameSettings.screen_shake.intensity_multiplier. Ships at 2.0 — DOUBLE the authored shake, sitting exactly ON the setter's 0..2 clamp and the slider's ceiling (the 08-31 defaults retune)
var screen_flash_enabled: bool = true          ## off = suppress every full-screen flash pulse — a photosensitivity toggle, read live at each fire site: PlayerHud.flash_* (hurt/dash/kill), StarSky.flash_kill (on-kill sky pop), and the camera white-flash on hitscan fire (Attack; view_model_punch weapons — the fists — are exempt and never flash) / ram kill (RamReactor)
var hitstop_enabled: bool = true               ## off = player immune to the freeze-frame slow (FreezeFrame reads this live)
var colorblind_mode: int = 0                    ## post-process daltonization: 0 none, 1 protan, 2 deutan, 3 tritan
var colorblind_safe_cues: bool = false          ## recolor disposition / rep cues to a CB-safe palette (read by CBPalette)
var view_bob_enabled: bool = true               ## off = no camera/weapon head-bob (motion comfort); read live by CameraEffects/GunPose
var view_model_visible: bool = true             ## off = hide the first-person weapon (view model); read live by GunPose
var view_model_left_handed: bool = false        ## true = mirror the view model to the LEFT side; read live by GunPose
var detection_meter_enabled: bool = true        ## off = hide the crouch-gated stealth detection "heat" bar (HUD declutter); read live by PlayerHud
var loot_beacons_enabled: bool = true           ## off = hide the colour-coded item lights over world pickups / dropped loot sacks; polled live by PickupBeacon
var enemy_health_bar_enabled: bool = true       ## off = hide the top-centre enemy HP bar that pops when you damage something (HUD declutter); polled live by EnemyHealthBar
var debug_skip_menu: bool = false                ## DEBUG: boot straight into a new game, skipping the main menu
var debug_always_show_tos: bool = false          ## DEBUG: replay the first-launch Terms-of-Service gate on EVERY launch — for testing the flow without wiping settings.cfg. Independent of tos_accepted (which stays recorded); StartMenu's gate check ORs this in. Surfaced as an Options row (Game tab), unlike the one-time tos_accepted flag. Defaults OFF; enable it manually only when you need to re-test the gate.
var camera_tilt_enabled: bool = true            ## off = no strafe camera roll (motion comfort); read live by CameraEffects
var fov_effects_enabled: bool = true            ## off = no cosmetic FOV kicks (fall/rise/forward-run/sprint/air-dash); ADS zoom unaffected; read live by CameraEffects
var ps1_warp_intensity: float = 0.0             ## 0..1 accessibility scale on the PS1 vertex-warp visual effect (motion comfort); 1 = the full authored warp, 0 = off (level renders normally — the shipped default since the 08-31 retune: the wobble is opt-IN, so a fresh install boots with PS1Applier holding no material overrides at all). Polled live by PS1Applier, which re-applies/rescales/restores without a level reload
var dialogue_text_scale: float = 1.0            ## 0.75..1.5 accessibility multiplier on ALL dialogue text (spoken line, response rows, speaker name, hint — the DialogueSettings font sizes are the 1.0 baseline). A SCALE, not per-element sizes: the box-less dialogue layout re-measures itself from its fonts, so one dial keeps the hierarchy intact. Read by DialogueView._apply_type_sizes on every conversation open — no apply step, no restart
var stamina_ring_enabled: bool = true           ## ON = stamina reads as the radial ring around the crosshair (ui.gd StaminaRing); OFF = the classic bottom-left corner bar. The RING is the shipped default: stamina gates twitch verbs (sprint/dash/jump), so its readout belongs at the aim point where the eyes already are — the corner bar forces a glance away mid-fight. The bar stays as this opt-in for players who prefer a stable peripheral readout or find crosshair-adjacent motion distracting (the ring drains/refills at screen centre). Polled live by ui.gd each frame, so the Options toggle swaps modes instantly
var hud_sway_scale: float = 1.0                 ## 0..1 accessibility scale on the diegetic HUD "weight" — the corner HUD cluster trailing camera turns, rattling under screen shake, leaning against strafe velocity, floating/pressing with vertical motion, breathing scale with the dynamic-FOV kicks, and dipping on landings (ui.gd + HudSway — this ONE dial governs every channel). A SCALE, not a bool, on purpose (the ps1_warp_intensity idiom): HUD motion is exactly the class of effect the view_bob/camera_tilt/fov_effects toggles exist for, and a dial lets a sensitive player keep a hint of it instead of all-or-nothing. 1 = full authored sway, 0 = off (panel welded static + unscaled, kicks silenced). Polled live by ui.gd each frame
var hud_curve_scale: float = 1.0                ## 0..1 accessibility scale on the HUD CURVE — the corner instrument panel rendered through a barrel warp so it bows away at its edges like the inside of a curved screen (resources/shaders/hud_curve.gdshader, driven by ui.gd._apply_hud_curve). A SCALE, not a bool, for the hud_sway_scale/ps1_warp_intensity reason, and it is the same motion-comfort family: a warped panel is exactly the class of effect a sensitive player wants to dial back rather than switch off. 1 = the full authored bend (GameSettings.hud.hud_curve_amount is the ceiling), 0 = OFF and genuinely free — the SubViewport is torn down and the carrier goes back to being a plain layer child, so the HUD is the pre-curve tree rather than an identity pass. Amplitudes live on GameSettings.hud ("HUD curve"); polled live by ui.gd each frame
var hud_ghost_scale: float = 1.0                ## 0..1 accessibility scale on HUD GHOSTING — the CRT phosphor persistence behind the HUD (scripts/ui/hud_ghost.gd): moving readouts drag a soft decaying tail, and while the camera turns the whole ghost image lags a couple of pixels behind the live HUD so the screen-locked reticle participates too. A SCALE, not a bool, for the hud_sway_scale/ps1_warp_intensity reason: this is a persistence-of-vision effect and it belongs to the same motion-comfort family as view_bob / camera_tilt / fov_effects, where all-or-nothing is the wrong shape. 1 = full authored ghost, 0 = OFF and genuinely free (the offscreen accumulation pass stops rendering and the HUD is pixel-identical to a build without the feature). Amplitudes live on GameSettings.hud ("HUD ghosting"); polled live by ui.gd each frame
var lens_curve: float = 1.0                      ## 0..1 accessibility scale on the WORLD LENS — the whole rendered frame drawn through a barrel (fisheye) warp: the centre magnified, the periphery squeezed, straight lines off the centre bowing outward (resources/shaders/post_process.gdshader, pushed by player.gd). A SCALE, not a bool, for the hud_curve_scale/ps1_warp_intensity reason, and it sits in the SAME motion-comfort family for a stronger reason than either: this bends the WORLD, not a HUD panel, and peripheral distortion at a wide field of view is a known nausea contributor — so a sensitive player needs to dial it back, not just switch it off. 1 = the full authored bend (GameSettings.camera.lens_barrel_amount is the ceiling), 0 = OFF and genuinely free (the shader early-outs to a plain screen fetch, so the frame is pixel-identical to a build without the feature). Amplitudes live on GameSettings.camera ("Lens"); polled live by player.gd each frame, so the slider bites with no level reload
var world_ghost_scale: float = 1.0              ## 0..1 accessibility scale on WORLD GHOSTING — the same phosphor persistence as hud_ghost_scale, extended very faintly to the PICTURE behind the HUD (scripts/effects/world_ghost.gd): a running average of the finished frame is added back over it, so where the view moved you see a short memory of where it was. Its own dial rather than a share of the HUD one because this is a FULL-SCREEN temporal effect — the closest thing in the game to motion blur, and exactly the class of effect a motion-sensitive player turns off first, while still wanting the HUD to ghost. 1 = full authored ghost, 0 = OFF and genuinely free (the offscreen pass stops rendering and the frame is bit-identical). Amplitudes live on GameSettings.effects ("World ghost"); polled live by ui.gd each frame
var minimap_enabled: bool = true                ## OFF = hide the top-right HUD floorplan entirely AND reflow the objective tracker back to the bare 8 px inset (the enemy_health_bar_enabled / detection_meter_enabled / loot_beacons declutter family). Polled live by ui.gd each frame, so the Options toggle bites the same frame with no rebuild; hiding it also stops the widget's gather/slice/redraw completely (Minimap._process bails on is_visible_in_tree), so OFF is a real cost win and not just a hidden node
var minimap_rotates: bool = false               ## ON = HEADING-UP (the plan turns under a fixed caret); OFF = NORTH-UP (the plan is axis-locked and the caret spins instead) — the shipped default since the 08-31 retune, matching the Map tab's always-north-up frame. A BOOL rather than a dropdown on purpose: there are exactly two modes, and a generic DROPDOWN spec loses its options on an editor .tres re-save (SettingSpec's own @risk). Read live by Minimap._draw
var minimap_zoom: float = 1.5                   ## Divides GameSettings.hud.minimap_world_span, so >1 shows FEWER metres (zooms IN). Ships at 1.5 (the 08-31 retune — the corner box reads closer-in by default). Clamped MINIMAP_ZOOM_MIN..MAX. Read live by Minimap._draw — a zoom change needs no re-slice, only the view matrix moves
var map_zoom: float = 2.0                       ## The MAP TAB's own zoom (Settings-owned so it persists like any other player choice, and so the Options -> Accessibility "Map Zoom" row and the map's wheel/buttons move ONE value). Ships at 2.0 (the 08-31 retune — the tab opens on a readable district, not the whole level). Divides GameSettings.hud.map_world_span, NOT minimap_world_span — the tab is the same widget at panel size showing a district, so it must be able to move independently of the corner box. Clamped MINIMAP_ZOOM_MIN..MAX (the shared scale). Read live by MapScreen, which pushes it onto its Minimap instance's zoom_override
var minimap_show_npcs: bool = true              ## OFF = the top-right floorplan draws terrain and objective markers only, no NPC blips. ON, a living NPC within the mapped area shows as a dot tinted by allegiance (CBPalette, matching the hover name / dialogue name / enemy health bar). This is a real gameplay affordance, not just decoration — it is effectively through-wall knowledge of who is nearby — so it belongs to the player, next to the difficulty-adjacent comfort rows. Dots are CLIPPED to the box and never pinned to its rim: a pinned dot would report every body on the level and turn a floorplan into a radar. Read live by Minimap._draw
var minimap_show_stations: bool = true          ## OFF = the floorplan draws terrain, objective markers and NPC dots only — no station glyphs. ON, every Merchant / Atm / Healer / trainer / ChipInstaller / Bonfire / ChessMatch / LevelDoor with a StationMarker paints its own SHAPE (shop diamond, bank hexagon, clinic cross, trainer triangle, tech square, leisure circle, exit chevron) in MenuStyle.hud.minimap_station_color. A weaker gameplay affordance than minimap_show_npcs — a shop is a fixture, not a body, so knowing where one is leaks no tactical information — but it belongs to the player for the same DECLUTTER reason the rest of the family does: a busy market district is a lot of glyphs on a 108 px box. Read live by Minimap._draw
var minimap_show_noise: bool = true             ## OFF = the floorplan draws no noise ring. ON, a circle around the player caret shows how far your own footsteps and gunfire currently carry — Player.noise_radius, the very scalar enemy Perception.can_hear() tests against, drawn at TRUE WORLD SCALE so an NPC dot inside the ring is an NPC that can hear you. It draws sound YOU made and never sound made at you, so unlike minimap_show_npcs beside it this leaks NOTHING about anyone else — it is a mirror, not a sensor, and the row is here for DECLUTTER (a gunshot's 28 m ring covers the whole box for half a second) rather than for difficulty. ⭐The ring is a WORST CASE, not a promise: hearing is attenuated per listener through walls (NpcAiSettings hearing_wall_attenuation / hearing_occlusion) and only hostile NPCs act on it, so a body inside the ring MAY have heard you — and with hearing_initiates off nothing hears you at all while the ring still reports the radius. Read live by Minimap._draw
var clock_enabled: bool = true                  ## OFF = hide the HUD time-of-day readout under the minimap AND reflow the objective tracker back up into the space it used (the minimap_enabled / detection_meter_enabled / loot_beacons declutter family). ON by default because the day/night cycle's LIGHTING is the only other time signal and it is a poor instrument — the moon keeps midnight readable, interiors are lit around the clock, and "is the shop open yet" should not require walking outside to squint at the sun. Polled live by ui.gd each frame, so the Options toggle bites the same frame with no rebuild; hiding it also stops the widget's read/compare entirely (HudClock._process bails on is_visible_in_tree)
var clock_24_hour: bool = true                  ## ON = the clock face reads 24-hour ("14:35"); OFF = 12-hour with an AM/PM marker ("2:35 PM"). A BOOL rather than a dropdown for the minimap_rotates reason: there are exactly two faces, and a generic DROPDOWN spec loses its options on an editor .tres re-save (SettingSpec's own @risk). Read live by HudClock._process, which re-stamps immediately on a flip rather than waiting for the next in-game minute
var compass_enabled: bool = true                 ## OFF = hide the top-centre HEADING TAPE (scripts/ui/hud_compass.gd) AND reflow the whole centre-top column back up into the band it used — the enemy health bar returns to GameSettings.hud.enemy_hp_top and the stealth badge -> detection meter -> claim -> takedown/pet ladder returns to its historical offsets byte-for-byte (the minimap_enabled / clock_enabled declutter family, one column over). ON by default because it is the only PRECISE bearing readout on the HUD: on the shipped NORTH-UP minimap the tiny spinning caret is the sole other facing cue, and a player who flips Rotate Minimap to HEADING-UP loses even that (the plan turns under a fixed caret) — the tape is the one instrument that serves both modes. Polled live by ui.gd each frame, so the Options toggle bites the same frame with no rebuild; hiding it also stops the widget's camera read and marker walk entirely (HudCompass._process bails on is_visible_in_tree), so OFF is a real cost win and not just a hidden node
var tts_enabled: bool = true                    ## ON by default (2026-09-01 design call: players must HEAR an NPC when they talk to them) — barks + dialogue read aloud via the offline Flite addon on the "voice" bus; OFF = silent text only. ⭐The shipped Flite DLL used to crash every release-export QUIT (a template_debug godot-cpp build-flavour bug, rebuilt 2026-09-01 — see addons/text_to_speech/REBUILD_WINDOWS.md); the rebuilt DLL caches voices process-wide and both SpeechTts pools pin one voice per player — read the SpeechTts header before touching that seam
var heartbeat_enabled: bool = true              ## off = silence JUST the low-HP heartbeat pulse (the SFX bus volume is unaffected); read live by the player's _update_low_hp
var difficulty_level: int = DifficultySettings.Level.NORMAL  ## 0 Easy / 1 Normal / 2 Hard -> GameSettings.difficulty.apply_level (ML-3)
var auto_equip_pickups: bool = true             ## ON = a WEAPON picked up off the ground with Interact (F) is drawn immediately, but ONLY while the player is UNARMED (bare fists / equipped_item null) — an already-armed player keeps what they're holding, so a floor pipe can't swap the rifle away mid-fight (CanPickUp.start_talk -> CharacterInventory.equip_item -> the swap anim). OFF = it always just lands in the backpack. Polled live at pickup time, so a change takes effect on the very next F. Per-pickup designer veto: CanPickUp.auto_equip_weapon
## The first-launch Terms-of-Service gate: false until the player consents to the (fake, comedic) TOS the very first
## time they boot (StartMenu shows terms_of_service_screen.gd while this is false, then calls accept_tos()). Persisted
## HERE, in per-install settings.cfg, on purpose — it must survive New Game (unlike the wiped-on-new-game gamestate.cfg
## profile), so the gate shows exactly once per installation. DELIBERATELY has NO SettingSpec / Options-menu row: it is
## a one-time consent flag, not a tunable — surfacing it would let a player "un-accept" and break the fiction. (This is
## the same catalog-less-persisted-field shape as `keybinds` / `music_folder`.) Do NOT add it to SettingsCatalog.tres.
var tos_accepted: bool = false

# --- Captured baselines so percentage models preserve the authored design ---
var _base_bus_db: Dictionary = {}              ## bus -> dB from the loaded layout
var _base_shake_intensity: float = 1.0
var _loaded: bool = false
## The OS caption + border around the client area, measured the last time apply_video placed a WINDOWED window
## (DisplayServer window_get_size_with_decorations - window_get_size). It only EXISTS while windowed — fullscreen
## reports zero — so it is cached here for available_resolutions(), which the Options menu may ask while the game
## is still fullscreen. ZERO until first measured; available_resolutions then fits with a 1 px pseudo-decoration
## (so a preset EQUAL to the screen is never offered before we know the caption height) and apply_video re-fits on
## the real number the moment the mode actually switches, so a too-big pick self-heals rather than wedging.
var _decoration_size: Vector2i = Vector2i.ZERO
## What apply_video last PLACED (mode index + the fitted size), so a Video setter that changes neither (VSync, Max
## FPS, Render Scale) does not re-centre a window the player has dragged somewhere. -1 / (-1,-1) = never placed.
var _placed_mode: int = -1
var _placed_windowed_size: Vector2i = Vector2i(-1, -1)
var _warned_no_focus: bool = false

func _ready() -> void:
	_capture_baselines()
	# Seed stored fields from the live design defaults so a MISSING cfg reproduces the authored game.
	fov = GameSettings.camera.default_fov
	mouse_sensitivity = GameSettings.camera.mouse_sensitivity
	var win := get_window()
	if win != null:
		render_scale = win.scaling_3d_scale
		if not Engine.is_embedded_in_editor():
			window_mode = _mode_to_index(win.mode)  # (the editor's embedded Game window is always windowed — not the design)
	# project.godot's rendering/scaling_3d/scale (2.0) is the RETRO supersample, tuned against the ~792x444 buffer.
	# The shipped default presentation is HIGH FIDELITY, where the root target is NATIVE and that same 2.0 would
	# mean 3840x2160 3D on a 1080p screen — seed 1.0 there instead. Must live HERE, not only in the cfg reads:
	# load_settings early-returns when no cfg exists, so a fresh install never reaches the migration.
	if presentation == PRESENTATION_HIGH_FIDELITY:
		render_scale = 1.0
	for bus in VOLUME_BUSES:
		volumes[bus] = float(DEFAULT_VOLUMES.get(bus, 1.0))  # per-bus shipped defaults (ambient 0.34); 1.0 = authored level
	load_settings()
	apply_all()

## Snapshot the engine/design values the percentage sliders scale FROM (run once, before any apply).
func _capture_baselines() -> void:
	for bus in VOLUME_BUSES:
		var idx := AudioServer.get_bus_index(bus)
		_base_bus_db[bus] = AudioServer.get_bus_volume_db(idx) if idx >= 0 else 0.0
	_base_shake_intensity = GameSettings.screen_shake.intensity_multiplier

# ---------------------------------------------------------------------------------------------------
# Apply
# ---------------------------------------------------------------------------------------------------

func apply_all() -> void:
	apply_video()
	apply_audio()
	apply_input()
	apply_accessibility()
	apply_keybinds()
	apply_difficulty()

## Push the chosen difficulty into the live mults the combat/spawn/reward seams read (ML-3). Done on boot (via
## apply_all) and on every set_difficulty, so the run starts at the saved level and a change takes effect at once.
func apply_difficulty() -> void:
	GameSettings.difficulty.apply_level(difficulty_level)

func apply_video() -> void:
	var win := get_window()
	if win == null:
		return  # headless / no live window — nothing to size (settings still persist)
	# A no_focus main window cannot be played in WINDOWED mode: the Windows DisplayServer strips WS_VISIBLE and
	# answers every click with MA_NOACTIVATE, so the game silently disappears the moment it leaves fullscreen
	# (fullscreen masks it — which is how the flag survived unnoticed for months). It is one project.godot checkbox
	# (Display > Window > No Focus) away from coming back, and a release export has neither this warning nor the
	# test, so the flag is also CLEARED here (while still fullscreen — the flip only touches window styles) rather
	# than trusted: a game's main window that cannot take focus is never the design. tests/test_windowed_mode.gd
	# pins the project setting itself, so the checkbox is still caught at the source; this is the last line.
	if win.unfocusable:
		if OS.is_debug_build() and not _warned_no_focus:
			_warned_no_focus = true
			push_warning("project.godot display/window/size/no_focus is ON — the game window would vanish + refuse focus in Windowed mode; clearing it at runtime. Untick Project Settings > Display > Window > No Focus.")
		win.unfocusable = false
	# The editor's embedded Game window (Godot 4.4+ "Embed Game") is a child of the editor: it cannot change mode,
	# size or position (every such call just prints "Embedded window can't be ..."), so only the non-window
	# settings apply there; a normal Play-with-own-window run and every export take the full path.
	if not Engine.is_embedded_in_editor():
		var mode: int = WINDOW_MODES[clampi(window_mode, 0, WINDOW_MODES.size() - 1)]
		var mode_changed := window_mode != _placed_mode
		win.mode = mode as Window.Mode
		if mode == Window.MODE_WINDOWED:
			# Place only when the mode or the requested size changed — VSync / Max FPS / Render Scale go through
			# here too and must not re-centre a window the player dragged somewhere else.
			if mode_changed or windowed_size != _placed_windowed_size:
				_place_guard_retries = 0
				_place_windowed(win)
		_placed_mode = window_mode
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if vsync else DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = max_fps
	# Presentation: HIGH FIDELITY renders the root viewport at the native window size (Controls keep laying out
	# against the logical ~792x444 canvas via Godot's size-2d override, so no layout moves); RETRO restores the
	# authored viewport stretch, where the window nearest-upscales the low-res buffer. Written explicitly BOTH
	# ways so a mid-session toggle is symmetric; content size/factor/aspect stay authored in project.godot.
	# Deliberately OUTSIDE the is_embedded_in_editor() guard above: content scale is a viewport-level property
	# (like scaling_3d_scale below), not an OS mode/size/position call the embedded Game window refuses.
	win.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS if presentation == PRESENTATION_HIGH_FIDELITY else Window.CONTENT_SCALE_MODE_VIEWPORT
	win.scaling_3d_scale = render_scale
	GameSettings.camera.default_fov = fov

## Render pixels per LOGICAL canvas pixel on the root viewport — the unit converter for effects whose knobs are
## authored in canvas px (ink line widths, ghost drag offsets, dither cells): push authored_value * native_scale().
## 1.0 in RETRO (canvas px ARE render px), ~2.42 at 1080p HIGH FIDELITY. Reads the LIVE window state on every call
## — never cache it (a mid-session presentation flip or resize must bite the consumer's next per-frame poll) — and
## floors at 1.0 so headless/off-tree callers (GUT drives effect params with no real screen) degrade to the RETRO
## identity. For sizing a screen-matching BUFFER use render_size() instead: this scalar rides the x axis, and the
## flooring of the logical canvas makes the stretch slightly anisotropic, so logical*native_scale() can drift a
## pixel from the true target on y.
func native_scale() -> float:
	var win := get_window()
	if win == null or win.content_scale_mode != Window.CONTENT_SCALE_MODE_CANVAS_ITEMS:
		return 1.0
	var logical := win.get_visible_rect().size
	if logical.x <= 0.0:
		return 1.0
	return maxf(1.0, float(win.size.x) / logical.x)

## The root render-target size in pixels — what a screen-matching buffer (the ghost accumulators, the HUD-curve
## viewport) must be sized to. Exact by construction: reads the window rather than multiplying the scalar
## native_scale(), whose per-axis rounding could land a pixel off and break a "texel == pixel, filter nearest"
## 1:1 contract. Native window size under HIGH FIDELITY, the logical canvas under RETRO; headless (the dummy
## window is smaller than the canvas) and no-window degrade to the logical canvas, matching native_scale()'s
## 1.0 floor.
func render_size() -> Vector2i:
	var win := get_window()
	if win == null:
		return Vector2i(792, 444)  # the 16:9 logical canvas — off-tree fallback only
	var logical := Vector2i(win.get_visible_rect().size.round())
	if win.content_scale_mode == Window.CONTENT_SCALE_MODE_CANVAS_ITEMS and win.size.x > logical.x:
		return win.size
	return logical

## Size + place the (already WINDOWED) window so the whole decorated frame sits INSIDE the current screen's usable
## rect (work area — the taskbar excluded), centred, caption on-screen. Why this exists: a windowed_size the size
## of the monitor (the 1920x1080 preset on a 1080p screen, or a saved size from a bigger monitor) used to land the
## client area at (0,0) — title bar above the screen, taskbar over the HUD — and project.godot ships resizable=false
## + maximize_disabled, so the player had NO way to fix it except knowing to reopen Options. Rules, in order:
##  1. Decorations are measured off the live window (caption + borders differ per OS/theme/DPI, and only exist while
##     windowed AND decorated) and cached in _decoration_size for available_resolutions().
##  2. If windowed_size + decorations does not fit the usable rect, windowed_size becomes the LARGEST preset (by
##     area) that does (all presets are ~16:9, so the canvas keeps its shape); if none fits (a screen smaller than
##     the 640x360 bottom rung) it is clamped to the usable client area instead — fit_windowed_size() is that pure
##     rule. The field is MUTATED on purpose — the Options row then shows the size the player actually got, and the
##     next save persists that instead of a value this screen can't hold.
##  3. The DECORATED frame is centred in the usable rect (Window.position is the CLIENT origin, hence the inset),
##     never above/left of it, so the caption is always reachable — centred_frame_origin() is that pure rule.
##  4. EXCEPT when the size fits the physical screen only once the caption + borders are gone — the native size on
##     its own monitor. Rule 2 used to demote that to the next preset down, which is why a 1080p player had no
##     1920x1080 in Options at all (2026-08-20); it is now placed BORDERLESS and centred on the SCREEN rect, so it
##     covers the taskbar like Borderless Fullscreen does. needs_borderless() is that pure rule, and the Options row
##     captions such an entry "(borderless)" so the disappearing title bar reads as the setting, not a glitch.
## Headless / no real screen: the usable rect is zero and this is a no-op beyond the size assignment.
func _place_windowed(win: Window) -> void:
	_place_guard_until_frame = -1  # our own moves below must not be mistaken for someone else's (see the guard)
	var wid := win.get_window_id()
	var usable := DisplayServer.screen_get_usable_rect(win.current_screen)
	if usable.size.x <= 0 or usable.size.y <= 0:
		win.size = windowed_size  # headless stub — nothing to fit against, keep the plain assignment
		_placed_windowed_size = windowed_size
		return
	var screen := DisplayServer.screen_get_size(win.current_screen)
	# Read the REAL client + frame sizes off the DisplayServer (not Window.size, which is merely what we asked
	# for — Windows can shave a frame taller than the screen, and the difference would then read as decoration).
	# ONLY while the window is DECORATED: a borderless one (rule 4 below) reports frame == client, and caching that
	# zero would tell available_resolutions() that every preset fits and re-park the next caption off the screen.
	if not win.borderless:
		var client_now := DisplayServer.window_get_size(wid)
		var frame_now := DisplayServer.window_get_size_with_decorations(wid)
		_decoration_size = Vector2i(maxi(frame_now.x - client_now.x, 0), maxi(frame_now.y - client_now.y, 0))
	windowed_size = fit_windowed_size(windowed_size, usable.size, _decoration_size, RESOLUTIONS, screen)
	# A preset whose bare client fits the physical screen but whose DECORATED frame does not is placed BORDERLESS
	# rather than dropped from the list: on a 1080p monitor that is the only way 1920x1080 can be a window at all.
	var borderless := needs_borderless(windowed_size, usable.size, _decoration_size, screen)
	win.borderless = borderless
	win.size = windowed_size
	# Centre the decorated frame; the client origin is that plus the frame's top-left inset (border + caption).
	# A BORDERLESS window centres on the PHYSICAL screen rect instead of the usable one: it is allowed to cover the
	# taskbar (exactly what Borderless Fullscreen does), and centring it in the work area would push it off-screen.
	var place_rect := usable
	if borderless:
		place_rect = Rect2i(DisplayServer.screen_get_position(win.current_screen), screen)
	var frame := DisplayServer.window_get_size_with_decorations(wid)
	var inset := DisplayServer.window_get_position(wid) - DisplayServer.window_get_position_with_decorations(wid)
	var client_pos := centred_frame_origin(place_rect, frame) + inset
	win.position = client_pos
	_placed_windowed_size = windowed_size
	# Arm the placement guard only now — our own moves above notified synchronously, so they are already past.
	_place_guard_pos = client_pos
	_place_guard_until_frame = Engine.get_process_frames() + PLACE_GUARD_FRAMES
	_place_guard_until_msec = Time.get_ticks_msec() + PLACE_GUARD_MSEC

## Pure: the CLIENT size to actually use for `wanted` on a screen whose usable size is `usable` once `decoration`
## (caption + borders) is added — `wanted` itself when it fits, else `wanted` again when its bare client fits the
## physical `screen` (it then gets placed borderless, see needs_borderless), else the LARGEST preset (by area) that
## fits either way, else `wanted` clamped to the usable client area (a screen smaller than every preset).
## `screen` ZERO = "nothing measured" and disables the borderless branch, i.e. the old 4-arg rule. Tested off-tree.
static func fit_windowed_size(wanted: Vector2i, usable: Vector2i, decoration: Vector2i, presets: Array[Vector2i], screen: Vector2i = Vector2i.ZERO) -> Vector2i:
	var max_client := usable - decoration
	if wanted.x <= max_client.x and wanted.y <= max_client.y:
		return wanted
	if _fits_bare(wanted, screen):
		return wanted  # too big only because of the decorations — kept, and placed without them
	var best := Vector2i.ZERO
	for r in fitting_resolutions(presets, usable, decoration, screen):
		if r.x * r.y > best.x * best.y:
			best = r
	if best != Vector2i.ZERO:
		return best
	return Vector2i(mini(wanted.x, max_client.x), mini(wanted.y, max_client.y))

## Pure: where the top-left of a `frame`-sized decorated window goes to sit centred in `usable`, never above or
## left of it (so a frame that does not fit keeps its caption reachable rather than centring off-screen).
static func centred_frame_origin(usable: Rect2i, frame: Vector2i) -> Vector2i:
	@warning_ignore("integer_division")
	var origin := usable.position + (usable.size - frame) / 2  # pixel-integer centring is intended
	return Vector2i(maxi(origin.x, usable.position.x), maxi(origin.y, usable.position.y))

## Placement guard. Leaving EXCLUSIVE fullscreen for a window, the OS / graphics driver can shove the window back
## to its pre-fullscreen rect a beat AFTER we placed it — observed on Windows + D3D12 as a jump to the engine's
## restore rect (the 396x216 boot rect centred on screen), delivered by the first message pump after the switch,
## and only when the window was not the foreground window at that instant (a coin-flip at boot; never seen for a
## focused runtime switch). It cannot be made deterministic from here, so instead: for a short while after
## _place_windowed we watch the root's NOTIFICATION_WM_POSITION_CHANGED / WM_SIZE_CHANGED and undo a move or resize
## we did not ask for, at most PLACE_GUARD_MAX_RETRIES times per apply_video so a stubborn OS wins rather than a
## fight. The budget is FRAMES (a boot-time load stall pumps no messages at all — the jump lands on frame 0 however
## long the load took) OR MILLISECONDS (a runtime switch on a fast machine burns 5 frames in ~35 ms), whichever
## lasts longer. The re-place itself is DEFERRED, never done inside the notification: Window::_rect_changed_callback
## keeps running after it propagates the notification and would then overwrite Window.size / the root viewport with
## the stale jump size. Expired guards ignore everything, so a player dragging the window later is never touched.
const PLACE_GUARD_FRAMES := 5
const PLACE_GUARD_MSEC := 250
const PLACE_GUARD_MAX_RETRIES := 2
var _place_guard_until_frame: int = -1          ## -1 = disarmed
var _place_guard_until_msec: int = 0
var _place_guard_pos: Vector2i = Vector2i.ZERO  ## the CLIENT position _place_windowed asked for
var _place_guard_retries: int = 0

func _notification(what: int) -> void:
	if (what != NOTIFICATION_WM_POSITION_CHANGED and what != NOTIFICATION_WM_SIZE_CHANGED) or _place_guard_until_frame < 0:
		return
	if Engine.get_process_frames() > _place_guard_until_frame and Time.get_ticks_msec() > _place_guard_until_msec:
		_place_guard_until_frame = -1
		return
	var win := get_window()
	if win == null or win.mode != Window.MODE_WINDOWED:
		return
	if win.position == _place_guard_pos and DisplayServer.window_get_size(win.get_window_id()) == windowed_size:
		return
	if _place_guard_retries >= PLACE_GUARD_MAX_RETRIES:
		_place_guard_until_frame = -1
		return
	_place_guard_retries += 1
	_place_guard_until_frame = -1  # one correction per notification; _place_windowed re-arms
	_replace_windowed_deferred.call_deferred()

## The guard's correction, run from the message queue (after the engine's own rect bookkeeping has finished).
func _replace_windowed_deferred() -> void:
	var win := get_window()
	if win == null or win.mode != Window.MODE_WINDOWED or WINDOW_MODES[clampi(window_mode, 0, WINDOW_MODES.size() - 1)] != Window.MODE_WINDOWED:
		return
	_place_windowed(win)  # re-fit + re-centre (idempotent) and re-arm

## The Windowed-mode presets the Options row should offer on THIS screen: RESOLUTIONS filtered to those whose
## decorated frame fits the current screen's usable rect (the same rule _place_windowed enforces, so what the row
## offers is what the player gets once the decorations have been measured; before that — the game still fullscreen
## since boot — a 1 px pseudo-decoration keeps a preset EQUAL to the screen off the list). Falls back to the whole
## list when there is nothing real to measure against (bare instance / headless / a zero usable rect — the row must
## never be empty), and to the SMALLEST preset alone when even that does not fit (apply then clamps it; the row's
## "(custom)" entry shows the true result).
func available_resolutions() -> Array[Vector2i]:
	var all: Array[Vector2i] = []
	all.assign(RESOLUTIONS)
	var win := get_window()
	if win == null:
		return all
	var usable := DisplayServer.screen_get_usable_rect(win.current_screen)
	if usable.size.x <= 0 or usable.size.y <= 0:
		return all
	var deco := _decoration_size if _decoration_size != Vector2i.ZERO else Vector2i.ONE
	var fits := fitting_resolutions(RESOLUTIONS, usable.size, deco, DisplayServer.screen_get_size(win.current_screen))
	if fits.is_empty():
		var smallest: Vector2i = RESOLUTIONS[0]
		for r in RESOLUTIONS:
			if r.x * r.y < smallest.x * smallest.y:
				smallest = r
		fits.append(smallest)
	return fits

## Pure fit rule shared by _place_windowed and available_resolutions (unit-tested off-tree): the presets whose
## CLIENT size plus `decoration` (caption + borders) fits inside `usable` (a screen's usable size), PLUS those whose
## bare client fits the physical `screen` — those are offered as BORDERLESS windows (needs_borderless). Pass a
## `screen` of ZERO for the decorated-only rule. Order preserved.
static func fitting_resolutions(presets: Array[Vector2i], usable: Vector2i, decoration: Vector2i, screen: Vector2i = Vector2i.ZERO) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for r in presets:
		if (r.x + decoration.x <= usable.x and r.y + decoration.y <= usable.y) or _fits_bare(r, screen):
			out.append(r)
	return out

## Pure: does `size` need the caption + borders DROPPED to exist on this screen at all? True when the decorated
## frame overflows the usable rect but the bare client still fits the physical screen — the native-resolution case
## (1920x1080 on a 1080p monitor, which the decorated rule can never offer). A `screen` of ZERO is never borderless.
static func needs_borderless(size: Vector2i, usable: Vector2i, decoration: Vector2i, screen: Vector2i) -> bool:
	if size.x + decoration.x <= usable.x and size.y + decoration.y <= usable.y:
		return false
	return _fits_bare(size, screen)

## Pure: does the bare client `size` fit `screen`? A ZERO screen means nothing to compare against -> false.
static func _fits_bare(size: Vector2i, screen: Vector2i) -> bool:
	return screen.x > 0 and screen.y > 0 and size.x <= screen.x and size.y <= screen.y

## Would `size` be placed as a BORDERLESS window on the live screen (see needs_borderless)? The live-window twin of
## the pure rule, used only to caption the Options row honestly — a player picking the native size must be told the
## title bar is going away rather than left thinking the game broke. False off-tree / headless (nothing to measure).
func is_borderless_size(size: Vector2i) -> bool:
	var win := get_window()
	if win == null:
		return false
	var usable := DisplayServer.screen_get_usable_rect(win.current_screen)
	if usable.size.x <= 0 or usable.size.y <= 0:
		return false
	var deco := _decoration_size if _decoration_size != Vector2i.ZERO else Vector2i.ONE
	return needs_borderless(size, usable.size, deco, DisplayServer.screen_get_size(win.current_screen))

func apply_audio() -> void:
	for bus in VOLUME_BUSES:
		var idx := AudioServer.get_bus_index(bus)
		if idx < 0:
			continue
		var v: float = clampf(float(volumes.get(bus, DEFAULT_VOLUMES.get(bus, 1.0))), 0.0, 1.0)
		AudioServer.set_bus_mute(idx, v <= 0.0)
		if v > 0.0:
			# Authored dB + the slider in dB: 100% = base, 50% ~ -6 dB, 0% = mute. Preserves the mix.
			AudioServer.set_bus_volume_db(idx, float(_base_bus_db[bus]) + linear_to_db(v))

## The dB a bus is CONFIGURED to sit at right now — the exact value apply_audio() writes (authored base +
## the slider in dB). This is the single source of truth for a bus level, so a transient effect that ducks or
## fades a bus (e.g. the player-death audio fade) can read the target to restore to WITHOUT sampling the live
## bus, which may itself be mid-fade (sampling the live bus lets rapid re-triggers ratchet the level down).
## A muted/zeroed bus returns a deep-silence dB (its mute flag is what truly silences it, not this value).
func current_bus_db(bus: StringName) -> float:
	var v: float = clampf(float(volumes.get(bus, DEFAULT_VOLUMES.get(bus, 1.0))), 0.0, 1.0)
	return float(_base_bus_db.get(bus, 0.0)) + linear_to_db(maxf(v, 0.0001))

func apply_input() -> void:
	GameSettings.camera.mouse_sensitivity = mouse_sensitivity

func apply_accessibility() -> void:
	GameSettings.screen_shake.intensity_multiplier = _base_shake_intensity * screen_shake_scale

## Re-apply rebound actions over the project + controller defaults (runs in apply_all, AFTER InputManager
## adds its controller bindings). Each stored action's event list fully replaces that action's events.
func apply_keybinds() -> void:
	for action in keybinds:
		var sn := StringName(action)
		if not InputMap.has_action(sn):
			continue
		var events: Variant = keybinds[action]
		if not (events is Array):
			continue  # a hand-edited / corrupt config storing a non-Array for this action -> skip, don't crash at boot
		InputMap.action_erase_events(sn)
		for d in events:
			# A hand-edited / corrupt config can store a non-Dictionary entry in this action's array; skip it —
			# the typed _dict_to_event(d: Dictionary) would otherwise raise a runtime arg-type error at boot.
			if not (d is Dictionary):
				continue
			var e := _dict_to_event(d)
			if e != null:
				InputMap.action_add_event(sn, e)

## Bind `new_event` to `action`, replacing existing events of the SAME category (keyboard/mouse vs
## gamepad) so keyboard and controller rebind independently. Persists the action's full new event list.
func rebind_action(action: StringName, new_event: InputEvent) -> void:
	if not InputMap.has_action(action):
		return
	var new_is_pad := new_event is InputEventJoypadButton or new_event is InputEventJoypadMotion
	var keep: Array[InputEvent] = []
	for e in InputMap.action_get_events(action):
		var e_is_pad := e is InputEventJoypadButton or e is InputEventJoypadMotion
		if e_is_pad != new_is_pad:
			keep.append(e)
	InputMap.action_erase_events(action)
	for e in keep:
		InputMap.action_add_event(action, e)
	InputMap.action_add_event(action, new_event)
	var dicts: Array = []
	for e in InputMap.action_get_events(action):
		var d := _event_to_dict(e)
		if not d.is_empty():
			dicts.append(d)
	keybinds[String(action)] = dicts
	save_settings()

func _event_to_dict(e: InputEvent) -> Dictionary:
	if e is InputEventKey:
		return {"t": "key", "c": (e as InputEventKey).physical_keycode}
	if e is InputEventMouseButton:
		return {"t": "mb", "b": (e as InputEventMouseButton).button_index}
	if e is InputEventJoypadButton:
		return {"t": "jb", "b": (e as InputEventJoypadButton).button_index}
	if e is InputEventJoypadMotion:
		return {"t": "jm", "a": (e as InputEventJoypadMotion).axis, "v": (e as InputEventJoypadMotion).axis_value}
	return {}

func _dict_to_event(d: Dictionary) -> InputEvent:
	match String(d.get("t", "")):
		"key":
			var k := InputEventKey.new()
			k.physical_keycode = int(d.get("c", 0)) as Key
			return k
		"mb":
			var mb := InputEventMouseButton.new()
			mb.button_index = int(d.get("b", 0)) as MouseButton
			return mb
		"jb":
			var jb := InputEventJoypadButton.new()
			jb.button_index = int(d.get("b", 0)) as JoyButton
			return jb
		"jm":
			var jm := InputEventJoypadMotion.new()
			jm.axis = int(d.get("a", 0)) as JoyAxis
			jm.axis_value = float(d.get("v", 0.0))
			return jm
	return null

# ---------------------------------------------------------------------------------------------------
# Setters — each applies immediately AND persists, so the menu is pure data-binding
# ---------------------------------------------------------------------------------------------------

func set_window_mode(index: int) -> void:
	window_mode = clampi(index, 0, WINDOW_MODES.size() - 1)
	apply_video()
	save_settings()

func set_windowed_size(size: Vector2i) -> void:
	windowed_size = size
	apply_video()
	save_settings()

func set_vsync(on: bool) -> void:
	vsync = on
	apply_video()
	save_settings()

func set_max_fps(n: int) -> void:
	max_fps = maxi(0, n)
	apply_video()
	save_settings()

func set_render_scale(f: float) -> void:
	render_scale = clampf(f, RENDER_SCALE_MIN, RENDER_SCALE_MAX)
	apply_video()
	save_settings()

## Presentation (Options -> Video): an index into the PRESENTATION_* modes, clamped so a stale/hand-edited cfg can
## only land on a real mode. Applies immediately — apply_video flips Window.content_scale_mode, and every
## native_scale()/render_size() consumer re-sizes on its own per-frame poll, so the toggle bites with no reload.
func set_presentation(mode: int) -> void:
	presentation = clampi(mode, 0, PRESENTATION_COUNT - 1)
	apply_video()
	save_settings()

func set_fov(f: float) -> void:
	fov = clampf(f, FOV_MIN, FOV_MAX)
	GameSettings.camera.default_fov = fov
	save_settings()

func set_contrast(f: float) -> void:
	contrast = clampf(f, CONTRAST_MIN, CONTRAST_MAX)
	save_settings()  # no apply step — the player's post-process driver reads it live each frame

func set_ink_outline_intensity(f: float) -> void:
	ink_outline_intensity = clampf(f, 0.0, 1.0)
	save_settings()  # no apply step — InkOutline polls it each frame (the ps1_warp_intensity shape)

func set_muzzle_smoke_scale(f: float) -> void:
	muzzle_smoke_scale = clampf(f, 0.0, 1.0)
	save_settings()  # no apply step — MuzzleSmoke polls it at each shot (the ink_outline_intensity shape)

## Colour Depth (Options -> Video): an INDEX into COLOR_QUANTIZE_LEVELS, clamped so a stale index can only ever
## fall back to Authored. No apply step — the player's post-process driver pushes the levels each frame.
func set_color_quantization(mode: int) -> void:
	color_quantization = clampi(mode, 0, COLOR_QUANTIZE_LEVELS.size() - 1)
	save_settings()

func set_dither_strength(f: float) -> void:
	dither_strength = clampf(f, 0.0, 1.0)
	save_settings()  # no apply step — the player's post-process driver polls it each frame (the contrast shape)

func set_volume(bus: StringName, v: float) -> void:
	volumes[bus] = clampf(v, 0.0, 1.0)
	apply_audio()
	save_settings()

## The player's own music folder for in-world radios. Blank clears the override (radios revert to their curated
## res:// folder). Stored verbatim — a user:// path or an OS directory; Radio resolves + scans it at turn-on.
func set_music_folder(path: String) -> void:
	music_folder = path.strip_edges()
	save_settings()

## Radians per SCREEN pixel (see SENS_MIN) — the Options slider hands in this unit; the 1..100 readout is cosmetic.
func set_mouse_sensitivity(f: float) -> void:
	mouse_sensitivity = clampf(f, SENS_MIN, SENS_MAX)
	GameSettings.camera.mouse_sensitivity = mouse_sensitivity
	save_settings()

func set_controller_look_sensitivity(f: float) -> void:
	controller_look_sensitivity = clampf(f, 0.5, 10.0)
	save_settings()

func set_invert_look_y(on: bool) -> void:
	invert_look_y = on
	save_settings()

func set_screen_shake_scale(f: float) -> void:
	screen_shake_scale = clampf(f, 0.0, 2.0)
	apply_accessibility()
	save_settings()

func set_hitstop_enabled(on: bool) -> void:
	hitstop_enabled = on
	save_settings()

func set_screen_flash_enabled(on: bool) -> void:
	screen_flash_enabled = on
	save_settings()  # no apply step — PlayerHud.flash_* / StarSky.flash_kill poll this live at fire time

func set_tts_enabled(on: bool) -> void:
	tts_enabled = on
	save_settings()

func set_heartbeat_enabled(on: bool) -> void:
	heartbeat_enabled = on
	save_settings()

## The per-channel step count for a Colour Depth index — what `post_process.gdshader`'s `quantize_levels`
## uniform wants. STATIC and total: an out-of-range index returns the Vector3.ZERO sentinel ("leave the
## material's authored `color_steps` alone"), so a caller can never push a garbage vec3 at the shader.
static func color_quantize_levels(mode: int) -> Vector3:
	if mode <= 0 or mode >= COLOR_QUANTIZE_LEVELS.size():
		return Vector3.ZERO
	return COLOR_QUANTIZE_LEVELS[mode]

## How many distinct colours a Colour Depth index can produce — (steps + 1) per channel, multiplied out.
## 0 means "however the material was authored" (the sentinel), which is the one answer this cannot know.
## Exists so the readout, the debug command and the QA harness all quote the SAME number, and so the count
## is assertable off-tree: it is the one claim about this feature a headless test can actually check.
static func color_quantize_color_count(mode: int) -> int:
	var levels := color_quantize_levels(mode)
	if levels == Vector3.ZERO:
		return 0
	return int((levels.x + 1.0) * (levels.y + 1.0) * (levels.z + 1.0))

func set_colorblind_mode(mode: int) -> void:
	colorblind_mode = clampi(mode, 0, 3)
	save_settings()

func set_colorblind_safe_cues(on: bool) -> void:
	colorblind_safe_cues = on
	save_settings()

func set_view_bob_enabled(on: bool) -> void:
	view_bob_enabled = on
	save_settings()

func set_detection_meter_enabled(on: bool) -> void:
	detection_meter_enabled = on
	save_settings()

func set_loot_beacons_enabled(on: bool) -> void:
	loot_beacons_enabled = on
	save_settings()  # no apply step — PickupBeacon polls this live each frame

func set_enemy_health_bar_enabled(on: bool) -> void:
	enemy_health_bar_enabled = on
	save_settings()  # no apply step — EnemyHealthBar polls this live and clears itself the same frame

func set_view_model_visible(on: bool) -> void:
	view_model_visible = on
	save_settings()

func set_view_model_left_handed(on: bool) -> void:
	view_model_left_handed = on
	save_settings()

func set_camera_tilt_enabled(on: bool) -> void:
	camera_tilt_enabled = on
	save_settings()

func set_fov_effects_enabled(on: bool) -> void:
	fov_effects_enabled = on
	save_settings()

func set_ps1_warp_intensity(f: float) -> void:
	ps1_warp_intensity = clampf(f, 0.0, 1.0)
	save_settings()  # no apply step — PS1Applier polls this live each frame and re-applies/restores

func set_dialogue_text_scale(f: float) -> void:
	dialogue_text_scale = clampf(f, 0.75, 1.5)
	save_settings()  # no apply step — DialogueView re-reads it on every conversation open (_apply_type_sizes)

func set_stamina_ring_enabled(on: bool) -> void:
	stamina_ring_enabled = on
	save_settings()  # no apply step — ui.gd polls this live each frame (_apply_stamina_mode)

func set_hud_sway_scale(f: float) -> void:
	hud_sway_scale = clampf(f, 0.0, 1.0)
	save_settings()  # no apply step — ui.gd polls this live each frame (_update_hud_sway)

func set_hud_ghost_scale(f: float) -> void:
	hud_ghost_scale = clampf(f, 0.0, 1.0)
	save_settings()  # no apply step — ui.gd polls this live each frame (HudGhost.poll)

func set_world_ghost_scale(f: float) -> void:
	world_ghost_scale = clampf(f, 0.0, 1.0)
	save_settings()  # no apply step — ui.gd polls this live each frame (WorldGhost.poll)

func set_hud_curve_scale(f: float) -> void:
	hud_curve_scale = clampf(f, 0.0, 1.0)
	save_settings()  # no apply step — ui.gd polls this live each frame (_apply_hud_curve)

func set_lens_curve(f: float) -> void:
	lens_curve = clampf(f, 0.0, 1.0)
	save_settings()  # no apply step — player.gd polls this live each frame (the contrast / dither_strength shape)

func set_minimap_enabled(on: bool) -> void:
	minimap_enabled = on
	save_settings()  # no apply step — ui.gd polls this live each frame (_apply_minimap_visibility)

func set_minimap_rotates(on: bool) -> void:
	minimap_rotates = on
	save_settings()  # no apply step — Minimap reads it live in _draw

func set_minimap_zoom(f: float) -> void:
	minimap_zoom = clampf(f, MINIMAP_ZOOM_MIN, MINIMAP_ZOOM_MAX)
	save_settings()  # no apply step — Minimap reads it live in _draw

## No apply step, and NO push onto the widget: MapScreen re-reads this into its Minimap's zoom_override every
## time it repaints the readout, and the widget's own _options_changed stamp (which compares the EFFECTIVE
## zoom) is what asks for the redraw. So the Options slider and the map's wheel are the same value from both
## directions, and a slider nudge with the tab open bites the next frame.
func set_map_zoom(f: float) -> void:
	map_zoom = clampf(f, MINIMAP_ZOOM_MIN, MINIMAP_ZOOM_MAX)
	save_settings()

func set_minimap_show_npcs(on: bool) -> void:
	minimap_show_npcs = on
	save_settings()  # no apply step — Minimap reads it live in _draw

func set_minimap_show_stations(on: bool) -> void:
	minimap_show_stations = on
	save_settings()  # no apply step — Minimap reads it live in _draw

func set_minimap_show_noise(on: bool) -> void:
	minimap_show_noise = on
	save_settings()  # no apply step — Minimap reads it live in _draw

func set_clock_enabled(on: bool) -> void:
	clock_enabled = on
	save_settings()  # no apply step — ui.gd polls this live each frame (_apply_minimap_visibility)

func set_clock_24_hour(on: bool) -> void:
	clock_24_hour = on
	save_settings()  # no apply step — HudClock reads it live in _process

func set_compass_enabled(on: bool) -> void:
	compass_enabled = on
	save_settings()  # no apply step — ui.gd polls this live each frame (_apply_compass_visibility)

func set_debug_skip_menu(on: bool) -> void:
	debug_skip_menu = on
	save_settings()

## DEBUG: toggle replaying the first-launch Terms-of-Service gate on every launch (StartMenu ORs this into its
## gate check). No apply step — StartMenu reads it live at boot.
func set_debug_always_show_tos(on: bool) -> void:
	debug_always_show_tos = on
	save_settings()

## ML-3: pick the difficulty (0 Easy / 1 Normal / 2 Hard). Copies the level's preset into the live mults
## immediately (apply_difficulty) and persists, so the menu is pure data-binding like every other setter.
func set_difficulty(level: int) -> void:
	difficulty_level = clampi(level, 0, 2)
	apply_difficulty()
	save_settings()

## Draw a weapon picked up off the ground (E) when the player is UNARMED, instead of leaving it in the
## backpack. No apply step — CanPickUp reads this live at pickup time, so the toggle bites on the next pickup.
func set_auto_equip_pickups(on: bool) -> void:
	auto_equip_pickups = on
	save_settings()

## Record the player's one-time consent to the first-launch Terms of Service and persist it, so the gate never shows
## again on this install (StartMenu calls this from the TOS screen's `accepted` signal). No apply step — nothing live
## reads it except StartMenu's boot check. There is intentionally no matching "un-accept" setter.
func accept_tos() -> void:
	tos_accepted = true
	save_settings()

func get_volume(bus: StringName) -> float:
	return float(volumes.get(bus, DEFAULT_VOLUMES.get(bus, 1.0)))  # DEFAULT_VOLUMES so a bare instance (never ran _ready) answers the shipped default, not 1.0

# ---------------------------------------------------------------------------------------------------
# Persistence
# ---------------------------------------------------------------------------------------------------

func load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(CONFIG_PATH) != OK:
		_loaded = true  # no file yet — keep the design defaults seeded in _ready
		return
	window_mode = int(cfg.get_value("video", "window_mode", window_mode))
	# A corrupt/hand-edited cfg can hold ANY Variant here; a non-Vector2i would hard-fail this typed
	# assignment and crash the autoload at boot. Read into a Variant local and keep the default if junk.
	var ws = cfg.get_value("video", "windowed_size", windowed_size)
	# A non-positive size (hand-edit / a future bug) would ask the OS for a zero window; the fit in apply_video only
	# shrinks TOO-BIG sizes, so floor junk to the default here. Too-big is left alone on purpose — the fit handles it.
	windowed_size = ws if ws is Vector2i and ws.x > 0 and ws.y > 0 else windowed_size
	vsync = _cfg_bool(cfg, "video", "vsync", vsync)
	max_fps = int(cfg.get_value("video", "max_fps", max_fps))
	# Presentation + render_scale travel TOGETHER through read_presentation: a pre-presentation cfg's saved scale
	# was a supersample of the RETRO buffer and must not be re-read against a native target (see the helper).
	var pres := read_presentation(cfg, presentation, render_scale)
	presentation = clampi(int(pres["presentation"]), 0, PRESENTATION_COUNT - 1)
	render_scale = clampf(float(pres["render_scale"]), RENDER_SCALE_MIN, RENDER_SCALE_MAX)
	fov = float(cfg.get_value("video", "fov", fov))
	contrast = clampf(float(cfg.get_value("video", "contrast", contrast)), CONTRAST_MIN, CONTRAST_MAX)
	ink_outline_intensity = clampf(float(cfg.get_value("video", "ink_outline_intensity", ink_outline_intensity)), 0.0, 1.0)
	muzzle_smoke_scale = clampf(float(cfg.get_value("video", "muzzle_smoke_scale", muzzle_smoke_scale)), 0.0, 1.0)
	# Clamped on load, like contrast: a cfg written by a build with MORE depths (or a hand edit) must not index
	# past the table and hand the shader a garbage vec3 — an out-of-range value lands on Authored, not on junk.
	color_quantization = clampi(int(cfg.get_value("video", "color_quantization", color_quantization)), 0, COLOR_QUANTIZE_LEVELS.size() - 1)
	dither_strength = clampf(float(cfg.get_value("video", "dither_strength", dither_strength)), 0.0, 1.0)
	for bus in VOLUME_BUSES:
		volumes[bus] = float(cfg.get_value("audio", String(bus), volumes.get(bus, DEFAULT_VOLUMES.get(bus, 1.0))))
	music_folder = str(cfg.get_value("audio", "music_folder", music_folder))
	# Clamped on load (like contrast / ps1_warp_intensity): a legacy value at the old ceiling rescales to ~3% over
	# SENS_MAX, and a hand-edited number outside the slider must not drive the camera faster than the slider allows.
	mouse_sensitivity = clampf(read_mouse_sensitivity(cfg, mouse_sensitivity), SENS_MIN, SENS_MAX)
	controller_look_sensitivity = float(cfg.get_value("input", "controller_look_sensitivity", controller_look_sensitivity))
	invert_look_y = _cfg_bool(cfg, "input", "invert_look_y", invert_look_y)
	# Same guard: a corrupt cfg could store a non-Dictionary under "binds", which would hard-fail this
	# typed assignment (and apply_keybinds iterates it) — fall back to an empty rebind set if it's junk.
	var kb = cfg.get_value("controls", "binds", {})
	keybinds = kb if kb is Dictionary else {}
	screen_shake_scale = float(cfg.get_value("accessibility", "screen_shake_scale", screen_shake_scale))
	screen_flash_enabled = _cfg_bool(cfg, "accessibility", "screen_flash_enabled", screen_flash_enabled)
	hitstop_enabled = _cfg_bool(cfg, "accessibility", "hitstop_enabled", hitstop_enabled)
	colorblind_mode = int(cfg.get_value("accessibility", "colorblind_mode", colorblind_mode))
	colorblind_safe_cues = _cfg_bool(cfg, "accessibility", "colorblind_safe_cues", colorblind_safe_cues)
	view_bob_enabled = _cfg_bool(cfg, "accessibility", "view_bob_enabled", view_bob_enabled)
	view_model_visible = _cfg_bool(cfg, "accessibility", "view_model_visible", view_model_visible)
	view_model_left_handed = _cfg_bool(cfg, "accessibility", "view_model_left_handed", view_model_left_handed)
	detection_meter_enabled = _cfg_bool(cfg, "accessibility", "detection_meter_enabled", detection_meter_enabled)
	loot_beacons_enabled = _cfg_bool(cfg, "accessibility", "loot_beacons_enabled", loot_beacons_enabled)
	enemy_health_bar_enabled = _cfg_bool(cfg, "accessibility", "enemy_health_bar_enabled", enemy_health_bar_enabled)
	camera_tilt_enabled = _cfg_bool(cfg, "accessibility", "camera_tilt_enabled", camera_tilt_enabled)
	fov_effects_enabled = _cfg_bool(cfg, "accessibility", "fov_effects_enabled", fov_effects_enabled)
	ps1_warp_intensity = clampf(float(cfg.get_value("accessibility", "ps1_warp_intensity", ps1_warp_intensity)), 0.0, 1.0)
	dialogue_text_scale = clampf(float(cfg.get_value("accessibility", "dialogue_text_scale", dialogue_text_scale)), 0.75, 1.5)
	stamina_ring_enabled = _cfg_bool(cfg, "accessibility", "stamina_ring_enabled", stamina_ring_enabled)
	hud_sway_scale = clampf(float(cfg.get_value("accessibility", "hud_sway_scale", hud_sway_scale)), 0.0, 1.0)
	hud_ghost_scale = clampf(float(cfg.get_value("accessibility", "hud_ghost_scale", hud_ghost_scale)), 0.0, 1.0)
	world_ghost_scale = clampf(float(cfg.get_value("accessibility", "world_ghost_scale", world_ghost_scale)), 0.0, 1.0)
	hud_curve_scale = clampf(float(cfg.get_value("accessibility", "hud_curve_scale", hud_curve_scale)), 0.0, 1.0)
	lens_curve = clampf(float(cfg.get_value("accessibility", "lens_curve", lens_curve)), 0.0, 1.0)
	minimap_enabled = _cfg_bool(cfg, "accessibility", "minimap_enabled", minimap_enabled)
	minimap_rotates = _cfg_bool(cfg, "accessibility", "minimap_rotates", minimap_rotates)
	minimap_zoom = clampf(float(cfg.get_value("accessibility", "minimap_zoom", minimap_zoom)), MINIMAP_ZOOM_MIN, MINIMAP_ZOOM_MAX)
	map_zoom = clampf(float(cfg.get_value("accessibility", "map_zoom", map_zoom)), MINIMAP_ZOOM_MIN, MINIMAP_ZOOM_MAX)
	minimap_show_npcs = _cfg_bool(cfg, "accessibility", "minimap_show_npcs", minimap_show_npcs)
	minimap_show_stations = _cfg_bool(cfg, "accessibility", "minimap_show_stations", minimap_show_stations)
	minimap_show_noise = _cfg_bool(cfg, "accessibility", "minimap_show_noise", minimap_show_noise)
	clock_enabled = _cfg_bool(cfg, "accessibility", "clock_enabled", clock_enabled)
	clock_24_hour = _cfg_bool(cfg, "accessibility", "clock_24_hour", clock_24_hour)
	compass_enabled = _cfg_bool(cfg, "accessibility", "compass_enabled", compass_enabled)
	tts_enabled = _cfg_bool(cfg, "accessibility", "tts_enabled", tts_enabled)
	heartbeat_enabled = _cfg_bool(cfg, "accessibility", "heartbeat_enabled", heartbeat_enabled)
	debug_skip_menu = _cfg_bool(cfg, "debug", "skip_menu", debug_skip_menu)
	debug_always_show_tos = _cfg_bool(cfg, "debug", "always_show_tos", debug_always_show_tos)
	difficulty_level = clampi(int(cfg.get_value("gameplay", "difficulty_level", difficulty_level)), 0, 2)
	auto_equip_pickups = _cfg_bool(cfg, "gameplay", "auto_equip_pickups", auto_equip_pickups)
	tos_accepted = _cfg_bool(cfg, "legal", "tos_accepted", tos_accepted)
	_loaded = true

## Pure: the mouse sensitivity a settings.cfg carries, in the CURRENT unit (radians per SCREEN pixel). Unit-tested
## off-tree with an in-memory ConfigFile (tests/test_settings.gd), so load_settings never has to touch user:// under GUT.
##  - MOUSE_SENS_KEY present -> that value, verbatim (it was saved in screen-px units).
##  - else the OLD MOUSE_SENS_LEGACY_KEY present -> a cfg from before MouseInput switched from `relative` (canvas px,
##    pre-scaled by the window->canvas stretch) to `screen_relative` (raw OS px): the value is multiplied ONCE by
##    LEGACY_MOUSE_SENS_SCALE, the 1080p-fullscreen factor every legacy value was tuned against, so a returning
##    player's 1080p feel is unchanged instead of ~2.4x faster (0.002 -> 0.000825 — which WAS the design default
##    at migration time; since the 08-31 retune to 0.00115 a migrated value keeps the returning player's exact
##    feel and deliberately does NOT land on the fresh-install default).
##  - neither -> `fallback` (the design default seeded in _ready).
## NOT clamped here — the caller clamps to SENS_MIN..SENS_MAX like every other loader/setter (a legacy value at the
## old ceiling lands ~3% over the new one). A junk (non-numeric) value degrades through float() like every other
## float row in load_settings; the old key is never written back, so this can never run twice on one value.
static func read_mouse_sensitivity(cfg: ConfigFile, fallback: float) -> float:
	if cfg.has_section_key("input", MOUSE_SENS_KEY):
		return float(cfg.get_value("input", MOUSE_SENS_KEY, fallback))
	if cfg.has_section_key("input", MOUSE_SENS_LEGACY_KEY):
		return float(cfg.get_value("input", MOUSE_SENS_LEGACY_KEY, fallback)) * LEGACY_MOUSE_SENS_SCALE
	return fallback

## Pure: the presentation mode + render scale a settings.cfg carries — unit-tested off-tree with an in-memory
## ConfigFile (the read_mouse_sensitivity idiom).
##  - presentation key present -> both values verbatim (they were saved by a presentation-aware build).
##  - key ABSENT -> a cfg from the RETRO-only era: HIGH FIDELITY (the new shipped look) with render_scale FORCED
##    to 1.0. The saved scale (typically the old 2.0 default) supersampled the ~792x444 RETRO buffer; re-read
##    against a native root target it would mean 3840x2160 3D on a 1080p screen — a silent 4x perf cliff.
## One-shot by construction: save_settings always writes the presentation key, so the reset can never run twice.
## NOT clamped here — the caller clamps both values, like every other loader.
static func read_presentation(cfg: ConfigFile, fallback_mode: int, fallback_scale: float) -> Dictionary:
	if cfg.has_section_key("video", "presentation"):
		return {
			"presentation": int(cfg.get_value("video", "presentation", fallback_mode)),
			"render_scale": float(cfg.get_value("video", "render_scale", fallback_scale)),
		}
	return {"presentation": PRESENTATION_HIGH_FIDELITY, "render_scale": 1.0}

## bool() has NO String constructor in Godot 4 (bool(<String>) throws "Invalid call. Nonexistent 'bool'
## constructor"), yet a hand-edited / legacy / corrupt settings.cfg can persist a bool key as a String. Mirror the
## windowed_size / binds Variant-guards in load_settings (and GameState._cfg_bool) so a junk-typed flag degrades to
## its default instead of crashing this autoload at boot. The int()/float() reads beside these are already safe —
## unlike bool(), those constructors DO parse a String ("5" -> 5), so only the bool reads need the guard.
static func _cfg_bool(cfg: ConfigFile, section: String, key: String, fallback: bool) -> bool:
	var v = cfg.get_value(section, key, fallback)
	return bool(v) if (v is bool or v is int or v is float) else fallback

func save_settings() -> void:
	if not _loaded:
		return  # never clobber the file before load_settings has run
	var cfg := ConfigFile.new()
	cfg.set_value("video", "window_mode", window_mode)
	cfg.set_value("video", "windowed_size", windowed_size)
	cfg.set_value("video", "vsync", vsync)
	cfg.set_value("video", "max_fps", max_fps)
	cfg.set_value("video", "presentation", presentation)  # ALWAYS written — the key's presence is what makes read_presentation's era migration one-shot
	cfg.set_value("video", "render_scale", render_scale)
	cfg.set_value("video", "fov", fov)
	cfg.set_value("video", "contrast", contrast)
	cfg.set_value("video", "ink_outline_intensity", ink_outline_intensity)
	cfg.set_value("video", "muzzle_smoke_scale", muzzle_smoke_scale)
	cfg.set_value("video", "color_quantization", color_quantization)
	cfg.set_value("video", "dither_strength", dither_strength)
	for bus in VOLUME_BUSES:
		cfg.set_value("audio", String(bus), float(volumes.get(bus, DEFAULT_VOLUMES.get(bus, 1.0))))
	cfg.set_value("audio", "music_folder", music_folder)
	cfg.set_value("input", MOUSE_SENS_KEY, mouse_sensitivity)  # screen-px units; the legacy key is deliberately NOT written (read_mouse_sensitivity)
	cfg.set_value("input", "controller_look_sensitivity", controller_look_sensitivity)
	cfg.set_value("input", "invert_look_y", invert_look_y)
	cfg.set_value("controls", "binds", keybinds)
	cfg.set_value("accessibility", "screen_shake_scale", screen_shake_scale)
	cfg.set_value("accessibility", "screen_flash_enabled", screen_flash_enabled)
	cfg.set_value("accessibility", "hitstop_enabled", hitstop_enabled)
	cfg.set_value("accessibility", "colorblind_mode", colorblind_mode)
	cfg.set_value("accessibility", "colorblind_safe_cues", colorblind_safe_cues)
	cfg.set_value("accessibility", "view_bob_enabled", view_bob_enabled)
	cfg.set_value("accessibility", "view_model_visible", view_model_visible)
	cfg.set_value("accessibility", "view_model_left_handed", view_model_left_handed)
	cfg.set_value("accessibility", "detection_meter_enabled", detection_meter_enabled)
	cfg.set_value("accessibility", "loot_beacons_enabled", loot_beacons_enabled)
	cfg.set_value("accessibility", "enemy_health_bar_enabled", enemy_health_bar_enabled)
	cfg.set_value("accessibility", "camera_tilt_enabled", camera_tilt_enabled)
	cfg.set_value("accessibility", "fov_effects_enabled", fov_effects_enabled)
	cfg.set_value("accessibility", "ps1_warp_intensity", ps1_warp_intensity)
	cfg.set_value("accessibility", "dialogue_text_scale", dialogue_text_scale)
	cfg.set_value("accessibility", "stamina_ring_enabled", stamina_ring_enabled)
	cfg.set_value("accessibility", "hud_sway_scale", hud_sway_scale)
	cfg.set_value("accessibility", "hud_ghost_scale", hud_ghost_scale)
	cfg.set_value("accessibility", "world_ghost_scale", world_ghost_scale)
	cfg.set_value("accessibility", "hud_curve_scale", hud_curve_scale)
	cfg.set_value("accessibility", "lens_curve", lens_curve)
	cfg.set_value("accessibility", "minimap_enabled", minimap_enabled)
	cfg.set_value("accessibility", "minimap_rotates", minimap_rotates)
	cfg.set_value("accessibility", "minimap_zoom", minimap_zoom)
	cfg.set_value("accessibility", "map_zoom", map_zoom)
	cfg.set_value("accessibility", "minimap_show_npcs", minimap_show_npcs)
	cfg.set_value("accessibility", "minimap_show_stations", minimap_show_stations)
	cfg.set_value("accessibility", "minimap_show_noise", minimap_show_noise)
	cfg.set_value("accessibility", "clock_enabled", clock_enabled)
	cfg.set_value("accessibility", "clock_24_hour", clock_24_hour)
	cfg.set_value("accessibility", "compass_enabled", compass_enabled)
	cfg.set_value("accessibility", "tts_enabled", tts_enabled)
	cfg.set_value("accessibility", "heartbeat_enabled", heartbeat_enabled)
	cfg.set_value("debug", "skip_menu", debug_skip_menu)
	cfg.set_value("debug", "always_show_tos", debug_always_show_tos)
	cfg.set_value("gameplay", "difficulty_level", difficulty_level)
	cfg.set_value("gameplay", "auto_equip_pickups", auto_equip_pickups)
	cfg.set_value("legal", "tos_accepted", tos_accepted)
	cfg.save(CONFIG_PATH)

## Window.Mode -> our dropdown index (defaults to Exclusive Fullscreen if it's an unlisted mode).
func _mode_to_index(mode: int) -> int:
	var i := WINDOW_MODES.find(mode)
	return i if i >= 0 else 2
