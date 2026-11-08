extends RefCounted

## 斗蛐蛐名录：只收录敌人，直接实例化正式房间用的场景，
## 攻击逻辑与闯关里完全一致（同一套 c016.gd / Boss 脚本），本文件只提供出场清单。
##
## 解锁名单必须与图鉴数据严格对齐：图鉴里不存在的角色统一标成「不可用·未知」，
## 只占位展示，不可选中，也不会被派上场。

const EnemyTypes := preload("res://scripts/enemies/enemy_types.gd")
const BossTypes := preload("res://scripts/enemies/boss_types.gd")
const Codex := preload("res://scripts/ui/codex_panel.gd")

const ENEMY_ORDER := ["c016", "c017", "c035", "c037", "c018", "c012"]
const BOSS_ORDER := ["c009", "c015a1", "c001", "c008", "c032"]

const UNKNOWN_NAME := "不可用·未知"

const ENEMY_SCENES := {
	"c016": "res://scenes/enemies/c016.tscn",
	"c017": "res://scenes/enemies/c017.tscn",
	"c035": "res://scenes/enemies/c035.tscn",
	"c037": "res://scenes/enemies/c037_elite.tscn",
	"c018": "res://scenes/enemies/c018_elite.tscn",
	"c012": "res://scenes/enemies/c012_elite.tscn",
}


## 斗蛐蛐的已解锁角色列表。当前与图鉴收录完全同源；
## 以后若接入其他解锁来源，只改这里（或调用 entries() 显式传入名单）。
static func unlocked_ids() -> Array:
	return ENEMY_ORDER + BOSS_ORDER


## 图鉴里真实收录的角色 id：与图鉴页签共用同一份数据源。
static func codex_ids() -> Array:
	return Codex.ENEMY_ORDER + BossTypes.ROSTER


## 该 id 是否是图鉴内存在的角色：既要有图鉴条目，也要有真实战斗数据。
static func in_codex(id: String) -> bool:
	if not codex_ids().has(id):
		return false
	if BossTypes.ROSTER.has(id):
		return BossTypes.BOSSES.has(id)
	return EnemyTypes.TYPES.has(id)


## 出战前最后一道过滤：只保留图鉴内可用的角色，去重并保持原顺序。
static func available_ids(ids: Array) -> Array:
	var out: Array = []
	for id in ids:
		var sid := str(id)
		if in_codex(sid) and not out.has(sid):
			out.append(sid)
	return out


## 名录：默认取已解锁列表；传入 unlocked 可覆盖（仍逐项校验图鉴数据）。
static func entries(unlocked: Array = []) -> Array:
	var ids: Array = unlocked if not unlocked.is_empty() else unlocked_ids()
	var list: Array = []
	for id in ids:
		var sid := str(id)
		var duplicated := false
		for e in list:
			if str(e["id"]) == sid:
				duplicated = true
				break
		if not duplicated:
			list.append(_entry(sid))
	return list


## 查名录；不在名录或图鉴里的 id 返回「不可用·未知」占位，绝不回落到第一个角色。
static func find(id: String) -> Dictionary:
	for e in entries():
		if str(e["id"]) == id:
			return e
	return _entry(id)


static func _entry(id: String) -> Dictionary:
	if not in_codex(id):
		return {
			"id": id,
			"kind": "未知",
			"name": UNKNOWN_NAME,
			"scene": "",
			"scale": 1.0,
			"radius": 30.0,
			"available": false,
		}
	var boss := BossTypes.ROSTER.has(id)
	var t: Dictionary = BossTypes.BOSSES.get(id, {}) if boss else EnemyTypes.TYPES.get(id, {})
	return {
		"id": id,
		"kind": "首领" if boss else "杂兵",
		"name": str(t.get("label", id)),
		"scene": str(BossTypes.SCENES.get(id, BossTypes.DEFAULT_SCENE)) if boss else str(ENEMY_SCENES.get(id, BossTypes.DEFAULT_SCENE)),
		"scale": float(t.get("scale", 1.0)),
		"radius": float(t.get("body_radius", 30.0)),
		"available": true,
	}
