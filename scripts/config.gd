class_name Cfg
extends RefCounted
## Balance and rule constants (CONCEPT.md "Начальные параметры для плейтеста").
## Tune here after playtests.

const LAPS := 3
const BOT_COUNT := 5
const RACER_COUNT := 6
const RACE_TIMEOUT := 300.0          # seconds of active (unpaused) racing
const COUNTDOWN_STEP := 1.0          # "3", "2", "1", "GO"
const RESET_COOLDOWN := 3.0
const WRECK_LINGER := 1.2            # destroyed car still collides during the effect
const PICKUP_RESPAWN := 10.0
const PICKUP_RADIUS := 2.8
const REPAIR_HP := 30.0
const BOOST_MULT := 1.2
const BOOST_TIME := 2.0
const ARMOR_HP_PER_LEVEL := 12.0
const ENGINE_PER_LEVEL := 0.04
const MAX_LEVEL := 3
const UPGRADE_COST := {1: 100, 2: 200}   # price to go from level key to key+1
const REWARD_WIN := 120
const REWARD_RIVAL_FINISH := 50
const REWARD_OTHER_LOSS := 25

# Collision damage. A light barrier touch (normal speed below threshold) costs nothing.
const WALL_DMG_THRESHOLD := 11.0     # m/s into the barrier
const WALL_DMG_PER_MS := 1.5
const CAR_DMG_THRESHOLD := 9.0       # m/s relative closing speed
const CAR_DMG_PER_MS := 1.4
const KILL_CREDIT_WINDOW := 5.0      # wall kill credited to last shooter/rammer within N s

const CARS := {
	"buggy": {
		"hp": 100.0, "vmax_kmh": 145.0, "accel": 15.0, "brake": 26.0,
		"reverse_kmh": 32.0, "steer_rate": 2.25, "grip": 8.0, "drift_grip": 1.6,
		"mass": 1.0, "length": 3.8, "width": 2.1,
	},
	"bruiser": {
		"hp": 135.0, "vmax_kmh": 128.0, "accel": 12.0, "brake": 24.0,
		"reverse_kmh": 28.0, "steer_rate": 2.0, "grip": 9.0, "drift_grip": 1.9,
		"mass": 1.55, "length": 4.3, "width": 2.3,
	},
}

const WEAPONS := {
	"blaster": {"dmg": 7.0, "cooldown": 0.22, "speed": 150.0, "range": 75.0, "radius": 0.45},
	"pulse": {"dmg": 27.0, "cooldown": 0.95, "speed": 115.0, "range": 85.0, "radius": 0.9},
}

const CAR_IDS := ["buggy", "bruiser"]
const WEAPON_IDS := ["blaster", "pulse"]


## Effective stats for a car with purchased levels (1..3). Level effects stack linearly on base.
static func car_stats(car_id: String, armor_lv: int, engine_lv: int) -> Dictionary:
	var base: Dictionary = CARS[car_id]
	var s := base.duplicate()
	var eng := 1.0 + ENGINE_PER_LEVEL * float(engine_lv - 1)
	s["hp"] = base["hp"] + ARMOR_HP_PER_LEVEL * float(armor_lv - 1)
	s["vmax"] = base["vmax_kmh"] / 3.6 * eng
	s["accel"] = base["accel"] * eng
	s["vrev"] = base["reverse_kmh"] / 3.6
	return s


static func upgrade_cost(level: int) -> int:
	return UPGRADE_COST.get(level, -1)


## Reward is derived from the end reason only.
static func reward_for(reason: String) -> int:
	match reason:
		"finished_first", "last_standing":
			return REWARD_WIN
		"rival_finished":
			return REWARD_RIVAL_FINISH
		"destroyed", "no_winner", "timeout":
			return REWARD_OTHER_LOSS
	return 0
