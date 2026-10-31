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

	# 4. 玩家连续攻击打死敌人（hp=6）
	for i in 8:
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
	# 打到半血以下验证狂暴（hp 20 -> 10 触发）
	while elite.hp > 10 and elite.state != 5:
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

	# 6. 刀客专项：四招配置、三刀反馈、升龙刀、倒地链与山民回血。
	await _swordsman_probe()

	# 第一只小怪尸体死后 ~1.7s 就 queue_free，精英段跑完它早没了，访问前必须判活
	var e_state := "freed"
	var e_hp := "-"
	if is_instance_valid(_enemy):
		e_state = str(_enemy.state)
		e_hp = str(_enemy.hp)
	p("ALL DONE, enemy state=" + e_state + " hp=" + e_hp
		+ " player state=" + str(_player.state))
	get_tree().quit()


## 刀客专项用固定站位与手动帧推进，避免随机选招和实时位移干扰数值断言。
func _swordsman_probe() -> void:
	_player.set_physics_process(false)
	_player.global_position = Vector2(500, 560)
	_player.hp = _player.max_hp
	_player.state = _player.State.IDLE
	_player._invincible = false
	_player._hurt_invincible = 0.0

	var e = load("res://scenes/enemies/c016.tscn").instantiate()
	e.position = Vector2(620, 560)
	add_child(e)
	e.set_physics_process(false)
	e._target = _player
	e.facing = -1
	e._apply_facing()
	p("刀客四招=%s 无招式5=%s（期望 4 / true）" % [e._attack_anims.size(), not e._attack_anims.has("skill05")])
	p("刀客移动动画 巡逻=%s 追击=%s（期望 run / speed_run）" % [e._anim_map["patrol"], e._anim_map["chase"]])

	# 亡命三刀：前两段只播受击，末段才扣一次基础 1 伤。
	e._start_attack("skill01")
	p("三刀命中段=%d 时刻=%s（期望 3 / [0.36, 0.88, 1.33]）" % [e._attack_hits_left.size(), str(e._hit_at_map["skill01"])])
	var hp_before: int = _player.hp
	e._deal_hit(0)
	var first_ok: bool = _player.hp == hp_before and _player.state == _player.State.HURT and _player._hurt_invincible <= 0.0
	e._deal_hit(1)
	var second_ok: bool = _player.hp == hp_before and _player.state == _player.State.HURT and _player._hurt_invincible <= 0.0
	e._deal_hit(2)
	var final_ok: bool = _player.hp == hp_before - Run.enemy_damage(1)
	p("三刀结算 首段=%s 次段=%s 末段=%s 净伤害=%d（期望 true/true/true/%d）" % [first_ok, second_ok, final_ok, hp_before - _player.hp, Run.enemy_damage(1)])
	e._release_token()
	e.queue_free()
	await get_tree().process_frame

	# 升龙刀：追击中 200px 起手，瞬至面前 72px，前摇不缩短，命中按基础 2 伤。
	_player.global_position = Vector2(700, 560)
	_player.hp = _player.max_hp
	_player.state = _player.State.IDLE
	_player._hurt_invincible = 0.0
	e = load("res://scenes/enemies/c016.tscn").instantiate()
	e.position = Vector2(900, 560)
	add_child(e)
	e.set_physics_process(false)
	e._target = _player
	e._attack_cd = 0.0
	e._set_state(e.State.CHASE)
	e._chase_tick(0.0)
	var blink_ok: bool = e.state == e.State.ATTACK and e._current_anim == "skill03" and absf(absf(e.global_position.x - _player.global_position.x) - 72.0) < 0.01
	var windup: float = e._attack_dur - float(e._attack_hits_left[0]["t"]) if not e._attack_hits_left.is_empty() else -1.0
	hp_before = _player.hp
	e._attack_tick(e._attack_dur)
	var rising_ok: bool = _player.hp == hp_before - Run.enemy_damage(2)
	var rising_cd: float = e._attack_rule_cds.get("skill03", 0.0)
	e.global_position.x = 900.0
	e._attack_cd = 0.0
	e._attack_rule_cds["skill02"] = 99.0
	e._set_state(e.State.CHASE)
	e._chase_tick(0.0)
	var cd_blocks: bool = e.state == e.State.CHASE and e._current_anim != "skill03"
	e._attack_rule_cds["skill03"] = 0.0
	e._chase_tick(0.0)
	var cd_ready: bool = e.state == e.State.ATTACK and e._current_anim == "skill03"
	p("升龙刀 瞬移贴身=%s 前摇=%.2fs 实伤=%s 独立CD=%.1fs 冷却禁重入=%s 到点可放=%s（期望 true / 0.87 / true / >=10 / true / true）" % [blink_ok, windup, rising_ok, rising_cd, cd_blocks, cd_ready])
	e._release_token()
	e.queue_free()
	await get_tree().process_frame

	# 近身池只含三刀与低权重双镰；远鞭限定中远距，特殊招冷却时普攻兜底。
	e = load("res://scenes/enemies/c016.tscn").instantiate()
	e.position = Vector2(820, 560)
	add_child(e)
	e.set_physics_process(false)
	e._target = _player
	var counts := {"skill01": 0, "skill02": 0, "skill03": 0, "skill04": 0}
	for i in 210:
		e._attack_rule_cds["skill01"] = 0.0
		e._attack_rule_cds["skill04"] = 0.0
		e._start_attack()
		counts[e._current_anim] += 1
		e._release_token()
	var basic_ratio := float(counts["skill01"]) / 210.0
	var pool_ok: bool = counts["skill02"] == 0 and counts["skill03"] == 0 and basic_ratio >= 0.75
	e.global_position.x = 900.0
	e._attack_cd = 0.0
	e._attack_rule_cds["skill03"] = 99.0
	e._attack_rule_cds["skill02"] = 0.0
	e._set_state(e.State.CHASE)
	e._chase_tick(0.0)
	var whip_window: bool = e._current_anim == "skill02"
	e._release_token()
	e.global_position.x = 820.0
	e._attack_cd = 0.0
	e._set_state(e.State.CHASE)
	e._chase_tick(0.0)
	whip_window = whip_window and e._current_anim != "skill02"
	e._release_token()
	e._attack_rule_cds["skill02"] = 99.0
	e._attack_rule_cds["skill04"] = 99.0
	e._attack_cd = 0.0
	e._set_state(e.State.CHASE)
	e._chase_tick(0.0)
	var basic_fallback: bool = e._current_anim == "skill01"
	p("出手规则 普攻占比=%.2f 近身池合规=%s 螺旋鞭距离窗=%s 特殊招冷却普攻兜底=%s（期望 >=0.75 / true / true / true）" % [basic_ratio, pool_ok, whip_window, basic_fallback])
	e._release_token()
	e.queue_free()
	await get_tree().process_frame

	# 高伤链：1 → 2 → 5 → 10；链中追加伤害照扣，但当前动画不重开。
	e = load("res://scenes/enemies/c016.tscn").instantiate()
	e.position = Vector2(620, 560)
	add_child(e)
	e.set_physics_process(false)
	e.configure({"hp": 20})
	e.take_damage(2, _player.global_position.x)
	var chain_ok: bool = e._hurt_chain_active and e._current_anim == "atked"
	var chain_hp: int = e.hp
	e.take_damage(1, _player.global_position.x)
	chain_ok = chain_ok and e.hp == chain_hp - 1 and e._current_anim == "atked"
	for expected in ["atked_air", "atked_fall_end", "getup"]:
		e._hurt_tick(e._hurt_timer + 0.001)
		chain_ok = chain_ok and e._current_anim == expected
	e._hurt_tick(e._hurt_timer + 0.001)
	chain_ok = chain_ok and not e._hurt_chain_active and e.state == e.State.IDLE
	p("高伤倒地链 顺序与防重入=%s 链中受伤后HP=%d（期望 true / 17）" % [chain_ok, chain_hp - 1])

	# 山民：到点恢复 1 点；满血只重置计时，不超过上限。
	e._regen_timer = 5.0
	hp_before = e.hp
	e._regen_tick(4.99)
	var regen_early: bool = e.hp == hp_before
	e._regen_tick(0.02)
	var regen_ok: bool = regen_early and e.hp == hp_before + 1
	e.hp = e.max_hp
	e._regen_timer = 0.01
	e._regen_tick(0.02)
	regen_ok = regen_ok and e.hp == e.max_hp
	p("山民回血 间隔与上限=%s 当前HP=%d/%d（期望 true / 满血）" % [regen_ok, e.hp, e.max_hp])
	e._release_token()
	e.queue_free()
	await get_tree().process_frame


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
