# Minimap art

Drop-in art for the HUD minimap. Two very different kinds of thing land here, and they go to two
different places in the editor:

## Whole-box layers -> the SCENE

A backdrop, a bezel, a frame, glass, scanlines, a vignette. These go into
`scenes/ui/hud_minimap.tscn`, as children of:

- **`%MapUnder`** — renders BEHIND the map's plan (a backdrop). Also zero the ALPHA of
  `minimap_backing_color` in `resources/ui/hud_skin.tres`, or the code-drawn backing paints over it.
- **`%MapOver`** — renders IN FRONT of everything (a frame). A `NinePatchRect` here is the right way
  to frame the box: it stretches the edges and keeps the corners sharp.

The box is 108x108 px on a 792x444 canvas that is nearest-upscaled ~2.4x to the window. Author at
that size, or at a whole multiple of it, and keep the master in `src_masters/`.

## Marker glyphs -> the SKIN

The player caret, POI beacons and the seven station badges are drawn at positions recomputed every
frame, so they cannot be scene nodes. They are `Texture2D` slots in the **Minimap art** group of
`resources/ui/hud_skin.tres`. Every one is optional — leave it empty and the code-drawn glyph stays.

They are TINY: a station badge is ~10 px across, a POI dot ~8 px, the caret ~10 px. Deliver them
white/grey (the game tints them) and readable as a silhouette at that size. Only the caret rotates;
author it pointing screen-up. See `docs/AUTHORING_GUIDE.md` §27 "Minimap marker art — the contact
sheet" for the full per-slot contract.

## src_masters/

High-resolution originals. `.gdignore`d, so Godot never imports them — bake a game-ready size into
this folder and keep the master beside it, exactly as `assets/textures/ui/src_masters/` does for the
menu button frames and panels.
