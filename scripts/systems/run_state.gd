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

## 局内强化：花墨骨三选一。cost = 8 + 4 * 已拥有等级
const UPGRADES := {
	"damage": {"label": "锋锐", "desc": "全部伤害 +1", "max": 5},
	"speed": {"label": "疾行", "desc": "移动速度 +12%", "max": 4},
	"cooldown": {"label": "静心", "desc": "技能冷却 -15%", "max": 3},
	"hp": {"label": "铁骨", "desc": "生命上限 +1，并回满", "max": 3},
	"swap": {"label": "轻骨", "desc": "换头消耗 -3 墨骨", "max": 2},
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


func upgrade_cost(key: String) -> int:
	return 8 + 4 * level(key)


## 随机 3 个还没满级的强化（不够 3 个就给几个）
func roll_cards(count: int = 3) -> Array:
	var pool: Array = []
	for k in UPGRADES:
		if level(k) < int(UPGRADES[k]["max"]):
			pool.append(k)
	pool.shuffle()
	if pool.size() > count:
		pool = pool.slice(0, count)
	return pool


## 花墨骨买一个强化。成功会立刻影响本房间的玩家（room 负责调用 apply_to）
func buy(key: String) -> bool:
	var info: Dictionary = UPGRADES.get(key, {})
	if info.is_empty():
		return false
	if level(key) >= int(info["max"]):
		return false
	if not Score.spend_bones(upgrade_cost(key)):
		return false
	upgrades[key] = level(key) + 1
	if key == "hp":
		max_hp = BASE_HP + level("hp")
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
