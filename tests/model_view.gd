extends Node3D
## Debug turntable: renders models with the game materials. Writes user://model_view.png
## Args (after --): --view=<glb path> --yaw=<deg>
var frames := 0
func _ready() -> void:
	var args := {}
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=")
		args[kv[0]] = kv[1] if kv.size() > 1 else ""
	TrackBuilder.add_environment(self)
	var ground := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(60, 60)
	ground.mesh = pm
	ground.material_override = MatLib.get_mat("Dark")
	add_child(ground)
	var list := str(args.get("view", "res://assets/models/car_buggy.glb,res://assets/models/car_bruiser.glb")).split(",")
	var x := -3.0 * (list.size() - 1)
	for p in list:
		var scene: Node3D = load(p).instantiate()
		MatLib.apply(scene, MatLib.paint(Color("1fc8c0")))
		scene.position.x = x
		scene.rotation_degrees.y = float(args.get("yaw", "35"))
		add_child(scene)
		x += 6.0
	var cam := Camera3D.new()
	add_child(cam)
	cam.fov = 40
	var d := 8.0 + list.size() * 3.0
	cam.look_at_from_position(Vector3(0, d * float(args.get("camh", "0.5")), float(args.get("camz", "-1")) * d), Vector3(0, 0.8, 0))
	cam.current = true
func _process(_d: float) -> void:
	frames += 1
	if frames == 8:
		get_viewport().get_texture().get_image().save_png("user://model_view.png")
		get_tree().quit()
