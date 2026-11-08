extends Node

## 武车专项回归：耐久难度、武撞动画链、单次接触、通缉、召唤波次与死亡。

var _log: FileAccess
var _room
var _b
var _p
var _checks := 0
var _failed := 0


func p(msg) -> void:
	print("[WC] ", msg)
	if _log:
		_log.store_line("[WC] " + str(msg))
		_log.flush()


func _check(ok: bool, label: String) -> void:
	_checks += 1
	if not ok:
		_failed += 1
	p(("PASS " if ok else "FAIL ") + label)


func _ready() -> void:
	Run.balance_scaling = false # 机制用例固定原始耐久数值，人数缩放由 enemy_balance_probe 覆盖
	_log = FileAccess.open("res://tests/wu_che_test.log", FileAccess.WRITE)
	get_tree().create_timer(45.0).timeout.connect(func():
		p("TIMEOUT")
		get_tree().quit(2)
	)
	Run.start()
	Run.room_index = Run.ROOMS.size()
	Run.boss_id = "c001"
	Run.boss_queue = ["c001"]
	_room = load("res://scenes/world/room_01.tscn").instantiate()
	add_child(_room)
	_b = _room._boss
	_p = _room._player
	_check(_b.get_script() == load("res://scripts/enemies/wu_che.gd"), "正式房间使用武车独立脚本")
	_check(_b.max_hp == 5 and _b.hp == 5, "落笔难度初始为 5 点耐久")
	await _test_formal_entrance()
	_b.set_physics_process(false)
	_p.set_physics_process(false)
	_test_difficulty()
	_test_startup_and_first_wall()
	await _test_time_stop_interrupts()
	await _test_contact_and_wanted()
	_test_passives()
	_test_waves()
	_test_charm_ally_isolation()
	_test_edge_player()
	_test_idle_and_death()
	p("DONE checks=%d failed=%d" % [_checks, _failed])
	get_tree().quit(1 if _failed > 0 else 0)


func _test_formal_entrance() -> void:
	var intro = _room.get_node_or_null("BossDuelIntro")
	if intro != null:
		intro._finish()
	for i in 6:
		await get_tree().create_timer(0.25).timeout
	_check(_b.state == _b.S_START or _b.state == _b.S_RUN, "正式先导结束后武车进入自己的冲锋链而非通用 CHASE")
	_check(_b._charge_elapsed > 1.15 and absf(_b.global_position.x - 1120.0) > 100.0 and absf(_b.velocity.x) > 0.0,
		"正式先导结束后武车朝目标真实开始移动")


func _reset_boss() -> void:
	_clear_summons()
	_b._end_stop()
	_b.state = _b.State.IDLE
	_b.max_hp = 5
	_b.hp = 5
	_b.global_position = Vector2(960, 560)
	_b.velocity = Vector2.ZERO
	_b.facing = 1
	_b._apply_facing()
	_b.arena_left = 0.0
	_b.arena_right = 1920.0
	_b._charges_completed = 0
	_b._set_ghost(false)
	_b._charge_moving = false
	_b._charge_contact_done = false
	_b._summon_total = 0
	_b._summon_index = 0
	_b._summon_elites_left = 0
	_b._summon_bonus = 0
	_b._history_time = 0.0
	_b._position_history = [{"time": 0.0, "position": _b.global_position}]
	_b._target = _p
	_p.global_position = Vector2(400, 100)
	_p.velocity = Vector2.ZERO
	_p.state = _p.State.IDLE
	_p.max_hp = 99
	_p.hp = 99
	_p._hurt_invincible = 0.0
	_p._hurt_cast_key = ""
	_p._invincible = false
	_p._shield_hits = 0
	_p._skill_reflect = false
	_p._parry_ready = false
	_p._bell_shell = false
	_p.wu_che_wanted = false
	Run.mode = Run.MODE_ADVENTURE
	Run.difficulty = 1
	Run.depth = 1
	Run.guard_available = false


func _clear_summons() -> void:
	for e in _b._summons:
		if is_instance_valid(e):
			e.queue_free()
	_b._summons.clear()


func _test_difficulty() -> void:
	_reset_boss()
	var expected := [4, 5, 6, 6, 7]
	for i in expected.size():
		Run.difficulty = i
		_check(_b._durability_for_run() == expected[i], "冒险难度 %d 耐久为 %d" % [i, expected[i]])
	Run.mode = Run.MODE_ENDLESS
	Run.depth = 1
	_check(_b._durability_for_run() == 5, "无尽第 1 层为 5 点耐久")
	Run.depth = 3
	_check(_b._durability_for_run() == 6, "无尽第 3 层提升至 6 点耐久")
	Run.depth = 99
	_check(_b._durability_for_run() == 9, "无尽耐久增长设有 9 点上限")


func _test_startup_and_first_wall() -> void:
	_reset_boss()
	var hp_before: int = _b.hp
	_b.take_damage(20, 400.0)
	_b._direct_damage(2)
	_check(_b.hp == hp_before, "普通攻击与直接伤害均不削减耐久")
	_b.arena_right = 10000.0
	_b._start_charge()
	var start_x: float = _b.global_position.x
	_check(_b._current_anim == "skill01" and not _b._charge_ghost, "武撞从 6 号动画启动且启动期保持实体")
	_b._physics_process(0.5)
	_check(is_equal_approx(_b.global_position.x, start_x), "6 号动画启动阶段不产生位移")
	_b._physics_process(0.65)
	_check(_b._charge_ghost and _b.global_position.x > start_x, "6 号动画后段开始位移并切换虚体")
	_b._physics_process(1.7)
	_check(_b.state == _b.S_RUN and _b._current_anim == "speed_run", "6 号动画结束后无缝续接 10 号持续冲刺")
	_reset_boss()
	_b._start_charge()
	_b._physics_process(1.14)
	_b._physics_process(0.5)
	_b._physics_process(0.5)
	_check(_b.state == _b.S_BRAKE and _b._current_anim == "stop", "马头抵达地图边缘立即播放 12 号刹车")
	_check(is_equal_approx(_b.global_position.x, 1590.0), "刹车位置按马头而非车体原点贴边")
	_check(_b.hp == 5 and _b._charges_completed == 1, "第一次撞墙免费，不扣耐久")
	_check(not _b._charge_ghost, "开始刹车即恢复正常碰撞")
	_b._physics_process(0.81)
	_check(_b.state == _b.S_TURNING and _b._current_anim == "zhuanshen", "仍有耐久时刹车后播放 14 号掉头")
	_b._physics_process(1.41)
	_check(_b.facing == -1 and _b.state == _b.S_SUMMON and _b._current_anim == "skill02", "掉头后翻转朝向并播放 7 号召唤")
	_check(_b._summon_total == 3, "第一轮召唤总数为 3")


func _test_time_stop_interrupts() -> void:
	for chain_state in [_b.S_START, _b.S_RUN, _b.S_BRAKE, _b.S_TURNING, _b.S_SUMMON]:
		_reset_boss()
		_b.state = chain_state
		_b._charge_elapsed = 1.6
		_b._charge_moving = true
		_b._charge_contact_done = true
		_b._summon_total = 4
		_b._summon_index = 2
		_b._summon_elites_left = 1
		_b._state_timer = 1.0
		_b._set_ghost(chain_state == _b.S_START or chain_state == _b.S_RUN)
		_b.time_stop(1.0)
		await get_tree().process_frame
		_check(_b.state == _b.State.IDLE and _b._stop_timer > 0.0 and _b.velocity == Vector2.ZERO \
			and not _b._charge_moving and not _b._charge_ghost and not _b.get_node("CollisionShape2D").disabled \
			and _b._summon_total == 0 and _b._summon_index == 0 and _b._summon_elites_left == 0,
			"时停取消状态 %d 并清理冲锋、召唤与碰撞" % chain_state)
		var stopped_position: Vector2 = _b.global_position
		var stopped_facing: int = _b.facing
		_b._physics_process(0.5)
		_b._end_stop()
		_check(_b.state == _b.State.IDLE and _b.global_position == stopped_position and _b.facing == stopped_facing \
			and _b._charge_elapsed == 0.0 and _b._summons.is_empty(),
			"状态 %d 解冻后不会继续旧招或补发召唤" % chain_state)


func _test_contact_and_wanted() -> void:
	_reset_boss()
	_b._history_time = 2.5
	_b._position_history = [
		{"time": 0.0, "position": Vector2(500, 560)},
		{"time": 0.5, "position": Vector2(600, 560)},
		{"time": 2.5, "position": Vector2(960, 560)},
	]
	_p.global_position = Vector2(1000, 560)
	_b.state = _b.S_RUN
	_b._charge_ghost = true
	_b._wc_charge_dir = 1
	_b._charge_hit_check()
	_check(_p.hp == 97 and _p.wu_che_wanted, "武撞实伤 2 点并施加一层通缉")
	_check(_p.global_position.is_equal_approx(Vector2(600, 560)), "武撞实伤后传送至 2 秒前的位置")
	_check(_b._summon_bonus == 1, "武撞实伤为本轮召唤记录 1 个增员")
	_p.hp = 99
	_p._hurt_invincible = 0.0
	_p.global_position = Vector2(1000, 560)
	_b._charge_hit_check()
	_check(_p.hp == 99 and _p.global_position.is_equal_approx(Vector2(1000, 560)), "同一次武撞不会重复结算伤害或传送")
	var e = load("res://scenes/enemies/c016.tscn").instantiate()
	_room.add_child(e)
	e.set_physics_process(false)
	e.wu_che_summon = true
	_p.state = _p.State.IDLE
	_p._hurt_invincible = 0.0
	_p.hurt(1, Vector2.ZERO, e, {})
	_check(_p.hp == 97, "通缉使武车召唤物实伤额外 +1")
	e.wu_che_summon = false
	_p._hurt_invincible = 0.0
	_p.hurt(1, Vector2.ZERO, e, {})
	_check(_p.hp == 96, "通缉不会强化非武车召唤物")
	e.queue_free()
	_p.state = _p.State.DASH
	_p._hurt_invincible = 0.0
	_b._charge_contact_done = false
	_b._charge_hit_check()
	_check(_p.hp == 96 and not _p.wu_che_wanted, "闪避武撞不扣血并解除通缉")
	_check(_p.global_position.is_equal_approx(Vector2(600, 560)) and _b._summon_bonus == 1, "闪避接触仍传送但不会增加召唤数量")
	_check(_b._charge_contact_done, "闪避后同次武撞也不会再补判")
	_p.state = _p.State.IDLE
	_p._invincible = true
	_p.global_position = Vector2(1000, 560)
	_b._charge_contact_done = false
	_b._charge_hit_check()
	_check(_p.hp == 96 and _p.global_position.is_equal_approx(Vector2(600, 560)) and _b._summon_bonus == 1,
		"无敌防御接触也传送且不增员")
	await get_tree().process_frame


func _test_passives() -> void:
	_reset_boss()
	_b._history_time = 3.0
	_b._position_history = [
		{"time": 0.0, "position": Vector2(500, 560)},
		{"time": 1.0, "position": Vector2(-120, 560)},
		{"time": 1.5, "position": Vector2(700, 560)},
		{"time": 3.0, "position": Vector2(960, 560)},
	]
	_check(_b._charge_history_position().is_equal_approx(Vector2(0, 560)), "传送选取不晚于 2 秒前的位置并限制在场地内")
	_b._summon_bonus = 1
	_b._begin_wave()
	_check(_b._summon_total == 4 and _b._summon_elites_left == 1 and _b._summon_bonus == 0,
		"实伤增员把本轮 3 人提升至 4 人并重算精英名额")
	for i in 4:
		_b._summon_animation_finished()
	var elite_count := 0
	for e in _b._summons:
		e.set_physics_process(false)
		if bool(e.get("_elite")):
			elite_count += 1
	_check(_b._summons.size() == 4 and elite_count == 1, "增员后的 4 人波次实际生成 1 个精英")
	_clear_summons()
	_b._begin_wave()
	_check(_b._summon_total == 3, "实伤增员只作用于紧接着的本轮召唤")

	_reset_boss()
	var e = load("res://scenes/enemies/c016.tscn").instantiate()
	_room.add_child(e)
	e.set_physics_process(false)
	e._target = _p
	e.global_position = Vector2(400, 560)
	e.facing = 1
	e._attack_move = "skill02"
	e._attack_visual = "skill02"
	_p.global_position = Vector2(500, 560)
	for difficulty in [0, 4]:
		Run.difficulty = difficulty
		var base_damage := Run.enemy_damage(1)
		e.wu_che_summon = false
		_p.hp = 99
		_p._hurt_invincible = 0.0
		e._deal_hit()
		var normal_hp: int = _p.hp
		e.wu_che_summon = true
		_p.hp = 99
		_p._hurt_invincible = 0.0
		e._deal_hit()
		_check(normal_hp == 99 - base_damage and _p.hp == 99 - base_damage - 1,
			"难度 %d 的武车召唤物直接攻击始终高一档" % difficulty)
	e._attack_move = "skill01"
	e._attack_visual = "skill01"
	_p.hp = 99
	_p._hurt_invincible = 0.0
	e._deal_hit(0)
	_check(_p.hp == 99, "墨徒信仰不会给无直伤招式加伤")
	e.queue_free()


func _test_waves() -> void:
	_reset_boss()
	# 第二撞扣到 4 耐久，随后应召唤 4 个，其中第 4 个是精英。
	_b._charges_completed = 1
	_b._start_charge()
	_b._physics_process(1.14)
	_b._physics_process(0.5)
	_b._physics_process(0.5)
	_check(_b.hp == 4, "第二次撞墙消耗 1 点耐久")
	_b._physics_process(0.81)
	_b._physics_process(1.41)
	for i in 4:
		_b._physics_process(2.26)
	_check(_b._summons.size() == 4, "4 耐久时逐个播放召唤并生成 4 个敌人")
	var elites := 0
	for e in _b._summons:
		if bool(e.get("_elite")):
			elites += 1
		e.set_physics_process(false)
		_check(bool(e.get("wu_che_summon")), "第 %d 个召唤物带武车归属标记" % (_b._summons.find(e) + 1))
	_check(elites == 1, "4 个敌人固定包含 1 个精英")
	_b._enter_wait()
	_b._physics_process(0.016)
	_check(_b.state == _b.State.IDLE and _b._current_anim == "stand", "小怪未清完时保持待机，不会提前冲刺")
	_clear_summons()
	_b._physics_process(0.016)
	_check(_b.state == _b.S_START, "当前召唤波全灭后立即开始下一次武撞")
	for total in [5, 6, 7, 8]:
		_clear_summons()
		_b.hp = 8 - total # max_hp=5 时依次得到 5/6/7/8；8 人单独用 max_hp=7 下式复核
		if total == 8:
			_b.max_hp = 7
			_b.hp = 2
		_b._begin_wave()
		_check(_b._summon_total == total and int(_b._summon_total / 4) == int(total / 4), "%d 人波次的数量与精英名额正确" % total)
		for i in total:
			_b._summon_animation_finished()
		var elite_count := 0
		for e in _b._summons:
			if bool(e.get("_elite")):
				elite_count += 1
			e.set_physics_process(false)
		_check(_b._summons.size() == total and elite_count == int(total / 4), "%d 人波次实际精英数量为 %d" % [total, int(total / 4)])


func _test_charm_ally_isolation() -> void:
	_reset_boss()
	var ally = load("res://scenes/enemies/c016.tscn").instantiate()
	ally.player_ally = true
	_room.add_child(ally)
	ally.set_physics_process(false)
	ally.global_position = _p.global_position + Vector2(40, 0)
	_check(ally.is_in_group("player_allies") and not ally.is_in_group("enemies"), "魅唤使用独立友方阵营")
	_check(_b._summons.is_empty(), "外部魅唤不会进入武车自己的召唤列表")
	ally._find_target()
	_check(ally._target != null and ally._target.is_in_group("enemies") and ally._target != _p,
		"魅唤只索敌敌人而不追击玩家")
	var player_hp: int = _p.hp
	ally._target = _p
	ally._deal_hit()
	_check(_p.hp == player_hp, "魅唤旧招命中玩家也不会造成伤害")
	_b._start_charge()
	_check(_b.state == _b.S_START and _b._current_anim == "skill01", "魅唤存在时武车仍能立即开始冲锋")
	ally.queue_free()


func _test_edge_player() -> void:
	_reset_boss()
	# 先落稳，再让玩家贴在右墙并与停车后的车体略微重叠，复现物理恢复抬升。
	_b.state = _b.S_ENTER
	for i in 60:
		_b._physics_process(1.0 / 60.0)
	_p.global_position = Vector2(1816, _b.global_position.y)
	_p._invincible = true
	_b.state = _b.State.IDLE
	_b._start_charge()
	var frames := 0
	while _b.state != _b.S_BRAKE and frames < 600:
		_b._physics_process(1.0 / 60.0)
		frames += 1
	var parked_y: float = _b.global_position.y
	for i in 30:
		_b._physics_process(1.0 / 60.0)
	_check(is_equal_approx(_b.global_position.y, parked_y) and _b.is_on_floor() and not _b._charge_ghost,
		"玩家贴墙时停车恢复实体不会把武车抬到头顶")


func _test_idle_and_death() -> void:
	_reset_boss()
	_b.hp = 3
	_b._enter_wait()
	_check(_b._current_anim == "stand", "耐久损失不足一半时使用 11 号待机")
	_b.hp = 2
	_b._enter_wait()
	_check(_b._current_anim == "dead", "耐久损失达到一半时使用 4 号待机")
	_b.hp = 1
	_b._charges_completed = 2
	_b._start_charge()
	_b._physics_process(1.14)
	_b._physics_process(0.5)
	_b._physics_process(0.5)
	_check(_b.hp == 0 and _b.state == _b.S_BRAKE, "最后一点耐久在撞墙时耗尽且先完成刹车")
	_p.wu_che_wanted = true
	_b._physics_process(0.81)
	_check(_b.state == _b.State.DEAD and _b._current_anim == "atked_fall_end", "耐久归零后播放 2 号阵亡动画")
	_check(not _p.wu_che_wanted, "武车死亡清除通缉")
