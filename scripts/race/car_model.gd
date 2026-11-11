class_name CarModel
extends Node3D
## Stylized low-poly car built from primitives. Faces +Z. Silhouettes differ per car type:
## Buggy = open roll cage + wide exposed wheels; Bruiser = boxy body + heavy front bumper.

const STRIPE := Color("f2ead8")
const DARK := Color("2a2622")
const TIRE := Color("1d1b1a")
const RIM := Color("b9b2a6")

var car_type := "buggy"
var color := Color.WHITE
var front_wheels: Array[Node3D] = []
var wheels: Array[Node3D] = []
var body_mats: Array[StandardMaterial3D] = []
var body_root: Node3D
var _flash := 0.0
var _wheel_spin := 0.0


static func mat(c: Color, rough := 0.75, metal := 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	m.metallic = metal
	return m


func setup(type: String, body_color: Color, with_stripe: bool) -> void:
	car_type = type
	color = body_color
	body_root = Node3D.new()
	add_child(body_root)
	if type == "bruiser":
		_build_bruiser(with_stripe)
	else:
		_build_buggy(with_stripe)


func _box(size: Vector3, pos: Vector3, m: Material, parent: Node3D = null, rot := Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = m
	mi.position = pos
	mi.rotation = rot
	(parent if parent else body_root).add_child(mi)
	return mi


func _wheel(pos: Vector3, radius: float, width: float, front: bool) -> void:
	var pivot := Node3D.new()
	pivot.position = pos
	add_child(pivot)
	var spin := Node3D.new()
	pivot.add_child(spin)
	var tire := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = radius
	cm.bottom_radius = radius
	cm.height = width
	cm.radial_segments = 14
	tire.mesh = cm
	tire.rotation.z = PI / 2
	tire.material_override = mat(TIRE, 0.95)
	spin.add_child(tire)
	var hub := MeshInstance3D.new()
	var hm := CylinderMesh.new()
	hm.top_radius = radius * 0.5
	hm.bottom_radius = radius * 0.5
	hm.height = width + 0.04
	hm.radial_segments = 8
	hub.mesh = hm
	hub.rotation.z = PI / 2
	hub.material_override = mat(RIM, 0.4, 0.6)
	spin.add_child(hub)
	wheels.append(spin)
	if front:
		front_wheels.append(pivot)


func _body_mat(c: Color) -> StandardMaterial3D:
	var m := mat(c, 0.55, 0.15)
	body_mats.append(m)
	return m


func _build_buggy(stripe: bool) -> void:
	var body := _body_mat(color)
	var dark := mat(DARK, 0.8)
	var cage := mat(Color("3a3632"), 0.5, 0.5)
	# low flat tub + wedge nose
	_box(Vector3(1.5, 0.32, 3.4), Vector3(0, 0.55, 0), body)
	_box(Vector3(1.4, 0.22, 0.9), Vector3(0, 0.66, 1.75), body, null, Vector3(-0.35, 0, 0))
	_box(Vector3(1.9, 0.1, 0.7), Vector3(0, 0.45, 1.95), dark)               # skid plate
	# side pods over wheels
	_box(Vector3(0.18, 0.18, 3.0), Vector3(0.78, 0.72, 0), body)
	_box(Vector3(0.18, 0.18, 3.0), Vector3(-0.78, 0.72, 0), body)
	# seat + engine block
	_box(Vector3(0.7, 0.5, 0.6), Vector3(0, 0.95, -0.35), dark)
	_box(Vector3(1.0, 0.45, 0.8), Vector3(0, 0.9, -1.35), mat(Color("4a4540"), 0.5, 0.6))
	# open roll cage: four posts + rails + roof panel
	for x in [-0.62, 0.62]:
		for z in [0.35, -0.85]:
			_box(Vector3(0.09, 1.0, 0.09), Vector3(x, 1.2, z), cage)
		_box(Vector3(0.09, 0.09, 1.3), Vector3(x, 1.7, -0.25), cage)
		_box(Vector3(0.09, 0.09, 1.0), Vector3(x, 1.25, 0.85), cage, null, Vector3(-0.85, 0, 0))
	_box(Vector3(1.33, 0.09, 0.09), Vector3(0, 1.7, 0.35), cage)
	_box(Vector3(1.33, 0.09, 0.09), Vector3(0, 1.7, -0.85), cage)
	_box(Vector3(1.3, 0.06, 1.25), Vector3(0, 1.74, -0.25), body)           # roof panel
	if stripe:
		_box(Vector3(0.55, 0.07, 1.27), Vector3(0, 1.76, -0.25), mat(STRIPE, 0.5))
		_box(Vector3(0.55, 0.05, 3.42), Vector3(0, 0.72, 0), mat(STRIPE, 0.5))
	# rear wing
	_box(Vector3(1.6, 0.06, 0.4), Vector3(0, 1.35, -1.85), body)
	_box(Vector3(0.06, 0.5, 0.3), Vector3(0.6, 1.1, -1.8), dark)
	_box(Vector3(0.06, 0.5, 0.3), Vector3(-0.6, 1.1, -1.8), dark)
	# wide exposed wheels
	for x in [-1.12, 1.12]:
		_wheel(Vector3(x, 0.5, 1.25), 0.5, 0.55, true)
		_wheel(Vector3(x, 0.52, -1.25), 0.52, 0.62, false)


func _build_bruiser(stripe: bool) -> void:
	var body := _body_mat(color)
	var dark := mat(DARK, 0.8)
	var steel := mat(Color("55504a"), 0.45, 0.7)
	var glass := mat(Color("1e2a30"), 0.2, 0.3)
	# boxy armored hull
	_box(Vector3(2.15, 0.85, 4.0), Vector3(0, 0.95, -0.05), body)
	_box(Vector3(1.8, 0.62, 2.0), Vector3(0, 1.68, -0.45), body)            # cabin
	_box(Vector3(1.82, 0.4, 0.06), Vector3(0, 1.72, 0.56), glass)          # windshield
	_box(Vector3(0.06, 0.32, 1.6), Vector3(0.91, 1.72, -0.45), glass)
	_box(Vector3(0.06, 0.32, 1.6), Vector3(-0.91, 1.72, -0.45), glass)
	if stripe:
		_box(Vector3(0.75, 0.05, 2.02), Vector3(0, 2.0, -0.45), mat(STRIPE, 0.5))
		_box(Vector3(0.75, 0.05, 1.2), Vector3(0, 1.39, 1.35), mat(STRIPE, 0.5))
	# heavy front bumper / ram
	_box(Vector3(2.5, 0.5, 0.45), Vector3(0, 0.7, 2.2), steel)
	_box(Vector3(0.25, 0.7, 0.3), Vector3(0.7, 0.85, 2.05), steel)
	_box(Vector3(0.25, 0.7, 0.3), Vector3(-0.7, 0.85, 2.05), steel)
	# armor plates on sides
	_box(Vector3(0.1, 0.45, 2.6), Vector3(1.12, 0.95, -0.1), steel)
	_box(Vector3(0.1, 0.45, 2.6), Vector3(-1.12, 0.95, -0.1), steel)
	_box(Vector3(2.2, 0.35, 0.3), Vector3(0, 0.75, -2.1), dark)            # rear bumper
	# exhaust stacks
	_box(Vector3(0.14, 0.7, 0.14), Vector3(0.75, 2.0, -1.5), steel)
	_box(Vector3(0.14, 0.7, 0.14), Vector3(-0.75, 2.0, -1.5), steel)
	for x in [-1.0, 1.0]:
		_wheel(Vector3(x, 0.52, 1.35), 0.52, 0.45, true)
		_wheel(Vector3(x, 0.52, -1.35), 0.52, 0.45, false)


## Visual update. steer -1..1 (+right), speed m/s, roll/pitch radians.
func animate(delta: float, steer: float, speed: float, roll: float, pitch: float) -> void:
	for fw in front_wheels:
		fw.rotation.y = lerpf(fw.rotation.y, -steer * 0.45, minf(1.0, delta * 12.0))
	_wheel_spin += speed / 0.5 * delta
	for w in wheels:
		w.rotation.x = _wheel_spin
	body_root.rotation.z = lerpf(body_root.rotation.z, roll, minf(1.0, delta * 8.0))
	body_root.rotation.x = lerpf(body_root.rotation.x, pitch, minf(1.0, delta * 8.0))
	if _flash > 0.0:
		_flash = maxf(0.0, _flash - delta * 6.0)
		for m in body_mats:
			m.albedo_color = color.lerp(Color.WHITE, _flash)
			m.emission_enabled = _flash > 0.01
			m.emission = Color(1, 0.9, 0.7) * _flash


func flash() -> void:
	_flash = 1.0


func set_wrecked() -> void:
	_flash = 0.0
	color = color.darkened(0.75)
	for m in body_mats:
		m.albedo_color = color
		m.emission_enabled = false
	body_root.rotation = Vector3(0.15, 0, 0.35)
