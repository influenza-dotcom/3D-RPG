@tool
extends RefCounted

## PURE render math for the item-icon baker (icon_baker.gd uses these; they're unit-tested with no renderer). The
## actual SubViewport render is editor-only and lives in icon_baker; this is the framing/sizing it depends on.

## Icon pixel size for an item's grid footprint: grid_w × grid_h cells at `cell` px each (square cells), so a 2×1
## item gets a 2:1 icon that "fits the boxes it takes up". Each dimension is at least one cell.
static func pixel_size(grid_w: int, grid_h: int, cell: int) -> Vector2i:
	return Vector2i(maxi(1, grid_w) * maxi(1, cell), maxi(1, grid_h) * maxi(1, cell))


## Normalize a mesh AABB to a unit box centred on the origin (mirrors item_mesh_view._normalize): returns
## {scale, offset, ext} where applying `scale` then `offset` lands the box centre on the origin and makes its
## largest dimension 1.0. `ext` is the resulting (normalized) extents — fed to fit_ortho_size. Degenerate AABB -> unit.
static func normalize(aabb: AABB) -> Dictionary:
	var maxdim := maxf(aabb.size.x, maxf(aabb.size.y, aabb.size.z))
	if maxdim <= 0.00001:
		return {"scale": 1.0, "offset": Vector3.ZERO, "ext": Vector3.ONE}
	var s := 1.0 / maxdim
	return {"scale": s, "offset": -(aabb.position + aabb.size * 0.5) * s, "ext": aabb.size * s}


## The orthographic camera `size` (view HEIGHT, KEEP_HEIGHT) that frames the origin-centred box `ext` to a viewport
## of `aspect` (width/height) seen from `cam_transform`. Projects the box's 8 corners into camera space and fits
## BOTH axes, so a long sniper and a chunky pistol each fill their own icon. `air` pads it (1.15 = 15% margin).
## Clamped as an anti-explosion safety net. Pure — mirrors item_mesh_view._frame so baked icons match the live tile.
static func fit_ortho_size(cam_transform: Transform3D, ext: Vector3, aspect: float, air: float = 1.15) -> float:
	var inv := cam_transform.affine_inverse()
	var half := ext * 0.5
	var hw := 0.0  # half-width of the footprint in the camera's view plane
	var hh := 0.0  # half-height
	for i in 8:
		var corner := Vector3(half.x if (i & 1) else -half.x, half.y if (i & 2) else -half.y, half.z if (i & 4) else -half.z)
		var cv := inv * corner
		hw = maxf(hw, absf(cv.x))
		hh = maxf(hh, absf(cv.y))
	var a := maxf(0.05, aspect)
	return clampf(maxf(2.0 * hh, 2.0 * hw / a) * air, 0.2, 4.0)
