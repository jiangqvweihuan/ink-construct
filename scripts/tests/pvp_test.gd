extends Node2D

## 玩家对战（PVP）冒烟测试：
## 1. 规则判定（射程/高度/朝向/背身/×8 伤害/回合与整场计分）
## 2. 本机解锁池（共用、只含已解锁、解锁变化后即时生效）
## 3. 竞技场完整对局（生成两名玩家 → KO → 下一回合 → 先到 2 分结算）

const PvpRules = preload("res://scripts/pvp/pvp_rules.gd")
const PvpPool = preload("res://scripts/pvp/pvp_pool.gd")
const Tuning = preload("res://scripts/pvp/pvp_tuning.gd")

var _checks := 0
var _failed := 0
var _meta_backup := {}


class Dummy extends Node2D:
	signal hp_changed(current: int, maximum: int)

	var hp := 100
	var max_hp := 100
	var facing := 1
	var taken := 0
	var dead := false

	func pvp_apply_damage(amount: int, _kb: Vector2 = Vector2.ZERO, _attacker: Node = null) -> void:
		taken += amount
		hp = maxi(0, hp - amount)
		if hp <= 0:
			dead = true
		hp_changed.emit(hp, max_hp)


func _check(ok: bool, label: String) -> void:
	_checks += 1
	if not ok:
		_failed += 1
	print("[PVP] ", ("PASS " if ok else "FAIL "), label)


func _ready() -> void:
	_meta_backup = {
		"kills": Meta.kills,
		"clears": Meta.clears,
		"purchases": Meta.purchases.duplicate(true),
	}
	Meta.persist = false

	_test_rules()
	_test_pool()
	await _test_panel()
	_test_lan()
	await _test_p0_adaptations()
	await _test_arena()

	Meta.kills = int(_meta_backup["kills"])
	Meta.clears = int(_meta_backup["clears"])
	Meta.purchases = _meta_backup["purchases"]
	print("[PVP] DONE checks=%d failed=%d" % [_checks, _failed])
	get_tree().quit(1 if _failed > 0 else 0)


# ---------------------------------------------------------------- 规则

func _test_rules() -> void:
	var rules = PvpRules.new()
	add_child(rules)
	var a := Dummy.new()
	a.position = Vector2(100, 500)
	a.facing = 1
	add_child(a)
	var b := Dummy.new()
	b.position = Vector2(200, 500)
	b.facing = -1
	add_child(b)
	rules.register(0, a)
	rules.register(1, b)
	rules.begin_round()

	rules.handle_strike(0, {"damage": 1, "range": 100, "height": 70})
	var per_hit := int(roundf(Tuning.DAMAGE_SCALE))
	_check(b.taken == per_hit, "正面近战命中，伤害按对战后系数结算")
	_check(int(rules.hp.get(1, 0)) == PvpRules.MAX_HP - per_hit, "命中后同步规则血量")

	b.hp = 100
	b.taken = 0
	rules.hp[1] = 100
	b.position = Vector2(0, 500)
	rules.handle_strike(0, {"damage": 1, "range": 100, "height": 70, "both": false})
	_check(b.taken == 0, "背身且不横扫时不命中")
	rules.handle_strike(0, {"damage": 1, "range": 100, "height": 70, "both": true})
	_check(b.taken == per_hit, "横扫（both）可命中身后目标")

	b.hp = 100
	b.taken = 0
	rules.hp[1] = 100
	b.position = Vector2(600, 500)
	rules.handle_strike(0, {"damage": 1, "range": 100, "height": 70})
	_check(b.taken == 0, "超出射程不命中")

	b.position = Vector2(200, 900)
	rules.handle_strike(0, {"damage": 1, "range": 400, "height": 70})
	_check(b.taken == 0, "高度差过大不命中")

	b.position = Vector2(200, 500)
	rules.handle_strike(0, {"damage": 1, "range": 400, "height": 200, "both": true})
	_check(b.taken > 0, "高度/横扫都满足时命中")

	# 回合与整场：连续命中直到 KO
	rules.reset_match()
	b.position = Vector2(200, 500)
	var hits_needed := int(ceil(float(PvpRules.MAX_HP) / float(per_hit)))
	for i in hits_needed:
		rules.handle_strike(0, {"damage": 1, "range": 400, "height": 200, "both": true})
	_check(int(rules.scores.get(0, 0)) == 1, "首次 KO 得 1 分")
	_check(rules.phase == "round_end", "KO 后进入回合结束阶段")

	rules.next_round()
	b.hp = 100
	b.taken = 0
	for i in hits_needed:
		rules.handle_strike(0, {"damage": 1, "range": 400, "height": 200, "both": true})
	_check(int(rules.scores.get(0, 0)) == 2, "第二次 KO 累计 2 分")
	_check(rules.phase == "match_end", "先到 2 分结束整场")
	_check(int(rules.winner) == 0, "胜者记录为 P1")

	rules.queue_free()
	a.queue_free()
	b.queue_free()


# ---------------------------------------------------------------- 解锁池

func _test_pool() -> void:
	Meta.kills = 0
	Meta.clears = 0
	Meta.purchases = {}

	var ids := PvpPool.unlocked_ids()
	_check(ids.size() > 0, "本机至少有一个已解锁角色")
	_check(PvpPool.can_pick("c021"), "初始角色可被选中")
	_check(not PvpPool.can_pick("c013"), "未解锁角色不可被选中")
	for id in ids:
		_check(PvpPool.can_pick(str(id)), "池内角色均可选中：" + str(id))

	# 单机同屏：两个槽位都从同一个本机池取人
	var p1 := PvpPool.default_id()
	var p2 := str(ids[ids.size() - 1])
	_check(PvpPool.can_pick(p1) and PvpPool.can_pick(p2), "P1/P2 共用同一套本机已解锁池")

	# 局域网各端独立：池子只由「本机」Meta 推导，本机进度变化后立即反映
	Meta.kills = 20
	_check(PvpPool.can_pick("c013"), "本机解锁进度变化后角色进入本端选池")
	_check(PvpPool.unlocked_ids().has("c013"), "新解锁角色出现在本端选池")
	Meta.kills = 0
	_check(not PvpPool.can_pick("c013"), "回到未解锁状态后角色移出本端选池")


# ---------------------------------------------------------------- 选角界面

func _test_panel() -> void:
	Meta.kills = 0
	Meta.clears = 0
	Meta.purchases = {}
	var panel = load("res://scenes/ui/start_panel.tscn").instantiate()
	panel.pvp_local = true
	add_child(panel)
	await get_tree().process_frame

	_check(panel._mode == Run.MODE_PVP, "本机对战面板直接落在对战模式")
	_check(int(panel._step) == 2, "本机对战面板直接进入化身页")
	_check(str(panel._char) != "" and Meta.is_unlocked(str(panel._char)), "P1 默认化身已解锁")
	_check(str(panel._char2) != "" and Meta.is_unlocked(str(panel._char2)), "P2 默认化身来自同一本机池")

	var before := str(panel._char2)
	panel._set_char(1, "c013")
	_check(str(panel._char2) == before, "未解锁化身无法被 P2 选中")

	panel.queue_free()
	await get_tree().process_frame


# ---------------------------------------------------------------- 局域网

## 只验证开局前的校验与场景选择：不真正建立 ENet 连接，也不切场景。
func _test_lan() -> void:
	LanNet.role = "host"
	LanNet.state = "lobby"
	LanNet.room = {"mode": Run.MODE_PVP, "difficulty": 1, "skull": "c021", "max": 2}
	LanNet.members = {
		1: {"name": "房主", "slot": 0, "ready": true, "skull": "c021"},
		2: {"name": "客机", "slot": 1, "ready": true, "skull": "c021"},
		3: {"name": "第三端", "slot": 2, "ready": true, "skull": "c021"},
	}
	_check(LanNet.start_game(Run.MODE_PVP, 1, "c021") == "对战模式需要恰好 2 名玩家", "对战房间超过 2 人时拒绝开局")

	LanNet.members.erase(3)
	_check(LanNet._play_scene() == LanNet.PVP_SCENE, "对战房间进入竞技场场景")
	LanNet.room["mode"] = Run.MODE_ADVENTURE
	_check(LanNet._play_scene() == LanNet.ROOM_SCENE, "冒险房间仍进入原关卡场景")
	LanNet.room["mode"] = Run.MODE_PVP

	Meta.kills = 0
	Meta.clears = 0
	Meta.purchases = {}
	_check(LanNet.start_game(Run.MODE_PVP, 1, "c013") == "房主化身未解锁，请重新选择", "主机侧拒绝未解锁的房主化身")

	LanNet.members[2]["skull"] = ""
	_check(LanNet.start_game(Run.MODE_PVP, 1, "c021") == "客机尚未选择化身", "客机未选化身时不能开局")

	LanNet.role = ""
	LanNet.state = "idle"
	LanNet.room = {}
	LanNet.members = {}
	Run.net_role = ""
	Run.net_slot = 0


# ---------------------------------------------------------------- P0 机制适配

## 圣僧 / 金刚反伤 / 连刃等追加伤害 / 实际伤害回调（降魔、heal_ratio）
func _test_p0_adaptations() -> void:
	Meta.kills = 0
	Meta.clears = 0
	Meta.purchases = {}
	Run.start_pvp({0: "c013", 1: "c021"}, true)
	var arena = load("res://scenes/pvp/pvp_arena.tscn").instantiate()
	add_child(arena)
	await get_tree().process_frame
	await get_tree().process_frame
	var a = arena._players[0]
	var b = arena._players[1]
	var rules = arena._rules
	_reset_pair(a, b, rules, "c013", "c021")

	# 圣僧：单次伤害封顶
	a.hp = 100
	a.hp_changed.emit(a.hp, a.max_hp)
	a.pvp_apply_damage(26)
	_check(int(a.hp) == 100 - Tuning.SAINT_HIT_CAP, "圣僧在 PVP 中把单次伤害压到 %d" % Tuning.SAINT_HIT_CAP)

	# 圣僧：负面免疫（a 为镇岳）
	_reset_pair(a, b, rules, "c013", "c021")
	a.apply_bleed(2)
	a.stun(2.0)
	a.apply_poison(2.0)
	a.apply_vulnerable(2.0)
	a.apply_frenzy(2.0)
	a.apply_charm(2.0)
	a.apply_room_cd_curse()
	_check(a._pvp_bleed_stacks == 0 and a._pvp_stun_time == 0.0 and a._pvp_poison_time == 0.0 \
		and a._pvp_vuln_time == 0.0 and a._pvp_frenzy_time == 0.0 and not a._pvp_cd_cursed,
		"圣僧在 PVP 中免疫全部负面状态")

	# 金刚反伤：自身免伤、攻击方吃反伤
	_reset_pair(a, b, rules, "c013", "c021")
	a._skill_reflect = true
	var a_hp := int(a.hp)
	var b_hp := int(b.hp)
	var dealt := _pvp_strike(a, b, rules, 1)
	_check(dealt == 0 and int(a.hp) == a_hp and int(b.hp) < b_hp,
		"金刚反伤在 PVP 中免伤并反弹给攻击方")
	a._skill_reflect = false

	# 技能无敌 / 受击无敌 / 完美闪避 / 回环招架
	_reset_pair(a, b, rules, "c021", "c021")
	a._invincible = true
	_check(_raw_strike(a, b, rules, 1) == 0, "技能无敌帧在 PVP 中免伤")
	_reset_pair(a, b, rules, "c021", "c021")
	a._hurt_invincible = 0.5
	_check(_raw_strike(a, b, rules, 1) == 0, "受击无敌帧在 PVP 中免伤")
	_reset_pair(a, b, rules, "c021", "c021")
	a.state = a.State.DASH
	_check(_raw_strike(a, b, rules, 1) == 0 and int(a._buff_damage) >= 1, "完美闪避在 PVP 中免伤并给出收益")
	_reset_pair(a, b, rules, "c023", "c021")
	a._parry_ready = true
	_check(_raw_strike(a, b, rules, 1) == 0 and b._pvp_stun_time > 0.0, "回环招架在 PVP 中挡下并反制")

	# 红尘：实际受伤给攻击方叠怨，每 3 层使攻击方每段 -1
	_reset_pair(a, b, rules, "c021", "z002")
	a._pvp_grudge = 0
	var first_hit := _pvp_strike(a, b, rules, 0)
	_check(first_hit > 0 and a._pvp_grudge == 1, "红尘在 PVP 中给攻击方叠怨")
	_pvp_strike(a, b, rules, 0)
	_pvp_strike(a, b, rules, 0)
	var reduced_hit := _pvp_strike(a, b, rules, 0)
	_check(a._pvp_grudge == 4 and reduced_hit == first_hit - 1, "红尘每 3 层怨使攻击方每段伤害 -1")

	# 剑宗：实际伤害后目标治疗减半
	_reset_pair(a, b, rules, "z000", "c021")
	_pvp_strike(a, b, rules, 0)
	b.hp = 50
	b.hp_changed.emit(b.hp, b.max_hp)
	b._restore_hp(10)
	_check(int(b.hp) == 53, "剑宗在 PVP 中使目标治疗减半")

	# 不朽：治疗翻倍在 PVP 中保留
	_reset_pair(a, b, rules, "z000", "c021")
	a.hp = 50
	a.hp_changed.emit(a.hp, a.max_hp)
	a._restore_hp(5)
	_check(int(a.hp) == 56, "不朽在 PVP 中保持治疗翻倍")

	# 神伤：伤害段与减益延展
	_reset_pair(a, b, rules, "c021", "z002")
	b._pipa_sorrow_timer = 0.0
	var sorrow_before := int(a.hp)
	b._pipa_passive_tick(0.01)
	_check(int(a.hp) < sorrow_before and a._pvp_vuln_time > 0.0, "神伤在 PVP 中造成伤害并延展减益")

	# 连刃·极追加斩
	_reset_pair(a, b, rules, "c021", "c021")
	var before := int(b.hp)
	a._combo_finish_wave()
	_check(int(b.hp) == before - int(roundf(1.0 * Tuning.DAMAGE_SCALE)), "连刃·极追加斩在 PVP 中结算")

	# 疾刃冲刺斩
	_reset_pair(a, b, rules, "c021", "c021")
	a._dash_attack_dmg = 1
	before = int(b.hp)
	var cut := bool(a._dash_attack())
	_check(cut and int(b.hp) == before - int(roundf(1.0 * Tuning.DAMAGE_SCALE)), "疾刃冲刺斩在 PVP 中结算")
	a._dash_attack_dmg = 0

	# 斩影·回响
	_reset_pair(a, b, rules, "z003", "c021")
	a._scar_x = 650.0
	a._scar_range = 200.0
	a._scar_damage = 2
	a._scar_bleed = 1
	a._scar_facing = 1
	before = int(b.hp)
	a._scar_ring()
	_check(int(b.hp) == before - int(roundf(2.0 * Tuning.DAMAGE_SCALE)), "斩影·回响在 PVP 中结算")
	_check(b._pvp_bleed_stacks > 0, "斩影·回响在 PVP 中挂流血")

	# 实际伤害回调：降魔计数 + 技能总伤（heal_ratio）
	_reset_pair(a, b, rules, "c013", "c021")
	Run.c013_damage_hits = 0
	Run.c013_buddha = 0
	for i in 4:
		_pvp_strike(a, b, rules, 0)
	_check(Run.c013_damage_hits == 4 and Run.c013_buddha == 1, "降魔在 PVP 中按实际伤害累计佛陀")

	_reset_pair(a, b, rules, "z000", "c021")
	a.hp = 50
	a.hp_changed.emit(a.hp, a.max_hp)
	a._skill_damage_total = 0
	_pvp_strike(a, b, rules, 0)
	var total := int(a._skill_damage_total)
	a._apply_skill_heal({"heal_ratio": 0.5})
	_check(total > 0 and int(a.hp) > 50, "PvP 实际伤害累加技能总伤，heal_ratio 可回血")

	arena.queue_free()
	await get_tree().process_frame
	Run.active = false


func _reset_pair(a, b, rules, id0: String, id1: String) -> void:
	if str(a.skull_id) != id0:
		a.swap_skull(id0)
	if str(b.skull_id) != id1:
		b.swap_skull(id1)
	a._skill_reflect = false
	b._skill_reflect = false
	a._dash_attack_dmg = 0
	b._dash_attack_dmg = 0
	a._hurt_invincible = 0.0
	b._hurt_invincible = 0.0
	a._invincible = false
	b._invincible = false
	a._parry_ready = false
	b._parry_ready = false
	a.global_position = Vector2(600, 560)
	b.global_position = Vector2(700, 560)
	a.facing = 1
	b.facing = -1
	a.pvp_reset(a.global_position)
	b.pvp_reset(b.global_position)
	a.state = a.State.IDLE
	b.state = b.State.IDLE
	rules.phase = "fight"
	rules.hp = {0: PvpRules.MAX_HP, 1: PvpRules.MAX_HP}
	rules.scores = {0: 0, 1: 0}
	rules.winner = -1
	rules._last_attacker.clear()


func _pvp_strike(a, b, rules, slot: int) -> int:
	var victim = b if slot == 0 else a
	victim._hurt_invincible = 0.0 # 多段测试逐次清掉 PvP 受击无敌，避免第二段起被吞
	var before := int(victim.hp)
	rules.handle_strike(slot, {"damage": 15, "range": 400, "height": 300, "both": true})
	return before - int(victim.hp)


## 不清受击无敌的打击，用于验证无敌帧本身
func _raw_strike(a, b, rules, slot: int) -> int:
	var victim = b if slot == 0 else a
	var before := int(victim.hp)
	rules.handle_strike(slot, {"damage": 15, "range": 400, "height": 300, "both": true})
	return before - int(victim.hp)


# ---------------------------------------------------------------- 竞技场

func _test_arena() -> void:
	Meta.kills = 0
	Meta.clears = 0
	Meta.purchases = {}
	Run.start_pvp({0: "c021", 1: "c021"}, true)
	_check(Run.mode == Run.MODE_PVP and Run.pvp_local, "本机对战写入 Run 会话状态")
	_check(Run.player_count() == 2, "本机对战人数为 2")

	var packed = load("res://scenes/pvp/pvp_arena.tscn")
	_check(packed != null, "竞技场场景可加载")
	if packed == null:
		return
	var arena = packed.instantiate()
	add_child(arena)
	await get_tree().process_frame
	await get_tree().process_frame

	_check(arena._players.size() == 2, "竞技场生成两名玩家")
	_check(arena._rules != null, "离线竞技场创建权威规则")
	_check(bool(arena._players[0].pvp_mode) and bool(arena._players[1].pvp_mode), "双方玩家进入 PVP 模式")
	_check(int(arena._players[0].max_hp) == PvpRules.MAX_HP, "PVP 血量为 %d" % PvpRules.MAX_HP)

	arena._players[0].global_position = Vector2(600, 560)
	arena._players[1].global_position = Vector2(700, 560)

	# ---- 金钟罩：PVP 中必须能挡下对手一击（旧逻辑被 pvp_apply_damage 直接绕过）
	var p0 = arena._players[0]
	p0.swap_skull("c013")
	_check(int(p0.max_hp) == PvpRules.MAX_HP, "PVP 中换人仍保持对战生命上限")
	p0._apply_self_shield({"hits": 1, "time": 8.0})
	var hp_before := int(p0.hp)
	arena._rules.handle_strike(1, {"damage": 15, "range": 400, "height": 200, "both": true})
	_check(int(p0.hp) == hp_before and int(p0._shield_hits) == 0, "金钟罩在 PVP 中挡下对手攻击并消耗一层")
	arena._rules.handle_strike(1, {"damage": 15, "range": 400, "height": 200, "both": true})
	_check(int(p0.hp) < hp_before, "金钟罩消耗后下一击正常扣血")
	p0.hp = PvpRules.MAX_HP
	p0.hp_changed.emit(p0.hp, p0.max_hp)
	arena._rules.hp[0] = PvpRules.MAX_HP

	# ---- 红蝶：PVP 中致命伤先复活（每回合一次），复活后回合继续
	var p1 = arena._players[1]
	p1.hp = 5
	p1.hp_changed.emit(p1.hp, p1.max_hp)
	arena._rules.handle_strike(0, {"damage": 15, "range": 400, "height": 200, "both": true})
	var revive_hp := int(roundf(float(PvpRules.MAX_HP) * Tuning.REVIVE_HP_RATIO))
	_check(int(p1.hp) == revive_hp and bool(p1._pvp_butterfly_used), "红蝶在 PVP 中触发复活并回半血")
	_check(arena._rules.phase == "fight", "红蝶复活后回合不结束")
	p1._pvp_status_tick(1.0)
	_check(int(p1.hp) == revive_hp - 1, "红蝶复活后每秒流失 1 生命")

	# 单次伤害受上限约束；复活保护用状态计时推进，测试环境没有物理帧
	_strike_until_round_ends(arena)
	_check(int(arena._rules.scores.get(0, 0)) == 1, "竞技场 KO 计分")
	_check(arena._rules.phase == "round_end", "竞技场回合结束")

	arena._rules.next_round()
	arena._players[0].pvp_reset(Vector2(600, 560))
	arena._players[1].pvp_reset(Vector2(700, 560))
	_check(not bool(arena._players[1]._pvp_butterfly_used), "红蝶复活次数按回合重置")
	_strike_until_round_ends(arena)
	_check(int(arena._rules.scores.get(0, 0)) == 2, "竞技场第二次 KO")
	_check(arena._rules.phase == "match_end", "竞技场整场结算")
	_check(int(arena._rules.winner) == 0, "竞技场记录胜者")

	arena.queue_free()
	await get_tree().process_frame
	Run.active = false


## 连续打击直到本回合结束；每次打击后推进 1 秒状态计时，让红蝶复活保护自然失效。
func _strike_until_round_ends(arena) -> void:
	var spec := {"damage": 15, "range": 400, "height": 200, "both": true}
	var guard := 0
	while str(arena._rules.phase) == "fight" and guard < 60:
		guard += 1
		var victim = arena._players[1]
		if is_instance_valid(victim):
			victim._hurt_invincible = 0.0 # 模拟帧间隔，避免 PvP 受击无敌吞掉后续打击
		arena._rules.handle_strike(0, spec)
		if is_instance_valid(victim):
			victim._pvp_status_tick(1.01)
	_check(guard < 60, "回合能在有限次打击内结束")
