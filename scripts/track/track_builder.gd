class_name TrackBuilder
extends RefCounted
## Builds the desert canyon around a TrackData from Blender-made props (assets/models) and
## procedural textures (assets/textures). Purely cosmetic: physics and rules use TrackData.

const SAND := Color("d29a63")
const LINE := Color("f4ecda")
const ROCKS := [Color("b5562f"), Color("a24827"), Color("c86a3c"), Color("9a5236"), Color("d07a48")]
const MODELS := "res://assets/models/"
const CHUNK := 120.0          # metres of track per MultiMesh chunk (frustum culling)

var track: TrackData
var root: Node3D
var rng := RandomNumberGenerator.new()
var _mesh_cache: Dictionary = {}


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
	b._canyon()
	b._props()
	return b.root


static func unshaded(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = c
	return m


## Golden-hour desert light. Forward+ features (SSAO, glow, adjustments) are ignored
## by the Compatibility/Mobile renderers, so the same setup degrades gracefully.
static func add_environment(parent: Node3D) -> void:
	var env := Environment.new()
	var sky := Sky.new()
	var sm := ProceduralSkyMaterial.new()
	sm.sky_top_color = Color("4f7fb3")
	sm.sky_horizon_color = Color("f0c99a")
	sm.ground_bottom_color = Color("7a4a2c")
	sm.ground_horizon_color = Color("e8b888")
	sm.sun_angle_max = 25.0
	sm.sky_energy_multiplier = 1.0
	sky.sky_material = sm
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.55
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_exposure = 1.1
	env.tonemap_white = 6.0
	env.ssao_enabled = true
	env.ssao_radius = 1.6
	env.ssao_intensity = 2.2
	env.ssao_power = 1.6
	env.glow_enabled = true
	env.glow_intensity = 0.7
	env.glow_bloom = 0.04
	env.glow_hdr_threshold = 1.1
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SOFTLIGHT
	env.fog_enabled = true
	env.fog_light_color = Color("e7b98c")
	env.fog_density = 0.0009
	env.fog_sky_affect = 0.2
	env.adjustment_enabled = true
	env.adjustment_saturation = 1.15
	env.adjustment_contrast = 1.06
	var we := WorldEnvironment.new()
	we.environment = env
	parent.add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-38, -40, 0)
	sun.light_color = Color(1.0, 0.86, 0.68)
	sun.light_energy = 1.7
	sun.shadow_enabled = true
	sun.shadow_bias = 0.04
	sun.shadow_blur = 1.5
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	sun.directional_shadow_max_distance = 160.0
	parent.add_child(sun)


# ------------------------------------------------------------------ materials

static func _tex(n: String) -> Texture2D:
	return MatLib.tex(n)


func _asphalt_mat() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_texture = _tex("asphalt_albedo")
	m.albedo_color = Color(0.82, 0.8, 0.8)
	m.normal_enabled = true
	m.normal_texture = _tex("asphalt_normal")
	m.roughness_texture = _tex("asphalt_rough")
	m.vertex_color_use_as_albedo = true
	m.vertex_color_is_srgb = true
	return m


func _sand_mat(tint: Color, world_scale: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = tint
	m.albedo_texture = _tex("sand_albedo")
	m.normal_enabled = true
	m.normal_texture = _tex("sand_normal")
	m.roughness = 1.0
	m.uv1_triplanar = true
	m.uv1_world_triplanar = true
	m.uv1_scale = Vector3.ONE * world_scale
	return m


# ------------------------------------------------------------------ geometry

func _ground() -> void:
	var mi := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(1800, 1800)
	mi.mesh = pm
	mi.material_override = _sand_mat(Color.WHITE, 0.07)
	mi.position = Vector3(130, -0.03, 40)
	root.add_child(mi)


## Strip along the track between lateral offsets a and b, each Vector2(k, c) = k*half_width + c.
## UV: u = lateral metres / uv_tile, v = arc length / uv_tile.
func _strip(a: Vector2, b: Vector2, y: float, mat: Material, color := Color.WHITE,
		uv_tile := 8.0, filter := Callable(), alpha_fn := Callable()) -> MeshInstance3D:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n := track.count
	for i in n:
		var j := (i + 1) % n
		if filter.is_valid() and not filter.call(i):
			continue
		var sj := track.s_at[i] + track.length / n
		var ri := TrackData.right_of(track.tans[i])
		var rj := TrackData.right_of(track.tans[j])
		var oa_i := a.x * track.half_w[i] + a.y
		var ob_i := b.x * track.half_w[i] + b.y
		var oa_j := a.x * track.half_w[j] + a.y
		var ob_j := b.x * track.half_w[j] + b.y
		var verts := [
			[track.pts[i] + ri * oa_i, oa_i, track.s_at[i], i],
			[track.pts[i] + ri * ob_i, ob_i, track.s_at[i], i],
			[track.pts[j] + rj * oa_j, oa_j, sj, j],
			[track.pts[j] + rj * ob_j, ob_j, sj, j],
		]
		for k in [0, 2, 1, 1, 2, 3]:
			var v: Array = verts[k]
			var c := color
			if alpha_fn.is_valid():
				c.a = alpha_fn.call(v[3])
			st.set_color(c)
			st.set_normal(Vector3.UP)
			st.set_uv(Vector2(float(v[1]) / uv_tile, float(v[2]) / uv_tile))
			var p: Vector2 = v[0]
			st.add_vertex(Vector3(p.x, y, p.y))
	st.generate_tangents()
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(mi)
	return mi


func _road() -> void:
	var shoulder := _sand_mat(Color("d8c0a4"), 0.12)
	_strip(Vector2(-1, -4.0), Vector2(-1, 0), 0.01, shoulder)
	_strip(Vector2(1, 0), Vector2(1, 4.0), 0.01, shoulder)
	_strip(Vector2(-1, 0), Vector2(1, 0), 0.02, _asphalt_mat(), Color.WHITE, 9.0)
	# tyre marks: denser on curves, where cars slide
	var tm := StandardMaterial3D.new()
	tm.albedo_texture = _tex("tiremarks")
	tm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	tm.vertex_color_use_as_albedo = true
	tm.roughness = 0.6
	_strip(Vector2(-1, 1.0), Vector2(1, -1.0), 0.025, tm, Color.WHITE, 22.0, Callable(),
		func(i: int) -> float: return clampf(0.25 + absf(track.curv[i]) * 25.0, 0.25, 0.9))


func _lines() -> void:
	var line := StandardMaterial3D.new()
	line.albedo_color = LINE
	line.albedo_texture = _tex("grime_albedo")
	line.roughness = 0.7
	_strip(Vector2(-1, 0.6), Vector2(-1, 0.95), 0.03, line)
	_strip(Vector2(1, -0.95), Vector2(1, -0.6), 0.03, line)
	_strip(Vector2(0, -0.18), Vector2(0, 0.18), 0.03, line, Color.WHITE, 8.0, func(i: int) -> bool:
		return (i / 3) % 2 == 0 and track.half_w[i] >= 8.5)
	var curvy := func(i: int) -> bool: return absf(track.curv[i]) > 1.0 / 55.0
	var red := StandardMaterial3D.new()
	red.albedo_color = Color("c8392c")
	red.albedo_texture = _tex("grime_albedo")
	for side: float in [-1.0, 1.0]:
		var a := Vector2(side, -1.1 if side > 0 else 0.0)
		var b := Vector2(side, 0.0 if side > 0 else 1.1)
		_strip(a, b, 0.035, red, Color.WHITE, 8.0, func(i: int) -> bool: return curvy.call(i) and i % 2 == 0)
		_strip(a, b, 0.035, line, Color.WHITE, 8.0, func(i: int) -> bool: return curvy.call(i) and i % 2 == 1)


# ------------------------------------------------------------------ instanced props

## Loads a (single-mesh) prop glb and returns its mesh with library materials applied.
func _prop_mesh(name: String, variant := "") -> Mesh:
	var key := name + variant
	if _mesh_cache.has(key):
		return _mesh_cache[key]
	var scene: Node = load(MODELS + name + ".glb").instantiate()
	var found: Array = scene.find_children("*", "MeshInstance3D", true, false)
	var mesh: Mesh = (found[0] as MeshInstance3D).mesh.duplicate()
	for i in mesh.get_surface_count():
		var src := mesh.surface_get_material(i)
		var n := src.resource_name if src else ""
		var m := MatLib.get_mat(n)
		if n == "Sign" and variant == "R":
			m = (m as StandardMaterial3D).duplicate()
			m.uv1_scale = Vector3(-1, 1, 1)
		mesh.surface_set_material(i, m)
	scene.free()
	_mesh_cache[key] = mesh
	return mesh


## items: Array of [s, Transform3D, Color]. Builds one MultiMesh per track chunk.
func _instances(mesh: Mesh, items: Array, shadows := true, colors := false) -> void:
	var chunks: Dictionary = {}
	for it in items:
		var k := int(float(it[0]) / CHUNK)
		if not chunks.has(k):
			chunks[k] = []
		chunks[k].append(it)
	for k in chunks:
		var list: Array = chunks[k]
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = colors
		mm.mesh = mesh
		mm.instance_count = list.size()
		for i in list.size():
			mm.set_instance_transform(i, list[i][1])
			if colors:
				mm.set_instance_color(i, list[i][2])
		var mi := MultiMeshInstance3D.new()
		mi.multimesh = mm
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadows else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(mi)


func _along(i: int, side: float, off: float) -> Vector2:
	return track.pts[i] + TrackData.right_of(track.tans[i]) * side * (track.half_w[i] + off)


func _barriers() -> void:
	var items: Array = []
	var seg := 3.6   # model is 4 m long: overlap so curves have no gaps
	var s := 0.0
	while s < track.length:
		var t := track.tangent_at(s + seg * 0.5)
		var h := TrackData.heading_of(t)
		for side: float in [-1.0, 1.0]:
			var p := track.point_at(s + seg * 0.5) + TrackData.right_of(t) * side * (track.half_width_at(s) + 0.55)
			var basis := Basis(Vector3.UP, h - PI * 0.5)
			if side > 0:
				basis = Basis(Vector3.UP, h + PI * 0.5)   # posts outside on both sides
			items.append([s, Transform3D(basis.scaled(Vector3(1.02, 1.3, 1.0)), Vector3(p.x, 0.0, p.y))])
		s += seg
	_instances(_prop_mesh("barrier"), items)


## Chevron boards behind the barrier on the outside of curves, facing oncoming cars.
func _chevrons() -> void:
	var left: Array = []
	var right: Array = []
	var i := 0
	while i < track.count:
		var c := track.curv[i]
		if absf(c) > 1.0 / 60.0:
			var t := track.tans[i]
			var outside := -signf(c)
			var p := _along(i, outside, 2.8)
			var tr := Transform3D(Basis(Vector3.UP, TrackData.heading_of(-t)).scaled(Vector3.ONE * 1.5), Vector3(p.x, 0, p.y))
			# texture shows "<" (turn left); mirrored variant for right turns
			(right if c > 0 else left).append([track.s_at[i], tr])
			i += 6
		else:
			i += 1
	_instances(_prop_mesh("chevron_board"), left)
	_instances(_prop_mesh("chevron_board", "R"), right)


func _start_line() -> void:
	var t := track.tangent_at(0.0)
	var r := TrackData.right_of(t)
	var hw := track.half_width_at(0.0)
	var sq := 1.0
	var cols := int(hw * 2.0 / sq)
	var bm := BoxMesh.new()
	bm.size = Vector3(sq, 0.02, sq)
	var white := StandardMaterial3D.new()
	white.albedo_color = Color("f2efe8")
	var black := StandardMaterial3D.new()
	black.albedo_color = Color("1c1b1a")
	var h := TrackData.heading_of(t)
	for row in 2:
		for c in cols:
			var p := track.pts[0] + r * (-hw + sq * (c + 0.5)) + t * (sq * (row - 0.5))
			var mi := MeshInstance3D.new()
			mi.mesh = bm
			mi.material_override = white if (row + c) % 2 == 0 else black
			mi.position = Vector3(p.x, 0.04, p.y)
			mi.rotation.y = h
			root.add_child(mi)
	# gantry posts with banners
	for side: float in [-1.0, 1.0]:
		var p: Vector2 = track.pts[0] + r * side * (hw + 1.8)
		var post := MeshInstance3D.new()
		var pbm := BoxMesh.new()
		pbm.size = Vector3(0.5, 4.5, 0.5)
		post.mesh = pbm
		post.material_override = MatLib.get_mat("Steel")
		post.position = Vector3(p.x, 2.25, p.y)
		root.add_child(post)
		var flag := MeshInstance3D.new()
		var fbm := BoxMesh.new()
		fbm.size = Vector3(1.8, 1.0, 0.08)
		flag.mesh = fbm
		var fm := StandardMaterial3D.new()
		fm.albedo_color = Color("1fc8c0") if side > 0 else Color("f2ead8")
		flag.material_override = fm
		flag.position = Vector3(p.x, 3.9, p.y)
		flag.rotation.y = h
		root.add_child(flag)
	for g in Cfg.RACER_COUNT:
		var gs := track.length - 10.0 - (g / 2) * 9.0 - (g % 2) * 4.5
		var gp := track.point_at(gs) + TrackData.right_of(track.tangent_at(gs)) * (3.2 if g % 2 == 0 else -3.2)
		var mark := MeshInstance3D.new()
		var mbm := BoxMesh.new()
		mbm.size = Vector3(2.6, 0.02, 0.25)
		mark.mesh = mbm
		mark.material_override = MatLib.get_mat("Stripe")
		var fwd := track.tangent_at(gs)
		mark.position = Vector3(gp.x + fwd.x * 2.6, 0.035, gp.y + fwd.y * 2.6)
		mark.rotation.y = h
		root.add_child(mark)


func _rock_xf(p: Vector2, scale: Vector3, sink := 0.0) -> Transform3D:
	var b := Basis(Vector3.UP, rng.randf() * TAU).scaled(scale)
	return Transform3D(b, Vector3(p.x, -sink, p.y))


## Canyon: low boulders near the barriers, mesas and cliffs further out, a tall rim far away.
## Everything keeps clear of every road section (checked against the whole centerline).
func _canyon() -> void:
	var groups := {"rock_boulder": [], "rock_slab": [], "rock_mesa": [], "rock_spire": [], "cliff": []}
	var i := 0
	while i < track.count:
		var s := track.s_at[i]
		for side: float in [-1.0, 1.0]:
			# near band: boulders/slabs, low enough not to hide the road
			if rng.randf() < 0.55:
				var off := rng.randf_range(3.5, 8.0)
				var p := _along(i, side, off)
				var sc := rng.randf_range(1.2, 2.6)
				if track.distance_to_road_edge(p) - sc * 1.2 > 2.8:
					var kind := "rock_boulder" if rng.randf() < 0.6 else "rock_slab"
					groups[kind].append([s, _rock_xf(p, Vector3(sc, sc * rng.randf_range(0.7, 1.2), sc), 0.2)])
			# mid band: canyon walls
			if rng.randf() < 0.7:
				var off := rng.randf_range(12.0, 34.0)
				var p := _along(i, side, off)
				var sc := rng.randf_range(4.0, 9.0)
				var clear := track.distance_to_road_edge(p) - sc * 1.3
				if clear > 5.0:
					var kind: String = ["rock_mesa", "cliff", "cliff", "rock_spire"][rng.randi() % 4]
					var hs := clampf(sc * rng.randf_range(0.8, 1.6), 3.0, 4.0 + clear * 0.8)
					groups[kind].append([s, _rock_xf(p, Vector3(sc, hs, sc), 0.5)])
		i += 4
	# far rim
	for k in 110:
		var a := TAU * k / 110.0
		var p := Vector2(130, 40) + Vector2(cos(a) * rng.randf_range(430, 520), sin(a) * rng.randf_range(440, 540))
		var sc := rng.randf_range(25.0, 45.0)
		groups["cliff" if k % 2 == 0 else "rock_mesa"].append([track.length + 1.0 + (k % 6) * CHUNK, _rock_xf(p, Vector3(sc, sc * rng.randf_range(0.8, 1.5), sc), 2.0)])
	for kind in groups:
		_instances(_prop_mesh(kind), groups[kind])


## Roadside dressing: crates and barrels behind barriers, bushes and stones on the sand.
func _props() -> void:
	var crates: Array = []
	var barrels: Array = []
	var bushes: Array = []
	var stones: Array = []
	var i := 0
	while i < track.count:
		var s := track.s_at[i]
		var side := -1.0 if rng.randf() < 0.5 else 1.0
		var r := rng.randf()
		var p := _along(i, side, rng.randf_range(1.6, 3.2))
		var ok := track.distance_to_road_edge(p) > 1.3
		if ok and r < 0.12:
			crates.append([s, Transform3D(Basis(Vector3.UP, rng.randf() * TAU), Vector3(p.x, 0, p.y))])
			if rng.randf() < 0.5:
				crates.append([s, Transform3D(Basis(Vector3.UP, rng.randf() * TAU), Vector3(p.x + 0.2, 1.2, p.y + 0.1))])
		elif ok and r < 0.22:
			barrels.append([s, Transform3D(Basis(Vector3.UP, rng.randf() * TAU), Vector3(p.x, 0, p.y))])
		var bp := _along(i, -side, rng.randf_range(2.0, 14.0))
		if track.distance_to_road_edge(bp) > 1.5:
			var bs := rng.randf_range(0.8, 1.6)
			bushes.append([s, Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * bs), Vector3(bp.x, 0, bp.y))])
		var sp := _along(i, side, rng.randf_range(1.2, 6.0))
		if track.distance_to_road_edge(sp) > 0.9:
			stones.append([s, Transform3D(Basis(Vector3.UP, rng.randf() * TAU), Vector3(sp.x, 0, sp.y))])
		i += 5
	_instances(_prop_mesh("crate"), crates)
	_instances(_prop_mesh("barrel"), barrels)
	_instances(_prop_mesh("bush"), bushes, false)
	_instances(_prop_mesh("stones"), stones, false)
