extends Node2D

## 联机稳定性探针：出生安全距离、最近玩家索敌、单击伤害上限、按槽位复活与机制血回归。
## 只验证规则本身，不跑完整网络会话（那部分由 net_unit_probe / net_integration_probe 覆盖）。

const SpawnerClass := preload("res://scripts/systems/wave_spawner.gd")
const EnemyClass := preload("res://scripts/enemies/c016.gd")

## 索敌/出生测试用的假玩家：只提供 hp / state / 坐标
class Dummy extends Node2D:
	var hp := 10
	var state := 0

var _checks := 0
var _failed := 0


func _check(ok: bool, label: String) -> void:
	_checks += 1
	if not ok:
		_failed += 1
	print("PROBE ", "PASS " if ok else "FAIL ", label)


func _ready() -> void:
	_test_spawn_distance()
	_test_nearest_target()
	_test_hit_cap()
	await _test_revive()
	Run.net_role = ""
	Run.active = false
	print("PROBE RESULT checks=%d fail=%d" % [_checks, _failed])
	await get_tree().process_frame
	get_tree().quit(1 if _failed > 0 else 0)


# ---------- 1. 出生点与玩家保持安全距离（含头顶/面部） ----------
func _test_spawn_distance() -> void:
	var spawner = SpawnerClass.new()
	spawner.spawn_y = 560.0
	spawner.spawn_safe_dist = 320.0

	var above := Dummy.new()
	above.position = Vector2(1200, 400) # 站在出生点上方的空中：面部/头顶
	add_child(above)
	spawner.player_refs = [above]
	_check(not spawner._safe_from_players(1200.0), "玩家头顶/面部位置判定为不安全")
	_check(spawner._safe_from_players(1700.0), "远离玩家的位置判定为安全")

	# 4 人把候选点全占住时，宁可不刷也不能贴脸刷
	var spread: Array = []
	for i in 4:
		var d := Dummy.new()
		d.position = Vector2(600.0 + i * 400.0, 560.0)
		add_child(d)
		spread.append(d)
	spawner.player_refs = spread
	_check(is_nan(spawner._pick_x()), "所有候选点都被玩家占住时返回 NAN（延迟刷新）")

	# 只剩一名玩家时一定能找到安全点
	spawner.player_refs = [above]
	above.position = Vector2(300, 560)
	var picked := spawner._pick_x()
	_check(not is_nan(picked) and spawner._safe_from_players(picked), "有安全点时会挑到远离玩家的位置")

	for n in [above]:
		n.queue_free()
	for n in spread:
		n.queue_free()
	spawner.free()


# ---------- 2. 敌人锁定最近的存活玩家 ----------
func _test_nearest_target() -> void:
	var a := Dummy.new()
	a.position = Vector2(900, 560)
	var b := Dummy.new()
	b.position = Vector2(1300, 560)
	add_child(a)
	add_child(b)

	_check(EnemyClass.nearest_living_player(Vector2(1000, 560), [a, b]) == a,
		"两名玩家中锁定更近的 P1")
	b.position = Vector2(1040, 560)
	_check(EnemyClass.nearest_living_player(Vector2(1000, 560), [a, b]) == b,
		"最近玩家变化后立即改锁 P2，不黏住旧目标")
	a.hp = 0
	a.position = Vector2(1010, 560)
	_check(EnemyClass.nearest_living_player(Vector2(1000, 560), [a, b]) == b,
		"跳过已阵亡玩家，改锁最近的存活玩家")
	b.state = 8
	_check(EnemyClass.nearest_living_player(Vector2(1000, 560), [a, b]) == null,
		"全部玩家阵亡时返回空目标，不锁尸体")
	a.queue_free()
	b.queue_free()


# ---------- 3. 敌方单击伤害不超过生命上限的一半 ----------
func _test_hit_cap() -> void:
	Run.start(Run.MODE_ADVENTURE, "c021", 1, false)
	Run.set_net_players(4)
	_check(Run.cap_enemy_hit(100, 8) == 4, "8 血角色单击伤害上限 4（两击才倒）")
	_check(Run.cap_enemy_hit(100, 12) == 6, "12 血角色单击伤害上限 6")
	_check(Run.cap_enemy_hit(100, 60) == 30, "梅剑 60 血单击伤害上限 30")
	_check(Run.cap_enemy_hit(3, 8) == 3, "未超上限的伤害保持原值")
	_check(8 - Run.cap_enemy_hit(100, 8) > 0, "4 人难度下小兵一击不会直接击杀 8 血角色")
	Run.balance_scaling = false
	_check(Run.cap_enemy_hit(100, 8) == 100, "测试关闭缩放时不做硬上限（机制断言不受影响）")
	Run.balance_scaling = true


# ---------- 4. 联机阵亡 -> 下一房间 50% 复活；红蝶/梅剑机制保留 ----------
func _test_revive() -> void:
	Run.start(Run.MODE_ADVENTURE, "z003", 1, false)
	Run.net_role = "host"
	Run.set_net_players(2)
	Run.mark_slot_dead(1)
	Run.advance()
	_check(Run.slot_hp_of(1) == 5, "影殇 10 血复活为 5（50%）")

	Run.start(Run.MODE_ADVENTURE, "c013", 1, false)
	Run.net_role = "host"
	Run.set_net_players(2)
	Run.mark_slot_dead(1)
	Run.advance()
	_check(Run.slot_hp_of(1) == 6, "镇岳 12 血复活为 6（50%）")

	Run.start(Run.MODE_ADVENTURE, "c021", 1, false)
	Run.net_role = "host"
	Run.set_net_players(2)
	Run.c021_red_butterfly_used = true
	Run.mark_slot_dead(1)
	Run.advance()
	_check(Run.slot_hp_of(1) == 50, "红蝶复活封顶 50（不再满 100）")
	_check(Run.calculated_max_hp() == 50, "红蝶复活后生命上限封到 50")
	_check(Run.c021_red_butterfly_used, "红蝶仍是每秒流失状态（机制未被修复掉）")

	Run.start(Run.MODE_ADVENTURE, "c023", 1, false)
	Run.net_role = "host"
	Run.set_net_players(2)
	Run.mark_slot_dead(1)
	Run.advance()
	_check(Run.slot_hp_of(1) == 30, "梅剑复活先拿 30（50%）")

	# 进新房间后由「每房回满」补到 60，验证机制血仍然完整
	var p = load("res://scenes/player/player.tscn").instantiate()
	p.input_slot = 1
	add_child(p)
	await get_tree().process_frame
	Run.skull_id = "c023"
	Run.slot_hp[1] = 30
	Run.apply_to(p, 1)
	_check(p.hp == 60 and p.max_hp == 60, "梅剑复活进入新房间后回满 60（核心机制保留）")
	p.queue_free()
