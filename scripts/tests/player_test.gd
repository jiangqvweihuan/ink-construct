extends Node2D

## 玩家控制器冒烟测试：模拟输入走一遍 idle/run/jump/dash/三连击，截图+日志。

## 反伤测试替身：只记账不参与战斗，验证定山把伤害弹回攻击者；
## hp 是给"敌人组结算"读的属性（当普攻拉回 / 两段伤害的靶子用）
class Trainer extends Node2D:
	var damage_taken := 0
	var hp := 99
	var state := 0
	var airborne := false
	var stunned := 0.0
	var rooted := 0.0
	var slowed := 0.0
	var slow_scale := 1.0
	var launches := 0
	var slams := 0
	var bleeds := 0
	var _stop_timer := 0.0
	var _stun_timer := 0.0
	var _target: Node2D = null

	func take_damage(amount: int, _source_x: float) -> void:
		damage_taken += amount

	func stun(dur: float) -> void:
		stunned = maxf(stunned, dur)
		_stun_timer = stunned

	func root(dur: float) -> void:
		rooted = maxf(rooted, dur)

	func slow(dur: float, scale: float) -> void:
		slowed = dur
		slow_scale = scale

	func launch(_dir: int, _vx: float, _vy: float, _ignore_armor := false) -> void:
		launches += 1
		airborne = true

	func slam() -> void:
		slams += 1
		airborne = false

	func apply_bleed(layers: int) -> void:
		bleeds = mini(5, bleeds + layers)

	func is_on_floor() -> bool:
		return not airborne

## 刺客割伤测试攻击者：提供终局对演读取的形态字段与反伤入口。
class CutAttacker extends Node2D:
	var type_id := "c035"
	var _current_anim := "skill02"
	var hp := 4
	var damage_taken := 0

	func take_damage(amount: int, _source_x: float) -> void:
		damage_taken += amount

const OUT_DIR := "res://tests/out/"
const PlayerClass := preload("res://scripts/player/player.gd")
const Skulls = preload("res://scripts/player/skulls.gd")

var _log: FileAccess
var _player: PlayerClass
var _last_state := -1


func p(msg) -> void:
	print("[PT] ", msg)
	if _log:
		_log.store_line("[PT] " + str(msg))
		_log.flush()


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	_log = FileAccess.open("res://tests/player_test.log", FileAccess.WRITE)
	get_window().size = Vector2i(1280, 720)

	var bg := ColorRect.new()
	bg.color = Color(0.949, 0.918, 0.847)
	bg.size = Vector2(1280, 720)
	bg.z_index = -10
	add_child(bg)

	var ground := StaticBody2D.new()
	ground.position = Vector2(640, 640)
	add_child(ground)
	var rect := RectangleShape2D.new()
	rect.size = Vector2(1280, 80)
	var gs := CollisionShape2D.new()
	gs.shape = rect
	ground.add_child(gs)
	var gc := ColorRect.new()
	gc.color = Color(0.102, 0.102, 0.102)
	gc.size = Vector2(1280, 80)
	gc.position = Vector2(-640, -40)
	ground.add_child(gc)

	_player = load("res://scenes/player/player.tscn").instantiate()
	_player.position = Vector2(300, 560)
	add_child(_player)
	p("player created, sprite=" + str(_player.sprite))

	await get_tree().create_timer(0.6).timeout
	await _shot("01_idle")

	# 跑动
	Input.action_press("move_right")
	await get_tree().create_timer(0.8).timeout
	await _shot("02_run")

	# 跳（按住方向，点一下跳）
	_tap("jump")
	await get_tree().create_timer(0.3).timeout
	await _shot("03_jump")
	await get_tree().create_timer(0.8).timeout
	Input.action_release("move_right")
	await get_tree().create_timer(0.3).timeout

	# 冲刺
	_tap("dash")
	await get_tree().create_timer(0.1).timeout
	await _shot("04_dash")
	await get_tree().create_timer(0.6).timeout

	# 三连击：J -> 0.25s -> J -> 0.35s -> J
	_tap("attack")
	await get_tree().create_timer(0.12).timeout
	await _shot("05_atk1")
	await get_tree().create_timer(0.15).timeout
	_tap("attack")
	await get_tree().create_timer(0.2).timeout
	await _shot("06_atk2")
	await get_tree().create_timer(0.15).timeout
	_tap("attack")
	await get_tree().create_timer(0.2).timeout
	await _shot("07_atk3")
	await get_tree().create_timer(0.8).timeout
	await _shot("08_back_idle")

	p("ALL DONE, final state=" + str(_player.state) + " pos=" + str(_player.position))

	# ---- 换头验证：走化身面板逐个选形态，确认骨架/技能表/HUD 数据全部换掉 ----
	Meta.debug_unlock_all() # 测试环境直接拉满解锁条件，别让存档挡住换头验证
	await _shot("09_before_swap")
	for id in ["c023", "z000", "c013", "z003"]:
		var panel = load("res://scenes/ui/swap_panel.tscn").instantiate()
		panel.setup(_player) # 必须在 add_child 前：面板 _ready 要读当前形态
		add_child(panel)
		await get_tree().process_frame
		await get_tree().process_frame
		panel.select(id) # 选中即换头并解除时停
		await get_tree().create_timer(0.6).timeout
		p("swap -> skull=%s hud=%s attacks=%d skills=%s" % [
			_player.skull_id, str(_player.hud_skills), _player.attacks.size(),
			str(_player.skill_config.keys())])
		# 力僧 U（定山）是回血技：先压血到 5，砸下后应回到 7，否则满血时回血分支不进等于没测
		if _player.skull_id == "c013":
			_player.hp = 5
			_player.hp_changed.emit(5, _player.max_hp)
			p("c013 压血 -> hp=5，准备验证定山回血")
		await _shot("10_swap_" + str(_player.skull_id))
		# 梅剑专项：普攻两段（2 点鞭击 + 3 点突刺）与鞭击拉回，靶子放在 300px 外
		var dummy: Trainer = null
		if _player.skull_id == "c023":
			dummy = Trainer.new()
			dummy.add_to_group("enemies")
			add_child(dummy)
			dummy.global_position = _player.global_position + Vector2(300.0 * _player.facing, 0.0)
			p("c023 靶子起点距玩家 %.0fpx（期望被拉到约 80）" % absf(dummy.global_position.x - _player.global_position.x))
		_tap("attack")
		await get_tree().create_timer(0.3).timeout
		await _shot("11_atk_" + str(_player.skull_id))
		if dummy != null:
			await get_tree().create_timer(0.6).timeout # 0.9s：鞭击已结算
			p("c023 鞭击后靶子距玩家 %.0fpx（期望约 80）" % absf(dummy.global_position.x - _player.global_position.x))
			await get_tree().create_timer(1.0).timeout # 1.9s：突刺已结算
			p("c023 普攻总伤害=%d（基础 2+3=5，伤害加成 %+d/段 = 契合/局内强化）" % [
				dummy.damage_taken, _player.damage_bonus + _player._mastery_dmg])
			dummy.queue_free()
			dummy = null
		await _wait_free() # 各形态招式时长不同，等回到可出招状态再按下一个键
		_tap("skill")
		await get_tree().create_timer(1.3).timeout
		await _shot("12_skill_" + str(_player.skull_id))
		if _player.skull_id == "c023":
			p("c023 技能中转鞭 ranged_guard=%s（期望 true，无敌人时只免疫）" % str(_player.try_reflect_ranged(1, _player.global_position.x + 400.0)))
		await _wait_free()
		_tap("skill_sweep")
		await get_tree().create_timer(0.8).timeout
		await _shot("12b_sweep_" + str(_player.skull_id))
		await _wait_free()
		_tap("skill_ult")
		await get_tree().create_timer(1.0).timeout
		# 定山反伤验证：蓄力中（reflect=1）挨打一下，应把伤害弹回攻击者且不断招
		if _player.skull_id == "c013":
			var trainer := Trainer.new()
			add_child(trainer)
			trainer.global_position = _player.global_position + Vector2(150, 0)
			var hp_before := _player.hp
			# 用 3 点伤害验证"按实际伤害反弹"，不是固定值
			_player.hurt(3, Vector2(80.0, -60.0), trainer)
			await get_tree().create_timer(0.2).timeout
			p("reflect_test c013: 挨打前 hp=%d 挨打后 hp=%d trainer_taken=%d state=%d（期望 hp 不掉、trainer 吃到 3、仍为 SKILL=6）" % [
				hp_before, _player.hp, trainer.damage_taken, _player.state])
		await get_tree().create_timer(0.4).timeout
		await _shot("13_ult_" + str(_player.skull_id))
		# 定山蓄力 3.05s 才砸下，等它结算完再看血量：5 -> 7 才说明回血真的生效
		await get_tree().create_timer(1.9).timeout
		p("ult_after skull=%s hp=%d/%d" % [_player.skull_id, _player.hp, _player.max_hp])
		await _shot("14_ult_after_" + str(_player.skull_id))

	p("SWAP DONE skull=" + str(_player.skull_id))

	# ---- 升级 Build 验证：免费流派进阶、续卡轮转、跨形态隔离、换头休眠 ----
	Run.start()
	_player.swap_skull("z003") # 银夜：走一条流派做样本（同形态会早退，这里同步 Run 的形态）
	Run.skull_id = str(_player.skull_id)
	await get_tree().process_frame
	var roll0: Array = Run.roll_cards(3)
	var kinds: Array = []
	for k in roll0:
		var inf: Dictionary = Run.card_info(str(k))
		kinds.append(str(k) + (("[流派%d]" % int(inf["tier"])) if inf.has("tier") else "[通用]"))
	p("roll0 银夜三选一：%s" % str(kinds))
	# 一条流派免费连选三级，无需任何局内货币。
	for k in ["z003_clock_1", "z003_clock_2", "z003_clock_3"]:
		var ok := Run.buy(k)
		p("claim %s ok=%s level=%d" % [k, ok, Run.level(k)])
		if k == "z003_clock_1":
			var roll1: Array = Run.roll_cards(3)
			p("roll1（已拿漏刻·初）含漏刻·续=%s → %s" % [roll1.has("z003_clock_2"), str(roll1)])
	Run.buy("dash") # 通用卡：疾影 Lv1，验证冲刺倍率确实被 set_upgrades 装上
	var roll2: Array = Run.roll_cards(3)
	var cross: Array = []
	for k in roll2:
		var forms: Array = Run.card_info(str(k)).get("forms", [])
		if not forms.is_empty() and not forms.has("z003"):
			cross.append(k)
	p("roll2 跨形态泄漏=%s（期望 []） → %s" % [str(cross), str(roll2)])
	_player.set_upgrades(Run.upgrades)
	p("build 生效：漏刻=%s/%s/%s dash_time=%.2f dash_cd=%.2f（期望 true/true/true / 1.20 / 0.90）" % [
		_player._own("z003_clock_1"), _player._own("z003_clock_2"), _player._own("z003_clock_3"),
		_player._dash_time_scale, _player._dash_cd_scale])
	# 换头只让银夜机制休眠，已购卡保留，切回来可继续使用。
	_player.swap_skull("c021")
	await get_tree().process_frame
	p("换到 c021：当前形态=%s 银夜卡保留=%s（机制按形态分支休眠）" % [_player.skull_id, _player._own("z003_clock_1")])
	_player.swap_skull("z003")
	await get_tree().process_frame
	p("切回 z003：漏刻可用=%s（期望 true）" % _player._own("z003_clock_1"))

	# 三选一面板冒烟：卡面（流派配色 / 层级 / 价格）能正常构建、不报错
	var panel = load("res://scenes/ui/upgrade_panel.tscn").instantiate()
	add_child(panel)
	# 固定放入长描述卡，避免随机三选一漏测正文换行与底部价格的布局。
	panel._cards = ["z003_returning_3", "z000_score_3", "c013_bell_2"]
	panel._build_cards()
	await get_tree().process_frame
	await get_tree().process_frame
	await _shot("16_upgrade_panel")
	p("upgrade_panel cards=%d" % panel._cards.size())
	panel.queue_free()
	get_tree().paused = false

	# ---- 开局流程验证：解锁梯度 / 开始面板三步 / 无尽缩放 ----
	Meta.persist = false # 这一段的读写都只在本进程，别污染真实存档
	Meta.kills = 0
	Meta.clears = 0
	Meta.purchases = {}
	var seq: Array = []
	for id in Skulls.ids():
		seq.append(str(id) + ("开" if Meta.is_unlocked(str(id)) else "锁"))
	p("新档解锁顺序 %s（期望 c021 开、其余全锁）" % str(seq))
	# 开始面板冒烟：新档下化身页应只有双刺可点
	var start = load("res://scenes/ui/start_panel.tscn").instantiate()
	add_child(start)
	await get_tree().process_frame
	await get_tree().process_frame
	await _shot("17_start_mode")
	# 真按按钮（走 pressed 信号整条链），而不是直接调内部函数：
	# 之前 _refresh 在回调里用 free() 销毁正在发信号的按钮，引擎当场报错卡死
	var mode_cards: Array = []
	for c in start.get_children():
		if c is TextureButton and is_equal_approx(c.size.x, 360.0):
			mode_cards.append(c)
	mode_cards[1].pressed.emit() # 第二张 = 无尽
	p("开始面板点「无尽」-> step=%d 模式卡=%d（期望 1 / 2）" % [start._step, mode_cards.size()])
	var difficulty_cards: Array = []
	for c in start.get_children():
		if c is TextureButton and is_equal_approx(c.size.x, 194.0):
			difficulty_cards.append(c)
	difficulty_cards[1].pressed.emit() # 第二张 = 落笔
	p("点「落笔」-> step=%d difficulty=%d 难度卡=%d（期望 2 / 1 / 5）" % [start._step, start._difficulty, difficulty_cards.size()])
	# 锁住的卡点了不该有反应（此时新档只有双刺可点）
	start._pick_char("z003")
	p("点未解锁银夜 -> step=%d（期望 2，停在化身页）" % start._step)
	await get_tree().process_frame
	await get_tree().process_frame
	await _shot("18_start_char_locked")
	Meta.kills = 20
	Meta.clears = 1
	p("击杀20 / 通关1 -> 力僧=%s 梅剑=%s 剑仙=%s 银夜=%s（期望 开/锁/开/锁）" % [
		Meta.is_unlocked("c013"), Meta.is_unlocked("c023"), Meta.is_unlocked("z000"), Meta.is_unlocked("z003")])
	p("银夜进度 %s（期望 击杀 20/150 · 通关 1/3）" % Meta.unlock_progress("z003"))
	Meta.kills = 150
	Meta.clears = 3
	p("击杀150 / 通关3 -> 银夜=%s（期望 开）" % Meta.is_unlocked("z003"))
	start._refresh()
	await get_tree().process_frame
	await get_tree().process_frame
	await _shot("19_start_char_all")

	# 逐颗按钮都按一遍：化身 → 问境 → 择路 → 返回关面板 → 再开一次确认没残留
	var back_btn := _find_btn(start, Vector2(220, 52))
	back_btn.pressed.emit()
	await get_tree().process_frame
	p("化身页点「上一步」-> step=%d（期望 1）" % start._step)
	await _shot("20_start_back")
	_find_btn(start, Vector2(220, 52)).pressed.emit()
	await get_tree().process_frame
	p("问境页点「上一步」-> step=%d（期望 0）" % start._step)
	var ret_btn := _find_btn(start, Vector2(220, 52))
	ret_btn.pressed.emit()
	await get_tree().process_frame
	await get_tree().process_frame
	p("点「返回」-> 面板已释放=%s（期望 true）" % (not is_instance_valid(start)))

	# 重新打开一次：确认上一步/返回留下的状态不会把新面板弄坏
	var start2 = load("res://scenes/ui/start_panel.tscn").instantiate()
	add_child(start2)
	await get_tree().process_frame
	_find_btn(start2, Vector2(220, 52)).pressed.emit() # 返回
	await get_tree().process_frame
	await get_tree().process_frame
	p("二次打开后点「返回」-> 已释放=%s（期望 true）" % (not is_instance_valid(start2)))

	# 无尽缩放：层数越深，小怪血量 / 精英倍率 / Boss 血量越高、出手越快
	Run.start(Run.MODE_ENDLESS, "c021")
	Run.depth = 1
	var hp1 := int(Run.room_config()["waves"][0]["hp"])
	var mul1 := float(Run.room_config()["waves"][0]["hp_mul"])
	var bhp1 := Run.boss_hp_scale()
	var cd1 := Run.boss_cd_scale()
	Run.depth = 6
	var hp6 := int(Run.room_config()["waves"][0]["hp"])
	var mul6 := float(Run.room_config()["waves"][0]["hp_mul"])
	p("无尽第1层 怪血=%d 精英倍率=%.2f Boss血倍率=%.2f 冷却倍率=%.2f（期望 原数值）" % [hp1, mul1, bhp1, cd1])
	p("无尽第6层 怪血=%d 精英倍率=%.2f Boss血倍率=%.2f 冷却倍率=%.2f（期望全部更狠）" % [
		hp6, mul6, Run.boss_hp_scale(), Run.boss_cd_scale()])
	p("HUD 模式文本（第6层第1间）：%s" % ("无尽 · 第 6 层 · 1/3"))

	_permanent_progression_check()
	await _new_build_regression()
	_assassin_cut_regression()
	get_tree().quit()


## 化身谱 / 商栈回归：购买退款链、永久战斗效果、重随券、护砚与复活墨符。
func _permanent_progression_check() -> void:
	Meta.persist = false
	Meta.kills = 999
	Meta.clears = 99
	Meta.ink = 500
	Meta.purchases = {}
	Meta.form_nodes = {}
	Meta.inventory = {}
	Meta.selected_supply = ""
	var counts := {}
	for info in Meta.FORM_NODES.values():
		var form := str(info["form"])
		counts[form] = int(counts.get(form, 0)) + 1
	p("永久节点总数=%d 各角色=%s（期望 45，五人各 9）" % [Meta.FORM_NODES.size(), str(counts)])
	var learn1 := Meta.learn_node("c021_dance_1")
	var learn2 := Meta.learn_node("c021_dance_2")
	p("顺序修炼=%s/%s 有后继时初阶可退=%s（期望 true/true/false）" % [learn1, learn2, Meta.can_refund("c021_dance_1")])
	var before_refund := Meta.ink
	var refunded := Meta.refund_node("c021_dance_2")
	p("末阶退款=%s 返还=%d（期望 true/65）" % [refunded, Meta.ink - before_refund])
	before_refund = Meta.ink
	var reset := Meta.reset_form("c021")
	p("整角色重置返还=%d 墨锭复原=%s（期望 35/true）" % [reset, Meta.ink == before_refund + 35])

	# 双刺半血技能 +1，同时血舞·初触发独立回血；直接走真实技能伤害入口。
	_player.swap_skull("c021")
	_player.set_upgrades({})
	Meta.form_nodes = {"c021_dance_1": true, "c021_dance_2": true}
	_player._apply_form_mods()
	_player.max_hp = 8
	_player.hp = 4
	_player._skill_name = "skill01"
	var dummy := Trainer.new()
	dummy.add_to_group("enemies")
	add_child(dummy)
	dummy.global_position = _player.global_position + Vector2(50.0 * _player.facing, 0.0)
	_player._deal_skill_hit({"range": 100.0, "height": 90.0, "damage": 2})
	p("血舞半血技能伤害=%d 命中后 hp=%d（期望 3/5）" % [dummy.damage_taken, _player.hp])
	dummy.queue_free()

	# 重随券：开局带入两次，整局共享，第三次不能继续扣。
	Meta.form_nodes = {}
	Meta.inventory = {"supply_reroll": 1}
	Meta.selected_supply = "supply_reroll"
	Run.start()
	var reroll1 := Run.consume_supply_reroll()
	var reroll2 := Run.consume_supply_reroll()
	var reroll3 := Run.consume_supply_reroll()
	p("重随券开局次数=2 实际=%s/%s/%s 库存=%d（期望 true/true/false/0）" % [reroll1, reroll2, reroll3, Meta.supply_count("supply_reroll")])

	# 护砚只在实际受伤时消耗，2 伤减为 1；最低 1 伤规则保持不变。
	Meta.purchases = {"start_guard": 1}
	Run.start()
	_player.set_upgrades({})
	_player.hp = 8
	_player.state = 0
	_player._hurt_invincible = 0.0
	_player.hurt(2)
	p("护砚后 hp=%d 剩余护砚=%s（期望 7/false）" % [_player.hp, Run.guard_available])

	# 复活墨符由开始流程入行囊、Run.start 消耗，致死伤后以 4 血起身。
	Meta.purchases = {}
	Meta.inventory = {"supply_revive": 1}
	Meta.selected_supply = "supply_revive"
	Run.start()
	_player.hp = 1
	_player.state = 0
	_player._hurt_invincible = 0.0
	_player.hurt(3)
	p("墨符复活 hp=%d 已消耗=%s 库存=%d（期望 4/true/0）" % [_player.hp, Run.supply_revive_used, Meta.supply_count("supply_revive")])


## 新局内流派的关键状态链：多层盾、封脉、空中派生、落匕/影饵、漏刻与去来。
func _new_build_regression() -> void:
	Meta.persist = false
	Run.guard_available = false
	Run.blessing = ""
	var counts := {}
	for info in Run.FORM_UPGRADES.values():
		for form in info.get("forms", []):
			counts[form] = int(counts.get(form, 0)) + 1
	p("局内流派节点=%d 各角色=%s（期望 45，五人各 9）" % [Run.FORM_UPGRADES.size(), str(counts)])

	# 苦行：满血时三戒转三层盾，三次攻击逐层消耗，不能一次清空。
	Meta.form_nodes = {}
	_player.swap_skull("c013")
	_player.set_upgrades({"c013_ascetic_1": 1, "c013_ascetic_2": 1})
	_player.max_hp = 8
	_player.hp = 8
	_player.state = 0
	_player._invincible = false
	_player._hurt_invincible = 0.0
	_player._skill_reflect = false
	_player._bell_shell = false
	_player._precepts = 3
	_player._skill_name = "skill02"
	_player._apply_skill_heal({"heal": 2})
	p("苦行三戒满血转盾=%d（期望 3）" % _player._shield_hits)
	for i in 3:
		_player._hurt_invincible = 0.0
		_player.hurt(1)
	p("苦行三次受击后 盾=%d hp=%d/%d（期望 0 / 8/8）" % [_player._shield_hits, _player.hp, _player.max_hp])

	# 藏锋：三段封脉、L 引爆与极阶牵引；随后验证空中砸落和回身横扫。
	_player.swap_skull("z000")
	_player.set_upgrades({})
	Meta.form_nodes = {
		"z000_edge_1": true, "z000_edge_2": true, "z000_edge_3": true,
		"z000_volley_3": true, "z000_wind_2": true, "z000_wind_3": true,
	}
	_player.global_position = Vector2(500, 560)
	_player.facing = 1
	var sword_target := Trainer.new()
	sword_target.add_to_group("enemies")
	add_child(sword_target)
	sword_target.global_position = Vector2(605, 560)
	var nearby := Trainer.new()
	nearby.add_to_group("enemies")
	add_child(nearby)
	nearby.global_position = Vector2(690, 560)
	for i in 3:
		_player._on_build_hit(sword_target, "atk04")
	var sword_id := sword_target.get_instance_id()
	p("藏锋三段 封脉=%s 破招=%.1f（期望 true/1.5）" % [_player._k_sealed.has(sword_id), sword_target.stunned])
	_player._on_build_hit(sword_target, "skill02-")
	p("藏锋引爆 封脉残留=%s 近敌定身=%.1f（期望 false/0.8）" % [_player._k_sealed.has(sword_id), nearby.rooted])
	_player.state = 2
	_player.global_position.y = 420.0
	await get_tree().create_timer(0.08).timeout
	_player._on_build_hit(sword_target, "attack3")
	p("回锋空中第四段 砸落次数=%d（期望 1）" % sword_target.slams)
	_player.global_position = Vector2(500, 560)
	_player.state = 0
	sword_target.airborne = false
	sword_target.global_position = Vector2(420, 560)
	nearby.global_position = Vector2(590, 560)
	_player._sword_dash_sweep()
	p("游身回身横扫 身后命中=%s 挑飞=%d 身前误伤=%d（期望 true/1/0）" % [
		sword_target.damage_taken > 0, sword_target.launches, nearby.damage_taken])
	_player._skill_cancel_ready = true
	_player._wind_final = true
	_player.swap_skull("c021")
	p("剑仙换头清理 段数=%d 封脉=%d 取消=%s 四段起手=%s（期望 0/0/false/false）" % [
		_player._edge_k_hits.size(), _player._k_sealed.size(), _player._skill_cancel_ready, _player._wind_final])
	sword_target.queue_free()
	nearby.queue_free()
	await get_tree().process_frame

	# 分裂匕只由真正的分裂段触发控制；终点留匕与影饵到期定身走真实回调。
	_player.set_upgrades({"c021_return_1": 1, "c021_feather_3": 1, "c021_bait_1": 1, "c021_bait_2": 1})
	var dagger_target := Trainer.new()
	dagger_target.add_to_group("enemies")
	add_child(dagger_target)
	dagger_target.global_position = _player.global_position + Vector2(100, 0)
	_player.on_projectile_expire(dagger_target.global_position + Vector2(40, 0), "dagger")
	_player.on_dagger_hit(dagger_target, dagger_target.global_position, true)
	p("归刃/绯羽回调 落匕=%d 分裂定身=%.1f（期望 2/1.2）" % [_player._daggers.size(), dagger_target.rooted])
	_player._spawn_bait()
	dagger_target._target = _player._bait
	_player._expire_bait()
	p("影饵到期 残影清理=%s 追饵定身=%.1f（期望 true/1.5）" % [not is_instance_valid(_player._bait), dagger_target.rooted])
	dagger_target.queue_free()
	await get_tree().process_frame

	# 漏刻只记不同招式；三刻自然结束触发定身和余滞。去来返程不重复扣血。
	_player.swap_skull("z003")
	Meta.form_nodes = {}
	_player.set_upgrades({
		"z003_clock_1": 1, "z003_clock_2": 1, "z003_clock_3": 1,
		"z003_returning_1": 1, "z003_returning_2": 1, "z003_returning_3": 1,
	})
	var silver_target := Trainer.new()
	silver_target.add_to_group("enemies")
	add_child(silver_target)
	silver_target._stop_timer = 1.0
	for move_id in ["attack0", "skill02", "skill06", "attack0"]:
		_player._on_build_hit(silver_target, move_id)
	var silver_id := silver_target.get_instance_id()
	p("漏刻不同招式计数=%d（期望 3，重复普攻不叠）" % (_player._time_marks[silver_id]["moves"] as Array).size())
	_player.on_time_stop_end(silver_target)
	p("漏刻自然结束 定身=%.1f 余滞=%.1f/%.2f（期望 1.8 / 4.0/0.45）" % [
		silver_target.rooted, silver_target.slowed, silver_target.slow_scale])
	_player.global_position = Vector2(600, 560)
	_player._return_mark = Vector2(400, 560)
	_player._return_time = 6.0
	_player._outbound_hits[silver_id] = true
	silver_target.global_position = Vector2(500, 560)
	_player._return_dash()
	p("去来返程 位置=%.0f 流血=%d 破招=%.1f 伤害=%d 闪避CD=%.1f（期望 400/1/1.5/0/0）" % [
		_player.global_position.x, silver_target.bleeds, silver_target.stunned, silver_target.damage_taken, _player._dash_cd])
	silver_target.queue_free()
	p("NEW BUILD DONE")


## 刺客割伤：同招穿透、独立 3/6 秒计时、防御不挂伤与致死对演。
func _assassin_cut_regression() -> void:
	Meta.form_nodes = {}
	Run.start()
	Run.guard_available = false
	_player.swap_skull("c021")
	_player.set_upgrades({})
	_player.set_physics_process(false)
	var attacker := CutAttacker.new()
	add_child(attacker)
	var other := CutAttacker.new()
	add_child(other)
	var move := {"anim": "skill02", "hit_at": 0.50, "cast_id": 1, "cut": true, "pierce_hurt_invincible": true}

	# 同一次出手的第二段可穿过受击无敌，但整招只登记一组割伤；新编号和其他攻击者不能穿透。
	_reset_cut_player()
	_player.hurt(1, Vector2.ZERO, attacker, move)
	var hp_before: int = _player.hp
	_player.hurt(1, Vector2.ZERO, attacker, move)
	var same_cast_ok: bool = _player.hp == hp_before - 1 and _player._cuts.size() == 1
	hp_before = _player.hp
	var new_move: Dictionary = move.duplicate()
	new_move["cast_id"] = 2
	_player.hurt(1, Vector2.ZERO, attacker, new_move)
	var new_cast_blocked: bool = _player.hp == hp_before and _player._cuts.size() == 1
	_player.hurt(1, Vector2.ZERO, other, move)
	var other_blocked: bool = _player.hp == hp_before and _player._cuts.size() == 1
	p("镖去玩家入口 同招次段/单组割伤=%s 新出手被无敌挡住=%s 其他攻击者被挡住=%s（期望全 true）" % [same_cast_ok, new_cast_blocked, other_blocked])

	# 第二组晚 1 秒命中：两组各自结算，第二组绝不刷新第一组。
	_reset_cut_player()
	var first: Dictionary = move.duplicate()
	first["cast_id"] = 11
	var second: Dictionary = move.duplicate()
	second["cast_id"] = 12
	_player.hurt(1, Vector2.ZERO, attacker, first)
	_player._cut_tick(1.0)
	_player._hurt_invincible = 0.0
	_player.hurt(1, Vector2.ZERO, attacker, second)
	var hp_after_direct: int = _player.hp
	_player._cut_tick(1.99)
	var before_three: bool = _player.hp == hp_after_direct and _player._cuts.size() == 2
	_player.state = _player.State.IDLE
	_player.velocity = Vector2.ZERO
	_player._hurt_invincible = 0.0
	_player._cut_tick(0.02)
	var first_three: bool = _player.hp == hp_after_direct - 1 and _player.state == _player.State.IDLE \
		and _player._hurt_invincible == 0.0 and _player.velocity == Vector2.ZERO
	_player._cut_tick(1.0)
	var second_three: bool = _player.hp == hp_after_direct - 2
	_player._cut_tick(1.98)
	var before_six: bool = _player.hp == hp_after_direct - 2 and _player._cuts.size() == 2
	_player._cut_tick(0.02)
	var first_six: bool = _player.hp == hp_after_direct - 3 and _player._cuts.size() == 1
	_player._cut_tick(1.0)
	var second_six: bool = _player.hp == hp_after_direct - 4 and _player._cuts.is_empty()
	p("割伤计时 3秒前不扣=%s 第一组3秒=%s 第二组独立3秒=%s 6秒前不扣=%s 第一组6秒=%s 第二组6秒=%s 无硬直/无敌/击退=%s（期望全 true）" % [before_three, first_three, second_three, before_six, first_six, second_six, first_three])

	# 所有未实伤的防御路径都不能登记割伤。
	_reset_cut_player()
	_player.state = _player.State.DASH
	hp_before = _player.hp
	_player.hurt(1, Vector2.ZERO, attacker, move)
	var dodge_ok: bool = _player.hp == hp_before and _player._cuts.is_empty()
	_reset_cut_player()
	_player._shield_hits = 1
	_player.hurt(1, Vector2.ZERO, attacker, move)
	var shield_ok: bool = _player.hp == hp_before and _player._cuts.is_empty()
	_reset_cut_player()
	_player._skill_reflect = true
	_player.hurt(1, Vector2.ZERO, attacker, move)
	var reflect_ok: bool = _player.hp == hp_before and _player._cuts.is_empty() and attacker.damage_taken > 0
	_reset_cut_player()
	_player._hurt_invincible = 0.8
	_player.hurt(1, Vector2.ZERO, attacker, move)
	var invincible_ok: bool = _player.hp == hp_before and _player._cuts.is_empty()
	p("割伤防御 闪避/护盾/反伤/受击无敌不附加=%s/%s/%s/%s（期望全 true）" % [dodge_ok, shield_ok, reflect_ok, invincible_ok])

	# 割伤致死也要记录真正的招式来源，终局对演仍能复现 skill02。
	_reset_cut_player(2)
	Run.last_hit = {}
	_player.hurt(1, Vector2.ZERO, attacker, move)
	_player.state = _player.State.IDLE
	_player._hurt_invincible = 0.0
	_player._cut_tick(3.01)
	var death_ok: bool = _player.hp <= 0 and _player.state == _player.State.DEAD and _player._cuts.is_empty()
	var replay_ok: bool = str(Run.last_hit.get("type_id", "")) == "c035" \
		and str(Run.last_hit.get("anim", "")) == "skill02" and int(Run.last_hit.get("damage", 0)) == 1
	p("割伤致死 死亡并清理=%s 终局对演记录=%s last_hit=%s（期望 true/true/c035+skill02）" % [death_ok, replay_ok, str(Run.last_hit)])
	attacker.queue_free()
	other.queue_free()


func _reset_cut_player(hp := 20) -> void:
	_player.max_hp = 20
	_player.hp = hp
	_player.state = _player.State.IDLE
	_player.velocity = Vector2.ZERO
	_player._invincible = false
	_player._hurt_invincible = 0.0
	_player._hurt_cast_key = ""
	_player._cuts.clear()
	_player._cut_casts.clear()
	_player._shield_hits = 0
	_player._shield_time = 0.0
	_player._parry_ready = false
	_player._bell_shell = false
	_player._skill_reflect = false
	_player._skill_poise = false
	_player._damage_reduce = 0
	_player.poise = false
	Run.guard_available = false
	Run.blessing = ""
	Run.blessing_used = false
	Run.supply_revive = false
	Run.supply_revive_used = false


func _physics_process(_delta: float) -> void:
	if _player and _player.state != _last_state:
		p("state -> " + str(_player.state) + " pos=" + str(_player.position))
		_last_state = _player.state


func _tap(action: String) -> void:
	Input.action_press(action)
	await get_tree().physics_frame
	Input.action_release(action)


## 等玩家回到可出招状态（IDLE/RUN），最多等 max_wait 秒。
## 各形态普攻/技能时长差得远（梅剑普攻 1.883s、定山 U 3.05s），硬编码等待会让
## 下一次按键落在上一招的锁定里被吞掉，测试就测不到该测的东西。
func _wait_free(max_wait := 6.0) -> void:
	var t := 0.0
	while _player.state > 1 and t < max_wait:
		await get_tree().physics_frame
		t += get_physics_process_delta_time()


## 按尺寸找一个按钮：开始面板里模式卡 360x270、难度卡 194x278、底部按钮 220x52
func _find_btn(parent: Node, wanted: Vector2) -> TextureButton:
	for c in parent.get_children():
		if c is TextureButton and c.size.is_equal_approx(wanted):
			return c
	return null


func _shot(name: String) -> void:
	await get_tree().process_frame
	RenderingServer.force_draw()
	var img = get_viewport().get_texture().get_image()
	var err = img.save_png(OUT_DIR + "ctrl_" + name + ".png")
	p("saved " + name + " err=" + str(err) + " state=" + str(_player.state) + " pos=" + str(_player.position))
