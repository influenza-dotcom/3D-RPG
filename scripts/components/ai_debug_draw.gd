class_name AiDebugDraw
extends Node3D

## Runtime immediate-mode 3D surface for NavDebugOverlay's AI-diagnostic layers: world-space wire LINES (sight
## cones, faction rings, zone extents) on a single ImmediateMesh, plus billboard TEXT (GOAP goal/action) on a
## pooled set of Label3D nodes. It is NOT a designer drop-in — NavDebugOverlay spawns/frees exactly ONE of these
## when any of its AI layers is on, and drives it each frame:
##
##     draw.begin()                       # clear the mesh, rewind the label pool
##     draw.add_lines(pts, color)         # buffer wire segments (PAIR format, already world-space)
##     draw.add_label(world_pos, text)    # grab/reuse a pooled Label3D above a head
##     draw.end()                         # commit the mesh surface, hide any labels not reused this frame
##
## All geometry is authored in WORLD coordinates and this node is kept at the origin (identity), so mesh verts and
## label global_positions map straight to world space with no transform bookkeeping. Nothing here touches gameplay;
## it only reads positions handed to it and draws. Debug/play only — NavDebugOverlay never builds it in the editor.

## Draw lines/labels IGNORING depth so they read THROUGH walls (the usual debug default — you want to see a cone
## behind a building). Set by the overlay before the first frame; live changes re-stamp the material + labels.
@export var draw_through_walls: bool = true: set = set_draw_through_walls
## On-screen size of the billboard labels (they are fixed_size, so this is a screen-space pixel scale, not metres).
@export var label_font_size: int = 32: set = set_label_font_size

var _mesh: ImmediateMesh = null
var _mi: MeshInstance3D = null
var _mat: StandardMaterial3D = null
## Accumulated segment endpoints + per-vertex colours for THIS frame; flushed to the mesh in end().
var _verts := PackedVector3Array()
var _cols := PackedColorArray()
## Pooled billboard labels, reused frame to frame. `_label_cursor` is how many were claimed this frame; the rest are
## hidden in end() (kept alive, not freed, so a steady NPC count never churns Label3D allocations).
var _labels: Array[Label3D] = []
var _label_cursor: int = 0


func _ready() -> void:
	# Keep this node at the origin so world-space verts/positions need no local<->world conversion.
	transform = Transform3D.IDENTITY
	_mesh = ImmediateMesh.new()
	_mi = MeshInstance3D.new()
	_mi.name = "Lines"
	_mi.mesh = _mesh
	_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_mat = StandardMaterial3D.new()
	_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED       # flat vertex colour, no lighting on debug lines
	_mat.vertex_color_use_as_albedo = true                        # per-segment colour comes from surface_set_color
	_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA         # honour the alpha in each layer's colour
	_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_mat.disable_receive_shadows = true
	_mat.no_depth_test = draw_through_walls
	_mi.material_override = _mat
	add_child(_mi)


# --- per-frame API (called by NavDebugOverlay) -----------------------------------------------------------------

## Start a fresh frame: drop last frame's segments and rewind the label pool to the start.
func begin() -> void:
	_verts.clear()
	_cols.clear()
	_label_cursor = 0


## Buffer wire segments. `pts` is in PAIR format (consecutive points = one segment), already in WORLD space (bake
## any transform in via WireShapes' `x` argument). No-op for an odd/empty array's trailing point.
func add_lines(pts: PackedVector3Array, color: Color) -> void:
	var n := pts.size() - (pts.size() & 1)  # drop a dangling odd vertex so we always add whole segments
	for i in n:
		_verts.append(pts[i])
		_cols.append(color)


## Draw `text` as a billboard at world `pos`, claiming the next pooled Label3D (growing the pool on demand). Only
## re-sets the text when it changed, so a label whose string is stable doesn't re-rasterize every frame.
func add_label(pos: Vector3, text: String, color: Color = Color.WHITE) -> void:
	var lbl: Label3D
	if _label_cursor < _labels.size():
		lbl = _labels[_label_cursor]
	else:
		lbl = _make_label()
		_labels.append(lbl)
	_label_cursor += 1
	if lbl.text != text:
		lbl.text = text
	if lbl.font_size != label_font_size:
		lbl.font_size = label_font_size
		lbl.outline_size = maxi(1, label_font_size / 6)
	lbl.modulate = color
	lbl.visible = true
	lbl.global_position = pos


## Commit the frame: flush buffered segments into one ImmediateMesh surface and hide any labels not claimed. Guarded
## so a frame with no lines emits no (empty) surface — surface_begin/end with zero vertices is invalid.
func end() -> void:
	_mesh.clear_surfaces()
	if _verts.size() >= 2:
		_mesh.surface_begin(Mesh.PRIMITIVE_LINES)
		for i in _verts.size():
			_mesh.surface_set_color(_cols[i])
			_mesh.surface_add_vertex(_verts[i])
		_mesh.surface_end()
	for i in range(_label_cursor, _labels.size()):
		_labels[i].visible = false


# --- config setters --------------------------------------------------------------------------------------------

func set_draw_through_walls(v: bool) -> void:
	draw_through_walls = v
	if _mat != null:
		_mat.no_depth_test = v
	for lbl in _labels:
		lbl.no_depth_test = v


func set_label_font_size(v: int) -> void:
	label_font_size = maxi(1, v)
	# add_label() re-applies per label as it's claimed; existing labels are updated in place next frame.


# --- internals -------------------------------------------------------------------------------------------------

## A fresh billboard label: constant on-screen size (fixed_size), camera-facing, with an outline for legibility on
## any background. pixel_size is tiny because fixed_size scales the glyph by pixel_size * font_size in screen space.
func _make_label() -> Label3D:
	var lbl := Label3D.new()
	lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	lbl.fixed_size = true
	lbl.pixel_size = 0.0006
	lbl.no_depth_test = draw_through_walls
	lbl.font_size = label_font_size
	lbl.outline_size = maxi(1, label_font_size / 6)
	lbl.outline_modulate = Color(0, 0, 0, 0.85)
	lbl.render_priority = 2       # draw over the wire lines
	lbl.outline_render_priority = 1
	add_child(lbl)
	return lbl
