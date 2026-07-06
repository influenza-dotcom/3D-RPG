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


## PASS-2 camera refit from MEASURED pixels: given the first render's used (non-transparent) rect, the ortho
## size that makes the art fill the frame and the lateral camera shift (in the camera's own view plane, world
## units) that centres it. The AABB-driven first fit only has to land the art SOMEWHERE in frame — real GLBs
## carry polluted bounds (the pistol scene's box is ~356 units across for a handgun-sized mesh) — so the baker
## re-frames from what actually drew and re-renders at full resolution instead of crop-and-upscale. `pad` leaves
## breathing room (1.06 = 6%). dx/dy are measured under `cam_size` (the OLD framing) — apply BOTH together.
## A degenerate `used`/image returns the inputs unchanged (no zoom, no shift).
static func refit(cam_size: float, aspect: float, used: Rect2i, img_size: Vector2i, pad: float = 1.06) -> Dictionary:
	if used.size.x <= 0 or used.size.y <= 0 or img_size.x <= 0 or img_size.y <= 0:
		return {"size": cam_size, "dx": 0.0, "dy": 0.0}
	var a := maxf(0.05, aspect)
	var fw := float(used.size.x) / float(img_size.x)   # fraction of the render the art spans, per axis
	var fh := float(used.size.y) / float(img_size.y)
	# Ortho `size` is view HEIGHT; view width = size × aspect — so filling EITHER axis needs size × that fraction.
	var size2 := clampf(cam_size * maxf(fh, fw) * pad, 0.05, 4.0)
	var cx := float(used.position.x) + float(used.size.x) * 0.5
	var cy := float(used.position.y) + float(used.size.y) * 0.5
	var dx := (cx / float(img_size.x) - 0.5) * cam_size * a   # art right of centre -> move the camera right
	var dy := -(cy / float(img_size.y) - 0.5) * cam_size      # screen y grows DOWN, camera-plane y grows UP
	return {"size": size2, "dx": dx, "dy": dy}


## The sub-rect of a baked render to KEEP (the autocrop): the `used` non-transparent pixels, padded by
## `margin_frac` of their larger side, then GROWN to the target `aspect` (w/h) so the final resize to the
## footprint never stretches the art. The AABB-driven camera fit above always leaves air — a 3/4-view BOX
## projects wider than the mesh's silhouette — so the baker renders loose, then crops to the actual pixels
## with this. Growth is centred, then SHIFTED (not shrunk) back inside the image; when the image itself is
## too small on an axis it clamps there (a slight aspect error the resize absorbs). An empty `used` rect
## (nothing rendered) returns the full image — callers treat that render as failed anyway.
static func crop_rect(used: Rect2i, img_size: Vector2i, aspect: float, margin_frac: float = 0.06) -> Rect2i:
	if used.size.x <= 0 or used.size.y <= 0 or img_size.x <= 0 or img_size.y <= 0:
		return Rect2i(Vector2i.ZERO, img_size)
	var a := maxf(0.05, aspect)
	var margin := int(ceilf(float(maxi(used.size.x, used.size.y)) * maxf(0.0, margin_frac)))
	var w := used.size.x + margin * 2
	var h := used.size.y + margin * 2
	# Grow the SHORT axis out to the target aspect (never shrink an axis — art must stay inside the crop).
	if float(w) < float(h) * a:
		w = int(ceilf(float(h) * a))
	else:
		h = int(ceilf(float(w) / a))
	w = mini(w, img_size.x)
	h = mini(h, img_size.y)
	var x := used.position.x + (used.size.x - w) / 2  # centre the growth on the used pixels
	var y := used.position.y + (used.size.y - h) / 2
	x = clampi(x, 0, img_size.x - w)
	y = clampi(y, 0, img_size.y - h)
	return Rect2i(x, y, w, h)
