extends RefCounted

## 斗蛐蛐名录：只收录敌人，直接实例化正式房间用的场景，
## 攻击逻辑与闯关里完全一致（同一套 c016.gd / Boss 脚本），本文件只提供出场清单。

const EnemyTypes := preload("res://scripts/enemies/enemy_types.gd")
const BossTypes := preload("res://scripts/enemies/boss_types.gd")

const ENEMY_ORDER := ["c016", "c017", "c035", "c037", "c018", "c012"]
const BOSS_ORDER := ["c009", "c015a1", "c001", "c008", "c032"]

const ENEMY_SCENES := {
	"c016": "res://scenes/enemies/c016.tscn",
	"c017": "res://scenes/enemies/c017.tscn",
	"c035": "res://scenes/enemies/c035.tscn",
	"c037": "res://scenes/enemies/c037_elite.tscn",
	"c018": "res://scenes/enemies/c018_elite.tscn",
	"c012": "res://scenes/enemies/c012_elite.tscn",
}


static func entries() -> Array:
	var list: Array = []
	for id in ENEMY_ORDER:
		list.append(_enemy(str(id), "杂兵"))
	for id in BOSS_ORDER:
		list.append(_enemy(str(id), "首领"))
	return list


static func find(id: String) -> Dictionary:
	for e in entries():
		if str(e["id"]) == id:
			return e
	return entries()[0]


static func _enemy(id: String, kind: String) -> Dictionary:
	var boss := kind == "首领"
	var t: Dictionary = BossTypes.BOSSES.get(id, {}) if boss else EnemyTypes.TYPES.get(id, {})
	return {
		"id": id,
		"kind": kind,
		"name": str(t.get("label", id)),
		"scene": str(BossTypes.SCENES.get(id, BossTypes.DEFAULT_SCENE)) if boss else str(ENEMY_SCENES.get(id, BossTypes.DEFAULT_SCENE)),
		"scale": float(t.get("scale", 1.0)),
		"radius": float(t.get("body_radius", 30.0)),
	}
