extends Node

## 碎岳专项回归：真实 C008 Boss 房、四招伤害帧、佛眼、双被动与公共攻击节奏。

const OUT_DIR := "res://tests/out/"
const BossTypes := preload("res://scripts/enemies/boss_types.gd")
const CHASE := 2
const DEAD := 5

var _log: FileAccess
var _room
var _b
var _p
var _checks := 0
var _failed := 0
var _saved_forms: Dictionary = {}
var _saved_mastery: Dictionary = {}


func p(msg) -> void:
	print("[SY] ", msg)
	if _log:
		_log.store_line("[SY] " + str(msg))
		_log.flush()


func _check(ok: bool, label: String) -> void:
	_checks += 1
	if not ok:
		_failed += 1
	p(("PASS " if ok else "FAIL ") + label)


func _ready() -> void:
	Run.balance_scaling = false # 机制用例固定原始伤害数值，人数缩放由 enemy_balance_probe 覆盖
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	_log = FileAccess.open("res://tests/sui_yue_test.log", FileAccess.WRITE)
	Meta.persist = false
	_saved_forms = Meta.form_nodes.duplicate(true)
	_saved_mastery = Meta.mastery.duplicate(true)
	Meta.form_nodes = {}
	get_tree().create_timer(60.0).timeout.connect(func():
		p("TIMEOUT")
		get_tree().quit(2)
	)
	Run.active = true
	Run.mode = Run.MODE_ADVENTURE
	Run.difficulty = 1
	Run.depth = 1
	Run.room_index = Run.ROOMS.size()
	Run.boss_id = "c008"
	Run.boss_queue = ["c008"]
	Run.boss_defeated = []
	Run.boss_phase = 0
	Run.skull_id = "c021"
	Run.upgrades = {"damage": 3, "cooldown": 2, "hp": 3, "dash": 2, "dodge": 2}
	Run.max_hp = 11 + Meta.start_hp_bonus()
	Run.hp = Run.max_hp
	Run.max_hp_loss = 0
	Run.blessing = ""
	Run.supply_hp = 0
	Run.guard_available = false
	Meta.form_nodes["c021_combo_1"] = true
	_room = load("res://scenes/world/room_01.tscn").instantiate()
	add_child(_room)
	_b = _room._boss
	_p = _room._player
	_check(_b.get_script() == load("res://scripts/enemies/sui_yue.gd"), "正式房间使用碎岳独立战斗脚本")
	var intro = _room.get_node_or_null("BossDuelIntro")
	_check(intro != null, "C008 创建黑底对峙先导")
	_check(_b.state == _b.S_ENTER and not _b.is_physics_processing(), "先导期间碎岳锁定登场并停物理")
	_check(_b._current_anim == "stand" and BossTypes.get_boss("c008")["intro"] == {"anim": "stand", "loop": true}, "碎岳实体与挑战界面均使用循环待机")
	_check(_p._sui_yue_pressure and _p.damage_bonus == 0 and _p.cooldown_scale == 1.0, "进房即压制局内加伤与冷却增益")
	_check(_p.max_hp == 8 and not _p._form_node("c021_combo_1"), "进房生命与永久修炼均被邪佛压制")
	_check(BossTypes.get_boss("c008")["anim"] == {"idle": "stand", "patrol": "run", "chase": "run", "hurt": "def_break", "dead": "atked_fall_end"}, "受击移动与倒地动画保持原配置")
	await _shot("sui_yue_room")
	if intro != null:
		await intro.finished
	_check(_b.state == CHASE and is_zero_approx(_b._attack_desire), "先导结束恢复追击且攻击欲望从零累计")
	_b._set_state(CHASE)

	_b.set_physics_process(false)
	_p.set_physics_process(false)
	_test_natural_timeline()
	_test_attack_desire()
	_test_arms()
	_test_crusher()
	await _test_hands()
	_test_eye()
	_test_bell()
	_test_pressure_and_seal()
	_test_status_effects()
	_test_uninterruptible()
	_test_cleanup()
	Meta.battle_passives.erase("test_sui_future")
	Meta.battle_passives.erase("test_sui_future_two")
	Meta.form_nodes = _saved_forms
	Meta.mastery = _saved_mastery
	p("DONE checks=%d failed=%d" % [_checks, _failed])
	get_tree().quit(1 if _failed > 0 else 0)


func _reset_all(player_hp := 99) -> void:
	Run.active = false
	Run.difficulty = 1
	Run.guard_available = false
	_b._cleanup_cast()
	_b._return_eye()
	_b._end_stop()
	_b.state = CHASE
	_b.max_hp = 64
	_b.hp = 64
	_b._invincible = false
	_b._bleed_stacks = 0
	_b._bleed_time = 0.0
	_b._bleed_acc = 0.0
	_b._poison_time = 0.0
	_b._poison_acc = 0.0
	_b._slow_timer = 0.0
	_b._slow_scale = 1.0
	_b._attack_desire = 5.0
	_b._approach_yield = 0.0
	_b._retreat_left = 0.0
	_b._planned_move = ""
	_b._bell_layers.clear()
	_b.cd_scale = 1.0
	for move in _b.MOVE_ORDER:
		_b._move_cds[move] = 0.0
	_b.global_position = Vector2(800, 560)
	_b.velocity = Vector2.ZERO
	_b.facing = -1
	_b._apply_facing()
	_b._target = _p
	_p.clear_sui_yue_effects()
	_p.set_upgrades({})
	_p.global_position = Vector2(500, 560)
	_p.velocity = Vector2.ZERO
	_p.max_hp = 99
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
	_p._skill_poise = false
	_p.poise = false
	_p._cripple_time = 0.0
	_p._room_awaken_damage = 0
	_p._awaken_stacks = 0
	_p._awaken_buff_damage = 0
	_p._buff_damage = 0
	_p._buff_timer = 0.0
	_p._stop_buff_damage = 0
	_p._stop_buff_timer = 0.0
	Meta.battle_passives.clear()
	Meta.form_nodes.clear()


func _test_natural_timeline() -> void:
	_reset_all(99999)
	_p.max_hp = 99999
	_p.global_position.x = 560.0
	_b._attack_desire = 4.9
	var eye_starts: Array = []
	var starts := 0
	var rhythm_violations := 0
	var retreated := true
	var previous_cast: int = _b._cast_id
	for i in range(2400):
		_b._physics_process(0.05)
		if _b._cast_id != previous_cast:
			previous_cast = _b._cast_id
			starts += 1
			if not retreated:
				rhythm_violations += 1
			retreated = false
			if _b._cast_move == _b.EYE:
				eye_starts.append(snappedf((i + 1) * 0.05, 0.01))
		if _b.state == _b.S_RETREAT:
			retreated = true
		if eye_starts.size() >= 2:
			break
	p("natural-eye-starts=" + str(eye_starts) + " all-starts=" + str(starts))
	_check(eye_starts.size() >= 2, "连续自然战斗能再次释放佛眼")
	if eye_starts.size() >= 2:
		_check(float(eye_starts[1]) - float(eye_starts[0]) >= 50.0, "佛眼两次自然起手间隔不少于 50 秒")
	_check(starts >= 4 and rhythm_violations == 0, "自然战斗每次收招后都经过后撤才再起招")


func _test_attack_desire() -> void:
	_reset_all()
	_p.global_position.x = 440.0
	_b._attack_desire = 0.0
	_b._chase_tick(0.016)
	_check(_b._cast_move.is_empty() and is_zero_approx(_b.velocity.x) and _b._current_anim == "stand", "保距带内停走待机 anim=%s vel=%s cast=%s" % [_b._current_anim, _b.velocity.x, _b._cast_move])
	_check(is_equal_approx(_b._attack_desire, 0.016), "相持按 1 倍速度累计攻击欲望")

	_reset_all()
	_b._attack_desire = 0.0
	_p.global_position.x = 1000.0
	_p.velocity.x = -200.0
	_b._chase_tick(1.5)
	_check(_b._cast_move.is_empty() and _b.velocity.x < 0.0, "玩家逼近时先向后排让")
	_check(is_equal_approx(_b._approach_yield, 120.0), "单轮逼近最多忍让 120px")
	_b._chase_tick(0.016)
	_b._chase_tick(0.016)
	_check(_b._planned_move == _b.EYE and _b._cast_move.is_empty(), "继续冒进只预选近身佛眼，不在范围外空挥")
	_p.global_position.x = 930.0
	_b._chase_tick(0.016)
	_check(_b._cast_move == _b.EYE and is_zero_approx(_b._attack_desire), "冒进预选佛眼后贴近到范围中段再出手")
	_b._finish_cast()
	_check(_b.state == _b.S_RETREAT and _b._planned_move.is_empty(), "收招进入后撤并清空上一轮预选")
	var cast_id: int = _b._cast_id
	_b._physics_process(0.05)
	_check(_b._cast_id == cast_id and _b.velocity.x < 0.0 and is_zero_approx(_b._attack_desire), "后撤期间不立即连击也不累积攻击欲望")
	_b._retreat_tick(_b.RETREAT_TIME)
	_b._attack_desire = 2.0
	_p.global_position.x = 440.0
	_p.velocity.x = 0.0
	_b._chase_tick(0.1)
	_check(_b.state == CHASE and _b._cast_move.is_empty() and is_zero_approx(_b.velocity.x), "后撤结束才重新进入相持积欲望")

	_reset_all()
	_b._attack_desire = 2.0
	_p.global_position.x = 1300.0
	_p.velocity.x = 200.0
	_b._chase_tick(0.5)
	_check(is_equal_approx(_b._attack_desire, 3.0) and _b.velocity.x > 0.0, "玩家后退时追逼并以 2 倍累计欲望")
	_p.global_position.x = 1120.0
	_p.velocity.x = 0.0
	_b._chase_tick(0.25)
	_check(is_equal_approx(_b._attack_desire, 3.25) and is_zero_approx(_b.velocity.x), "重新相持后恢复 1 倍欲望并停走")
	_b._attack_desire = 5.0
	_b._chase_tick(0.016)
	_check(_b._planned_move == _b.EYE and _b._cast_move.is_empty() and _b.velocity.x > 0.0, "欲望满后先选佛眼，距离不足只接近不出手")
	_p.global_position.x = 1020.0
	_b._chase_tick(0.016)
	_check(_b._cast_move.is_empty() and _b._planned_move == _b.EYE and _b.velocity.x > 0.0, "佛眼最大射程边缘不再提前起手")
	_p.global_position.x = 940.0
	_b._chase_tick(0.016)
	_check(_b._cast_move == _b.EYE, "佛眼贴近到实际范围中段后才正式出手")

	_reset_all()
	_b._move_cds[_b.EYE] = 50.0
	_b._attack_desire = _b.ATTACK_DESIRE_TIME
	_p.global_position.x = 1100.0
	_b._chase_tick(0.016)
	_check(_b._planned_move == _b.HANDS and _b._cast_move.is_empty() and _b.velocity.x > 0.0, "万佛手玩家仍在真实射程外时继续接近")
	_check(_b._current_anim == "run" and is_equal_approx(_b._current_anim_speed, _b.MOVE_ANIM_SPEED), "碎岳追击动画按 1.3 倍速度播放")
	_p.global_position.x = 1090.0
	_b._chase_tick(0.016)
	_check(_b._cast_move.is_empty() and _b._planned_move == _b.HANDS, "万佛手最大射程边缘仍继续贴近")
	_p.global_position.x = 960.0
	_b._chase_tick(0.016)
	_check(_b._cast_move == _b.HANDS, "万佛手进入实际范围中段后才起手")
	_b._cast_tick(2.17)
	_check(_p.hp == 98, "万佛手贴近后首段能命中保持不动的玩家")


func _test_arms() -> void:
	_reset_all(8)
	_b._start_sui_move(_b.ARMS)
	_check(_b.ARMS == "skill04" and _b._current_anim == "skill04", "掷臂使用 9 号动画 skill04")
	_check(is_zero_approx(float(_b._move_cds[_b.ARMS])) and _b._bell_layers.is_empty(), "普攻无独立冷却不获得金钟")
	_b._cast_tick(0.91)
	_check(_p.hp == 8 and is_zero_approx(_p._passive_seal_time), "双臂发射前不提前出伤或剥离")
	_b._cast_tick(0.01)
	_check(_p.hp == 5 and is_equal_approx(_p._passive_seal_time, 15.0), "掷臂造成 3 伤并附加 15 秒剥离")
	_check(_p._passives_disabled(), "剥落实伤后禁止被动")


func _test_crusher() -> void:
	_reset_all()
	_b._start_sui_move(_b.CRUSHER)
	_check(_b.CRUSHER == "skill03" and _b._current_anim == "skill03", "崩坛使用 7 号动画 skill03")
	_check(is_equal_approx(float(_b._move_cds[_b.CRUSHER]), 24.0), "崩坛冷却 24 秒")
	_check(_b._bell_layers == [2], "崩坛起手获得一层两次金钟")
	_b._cast_tick(0.70)
	_check(_p.hp == 99, "踢击前不提前出伤")
	_b._cast_tick(0.01)
	_check(_p.hp == 97 and is_zero_approx(_p._cripple_time), "踢击造成 2 伤且不附加致残")
	_b._cast_tick(0.63)
	_check(_p.hp == 97, "砸落前不追加第二段")
	_b._cast_tick(0.02)
	_check(_p.hp == 94 and is_equal_approx(_p._cripple_time, 5.0), "砸落造成 3 伤并附加 5 秒致残 hp=%d cripple=%s" % [_p.hp, _p._cripple_time])
	_reset_all()
	_b.cd_scale = 0.5
	_b._start_sui_move(_b.CRUSHER)
	_check(is_equal_approx(float(_b._move_cds[_b.CRUSHER]), 12.0), "无尽冷却倍率只在起手时缩放一次")


func _test_hands() -> void:
	_reset_all()
	_p.global_position.x = 560.0
	_b._start_sui_move(_b.HANDS)
	_check(_b.HANDS == "skill02" and _b._current_anim == "skill02", "万佛手使用 6 号动画 skill02")
	_check(is_equal_approx(float(_b._move_cds[_b.HANDS]), 30.0), "万佛手冷却 30 秒")
	_b._cast_tick(2.15)
	_check(_p.hp == 99, "万佛手首次落手前不提前出伤")
	var times := [0.02, 0.45, 0.45, 0.45, 0.45]
	for i in range(times.size()):
		_b._cast_tick(float(times[i]))
		_check(_p.hp == 98 - i and is_equal_approx(_p._stun_time, 0.5), "落手段第 %d 击造成 1 伤并附加 0.5 秒眩晕" % (i + 1))
	_check(_p._hurt_invincible > 0.0, "末段后仍存在受伤无敌以检验同招穿透")
	var guard := 0
	while _p.state == _p.State.HURT and guard < 40:
		_p._physics_process(0.05)
		guard += 1
	_check(_p.state != _p.State.HURT and is_equal_approx(_p._stun_time, 0.5), "受击动画结束后仍保留完整 0.5 秒眩晕")
	Input.action_press("move_right")
	_p.velocity.x = 0.0
	_p._physics_process(0.05)
	_check(is_zero_approx(_p.velocity.x) and _p._stun_time > 0.4, "眩晕期间移动输入不能推动角色")
	for i in range(9):
		_p._physics_process(0.05)
	_check(is_zero_approx(_p._stun_time), "起身后的操作锁按真实时间结束")
	_p._physics_process(0.05)
	_check(_p.velocity.x > 0.0, "眩晕结束后移动输入立即恢复")
	Input.action_release("move_right")
	await _shot("sui_yue_hands")


func _test_eye() -> void:
	_reset_all()
	Run.active = true
	Run.max_hp = 99
	Run.hp = 99
	Run.max_hp_loss = 0
	Run.skull_id = "c021"
	Run.upgrades = {}
	_p.global_position.x = 560.0
	Meta.register_battle_passive("test_sui_future", {
		"form": "c021", "owned": true, "name": "未来被动",
		"boss_effect": {"damage": 2},
	})
	_check(_p.sui_yue_passive_candidates() == ["test_sui_future"], "战斗扫描可读取未来角色注册被动")
	_check(_p.has_battle_passive("test_sui_future"), "未来角色可查询自身注册被动当前生效")
	_p.state = 4
	_p._shield_hits = 2
	_p._hurt_invincible = 0.8
	_p._skill_reflect = true
	_b._start_sui_move(_b.EYE)
	_check(_b.EYE == "skill01" and _b._current_anim == "skill01", "佛眼使用 5 号动画 skill01")
	_check(is_equal_approx(float(_b._move_cds[_b.EYE]), 50.0), "佛眼冷却 50 秒")
	_b._cast_tick(1.18)
	_check(_p._stolen_passives.is_empty(), "勘探帧前不提前夺取")
	_b._cast_tick(0.02)
	_check(_p._stolen_passives.has("test_sui_future") and _b._eye_passive == "test_sui_future", "佛眼夺取注册被动并由碎岳持有")
	_check(not _p.has_battle_passive("test_sui_future"), "统一查询会立即识别被动已被佛眼取走")
	_check(_p.hp == 99 and _p._shield_hits == 2 and _p.state == 4, "佛眼无视受伤无敌护盾与闪避且不经过普通受击")
	_check(is_equal_approx(_b._eye_effect("damage"), 2.0), "碎岳实际获得注册被动的 boss_effect")
	_p.state = 0
	_p._shield_hits = 0
	_p._hurt_invincible = 0.0
	_p._skill_reflect = false
	_b._hit_front(1, 300.0)
	_check(_p.hp == 96, "夺来的加伤真实进入碎岳伤害公式")

	Meta.battle_passives["test_sui_future"]["owned"] = false
	Meta.register_battle_passive("test_sui_future_two", {
		"form": "c021", "owned": true, "name": "第二被动",
		"boss_effect": {"max_hp": 2, "bell_charges": 3},
	})
	_b._scan_eye()
	_check(not _p._stolen_passives.has("test_sui_future") and _p._stolen_passives.has("test_sui_future_two"), "下一次扫描先归还旧被动再夺取新被动")
	_check(_b.max_hp == 66 and _b._bell_layers.size() == 4, "佛眼生命与额外金钟效果真实生效")

	Meta.battle_passives.clear()
	Meta.form_nodes["c021_combo_1"] = true
	_b._scan_eye()
	_check(not _p._stolen_passives.has("test_sui_future_two") and _p._stolen_passives.has("c021_combo_1"), "后续扫描可改为夺取已点亮永久修炼")
	_check(not _p._form_node("c021_combo_1") and Meta.has_form_node("c021_combo_1"), "失窃只封战斗实例且不修改永久存档")
	_check(is_equal_approx(_b._eye_effect("damage"), 1.0) and _b.max_hp == 64, "永久修炼映射为碎岳加伤且旧生命效果归还")


func _test_bell() -> void:
	_reset_all()
	_b._start_sui_move(_b.ARMS)
	_check(_b._bell_layers.is_empty(), "掷臂不触发佛曰")
	var cast_id: int = _b._cast_id
	_b._start_sui_move(_b.CRUSHER)
	_check(_b._cast_id == cast_id and _b._bell_layers.is_empty(), "施法状态与后撤保护禁止跳过节奏连开技能")
	for move in [_b.CRUSHER, _b.HANDS, _b.EYE]:
		_b._finish_cast()
		_b._set_state(CHASE)
		_b._move_cds[move] = 0.0
		_b._start_sui_move(move)
	_check(_b._bell_layers == [2, 2, 2], "三个非普攻各叠一层且每层独立两次")
	_b.take_damage(3, 500.0)
	_b.take_damage(3, 500.0)
	_check(_b.hp == 64 and _b._bell_layers == [2, 2], "同一层完整抵挡两次任意普通伤害")
	_b._direct_damage(2)
	_b._direct_damage(2)
	_check(_b.hp == 64 and _b._bell_layers == [2], "持续直伤同样消耗一层两次抵挡")
	_b.take_damage(1, 500.0)
	_check(_b._bell_layers == [1], "最后一层第一次受击后保留一次")
	_b.take_damage(1, 500.0)
	_b.take_damage(1, 500.0)
	_check(_b.hp == 63 and _b._bell_layers.is_empty(), "金钟耗尽后伤害正常结算")
	_reset_all()
	for i in range(20):
		_b._move_cds[_b.HANDS] = 0.0
		_b._start_sui_move(_b.HANDS)
		_b._finish_cast()
		_b._set_state(CHASE)
	_check(_b._bell_layers.size() == 20, "金钟层数没有叠加上限")


func _test_pressure_and_seal() -> void:
	_reset_all()
	Run.active = true
	Run.room_index = Run.ROOMS.size()
	Run.skull_id = "c021"
	Run.upgrades = {"damage": 3, "cooldown": 2, "hp": 3, "dash": 2, "dodge": 2}
	Run.max_hp = 14
	Run.hp = 14
	Run.max_hp_loss = 1
	Meta.form_nodes["c021_combo_1"] = true
	Meta.mastery["c021"] = 100
	_p.set_upgrades(Run.upgrades)
	_p._refresh_mastery()
	_check(_p.damage_bonus == 3 and _p._mastery_dmg == 1 and _p._form_node("c021_combo_1"), "压场前局内永久与契合增益正常生效")
	_p._buff_damage = 2
	_p._buff_timer = 6.0
	_p._stop_buff_damage = 1
	_p._stop_buff_timer = 6.0
	_p._room_awaken_damage = 2
	_p._awaken_stacks = 3
	_p._awaken_buff_damage = 1
	_p.set_sui_yue_pressure(true)
	_check(_p.damage_bonus == 0 and _p.cooldown_scale == 1.0 and is_equal_approx(_p._dash_time_scale, 1.0), "邪佛持续压制局内伤害冷却与疾影")
	_check(_p._mastery_dmg == 0 and not _p._form_node("c021_combo_1") and not _p._own("damage"), "邪佛压制契合永久修炼与流派查询")
	_check(_p.max_hp == 7 and Run.max_hp == 14, "邪佛只压战斗有效生命且不污染 Run 真实上限")
	_p.run_speed = 360.0
	_check(is_equal_approx(_p._move_speed(), 240.0), "石碑等临时移速增益在邪佛下无效")
	_check(_p._buff_now() == 6, "普通加伤被移除但觉醒房强化剑意与觉醒加伤保留")
	_p.hp = 3
	_p._apply_skill_heal({"heal": 2})
	_check(_p.hp == 5, "邪佛下技能回血保持有效")
	Run.apply_to(_p)
	_check(_p.max_hp == 7 and _p.damage_bonus == 0, "Run 状态注入不会把生命与增益写回")
	_p.swap_skull("c013")
	_check(_p._sui_yue_pressure and _p.damage_bonus == 0 and _p._mastery_dmg == 0, "邪佛下换头仍持续压制增益")
	_p.swap_skull("c021")
	_p.set_sui_yue_pressure(false)
	_check(_p.max_hp == Run.max_hp and _p.damage_bonus == 3 and _p._mastery_dmg == 1, "邪佛解除后真实上限与增益恢复")

	_p.apply_sui_yue_seal(15.0)
	_check(_p._passives_disabled() and _p.damage_bonus == 0 and not _p._form_node("c021_combo_1"), "剥离统一封锁局内与永久被动")
	_p._passive_seal_time = 0.01
	_p.state = 8
	_p._physics_process(0.02)
	_check(is_zero_approx(_p._passive_seal_time) and _p.damage_bonus == 3 and _p._form_node("c021_combo_1"), "剥离到期自动恢复被动且不改存档")


func _test_status_effects() -> void:
	_reset_all()
	_p.global_position.x = 1800.0
	_b._start_sui_move(_b.ARMS)
	_b._cast_duration = 10.0
	_b.apply_bleed(2)
	_b.apply_poison(2.0)
	_b.slow(4.0, 0.5)
	var hp_before: int = _b.hp
	_b._physics_process(1.0)
	_check(_b.hp == hp_before - 4 and _b.state == _b.S_CAST, "施法状态持续推进两层流血与两次中毒")
	_check(is_equal_approx(_b._slow_timer, 1.0), "施法状态持续推进余滞计时")

	_reset_all()
	_b._attack_desire = 0.0
	_p.global_position.x = 1300.0
	_b.slow(4.0, 0.5)
	_b._chase_tick(0.5)
	var expected := move_toward(0.0, _b.chase_speed * 0.5, _b.accel * 0.5)
	_check(is_equal_approx(_b.velocity.x, expected), "普通追击速度应用余滞倍率")

	_reset_all()
	_b.state = _b.S_RETREAT
	_b._retreat_left = 1.0
	_b.slow(4.0, 0.5)
	_b._retreat_tick(0.016)
	expected = move_toward(0.0, _b.chase_speed * _b.RETREAT_SPEED_SCALE * 0.5, _b.accel * 0.016)
	_check(is_equal_approx(_b.velocity.x, expected), "收招后撤速度应用余滞倍率")


func _test_uninterruptible() -> void:
	# Boss 词条默认规则：掷臂之外的招式出手期间免疫全部控制，时停仍可打断（清理由清理测试覆盖）。
	_reset_all()
	_b._start_sui_move(_b.EYE)
	var root_before: float = _b._root_timer
	var stun_before: float = _b._stun_timer
	var velocity_before: Vector2 = _b.velocity
	_b.root(2.0, true)
	_b.contain(2.0, true)
	_b.stun(2.0, true)
	_b.slam(true)
	_b.launch(1, 900.0, 400.0, true)
	_b.knock_back(1, 900.0, 4, true)
	_check(_b.state == _b.S_CAST and _b._cast_move == _b.EYE, "佛眼出手期间免疫定身/晕眩/砸落/击飞/击退")
	_check(_b._root_timer == root_before and _b._stun_timer == stun_before and _b.velocity == velocity_before,
		"非普攻招式期间控制不写入移动状态")

	_reset_all()
	_b._start_sui_move(_b.ARMS)
	_b.launch(1, 900.0, 400.0, true)
	_check(_b.velocity.y == -200.0, "普攻掷臂仍可被规则级击飞挑起")
	_reset_all()


func _test_cleanup() -> void:
	_reset_all()
	Meta.register_battle_passive("test_sui_future", {"form": "c021", "owned": true, "boss_effect": {}})
	_b._scan_eye()
	_p.apply_sui_yue_seal(15.0)
	_p._stun_time = 0.5
	_b._start_sui_move(_b.HANDS)
	_b.time_stop(1.0)
	_check(_b._cast_events.is_empty() and _b._cast_move.is_empty() and _b.state == CHASE, "时停打断施法并清理待结算事件")
	_p.set_sui_yue_pressure(true)
	_b._bell_layers.clear()
	_b.take_damage(999, 500.0)
	_check(_b.state == DEAD, "碎岳死亡进入原倒地流程")
	_check(_p._stolen_passives.is_empty() and is_zero_approx(_p._passive_seal_time) and is_zero_approx(_p._stun_time), "死亡归还佛眼被动并清除剥离与眩晕")
	_check(not _p._sui_yue_pressure, "死亡解除邪佛压场")


func _shot(tag: String) -> void:
	await get_tree().process_frame
	RenderingServer.force_draw()
	var img = get_viewport().get_texture().get_image()
	if img == null:
		p("screenshot unavailable " + tag)
		return
	var err = img.save_png(OUT_DIR + tag + ".png")
	p("saved " + tag + " err=" + str(err))
