extends Node2D

## 全角色对战验证：每个化身都能在竞技场入场、技能目标锁定对手玩家、
## 技能表中的所有状态效果都有玩家侧承接接口，并校验时停/数值平衡。

const Skulls = preload("res://scripts/player/skulls.gd")
const Tuning = preload("res://scripts/pvp/pvp_tuning.gd")
const ARENA_SCENE := preload("res://scenes/pvp/pvp_arena.tscn")

## 敌人接口名 → 玩家侧 PVP 适配接口名；技能表里出现这些字段就必须有对应方法
const EFFECT_METHODS := {
	"root": "root",
	"contain": "contain",
	"stun": "stun",
	"slow": "slow",
	"bleed": "apply_bleed",
	"poison": "apply_poison",
	"vulnerable": "apply_vulnerable",
	"frenzy": "apply_frenzy",
	"launch": "launch",
	"knockback": "knock_back",
	"stop": "time_stop",
	"charm": "apply_charm",
	"mind_detonate": "detonate_mind",
}

const ADAPTERS := [
	"root", "contain", "stun", "slow", "launch", "knock_back",
	"apply_bleed", "apply_poison", "apply_vulnerable", "apply_frenzy",
	"apply_charm", "detonate_mind", "apply_transferred_debuff",
	"amplify_debuffs", "set_evil_buddha_pressure", "apply_room_cd_curse",
	"stop_tier", "time_stop", "pvp_damage_taken_scale", "pvp_damage_scale",
]

var _checks := 0
var _failed := 0
var _arena = null
var _a = null
var _b = null
var _rules = null


func _ready() -> void:
	Run.active = true
	Run.start_pvp({0: Skulls.DEFAULT_ID, 1: Skulls.DEFAULT_ID}, true)
	_arena = ARENA_SCENE.instantiate()
	add_child(_arena)
	_a = _arena._players[0]
	_b = _arena._players[1]
	_rules = _arena._rules

	_test_all_characters()
	_test_status_adapters()
	_test_shield_skill()
	_test_damage_dedup_and_cap()
	_test_time_stop()
	_test_dot_and_round()
	_test_heal_and_control_scale()

	print("[PBA] DONE checks=%d failed=%d" % [_checks, _failed])
	get_tree().quit(0 if _failed == 0 else 1)


func _check(cond: bool, label: String) -> void:
	_checks += 1
	if cond:
		print("[PBA] PASS ", label)
	else:
		_failed += 1
		printerr("[PBA] FAIL ", label)


## 把一对玩家复位到可结算状态（不触发竞技场的回合演出）
func _reset_pair(id0: String, id1: String) -> void:
	if str(_a.skull_id) != id0:
		_a.swap_skull(id0)
	if str(_b.skull_id) != id1:
		_b.swap_skull(id1)
	_a.global_position = Vector2(600, 560)
	_b.global_position = Vector2(700, 560)
	_a.facing = 1
	_b.facing = -1
	_rules.phase = "idle"
	_rules.phase = "fight"
	_a.pvp_reset(_a.global_position)
	_b.pvp_reset(_b.global_position)
	_rules.scores = {0: 0, 1: 0}
	_rules.hp = {0: Tuning.MAX_HP, 1: Tuning.MAX_HP}
	_rules.round_no = 1
	_rules.winner = -1
	_rules._last_attacker.clear()


# ---------------------------------------------------------------- 全角色

func _test_all_characters() -> void:
	var ids := Skulls.ids()
	_check(ids.size() >= 6, "化身谱至少 6 个角色")
	for id in ids:
		_reset_pair(str(id), Skulls.DEFAULT_ID)
		var foes: Array = _a._foes()
		_check(foes.size() == 1 and foes[0] == _b, "%s：技能目标只锁定对手玩家" % id)
		_check(_a.is_in_group("pvp_players") and _b.is_in_group("pvp_players"), "%s：双方都登记为对战目标" % id)
		_check(Tuning.CHAR_SCALE.has(str(id)), "%s：对战角色系数已配置" % id)
		var missing: Array = []
		for m in ADAPTERS:
			if not _b.has_method(m):
				missing.append(m)
		_check(missing.is_empty(), "%s：PVP 状态适配接口齐全 %s" % [id, str(missing)])
		var need := _effect_methods(id)
		var absent: Array = []
		for m in need:
			if not _b.has_method(m):
				absent.append(m)
		_check(absent.is_empty(), "%s：技能表效果字段均有承接接口 %s" % [id, str(absent)])
		_test_skill_applies(str(id))


## 真打一发技能命中帧：伤害经 pvp_rules 结算，状态由目标适配层挂到对手身上
func _test_skill_applies(id: String) -> void:
	_reset_pair(id, "c021")
	var profile: Dictionary = Skulls.SKULLS.get(id, {})
	var probed := false
	for key in profile.get("skills", {}):
		var cfg: Dictionary = profile["skills"][key]
		for h in cfg.get("hits", []):
			if not (h is Dictionary):
				continue
			# 投射物/魅惑/心魔/护罩走各自的分支，这里只验近战命中帧
			if h.has("projectile") or h.has("charm") or h.has("mind_detonate") or h.has("self_shield"):
				continue
			if not h.has("damage") or not h.has("height"):
				continue
			_reset_pair(id, "c021")
			_a._skill_name = str(key)
			_a._skill_start_x = _a.global_position.x
			var hp_before := int(_b.hp)
			_a._deal_skill_hit(h.duplicate(true))
			var status_on: bool = _b._pvp_bleed_time > 0.0 or _b._pvp_poison_time > 0.0 \
				or _b._pvp_vuln_time > 0.0 or _b._pvp_frenzy_time > 0.0 \
				or _b._pvp_root_time > 0.0 or _b._pvp_stun_time > 0.0
			_check(int(_b.hp) < hp_before or status_on, "%s：%s 命中后对手掉血或挂上状态" % [id, str(key)])
			probed = true
			break
		if probed:
			break
	if not probed:
		# 远程/功能型角色（绛弦）没有近战命中帧，改为验证投射物命中帧会广播 PVP 判定
		for key in profile.get("skills", {}):
			var cfg2: Dictionary = profile["skills"][key]
			for h in cfg2.get("hits", []):
				if not (h is Dictionary) or not h.has("projectile") or not h.has("damage"):
					continue
				_reset_pair(id, "c021")
				_a._skill_name = str(key)
				var got: Array = []
				var cb := func(spec: Dictionary) -> void: got.append(spec)
				_a.pvp_strike.connect(cb)
				_a._deal_skill_hit(h.duplicate(true))
				_a.pvp_strike.disconnect(cb)
				_check(got.size() > 0 and float(got[0].get("damage", 0)) > 0.0,
					"%s：%s 远程命中帧广播 PVP 判定" % [id, str(key)])
				probed = true
				break
			if probed:
				break
	_check(probed, "%s：至少有一个可验证的命中帧" % id)


## 递归扫描技能表，收集所有需要玩家侧承接的效果接口
func _effect_methods(id: String) -> Array:
	var out: Array = []
	var profile: Dictionary = Skulls.SKULLS.get(id, {})
	_collect_effects(profile.get("attacks", []), out)
	_collect_effects(profile.get("skills", {}), out)
	return out


func _collect_effects(node, out: Array) -> void:
	if node is Array:
		for item in node:
			_collect_effects(item, out)
		return
	if not (node is Dictionary):
		return
	for key in node:
		var k := str(key)
		if EFFECT_METHODS.has(k):
			var m := str(EFFECT_METHODS[k])
			if not out.has(m):
				out.append(m)
		var v = node[key]
		if v is Dictionary or v is Array:
			_collect_effects(v, out)


# ---------------------------------------------------------------- 状态施加

func _test_status_adapters() -> void:
	_reset_pair("c021", "c021")

	_b._clear_pvp_status()
	_b.call("root", 2.0)
	_check(is_equal_approx(_b._pvp_root_time, 2.0 * Tuning.CONTROL_SCALE), "定身按控制系数折算")

	_b._clear_pvp_status()
	_b.call("contain", 2.0)
	_check(_b._pvp_root_time > 0.0, "枝界约束可定身玩家")

	_b._clear_pvp_status()
	_b.call("stun", 2.0)
	_check(_b._pvp_stun_time > 0.0, "眩晕可锁住玩家操作")

	_b._clear_pvp_status()
	_b.call("slow", 3.0, 0.5)
	_check(_b._pvp_slow_time > 0.0 and is_equal_approx(_b._pvp_slow_scale, 0.5), "减速记录时长与系数")

	_b._clear_pvp_status()
	_b.call("apply_bleed", 2)
	_check(_b._pvp_bleed_stacks == 2 and _b._pvp_bleed_time > 0.0, "流血可叠层")

	_b._clear_pvp_status()
	_b.call("apply_poison", 4.0)
	_check(_b._pvp_poison_time > 0.0, "中毒可挂到玩家")

	_b._clear_pvp_status()
	_b.call("apply_vulnerable", 5.0, 0.25)
	_check(_b._pvp_vuln_time > 0.0 and _b.pvp_damage_taken_scale() > 1.0, "易伤放大承伤")

	_b._clear_pvp_status()
	_b.call("apply_frenzy", 6.0, true)
	_check(_b._pvp_frenzy_time > 0.0 and _b.pvp_damage_taken_scale() > 1.0, "躁动放大承伤")

	_b._clear_pvp_status()
	_b.call("apply_bleed", 1)
	var before: float = _b._pvp_bleed_time
	_b.call("amplify_debuffs")
	_check(_b._pvp_bleed_time > before, "神伤可延长负面状态")

	_b._clear_pvp_status()
	_a.call("set_evil_buddha_pressure", true)
	_check(_a.pvp_damage_scale() < 1.0, "邪佛压场降低自身输出")
	_a.call("set_evil_buddha_pressure", false)

	_b._clear_pvp_status()
	_b.call("apply_charm", 5.0)
	_check(_b._pvp_stun_time > 0.0 and _b._pvp_stun_time <= 2.0, "摄心转为短硬控且不超过 2 秒")

	_b._clear_pvp_status()
	_b.call("apply_transferred_debuff", {"id": "stun", "time": 2.0})
	_check(_b._pvp_stun_time > 0.0, "转移负面可落成硬控")

	_b._clear_pvp_status()
	_b.call("apply_room_cd_curse")
	_check(bool(_b._pvp_cd_cursed), "换房诅咒标记生效")

	_b._clear_pvp_status()
	_b.call("launch", 1, 120.0, 300.0)
	_check(_b.velocity.y < 0.0, "击飞给玩家竖直速度")

	_b.velocity = Vector2.ZERO
	_b.call("knock_back", -1, 620.0, 0)
	_check(_b.velocity.x < 0.0, "击退给玩家水平推力")


# ---------------------------------------------------------------- 金钟罩

## 走真实技能表：镇岳 K 第二段的 self_shield 命中帧要在 PvP 里正常挂盾并挡下对手一击。
func _test_shield_skill() -> void:
	_reset_pair("c013", "c021")
	var shield_hit: Dictionary = {}
	for h in Skulls.SKULLS["c013"]["skills"]["skill01"]["hits"]:
		if h is Dictionary and h.has("self_shield"):
			shield_hit = h
	_check(not shield_hit.is_empty(), "镇岳 K 第二段配置了金钟罩")
	_a._skill_name = "skill01"
	_a._deal_skill_hit(shield_hit.duplicate(true))
	var want_hits := int(shield_hit["self_shield"].get("hits", 1))
	_check(int(_a._shield_hits) == want_hits, "金钟罩命中帧给自身挂上护盾层数")
	var hp_before := int(_a.hp)
	_rules.handle_strike(1, {"damage": 15, "range": 400, "height": 300, "both": true})
	_check(int(_a.hp) == hp_before and int(_a._shield_hits) == want_hits - 1, "对手攻击被金钟罩挡下并消耗一层")


# ---------------------------------------------------------------- 伤害与上限

func _test_damage_dedup_and_cap() -> void:
	_reset_pair("c021", "c021")
	var hp_before := int(_b.hp)
	var dealt := int(_a._damage_enemy(_b, 10))
	_check(dealt == 0 and int(_b.hp) == hp_before, "对手玩家不会被 _damage_enemy 重复扣血")

	_reset_pair("c021", "c021")
	_rules.handle_strike(0, {"damage": 999, "range": 400, "height": 300, "both": true})
	_check(int(_b.hp) == Tuning.MAX_HP - Tuning.HIT_DAMAGE_CAP, "单次命中伤害受上限约束")

	_reset_pair("c021", "c021")
	_b.position = Vector2(1600, 560)
	_rules.handle_strike(0, {"damage": 10, "range": 100, "height": 300, "both": true})
	_check(int(_b.hp) == Tuning.MAX_HP, "超出射程不结算伤害")


# ---------------------------------------------------------------- 将去未还

func _test_time_stop() -> void:
	_reset_pair("z003", "c021")
	var stop_cfg: Dictionary = Skulls.SKULLS["z003"]["skills"]["skill06"]["stop"]
	_check(float(stop_cfg.get("boss", 0.0)) == 5.0, "将去未还配置了 BOSS 档位 5 秒")

	_check(str(_b.stop_tier()) == "boss", "玩家目标的时停档位按 BOSS 处理")
	var dur := float(stop_cfg.get("boss", 10.0)) + float(_a._stop_bonus)
	_b.call("time_stop", dur, _a)
	_check(is_equal_approx(_b._pvp_stop_time, minf(dur, Tuning.TIME_STOP_MAX)), "时停按 BOSS 档位写入玩家计时")
	_check(_b.velocity == Vector2.ZERO, "时停期间玩家速度归零")
	_check(_b._pvp_stop_caster == _a, "时停记录施法者用于结束回报")

	_b._pvp_status_tick(Tuning.TIME_STOP_MAX + 0.1)
	_check(_b._pvp_stop_time == 0.0, "时停到点自然结束")


# ---------------------------------------------------------------- DOT 与回合

func _test_dot_and_round() -> void:
	_reset_pair("c021", "c021")
	_b.hp = 1
	_b.hp_changed.emit(_b.hp, _b.max_hp)
	_b.apply_bleed(1)
	_b._pvp_status_tick(1.01)
	_check(int(_b.hp) > 0 and bool(_b._pvp_butterfly_used), "持续伤害致命时红蝶正常复活")
	_check(_rules.phase == "fight", "红蝶复活后回合继续")
	# 复活已消耗：再吃一次致命持续伤害即正常阵亡
	_b.hp = 1
	_b.hp_changed.emit(_b.hp, _b.max_hp)
	_b.apply_bleed(1)
	_b._pvp_status_tick(1.01)
	_check(int(_b.hp) == 0, "红蝶用尽后持续伤害可击杀玩家")
	_check(int(_rules.scores.get(0, 0)) == 1, "持续伤害致死正常判回合")
	_check(_rules.phase == "round_end", "持续伤害致死后进入回合结束")


# ---------------------------------------------------------------- 治疗与控制折算

func _test_heal_and_control_scale() -> void:
	_reset_pair("c021", "c021")
	_b.hp = 40
	_b.hp_changed.emit(_b.hp, _b.max_hp)
	_b._restore_hp(10)
	_check(int(_b.hp) == 40 + int(roundf(10.0 * Tuning.HEAL_SCALE)), "治疗按对战系数折算")

	_b._clear_pvp_status()
	_b.call("stun", 1.0)
	_check(is_equal_approx(_b._pvp_stun_time, Tuning.CONTROL_SCALE), "控制时长按对战系数折算")
