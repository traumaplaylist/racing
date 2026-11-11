extends Node
## Headless rule tests. Run:
##   godot --headless res://tests/sim_test.tscn
## Each check prints PASS/FAIL; exit code = number of failures.

const DT := 1.0 / 60.0
var fails := 0
var passes := 0
var game: Node


func check(cond: bool, name: String, info := "") -> void:
	if cond:
		passes += 1
		print("PASS  ", name, ("  (" + info + ")") if info != "" else "")
	else:
		fails += 1
		print("FAIL  ", name, ("  (" + info + ")") if info != "" else "")


func new_race() -> RaceManager:
	var r := RaceManager.new()
	r.set_physics_process(false)
	r.set_process(false)
	add_child(r)
	r.setup(false)
	return r


func run_countdown(r: RaceManager) -> void:
	while r.phase == RaceManager.Phase.COUNTDOWN:
		r.step(DT)


func steps(r: RaceManager, n: int) -> void:
	for i in n:
		if r.phase == RaceManager.Phase.ENDED:
			return
		r.step(DT)


func freeze_bots(r: RaceManager) -> void:
	# park bots: replace drivers with no-op by zeroing their commands every tick via skill 0
	for c in r.cars:
		if not c.is_player:
			r.drivers[c].skill = 0.0


func kill(r: RaceManager, c: RaceCar, src: RaceCar = null) -> void:
	r.debug_damage(c, 9999.0, src)


func _ready() -> void:
	run.call_deferred()


func run() -> void:
	game = get_node("/root/Game")
	game.set_profile_name("test")
	for p in [game.SAVE_PATH, game.BACKUP_PATH, game.TMP_PATH]:
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(p))
	game.load_game()
	t_track()
	t_full_autopilot_race()
	t_false_lap_and_reset()
	t_finish_first()
	t_survival()
	t_rival_finish_and_destroyed()
	t_same_tick()
	t_weapons()
	t_pickups()
	t_timeout()
	t_bot_unstuck()
	t_profile()
	print("\nRESULT: %d passed, %d failed" % [passes, fails])
	game.set_profile_name("test")
	get_tree().quit(fails)


func t_track() -> void:
	var t := TrackData.new()
	check(t.length > 1400 and t.length < 2000, "track length", "%.0f m" % t.length)
	check(t.cp_s.size() == 10 and t.cp_s[0] == 0.0, "checkpoints")
	var pr := t.project(t.point_at(500.0) + TrackData.right_of(t.tangent_at(500.0)) * 3.0)
	check(absf(pr["s"] - 500.0) < 1.0 and absf(pr["lat"] - 3.0) < 0.3, "projection", str(pr))


func t_full_autopilot_race() -> void:
	var r := new_race()
	r.player_autopilot = true
	run_countdown(r)
	var lap_times: Array = []
	var last_lap := 0
	var resets := 0
	var min_hp := 999.0
	var t0 := 0.0
	var max_ticks := int(Cfg.RACE_TIMEOUT * 60) + 10
	var shots := 0
	for i in max_ticks:
		var before := r.projectiles.size()
		r.step(DT)
		shots += maxi(0, r.projectiles.size() - before)
		for c in r.cars:
			if c.reset_cd > Cfg.RESET_COOLDOWN - DT * 1.5:
				resets += 1
		if r.player.laps_done != last_lap:
			lap_times.append(snappedf(r.race_time - t0, 0.1))
			t0 = r.race_time
			last_lap = r.player.laps_done
		min_hp = minf(min_hp, r.player.hp)
		if r.phase == RaceManager.Phase.ENDED:
			break
	var order := []
	for c in r.standings:
		order.append("%s(L%d,cp%d,hp%d%s)" % [c.display_name, c.laps_done, c.cps_passed, int(c.hp), "" if c.alive else ",X"])
	print("   autopilot race: reason=%s time=%.1f laps=%s resets=%d shots=%d" % [r.result.get("reason", "-"), r.race_time, str(lap_times), resets, shots])
	print("   standings: ", ", ".join(order))
	print("   damage: ", r.dmg_stats)
	check(r.phase == RaceManager.Phase.ENDED, "autopilot race ends", str(r.result.get("reason")))
	check(r.race_time > 100.0 or r.result.get("reason") == "destroyed", "race runs its course", "%.1f" % r.race_time)
	check(shots > 0, "bots shoot")
	var best_bot := 0
	for c in r.cars:
		if not c.is_player:
			best_bot = maxi(best_bot, c.cps_passed)
	check(best_bot >= 20, "bots make progress (cps)", str(best_bot))
	r.queue_free()


func t_false_lap_and_reset() -> void:
	var r := new_race()
	freeze_bots(r)
	run_countdown(r)
	var p := r.player
	# drive forward over the start line and past cp1
	p.place_at(r.track.point_at(r.track.cp_s[1] - 5.0), TrackData.heading_of(r.track.tangent_at(r.track.cp_s[1])))
	p.started = true
	p.next_cp = 1
	p.cps_passed = 1
	p.s = r.track.cp_s[1] - 5.0
	p.track_i = r.track.index_at(p.s)
	r.player_cmd = {"throttle": 1.0}
	steps(r, 60)
	check(p.next_cp == 2 and p.cps_passed == 2, "forward cp counted", "next=%d" % p.next_cp)
	# reverse back across cp1: must not change progress
	r.player_cmd = {"brake": 1.0}
	steps(r, 240)
	check(p.next_cp == 2 and p.cps_passed == 2, "reverse cp ignored", "next=%d passed=%d" % [p.next_cp, p.cps_passed])
	# shortcut: teleport just before finish (skipping cps 2..9) and cross it
	var s := r.track.length - 6.0
	p.place_at(r.track.point_at(s), TrackData.heading_of(r.track.tangent_at(s)))
	p.track_i = r.track.index_at(s)
	p.s = s
	r.player_cmd = {"throttle": 1.0}
	steps(r, 90)
	check(p.laps_done == 0, "shortcut lap not counted", "laps=%d" % p.laps_done)
	# reset → last valid cp (cp1), keeps hp/time/progress, 3 s cooldown
	p.hp = 61.0
	var t_before := r.race_time
	var cps := p.cps_passed
	check(r.request_reset(p), "reset accepted")
	var d := r.track.delta_s(r.track.cp_s[1], p.s)
	check(absf(d - 2.0) < 1.0 and p.speed() < 0.01, "reset to last valid cp, speed 0", "ds=%.1f" % d)
	check(p.hp == 61.0 and p.cps_passed == cps and r.race_time == t_before, "reset keeps hp/progress/time")
	check(not r.request_reset(p), "reset cooldown blocks immediate repeat")
	steps(r, int(Cfg.RESET_COOLDOWN * 60) + 2)
	r.player_cmd = {}
	check(r.request_reset(p), "reset available after 3 s")
	# occupied spot: put a bot on every candidate → reset deferred
	r.queue_free()


func t_finish_first() -> void:
	var r := new_race()
	freeze_bots(r)
	run_countdown(r)
	r.debug_place_before_finish(r.player, 8.0)
	r.player_cmd = {"throttle": 1.0}
	steps(r, 120)
	check(r.result.get("reason") == "finished_first", "finish first → win", str(r.result.get("reason")))
	check(r.result.get("reward") == 120 and r.result.get("place") == 1, "+120 CR, place 1/6")
	r.queue_free()


func t_survival() -> void:
	var r := new_race()
	freeze_bots(r)
	run_countdown(r)
	var bots := r.cars.filter(func(c: RaceCar) -> bool: return not c.is_player)
	kill(r, bots[0], r.player)          # player kill
	kill(r, bots[1], bots[2])           # bot kills bot
	steps(r, 1)
	kill(r, bots[2], r.player)
	kill(r, bots[3], null)              # wall, no attacker
	steps(r, 1)
	check(r.result.is_empty(), "race continues with 2 alive")
	kill(r, bots[4], bots[4])           # self-inflicted wall-ish
	steps(r, 1)
	check(r.result.get("reason") == "last_standing", "last standing → win", str(r.result.get("reason")))
	check(r.result.get("kills") == 2, "only player's kills counted", str(r.result.get("kills")))
	check(r.result.get("reward") == 120, "+120 CR survival")
	r.queue_free()


func t_rival_finish_and_destroyed() -> void:
	var r := new_race()
	freeze_bots(r)
	run_countdown(r)
	var bot := r.cars[1]
	r.debug_place_before_finish(bot, 6.0)
	r.drivers[bot].skill = 1.0
	steps(r, 120)
	check(r.result.get("reason") == "rival_finished" and r.result.get("reward") == 50, "bot finishes first → loss +50", str(r.result.get("reason")))
	r.queue_free()
	r = new_race()
	run_countdown(r)
	kill(r, r.player, r.cars[1])
	steps(r, 1)
	check(r.result.get("reason") == "destroyed" and r.result.get("reward") == 25, "player destroyed → loss +25", str(r.result.get("reason")))
	r.queue_free()


func t_same_tick() -> void:
	# player crosses the finish in the same tick it is destroyed → no win by finish
	var r := new_race()
	freeze_bots(r)
	run_countdown(r)
	r.debug_place_before_finish(r.player, 0.3)
	r.player.vel = r.player.forward() * 30.0
	r.player_cmd = {"throttle": 1.0}
	kill(r, r.player, null)
	r.step(DT)
	check(not r.player.finished and r.result.get("reason") == "destroyed", "destroyed racer cannot win by finish", str(r.result.get("reason")))
	r.queue_free()
	# two finishers in one tick: earlier crossing wins; exact tie → lower id
	r = new_race()
	freeze_bots(r)
	run_countdown(r)
	var a := r.cars[2]
	var b := r.cars[4]
	r.debug_place_before_finish(a, 0.3)
	r.debug_place_before_finish(b, 0.3)
	b.pos += b.right() * 4.0
	a.pos += a.right() * -4.0
	a.vel = a.forward() * 30.0
	b.vel = b.forward() * 30.0
	r.step(DT)
	check(r.winner == a, "tie in one tick → stable id wins", r.winner.display_name if r.winner else "none")
	r.queue_free()
	# all remaining cars destroyed in the same tick → no winner, +25 once
	r = new_race()
	run_countdown(r)
	for c in r.cars:
		kill(r, c, null)
	r.step(DT)
	check(r.winner == null and r.result.get("reason") == "no_winner" and r.result.get("reward") == 25, "all destroyed → no winner, +25", str(r.result.get("reason")))
	r.queue_free()


func t_weapons() -> void:
	for wid in ["blaster", "pulse"]:
		game.weapon_id = wid
		var r := new_race()
		freeze_bots(r)
		run_countdown(r)
		var p := r.player
		var target := r.cars[1]
		var s := 40.0   # main straight
		var t := r.track.tangent_at(s)
		p.place_at(r.track.point_at(s), TrackData.heading_of(t))
		# target 25 m ahead but 5 m to the side: off-axis → must miss
		target.place_at(r.track.point_at(s + 25.0) + TrackData.right_of(r.track.tangent_at(s + 25.0)) * 5.0, TrackData.heading_of(t))
		var hp0 := target.hp
		r.player_cmd = {"fire": true}
		steps(r, 30)
		check(target.hp == hp0, "%s: no aim assist (off-axis miss)" % wid)
		target.place_at(r.track.point_at(s + 25.0), TrackData.heading_of(t))
		var shots := 0
		var hp1 := target.hp
		r.player_cmd = {"fire": false}
		steps(r, 60)   # let earlier volleys expire
		var w: Dictionary = Cfg.WEAPONS[wid]
		var hp := target.hp
		var deltas: Array = []
		r.player_cmd = {"fire": true}
		for i in 90:
			if i == 60:
				r.player_cmd = {"fire": false}
			var cd_before := p.fire_cd
			r.step(DT)
			if p.fire_cd > cd_before + 0.01:
				shots += 1
			if target.hp != hp:
				deltas.append(snappedf(hp - target.hp, 0.01))
				hp = target.hp
		var expect_shots := int(ceil(1.0 / w["cooldown"]))
		check(absi(shots - expect_shots) <= 1, "%s: fire rate" % wid, "%d shots/s" % shots)
		var all_exact := deltas.size() == shots and deltas.all(func(d: float) -> bool: return is_equal_approx(d, w["dmg"]))
		check(all_exact, "%s: every hit deals %d" % [wid, int(w["dmg"])], str(deltas))
		r.queue_free()
	game.weapon_id = "blaster"


func t_pickups() -> void:
	var r := new_race()
	freeze_bots(r)
	run_countdown(r)
	var p := r.player
	var rep: Dictionary = r.pickups.filter(func(e: Dictionary) -> bool: return e["type"] == "repair")[0]
	var boosts := r.pickups.filter(func(e: Dictionary) -> bool: return e["type"] == "boost")
	p.hp = p.max_hp
	p.place_at(rep["pos"], 0.0)
	steps(r, 1)
	check(rep["active"], "repair stays at full HP")
	p.hp = p.max_hp - 10.0
	steps(r, 1)
	check(not rep["active"] and p.hp == p.max_hp, "repair heals capped at max", "%.0f" % p.hp)
	steps(r, int(Cfg.PICKUP_RESPAWN * 60) - 5)
	check(not rep["active"], "repair not back before 10 s")
	steps(r, 10)
	check(rep["active"], "repair respawns after 10 s")
	p.place_at(boosts[0]["pos"], 0.0)
	steps(r, 1)
	check(p.boost_t > 1.9 and not boosts[0]["active"], "boost picked")
	steps(r, 60)
	var vmax_boost := p.vmax()
	p.place_at(boosts[1]["pos"], 0.0)
	steps(r, 1)
	check(p.boost_t > 1.9 and is_equal_approx(p.vmax(), vmax_boost), "second boost refreshes time, no stacking",
		"vmax %.1f vs base %.1f" % [p.vmax(), p.stats["vmax"]])
	check(is_equal_approx(p.vmax(), p.stats["vmax"] * Cfg.BOOST_MULT), "boost = +20% top speed")
	r.queue_free()


func t_timeout() -> void:
	var r := new_race()
	freeze_bots(r)
	run_countdown(r)
	steps(r, int(Cfg.RACE_TIMEOUT * 60) + 5)
	check(r.result.get("reason") == "timeout" and r.result.get("reward") == 25, "5 min timeout → +25", str(r.result.get("reason")))
	r.queue_free()


func t_profile() -> void:
	game.set_profile_name("test")
	for p in [game.SAVE_PATH, game.BACKUP_PATH]:
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(p))
	game.load_game()
	check(game.credits == 0, "fresh profile 0 CR")
	var res := {"id": "test-1", "reason": "finished_first", "reward": 99999}
	game.commit_result(res)
	check(game.credits == 120, "win credited 120 (reward recomputed, not trusted)", str(game.credits))
	game.commit_result(res)
	game.commit_result(res)
	check(game.credits == 120, "same result not credited twice")
	check(game.buy_upgrade("buggy", "armor") and game.credits == 20, "armor II costs 100 → 20 left")
	check(Cfg.car_stats("buggy", game.level("buggy", "armor"), 1)["hp"] == 112.0, "buggy 112 HP")
	check(game.level("bruiser", "armor") == 1, "bruiser unaffected")
	check(not game.buy_upgrade("buggy", "engine") and game.credits == 20 and game.level("buggy", "engine") == 1, "unaffordable purchase changes nothing")
	game.select("buggy", "pulse")
	game.load_game()
	check(game.weapon_id == "pulse" and game.level("buggy", "armor") == 2 and game.credits == 20, "selection/upgrades persist after reload")
	# corrupt main → backup restore
	game.select("buggy", "blaster")    # ensures backup holds a valid previous profile
	var f := FileAccess.open(game.SAVE_PATH, FileAccess.WRITE)
	f.store_string("{garbage")
	f.close()
	game.load_game()
	check(game.load_source == "backup" and game.level("buggy", "armor") == 2, "corrupt main → restored from backup", game.load_source)
	# both corrupt → clean defaults
	for p in [game.SAVE_PATH, game.BACKUP_PATH]:
		var g := FileAccess.open(p, FileAccess.WRITE)
		g.store_string("nope")
		g.close()
	game.load_game()
	check(game.credits == 0 and game.load_source == "reset", "both corrupt → safe defaults", game.load_source)
	# newer format is never overwritten
	var h := FileAccess.open(game.SAVE_PATH, FileAccess.WRITE)
	h.store_string('{"format": 99, "credits": 5}')
	h.close()
	game.load_game()
	game.select("bruiser", "pulse")
	var txt := FileAccess.get_file_as_string(game.SAVE_PATH)
	check(game.save_blocked and txt.contains("99"), "newer format not overwritten")


func t_bot_unstuck() -> void:
	var r := new_race()
	run_countdown(r)
	steps(r, 60 * 11)
	var bot := r.cars[2]
	# jam the bot nose-first into the barrier, facing backwards across the track
	var s := bot.s
	var t := r.track.tangent_at(s)
	var side := TrackData.right_of(t)
	var hw := r.track.half_width_at(s)
	bot.place_at(r.track.point_at(s) + side * (hw - 2.5), TrackData.heading_of(-t) + 1.2)
	var cps := bot.cps_passed
	var reset_seen := false
	for i in 60 * 8:
		r.step(DT)
		if bot.reset_cd > 0.0:
			reset_seen = true
			break
	check(reset_seen or bot.forward().dot(r.track.tangent_at(bot.s)) > 0.5, "stuck bot recovers (reset or drives out)",
		"reset=%s" % reset_seen)
	steps(r, 60 * 12)
	check(bot.cps_passed > cps, "bot keeps progressing after recovery", "%d -> %d" % [cps, bot.cps_passed])
	r.queue_free()
