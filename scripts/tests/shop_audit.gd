extends Node

## 墨锭商栈审计探针：配置结构 / 购买流程 / 局内效果 / 外观素材 / 商栈 UI
## 只读检查，绝不写玩家存档：Meta.persist 全程关闭，结束后恢复内存状态。
## 输出：tests/shop_audit.log；控制台汇总 SHOP AUDIT checks=N fail=M

const Skulls := preload("res://scripts/player/skulls.gd")
const Types := preload("res://scripts/enemies/enemy_types.gd")
const BossTypes := preload("res://scripts/enemies/boss_types.gd")
const Skins := preload("res://scripts/systems/skins.gd")
const PlayerClass := preload("res://scripts/player/player.gd")

const LOG_PATH := "res://tests/shop_audit.log"
const TABS := ["permanent", "reroll", "supply"]

var _log: FileAccess
var _checks := 0
var _fails := 0
var _warns := 0
var _snap: Dictionary = {}
var _prev_persist := true


func _ready() -> void:
	_log = FileAccess.open(LOG_PATH, FileAccess.WRITE)
	_prev_persist = Meta.persist
	Meta.persist = false
	_save_state()
	await _run()
	_restore_state()
	Meta.persist = _prev_persist
	_log.flush()
	p("SHOP AUDIT checks=%d fail=%d warn=%d" % [_checks, _fails, _warns])
	p("ALL DONE")
	get_tree().quit()


func p(msg: String) -> void:
	print("[SHOP] ", msg)
	if _log:
		_log.store_line("[SHOP] " + msg)


func _check(ok: bool, msg: String) -> void:
	_checks += 1
	if not ok:
		_fails += 1
		p("FAIL " + msg)
	else:
		p("OK   " + msg)


func _warn(msg: String) -> void:
	_warns += 1
	p("WARN " + msg)


func _save_state() -> void:
	_snap = {
		"ink": Meta.ink,
		"purchases": Meta.purchases.duplicate(true),
		"inventory": Meta.inventory.duplicate(true),
		"selected_supply": Meta.selected_supply,
		"kills": Meta.kills,
		"clears": Meta.clears,
		"seen": Meta.seen.duplicate(true),
		"skins": Meta.skins.duplicate(true),
		"skin_worn": Meta.skin_worn.duplicate(true),
		"form_nodes": Meta.form_nodes.duplicate(true),
		"ach_unlocked": Achievements.unlocked.duplicate(true),
		"ach_stats": Achievements.stats.duplicate(true),
		"ach_run": Achievements.run.duplicate(true),
		"ach_equipped": Achievements.equipped,
		"ach_bonus_on": Achievements.bonus_on,
	}


func _restore_state() -> void:
	Meta.ink = int(_snap["ink"])
	Meta.purchases = (_snap["purchases"] as Dictionary).duplicate(true)
	Meta.inventory = (_snap["inventory"] as Dictionary).duplicate(true)
	Meta.selected_supply = str(_snap["selected_supply"])
	Meta.kills = int(_snap["kills"])
	Meta.clears = int(_snap["clears"])
	Meta.seen = (_snap["seen"] as Dictionary).duplicate(true)
	Meta.skins = (_snap["skins"] as Dictionary).duplicate(true)
	Meta.skin_worn = (_snap["skin_worn"] as Dictionary).duplicate(true)
	Meta.form_nodes = (_snap["form_nodes"] as Dictionary).duplicate(true)
	Achievements.unlocked = (_snap["ach_unlocked"] as Dictionary).duplicate(true)
	Achievements.stats = (_snap["ach_stats"] as Dictionary).duplicate(true)
	Achievements.run = (_snap["ach_run"] as Dictionary).duplicate(true)
	Achievements.equipped = str(_snap["ach_equipped"])
	Achievements.bonus_on = bool(_snap["ach_bonus_on"])


## 把所有成就标记为已解锁：购买测试期间只验证扣款，不让“首次购买”等奖励回补墨锭
func _seal_achievements() -> void:
	var all_unlocked := {}
	for a in Achievements.ACHIEVEMENTS:
		all_unlocked[str(a.get("id", ""))] = 1
	Achievements.unlocked = all_unlocked


func _run() -> void:
	p("==== 墨锭商栈审计开始 ====")
	_seal_achievements()
	_audit_schema()
	_audit_skin_defs()
	_audit_purchase_flow()
	await _audit_effects()
	await _audit_ui()
	p("==== 墨锭商栈审计结束 ====")


# ------------------------------------------------------------------ A. 配置结构

func _price(base: int) -> int:
	var disc := Achievements.bonus("shop_discount")
	if disc < 0.0:
		return maxi(1, int(round(float(base) * (1.0 + disc))))
	return base


func _audit_schema() -> void:
	p("---- A. INK_SHOP 配置结构 ----")
	var labels := {}
	var tab_count := {"permanent": 0, "reroll": 0, "supply": 0}
	var supply_keys: Array = []
	for raw_key in Meta.INK_SHOP:
		var key := str(raw_key)
		var item: Dictionary = Meta.INK_SHOP[raw_key]
		_check(not key.is_empty(), "ID 非空: %s" % key)
		var label := str(item.get("label", ""))
		_check(not label.is_empty(), "%s 名称非空" % key)
		if not label.is_empty():
			_check(not labels.has(label), "%s 名称不重复（%s）" % [key, label])
			labels[label] = key
		var is_form := item.has("form")
		var is_supply := bool(item.get("supply", false))
		var has_costs := item.has("costs")
		var kinds := int(is_form) + int(is_supply) + int(has_costs)
		_check(kinds == 1, "%s 分类字段互斥且完整（form=%s supply=%s costs=%s）" % [key, is_form, is_supply, has_costs])
		if is_form:
			var form := str(item.get("form", ""))
			_check(Skulls.SKULLS.has(form), "%s 买断目标存在: %s" % [key, form])
			_check(key == "buyout_" + form, "%s 买断 ID 命名规范" % key)
			_check(Meta.UNLOCKS.has(form), "%s 买断目标有解锁条件: %s" % [key, form])
			var cost := int(item.get("cost", -1))
			_check(cost > 0 and cost <= 10000, "%s 买断价格合法: %d" % [key, cost])
			_check(not item.has("tab"), "%s 买断不带商栈页签（只在修炼页出售）" % key)
			_check(item.has("desc") and not str(item.get("desc", "")).is_empty(), "%s 买断描述非空" % key)
			_check(Meta.shop_max_level(key) == 1, "%s 买断上限为 1" % key)
			_check(str(item.get("tab", "")) == "", "%s 不会被商栈页重复上架" % key)
			continue
		_check(item.has("desc") and not str(item.get("desc", "")).is_empty(), "%s 描述非空" % key)
		if is_supply:
			supply_keys.append(key)
			var tab := str(item.get("tab", ""))
			_check(tab == "supply", "%s 补给页签正确: %s" % [key, tab])
			var cost := int(item.get("cost", -1))
			_check(cost > 0 and cost <= 10000, "%s 补给价格合法: %d" % [key, cost])
			var stock := int(item.get("stock", 0))
			_check(stock >= 1 and stock <= 99, "%s 库存上限合法: %d" % [key, stock])
			_check(not item.has("costs"), "%s 补给使用单价格式" % key)
			_check(Meta.shop_max_level(key) == stock, "%s 库存上限接线一致" % key)
			tab_count["supply"] += 1
			continue
		_check(has_costs, "%s 强化/重随使用 costs 数组" % key)
		var tab2 := str(item.get("tab", ""))
		_check(TABS.has(tab2) and tab2 != "supply", "%s 页签合法: %s" % [key, tab2])
		var costs: Array = item.get("costs", [])
		_check(not costs.is_empty(), "%s costs 非空" % key)
		var prev := 0
		var all_ok := true
		for c in costs:
			if typeof(c) != TYPE_INT and typeof(c) != TYPE_FLOAT:
				all_ok = false
				continue
			var ci := int(c)
			if ci <= 0 or ci > 10000 or ci <= prev:
				all_ok = false
			prev = ci
		_check(all_ok, "%s 各级价格为正且逐级递增: %s" % [key, str(costs)])
		_check(Meta.shop_max_level(key) == costs.size(), "%s 等级上限等于价格档数" % key)
		if tab_count.has(tab2):
			tab_count[tab2] += 1
	for tab in TABS:
		_check(int(tab_count[tab]) > 0, "页签 %s 至少有一个在售道具（%d）" % [tab, int(tab_count[tab])])
	for supply_key in ["supply_hp", "supply_revive", "supply_reroll"]:
		_check(supply_keys.has(supply_key), "选角页补给入口包含 %s" % supply_key)
	_check(Meta.shop_cost("__missing__") == -1, "未知商品 shop_cost 返回 -1")
	_check(not Meta.can_buy("__missing__"), "未知商品不可购买")
	_check(not Meta.buy("__missing__"), "未知商品 buy 不扣墨锭且不崩溃")
	p("配置统计：买断 %d / 永久 %d / 重随 %d / 补给 %d" % [
		_count_kind("form"), _count_kind("permanent"), _count_kind("reroll"), _count_kind("supply")])


func _count_kind(kind: String) -> int:
	var n := 0
	for key in Meta.INK_SHOP:
		var item: Dictionary = Meta.INK_SHOP[key]
		if kind == "form" and item.has("form"):
			n += 1
		elif kind == "supply" and bool(item.get("supply", false)):
			n += 1
		elif kind == str(item.get("tab", "")) and not item.has("form") and not bool(item.get("supply", false)):
			n += 1
	return n


# ------------------------------------------------------------------ B. 外观定义 / 素材

func _audit_skin_defs() -> void:
	p("---- B. 外观商品定义与素材 ----")
	_check(Skins.PRICE > 0, "外观统一定价为正: %d" % Skins.PRICE)
	var enemy_ids: Array = Types.TYPES.keys() + BossTypes.BOSSES.keys()
	for side in [false, true]:
		var table: Dictionary = Skins.ENEMY if side else Skins.PLAYER
		var side_name := "敌人" if side else "主角"
		for raw_owner in table:
			var owner := str(raw_owner)
			var group: Dictionary = table[raw_owner]
			var owner_ok := Skulls.SKULLS.has(owner) if not side else enemy_ids.has(owner)
			_check(owner_ok, "%s外观 owner 存在: %s" % [side_name, owner])
			var defs: Array = group.get("skins", [])
			_check(not defs.is_empty(), "%s %s 至少有一套外观" % [side_name, owner])
			var ids := {}
			for raw_def in defs:
				var d: Dictionary = raw_def
				var sid := str(d.get("id", ""))
				_check(not sid.is_empty(), "%s/%s skin id 非空" % [owner, sid])
				_check(not ids.has(sid), "%s skin id 不重复: %s" % [owner, sid])
				ids[sid] = true
				_check(not str(d.get("name", "")).is_empty(), "%s/%s 名称非空" % [owner, sid])
				var sc := float(d.get("scale", 0.0))
				_check(sc >= 0.15 and sc <= 1.0, "%s/%s 缩放合法: %.3f" % [owner, sid, sc])
				if d.has("desc"):
					_check(not str(d["desc"]).is_empty(), "%s/%s 描述非空" % [owner, sid])
				if d.has("tag"):
					_check(not str(d["tag"]).is_empty(), "%s/%s 分类标签非空" % [owner, sid])
				if d.has("price"):
					_check(int(d["price"]) > 0, "%s/%s 定价为正: %d" % [owner, sid, int(d["price"])])
				if d.has("portrait"):
					var pic := str(d["portrait"])
					_check(pic != "" and ResourceLoader.exists(pic), "%s/%s 展示图存在: %s" % [owner, sid, pic.get_file()])
				var path := Skins.data_path(owner, sid, side)
				_check(ResourceLoader.exists(path), "%s/%s 骨架文件存在: %s" % [owner, sid, path.get_file()])
				var loadable := Skins.loadable(owner, sid, side)
				_check(loadable, "%s/%s 骨架可加载" % [owner, sid])
				if not loadable:
					continue
				var data = load(path)
				if data == null:
					_check(false, "%s/%s 骨架实例化失败" % [owner, sid])
					continue
				var anims := {}
				for a in data.call("get_animations"):
					anims[str(a.call("get_name"))] = true
				var amap: Dictionary = d.get("anim", {})
				for k in amap:
					var v := str(amap[k])
					_check(anims.has(v), "%s/%s anim 映射 %s -> %s 目标存在" % [owner, sid, str(k), v])
				var preview := str(d.get("preview", ""))
				if preview != "":
					_check(anims.has(preview), "%s/%s 预览动画存在: %s" % [owner, sid, preview])
				var smap: Dictionary = d.get("skill_anims", {})
				for k in smap:
					var v2 := str(smap[k])
					_check(anims.has(v2), "%s/%s skill_anim %s -> %s 目标存在" % [owner, sid, str(k), v2])


# ------------------------------------------------------------------ C. 购买流程

func _audit_purchase_flow() -> void:
	p("---- C1. 强化/重随购买流程 ----")
	Meta.kills = 0
	Meta.clears = 0
	Meta.purchases = {}
	Meta.inventory = {}
	Meta.selected_supply = ""
	for raw_key in Meta.INK_SHOP:
		var key := str(raw_key)
		var item: Dictionary = Meta.INK_SHOP[raw_key]
		if item.has("form") or bool(item.get("supply", false)):
			continue
		var costs: Array = item.get("costs", [])
		Meta.purchases.erase(key)
		Meta.ink = 1000000
		for lv in costs.size():
			_check(Meta.shop_level(key) == lv, "%s 当前等级 %d/%d" % [key, Meta.shop_level(key), costs.size()])
			var want := _price(int(costs[lv]))
			_check(Meta.shop_cost(key) == want, "%s 第 %d 级价格 %d（期望 %d）" % [key, lv + 1, Meta.shop_cost(key), want])
			var before := Meta.ink
			_check(Meta.can_buy(key), "%s 第 %d 级墨锭充足可买" % [key, lv + 1])
			_check(Meta.buy(key), "%s 第 %d 级购买成功" % [key, lv + 1])
			_check(Meta.ink == before - want, "%s 第 %d 级扣款正确（余 %d）" % [key, lv + 1, Meta.ink])
			_check(Meta.shop_level(key) == lv + 1, "%s 购买后等级推进到 %d" % [key, lv + 1])
		_check(Meta.shop_cost(key) == -1, "%s 满级后价格返回 -1" % key)
		_check(not Meta.can_buy(key), "%s 满级后不可购买" % key)
		var ink_before := Meta.ink
		_check(not Meta.buy(key), "%s 满级后重复购买被拒绝" % key)
		_check(Meta.ink == ink_before, "%s 满级后重复购买不扣墨锭" % key)

	p("---- C2. 买断购买流程 ----")
	for raw_key in Meta.INK_SHOP:
		var key := str(raw_key)
		var item: Dictionary = Meta.INK_SHOP[raw_key]
		if not item.has("form"):
			continue
		var form := str(item["form"])
		Meta.purchases.erase(key)
		Meta.kills = 0
		Meta.clears = 0
		_check(not Meta.is_unlocked(form), "%s 目标初始未解锁: %s" % [key, form])
		var want := _price(int(item.get("cost", 0)))
		_check(Meta.shop_cost(key) == want, "%s 买断价 %d（期望 %d）" % [key, Meta.shop_cost(key), want])
		Meta.ink = want
		_check(Meta.can_buy(key), "%s 买断墨锭刚好够" % key)
		_check(Meta.buy(key), "%s 买断成功" % key)
		_check(Meta.ink == 0, "%s 买断扣款到 0" % key)
		_check(bool(Meta.purchases.get(key, false)), "%s 买断记录已写入" % key)
		_check(Meta.is_unlocked(form), "%s 买断后目标已解锁" % form)
		_check(Meta.shop_level(key) == 1, "%s 买断后等级为 1" % key)
		_check(Meta.shop_cost(key) == -1, "%s 已解锁后不再出售" % key)
		_check(not Meta.buy(key), "%s 买断后重复购买被拒绝" % key)

	p("---- C3. 补给购买 / 选择 / 消耗 ----")
	for raw_key in Meta.INK_SHOP:
		var key := str(raw_key)
		var item: Dictionary = Meta.INK_SHOP[raw_key]
		if not bool(item.get("supply", false)):
			continue
		var stock := int(item.get("stock", 0))
		var want := _price(int(item.get("cost", 0)))
		Meta.inventory.erase(key)
		Meta.selected_supply = ""
		Meta.ink = 1000000
		for n in stock:
			_check(Meta.supply_count(key) == n, "%s 当前库存 %d/%d" % [key, Meta.supply_count(key), stock])
			_check(Meta.shop_cost(key) == want, "%s 第 %d 件价格 %d" % [key, n + 1, want])
			_check(Meta.buy(key), "%s 第 %d 件购买成功" % [key, n + 1])
			_check(Meta.supply_count(key) == n + 1, "%s 购买后库存 %d" % [key, n + 1])
		_check(Meta.shop_cost(key) == -1, "%s 库存满后价格返回 -1" % key)
		_check(not Meta.can_buy(key), "%s 库存满后不可购买" % key)
		var ink_before := Meta.ink
		_check(not Meta.buy(key), "%s 库存满后重复购买被拒绝" % key)
		_check(Meta.ink == ink_before, "%s 库存满后不扣墨锭" % key)
		_check(Meta.supply_count(key) == stock, "%s 库存不会被买超" % key)
		_check(Meta.select_supply(key), "%s 有库存时可选中" % key)
		_check(Meta.consume_selected_supply() == key, "%s 启程消耗返回自身" % key)
		_check(Meta.supply_count(key) == stock - 1, "%s 消耗后库存 -1" % key)
		_check(Meta.selected_supply == "", "%s 消耗后选择清空" % key)
		Meta.inventory.erase(key)
		_check(not Meta.select_supply(key), "%s 无库存不可选中" % key)
		_check(Meta.consume_selected_supply() == "", "%s 无库存消耗返回空" % key)
		_check(Meta.selected_supply == "", "%s 无库存时选择保持为空" % key)


# ------------------------------------------------------------------ C4. 局内效果

func _audit_effects() -> void:
	p("---- C4. 局内效果接线 ----")
	Meta.kills = 0
	Meta.clears = 0
	Meta.purchases = {}
	Meta.inventory = {}
	Meta.selected_supply = ""
	Meta.form_nodes = {}
	Run.start()
	var base_hp := Run.max_hp
	_check(base_hp > 0, "基线生命上限 %d" % base_hp)

	Meta.purchases = {"start_hp": 1}
	Run.start()
	_check(Run.max_hp == base_hp + 1, "固元开局生命上限 +1（%d -> %d）" % [base_hp, Run.max_hp])

	Meta.purchases = {}
	Meta.inventory = {"supply_hp": 1}
	Meta.selected_supply = "supply_hp"
	Run.start()
	_check(Run.max_hp == base_hp + 2, "生肌散开局生命上限 +2（%d -> %d）" % [base_hp, Run.max_hp])
	_check(Meta.supply_count("supply_hp") == 0, "生肌散启程消耗 1 件")

	Meta.purchases = {"blessing_reroll": 2}
	Run.start()
	_check(Run.blessing_rerolls == 2, "赐福重随 2 级 -> 每局 2 次（实际 %d）" % Run.blessing_rerolls)

	Meta.purchases = {"upgrade_reroll": 1}
	Meta.inventory = {}
	Meta.selected_supply = ""
	Run.start()
	_check(Meta.shop_level("upgrade_reroll") == 1, "强化重随等级为 1")

	Meta.purchases = {"start_guard": 1}
	Run.start()
	_check(Run.guard_available, "护砚开局置位")

	Meta.purchases = {}
	Meta.inventory = {"supply_revive": 1}
	Meta.selected_supply = "supply_revive"
	Run.start()
	_check(Run.supply_revive, "复活墨符开局置位")
	_check(Meta.supply_count("supply_revive") == 0, "复活墨符启程消耗 1 件")

	Meta.purchases = {}
	Meta.inventory = {"supply_reroll": 1}
	Meta.selected_supply = "supply_reroll"
	Run.start()
	_check(Run.supply_upgrade_rerolls == 2, "重随券开局获得 2 次")
	_check(Run.consume_supply_reroll(), "重随券第 1 次可用")
	_check(Run.consume_supply_reroll(), "重随券第 2 次可用")
	_check(not Run.consume_supply_reroll(), "重随券第 3 次不可用")

	# 聚墨：同一战绩下 0 级与 1 级结算差 2
	Meta.purchases = {}
	Meta.inventory = {}
	Meta.selected_supply = ""
	Meta.ink = 0
	var ink0 := Meta.deposit_ink(0, 0, false)
	Meta.purchases = {"start_ink": 1}
	Meta.ink = 0
	var ink1 := Meta.deposit_ink(0, 0, false)
	_check(ink1 == ink0 + 2, "聚墨 1 级结算 +2（%d -> %d）" % [ink0, ink1])

	# 初锋：只在本局第一个普通房生效
	Meta.purchases = {}
	Meta.form_nodes = {}
	Run.room_index = 0
	Run.depth = 1
	var p = PlayerClass.new()
	var base_buff := int(p._buff_now())
	Meta.purchases = {"start_edge": 1}
	var edge_buff := int(p._buff_now())
	Run.room_index = 1
	var later_buff := int(p._buff_now())
	_check(edge_buff == base_buff + 1, "初锋首个普通房伤害 +1（%d -> %d）" % [base_buff, edge_buff])
	_check(later_buff == base_buff, "初锋离开首个普通房后失效（%d）" % later_buff)
	p.free()

	# 护砚最低 1 伤规则：Run 状态已由 player_test 覆盖，这里只核对布尔接线
	_check(Meta.shop_level("start_guard") == 0, "清理后护砚等级归零")


# ------------------------------------------------------------------ D. UI 展示

func _collect_labels(n: Node, out: Array) -> void:
	if n is Label:
		out.append((n as Label).text)
	for c in n.get_children():
		_collect_labels(c, out)


func _has_label(labels: Array, text: String) -> bool:
	for l in labels:
		if str(l) == text:
			return true
	return false


func _audit_ui() -> void:
	p("---- D. 商栈 UI 展示 ----")
	Meta.kills = 99999
	Meta.clears = 99
	for oid in Skins.ENEMY:
		Meta.seen[str(oid)] = 1
	Meta.purchases = {}
	Meta.inventory = {}
	Meta.ink = 1000000
	var shop = load("res://scenes/ui/shop_panel.tscn").instantiate()
	add_child(shop)
	await get_tree().process_frame

	for tab in TABS:
		shop._tab = tab
		shop._refresh()
		await get_tree().process_frame
		var labels: Array = []
		_collect_labels(shop, labels)
		var expected := 0
		for raw_key in Meta.INK_SHOP:
			var item: Dictionary = Meta.INK_SHOP[raw_key]
			if str(item.get("tab", "")) != tab:
				continue
			expected += 1
			var key := str(raw_key)
			var title := ""
			if bool(item.get("supply", false)):
				title = "%s  库存 %d/%d" % [str(item["label"]), Meta.shop_level(key), Meta.shop_max_level(key)]
			else:
				title = "%s  Lv%d/%d" % [str(item["label"]), Meta.shop_level(key), Meta.shop_max_level(key)]
			_check(_has_label(labels, title), "页签 %s 展示 %s" % [tab, title])
			_check(_has_label(labels, str(item.get("desc", ""))), "%s 描述展示正确" % key)
			var price_text := ""
			var cost := Meta.shop_cost(key)
			if cost < 0:
				price_text = "库存已满" if bool(item.get("supply", false)) else "已满级"
			else:
				price_text = "%d 墨锭" % cost
			_check(_has_label(labels, price_text), "%s 价格展示正确（%s）" % [key, price_text])
		p("页签 %s 在售卡片 %d 张" % [tab, expected])

	# 外观页：逐 owner 检查名称与皮肤条目
	shop._tab = "appearance"
	for side in [false, true]:
		shop._appearance_enemy = bool(side)
		for raw_owner in (Skins.ENEMY if side else Skins.PLAYER):
			var owner := str(raw_owner)
			shop._appearance_owner = owner
			shop._appearance_pick = ""
			shop._refresh()
			await get_tree().process_frame
			var labels2: Array = []
			_collect_labels(shop, labels2)
			var group: Dictionary = Skins.group(owner, bool(side))
			_check(_has_label(labels2, str(group.get("label", owner))), "%s外观分类展示 %s" % ["敌人" if side else "主角", owner])
			for raw_def in Skins.defs(owner, bool(side)):
				var d: Dictionary = raw_def
				_check(_has_label(labels2, str(d.get("name", ""))), "%s/%s 外观条目展示" % [owner, str(d.get("id", ""))])

	# 外观购买/穿戴隔离测试
	Meta.ink = 10000
	Meta.skins = {}
	Meta.skin_worn = {}
	for side in [false, true]:
		for raw_owner in (Skins.ENEMY if side else Skins.PLAYER):
			var owner := str(raw_owner)
			var defs: Array = Skins.defs(owner, bool(side))
			if defs.is_empty():
				continue
			var sid := str((defs[0] as Dictionary).get("id", ""))
			var want_price := Skins.price_of(defs[0] as Dictionary)
			var loadable := Skins.loadable(owner, sid, bool(side))
			var before := Meta.ink
			var bought := Skins.buy(owner, sid, bool(side))
			_check(bought == loadable, "%s/%s 购买结果与可加载性一致" % [owner, sid])
			if bought:
				_check(Meta.ink == before - want_price, "%s/%s 购买扣 %d" % [owner, sid, want_price])
				_check(not Skins.buy(owner, sid, bool(side)), "%s/%s 重复购买被拒绝" % [owner, sid])
				_check(Meta.ink == before - want_price, "%s/%s 重复购买不扣墨锭" % [owner, sid])
				Skins.wear(owner, sid)
				_check(Skins.worn(owner) == sid, "%s 穿戴生效" % owner)
				Skins.wear(owner, "")
				_check(Skins.worn(owner) == "", "%s 恢复原装生效" % owner)

	shop.queue_free()
	await get_tree().process_frame
