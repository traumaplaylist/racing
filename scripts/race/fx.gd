class_name Fx
extends RefCounted
## Short-lived visual effects. Particle counts are kept small (mobile-friendly).


static func burst(parent: Node, pos: Vector3, color: Color, amount: int, speed: float, size: float, life := 0.5) -> void:
	var p := CPUParticles3D.new()
	p.one_shot = true
	p.amount = amount
	p.lifetime = life
	p.explosiveness = 0.95
	p.direction = Vector3.UP
	p.spread = 180.0
	p.initial_velocity_min = speed * 0.4
	p.initial_velocity_max = speed
	p.gravity = Vector3(0, -12, 0)
	p.scale_amount_min = size * 0.5
	p.scale_amount_max = size
	var qm := QuadMesh.new()
	qm.size = Vector2(0.5, 0.5)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.vertex_color_use_as_albedo = true
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	qm.material = m
	p.mesh = qm
	var g := Gradient.new()
	g.set_color(0, color)
	g.set_color(1, Color(color.r, color.g, color.b, 0.0))
	p.color_ramp = g
	parent.add_child(p)
	p.global_position = pos
	p.emitting = true
	p.get_tree().create_timer(life + 0.3, false).timeout.connect(p.queue_free)


static func explosion(parent: Node, pos: Vector3) -> void:
	burst(parent, pos + Vector3.UP, Color(1.0, 0.75, 0.3), 36, 14.0, 3.0, 0.7)
	burst(parent, pos + Vector3.UP * 0.5, Color(0.25, 0.2, 0.18, 0.9), 24, 6.0, 5.0, 1.4)


static func sparks(parent: Node, pos: Vector3, color := Color(1.0, 0.85, 0.4)) -> void:
	burst(parent, pos, color, 12, 9.0, 0.8, 0.35)
