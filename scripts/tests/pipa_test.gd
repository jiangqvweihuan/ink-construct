extends Node

## 绛弦专项回归：真实玩家 / C016 / 投射物，私有入口与手动 tick 避免随机和实时等待。

const PlayerClass := preload("res://scripts/player/player.gd")
const C016Class := preload("res://scripts/enemies/c016.gd")
const ProjectileClass := preload("res://scripts/systems/projectile.gd")
const SpineFX := preload("res://scripts/systems/spine_fx.gd")
const Settings := preload("res://scripts/ui/settings.gd")
const PLAYER_SCENE := preload("res://scenes/player/player.tscn")
const ENEMY_SCENE := preload("res://scenes/enemies/c016.tscn")

class BossTarget:
	extends "res://scripts/enemies/c016.gd"

	func stop_tier() -> String:
		return "boss"

var _log: FileAccess
var _p: PlayerClass
var _enemies: Array = []
var _checks := 0
var _failed := 0
var _saved_forms: Dictionary = {}
var _saved_mastery: Dictionary = {}
var _saved_purchases: Dictionary = {}
var _saved_passives: Dictionary = {}


func p(msg: String) -> void:
	print("[PIPA] ", msg)
	if _log:
		_log.store_line("[PIPA] " + msg)
		_log.flush()


func _check(ok: bool, label: String) -> void:
	_checks += 1
	if not ok:
		_failed += 1
	p(("PASS " if ok else "FAIL ") + label)


func _ready() -> void:
	seed(20261102)
	_log = FileAccess.open("res://tests/pipa_test.log", FileAccess.WRITE)
	# 测试场景不经过主菜单，SFX/Music 总线由 Settings 首次使用时创建，这里先补齐。
	Settings._ensure_bus("SFX")
	Settings._ensure_bus("Music")
	Meta.persist = false
	_saved_forms = Meta.form_nodes.duplicate(true)
	_saved_mastery = Meta.mastery.duplicate(true)
	_saved_purchases = Meta.purchases.duplicate(true)
	_saved_passives = Meta.battle_passives.duplicate(true)
	Run.active = false
	Run.difficulty = 1
	Run.depth = 2
	Run.room_index = 1
	Run.skull_id = "z002"
	Run.upgrades = {}
	Run.guard_available = false
	Run.max_hp_loss = 0

	_test_profile_and_attacks()
	_test_attack_recovery()
	_test_k()
	_test_l()
	_test_charm_and_frenzy()
	_test_awaken_u()
	_test_i()
	_test_o()
	_test_p()
	_test_form_upgrades()
	_test_six_senses()
	_test_red_dust_and_scapegoat()
	_test_sorrow()
	_test_permanent_nodes()
	_test_state_boundaries()
	_test_projectile_audio()
	_test_spine_fx()

	_clear_world()
	Meta.form_nodes = _saved_forms
	Meta.mastery = _saved_mastery
	Meta.purchases = _saved_purchases
	Meta.battle_passives = _saved_passives
	p(("PASS" if _failed == 0 else "FAIL") + " SUMMARY checks=%d failed=%d" % [_checks, _failed])
	get_tree().quit(1 if _failed > 0 else 0)


func _clear_world() -> void:
	C016Class._attacker = null
	for e in _enemies:
		if is_instance_valid(e):
			e.free()
	_enemies.clear()
	for child in get_children():
		if child.get_script() == ProjectileClass or child.has_meta("fx_id"):
			child.free()
	if is_instance_valid(_p):
		_p.free()
	_p = null


func _reset_world(max_hp_value := 40, hp_value := -1) -> void:
	_clear_world()
	Meta.form_nodes.clear()
	Meta.mastery.clear()
	Meta.purchases.clear()
	Meta.battle_passives.clear()
	Run.active = false
	Run.difficulty = 1
	Run.depth = 2
	Run.room_index = 1
	Run.skull_id = "z002"
	Run.upgrades = {}
	Run.guard_available = false
	_p = PLAYER_SCENE.instantiate()
	_p.skull_id = "z002"
	add_child(_p)
	_p.set_physics_process(false)
	_p.attacks = (_p.attacks as Array).duplicate(true)
	_p.skill_config = (_p.skill_config as Dictionary).duplicate(true)
	_p.max_hp = max_hp_value
	_p.hp = max_hp_value if hp_value < 0 else mini(hp_value, max_hp_value)
	_p.global_position = Vector2.ZERO
	_p.facing = 1
	_p._pipa_sorrow_timer = 30.0


func _enemy_at(x: float, hp_value := 100, elite := false, boss := false):
	var e = ENEMY_SCENE.instantiate()
	if boss:
		e.set_script(BossTarget)
	e.type_id = "c016"
	e.position = Vector2(x, 0.0)
	add_child(e)
	e.set_physics_process(false)
	e.set_process(false)
	e.max_hp = hp_value
	e.hp = hp_value
	e._elite = elite
	e._regen_interval = 0.0
	e._regen_amount = 0
	e._super_armor = true
	e._knock_chain.clear()
	e._target = null
	_enemies.append(e)
	return e


func _shots() -> Array:
	var out: Array = []
	for child in get_children():
		if child.get_script() == ProjectileClass and not child.is_queued_for_deletion():
			out.append(child)
	return out


func _test_profile_and_attacks() -> void:
	_reset_world()
	_check(_p.skull_id == "z002" and _p.attacks.size() == 4 \
		and _p.hud_skills == ["run-", "skill03", "skill13-", "skill07_02", "skill10_03", "skill09"], "绛弦四段普攻与六技能栏配置完整")
	var silent_attacks := true
	for atk in _p.attacks:
		silent_attacks = silent_attacks and str(atk.get("cast_sfx", "")).is_empty()
	_check(silent_attacks, "苏挽音四段普攻均不再播放残留挥剑起手音")
	var e = _enemy_at(100.0)
	var expected := [1, 2, 2]
	var before: int = e.hp
	for i in range(3):
		_p._start_attack(i)
		_p._attack_tick(float(_p.attacks[i]["hits"][0]["at"]))
		before -= int(expected[i])
		_check(e.hp == before, "普攻第 %d 段造成 %d 伤" % [i + 1, int(expected[i])])
	_p._start_attack(3)
	_p.audio.sfx_player.stop()
	_p._attack_tick(0.81)
	_check(_shots().is_empty() and not _p.audio.sfx_player.playing, "普攻末段发射前不提前生成魔音或播放发射音")
	_p._attack_tick(0.02)
	var second = _enemy_at(150.0)
	var shots := _shots()
	_check(e.hp == before and shots.size() == 1, "普攻末段在 0.82 秒只发一道魔音而不直接近战结算")
	_check(_p.audio.wave_player.playing and _p.audio.wave_player.stream == _p.audio.cache["pipa_basic_wave"] \
		and not _p.audio.sfx_player.playing, "普攻末段发射魔音时使用独立通道播放新音波音效")
	_p._set_state(PlayerClass.State.RUN)
	_p._play_sfx("player_footstep")
	_check(_p.audio.wave_player.playing and _p.audio.wave_player.stream == _p.audio.cache["pipa_basic_wave"] \
		and _p.audio.sfx_player.stream == _p.audio.cache["player_footstep"], "普攻末段音波发射后，移动与其他音效均不截断播放")
	if shots.is_empty():
		return
	var pr = shots[0]
	_check(pr._damage == 3 and is_equal_approx(pr._speed, 600.0) and is_equal_approx(pr._range, 430.0) \
		and pr._style == "magic_sound" and is_equal_approx(float(pr._effects.get("frenzy", 0.0)), 12.0), "末段魔音为 3 伤、600 速、430 射程并附 12 秒癫狂")
	pr._physics_process(0.02)
	_check(e.hp == before - 3 and is_equal_approx(e._frenzy_time, 12.0), "魔音真实命中扣 3 血并施加癫狂")
	_check(not pr._pierce and second.hp == second.max_hp, "普攻魔音不穿透，首个目标后方敌人不受影响")


func _test_attack_recovery() -> void:
	_reset_world()
	_p._start_attack(0)
	_p._attack_tick(float(_p.attacks[0]["lock"]) + 0.001)
	_check(is_equal_approx(_p._attack_recovery, 1.0), "普攻自然收招进入 1 秒恢复")
	var old_state: int = _p.state
	_p._start_attack(0)
	_check(_p.state == old_state and _p._attack_hits.is_empty(), "恢复期内不能重新起手普攻")
	_p.state = PlayerClass.State.IDLE
	_p._attack_recovery = 0.0
	_p._start_attack(1)
	_p._set_state(PlayerClass.State.IDLE)
	_check(is_equal_approx(_p._attack_recovery, 1.0) and _p._attack_hits.is_empty(), "普攻被移动等状态中断同样进入恢复并清空未结算段")

	_reset_world()
	_p.state = PlayerClass.State.DASH
	_p._dash_timer = 0.0
	_p._dash_cd_set = _p.dash_cooldown
	_p._dash_tick(0.0)
	_p._dash_cd = 0.0 # 模拟冲刺斩或完美闪避返还普通冷却
	Input.action_press("dash")
	_p._try_dash()
	Input.action_release("dash")
	_check(is_equal_approx(_p._dash_gap, 0.5) and _p.state != PlayerClass.State.DASH, "闪避结束后即使冷却返还也须等待 0.5 秒")
	_p._dash_gap = 0.0
	Input.action_press("dash")
	_p._try_dash()
	Input.action_release("dash")
	_check(_p.state == PlayerClass.State.DASH, "闪避最小间隔结束后可以再次闪避")
	_p._dash_gap = 0.0
	_p._return_mark = Vector2(40.0, 0.0)
	_p._return_dash()
	_check(is_equal_approx(_p._dash_gap, 0.5), "银夜返程闪避同样进入 0.5 秒最小间隔")


func _test_k() -> void:
	_reset_world()
	var e = _enemy_at(160.0)
	var cfg: Dictionary = _p.skill_config["run-"]
	_check(cfg.get("pool", []) == ["run-", "skill13_02-cankao"] and cfg.get("hits", []).is_empty(), "K 在两段位移动画中随机且不配置伤害段")
	_check(_p._pose_mixer != null, "K 位移复用山民同款完整姿势混合，避免缺 key 骨骼抽动")
	for anim in ["run-", "skill13_02-cankao"]:
		_p.skill_config["run-"]["pool"] = [anim]
		_p.state = PlayerClass.State.IDLE
		_p._start_skill("run-")
		_p._skill_tick(0.1)
		_check(_p._skill_anim == anim and _p._skill_root_follow and _p._blink_active and _p._invincible \
			and is_zero_approx(_p.velocity.x) and is_equal_approx(float(_p._skill_cds["run-"]), 2.5), "K %s 跟随根位移、无敌穿身且冷却 2.5 秒" % anim)
		_check(e.hp == e.max_hp, "K %s 不对路径敌人造成伤害" % anim)
	_p._set_blink(false)


func _test_l() -> void:
	for anim in ["skill03", "skill04"]:
		_reset_world(20, 8)
		var first = _enemy_at(90.0)
		var second = _enemy_at(130.0)
		first.apply_frenzy(5.0)
		second.apply_frenzy(20.0)
		_p.skill_config["skill03"]["pool"] = [anim]
		_p._start_skill("skill03")
		var at := float(_p.skill_config["skill03"]["hit_at"][anim])
		_check(is_equal_approx(at, 0.68 if anim == "skill03" else 0.84) \
			and is_equal_approx(float(_p._skill_cds["skill03"]), 8.0), "L %s 使用独立伤害帧且冷却 8 秒" % anim)
		_p._skill_tick(at - 0.01)
		_check(_shots().is_empty() and _p.hp == 8, "L %s 曲终前不发音也不回血" % anim)
		_p._skill_tick(0.0101)
		_check(_p.hp == 11 and _shots().size() == 1, "L %s 曲终无需命中即回 3 血并发一道魔音" % anim)
		if _shots().is_empty():
			continue
		var pr = _shots()[0]
		_check(pr._pierce and pr._damage == 3 and bool(pr._effects.get("frenzy_double", false)), "L %s 魔音为 3 伤穿透并翻倍癫狂" % anim)
		pr._physics_process(0.1)
		_check(first.hp == 97 and second.hp == 97, "L %s 同一道穿透魔音可命中两个目标" % anim)
		_check(is_equal_approx(first._frenzy_time, 12.0) and is_equal_approx(second._frenzy_time, 40.0), "L 癫狂翻倍且不足时至少保留 12 秒")
		pr._physics_process(0.01)
		_check(first.hp == 97 and second.hp == 97 and pr._hit_list.size() == 2, "穿透魔音借命中名单防止重复伤害")


func _test_charm_and_frenzy() -> void:
	_reset_world()
	var near = _enemy_at(120.0, 6)
	var far = _enemy_at(240.0, 20)
	var behind = _enemy_at(-80.0, 20)
	near.hp = 2
	_p._start_skill("skill13-")
	_p._skill_tick(0.71)
	_check(near._charm_time <= 0.0, "普通 U 在 0.72 秒前不提前摄心")
	_p._skill_tick(0.0101)
	_check(near.hp == 6 and is_equal_approx(near._charm_time, 15.0), "普通 U 摄心最近前方杂兵，回满并魅惑 15 秒")
	_check(far._charm_time <= 0.0 and behind._charm_time <= 0.0, "普通 U 只选单个前方目标，不波及其他敌人")
	_p._damage_enemy(near, 3)
	_p._damage_enemy(near, 1)
	_check(near.hp == 3, "玩家对魅惑目标伤害减半向上取整且至少 1 伤")

	_reset_world()
	var elite = _enemy_at(100.0, 20, true)
	elite.hp = 5
	_p._deal_charm()
	_check(elite.hp == 20 and is_equal_approx(elite._charm_time, 10.0), "精英被回满并魅惑 10 秒")

	_reset_world()
	var boss = _enemy_at(100.0, 20, false, true)
	boss.hp = 5
	_p._deal_charm()
	_check(boss.hp == 5 and is_equal_approx(boss._charm_time, 5.0), "Boss 只魅惑 5 秒且不回血")

	_reset_world()
	var charmer = _enemy_at(100.0, 30)
	var other = _enemy_at(300.0, 30)
	charmer.apply_charm(15.0)
	charmer._find_target()
	_check(charmer._target == other, "魅惑索敌排除玩家并选择敌方同伴")
	charmer._attack_move = "skill02"
	charmer.facing = 1
	charmer._deal_hit()
	_check(other.hp == 29 and _p.hp == _p.max_hp, "魅惑目标真实攻击敌方同伴")
	charmer._target = _p
	charmer.facing = -1
	charmer._deal_hit()
	_check(_p.hp == _p.max_hp, "魅惑目标即使旧招已起手也不会攻击玩家")
	charmer._charm_time = 0.0
	charmer.apply_frenzy(12.0)
	charmer._find_target()
	_check(charmer._target == _p, "无魅惑时癫狂从敌我双方中选择最近目标")


func _test_awaken_u() -> void:
	_reset_world()
	var far = _enemy_at(1000.0, 50)
	var behind = _enemy_at(-900.0, 50)
	behind.global_position.y = 1000.0
	_p._awaken_time = 8.0
	_p._start_skill("skill13-")
	_check(_p._skill_anim == "skill10" and bool(_p._skill_runtime.get("invincible", false)) \
		and str(_p._skill_runtime.get("cast_sfx", "")) == "pipa_mind_snare", "觉醒 U 切换 skill10 演出、全程无敌并继承普通 U 起手音")
	_p._skill_tick(5.3501)
	_check(far.hp == 49 and behind.hp == 49, "觉醒 U 全屏无视距离、朝向与高度造成 1 伤")
	_check(is_equal_approx(far._frenzy_time, 12.0) and far._frenzy_empowered \
		and is_equal_approx(behind._frenzy_time, 12.0) and behind._frenzy_empowered, "觉醒 U 给全房存活目标 12 秒强化癫狂")


func _test_i() -> void:
	_reset_world(20, 3)
	_p._start_skill("skill07_02")
	_check(_p._skill_poise and not _p._invincible and is_equal_approx(_p._awaken_pending, 8.0) \
		and _p._awaken_time <= 0.0, "I 是霸体而非无敌，觉醒在曲终后才开始")
	_p._skill_tick(0.01)
	_check(_p.hp == 3 and _p._awaken_time <= 0.0, "I 未收招时不提前回血或觉醒")
	_p._skill_tick(_p._skill_timer + 0.001)
	_check(_p.hp == 12, "I 曲终恢复已损生命一半并向上取整")
	_check(is_equal_approx(_p._awaken_time, 8.0) and _p._pipa_awaken_count == 1 and not _p._pipa_o_used, "I 开启 8 秒觉醒、累计次数并重置每觉醒 O 名额")


func _test_o() -> void:
	_run_o_case(1, 8, "首次觉醒")
	_run_o_case(2, 4, "第二次觉醒")
	_test_o_collision_boundaries()


func _run_o_case(awaken_count: int, expected_senses: int, label: String) -> void:
	_reset_world()
	var e = _enemy_at(100.0, 200)
	_p._awaken_time = 8.0
	_p._pipa_awaken_count = awaken_count
	_p._start_skill("skill10_03")
	_check(_p._pipa_o_used and _p._skill_hits.size() == 8 and _shots().is_empty(), "%s O 起手占用名额、准备八段且不提前发弹" % label)
	var expected := [4, 3, 2, 1, 1, 1, 1, 1]
	var elapsed := 0.0
	for i in range(expected.size()):
		var h: Dictionary = _p._skill_hits[0]
		var at := float(h["at"])
		var delta := at - elapsed + 0.0001
		var before: int = e.hp
		_p.audio.sfx_player.stop()
		_p._skill_tick(delta)
		elapsed += delta
		var shots := _shots()
		_check(shots.size() == 1 and int(e.hp) == before, "%s O 第 %d 段只发一颗弹，发射本身不扣血" % [label, i + 1])
		_check(_p.audio.sfx_player.playing and _p.audio.sfx_player.stream == _p.audio.cache["pipa_eight_tones"], "%s O 第 %d 段发射时播放一次八音" % [label, i + 1])
		var shot = shots[0] if shots.size() == 1 else null
		_check(shot != null and ["E53008", "E53009"].has(str(shot._effects.get("fx_id", ""))) \
			and str(shot._effects.get("fx_anim", "")) == "action" and is_instance_valid(shot._spine_fx) \
			and is_equal_approx(float(shot._effects.get("fx_scale", 0.0)), 0.35) and is_equal_approx(shot._size, 0.75) \
			and not shot._pierce and is_equal_approx(shot._range, 2000.0), "%s O 第 %d 段使用随机双色小火弹、非穿透且射程覆盖房间" % [label, i + 1])
		if shot != null:
			shot._physics_process(0.02)
		var actual: int = before - int(e.hp)
		_check(actual == int(expected[i]), "%s O 第 %d 段碰撞伤害：期望 %d，实际 %d" % [label, i + 1, int(expected[i]), actual])
	_check(e._six_senses == expected_senses, "%s O 六感层数为 %d" % [label, expected_senses])
	_p.state = PlayerClass.State.IDLE
	_p._skill_cds["skill10_03"] = 0.0
	var cast_id: int = _p._skill_cast_id
	Input.action_press("skill_o")
	_p._try_skill()
	Input.action_release("skill_o")
	_check(_p._skill_cast_id == cast_id, "%s 内不能再次释放 O" % label)
	_p._pipa_o_used = false
	Input.action_press("skill_o")
	_p._try_skill()
	Input.action_release("skill_o")
	_check(_p._skill_cast_id == cast_id + 1, "新觉醒名额恢复后可再次释放 O")


func _test_o_collision_boundaries() -> void:
	_reset_world()
	var first = _enemy_at(60.0, 200)
	var second = _enemy_at(80.0, 200)
	_p._awaken_time = 8.0
	_p._pipa_awaken_count = 1
	_p._start_skill("skill10_03")
	_p._skill_tick(0.5501)
	var shots := _shots()
	if not shots.is_empty():
		shots[0]._physics_process(0.02)
		_check(first.hp == 196 and second.hp == 200 and first._six_senses == 1 and second._six_senses == 0 \
			and shots[0].is_queued_for_deletion(), "O 火弹只伤害并减益首个碰撞目标，随后销毁")
	else:
		_check(false, "O 非穿透测试需要首段火弹")

	_reset_world()
	var missed = _enemy_at(-100.0, 100)
	_p._awaken_time = 8.0
	_p._pipa_awaken_count = 1
	_p._start_skill("skill10_03")
	_p._skill_tick(0.5501)
	shots = _shots()
	if not shots.is_empty():
		shots[0]._physics_process(3.2)
		_check(missed.hp == 100 and missed._six_senses == 0 and _p._pipa_wave_hits.is_empty() \
			and shots[0].is_queued_for_deletion(), "O 火弹未命中则耗程自毁，不造成伤害或六感")
	else:
		_check(false, "O 未命中测试需要首段火弹")


func _test_p() -> void:
	_reset_world()
	var e = _enemy_at(400.0, 100)
	e.add_grudge(2)
	e.apply_six_senses(3)
	e.apply_frenzy(4.0)
	e.apply_charm(3.0)
	_p._bleed_stacks = 2
	_p._bleed_time = 3.0
	_p._cripple_time = 4.0
	_p._awaken_time = 8.0
	_check(e.mind_status_count() == 9, "心魔引按层数与每 2 秒一层统计全部状态")
	_p._start_skill("skill09")
	var hit_at := float(_p.skill_config["skill09"]["hits"][0]["at"])
	var voice = _p.audio.cache["pipa_inner_demon"] as AudioStream
	_check(_p._skill_anim == "skill16_02-" and is_equal_approx(_p._skill_dur, 5.333333) \
		and voice != null and hit_at > voice.get_length(), "P 使用第 100 号完整动画，伤害帧晚于心魔引音效")
	_check(_p._skill_poise and is_equal_approx(float(_p._skill_cds["skill09"]), 22.0), "P 具有霸体且冷却 22 秒")
	_p._skill_tick(0.9201)
	_check(e.hp == 100 and e.mind_status_count() == 9, "P 不再于旧伤害帧提前引爆")
	_p._skill_tick(4.55 - 0.9201)
	_check(e.hp == 100 and e.mind_status_count() == 9, "P 音效结束前不造成伤害或清空状态")
	_p._skill_tick(4.61 - 4.55)
	_check(e.hp == 83, "P 音效结束后以基础 8 伤加 9 层状态造成 17 伤")
	_check(e._grudge == 0 and e._six_senses == 0 and e._frenzy_time <= 0.0 and e._charm_time <= 0.0, "P 引爆后清空被计入的敌人状态")
	_check(e._bleed_stacks == 2 and is_equal_approx(e._root_timer, 4.0), "P 将自身流血与致残分赠给引爆后存活目标")
	_check(_p._bleed_stacks == 0 and _p._cripple_time <= 0.0, "P 转移后净化自身对应减益")
	_check(_p.state == PlayerClass.State.SKILL and _p._skill_timer > 0.0, "P 伤害后继续播放第 100 号动画而不截断")
	_p._skill_tick(_p._skill_timer + 0.001)
	_check(_p.state != PlayerClass.State.SKILL, "P 完整动画结束后才收招")


func _test_form_upgrades() -> void:
	var card_count := 0
	var links_valid := true
	for key in Run.FORM_UPGRADES:
		var info: Dictionary = Run.FORM_UPGRADES[key]
		if not (info["forms"] as Array).has("z002"):
			continue
		card_count += 1
		var tier := int(info["tier"])
		if tier > 1:
			var req := str(info.get("req", ""))
			links_valid = links_valid and Run.FORM_UPGRADES.has(req) and int(Run.FORM_UPGRADES[req]["tier"]) == tier - 1
	_check(card_count == 9 and links_valid, "万狂同奏包含三条完整且前置正确的三阶流派")

	_reset_world()
	Run.upgrades = {"z002_chorus_1": 1}
	_p.set_upgrades(Run.upgrades)
	var target = _enemy_at(100.0)
	var near = _enemy_at(140.0)
	var second = _enemy_at(180.0)
	var far = _enemy_at(400.0)
	_p._spawn_projectile({"style": "magic_sound", "speed": 600.0, "range": 430.0, "frenzy": 12.0}, 3, "")
	var shots := _shots()
	if not shots.is_empty():
		shots[0]._physics_process(0.1)
		_check(is_equal_approx(target._frenzy_time, 12.0) and is_equal_approx(near._frenzy_time, 6.0) \
			and is_equal_approx(second._frenzy_time, 6.0) and far._frenzy_time <= 0.0, "乱弦初阶向最近两名周围敌人传染 6 秒癫狂")

	_reset_world()
	Run.upgrades = {"z002_chorus_2": 1, "z002_chorus_3": 1}
	_p.set_upgrades(Run.upgrades)
	var attacker = _enemy_at(100.0, 30)
	var victim = _enemy_at(200.0, 30)
	attacker.apply_frenzy(8.0)
	victim.take_damage_from(3, attacker)
	_check(victim.hp == 27 and is_equal_approx(victim._frenzy_time, 4.0) and victim._grudge == 1 and victim._six_senses == 1, "乱弦续极在癫狂敌人互伤后传染并附加怨与六感尽失")
	var sealed_victim = _enemy_at(300.0, 30)
	_p._passive_seal_time = 8.0
	sealed_victim.take_damage_from(3, attacker)
	_check(sealed_victim._frenzy_time <= 0.0 and sealed_victim._grudge == 0 and sealed_victim._six_senses == 0, "被动封印期间万狂同奏不会生效")

	_reset_world()
	Run.upgrades = {"z002_allure_1": 1}
	_p.set_upgrades(Run.upgrades)
	var primary = _enemy_at(100.0, 30)
	var boss = _enemy_at(130.0, 20, false, true)
	var extra = _enemy_at(170.0, 30)
	var outside = _enemy_at(420.0, 30)
	primary.hp = 4
	extra.hp = 3
	_p._deal_charm()
	_check(primary.hp == 30 and is_equal_approx(primary._charm_time, 15.0) and extra.hp == 3 \
		and is_equal_approx(extra._charm_time, 6.0) and boss._charm_time <= 0.0 and outside._charm_time <= 0.0, "同梦初阶额外魅惑一名附近非首领且不回血")

	_reset_world()
	Run.upgrades = {"z002_allure_2": 1, "z002_allure_3": 1}
	_p.set_upgrades(Run.upgrades)
	var charmer = _enemy_at(100.0, 30)
	var ally_victim = _enemy_at(200.0, 30)
	charmer.apply_charm(19.5)
	ally_victim.take_damage_from(3, charmer)
	_check(ally_victim.hp == 24 and is_equal_approx(charmer._charm_time, 20.0), "同梦续极使魅惑互伤翻倍并延长且封顶 20 秒")

	_reset_world()
	Run.upgrades = {"z002_mind_1": 1}
	_p.set_upgrades(Run.upgrades)
	var preserved = _enemy_at(100.0, 100)
	preserved.add_grudge(2)
	preserved.apply_six_senses(3)
	preserved.apply_frenzy(4.0)
	_p._skill_name = "skill09"
	_p._skill_cds["skill09"] = 22.0
	_p._deal_mind_detonate()
	_check(preserved.hp == 85 and preserved._six_senses == 3 and preserved._grudge == 0 and preserved._frenzy_time <= 0.0, "心魔初阶只保留存活目标的六感尽失")

	_reset_world()
	Run.upgrades = {"z002_mind_2": 1}
	_p.set_upgrades(Run.upgrades)
	_enemy_at(100.0, 5)
	_enemy_at(200.0, 5)
	_p._skill_name = "skill09"
	_p._skill_cds["skill09"] = 22.0
	_p._deal_mind_detonate()
	_check(is_equal_approx(float(_p._skill_cds["skill09"]), 16.0), "心魔续阶按直接引爆击杀数返还冷却")

	_reset_world()
	Run.upgrades = {"z002_mind_3": 1}
	_p.set_upgrades(Run.upgrades)
	var burst = _enemy_at(0.0, 5)
	var splash = _enemy_at(100.0, 100)
	var beyond = _enemy_at(400.0, 100)
	_p._skill_name = "skill09"
	_p._skill_cds["skill09"] = 22.0
	_p._deal_mind_detonate()
	_check(burst.hp <= 0 and splash.hp == 89 and is_equal_approx(splash._frenzy_time, 6.0) \
		and beyond.hp == 92 and beyond._frenzy_time <= 0.0, "心魔极阶在引爆后溅射近敌并附加癫狂且不波及远处")


func _test_six_senses() -> void:
	_reset_world()
	var e = _enemy_at(100.0, 50)
	e.apply_six_senses(3)
	e._start_attack("skill01")
	_check(e.hp == 50, "六感尽失不被独立普攻触发")
	e._start_attack("skill02", true)
	_check(e.hp == 50, "六感尽失不被连段接续重复触发")
	e._start_attack("skill02")
	_check(e.hp == 47, "六感尽失在非普攻独立起手时结算对应层数伤害")


func _test_red_dust_and_scapegoat() -> void:
	_reset_world(40)
	var e = _enemy_at(50.0, 100)
	e._target = _p
	e._attack_move = "skill03"
	e.facing = -1
	e._grudge = 0
	e._deal_hit()
	_check(_p.hp == 38 and e._grudge == 1, "红尘在每个实伤段给攻击者叠 1 层怨")
	_p._hurt_invincible = 0.0
	e._grudge = 3
	e._deal_hit()
	_check(_p.hp == 37, "3 层怨使敌人每段 2 伤降为 1 伤")
	_p._hurt_invincible = 0.0
	e._grudge = 6
	e._deal_hit()
	_check(_p.hp == 36, "6 层怨继续减伤但每段最低仍为 1")
	_p._hurt_invincible = 0.0
	e._grudge = 6
	e.apply_frenzy(12.0, true)
	e._target = _p
	e._deal_hit()
	_check(_p.hp == 34, "强化癫狂在怨减伤后将每段最终伤害翻倍")

	_reset_world(20, 3)
	var scapegoat = _enemy_at(100.0, 100)
	var bystander = _enemy_at(200.0, 100)
	scapegoat.apply_frenzy(12.0)
	_p.hurt(6)
	_check(_p.hp == 1, "须臾把致命伤改为保留 1 生命")
	_check(scapegoat.hp == 92 and scapegoat._red_scapegoat_used and bystander.hp == 100, "须臾只选择癫狂目标，转承双倍溢出 8 伤并标记已用")
	var returned: int = _p._try_pipa_scapegoat(5)
	_check(returned == 5 and scapegoat.hp == 92 and bystander.hp == 100, "同一目标不能再次替死，无候选时保留原伤害")


func _test_sorrow() -> void:
	_reset_world()
	var e = _enemy_at(500.0, 100)
	e.apply_bleed(1)
	e._poison_time = 2.0
	e._root_timer = 3.0
	e.add_grudge(2)
	e.apply_six_senses(2)
	e.apply_frenzy(4.0)
	e.apply_charm(3.0)
	_p._pipa_sorrow_timer = 0.01
	_p._pipa_passive_tick(0.01)
	_check(_p.audio.sfx_player.playing and _p.audio.sfx_player.stream == _p.audio.cache["pipa_sorrow"], "神伤全屏波纹触发时播放专属音效")
	_check(e.hp == 97 and is_equal_approx(_p._pipa_sorrow_timer, 30.0), "神伤 5 伤经魅惑减半为 3，并重置 30 秒计时")
	_check(e._mind_shock == 1 and e._bleed_stacks == 2 and is_equal_approx(e._bleed_time, 10.0) \
		and is_equal_approx(e._poison_time, 7.0) and is_equal_approx(e._root_timer, 8.0), "神伤增幅：shock=%d bleed=%d/%.2f poison=%.2f root=%.2f" % [e._mind_shock, e._bleed_stacks, e._bleed_time, e._poison_time, e._root_timer])
	_check(e._grudge == 3 and e._six_senses == 3 and is_equal_approx(e._frenzy_time, 9.0) \
		and is_equal_approx(e._charm_time, 8.0), "神伤同步强化怨、六感、癫狂与魅惑")
	_p._pipa_passive_tick(29.9)
	_check(e.hp == 97, "神伤未到下一间隔不会重复结算")
	_p._pipa_passive_tick(0.1001)
	_check(e.hp == 94, "神伤下一周期再次经魅惑结算 3 伤")


func _test_permanent_nodes() -> void:
	_reset_world(20, 8)
	Meta.form_nodes["z002_echo_1"] = true
	Meta.form_nodes["z002_echo_2"] = true
	Meta.form_nodes["z002_echo_3"] = true
	var echo_target = _enemy_at(90.0, 100)
	echo_target.apply_frenzy(5.0)
	_p.skill_config["skill03"]["pool"] = ["skill03"]
	_p._start_skill("skill03")
	_p._skill_tick(0.6801)
	var shots := _shots()
	_check(is_equal_approx(float(_p._skill_cds["skill03"]), 7.0) and _p.hp == 12 and shots.size() == 1, "余音续极分别使 L 冷却 -1 秒并额外回 1 血")
	if not shots.is_empty():
		shots[0]._physics_process(0.1)
		_check(is_equal_approx(echo_target._frenzy_time, 14.0), "余音初阶使魔音癫狂基础与最小时长 +2 秒")

	_reset_world()
	Meta.form_nodes["z002_charm_1"] = true
	Meta.form_nodes["z002_charm_3"] = true
	var charmed = _enemy_at(100.0, 10)
	_p._deal_charm()
	charmed._pipa_status_tick(18.0)
	_check(is_equal_approx(charmed._charm_time, 0.0) and charmed._grudge == 3, "缚心初阶延长非 Boss 魅惑，极阶在结束时附 3 层怨")

	_reset_world()
	Meta.form_nodes["z002_charm_1"] = true
	var boss = _enemy_at(100.0, 20, false, true)
	_p._deal_charm()
	_check(is_equal_approx(boss._charm_time, 5.0), "缚心初阶不延长 Boss 魅惑")

	_reset_world()
	Meta.form_nodes["z002_charm_2"] = true
	var awaken_target = _enemy_at(500.0, 50)
	_p._awaken_time = 8.0
	_p._start_skill("skill13-")
	_p._skill_tick(5.3501)
	_check(awaken_target.hp == 48, "缚心续阶使觉醒 U 全房伤害 +1")

	_reset_world()
	Meta.form_nodes["z002_grudge_1"] = true
	_p._pipa_sorrow_timer = 0.01
	_p._pipa_passive_tick(0.01)
	_check(is_equal_approx(_p._pipa_sorrow_timer, 27.0), "红尘初阶把神伤间隔缩至 27 秒")

	_reset_world()
	Meta.form_nodes["z002_grudge_2"] = true
	var detonate_target = _enemy_at(100.0, 100)
	_p._deal_mind_detonate()
	_check(detonate_target.hp == 90, "红尘续阶把心魔引基础伤害提高到 10")

	_reset_world()
	Meta.form_nodes["z002_grudge_3"] = true
	var senses_target = _enemy_at(100.0, 20)
	senses_target.apply_six_senses(2)
	senses_target._start_attack("skill02")
	_check(senses_target.hp == 17, "红尘极阶使六感尽失触发额外造成 1 点固定伤害")


func _test_state_boundaries() -> void:
	_reset_world()
	_enemy_at(160.0)
	_p.skill_config["run-"]["pool"] = ["run-"]
	_p._start_skill("run-")
	_p._skill_tick(0.1)
	_p.swap_skull("z000")
	_check(not _p._blink_active and not _p._skill_root_follow and not _p._invincible \
		and _p._skill_runtime.is_empty() and _p._skill_hits.is_empty(), "K 位移中换头会清理穿身、根骨跟随、无敌与待结算段")
	_p.swap_skull("z002")
	_p.skill_config = (_p.skill_config as Dictionary).duplicate(true)
	_p.skill_config["run-"]["pool"] = ["run-"]
	_p._start_skill("run-")
	_check(_p.skull_id == "z002" and _p._skill_anim == "run-" and not _p._skill_runtime.is_empty(), "换回绛弦后技能运行配置使用独立副本，可再次起手")

	_reset_world()
	_p._start_skill("skill03")
	_p._skill_tick(0.1)
	_p.hurt(1)
	_check(_p.state == PlayerClass.State.HURT and _p._skill_hits.is_empty() and _shots().is_empty(), "L 被受击中断后不会曲终补发魔音")
	_p.state = PlayerClass.State.IDLE
	_p._awaken_time = 0.0
	_p._buff_timer = 0.0
	_p._perfect_dodge()
	var cast_id: int = _p._skill_cast_id
	for action in ["skill_o", "skill_p"]:
		Input.action_press(action)
		_p._try_skill()
		Input.action_release(action)
	_check(_p._buff_timer > 0.0 and _p._awaken_time <= 0.0 and _p._skill_cast_id == cast_id,
		"完美闪避只保留普通加伤，不会误解锁 O 与 P")

	_p._pipa_sorrow_timer = 3.0
	_p._pipa_awaken_count = 4
	_p._pipa_o_used = true
	_p._apply_profile("z002")
	_check(is_equal_approx(_p._pipa_sorrow_timer, 30.0) and _p._pipa_awaken_count == 0 \
		and not _p._pipa_o_used and _p._skill_runtime.is_empty(), "新房重装形态时重置神伤计时与每房觉醒运行状态")

	_reset_world(20, 1)
	_enemy_at(0.0)
	_p.skill_config["run-"]["pool"] = ["run-"]
	_p._start_skill("run-")
	_p._skill_tick(0.1)
	_p._start_skill_loop("pipa_eight_tones")
	_p._skill_hits.append({"at": 99.0})
	_p._skill_audio_events.append({"at": 99.0, "sfx": "pipa_string_step"})
	_p._delayed.append({"time": 99.0, "kind": "test"})
	_p._skill_teleport = 50.0
	_p._awaken_pending = 8.0
	_p._skill_poise = true
	_p._skill_reflect = true
	_p._skill_ranged_guard = true
	_p._skill_cancel_ready = true
	_p._parry_ready = true
	_p._bell_shell = true
	_p._shield_hits = 1
	_p._shield_time = 3.0
	Run.supply_revive = true
	Run.supply_revive_used = false
	_p.hp = 0
	var revived: bool = _p._try_revive(Vector2.ZERO)
	_check(revived and _p.state == PlayerClass.State.HURT and _p.hp == 4 and not _p.audio._loop_active \
		and not _p.audio._loop_player.playing and not _p._blink_active and not _p._skill_root_follow \
		and not _p._invincible, "技能中复活会停止循环音并收掉穿身、根骨跟随与技能无敌")
	_check(_p._skill_hits.is_empty() and _p._skill_audio_events.is_empty() and _p._delayed.is_empty() \
		and _p._skill_runtime.is_empty() and _p._skill_name.is_empty() and is_zero_approx(_p._skill_timer) \
		and is_zero_approx(_p._skill_teleport) and is_zero_approx(_p._awaken_pending) \
		and not _p._skill_poise and not _p._skill_reflect and not _p._skill_ranged_guard \
		and not _p._skill_cancel_ready and not _p._parry_ready and not _p._bell_shell \
		and _p._shield_hits == 0 and is_zero_approx(_p._shield_time), "复活清空技能待结算事件、运行配置与防御取消窗口")
	Run.supply_revive = false
	Run.supply_revive_used = false

	_reset_world()
	_check(_p.audio.sfx_player.bus == "SFX" and _p.audio._loop_player.bus == "SFX", "玩家普通与循环音效均走 SFX 总线")
	_p.cooldown_scale = 0.5
	_p._start_skill("skill03")
	_p._skill_cds["skill03"] = 2.0
	_p.state = PlayerClass.State.IDLE
	_p._start_skill("run-")
	_check(is_equal_approx(float(_p._skill_cd_totals["skill03"]), 4.0) \
		and is_equal_approx(_p.get_skill_cd_ratio("skill03"), 0.5) \
		and is_equal_approx(float(_p._skill_cd_totals["run-"]), 1.25) \
		and is_equal_approx(_p.get_skill_cd_ratio("run-"), 1.0), "后续技能不会覆盖前一技能本次实际总冷却与比例")


func _direct_spine(root: Node, fx_id := "", role := "") -> Array:
	var out: Array = []
	for child in root.get_children():
		if not child.has_meta("fx_id"):
			continue
		if not fx_id.is_empty() and str(child.get_meta("fx_id")) != fx_id:
			continue
		if not role.is_empty() and str(child.get_meta("fx_role", "")) != role:
			continue
		out.append(child)
	return out


func _test_spine_fx() -> void:
	# 第四段普攻：飞行为 E54055，真实命中才生成 E54056；癫狂沿用 C016 状态所有者。
	_reset_world()
	var target = _enemy_at(100.0, 100)
	_p._start_attack(3)
	_p._attack_tick(0.82)
	var shots := _shots()
	_check(shots.size() == 1 and is_instance_valid(shots[0]._spine_fx) \
		and str(shots[0]._spine_fx.get_meta("fx_id")) == "E54055" \
		and str(shots[0]._spine_fx.get_meta("fx_anim")) == "action", "第四段远程剑气飞行使用 E54055 action")
	if not shots.is_empty():
		shots[0]._physics_process(0.02)
		var hit_nodes := _direct_spine(self, "E54056", "hit")
		_check(hit_nodes.size() == 1 and str(hit_nodes[0].get_meta("fx_anim")) == "action",
			"第四段剑气真实命中生成 E54056 action")
		target._sync_status_effects()
		var frenzy_fx = target._status_fx.get("frenzy")
		_check(is_instance_valid(frenzy_fx) and str(frenzy_fx.get_meta("fx_id")) == "E52007" \
			and is_equal_approx(float(frenzy_fx._lifetime), -1.0), "癫狂由目标持有点头顶 E52007 持续特效")
		target._frenzy_time = 0.0
		target._sync_status_effects()
		_check(not target._status_fx.has("frenzy") and frenzy_fx.is_queued_for_deletion(), "癫狂结束由目标释放 E52007")

	# 黍离：height 是投射物本地拟合尺寸，父节点再乘一次 _size；动画速度跟实际弹速同比。
	_reset_world()
	_p.skill_config["skill03"]["pool"] = ["skill03"]
	_p.skill_config["skill03"]["projectile"]["scale"] = 1.75
	_p.skill_config["skill03"]["projectile"]["speed"] = 780.0
	_p._start_skill("skill03")
	_p._skill_tick(0.6801)
	shots = _shots()
	_check(shots.size() == 1 and str(shots[0]._effects.get("fx_id", "")) == "E100129" \
		and is_equal_approx(float(shots[0]._effects.get("fx_height", 0.0)), 110.0) \
		and is_equal_approx(float(shots[0]._size), 1.75) \
		and is_equal_approx(float(shots[0]._effects.get("fx_speed", 0.0)), 1.2),
		"黍离 E100129 高度保持 110、父节点负责尺寸倍率且弹速比例为 1.2")
	if not shots.is_empty():
		_check(is_instance_valid(shots[0]._spine_fx) and is_equal_approx(float(shots[0]._spine_fx._fit_height), 110.0) \
			and bool(shots[0]._spine_fx._center), "黍离运行时按 bounds 拟合高度并居中对齐")

	# I 的起手演出与真正的觉醒持续特效分属两个阶段。
	_reset_world(20, 3)
	_p._start_skill("skill07_02")
	var cast_nodes := _direct_spine(_p, "E53174", "awaken_cast")
	_check(cast_nodes.size() == 1 and str(cast_nodes[0].get_meta("fx_anim")) == "action" \
		and cast_nodes[0].position.is_equal_approx(Vector2.ZERO) and not is_instance_valid(_p.fx.awaken_spine),
		"苏挽音 I 起手荷花在脚下地面生成，不提前生成觉醒环绕")
	_p._skill_tick(_p._skill_timer + 0.001)
	var awaken = _p.fx.awaken_spine
	_check(is_instance_valid(awaken) and str(awaken.get_meta("fx_id")) == "E100172" \
		and str(awaken.get_meta("fx_anim")) == "action" and awaken.position.is_equal_approx(Vector2(0.0, -64.0)) \
		and bool(awaken._center), "苏挽音 I 收招后以胸口为中心生成 E100172 持续环绕")
	_p._awaken_time = 0.0
	_p.fx.sync_persistent(_p.state == _p.State.DEAD)
	_check(_p.fx.awaken_spine == null and awaken.is_queued_for_deletion(), "苏挽音觉醒结束释放 E100172")

	# O 不再于起手额外生成视觉弹，八颗真实弹及逐次发音由 _test_o 完整检查。
	_reset_world()
	_p._awaken_time = 8.0
	_p._start_skill("skill10_03")
	shots = _shots()
	_check(shots.is_empty() and _p._skill_hits.size() == 8 and not _p.audio._loop_active,
		"苏挽音 O 起手无视觉弹且不循环播放八音")

	# 神伤以视口宽度拟合 6400 原始素材，视觉中心仍位于玩家上方。
	_reset_world()
	_p._pipa_sorrow_timer = 0.0
	_p._pipa_passive_tick(0.01)
	var sorrow_nodes := _direct_spine(self, "E54061", "sorrow")
	_check(sorrow_nodes.size() == 1 and is_equal_approx(float(sorrow_nodes[0]._fit_width), get_viewport().get_visible_rect().size.x) \
		and bool(sorrow_nodes[0]._center) and sorrow_nodes[0].position.is_equal_approx(Vector2(0.0, -180.0)),
		"神伤 E54061 按视口宽度拟合并居中于玩家上方")
	if not sorrow_nodes.is_empty():
		var data = SpineFX.data("E54061")
		var animation = data.call("find_animation", "action")
		_check(is_equal_approx(float(sorrow_nodes[0]._lifetime), float(animation.call("get_duration"))),
			"神伤一次性特效按 action 真实时长销毁")


func _test_projectile_audio() -> void:
	_reset_world()
	var target = _enemy_at(0.0, 100)
	var pr = ProjectileClass.new()
	pr.setup(1, 0.0, 100.0, 1, "weapon_sword", false, 0.0, 1, "dagger")
	add_child(pr)
	pr.global_position = Vector2.ZERO
	pr._physics_process(0.0)
	var split_child_count := 0
	for shot in _shots():
		if shot._from_split:
			split_child_count += 1
	_check(target.hp == 99 and split_child_count == 1 and pr._sfx_player != null \
		and pr._sfx_player.bus == "SFX" and pr._sfx_player.playing and not pr.visible \
		and not pr.is_queued_for_deletion(), "分裂首次命中保留分裂行为并走统一命中音与 SFX 总线")
