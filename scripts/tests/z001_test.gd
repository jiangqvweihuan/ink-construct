extends Node2D

## 烬生·Z001 机制回归：动画映射、三段普攻、K 六段、L 斩杀、I 满血、O 路径秒杀、P 眩晕、
## 受击阈值、燃尽、战狂与换房清空。

const PlayerClass := preload("res://scripts/player/player.gd")
const Skulls = preload("res://scripts/player/skulls.gd")
const BattleStatus = preload("res://scripts/ui/battle_status.gd")

var _checks := 0
var _failed := 0


class Target extends Node2D:
	var hp := 100
	var max_hp := 100
	var stop_kind := "mob"
	var stunned := 0.0
	var vulnerable := 0.0
	var vulnerable_ratio := 0.0
	var body_radius := 30.0

	func take_damage(amount: int, _source_x := 0.0) -> void:
		hp = maxi(0, hp - amount)

	func take_damage_from(amount: int, _source: Node) -> void:
		take_damage(amount)

	func stop_tier() -> String:
		return stop_kind

	func stun(dur: float) -> void:
		stunned = maxf(stunned, dur)

	func apply_vulnerable(time: float, ratio: float) -> void:
		vulnerable = time
		vulnerable_ratio = ratio

	func is_on_floor() -> bool:
		return true

	func damage_taken_scale() -> float:
		return 1.0


func _check(ok: bool, label: String) -> void:
	_checks += 1
	if not ok:
		_failed += 1
	print("[Z1] ", ("PASS " if ok else "FAIL "), label)


func _make_player() -> PlayerClass:
	var p = load("res://scenes/player/player.tscn").instantiate()
	p.skull_id = "z001"
	p.position = Vector2(400, 560)
	add_child(p)
	p.set_physics_process(false)
	return p


func _target(x: float, hp := 100) -> Target:
	var t := Target.new()
	t.hp = hp
	t.max_hp = hp
	t.position = Vector2(x, 560)
	t.add_to_group("enemies")
	add_child(t)
	return t


func _ready() -> void:
	Run.balance_scaling = false
	Meta.persist = false
	var p := _make_player()
	var bonus := Achievements.bonus_int("damage")

	# 形态表 / 动画映射
	_check(p.anim_map["idle"] == "stand" and p.anim_map["run"] == "run", "待机 123 / 跑步 69 映射正确")
	_check(p.hud_skills.size() == 5 and BattleStatus.skill_name(p, 0) == "焚骨三叩" \
		and BattleStatus.skill_name(p, 4) == "烬火燎原", "HUD 五技能名称与招式表对齐")
	_check(p.anim_map["low_idle"] == "weak" and p.anim_map["dead"] == "dead", "虚弱 126 / 死亡 48 映射正确")
	_check(p._knock_chain == ["atked_heavy", "atked_fall_end", "getup"], "≥5 伤走 27 → 26 → 50 倒地链")
	_check(p._jump_seg and p.anim_map["jump_mid"] == "jump02_mid" and p.anim_map["jump_down"] == "jump03_down" \
		and p.anim_map["jump_land"] == "jump03_end", "跳跃 53 / 56 / 57 且无起跳过渡")
	var pool: Array = p._dash_pool.get("move", [])
	_check(pool.size() == 2 and str(pool[0]["anim"]) == "autorush" and str(pool[1]["anim"]) == "dash_front", "闪避 28 / 47 随机池")
	var d0: float = float(pool[0]["time"]) * float(pool[0]["speed"])
	var d1: float = float(pool[1]["time"]) * float(pool[1]["speed"])
	_check(absf(d0 - 127.0) <= 2.0 and absf(d1 - 130.0) <= 2.0, "两段闪避位移都在 130px 左右")

	# 普攻配置：动画 2 三段 2 / 2 / 3，末段 10 秒易伤
	var atk: Dictionary = p.attacks[0]
	var hits: Array = atk["hits"]
	_check(str(atk["anim"]) == "3" and hits.size() == 3, "J 绑定动画 2 并分三段")
	_check(int(hits[0]["damage"]) == 2 and int(hits[1]["damage"]) == 2 and int(hits[2]["damage"]) == 3, "J 伤害 2 / 2 / 3")
	_check(float(hits[2]["vulnerable"]["time"]) == 10.0, "J 末段易伤 10 秒")
	var tj := _target(450, 100)
	p._attack_idx = 0
	p._deal_hit({"damage": 3, "range": 200.0, "height": 200.0,
		"vulnerable": {"ratio": 0.25, "time": 10.0}})
	_check(tj.hp == 100 - 3 - bonus and tj.vulnerable == 10.0, "J 末段命中实际挂上 10 秒易伤")

	# K：动画 6 连播 3 次，每轮 2 段 1 伤，合计 6
	p._skill_cds.clear()
	p._start_skill("burn_k")
	_check(p._skill_anim == "atk03" and p._skill_hits.size() == 6, "K 连播 3 次 × 2 段")
	var total := 0
	for h in p._skill_hits:
		total += int(h["damage"])
	_check(total == 6, "K 总伤害 6")
	_check(absf(p._skill_dur - 0.45 * 3.0) < 0.001, "K 总时长 = 3 个动画周期（实际 %.3f）" % p._skill_dur)

	# L：5 + 已损生命 20%（Boss 10%）
	var t := _target(450, 50)
	t.max_hp = 100
	p._skill_name = "burn_l"
	p._skill_start_x = p.global_position.x
	p._deal_skill_hit({"at": 0.0, "damage": 5, "range": 200.0, "height": 200.0,
		"execute": {"normal": 0.2, "boss": 0.1}})
	_check(t.hp == 50 - 15 - bonus, "L 对普通目标 5 + 已损 50 的 20% = 15")
	t.hp = 50
	t.max_hp = 100
	t.stop_kind = "boss"
	p._deal_skill_hit({"at": 0.0, "damage": 5, "range": 200.0, "height": 200.0,
		"execute": {"normal": 0.2, "boss": 0.1}})
	_check(t.hp == 50 - 10 - bonus, "L 对 Boss 追伤改为已损 10% = 10")

	# O：路径小怪秒杀 / 精英固定 8
	t.hp = 30
	t.max_hp = 30
	t.stop_kind = "mob"
	p._skill_start_x = p.global_position.x - 60.0
	p._deal_skill_hit({"at": 0.0, "range": 160.0, "height": 140.0, "path": true, "damage": 8,
		"dash_kill": {"elite_damage": 8}})
	_check(t.hp == 0, "O 路径普通小怪直接秒杀")
	t.hp = 50
	t.max_hp = 50
	t.stop_kind = "elite"
	p._deal_skill_hit({"at": 0.0, "range": 160.0, "height": 140.0, "path": true, "damage": 8,
		"dash_kill": {"elite_damage": 8}})
	_check(t.hp == 42, "O 对精英固定 8 伤")

	# P：正前方 12 伤 + 5 秒眩晕
	t.hp = 100
	t.max_hp = 100
	t.stunned = 0.0
	p._deal_skill_hit({"at": 0.0, "damage": 12, "range": 300.0, "height": 200.0, "stun": 5.0})
	_check(t.hp == 100 - 12 - bonus and t.stunned == 5.0, "P 12 伤 + 5 秒眩晕")

	# 受击阈值：≤4 不打断技能；≥5 进入倒地链
	p.hp = 10
	p.max_hp = 10
	p.state = p.State.SKILL
	p._skill_name = "burn_l"
	p._skill_timer = 1.0
	p._hurt_invincible = 0.0
	p.hurt(4, Vector2.ZERO, null)
	_check(p.hp == 6 and p.state == p.State.SKILL, "≤4 伤不硬直、不打断技能")
	p.hp = 10
	p.state = p.State.IDLE
	p._hurt_invincible = 0.0
	p._knock_cd = 0.0
	p.hurt(5, Vector2.ZERO, null)
	_check(p.state == p.State.HURT and not p._hurt_chain.is_empty(), "≥5 伤触发倒地链")

	# I：回满生命
	p.state = p.State.IDLE
	p._skill_cds.clear()
	p.hp = 3
	p.max_hp = 10
	p._start_skill("burn_i")
	_check(p.hp == p.max_hp, "I 将生命恢复至满值")

	# 燃尽：致命伤不死亡，后续伤害扣上限；回血退出
	p.state = p.State.IDLE
	p._hurt_invincible = 0.0
	p.hp = 3
	p.max_hp = 10
	p.hurt(5, Vector2.ZERO, null)
	_check(p.hp == 0 and bool(p._z001_burnout) and p.state != p.State.DEAD, "致命伤进入燃尽而非死亡")
	p._hurt_invincible = 0.0
	p.hurt(4, Vector2.ZERO, null)
	_check(p.max_hp == 6 and p.hp == 0 and bool(p._z001_burnout), "燃尽期间伤害改为扣生命上限")
	p._restore_hp(2)
	_check(not bool(p._z001_burnout) and p.hp == 2, "获得回血立即退出燃尽并正常回血")
	p.max_hp = 3
	p.hp = 0
	p._z001_burnout = true
	p._hurt_invincible = 0.0
	p.hurt(5, Vector2.ZERO, null)
	_check(p.state == p.State.DEAD, "生命上限清零后判定死亡")

	# 战狂：5 次受击 / 5 次击杀各叠 1 层；伤害追加；换房清空
	var p2 := _make_player()
	p2._z001_fury = 0
	p2._z001_hit_acc = 0
	p2._z001_kill_acc = 0
	for i in 4:
		p2._z001_on_hit_taken()
	_check(p2._z001_fury == 0, "受击 4 次未叠战意")
	p2._z001_on_hit_taken()
	_check(p2._z001_fury == 1, "受击 5 次叠 1 层战意")
	p2._z001_kill_acc = 4
	p2._z001_on_kill()
	_check(p2._z001_fury == 2, "击杀 5 次再叠 1 层战意")
	var t2 := _target(450, 100)
	var before := t2.hp
	p2._damage_enemy(t2, 5)
	_check(before - t2.hp == 5 + 2 + bonus, "每层战意追加等量焚烧伤害")
	p2.on_room_enter()
	_check(p2._z001_fury == 0 and p2._z001_kill_acc == 0 and p2._z001_hit_acc == 0, "换房清空战意与累计")

	print("[Z1] DONE checks=%d failed=%d" % [_checks, _failed])
	get_tree().quit(1 if _failed > 0 else 0)
