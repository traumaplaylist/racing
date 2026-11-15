class_name Showroom
extends Node3D
## Desert canyon set with a car on a turntable for the garage / results screens.

var car: CarModel
var turntable: Node3D
var camera: Camera3D
var spin := 0.35


func build(car_type: String, color: Color, h_offset: float, weapon_id := "blaster") -> void:
	TrackBuilder.add_environment(self)
	var key := DirectionalLight3D.new()   # studio fill from the camera side
	key.rotation_degrees = Vector3(-30, 25, 0)
	key.light_color = Color(1.0, 0.93, 0.85)
	key.light_energy = 1.1
	add_child(key)
	var ground := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(400, 400)
	ground.mesh = pm
	var sand := StandardMaterial3D.new()
	sand.albedo_texture = MatLib.tex("sand_albedo")
	sand.normal_enabled = true
	sand.normal_texture = MatLib.tex("sand_normal")
	sand.uv1_triplanar = true
	sand.uv1_world_triplanar = true
	sand.uv1_scale = Vector3.ONE * 0.12
	ground.material_override = sand
	add_child(ground)
	var pad := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 4.4
	cm.bottom_radius = 4.6
	cm.height = 0.2
	cm.radial_segments = 48
	pad.mesh = cm
	pad.material_override = MatLib.get_mat("Dark")
	pad.position.y = 0.1
	add_child(pad)
	var ring := MeshInstance3D.new()
	var rm := TorusMesh.new()
	rm.inner_radius = 4.45
	rm.outer_radius = 4.6
	ring.mesh = rm
	var rmat := StandardMaterial3D.new()
	rmat.albedo_color = Color("1fc8c0")
	rmat.emission_enabled = true
	rmat.emission = Color("1fc8c0")
	rmat.emission_energy_multiplier = 0.6
	ring.material_override = rmat
	ring.position.y = 0.2
	add_child(ring)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var kinds := ["cliff", "rock_mesa", "rock_spire", "cliff"]
	for i in 22:
		var a := lerpf(-2.3, 2.3, i / 21.0) + rng.randf_range(-0.05, 0.05)
		var d := rng.randf_range(28, 55)
		var rock: Node3D = load("res://assets/models/%s.glb" % kinds[i % 4]).instantiate()
		MatLib.apply(rock)
		var sc := rng.randf_range(6, 12)
		rock.scale = Vector3(sc, sc * rng.randf_range(1.0, 2.0), sc)
		rock.position = Vector3(sin(a) * d, -0.5, -cos(a) * d)
		rock.rotation.y = rng.randf() * TAU
		add_child(rock)
	for i in 8:
		var b: Node3D = load("res://assets/models/%s.glb" % ["rock_boulder", "bush", "stones", "barrel"][i % 4]).instantiate()
		MatLib.apply(b)
		var a := rng.randf_range(-1.4, 1.4)
		b.position = Vector3(sin(a) * rng.randf_range(8, 14), 0, -cos(a) * rng.randf_range(8, 14))
		add_child(b)
	turntable = Node3D.new()
	turntable.position.y = 0.2
	add_child(turntable)
	set_car(car_type, color, weapon_id)
	camera = Camera3D.new()
	camera.fov = 36
	camera.h_offset = h_offset
	add_child(camera)
	camera.look_at_from_position(Vector3(0, 3.4, 11.0), Vector3(0, 0.9, 0))
	camera.current = true


func set_car(car_type: String, color: Color, weapon_id := "blaster") -> void:
	if car:
		car.queue_free()
	car = CarModel.new()
	car.setup(car_type, color, true, weapon_id)
	car.scale = Vector3.ONE * 1.1
	turntable.add_child(car)


func _process(delta: float) -> void:
	if turntable:
		turntable.rotation.y += delta * spin
	if car:
		car.animate(delta, 0.0, 0.0, 0.0, 0.0)
