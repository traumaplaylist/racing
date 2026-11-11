class_name RaceManager
extends Node3D
## Race state and rules. Owns the fixed-tick simulation: inputs → resets → movement →
## collisions → progress → weapons → pickups → damage → finishes → survivor → result.
## HUD/garage/profile only read this state or receive the final result.

signal message(text: String, color: Color)
signal player_hit_target(target: RaceCar)
signal player_damaged
signal result_fixed(result: Dictionary)
signal race_finished(result: Dictionary)

enum Phase { COUNTDOWN, RACING, ENDED }

const BOT_COLORS := [Color("ff8a1f"), Color("d43a8c"), Color("ffd23a"), Color("c8282e"), Color("7a4fd6")]
const BOT_TYPES := ["bruiser", "buggy", "bruiser", "buggy", "buggy"]
const BOT_WEAPONS := ["pulse", "blaster", "blaster", "pulse", "blaster"]
const PLAYER_COLOR := Color("1fc8c0")
## Pickup spots: fraction of lap, lateral offset (m), type. Shared by player and bots.
const PICKUP_SPOTS := [
	[0.07, -4.0, "boost"], [0.07, 4.0, "repair"],
	[0.33, 3.0, "boost"], [0.52, -2.0, "repair"],
	[0.72, 0.0, "boost"], [0.86, -3.5, "repair"], [0.86, 3.5, "boost"],
]

var track: TrackData
var cars: Array[RaceCar] = []
var player: RaceCar
var drivers: Dictionary = {}          # RaceCar -> BotDriver
var projectiles: Array[Dictionary] = []
var pickups: Array[Dictionary] = []
var phase := Phase.COUNTDOWN
var countdown := 0.0
var race_time := 0.0
var tick := 0
var winner: RaceCar = null
var win_by := ""                      # "finish" | "survival"
var finish_order: Array[RaceCar] = []
var result: Dictionary = {}
var standings: Array[RaceCar] = []
var visuals := true                   # false in headless tests: skip FX/audio
var player_autopilot := false         # debug/test only
var player_cmd := {}
var bot_seed := 1000                  # optional scripted player commands (tests)

var camera: RaceCamera
var engine_audio: EngineAudio
var _end_timer := -1.0
var _pending_dmg: Array = []          # [car, amount, source]
var _finish_cands: Array = []         # [car, frac]
var dmg_stats := {"wall": 0.0, "car": 0.0, "shot": 0.0}   # telemetry for tuning


func setup(p_visuals := true) -> void:
	visuals = p_visuals
	track = TrackData.new()
	if visuals:
		TrackBuilder.build(self, track)
	_spawn_cars()
	_spawn_pickups()
	countdown = Cfg.COUNTDOWN_STEP * 3.0
	_update_standings()
	if visuals:
		camera = RaceCamera.new()
		camera.target = player
		add_child(camera)
		camera.current = true
		camera.snap()
		engine_audio = EngineAudio.new()
		add_child(engine_audio)


func is_racing() -> bool:
	return phase == Phase.RACING


func _spawn_cars() -> void:
	var stats := Game.current_stats()
	var order: Array = []
	for i in Cfg.RACER_COUNT:
		order.append(i)
	# player starts mid-pack (slot 3 of 6)
	var player_slot := 3
	var bot_i := 0
	for slot in Cfg.RACER_COUNT:
		var car := RaceCar.new()
		car.name = "Car%d" % slot
		if slot == player_slot:
			car.setup(0, true, Loc.t("racer_you"), Game.car_id, Game.weapon_id, PLAYER_COLOR, stats)
			player = car
		else:
			var t: String = BOT_TYPES[bot_i]
			var st := Cfg.car_stats(t, 1, 1)
			car.setup(bot_i + 1, false, Loc.t("racer_bot_%d" % (bot_i + 1)), t, BOT_WEAPONS[bot_i], BOT_COLORS[bot_i], st)
			bot_i += 1
		add_child(car)
		var gs := track.length - 10.0 - (slot / 2) * 9.0 - (slot % 2) * 4.5
		var lat := 3.2 if slot % 2 == 0 else -3.2
		var p := track.point_at(gs) + TrackData.right_of(track.tangent_at(gs)) * lat
		car.place_at(p, TrackData.heading_of(track.tangent_at(gs)))
		var pr := track.project(car.pos)
		car.track_i = pr["i"]
		car.s = pr["s"]
		car.lat = pr["lat"]
		cars.append(car)
		car.destroyed_at = -1.0
	cars.sort_custom(func(a: RaceCar, b: RaceCar) -> bool: return a.id < b.id)
	for c in cars:
		if not c.is_player:
			drivers[c] = BotDriver.new(c, self, track, bot_seed + c.id * 7919)
	if Game.debug_flags.has("autopilot"):
		player_autopilot = true
	var pd := BotDriver.new(player, self, track, 77)
	pd.skill = 1.0
	pd.lane_bias = 0.0
	pd.autopilot = true
	drivers[player] = pd


func _spawn_pickups() -> void:
	for spot in PICKUP_SPOTS:
		var s: float = track.length * spot[0]
		var lat: float = spot[1]
		var p := track.point_at(s) + TrackData.right_of(track.tangent_at(s)) * lat
		var e := {"type": spot[2], "s": s, "lat": lat, "pos": p, "active": true, "timer": 0.0, "node": null}
		if visuals:
			e["node"] = _make_pickup_node(spot[2], p)
		pickups.append(e)


func _make_pickup_node(type: String, p: Vector2) -> Node3D:
	var n := Node3D.new()
	n.position = Vector3(p.x, 0, p.y)
	add_child(n)
	var pad := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 2.2
	cm.bottom_radius = 2.2
	cm.height = 0.05
	cm.radial_segments = 20
	pad.mesh = cm
	var col := Color("3ddc6a") if type == "repair" else Color("ffb21f")
	var pm := TrackBuilder.unshaded(col.darkened(0.35))
	pad.material_override = pm
	pad.position.y = 0.04
	n.add_child(pad)
	var icon := Node3D.new()
	icon.name = "Icon"
	icon.position.y = 1.6
	n.add_child(icon)
	var m := TrackBuilder.unshaded(col)
	var white := TrackBuilder.unshaded(Color("fffaf0"))
	if type == "repair":
		# cross
		for sz in [Vector3(2.0, 0.6, 0.6), Vector3(0.6, 0.6, 2.0)]:
			var b := MeshInstance3D.new()
			var bm := BoxMesh.new()
			bm.size = sz
			b.mesh = bm
			b.material_override = white
			icon.add_child(b)
		var base := MeshInstance3D.new()
		var bb := BoxMesh.new()
		bb.size = Vector3(2.5, 0.3, 2.5)
		base.mesh = bb
		base.material_override = m
		base.position.y = -0.45
		icon.add_child(base)
	else:
		# double chevron pointing along travel direction (+Z local, rotated per frame)
		for row in 2:
			for side in [-1.0, 1.0]:
				var b := MeshInstance3D.new()
				var bm := BoxMesh.new()
				bm.size = Vector3(1.3, 0.45, 0.45)
				b.mesh = bm
				b.material_override = m if row == 0 else white
				b.position = Vector3(side * 0.45, 0, row * 1.0 - 0.5)
				b.rotation.y = side * 0.75
				icon.add_child(b)
	return n


# ------------------------------------------------------------------ main loop

func _physics_process(dt: float) -> void:
	step(dt)


func _process(delta: float) -> void:
	if not visuals:
		return
	for c in cars:
		if c.in_race or c.visible:
			c.sync_visual(delta)
	for p in pickups:
		var n: Node3D = p["node"]
		if n:
			n.visible = p["active"]
			var icon: Node3D = n.get_node("Icon")
			icon.rotation.y += delta * 2.0
			icon.position.y = 1.6 + sin(Time.get_ticks_msec() * 0.004) * 0.25
	for pr in projectiles:
		var node: Node3D = pr["node"]
		if node:
			node.position = Vector3(pr["pos"].x, 1.0, pr["pos"].y)
	if engine_audio:
		engine_audio.rpm = clampf(absf(player.vf) / player.stats["vmax"], 0.0, 1.2) if player.alive else 0.0
		engine_audio.engine_load = player.throttle if player.alive else 0.0
		engine_audio.slide = player.drift if player.alive and player.speed() > 5.0 else 0.0
		engine_audio.volume_db = -6.0 if phase != Phase.ENDED else -18.0


func step(dt: float) -> void:
	tick += 1
	if phase == Phase.COUNTDOWN:
		var before := ceili(countdown)
		countdown -= dt
		var after := ceili(countdown)
		if after != before and visuals:
			Sfx.play("go" if after <= 0 else "beep")
		if countdown <= 0.0:
			phase = Phase.RACING
			message.emit(Loc.t("hud_go"), Color("ffd23a"))
		return
	if phase == Phase.ENDED:
		for c in cars:
			c.throttle = 0.0
			c.brake = 0.4
			c.fire = false
			c.sim_move(dt)
			_resolve_walls(c)
		if _end_timer >= 0.0:
			_end_timer -= dt
			if _end_timer < 0.0:
				race_finished.emit(result)
		return

	race_time += dt
	_finish_cands.clear()

	# 1. commands: player input or autopilot; bots
	_read_player_input()
	for c in cars:
		if not c.is_player:
			drivers[c].update(dt)
	# 2. resets (same rule for everyone)
	for c in cars:
		if c.reset_pending:
			_try_reset(c)
	# 3. movement + barriers
	for c in cars:
		if not c.in_race:
			continue
		c.tick_timers(dt)
		c.sim_move(dt)
		_resolve_walls(c)
	# 4. car vs car
	_resolve_car_collisions()
	# 5. progress / checkpoints (records finish candidates with in-tick crossing order)
	for c in cars:
		if c.in_race:
			_update_progress(c)
	# 6. weapons
	for c in cars:
		if c.in_race and c.alive and c.fire and c.can_fire():
			_fire(c)
	_step_projectiles(dt)
	# 7. pickups
	_step_pickups(dt)
	# 8. damage first
	_apply_damage()
	# 9. valid finishes of cars still alive, by crossing order then stable id
	_resolve_finishes()
	# 10. last car standing / nobody left
	_resolve_survivor()
	# wreck cleanup
	for c in cars:
		if not c.alive and c.in_race:
			c.wreck_timer -= dt
			if c.wreck_timer <= 0.0:
				c.in_race = false
				c.visible = false
	_update_standings()
	# 11. player-facing result (fixed once)
	_check_result()


func _read_player_input() -> void:
	var p := player
	if not p.alive:
		return
	if player_autopilot:
		drivers[p].update(1.0 / 60.0)
	elif not player_cmd.is_empty():
		p.throttle = player_cmd.get("throttle", 0.0)
		p.brake = player_cmd.get("brake", 0.0)
		p.steer = player_cmd.get("steer", 0.0)
		p.handbrake = player_cmd.get("handbrake", false)
		p.fire = player_cmd.get("fire", false)
	else:
		p.throttle = Input.get_action_strength("accelerate")
		p.brake = Input.get_action_strength("brake")
		p.steer = Input.get_axis("steer_left", "steer_right")
		p.handbrake = Input.is_action_pressed("handbrake")
		p.fire = Input.is_action_pressed("fire")
	if not visuals:
		return
	if Input.is_action_just_pressed("reset_car"):
		request_reset(p)


# ------------------------------------------------------------------ reset

## Request a manual reset. Ignored during cooldown; deferred while the spot is occupied.
func request_reset(c: RaceCar) -> bool:
	if not c.alive or phase != Phase.RACING or c.reset_cd > 0.0 or c.reset_pending:
		return false
	c.reset_pending = true
	_try_reset(c)
	return true


func reset_anchor_s(c: RaceCar) -> float:
	if not c.started:
		return track.length - 12.0
	var n := track.cp_s.size()
	return track.cp_s[(c.next_cp - 1 + n) % n] + 2.0


func _try_reset(c: RaceCar) -> void:
	if not c.alive:
		c.reset_pending = false
		return
	var s := reset_anchor_s(c)
	var t := track.tangent_at(s)
	var r := TrackData.right_of(t)
	var hw := track.half_width_at(s) - c.radius - 1.0
	for off: float in [0.0, -4.0, 4.0, -7.5, 7.5]:
		if absf(off) > hw:
			continue
		for back: float in [0.0, -6.0]:
			var p := track.point_at(s + back) + r * off
			var free := true
			for o in cars:
				if o != c and o.in_race and o.pos.distance_to(p) < 5.5:
					free = false
					break
			if free:
				c.place_at(p, TrackData.heading_of(t))
				var pr := track.project(c.pos)
				c.track_i = pr["i"]
				c.s = pr["s"]
				c.lat = pr["lat"]
				c.reset_pending = false
				c.reset_cd = Cfg.RESET_COOLDOWN
				return
	# occupied: stay pending and retry next tick


# ------------------------------------------------------------------ physics

func _resolve_walls(c: RaceCar) -> void:
	var pr := track.project(c.pos, c.track_i)
	c.track_i = pr["i"]
	var s: float = pr["s"]
	var lat: float = pr["lat"]
	var hw := track.half_width_at(s)
	var n := TrackData.right_of(track.tangent_at(s))
	var ext := c.radius + c.half_len * absf(c.forward().dot(n))
	var limit := hw - ext
	if absf(lat) <= limit:
		return
	var out := n * signf(lat)
	c.pos -= out * (absf(lat) - limit)
	var vn := c.vel.dot(out)
	if vn > 0.0:
		c.vel -= out * vn * 1.25
		c.vel *= 0.985
		c.yaw_rate *= 0.6
		if c.alive and phase == Phase.RACING and vn > Cfg.WALL_DMG_THRESHOLD:
			_pending_dmg.append([c, (vn - Cfg.WALL_DMG_THRESHOLD) * Cfg.WALL_DMG_PER_MS, null])
			dmg_stats["wall"] += (vn - Cfg.WALL_DMG_THRESHOLD) * Cfg.WALL_DMG_PER_MS
		if visuals and vn > 4.0:
			var hit := c.pos + out * c.radius
			Fx.sparks(self, Vector3(hit.x, 0.6, hit.y))
			if c.is_player:
				Sfx.play("bump", clampf(vn / 20.0, 0.2, 1.0))
				if camera and vn > Cfg.WALL_DMG_THRESHOLD:
					camera.shake(0.8)


static func _closest_seg_seg(p1: Vector2, q1: Vector2, p2: Vector2, q2: Vector2) -> Array:
	var d1 := q1 - p1
	var d2 := q2 - p2
	var r := p1 - p2
	var a := d1.dot(d1)
	var e := d2.dot(d2)
	var f := d2.dot(r)
	var s := 0.0
	var t := 0.0
	var c := d1.dot(r)
	var b := d1.dot(d2)
	var denom := a * e - b * b
	if denom > 1e-6:
		s = clampf((b * f - c * e) / denom, 0.0, 1.0)
	t = (b * s + f) / e
	if t < 0.0:
		t = 0.0
		s = clampf(-c / a, 0.0, 1.0)
	elif t > 1.0:
		t = 1.0
		s = clampf((b - c) / a, 0.0, 1.0)
	return [p1 + d1 * s, p2 + d2 * t]


func _resolve_car_collisions() -> void:
	var n := cars.size()
	for i in n:
		var a := cars[i]
		if not a.in_race:
			continue
		for j in range(i + 1, n):
			var b := cars[j]
			if not b.in_race:
				continue
			if a.pos.distance_squared_to(b.pos) > 49.0:
				continue
			var ca := a.capsule()
			var cb := b.capsule()
			var cp := _closest_seg_seg(ca[0], ca[1], cb[0], cb[1])
			var d: Vector2 = cp[0] - cp[1]
			var dist := d.length()
			var min_d := a.radius + b.radius
			if dist >= min_d:
				continue
			var nrm := d / dist if dist > 1e-4 else (a.pos - b.pos).normalized()
			var pen := min_d - dist
			var ima := 1.0 / a.mass
			var imb := 1.0 / b.mass
			a.pos += nrm * pen * ima / (ima + imb)
			b.pos -= nrm * pen * imb / (ima + imb)
			var rel := (a.vel - b.vel).dot(nrm)
			if rel >= 0.0:
				continue
			var jimp := -(1.0 + 0.3) * rel / (ima + imb)
			a.vel += nrm * jimp * ima
			b.vel -= nrm * jimp * imb
			var closing := -rel
			if phase == Phase.RACING and closing > Cfg.CAR_DMG_THRESHOLD:
				var dmg := (closing - Cfg.CAR_DMG_THRESHOLD) * Cfg.CAR_DMG_PER_MS
				# heavier car takes less
				var share_a := 2.0 * b.mass / (a.mass + b.mass)
				var share_b := 2.0 * a.mass / (a.mass + b.mass)
				dmg_stats["car"] += dmg * 2.0
				if a.alive:
					_pending_dmg.append([a, dmg * share_a, b])
				if b.alive:
					_pending_dmg.append([b, dmg * share_b, a])
			if visuals and closing > 3.0:
				var mid: Vector2 = (cp[0] + cp[1]) * 0.5
				Fx.sparks(self, Vector3(mid.x, 0.8, mid.y))
				if a.is_player or b.is_player:
					Sfx.play("bump", clampf(closing / 15.0, 0.2, 1.0))


# ------------------------------------------------------------------ progress

func _update_progress(c: RaceCar) -> void:
	var pr := track.project(c.pos, c.track_i)
	c.track_i = pr["i"]
	var s_new: float = pr["s"]
	var d := track.delta_s(c.s, s_new)
	var target := track.cp_s[c.next_cp]
	var a := track.delta_s(c.s, target)
	if d > 0.0 and a > 0.0 and a <= d:
		var frac := a / d
		if c.next_cp == 0:
			if not c.started:
				c.started = true
			else:
				c.laps_done += 1
				if c.laps_done >= Cfg.LAPS and not c.finished:
					_finish_cands.append([c, frac])
				elif c.is_player and c.laps_done == Cfg.LAPS - 1:
					message.emit(Loc.t("hud_final_lap"), Color("ffd23a"))
		c.cps_passed += 1
		c.next_cp = (c.next_cp + 1) % track.cp_s.size()
	c.s = s_new
	c.lat = pr["lat"]
	# wrong-way timer (HUD hint)
	if c.vel.dot(track.tangent_at(c.s)) < -3.0:
		c.wrong_way_t += 1.0 / 60.0
	else:
		c.wrong_way_t = 0.0


func current_lap(c: RaceCar) -> int:
	return clampi(c.laps_done + 1, 1, Cfg.LAPS)


func _rank_less(a: RaceCar, b: RaceCar) -> bool:
	var fa := finish_order.find(a)
	var fb := finish_order.find(b)
	if fa >= 0 or fb >= 0:
		if fa < 0:
			return false
		if fb < 0:
			return true
		return fa < fb
	if a.alive != b.alive:
		return a.alive
	if not a.alive:
		return a.destroyed_at > b.destroyed_at
	if a.cps_passed != b.cps_passed:
		return a.cps_passed > b.cps_passed
	var da := fposmod(track.cp_s[a.next_cp] - a.s, track.length)
	var db := fposmod(track.cp_s[b.next_cp] - b.s, track.length)
	if absf(da - db) > 0.001:
		return da < db
	return a.id < b.id


func _update_standings() -> void:
	standings = cars.duplicate()
	standings.sort_custom(_rank_less)


func position_of(c: RaceCar) -> int:
	return standings.find(c) + 1


func rivals_left() -> int:
	var n := 0
	for c in cars:
		if c != player and c.alive:
			n += 1
	return n


# ------------------------------------------------------------------ weapons

func _fire(c: RaceCar) -> void:
	var w := c.weapon
	c.fire_cd = w["cooldown"]
	var f := c.forward()
	var muzzle := c.pos + f * (c.half_len + c.radius + 0.3)
	# strictly along the body axis; inherits forward speed only
	var spd: float = w["speed"] + maxf(0.0, c.vf)
	var pr := {"pos": muzzle, "dir": f, "speed": spd, "owner": c, "dmg": w["dmg"],
		"left": w["range"], "radius": w["radius"], "hint": c.track_i, "node": null}
	if visuals:
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		var heavy := c.weapon_id == "pulse"
		bm.size = Vector3(0.9, 0.9, 2.6) if heavy else Vector3(0.3, 0.3, 2.2)
		mi.mesh = bm
		var col := Color("9ff6ff") if heavy else Color("fff1a0")
		if c.is_player:
			col = Color("7ffff2") if heavy else Color("e9fff9")
		mi.material_override = TrackBuilder.unshaded(col)
		mi.position = Vector3(muzzle.x, 1.0, muzzle.y)
		mi.rotation.y = c.heading
		add_child(mi)
		pr["node"] = mi
		var vol := 1.0 if c.is_player else clampf(1.0 - c.pos.distance_to(player.pos) / 90.0, 0.0, 0.5)
		Sfx.play(c.weapon_id, vol, randf_range(0.95, 1.05))
	projectiles.append(pr)


func _step_projectiles(dt: float) -> void:
	var keep: Array[Dictionary] = []
	for pr in projectiles:
		var p0: Vector2 = pr["pos"]
		var dist: float = pr["speed"] * dt
		var p1: Vector2 = p0 + pr["dir"] * dist
		var best_t := INF
		var best: RaceCar = null
		for c in cars:
			if c == pr["owner"] or not c.in_race or not c.alive:
				continue
			if c.pos.distance_to(p0) > dist + 6.0:
				continue
			var cap := c.capsule()
			var cp := _closest_seg_seg(p0, p1, cap[0], cap[1])
			if (cp[0] - cp[1]).length() <= c.radius + float(pr["radius"]):
				var t := p0.distance_to(cp[0])
				if t < best_t:
					best_t = t
					best = c
		if best:
			var owner: RaceCar = pr["owner"]
			_pending_dmg.append([best, pr["dmg"], owner])
			dmg_stats["shot"] += float(pr["dmg"])
			if visuals:
				var hp3 := Vector3(best.pos.x, 1.0, best.pos.y)
				Fx.sparks(self, hp3, Color("ffe08a") if pr["radius"] < 0.6 else Color("9ff6ff"))
				var heavy: bool = float(pr["dmg"]) > 15.0
				var vol := 1.0 if (owner.is_player or best.is_player) else 0.35
				Sfx.play("hit_heavy" if heavy else "hit", vol)
				best.model.flash()
				if owner.is_player:
					player_hit_target.emit(best)
				if best.is_player:
					player_damaged.emit()
					if camera:
						camera.shake(0.5 if heavy else 0.2)
			_free_proj(pr)
			continue
		pr["pos"] = p1
		pr["left"] = float(pr["left"]) - dist
		var tp := track.project(p1, pr["hint"])
		pr["hint"] = tp["i"]
		if absf(tp["lat"]) > track.half_width_at(tp["s"]) + 0.6:
			if visuals:
				Fx.sparks(self, Vector3(p1.x, 1.0, p1.y), Color(1, 0.7, 0.4))
			_free_proj(pr)
			continue
		if pr["left"] <= 0.0:
			_free_proj(pr)
			continue
		keep.append(pr)
	projectiles = keep


func _free_proj(pr: Dictionary) -> void:
	var n: Node3D = pr["node"]
	if n:
		n.queue_free()


# ------------------------------------------------------------------ pickups

func _step_pickups(dt: float) -> void:
	for p in pickups:
		if not p["active"]:
			p["timer"] = float(p["timer"]) - dt
			if p["timer"] <= 0.0:
				p["active"] = true
			continue
		for c in cars:   # stable id order: first touch wins
			if not c.alive or not c.in_race:
				continue
			if c.pos.distance_to(p["pos"]) > Cfg.PICKUP_RADIUS + c.radius:
				continue
			if p["type"] == "repair":
				if c.hp >= c.max_hp:
					continue          # stays on track for someone who needs it
				c.hp = minf(c.max_hp, c.hp + Cfg.REPAIR_HP)
			else:
				c.boost_t = Cfg.BOOST_TIME   # refresh, never stack
			p["active"] = false
			p["timer"] = Cfg.PICKUP_RESPAWN
			if visuals:
				var vol := 1.0 if c.is_player else clampf(1.0 - c.pos.distance_to(player.pos) / 70.0, 0.0, 0.4)
				Sfx.play("pickup_" + str(p["type"]), vol)
			break


# ------------------------------------------------------------------ terminal events

func _apply_damage() -> void:
	var killing_src: Dictionary = {}
	for e in _pending_dmg:
		var c: RaceCar = e[0]
		var amount: float = e[1]
		var src: RaceCar = e[2]
		if not c.alive or amount <= 0.0:
			continue
		c.hp = maxf(0.0, c.hp - amount)
		if src:
			c.last_attacker = src
			c.last_attacker_t = race_time
		if c.hp <= 0.0 and not killing_src.has(c):
			killing_src[c] = src
		if c.is_player and src == null and visuals:
			player_damaged.emit()
	_pending_dmg.clear()
	for c in cars:
		if c.alive and c.hp <= 0.0:
			_destroy(c, killing_src.get(c))


func _destroy(c: RaceCar, src: RaceCar) -> void:
	c.alive = false
	c.destroyed_at = race_time
	c.wreck_timer = Cfg.WRECK_LINGER
	c.reset_pending = false
	var killer := src
	if killer == null and c.last_attacker and race_time - c.last_attacker_t <= Cfg.KILL_CREDIT_WINDOW:
		killer = c.last_attacker
	if killer and killer != c:
		killer.kills += 1
	if visuals:
		c.model.set_wrecked()
		Fx.explosion(self, Vector3(c.pos.x, 0.5, c.pos.y))
		var vol := 1.0 if c.is_player else clampf(1.0 - c.pos.distance_to(player.pos) / 120.0, 0.25, 0.8)
		Sfx.play("explode", vol)
		if c.is_player:
			message.emit(Loc.t("hud_destroyed"), Color("ff5a3c"))
		else:
			message.emit(Loc.t("hud_rival_down", [c.display_name]), c.body_color)
		if camera:
			camera.shake(1.2 if c.is_player else 0.3)


func _resolve_finishes() -> void:
	if _finish_cands.is_empty():
		return
	var valid: Array = []
	for e in _finish_cands:
		var c: RaceCar = e[0]
		if c.alive:
			valid.append(e)
	valid.sort_custom(func(x: Array, y: Array) -> bool:
		if absf(x[1] - y[1]) > 1e-9:
			return x[1] < y[1]
		return (x[0] as RaceCar).id < (y[0] as RaceCar).id)
	for e in valid:
		var c: RaceCar = e[0]
		c.finished = true
		c.finish_time = race_time - (1.0 - float(e[1])) / 60.0
		finish_order.append(c)
		if winner == null:
			winner = c
			win_by = "finish"


func _resolve_survivor() -> void:
	if winner != null:
		return
	var alive: Array[RaceCar] = []
	for c in cars:
		if c.alive:
			alive.append(c)
	if alive.size() == 1:
		winner = alive[0]
		win_by = "survival"
	elif alive.is_empty():
		win_by = "none"


func _check_result() -> void:
	if not result.is_empty():
		return
	var reason := ""
	if winner == player:
		reason = "finished_first" if win_by == "finish" else "last_standing"
	elif not player.alive:
		reason = "no_winner" if win_by == "none" else "destroyed"
	elif winner != null:
		reason = "rival_finished"
	elif race_time >= Cfg.RACE_TIMEOUT:
		reason = "timeout"
	if reason == "":
		return
	_end(reason)


func _end(reason: String) -> void:
	phase = Phase.ENDED
	_update_standings()
	result = {
		"id": "%d-%d" % [Time.get_unix_time_from_system() * 1000.0, randi()],
		"outcome": "win" if reason in ["finished_first", "last_standing"] else "loss",
		"reason": reason,
		"rival": winner.display_name if winner and winner != player else "",
		"place": position_of(player),
		"player_finished": player.finished,
		"player_alive": player.alive,
		"time": race_time,
		"kills": player.kills,
		"reward": Cfg.reward_for(reason),
		"car": player.car_type,
		"weapon": player.weapon_id,
	}
	for p in projectiles:
		_free_proj(p)
	projectiles.clear()
	if visuals:
		message.emit(Loc.t("hud_finish") if player.finished else "", Color.WHITE)
	_end_timer = 2.5
	result_fixed.emit(result)


## Debug-only helpers used by automated tests and debug builds (not exposed in release UI).
func debug_damage(c: RaceCar, amount: float, src: RaceCar = null) -> void:
	_pending_dmg.append([c, amount, src])


func debug_place_before_finish(c: RaceCar, dist: float, final_lap := true) -> void:
	var s := track.length - dist
	c.place_at(track.point_at(s), TrackData.heading_of(track.tangent_at(s)))
	var pr := track.project(c.pos)
	c.track_i = pr["i"]
	c.s = pr["s"]
	c.started = true
	c.next_cp = 0
	c.laps_done = Cfg.LAPS - 1 if final_lap else 0
	c.cps_passed = c.laps_done * track.cp_s.size() + track.cp_s.size()
