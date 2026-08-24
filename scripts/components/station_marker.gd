@tool
class_name StationMarker
extends Node3D

## @system Minimap
## NOTE: each @seam/@risk below must stay on ONE line — ArchScan only reads lines that start with a @tag, so a
## wrapped continuation line is DROPPED and the statement renders truncated in docs/SYSTEM_MAP.md.
## @seam ensure(station, kind) is the ZERO-AUTHORING seam: every station calls it once from its own _ready, so dropping a bare Merchant / Atm / Healer prefab into a level puts it on the minimap with no tick and no child node to remember — and an AUTHORED StationMarker child always wins, which makes a hand-placed one both the retune (kind, colour, nudged position) AND the hide switch (enabled = false). Verbatim the StationSpeaker.ensure bargain.
## @seam Joins Groups.MINIMAP_STATION (never Groups.MINIMAP): the station channel is painted with its own glyph alphabet, and a station riding a dialogue NPC must keep its disposition-tinted NPC dot, which joining MINIMAP would suppress via Minimap._paint_markers' de-dupe.
## @risk ensure() is runtime-only (Engine.is_editor_hint bails) — a @tool station must never spawn nodes into a scene the designer is editing, or the marker gets SAVED into the .tscn and then a second one spawns beside it at run time.
## @risk pin_offscreen defaults from the station's own `standalone` flag, so a WALL KIOSK points at itself from the rim while a VENDOR ON A WALKING NPC does not. Hardcoding pin = true would make every shopkeeper a permanent rim blip — the "that is a radar, not a floorplan" line Minimap already refuses to cross.
## @test res://tests/test_station_marker.gd
##
## Drop-in MINIMAP PIN for a station. You almost never place this by hand: each of the ten station components
## calls StationMarker.ensure(self, <kind>) from its _ready, so the pin comes free with the station. Place one
## ONLY to override something:
##   * a different `kind` (a Merchant that is really a fence, a Bonfire that is really a shrine),
##   * a different `color` (a story-critical vendor picked out from the rest),
##   * a nudged POSITION — this is a Node3D, so moving it moves the pin without moving the station's hitbox
##     (useful when the interactable sits on a counter but the pin should read at the shop's doorway),
##   * `enabled = false` to keep one station off the map entirely (the MinimapHide role, per station).
##
## WHY A Node3D AND NOT THE MinimapHide "join my parent" IDIOM. MinimapHide adds its PARENT because the thing
## being hidden is the parent's collider. Here the marker carries data of its own (kind, colour, pin) and a
## position worth nudging, so it joins ITSELF and the widget reads it directly — one node, one glyph, no
## duck-typed hop through a host.

## What this station IS, which picks the glyph the minimap draws. SEVEN kinds, not one per component, because
## the box is 108 px and a glyph is ~5 px: shapes have to stay mutually distinguishable, so components with the
## same MEANING to a player share one. LevelUp / PerkStation / RespecStation are all "spend what you earned"
## (TRAIN); Bonfire / ChessMatch are both "somewhere to stop" (LEISURE).
enum Kind {
	SHOP,     ## Merchant — buy and sell
	BANK,     ## Atm — the ledger terminal
	HEAL,     ## Healer — patch up
	TRAIN,    ## LevelUp / PerkStation / RespecStation — spend levels, perks, respec
	TECH,     ## ChipInstaller — implants and microchips
	LEISURE,  ## Bonfire / ChessMatch — rest, save, play
	EXIT,     ## LevelDoor — the way out of this level
}

## OFF = this station is not on the minimap at all (the per-station MinimapHide). Read on _ready only; flipping
## it at runtime does nothing, which matches MinimapHide's own contract.
@export var enabled: bool = true
## Which glyph the minimap draws for this station. ensure() stamps the component's own kind; override it here
## when a placement means something different from what its component class implies.
@export var kind: Kind = Kind.SHOP
## Per-instance tint override. TRANSPARENT (the default, alpha 0) means "use the skin" —
## MenuStyle.hud.minimap_station_color, or minimap_exit_color for an EXIT — so the whole map restyles from the
## skin and this export stays the exception rather than the norm. Any alpha above 0 wins.
## (A transparent SENTINEL rather than a second `use_skin_color` bool: a colour a designer can see is
## transparent is self-documenting in the inspector, and two exports for one decision is the worse trade.)
@export var color: Color = Color(0.0, 0.0, 0.0, 0.0)
## Should this glyph PIN to the box rim when the station is off the drawn area? True for a fixed landmark whose
## whole job is to be findable (a wall terminal, a level exit); false for a station riding a walking NPC, where
## a rim blip would track a body around the edge of the box and hand the player a radar. ensure() derives the
## default from the station's own `standalone` flag — see _default_pin_for.
@export var pin_offscreen: bool = false


func _ready() -> void:
	# @tool guard: in the editor this node is only ever a thing the designer is positioning. Joining a group
	# in-editor would leak editor state into the group the HUD scans (the @tool station idiom).
	if Engine.is_editor_hint():
		return
	if enabled:
		add_to_group(Groups.MINIMAP_STATION)


## The tint the minimap paints this glyph with: this instance's `color` when a designer set one (alpha > 0),
## else the skin's. Instance method so a test can pin the precedence off-tree, and the ONE place the sentinel
## rule lives so no paint site has to know about it.
func resolved_color(station_color: Color, exit_color: Color) -> Color:
	if color.a > 0.0:
		return color
	return exit_color if kind == Kind.EXIT else station_color


## THE GLYPH ALPHABET: which MapGlyph.Shape each kind wears. One shape per kind, no repeats — that is the whole
## reason Kind has seven members and not one per component (see the enum).
##
## The mapping lives HERE, beside the enum it explains, rather than in the widget: adding an eighth kind should
## be one edit in one file, and a kind whose shape nobody chose is a bug you want to see next to the kind.
## Anything unrecognised degrades to CIRCLE — a glyph in the wrong shape is a cosmetic bug; a crash in a HUD
## paint loop is not.
##
## ⭐TRIANGLE IS SHARED WITH THE NPC FAMILY ON PURPOSE, and safely: a station is drawn STROKED and larger, an
## NPC FILLED and smaller, so a hollow triangle is a campfire and a solid one is a hostile. Do not "fix" this by
## filling station glyphs.
static func glyph_shape(k: Kind) -> int:
	match k:
		Kind.SHOP:
			return MapGlyph.Shape.DIAMOND
		Kind.BANK:
			return MapGlyph.Shape.HEXAGON
		Kind.HEAL:
			return MapGlyph.Shape.CROSS
		Kind.TRAIN:
			return MapGlyph.Shape.TRIANGLE   # inverted by glyph_angle — see there for why
		Kind.TECH:
			return MapGlyph.Shape.SQUARE     # a chip
		Kind.LEISURE:
			return MapGlyph.Shape.CIRCLE     # a fire, a board — somewhere to stop
		Kind.EXIT:
			return MapGlyph.Shape.CHEVRON    # the arrowhead: the way OUT, and the one glyph a lost player hunts
	return MapGlyph.Shape.CIRCLE


## Rotation (radians) for this kind's glyph, on top of the shape.
##
## ⭐TRAIN ALONE IS TURNED, and it is not decoration: TRIANGLE is the one shape the station alphabet shares with
## the BODY alphabet, where a filled up-caret means HOSTILE. Stroke-vs-fill and size already separate the two
## families, but an inverted triangle separates them on SILHOUETTE as well — so a trainer can never be misread
## as a man with a gun even at 3 px, in a colourblind palette, at 0.3 alpha through the off-floor fade. Pointing
## DOWN also reads better for what a trainer IS: you put something in (levels, points) rather than take it out.
static func glyph_angle(k: Kind) -> float:
	return PI if k == Kind.TRAIN else 0.0


## Give `station` a minimap pin unless a designer already authored one. Called once from each station
## component's _ready. An AUTHORED StationMarker child always wins — that is what makes a hand-placed one the
## override AND the mute switch (`enabled = false`), exactly the StationSpeaker.ensure bargain.
##
## Runtime only: a @tool station must never spawn nodes into a scene the designer is editing, or the spawned
## marker would be SAVED into the .tscn and a second one would appear beside it on the next run.
##
## Returns the marker in play (found or created), or null when there is nothing to mark — so a caller can
## chain a tweak onto it, and a test can assert the found-vs-created branch.
static func ensure(station: Node, kind_hint: Kind) -> StationMarker:
	if not is_instance_valid(station) or Engine.is_editor_hint():
		return null
	var existing := find_marker(station)
	if existing != null:
		return existing
	var m := StationMarker.new()
	m.name = "MapPin"
	m.kind = kind_hint
	m.pin_offscreen = _default_pin_for(station)
	station.add_child(m)
	return m


## The station's own authored marker, if it has one. A DIRECT-children scan (the DialogueManager._station_options
## idiom): a marker is authored ON the station, and a deep search would find a marker belonging to a sibling
## station on the same NPC.
static func find_marker(station: Node) -> StationMarker:
	if not is_instance_valid(station):
		return null
	for c in station.get_children():
		if c is StationMarker:
			return c as StationMarker
	return null


## Should a freshly-ensured marker pin to the rim? The station's OWN `standalone` flag already answers "am I a
## fixed kiosk or am I riding a person", so this reads it rather than inventing a second concept:
##   standalone true  -> a wall terminal / counter: a landmark, worth pointing at from the rim.
##   standalone false -> a dual-mode station on a dialogue NPC: a body, so clipped to the box like every other
##                       body (Minimap's radar rule).
## A station with NO `standalone` field at all (PerkStation, RespecStation, LevelDoor — always on the talk
## layer) is by construction a fixed fixture, so the absent case pins. `.get()` is the house rule for a
## duck-typed host property read.
static func _default_pin_for(station: Node) -> bool:
	var raw: Variant = station.get(&"standalone")
	if raw is bool:
		return raw == true   # `== true` never bool(...): a Variant narrowing, the house rule for duck-typed reads
	return true
