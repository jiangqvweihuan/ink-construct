extends Node

## 墨霆专项回归：真实 Boss 房先导 + 独立状态机的伤害帧、机制与清理链路。

const OUT_DIR := "res://tests/out/"
const CHASE := 2
const DEAD := 5

var _log: FileAccess
var _room
var _b
var _p
var _checks := 0
var _failed := 0


func p(msg) -> void:
	print("[MT] ", msg)
	if _log:
		_log.store_line("[MT] " + str(msg))
		_log.flush()


func _check(ok: bool, label: String) -> void:
	_checks += 1
	if not ok:
		_failed += 1
	p(("PASS " if ok else "FAIL ") + label)


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	_log = FileAccess.open("res://tests/mo_ting_test.log", FileAccess.WRITE)
	get_tree().create_timer(45.0).timeout.connect(func():
		p("TIMEOUT")
		get_tree().quit(2)
	)
	Run.start()
	Run.room_index = Run.ROOMS.size()
	Run.boss_id = "c009"
	Run.boss_queue = ["c009"]
	_room = load("res://scenes/world/room_01.tscn").instantiate()
	add_child(_room)
	_b = _room._boss
	_p = _room._player
	var intro = _room.get_node_or_null("BossDuelIntro")
	_check(intro != null, "C009 创建黑底对峙先导")
	_check(_b.state == _b.S_ENTER and not _b.is_physics_processing(), "先导期间 Boss 锁定在登场状态")
	_check(not _p.is_physics_processing() and not _p.visible and not _b.visible, "先导期间双方实体隐藏并停物理")
	await _shot("mo_ting_intro")
	if intro != null:
		await intro.finished
	_check(_p.visible and _b.visible and _p.is_physics_processing() and _b.is_physics_processing(), "先导结束恢复双方显示与物理")
	_check(_b.state == CHASE and is_zero_approx(_b._battle_time), "先导结束进入追击并重置开局计时")

	# 后续直接驱动独立状态机，避免重力和自主选招污染精确伤害帧断言。
	_b.set_physics_process(false)
	_p.set_physics_process(false)
	_test_break_and_passives()
	_test_basic()
	_test_tremor()
	_test_rush()
	_test_slam_and_leap()
	_test_laser()
	_test_move_selection()
	_test_death_cleanup()
	p("DONE checks=%d failed=%d" % [_checks, _failed])
	get_tree().quit(1 if _failed > 0 else 0)


func _reset_all(player_hp := 99, player_max := 99) -> void:
	_b._cleanup_cast()
	_b._end_stop()
	_b.state = CHASE
	_b.max_hp = 120
	_b.hp = 120
	_b._invincible = false
	_b._attack_cd = 0.0
	_b._battle_time = 10.0
	_b._attack_desire = 5.0
	_b._approach_yield = 0.0
	_b._recent_hits.clear()
	_b.cd_scale = 1.0
	for move in _b.MOVE_ORDER:
		_b._move_cds[move] = 0.0
	_b.global_position = Vector2(800, 560)
	_b.velocity = Vector2.ZERO
	_b.facing = -1
	_b._apply_facing()
	_b._target = _p
	_p.global_position = Vector2(460, 560)
	_p.velocity = Vector2.ZERO
	_p.max_hp = player_max
	_p.hp = player_hp
	_p.state = 0
	_p._hurt_phase = ""
	_p._hurt_timer = 0.0
	_p._hurt_invincible = 0.0
	_p._hurt_cast_key = ""
	_p._hurt_chain.clear()
	_p._invincible = false
	_p._damage_reduce = 0
	_p._shield_hits = 0
	_p._parry_ready = false
	_p._bell_shell = false
	_p._skill_reflect = false
	_p._mo_ting_grabbed = false
	_p._mo_ting_burn_stacks = 0
	_p._mo_ting_burn_time = 0.0
	_p._cripple_time = 0.0
	Run.active = false
	Run.difficulty = 1
	Run.guard_available = false


func _test_break_and_passives() -> void:
	_reset_all()
	_b._battle_time = 0.0
	_b.take_damage(5, 460.0)
	_check(_b.state == CHASE and _b.hp == 115 and _b.max_hp == 115, "5 伤不破招，失心疯同步扣上限并保持满血")
	_b.take_damage(6, 460.0)
	_check(_b.state == _b.S_BREAK and _b._current_anim == "def_break", "单次 6 伤触发动画 3 破招")

	_reset_all()
	_b._battle_time = 0.0
	for i in 4:
		_b.take_damage(1, 460.0)
	_check(_b.state == CHASE, "2 秒内前 4 次攻击不破招")
	_b.take_damage(1, 460.0)
	_check(_b.state == _b.S_BREAK, "2 秒内第 5 次攻击破招")

	_reset_all()
	_b._battle_time = 0.0
	_b.take_damage(1, 460.0)
	_b._battle_time = 2.1
	for i in 4:
		_b.take_damage(1, 460.0)
	_check(_b.state == CHASE, "超过 2 秒的旧攻击不计入五击窗口")
	_b.take_damage(1, 460.0)
	_check(_b.state == _b.S_BREAK, "新窗口累计五击后正常破招")

	_reset_all()
	_b.apply_bleed(5)
	_b.apply_poison(5.0)
	_b.root(2.0, true)
	_b.stun(2.0, true)
	_b.slow(2.0, 0.4, true)
	var old_pos: Vector2 = _b.global_position
	_b.launch(1, 500.0, 500.0, true)
	_b.knock_back(1, 900.0, 2, true)
	_check(_b._bleed_stacks == 0 and _b._poison_time == 0.0, "机关造物免疫流血与中毒")
	_check(_b._root_timer == 0.0 and _b._stun_timer == 0.0 and _b._slow_timer == 0.0, "机关造物免疫普通定身、晕眩与余滞")
	_check(_b.global_position == old_pos and _b.velocity == Vector2.ZERO, "机关造物免疫击飞与击退")
	_b._start_mo_move(_b.TREMOR)
	_check(is_instance_valid(_b._marker), "墨颤起手生成红点")
	_b.time_stop(1.0)
	_check(_b._stop_timer == 1.0 and _b.state == CHASE and _b._marker == null, "时间暂停优先级最高并清理当前招式")

	_reset_all()
	_b.on_player_hit(2, {}, _p)
	_check(_b.max_hp == 121 and _b.hp == 121, "失心疯每次真实伤害只增加 1 点上限")
	_b.on_player_hit(0, {}, _p)
	_check(_b.max_hp == 121, "无直伤特殊命中不增加上限")
	_b._direct_damage(7)
	_check(_b.max_hp == 114 and _b.hp == 114, "持续直扣也同样失去等量上限")


func _test_basic() -> void:
	_reset_all()
	_b._start_mo_move(_b.BASIC)
	_b._cast_tick(0.62)
	_check(_p.hp == 99, "奋挥首段 0.63 秒前不提前出伤")
	_b._cast_tick(0.02)
	_check(_p.hp == 98, "奋挥首段造成 1 伤")
	_b._cast_tick(0.87)
	_check(_p.hp == 98, "奋挥第二段前摇无伤害")
	_b._cast_tick(0.02)
	_check(_p.hp == 97, "奋挥第二段造成 1 伤并穿透同招收招无敌")
	_b._cast_tick(1.07)
	_check(_p.hp == 97, "奋挥蓄力阶段不提前出伤")
	_b._cast_tick(0.01)
	_check(_p.hp == 94, "奋挥最后蓄力一击造成 3 伤")
	_check(_b.max_hp == 123, "奋挥三次实伤各触发一次失心疯")


func _test_tremor() -> void:
	_reset_all(12, 20)
	Run.active = true
	Run.max_hp = 20
	Run.hp = 12
	_b._start_mo_move(_b.TREMOR)
	_p.global_position.x = 520.0
	_b._cast_tick(0.5)
	_check(is_equal_approx(_b._marker.global_position.x, 520.0), "墨颤举手期间红点跟随玩家")
	_p.global_position.x = 580.0
	_b._cast_tick(0.75)
	_b._cast_tick(0.02)
	var locked_x: float = _b._marker.global_position.x
	_p.global_position.x = 700.0
	_b._cast_tick(0.34)
	_check(_b._marker_locked and is_equal_approx(_b._marker.global_position.x, locked_x), "机关垂手后红点停止跟踪")
	_p.global_position.x = locked_x
	_b._cast_tick(0.02)
	_check(_p._mo_ting_grabbed and _b._marker == null, "落手时站在红点内会被抓取且红点消失")
	_check(_p.global_position.distance_to(_b.global_position + Vector2(-190, -180)) < 0.01, "抓取落点正对机关上方的操控者")
	_b._cast_tick(0.84)
	_check(_p.hp == 12, "墨颤刺击前不扣当前生命")
	_b._cast_tick(0.01)
	_check(_p.hp == 10 and _b.max_hp == 121, "墨颤先刺击造成 2 伤")
	_b._cast_tick(0.44)
	_check(_p.max_hp == 10 and _p.hp == 10 and Run.max_hp == 10, "滑斩把玩家与 Run 的生命上限削至当前生命")
	_b._cast_tick(0.44)
	_check(_p.max_hp == 10 and _b.max_hp == 121, "后续滑斩不重复削上限也不触发失心疯")
	_b._finish_cast()
	_check(not _p._mo_ting_grabbed, "墨颤收招释放玩家定点")

	_reset_all()
	_b._start_mo_move(_b.TREMOR)
	_b._cast_tick(1.27)
	_p.global_position.x = 1200.0
	_b._cast_tick(0.36)
	_check(not _p._mo_ting_grabbed, "落手时已离开红点的玩家不会被抓取")


func _test_rush() -> void:
	_reset_all()
	_b.global_position.x = 500.0
	_b.facing = 1
	_p.global_position.x = 900.0
	_b._start_mo_move(_b.RUSH)
	_check(is_equal_approx(_b._move_cds[_b.RUSH], 35.0), "墨冲冷却已调整为 35 秒")
	_b._cast_tick(1.60)
	_check(_p.hp == 99 and is_zero_approx(_b.velocity.x), "墨冲蓄力期间不位移也不出伤")
	_b._cast_tick(0.03)
	_check(_p.hp == 99 and is_equal_approx(_b.velocity.x, 620.0), "墨冲在 1.62 秒蓄力结束后才开始高速位移与伤害")
	_p.global_position.x = 710.0
	_b._cast_tick(0.5)
	_check(_p.hp == 97 and _p._hurt_phase != "", "玩家进入墨冲范围受到 2 伤并触发已有倒地动作")
	_b._cast_tick(0.5)
	_check(_p.hp == 95, "墨冲每 0.5 秒续伤不被同招受伤无敌吞掉")


func _test_slam_and_leap() -> void:
	_reset_all()
	_b._start_mo_move(_b.SLAM)
	_b._cast_tick(1.47)
	_check(_p.hp == 99 and _p._cripple_time == 0.0, "断岳蓄力阶段不提前出伤或致残")
	_b._cast_tick(0.02)
	_check(_p.hp == 94 and is_equal_approx(_p._cripple_time, 5.0), "断岳砸地造成 5 伤并附加 5 秒致残")
	var slam_crack := get_tree().current_scene.get_child(get_tree().current_scene.get_child_count() - 1)
	_check(slam_crack.get_script() == load("res://scripts/systems/fx.gd") and slam_crack.global_position.is_equal_approx(Vector2(560, 560)), "断岳地裂生成在身前拍地点而非 Boss 脚底")
	_p._jump_buf = 0.1
	_p._coyote = 0.1
	_p._try_jump()
	_check(_p.state != 2, "致残封锁空格跳跃")

	_reset_all()
	_b.global_position.x = 500.0
	_b.facing = 1
	_p.global_position.x = 1100.0
	_b._start_mo_move(_b.LEAP)
	_check(_b._cast_visual == "skill08", "中距离陨构选择动画 12 小跳")
	_b._cast_tick(0.17)
	_check(_b.velocity.y == 0.0 and _p.hp == 99, "陨构起跳前不位移也不出伤")
	_b._cast_tick(0.02)
	_check(_b.velocity.y < 0.0 and _p.hp == 99, "陨构起跳后仍未到落地伤害帧")
	_p.global_position.x = 700.0
	_b._cast_tick(1.09)
	_check(_p.hp == 95 and is_equal_approx(_p._cripple_time, 5.0), "陨构落地造成 4 伤并致残")
	var leap_crack := get_tree().current_scene.get_child(get_tree().current_scene.get_child_count() - 1)
	_check(leap_crack.get_script() == load("res://scripts/systems/fx.gd") and leap_crack.global_position.is_equal_approx(Vector2(740, 560)), "陨构地裂生成在身前落地点而非 Boss 脚底")

	_reset_all()
	_b.global_position.x = 500.0
	_b.facing = 1
	_p.global_position.x = 1350.0
	_b._start_mo_move(_b.LEAP)
	_check(_b._cast_visual == "skill08-cankao", "远距离陨构选择动画 16 大跳")
	_p.global_position.x = 100.0
	_b._cast_tick(1.29)
	_check(_p.hp == 99 and _p._cripple_time == 0.0, "落地时已离开范围的玩家不吃伤害与致残")


func _test_laser() -> void:
	_reset_all()
	_b.global_position.x = 500.0
	_b.facing = 1
	_p.global_position.x = 1750.0
	_b._start_mo_move(_b.LASER)
	_b._cast_tick(0.84)
	_check(_p.hp == 99 and _b._laser == null, "贯昼短蓄力期间不提前发射")
	_b._cast_tick(0.02)
	_check(_p.hp == 98 and is_instance_valid(_b._laser), "贯昼正前方延伸至地图远端并立即造成 1 伤")
	_check(_b._laser.global_position.is_equal_approx(Vector2(620, 445)), "贯昼可见光束从身前 120px 的发射点起始")
	_b._cast_tick(0.5)
	_b._cast_tick(0.5)
	_check(_p.hp == 96 and _p._mo_ting_burn_stacks == 3, "贯昼每 0.5 秒续伤并累积灼烧")
	_check(_p.mo_ting_laser_damage() == 2, "三层灼烧使后续激光基础伤害增至 2")
	_b._cast_tick(0.5)
	_check(_p.hp == 94 and _p._mo_ting_burn_stacks == 4, "第四次激光按递增后的 2 伤结算")
	_p._mo_ting_burn_tick(6.1)
	_check(_p._mo_ting_burn_stacks == 0 and _p.mo_ting_laser_damage() == 1, "六秒未再命中后灼烧清零")
	_b.time_stop(1.0)
	_check(_b._laser == null, "时停打断贯昼会清理激光")

	_reset_all()
	_b.global_position.x = 500.0
	_b.facing = 1
	_p.global_position.x = 600.0
	_b._start_mo_move(_b.LASER)
	_b._cast_tick(0.86)
	_check(_p.hp == 99 and is_instance_valid(_b._laser), "贯昼身前 80～120px 不再被不可见光束命中")
	_p.global_position.x = 620.0
	_b._continuous_hit()
	_check(_p.hp == 98, "贯昼从可见光束起点 120px 开始结算伤害")


func _test_move_selection() -> void:
	_reset_all()
	_b._battle_time = 4.99
	_b._attack_desire = 0.0
	_b._chase_tick(0.016)
	_check(_b._cast_move.is_empty() and is_zero_approx(_b.velocity.x) and _b._current_anim == "stand", "欲望未满且距离合适时停走待机")
	_b._battle_time = 5.0
	_b._attack_desire = 5.0
	_b._chase_tick(0.016)
	_check(_b._cast_move == _b.TREMOR, "公共欲望满 5 秒且冷却完成时优先墨颤")
	_check(is_zero_approx(_b._attack_desire) and is_zero_approx(_b._approach_yield), "墨霆每次起手重置公共欲望与忍让计数")
	_b._finish_cast()
	_b._attack_desire = 2.0
	_b._chase_tick(0.016)
	_check(_b._cast_move.is_empty() and is_zero_approx(_b.velocity.x) and _b._current_anim == "stand", "墨霆收招后在保距带内待机而非一直后退")
	_b.cd_scale = 0.5
	_b._start_mo_move(_b.TREMOR)
	_check(is_equal_approx(_b._move_cds[_b.TREMOR], 15.0), "无尽冷却倍率在起手时一次性正确缩放")

	_reset_all()
	_b._attack_desire = 0.0
	_b._move_cds[_b.TREMOR] = 1.0
	_p.global_position.x = 1000.0
	_p.velocity.x = -200.0
	_b._chase_tick(1.5)
	_check(_b._cast_move.is_empty() and _b.velocity.x < 0.0, "墨霆面对逼近先忍让一段距离")
	_check(is_equal_approx(_b._approach_yield, 120.0), "墨霆单轮忍让最多 120px")
	_b._chase_tick(0.016)
	_check(_b._cast_move == _b.LEAP and is_zero_approx(_b._attack_desire), "持续冒进使墨霆立即满欲望并释放当前招")

	_reset_all()
	_b._attack_desire = 2.0
	_p.global_position.x = 1400.0
	_p.velocity.x = 200.0
	_b._chase_tick(0.5)
	_check(is_equal_approx(_b._attack_desire, 3.0) and _b.velocity.x > 0.0, "墨霆追击后退玩家时以 2 倍速度累计欲望")
	_p.global_position.x = 1180.0
	_p.velocity.x = 0.0
	_b._chase_tick(0.5)
	_check(is_equal_approx(_b._attack_desire, 3.5) and is_zero_approx(_b.velocity.x) and _b._current_anim == "stand", "墨霆相持时恢复 1 倍欲望并保持待机")

	_reset_all()
	_b._move_cds[_b.TREMOR] = 1.0
	_b._chase_tick(0.016)
	_check(_b._cast_move.is_empty() and _b.velocity.x > 0.0, "陨构就绪时近身主动后退拉距")
	_b.global_position.x = 1000.0
	_b._chase_tick(0.016)
	_check(_b._cast_move == _b.LEAP, "陨构达到 520 距离后立即释放")

	_reset_all()
	_b._move_cds[_b.TREMOR] = 1.0
	_b._move_cds[_b.LEAP] = 1.0
	_b._chase_tick(0.016)
	_check(_b._cast_move.is_empty() and _b.velocity.x > 0.0, "墨冲就绪时近身主动后退拉距")
	_b.global_position.x = 900.0
	_b._chase_tick(0.016)
	_check(_b._cast_move == _b.RUSH, "墨冲达到 431 距离后立即释放")

	_reset_all()
	_p.global_position.x = 500.0
	_b._move_cds[_b.TREMOR] = 1.0
	_b._move_cds[_b.LEAP] = 1.0
	_b._move_cds[_b.RUSH] = 1.0
	_b._chase_tick(0.016)
	_check(_b._cast_move.is_empty() and _b.velocity.x > 0.0, "贯昼就绪时近身主动后退拉距")
	_b.global_position.x = 840.0
	_b._chase_tick(0.016)
	_check(_b._cast_move == _b.LASER, "贯昼达到 340 距离后立即释放")

	for case in [
		{"move": _b.LEAP, "label": "陨构"},
		{"move": _b.RUSH, "label": "墨冲"},
		{"move": _b.LASER, "label": "贯昼"},
	]:
		_reset_all()
		_b.global_position.x = 700.0
		_p.velocity.x = 200.0
		_b._move_cds[_b.TREMOR] = 1.0
		for ranged in [_b.LEAP, _b.RUSH, _b.LASER]:
			_b._move_cds[ranged] = 1.0
		_b._move_cds[case["move"]] = 0.0
		_b._chase_tick(0.016)
		_check(_b._cast_move == case["move"], "%s 后退拉距时被玩家追逼至 260px 内立即释放" % case["label"])


func _test_death_cleanup() -> void:
	_reset_all()
	_b._start_mo_move(_b.TREMOR)
	_b._cast_tick(1.63)
	_check(_p._mo_ting_grabbed, "死亡清理前建立真实抓取")
	_b.take_damage(999, 460.0)
	_check(_b.state == DEAD and _b.hp == 0, "墨霆失去全部上限后死亡")
	_check(not _p._mo_ting_grabbed and _b._marker == null and _b._laser == null, "死亡释放抓取并清理所有招式残留")


func _shot(tag: String) -> void:
	await get_tree().process_frame
	RenderingServer.force_draw()
	var img = get_viewport().get_texture().get_image()
	if img == null:
		p("screenshot unavailable " + tag)
		return
	var err = img.save_png(OUT_DIR + tag + ".png")
	p("saved " + tag + " err=" + str(err))
