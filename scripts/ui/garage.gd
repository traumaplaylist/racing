extends Node
## Garage: big 3D preview left, build settings right, upgrades with level and price below.

const LV := ["", "I", "II", "III"]

var show: Showroom
var credits_l: Label
var car_btns: Dictionary = {}
var weapon_btns: Dictionary = {}
var car_desc: Label
var car_stats_l: Label
var weapon_desc: Label
var up_rows: Dictionary = {}       # kind -> {level: Label, effect: Label, buy: Button}
var error_l: Label
var retry_btn: Button
var start_btn: Button


func _ready() -> void:
	show = Showroom.new()
	add_child(show)
	show.build(Game.car_id, RaceManager.PLAYER_COLOR, 3.2)
	_build_ui()
	_refresh()
	start_btn.grab_focus()
	if Game.load_source == "backup" or Game.load_source == "reset" or Game.load_source == "newer":
		_show_error({"backup": "Profile was damaged and restored from backup.",
			"reset": "Profile was unreadable; started a new one.",
			"newer": "Profile is from a newer version; progress will not be saved."}[Game.load_source], false)


func _build_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(root)

	var title := UiKit.label(Loc.t("garage_title"), 52, UiKit.TEXT, 10)
	root.add_child(title)
	title.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT, Control.PRESET_MODE_MINSIZE, 28)

	var panel := UiKit.panel()
	root.add_child(panel)
	panel.anchor_left = 0.5
	panel.anchor_right = 1.0
	panel.anchor_top = 0.0
	panel.anchor_bottom = 1.0
	panel.offset_left = 40
	panel.offset_right = -24
	panel.offset_top = 24
	panel.offset_bottom = -24
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	panel.add_child(v)

	var head := HBoxContainer.new()
	var bal_t := UiKit.label("BALANCE", 20, UiKit.DIM)
	bal_t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(bal_t)
	credits_l = UiKit.label("", 34, UiKit.WARM)
	head.add_child(credits_l)
	v.add_child(head)

	v.add_child(UiKit.label(Loc.t("section_car"), 20, UiKit.DIM))
	var ch := HBoxContainer.new()
	ch.add_theme_constant_override("separation", 10)
	for cid in Cfg.CAR_IDS:
		var b := UiKit.choice(Loc.t("car_" + cid), 24)
		b.custom_minimum_size = Vector2(0, 52)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.pressed.connect(_pick_car.bind(cid))
		ch.add_child(b)
		car_btns[cid] = b
	v.add_child(ch)
	car_desc = UiKit.label("", 18, UiKit.TEXT)
	v.add_child(car_desc)
	car_stats_l = UiKit.label("", 18, UiKit.ACCENT)
	v.add_child(car_stats_l)

	v.add_child(UiKit.label(Loc.t("section_weapon"), 20, UiKit.DIM))
	var wh := HBoxContainer.new()
	wh.add_theme_constant_override("separation", 10)
	for wid in Cfg.WEAPON_IDS:
		var b := UiKit.choice(Loc.t("weapon_" + wid), 24)
		b.custom_minimum_size = Vector2(0, 52)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.pressed.connect(_pick_weapon.bind(wid))
		wh.add_child(b)
		weapon_btns[wid] = b
	v.add_child(wh)
	weapon_desc = UiKit.label("", 18)
	v.add_child(weapon_desc)

	v.add_child(UiKit.label(Loc.t("section_upgrades"), 20, UiKit.DIM))
	for kind in ["armor", "engine"]:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		var name_l := UiKit.label(Loc.t("upgrade_" + kind), 24)
		name_l.custom_minimum_size.x = 110
		row.add_child(name_l)
		var lv_l := UiKit.label("", 24, UiKit.ACCENT)
		lv_l.custom_minimum_size.x = 80
		row.add_child(lv_l)
		var eff := UiKit.label("", 17, UiKit.DIM)
		eff.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		eff.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		row.add_child(eff)
		var buy := UiKit.button("", 20)
		buy.custom_minimum_size = Vector2(200, 48)
		buy.pressed.connect(_buy.bind(kind))
		row.add_child(buy)
		v.add_child(row)
		up_rows[kind] = {"level": lv_l, "effect": eff, "buy": buy}

	var err_row := HBoxContainer.new()
	error_l = UiKit.label("", 17, UiKit.BAD)
	error_l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	error_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	err_row.add_child(error_l)
	retry_btn = UiKit.button("Retry save", 18)
	retry_btn.visible = false
	retry_btn.pressed.connect(func() -> void:
		if Game.save_game():
			_show_error("", false)
		else:
			_show_error(Game.save_error, true))
	err_row.add_child(retry_btn)
	v.add_child(err_row)

	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(spacer)
	start_btn = UiKit.button(Loc.t("start_race"), 34, true)
	start_btn.custom_minimum_size.y = 74
	start_btn.pressed.connect(_start)
	v.add_child(start_btn)
	var bottom := HBoxContainer.new()
	var hint := UiKit.label(Loc.t("garage_hint"), 15, UiKit.DIM)
	hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	bottom.add_child(hint)
	var quit := UiKit.button(Loc.t("quit_game"), 18)
	quit.pressed.connect(func() -> void: get_tree().quit())
	bottom.add_child(quit)
	v.add_child(bottom)


func _show_error(text: String, can_retry: bool) -> void:
	error_l.text = text
	retry_btn.visible = can_retry and text != ""


func _refresh() -> void:
	credits_l.text = Loc.t("balance", [Game.credits])
	for cid in car_btns:
		car_btns[cid].set_pressed_no_signal(cid == Game.car_id)
	for wid in weapon_btns:
		weapon_btns[wid].set_pressed_no_signal(wid == Game.weapon_id)
	var st := Game.current_stats()
	car_desc.text = Loc.t("car_%s_desc" % Game.car_id)
	car_stats_l.text = Loc.t("stat_line", [int(st["hp"]), roundi(st["vmax"] * 3.6), "%.1f" % st["accel"]])
	var w: Dictionary = Cfg.WEAPONS[Game.weapon_id]
	weapon_desc.text = Loc.t("weapon_%s_desc" % Game.weapon_id, [int(w["dmg"]), "%.2f" % w["cooldown"]])
	for kind in up_rows:
		var r: Dictionary = up_rows[kind]
		var lv := Game.level(Game.car_id, kind)
		(r["level"] as Label).text = Loc.t("level", [LV[lv]])
		var total := lv - 1
		if kind == "armor":
			(r["effect"] as Label).text = Loc.t("upgrade_armor_effect", [int(Cfg.ARMOR_HP_PER_LEVEL * total)])
		else:
			(r["effect"] as Label).text = Loc.t("upgrade_engine_effect", [int(Cfg.ENGINE_PER_LEVEL * 100 * total)])
		var buy: Button = r["buy"]
		if lv >= Cfg.MAX_LEVEL:
			buy.text = Loc.t("upgrade_max")
			buy.disabled = true
		else:
			var cost := Cfg.upgrade_cost(lv)
			buy.text = Loc.t("upgrade_buy", [cost])
			buy.disabled = false   # stays focusable; shows denial when unaffordable
			buy.modulate = Color.WHITE if Game.credits >= cost else Color(1, 1, 1, 0.55)


func _pick_car(cid: String) -> void:
	if not Game.select(cid, Game.weapon_id):
		_show_error(Game.save_error, true)
	show.set_car(Game.car_id, RaceManager.PLAYER_COLOR)
	Sfx.play("ui_ok")
	_refresh()


func _pick_weapon(wid: String) -> void:
	if not Game.select(Game.car_id, wid):
		_show_error(Game.save_error, true)
	Sfx.play("ui_ok")
	_refresh()


func _buy(kind: String) -> void:
	var lv := Game.level(Game.car_id, kind)
	if lv >= Cfg.MAX_LEVEL or Game.credits < Cfg.upgrade_cost(lv):
		Sfx.play("ui_deny")
		_show_error(Loc.t("upgrade_cant_afford", [Cfg.upgrade_cost(lv)]) if lv < Cfg.MAX_LEVEL else "", false)
		return
	if Game.buy_upgrade(Game.car_id, kind):
		Sfx.play("pickup_repair")
		_show_error("", false)
	else:
		_show_error(Game.save_error, true)
	_refresh()


func _start() -> void:
	Sfx.play("ui_ok")
	start_btn.disabled = true
	Game.start_race()
