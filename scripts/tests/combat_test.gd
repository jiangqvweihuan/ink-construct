extends Node2D

## 战斗反馈测试：伤害飘字 + 玩家 HUD 血条 + 小怪头顶血条。

const OUT_DIR := "res://tests/out/"
const PlayerClass := preload("res://scripts/player/player.gd")
const C016Class := preload("res://scripts/enemies/c016.gd")
const Settings = preload("res://scripts/ui/settings.gd")

var _log: FileAccess
var _player: PlayerClass
var _enemy: C016Class
var _hud: CanvasLayer
var _last_p_hp := -1
var _last_e_hp := -1
var _failed := 0


func p(msg) -> void:
	print("[CT] ", msg)
	if _log:
		_log.store_line("[CT] " + str(msg))
		_log.flush()


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	_log = FileAccess.open("res://tests/combat_test.log", FileAccess.WRITE)
	get_window().size = Vector2i(1280, 720)

	var bg := ColorRect.new()
	bg.color = Color(0.949, 0.918, 0.847)
	bg.size = Vector2(1280, 720)
	bg.z_index = -10
	add_child(bg)

	var ground := StaticBody2D.new()
	ground.position = Vector2(640, 640)
	add_child(ground)
	var rect := RectangleShape2D.new()
	rect.size = Vector2(1280, 80)
	var gs := CollisionShape2D.new()
	gs.shape = rect
	ground.add_child(gs)
	var gc := ColorRect.new()
	gc.color = Color(0.102, 0.102, 0.102)
	gc.size = Vector2(1280, 80)
	gc.position = Vector2(-640, -40)
	ground.add_child(gc)

	_player = load("res://scenes/player/player.tscn").instantiate()
	_player.position = Vector2(400, 560)
	add_child(_player)
	_enemy = load("res://scenes/enemies/c016.tscn").instantiate()
	_enemy.position = Vector2(700, 560)
	add_child(_enemy)
	_hud = load("res://scenes/ui/hud.tscn").instantiate()
	add_child(_hud)

	await get_tree().create_timer(0.8).timeout
	await _shot("01_start") # HUD 满血

	# 玩家走近站桩，等敌人攻击两刀（hp 5 -> 3）
	Input.action_press("move_right")
	var t := 0.0
	while t < 3.0:
		await get_tree().physics_frame
		t += get_physics_process_delta_time()
		if absf(_player.global_position.x - _enemy.global_position.x) < 150.0:
			break
	Input.action_release("move_right")
	if await _wait_hp_drop(true, _player.hp - 1, 6.0):
		await _shot("02_player_hit") # 飘字 + HUD 掉血
	await _wait_hp_drop(true, 3, 8.0)
	p("after enemy attacks, player hp=" + str(_player.hp))

	# 玩家反击，抓小怪掉血瞬间（飘字 + 头顶血条）
	var guard := 0
	while _enemy.state != 5 and guard < 20: # 5=DEAD
		if _player.state == 0 or _player.state == 1: # IDLE/RUN 才能出手
			_tap("attack")
		var before: int = _enemy.hp
		if await _wait_hp_drop(false, before - 1, 1.2):
			if before - 1 == 2:
				await _shot("03_enemy_hit")
		guard += 1
	await _shot("04_enemy_dead")
	_test_score_pause()
	await _test_hud_overhaul()

	var enemy_hp: int = _enemy.hp if is_instance_valid(_enemy) else 0
	var enemy_state: int = _enemy.state if is_instance_valid(_enemy) else 5
	p("ALL DONE, player hp=" + str(_player.hp) + " enemy hp=" + str(enemy_hp)
		+ " enemy state=" + str(enemy_state) + " failed=" + str(_failed))
	get_tree().quit(1 if _failed > 0 else 0)


func _check(ok: bool, label: String) -> void:
	if not ok:
		_failed += 1
	p(("PASS " if ok else "FAIL ") + label)


func _test_score_pause() -> void:
	var previous_time_scale := Engine.time_scale
	Engine.time_scale = 1.0
	Score.reset()
	Score.add_hit()
	var left: float = Score._combo_left
	get_tree().paused = true
	Score._process(0.5)
	_check(Score.combo == 1 and is_equal_approx(Score._combo_left, left), "暂停时连击窗口不递减")
	get_tree().paused = false
	Engine.time_scale = 0.05
	Score._process(0.005)
	_check(Score.combo == 1 and is_equal_approx(Score._combo_left, left - 0.1), "恢复后仍按顿帧真实时间递减")
	Engine.time_scale = previous_time_scale
	Score.reset()


func _test_hud_overhaul() -> void:
	Settings.persist = false
	_player.set_physics_process(false)
	_player.set_process(false)
	_enemy.set_physics_process(false)
	_player.state = PlayerClass.State.IDLE
	_player._invincible = false
	_player._hurt_invincible = 0.0
	_player._shield_hits = 0
	_player._stolen_bell = 0
	_player._stolen_block = 0
	_player._parry_ready = false
	_player._bell_shell = false
	_player._bleed_stacks = 0
	_player._buff_timer = 0.0
	_player.max_hp = 10
	_player.hp = 10
	_hud._player_extra = 0
	_hud._hp_bar.set_vital(10, 10, 0, true)
	_hud._on_hp_changed(10, 10)
	await get_tree().create_timer(0.1).timeout

	_player.hp = 6
	_player.hp_changed.emit(6, 10)
	await get_tree().create_timer(0.08).timeout
	_check(is_equal_approx(_hud._hp_bar._red_clip.size.x, 228.0), "掉血红条立即到 60%")
	_check(is_equal_approx(_hud._hp_bar._white_clip.size.x, 380.0), "掉血白色残影先停留")
	await _shot("05_hud_damage_mid")
	await get_tree().create_timer(0.8).timeout
	_check(is_equal_approx(_hud._hp_bar._white_clip.size.x, 228.0), "白色残影延迟后追至当前生命")

	_player.hp = 10
	_player.hp_changed.emit(10, 10)
	await get_tree().create_timer(0.08).timeout
	_check(is_equal_approx(_hud._hp_bar._green_clip.size.x, 380.0), "回血绿色提前量先到 100%")
	_check(_hud._hp_bar._red_clip.size.x < 380.0, "回血红条仍在追随")
	await _shot("06_hud_heal_mid")
	await get_tree().create_timer(0.55).timeout
	_check(is_equal_approx(_hud._hp_bar._red_clip.size.x, 380.0), "回血红条最终到 100%")

	_player.hp = 13
	_player.hp_changed.emit(13, 10)
	_player._shield_hits = 2
	await get_tree().create_timer(0.15).timeout
	_check(_hud._hp_bar.extra == 5 and _hud._hp_bar._extra_root.visible, "超额生命与护盾合并为白色尾段")
	await _shot("07_hud_extra")
	_player.hp = 10
	_player.hp_changed.emit(10, 10)
	_player.hurt(1)
	await get_tree().create_timer(0.1).timeout
	_check(_player.hp == 10 and _player._shield_hits == 1 and _hud._hp_bar.extra == 1, "首次攻击只消耗护盾不扣生命")
	_player.hurt(1)
	await get_tree().create_timer(0.1).timeout
	_check(_player.hp == 10 and _player._shield_hits == 0 and _hud._hp_bar.extra == 0, "护盾耗尽后尾段消失")

	_player._shield_hits = 2
	_player._buff_timer = 4.0
	_player._bleed_stacks = 2
	_player._bleed_time = 3.0
	_hud._sync_status(true)
	if not _player.hud_skills.is_empty():
		var skill_id := str(_player.hud_skills[0])
		_player._skill_cds[skill_id] = 3.0
		_hud._update_action_bar()
		_check(_hud._cd_labels[1].visible, "技能栏显示真实剩余冷却")
	await get_tree().create_timer(0.25).timeout
	await _shot("08_hud_status_skills")

	_player.swap_skull("c023")
	var pm = load("res://scenes/ui/pause_menu.tscn").instantiate()
	add_child(pm)
	await get_tree().create_timer(0.2).timeout
	_check(get_tree().paused, "暂停菜单暂停战斗")
	var long_desc: Label = null
	for label in pm.find_children("*", "Label", true, false):
		if str(label.text).contains("生命上限为 60"):
			long_desc = label
	_check(long_desc != null, "暂停页显示霜梅完整被动描述")
	if long_desc != null:
		_check(long_desc.autowrap_mode == TextServer.AUTOWRAP_ARBITRARY, "长被动描述启用自动换行")
		_check(long_desc.get_line_count() > 1, "长被动描述实际换成多行")
		_check(long_desc.position.y + long_desc.size.y <= long_desc.get_parent().size.y, "描述面板高度容纳全部文字")
	var scrolls: Array = pm.find_children("*", "ScrollContainer", true, false)
	_check(scrolls.size() == 1 and scrolls[0].vertical_scroll_mode == ScrollContainer.SCROLL_MODE_AUTO, "状态详情启用自动下滑条")
	if long_desc != null and not scrolls.is_empty():
		scrolls[0].ensure_control_visible(long_desc.get_parent())
		await get_tree().process_frame
	await _shot("09_pause_details")
	if not scrolls.is_empty():
		scrolls[0].scroll_vertical = 100000
		await get_tree().process_frame
		_check(scrolls[0].scroll_vertical > 0, "状态详情可实际向下滚动")
	await _press_escape()
	await get_tree().create_timer(0.1).timeout
	_check(not is_instance_valid(pm) and not get_tree().paused, "Esc 再次按下直接继续战斗")

	pm = load("res://scenes/ui/pause_menu.tscn").instantiate()
	add_child(pm)
	await get_tree().process_frame
	pm._open_settings()
	await get_tree().create_timer(0.2).timeout
	_check(is_instance_valid(pm._settings), "暂停菜单内打开设置")
	await _shot("10_pause_settings")
	await _press_escape()
	await get_tree().create_timer(0.25).timeout
	_check(is_instance_valid(pm) and not is_instance_valid(pm._settings) and get_tree().paused, "设置内 Esc 只关闭最内层面板")
	await _press_escape()
	await get_tree().create_timer(0.1).timeout
	_check(not is_instance_valid(pm) and not get_tree().paused, "回到暂停层后 Esc 才恢复战斗")


func _press_escape() -> void:
	var ev := InputEventKey.new()
	ev.physical_keycode = KEY_ESCAPE
	ev.keycode = KEY_ESCAPE
	ev.pressed = true
	get_viewport().push_input(ev)
	await get_tree().process_frame
	var up := InputEventKey.new()
	up.physical_keycode = KEY_ESCAPE
	up.keycode = KEY_ESCAPE
	up.pressed = false
	get_viewport().push_input(up)
	await get_tree().process_frame


func _physics_process(_delta: float) -> void:
	if _player and _player.hp != _last_p_hp:
		p("player hp -> " + str(_player.hp))
		_last_p_hp = _player.hp
	if _enemy and _enemy.hp != _last_e_hp:
		p("enemy hp -> " + str(_enemy.hp))
		_last_e_hp = _enemy.hp


func _wait_hp_drop(is_player: bool, target_hp: int, timeout: float) -> bool:
	var t := 0.0
	while t < timeout:
		var cur: int = _player.hp if is_player else _enemy.hp
		if cur <= target_hp:
			return true
		await get_tree().physics_frame
		t += get_physics_process_delta_time()
	return false


func _tap(action: String) -> void:
	Input.action_press(action)
	await get_tree().physics_frame
	Input.action_release(action)


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img = get_viewport().get_texture().get_image()
	var err = img.save_png(OUT_DIR + "fb_" + name + ".png")
	p("saved " + name + " err=" + str(err))
