class_name MinimapArt
extends RefCounted

## @system Minimap
## @seam The PRECEDENCE and SIZING rules for every drop-in marker texture the minimap can wear. Statics only, and the skin arrives as a PARAMETER (never MenuStyle.hud), so every rule here is provable off-tree against a bare HudSkin.new() — the FloorplanSection / MapGlyph promise, verbatim.
## @seam THE BOUNDARY between the two artist surfaces: the SCENE (scenes/ui/hud_minimap.tscn's %MapUnder / %MapOver) owns whole-box LAYERS, and the SKIN owns per-MARKER glyphs. A scene node cannot draw a badge at a position recomputed every frame, which is exactly why these three families — the player caret, the POI beacon, the seven station badges — are skin slots and the backdrop/frame are not.
## @risk Art replaces a marker's SILHOUETTE only. Position, SIZE and TINT stay owned by the knobs (MenuStyle.hud.minimap_*_px, beside the colours) and by the colour the channel already resolved, so a delivered PNG can never encode its own size and fight the canvas's ~2.4x nearest upscale, and can never break the colour contract (a station's per-instance StationMarker.color, the EXIT exception, the off-floor alpha fade).
## @test res://tests/test_minimap_art.gd
##
## WHY THE BODY GLYPHS ARE DELIBERATELY ABSENT. There is no slot for the hostile caret / ally diamond /
## friendly dot / neutral ring, nor for the alert ring, floor tick or north tick. Those are 2-4 px marks whose
## whole job is to be read as a SHAPE — that is the accessibility channel this project chose over hue precisely
## because hue fails at that size and swaps under Settings.colorblind_safe_cues. Art there would trade a
## readable alphabet for a smudge. See docs/AUTHORING_GUIDE.md §"The glyph alphabet".


## THE PRECEDENCE RULE, in one place so the three channels cannot disagree: a per-level MapData's art wins, then
## the global skin slot, then null meaning "draw the primitive".
##
## Per-level FIRST on purpose. MapData.player_marker / npc_marker are the older, narrower surface and belong to
## one authored level, so a set-piece level must be able to override the skin the rest of the game wears —
## the same direction every other per-instance override in this project resolves (StationMarker.color over the
## skin tint, Minimap.map_data over LevelData.map_data).
static func pick(per_level: Texture2D, slot: Texture2D) -> Texture2D:
	if per_level != null:
		return per_level
	return slot


## The station badge for one StationMarker.Kind: its own slot, else the family badge, else null (stroke the
## glyph). Mirrors StationMarker.glyph_shape's one-shape-per-Kind table so an eighth station Kind is one edit
## here beside the one there.
##
## SEVEN NAMED SLOTS, never an Array[Texture2D]: reordering the enum would silently re-key an artist's whole
## delivery, and seven labelled inspector rows are legible to someone who does not open Godot.
##
## `skin` is untyped so a bare HudSkin.new() satisfies it with no class coupling; a null skin answers null,
## which is the shipped code-drawn look.
static func station_texture(skin, kind: int) -> Texture2D:
	if skin == null:
		return null
	var own: Texture2D = null
	match kind:
		StationMarker.Kind.SHOP:
			own = skin.minimap_station_shop_texture
		StationMarker.Kind.BANK:
			own = skin.minimap_station_bank_texture
		StationMarker.Kind.HEAL:
			own = skin.minimap_station_heal_texture
		StationMarker.Kind.TRAIN:
			own = skin.minimap_station_train_texture
		StationMarker.Kind.TECH:
			own = skin.minimap_station_tech_texture
		StationMarker.Kind.LEISURE:
			own = skin.minimap_station_leisure_texture
		StationMarker.Kind.EXIT:
			own = skin.minimap_station_exit_texture
	# An unrecognised Kind (a future enum member whose slot has not been added here yet) falls through to the
	# family badge rather than to nothing — the same degrade glyph_shape makes when it returns CIRCLE.
	return own if own != null else skin.minimap_station_texture


## THE SIZING RULE: every glyph texture is stretched into a square of 2x the radius the DRAWN glyph used at that
## call site, centred on the marker point. So art is sized by the skin's minimap_station_glyph_px /
## minimap_poi_glyph_px / minimap_caret_px exactly as the drawn primitive was, and swapping a PNG can never
## silently change how much of the 108 px box a marker eats.
##
## A non-positive radius returns an empty Rect2 — the MapGlyph.shape_points "no points" degrade, so a knob
## zeroed to switch a channel off switches the art off with it instead of drawing a native-size texture.
static func glyph_rect(at: Vector2, radius: float) -> Rect2:
	if radius <= 0.0:
		return Rect2()
	return Rect2(at - Vector2(radius, radius), Vector2(radius, radius) * 2.0)
