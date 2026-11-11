extends Node2D

## C033 舞姬（杂兵）自检：配置、素材、普攻/主动伤害、残舞被动、掉落。

const EnemyTypes = preload("res://scripts/enemies/enemy_types.gd")
const EnemyClass = preload("res://scripts/enemies/c016.gd")
const WaveSpawner = preload("res://scripts/systems/wave_spawner.gd")

var _checks := 0
var _failed := 0


class FakeTarget extends Node2D:
	var hp := 100
	var body_radius := 30.0
	var last_move: Dictionary = {}
	var last_damage := 0

	func hurt(amount: int, _kb: Vector2, _source, move: Dictionary) -> void:
		last_damage = amount
		last_move = move.duplicate(true)
		hp -= amount


func _check(ok: bool, label: String) -> void:
	_checks += 1
	if not ok:
		_failed += 1
	print("[C033] ", ("PASS " if ok else "FAIL "), label)


func _ready() -> void:
	Run.balance_scaling = false
	Meta.persist = false
	var t: Dictionary = EnemyTypes.get_type("c033")
	_check(not t.is_empty() and str(t.get("label", "")) == "舞姬", "已注册为杂兵「舞姬」")
	_check(not bool(t.get("elite", true)), "杂兵标记 elite=false")
	_check(WaveSpawner.NORMAL_SCENES.has("res://scenes/enemies/c033.tscn"), "已加入普通怪刷新池")
	_check(int(t.get("hp", 0)) == 5 and float(t.get("chase_speed", 0.0)) == 175.0, "基础生命 / 追击速度符合杂兵档位")
	_check(int(t.get("drop", {}).get("ink", 0)) == 1 and int(t.get("drop", {}).get("every", 0)) == 5, "掉落：每 5 杀 1 墨锭")
	_check(int(t.get("drop", {}).get("ink", 0)) > 0, "掉落奖励为正")
	var data = load(str(t["data"]))
	_check(data != null and bool(data.call("is_skeleton_data_loaded")), "C033 骨架可加载")
	var names := {}
	for a in data.call("get_animations"):
		names[str(a.call("get_name"))] = true
	for nm in ["stand", "atked", "skill15", "skill09_03"]:
		_check(names.has(nm), "动画存在：" + nm)
	_check(float(data.call("get_height")) > 400.0, "骨架身高读取正常")

	var e = load("res://scenes/enemies/c033.tscn").instantiate()
	e.position = Vector2(400, 560)
	add_child(e)
	await get_tree().process_frame
	_check(e.max_hp == 5 and e.hp == 5, "场景实例生命值 5")
	_check(e.stop_tier() == "mob", "时停 / 分档按杂兵处理")
	_check(e._attack_anims == ["skill15", "skill09_03"], "普攻 / 主动招式表正确")
	_check(e._attack_rules.get("skill09_03", {}).get("cooldown", 0.0) == 9.6, "主动技冷却 9.6 秒")
	_check(e._damage_map.get("skill09_03", 0) == 2 and e._damage_map.get("skill15", 0) == 1, "普攻 1 / 主动 2")
	_check(e._hit_effects.get("skill09_03", {}).get("bleed", 0) == 1, "主动技附加 1 层流血")

	var target := FakeTarget.new()
	target.position = Vector2(500, 560)
	target.hp = 100
	add_child(target)
	e.facing = 1
	e._target = target
	e._attack_move = "skill15"
	e._attack_visual = "skill15"
	e._deal_hit(0)
	_check(target.last_damage == 1 and target.hp == 99, "普攻命中 1 伤")
	target.hp = 100
	e._attack_move = "skill09_03"
	e._attack_visual = "skill09_03"
	e._deal_hit(0)
	_check(target.last_damage == 2 and target.hp == 98, "主动技命中 2 伤")
	_check(int(target.last_move.get("bleed", 0)) == 1, "主动技命中传递流血")
	target.hp = 100
	target.position.x = e.global_position.x + 135.0 + 30.0 + 5.0
	e._attack_move = "skill15"
	e._attack_visual = "skill15"
	e._deal_hit(0)
	_check(target.hp == 100, "超出 135px 判程不命中")
	target.position.x = e.global_position.x + 135.0 + 30.0 - 1.0
	e._deal_hit(0)
	_check(target.hp == 99, "135px 边缘命中")

	# 残舞：生命跌至 35% 以下时提速并缩短出手间隔
	e.hp = 2
	e.max_hp = 5
	e.attack_cooldown = 1.6
	e.chase_speed = 175.0
	e._enraged = false
	e.take_damage(1, 0.0)
	_check(e._enraged and absf(e.attack_cooldown - 1.152) < 0.001 and absf(e.chase_speed - 227.5) < 0.001,
		"残舞被动：低血后冷却 ×0.72、移速 ×1.3")

	# 掉落：累计第 5 杀给 1 墨锭（先锁掉成就奖励，避免干扰墨锭断言）
	for a in Achievements.ACHIEVEMENTS:
		Achievements.unlocked[str(a["id"])] = true
	Meta.seen["c033"] = 4
	Meta.ink = 0
	e.die()
	_check(Meta.enemy_kills("c033") == 5, "第 5 杀累计正确")
	_check(Meta.ink == 1, "第 5 杀掉落 1 墨锭")
	Meta.seen.erase("c033")
	Meta.ink = 0
	print("[C033] DONE checks=%d failed=%d" % [_checks, _failed])
	get_tree().quit()
