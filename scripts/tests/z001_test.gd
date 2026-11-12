extends Node2D

## 烬生·Z001 机制回归：动画映射、三段普攻、K 六段、L 斩杀、I 满血、O 路径秒杀、P 眩晕、
## 受击阈值、燃尽、战狂与换房清空。

const PlayerClass := preload("res://scripts/player/player.gd")
const Skulls = preload("res://scripts/player/skulls.gd")
const BattleStatus = preload("res://scripts/ui/battle_status.gd")
const Codex = preload("res://scripts/ui/codex_panel.gd")

var _checks := 0
var _failed := 0


class Target extends Node2D:
	var hp := 100
	var max_hp := 100
	var stop_kind := "mob"
	var stunned := 0.0
	var vulnerable := 0.0
	var vulnerable_ratio := 0.0
	var _vuln_timer := 0.0
	var body_radius := 30.0

	func take_damage(amount: int, _source_x := 0.0) -> void:
		hp = maxi(0, hp - amount)

	func take_damage_from(amount: int, _source: Node) -> void:
		take_damage(amount)

	func stop_tier() -> String:
		return stop_kind

	func stun(dur: float) -> void:
		stunned = maxf(stunned, dur)

	func apply_vulnerable(time: float, ratio: float) -> void:
		_vuln_timer = maxf(_vuln_timer, time)
		vulnerable = time
		vulnerable_ratio = ratio

	func is_on_floor() -> bool:
		return true

	func damage_taken_scale() -> float:
		return 1.0


func _check(ok: bool, label: String) -> void:
	_checks += 1
	if not ok:
		_failed += 1
	print("[Z1] ", ("PASS " if ok else "FAIL "), label)


func _make_player() -> PlayerClass:
	var p = load("res://scenes/player/player.tscn").instantiate()
	p.skull_id = "z001"
	p.position = Vector2(400, 560)
	add_child(p)
	p.set_physics_process(false)
	return p


func _target(x: float, hp := 100) -> Target:
	var t := Target.new()
	t.hp = hp
	t.max_hp = hp
	t.position = Vector2(x, 560)
	t.add_to_group("enemies")
	add_child(t)
	return t


func _ready() -> void:
	Run.balance_scaling = false
	Meta.persist = false
	# 清掉真实存档里可能已购的 z001 修炼/局内卡，保证机制回归可重复
	for id in Meta.FORM_NODES:
		if str(Meta.FORM_NODES[id]["form"]) == "z001":
			Meta.form_nodes.erase(id)
	for id in Run.FORM_UPGRADES:
		if (Run.FORM_UPGRADES[id]["forms"] as Array).has("z001"):
			Run.upgrades.erase(id)
	# 契合等级会带来普攻 +1，机制回归按无契合基线校验
	Meta.mastery["z001"] = 0
	var p := _make_player()
	var bonus := Achievements.bonus_int("damage")
	var base_data = load(str(Skulls.SKULLS["z001"]["data"]))
	var base_names := {}
	for a in base_data.call("get_animations"):
		base_names[str(a.call("get_name"))] = true

	# 图鉴排序与解锁条件：烬生必须紧跟绛弦，且双条件完全一致
	var z1_unlock: Dictionary = Meta.UNLOCKS.get("z001", {})
	var z2_unlock: Dictionary = Meta.UNLOCKS.get("z002", {})
	_check(int(z1_unlock.get("clears", -1)) == int(z2_unlock.get("clears", -2)) \
		and int(z1_unlock.get("kills", -1)) == int(z2_unlock.get("kills", -2)) \
		and str(z1_unlock.get("hint", "")) == str(z2_unlock.get("hint", "")), "烬生与绛弦解锁条件完全一致")
	var form_order: Array = Skulls.ids()
	_check(form_order.find("z001") == form_order.find("z002") + 1, "烬生图鉴条目排在绛弦之后")

	# 形态表 / 动画映射
	_check(p.anim_map["idle"] == "stand" and p.anim_map["run"] == "run", "待机 123 / 跑步 69 映射正确")
	_check(p.hud_skills.size() == 5 and BattleStatus.skill_name(p, 0) == "焚骨三叩" \
		and BattleStatus.skill_name(p, 4) == "烬火燎原", "HUD 五技能名称与招式表对齐")
	_check(p.anim_map["low_idle"] == "weak" and p.anim_map["dead"] == "dead", "虚弱 126 / 死亡 48 映射正确")
	_check(p._knock_chain == ["atked_heavy", "atked_fall_end", "getup"], "≥5 伤走 27 → 26 → 50 倒地链")
	_check(p._jump_seg and p.anim_map["jump_mid"] == "jump02_mid" and p.anim_map["jump_down"] == "jump03_down" \
		and p.anim_map["jump_land"] == "jump03_end", "跳跃 53 / 56 / 57 且无起跳过渡")
	var pool: Array = p._dash_pool.get("move", [])
	_check(pool.size() == 2 and str(pool[0]["anim"]) == "autorush" and str(pool[1]["anim"]) == "dash_front", "闪避 28 / 47 随机池")
	var d0: float = float(pool[0]["time"]) * float(pool[0]["speed"])
	var d1: float = float(pool[1]["time"]) * float(pool[1]["speed"])
	_check(absf(d0 - 127.0) <= 2.0 and absf(d1 - 130.0) <= 2.0, "两段闪避位移都在 130px 左右")

	# 普攻配置：动画 2 三段 2 / 2 / 3，末段 10 秒易伤
	var atk: Dictionary = p.attacks[0]
	var hits: Array = atk["hits"]
	_check(str(atk["anim"]) == "3" and hits.size() == 3, "J 绑定动画 2 并分三段")
	_check(int(hits[0]["damage"]) == 2 and int(hits[1]["damage"]) == 2 and int(hits[2]["damage"]) == 3, "J 伤害 2 / 2 / 3")
	_check(absf(float(hits[0]["at"]) - 0.38) < 0.001 and absf(float(hits[1]["at"]) - 0.94) < 0.001 \
		and absf(float(hits[2]["at"]) - 1.82) < 0.001, "J 命中帧对齐三次挥击峰值")
	_check(absf(float(hits[0]["range"]) - 90.0) < 0.001 and absf(float(hits[1]["range"]) - 125.0) < 0.001 \
		and absf(float(hits[2]["range"]) - 115.0) < 0.001, "J 三段射程对齐剪影")
	_check(float(hits[2]["vulnerable"]["time"]) == 10.0, "J 末段易伤 10 秒")
	var tj := _target(450, 100)
	p._attack_idx = 0
	p._deal_hit({"damage": 3, "range": 200.0, "height": 200.0,
		"vulnerable": {"ratio": 0.25, "time": 10.0}})
	_check(tj.hp == 100 - 3 - bonus and tj.vulnerable == 10.0, "J 末段命中实际挂上 10 秒易伤")
	tj.hp = 0
	var tj_edge := _target(400 + 90 + 30 - 1, 100)
	p._deal_hit({"damage": 2, "range": 90.0, "height": 200.0})
	_check(tj_edge.hp == 100 - 2 - bonus, "J 首段在 90px 边缘命中")
	tj_edge.hp = 0
	var tj_far := _target(400 + 90 + 30 + 10, 100)
	p._deal_hit({"damage": 2, "range": 90.0, "height": 200.0})
	_check(tj_far.hp == 100, "J 首段超出 90px 不命中")
	tj_far.hp = 0

	# K：动画 6 连播 3 次，每轮 2 段 1 伤，合计 6
	p._skill_cds.clear()
	p._start_skill("burn_k")
	_check(p._skill_anim == "atk03" and p._skill_hits.size() == 6, "K 连播 3 次 × 2 段")
	_check(absf(float(p._skill_hits[0]["at"]) - 0.12) < 0.001 and absf(float(p._skill_hits[1]["at"]) - 0.22) < 0.001,
		"K 命中帧对齐双峰 0.12 / 0.22")
	_check(absf(float(p.skill_config["burn_k"]["range"]) - 170.0) < 0.001 \
		and not bool(p.skill_config["burn_k"].get("both", false)), "K 射程 170 且只判身前")
	var total := 0
	for h in p._skill_hits:
		total += int(h["damage"])
	_check(total == 6, "K 总伤害 6")
	_check(absf(p._skill_dur - 0.45 * 3.0) < 0.001, "K 总时长 = 3 个动画周期（实际 %.3f）" % p._skill_dur)
	var tk := _target(450, 100)
	var k_hits: Array = p._skill_hits.duplicate(true)
	p._skill_hits.clear()
	for hh in k_hits:
		p._deal_skill_hit(hh)
	_check(tk.hp == 100 - 6 - 6 * bonus, "K 六段实际结算合计 6 伤")
	tk.hp = 0
	var tk_far := _target(700, 100)
	p._skill_name = "burn_k"
	p._skill_start_x = p.global_position.x
	p._deal_skill_hit({"at": 0.0, "damage": 1, "range": 170.0, "height": 200.0})
	_check(tk_far.hp == 100, "K 超出 170px 不命中")
	tk_far.hp = 0
	for round in 3:
		var tr := _target(450, 100)
		p.state = p.State.IDLE
		p._skill_timer = 0.0
		p._skill_cds.clear()
		p._start_skill("burn_k")
		var round_hits: Array = p._skill_hits.duplicate(true)
		p._skill_hits.clear()
		for hh in round_hits:
			p._deal_skill_hit(hh)
		_check(tr.hp == 100 - 6 - 6 * bonus, "K 第 %d 轮六段伤害稳定" % (round + 1))
		tr.hp = 0

	# L：5 + 已损生命 20%（Boss 10%）
	var lcfg: Dictionary = p.skill_config["burn_l"]
	var lh: Dictionary = lcfg["hits"][0]
	_check(absf(float(lh["at"]) - 1.21) < 0.001 and absf(float(lh["range"]) - 150.0) < 0.001,
		"L 命中帧 1.21s / 射程 150 对齐落刀峰值")
	var t := _target(450, 50)
	t.max_hp = 100
	p._skill_name = "burn_l"
	p._skill_start_x = p.global_position.x
	p._deal_skill_hit({"at": 0.0, "damage": 5, "range": 150.0, "height": 200.0,
		"execute": {"normal": 0.2, "boss": 0.1}})
	_check(t.hp == 50 - 15 - bonus, "L 对普通目标 5 + 已损 50 的 20% = 15")
	t.hp = 50
	t.max_hp = 100
	t.stop_kind = "boss"
	p._deal_skill_hit({"at": 0.0, "damage": 5, "range": 150.0, "height": 200.0,
		"execute": {"normal": 0.2, "boss": 0.1}})
	_check(t.hp == 50 - 10 - bonus, "L 对 Boss 追伤改为已损 10% = 10")
	t.hp = 0
	var tl_edge := _target(400 + 150 + 30 - 1, 100)
	p._skill_start_x = p.global_position.x
	p._deal_skill_hit({"at": 0.0, "damage": 5, "range": 150.0, "height": 200.0})
	_check(tl_edge.hp == 100 - 5 - bonus, "L 在 150px 边缘命中")
	tl_edge.hp = 0
	var tl_far := _target(400 + 150 + 30 + 10, 100)
	p._deal_skill_hit({"at": 0.0, "damage": 5, "range": 150.0, "height": 200.0})
	_check(tl_far.hp == 100, "L 超出 150px 不命中")
	tl_far.hp = 0

	# O：路径小怪秒杀 / 精英固定 8
	var ocfg: Dictionary = p.skill_config["burn_o"]
	var oh: Dictionary = ocfg["hits"][0]
	_check(absf(float(oh["at"]) - 0.95) < 0.001 and absf(float(oh["range"]) - 150.0) < 0.001,
		"O 命中帧 0.95s / 射程 150 对齐现身斩")
	t.hp = 30
	t.max_hp = 30
	t.stop_kind = "mob"
	p._skill_start_x = p.global_position.x - 60.0
	p._deal_skill_hit({"at": 0.0, "range": 150.0, "height": 140.0, "path": true, "damage": 8,
		"dash_kill": {"elite_damage": 8}})
	_check(t.hp == 0, "O 路径普通小怪直接秒杀")
	t.hp = 50
	t.max_hp = 50
	t.stop_kind = "elite"
	p._deal_skill_hit({"at": 0.0, "range": 150.0, "height": 140.0, "path": true, "damage": 8,
		"dash_kill": {"elite_damage": 8}})
	_check(t.hp == 42, "O 对精英固定 8 伤")
	t.hp = 0
	var to_far := _target(400 + 150 + 30 + 40, 100)
	p._skill_start_x = p.global_position.x
	p._deal_skill_hit({"at": 0.0, "range": 150.0, "height": 140.0, "path": true, "damage": 8,
		"dash_kill": {"elite_damage": 8}})
	_check(to_far.hp == 100, "O 落点超出 150px 不命中")
	to_far.hp = 0

	# P：正前方 12 伤 + 5 秒眩晕
	var pcfg: Dictionary = p.skill_config["burn_p"]
	var ph: Dictionary = pcfg["hits"][0]
	_check(absf(float(ph["at"]) - 0.34) < 0.001 and absf(float(ph["range"]) - 280.0) < 0.001,
		"P 命中帧 0.34s / 射程 280 对齐火线")
	t.hp = 100
	t.max_hp = 100
	t.stunned = 0.0
	p._skill_start_x = p.global_position.x
	p._deal_skill_hit({"at": 0.0, "damage": 12, "range": 280.0, "height": 200.0, "stun": 5.0})
	_check(t.hp == 100 - 12 - bonus and t.stunned == 5.0, "P 12 伤 + 5 秒眩晕")
	t.hp = 0
	var tp_edge := _target(400 + 280 + 30 - 1, 100)
	p._deal_skill_hit({"at": 0.0, "damage": 12, "range": 280.0, "height": 200.0, "stun": 5.0})
	_check(tp_edge.hp == 100 - 12 - bonus and tp_edge.stunned == 5.0, "P 在 280px 边缘命中并眩晕")
	tp_edge.hp = 0
	var tp_far := _target(400 + 280 + 30 + 10, 100)
	p._deal_skill_hit({"at": 0.0, "damage": 12, "range": 280.0, "height": 200.0, "stun": 5.0})
	_check(tp_far.hp == 100 and tp_far.stunned == 0.0, "P 超出 280px 不命中")
	tp_far.hp = 0

	# 受击阈值：≤4 不打断技能；≥5 进入倒地链
	p.hp = 10
	p.max_hp = 10
	p.state = p.State.SKILL
	p._skill_name = "burn_l"
	p._skill_timer = 1.0
	p._hurt_invincible = 0.0
	p.hurt(4, Vector2.ZERO, null)
	_check(p.hp == 6 and p.state == p.State.SKILL, "≤4 伤不硬直、不打断技能")
	p.hp = 10
	p.state = p.State.IDLE
	p._hurt_invincible = 0.0
	p._knock_cd = 0.0
	p.hurt(5, Vector2.ZERO, null)
	_check(p.state == p.State.HURT and not p._hurt_chain.is_empty(), "≥5 伤触发倒地链")

	# I：回满生命
	p.state = p.State.IDLE
	p._skill_cds.clear()
	p.hp = 3
	p.max_hp = 10
	p._start_skill("burn_i")
	_check(p.hp == p.max_hp, "I 将生命恢复至满值")

	# 燃尽：致命伤不死亡并保留 1 点生命，后续伤害扣上限；回血退出
	p.state = p.State.IDLE
	p._hurt_invincible = 0.0
	p.hp = 3
	p.max_hp = 10
	p.hurt(5, Vector2.ZERO, null)
	_check(p.hp == 1 and bool(p._z001_burnout) and p.state != p.State.DEAD, "致命伤进入燃尽并保留 1 点生命")
	p._hurt_invincible = 0.0
	p.hurt(4, Vector2.ZERO, null)
	_check(p.max_hp == 6 and p.hp == 1 and bool(p._z001_burnout), "燃尽期间伤害改为扣生命上限")
	p._restore_hp(2)
	_check(not bool(p._z001_burnout) and p.hp == 3, "获得回血立即退出燃尽并正常回血")

	# 持续伤害不能绕过燃尽：割伤 / 焚鼎灼烧只扣上限，不直接判死
	p.state = p.State.IDLE
	p.max_hp = 10
	p.hp = 1
	p._z001_burnout = true
	p._cut_damage({"attacker": null, "move": {}})
	_check(p.max_hp == 9 and p.hp == 1 and p.state != p.State.DEAD, "燃尽期间割伤只扣生命上限")
	var t_burn := _target(450, 100)
	p._fen_ding_burn_stacks = 1
	p._fen_ding_burn_left = 0.0
	p._fen_ding_burn_source = t_burn
	p._fen_ding_burn_tick(0.0)
	_check(p.max_hp == 8 and p.hp == 1 and p.state != p.State.DEAD, "燃尽期间灼烧只扣生命上限")
	p.clear_fen_ding_burn()

	# 上限清零才判死
	p.max_hp = 1
	p.hp = 1
	p._z001_burnout = true
	p._hurt_invincible = 0.0
	p.hurt(5, Vector2.ZERO, null)
	_check(p.state == p.State.DEAD and p.hp == 0, "生命上限清零后判定死亡")

	# 战狂：5 次受击 / 5 次击杀各叠 1 层；伤害追加；换房清空
	var p2 := _make_player()
	p2._z001_fury = 0
	p2._z001_hit_acc = 0
	p2._z001_kill_acc = 0
	for i in 4:
		p2._z001_on_hit_taken()
	_check(p2._z001_fury == 0, "受击 4 次未叠战意")
	p2._z001_on_hit_taken()
	_check(p2._z001_fury == 1, "受击 5 次叠 1 层战意")
	p2._z001_kill_acc = 4
	p2._z001_on_kill()
	_check(p2._z001_fury == 2, "击杀 5 次再叠 1 层战意")
	var t2 := _target(450, 100)
	var before := t2.hp
	p2._damage_enemy(t2, 5)
	_check(before - t2.hp == 5 + 2 + bonus, "每层战意追加等量焚烧伤害")
	p2.on_room_enter()
	_check(p2._z001_fury == 0 and p2._z001_kill_acc == 0 and p2._z001_hit_acc == 0, "换房清空战意与累计")

	# ---------- 局内流派 / 永久修炼：烬生专属 ----------
	var z1_cards: Array = []
	var z1_paths := {}
	for id in Run.FORM_UPGRADES:
		var info: Dictionary = Run.FORM_UPGRADES[id]
		if (info["forms"] as Array).has("z001"):
			z1_cards.append(str(id))
			z1_paths[str(info["path"])] = int(z1_paths.get(str(info["path"]), 0)) + 1
	var path_counts_ok := z1_paths.size() == 3
	for k in z1_paths:
		path_counts_ok = path_counts_ok and int(z1_paths[k]) == 3
	_check(z1_cards.size() == 9 and path_counts_ok, "烬生局内 3 流派 × 3 阶齐全（%d 张）" % z1_cards.size())
	var z1_nodes: Array = []
	for id in Meta.FORM_NODES:
		if str(Meta.FORM_NODES[id]["form"]) == "z001":
			z1_nodes.append(str(id))
	var cost_ok := z1_nodes.size() == 9
	for id in z1_nodes:
		cost_ok = cost_ok and [35, 65, 110].has(Meta.node_cost(str(id)))
	_check(cost_ok and Meta.INK_SHOP.has("buyout_z001"), "烬生永久修炼 9 节点/价格梯度/买断齐全")
	_check(not Run.card_info("z001_ember_1").is_empty() and not Run.card_info("z001_exec_1").is_empty() \
		and not Run.card_info("z001_rage_1").is_empty(), "烬生三流派首阶均进入局内卡池")
	Run.skull_id = "z001"
	Run.slot_skull[0] = "z001"
	var rolled := Run.roll_cards(3, 0)
	var rolled_z1 := 0
	for k in rolled:
		if (Run.FORM_UPGRADES.get(str(k), {}).get("forms", []) as Array).has("z001"):
			rolled_z1 += 1
	_check(rolled_z1 >= 1, "烬生局内三选一能抽到专属流派")

	# 焚骨：K 命中挂易伤；对易伤目标增伤
	var p3 := _make_player()
	Run.upgrades["z001_ember_1"] = 1
	p3._upgrades = Run.upgrades.duplicate()
	var tv := _target(450, 100)
	p3._skill_name = "burn_k"
	p3._skill_start_x = p3.global_position.x
	p3._deal_skill_hit({"at": 0.0, "damage": 1, "range": 170.0, "height": 200.0})
	_check(tv.vulnerable == 3.0 and tv._vuln_timer == 3.0, "焚骨·初：K 命中挂 3 秒易伤")
	Run.upgrades["z001_ember_2"] = 1
	p3._upgrades = Run.upgrades.duplicate()
	tv.hp = 100
	tv._vuln_timer = 3.0
	var hp_before := tv.hp
	p3._deal_skill_hit({"at": 0.0, "damage": 1, "range": 170.0, "height": 200.0})
	_check(hp_before - tv.hp == 2 + bonus, "焚骨·续：K 对易伤目标 +1 伤")
	# 烬灭：L 斩杀比例提高
	Run.upgrades["z001_exec_1"] = 1
	p3._upgrades = Run.upgrades.duplicate()
	var te := _target(450, 50)
	te.max_hp = 100
	p3._skill_name = "burn_l"
	p3._skill_start_x = p3.global_position.x
	p3._deal_skill_hit({"at": 0.0, "damage": 5, "range": 150.0, "height": 200.0,
		"execute": {"normal": 0.2, "boss": 0.1}})
	_check(te.hp == 50 - 5 - 15 - bonus, "烬灭·初：L 对普通目标斩杀 30%")
	# L→P 增伤窗口
	Run.upgrades["z001_exec_2"] = 1
	p3._upgrades = Run.upgrades.duplicate()
	te.hp = 0
	var tl_p := _target(450, 100)
	p3._skill_name = "burn_l"
	p3._deal_skill_hit({"at": 0.0, "damage": 5, "range": 150.0, "height": 200.0})
	_check(is_equal_approx(p3._z001_p_buff, 2.0), "烬灭·续：L 命中开启 2 秒 P 增伤")
	tl_p.hp = 100
	p3._skill_name = "burn_p"
	p3._skill_start_x = p3.global_position.x
	p3._deal_skill_hit({"at": 0.0, "damage": 12, "range": 280.0, "height": 200.0})
	_check(tl_p.hp == 100 - 15 - bonus, "烬灭·续：增伤窗口内 P 伤害 +3")
	# 战狂：4 次一叠
	Run.upgrades["z001_rage_1"] = 1
	var p4 := _make_player()
	p4._upgrades = Run.upgrades.duplicate()
	p4._z001_fury = 0
	p4._z001_kill_acc = 0
	for i in 3:
		p4._z001_on_kill()
	_check(p4._z001_fury == 0, "战狂·初：3 次击杀未叠战意")
	p4._z001_on_kill()
	_check(p4._z001_fury == 1, "战狂·初：第 4 次击杀叠 1 层")
	# 战狂·极：燃尽时获得 3 层；燃尽减伤
	Run.upgrades["z001_rage_3"] = 1
	p4._upgrades = Run.upgrades.duplicate()
	p4._z001_burnout = false
	p4.max_hp = 10
	p4.hp = 1
	p4._z001_fury = 0
	p4._z001_enter_burnout()
	_check(p4._z001_fury == 3 and p4._z001_burnout, "战狂·极：燃尽触发获得 3 层战意")
	p4.max_hp = 10
	p4.hp = 1
	p4._z001_fury = 3
	p4._z001_burnout = true
	p4._z001_burnout_take_damage(5)
	_check(p4.max_hp == 8, "战狂·极：燃尽期间每层战意减少 1 点上限伤害")
	# 永久修炼：4 次一叠 / 燃尽减伤 / 燃尽 3 杀复燃
	Run.upgrades.clear()
	p4._upgrades = {}
	Meta.form_nodes["z001_p_fury_1"] = true
	p4._z001_fury = 0
	p4._z001_kill_acc = 3
	p4._z001_burnout = false
	p4._z001_on_kill()
	_check(p4._z001_fury == 1, "战意·初：永久修炼把阈值降到 4 次")
	Meta.form_nodes["z001_p_burnout_2"] = true
	p4._z001_fury = 0
	p4.max_hp = 10
	p4.hp = 1
	p4._z001_burnout = true
	p4._z001_burnout_take_damage(5)
	_check(p4.max_hp == 6, "余烬·续：燃尽上限伤害再 -1")
	Meta.form_nodes["z001_p_burnout_3"] = true
	p4.max_hp = 10
	p4.hp = 1
	p4._z001_burnout = true
	p4._z001_burnout_kills = 0
	p4._z001_kill_acc = 0
	for i in 3:
		p4._z001_on_kill()
	_check(not p4._z001_burnout and p4.hp == 3, "余烬·极：燃尽期间 3 杀回 2 血并退出燃尽")
	# 战斗状态栏能读到战意/燃尽
	p4._z001_fury = 2
	p4._z001_burnout = true
	var status_ids := {}
	for e in BattleStatus.entries(p4):
		status_ids[str(e["id"])] = true
	_check(status_ids.has("z001_fury") and status_ids.has("z001_burnout"), "战斗状态栏显示战意与燃尽")
	# 清理测试态，避免影响后续图鉴检查
	Run.upgrades.clear()
	for id in Meta.FORM_NODES:
		if str(Meta.FORM_NODES[id]["form"]) == "z001":
			Meta.form_nodes.erase(id)

	# 图鉴文案与实际逻辑一致
	var atk_text: Array = Codex.FORM_ATTACK_TEXT.get("z001", [])
	_check(atk_text.size() == 1 and str(atk_text[0]["num"]).contains("2 / 2 / 3") \
		and str(atk_text[0]["num"]).contains("10 秒"), "图鉴普攻说明包含三段伤害与 10 秒易伤")
	var passives: Array = Codex.FORM_PASSIVES.get("z001", [])
	_check(passives.size() == 2 and str(passives[0]["desc"]).contains("1 点生命") \
		and str(passives[0]["desc"]).contains("生命上限"), "图鉴燃尽说明与最低生命阈值一致")
	var skill_text: Array = Codex.FORM_SKILL_TEXT.get("z001", [])
	_check(skill_text.size() == 5, "图鉴五条主动技能说明齐全")
	_check(str(skill_text[3]["num"]).contains("240") and str(skill_text[3]["num"]).contains("8 伤"),
		"图鉴 O 位移与固定伤害说明一致")
	_check(str(skill_text[4]["num"]).contains("280") and str(skill_text[4]["num"]).contains("5 秒"),
		"图鉴 P 范围与眩晕说明一致")
	var lore := str(Codex.LORE.get("z001", ""))
	_check(lore.length() > 120 and lore.contains("墨堂") and lore.contains("六人之约"), "图鉴背景故事已补全且不与六人之约冲突")

	# 图鉴动作页：五个技能必须使用真实动画名，且都可点击播放
	var codex = load("res://scenes/ui/codex_panel.tscn").instantiate()
	add_child(codex)
	await get_tree().process_frame
	codex._tab = Codex.TAB_FORM
	codex._sel = "z001"
	codex._show_portrait = false
	codex._refresh()
	await get_tree().process_frame
	var labels: Array = []
	for a in codex._acts:
		labels.append(str(a["label"]))
	_check(labels.has("烬火三叠") and labels.has("焚骨三叩") and labels.has("烬灭斩") \
		and labels.has("余烬重燃") and labels.has("焚影掠") and labels.has("烬火燎原"), "图鉴烬生动作条目齐全")
	var anims_ok := true
	for a in codex._acts:
		if str(a["kind"]) != "skill":
			continue
		for nm in a["anims"]:
			if not base_names.has(str(nm)):
				anims_ok = false
	_check(anims_ok, "图鉴技能动画名均真实存在")
	for i in codex._acts.size():
		if str(codex._acts[i]["kind"]) == "skill":
			codex._pick(i)
	_check(true, "图鉴五个技能动作均可播放")
	codex.queue_free()
	await get_tree().process_frame

	print("[Z1] DONE checks=%d failed=%d" % [_checks, _failed])
	get_tree().quit(1 if _failed > 0 else 0)
