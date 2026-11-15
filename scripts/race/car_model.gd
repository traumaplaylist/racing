class_name CarModel
extends Node3D
## Car visual. Loads the Blender model assets/models/car_<type>.glb (faces +Z), tints the
## "Paint" material per racer and animates wheels/body. Behaviour never depends on it.

const STRIPE := Color("f2ead8")

var car_type := "buggy"
var color := Color.WHITE
var front_wheels: Array[Node3D] = []
var wheels: Array[Node3D] = []
var body_mats: Array[StandardMaterial3D] = []
var body_root: Node3D
var _flash := 0.0
var _wheel_spin := 0.0
var _steer := 0.0
var _wheel_rest: Dictionary = {}


static func mat(c: Color, rough := 0.75, metal := 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	m.metallic = metal
	return m


func setup(type: String, body_color: Color, _with_stripe: bool, weapon_id := "blaster") -> void:
	car_type = type
	color = body_color
	body_root = Node3D.new()
	add_child(body_root)
	var scene: Node3D = load("res://assets/models/car_%s.glb" % type).instantiate()
	var paint := MatLib.paint(body_color)
	body_mats.append(paint)
	MatLib.apply(scene, paint)
	# wheels move with the car, not with body roll: reparent them under this node
	for wn in ["Wheel_FL", "Wheel_FR", "Wheel_RL", "Wheel_RR"]:
		var w: Node3D = scene.find_child(wn, true, false)
		if w == null:
			continue
		var xf := w.transform
		w.get_parent().remove_child(w)
		add_child(w)
		w.transform = xf
		_wheel_rest[w] = xf
		wheels.append(w)
		if wn.ends_with("FL") or wn.ends_with("FR"):
			front_wheels.append(w)
	body_root.add_child(scene)
	set_weapon(weapon_id)


func set_weapon(weapon_id: String) -> void:
	for wid in Cfg.WEAPON_IDS:
		var n: Node3D = body_root.find_child("Weapon_" + wid, true, false)
		if n:
			n.visible = wid == weapon_id


## Visual update. steer -1..1 (+right), speed m/s, roll/pitch radians.
func animate(delta: float, steer: float, speed: float, roll: float, pitch: float) -> void:
	_steer = lerpf(_steer, -steer * 0.45, minf(1.0, delta * 12.0))
	_wheel_spin = fmod(_wheel_spin + speed / 0.55 * delta, TAU)
	for w in wheels:
		var rest: Transform3D = _wheel_rest[w]
		var yaw := _steer if w in front_wheels else 0.0
		w.transform = Transform3D(Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, _wheel_spin), rest.origin)
	body_root.rotation.z = lerpf(body_root.rotation.z, roll, minf(1.0, delta * 8.0))
	body_root.rotation.x = lerpf(body_root.rotation.x, pitch, minf(1.0, delta * 8.0))
	if _flash > 0.0:
		_flash = maxf(0.0, _flash - delta * 6.0)
		for m in body_mats:
			m.albedo_color = color.lerp(Color.WHITE, _flash)
			m.emission_enabled = _flash > 0.01
			m.emission = Color(1, 0.9, 0.7) * _flash * 2.0


func flash() -> void:
	_flash = 1.0


func set_wrecked() -> void:
	_flash = 0.0
	color = color.darkened(0.8)
	for m in body_mats:
		m.albedo_color = color
		m.emission_enabled = false
	body_root.rotation = Vector3(0.15, 0, 0.35)
