extends Node

## 鸣钟专项回归：真实 C032 Boss 房、四招节奏、根骨位移、英勇、武神与神眷。

const BossTypes := preload("res://scripts/enemies/boss_types.gd")
const CHASE := 2
const DEAD := 5

var _log: FileAccess
var _room
var _b
var _p
var _checks := 0
var _failed := 0


func p(msg) -> void:
	print("[MZ] ", msg)
	if _log:
		_log.store_line("[MZ] " + str(msg))
		_log.flush()


func _check(ok: bool, label: String) -> void:
	_checks += 1
	if not ok:
		_failed += 1
	p(("PASS " if ok else "FAIL ") + label)


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://tests/out/"))
	_log = FileAccess.open("res://tests/ming_zhong_test.log", FileAccess.WRITE)
	Meta.persist = false
	get_tree().create_timer(45.0).timeout.connect(func():
		p("TIMEOUT")
		get_tree().quit(2)
	)
	Run.start()
	Run.difficulty = 1
	Run.room_index = Run.ROOMS.size()
	Run.boss_id = "c032"
	Run.boss_queue = ["c032"]
	_room = load("res://scenes/world/room_01.tscn").instantiate()
	add_child(_room)
	_b = _room._boss
	_p = _room._player
	_check(_b.get_script() == load("res://scripts/enemies/ming_zhong.gd"), "正式房间使用鸣钟独立战斗脚本")
	_check(is_equal_approx(float(BossTypes.get_boss("c032")["scale"]), 0.48), "鸣钟实战模型缩放为 0.48")
	_check(is_equal_approx(float(BossTypes.get_boss("c032").get("codex_scale", 0.0)), 0.62), "鸣钟图鉴使用独立正常大小预览")
	_check(_b.state == _b.S_ENTER and _b._current_anim == "skill02", "入场使用动画 14 skill02")
	var intro = _room.get_node_or_null("BossDuelIntro")
	_check(intro != null, "正式房创建鸣钟独立入场 UI")
	if intro != null:
		intro._finish()
	var capsule := _b.get_node("CollisionShape2D").shape as CapsuleShape2D
	_check(capsule != null and is_equal_approx(capsule.height, 112.0) and is_equal_approx(capsule.radius, 20.0), "碰撞体同步缩至略高于玩家")
	_b.set_physics_process(false)
	_p.set_physics_process(false)
	_test_standard_moves()
	_test_combo_and_chain()
	_test_pursuit()
	_test_awaken()
	_test_block_and_hurt()
	_test_interruptions()
	_test_status_effects()
	_test_root_motion()
	await _test_pursuit_root_motion()
	await _test_hud_bar()
	_test_cleanup_and_execute()
	p("DONE checks=%d failed=%d" % [_checks, _failed])
	get_tree().quit(1 if _failed > 0 else 0)


func _reset_all(player_hp := 99) -> void:
	Run.active = false
	Run.difficulty = 1
	Run.guard_available = false
	_b._cleanup_cast()
	_b._end_stop()
	_b._hurt_chain_active = false
	_b._hurt_chain.clear()
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
	_b._heroic = false
	_b._cast_heroic = false
	_b._block = 0
	_b._attack_desire = _b.ATTACK_DESIRE_TIME
	_b._approach_yield = 0
	_b._retreat_left = 0.0
	_b._planned_move = ""
	_b.cd_scale = 1.0
	for move in _b.MOVE_ORDER:
		_b._move_cds[move] = 0.0
	_b.global_position = Vector2(800, 560)
	_b.velocity = Vector2.ZERO
	_b.facing = -1
	_b._apply_facing()
	_b._target = _p
	_p.clear_ming_zhong_effects()
	_p.global_position = Vector2(560, 560)
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


func _test_standard_moves() -> void:
	_reset_all()
	_p.global_position.x = 1500.0
	_b._chase_tick(0.016)
	_check(_b._planned_move == _b.PURSUIT and _b._cast_move.is_empty(), "远距离满欲望先预选追击而不隔空起手")
	_check(_b._current_anim == "speed_run" and _b.velocity.x > 0.0, "满欲望追近使用动画 22 speed_run")
	_p.global_position.x = 1200.0
	_b._chase_tick(0.016)
	_check(_b._cast_move.is_empty() and _b._planned_move == _b.PURSUIT and _b.velocity.x > 0.0, "旧追击起手距离仍会空挥，现在必须继续贴近")
	_p.global_position.x = 960.0
	_b._chase_tick(0.016)
	_check(_b._cast_move == _b.PURSUIT, "玩家进入追击实际命中范围中段后才起手")
	_b._cast_tick(0.53)
	_check(_p.hp == 98, "追击贴近后首段能命中保持不动的玩家")
	_b._finish_cast()
	_b._retreat_tick(0.016)
	_check(_b.state == _b.S_RETREAT and _b._current_anim == "run1", "收招后撤使用动画 12 run1")


func _test_combo_and_chain() -> void:
	_reset_all()
	_b._start_ming_move(_b.COMBO)
	_check(_b._current_anim == "skill05-cankao", "普攻使用动画 21 跳劈")
	_b._cast_tick(0.63)
	_check(_p.hp == 99 and not _b._heroic, "跳劈落斧前不提前出伤或获得英勇")
	_b._cast_tick(0.02)
	_check(_p.hp == 97 and _b._heroic and _b._block == 2, "跳劈造成 2 伤，实伤获得英勇与 2 格挡")
	_b._finish_cast()
	_b._set_state(CHASE)
	_p.state = 0
	_p._hurt_invincible = 0.0
	_p._hurt_cast_key = ""
	var before: int = _p.hp
	_b._start_ming_move(_b.CHAIN)
	_check(_b._current_anim == "skill01-cankao" and is_equal_approx(float(_b._move_cds[_b.CHAIN]), 24.0), "四连击使用动画 18 且冷却 24 秒")
	_check(_b._cast_heroic and not _b._heroic, "英勇在下一招起手消耗")
	_b._cast_tick(0.81)
	_check(_p.hp == before and _p._ming_zhong_holder == null, "四连击首段前不提前出伤或定点")
	_b._cast_tick(0.02)
	_check(_p.hp == before - 2 and _p._ming_zhong_holder == _b, "英勇令首段由 1 增至 2，实伤固定玩家")
	_check(is_equal_approx(_p.global_position.x, _b.global_position.x - 92.0), "玩家被固定在鸣钟正前方")
	_b.global_position.x -= 40.0
	_b._cast_tick(0.75)
	_check(_p.hp == before - 4 and is_equal_approx(_p.global_position.x, _b.global_position.x - 92.0), "第二段翻倍为 2 且玩家跟随鸣钟位移")
	_b._cast_tick(0.67)
	_check(_p.hp == before - 8, "第三段由 2 翻倍为 4")
	_b._cast_tick(0.71)
	_check(_p.hp == before - 12 and is_equal_approx(_p._ming_zhong_vulnerable_time, 12.0), "第四段由 2 翻倍为 4并附加 12 秒易伤")
	_b._finish_cast()
	_check(_p._ming_zhong_holder == null, "四连击收招统一释放定点")
	_p.state = 0
	_p._hurt_invincible = 0.0
	_p._ming_zhong_vulnerable_time = 5.0
	before = _p.hp
	_p.hurt(1, Vector2.ZERO, null, {})
	_check(_p.hp == before - 2 and is_equal_approx(_p._ming_zhong_vulnerable_time, 12.0), "易伤仅一层，任意实伤 +1并刷新持续时间")

	_reset_all()
	_b._heroic = true
	_p.global_position.x = 1200.0
	_b._start_ming_move(_b.COMBO)
	_b._cast_tick(0.65)
	_check(_p.hp == 99 and not _b._heroic, "普攻落空不获得英勇，已有英勇也在起手消耗")


func _test_pursuit() -> void:
	_reset_all()
	_b.hp = 50
	_b._start_ming_move(_b.PURSUIT)
	_check(_b.PURSUIT_ANIMS.has(_b._current_anim) and is_equal_approx(float(_b._move_cds[_b.PURSUIT]), 36.0), "追击随机使用动画 19／20且冷却 36 秒")
	_b._cast_tick(0.51)
	_check(_p.hp == 99, "追击前劈尚未落斧时无伤害")
	_b._cast_tick(0.02)
	_check(_p.hp == 98, "追击前劈造成 1 伤")
	_p.global_position.x = 650.0
	_b._cast_tick(0.62)
	_check(_b._spin_phase and _b._invincible and _b.get_collision_exceptions().has(_p), "旋转期间无敌无实体并穿过玩家")
	_check(_p.hp == 96 and _b.hp == 52 and _b._spin_done, "旋转仅结算 2 伤并按实伤回血")
	_b._cast_tick(0.50)
	_check(_p.hp == 96 and _b.hp == 52, "持续接触不会在旋转中重复伤害或回血")
	_b._cast_tick(1.0)
	_check(not _b._spin_phase and not _b._invincible and not _b.get_collision_exceptions().has(_p), "旋转结束恢复实体与非无敌")
	_b._cast_tick(0.36)
	_check(_p.hp == 93 and is_equal_approx(_p._ming_zhong_vulnerable_time, 12.0), "末尾下劈造成 3 伤并附加易伤")

	_reset_all()
	_b.hp = 50
	_p.global_position.x = 1200.0
	_b._start_ming_move(_b.PURSUIT)
	_b._cast_tick(0.53)
	_p.global_position.x = 650.0
	_p.state = _p.State.DASH
	_b._cast_tick(0.63)
	_check(_p.hp == 99 and _b.hp == 50 and _b._spin_done and not _b._heroic, "旋转被完美闪避后不伤害、不回血也不触发命中收益")


func _test_awaken() -> void:
	_reset_all()
	_b.hp = 34
	_check(_b._choose_move(500.0) != _b.AWAKEN, "生命恰为 50%时尚未解锁觉醒")
	_b.hp = 33
	_check(_b._choose_move(500.0) == _b.AWAKEN, "生命低于 50%后解锁觉醒")
	_b.hp = 30
	_b._start_ming_move(_b.AWAKEN)
	_check(_b._current_anim == "transform1" and is_equal_approx(float(_b._move_cds[_b.AWAKEN]), 40.0), "觉醒使用动画 26且冷却 40 秒")
	_b.take_damage(6, 500.0)
	_check(_b.hp == 30 and _b.state == _b.S_CAST, "蓄力期间无敌霸体，高伤也不打断")
	_b._cast_tick(4.31)
	_check(_p.hp == 99 and _b.hp == 30 and not _b._awakened, "双斧完全展开前不爆发、不回血")
	_b._cast_tick(0.02)
	_check(_p.hp == 95 and _b.hp == 47 and _b._awakened, "首次觉醒全屏 4 伤并恢复 25%生命")
	_check(_b._block == 12 and _b._heroic and _p._ming_zhong_holy == 0, "觉醒获得 10 格挡，命中另触发武神与英勇")
	_b._finish_cast()
	_b._set_state(CHASE)
	_b._move_cds[_b.AWAKEN] = 0.0
	_p.state = 0
	_p._hurt_invincible = 0.0
	_b._start_ming_move(_b.AWAKEN)
	_check(_b._cast_heroic, "觉醒后英勇仍可被下一招消耗")
	_b._cast_tick(4.33)
	_check(_p.hp == 95 and _p._ming_zhong_holy == 2 and _b.hp == 64, "觉醒后攻击不扣血，英勇使整招圣光累计翻倍")
	_b._move_cds[_b.AWAKEN] = 0.0
	_check(_b._awakened and _b._choose_move(500.0) == _b.AWAKEN, "首次觉醒后觉醒技能保持可用")


func _test_block_and_hurt() -> void:
	_reset_all()
	for move in _b.MOVE_ORDER:
		_b._move_cds[move] = 10.0
	for i in range(20):
		_b.on_player_hit(1, {}, _p)
	var ready := true
	for move in _b.MOVE_ORDER:
		ready = ready and is_zero_approx(float(_b._move_cds[move]))
	_check(ready and _b._block == 40, "武神每次命中全部技能冷却 -3，格挡无限叠加")
	_b.take_damage(6, 500.0)
	_check(_b.hp == 68 and _b._block == 34 and _b.state == CHASE, "只损失格挡不扣生命也不触发倒地")
	_b._block = 0
	_b.take_damage(5, 500.0)
	_check(_b.hp == 63 and _b.state == CHASE, "实际生命损失等于 5不触发倒地")
	_b.take_damage(6, 500.0)
	_check(_b.hp == 57 and _b.state == _b.State.HURT and _b._current_anim == "atked_heavy", "实际生命损失大于 5先播重受击")
	_b._hurt_tick(float(_b._anim_durations.get("atked_heavy", 0.5)) + 0.01)
	_check(_b._current_anim == "atked_fall_end", "重受击后接动画 6倒地")
	_b._hurt_tick(float(_b._anim_durations.get("atked_fall_end", 0.5)) + 0.01)
	_check(_b._current_anim == "getup", "倒地后接动画 10起身")
	_b._hurt_tick(float(_b._anim_durations.get("getup", 0.5)) + 0.01)
	_check(_b.state == CHASE and not _b._hurt_chain_active, "起身完成后恢复追击")


func _test_interruptions() -> void:
	_reset_all()
	_b.hp = 30
	_b._start_ming_move(_b.AWAKEN)
	_b._cast_tick(4.31)
	_p.state = _p.State.DASH
	_b._cast_tick(0.02)
	_check(_p.hp == 99 and _p._ming_zhong_holy == 0 and not _b._heroic, "觉醒爆发可被完美闪避且不触发命中收益")
	_check(_b.hp == 43 and _b._awakened and _b._block == 10, "闪身回敬觉醒爆发 4 伤后，鸣钟仍完成觉醒、回血与获得格挡")

	_reset_all()
	_b._start_ming_move(_b.CHAIN)
	_b._cast_tick(0.83)
	_check(_p._ming_zhong_holder == _b, "时停测试前四连击首段已固定玩家")
	_b.time_stop(1.0)
	_check(_p._ming_zhong_holder == null and _b._cast_events.is_empty() and _b.state == CHASE, "时停打断四连击并解除定点与待结算伤害")


func _test_status_effects() -> void:
	_reset_all()
	_p.global_position.x = 1800.0
	_b._start_ming_move(_b.COMBO)
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
	expected = move_toward(0.0, _b.chase_speed * 1.25 * 0.5, _b.accel * 0.016)
	_check(is_equal_approx(_b.velocity.x, expected), "收招后撤速度应用余滞倍率")


func _test_root_motion() -> void:
	_reset_all()
	_b._start_ming_move(_b.COMBO)
	var start_x: float = _b.global_position.x
	_b._root_bone.call("set_x", _b._root_bone_base + 250.0)
	_b.sprite.call("get_skeleton").call("update_world_transform", 0)
	_b._update_root_follow()
	_check(is_equal_approx(_b.global_position.x, start_x - 120.0) and is_equal_approx(_b.sprite.position.x, 120.0), "根骨位移驱动实体且视觉不重复位移")
	_b._reset_root_follow()
	_check(is_equal_approx(_b.global_position.x, start_x - 120.0) and _b.sprite.position == Vector2.ZERO, "收招保留动画末帧位置并清除补偿")
	_check(is_equal_approx(float(_b._root_bone.call("get_x")), _b._root_bone_base), "收招恢复根骨基准")


func _test_pursuit_root_motion() -> void:
	for anim in _b.PURSUIT_ANIMS:
		_reset_all()
		_p.global_position.x = 560.0
		_b._start_ming_move(_b.PURSUIT)
		_b._cast_anim = anim
		_b._cast_duration = float(_b._anim_durations.get(anim, 3.467))
		_b._play(anim, false)
		var start_x: float = _b.global_position.x
		var max_travel := 0.0
		var last_cast_travel := 0.0
		_b.set_physics_process(true)
		while _b.state == _b.S_CAST and _b._cast_elapsed < 4.2:
			await get_tree().create_timer(0.1).timeout
			if _b.state == _b.S_CAST:
				last_cast_travel = _b.global_position.x - start_x
				max_travel = minf(max_travel, last_cast_travel)
		_b.set_physics_process(false)
		_check(max_travel < -300.0, "旋征%s在旋转阶段产生真实位移" % anim)
		_check(last_cast_travel < -300.0, "旋征%s收招保留末帧位移" % anim)
		_check(is_zero_approx(_b.sprite.position.x) and is_zero_approx(_b._root_offset()), "旋征%s收招清除视觉补偿并恢复根骨" % anim)


func _test_hud_bar() -> void:
	_reset_all()
	_b.hp_changed.emit(_b.hp, _b.max_hp)
	_b._block = 12
	await get_tree().create_timer(0.2).timeout
	_check(_room._hud._boss_vital.extra == 12 and _room._hud._boss_vital._extra_root.visible, "鸣钟格挡同步到 Boss 血条白色尾段")
	await _shot("hud_block")
	_b.take_damage(6, 500.0)
	await get_tree().create_timer(0.15).timeout
	_check(_b.hp == 68 and _b._block == 6 and _room._hud._boss_vital.extra == 6, "完全格挡无血量信号时尾段仍实时扣除")
	_b._block = 40
	await get_tree().create_timer(0.15).timeout
	_check(_room._hud._boss_vital.extra == 40, "高格挡尾段同步不丢失")
	_check(_room._hud._boss_bar.position.x + _room._hud._boss_vital.size.x < _room._hud._status_panel.position.x, "高格挡尾段不侵入右上状态区")
	await _shot("hud_block_high")
	_b._block = 0


func _shot(tag: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var err := img.save_png("res://tests/out/ming_zhong_" + tag + ".png")
	p("saved " + tag + " err=" + str(err))


func _test_cleanup_and_execute() -> void:
	_reset_all()
	_p.ming_zhong_hold(_b)
	_b._held_player = _p
	_p.apply_ming_zhong_vulnerability()
	_p.apply_ming_zhong_holy(3)
	_b.hp = 1
	_b.take_damage(2, 500.0)
	_check(_b.state == DEAD, "鸣钟生命归零进入死亡流程")
	_check(_p._ming_zhong_holder == null and is_zero_approx(_p._ming_zhong_vulnerable_time) and _p._ming_zhong_holy == 0, "鸣钟死亡清掉定点、易伤与圣光")
	_p.state = 0
	_p._ming_zhong_holy = 35
	_p.apply_ming_zhong_holy(1)
	_check(_p.hp == 0 and _p.state == _p.State.DEAD, "圣光达到 36层直接秒杀")
