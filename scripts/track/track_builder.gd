class_name TrackBuilder
extends RefCounted
## Builds the desert canyon visuals around a TrackData. Purely cosmetic: collisions and
## rules use TrackData math, so this blocking can be replaced by real art later.

const SAND := Color("d29a63")
const SAND_DARK := Color("b9804f")
const ASPHALT := Color("6e635b")
const SHOULDER := Color("c79a72")
const LINE := Color("efe6d4")
const RUST := Color("8d4a2a")
const ROCKS := [Color("b5562f"), Color("a24827"), Color("c86a3c"), Color("9a5236"), Color("d07a48")]

var track: TrackData
var root: Node3D
var rng := RandomNumberGenerator.new()


static func build(parent: Node3D, p_track: TrackData, with_env := true) -> Node3D:
	var b := TrackBuilder.new()
	b.track = p_track
	b.root = Node3D.new()
	b.root.name = "TrackVisuals"
	parent.add_child(b.root)
	b.rng.seed = 20261111
	if with_env:
		add_environment(b.root)
	b._ground()
	b._road()
	b._lines()
	b._barriers()
	b._chevrons()
	b._start_line()
	b._rocks()
	return b.root


static func unshaded(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = c
	return m


static func add_environment(parent: Node3D) -> void:
	var env := Environment.new()
	var sky := Sky.new()
	var sm := ProceduralSkyMaterial.new()
	sm.sky_top_color = Color("6f9cc4")
	sm.sky_horizon_color = Color("e9c9a0")
	sm.ground_bottom_color = Color("9b6a44")
	sm.ground_horizon_color = Color("e9c9a0")
	sm.sun_angle_max = 30.0
	sky.sky_material = sm
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("c9b8a6")
	env.ambient_light_energy = 0.35
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	env.fog_enabled = true
	env.fog_light_color = Color("c99a72")
	env.fog_density = 0.0007
	env.fog_sky_affect = 0.3
	var we := WorldEnvironment.new()
	we.environment = env
	parent.add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-52, -38, 0)
	sun.light_color = Color(1.0, 0.92, 0.8)
	sun.light_energy = 1.0
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 140.0
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	parent.add_child(sun)


func _ground() -> void:
	var mi := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(1600, 1600)
	mi.mesh = pm
	var m := StandardMaterial3D.new()
	m.albedo_color = SAND
	m.roughness = 1.0
	mi.material_override = m
	mi.position = Vector3(130, -0.03, 40)
	root.add_child(mi)
	# darker sand patches for texture/scale cues
	var mm := _multimesh(_cyl_mesh(1.0, 1.0, 0.01, 8), 260, true)
	for i in 260:
		var p := Vector3(rng.randf_range(-350, 600), -0.012, rng.randf_range(-450, 550))
		var r := rng.randf_range(4, 18)
		var t := Transform3D(Basis().scaled(Vector3(r, 1, r * rng.randf_range(0.5, 1.2))).rotated(Vector3.UP, rng.randf() * TAU), p)
		mm.multimesh.set_instance_transform(i, t)
		mm.multimesh.set_instance_color(i, SAND_DARK.lerp(SAND, rng.randf() * 0.5))
	root.add_child(mm)


func _strip(offset_a: Vector2, offset_b: Vector2, y: float, color: Color, jitter := 0.0, filter := Callable()) -> MeshInstance3D:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n := track.count
	for i in n:
		var j := (i + 1) % n
		if filter.is_valid() and not filter.call(i):
			continue
		var c1 := color
		var c2 := color
		if jitter > 0.0:
			c1 = color.lightened(sin(i * 0.37) * jitter + sin(i * 0.11) * jitter)
			c2 = color.lightened(sin(j * 0.37) * jitter + sin(j * 0.11) * jitter)
		var ri := TrackData.right_of(track.tans[i])
		var rj := TrackData.right_of(track.tans[j])
		var hi := track.half_w[i]
		var hj := track.half_w[j]
		var a0 := track.pts[i] + ri * _off(offset_a, hi)
		var a1 := track.pts[i] + ri * _off(offset_b, hi)
		var b0 := track.pts[j] + rj * _off(offset_a, hj)
		var b1 := track.pts[j] + rj * _off(offset_b, hj)
		var v := [Vector3(a0.x, y, a0.y), Vector3(a1.x, y, a1.y), Vector3(b0.x, y, b0.y), Vector3(b1.x, y, b1.y)]
		for k in [0, 2, 1, 1, 2, 3]:
			st.set_color(c1 if k < 2 else c2)
			st.set_normal(Vector3.UP)
			st.add_vertex(v[k])
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.vertex_color_is_srgb = true
	m.roughness = 0.95
	mi.material_override = m
	root.add_child(mi)
	return mi


## Lateral offset encoded as Vector2(k, c) = k * half_width + c (meters, + = right).
static func _off(o: Vector2, hw: float) -> float:
	return o.x * hw + o.y


func _road() -> void:
	_strip(Vector2(-1, -3.5), Vector2(-1, 0), 0.01, SHOULDER)
	_strip(Vector2(1, 0), Vector2(1, 3.5), 0.01, SHOULDER)
	_strip(Vector2(-1, 0), Vector2(1, 0), 0.02, ASPHALT, 0.04)


func _lines() -> void:
	# edge lines
	_strip(Vector2(-1, 0.6), Vector2(-1, 0.95), 0.03, LINE)
	_strip(Vector2(1, -0.95), Vector2(1, -0.6), 0.03, LINE)
	# dashed center line on wide sections
	_strip(Vector2(0, -0.18), Vector2(0, 0.18), 0.03, LINE, 0.0, func(i: int) -> bool:
		return (i / 3) % 2 == 0 and track.half_w[i] >= 8.5)
	# red/white curbs on curves
	var curvy := func(i: int) -> bool:
		return absf(track.curv[i]) > 1.0 / 55.0
	var red_c := func(i: int) -> bool:
		return curvy.call(i) and i % 2 == 0
	var white_c := func(i: int) -> bool:
		return curvy.call(i) and i % 2 == 1
	_strip(Vector2(-1, 0), Vector2(-1, 1.1), 0.035, Color("c7372c"), 0.0, red_c)
	_strip(Vector2(-1, 0), Vector2(-1, 1.1), 0.035, LINE, 0.0, white_c)
	_strip(Vector2(1, -1.1), Vector2(1, 0), 0.035, Color("c7372c"), 0.0, red_c)
	_strip(Vector2(1, -1.1), Vector2(1, 0), 0.035, LINE, 0.0, white_c)


func _multimesh(mesh: Mesh, count: int, colors: bool) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = colors
	mm.mesh = mesh
	mm.instance_count = count
	var mi := MultiMeshInstance3D.new()
	mi.multimesh = mm
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = colors
	m.vertex_color_is_srgb = colors
	m.roughness = 0.9
	mi.material_override = m
	return mi


static func _cyl_mesh(top: float, bottom: float, h: float, seg: int) -> CylinderMesh:
	var cm := CylinderMesh.new()
	cm.top_radius = top
	cm.bottom_radius = bottom
	cm.height = h
	cm.radial_segments = seg
	cm.rings = 1
	return cm


func _barriers() -> void:
	var n := track.count
	var bm := BoxMesh.new()
	bm.size = Vector3(0.6, 1.0, 2.1)
	var mm := _multimesh(bm, n * 2, true)
	var k := 0
	for i in n:
		var t := track.tans[i]
		var r := TrackData.right_of(t)
		var h := TrackData.heading_of(t)
		for side in [-1.0, 1.0]:
			var p: Vector2 = track.pts[i] + r * side * (track.half_w[i] + 0.45)
			var tr := Transform3D(Basis(Vector3.UP, h), Vector3(p.x, 0.5, p.y))
			mm.multimesh.set_instance_transform(k, tr)
			var c := RUST.lerp(Color("b0602e"), 0.5 + 0.5 * sin(i * 0.9 + side))
			if (i / 4) % 2 == 0:
				c = c.darkened(0.15)
			mm.multimesh.set_instance_color(k, c)
			k += 1
	root.add_child(mm)


## Large light chevron boards on the outside of curves, pointing into the turn.
func _chevrons() -> void:
	var board_mat := StandardMaterial3D.new()
	board_mat.albedo_color = Color("7d2f1d")
	var chev_mat := unshaded(Color("fff3dc"))
	var n := track.count
	var i := 0
	while i < n:
		var c := track.curv[i]
		if absf(c) > 1.0 / 60.0:
			var t := track.tans[i]
			var r := TrackData.right_of(t)
			var outside := -signf(c)   # right turn (c > 0) → outside is left (−)
			var p: Vector2 = track.pts[i] + r * outside * (track.half_w[i] + 2.6)
			var node := Node3D.new()
			node.position = Vector3(p.x, 0, p.y)
			# board faces oncoming traffic, tilted back to read from the high camera
			node.rotation = Vector3(0, TrackData.heading_of(t) + PI, 0)
			root.add_child(node)
			var board := MeshInstance3D.new()
			var bm := BoxMesh.new()
			bm.size = Vector3(3.2, 1.9, 0.15)
			board.mesh = bm
			board.material_override = board_mat
			board.position = Vector3(0, 1.0, 0)
			board.rotation.x = -1.1   # tilted back so the face reads from the high camera
			node.add_child(board)
			# ">" pointing into the turn. Board local +X = driver's right.
			var dir := signf(c)       # + = right turn
			for k in [-1.0, 1.0]:
				var bar := MeshInstance3D.new()
				var sb := BoxMesh.new()
				sb.size = Vector3(1.35, 0.34, 0.05)
				bar.mesh = sb
				bar.material_override = chev_mat
				bar.position = Vector3(0, k * 0.42, 0.1)
				bar.rotation.z = -k * dir * 0.7
				board.add_child(bar)
			i += 5
		else:
			i += 1


func _start_line() -> void:
	var t := track.tangent_at(0.0)
	var r := TrackData.right_of(t)
	var hw := track.half_width_at(0.0)
	var sq := 1.0
	var cols := int(hw * 2.0 / sq)
	var bm := BoxMesh.new()
	bm.size = Vector3(sq, 0.02, sq)
	var mm := _multimesh(bm, cols * 2, true)
	var h := TrackData.heading_of(t)
	var k := 0
	for row in 2:
		for c in cols:
			var p := track.pts[0] + r * (-hw + sq * (c + 0.5)) + t * (sq * (row - 0.5))
			mm.multimesh.set_instance_transform(k, Transform3D(Basis(Vector3.UP, h), Vector3(p.x, 0.04, p.y)))
			mm.multimesh.set_instance_color(k, Color.WHITE if (row + c) % 2 == 0 else Color("1a1a1a"))
			k += 1
	root.add_child(mm)
	# side posts with banners
	for side in [-1.0, 1.0]:
		var p: Vector2 = track.pts[0] + r * side * (hw + 1.6)
		var post := MeshInstance3D.new()
		var pbm := BoxMesh.new()
		pbm.size = Vector3(0.5, 4.0, 0.5)
		post.mesh = pbm
		post.material_override = CarModel.mat(Color("2b2622"))
		post.position = Vector3(p.x, 2.0, p.y)
		root.add_child(post)
		var flag := MeshInstance3D.new()
		var fbm := BoxMesh.new()
		fbm.size = Vector3(1.6, 0.9, 0.08)
		flag.mesh = fbm
		flag.material_override = unshaded(Color("1fc8c0") if side > 0 else Color("f2ead8"))
		flag.position = Vector3(p.x, 3.6, p.y)
		flag.rotation.y = h
		root.add_child(flag)
	# grid slot marks
	for g in Cfg.RACER_COUNT:
		var gs := track.length - 10.0 - (g / 2) * 9.0 - (g % 2) * 4.5
		var gp := track.point_at(gs) + TrackData.right_of(track.tangent_at(gs)) * (3.2 if g % 2 == 0 else -3.2)
		var mark := MeshInstance3D.new()
		var mbm := BoxMesh.new()
		mbm.size = Vector3(2.6, 0.02, 0.25)
		mark.mesh = mbm
		mark.material_override = unshaded(LINE)
		var fwd := track.tangent_at(gs)
		mark.position = Vector3(gp.x + fwd.x * 2.6, 0.035, gp.y + fwd.y * 2.6)
		mark.rotation.y = h
		root.add_child(mark)


## Canyon: mesas/buttes outside the road, kept away from every road section so they
## never sit right on the racing line from the high camera.
func _rocks() -> void:
	var meshes := [_cyl_mesh(0.75, 1.0, 1.0, 6), _cyl_mesh(0.55, 1.0, 1.0, 5), _cyl_mesh(0.9, 1.0, 1.0, 7)]
	var lists: Array = [[], [], []]
	var n := track.count
	var i := 0
	while i < n:
		for side in [-1.0, 1.0]:
			if rng.randf() < 0.25:
				continue
			var dist := rng.randf_range(9.0, 60.0)
			var s := track.s_at[i]
			var r := TrackData.right_of(track.tans[i])
			var p: Vector2 = track.pts[i] + r * side * (track.half_w[i] + dist)
			var rad := rng.randf_range(3.0, 9.0) * (0.6 + dist / 60.0)
			var clearance := track.distance_to_road_edge(p) - rad
			if clearance < 6.0:
				continue
			var hgt := rng.randf_range(4.0, 9.0) + clearance * rng.randf_range(0.15, 0.45)
			hgt = minf(hgt, 6.0 + clearance * 0.9)
			lists[rng.randi() % 3].append([p, rad, hgt])
		i += 3
	# far canyon rim
	for k in 90:
		var a := TAU * k / 90.0
		var p := Vector2(130, 40) + Vector2(cos(a) * rng.randf_range(420, 520), sin(a) * rng.randf_range(430, 540))
		lists[k % 3].append([p, rng.randf_range(25, 50), rng.randf_range(35, 80)])
	for mi in 3:
		var arr: Array = lists[mi]
		var mm := _multimesh(meshes[mi], arr.size(), true)
		for k in arr.size():
			var e: Array = arr[k]
			var p: Vector2 = e[0]
			var rad: float = e[1]
			var hgt: float = e[2]
			var b := Basis().scaled(Vector3(rad, hgt, rad * rng.randf_range(0.7, 1.3))).rotated(Vector3.UP, rng.randf() * TAU)
			mm.multimesh.set_instance_transform(k, Transform3D(b, Vector3(p.x, hgt * 0.5 - 0.3, p.y)))
			var col: Color = ROCKS[rng.randi() % ROCKS.size()]
			mm.multimesh.set_instance_color(k, col.lightened(rng.randf_range(-0.08, 0.08)))
		mm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		root.add_child(mm)
