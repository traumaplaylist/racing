extends "res://tests/sim_test.gd"
## Balance sweep: N autopilot races with different bot seeds. Prints outcome stats.
func run() -> void:
	game = get_node("/root/Game")
	game.set_profile_name("test")
	var n := 12
	var reasons := {}
	for k in n:
		var r := RaceManager.new()
		r.set_physics_process(false)
		r.set_process(false)
		r.bot_seed = 5000 + k * 31
		add_child(r)
		r.setup(false)
		r.player_autopilot = true
		run_countdown(r)
		var first_lap := -1.0
		for i in int(Cfg.RACE_TIMEOUT * 60) + 10:
			r.step(DT)
			if first_lap < 0 and r.player.laps_done == 1:
				first_lap = r.race_time
			if r.phase == RaceManager.Phase.ENDED:
				break
		var dead := 0
		var resets := 0
		for c in r.cars:
			if not c.alive: dead += 1
		reasons[r.result["reason"]] = reasons.get(r.result["reason"], 0) + 1
		print("race %2d: %-15s t=%6.1f lap1=%5.1f place=%d dead=%d kills=%d hp=%3d dmg=%s winner=%s" % [k, r.result["reason"], r.race_time, first_lap, r.result["place"], dead, r.player.kills, int(r.player.hp), str(r.dmg_stats), r.winner.display_name if r.winner else "-"])
		r.free()
	print(reasons)
	get_tree().quit()
