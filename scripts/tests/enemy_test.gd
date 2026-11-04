extends Node2D

## C016 小怪 AI 冒烟测试：巡逻 -> 追击 -> 攻击玩家 -> 被玩家三连击打死。

const OUT_DIR := "res://tests/out/"
const PlayerClass := preload("res://scripts/player/player.gd")
const C016Class := preload("res://scripts/enemies/c016.gd")
const EnemyTypes := preload("res://scripts/enemies/enemy_types.gd")
const SpineFX := preload("res://scripts/systems/spine_fx.gd")

class BurnSource extends Node:
	var hits := 0
	var dealt := 0

	func on_fen_ding_burn_hit(amount: int, _target: Node) -> void:
		hits += 1
		dealt += amount

var _log: FileAccess
var _player: PlayerClass
var _enemy: C016Class
var _last_p_state := -1
var _last_e_state := -1
var _last_e_hp := -1
var _checks := 0
var _failed := 0


func p(msg) -> void:
	print("[ET] ", msg)
	if _log:
		_log.store_line("[ET] " + str(msg))
		_log.flush()


func _check(ok: bool, label: String) -> void:
	_checks += 1
	if not ok:
		_failed += 1
	p(("PASS " if ok else "FAIL ") + label)


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

	# 10b. 敌方 Spine 状态持续、时停、死亡与碎岳金钟生命周期。
	await _spine_status_probe()

	# 11. 全部普通怪与精英：首招普攻、其余独立冷却、技能优先与普攻兜底。
	await _attack_rule_probe()

	# 12. 青魇剑主专项：礼剑连段、藏剑变式、祭剑强化、魔爆与房间诅咒。
	await _qingyan_probe()

	# 13. 夺取被动与魅唤：怒焰真实扣血回报、剑宗减半与友方击杀隔离。
	_passive_interaction_probe()

	# 第一只小怪尸体死后 ~1.7s 就 queue_free，精英段跑完它早没了，访问前必须判活
	var e_state := "freed"
	var e_hp := "-"
	if is_instance_valid(_enemy):
		e_state = str(_enemy.state)
		e_hp = str(_enemy.hp)
	p("ALL DONE, enemy state=" + e_state + " hp=" + e_hp
		+ " player state=" + str(_player.state) + " checks=" + str(_checks) + " failed=" + str(_failed))
	get_tree().quit(1 if _failed > 0 else 0)


## 全部普通怪与精英共用规则：首招无独立冷却，其余技能就绪优先，全部冷却才回普攻。
func _attack_rule_probe() -> void:
	_player.set_physics_process(false)
	_player.global_position = Vector2(500, 560)
	var all_ok := true
	for id in EnemyTypes.TYPES:
		var e = load("res://scenes/enemies/c016.tscn").instantiate()
		e.type_id = str(id)
		e.position = Vector2(540, 560)
		add_child(e)
		e.set_physics_process(false)
		e._target = _player
		var attacks: Array = e._attack_anims
		var basic := str(attacks[0])
		var followups: Array = []
		for start in e._attack_chain:
			followups.append(str((e._attack_chain[start] as Dictionary).get("anim", "")))
		var rules_ok: bool = is_zero_approx(float(e._attack_rules[basic].get("cooldown", -1.0)))
		var eligible_skill := false
		for i in range(1, attacks.size()):
			var move := str(attacks[i])
			var cd := float(e._attack_rules[move].get("cooldown", 0.0))
			rules_ok = rules_ok and (is_zero_approx(cd) if followups.has(move) else cd > 0.0)
			var rule: Dictionary = e._attack_rules[move]
			if not followups.has(move) and bool(rule.get("random", true)) and e._rule_allows(move, 40.0) and e._max_range_of(move) >= 30.0:
				eligible_skill = true
		e._start_attack()
		var priority_ok: bool = e._attack_move != basic if eligible_skill else e._attack_move == basic
		e._release_token()
		for i in range(1, attacks.size()):
			e._attack_rule_cds[str(attacks[i])] = 99.0
		e._start_attack()
		var fallback_ok: bool = e._attack_move == basic
		e._release_token()
		for move in e._attack_rule_cds:
			e._attack_rule_cds[move] = 0.0
		e._start_attack()
		var restored_ok: bool = e._attack_move != basic if eligible_skill else e._attack_move == basic
		if str(id) == "c037":
			rules_ok = rules_ok and is_equal_approx(float(e._attack_rules["skill03"]["cooldown"]), 7.2) \
				and is_equal_approx(float(e._attack_rules["cangjian"]["cooldown"]), 9.6)
		var one_ok: bool = rules_ok and priority_ok and fallback_ok and restored_ok
		all_ok = all_ok and one_ok
		p("统一出手规则 %s 冷却配置=%s 技能优先=%s 普攻兜底=%s 恢复优先=%s（期望全 true）" % [str(id), rules_ok, priority_ok, fallback_ok, restored_ok])
		e._release_token()
		e.queue_free()
		await get_tree().process_frame
	p("六种敌人统一出手规则=%s（期望 true）" % all_ok)


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
	p("升龙刀 瞬移贴身=%s 前摇=%.2fs 实伤=%s 短击飞=%s 独立CD14.4秒=%s 冷却禁重入=%s 到点可放=%s 闪避不击飞=%s（期望全 true / 0.87）" % [blink_ok, windup, rising_ok, launch_ok, is_equal_approx(rising_cd, 14.4), cd_blocks, cd_ready, dodge_no_launch])
	e._release_token()
	e.queue_free()
	await get_tree().process_frame

	# 双镰就绪时永远优先于普攻；冷却期间回普攻，恢复后再次优先技能。
	e = load("res://scenes/enemies/c016.tscn").instantiate()
	e.position = Vector2(820, 560)
	add_child(e)
	e.set_physics_process(false)
	e._target = _player
	var skill_priority := true
	for i in 40:
		e._attack_rule_cds["skill04"] = 0.0
		e._start_attack()
		skill_priority = skill_priority and e._attack_move == "skill04"
		e._release_token()
	e._attack_rule_cds["skill04"] = 99.0
	e._start_attack()
	var basic_fallback: bool = e._attack_move == "skill01"
	e._release_token()
	e._attack_rule_cds["skill04"] = 0.0
	e._start_attack()
	var skill_restored: bool = e._attack_move == "skill04"
	e._release_token()
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
	p("出手规则 双镰优先=%s 冷却普攻兜底=%s 冷却结束恢复优先=%s 螺旋鞭距离窗=%s（期望全 true）" % [skill_priority, basic_fallback, skill_restored, whip_window])
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

	# 辟地就绪优先；追击连段不进入近身随机池，连段收尾也不作为独立技能。
	var skill_priority := true
	for i in 40:
		e._attack_rule_cds["skill02"] = 0.0
		e._start_attack()
		skill_priority = skill_priority and e._attack_move == "skill02"
		e._release_token()
	e._attack_rule_cds["skill02"] = 99.0
	e._start_attack()
	var basic_fallback: bool = e._attack_move == "skill01"
	e._release_token()
	var pool_ok: bool = skill_priority and basic_fallback and is_zero_approx(float(e._attack_rules["skill01"]["cooldown"])) \
		and float(e._attack_rules["skill03_2"]["cooldown"]) > 0.0 and is_zero_approx(float(e._attack_rules["skill03_3"]["cooldown"]))
	p("蛮兵出手池 辟地优先=%s 冷却开天兜底=%s 主招计时/收尾共享=%s（期望全 true）" % [skill_priority, basic_fallback, pool_ok])

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

	# 辟地：独立 10.8 秒冷却，实伤才附加 8 秒封跳；防御路径不误挂。
	_reset_brute_player()
	e._start_attack("skill02")
	hit_at = e._attack_dur - float(e._attack_hits_left[0]["t"])
	hp_before = _player.hp
	e._deal_hit(0)
	var ground_ok: bool = is_equal_approx(hit_at, 1.58) and is_equal_approx(e._range_of("skill02", 0), 152.0) \
		and _player.hp == hp_before - Run.enemy_damage(2) and is_equal_approx(_player._jump_seal, 8.0) \
		and is_equal_approx(float(e._attack_rule_cds["skill02"]), 10.8)
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
	p("辟地 2伤/10.8秒CD/8秒封跳=%s 封跳禁跳=%s 解禁可跳=%s 闪避/护盾/无敌不附加=%s/%s/%s（期望全 true）" % [ground_ok, sealed_jump, free_jump, dodge_ok, shield_ok, invincible_ok])
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
		and is_equal_approx(float(e._attack_rule_cds["skill03_2"]), 19.2) \
		and is_equal_approx(float(e._advance_map["skill03_2"]), 85.0)
	var chain_cast_id: int = e._attack_cast_id
	hp_before = _player.hp
	e._attack_tick(0.35)
	e.global_position.x += e.velocity.x * 0.35 # 手动帧推进也要同步攻击步进，否则首劈仍停在 200px 外
	var no_early_chain_hit: bool = _player.hp == hp_before
	e._attack_tick(0.01)
	e.global_position.x += e.velocity.x * 0.01
	var first_hit: bool = _player.hp == hp_before - Run.enemy_damage(1)
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
		and is_equal_approx(e.velocity.x, 0.0) and e._attack_cast_id == chain_cast_id
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
	_check(first_hit and second_hit and final_hit and second_stage,
		"赶山三斧全程保留cast key，0.8秒受击无敌不吞同连段")

	# 独立重新起手必须生成新编号，不能借用上一连段的穿透身份。
	_player.global_position = Vector2(500, 560)
	e.global_position = Vector2(580, 560)
	e.facing = -1
	e._apply_facing()
	hp_before = _player.hp
	e._start_attack("skill01")
	var new_cast_blocked: bool = e._attack_cast_id != chain_cast_id
	e._deal_hit(0)
	new_cast_blocked = new_cast_blocked and _player.hp == hp_before
	_check(new_cast_blocked, "赶山三斧独立新起手不穿上次受击无敌")
	e._release_token()

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
	p("赶山三斧 19.2秒冷却禁重入=%s 到点可放=%s（期望 true / true）" % [cd_blocks, cd_ready])
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

	# 偷袭：200px 追击窗内绕到目标背后 72px，14.4 秒独立冷却，砸击触发背刺。
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
		and e.facing == 1 and is_equal_approx(float(e._attack_rule_cds["sneak"]), 14.4) \
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
	p("偷袭 11号动画/绕背72px/14.4秒CD=%s 前摇无判=%s 0.94秒背刺4伤=%s 无割伤=%s 冷却禁重入=%s 到点可放=%s（期望全 true）" % [blink_ok, no_early_hit, sneak_hit, _player._cuts.is_empty(), cd_blocks, cd_ready])
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
	e._attack_rule_cds["skill02"] = 9.6
	e._start_attack("skill03")
	e._deal_hit(0)
	var bloom_ok: bool = _player.hp == 5 and _player.max_hp == Run.max_hp and Run.max_hp_loss == 2 \
		and _player.global_position.is_equal_approx(e.global_position + Vector2(0, -120)) \
		and is_equal_approx(e._skill_cooldown_scale, 0.5) and is_equal_approx(float(e._attack_rule_cds["skill03"]), 7.2) \
		and is_equal_approx(float(e._attack_rule_cds["skill02"]), 4.8) and is_equal_approx(e._attack_cd, 0.95)
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

	# 绽花的零伤回调只有在 _apply_bloom 真正结算后才减冷却并嗜血回血。
	e.hp = 10
	e._skill_cooldown_scale = 1.0
	var bloom_loss_before: int = Run.max_hp_loss
	_reset_brute_player(Vector2(500, 560))
	_player._hurt_invincible = 0.8
	e._start_attack("skill03")
	e._deal_hit(0)
	var bloom_hurt_block: bool = e.hp == 10 and is_equal_approx(e._skill_cooldown_scale, 1.0) \
		and Run.max_hp_loss == bloom_loss_before
	_reset_brute_player(Vector2(500, 560))
	_player._invincible = true
	e._start_attack("skill03")
	e._deal_hit(0)
	var bloom_skill_block: bool = e.hp == 10 and is_equal_approx(e._skill_cooldown_scale, 1.0) \
		and Run.max_hp_loss == bloom_loss_before
	_reset_brute_player(Vector2(500, 560))
	_player._shield_hits = 1
	e._start_attack("skill03")
	e._deal_hit(0)
	var bloom_shield_block: bool = e.hp == 10 and is_equal_approx(e._skill_cooldown_scale, 1.0) \
		and Run.max_hp_loss == bloom_loss_before
	_reset_brute_player(Vector2(500, 560))
	e._start_attack("skill03")
	e._deal_hit(0)
	var bloom_effective: bool = e.hp == 11 and is_equal_approx(e._skill_cooldown_scale, 0.5) \
		and Run.max_hp_loss == bloom_loss_before + 2
	_check(bloom_hurt_block and bloom_skill_block and bloom_shield_block and bloom_effective,
		"绽花受击/技能无敌与护盾不增益，真实零伤结算仍减CD并嗜血")
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

	# 本体时停/晕眩同步打断分身；控制期间不得被后续同步调用重新拉起。
	e.time_stop(1.0)
	var clone_control_ok: bool = e._stop_timer > 0.0 and is_equal_approx(clone._stop_timer, e._stop_timer) \
		and clone.state == clone.State.IDLE and clone._attack_hits_left.is_empty() \
		and clone.sprite.process_mode == Node.PROCESS_MODE_DISABLED and C016Class._attacker == null
	clone._sword_sync_attack("skill01")
	clone_control_ok = clone_control_ok and clone.state == clone.State.IDLE
	clone._physics_process(0.4)
	clone_control_ok = clone_control_ok and clone._stop_timer > 0.0 and clone.state == clone.State.IDLE
	clone._physics_process(0.7)
	clone_control_ok = clone_control_ok and clone._stop_timer <= 0.0 \
		and clone.sprite.process_mode == Node.PROCESS_MODE_INHERIT
	e._end_stop()
	e.stun(1.0)
	clone_control_ok = clone_control_ok and e._stun_timer > 0.0 \
		and is_equal_approx(clone._stun_timer, e._stun_timer) and clone.state == clone.State.IDLE
	clone._sword_sync_attack("skill02")
	clone_control_ok = clone_control_ok and clone.state == clone.State.IDLE
	clone._physics_process(1.1)
	clone_control_ok = clone_control_ok and clone._stun_timer <= 0.0 and clone.state == clone.State.IDLE
	_check(clone_control_ok, "青笠分身同步时停/晕眩，控制中拒绝同步起手并正常解除")

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


## 敌方 Spine：真实节点随状态生灭，重复施加不重建，时停继承冻结，死亡/离场不泄漏。
func _spine_status_probe() -> void:
	var e = load("res://scenes/enemies/c016.tscn").instantiate()
	e.position = Vector2(900, 560)
	add_child(e)
	e.set_physics_process(false)
	e.apply_poison(4.0)
	e.stun(4.0, true)
	e.apply_charm(4.0)
	e.apply_frenzy(4.0)
	await get_tree().process_frame
	var ids := {"poison": "E50127", "stun": "E52000", "charm": "E54156", "frenzy": "E52007"}
	var nodes: Dictionary = {}
	var nodes_ok := true
	for key in ids:
		var fx = e._status_fx.get(key)
		nodes[key] = fx
		if not is_instance_valid(fx):
			nodes_ok = false
			continue
		nodes_ok = nodes_ok and fx.get_parent() == e and str(fx.get_meta("fx_id", "")) == ids[key] \
			and fx.sprite != null and fx.sprite.get("skeleton_data_res") == SpineFX.data(ids[key]) \
			and fx._lifetime < 0.0 and fx.position.y < 0.0
	_check(nodes_ok and e._status_fx.size() == 4 and not e._status_fx.has("bell"),
		"中毒/晕眩/魅惑/癫狂生成对应真实Spine子节点，普通怪无金钟")

	e.apply_poison(5.0)
	e.stun(5.0, true)
	e.apply_charm(5.0)
	e.apply_frenzy(5.0)
	await get_tree().process_frame
	var unique_ok := true
	var attached_count := 0
	for child in e.get_children():
		if child.has_meta("status_key"):
			attached_count += 1
	for key in nodes:
		unique_ok = unique_ok and e._status_fx.get(key) == nodes[key]
	_check(unique_ok and attached_count == 4, "重复刷新四种状态不重复生成或替换持续特效")

	e.time_stop(1.0)
	var stop_ok := true
	for fx in nodes.values():
		stop_ok = stop_ok and fx.process_mode == Node.PROCESS_MODE_DISABLED \
			and not fx.can_process() and not fx.sprite.can_process()
	e._end_stop()
	for fx in nodes.values():
		stop_ok = stop_ok and fx.process_mode == Node.PROCESS_MODE_INHERIT and fx.can_process() and fx.sprite.can_process()
	_check(stop_ok, "状态特效随敌人时停冻结并在解冻后恢复，不另跑计时")

	# 走实际 tick 让四种状态自然到期，队列释放后旧引用必须全部失效。
	e._poison_time = 0.01
	e._stun_timer = 0.01
	e._charm_time = 0.01
	e._frenzy_time = 0.01
	e._poison_tick(0.02)
	e._pipa_status_tick(0.02)
	e._stun_tick(0.02)
	await get_tree().process_frame
	var expired_ok: bool = e._status_fx.is_empty()
	for fx in nodes.values():
		expired_ok = expired_ok and not is_instance_valid(fx)
	_check(expired_ok, "四种状态自然结束立即释放各自持续特效")

	e.apply_poison(2.0)
	await get_tree().process_frame
	var death_status = e._status_fx.get("poison")
	e.take_damage(e.hp, _player.global_position.x)
	await get_tree().process_frame
	_check(e.state == e.State.DEAD and e._status_fx.is_empty() and not is_instance_valid(death_status) \
		and not is_instance_valid(e._qingli_death_fx), "普通c016死亡清除状态且不触发青笠亡语视觉")
	e.queue_free()
	await get_tree().process_frame

	# 青笠原配置没有死亡伤害段；替换消散视觉后仍不得新增判定或改动既有 hit_at/range。
	_reset_brute_player(Vector2(500, 560))
	_player.hp = 50
	var q = load("res://scenes/enemies/c012_elite.tscn").instantiate()
	q.position = Vector2(500, 560)
	add_child(q)
	q.set_physics_process(false)
	var witness = load("res://scenes/enemies/c016.tscn").instantiate()
	witness.position = Vector2(550, 560)
	add_child(witness)
	witness.set_physics_process(false)
	var old_hit_at: Dictionary = q._hit_at_map.duplicate(true)
	var old_ranges: Dictionary = q._ranges.duplicate(true)
	var player_hp: int = _player.hp
	var witness_hp: int = witness.hp
	q.die()
	var death_fx = q._qingli_death_fx
	var death_ok: bool = q._is_qingli_elite() and is_instance_valid(death_fx) \
		and death_fx.get_parent() == get_tree().current_scene and str(death_fx.get_meta("fx_id", "")) == "E54148" \
		and death_fx.sprite.get("skeleton_data_res") == SpineFX.data("E54148") and death_fx._lifetime > 0.0
	death_ok = death_ok and q._attack_hits_left.is_empty() and _player.hp == player_hp and witness.hp == witness_hp \
		and q._hit_at_map == old_hit_at and q._ranges == old_ranges
	_check(death_ok, "真正青笠精英仅替换死亡视觉，不新增伤害次数/范围并保留原hit_at/range")
	if is_instance_valid(death_fx):
		death_fx._process(death_fx._lifetime + 0.1)
	await get_tree().process_frame
	_check(not is_instance_valid(death_fx), "青笠死亡Spine按原动画生命周期自动销毁")
	q.queue_free()
	witness.queue_free()
	await get_tree().process_frame

	# 碎岳确实拥有金钟：一层抵挡两次，视觉保持到第二次抵挡后才消失。
	var b = load("res://scenes/enemies/bosses/boss.tscn").instantiate()
	b.set_script(load("res://scripts/enemies/sui_yue.gd"))
	b.type_id = "c008"
	add_child(b)
	b.set_physics_process(false)
	await get_tree().process_frame
	var bell_ok: bool = b._status_fx.is_empty() and not b._is_qingli_elite()
	b._bell_layers.append(2)
	await get_tree().process_frame
	var bell = b._status_fx.get("bell")
	bell_ok = bell_ok and is_instance_valid(bell) and str(bell.get_meta("fx_id", "")) == "E52025" \
		and bell.sprite.get("skeleton_data_res") == SpineFX.data("E52025")
	b.take_damage(1, b.global_position.x - 10.0)
	await get_tree().process_frame
	bell_ok = bell_ok and b._bell_layers == [1] and b._status_fx.get("bell") == bell and is_instance_valid(bell)
	b.take_damage(1, b.global_position.x - 10.0)
	await get_tree().process_frame
	bell_ok = bell_ok and b._bell_layers.is_empty() and not b._status_fx.has("bell") and not is_instance_valid(bell)
	_check(bell_ok, "碎岳E52025随金钟生成，两次抵挡期间去重并在耗尽后释放")
	b.queue_free()
	await get_tree().process_frame


## 青魇剑主：首段慢放、三变式藏剑、祭剑强化，以及魔爆后的双侧房间诅咒。
func _qingyan_probe() -> void:
	Run.start()
	Run.apply_to(_player)
	_reset_brute_player(Vector2(500, 560))
	_player._room_cd_cursed = false
	_player._room_cd_uses.clear()
	var e = load("res://scenes/enemies/c037_elite.tscn").instantiate()
	e.position = Vector2(580, 560)
	add_child(e)
	e.set_physics_process(false)
	e._target = _player
	e.facing = -1
	e._apply_facing()

	# 亭台剑：只拉长首段前摇，后续两剑恢复原速；三段仍按同一次起手穿透受击无敌。
	e._start_attack("skill01")
	var real_hits: Array = []
	for hit in e._attack_hits_left:
		real_hits.append(snappedf(e._attack_dur - float(hit["t"]), 0.001))
	var opening_ok: bool = e._attack_visual == "skill01" and e._attack_hits_left.size() == 3 \
		and is_equal_approx(float(e._current_anim_speed), 0.50) and real_hits == [0.98, 1.68, 1.99] \
		and e._damage_map["skill01"] == [1, 1, 2]
	var hp_before: int = _player.hp
	e._attack_tick(1.01)
	var first_ok: bool = _player.hp == hp_before - Run.enemy_damage(1) \
		and is_equal_approx(float(e._current_anim_speed), 1.0) and e._attack_hits_left.size() == 2
	hp_before = _player.hp
	e._deal_hit(1)
	var second_ok: bool = _player.hp == hp_before - Run.enemy_damage(1)
	hp_before = _player.hp
	e._deal_hit(2)
	var third_ok: bool = _player.hp == hp_before - Run.enemy_damage(2) and _player._cuts.is_empty()
	p("亭台剑 首段半速/真实判定0.98/1.68/1.99=%s 三段1/1/2实伤=%s/%s/%s（期望全 true）" % [opening_ok, first_ok, second_ok, third_ok])

	# 转：首次 2 伤，实伤后才叠层；新起手撞受击无敌不叠，下一记实伤变为 3。
	_reset_brute_player(Vector2(500, 560))
	e._set_state(e.State.IDLE)
	e._start_attack("skill03")
	hp_before = _player.hp
	e._deal_hit(0)
	var player_id: int = _player.get_instance_id()
	var turn_first: bool = _player.hp == hp_before - Run.enemy_damage(2) \
		and int(e._turn_stacks.get(player_id, 0)) == 1 and is_equal_approx(_player.velocity.x, -420.0)
	hp_before = _player.hp
	e._set_state(e.State.IDLE)
	e._start_attack("skill03")
	e._deal_hit(0)
	var turn_blocked: bool = _player.hp == hp_before and int(e._turn_stacks.get(player_id, 0)) == 1
	_reset_brute_player(Vector2(500, 560))
	e._set_state(e.State.IDLE)
	e._start_attack("skill03")
	hp_before = _player.hp
	e._deal_hit(0)
	var turn_second: bool = _player.hp == hp_before - Run.enemy_damage(3) \
		and int(e._turn_stacks.get(player_id, 0)) == 2
	var other = load("res://scenes/player/player.tscn").instantiate()
	other.position = Vector2(500, 560)
	add_child(other)
	other.remove_from_group("player")
	other.set_physics_process(false)
	other.hp = 50
	e._target = other
	e._set_state(e.State.IDLE)
	e._start_attack("skill03")
	hp_before = other.hp
	e._deal_hit(0)
	var other_id: int = other.get_instance_id()
	var turn_independent: bool = other.hp == hp_before - Run.enemy_damage(2) \
		and int(e._turn_stacks.get(other_id, 0)) == 1 and int(e._turn_stacks.get(player_id, 0)) == 2
	p("转 首次2伤/击退/二次3伤=%s/%s 受击无敌不叠层=%s 不同目标独立=%s（期望全 true）" % [turn_first, turn_second, turn_blocked, turn_independent])
	other.queue_free()
	e._target = _player
	await get_tree().process_frame

	# 藏剑式：逐条强制抽取三种动画，各自使用自己的时刻与范围，末段只登记一组割伤。
	e._move_pool = e._move_pool.duplicate(true)
	var visuals: Array = e._move_pool["cangjian"].duplicate()
	var expected_hits := {"skill05": [0.40, 1.20, 1.88], "skill06": [0.28, 0.69, 1.62], "skill01-cankao": [0.47, 1.18, 1.47]}
	var expected_ranges := {"skill05": [128.0, 96.0, 176.0], "skill06": [131.0, 162.0, 164.0], "skill01-cankao": [130.0, 164.0, 161.0]}
	var cangjian_ok := true
	for visual in visuals:
		e._move_pool["cangjian"] = [visual]
		_reset_brute_player(Vector2(500, 560))
		e._set_state(e.State.IDLE)
		e._start_attack("cangjian")
		var variant_ok: bool = e._attack_move == "cangjian" and e._attack_visual == visual \
			and e._attack_hits_left.size() == 3 and e._hit_at_map[visual] == expected_hits[visual] \
			and e._ranges[visual] == expected_ranges[visual]
		hp_before = _player.hp
		for seg in 3:
			e._deal_hit(seg)
		variant_ok = variant_ok and _player.hp == hp_before - Run.enemy_damage(1) - Run.enemy_damage(2) - Run.enemy_damage(3) \
			and _player._cuts.size() == 1 and _player._cuts[0]["left"] == [3.0, 6.0]
		cangjian_ok = cangjian_ok and variant_ok
	e._move_pool["cangjian"] = visuals
	p("藏剑式 三变式各自三段1/2/3与判定范围/末段单组3及6秒割伤=%s（期望 true）" % cangjian_ok)
	e.queue_free()
	await get_tree().process_frame

	# 半血本身不触发，严格低于一半才祭剑；他人持令牌时只回满排队，不得抢招。
	e = load("res://scenes/enemies/c037_elite.tscn").instantiate()
	e.position = Vector2(580, 560)
	add_child(e)
	e.set_physics_process(false)
	e._target = _player
	var blocker = load("res://scenes/enemies/c016.tscn").instantiate()
	blocker.position = Vector2(900, 560)
	add_child(blocker)
	blocker.set_physics_process(false)
	blocker._target = _player
	blocker._start_attack("skill01")
	e.take_damage(12, _player.global_position.x)
	var limit_half: bool = e.hp == 12 and not e._limit_used
	e.take_damage(1, _player.global_position.x)
	var limit_wait: bool = limit_half and e._limit_used and e._limit_pending and e.hp == e.max_hp \
		and e._cut_every_segment and C016Class._attacker == blocker and e.state != e.State.ATTACK
	e.take_damage(1, _player.global_position.x)
	limit_wait = limit_wait and e.hp == e.max_hp - 1 and e._limit_pending
	e.time_stop(1.0)
	blocker._release_token()
	e._try_start_limit()
	var limit_stop: bool = e._limit_pending and e.state != e.State.ATTACK
	e._end_stop()
	e._try_start_limit()
	var limit_ok: bool = limit_wait and limit_stop and not e._limit_pending and C016Class._attacker == e \
		and e._attack_move == "jijian" and ["skill04", "skill04-cankao"].has(e._attack_visual) \
		and e._attack_hits_left.is_empty() and not e._hurt_chain_active
	_check(limit_ok, "祭剑严格跨半血一次，令牌竞争与时停只排队不起手")
	_reset_brute_player(Vector2(500, 560))
	e._set_state(e.State.IDLE)
	e._start_attack("skill01")
	for seg in 3:
		e._deal_hit(seg)
	var empowered_ok: bool = _player._cuts.size() == 3
	var cut_keys: Dictionary = {}
	for cut in _player._cuts:
		cut_keys[str(cut["key"])] = true
	empowered_ok = empowered_ok and cut_keys.size() == 3
	p("断楹祭剑 半血/回满/令牌等待/每实体一次=%s 强化后每段独立割伤=%s（期望全 true）" % [limit_ok, empowered_ok])
	e._release_token()
	e.queue_free()
	blocker.queue_free()
	await get_tree().process_frame

	# 非致命 DoT 共用严格阈值；先回满并排/起祭剑，不能留在旧受击状态。
	var dot = load("res://scenes/enemies/c037_elite.tscn").instantiate()
	dot.position = Vector2(580, 560)
	add_child(dot)
	dot.set_physics_process(false)
	dot._target = _player
	dot.hp = 13
	dot._direct_damage(2)
	_check(dot.hp == dot.max_hp and dot._limit_used and not dot._limit_pending \
		and dot._attack_move == "jijian" and not dot._hurt_chain_active,
		"DoT跨严格半血触发一次祭剑并回满")
	dot._release_token()
	dot.queue_free()
	await get_tree().process_frame

	# 高伤链：5 伤不倒，6 伤触发，最后固定使用 9 号 getup。
	e = load("res://scenes/enemies/c037_elite.tscn").instantiate()
	e.position = Vector2(580, 560)
	add_child(e)
	e.set_physics_process(false)
	e._limit_used = true
	e.take_damage(5, _player.global_position.x)
	var chain_ok: bool = not e._hurt_chain_active and e.hp == 19
	e.take_damage(6, _player.global_position.x)
	chain_ok = chain_ok and e._hurt_chain_active and e._current_anim == "atked_heavy"
	for expected in ["atked_fall_end", "getup"]:
		e._hurt_tick(e._hurt_timer + 0.001)
		chain_ok = chain_ok and e._current_anim == expected
	e._hurt_tick(e._hurt_timer + 0.001)
	chain_ok = chain_ok and not e._hurt_chain_active and e.state == e.State.IDLE
	p("青魇高伤链 5伤不倒/6伤倒地/9号起身=%s（期望 true）" % chain_ok)
	e.queue_free()
	await get_tree().process_frame

	# 魔爆：死亡信号等最后一击后才发；前方玩家与敌人都实伤并中诅咒，后方不受影响。
	_reset_brute_player(Vector2(700, 560))
	_player.hp = 50
	var caster = load("res://scenes/enemies/c037_elite.tscn").instantiate()
	caster.position = Vector2(500, 560)
	add_child(caster)
	caster.set_physics_process(false)
	caster.facing = 1
	caster._apply_facing()
	var front = load("res://scenes/enemies/c016.tscn").instantiate()
	front.position = Vector2(700, 560)
	add_child(front)
	front.set_physics_process(false)
	front._target = _player
	var back = load("res://scenes/enemies/c016.tscn").instantiate()
	back.position = Vector2(300, 560)
	add_child(back)
	back.set_physics_process(false)
	var burst_done := {"value": false}
	caster.died.connect(func(): burst_done["value"] = true)
	var wave_done := {"cleared": false, "all": false}
	var spawner = load("res://scripts/systems/wave_spawner.gd").new()
	spawner.waves = [{"count": 0}]
	spawner.wave_cleared.connect(func(_index): wave_done["cleared"] = true)
	spawner.all_cleared.connect(func(): wave_done["all"] = true)
	add_child(spawner)
	spawner.set_process(false)
	spawner._cd = 0.0
	spawner._alive.append(caster)
	caster.died.connect(spawner._on_enemy_died.bind(caster))
	hp_before = _player.hp
	var front_hp: int = front.hp
	var back_hp: int = back.hp
	caster.take_damage(caster.hp, caster.global_position.x - 10.0)
	spawner._process(0.0)
	var delayed_ok: bool = caster.state == caster.State.DEAD and caster._current_anim == "getup" and not burst_done["value"] \
		and spawner._alive.has(caster) and not wave_done["cleared"]
	await get_tree().create_timer(0.9).timeout
	spawner._process(0.0)
	delayed_ok = delayed_ok and caster._current_anim == "transform" and not burst_done["value"] \
		and _player.hp == hp_before and front.hp == front_hp and not front._room_cd_cursed \
		and spawner._alive.has(caster) and not wave_done["cleared"]
	await get_tree().create_timer(3.7).timeout
	spawner._process(0.0)
	var burst_hit_ok: bool = _player.hp == hp_before - 3 and front.hp == front_hp - 3 and back.hp == back_hp \
		and _player._room_cd_cursed and front._room_cd_cursed and not back._room_cd_cursed and not burst_done["value"] \
		and spawner._alive.has(caster) and not wave_done["cleared"]
	await get_tree().create_timer(0.3).timeout
	spawner._process(0.0)
	delayed_ok = delayed_ok and burst_done["value"]
	_check(delayed_ok and wave_done["cleared"] and wave_done["all"] and spawner._wave == -1,
		"魔爆hp归零与演出期间不清波，真实died后才结算波次")
	p("魔爆 起身/22号变身/延迟死亡信号=%s 前方敌我3伤与魔诅/后方无伤=%s（期望全 true）" % [delayed_ok, burst_hit_ok])

	# 玩家与敌人的独立冷却都在每次使用后再 +1；新实例等同于换房，不继承魔诅。
	front._start_attack("skill02")
	var enemy_cd1: float = front._attack_rule_cds["skill02"]
	front._start_attack("skill02")
	var enemy_cd2: float = front._attack_rule_cds["skill02"]
	front._start_attack("skill01")
	var enemy_curse_ok: bool = is_equal_approx(enemy_cd2 - enemy_cd1, 1.0) \
		and int(front._room_skill_uses.get("skill02", 0)) == 2 and not front._room_skill_uses.has("skill01")
	_player._start_skill("skill01")
	var player_cd1: float = _player._skill_cds["skill01"]
	_player._start_skill("skill01")
	var player_cd2: float = _player._skill_cds["skill01"]
	_player._start_skill("skill01")
	var player_cd3: float = _player._skill_cds["skill01"]
	var player_curse_ok: bool = is_equal_approx(player_cd2 - player_cd1, 1.0) and is_equal_approx(player_cd3 - player_cd2, 1.0)
	var fresh_player = load("res://scenes/player/player.tscn").instantiate()
	add_child(fresh_player)
	var room_clear_ok: bool = not fresh_player._room_cd_cursed and fresh_player._room_cd_uses.is_empty()
	fresh_player.queue_free()
	var fresh_enemy = load("res://scenes/enemies/c016.tscn").instantiate()
	add_child(fresh_enemy)
	room_clear_ok = room_clear_ok and not fresh_enemy._room_cd_cursed and fresh_enemy._room_skill_uses.is_empty()
	fresh_enemy.queue_free()
	p("魔诅 敌人逐用+1且普攻不受罚=%s 玩家逐用+1=%s 新房间实例清除=%s（期望全 true）" % [enemy_curse_ok, player_curse_ok, room_clear_ok])
	caster.queue_free()
	front.queue_free()
	back.queue_free()
	spawner.queue_free()
	await get_tree().process_frame


func _passive_interaction_probe() -> void:
	var e = load("res://scenes/enemies/c016.tscn").instantiate()
	add_child(e)
	e.set_physics_process(false)
	e.hp = 4
	var source := BurnSource.new()
	add_child(source)
	e.apply_player_burn(source)
	e._player_burn_left = 0.0
	var burn_hp: int = e.hp
	e._player_burn_tick(0.016)
	_check(e.hp == burn_hp - 1 and source.hits == 1 and source.dealt == 1,
		"炽热之心只在怒焰实际扣血后回报一次")
	source.queue_free()

	e.max_hp = 6
	e.hp = 1
	e.state = e.State.IDLE
	e.apply_sword_sect()
	e.apply_sword_sect()
	e._heal(1)
	var fractional_ok: bool = e.hp == 1 and is_equal_approx(e._heal_fraction, 0.5)
	e._heal(1)
	fractional_ok = fractional_ok and e.hp == 2
	e._heal(1)
	e._heal(1)
	_check(fractional_ok and e.hp == 3 and is_equal_approx(e._sword_sect_scale, 0.5),
		"剑宗固定减半且累计小数治疗，重复命中不继续叠乘")

	var ally = load("res://scenes/enemies/c016.tscn").instantiate()
	ally.player_ally = true
	add_child(ally)
	ally.set_physics_process(false)
	ally._find_target()
	_check(ally.is_in_group("player_allies") and not ally.is_in_group("enemies") \
		and ally._target != null and ally._target.is_in_group("enemies"),
		"魅唤只从敌人组选择攻击目标")
	var kills_before: int = Meta.kills
	var score_before: int = Score.kills
	var seen_before := int(Meta.seen.get("c016", 0))
	ally.hp = 0
	ally.die()
	_check(Meta.kills == kills_before and Score.kills == score_before and int(Meta.seen.get("c016", 0)) == seen_before,
		"魅唤死亡不计局外击杀、图鉴或本局战绩")
	e.queue_free()


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
