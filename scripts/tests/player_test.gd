extends Node2D

## 玩家控制器冒烟测试：模拟输入走一遍 idle/run/jump/dash/三连击，截图+日志。

const OUT_DIR := "res://tests/out/"
const PlayerClass := preload("res://scripts/player/player.gd")

var _log: FileAccess
var _player: PlayerClass
var _last_state := -1


func p(msg) -> void:
	print("[PT] ", msg)
	if _log:
		_log.store_line("[PT] " + str(msg))
		_log.flush()


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	_log = FileAccess.open("res://tests/player_test.log", FileAccess.WRITE)
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
	_player.position = Vector2(300, 560)
	add_child(_player)
	p("player created, sprite=" + str(_player.sprite))

	await get_tree().create_timer(0.6).timeout
	await _shot("01_idle")

	# 跑动
	Input.action_press("move_right")
	await get_tree().create_timer(0.8).timeout
	await _shot("02_run")

	# 跳（按住方向，点一下跳）
	_tap("jump")
	await get_tree().create_timer(0.3).timeout
	await _shot("03_jump")
	await get_tree().create_timer(0.8).timeout
	Input.action_release("move_right")
	await get_tree().create_timer(0.3).timeout

	# 冲刺
	_tap("dash")
	await get_tree().create_timer(0.1).timeout
	await _shot("04_dash")
	await get_tree().create_timer(0.6).timeout

	# 三连击：J -> 0.25s -> J -> 0.35s -> J
	_tap("attack")
	await get_tree().create_timer(0.12).timeout
	await _shot("05_atk1")
	await get_tree().create_timer(0.15).timeout
	_tap("attack")
	await get_tree().create_timer(0.2).timeout
	await _shot("06_atk2")
	await get_tree().create_timer(0.15).timeout
	_tap("attack")
	await get_tree().create_timer(0.2).timeout
	await _shot("07_atk3")
	await get_tree().create_timer(0.8).timeout
	await _shot("08_back_idle")

	p("ALL DONE, final state=" + str(_player.state) + " pos=" + str(_player.position))

	# ---- 换头验证：给够墨骨，走化身面板逐个选形态，确认骨架/技能表/HUD 数据全部换掉 ----
	Score.add_bones(60)
	Meta.debug_unlock_all() # 测试环境直接拉满解锁条件，别让存档挡住换头验证
	await _shot("09_before_swap")
	for id in ["c023", "z000", "c013", "c012"]:
		var panel = load("res://scenes/ui/swap_panel.tscn").instantiate()
		panel.setup(_player) # 必须在 add_child 前：面板 _ready 要读当前形态
		add_child(panel)
		await get_tree().process_frame
		await get_tree().process_frame
		panel.select(id) # 选中即扣墨骨换头并解除时停
		await get_tree().create_timer(0.6).timeout
		p("swap -> skull=%s hud=%s attacks=%d skills=%s bones=%d" % [
			_player.skull_id, str(_player.hud_skills), _player.attacks.size(),
			str(_player.skill_config.keys()), Score.bones])
		# 力僧 U（定山）是回血技：先压血到 5，砸下后应回到 7，否则满血时回血分支不进等于没测
		if _player.skull_id == "c013":
			_player.hp = 5
			_player.hp_changed.emit(5, _player.max_hp)
			p("c013 压血 -> hp=5，准备验证定山回血")
		await _shot("10_swap_" + str(_player.skull_id))
		_tap("attack")
		await get_tree().create_timer(0.3).timeout
		await _shot("11_atk_" + str(_player.skull_id))
		_tap("skill")
		await get_tree().create_timer(1.3).timeout
		await _shot("12_skill_" + str(_player.skull_id))
		_tap("skill_ult")
		await get_tree().create_timer(1.6).timeout
		await _shot("13_ult_" + str(_player.skull_id))
		# 定山蓄力 3.05s 才砸下，等它结算完再看血量：5 -> 7 才说明回血真的生效
		await get_tree().create_timer(1.9).timeout
		p("ult_after skull=%s hp=%d/%d" % [_player.skull_id, _player.hp, _player.max_hp])
		await _shot("14_ult_after_" + str(_player.skull_id))

	p("SWAP DONE skull=" + str(_player.skull_id))
	get_tree().quit()


func _physics_process(_delta: float) -> void:
	if _player and _player.state != _last_state:
		p("state -> " + str(_player.state) + " pos=" + str(_player.position))
		_last_state = _player.state


func _tap(action: String) -> void:
	Input.action_press(action)
	await get_tree().physics_frame
	Input.action_release(action)


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img = get_viewport().get_texture().get_image()
	var err = img.save_png(OUT_DIR + "ctrl_" + name + ".png")
	p("saved " + name + " err=" + str(err) + " state=" + str(_player.state) + " pos=" + str(_player.position))
