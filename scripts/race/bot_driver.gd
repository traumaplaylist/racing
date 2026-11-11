class_name BotDriver
extends RefCounted
## Bot brain. Produces the same command set as the player (throttle, brake, steer,
## handbrake, fire, reset) for its car. Follows the centerline with a lateral offset,
## brakes for upcoming curvature, dodges cars ahead, grabs pickups and shoots forward.

var car: RaceCar
var race: Node   # RaceManager
var track: TrackData
var skill := 0.95          # fraction of the car's top speed the bot is willing to use
var corner_grip := 24.0    # lateral acceleration budget used for corner speed (m/s^2)
var lane_bias := 0.0       # preferred lateral offset fraction (-1..1)
var aim_slop := 0.6        # extra lateral tolerance when deciding to shoot
const RECENT_HIT_GRACE := 5.0
const OPENING_CEASEFIRE := 10.0   # let the pack spread before bots open fire
var autopilot := false     # used for the player in debug/automated tests

var _lat := 0.0
var _stuck_t := 0.0
var _wrong_t := 0.0
var _rng := RandomNumberGenerator.new()
var _want_boost := true
# trigger discipline: react, fire a burst, then hold fire for a while
var reaction := 0.35
var aggression := 0.8      # scales how long a bot holds fire between bursts (higher = shorter)
var burst_len := 1.0
var _sight_t := 0.0
var _burst_t := 0.0
var _hold_t := 0.0


func _init(p_car: RaceCar, p_race: Node, p_track: TrackData, seed_v: int) -> void:
	car = p_car
	race = p_race
	track = p_track
	_rng.seed = seed_v
	lane_bias = _rng.randf_range(-0.35, 0.35)
	skill = _rng.randf_range(0.9, 0.97)
	corner_grip = _rng.randf_range(21.0, 25.0)
	_want_boost = _rng.randf() < 0.7
	reaction = _rng.randf_range(0.5, 0.9)
	burst_len = _rng.randf_range(0.25, 0.6)
	aim_slop = _rng.randf_range(0.6, 1.6)   # wider window than the car → some misses
	aggression = _rng.randf_range(0.6, 1.0)


func update(dt: float) -> void:
	car.fire = false
	car.handbrake = false
	if not car.alive:
		car.throttle = 0.0
		car.brake = 0.0
		car.steer = 0.0
		return
	var spd := car.speed()
	var hw := track.half_width_at(car.s)

	# ---- desired lateral line
	var c_ahead := track.curvature_at(car.s + 18.0 + spd * 0.7)
	var inside := signf(c_ahead) * minf(1.0, absf(c_ahead) * 45.0)
	var target := (inside * 0.45 + lane_bias * (1.0 - absf(inside))) * hw
	target = _pickup_line(target, hw)
	target = _avoid(target, spd, hw)
	var lim := hw - car.radius - 1.0
	target = clampf(target, -lim, lim)
	_lat = move_toward(_lat, target, 7.0 * dt)

	# ---- steering towards a look-ahead point
	var look := 7.0 + spd * 0.5
	var ls := car.s + look
	var aim := track.point_at(ls) + TrackData.right_of(track.tangent_at(ls)) * _lat
	var to := aim - car.pos
	var ang := car.forward().angle_to(to)
	car.steer = clampf(ang * 2.6, -1.0, 1.0)

	# ---- speed for upcoming curvature
	var kmax := track.max_curvature(car.s + 2.0, 14.0 + spd * 1.3)
	var vt: float = car.vmax() * skill
	if kmax > 0.001:
		vt = minf(vt, sqrt(corner_grip / kmax))
	if absf(ang) > 0.6:
		vt = minf(vt, 14.0)
	if spd < vt - 0.5:
		car.throttle = 1.0
		car.brake = 0.0
	elif spd > vt + 2.0:
		car.throttle = 0.0
		car.brake = clampf((spd - vt) / 6.0, 0.3, 1.0)
	else:
		car.throttle = 0.35
		car.brake = 0.0
	if absf(ang) > 1.0 and spd > 12.0:
		car.handbrake = true

	# ---- weapons: fire only straight along the body axis
	car.fire = _trigger(dt)

	# ---- stuck / wrong way → same reset the player uses
	if race.is_racing():
		if spd < 1.5:
			_stuck_t += dt
		else:
			_stuck_t = maxf(0.0, _stuck_t - dt * 2.0)
		if car.forward().dot(track.tangent_at(car.s)) < -0.3:
			_wrong_t += dt
		else:
			_wrong_t = 0.0
		if _stuck_t > 2.5 or _wrong_t > 3.0:
			if race.request_reset(car):
				_stuck_t = 0.0
				_wrong_t = 0.0
		# blocked against something: try reversing out briefly
		if _stuck_t > 1.0 and _stuck_t < 2.2:
			car.throttle = 0.0
			car.brake = 1.0
			car.steer = -car.steer


func _pickup_line(target: float, hw: float) -> float:
	var best := INF
	var res := target
	for p: Dictionary in race.pickups:
		if not p["active"]:
			continue
		var ahead := track.delta_s(car.s, p["s"])
		if ahead < 8.0 or ahead > 70.0:
			continue
		var wanted := false
		if p["type"] == "repair" and car.hp < car.max_hp * 0.65:
			wanted = true
		elif p["type"] == "boost" and _want_boost:
			wanted = true
		if wanted and ahead < best:
			best = ahead
			res = p["lat"]
	return res


func _avoid(target: float, spd: float, hw: float) -> float:
	var f := car.forward()
	for o: RaceCar in race.cars:
		if o == car or not o.in_race:
			continue
		var rel: Vector2 = o.pos - car.pos
		var along := rel.dot(f)
		if along < 0.0 or along > 10.0 + spd * 0.45:
			continue
		var closing := car.vel.dot(f) - o.vel.dot(f)
		if closing < 1.0 and o.alive:
			continue
		if absf(o.lat - target) < 3.4:
			var left := o.lat - 3.8
			var right := o.lat + 3.8
			var lim := hw - car.radius - 1.0
			if absf(left - car.lat) < absf(right - car.lat) and left > -lim:
				target = left
			elif right < lim:
				target = right
			else:
				target = left
	return target


func _trigger(dt: float) -> bool:
	if race.race_time < OPENING_CEASEFIRE:
		return false   # no point-blank grid massacre at the start
	if _hold_t > 0.0:
		_hold_t -= dt
		return false
	if _target_in_sights():
		_sight_t += dt
	else:
		_sight_t = 0.0
		if _burst_t > 0.0:
			_burst_t = 0.0
			_hold_t = _rng.randf_range(3.0, 5.0) / aggression
		return false
	if _sight_t < reaction:
		return false
	_burst_t += dt
	if _burst_t > burst_len:
		_burst_t = 0.0
		_sight_t = 0.0
		_hold_t = _rng.randf_range(4.0, 7.0) / aggression
		return false
	return true


func _target_in_sights() -> bool:
	if not car.can_fire():
		return false
	var f := car.forward()
	var r := car.right()
	var rng: float = minf(car.weapon["range"] * 0.85, 30.0)
	for o: RaceCar in race.cars:
		if o == car or not o.alive or not o.in_race:
			continue
		# spread fire: leave a car alone for a moment after it was just hit
		if race.race_time - o.last_attacker_t < RECENT_HIT_GRACE:
			continue
		var rel: Vector2 = o.pos - car.pos
		var along := rel.dot(f)
		if along < 3.0 or along > rng:
			continue
		var side := absf(rel.dot(r))
		if side < o.radius + aim_slop:
			return true
	return false
