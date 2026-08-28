extends GutTest

## StationMarker (scripts/components/station_marker.gd) — the drop-in that puts a station on the minimap.
##
## What is pinned here is the ZERO-AUTHORING promise and the two rules that make it safe: ensure() must never
## double-add (an authored marker is the designer's override AND mute switch) and it must derive PINNING from
## the station's own `standalone` flag, because a shopkeeper who walks around must not become a permanent blip
## on the box rim. Plus the roster check: a station component that forgets its ensure() line is invisible on
## the map with nothing failing, which is exactly the silent rot the dialogue-station roster test exists to
## catch on the other contract.
##
## Loaded BY PATH for the stale-class-cache reason test_minimap.gd documents.
const MARKER_SCRIPT := "res://scripts/components/station_marker.gd"
## Every component that must carry a minimap pin, and the Kind it must ask for. THE SPEC — a new station adds
## its row here and the roster test below makes the missing ensure() line fail loudly.
const STATION_PINS := {
	"res://scripts/components/merchant.gd": "SHOP",
	"res://scripts/components/atm.gd": "BANK",
	"res://scripts/components/healer.gd": "HEAL",
	"res://scripts/components/level_up.gd": "TRAIN",
	"res://scripts/components/perk_station.gd": "TRAIN",
	"res://scripts/components/respec_station.gd": "TRAIN",
	"res://scripts/components/chip_installer.gd": "TECH",
	"res://scripts/components/weapon_bench.gd": "TECH",
	"res://scripts/components/bonfire.gd": "LEISURE",
	"res://scripts/components/chess_match.gd": "LEISURE",
	"res://scripts/components/level_door.gd": "EXIT",
}


func _new_marker() -> StationMarker:
	return load(MARKER_SCRIPT).new()


# --- the inspector surface -----------------------------------------------------------------------------

## The defaults a designer sees. `enabled` on and a TRANSPARENT colour are the two that carry meaning: the
## marker is opt-OUT, and a transparent tint is the sentinel for "use the skin".
func test_component_defaults() -> void:
	var m := _new_marker()
	autofree(m)
	assert_true(m.enabled, "a station pin is opt-OUT, not opt-in — that is the zero-authoring promise")
	assert_eq(m.color.a, 0.0,
			"the tint ships TRANSPARENT: the sentinel for 'use MenuStyle.hud.minimap_station_color'")
	assert_false(m.pin_offscreen,
			"the bare default does not pin — ensure() is what raises it for a fixed kiosk")

## The sentinel rule, both branches, in the one place it lives.
func test_resolved_color_prefers_the_skin_until_a_designer_overrides() -> void:
	var m := _new_marker()
	autofree(m)
	var station := Color(0.1, 0.2, 0.3, 1.0)
	var exit_col := Color(0.4, 0.5, 0.6, 1.0)
	m.kind = StationMarker.Kind.SHOP
	assert_eq(m.resolved_color(station, exit_col), station, "a transparent tint defers to the skin")
	m.kind = StationMarker.Kind.EXIT
	assert_eq(m.resolved_color(station, exit_col), exit_col,
			"an EXIT takes the skin's OWN exit tint — a way out is not the same class of thing as a shop")
	m.color = Color(0.9, 0.1, 0.9, 1.0)
	assert_eq(m.resolved_color(station, exit_col), m.color,
			"...and any opaque authored colour wins over both")


# --- the glyph alphabet --------------------------------------------------------------------------------

## Every Kind must map to a DISTINCT shape. A repeat would make two station types indistinguishable, which is
## the entire reason Kind has seven members instead of one per component.
func test_every_kind_gets_its_own_shape() -> void:
	var seen := {}
	for k in [StationMarker.Kind.SHOP, StationMarker.Kind.BANK, StationMarker.Kind.HEAL,
			StationMarker.Kind.TRAIN, StationMarker.Kind.TECH, StationMarker.Kind.LEISURE,
			StationMarker.Kind.EXIT]:
		var shape: int = StationMarker.glyph_shape(k)
		assert_false(seen.has(shape),
				"kind %s must not reuse a shape already taken by kind %s" % [k, seen.get(shape, -1)])
		seen[shape] = k
	assert_eq(seen.size(), 7, "seven kinds, seven shapes")

## The two glyphs a player hunts for get the shapes their meaning implies — a pin the next person to reshuffle
## the alphabet has to argue with.
func test_the_semantic_shapes_are_the_ones_that_matter() -> void:
	assert_eq(StationMarker.glyph_shape(StationMarker.Kind.EXIT), MapGlyph.Shape.CHEVRON,
			"the way OUT is the arrowhead")
	assert_eq(StationMarker.glyph_shape(StationMarker.Kind.HEAL), MapGlyph.Shape.CROSS,
			"a clinic is a cross — the one glyph that needs no learning")

## An unrecognised kind degrades to a circle. A glyph in the wrong shape is cosmetic; an error inside a HUD
## paint loop is not.
func test_an_unknown_kind_degrades_rather_than_erroring() -> void:
	assert_eq(StationMarker.glyph_shape(99 as StationMarker.Kind), MapGlyph.Shape.CIRCLE,
			"an out-of-range kind still draws something")


# --- ensure() ------------------------------------------------------------------------------------------

## The happy path: a bare station gets a pin with no authoring at all.
func test_ensure_creates_a_pin_on_a_bare_station() -> void:
	var station := Node3D.new()
	add_child_autofree(station)
	var m := StationMarker.ensure(station, StationMarker.Kind.SHOP)
	assert_not_null(m, "a station with no authored marker gets one")
	assert_eq(m.kind, StationMarker.Kind.SHOP, "stamped with the kind the component asked for")
	assert_eq(m.get_parent(), station, "and parented to the station, so its transform is the pin")

## THE OVERRIDE BARGAIN: an authored marker always wins, so a hand-placed one is the retune AND the mute
## switch. Calling ensure() twice must never leave two pins on one station either.
func test_ensure_never_replaces_or_duplicates_an_authored_pin() -> void:
	var station := Node3D.new()
	add_child_autofree(station)
	var authored := _new_marker()
	authored.kind = StationMarker.Kind.EXIT
	authored.enabled = false
	station.add_child(authored)
	var got := StationMarker.ensure(station, StationMarker.Kind.SHOP)
	assert_eq(got, authored, "the authored marker is returned, not a fresh one")
	assert_eq(authored.kind, StationMarker.Kind.EXIT, "...and its authored kind is left alone")
	assert_false(authored.enabled, "...including enabled = false, which is how a designer hides ONE station")
	StationMarker.ensure(station, StationMarker.Kind.SHOP)
	var count := 0
	for c in station.get_children():
		if c is StationMarker:
			count += 1
	assert_eq(count, 1, "ensure() is idempotent — a second call must not stack a second pin")

## THE PIN RULE. A wall kiosk (standalone) points at itself from the rim; a station riding a dialogue NPC does
## not, because a rim blip that tracks a walking body around the edge of the box is a radar, which is the line
## the minimap already refuses to cross for NPC dots.
func test_pinning_follows_the_stations_own_standalone_flag() -> void:
	var kiosk := StandaloneStub.new()
	add_child_autofree(kiosk)
	kiosk.standalone = true
	assert_true(StationMarker.ensure(kiosk, StationMarker.Kind.BANK).pin_offscreen,
			"a self-serve terminal is a landmark — pin it to the rim")
	var on_npc := StandaloneStub.new()
	add_child_autofree(on_npc)
	on_npc.standalone = false
	assert_false(StationMarker.ensure(on_npc, StationMarker.Kind.SHOP).pin_offscreen,
			"a vendor riding a walking NPC stays clipped to the box")

## A station with NO `standalone` field (PerkStation, RespecStation, LevelDoor are always on the talk layer)
## is a fixed fixture by construction, so the absent case pins.
func test_a_station_without_a_standalone_field_pins() -> void:
	var fixture := Node3D.new()
	add_child_autofree(fixture)
	assert_true(StationMarker.ensure(fixture, StationMarker.Kind.TRAIN).pin_offscreen,
			"no standalone field = always a kiosk = worth pointing at")

## Null-safe like every other ensure() in this codebase — a station being freed mid-teardown must not take the
## HUD down with it.
func test_ensure_is_null_safe() -> void:
	assert_null(StationMarker.ensure(null, StationMarker.Kind.SHOP), "no station, no marker, no crash")

## find_marker scans DIRECT children only. Two stations on one dialogue NPC are SIBLINGS, so a deep search
## would hand the Merchant the Atm's pin.
func test_find_marker_does_not_reach_into_a_sibling_station() -> void:
	var npc := Node3D.new()
	add_child_autofree(npc)
	var shop := Node3D.new()
	npc.add_child(shop)
	var bank := Node3D.new()
	npc.add_child(bank)
	StationMarker.ensure(bank, StationMarker.Kind.BANK)
	assert_null(StationMarker.find_marker(shop), "the shop must not see the bank's pin")
	var own := StationMarker.ensure(shop, StationMarker.Kind.SHOP)
	assert_eq(own.kind, StationMarker.Kind.SHOP, "...it gets its own instead")


# --- the roster: a station that forgets its line is invisible with nothing failing ----------------------

## ROSTER-AS-SPEC (the tests/test_dialogue_speaker_contracts.gd idiom). Every component in STATION_PINS must
## call StationMarker.ensure with the Kind this test names. Greps SOURCE TEXT, so it catches the one failure
## mode that has no runtime symptom: a new station whose author never added the line just never appears on
## the map, and no other test would notice.
func test_every_station_component_asks_for_its_pin() -> void:
	for path in STATION_PINS:
		var f := FileAccess.open(path, FileAccess.READ)
		assert_not_null(f, "station component %s must exist" % path)
		if f == null:
			continue
		var src := f.get_as_text()
		f.close()
		var want := "StationMarker.ensure(self, StationMarker.Kind.%s)" % STATION_PINS[path]
		assert_true(src.contains(want),
				"%s must call %s from its _ready, or it is silently missing from the minimap" % [path, want])


## Minimal stand-in for a dual-mode station: ensure() only duck-reads `standalone`, so this needs none of a
## real component's _ready (which builds hitboxes, outlines, inventories and speakers).
class StandaloneStub extends Node3D:
	var standalone: bool = true
