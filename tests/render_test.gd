extends Node3D
var variant := 0
var frames := 0
var cam: Camera3D
var t: TrackData
const OUT := "user://"   # render-check images land in the user data dir
func _ready() -> void:
	t = TrackData.new()
	_build()
func _build() -> void:
	for c in get_children(): c.free()
	var tv := TrackBuilder.build(self, t, variant != 1)
	if variant == 1:
		var sun := DirectionalLight3D.new()
		sun.rotation_degrees = Vector3(-52, -38, 0)
		add_child(sun)
	if variant == 2:
		for c in tv.get_children():
			if c is WorldEnvironment:
				c.environment.fog_enabled = false
	cam = Camera3D.new()
	add_child(cam)
	cam.fov = 50
	cam.look_at_from_position(Vector3(0, 35, -20), Vector3(0, 0, 20))
	cam.current = true
	frames = 0
func _process(_d: float) -> void:
	frames += 1
	if frames == 5:
		get_viewport().get_texture().get_image().save_png(OUT + "rt%d.png" % variant)
		variant += 1
		if variant > 2:
			get_tree().quit()
		else:
			_build()
