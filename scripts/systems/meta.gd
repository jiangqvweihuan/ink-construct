extends Node

## 局外养成 · 化身解锁 + 契合度（形态专精）
## 存档：user://meta.json（JSON），只存累计击杀/通关/各形态契合经验，解锁状态由条件推导。
##
## 解锁条件：c021/c023 初始开放；其余按 UNLOCKS 里的累计击杀 / 通关次数。
## 解锁顺序 = 强度梯度（近战 -> 远程）：力僧杀25 -> 剑仙杀60，越强的越靠后。
## 剑仙（真远程剑气）实测最强，放最难位置；青笠 c012 已下掉玩家形态转精英怪，第 5 席待新素材。
## 契合度：用某形态击杀 +1、通关整局 +20；等级加成只作用于该形态：
##   Lv1(30) 技能冷却 -10% ｜ Lv2(80) 普攻伤害 +1 ｜ Lv3(150) 化身为该形态免费

const SAVE_PATH := "user://meta.json"
const LV_EXP := [30, 80, 150]

const UNLOCKS := {
	"c013": {"kills": 25, "hint": "累计击杀 25 解锁"},
	"z000": {"kills": 60, "hint": "累计击杀 60 解锁"},
}

## 墨锭商店（化身谱面板消费）：买断解锁绕过条件，按强度梯度定价；开局加成为永久被动。
## 买断为一次性购买（cost），开局加成可升级（costs 每级价格）。
const INK_SHOP := {
	"buyout_c013": {"label": "买断 · 力僧", "cost": 40, "form": "c013"},
	"buyout_z000": {"label": "买断 · 剑仙", "cost": 120, "form": "z000"},
	"start_bones": {"label": "墨囊", "desc": "每局开局墨骨 +5", "costs": [30, 50, 80]},
	"start_hp": {"label": "固元", "desc": "每局开局生命上限 +1", "costs": [80]},
}

var kills := 0 # 累计击杀（全形态合计）
var clears := 0 # 累计通关整局次数
var mastery := {} # 形态 id -> 契合经验
var ink := 0 # 局外货币·墨锭：结算时由本局剩余墨骨沉淀而来
var purchases := {} # 墨锭消费记录：买断 buyout_* -> true；开局加成 start_* -> 等级
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


## 解锁进度文本（未解锁形态用）：12/25 之类
func unlock_progress(id: String) -> String:
	var cond: Dictionary = UNLOCKS.get(id, {})
	if cond.has("kills"):
		return "%d/%d" % [mini(kills, int(cond["kills"])), int(cond["kills"])]
	if cond.has("clears"):
		return "%d/%d" % [mini(clears, int(cond["clears"])), int(cond["clears"])]
	return ""


# ---------- 墨锭商店 ----------

## 各级价格：买断 [cost]，开局加成 costs 数组
func _shop_costs(item: Dictionary) -> Array:
	if item.has("form"):
		return [int(item["cost"])]
	return item.get("costs", [])


## 当前等级：买断 0/1，开局加成 0..N
func shop_level(key: String) -> int:
	var item: Dictionary = INK_SHOP.get(key, {})
	if item.has("form"):
		return 1 if bool(purchases.get(key, false)) else 0
	return int(purchases.get(key, 0))


## 满级等级：买断 1，开局加成 costs 长度
func shop_max_level(key: String) -> int:
	return _shop_costs(INK_SHOP.get(key, {})).size()


## 下一级价格；-1 = 已满级/已买断/买断目标已解锁（没必要买）
func shop_cost(key: String) -> int:
	var item: Dictionary = INK_SHOP.get(key, {})
	if item.is_empty():
		return -1
	if item.has("form") and is_unlocked(str(item["form"])):
		return -1
	var costs := _shop_costs(item)
	var lv := shop_level(key)
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
	else:
		purchases[key] = shop_level(key) + 1
	_save()
	return true


## 永久开局加成：每局初始墨骨 / 生命上限
func start_bones_bonus() -> int:
	return 5 * shop_level("start_bones")


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


## 该形态当前的专精加成：冷却倍率 / 普攻加伤 / 化身是否免费
func mods(id: String) -> Dictionary:
	var lv := mastery_level(id)
	return {
		"cd": 1.0 - (0.1 if lv >= 1 else 0.0),
		"damage": 1 if lv >= 2 else 0,
		"free": lv >= 3,
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


## 结算沉淀：剩余墨骨的一半转为墨锭（向下取整），通关额外 +25
func deposit_ink(bones_left: int, cleared: bool) -> int:
	var n := bones_left / 2 + (25 if cleared else 0)
	if n > 0:
		ink += n
		_save()
	return n


# ---------- 记账（战斗中调用） ----------

## 击杀一只怪：全形态累计 +1 解锁进度，当前形态契合 +1
func add_kill(form_id: String) -> void:
	kills += 1
	mastery[form_id] = mastery_exp(form_id) + 1
	_save()


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
	f.store_string(JSON.stringify({"kills": kills, "clears": clears, "mastery": mastery, "ink": ink, "purchases": purchases}))


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
