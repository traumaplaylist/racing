class_name RaceCar
extends Node3D
## One racer: arcade vehicle simulation on the ground plane + its visual model.
## The race manager drives sim steps; this node never reads input itself.

signal destroyed(car: RaceCar)

# identity
var id := 0
var is_player := false
var display_name := ""
var car_type := "buggy"
var weapon_id := "blaster"
var body_color := Color.WHITE
var stats: Dictionary = {}
var weapon: Dictionary = {}

# physics state (x, z plane). forward = (sin heading, cos heading)
var pos := Vector2.ZERO
var heading := 0.0
var vel := Vector2.ZERO
var yaw_rate := 0.0
var mass := 1.0
var half_len := 1.0      # capsule half segment length
var radius := 1.0        # capsule radius

# controls (set by player input or bot each tick)
var throttle := 0.0
var brake := 0.0
var steer := 0.0         # -1 left .. +1 right
var handbrake := false
var fire := false

# combat / status
var hp := 100.0
var max_hp := 100.0
var alive := true
var in_race := true      # false after wreck effect: no longer collides or counts
var wreck_timer := 0.0
var boost_t := 0.0
var fire_cd := 0.0
var reset_cd := 0.0
var reset_pending := false
var last_attacker: RaceCar = null
var last_attacker_t := -999.0
var kills := 0
var destroyed_at := -1.0

# progress
var track_i := -1
var s := 0.0
var lat := 0.0
var next_cp := 0
var started := false     # crossed the start line once
var laps_done := 0
var cps_passed := 0
var finished := false
var finish_time := -1.0
var wrong_way_t := 0.0

# derived per tick
var drift := 0.0         # 0..1 lateral slip amount
var vf := 0.0            # forward speed (signed)

var model: CarModel
var hp_bar: Node3D
var _hp_fill: MeshInstance3D
var _dust: CPUParticles3D


func setup(p_id: int, p_player: bool, p_name: String, p_type: String, p_weapon: String,
		p_color: Color, p_stats: Dictionary) -> void:
	id = p_id
	is_player = p_player
	display_name = p_name
	car_type = p_type
	weapon_id = p_weapon
	body_color = p_color
	stats = p_stats
	weapon = Cfg.WEAPONS[p_weapon]
	max_hp = stats["hp"]
	hp = max_hp
	mass = stats["mass"]
	radius = stats["width"] * 0.5
	half_len = (stats["length"] - stats["width"]) * 0.5
	model = CarModel.new()
	model.setup(p_type, p_color, p_player)
	add_child(model)
	_make_dust()
	if not is_player:
		_make_hp_bar()


func forward() -> Vector2:
	return Vector2(sin(heading), cos(heading))


func right() -> Vector2:
	return Vector2(-cos(heading), sin(heading))


func speed() -> float:
	return vel.length()


func vmax() -> float:
	return stats["vmax"] * (Cfg.BOOST_MULT if boost_t > 0.0 else 1.0)


func capsule() -> Array[Vector2]:
	var f := forward() * half_len
	return [pos + f, pos - f]


## Arcade vehicle integration for one fixed step.
func sim_move(dt: float) -> void:
	if not alive:
		vel = vel.move_toward(Vector2.ZERO, 14.0 * dt)
		pos += vel * dt
		return
	var f := forward()
	var r := right()
	vf = vel.dot(f)
	var vl := vel.dot(r)
	var top := vmax()
	var acc: float = stats["accel"] * (Cfg.BOOST_MULT if boost_t > 0.0 else 1.0)
	var brk: float = stats["brake"]

	if throttle > 0.01:
		if vf < -0.5:
			vf = minf(0.0, vf + brk * throttle * dt)
		else:
			var k := 1.0 - (vf / top) * (vf / top)
			vf += acc * throttle * maxf(k, 0.0) * dt
	if brake > 0.01:
		if vf > 0.5:
			vf = maxf(0.0, vf - brk * brake * dt)
		else:
			vf = maxf(-stats["vrev"], vf - acc * 0.6 * brake * dt)
	if vf > top:
		vf = move_toward(vf, top, 9.0 * dt)
	# rolling resistance / coasting
	vf -= vf * 0.05 * dt
	if throttle <= 0.01 and brake <= 0.01:
		vf = move_toward(vf, 0.0, 2.2 * dt)
	if handbrake:
		vf = move_toward(vf, 0.0, 7.0 * dt)

	# steering: needs speed, gets less twitchy near top speed, inverts in reverse
	var spd := absf(vf)
	var factor := clampf(spd / 6.0, 0.0, 1.0) * lerpf(1.0, 0.5, clampf(spd / stats["vmax"], 0.0, 1.0))
	var dir := 1.0 if vf >= 0.0 else -1.0
	var drift_boost := 1.35 if (handbrake or drift > 0.35) else 1.0
	var target_yaw: float = -steer * stats["steer_rate"] * factor * dir * drift_boost
	yaw_rate = lerpf(yaw_rate, target_yaw, 1.0 - exp(-10.0 * dt))
	heading = wrapf(heading + yaw_rate * dt, -PI, PI)

	# lateral grip: handbrake breaks traction, drift recovers progressively
	var grip: float = stats["grip"]
	if handbrake:
		grip = stats["drift_grip"]
	elif drift > 0.3:
		grip = lerpf(stats["drift_grip"] * 1.6, grip, 0.35)
	vl *= exp(-grip * dt)
	# sliding scrubs a little speed
	vf -= signf(vf) * absf(vl) * 0.08 * dt
	drift = clampf(absf(vl) / 6.0, 0.0, 1.0)

	vel = f * vf + r * vl
	pos += vel * dt


func tick_timers(dt: float) -> void:
	boost_t = maxf(0.0, boost_t - dt)
	fire_cd = maxf(0.0, fire_cd - dt)
	reset_cd = maxf(0.0, reset_cd - dt)


func can_fire() -> bool:
	return alive and fire_cd <= 0.0


func weapon_ready_frac() -> float:
	return 1.0 - clampf(fire_cd / float(weapon["cooldown"]), 0.0, 1.0)


func place_at(p: Vector2, h: float) -> void:
	pos = p
	heading = h
	vel = Vector2.ZERO
	yaw_rate = 0.0
	drift = 0.0
	vf = 0.0
	track_i = -1   # force a global projection after a teleport
	sync_visual(0.0)


## Copies sim state into the 3D transform and animates the model.
func sync_visual(delta: float) -> void:
	position = Vector3(pos.x, 0.0, pos.y)
	rotation = Vector3(0.0, heading, 0.0)
	if model == null:
		return
	var lat_v := vel.dot(right())
	var roll := clampf(lat_v * 0.02, -0.12, 0.12) if alive else 0.35
	var pitch := clampf(-throttle * 0.03 + brake * 0.04, -0.05, 0.06) if alive else 0.15
	model.animate(delta, steer if alive else 0.0, vf, roll, pitch)
	if _dust:
		var dusty := alive and (drift > 0.35 or (handbrake and speed() > 6.0))
		_dust.emitting = dusty
	if hp_bar:
		hp_bar.visible = alive
		_hp_fill.scale.x = maxf(0.001, hp / max_hp)
		_hp_fill.position.x = -(1.0 - hp / max_hp) * 0.9


func _make_dust() -> void:
	_dust = CPUParticles3D.new()
	_dust.amount = 40
	_dust.lifetime = 0.9
	_dust.emitting = false
	_dust.position = Vector3(0, 0.25, -stats["length"] * 0.45)
	_dust.direction = Vector3(0, 0.6, -1)
	_dust.spread = 35.0
	_dust.initial_velocity_min = 1.5
	_dust.initial_velocity_max = 4.0
	_dust.gravity = Vector3(0, 0.6, 0)
	_dust.scale_amount_min = 0.8
	_dust.scale_amount_max = 1.8
	_dust.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	_dust.emission_box_extents = Vector3(stats["width"] * 0.5, 0.1, 0.2)
	var qm := QuadMesh.new()
	qm.size = Vector2(1.2, 1.2)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.vertex_color_use_as_albedo = true
	m.albedo_color = Color(0.86, 0.68, 0.48, 0.45)
	qm.material = m
	_dust.mesh = qm
	var grad := Gradient.new()
	grad.set_color(0, Color(1, 1, 1, 0.8))
	grad.set_color(1, Color(1, 1, 1, 0.0))
	_dust.color_ramp = grad
	_dust.local_coords = false
	add_child(_dust)


func _make_hp_bar() -> void:
	hp_bar = Node3D.new()
	hp_bar.position = Vector3(0, 3.2, 0)
	add_child(hp_bar)
	var back := MeshInstance3D.new()
	var qm := QuadMesh.new()
	qm.size = Vector2(1.9, 0.32)
	back.mesh = qm
	var bm := StandardMaterial3D.new()
	bm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	bm.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	bm.albedo_color = Color(0.08, 0.07, 0.06)
	bm.no_depth_test = true
	bm.render_priority = 1
	back.material_override = bm
	hp_bar.add_child(back)
	_hp_fill = MeshInstance3D.new()
	var fm := QuadMesh.new()
	fm.size = Vector2(1.8, 0.22)
	_hp_fill.mesh = fm
	var fmat := StandardMaterial3D.new()
	fmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	fmat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	fmat.albedo_color = body_color.lightened(0.15)
	fmat.no_depth_test = true
	fmat.render_priority = 2
	_hp_fill.material_override = fmat
	hp_bar.add_child(_hp_fill)
