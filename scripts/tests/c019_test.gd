extends Node2D

## C019 双形态 Boss 自检：一阶段配置、空血切形态、二阶段强化、总血量对标鸣钟。

const BossTypes = preload("res://scripts/enemies/boss_types.gd")
const C019Script = preload("res://scripts/enemies/c019.gd")
const Codex = preload("res://scripts/ui/codex_panel.gd")
const StatusCodex = preload("res://scripts/ui/status_codex.gd")
const AchievementsDef = preload("res://scripts/systems/achievements.gd")

var _checks := 0
var _failed := 0


class FakeTarget extends Node2D:
	var hp := 100
	var body_radius := 30.0
	var last_damage := 0

	func hurt(amount: int, _kb: Vector2, _source, _move: Dictionary) -> void:
		last_damage = amount
		hp -= amount


func _check(ok: bool, label: String) -> void:
	_checks += 1
	if not ok:
		_failed += 1
	print("[C019] ", ("PASS " if ok else "FAIL "), label)


func _ready() -> void:
	Run.balance_scaling = false
	Meta.persist = false
	var p1: Dictionary = BossTypes.get_boss("c019")
	var p2: Dictionary = BossTypes.get_boss("c019_sp")
	var c032: Dictionary = BossTypes.get_boss("c032")
	_check(BossTypes.BOSSES.has("c019") and BossTypes.BOSSES.has("c019_sp"), "双形态 Boss 配置已注册")
	_check(not BossTypes.ROSTER.has("c019_sp"), "二阶段形态不单独进随机池")
	_check(BossTypes.codex_order().has("c019") and not BossTypes.ROSTER.has("c019"), "图鉴收录剑冢但不进随机轮换")
	_check(BossTypes.encounter_pool().has("c019"), "番外首领已加入普通 / 无尽可遭遇池")
	_check(int(p1["hp"]) + int(p2["hp"]) == int(c032["hp"]), "双阶段总血量对标鸣钟 68")
	var p1_attacks: Array = p1["stages"][0]["attacks"]
	var p2_attacks: Array = p2["stages"][0]["attacks"]
	_check(p1_attacks.size() + p2_attacks.size() >= 8, "双阶段共 8 个独立招式")
	_check(p1_attacks.size() == 4 and p2_attacks.size() == 4, "每阶段 4 招")
	# 二阶段是近身 Boss：所有招式触发窗口必须覆盖 keep_dist，否则会被后退逻辑卡成永不触发
	var p2_keep := float(p2["keep_dist"])
	var p2_windows_ok := true
	for move in p2_attacks:
		if float((p2["attack_rules"] as Dictionary).get(move, {}).get("max", 0.0)) < p2_keep:
			p2_windows_ok = false
	_check(p2_windows_ok, "二阶段全部招式触发窗口覆盖 keep_dist")
	var d1 = load(str(p1["data"]))
	var d2 = load(str(p2["data"]))
	_check(d1 != null and bool(d1.call("is_skeleton_data_loaded")), "一阶段骨架可加载")
	_check(d2 != null and bool(d2.call("is_skeleton_data_loaded")), "二阶段骨架可加载")
	_check(absf(float(d1.call("get_height")) * float(p1["scale"]) - 200.0) < 30.0, "一阶段体型约 200px")
	# 骨架包围盒含召唤剑阵约 464px；站姿本体实测 426.7px × 0.58 ≈ 247px，大于一阶段 202px
	_check(absf(float(d2.call("get_height")) * float(p2["scale"]) - 463.5) < 30.0, "二阶段体型包围盒约 464px")

	# 图鉴内容完整性：背景、8 招名称/机制/来历、两阶段被动、词条与成就
	_check(Codex.LORE.has("c019") and not str(Codex.LORE["c019"]).is_empty(), "剑冢背景故事已录入")
	var codex_moves_ok := true
	for fid in ["c019", "c019_sp"]:
		var names: Dictionary = Codex.ENEMY_ATTACK_NAMES.get(fid, {})
		var mechs: Dictionary = Codex.ENEMY_ATTACK_MECH.get(fid, {})
		var lores: Dictionary = Codex.ENEMY_ATTACK_LORE.get(fid, {})
		for key in names:
			if str(mechs.get(key, "")) == "" or str(lores.get(key, "")) == "":
				codex_moves_ok = false
	_check(codex_moves_ok and (Codex.ENEMY_ATTACK_NAMES["c019"] as Dictionary).size() == 4 \
		and (Codex.ENEMY_ATTACK_NAMES["c019_sp"] as Dictionary).size() == 4, "8 招名称/机制/来历齐全")
	_check((Codex.ENEMY_PASSIVES.get("c019", []) as Array).size() == 2, "两阶段被动词条已录入")
	var c019_tags: Array = StatusCodex.tags_for("c019")
	_check(c019_tags.has("首领") and c019_tags.size() == 5, "剑冢人物词条已录入")
	var status_ids: Array = []
	for entry in StatusCodex.entries():
		status_ids.append(str(entry["id"]))
	_check(status_ids.has("sword_momentum") and status_ids.has("wanren_grief"), "守冢剑势/万刃同悲状态词条已录入")
	var beast_record: Dictionary = {}
	for b in AchievementsDef.BEASTS:
		if str(b["id"]) == "c019":
			beast_record = b
	_check(bool(beast_record.get("boss", false)) and bool(beast_record.get("bonus", false)), "成就名录已收录剑冢（独立首领）")
	var ach_ok := false
	for a in AchievementsDef.ACHIEVEMENTS:
		if str(a["id"]) == "e_c019":
			ach_ok = true
	_check(ach_ok, "剑冢专属成就已注册")

	var boss = load("res://scenes/enemies/bosses/boss.tscn").instantiate()
	boss.set_script(C019Script)
	boss.type_id = "c019"
	boss.hp_scale = 1.0
	boss.cd_scale = 1.0
	boss.position = Vector2(500, 560)
	add_child(boss)
	await get_tree().process_frame
	_check(boss.max_hp == 32 and boss.hp == 32, "一阶段生命 32")
	_check(boss._attack_anims.size() == 4 and boss._damage_map.get("p1_thrust", 0) == 2, "一阶段通用招式表注入")
	_check(absf(boss._ranges.get("p1_rain", [])[2] - 335.0) < 0.001, "飞锋末段射程 335")
	_check(boss._hit_at_map.get("p1_rain", [])[0] == 0.31, "飞锋首段命中帧 0.31")
	_check(boss._attack_rules.get("p1_rain", {}).get("cooldown", 0.0) == 16.0, "飞锋冷却 16 秒")

	# 一阶段普攻实际结算
	var target := FakeTarget.new()
	target.position = Vector2(700, 560)
	target.hp = 100
	add_child(target)
	boss.facing = 1
	boss._target = target

	# 一阶段被动「守冢剑势」：技能实伤积层 -> 断岳起手消耗增伤
	boss._attack_move = "p1_rain"
	boss._attack_visual = "skill01"
	boss._attack_cast_id += 1
	boss._attack_hit_landed = false
	boss._p1_mark_cast = -1
	boss._p1_marks = 0
	boss._deal_hit(0)
	_check(boss._p1_marks == 1, "技能实伤积累 1 层剑势")
	boss._p1_marks = 2
	boss._p1_thrust_bonus = 0
	boss.state = boss.State.IDLE
	boss._start_attack("p1_thrust")
	_check(boss._p1_thrust_bonus == 2 and boss._p1_marks == 0, "断岳起手消耗全部剑势")
	_check(boss._damage_of("p1_thrust", 0) == 4, "2 层剑势使断岳 2→4 伤")
	boss._p1_marks = 5
	boss._p1_thrust_bonus = 0
	boss.state = boss.State.IDLE
	boss._start_attack("p1_thrust")
	_check(boss._p1_thrust_bonus == 2 and boss._p1_marks == 0, "剑势消耗上限 2 层")
	# 复位，继续验证未叠剑势时的基础伤害
	boss._p1_thrust_bonus = 0
	boss._attack_hits_left.clear()
	boss._attack_timer = 0.0
	boss._release_token()
	boss.state = boss.State.IDLE
	boss._attack_move = "p1_thrust"
	boss._attack_visual = "skill06"
	boss._attack_cast_id += 1
	boss._attack_hit_landed = false
	boss._p1_mark_cast = -1
	target.hp = 100
	boss._deal_hit(0)
	_check(target.last_damage == 2 and target.hp == 98, "断岳飞锋命中 2 伤")
	target.hp = 0

	# 一阶段空血 -> 换形态
	boss.take_damage(999, 0.0)
	_check(boss._phase_two and boss.state == boss.S_TRANSFORM and boss._invincible, "一阶段空血进入换形态演出")
	_check(boss.hp == 0, "换形态期间一阶段血条清零")
	var waited := 0.0
	while waited < 5.0 and boss.type_id != "c019_sp":
		await get_tree().create_timer(0.1).timeout
		waited += 0.1
	_check(boss.type_id == "c019_sp", "换形态完成后切到 C019_sp")
	_check(boss._p1_marks == 0 and boss._p1_thrust_bonus == 0, "换形态清空剑势")
	_check(boss.max_hp == 36 and boss.hp == 36, "二阶段生命 36 / 满血")
	_check(boss._attack_anims.size() == 4 and boss._damage_map.get("p2_rain", 0) == 4, "二阶段招式表注入")
	_check(absf(boss._scale - 0.58) < 0.001, "二阶段体型缩放 0.58")
	_check(absf(boss._ranges.get("p2_prison", 0.0) - 406.0) < 0.001, "剑狱天倾射程按新体型换算 406")
	# 等二阶段登场演出结束
	waited = 0.0
	while waited < 2.0 and boss._invincible:
		await get_tree().create_timer(0.1).timeout
		waited += 0.1
	_check(not boss._invincible, "二阶段登场演出结束后解除无敌")
	# 二阶段不再积累一阶段剑势
	boss._attack_move = "p2_prison"
	boss._attack_cast_id += 1
	boss._attack_hit_landed = false
	boss._p1_mark_cast = -1
	boss._p1_marks = 0
	boss._deal_hit(0)
	_check(boss._p1_marks == 0, "二阶段不再积累剑势")

	# 二阶段半血强化
	boss.hp = 18
	boss.attack_cooldown = 2.1
	boss.chase_speed = 170.0
	boss.take_damage(1, 0.0)
	_check(boss._phase2_enraged, "二阶段半血触发万刃同悲")
	_check(absf(boss.attack_cooldown - 1.68) < 0.001 and absf(boss.chase_speed - 195.5) < 0.001, "万刃同悲提速 20% / 15%")
	_check(absf(boss.attack_damage_mul() - 1.15) < 0.001, "万刃同悲伤害 +15%")

	boss.take_damage(999, 0.0)
	_check(boss.state == boss.State.DEAD, "二阶段空血正常死亡")

	# 斗蛐蛐：换形后保留面板调好的生命 / 出手 / 移速，不跳回配置值
	var duel_boss = load("res://scenes/enemies/bosses/boss.tscn").instantiate()
	duel_boss.set_script(C019Script)
	duel_boss.type_id = "c019"
	duel_boss.duel_mode = true
	duel_boss.position = Vector2(900, 560)
	add_child(duel_boss)
	await get_tree().process_frame
	duel_boss.max_hp = 50
	duel_boss.hp = 50
	duel_boss.attack_cooldown = 1.0
	duel_boss.chase_speed = 200.0
	duel_boss._start_phase_two()
	duel_boss._swap_to_phase_two()
	_check(duel_boss.type_id == "c019_sp" and duel_boss.max_hp == 50 and duel_boss.hp == 50 \
		and absf(duel_boss.attack_cooldown - 1.0) < 0.001 and absf(duel_boss.chase_speed - 200.0) < 0.001,
		"斗蛐蛐换形保留面板生命/出手/移速")
	duel_boss.queue_free()
	print("[C019] DONE checks=%d failed=%d" % [_checks, _failed])
	print("[C019] 自动测试已完成，场景将退出；实测战斗请运行 res://scenes/tests/c019_arena.tscn")
	get_tree().quit()
