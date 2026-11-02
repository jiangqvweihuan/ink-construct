extends Node

## 绛弦专项回归：真实玩家 / C016 / 投射物，私有入口与手动 tick 避免随机和实时等待。

const PlayerClass := preload("res://scripts/player/player.gd")
const C016Class := preload("res://scripts/enemies/c016.gd")
const ProjectileClass := preload("res://scripts/systems/projectile.gd")
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
		if child.get_script() == ProjectileClass:
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
	var e = _enemy_at(100.0)
	var expected := [1, 2, 2]
	var before: int = e.hp
	for i in range(3):
		_p._start_attack(i)
		_p._attack_tick(float(_p.attacks[i]["hits"][0]["at"]))
		before -= int(expected[i])
		_check(e.hp == before, "普攻第 %d 段造成 %d 伤" % [i + 1, int(expected[i])])
	_p._start_attack(3)
	_p._attack_tick(0.82)
	var second = _enemy_at(150.0)
	var shots := _shots()
	_check(e.hp == before and shots.size() == 1, "普攻末段在 0.82 秒只发一道魔音而不直接近战结算")
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
		_check(_p.hp == 10 and _shots().size() == 1, "L %s 曲终无需命中即回 2 血并发一道魔音" % anim)
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
	_check(_p._skill_anim == "skill10" and bool(_p._skill_runtime.get("invincible", false)), "觉醒 U 切换 skill10 演出并全程无敌")
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


func _run_o_case(awaken_count: int, expected_senses: int, label: String) -> void:
	_reset_world()
	var e = _enemy_at(100.0, 200)
	_p._awaken_time = 8.0
	_p._pipa_awaken_count = awaken_count
	_p._start_skill("skill10_03")
	_check(_p._pipa_o_used and _p._skill_hits.size() == 8, "%s O 起手即占用名额并准备八段判定" % label)
	var expected := [4, 3, 2, 1, 1, 1, 1, 1]
	var elapsed := 0.0
	for i in range(expected.size()):
		var h: Dictionary = _p._skill_hits[0]
		var at := float(h["at"])
		var delta := at - elapsed + 0.0001
		var before: int = e.hp
		_p._skill_tick(delta)
		elapsed += delta
		var actual: int = before - int(e.hp)
		_check(actual == int(expected[i]), "%s O 第 %d 段伤害：期望 %d，实际 %d" % [label, i + 1, int(expected[i]), actual])
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
	_check(_p._skill_poise and is_equal_approx(float(_p._skill_cds["skill09"]), 22.0), "P 具有霸体且冷却 22 秒")
	_p._skill_tick(0.9201)
	_check(e.hp == 83, "P 以基础 8 伤加 9 层状态造成 17 伤")
	_check(e._grudge == 0 and e._six_senses == 0 and e._frenzy_time <= 0.0 and e._charm_time <= 0.0, "P 引爆后清空被计入的敌人状态")
	_check(e._bleed_stacks == 2 and is_equal_approx(e._root_timer, 4.0), "P 将自身流血与致残分赠给引爆后存活目标")
	_check(_p._bleed_stacks == 0 and _p._cripple_time <= 0.0, "P 转移后净化自身对应减益")


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
	_check(is_equal_approx(float(_p._skill_cds["skill03"]), 7.0) and _p.hp == 11 and shots.size() == 1, "余音续极分别使 L 冷却 -1 秒并额外回 1 血")
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
	_p._start_skill("run-")
	_check(_p.skull_id == "z002" and _p._skill_anim == "run-" and not _p._skill_runtime.is_empty(), "换回绛弦后技能运行配置使用独立副本，可再次起手")

	_reset_world()
	_p._start_skill("skill03")
	_p._skill_tick(0.1)
	_p.hurt(1)
	_check(_p.state == PlayerClass.State.HURT and _p._skill_hits.is_empty() and _shots().is_empty(), "L 被受击中断后不会曲终补发魔音")
	_p.state = PlayerClass.State.IDLE
	_p._awaken_time = 0.0
	var cast_id: int = _p._skill_cast_id
	for action in ["skill_o", "skill_p"]:
		Input.action_press(action)
		_p._try_skill()
		Input.action_release(action)
	_check(_p._skill_cast_id == cast_id, "觉醒结束后 O 与 P 都立即重新锁定")

	_p._pipa_sorrow_timer = 3.0
	_p._pipa_awaken_count = 4
	_p._pipa_o_used = true
	_p._apply_profile("z002")
	_check(is_equal_approx(_p._pipa_sorrow_timer, 30.0) and _p._pipa_awaken_count == 0 \
		and not _p._pipa_o_used and _p._skill_runtime.is_empty(), "新房重装形态时重置神伤计时与每房觉醒运行状态")
