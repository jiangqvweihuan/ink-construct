extends Node2D

## 敌人数值缩放探针：验证单人 / 双人（本机 + 局域网）三套数值互相独立，
## 普通怪生命、伤害、节奏、防御、刷新数量、同屏上限与 Boss 生命 / 阶段加成都按表生效。
## 运行：godot --headless --path . res://scenes/tests/enemy_balance_probe.tscn

const ENEMY_SCENE := preload("res://scenes/enemies/c016.tscn")
const BOSS_SCENE := preload("res://scenes/enemies/bosses/boss.tscn")
const WU_CHE_SCENE := preload("res://scenes/enemies/bosses/wu_che.tscn")
const EnemyTypes := preload("res://scripts/enemies/enemy_types.gd")

var _checks := 0
var _failed := 0


func _check(ok: bool, label: String) -> void:
	_checks += 1
	if not ok:
		_failed += 1
	print("PROBE %s %s" % ["PASS" if ok else "FAIL", label])


func _spawn_enemy() -> Node:
	var e = ENEMY_SCENE.instantiate()
	add_child(e)
	return e


func _spawn_boss(type_id: String) -> Node:
	var b = BOSS_SCENE.instantiate()
	b.type_id = type_id
	b.hp_scale = Run.boss_hp_scale()
	b.cd_scale = Run.boss_cd_scale()
	add_child(b)
	return b


func _ready() -> void:
	await get_tree().process_frame
	Run.balance_scaling = true

	# ---------- 1. 未开局：全部回落中性，保证旧测试与斗蛐蛐不受影响 ----------
	Run.active = false
	Run.local_coop = false
	Run.net_role = ""
	_check(is_equal_approx(Run.enemy_hp_mul(), 1.0), "未开局生命倍率=1")
	_check(is_equal_approx(Run.enemy_cd_scale(), 1.0), "未开局节奏倍率=1")
	_check(is_equal_approx(Run.enemy_taken_scale(), 1.0), "未开局承伤倍率=1")
	_check(Run.max_concurrent() == 6 and is_equal_approx(Run.spawn_interval(), 0.9), "未开局刷新上限/间隔=旧值")
	_check(Run.enemy_damage(3) == 3, "未开局基础伤害不变")

	# ---------- 2. 单人 ----------
	Run.start(Run.MODE_ADVENTURE, "c021", 1, false)
	_check(Run.player_count() == 1, "单人玩家数=1")
	var solo_hp := Run.enemy_hp_mul()
	var solo_dmg := Run.enemy_damage(3)
	_check(is_equal_approx(solo_hp, 1.30), "单人生命倍率=1.30")
	_check(solo_dmg == 4, "单人 3 点基础伤害 -> 4")
	_check(Run.enemy_damage(5) == 6, "单人 5 点基础伤害 -> 6")
	_check(is_equal_approx(Run.enemy_cd_scale(), 0.90), "单人出手间隔=0.90")
	_check(is_equal_approx(Run.enemy_taken_scale(), 0.94), "单人承伤倍率=0.94")
	_check(Run.max_concurrent() == 4, "单人同屏上限=4")
	_check(is_equal_approx(Run.spawn_interval(), 1.10), "单人补怪间隔=1.10")
	var solo_waves := Run.scale_waves(Run.ROOMS[0]["waves"])
	_check(int(solo_waves[0]["count"]) == 4 and int(solo_waves[1]["count"]) == 5,
		"单人首关波次 5/6 -> 4/5")

	var e = _spawn_enemy()
	e.configure({"hp": 6, "attack_cooldown": 2.0})
	_check(e.max_hp == 8, "单人普通怪 6 血 -> 8（实际 %d）" % e.max_hp)
	_check(is_equal_approx(e.attack_cooldown, 1.8), "单人普通怪出手 2.0s -> 1.8s")
	e.queue_free()

	var b = _spawn_boss("c015a1")
	var solo_boss_hp: int = int(b.max_hp)
	_check(solo_boss_hp == 88, "单人焚鼎生命 68 -> 88（实际 %d）" % solo_boss_hp)
	_check(is_equal_approx(b.attack_damage_mul(), 1.0), "Boss 阶段 0 伤害倍率=1.0")
	b.stage = 1
	_check(is_equal_approx(b.attack_damage_mul(), 1.1), "Boss 阶段 1 伤害倍率=1.10")
	b.stage = 2
	_check(is_equal_approx(b.attack_damage_mul(), 1.2), "Boss 阶段 2 伤害倍率=1.20")
	b.queue_free()

	var w = WU_CHE_SCENE.instantiate()
	w.type_id = "c001"
	w.hp_scale = Run.boss_hp_scale()
	add_child(w)
	_check(w.max_hp > 5, "单人武车耐久随人数生命倍率提升（%d）" % w.max_hp)
	w.queue_free()

	# ---------- 3. 双人（本机双人） ----------
	Run.start(Run.MODE_ADVENTURE, "c021", 1, true)
	_check(Run.player_count() == 2, "双人玩家数=2")
	var duo_hp := Run.enemy_hp_mul()
	var duo_dmg := Run.enemy_damage(3)
	_check(is_equal_approx(duo_hp, 1.95), "双人生命倍率=1.95")
	_check(not is_equal_approx(duo_hp, solo_hp) and duo_hp > solo_hp, "双人生命独立于单人且更高")
	_check(duo_dmg == 4 and Run.enemy_damage(5) == 6, "双人 3/5 点基础伤害 -> 4/6（与单人同档，靠数量/频率加难度）")
	_check(is_equal_approx(Run.enemy_cd_scale(), 0.80), "双人出手间隔=0.80")
	_check(is_equal_approx(Run.enemy_taken_scale(), 0.88), "双人承伤倍率=0.88")
	_check(Run.max_concurrent() == 6 and is_equal_approx(Run.spawn_interval(), 0.85), "双人刷新上限/间隔独立")
	var duo_waves := Run.scale_waves(Run.ROOMS[0]["waves"])
	_check(int(duo_waves[0]["count"]) == 5 and int(duo_waves[1]["count"]) == 6,
		"双人首关波次 5/6 -> 5/6")

	var e2 = _spawn_enemy()
	e2.configure({"hp": 6, "attack_cooldown": 2.0})
	_check(e2.max_hp == 12, "双人普通怪 6 血 -> 12（实际 %d）" % e2.max_hp)
	_check(is_equal_approx(e2.attack_cooldown, 1.60), "双人普通怪出手 2.0s -> 1.60s")
	e2.queue_free()

	var b2 = _spawn_boss("c015a1")
	_check(b2.max_hp == 133, "双人焚鼎生命 68 -> 133（实际 %d）" % b2.max_hp)
	b2.stage = 2
	_check(is_equal_approx(b2.attack_damage_mul(), 1.24), "双人 Boss 阶段 2 伤害倍率=1.24")
	b2.queue_free()

	# ---------- 4. 局域网双人：与单人彻底解耦，按人数走同一独立行 ----------
	Run.start(Run.MODE_ADVENTURE, "c021", 1, false)
	Run.net_role = "host"
	Run.set_net_players(2)
	_check(Run.player_count() == 2, "局域网主机玩家数=2")
	_check(is_equal_approx(Run.enemy_hp_mul(), 1.95) and Run.max_concurrent() == 6,
		"局域网双人使用独立 2P 行（生命 1.95 / 上限 6）")
	Run.net_role = ""

	# ---------- 5. 局域网 3/4 人：动态匹配独立难度行 ----------
	Run.start(Run.MODE_ADVENTURE, "c021", 1, false)
	Run.net_role = "host"
	Run.set_net_players(3)
	_check(Run.player_count() == 3, "局域网 3 人玩家数=3")
	_check(is_equal_approx(Run.enemy_hp_mul(), 2.40) and Run.max_concurrent() == 7,
		"3 人生命 2.40 / 上限 7")
	_check(Run.enemy_damage(5) == 6, "3 人 5 点基础伤害仍为 6（严控单击秒杀）")
	Run.set_net_players(4)
	_check(Run.player_count() == 4, "局域网 4 人玩家数=4")
	_check(is_equal_approx(Run.enemy_hp_mul(), 2.85) and Run.max_concurrent() == 8,
		"4 人生命 2.85 / 上限 8")
	_check(is_equal_approx(Run.enemy_cd_scale(), 0.72) and Run.enemy_damage(3) <= 4,
		"4 人出手更快但单次伤害不超 4")
	Run.net_role = ""
	Run.set_net_players(1)

	Run.active = false
	print("PROBE RESULT checks=%d fail=%d" % [_checks, _failed])
	await get_tree().process_frame
	get_tree().quit(1 if _failed > 0 else 0)
