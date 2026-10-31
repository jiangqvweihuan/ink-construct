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

	# 7. 蛮兵专项：三招判定、封跳、连段力竭、追击倍速与蛮力霸体。
	await _brute_probe()

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

	# 升龙刀：追击中 200px 起手，瞬至面前 72px，前摇不缩短，实伤 2 点并短暂击飞。
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
	var launch_ok: bool = is_equal_approx(_player.velocity.y, -420.0)
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
	_player.state = _player.State.DASH
	_player.velocity = Vector2.ZERO
	_player._hurt_invincible = 0.0
	hp_before = _player.hp
	e._deal_hit(0)
	var dodge_no_launch: bool = _player.hp == hp_before and is_zero_approx(_player.velocity.y)
	p("升龙刀 瞬移贴身=%s 前摇=%.2fs 实伤=%s 短击飞=%s 独立CD=%.1fs 冷却禁重入=%s 到点可放=%s 闪避不击飞=%s（期望全 true / 0.87 / >=10）" % [blink_ok, windup, rising_ok, launch_ok, rising_cd, cd_blocks, cd_ready, dodge_no_launch])
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


## 蛮兵专项：固定站位并手动推进攻击帧，逐项核对三招与霸体规则。
func _brute_probe() -> void:
	_reset_brute_player()
	var e := _spawn_brute(Vector2(580, 560))
	var brute_height := e._scale * 502.9
	var collider := e.get_node("CollisionShape2D") as CollisionShape2D
	var capsule := collider.shape as CapsuleShape2D
	var size_ok: bool = is_equal_approx(e._scale, 0.258) and brute_height > 111.0 and brute_height < 148.0 \
		and is_equal_approx(e.body_radius, 42.0) and is_equal_approx(e._bar_y, -140.0) \
		and is_equal_approx(e._number_y, -123.0) and capsule != null \
		and is_equal_approx(capsule.radius, 28.0) and is_equal_approx(capsule.height, 108.0) \
		and is_equal_approx(collider.position.y, -54.0)
	p("蛮兵体型 身高=%.1fpx 最大杂兵且小于精英=%s 碰撞/受击/UI同步=%s（期望约130 / true / true）" % [brute_height, brute_height > 111.0 and brute_height < 148.0, size_ok])
	e._set_state(e.State.PATROL)
	var walk_ok: bool = e._anim_map["patrol"] == "walk2" and e._anim_map["chase"] == "walk2" \
		and is_equal_approx(e.patrol_speed, 40.0) and is_equal_approx(e.chase_speed, 52.0) \
		and is_equal_approx(e._current_anim_speed, 1.0)
	var patrol_track = e._anim_state.call("get_current", 0)
	patrol_track.call("set_track_time", 0.5)
	e._set_state(e.State.CHASE)
	var chase_track = e._anim_state.call("get_current", 0)
	walk_ok = walk_ok and e._current_anim == "walk2" and is_equal_approx(e._current_anim_speed, 1.2) \
		and is_equal_approx(float(chase_track.call("get_track_time")), 0.5)
	p("蛮兵移动 共用walk2且不重启轨道=%s 巡逻/追击=%.0f/%.0f 动画倍率=%.1f（期望 true / 40/52 / 1.2）" % [walk_ok, e.patrol_speed, e.chase_speed, e._current_anim_speed])

	# 近身随机池只含开天与低权重辟地，追击连段不会被随机拆出来。
	var counts := {"skill01": 0, "skill02": 0, "skill03_2": 0, "skill03_3": 0}
	for i in 210:
		e._attack_rule_cds["skill02"] = 0.0
		e._start_attack()
		counts[e._current_anim] += 1
		e._release_token()
	var basic_ratio := float(counts["skill01"]) / 210.0
	var pool_ok: bool = counts["skill03_2"] == 0 and counts["skill03_3"] == 0 and basic_ratio >= 0.75
	p("蛮兵出手池 开天占比=%.2f 连段不入随机池=%s（期望 >=0.75 / true）" % [basic_ratio, pool_ok])

	# 开天：0.64 秒斧刃扫入身前才结算，2 伤、81px 身前范围与蛮力短击退。
	_reset_brute_player()
	e.global_position.x = 580.0
	e.facing = -1
	e._apply_facing()
	e._start_attack("skill01")
	var hit_at: float = e._attack_dur - float(e._attack_hits_left[0]["t"])
	var hp_before: int = _player.hp
	e._attack_tick(0.63)
	var no_early_hit: bool = _player.hp == hp_before
	e._attack_tick(0.02) # 跨过 0.64 秒边界，避免 0.63 + 0.01 的浮点误差停在命中前
	var basic_ok: bool = is_equal_approx(hit_at, 0.64) and is_equal_approx(e._range_of("skill01", 0), 81.0) \
		and _player.hp == hp_before - Run.enemy_damage(2)
	var knock_ok: bool = is_equal_approx(_player.velocity.x, -140.0) and is_equal_approx(_player.velocity.y, 0.0)
	_reset_brute_player(Vector2(700, 560))
	hp_before = _player.hp
	e._deal_hit(0)
	var behind_ok: bool = _player.hp == hp_before
	_reset_brute_player(Vector2(440, 560))
	hp_before = _player.hp
	e._deal_hit(0)
	var out_of_range_ok: bool = _player.hp == hp_before
	p("开天 蓄力无判=%s 0.64秒时刻/2伤/81px=%s 短击退=%s 背向无伤=%s 超程无伤=%s（期望全 true）" % [no_early_hit, basic_ok, knock_ok, behind_ok, out_of_range_ok])

	# 辟地：独立 9 秒冷却，实伤才附加 8 秒封跳；防御路径不误挂。
	_reset_brute_player()
	e._start_attack("skill02")
	hit_at = e._attack_dur - float(e._attack_hits_left[0]["t"])
	hp_before = _player.hp
	e._deal_hit(0)
	var ground_ok: bool = is_equal_approx(hit_at, 1.58) and is_equal_approx(e._range_of("skill02", 0), 152.0) \
		and _player.hp == hp_before - Run.enemy_damage(2) and is_equal_approx(_player._jump_seal, 8.0) \
		and is_equal_approx(float(e._attack_rule_cds["skill02"]), 9.0)
	_player.state = _player.State.IDLE
	_player.velocity = Vector2.ZERO
	_player._jump_buf = 0.1
	_player._coyote = 0.1
	_player._try_jump()
	var sealed_jump: bool = _player.state != _player.State.JUMP and is_equal_approx(_player.velocity.y, 0.0)
	_player._jump_seal = 0.0
	_player._jump_buf = 0.1
	_player._coyote = 0.1
	_player._try_jump()
	var free_jump: bool = _player.state == _player.State.JUMP and _player.velocity.y < 0.0

	_reset_brute_player()
	_player.state = _player.State.DASH
	hp_before = _player.hp
	e._deal_hit(0)
	var dodge_ok: bool = _player.hp == hp_before and _player._jump_seal <= 0.0
	_reset_brute_player()
	_player._shield_hits = 1
	hp_before = _player.hp
	e._deal_hit(0)
	var shield_ok: bool = _player.hp == hp_before and _player._jump_seal <= 0.0
	_reset_brute_player()
	_player._hurt_invincible = 0.8
	hp_before = _player.hp
	e._deal_hit(0)
	var invincible_ok: bool = _player.hp == hp_before and _player._jump_seal <= 0.0
	p("辟地 2伤/9秒CD/8秒封跳=%s 封跳禁跳=%s 解禁可跳=%s 闪避/护盾/无敌不附加=%s/%s/%s（期望全 true）" % [ground_ok, sealed_jump, free_jump, dodge_ok, shield_ok, invincible_ok])
	e._release_token()
	e.queue_free()
	await get_tree().process_frame

	# 赶山三斧：追击窗口触发但不瞬移，两段连劈接原地大劈，再静默力竭 3 秒。
	_reset_brute_player(Vector2(700, 560))
	e = _spawn_brute(Vector2(900, 560))
	e._set_state(e.State.CHASE)
	var start_x := e.global_position.x
	e._chase_tick(0.0)
	var chain_ok: bool = e.state == e.State.ATTACK and e._current_anim == "skill03_2" \
		and is_equal_approx(e.global_position.x, start_x) and e._chain_next == "skill03_3" \
		and is_equal_approx(float(e._attack_rule_cds["skill03_2"]), 16.0) \
		and is_equal_approx(float(e._advance_map["skill03_2"]), 85.0)
	hp_before = _player.hp
	e._attack_tick(0.35)
	e.global_position.x += e.velocity.x * 0.35 # 手动帧推进也要同步攻击步进，否则首劈仍停在 200px 外
	var no_early_chain_hit: bool = _player.hp == hp_before
	e._attack_tick(0.01)
	e.global_position.x += e.velocity.x * 0.01
	var first_hit: bool = _player.hp == hp_before - Run.enemy_damage(1)
	_player._hurt_invincible = 0.0
	hp_before = _player.hp
	# 小步同步推进：大步长若先判定再补位移，会在第二劈瞬间制造实战不存在的假超程。
	for i in 45:
		e._attack_tick(0.01)
		e.global_position.x += e.velocity.x * 0.01
	var second_hit: bool = _player.hp == hp_before - Run.enemy_damage(1)
	var advance_ok: bool = is_equal_approx(e.velocity.x, -85.0)
	e._attack_tick(e._attack_timer + 0.001)
	var second_stage: bool = e.state == e.State.ATTACK and e._current_anim == "skill03_3" \
		and e._chain_next.is_empty() and is_equal_approx(e._recovery_after_attack, 3.0) \
		and is_equal_approx(e.velocity.x, 0.0)
	_player._hurt_invincible = 0.0
	hp_before = _player.hp
	e._attack_tick(0.19)
	var no_early_final: bool = _player.hp == hp_before
	e._attack_tick(0.01)
	var final_hit: bool = _player.hp == hp_before - Run.enemy_damage(2)
	e._attack_tick(e._attack_timer + 0.001)
	var recovery_ok: bool = e.state == e.State.IDLE and is_equal_approx(e._recovery_timer, 3.0) \
		and e._attacker != e and e._root_timer <= 0.0 and e._stun_timer <= 0.0
	_player.global_position.x = 820.0
	e.velocity.x = 50.0
	e._attack_cd = 0.0
	for i in 3:
		e._physics_process(1.0)
		recovery_ok = recovery_ok and e.state == e.State.IDLE and is_equal_approx(e.velocity.x, 0.0) \
			and e._current_anim == "stand" and e._root_timer <= 0.0 and e._stun_timer <= 0.0
	recovery_ok = recovery_ok and e._recovery_timer <= 0.0
	p("赶山三斧 追击触发不瞬移=%s 蓄力无判=%s 三劈实伤=%s/%s/%s 前半推进=%s 后半原地=%s 力竭3秒=%s（期望全 true）" % [chain_ok, no_early_chain_hit and no_early_final, first_hit, second_hit, final_hit, advance_ok, second_stage, recovery_ok])

	# 长冷却期间不能再次触发，到点后仍可从同一追击窗口起手。
	_player.global_position.x = 700.0
	e.global_position.x = 900.0
	e._attack_cd = 0.0
	e._set_state(e.State.CHASE)
	e._chase_tick(0.0)
	var cd_blocks: bool = e.state == e.State.CHASE and e._current_anim != "skill03_2"
	e._attack_rule_cds["skill03_2"] = 0.0
	e._chase_tick(0.0)
	var cd_ready: bool = e.state == e.State.ATTACK and e._current_anim == "skill03_2"
	p("赶山三斧 16秒冷却禁重入=%s 到点可放=%s（期望 true / true）" % [cd_blocks, cd_ready])
	e._release_token()
	e.queue_free()
	await get_tree().process_frame

	# 蛮力霸体：保留伤害与白闪，但普通受击、控制、位移不断招；规则级控制与时停穿透。
	_reset_brute_player()
	e = _spawn_brute(Vector2(580, 560))
	e._start_attack("skill03_2")
	hp_before = e.hp
	e.take_damage(1, _player.global_position.x)
	var armor_hit: bool = e.hp == hp_before - 1 and e.state == e.State.ATTACK \
		and e._current_anim == "skill03_2" and e._chain_next == "skill03_3"
	e.root(2.0)
	e.contain(2.0)
	e.slow(4.0, 0.45)
	e.stun(1.0)
	e.slam()
	e.launch(1, 150.0, 500.0)
	e.knock_back(1, 400.0, 0)
	var control_immune: bool = e.state == e.State.ATTACK and e._root_timer <= 0.0 and e._stun_timer <= 0.0 \
		and e._slow_timer <= 0.0 and is_equal_approx(e._slow_scale, 1.0) and e._chain_next == "skill03_3"
	start_x = e.global_position.x
	_player._pull_enemy(e, 100.0)
	var pull_immune: bool = is_equal_approx(e.global_position.x, start_x)
	e.launch(1, 150.0, 500.0, true)
	var launch_through: bool = e.state == e.State.FLY and e._chain_next.is_empty() and e._attack_hits_left.is_empty()
	e._start_attack("skill03_2")
	e.time_stop(1.0)
	var stop_through: bool = e.state == e.State.IDLE and e._stop_timer > 0.0 and e._chain_next.is_empty()
	e._end_stop()
	e._start_attack("skill03_2")
	e.knock_back(1, 400.0, 0, true)
	var knock_through: bool = e.state == e.State.FLY and e._chain_next.is_empty() and e._recovery_timer <= 0.0
	p("蛮力霸体 受击不断招=%s 普通控制免疫=%s 牵引免疫=%s 无视霸体击飞/时停/击退=%s/%s/%s（期望全 true）" % [armor_hit, control_immune, pull_immune, launch_through, stop_through, knock_through])
	e._release_token()
	e.queue_free()
	await get_tree().process_frame


func _spawn_brute(pos: Vector2) -> C016Class:
	var e = load("res://scenes/enemies/c017.tscn").instantiate()
	e.position = pos
	add_child(e)
	e.set_physics_process(false)
	e._target = _player
	e._attack_cd = 0.0
	e.facing = 1 if _player.global_position.x > e.global_position.x else -1
	e._apply_facing()
	return e


func _reset_brute_player(pos := Vector2(500, 560)) -> void:
	_player.set_physics_process(false)
	_player.global_position = pos
	_player.hp = _player.max_hp
	_player.state = _player.State.IDLE
	_player.velocity = Vector2.ZERO
	_player._invincible = false
	_player._hurt_invincible = 0.0
	_player._jump_seal = 0.0
	_player._shield_hits = 0
	_player._shield_time = 0.0
	_player._parry_ready = false
	_player._bell_shell = false
	_player._skill_reflect = false
	_player._skill_poise = false
	_player._damage_reduce = 0
	_player.poise = false
	Run.guard_available = false


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
