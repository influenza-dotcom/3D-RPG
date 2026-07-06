@tool
extends RefCounted

## PROCEDURAL stand-in models for items with NO authored model — so the icon baker can render EVERY item and no
## tile ever falls back to a letter glyph. Each builder composes engine primitives (cylinders / boxes / spheres +
## StandardMaterial3D) into a small Node3D the baker frames exactly like a real mesh: ammo -> cartridges keyed by
## caliber, healing consumable -> a medkit, MISC -> a keyword-matched trinket (scope / dog-tags / syringe / ...)
## with a tinted pouch as the last resort. These are deliberate PLACEHOLDERS with the same lighting/framing as
## authored icons: the moment a designer sets `world_model` (or `Item.icon`) on the .tres, that wins and the
## stand-in stops being used (icon_baker.bake_item prefers authored models). Pure node-building — no renderer
## needed, so it's GUT-testable headless. Deterministic: same item -> same model (fallback hue hashes the id).

## Build the stand-in for `item`, or null for a null item. The result is an orphan Node3D (no scripts anywhere);
## the caller parents + frees it (the baker's capture viewport does both).
static func build_for(item: Item) -> Node3D:
	if item == null:
		return null
	var root := Node3D.new()
	root.name = "IconStandin"
	if item.is_ammo():
		_build_ammo(root, item.caliber)
	elif item.is_consumable():
		if item.heal_amount > 0.0:
			_build_medkit(root)
		else:
			_build_syringe(root)
	else:
		_build_misc(root, item)
	return root


# ---------------------------------------------------------------------------------------------------
# Ammo — "a clip of rounds", keyed by caliber so pistol / rifle / shells / grenades read differently
# ---------------------------------------------------------------------------------------------------

static func _build_ammo(root: Node3D, caliber: StringName) -> void:
	var c := String(caliber)
	if c.contains("shell"):
		for i in 3:
			_shotshell(root, (i - 1) * 0.30, absf(float(i - 1)) * 0.10, (i - 1) * 4.0)
	elif c.contains("grenade"):
		_grenade_round(root, -0.20, 6.0)
		_grenade_round(root, 0.20, -4.0)
	elif c.contains("rifle") or c.contains("sniper"):
		for i in 3:
			_cartridge(root, (i - 1) * 0.24, absf(float(i - 1)) * 0.08, 0.78, 0.085, 0.30, (i - 1) * 4.0)
	elif c.contains("smg"):
		for i in 4:
			_cartridge(root, (float(i) - 1.5) * 0.20, absf(float(i) - 1.5) * 0.05, 0.46, 0.080, 0.16, (float(i) - 1.5) * 3.0)
	else:  # pistol + any future sidearm caliber
		for i in 3:
			_cartridge(root, (i - 1) * 0.24, absf(float(i - 1)) * 0.08, 0.50, 0.095, 0.17, (i - 1) * 4.0)


## One standing brass cartridge (case + copper tip) leaning `lean_deg` about Z, under its own pivot so the lean
## can't shear the tip off the case.
static func _cartridge(root: Node3D, x: float, z: float, case_h: float, case_r: float, tip_h: float, lean_deg: float) -> void:
	var pivot := _pivot(root, Vector3(x, 0.0, z), lean_deg)
	var case := CylinderMesh.new()
	case.top_radius = case_r * 0.92
	case.bottom_radius = case_r
	case.height = case_h
	_mesh(pivot, case, Vector3(0.0, case_h * 0.5, 0.0), _mat(Color(0.80, 0.64, 0.30), 0.35, 0.35))
	var tip := CylinderMesh.new()
	tip.top_radius = case_r * 0.22
	tip.bottom_radius = case_r * 0.80
	tip.height = tip_h
	_mesh(pivot, tip, Vector3(0.0, case_h + tip_h * 0.5, 0.0), _mat(Color(0.70, 0.42, 0.28), 0.35, 0.40))


static func _shotshell(root: Node3D, x: float, z: float, lean_deg: float) -> void:
	var pivot := _pivot(root, Vector3(x, 0.0, z), lean_deg)
	var hull := CylinderMesh.new()
	hull.top_radius = 0.105
	hull.bottom_radius = 0.105
	hull.height = 0.46
	_mesh(pivot, hull, Vector3(0.0, 0.14 + 0.23, 0.0), _mat(Color(0.75, 0.16, 0.14), 0.0, 0.55))
	var base := CylinderMesh.new()
	base.top_radius = 0.112
	base.bottom_radius = 0.112
	base.height = 0.14
	_mesh(pivot, base, Vector3(0.0, 0.07, 0.0), _mat(Color(0.80, 0.64, 0.30), 0.35, 0.35))


static func _grenade_round(root: Node3D, x: float, lean_deg: float) -> void:
	var pivot := _pivot(root, Vector3(x, 0.0, 0.0), lean_deg)
	var body := CylinderMesh.new()
	body.top_radius = 0.15
	body.bottom_radius = 0.15
	body.height = 0.34
	_mesh(pivot, body, Vector3(0.0, 0.17, 0.0), _mat(Color(0.80, 0.64, 0.30), 0.35, 0.35))
	var head := SphereMesh.new()
	head.radius = 0.15
	head.height = 0.22
	_mesh(pivot, head, Vector3(0.0, 0.34 + 0.05, 0.0), _mat(Color(0.38, 0.44, 0.30), 0.1, 0.55))


# ---------------------------------------------------------------------------------------------------
# Consumables
# ---------------------------------------------------------------------------------------------------

## A white first-aid case with a red cross laid into the lid.
static func _build_medkit(root: Node3D) -> void:
	var shell := _mat(Color(0.92, 0.92, 0.90), 0.0, 0.45)
	var red := _mat(Color(0.78, 0.12, 0.12), 0.0, 0.5)
	_mesh(root, _box(0.90, 0.50, 0.42), Vector3(0.0, 0.25, 0.0), shell)
	_mesh(root, _box(0.94, 0.06, 0.46), Vector3(0.0, 0.34, 0.0), _mat(Color(0.70, 0.70, 0.68), 0.0, 0.5))  # lid seam
	_mesh(root, _box(0.40, 0.03, 0.13), Vector3(0.0, 0.515, 0.0), red)
	_mesh(root, _box(0.13, 0.03, 0.40), Vector3(0.0, 0.515, 0.0), red)
	_mesh(root, _box(0.16, 0.10, 0.44), Vector3(0.0, 0.53, 0.0), shell)  # handle hump the cross sits beside
	# nudge the handle off-centre so it doesn't z-fight the cross
	(root.get_child(root.get_child_count() - 1) as Node3D).position.x = -0.34


## A stim syringe: body, plunger, needle, dose band — the generic "chemical consumable" read.
static func _build_syringe(root: Node3D) -> void:
	var pivot := _pivot(root, Vector3.ZERO, 18.0)
	var body := CylinderMesh.new()
	body.top_radius = 0.09
	body.bottom_radius = 0.09
	body.height = 0.55
	_mesh(pivot, body, Vector3(0.0, 0.42, 0.0), _mat(Color(0.85, 0.90, 0.92), 0.0, 0.25))
	var band := CylinderMesh.new()
	band.top_radius = 0.095
	band.bottom_radius = 0.095
	band.height = 0.10
	_mesh(pivot, band, Vector3(0.0, 0.34, 0.0), _mat(Color(0.95, 0.55, 0.15), 0.0, 0.5))
	var plunger := CylinderMesh.new()
	plunger.top_radius = 0.11
	plunger.bottom_radius = 0.11
	plunger.height = 0.05
	_mesh(pivot, plunger, Vector3(0.0, 0.72, 0.0), _mat(Color(0.30, 0.32, 0.36), 0.1, 0.5))
	var needle := CylinderMesh.new()
	needle.top_radius = 0.012
	needle.bottom_radius = 0.012
	needle.height = 0.22
	_mesh(pivot, needle, Vector3(0.0, 0.045, 0.0), _mat(Color(0.75, 0.78, 0.82), 0.6, 0.25))


# ---------------------------------------------------------------------------------------------------
# MISC — keyword-matched trinkets for the shipped passives (+ lockpick / package), else a tinted pouch
# ---------------------------------------------------------------------------------------------------

static func _build_misc(root: Node3D, item: Item) -> void:
	var key := String(item.id).to_lower()
	if key.contains("lockpick"):
		_build_lockpick(root)
	elif key.contains("package") or key.contains("parcel"):
		_build_package(root)
	elif key.contains("optic") or key.contains("scope"):
		_build_optic(root)
	elif key.contains("plate") or key.contains("armor"):
		_build_plate(root)
	elif key.contains("locket") or key.contains("amulet"):
		_build_locket(root)
	elif key.contains("tags"):
		_build_dogtags(root)
	elif key.contains("stim"):
		_build_syringe(root)
	elif key.contains("cell") or key.contains("battery"):
		_build_battery(root)
	elif key.contains("bone"):
		_build_bone(root)
	elif key.contains("weave") or key.contains("cloth"):
		_build_weave(root)
	elif key.contains("grin") or key.contains("teeth"):
		_build_grin(root)
	elif key.contains("rig") or key.contains("pack"):
		_build_rig(root)
	else:
		_build_pouch(root, item.id)


static func _build_lockpick(root: Node3D) -> void:
	var steel := _mat(Color(0.72, 0.74, 0.78), 0.5, 0.3)
	var p1 := _pivot(root, Vector3(0.0, 0.30, 0.0), 58.0)   # the pick, leaning hard
	_mesh(p1, _box(0.045, 0.85, 0.03), Vector3.ZERO, steel)
	_mesh(p1, _box(0.10, 0.06, 0.03), Vector3(0.03, 0.44, 0.0), steel)      # bent tip
	var p2 := _pivot(root, Vector3(0.05, 0.26, 0.06), -50.0)  # the L torsion wrench, crossed the other way
	_mesh(p2, _box(0.045, 0.70, 0.03), Vector3.ZERO, steel)
	_mesh(p2, _box(0.22, 0.045, 0.03), Vector3(0.09, -0.33, 0.0), steel)


static func _build_package(root: Node3D) -> void:
	var paper := _mat(Color(0.62, 0.47, 0.30), 0.0, 0.7)
	var tape := _mat(Color(0.82, 0.78, 0.66), 0.0, 0.5)
	_mesh(root, _box(1.00, 0.38, 0.55), Vector3(0.0, 0.19, 0.0), paper)
	_mesh(root, _box(1.02, 0.40, 0.16), Vector3(0.0, 0.19, 0.0), tape)   # tape band around the girth
	_mesh(root, _box(0.16, 0.40, 0.57), Vector3(-0.22, 0.19, 0.0), tape)


static func _build_optic(root: Node3D) -> void:
	var metal := _mat(Color(0.30, 0.33, 0.38), 0.2, 0.4)
	var pivot := _pivot(root, Vector3(0.0, 0.22, 0.0), 90.0)  # a scope lying on its side
	var tube := CylinderMesh.new()
	tube.top_radius = 0.13
	tube.bottom_radius = 0.13
	tube.height = 0.75
	_mesh(pivot, tube, Vector3.ZERO, metal)
	for end_y in [-0.34, 0.34]:
		var bell := CylinderMesh.new()
		bell.top_radius = 0.17
		bell.bottom_radius = 0.17
		bell.height = 0.14
		_mesh(pivot, bell, Vector3(0.0, float(end_y), 0.0), metal)
	var lens := CylinderMesh.new()
	lens.top_radius = 0.145
	lens.bottom_radius = 0.145
	lens.height = 0.02
	_mesh(pivot, lens, Vector3(0.0, 0.415, 0.0), _mat(Color(0.25, 0.45, 0.75), 0.6, 0.1))
	var knob := CylinderMesh.new()
	knob.top_radius = 0.07
	knob.bottom_radius = 0.07
	knob.height = 0.10
	var k := _mesh(pivot, knob, Vector3(0.0, 0.06, 0.16), metal)
	k.rotation_degrees = Vector3(90.0, 0.0, 0.0)


static func _build_plate(root: Node3D) -> void:
	var steel := _mat(Color(0.36, 0.40, 0.46), 0.4, 0.45)
	_mesh(root, _box(0.72, 0.88, 0.10), Vector3(0.0, 0.44, 0.0), steel)
	_mesh(root, _box(0.60, 0.74, 0.05), Vector3(0.0, 0.44, 0.08), _mat(Color(0.30, 0.33, 0.38), 0.4, 0.5))  # raised centre
	for sx in [-0.26, 0.26]:
		_mesh(root, _box(0.14, 0.98, 0.04), Vector3(float(sx), 0.44, -0.06), _mat(Color(0.16, 0.17, 0.18), 0.0, 0.8))  # straps


static func _build_locket(root: Node3D) -> void:
	var iron := _mat(Color(0.45, 0.46, 0.50), 0.5, 0.35)
	var ring := TorusMesh.new()
	ring.inner_radius = 0.16
	ring.outer_radius = 0.22
	var r := _mesh(root, ring, Vector3(0.0, 0.78, 0.0), iron)   # the chain loop, facing the camera
	r.rotation_degrees = Vector3(90.0, 0.0, 0.0)
	var pendant := SphereMesh.new()
	pendant.radius = 0.26
	pendant.height = 0.52
	var p := _mesh(root, pendant, Vector3(0.0, 0.30, 0.0), iron)
	p.scale = Vector3(1.0, 1.05, 0.45)                          # flattened heart-ish medallion
	var bail := CylinderMesh.new()
	bail.top_radius = 0.05
	bail.bottom_radius = 0.05
	bail.height = 0.10
	_mesh(root, bail, Vector3(0.0, 0.60, 0.0), iron)


static func _build_dogtags(root: Node3D) -> void:
	var steel := _mat(Color(0.70, 0.72, 0.76), 0.5, 0.3)
	var ring := TorusMesh.new()
	ring.inner_radius = 0.12
	ring.outer_radius = 0.16
	var r := _mesh(root, ring, Vector3(0.0, 0.80, 0.0), steel)
	r.rotation_degrees = Vector3(90.0, 0.0, 0.0)
	var t1 := _pivot(root, Vector3(-0.08, 0.34, 0.04), 6.0)
	_mesh(t1, _box(0.30, 0.50, 0.025), Vector3.ZERO, steel)
	var t2 := _pivot(root, Vector3(0.14, 0.30, -0.09), -8.0)
	_mesh(t2, _box(0.30, 0.50, 0.025), Vector3.ZERO, _mat(Color(0.58, 0.60, 0.64), 0.5, 0.35))


static func _build_battery(root: Node3D) -> void:
	var body := CylinderMesh.new()
	body.top_radius = 0.20
	body.bottom_radius = 0.20
	body.height = 0.62
	_mesh(root, body, Vector3(0.0, 0.31, 0.0), _mat(Color(0.16, 0.55, 0.45), 0.1, 0.45))
	var band := CylinderMesh.new()
	band.top_radius = 0.205
	band.bottom_radius = 0.205
	band.height = 0.12
	_mesh(root, band, Vector3(0.0, 0.56, 0.0), _mat(Color(0.85, 0.87, 0.90), 0.3, 0.35))
	var terminal := CylinderMesh.new()
	terminal.top_radius = 0.07
	terminal.bottom_radius = 0.07
	terminal.height = 0.08
	_mesh(root, terminal, Vector3(0.0, 0.66, 0.0), _mat(Color(0.75, 0.78, 0.82), 0.6, 0.25))
	_mesh(root, _box(0.26, 0.10, 0.005), Vector3(0.0, 0.30, 0.205), _mat(Color(0.95, 0.92, 0.25), 0.0, 0.5))  # charge stripe


static func _build_bone(root: Node3D) -> void:
	var ivory := _mat(Color(0.88, 0.85, 0.76), 0.0, 0.6)
	var pivot := _pivot(root, Vector3(0.0, 0.24, 0.0), 65.0)
	var shaft := CylinderMesh.new()
	shaft.top_radius = 0.09
	shaft.bottom_radius = 0.09
	shaft.height = 0.62
	_mesh(pivot, shaft, Vector3.ZERO, ivory)
	for end_y in [-0.31, 0.31]:
		for dz in [-0.08, 0.08]:
			var knob := SphereMesh.new()
			knob.radius = 0.13
			knob.height = 0.26
			_mesh(pivot, knob, Vector3(0.0, float(end_y), float(dz)), ivory)


static func _build_weave(root: Node3D) -> void:
	var cloth := _mat(Color(0.30, 0.55, 0.58), 0.0, 0.75)
	var cloth2 := _mat(Color(0.26, 0.48, 0.52), 0.0, 0.75)
	_mesh(root, _box(0.85, 0.14, 0.60), Vector3(0.0, 0.07, 0.0), cloth)
	_mesh(root, _box(0.78, 0.14, 0.52), Vector3(0.04, 0.20, -0.03), cloth2)
	_mesh(root, _box(0.68, 0.14, 0.44), Vector3(-0.03, 0.33, 0.03), cloth)
	var tie := _mesh(root, _box(0.90, 0.05, 0.10), Vector3(0.0, 0.22, 0.0), _mat(Color(0.80, 0.78, 0.70), 0.0, 0.6))
	tie.rotation_degrees = Vector3(0.0, 0.0, 4.0)


static func _build_grin(root: Node3D) -> void:
	var chrome := _mat(Color(0.80, 0.83, 0.88), 0.8, 0.15)
	var gum := _mat(Color(0.55, 0.25, 0.28), 0.0, 0.55)
	_mesh(root, _box(0.78, 0.14, 0.22), Vector3(0.0, 0.30, 0.0), gum)
	for i in 5:
		_mesh(root, _box(0.115, 0.18, 0.16), Vector3((float(i) - 2.0) * 0.145, 0.16, 0.0), chrome)


static func _build_rig(root: Node3D) -> void:
	var canvas := _mat(Color(0.45, 0.42, 0.30), 0.0, 0.75)
	var strap := _mat(Color(0.22, 0.20, 0.16), 0.0, 0.8)
	_mesh(root, _box(0.70, 0.80, 0.34), Vector3(0.0, 0.40, 0.0), canvas)
	_mesh(root, _box(0.44, 0.34, 0.12), Vector3(0.0, 0.26, 0.22), _mat(Color(0.40, 0.37, 0.27), 0.0, 0.75))  # front pocket
	for sx in [-0.22, 0.22]:
		_mesh(root, _box(0.12, 0.86, 0.05), Vector3(float(sx), 0.42, -0.19), strap)


## Last-resort trinket: a small strapped pouch tinted deterministically from the item id, so even a brand-new
## MISC item bakes as SOMETHING inventory-shaped (never a letter) until it gets a real model.
static func _build_pouch(root: Node3D, id: StringName) -> void:
	var hue := float(String(id).hash() % 360) / 360.0
	var tint := Color.from_hsv(hue, 0.45, 0.60)
	_mesh(root, _box(0.72, 0.50, 0.34), Vector3(0.0, 0.25, 0.0), _mat(tint, 0.0, 0.7))
	_mesh(root, _box(0.74, 0.18, 0.36), Vector3(0.0, 0.48, 0.0), _mat(tint.darkened(0.25), 0.0, 0.7))  # flap
	var button := SphereMesh.new()
	button.radius = 0.05
	button.height = 0.10
	_mesh(root, button, Vector3(0.0, 0.40, 0.19), _mat(Color(0.75, 0.78, 0.82), 0.5, 0.3))


# ---------------------------------------------------------------------------------------------------
# Primitive helpers
# ---------------------------------------------------------------------------------------------------

static func _pivot(parent: Node3D, pos: Vector3, lean_z_deg: float) -> Node3D:
	var p := Node3D.new()
	parent.add_child(p)
	p.position = pos
	p.rotation_degrees = Vector3(0.0, 0.0, lean_z_deg)
	return p


static func _mesh(parent: Node3D, mesh: Mesh, pos: Vector3, mat: StandardMaterial3D) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	parent.add_child(mi)
	mi.position = pos
	return mi


static func _box(w: float, h: float, d: float) -> BoxMesh:
	var b := BoxMesh.new()
	b.size = Vector3(w, h, d)
	return b


## Low metallic on purpose: the bake world has only ambient + one key light (no reflections), so high metallic
## renders near-black there.
static func _mat(albedo: Color, metallic: float = 0.0, roughness: float = 0.6) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = albedo
	m.metallic = metallic
	m.roughness = roughness
	return m
