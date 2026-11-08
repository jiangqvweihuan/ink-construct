extends Node2D

## 角色数值探针：验证六名角色的基础生命分档、机制血量（梅剑 60 / 红蝶 100）与本次技能数值调整。
## 运行：godot --headless --path . res://scenes/tests/character_balance_probe.tscn

const Skulls := preload("res://scripts/player/skulls.gd")

var _checks := 0
var _failed := 0


func _check(ok: bool, label: String) -> void:
	_checks += 1
	if not ok:
		_failed += 1
	print("PROBE %s %s" % ["PASS" if ok else "FAIL", label])


func _ready() -> void:
	await get_tree().process_frame
	# 隔离存档带来的额外生命，保证只测角色表本身。
	Meta.persist = false
	Meta.purchases = {}
	Meta.form_nodes = {}
	Meta.inventory = {}
	Meta.selected_supply = ""

	# ---------- 1. 基础生命分档 ----------
	var expect := {"c021": 8, "c013": 12, "c023": 60, "z000": 10, "z002": 8, "z003": 10}
	for id in expect:
		var hp := Run.form_base_hp(id)
		_check(hp == int(expect[id]), "%s 基础生命 = %d（期望 %d）" % [id, hp, int(expect[id])])
	_check(Run.form_base_hp("unknown_form") == Run.BASE_HP,
		"未登记形态回落到全局基础生命 %d" % Run.BASE_HP)

	# ---------- 2. 开局生命与角色表一致（扣掉成就等全角色通用加成后应相等） ----------
	Run.start(Run.MODE_ADVENTURE, "c021", 1, false)
	var offset: int = Run.max_hp - Run.form_base_hp("c021")
	for id in expect:
		Run.start(Run.MODE_ADVENTURE, id, 1, false)
		var diff: int = Run.max_hp - Run.form_base_hp(id)
		_check(diff == offset, "%s 开局生命接入角色表（基础 %d，实际 %d）" % [
			id, Run.form_base_hp(id), Run.max_hp])

	# ---------- 3. 机制血量保持 ----------
	_check(Run.RED_BUTTERFLY_HP == 100, "红蝶复活上限保持 100（限时资源池）")
	Run.start(Run.MODE_ADVENTURE, "c023", 1, false)
	_check(Run.max_hp >= 60, "梅剑开局生命仍为 60 档（实际 %d）" % Run.max_hp)

	# ---------- 4. 本次技能数值 ----------
	var c021: Dictionary = Skulls.get_profile("c021")
	var atk3: Dictionary = c021["attacks"][2]
	var atk3_hits: Array = atk3["hits"]
	_check(atk3_hits.size() == 2 and int(atk3_hits[0].get("damage", atk3["damage"])) == 1 \
		and int(atk3_hits[1].get("damage", atk3["damage"])) == 2,
		"绯刃普攻第三段两段伤害 1 + 2（整套 5 伤）")
	_check(int(c021["skills"]["skill02-cankao"]["hits"][0]["damage"]) == 3,
		"绯刃 U 飞刃伤害 2 -> 3")

	var z002: Dictionary = Skulls.get_profile("z002")
	_check(int(z002["skills"]["skill03"]["heal"]) == 3, "绛弦 L 黍离治疗 2 -> 3")

	var z003: Dictionary = Skulls.get_profile("z003")
	_check(is_equal_approx(float(z003["skills"]["skill06"]["cooldown"]), 16.0),
		"影殇 U 时停冷却 14 -> 16 秒")
	_check(is_equal_approx(float(z003["skills"]["sky_skill18_02"]["cooldown"]), 30.0),
		"影殇 P 天倾冷却 25 -> 30 秒")

	var z000: Dictionary = Skulls.get_profile("z000")
	var z000_hits: Array = z000["skills"]["skill09"]["hits"]
	_check(is_equal_approx(float(z000_hits[z000_hits.size() - 1].get("heal_ratio", 0.0)), 0.25),
		"剑仙 O 觉醒收招治疗 30% -> 25%")

	Run.active = false
	print("PROBE RESULT checks=%d fail=%d" % [_checks, _failed])
	await get_tree().process_frame
	get_tree().quit(1 if _failed > 0 else 0)
