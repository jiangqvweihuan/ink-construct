extends Node

## 一局（run）的状态：房间进度 + 跨房间带走的东西 + 局内强化等级。
## 局内循环：连续 3 个房间，每清一间可以花墨骨选一次强化，三关全过进 Boss 房，斩杀 Boss 通关。
## 墨骨由 Score 管（跨房间不清空），只有开新一局才 reset。

const BASE_HP := 8
const SWAP_FROM := 8 # 换头基础消耗（与 player.gd 的 SWAP_COST 对齐）
const BossTypes := preload("res://scripts/enemies/boss_types.gd")

## 每个房间的波次配置；index 越大越难
const ROOMS := [
	{
		"label": "残卷山谷 · 外院",
		"waves": [
			{"count": 5, "hp": 2, "speed": 1.0},
			{"count": 6, "hp": 2, "speed": 1.02},
		],
	},
	{
		"label": "残卷山谷 · 中庭",
		"waves": [
			{"count": 6, "hp": 3, "speed": 1.0, "elite": 1},
			{"count": 7, "hp": 3, "speed": 1.05},
		],
	},
	{
		"label": "残卷山谷 · 墨堂",
		"waves": [
			{"count": 6, "hp": 3, "speed": 1.1, "elite": 1},
			{"count": 4, "hp": 4, "speed": 1.05, "elite": 1},
		],
	},
]

## Boss 房（三关全过后进入）：无波次，只有 Run.boss_id 指定的一只 Boss
const BOSS_ROOM := {"label": "残卷山谷 · 墨堂深处", "waves": []}

## 局内强化 · 通用池：全部是"能和机制搭话"的词条（不做纯数值移速），任何形态都吃得下。
## cost = 8 + 4 * 已拥有等级
const UPGRADES := {
	"damage": {"label": "锋锐", "desc": "全部伤害 +1", "max": 5, "icon": "icon_sword"},
	"cooldown": {"label": "静心", "desc": "技能冷却 -15%", "max": 3, "icon": "icon_undo"},
	"hp": {"label": "铁骨", "desc": "生命上限 +1，并回满", "max": 3, "icon": "icon_potion"},
	"swap": {"label": "轻骨", "desc": "换头消耗 -3 墨骨", "max": 2, "icon": "icon_currency"},
	# 疾影：冲刺时长 +20% —— 冲刺距离与"完美闪避"判定窗口同步变长，回收冲刺冷却 -10%
	"dash": {"label": "疾影", "desc": "冲刺更远，完美闪避窗口更长", "max": 3, "icon": "icon_arrow_up"},
	# 掠影：完美闪避的收益直接加档（加伤与垫底无敌一起抬）
	"dodge": {"label": "掠影", "desc": "完美闪避赏伤 +1、无敌 +0.2 秒", "max": 2, "icon": "icon_medal"},
}

## 形态专属强化 · 流派制：每个形态 3 条流派，各 3 级（初/续/极）。
## tier 2/3 需要先拥有前置卡（req）——一局 3 次强化正好能把一条流派走到"极"。
## theme 给面板配色用（0 朱砂 / 1 墨青 / 2 赭金）。
## 只对当前形态生效：换头后旧形态的卡休眠，换回来再生效（player._apply_form_mods 过滤 forms）。
const FORM_UPGRADES := {
	# ---------- 双刺·冷红绫：吸血续航 / 群战范围 / 冲刺输出 ----------
	"c021_blood_1": {"label": "血饮 · 初", "desc": "技能命中回 1 生命（6 秒一次）", "max": 1, "icon": "icon_potion", "forms": ["c021"], "path": "血饮", "tier": 1, "theme": 0},
	"c021_blood_2": {"label": "血饮 · 续", "desc": "回血升到 2，间隔缩到 4 秒", "max": 1, "icon": "icon_potion", "forms": ["c021"], "path": "血饮", "tier": 2, "theme": 0, "req": "c021_blood_1"},
	"c021_blood_3": {"label": "血饮 · 极", "desc": "回血同时 4 秒内全伤害 +1", "max": 1, "icon": "icon_potion", "forms": ["c021"], "path": "血饮", "tier": 3, "theme": 0, "req": "c021_blood_2"},
	"c021_sweep_1": {"label": "锋扫 · 初", "desc": "攻击范围 +30%", "max": 1, "icon": "icon_sword", "forms": ["c021"], "path": "锋扫", "tier": 1, "theme": 1},
	"c021_sweep_2": {"label": "锋扫 · 续", "desc": "范围再 +25%，普攻伤害 +1", "max": 1, "icon": "icon_sword", "forms": ["c021"], "path": "锋扫", "tier": 2, "theme": 1, "req": "c021_sweep_1"},
	"c021_sweep_3": {"label": "锋扫 · 极", "desc": "范围再 +20%，普攻伤害再 +1", "max": 1, "icon": "icon_sword", "forms": ["c021"], "path": "锋扫", "tier": 3, "theme": 1, "req": "c021_sweep_2"},
	"c021_dash_1": {"label": "疾刃 · 初", "desc": "冲刺终点斩身前敌人，1 伤", "max": 1, "icon": "icon_arrow_up", "forms": ["c021"], "path": "疾刃", "tier": 1, "theme": 2},
	"c021_dash_2": {"label": "疾刃 · 续", "desc": "冲刺斩 2 伤，命中即回满冲刺", "max": 1, "icon": "icon_arrow_up", "forms": ["c021"], "path": "疾刃", "tier": 2, "theme": 2, "req": "c021_dash_1"},
	"c021_dash_3": {"label": "疾刃 · 极", "desc": "冲刺斩 3 伤，命中回 1 墨骨", "max": 1, "icon": "icon_arrow_up", "forms": ["c021"], "path": "疾刃", "tier": 3, "theme": 2, "req": "c021_dash_2"},
	# ---------- 梅剑·白疏影：鞭术范围 / 内劲转鞭 / 铁骨站桩 ----------
	"c023_whip_1": {"label": "鞭术 · 初", "desc": "攻击范围 +25%", "max": 1, "icon": "icon_sword", "forms": ["c023"], "path": "鞭术", "tier": 1, "theme": 0},
	"c023_whip_2": {"label": "鞭术 · 续", "desc": "范围再 +25%，普攻伤害 +1", "max": 1, "icon": "icon_sword", "forms": ["c023"], "path": "鞭术", "tier": 2, "theme": 0, "req": "c023_whip_1"},
	"c023_whip_3": {"label": "鞭术 · 极", "desc": "范围再 +25%，普攻伤害再 +1", "max": 1, "icon": "icon_sword", "forms": ["c023"], "path": "鞭术", "tier": 3, "theme": 0, "req": "c023_whip_2"},
	"c023_force_1": {"label": "内劲 · 初", "desc": "转鞭每跳伤害 +1", "max": 1, "icon": "icon_undo", "forms": ["c023"], "path": "内劲", "tier": 1, "theme": 1},
	"c023_force_2": {"label": "内劲 · 续", "desc": "转鞭出鞭更快（0.5→0.35 秒）", "max": 1, "icon": "icon_undo", "forms": ["c023"], "path": "内劲", "tier": 2, "theme": 1, "req": "c023_force_1"},
	"c023_force_3": {"label": "内劲 · 极", "desc": "转鞭范围 +40%，技能冷却 -25%", "max": 1, "icon": "icon_undo", "forms": ["c023"], "path": "内劲", "tier": 3, "theme": 1, "req": "c023_force_2"},
	"c023_iron_1": {"label": "铁骨 · 初", "desc": "受到的伤害 -1（最低仍吃 1）", "max": 1, "icon": "icon_potion", "forms": ["c023"], "path": "铁骨", "tier": 1, "theme": 2},
	"c023_iron_2": {"label": "铁骨 · 续", "desc": "减伤保持，技能冷却 -20%", "max": 1, "icon": "icon_potion", "forms": ["c023"], "path": "铁骨", "tier": 2, "theme": 2, "req": "c023_iron_1"},
	"c023_iron_3": {"label": "铁骨 · 极", "desc": "受到的伤害 -2（最低仍吃 1）", "max": 1, "icon": "icon_potion", "forms": ["c023"], "path": "铁骨", "tier": 3, "theme": 2, "req": "c023_iron_2"},
	# ---------- 力僧·定山：金刚反伤 / 震地范围 / 禅定减伤 ----------
	"c013_vajra_1": {"label": "金刚 · 初", "desc": "定山反弹伤害 +2", "max": 1, "icon": "icon_medal", "forms": ["c013"], "path": "金刚", "tier": 1, "theme": 0},
	"c013_vajra_2": {"label": "金刚 · 续", "desc": "定山砸地回血 +2", "max": 1, "icon": "icon_potion", "forms": ["c013"], "path": "金刚", "tier": 2, "theme": 0, "req": "c013_vajra_1"},
	"c013_vajra_3": {"label": "金刚 · 极", "desc": "反弹再 +2，定山冷却 -30%", "max": 1, "icon": "icon_medal", "forms": ["c013"], "path": "金刚", "tier": 3, "theme": 0, "req": "c013_vajra_2"},
	"c013_quake_1": {"label": "震地 · 初", "desc": "攻击范围 +35%", "max": 1, "icon": "icon_sword", "forms": ["c013"], "path": "震地", "tier": 1, "theme": 1},
	"c013_quake_2": {"label": "震地 · 续", "desc": "范围再 +25%，普攻伤害 +1", "max": 1, "icon": "icon_sword", "forms": ["c013"], "path": "震地", "tier": 2, "theme": 1, "req": "c013_quake_1"},
	"c013_quake_3": {"label": "震地 · 极", "desc": "范围再 +25%，普攻伤害再 +1", "max": 1, "icon": "icon_sword", "forms": ["c013"], "path": "震地", "tier": 3, "theme": 1, "req": "c013_quake_2"},
	"c013_zen_1": {"label": "禅定 · 初", "desc": "受到伤害 -1（最低仍吃 1）", "max": 1, "icon": "icon_potion", "forms": ["c013"], "path": "禅定", "tier": 1, "theme": 2},
	"c013_zen_2": {"label": "禅定 · 续", "desc": "每次受伤回 1 墨骨", "max": 1, "icon": "icon_currency", "forms": ["c013"], "path": "禅定", "tier": 2, "theme": 2, "req": "c013_zen_1"},
	"c013_zen_3": {"label": "禅定 · 极", "desc": "受到伤害 -2（最低仍吃 1）", "max": 1, "icon": "icon_potion", "forms": ["c013"], "path": "禅定", "tier": 3, "theme": 2, "req": "c013_zen_2"},
	# ---------- 剑仙·洛惊鸿：剑气强度 / 齐发数量 / 御剑冷却 ----------
	"z000_qi_1": {"label": "剑气 · 初", "desc": "剑气伤害 +1", "max": 1, "icon": "icon_sword", "forms": ["z000"], "path": "剑气", "tier": 1, "theme": 0},
	"z000_qi_2": {"label": "剑气 · 续", "desc": "剑气伤害再 +1，飞行快 30%", "max": 1, "icon": "icon_sword", "forms": ["z000"], "path": "剑气", "tier": 2, "theme": 0, "req": "z000_qi_1"},
	"z000_qi_3": {"label": "剑气 · 极", "desc": "剑气穿透敌人，命中后继续飞", "max": 1, "icon": "icon_sword", "forms": ["z000"], "path": "剑气", "tier": 3, "theme": 0, "req": "z000_qi_2"},
	"z000_twin_1": {"label": "双发 · 初", "desc": "剑气齐发 +1 道", "max": 1, "icon": "icon_arrow_up", "forms": ["z000"], "path": "双发", "tier": 1, "theme": 1},
	"z000_twin_2": {"label": "双发 · 续", "desc": "剑气齐发 +1 道（共三道）", "max": 1, "icon": "icon_arrow_up", "forms": ["z000"], "path": "双发", "tier": 2, "theme": 1, "req": "z000_twin_1"},
	"z000_twin_3": {"label": "双发 · 极", "desc": "剑气齐发 +1 道（共四道）", "max": 1, "icon": "icon_arrow_up", "forms": ["z000"], "path": "双发", "tier": 3, "theme": 1, "req": "z000_twin_2"},
	"z000_calm_1": {"label": "御剑 · 初", "desc": "技能冷却 -25%", "max": 1, "icon": "icon_undo", "forms": ["z000"], "path": "御剑", "tier": 1, "theme": 2},
	"z000_calm_2": {"label": "御剑 · 续", "desc": "剑气射程 +30%", "max": 1, "icon": "icon_undo", "forms": ["z000"], "path": "御剑", "tier": 2, "theme": 2, "req": "z000_calm_1"},
	"z000_calm_3": {"label": "御剑 · 极", "desc": "技能冷却再 -15%，剑气伤害 +1", "max": 1, "icon": "icon_undo", "forms": ["z000"], "path": "御剑", "tier": 3, "theme": 2, "req": "z000_calm_2"},
	# ---------- 银夜·将去未还：轻功闪避流 / 时停流 / 位移斩杀流 ----------
	"z003_qinggong_1": {"label": "轻功 · 初", "desc": "跳得更高，空中悬停更久", "max": 1, "icon": "icon_arrow_up", "forms": ["z003"], "path": "轻功", "tier": 1, "theme": 0},
	"z003_qinggong_2": {"label": "轻功 · 续", "desc": "完美闪避额外减全部技能 2 秒", "max": 1, "icon": "icon_arrow_up", "forms": ["z003"], "path": "轻功", "tier": 2, "theme": 0, "req": "z003_qinggong_1"},
	"z003_qinggong_3": {"label": "轻功 · 极", "desc": "完美闪避减全部技能 4 秒", "max": 1, "icon": "icon_arrow_up", "forms": ["z003"], "path": "轻功", "tier": 3, "theme": 0, "req": "z003_qinggong_2"},
	"z003_stop_1": {"label": "时停 · 初", "desc": "时停时长 +1 秒（全档位）", "max": 1, "icon": "icon_undo", "forms": ["z003"], "path": "时停", "tier": 1, "theme": 1},
	"z003_stop_2": {"label": "时停 · 续", "desc": "时停期间全伤害 +2", "max": 1, "icon": "icon_undo", "forms": ["z003"], "path": "时停", "tier": 2, "theme": 1, "req": "z003_stop_1"},
	"z003_stop_3": {"label": "时停 · 极", "desc": "时停冷却 -30%", "max": 1, "icon": "icon_undo", "forms": ["z003"], "path": "时停", "tier": 3, "theme": 1, "req": "z003_stop_2"},
	"z003_kill_1": {"label": "杀阵 · 初", "desc": "O 位移距离 +200px", "max": 1, "icon": "icon_sword", "forms": ["z003"], "path": "杀阵", "tier": 1, "theme": 2},
	"z003_kill_2": {"label": "杀阵 · 续", "desc": "O 伤害 +2", "max": 1, "icon": "icon_sword", "forms": ["z003"], "path": "杀阵", "tier": 2, "theme": 2, "req": "z003_kill_1"},
	"z003_kill_3": {"label": "杀阵 · 极", "desc": "O 命中返还 3 秒冷却", "max": 1, "icon": "icon_sword", "forms": ["z003"], "path": "杀阵", "tier": 3, "theme": 2, "req": "z003_kill_2"},
}

## 开局赐福：每局出发前三选一（blessing_panel 弹出），效果只在本局生效
const BLESSINGS := {
	"revive": {"label": "残墨续命", "desc": "阵亡后以 4 点生命原地爬起一次"},
	"bones": {"label": "墨囊饱满", "desc": "开局墨骨 +15"},
	"hp": {"label": "铁砚护身", "desc": "生命上限 +2"},
}

var active := false
var room_index := 0
var hp := BASE_HP
var max_hp := BASE_HP
var skull_id := "c021"
var upgrades: Dictionary = {}
var blessing := ""
var blessing_used := false # 续命赐福是否已消耗（一局一次）
var boss_id := "" # 本局 Boss 房登场的 Boss（开局随机定）
var meta_snapshot := {} # 开局时的 Meta 快照，结算面板 diff 出本局收获


## 开新一局（主菜单点开始 / 重开）
func start() -> void:
	active = true
	room_index = 0
	max_hp = BASE_HP + Meta.start_hp_bonus() # 固元：墨锭商店的永久开局生命
	hp = max_hp
	skull_id = "c021"
	upgrades = {}
	blessing = ""
	blessing_used = false
	# 本局 Boss：从 Boss 名录随机挑一只（名录见 boss_types.gd，转换完成前是占位）
	boss_id = BossTypes.ROSTER[randi() % BossTypes.ROSTER.size()]
	meta_snapshot = Meta.snapshot() # 结算面板据此展示本局契合/解锁收获
	Score.reset()
	if Meta.start_bones_bonus() > 0: # 墨囊：永久开局墨骨
		Score.add_bones(Meta.start_bones_bonus())


func room_config() -> Dictionary:
	if is_boss_room():
		return BOSS_ROOM
	return ROOMS[clampi(room_index, 0, ROOMS.size() - 1)]


func room_label() -> String:
	return str(room_config()["label"])


func room_no() -> String:
	if is_boss_room():
		return "Boss"
	return "%d / %d" % [room_index + 1, ROOMS.size()]


## 三关全过后进入 Boss 房（room_index 越过普通房间数）
func is_boss_room() -> bool:
	return room_index >= ROOMS.size()


func is_last_room() -> bool:
	return room_index >= ROOMS.size() - 1


func advance() -> void:
	room_index += 1


func level(key: String) -> int:
	return int(upgrades.get(key, 0))


## 价格：流派卡按层级递增（初 8 / 续 14 / 极 20），通用卡按已拥有等级递增
func upgrade_cost(key: String) -> int:
	var info: Dictionary = card_info(key)
	if info.has("tier"):
		return 8 + 6 * (int(info["tier"]) - 1)
	return 8 + 4 * level(key)


## 卡牌信息查询：通用与形态专属两表合并（面板/购买统一走这里）
func card_info(key: String) -> Dictionary:
	if UPGRADES.has(key):
		return UPGRADES[key]
	return FORM_UPGRADES.get(key, {})


## 卡池轮转：每次三选一保证「一条正在走的流派 · 一条新流派 · 一张通用」，
## 一局的 3 次强化刚好能把一条流派从"初"推到"极"，选择即流派。
func roll_cards(count: int = 3) -> Array:
	var gen: Array = [] # 通用池：还没满级
	for k in UPGRADES:
		if level(k) < int(UPGRADES[k]["max"]):
			gen.append(k)
	var cont: Array = [] # 已开张流派的下一个层级（前置已拥有）
	var fresh: Array = [] # 还没开张的流派第一层
	for k in FORM_UPGRADES:
		var info: Dictionary = FORM_UPGRADES[k]
		if not (info["forms"] as Array).has(skull_id) or level(k) >= int(info["max"]):
			continue
		var req := str(info.get("req", ""))
		if req == "":
			fresh.append(k)
		elif level(req) > 0:
			cont.append(k)
	var picked: Array = []
	_take_random(cont, picked, count)
	_take_random(fresh, picked, count)
	_take_random(gen, picked, count)
	var rest: Array = []
	rest.append_array(fresh)
	rest.append_array(cont)
	rest.append_array(gen)
	rest.shuffle()
	for k in rest:
		if picked.size() >= count:
			break
		if not picked.has(k):
			picked.append(k)
	picked.shuffle()
	return picked


## 从池里随机取一张塞进结果（池空或已取满就跳过）
func _take_random(pool: Array, into: Array, count: int) -> void:
	if pool.is_empty() or into.size() >= count:
		return
	into.append(pool[randi() % pool.size()])


## 花墨骨买一个强化。成功会立刻影响本房间的玩家（room 负责调用 apply_to）
func buy(key: String) -> bool:
	var info: Dictionary = card_info(key)
	if info.is_empty():
		return false
	if level(key) >= int(info["max"]):
		return false
	if not Score.spend_bones(upgrade_cost(key)):
		return false
	upgrades[key] = level(key) + 1
	if key == "hp":
		# 与 apply_to 同公式：铁砚护身赐福 + 固元（局外）都要算进上限
		max_hp = BASE_HP + level("hp") + (2 if blessing == "hp" else 0) + Meta.start_hp_bonus()
		hp = max_hp # 买了加血就回满，下一层的起始血量一并提高
	return true


## 离开房间前：把玩家当前状态写进 run
func snapshot(player) -> void:
	hp = int(player.hp)
	max_hp = int(player.max_hp)
	skull_id = str(player.skull_id)


## 进入房间后：把 run 状态装回玩家（强化 / 血量 / 形态）
func apply_to(player) -> void:
	# 玩家脚本没编译过时实例是裸 CharacterBody2D，直接跳过避免 Invalid access
	if not player.has_method("set_upgrades"):
		push_error("Run.apply_to: 玩家缺少 set_upgrades（脚本未加载？），状态未装回")
		return
	player.set_upgrades(upgrades)
	max_hp = BASE_HP + level("hp") + (2 if blessing == "hp" else 0) + Meta.start_hp_bonus() # 铁砚护身赐福 + 固元（局外）
	player.max_hp = max_hp
	player.hp = clampi(hp, 1, max_hp)
	if player.skull_id != skull_id:
		player.swap_skull(skull_id)
	player.hp_changed.emit(player.hp, player.max_hp)
