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

	# 5. 精英青笠冒烟：双剑斩两段、旋斩与三层剑意凝华；精确数值由后面的专项验证。
	_reset_brute_player(Vector2(180, 560))
	_player.hp = 50 # 冒烟会吃本体与镜像的完整连段，避免中途死亡干扰后续场景
	var elite = load("res://scenes/enemies/c012_elite.tscn").instantiate()
	elite.position = Vector2(_player.global_position.x + 300.0, 560)
	add_child(elite)
	p("elite c012 spawned hp=%d scale=%.3f" % [elite.hp, elite._scale])
	elite._attack_anims = ["skill01"]
	if await _wait_state(elite, 3, 6.0): # ATTACK
		p("elite attack anim=" + str(elite._current_anim) + " hits_left=" + str(elite._attack_hits_left.size()) + "（双剑斩应为 2）")
		await get_tree().create_timer(1.4).timeout
		await _shot("06_c012_attack")
		p("elite 双剑斩后 player_hp=%d sword_intent=%d bleed=%d" % [_player.hp, elite._sword_intent, _player._bleed_stacks])
	elite._attack_anims = ["skill02"]
	if await _wait_state(elite, 3, 6.0):
		p("elite attack2 anim=" + str(elite._current_anim) + " hits_left=" + str(elite._attack_hits_left.size()) + "（旋斩应为 1）")
		await get_tree().create_timer(1.0).timeout
		await _shot("07_c012_leap")
		p("elite 旋斩后 player_hp=%d sword_intent=%d dash_seal=%.1f" % [_player.hp, elite._sword_intent, _player._dash_seal])
	if elite.state != 5:
		elite.take_damage(elite.hp, _player.global_position.x)
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

	# 8. 刺客专项：同动画双招、两段镖去、绕背偷袭、阴影背刺与倒地链。
	await _assassin_probe()

	# 9. 双镰专项：两段普通流血、实伤回血、绽花、嗜血虚弱与倒地链。
	await _dualsickle_probe()

	# 10. 青笠专项：剑意结算、同步凝华分身、封闪避、普通流血与严格高伤链。
	await _qingli_probe()

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
	p("升龙刀 瞬移贴身=%s 前摇=%.2fs 实伤=%s 短击飞=%s 独立CD24秒=%s 冷却禁重入=%s 到点可放=%s 闪避不击飞=%s（期望全 true / 0.87）" % [blink_ok, windup, rising_ok, launch_ok, is_equal_approx(rising_cd, 24.0), cd_blocks, cd_ready, dodge_no_launch])
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
		and is_equal_approx(float(e._attack_rule_cds["skill02"]), 18.0)
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
		and is_equal_approx(float(e._attack_rule_cds["skill03_2"]), 32.0) \
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
	p("赶山三斧 32秒冷却禁重入=%s 到点可放=%s（期望 true / true）" % [cd_blocks, cd_ready])
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


## 刺客专项：镖去 / 偷袭分别映射 skill02 / skill01，手动结算以排除实时 AI 和位移干扰。
func _assassin_probe() -> void:
	_reset_brute_player(Vector2(500, 560))
	_player.facing = 1 # 目标朝右，刺客在其右侧时属于正面
	var e = load("res://scenes/enemies/c035.tscn").instantiate()
	e.position = Vector2(580, 560)
	add_child(e)
	e.set_physics_process(false)
	e._target = _player
	e.facing = -1
	e._apply_facing()

	# 镖去：12 号普攻与 11 号偷袭的逻辑键、命中段和冷却配置互不串用。
	e._start_attack("dart")
	var alias_ok: bool = e._attack_move == "dart" and e._current_anim == "skill02" \
		and e._attack_hits_left.size() == 2 and str(e._move_anims.get("sneak", "")) == "skill01"
	var hp_before: int = _player.hp
	e._deal_hit(0)
	var first_hit: bool = _player.hp == hp_before - Run.enemy_damage(1) and _player._cuts.size() == 1
	hp_before = _player.hp
	e._deal_hit(1) # 同一次起手的第二段穿过首段的 0.8 秒受击无敌
	var second_hit: bool = _player.hp == hp_before - Run.enemy_damage(1) and _player._cuts.size() == 1
	hp_before = _player.hp
	e._start_attack("dart") # 新起手编号不能再穿上一次实伤留下的无敌
	e._deal_hit(0)
	var new_cast_blocked: bool = _player.hp == hp_before and _player._cuts.size() == 1
	p("镖去 动画别名/两段=%s 首段实伤=%s 同招次段穿无敌=%s 整招一组割伤=%s 新起手不穿=%s（期望全 true）" % [alias_ok, first_hit, second_hit, _player._cuts.size() == 1, new_cast_blocked])
	e._release_token()
	e.queue_free()
	await get_tree().process_frame

	# 阴影：同一段镖去在正面只有基础 1 伤，绕到目标背后则双倍为 2 伤。
	_reset_brute_player(Vector2(500, 560))
	_player.facing = 1
	e = load("res://scenes/enemies/c035.tscn").instantiate()
	e.position = Vector2(420, 560)
	add_child(e)
	e.set_physics_process(false)
	e._target = _player
	e.facing = 1
	e._apply_facing()
	e._start_attack("dart")
	hp_before = _player.hp
	e._deal_hit(0)
	var backstab_ok: bool = _player.hp == hp_before - Run.enemy_damage(1) * 2
	p("阴影 背后直伤双倍=%s 净伤害=%d（期望 true / %d）" % [backstab_ok, hp_before - _player.hp, Run.enemy_damage(1) * 2])
	e._release_token()
	e.queue_free()
	await get_tree().process_frame

	# 偷袭：200px 追击窗内绕到目标背后 72px，12 秒独立冷却，砸击触发背刺。
	_reset_brute_player(Vector2(700, 560))
	_player.facing = 1
	e = load("res://scenes/enemies/c035.tscn").instantiate()
	e.position = Vector2(900, 560)
	add_child(e)
	e.set_physics_process(false)
	e._target = _player
	e._attack_cd = 0.0
	e._set_state(e.State.CHASE)
	e._chase_tick(0.0)
	var blink_ok: bool = e.state == e.State.ATTACK and e._attack_move == "sneak" \
		and e._current_anim == "skill01" and is_equal_approx(e.global_position.x, 628.0) \
		and e.facing == 1 and is_equal_approx(float(e._attack_rule_cds["sneak"]), 24.0) \
		and is_equal_approx(e.velocity.x, 0.0)
	hp_before = _player.hp
	e._attack_tick(0.93)
	var no_early_hit: bool = _player.hp == hp_before
	e._attack_tick(0.01)
	var sneak_hit: bool = _player.hp == hp_before - Run.enemy_damage(2) * 2 and _player._cuts.is_empty()
	e.global_position.x = 900.0
	e._attack_cd = 0.0
	e._set_state(e.State.CHASE)
	e._chase_tick(0.0)
	var cd_blocks: bool = e.state == e.State.CHASE
	e._attack_rule_cds["sneak"] = 0.0
	e._chase_tick(0.0)
	var cd_ready: bool = e.state == e.State.ATTACK and e._attack_move == "sneak"
	p("偷袭 11号动画/绕背72px/24秒CD=%s 前摇无判=%s 0.94秒背刺4伤=%s 无割伤=%s 冷却禁重入=%s 到点可放=%s（期望全 true）" % [blink_ok, no_early_hit, sneak_hit, _player._cuts.is_empty(), cd_blocks, cd_ready])
	e._release_token()
	e.queue_free()
	await get_tree().process_frame

	# 高伤链：原受击 → 空中受击 → 倒地 → 9 号 getup，链中掉血但不重播受击。
	e = load("res://scenes/enemies/c035.tscn").instantiate()
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
	p("刺客高伤倒地链 顺序与防重入=%s 链中受伤后HP=%d（期望 true / 17）" % [chain_ok, chain_hp - 1])
	e._release_token()
	e.queue_free()
	await get_tree().process_frame


## 双镰专项：手动结算每一段，验证普通流血、实际扣血回血、绽花与永久嗜血。
func _dualsickle_probe() -> void:
	Run.start()
	Run.apply_to(_player)
	_reset_brute_player(Vector2(500, 560))
	var e = load("res://scenes/enemies/c018_elite.tscn").instantiate()
	e.position = Vector2(580, 560)
	add_child(e)
	e.set_physics_process(false)
	e._target = _player
	e.facing = -1
	e._apply_facing()

	# 镰舞：同一出手两段各 2 伤、各叠一层普通流血，第二段穿过首段受击无敌。
	e._start_attack("skill01")
	var hp_before: int = _player.hp
	e._deal_hit(0)
	var first_ok: bool = _player.hp == hp_before - Run.enemy_damage(2) and _player._bleed_stacks == 1 and _player._cuts.is_empty()
	hp_before = _player.hp
	e._deal_hit(1)
	var second_ok: bool = _player.hp == hp_before - Run.enemy_damage(2) and _player._bleed_stacks == 2 and _player._cuts.is_empty()
	var timing_ok: bool = e._hit_at_map["skill01"] == [0.30, 0.60] and e._ranges["skill01"] == [107.0, 156.0] \
		and e._back_ranges["skill01"] == [174.0, 209.0]
	p("镰舞 两段实伤/各1层普通流血=%s/%s 非割伤=%s 双段标定=%s（期望全 true）" % [first_ok, second_ok, _player._cuts.is_empty(), timing_ok])

	# 身后 190px：第一段前侧射程够不到，第二段必须按独立后侧 209px 结算。
	_reset_brute_player(Vector2(390, 560))
	e.global_position.x = 580.0
	e.facing = 1 # 目标在身后
	e._apply_facing()
	e._start_attack("skill01")
	e._deal_hit(0)
	hp_before = _player.hp
	e._deal_hit(1)
	var back_ok: bool = hp_before - _player.hp == Run.enemy_damage(2)
	p("镰舞身后第二段 190px 命中=%s 后侧射程=%s（期望 true/209）" % [back_ok, str(e._back_range_of("skill01", 1))])

	# 镰碎：基础 5 伤按玩家实际扣血等量回血；完美闪避则双方状态不变。
	_reset_brute_player(Vector2(500, 560))
	e.global_position.x = 580.0
	e.facing = -1
	e._apply_facing()
	e.hp = 10
	e._start_attack("skill02")
	hp_before = _player.hp
	e._deal_hit(0)
	var shatter_ok: bool = _player.hp == hp_before - Run.enemy_damage(5) and e.hp == 10 + Run.enemy_damage(5)
	_reset_brute_player(Vector2(500, 560))
	_player.state = _player.State.DASH
	e.hp = 10
	hp_before = _player.hp
	e._start_attack("skill02")
	e._deal_hit(0)
	var shatter_dodge_ok: bool = _player.hp == hp_before and e.hp == 10
	p("镰碎 实伤等额回血=%s 闪避不回血=%s（期望全 true）" % [shatter_ok, shatter_dodge_ok])

	# 绽花：未命中无效果；命中无直伤，减本局上限、移到正上方并将当前与后续冷却减半。
	Run.start()
	Run.apply_to(_player)
	_reset_brute_player(Vector2(1000, 560))
	e._skill_cooldown_scale = 1.0
	e._start_attack("skill03")
	e._deal_hit(0)
	var bloom_miss_ok: bool = Run.max_hp_loss == 0 and is_equal_approx(e._skill_cooldown_scale, 1.0)
	_reset_brute_player(Vector2(500, 560))
	_player.hp = 5
	Run.hp = 5
	e.global_position.x = 580.0
	e._attack_cd = 1.9
	e._attack_rule_cds["skill02"] = 16.0
	e._start_attack("skill03")
	e._deal_hit(0)
	var bloom_ok: bool = _player.hp == 5 and _player.max_hp == Run.max_hp and Run.max_hp_loss == 2 \
		and _player.global_position.is_equal_approx(e.global_position + Vector2(0, -120)) \
		and is_equal_approx(e._skill_cooldown_scale, 0.5) and is_equal_approx(float(e._attack_rule_cds["skill03"]), 12.0) \
		and is_equal_approx(float(e._attack_rule_cds["skill02"]), 8.0) and is_equal_approx(e._attack_cd, 0.95)
	Run.snapshot(_player)
	Run.apply_to(_player)
	var bloom_persist_ok: bool = _player.max_hp == Run.max_hp and Run.max_hp_loss == 2 and _player.hp == 5
	p("绽花 未命中无效=%s 无直伤/正上方/上限-2/冷却减半=%s 跨房保留=%s（期望全 true）" % [bloom_miss_ok, bloom_ok, bloom_persist_ok])
	e._release_token()
	e.queue_free()
	await get_tree().process_frame

	# 嗜血：低于 30% 永久激活；虚弱只控制当前动画与速度，回血后外观恢复但伤害-1与吸血保留。
	Run.start()
	Run.apply_to(_player)
	_reset_brute_player(Vector2(500, 560))
	e = load("res://scenes/enemies/c018_elite.tscn").instantiate()
	e.position = Vector2(580, 560)
	add_child(e)
	e.set_physics_process(false)
	e._target = _player
	e.take_damage(13, _player.global_position.x)
	e._set_state(e.State.IDLE)
	e._sync_bloodthirst()
	var weak_idle_ok: bool = e._bloodthirst_active and e._bloodthirst_weak() and e._current_anim == "swim"
	e._set_state(e.State.PATROL)
	e._sync_bloodthirst()
	var weak_patrol_ok: bool = e._current_anim == "walk" and is_equal_approx(e._patrol_speed_now(), 30.0)
	e._set_state(e.State.CHASE)
	e._sync_bloodthirst()
	var weak_chase_ok: bool = e._current_anim == "walk" and is_equal_approx(e._chase_speed_now(), 52.0)
	e._heal(99)
	e._set_state(e.State.IDLE)
	e._sync_bloodthirst()
	var recovered_ok: bool = e._bloodthirst_active and not e._bloodthirst_weak() and e._current_anim == "stand" \
		and is_equal_approx(e._chase_speed_now(), 135.0)
	e.hp = 10
	e.facing = -1
	e._apply_facing()
	e._start_attack("skill01")
	hp_before = _player.hp
	e._deal_hit(0)
	var blood_hit_ok: bool = _player.hp == hp_before - maxi(1, Run.enemy_damage(2) - 1) and e.hp == 11
	p("嗜血 虚弱待机/巡逻/追击=%s/%s/%s 回血恢复外观且被动常驻=%s 非虚弱技能-1并吸血=%s（期望全 true）" % [weak_idle_ok, weak_patrol_ok, weak_chase_ok, recovered_ok, blood_hit_ok])
	e._release_token()
	e.queue_free()
	await get_tree().process_frame

	# 严格大于 5：5 伤只普通受击，6 伤才走受伤 → 倒地 → 9 号起身，链中不重入。
	e = load("res://scenes/enemies/c018_elite.tscn").instantiate()
	e.position = Vector2(580, 560)
	add_child(e)
	e.set_physics_process(false)
	e.take_damage(5, _player.global_position.x)
	var chain_ok: bool = not e._hurt_chain_active and e._current_anim == "atked_heavy"
	e.take_damage(6, _player.global_position.x)
	chain_ok = chain_ok and e._hurt_chain_active and e._current_anim == "atked_heavy"
	e.take_damage(1, _player.global_position.x)
	chain_ok = chain_ok and e.hp == 6 and e._current_anim == "atked_heavy"
	for expected in ["atked_fall_end", "getup"]:
		e._hurt_tick(e._hurt_timer + 0.001)
		chain_ok = chain_ok and e._current_anim == expected
	e._hurt_tick(e._hurt_timer + 0.001)
	chain_ok = chain_ok and not e._hurt_chain_active and e.state == e.State.IDLE
	p("双镰高伤倒地链 5伤不触发/6伤触发/顺序防重入=%s（期望 true）" % chain_ok)
	e._release_token()
	e.queue_free()
	await get_tree().process_frame


## 青笠：按段伤害、实伤养剑意、唯一同步分身，以及严格大于 5 的高伤倒地。
func _qingli_probe() -> void:
	Run.start()
	Run.apply_to(_player)
	_reset_brute_player(Vector2(500, 560))
	var e = load("res://scenes/enemies/c012_elite.tscn").instantiate()
	e.position = Vector2(580, 560)
	add_child(e)
	e.set_physics_process(false)
	e._target = _player
	e.facing = -1
	e._apply_facing()

	# 双剑斩：首段按 0 层结算后才叠到 1 层；次段吃这层加成，穿同招受击无敌并附普通流血。
	e._start_attack("skill01")
	var hp_before: int = _player.hp
	e._deal_hit(0)
	var first_ok: bool = _player.hp == hp_before - Run.enemy_damage(1) and e._sword_intent == 1 and _player._bleed_stacks == 0
	hp_before = _player.hp
	e._deal_hit(1)
	var second_ok: bool = _player.hp == hp_before - Run.enemy_damage(3) and e._sword_intent == 1 \
		and _player._bleed_stacks == 1 and is_equal_approx(_player._bleed_time, 3.0) and _player._cuts.is_empty()
	var timing_ok: bool = e._hit_at_map["skill01"] == [0.80, 1.21] and e._ranges["skill01"] == [172.0, 138.0] \
		and e._damage_map["skill01"] == [1, 2] and is_equal_approx(float(e._hit_at_map["skill02"]), 0.89) \
		and is_equal_approx(float(e._ranges["skill02"]), 163.0)
	p("双剑斩 首段1伤后叠层=%s 次段2+1伤/3秒普通流血=%s 两招标定=%s（期望全 true）" % [first_ok, second_ok, timing_ok])

	# 旋斩：吃当前剑意，实伤再叠一层并封闪 8 秒；独立冷却 12 秒，期间只能回到双剑斩。
	_reset_brute_player(Vector2(500, 560))
	e.global_position.x = 580.0
	e.facing = -1
	e._apply_facing()
	e._start_attack("skill02")
	hp_before = _player.hp
	e._deal_hit(0)
	var spin_ok: bool = _player.hp == hp_before - Run.enemy_damage(3) and e._sword_intent == 2 \
		and is_equal_approx(_player._dash_seal, 8.0)
	var spin_cd_ok: bool = is_equal_approx(float(e._attack_rule_cds["skill02"]), 12.0) \
		and not e._rule_allows("skill02", 80.0)
	e._set_state(e.State.IDLE)
	e._start_attack()
	spin_cd_ok = spin_cd_ok and e._attack_move == "skill01" and e._current_anim == "skill01"
	e._attack_rule_cds["skill02"] = 0.0
	spin_cd_ok = spin_cd_ok and e._rule_allows("skill02", 80.0)
	_reset_brute_player(Vector2(500, 560))
	_player.hp = 50
	e._start_attack("skill02")
	e._deal_hit(0)
	var clone: C016Class = e._sword_clone_node
	var clone_ok: bool = e._sword_intent == 3 and is_instance_valid(clone) \
		and clone._is_sword_clone and clone._sword_owner == e and clone.facing == e.facing \
		and clone._current_anim == e._current_anim and clone.get_node_or_null("SwordCloneThread") == null \
		and clone.get_node_or_null("SwordCloneRing") != null and is_equal_approx(clone.sprite.modulate.a, 0.60) \
		and clone.sprite.modulate.g > clone.sprite.modulate.r and clone.sprite.modulate.b > clone.sprite.modulate.g \
		and not clone.is_in_group("enemies")
	var clone_hp: int = clone.hp
	clone.take_damage(99, _player.global_position.x)
	clone_ok = clone_ok and clone.hp == clone_hp and clone.state != clone.State.DEAD
	e._gain_sword_intent(1)
	clone_ok = clone_ok and e._sword_intent == 3 and e._sword_clone_node == clone
	p("旋斩/剑意 2+1伤与封闪8秒=%s 旋斩12秒CD/冷却普攻兜底/到点可放=%s 三层唯一凝华分身/淡青虚影墨环/同步姿态/无敌=%s（期望全 true）" % [spin_ok, spin_cd_ok, clone_ok])

	# 下一次双剑斩完整同步：镜像复用本体同段伤害，共享出手钥匙，双方直伤与流血都生效。
	clone.set_physics_process(false)
	_reset_brute_player(Vector2(500, 560))
	_player.hp = 50
	e._set_state(e.State.IDLE)
	e._start_attack("skill01")
	var sync_ok: bool = clone.state == clone.State.ATTACK and clone._attack_move == "skill01" \
		and clone._current_anim == e._current_anim and clone.facing == e.facing \
		and clone._attack_cast_id == e._attack_cast_id and C016Class._attacker == e
	hp_before = _player.hp
	e._deal_hit(0)
	var owner_first: int = hp_before - _player.hp
	hp_before = _player.hp
	clone._deal_hit(0)
	var clone_first: int = hp_before - _player.hp
	hp_before = _player.hp
	e._deal_hit(1)
	var owner_second: int = hp_before - _player.hp
	hp_before = _player.hp
	clone._deal_hit(1)
	var clone_second: int = hp_before - _player.hp
	sync_ok = sync_ok and owner_first == Run.enemy_damage(4) and clone_first == owner_first \
		and owner_second == Run.enemy_damage(5) and clone_second == owner_second
	var clone_effect_ok: bool = _player._bleed_stacks == 2 and is_equal_approx(_player._bleed_time, 3.0) \
		and e._sword_intent == 3 and clone._sword_intent == 0 and clone._sword_clone_node == null \
		and e._sword_clone_node == clone
	p("凝华分身 同步招式/朝向/出手编号=%s 同段同伤/共享穿透/双倍普通流血=%s（期望全 true）" % [sync_ok, clone_effect_ok])

	# 旋斩也由镜像完整复刻；镜像实伤封闪，但不给本体叠层、不继续繁殖。
	_reset_brute_player(Vector2(500, 560))
	_player.hp = 50
	e._set_state(e.State.IDLE)
	e._start_attack("skill02")
	hp_before = _player.hp
	e._deal_hit(0)
	var owner_spin: int = hp_before - _player.hp
	hp_before = _player.hp
	clone._deal_hit(0)
	var clone_spin: int = hp_before - _player.hp
	var mirror_spin_ok: bool = owner_spin == Run.enemy_damage(5) and clone_spin == owner_spin \
		and is_equal_approx(_player._dash_seal, 8.0) and e._sword_intent == 3 \
		and clone._sword_intent == 0 and clone._sword_clone_node == null
	p("凝华旋斩 镜像同伤/封闪8秒/不叠层不繁殖=%s（期望 true）" % mirror_spin_ok)

	# 本体死亡立即撤走分身。
	e.take_damage(999, _player.global_position.x)
	await get_tree().process_frame
	var dismiss_ok: bool = e._sword_clone_node == null and not is_instance_valid(clone)
	p("剑意凝华 本体死亡分身消失=%s（期望 true）" % dismiss_ok)
	e.queue_free()
	await get_tree().process_frame

	# 青笠同样严格大于 5：atked → atked_fall_end → 11 号 getup。
	e = load("res://scenes/enemies/c012_elite.tscn").instantiate()
	e.position = Vector2(580, 560)
	add_child(e)
	e.set_physics_process(false)
	e.take_damage(5, _player.global_position.x)
	var chain_ok: bool = not e._hurt_chain_active and e._current_anim == "atked"
	e._start_attack("skill02")
	e.take_damage(6, _player.global_position.x)
	chain_ok = chain_ok and e._hurt_chain_active and e._current_anim == "atked"
	e.take_damage(1, _player.global_position.x)
	chain_ok = chain_ok and e.hp == 8 and e._current_anim == "atked"
	for expected in ["atked_fall_end", "getup"]:
		e._hurt_tick(e._hurt_timer + 0.001)
		chain_ok = chain_ok and e._current_anim == expected
	e._hurt_tick(e._hurt_timer + 0.001)
	chain_ok = chain_ok and not e._hurt_chain_active and e.state == e.State.IDLE
	p("青笠高伤倒地链 5伤不触发/6伤穿旋斩霸体/11号起身=%s（期望 true）" % chain_ok)
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
	_player._hurt_cast_key = ""
	_player._cuts.clear()
	_player._cut_casts.clear()
	_player._clear_bleed()
	_player._jump_seal = 0.0
	_player._dash_seal = 0.0
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
