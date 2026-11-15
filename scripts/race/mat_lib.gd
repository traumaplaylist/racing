class_name MatLib
extends RefCounted
## Material library. Imported models only carry material *names*; this maps them to
## PBR materials built from assets/textures (triplanar, so models need no UV work).

const TEX := "res://assets/textures/"
static var _cache: Dictionary = {}


static func tex(name: String) -> Texture2D:
	var path := TEX + name + ".png"
	if ResourceLoader.exists(path):
		return load(path)
	return null


static func _tri(m: StandardMaterial3D, scale: float, world := false) -> void:
	m.uv1_triplanar = true
	m.uv1_world_triplanar = world
	m.uv1_scale = Vector3.ONE * scale
	m.uv1_triplanar_sharpness = 4.0


static func get_mat(name: String) -> Material:
	if _cache.has(name):
		return _cache[name]
	var m := StandardMaterial3D.new()
	match name:
		"Stripe":
			m.albedo_color = Color("fffaf0")
			m.emission_enabled = true
			m.emission = Color("2a2620")
			m.albedo_texture = tex("grime_albedo")
			m.roughness = 0.5
			_tri(m, 0.9)
		"Dark":
			m.albedo_color = Color("2a2826")
			m.roughness = 0.75
			m.albedo_texture = tex("grime_albedo")
			_tri(m, 0.9)
		"Steel":
			m.albedo_color = Color("8d8f92")
			m.metallic = 0.85
			m.roughness = 0.38
			m.roughness_texture = tex("grime_rough")
			_tri(m, 1.0)
		"Rubber":
			m.albedo_color = Color("1e1c1b")
			m.roughness = 0.92
		"Rim":
			m.albedo_color = Color("7a7d80")
			m.metallic = 0.8
			m.roughness = 0.4
		"Glass":
			m.albedo_color = Color("16232b")
			m.metallic = 0.3
			m.roughness = 0.08
		"Seat":
			m.albedo_color = Color("3a2e26")
			m.roughness = 0.85
		"LightFront":
			m.albedo_color = Color("fff6dc")
			m.emission_enabled = true
			m.emission = Color("fff1c8")
			m.emission_energy_multiplier = 2.5
		"LightRear":
			m.albedo_color = Color("ff3a20")
			m.emission_enabled = true
			m.emission = Color("ff2a10")
			m.emission_energy_multiplier = 3.0
		"Glow":
			m.albedo_color = Color("7ff6ff")
			m.emission_enabled = true
			m.emission = Color("39e8ff")
			m.emission_energy_multiplier = 3.0
		"Rust":
			m.albedo_texture = tex("rust_albedo")
			m.roughness_texture = tex("rust_rough")
			m.normal_enabled = true
			m.normal_texture = tex("rust_normal")
			m.metallic = 0.4
			_tri(m, 0.35, true)
		"Rock":
			m.albedo_texture = tex("rock_albedo")
			m.normal_enabled = true
			m.normal_texture = tex("rock_normal")
			m.normal_scale = 1.2
			m.roughness = 0.95
			_tri(m, 0.045, true)
		"Wood", "Crate":
			m.albedo_texture = tex("wood_albedo")
			m.roughness = 0.85
			_tri(m, 0.6)
		"Barrel":
			m.albedo_color = Color("9a3a22")
			m.albedo_texture = tex("rust_albedo")
			m.metallic = 0.5
			m.roughness = 0.6
			_tri(m, 0.5)
		"Leaf":
			m.albedo_color = Color("8a8a3a")
			m.roughness = 0.9
		"Sign":
			m.albedo_texture = tex("chevron_sign")
			m.roughness = 0.7
		"PickupRepair":
			m.albedo_color = Color("6ffff0")
			m.emission_enabled = true
			m.emission = Color("2fe8d8")
			m.emission_energy_multiplier = 2.2
		"PickupBoost":
			m.albedo_color = Color("ffc24a")
			m.emission_enabled = true
			m.emission = Color("ff9a1a")
			m.emission_energy_multiplier = 2.4
		"PickupFrame":
			m.albedo_color = Color("2a3036")
			m.metallic = 0.6
			m.roughness = 0.35
		_:
			m.albedo_color = Color(0.8, 0.8, 0.8)
	_cache[name] = m
	return m


## Car paint tinted per racer, with dirt/chips from the grime texture.
static func paint(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.albedo_texture = tex("grime_albedo")
	m.roughness_texture = tex("grime_rough")
	m.metallic = 0.25
	m.roughness = 1.0
	_tri(m, 0.9)
	return m


## Replaces every surface material in `root` by its library material (by name).
static func apply(root: Node, paint_mat: Material = null) -> Array[StandardMaterial3D]:
	var painted: Array[StandardMaterial3D] = []
	for mi in root.find_children("*", "MeshInstance3D", true, false):
		var mesh: Mesh = (mi as MeshInstance3D).mesh
		if mesh == null:
			continue
		for i in mesh.get_surface_count():
			var src := mesh.surface_get_material(i)
			var n := src.resource_name if src else ""
			if n == "Paint" and paint_mat:
				(mi as MeshInstance3D).set_surface_override_material(i, paint_mat)
			else:
				(mi as MeshInstance3D).set_surface_override_material(i, get_mat(n))
	return painted
