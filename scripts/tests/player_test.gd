extends Node2D

## 玩家控制器冒烟测试：模拟输入走一遍 idle/run/jump/dash/三连击，截图+日志。

## 反伤测试替身：只记账不参与战斗，验证定山把伤害弹回攻击者；
## hp 是给"敌人组结算"读的属性（当普攻拉回 / 两段伤害的靶子用）
class Trainer extends Node2D:
	var damage_taken := 0
	var hp := 99

	func take_damage(amount: int, _source_x: float) -> void:
		damage_taken += amount

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
		# 梅剑专项：普攻两段（2 点鞭击 + 3 点突刺）与鞭击拉回，靶子放在 300px 外
		var dummy: Trainer = null
		if _player.skull_id == "c023":
			dummy = Trainer.new()
			dummy.add_to_group("enemies")
			add_child(dummy)
			dummy.global_position = _player.global_position + Vector2(300.0 * _player.facing, 0.0)
			p("c023 靶子起点距玩家 %.0fpx（期望被拉到约 80）" % absf(dummy.global_position.x - _player.global_position.x))
		_tap("attack")
		await get_tree().create_timer(0.3).timeout
		await _shot("11_atk_" + str(_player.skull_id))
		if dummy != null:
			await get_tree().create_timer(0.6).timeout # 0.9s：鞭击已结算
			p("c023 鞭击后靶子距玩家 %.0fpx（期望约 80）" % absf(dummy.global_position.x - _player.global_position.x))
			await get_tree().create_timer(1.0).timeout # 1.9s：突刺已结算
			p("c023 普攻总伤害=%d（期望 2+3=5）" % dummy.damage_taken)
			dummy.queue_free()
			dummy = null
		await _wait_free() # 各形态招式时长不同，等回到可出招状态再按下一个键
		_tap("skill")
		await get_tree().create_timer(1.3).timeout
		await _shot("12_skill_" + str(_player.skull_id))
		if _player.skull_id == "c023":
			p("c023 技能中转鞭 ranged_guard=%s（期望 true，无敌人时只免疫）" % str(_player.try_reflect_ranged(1, _player.global_position.x + 400.0)))
		await _wait_free()
		_tap("skill_sweep")
		await get_tree().create_timer(0.8).timeout
		await _shot("12b_sweep_" + str(_player.skull_id))
		await _wait_free()
		_tap("skill_ult")
		await get_tree().create_timer(1.0).timeout
		# 定山反伤验证：蓄力中（reflect=1）挨打一下，应把伤害弹回攻击者且不断招
		if _player.skull_id == "c013":
			var trainer := Trainer.new()
			add_child(trainer)
			trainer.global_position = _player.global_position + Vector2(150, 0)
			var hp_before := _player.hp
			# 用 3 点伤害验证"按实际伤害反弹"，不是固定值
			_player.hurt(3, Vector2(80.0, -60.0), trainer)
			await get_tree().create_timer(0.2).timeout
			p("reflect_test c013: 挨打前 hp=%d 挨打后 hp=%d trainer_taken=%d state=%d（期望 hp 不掉、trainer 吃到 3、仍为 SKILL=6）" % [
				hp_before, _player.hp, trainer.damage_taken, _player.state])
		await get_tree().create_timer(0.4).timeout
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


## 等玩家回到可出招状态（IDLE/RUN），最多等 max_wait 秒。
## 各形态普攻/技能时长差得远（梅剑普攻 1.883s、定山 U 3.05s），硬编码等待会让
## 下一次按键落在上一招的锁定里被吞掉，测试就测不到该测的东西。
func _wait_free(max_wait := 6.0) -> void:
	var t := 0.0
	while _player.state > 1 and t < max_wait:
		await get_tree().physics_frame
		t += get_physics_process_delta_time()


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img = get_viewport().get_texture().get_image()
	var err = img.save_png(OUT_DIR + "ctrl_" + name + ".png")
	p("saved " + name + " err=" + str(err) + " state=" + str(_player.state) + " pos=" + str(_player.position))
