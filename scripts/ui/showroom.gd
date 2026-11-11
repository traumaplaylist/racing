class_name Showroom
extends Node3D
## Small desert canyon set with a car on a turntable for the garage / results screens.

var car: CarModel
var turntable: Node3D
var camera: Camera3D
var spin := 0.35


func build(car_type: String, color: Color, h_offset: float) -> void:
	TrackBuilder.add_environment(self)
	var ground := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(400, 400)
	ground.mesh = pm
	ground.material_override = CarModel.mat(TrackBuilder.SAND, 1.0)
	add_child(ground)
	var pad := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 4.2
	cm.bottom_radius = 4.4
	cm.height = 0.2
	cm.radial_segments = 40
	pad.mesh = cm
	pad.material_override = CarModel.mat(Color("5e544c"), 0.9)
	pad.position.y = 0.1
	add_child(pad)
	var ring := MeshInstance3D.new()
	var rm := CylinderMesh.new()
	rm.top_radius = 4.45
	rm.bottom_radius = 4.45
	rm.height = 0.12
	rm.radial_segments = 40
	ring.mesh = rm
	ring.material_override = TrackBuilder.unshaded(UiKit.ACCENT.darkened(0.2))
	ring.position.y = 0.06
	add_child(ring)
	# canyon walls behind
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for i in 26:
		var a := lerpf(-2.2, 2.2, i / 25.0) + rng.randf_range(-0.05, 0.05)
		var d := rng.randf_range(30, 60)
		var rock := MeshInstance3D.new()
		rock.mesh = TrackBuilder._cyl_mesh(0.75, 1.0, 1.0, 6)
		var col: Color = TrackBuilder.ROCKS[i % TrackBuilder.ROCKS.size()]
		rock.material_override = CarModel.mat(col, 0.95)
		var h := rng.randf_range(10, 34)
		var r := rng.randf_range(6, 14)
		rock.scale = Vector3(r, h, r)
		rock.position = Vector3(sin(a) * d, h * 0.5 - 0.5, -cos(a) * d)
		rock.rotation.y = rng.randf() * TAU
		add_child(rock)
	turntable = Node3D.new()
	turntable.position.y = 0.2
	add_child(turntable)
	set_car(car_type, color)
	camera = Camera3D.new()
	camera.fov = 38
	camera.h_offset = h_offset
	add_child(camera)
	camera.look_at_from_position(Vector3(0, 3.6, 10.5), Vector3(0, 0.9, 0))
	camera.current = true


func set_car(car_type: String, color: Color) -> void:
	if car:
		car.queue_free()
	car = CarModel.new()
	car.setup(car_type, color, true)
	car.scale = Vector3.ONE * 1.15
	turntable.add_child(car)


func _process(delta: float) -> void:
	if turntable:
		turntable.rotation.y += delta * spin
	if car:
		car.animate(delta, 0.0, 0.0, 0.0, 0.0)
