extends Node

## 局外养成 · 化身解锁 + 契合度（形态专精）
## 存档：user://meta.json（JSON），只存累计击杀/通关/各形态契合经验，解锁状态由条件推导。
##
## 解锁条件：c021 双刺初始开放；其余形态按各自门槛解锁，绛弦采用更高双条件门槛。
## 常规梯度：击杀 20 → 击杀 60 → 通关冒险 1 次 → 通关冒险 3 次 + 累计击杀 150；绛弦需通关 5 次 + 累计击杀 300。
## 通关计数只记「冒险模式」，无尽模式不计通关（但击杀照常累计，进度靠多打）。
## 契合度：用某形态击杀 +1、通关整局 +20；等级加成只作用于该形态：
##   Lv1(30) 技能冷却 -10% ｜ Lv2(80) 普攻伤害 +1 ｜ Lv3(150) 技能冷却再 -10%

const SAVE_PATH := "user://meta.json"
const LV_EXP := [30, 80, 150]

const UNLOCKS := {
	"c013": {"kills": 20, "hint": "累计击杀 20 解锁"},
	"c023": {"kills": 60, "hint": "累计击杀 60 解锁"},
	"z000": {"clears": 1, "hint": "通关冒险模式 1 次解锁"},
	"z002": {"clears": 5, "kills": 300, "hint": "通关冒险模式 5 次\n+ 累计击杀 300 解锁"},
	"z003": {"clears": 3, "kills": 150, "hint": "通关冒险模式 3 次\n+ 累计击杀 150 解锁"}, # 银夜强度超标，压轴解锁
}

## 永久修炼：每形态三分支，各初/续/极三阶；可跨分支混点，同分支顺序购买。
## 退款只允许没有已购后继的节点，整角色重置则一次返还全部；价格统一 35 / 65 / 110。
const NODE_COSTS := [35, 65, 110]
const FORM_NODES := {
	"c021_dance_1": {"form": "c021", "path": "血舞", "tier": 1, "desc": "技能命中回 1 生命（8 秒一次）"},
	"c021_dance_2": {"form": "c021", "path": "血舞", "tier": 2, "desc": "生命不高于一半时，技能伤害 +1", "req": "c021_dance_1"},
	"c021_dance_3": {"form": "c021", "path": "血舞", "tier": 3, "desc": "每击杀 3 名敌人回 1 生命", "req": "c021_dance_2"},
	"c021_combo_1": {"form": "c021", "path": "连刃", "tier": 1, "desc": "普攻末段伤害 +1"},
	"c021_combo_2": {"form": "c021", "path": "连刃", "tier": 2, "desc": "达到 10 连击后，全部伤害 +1", "req": "c021_combo_1"},
	"c021_combo_3": {"form": "c021", "path": "连刃", "tier": 3, "desc": "普攻末段命中后，追加大范围 1 伤", "req": "c021_combo_2"},
	"c021_shadow_1": {"form": "c021", "path": "无影", "tier": 1, "desc": "闪避后 2 秒内，下一次普攻伤害 +1"},
	"c021_shadow_2": {"form": "c021", "path": "无影", "tier": 2, "desc": "完美闪避使全部技能冷却 -1 秒", "req": "c021_shadow_1"},
	"c021_shadow_3": {"form": "c021", "path": "无影", "tier": 3, "desc": "空中造成的伤害 +1", "req": "c021_shadow_2"},

	"c013_guard_1": {"form": "c013", "path": "金刚", "tier": 1, "desc": "U 反伤 +1"},
	"c013_guard_2": {"form": "c013", "path": "金刚", "tier": 2, "desc": "金钟罩持续时间 +2 秒", "req": "c013_guard_1"},
	"c013_guard_3": {"form": "c013", "path": "金刚", "tier": 3, "desc": "护盾抵挡或消失时回 1 生命（每房一次）", "req": "c013_guard_2"},
	"c013_seismic_1": {"form": "c013", "path": "震岳", "tier": 1, "desc": "K 攻击范围 +15%"},
	"c013_seismic_2": {"form": "c013", "path": "震岳", "tier": 2, "desc": "K 定身由 2 秒延长至 2.5 秒", "req": "c013_seismic_1"},
	"c013_seismic_3": {"form": "c013", "path": "震岳", "tier": 3, "desc": "L 命中获得撞人效果，碰撞伤害 +1", "req": "c013_seismic_2"},
	"c013_meditation_1": {"form": "c013", "path": "禅定", "tier": 1, "desc": "生命上限 +1"},
	"c013_meditation_2": {"form": "c013", "path": "禅定", "tier": 2, "desc": "受击后 2 秒内，受到的伤害 -1", "req": "c013_meditation_1"},
	"c013_meditation_3": {"form": "c013", "path": "禅定", "tier": 3, "desc": "生命不高于 4 时，冷却恢复速度 +20%", "req": "c013_meditation_2"},

	"c023_lash_1": {"form": "c023", "path": "鞭势", "tier": 1, "desc": "普攻范围 +15%"},
	"c023_lash_2": {"form": "c023", "path": "鞭势", "tier": 2, "desc": "首段鞭击拉回距离由 80 提至 120", "req": "c023_lash_1"},
	"c023_lash_3": {"form": "c023", "path": "鞭势", "tier": 3, "desc": "K 尾鞭伤害 +1", "req": "c023_lash_2"},
	"c023_venom_1": {"form": "c023", "path": "毒梅", "tier": 1, "desc": "中毒持续时间由 4 秒延长至 5 秒"},
	"c023_venom_2": {"form": "c023", "path": "毒梅", "tier": 2, "desc": "对中毒敌人的伤害 +1", "req": "c023_venom_1"},
	"c023_venom_3": {"form": "c023", "path": "毒梅", "tier": 3, "desc": "毒死敌人时，向附近最多 2 人传毒", "req": "c023_venom_2"},
	"c023_patience_1": {"form": "c023", "path": "静守", "tier": 1, "desc": "K 获得霸体"},
	"c023_patience_2": {"form": "c023", "path": "静守", "tier": 2, "desc": "生命上限 +1", "req": "c023_patience_1"},
	"c023_patience_3": {"form": "c023", "path": "静守", "tier": 3, "desc": "受击使 K 冷却 -2 秒（5 秒一次）", "req": "c023_patience_2"},

	"z000_edge_1": {"form": "z000", "path": "藏锋", "tier": 1, "desc": "K 每段命中都把敌人牵回剑锋前"},
	"z000_edge_2": {"form": "z000", "path": "藏锋", "tier": 2, "desc": "K 三段打全后封招，并留下可被 L 引爆的封脉", "req": "z000_edge_1"},
	"z000_edge_3": {"form": "z000", "path": "藏锋", "tier": 3, "desc": "L 命中封脉目标时，以其为中心牵引周围敌人", "req": "z000_edge_2"},
	"z000_volley_1": {"form": "z000", "path": "回锋", "tier": 1, "desc": "L 命中后可按闪避取消收招"},
	"z000_volley_2": {"form": "z000", "path": "回锋", "tier": 2, "desc": "U 后 2 秒内可在空中普攻追身", "req": "z000_volley_1"},
	"z000_volley_3": {"form": "z000", "path": "回锋", "tier": 3, "desc": "空中普攻第四段改为砸落，落点范围击飞", "req": "z000_volley_2"},
	"z000_wind_1": {"form": "z000", "path": "游身", "tier": 1, "desc": "完美闪避后，下一普攻直接从第四段起手"},
	"z000_wind_2": {"form": "z000", "path": "游身", "tier": 2, "desc": "闪避结束时回身横扫身后近敌", "req": "z000_wind_1"},
	"z000_wind_3": {"form": "z000", "path": "游身", "tier": 3, "desc": "回身横扫将浮空目标砸落，否则将其挑飞", "req": "z000_wind_2"},

	"z002_echo_1": {"form": "z002", "path": "余音", "tier": 1, "desc": "普攻末段与 L 的癫狂基础时长 +2 秒"},
	"z002_echo_2": {"form": "z002", "path": "余音", "tier": 2, "desc": "L 冷却 -1 秒", "req": "z002_echo_1"},
	"z002_echo_3": {"form": "z002", "path": "余音", "tier": 3, "desc": "L 曲终额外回复 1 生命", "req": "z002_echo_2"},
	"z002_charm_1": {"form": "z002", "path": "缚心", "tier": 1, "desc": "非 Boss 魅惑时长 +3 秒"},
	"z002_charm_2": {"form": "z002", "path": "缚心", "tier": 2, "desc": "觉醒 U 全体伤害 +1", "req": "z002_charm_1"},
	"z002_charm_3": {"form": "z002", "path": "缚心", "tier": 3, "desc": "魅惑结束时目标获得 3 层怨", "req": "z002_charm_2"},
	"z002_grudge_1": {"form": "z002", "path": "红尘", "tier": 1, "desc": "神伤间隔 -3 秒"},
	"z002_grudge_2": {"form": "z002", "path": "红尘", "tier": 2, "desc": "心魔引基础伤害 +2", "req": "z002_grudge_1"},
	"z002_grudge_3": {"form": "z002", "path": "红尘", "tier": 3, "desc": "六感尽失触发时额外造成 1 点固定伤害", "req": "z002_grudge_2"},

	"z003_chase_1": {"form": "z003", "path": "逐影", "tier": 1, "desc": "普攻末段伤害 +1"},
	"z003_chase_2": {"form": "z003", "path": "逐影", "tier": 2, "desc": "对击飞状态敌人的伤害 +1", "req": "z003_chase_1"},
	"z003_chase_3": {"form": "z003", "path": "逐影", "tier": 3, "desc": "击杀使全部技能冷却 -1 秒", "req": "z003_chase_2"},
	"z003_time_1": {"form": "z003", "path": "止时", "tier": 1, "desc": "时停各档时长 +0.25 秒"},
	"z003_time_2": {"form": "z003", "path": "止时", "tier": 2, "desc": "时停期间全部伤害 +1", "req": "z003_time_1"},
	"z003_time_3": {"form": "z003", "path": "止时", "tier": 3, "desc": "时停自然结束时，对被停敌人追加 1 伤", "req": "z003_time_2"},
	"z003_return_1": {"form": "z003", "path": "无还", "tier": 1, "desc": "O 位移距离 +100"},
	"z003_return_2": {"form": "z003", "path": "无还", "tier": 2, "desc": "I 觉醒持续时间 +2 秒", "req": "z003_return_1"},
	"z003_return_3": {"form": "z003", "path": "无还", "tier": 3, "desc": "觉醒中 O 击杀返还 4 秒觉醒", "req": "z003_return_2"},
}

## 墨锭商栈：角色买断放在各角色修炼页顶部；独立商栈只卖通用强化、重随与补给。
const INK_SHOP := {
	"buyout_c013": {"label": "买断 · 力僧", "cost": 40, "form": "c013"},
	"buyout_c023": {"label": "买断 · 梅剑", "cost": 80, "form": "c023"},
	"buyout_z000": {"label": "买断 · 剑仙", "cost": 120, "form": "z000"},
	"buyout_z002": {"label": "买断 · 绛弦", "cost": 280, "form": "z002"},
	"buyout_z003": {"label": "买断 · 银夜", "cost": 200, "form": "z003"},
	"start_ink": {"label": "聚墨", "desc": "每局结算墨锭 +2", "costs": [30, 50, 80], "tab": "permanent"},
	"start_hp": {"label": "固元", "desc": "每局开局生命上限 +1", "costs": [80], "tab": "permanent"},
	"start_edge": {"label": "初锋", "desc": "每局首个普通房全部伤害 +1", "costs": [120], "tab": "permanent"},
	"start_guard": {"label": "护砚", "desc": "每局第一次受到的伤害 -1", "costs": [100], "tab": "permanent"},
	"blessing_reroll": {"label": "赐福重随", "desc": "每局可重随开局赐福", "costs": [120, 220], "tab": "reroll"},
	"upgrade_reroll": {"label": "强化重随", "desc": "每次强化三选一可重随 1 次", "costs": [180], "tab": "reroll"},
	"supply_hp": {"label": "生肌散", "desc": "选用后本局生命上限 +2", "cost": 12, "supply": true, "stock": 3, "tab": "supply"},
	"supply_revive": {"label": "复活墨符", "desc": "本局可复活一次并回复 4 生命", "cost": 35, "supply": true, "stock": 1, "tab": "supply"},
	"supply_reroll": {"label": "重随券", "desc": "本局额外获得 2 次强化重随", "cost": 20, "supply": true, "stock": 3, "tab": "supply"},
}

var kills := 0 # 累计击杀（全形态合计）
var clears := 0 # 累计通关整局次数
var mastery := {} # 形态 id -> 契合经验
var ink := 0 # 局外货币·墨锭：按每局击杀、房间进度与通关结果结算
var purchases := {} # 墨锭消费记录：买断 buyout_* -> true；通用强化 -> 等级
var form_nodes := {} # 永久修炼节点 id -> true（与局内 Run.upgrades 完全分开）
var battle_passives := {} # 未来图鉴角色战斗被动：注册后可被玩家与佛眼共同查询
var inventory := {} # 一次性补给 id -> 库存数量
var selected_supply := "" # 下一局选用的补给；Run.start 时消耗一个
var seen := {} # 图鉴收录：敌人 / Boss id -> 已击败次数（>0 即收录，图鉴里才不是 ？？？）
var persist := true # 测试场景里关掉，别把 debug 数据写进玩家存档


func _ready() -> void:
	_load()


# ---------- 解锁 ----------

func is_unlocked(id: String) -> bool:
	if bool(purchases.get("buyout_" + id, false)): # 墨锭买断，绕过解锁条件
		return true
	var cond: Dictionary = UNLOCKS.get(id, {})
	if cond.is_empty():
		return true
	if cond.has("kills") and kills < int(cond["kills"]):
		return false
	if cond.has("clears") and clears < int(cond["clears"]):
		return false
	return true


func unlock_hint(id: String) -> String:
	return str(UNLOCKS.get(id, {}).get("hint", ""))


## 解锁进度文本（未解锁形态用）：支持双条件的条目会拼成「击杀 12/150 · 通关 1/3」
func unlock_progress(id: String) -> String:
	var cond: Dictionary = UNLOCKS.get(id, {})
	var parts: Array = []
	if cond.has("kills"):
		parts.append("击杀 %d/%d" % [mini(kills, int(cond["kills"])), int(cond["kills"])])
	if cond.has("clears"):
		parts.append("通关 %d/%d" % [mini(clears, int(cond["clears"])), int(cond["clears"])])
	return " · ".join(parts)


# ---------- 永久修炼 ----------

func has_form_node(id: String) -> bool:
	return bool(form_nodes.get(id, false))


func node_cost(id: String) -> int:
	var info: Dictionary = FORM_NODES.get(id, {})
	return int(NODE_COSTS[int(info.get("tier", 1)) - 1]) if not info.is_empty() else -1


func can_learn(id: String) -> bool:
	var info: Dictionary = FORM_NODES.get(id, {})
	if info.is_empty() or has_form_node(id) or not is_unlocked(str(info["form"])):
		return false
	var req := str(info.get("req", ""))
	return (req == "" or has_form_node(req)) and ink >= node_cost(id)


func learn_node(id: String) -> bool:
	if not can_learn(id):
		return false
	ink -= node_cost(id)
	form_nodes[id] = true
	_save()
	return true


## 只能退分支最末的已购节点，保证退回后不会出现"有续/极却没有初"的断链。
func can_refund(id: String) -> bool:
	if not has_form_node(id):
		return false
	for other in FORM_NODES:
		if str(FORM_NODES[other].get("req", "")) == id and has_form_node(str(other)):
			return false
	return true


func refund_node(id: String) -> bool:
	if not can_refund(id):
		return false
	form_nodes.erase(id)
	ink += node_cost(id)
	_save()
	return true


func form_spent(form_id: String) -> int:
	var total := 0
	for id in FORM_NODES:
		if str(FORM_NODES[id]["form"]) == form_id and has_form_node(str(id)):
			total += node_cost(str(id))
	return total


func form_node_count(form_id: String) -> int:
	var total := 0
	for id in FORM_NODES:
		if str(FORM_NODES[id]["form"]) == form_id and has_form_node(str(id)):
			total += 1
	return total


func reset_form(form_id: String) -> int:
	var total := form_spent(form_id)
	if total <= 0:
		return 0
	for id in FORM_NODES:
		if str(FORM_NODES[id]["form"]) == form_id:
			form_nodes.erase(id)
	ink += total
	_save()
	return total


func form_hp_bonus(form_id: String) -> int:
	return int(form_id == "c013" and has_form_node("c013_meditation_1")) + int(form_id == "c023" and has_form_node("c023_patience_2"))


## 未来角色的固有战斗被动从这里注册；owned 表示当前形态确实持有，boss_effect 供佛眼复用。
func register_battle_passive(id: String, info: Dictionary) -> void:
	if id.is_empty():
		return
	battle_passives[id] = info.duplicate(true)


func battle_passive_info(id: String) -> Dictionary:
	if battle_passives.has(id):
		var registered: Dictionary = battle_passives[id].duplicate(true)
		registered["id"] = id
		return registered
	if not FORM_NODES.has(id):
		return {}
	var info: Dictionary = FORM_NODES[id].duplicate(true)
	info["id"] = id
	var tiers := ["", "初", "续", "极"]
	info["name"] = "%s · %s" % [str(info["path"]), tiers[int(info["tier"])]]
	# 永久修炼在碎岳身上的对应表现；未来被动可直接在自己的注册资料里覆盖 boss_effect。
	var path := str(info["path"])
	var tier := int(info["tier"])
	match path:
		"血舞": info["boss_effect"] = {"heal_on_hit": 1, "heal_cooldown": maxf(2.0, 9.0 - tier * 2.0)}
		"连刃": info["boss_effect"] = {"damage": int(ceil(tier * 0.5))}
		"无影", "游身": info["boss_effect"] = {"speed": 0.08 * tier, "desire": 0.1 * tier}
		"金刚": info["boss_effect"] = {"bell_charges": tier}
		"震岳", "鞭势": info["boss_effect"] = {"reach": 0.1 * tier}
		"禅定": info["boss_effect"] = {"max_hp": tier}
		"毒梅", "逐影": info["boss_effect"] = {"controlled_damage": 1}
		"静守": info["boss_effect"] = {"cooldown_recovery": 0.1 * tier}
		"藏锋": info["boss_effect"] = {"cooldown_on_hit": 0.3 * tier}
		"回锋": info["boss_effect"] = {"cooldown_on_cast": 0.3 * tier}
		"止时": info["boss_effect"] = {"desire": 0.15 * tier}
		"无还": info["boss_effect"] = {"speed": 0.05 * tier, "reach": 0.05 * tier}
	return info


func battle_passive_candidates(form_id: String) -> Array:
	var out: Array = []
	for id in FORM_NODES:
		if str(FORM_NODES[id]["form"]) == form_id and has_form_node(str(id)):
			out.append(str(id))
	for id in battle_passives:
		var info: Dictionary = battle_passives[id]
		if str(info.get("form", "")) == form_id and bool(info.get("owned", true)):
			out.append(str(id))
	return out


# ---------- 墨锭商店 ----------

## 各级价格：买断/补给 [cost]，可升级强化 costs 数组
func _shop_costs(item: Dictionary) -> Array:
	if item.has("form") or item.has("supply"):
		return [int(item["cost"])]
	return item.get("costs", [])


## 当前等级：买断 0/1，补给为库存，其余为强化等级
func shop_level(key: String) -> int:
	var item: Dictionary = INK_SHOP.get(key, {})
	if item.has("form"):
		return 1 if bool(purchases.get(key, false)) else 0
	if item.has("supply"):
		return supply_count(key)
	return int(purchases.get(key, 0))


## 满级等级：买断 1，补给为库存上限，其余为 costs 长度
func shop_max_level(key: String) -> int:
	var item: Dictionary = INK_SHOP.get(key, {})
	return int(item.get("stock", 0)) if item.has("supply") else _shop_costs(item).size()


## 下一级价格；-1 = 已满级/已买断/买断目标已解锁（没必要买）
func shop_cost(key: String) -> int:
	var item: Dictionary = INK_SHOP.get(key, {})
	if item.is_empty():
		return -1
	if item.has("form") and is_unlocked(str(item["form"])):
		return -1
	if item.has("supply") and supply_count(key) >= int(item["stock"]):
		return -1
	var costs := _shop_costs(item)
	var lv := 0 if item.has("supply") else shop_level(key)
	if lv >= costs.size():
		return -1
	return int(costs[lv])


func can_buy(key: String) -> bool:
	var cost := shop_cost(key)
	return cost >= 0 and ink >= cost


func buy(key: String) -> bool:
	var cost := shop_cost(key)
	if cost < 0 or ink < cost:
		return false
	ink -= cost
	var item: Dictionary = INK_SHOP[key]
	if item.has("form"):
		purchases[key] = true
	elif item.has("supply"):
		inventory[key] = supply_count(key) + 1
	else:
		purchases[key] = shop_level(key) + 1
	_save()
	return true


# ---------- 一次性补给行囊 ----------

func supply_count(key: String) -> int:
	return int(inventory.get(key, 0))


func select_supply(key: String) -> bool:
	if key != "" and supply_count(key) <= 0:
		return false
	selected_supply = key
	_save()
	return true


## Run.start 调用：返回实际带入本局的补给并扣库存；无库存时自动清空旧选择。
func consume_selected_supply() -> String:
	var key := selected_supply
	if key == "":
		return ""
	if supply_count(key) <= 0:
		selected_supply = ""
		return ""
	inventory[key] = supply_count(key) - 1
	selected_supply = ""
	_save()
	return key


## 永久开局加成：生命上限
func start_hp_bonus() -> int:
	return shop_level("start_hp") # 每级 +1，限 1 级


# ---------- 契合度 ----------

func mastery_exp(id: String) -> int:
	return int(mastery.get(id, 0))


func mastery_level(id: String) -> int:
	var exp := mastery_exp(id)
	var lv := 0
	for need in LV_EXP:
		if exp >= int(need):
			lv += 1
	return lv


## 该形态当前的专精加成：冷却倍率 / 普攻加伤
func mods(id: String) -> Dictionary:
	var lv := mastery_level(id)
	return {
		"cd": 0.8 if lv >= 3 else (0.9 if lv >= 1 else 1.0),
		"damage": 1 if lv >= 2 else 0,
	}


## 契合进度文本：Lv2 80/150，满级 Lv3 MAX
func mastery_text(id: String) -> String:
	var lv := mastery_level(id)
	if lv >= LV_EXP.size():
		return "Lv%d MAX" % lv
	return "Lv%d %d/%d" % [lv, mastery_exp(id), int(LV_EXP[lv])]


# ---------- 本局收获（Run.start 取快照，结算面板 diff） ----------

func snapshot() -> Dictionary:
	var u := {}
	for id in UNLOCKS:
		u[id] = is_unlocked(id)
	return {"mastery": mastery.duplicate(), "unlocked": u}


## 对比快照：{mastery: {形态: 本局契合增量}, unlocks: [本局新解锁的形态]}
func diff_since(snap: Dictionary) -> Dictionary:
	var gains := {}
	var old_m: Dictionary = snap.get("mastery", {})
	for id in mastery:
		var d := mastery_exp(id) - int(old_m.get(id, 0))
		if d > 0:
			gains[id] = d
	var unlocks: Array = []
	var old_u: Dictionary = snap.get("unlocked", {})
	for id in UNLOCKS:
		if is_unlocked(id) and not bool(old_u.get(id, false)):
			unlocks.append(id)
	return {"mastery": gains, "unlocks": unlocks}


## 每局基础 2 墨锭；每 2 击杀 +1、每个已清房间 +5，通关额外 +25。
## 聚墨每级再 +2；阵亡同样按已有战绩结算，不再依赖局内货币余量。
func deposit_ink(run_kills: int, cleared_rooms: int, cleared: bool) -> int:
	var n := 2 + maxi(0, run_kills) / 2 + maxi(0, cleared_rooms) * 5 + (25 if cleared else 0) + 2 * shop_level("start_ink")
	ink += n
	_save()
	return n


# ---------- 记账（战斗中调用） ----------

## 击杀一只怪：全形态累计 +1 解锁进度，当前形态契合 +1
func add_kill(form_id: String) -> void:
	kills += 1
	mastery[form_id] = mastery_exp(form_id) + 1
	_save()


## 击败一只敌人 / Boss：图鉴收录计数 +1（同一只被击败多次会一直累加）
func add_enemy_kill(id: String) -> void:
	seen[id] = enemy_kills(id) + 1
	_save()


## 图鉴收录次数：0 = 还没击败过，图鉴里显示 ？？？
func enemy_kills(id: String) -> int:
	return int(seen.get(id, 0))


## 通关整局：通关计数 +1，当前形态契合 +20
func add_clear(form_id: String) -> void:
	clears += 1
	mastery[form_id] = mastery_exp(form_id) + 20
	_save()


## 测试用：直接拉满解锁条件，并停止落盘（别污染真实存档）
func debug_unlock_all() -> void:
	persist = false
	kills = maxi(kills, 999)
	clears = maxi(clears, 99)
	ink = maxi(ink, 999) # 商店条目在测试面板里也可点


# ---------- 存档 ----------

func _save() -> void:
	if not persist:
		return
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f == null:
		return
	f.store_string(JSON.stringify({
		"kills": kills, "clears": clears, "mastery": mastery, "ink": ink,
		"purchases": purchases, "form_nodes": form_nodes, "inventory": inventory,
		"selected_supply": selected_supply, "seen": seen,
	}))


func _load() -> void:
	if not FileAccess.file_exists(SAVE_PATH):
		return
	var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if f == null:
		return
	var data = JSON.parse_string(f.get_as_text())
	if typeof(data) != TYPE_DICTIONARY:
		return
	kills = int(data.get("kills", 0))
	clears = int(data.get("clears", 0))
	ink = int(data.get("ink", 0))
	var m = data.get("mastery", {})
	if typeof(m) == TYPE_DICTIONARY:
		mastery = m
	var p = data.get("purchases", {})
	if typeof(p) == TYPE_DICTIONARY:
		purchases = p
	var fn = data.get("form_nodes", {})
	if typeof(fn) == TYPE_DICTIONARY:
		form_nodes = fn
	var inv = data.get("inventory", {})
	if typeof(inv) == TYPE_DICTIONARY:
		inventory = inv
	selected_supply = str(data.get("selected_supply", ""))
	# 旧存档迁移：保留已购等级与补给库存，替换为无墨骨经济下的等阶条目。
	if purchases.has("start_bones"):
		purchases["start_ink"] = maxi(int(purchases.get("start_ink", 0)), int(purchases["start_bones"]))
		purchases.erase("start_bones")
	if inventory.has("supply_bones"):
		inventory["supply_hp"] = mini(int(INK_SHOP["supply_hp"]["stock"]), supply_count("supply_hp") + int(inventory["supply_bones"]))
		inventory.erase("supply_bones")
	if selected_supply == "supply_bones":
		selected_supply = "supply_hp"
	if selected_supply != "" and supply_count(selected_supply) <= 0:
		selected_supply = ""
	var s = data.get("seen", {})
	if typeof(s) == TYPE_DICTIONARY:
		seen = s
