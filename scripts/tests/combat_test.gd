extends Node2D

## 战斗反馈测试：伤害飘字 + 玩家 HUD 血条 + 小怪头顶血条。

const OUT_DIR := "res://tests/out/"
const PlayerClass := preload("res://scripts/player/player.gd")
const C016Class := preload("res://scripts/enemies/c016.gd")

var _log: FileAccess
var _player: PlayerClass
var _enemy: C016Class
var _last_p_hp := -1
var _last_e_hp := -1


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

	add_child(load("res://scenes/ui/hud.tscn").instantiate())

	_player = load("res://scenes/player/player.tscn").instantiate()
	_player.position = Vector2(400, 560)
	add_child(_player)
	_enemy = load("res://scenes/enemies/c016.tscn").instantiate()
	_enemy.position = Vector2(700, 560)
	add_child(_enemy)

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

	p("ALL DONE, player hp=" + str(_player.hp) + " enemy hp=" + str(_enemy.hp)
		+ " enemy state=" + str(_enemy.state))
	get_tree().quit()


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
