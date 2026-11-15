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
	b._sand_edges()
	b._barriers()
	b._road_arrows()
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
	env.volumetric_fog_enabled = true
	env.volumetric_fog_density = 0.004
	env.volumetric_fog_albedo = Color("f1c69a")
	env.volumetric_fog_length = 160.0
	env.volumetric_fog_anisotropy = 0.6
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
		uv_tile := 8.0, filter := Callable(), alpha_fn := Callable(), edge_w := 0.0) -> MeshInstance3D:
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
			var uu := float(v[1]) / uv_tile
			if edge_w > 0.0:
				uu = (track.half_w[int(v[3])] - absf(float(v[1]))) / edge_w   # 0 at the road edge
			st.set_uv(Vector2(uu, float(v[2]) / uv_tile))
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


## Sand blown onto the asphalt edges (alpha-blended, noisy inner border).
func _sand_edges() -> void:
	var m := StandardMaterial3D.new()
	m.albedo_texture = _tex("edge_sand")
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.roughness = 1.0
	for side: float in [-1.0, 1.0]:
		var a := Vector2(side, 0.0)
		var b := Vector2(side, -side * 2.6)
		if side > 0:
			_strip(b, a, 0.045, m, Color.WHITE, 14.0, Callable(), Callable(), 2.6)
		else:
			_strip(a, b, 0.045, m, Color.WHITE, 14.0, Callable(), Callable(), 2.6)


## Painted chevron arrows on the asphalt ahead of the sharper corners.
func _road_arrows() -> void:
	var m := StandardMaterial3D.new()
	m.albedo_texture = _tex("road_arrow")
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.roughness = 0.8
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var i := 0
	var last := -1000
	while i < track.count:
		if absf(track.curv[i]) > 1.0 / 42.0 and i - last > 60:
			last = i
			var s := track.s_at[i] - 34.0
			var c := track.point_at(s)
			var t := track.tangent_at(s)
			var r := TrackData.right_of(t)
			c += r * signf(track.curv[i]) * 1.5
			# texture chevrons point to +V: V grows along the travel direction
			var quad := [[c - r * 2.6 - t * 5.5, Vector2(0, 0)], [c + r * 2.6 - t * 5.5, Vector2(1, 0)],
				[c - r * 2.6 + t * 5.5, Vector2(0, 1)], [c + r * 2.6 + t * 5.5, Vector2(1, 1)]]
			for k in [0, 2, 1, 1, 2, 3]:
				var p: Vector2 = quad[k][0]
				st.set_normal(Vector3.UP)
				st.set_uv(quad[k][1])
				st.add_vertex(Vector3(p.x, 0.04, p.y))
		i += 1
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(mi)


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
	var plain: Array = []
	var chev_l: Array = []   # default texture "<": right-side barrier, outside of a left turn
	var chev_r: Array = []   # mirrored ">": left-side barrier, outside of a right turn
	var seg := 3.9
	var s := 0.0
	var k := 0
	while s < track.length - seg * 0.5:
		var sm := s + seg * 0.5
		var t := track.tangent_at(sm)
		var h := TrackData.heading_of(t)
		var c := track.curvature_at(sm)
		for side: float in [-1.0, 1.0]:
			var p := track.point_at(sm) + TrackData.right_of(t) * side * (track.half_width_at(sm) + 0.6)
			var basis := Basis(Vector3.UP, h - PI * 0.5)
			if side > 0:
				basis = Basis(Vector3.UP, h + PI * 0.5)   # road-facing side inwards on both sides
			var item := [s, Transform3D(basis.scaled(Vector3(1.03, 1.0, 1.0)), Vector3(p.x, 0.0, p.y))]
			var outside := absf(c) > 1.0 / 70.0 and side == -signf(c)
			if outside and k % 2 == 0:
				(chev_r if side < 0 else chev_l).append(item)
			else:
				plain.append(item)
		s += seg
		k += 1
	_instances(_prop_mesh("barrier"), plain)
	_instances(_prop_mesh("barrier_chevron"), chev_l)
	_instances(_prop_mesh("barrier_chevron", "R"), chev_r)


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


## Canyon: boulders near the barriers, sandstone walls running along the road, tall rim
## far away. Every rock is checked against the whole centerline so nothing sits on the road.
func _canyon() -> void:
	var groups := {"rock_boulder": [], "rock_slab": [], "rock_mesa": [], "rock_spire": [], "cliff": [], "cliff_b": []}
	var elong := {"cliff": 2.4, "cliff_b": 1.8, "rock_mesa": 1.2, "rock_spire": 1.0}
	var i := 0
	while i < track.count:
		var s := track.s_at[i]
		var t := track.tans[i]
		for side: float in [-1.0, 1.0]:
			if rng.randf() < 0.5:
				var off := rng.randf_range(3.2, 7.5)
				var p := _along(i, side, off)
				var sc := rng.randf_range(1.0, 2.2)
				if track.distance_to_road_edge(p) - sc * 1.7 > 1.6:
					var kind := "rock_boulder" if rng.randf() < 0.6 else "rock_slab"
					groups[kind].append([s, _rock_xf(p, Vector3(sc, sc * rng.randf_range(0.8, 1.3), sc), 0.05)])
			if rng.randf() < 0.8:
				var kind: String = ["cliff", "cliff_b", "rock_mesa", "cliff", "rock_spire", "cliff_b"][rng.randi() % 6]
				var sc := rng.randf_range(4.5, 9.5)
				var off := rng.randf_range(sc * 1.9 + 3.0, sc * 1.9 + 22.0)
				var p := _along(i, side, off)
				var el: float = elong[kind]
				var ok := true
				for d: float in [-0.8, 0.0, 0.8]:
					var q := p + t * d * sc * el
					if track.distance_to_road_edge(q) - sc * 1.9 < 2.5:
						ok = false
						break
				if ok:
					var hs := sc * rng.randf_range(0.9, 1.6)
					var yaw := TrackData.heading_of(t) - PI * 0.5 + rng.randf_range(-0.3, 0.3)
					var b := Basis(Vector3.UP, yaw).scaled(Vector3(sc, hs, sc))
					groups[kind].append([s, Transform3D(b, Vector3(p.x, -0.1, p.y))])
		i += 4
	for k in 120:
		var a := TAU * k / 120.0
		var p := Vector2(130, 40) + Vector2(cos(a) * rng.randf_range(430, 540), sin(a) * rng.randf_range(440, 560))
		var sc := rng.randf_range(22.0, 40.0)
		var b := Basis(Vector3.UP, a + PI * 0.5).scaled(Vector3(sc, sc * rng.randf_range(0.9, 1.6), sc))
		groups["cliff" if k % 2 == 0 else "cliff_b"].append([track.length + 1.0 + (k % 6) * CHUNK, Transform3D(b, Vector3(p.x, -1.0, p.y))])
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
