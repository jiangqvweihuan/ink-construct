extends Node

## 焚鼎专项回归：真实 Boss 房先导、四招伤害帧、怒焰、双被动与公共攻击节奏。

const OUT_DIR := "res://tests/out/"
const BossTypes := preload("res://scripts/enemies/boss_types.gd")
const SpineFX := preload("res://scripts/systems/spine_fx.gd")
const CHASE := 2
const DEAD := 5

var _log: FileAccess
var _room
var _b
var _p
var _checks := 0
var _failed := 0


func p(msg) -> void:
	print("[FD] ", msg)
	if _log:
		_log.store_line("[FD] " + str(msg))
		_log.flush()


func _check(ok: bool, label: String) -> void:
	_checks += 1
	if not ok:
		_failed += 1
	p(("PASS " if ok else "FAIL ") + label)


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	_log = FileAccess.open("res://tests/fen_ding_test.log", FileAccess.WRITE)
	get_tree().create_timer(45.0).timeout.connect(func():
		p("TIMEOUT")
		get_tree().quit(2)
	)
	Run.start()
	Run.room_index = Run.ROOMS.size()
	Run.boss_id = "c015a1"
	Run.boss_queue = ["c015a1"]
	_room = load("res://scenes/world/room_01.tscn").instantiate()
	add_child(_room)
	_b = _room._boss
	_p = _room._player
	var intro = _room.get_node_or_null("BossDuelIntro")
	_check(intro != null, "C015a1 创建黑底对峙先导")
	_check(_b.get_script() == load("res://scripts/enemies/fen_ding.gd"), "正式房间使用焚鼎独立战斗脚本")
	_check(BossTypes.get_boss("c015a1")["intro"] == {"anim": "stand", "loop": true}, "挑战界面使用动画 13 循环待机")
	_check(_b.state == _b.S_ENTER and not _b.is_physics_processing(), "先导期间焚鼎锁定登场并停物理")
	await _shot("fen_ding_intro")
	if intro != null:
		await intro.finished
	_check(_p.visible and _b.visible and _p.is_physics_processing() and _b.is_physics_processing(), "先导结束恢复双方显示与物理")
	_check(_b.state == CHASE and is_zero_approx(_b._attack_desire), "先导结束从零累计公共攻击欲望")

	_b.set_physics_process(false)
	_p.set_physics_process(false)
	_test_attack_desire()
	_test_palm()
	_test_crush()
	_test_fists()
	_test_burn()
	_test_uninterruptible()
	await _test_awaken()
	await _test_rise()
	_test_status_effects()
	_test_cleanup()
	p("DONE checks=%d failed=%d" % [_checks, _failed])
	get_tree().quit(1 if _failed > 0 else 0)


func _reset_all(player_hp := 99) -> void:
	_b._cleanup_cast()
	_b._end_stop()
	_b.state = CHASE
	_b.max_hp = 68
	_b.hp = 68
	_b._invincible = false
	_b._bleed_stacks = 0
	_b._bleed_time = 0.0
	_b._bleed_acc = 0.0
	_b._poison_time = 0.0
	_b._poison_acc = 0.0
	_b._slow_timer = 0.0
	_b._slow_scale = 1.0
	_b._awakened = false
	_b._attack_desire = 5.0
	_b._approach_yield = 0.0
	_b.cd_scale = 1.0
	for move in _b.MOVE_ORDER:
		_b._move_cds[move] = 0.0
	_b.global_position = Vector2(800, 560)
	_b.velocity = Vector2.ZERO
	_b.facing = -1
	_b._apply_facing()
	_b._target = _p
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
	_p._knock_cd = 0.0 # 清掉前一招留下的击倒保护，避免佛陀免倒地判定被吞掉
	_p._invincible = false
	_p._damage_reduce = 0
	_p._shield_hits = 0
	_p._parry_ready = false
	_p._bell_shell = false
	_p._skill_reflect = false
	_p._cripple_time = 0.0
	_p.clear_fen_ding_burn()
	Run.active = false
	Run.difficulty = 1
	Run.guard_available = false


func _test_attack_desire() -> void:
	_reset_all()
	_b._attack_desire = 0.0
	_b._chase_tick(0.016)
	_check(_b._cast_move.is_empty() and is_zero_approx(_b.velocity.x) and _b._current_anim == "stand", "保距带内没有位移时播放待机")
	_check(is_equal_approx(_b._attack_desire, 0.016), "相持状态按 1 倍速度累计欲望")

	_reset_all()
	_b._attack_desire = 0.0
	_p.global_position.x = 1000.0
	_p.velocity.x = -200.0
	_b._chase_tick(1.5)
	_check(_b._cast_move.is_empty() and _b.velocity.x < 0.0, "玩家逼近时先向后排让而非立即出手")
	_check(is_equal_approx(_b._approach_yield, 120.0), "单轮逼近最多忍让 120px")
	_b._chase_tick(0.016)
	_check(_b._cast_move == _b.CRUSH and is_zero_approx(_b._attack_desire), "忍让后玩家继续冒进立即刷新欲望并进攻")
	_b._finish_cast()
	_b._attack_desire = 2.0
	_p.global_position.x = 500.0
	_p.velocity.x = 0.0
	_b._chase_tick(0.016)
	_check(_b._cast_move.is_empty() and is_zero_approx(_b.velocity.x) and _b._current_anim == "stand", "收招后距离合适就停走待机而非持续后退")

	_reset_all()
	_b._attack_desire = 2.0
	_p.global_position.x = 1300.0
	_p.velocity.x = 200.0
	_b._chase_tick(0.5)
	_check(is_equal_approx(_b._attack_desire, 3.0) and _b.velocity.x > 0.0, "玩家后退时 Boss 跟紧并以 2 倍速度累计欲望")
	_p.global_position.x = 1120.0
	_p.velocity.x = 0.0
	_b._chase_tick(0.5)
	_check(is_equal_approx(_b._attack_desire, 3.5) and is_zero_approx(_b.velocity.x) and _b._current_anim == "stand", "重新相持后恢复 1 倍欲望并待机")
	_b._attack_desire = 5.0
	_b._chase_tick(0.016)
	_check(_b._planned_move == _b.CRUSH and _b._cast_move.is_empty() and _b.velocity.x > 0.0, "欲望满后预选愤炎碎并继续贴近")
	_p.global_position.x = 1000.0
	_b._chase_tick(0.016)
	_check(_b._cast_move == _b.CRUSH, "愤炎碎进入实际范围中段后才起手")
	_b._cast_tick(1.18)
	_check(_p.hp == 98, "愤炎碎贴近后首段能命中保持不动的玩家")

	_reset_all()
	_p.global_position.x = 1400.0
	_b._chase_tick(0.016)
	_check(_b._planned_move == _b.FISTS and _b._cast_move.is_empty() and _b.velocity.x > 0.0, "远距离满欲望预选双拳并主动贴近")
	_p.global_position.x = 1030.0
	_b._chase_tick(0.016)
	_check(_b._cast_move == _b.FISTS, "双拳进入实际范围中段后才起手")
	_b._cast_tick(0.91)
	_check(_p.hp == 96, "双拳贴近后能命中保持不动的玩家")


func _test_palm() -> void:
	_reset_all()
	_b._start_fen_move(_b.PALM)
	_check(_b.PALM == "skill01" and _b._current_anim == "skill01", "炎掌使用动画 5 skill01")
	_b._cast_tick(0.71)
	_check(_p.hp == 99 and _p._fen_ding_burn_stacks == 0, "炎掌劈落前不提前出伤或叠怒焰")
	_b._cast_tick(0.01)
	_check(_p.hp == 97 and _p._fen_ding_burn_stacks == 1, "炎掌造成 2 伤并叠加 1 层怒焰")
	_check(is_equal_approx(_p.fen_ding_burn_interval(), 60.0), "第一层怒焰每 60 秒结算")


func _test_crush() -> void:
	_reset_all()
	_b._start_fen_move(_b.CRUSH)
	_check(is_equal_approx(_b._move_cds[_b.CRUSH], 20.0), "愤炎碎冷却 20 秒")
	_b._cast_tick(1.16)
	_check(_p.hp == 99, "愤炎碎第一次落地前无伤害")
	_b._cast_tick(0.01)
	_check(_p.hp == 98 and is_equal_approx(_p._cripple_time, 5.0), "第一次捶地造成 1 伤并致残 5 秒")
	_p._cripple_time = 1.0
	_b._cast_tick(0.72)
	_check(_p.hp == 97 and is_equal_approx(_p._cripple_time, 5.0), "第二次捶地造成 1 伤并刷新致残")
	_b._cast_tick(0.72)
	_check(_p.hp == 95 and is_equal_approx(_p._cripple_time, 5.0), "第三次捶地造成 2 伤并再次刷新致残")
	_check(_p._fen_ding_burn_stacks == 3, "炽热之心让愤炎碎三段各附加 1 层怒焰")
	_reset_all()
	_b.cd_scale = 0.5
	_b._start_fen_move(_b.CRUSH)
	_check(is_equal_approx(_b._move_cds[_b.CRUSH], 10.0), "无尽冷却倍率只在起手时缩放一次")


func _test_fists() -> void:
	_reset_all()
	_b._start_fen_move(_b.FISTS)
	_check(is_equal_approx(_b._move_cds[_b.FISTS], 25.0), "双拳冷却 25 秒")
	_b._cast_tick(0.89)
	_check(_p.hp == 99, "双拳锤出前不提前出伤")
	_b._cast_tick(0.01)
	_check(_p.hp == 96 and _p._fen_ding_burn_stacks == 1, "双拳造成 3 伤并叠加 1 层怒焰")
	_check(_p.velocity.x <= -600.0 and _p.velocity.y < 0.0, "双拳附带高额击退")

	_reset_all()
	var previous_skull: String = _p.skull_id
	_p.swap_skull("c013")
	_p.max_hp = 20
	_p.hp = 20
	Run.c013_buddha = 1
	_b._start_fen_move(_b.FISTS)
	_b._cast_tick(0.91)
	_check(_p.hp == 17 and Run.c013_buddha == 0 and _p._hurt_chain.is_empty(), "真实 Boss 恰好 3 实伤消耗镇岳佛陀且只免除倒地")
	_p.swap_skull(previous_skull)


func _test_burn() -> void:
	_reset_all(30)
	var expected := [60.0, 58.0, 54.0, 48.0, 40.0, 30.0, 18.0, 10.0]
	for i in range(8):
		_p._apply_fen_ding_burn(_b)
		_check(is_equal_approx(_p.fen_ding_burn_interval(), float(expected[i])), "怒焰第 %d 层共享间隔正确" % (i + 1))
	_p._apply_fen_ding_burn(_b)
	_check(_p._fen_ding_burn_stacks == 9 and is_equal_approx(_p.fen_ding_burn_interval(), 10.0), "怒焰无限叠层且 8 层后固定 10 秒")
	_b.hp = 40
	for move in _b.MOVE_ORDER:
		_b._move_cds[move] = 9.0
	_p._hurt_invincible = 0.5
	_p._fen_ding_burn_tick(10.0)
	_check(_p.hp == 29 and is_equal_approx(_p._hurt_invincible, 0.5), "怒焰固定真实扣 1 血且不写受伤无敌")
	_check(_b.hp == 50, "炽热之心每次共享扣血只恢复 10 点生命")
	var ready := true
	for move in _b.MOVE_ORDER:
		ready = ready and is_zero_approx(float(_b._move_cds[move]))
	_check(ready, "炽热之心刷新全部技能冷却")
	_p._fen_ding_burn_tick(9.9)
	_check(_p.hp == 29 and _b.hp == 50, "共享计时未到期不重复扣血回血")
	_p._fen_ding_burn_tick(0.1)
	_check(_p.hp == 28 and _b.hp == 60, "下一次共享扣血仍只各结算一次")


func _test_uninterruptible() -> void:
	# Boss 词条默认规则：非普攻招式出手期间免疫全部控制，连规则级 ignore_armor 也打不断。
	_reset_all()
	_b._start_fen_move(_b.CRUSH)
	var root_before: float = _b._root_timer
	var stun_before: float = _b._stun_timer
	var velocity_before: Vector2 = _b.velocity
	_b.root(2.0, true)
	_b.contain(2.0, true)
	_b.stun(2.0, true)
	_b.slam(true)
	_b.launch(1, 900.0, 400.0, true)
	_b.knock_back(1, 900.0, 4, true)
	_check(_b.state == _b.S_CAST and _b._cast_move == _b.CRUSH, "愤炎碎出手期间免疫定身/晕眩/砸落/击飞/击退")
	_check(_b._root_timer == root_before and _b._stun_timer == stun_before and _b.velocity == velocity_before,
		"非普攻招式期间控制不写入移动状态")

	_reset_all()
	_b._start_fen_move(_b.FISTS)
	_b.launch(1, 900.0, 400.0, true)
	_check(_b.state == _b.S_CAST and _b._cast_move == _b.FISTS and _b.velocity.y == 0.0, "双拳出手期间同样不可打断")

	# 炎骨觉醒演出（S_AWAKEN）也在不可打断之列。
	_reset_all()
	_b.state = _b.S_AWAKEN
	_b.stun(2.0, true)
	_check(_b.state == _b.S_AWAKEN and _b._stun_timer == 0.0, "炎骨觉醒演出期间不可打断")

	# 普攻炎掌不受保护：规则级击飞仍能把它挑起来（Boss 版只改纵向速度，不重置招式）。
	_reset_all()
	_b._start_fen_move(_b.PALM)
	_b.launch(1, 900.0, 400.0, true)
	_check(_b.velocity.y == -200.0, "普攻炎掌仍可被规则级击飞挑起")
	_reset_all()


func _test_awaken() -> void:
	_reset_all()
	_b.hp = 35
	_b.take_damage(1, 500.0)
	_check(_b.hp == 34 and not _b._awakened, "生命恰为 50% 时尚未觉醒")
	_b.take_damage(1, 500.0)
	_check(_b.hp == 33 and _b._awakened and _b.state == _b.S_AWAKEN, "首次低于 50% 播放动画 8 并永久觉醒")
	_check(_b._current_anim == _b.AWAKEN_ANIM, "炎骨使用 skill04 觉醒演出")
	var awaken_nodes := _spine_fx_children(_b, _b.AWAKEN_FX_ID)
	_check(awaken_nodes.size() == 1, "觉醒在焚鼎节点下生成且只生成一个 E54110 Spine 特效")
	if awaken_nodes.size() == 1:
		var awaken_fx = awaken_nodes[0]
		_check(awaken_fx.sprite.scale.x < 0.0, "觉醒 Spine 朝向跟随焚鼎")
		var expected: String = _b.AWAKEN_FX_ANIM
		var state = awaken_fx.sprite.call("get_animation_state")
		var track = state.call("get_current", 0)
		var actual := str(track.call("get_animation").call("get_name")) if track != null else ""
		_check(actual == expected and not actual.is_empty(), "觉醒 Spine 使用用户指定的 action1（%s）" % actual)
		_check(awaken_fx.position == _b.AWAKEN_FX_CENTER, "觉醒 Spine 锚定在身体中心而不是脚下")
		var visual: Rect2 = awaken_fx.sprite.call("get_skeleton").call("get_bounds")
		_check(absf(visual.size.y * absf(awaken_fx.sprite.scale.y) - _b.AWAKEN_FX_HEIGHT) < 2.0,
			"觉醒 Spine 放大到 %.0f 像素高（实际 %.0f）" % [_b.AWAKEN_FX_HEIGHT, visual.size.y * absf(awaken_fx.sprite.scale.y)])
	await get_tree().create_timer(0.9).timeout
	await _shot("fen_ding_awaken")
	_b.take_damage(1, 500.0)
	_check(_b.hp == 32, "觉醒后 1 伤向上取整仍为 1")
	_b.take_damage(3, 500.0)
	_check(_b.hp == 30, "觉醒后 3 伤减半向上取整为 2")
	_b.on_fen_ding_burn_hit(1, _p)
	_check(_b.hp == 40 and _b._awakened, "回血不会撤销炎骨觉醒")
	_b.state = CHASE
	_b._attack_desire = 5.0
	_b._move_cds[_b.CRUSH] = 9.0
	_b._move_cds[_b.FISTS] = 9.0
	_b._chase_tick(0.016)
	_check(_b._cast_move == _b.RISE, "觉醒后优先解锁并选择炎起")
	_check(is_equal_approx(_b._move_cds[_b.RISE], 30.0), "炎起冷却 30 秒")


func _test_rise() -> void:
	_reset_all()
	_b._awakened = true
	_b._start_fen_move(_b.RISE)
	_b._cast_tick(0.53)
	_check(_b._rise_warnings.is_empty() and _p.hp == 99, "炎起抬腿前不生成预警")
	_b._cast_tick(0.01)
	_check(_b._rise_positions.size() == 3 and _b._rise_warnings.size() == 3, "抬腿时生成玩家脚下与随机点共 3 个预警")
	_check(is_equal_approx(float(_b._rise_positions[0]), _p.global_position.x), "第一处预警锁定玩家脚下")
	await _shot("fen_ding_rise_warn")
	_b._cast_tick(0.35)
	_check(_p.hp == 99, "跺脚前只有预警不结算伤害")
	var previous_lava := _spine_fx_children(get_tree().current_scene, _b.RISE_FX_ID)
	_b._cast_tick(0.01)
	_check(_p.hp == 96 and _p._fen_ding_burn_stacks == 1, "跺脚与岩浆同帧造成 3 伤并叠加怒焰")
	var current_lava := _spine_fx_children(get_tree().current_scene, _b.RISE_FX_ID)
	var new_lava: Array = []
	for fx in current_lava:
		if not previous_lava.has(fx):
			new_lava.append(fx)
	_check(new_lava.size() == _b._rise_positions.size(), "rise_burst 在每处伤害点生成一个 E53038 岩浆 Spine")
	var lava_positions_match: bool = new_lava.size() == _b._rise_positions.size()
	for i in range(mini(new_lava.size(), _b._rise_positions.size())):
		var expected_pos := Vector2(float(_b._rise_positions[i]), _b.global_position.y)
		lava_positions_match = lava_positions_match and new_lava[i].global_position.is_equal_approx(expected_pos)
	_check(lava_positions_match, "E53038 岩浆节点位置与原真实伤害点逐一一致")
	_check(_b._rise_warnings.is_empty(), "喷发后清理全部预警")
	await _shot("fen_ding_rise_burst")
	await get_tree().create_timer(0.55).timeout
	await _shot("fen_ding_rise_hold")
	if not new_lava.is_empty() and is_instance_valid(new_lava[0]):
		var lava_state = new_lava[0].sprite.call("get_animation_state")
		var lava_track = lava_state.call("get_current", 0)
		var lava_anim := str(lava_track.call("get_animation").call("get_name")) if lava_track != null else ""
		_check(lava_anim == _b.RISE_FX_ANIM, "炎起岩浆播放 action4（实际 %s）" % lava_anim)
		var lava_bounds: Rect2 = new_lava[0].sprite.call("get_skeleton").call("get_bounds")
		var fitted: float = lava_bounds.size.x * absf(new_lava[0].sprite.scale.x)
		_check(absf(fitted - _b.RISE_FX_WIDTH) < 2.0,
			"岩浆宽度贴合 %.0f 像素火区（实际 %.0f）" % [_b.RISE_FX_WIDTH, fitted])

	_reset_all()
	_b._awakened = true
	_b._start_fen_move(_b.RISE)
	_b._cast_tick(0.54)
	_b._rise_positions = [500.0, 800.0, 1100.0]
	_p.global_position.x = 1800.0
	_b._cast_tick(0.36)
	_check(_p.hp == 99 and _p._fen_ding_burn_stacks == 0, "离开半径 110 的火区后不受伤也不叠层")


func _test_status_effects() -> void:
	_reset_all()
	_p.global_position.x = 1800.0
	_b._start_fen_move(_b.CRUSH)
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
	_b._attack_desire = 0.0
	_p.global_position.x = 550.0
	_b.slow(4.0, 0.5)
	_b._chase_tick(0.5)
	expected = move_toward(0.0, _b.chase_speed * 0.5, _b.accel * 0.5)
	_check(is_equal_approx(_b.velocity.x, expected), "近距离退让速度应用余滞倍率")


func _test_cleanup() -> void:
	_reset_all()
	_b._awakened = true
	_b._start_fen_move(_b.RISE)
	_b._cast_tick(0.54)
	_b.time_stop(1.0)
	_check(_b._rise_warnings.is_empty() and _b._cast_events.is_empty(), "时停清理炎起预警与待结算喷发")
	_reset_all()
	_b._start_fen_move(_b.PALM)
	_b._cast_tick(0.72)
	_check(_p._fen_ding_burn_stacks == 1, "死亡清理前建立真实怒焰")
	_b.take_damage(999, 500.0)
	_check(_b.state == DEAD and _p._fen_ding_burn_stacks == 0, "焚鼎死亡立即清除玩家永久怒焰")
	_check(_b._fz.is_empty(), "旧三阶段自动周期火区已移除")


func _spine_fx_children(parent: Node, fx_id: String) -> Array:
	var out: Array = []
	var data = SpineFX.data(fx_id)
	for child in parent.get_children():
		if child.get_script() == SpineFX and child.sprite != null and child.sprite.get("skeleton_data_res") == data:
			out.append(child)
	return out


func _shot(tag: String) -> void:
	await get_tree().process_frame
	RenderingServer.force_draw()
	var img = get_viewport().get_texture().get_image()
	if img == null:
		p("screenshot unavailable " + tag)
		return
	var err = img.save_png(OUT_DIR + tag + ".png")
	p("saved " + tag + " err=" + str(err))
