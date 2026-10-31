extends Node2D

## C016 小怪 AI 冒烟测试：巡逻 -> 追击 -> 攻击玩家 -> 被玩家三连击打死。

const OUT_DIR := "res://tests/out/"
const PlayerClass := preload("res://scripts/player/player.gd")
const C016Class := preload("res://scripts/enemies/c016.gd")

var _log: FileAccess
var _player: PlayerClass
var _enemy: C016Class
var _last_p_state := -1
var _last_e_state := -1
var _last_e_hp := -1


func p(msg) -> void:
	print("[ET] ", msg)
	if _log:
		_log.store_line("[ET] " + str(msg))
		_log.flush()


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	_log = FileAccess.open("res://tests/enemy_test.log", FileAccess.WRITE)
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
	_player.position = Vector2(180, 560)
	add_child(_player)
	_enemy = load("res://scenes/enemies/c016.tscn").instantiate()
	_enemy.position = Vector2(980, 560)
	add_child(_enemy)
	p("created player=" + str(_player.sprite) + " enemy=" + str(_enemy.sprite))

	# 1. 敌人巡逻
	await get_tree().create_timer(1.2).timeout
	await _shot("01_patrol")

	# 2. 玩家向右走近，触发追击
	Input.action_press("move_right")
	var t := 0.0
	while t < 5.0:
		await get_tree().physics_frame
		t += get_physics_process_delta_time()
		if absf(_player.global_position.x - _enemy.global_position.x) < 220.0:
			break
	Input.action_release("move_right")
	p("approach done, dist=" + str(_enemy.global_position.x - _player.global_position.x))
	if await _wait_state(_enemy, 2, 2.0): # CHASE
		await _shot("02_chase")

	# 3. 等敌人攻击（玩家应被打到）
	if await _wait_state(_enemy, 3, 4.0): # ATTACK
		await get_tree().create_timer(0.35).timeout
		await _shot("03_enemy_attack")
	await get_tree().create_timer(1.5).timeout

	# 4. 玩家三连击打死敌人（hp=3）
	for i in 4:
		_tap("attack")
		await get_tree().create_timer(0.28).timeout
		if _enemy.state == 5: # DEAD
			break
	if _enemy.state != 5:
		await _wait_state(_enemy, 5, 3.0)
	await _shot("04_enemy_dead")
	await get_tree().create_timer(1.0).timeout
	await _shot("05_corpse")

	# 5. 精英青笠：两连击 / 跳斩霸体 / 半血狂暴
	var elite = load("res://scenes/enemies/c012_elite.tscn").instantiate()
	elite.position = Vector2(_player.global_position.x + 300.0, 560)
	add_child(elite)
	p("elite c012 spawned hp=%d scale=%.3f" % [elite.hp, elite._scale])
	# 先强制出两连击，验证多段命中队列
	elite._attack_anims = ["skill01"]
	if await _wait_state(elite, 3, 6.0): # ATTACK
		p("elite attack anim=" + str(elite._current_anim) + " hits_left=" + str(elite._attack_hits_left.size()) + "（两连击应为 2）")
		var hp_before := _player.hp
		await get_tree().create_timer(1.4).timeout # 两段 0.80/1.21 都已结算
		await _shot("06_c012_attack")
		p("elite 两连击后 player_hp=%d（前 %d；第二段落在 0.8s 受击无敌内应被吞，净掉 1）" % [_player.hp, hp_before])
	# 恢复招式池，等跳斩（skill02：伤害 2 + 出手霸体 + 跃起）
	elite._attack_anims = ["skill02"]
	if await _wait_state(elite, 3, 6.0):
		p("elite attack2 anim=" + str(elite._current_anim) + " hits_left=" + str(elite._attack_hits_left.size()) + "（跳斩应为 1）")
		await get_tree().create_timer(1.0).timeout # 0.89s 劈落已结算
		await _shot("07_c012_leap")
		p("elite 跳斩后 player_hp=%d" % _player.hp)
	# 打到半血以下验证狂暴（hp 10 -> 5 触发）
	while elite.hp > 5 and elite.state != 5:
		elite.take_damage(1, _player.global_position.x)
		await get_tree().create_timer(0.15).timeout
	await get_tree().create_timer(0.2).timeout
	p("elite enrage hp=%d/%d cooldown=%.2f（基础 1.70，狂暴后应约 1.11）" % [elite.hp, elite.max_hp, elite.attack_cooldown])
	# 打死收尾
	while elite.state != 5:
		elite.take_damage(2, _player.global_position.x)
		await get_tree().create_timer(0.15).timeout
	await _shot("08_c012_dead")

	# 新流派共用接口：流血收束、诱饵索敌、余滞移动与砸落落地单次回报。
	var probe = load("res://scenes/enemies/c016.tscn").instantiate()
	probe.position = Vector2(500, 560)
	add_child(probe)
	probe.apply_bleed(2)
	var consumed: int = probe.consume_bleed()
	p("consume_bleed 收走=%d 剩余=%d（期望 2/0）" % [consumed, probe._bleed_stacks])
	var decoy := Node2D.new()
	decoy.add_to_group("player_decoy")
	decoy.position = Vector2(550, 560)
	add_child(decoy)
	probe._find_target()
	p("影饵索敌 优先残影=%s（期望 true）" % (probe._target == decoy))
	decoy.queue_free()
	await get_tree().process_frame
	probe._find_target()
	p("残影消失 回到玩家=%s（期望 true）" % (probe._target == _player))
	_player.global_position = Vector2(750, 560)
	probe.global_position = Vector2(500, 560)
	probe._target = _player
	probe._attack_cd = 99.0
	probe.velocity.x = probe.chase_speed
	probe.slow(4.0, 0.45)
	probe._chase_tick(1.0)
	p("余滞追击速度=%.1f 期望=%.1f" % [probe.velocity.x, probe.chase_speed * 0.45])
	probe.detect_range = 0.0
	probe.global_position.y = 600.0
	probe.velocity = Vector2.ZERO
	probe._set_state(probe.State.IDLE)
	await get_tree().create_timer(0.1).timeout
	probe.slam()
	p("地面砸落 待回报=%s 状态=%d（期望 false/HURT=4）" % [probe._slam_pending, probe.state])
	probe.queue_free()

	# 第一只小怪尸体死后 ~1.7s 就 queue_free，精英段跑完它早没了，访问前必须判活
	var e_state := "freed"
	var e_hp := "-"
	if is_instance_valid(_enemy):
		e_state = str(_enemy.state)
		e_hp = str(_enemy.hp)
	p("ALL DONE, enemy state=" + e_state + " hp=" + e_hp
		+ " player state=" + str(_player.state))
	get_tree().quit()


func _physics_process(_delta: float) -> void:
	if _player and _player.state != _last_p_state:
		p("player state -> " + str(_player.state))
		_last_p_state = _player.state
	if _enemy:
		if _enemy.state != _last_e_state:
			p("enemy state -> " + str(_enemy.state) + " x=" + str(_enemy.global_position.x))
			_last_e_state = _enemy.state
		if _enemy.hp != _last_e_hp:
			p("enemy hp -> " + str(_enemy.hp))
			_last_e_hp = _enemy.hp


func _wait_state(obj, s: int, timeout: float) -> bool:
	var t := 0.0
	while t < timeout:
		if obj.state == s:
			return true
		await get_tree().physics_frame
		t += get_physics_process_delta_time()
	return false


func _tap(action: String) -> void:
	Input.action_press(action)
	await get_tree().physics_frame
	Input.action_release(action)


func _shot(name: String) -> void:
	await get_tree().process_frame
	RenderingServer.force_draw()
	var img = get_viewport().get_texture().get_image()
	var err = img.save_png(OUT_DIR + "ai_" + name + ".png")
	p("saved " + name + " err=" + str(err))
