extends Node
## Race screen: wires the race simulation, HUD and profile commit together.

var race: RaceManager
var hud: Hud


func _ready() -> void:
	race = RaceManager.new()
	race.name = "Race"
	add_child(race)
	race.setup(true)
	hud = Hud.new()
	add_child(hud)
	hud.bind(race)
	race.result_fixed.connect(func(r: Dictionary) -> void: Game.commit_result(r))
	race.race_finished.connect(func(_r: Dictionary) -> void: Game.goto_results())
