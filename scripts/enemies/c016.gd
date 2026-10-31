extends CharacterBody2D

## 小怪通用 AI：巡逻 / 追击 / 攻击 / 受击 / 死亡
## 长什么样、出什么招、判定多长，全部来自 scripts/enemies/enemy_types.gd 的形态表。
## 主角形态不设同名敌人版本（梅剑 c023 精英已删；青笠 c012 已从玩家形态下掉，转生为精英怪）。

const Types := preload("res://scripts/enemies/enemy_types.gd")
const DAMAGE_NUMBER := preload("res://scripts/ui/damage_number.gd")
const FX := preload("res://scripts/systems/fx.gd")
const SpinePoseMixer := preload("res://scripts/systems/spine_pose_mixer.gd")
const DMG_COLOR := Color(0.66, 0.2, 0.16) # 朱砂：敌人受伤数字
const SFX_HIT_QI := preload("res://audio/sfx/hit_qi.wav")
const SFX_TELEGRAPH := preload("res://audio/sfx/telegraph.wav")

@export var type_id := "c016"

enum State { IDLE, PATROL, CHASE, ATTACK, HURT, DEAD, FLY } # FLY=被击飞/击退的浮空状态

signal died

## 全局出手令牌：同一时刻只允许一只小怪起手，其余在原地等（否则一排同时挥刀像广播体操）
static var _attacker: Node2D = null

var state: int = State.IDLE
var facing := -1
var hp: int

# ---------- 形态参数（由 enemy_types.gd 注入，别在这里手改） ----------
var max_hp := 3
var patrol_speed := 60.0
var chase_speed := 150.0
var patrol_range := 120.0 # 以出生点为中心左右巡逻
var idle_time := 1.0
var detect_range := 240.0
var lose_range := 340.0
var attack_range := 180.0 # AI 决定出手的距离（贴近到多近才起手）
var keep_dist := 95.0 # 贴得比这更近就往后退一点，几只怪不会挤成一坨
var attack_hit_height := 90.0 # 命中判定的纵向容差
var attack_cooldown := 1.8 # 两次出手间隔，别太快
var attack_lunge := 300.0 # 出手前冲，保证挥到脸上
var gravity := 2000.0
var hurt_time := 0.3

# 三档加速度（对齐玩家手感：起步渐快、急停更快、反向转向最快），替换原先硬编码的瞬时变速
var accel := 1300.0 # 启动/追击提速
var brake := 1700.0 # 制动
var turn_accel := 2100.0 # 反向转向

var _armor := 0 # 伤害低于此值不打断出手（精英霸体）
var body_radius := 30.0 # 受击半径：挨打按"攻击方射程 + 本半径"判定，体型越大越容易被够到（永久规则，见 PROGRESS 项目约束）
var _dead_min := 1.2 # 尸体最少停留时间（补死动画过短的形态）
var _telegraph_on := false
var _pick_nearest := false
var _base_scale := 0.32
var _scale := 0.32
var _anim_map: Dictionary = {}
var _attack_anims: Array = [] # 逻辑招式键；演出动画可经 move_anims 共用同一条 Spine 动画
var _move_anims: Dictionary = {}
var _attack_move := "" # 本次出手的逻辑键，判定/伤害/冷却均按它查询
var _attack_cast_id := 0 # 每次起手递增，同招多段凭它识别，不靠动画名猜测
var _ranges: Dictionary = {}
var _hit_at_map: Dictionary = {}
# both：该招是回身横扫，动画把武器甩到身后，判定不分前后（否则"动画打到却判不上"）
var _both_anims: Dictionary = {}
var _damage_map: Dictionary = {} # 每招伤害（默认 1；精英重招可写 2）
var _poise_anims: Dictionary = {} # 出手霸体：该招出手期间挨打只掉血、不断招（青笠跳斩）
var _lunge_map: Dictionary = {} # 该招前冲倍率（跳斩跨步更大）
var _hop_map: Dictionary = {} # 该招起手向上跃起的速度（跳斩腾空的视觉配合）
var _feedback_segments: Dictionary = {} # 只播受击反馈、不实际扣血的招式段（刀客前两刀）
var _blink_strike: Dictionary = {} # 追击窗口强制出招；behind=true 时瞬到目标背后
var _backstab := false # 阴影：从目标背后造成的直接伤害双倍，持续伤害不经过这里
var _hit_effects: Dictionary = {} # 实际命中后附加的招式效果（如升龙刀击飞、辟地封跳）
var _hit_knockback := Vector2(220.0, -80.0)
var _attack_chain: Dictionary = {} # 同一招内的接续动画与收招后的静默恢复
var _advance_map: Dictionary = {} # 攻击动画期间持续前进的速度
var _chase_anim_speed := 1.0
var _super_armor := false # 全程霸体；规则级 ignore_armor 与时停不受此影响
var _attack_rules: Dictionary = {} # 特殊招式的独立冷却、触发窗口与随机权重
var _attack_rule_cds: Dictionary = {}
var _knock_at := 999 # 高伤倒地阈值；未配置时保持原受击逻辑
var _knock_chain: Array = [] # 高伤倒地动画链
var _hurt_chain: Array = [] # 当前尚未播完的倒地链
var _hurt_chain_active := false # 链中照常吃伤害，但受击动画不得重入
var _regen_interval := 0.0 # 山民被动：回血间隔，0=无被动
var _regen_amount := 0
var _regen_timer := 0.0
# 半血狂暴：血量跌破 below 比例时触发一次——出手冷却 ×cd、追击速度 ×speed
var _enrage_below := 0.0
var _enrage_cd := 0.65
var _enrage_speed := 1.2
var _enraged := false
var _elite := false # 精英标记（时停分档用：杂兵 3s / 精英 2s / Boss 1s）
var _stop_timer := 0.0 # 时间暂停（银夜 U）剩余
var _slow_timer := 0.0 # 余滞剩余：时停期间冻结，其余状态照常计时
var _slow_scale := 1.0 # 余滞横向速度倍率：只缩放移动目标，不改形态参数
# ---------- 定身 / 流血（双刺 L/U 的机制接口，Boss 继承后按体型覆盖） ----------
var _root_timer := 0.0 # 定身剩余：不能移动，但可以照常出手
var _stun_timer := 0.0 # 晕眩剩余：不能移动、也不能出手（力僧 L）
var _bleed_stacks := 0 # 流血层数：每层每秒扣 1 血
var _bleed_time := 0.0 # 流血剩余时间（再次命中会刷新）
var _bleed_acc := 0.0 # 流血的计时累计
const BLEED_MAX := 5 # 流血最多叠 5 层
const BLEED_DUR := 5.0 # 每次命中刷新到 5 秒
var _poison_time := 0.0 # 中毒剩余时间（梅剑 K 尾端甩鞭）
var _poison_acc := 0.0 # 中毒的计时累计
const POISON_TICK := 0.5 # 每 0.5 秒扣一次
const POISON_DMG := 1 # 每次扣 1 点
const POISON_COLOR := Color(0.36, 0.6, 0.32) # 竹青：中毒飘字与掉血数字
const POISON_LABEL_COLOR := Color(0.45, 0.7, 0.4)
var _fly_impact := 0 # 击退（银夜 L）撞人/撞墙的组合伤害，0=纯击飞无碰撞伤害
var _fly_hit := {} # 本次击退已撞过的同伴（一只只撞一次）
var _slam_pending := false # 仅 slam 的落地待回报；普通击飞/击退必须清除
var _bar_w := 44.0
var _bar_y := -120.0
var _number_y := -105.0

var _home_x := 0.0
var _patrol_dir := 1
var _idle_timer := 0.0
var _attack_cd := 0.0
var _attack_timer := 0.0
var _attack_dur := 0.0 # 本次出手动画的真实时长
var _chain_next := "" # 当前攻击段播完后必须接续的动画
var _recovery_after_attack := 0.0 # 连段末播完后进入静默力竭的时长
var _recovery_timer := 0.0 # 力竭期间不移动、不出手，也不生成控制提示
# 本次出手尚未结算的命中段：{t=倒计时阈值, i=段序号}，按阈值从大到小弹出。
# hit_at 标定的是"动画开始后多少秒"，倒计时阈值 = 时长 - hit_at；支持单段（float）与多段（Array）
var _attack_hits_left: Array = []
var _anim_durations := {} # 动画名 -> 时长，setup 时缓存
var _idle_queued := false # stand 已排队在技能后面，切 IDLE 时别重复 set
var _chase_block := 0.0 # 收招后的收势时间：这期间不许起跑，等 stand 队列接续完
var _hurt_timer := 0.0
var _target: Node2D
var _ghosts: Dictionary = {} # 已互相关闭碰撞的同伴（对穿状态）

var sprite: Node2D # SpineSprite
var _anim_state
var _pose_mixer = null # 刀客：手动同帧更新并补齐缺 key 骨骼的视觉混合
var _pending_anim := ""
var _pending_loop := false
var _pending_speed := 1.0
var _pending_queue: Array = []
var _current_anim := "" # 防同名循环动画重放抽搐
var _current_anim_speed := 1.0
var _hp_bar: Node2D
var _hp_fill: ColorRect
var _sfx_player: AudioStreamPlayer


func _ready() -> void:
	add_to_group("enemies")
	_apply_type()
	hp = max_hp
	_regen_timer = _regen_interval
	_home_x = global_position.x
	_idle_timer = idle_time
	_setup_spine()
	_make_hp_bar()
	_sfx_player = AudioStreamPlayer.new()
	add_child(_sfx_player)


## 把形态表装到实例上
func _apply_type() -> void:
	var t: Dictionary = Types.get_type(type_id)
	type_id = type_id if Types.TYPES.has(type_id) else Types.DEFAULT_ID
	_base_scale = float(t["scale"])
	_scale = _base_scale
	_anim_map = t["anim"]
	_attack_anims = t["attacks"]
	_move_anims = t.get("move_anims", {})
	_ranges = t["ranges"]
	_hit_at_map = t["hit_at"]
	_both_anims = t.get("both", {})
	_damage_map = t.get("damage", {})
	_poise_anims = t.get("poise_atk", {})
	_lunge_map = t.get("lunge_mul", {})
	_hop_map = t.get("hop", {})
	_feedback_segments = t.get("feedback_only", {})
	_blink_strike = t.get("blink_strike", {})
	_backstab = bool(t.get("backstab", false))
	_hit_effects = t.get("hit_effects", {})
	_hit_knockback = t.get("hit_knockback", Vector2(220.0, -80.0))
	_attack_chain = t.get("attack_chain", {})
	_advance_map = t.get("advance", {})
	_chase_anim_speed = float(t.get("chase_anim_speed", 1.0))
	_super_armor = bool(t.get("super_armor", false))
	_attack_rules = t.get("attack_rules", {})
	_attack_rule_cds.clear()
	for anim in _attack_rules:
		_attack_rule_cds[anim] = 0.0
	_knock_at = int(t.get("knock_at", 999))
	_knock_chain = (t.get("knock_chain", []) as Array).duplicate()
	var regen: Dictionary = t.get("regen", {})
	_regen_interval = float(regen.get("interval", 0.0))
	_regen_amount = int(regen.get("amount", 0))
	var en: Dictionary = t.get("enrage", {})
	_enrage_below = float(en.get("below", 0.0))
	_enrage_cd = float(en.get("cd", 0.65))
	_enrage_speed = float(en.get("speed", 1.2))
	max_hp = int(t["hp"])
	patrol_speed = float(t["patrol_speed"])
	chase_speed = float(t["chase_speed"])
	patrol_range = float(t["patrol_range"])
	idle_time = float(t["idle_time"])
	detect_range = float(t["detect_range"])
	lose_range = float(t["lose_range"])
	attack_range = float(t["attack_range"])
	keep_dist = float(t["keep_dist"])
	attack_cooldown = float(t["attack_cooldown"])
	attack_lunge = float(t["attack_lunge"])
	attack_hit_height = float(t["hit_height"])
	hurt_time = float(t["hurt_time"])
	_armor = int(t["armor"])
	_elite = bool(t.get("elite", false))
	body_radius = float(t.get("body_radius", 30.0))
	_telegraph_on = bool(t["telegraph"])
	_pick_nearest = str(t["pick"]) == "nearest"
	_dead_min = float(t["dead_min"])
	_bar_w = float(t["bar_w"])
	_bar_y = float(t["bar_y"])
	_number_y = float(t["number_y"])


## 刷怪器在 add_child 之后调用：按波次覆盖血量 / 速度 / 节奏，形态本身不动
func configure(cfg: Dictionary) -> void:
	if cfg.has("hp"):
		max_hp = int(cfg["hp"])
	# 倍率血量：精英不填绝对血量，按形态表基础值乘倍率（无尽模式逐层变厚）
	if cfg.has("hp_mul"):
		max_hp = maxi(1, int(round(float(max_hp) * float(cfg["hp_mul"]))))
	if cfg.has("speed"):
		var m := float(cfg["speed"])
		patrol_speed *= m
		chase_speed *= m
	if cfg.has("attack_range"):
		attack_range = float(cfg["attack_range"])
	if cfg.has("keep_dist"):
		keep_dist = float(cfg["keep_dist"])
	if cfg.has("attack_cooldown"):
		attack_cooldown = float(cfg["attack_cooldown"])
	hp = max_hp
	_update_hp_bar()


func _make_hp_bar() -> void:
	_hp_bar = Node2D.new()
	_hp_bar.position = Vector2(-_bar_w * 0.5, _bar_y)
	var bgc := ColorRect.new()
	bgc.size = Vector2(_bar_w, 6)
	bgc.color = Color(0.05, 0.05, 0.05, 0.7)
	_hp_fill = ColorRect.new()
	_hp_fill.position = Vector2(1, 1)
	_hp_fill.size = Vector2(_bar_w - 2.0, 4)
	_hp_fill.color = DMG_COLOR
	_hp_bar.add_child(bgc)
	_hp_bar.add_child(_hp_fill)
	_hp_bar.visible = false
	add_child(_hp_bar)


func _update_hp_bar() -> void:
	if _hp_bar == null:
		return
	_hp_bar.visible = hp < max_hp and state != State.DEAD
	_hp_fill.size.x = (_bar_w - 2.0) * clampf(float(hp) / float(max_hp), 0.0, 1.0)


func _setup_spine() -> void:
	var data = load(str(Types.get_type(type_id)["data"]))
	if data == null or not data.call("is_skeleton_data_loaded"):
		push_error("Enemy: 骨架数据加载失败 " + type_id)
		return
	sprite = ClassDB.instantiate("SpineSprite")
	add_child(sprite)
	sprite.set("skeleton_data_res", data)
	# 刀客由 SpinePoseMixer 独立混合；原生混合会在旧轨道销毁时再次写入缺 key 骨骼。
	data.call("set_default_mix", 0.0 if type_id == "c016" else 0.2)
	sprite.scale = Vector2(_scale * facing, _scale)
	_anim_state = sprite.call("get_animation_state")
	if type_id == "c016":
		_pose_mixer = SpinePoseMixer.new(sprite)
	# 缓存攻击动画真实时长：比想象中长得多，攻击锁定必须按实际时长走，
	# 否则收招段被切掉 + 0.1s 交叉淡化 = 抽搐
	for n in _attack_anims:
		var a = data.call("find_animation", str(_move_anims.get(n, n)))
		if a != null:
			_anim_durations[n] = a.call("get_duration")
	# 倒地链也按真实时长逐段接续，不能拿固定 hurt_time 截断起身。
	for n in _knock_chain:
		var a = data.call("find_animation", n)
		if a != null:
			_anim_durations[n] = a.call("get_duration")
	# 死亡动画时长也要缓存：尸体清理要等它播完
	var da = data.call("find_animation", str(_anim_map["dead"]))
	if da != null:
		_anim_durations[str(_anim_map["dead"])] = da.call("get_duration")
	_play(str(_anim_map["idle"]), true)


func _process(delta: float) -> void:
	if _pose_mixer == null or _anim_state == null:
		return
	var step := 0.0 if _stop_timer > 0.0 else delta
	if not _pending_anim.is_empty():
		var entry = _anim_state.call("set_animation", _pending_anim, _pending_loop, 0)
		if _pending_speed != 1.0 and entry != null and entry.has_method("set_time_scale"):
			entry.call("set_time_scale", _pending_speed)
		for queued in _pending_queue:
			_anim_state.call("add_animation", queued["anim"], 0.0, queued["loop"], 0)
		_pending_anim = ""
		_pending_queue.clear()
		step = 0.0 # 新轨道先应用，再恢复旧姿势；不把未补偿的第 0 帧送去渲染
	_pose_mixer.update(step)


func _physics_process(delta: float) -> void:
	if state == State.DEAD:
		return
	# 时间暂停（银夜 U）：彻底定住——不走 AI、不吃重力、动画冻结，到点恢复
	if _stop_timer > 0.0:
		_stop_timer -= delta
		if _stop_timer <= 0.0:
			_end_stop(true)
		return
	if _slow_timer > 0.0:
		_slow_timer = maxf(0.0, _slow_timer - delta)
		if _slow_timer <= 0.0:
			_slow_scale = 1.0
	_attack_cd = maxf(0.0, _attack_cd - delta)
	for anim in _attack_rule_cds:
		_attack_rule_cds[anim] = maxf(0.0, float(_attack_rule_cds[anim]) - delta)
	_chase_block = maxf(0.0, _chase_block - delta)
	_find_target()
	_bleed_tick(delta) # 流血照常跳（时停里不动，所以放在 stop 分支之后）
	_poison_tick(delta) # 中毒同理：时停期间不跳毒
	_regen_tick(delta) # 山民：时停冻结，其他状态照常计时

	# 晕眩（力僧 L）：比定身更强——站桩发愣，不出手也不移动（放在定身之前结算）
	if _stun_timer > 0.0:
		_stun_tick(delta)
		_update_peer_ghosts()
		velocity.y = minf(velocity.y + gravity * delta, 900.0)
		move_and_slide()
		return

	# 定身（双刺 U）：只锁移动，不锁出手——站桩期间贴脸照样能挥刀
	if _root_timer > 0.0:
		_root_tick(delta)
		_update_peer_ghosts()
		velocity.y = minf(velocity.y + gravity * delta, 900.0)
		move_and_slide()
		return

	# 连段末尾的力竭是招式自身恢复段：静默站桩，不移动、不再出手，也不显示控制文字。
	if _recovery_timer > 0.0:
		_recovery_timer = maxf(0.0, _recovery_timer - delta)
		velocity.x = move_toward(velocity.x, 0.0, brake * delta)
		_play(str(_anim_map["idle"]), true)
		velocity.y = minf(velocity.y + gravity * delta, 900.0)
		move_and_slide()
		return

	match state:
		State.IDLE:
			_idle_tick(delta)
		State.PATROL:
			_patrol_tick(delta)
		State.CHASE:
			_chase_tick(delta)
		State.ATTACK:
			_attack_tick(delta)
		State.HURT:
			_hurt_tick(delta)
		State.FLY:
			_fly_tick(delta)

	# 同伴分离力：同一水平线上靠太近就互相推开，避免几只怪叠成一团互相卡位
	if state != State.ATTACK and state != State.FLY:
		velocity.x += _separation_push() * 900.0 * delta

	_update_peer_ghosts()
	velocity.y = minf(velocity.y + gravity * delta, 900.0)
	move_and_slide()


# ---------- 状态逻辑 ----------

func _idle_tick(delta: float) -> void:
	velocity.x = move_toward(velocity.x, 0.0, brake * delta)
	_idle_timer -= delta
	if _chase_block <= 0.0 and _sees_player(detect_range):
		_set_state(State.CHASE)
	elif _idle_timer <= 0.0:
		_set_state(State.PATROL)


func _patrol_tick(delta: float) -> void:
	if _sees_player(detect_range):
		_set_state(State.CHASE)
		return
	if global_position.x > _home_x + patrol_range:
		_patrol_dir = -1
	elif global_position.x < _home_x - patrol_range:
		_patrol_dir = 1
	facing = _patrol_dir
	_apply_facing()
	velocity.x = move_toward(velocity.x, _patrol_dir * patrol_speed * _slow_scale, accel * delta)


func _chase_tick(delta: float) -> void:
	if _target == null or not is_instance_valid(_target):
		_set_state(State.PATROL)
		return
	var dx: float = _target.global_position.x - global_position.x
	var dy: float = absf(_target.global_position.y - global_position.y)
	var max_range := 520.0 if _target.is_in_group("player_decoy") else lose_range
	if absf(dx) > max_range:
		_target = null
		_set_state(State.PATROL)
		return
	facing = 1 if dx > 0.0 else -1
	_apply_facing()
	# 升龙刀有独立追击窗口与冷却：中距离直接贴身，但完整保留动画前摇供玩家闪避。
	if not _blink_strike.is_empty() and _attack_cd <= 0.0 and _can_attack() and dy <= 60.0:
		var blink_min := float(_blink_strike.get("min", 0.0))
		var blink_max := float(_blink_strike.get("max", attack_range))
		var blink_anim := str(_blink_strike.get("anim", ""))
		if absf(dx) >= blink_min and absf(dx) <= blink_max and _rule_allows(blink_anim, absf(dx)):
			_start_attack(blink_anim)
			return
	# 中远距招式只在各自窗口内主动触发，不进近身随机池。
	if _attack_cd <= 0.0 and _can_attack() and dy <= 60.0:
		for n in _attack_anims:
			var rule: Dictionary = _attack_rules.get(n, {})
			if str(rule.get("trigger", "")) == "distance" and _rule_allows(str(n), absf(dx)):
				_start_attack(str(n))
				return
	if absf(dx) <= attack_range and dy <= 60.0 and _attack_cd <= 0.0 and _can_attack():
		_start_attack()
		return
	# 贴太近但还在冷却：先退开一点保持站位，别和同伴挤在同一格
	if absf(dx) < keep_dist and _attack_cd > 0.0:
		velocity.x = move_toward(velocity.x, -facing * 80.0 * _slow_scale, accel * delta)
		return
	var acc := turn_accel if signf(velocity.x) != 0.0 and signf(velocity.x) != signf(dx) else accel
	velocity.x = move_toward(velocity.x, facing * chase_speed * _slow_scale, acc * delta)


func _attack_tick(delta: float) -> void:
	_attack_timer -= delta
	var advance := float(_advance_map.get(_attack_move, 0.0))
	if advance > 0.0:
		velocity.x = move_toward(velocity.x, facing * advance * _slow_scale, accel * delta)
	else:
		# lunge 用半速制动带惯性；持续前进的攻击段则保持自己的慢步节奏。
		velocity.x = move_toward(velocity.x, 0.0, brake * 0.5 * delta)
	# 多段命中：到一段弹一段（倒计时阈值大的先弹，即动画里先打出去的那段）
	while not _attack_hits_left.is_empty() and _attack_timer <= float(_attack_hits_left[0]["t"]):
		var seg: Dictionary = _attack_hits_left.pop_front()
		_deal_hit(int(seg["i"]))
	# 收招按真实时长驱动；有后续段时仍属同一次攻击，不交令牌、不进入普通收招。
	if _attack_timer <= 0.0:
		if not _chain_next.is_empty():
			var chain: Dictionary = _attack_chain.get(_attack_move, {})
			var next_anim := _chain_next
			_recovery_after_attack = float(chain.get("recovery", 0.0))
			_start_attack(next_anim, true)
			return
		_attack_cd = attack_cooldown
		_chase_block = 0.35
		_release_token()
		if _recovery_after_attack > 0.0:
			_recovery_timer = _recovery_after_attack
			_recovery_after_attack = 0.0
			velocity.x = 0.0
		_set_state(State.IDLE)


func _hurt_tick(delta: float) -> void:
	_hurt_timer -= delta
	velocity.x = move_toward(velocity.x, 0.0, brake * delta)
	if _hurt_chain_active:
		if _hurt_timer <= 0.0:
			_advance_hurt_chain()
		return
	if _hurt_timer <= 0.0:
		_set_state(State.CHASE if _target != null else State.IDLE)


## 高伤倒地链：每段都播满真实时长；链中再次受伤只掉血/白闪，不从这里重入。
func _start_hurt_chain(dir: float) -> void:
	state = State.HURT
	_hurt_chain_active = true
	_hurt_chain = _knock_chain.duplicate()
	_idle_queued = false
	velocity = Vector2(dir * 200.0, -70.0)
	_hurt_timer = 0.0
	_advance_hurt_chain()


func _advance_hurt_chain() -> void:
	if _hurt_chain.is_empty():
		_hurt_chain_active = false
		_hurt_timer = 0.0
		_set_state(State.CHASE if _target != null else State.IDLE)
		return
	var anim := str(_hurt_chain.pop_front())
	_hurt_timer = maxf(0.05, float(_anim_durations.get(anim, hurt_time)))
	_play(anim, false)
	if _hurt_chain.is_empty():
		# 起身后直接接待机，避免最后一帧落回 setup pose 造成瞬时抽搐。
		_queue(str(_anim_map["idle"]), true)
		_idle_queued = true


# ---------- 动作 ----------

func _rule_allows(anim: String, dist: float) -> bool:
	var rule: Dictionary = _attack_rules.get(anim, {})
	if float(_attack_rule_cds.get(anim, 0.0)) > 0.0:
		return false
	return dist >= float(rule.get("min", 0.0)) and dist <= float(rule.get("max", INF))


func _start_attack(forced_anim := "", continue_chain := false) -> void:
	if not continue_chain:
		_chain_next = ""
		_recovery_after_attack = 0.0
		_recovery_timer = 0.0
	# 按当前距离、独立冷却与权重挑招式；未配置规则的敌人保持原有随机/最近逻辑。
	var dist := 0.0
	if _target != null:
		dist = absf(_target.global_position.x - global_position.x)
	var pool: Array = []
	var weights: Array = []
	var total_weight := 0.0
	for n in _attack_anims:
		var rule: Dictionary = _attack_rules.get(n, {})
		if not bool(rule.get("random", true)) or not _rule_allows(str(n), dist):
			continue
		if _range_of(n, 0) >= dist - 10.0:
			pool.append(n)
			var weight := float(rule.get("weight", 1.0))
			weights.append(weight)
			total_weight += weight
	var anim := forced_anim
	if anim == "" and pool.is_empty():
		if not _attack_rules.is_empty():
			return # 特殊招全在冷却或不在窗口时继续贴近，不拿远招违规兜底
		# 所有招都够不着：用最远那招（至少方向对、范围最大）
		var far_r := -1.0
		for n in _attack_anims:
			var fr := _range_of(n, 0)
			if fr > far_r:
				far_r = fr
				anim = str(n)
	elif anim == "" and _pick_nearest:
		# 精英：挑"刚好够得着"的最近一招，近身不会甩 580px 的大招
		var best_r := INF
		for n in pool:
			var br := _range_of(n, 0)
			if br < best_r:
				best_r = br
				anim = str(n)
	elif anim == "":
		var roll := randf() * total_weight
		for i in pool.size():
			roll -= float(weights[i])
			if roll <= 0.0:
				anim = str(pool[i])
				break
		if anim == "":
			anim = str(pool.back())
	state = State.ATTACK
	_attacker = self # 占住出手令牌
	_attack_move = anim
	_attack_cast_id += 1
	var chain: Dictionary = _attack_chain.get(anim, {})
	_chain_next = str(chain.get("anim", ""))
	if _attack_rules.has(anim):
		_attack_rule_cds[anim] = float((_attack_rules[anim] as Dictionary).get("cooldown", 0.0))
	# 追击招只能由窗口强制选出；behind=true 时落到目标背后，并立即回身面向目标。
	if forced_anim != "" and not _blink_strike.is_empty() and anim == str(_blink_strike.get("anim", "")) \
			and _target != null and is_instance_valid(_target):
		var dx: float = _target.global_position.x - global_position.x
		var offset := float(_blink_strike.get("offset", 72.0))
		if bool(_blink_strike.get("behind", false)):
			var raw_facing = _target.get("facing")
			var target_facing := float(raw_facing) if raw_facing != null and float(raw_facing) != 0.0 else (1.0 if dx > 0.0 else -1.0)
			global_position.x = _target.global_position.x - target_facing * offset
			facing = 1 if target_facing > 0.0 else -1
		else:
			facing = 1 if dx > 0.0 else -1
			if offset > 0.0:
				global_position.x = _target.global_position.x - facing * offset
		_apply_facing()
	_attack_dur = _anim_durations.get(anim, 1.5)
	_attack_timer = _attack_dur
	# hit_at 由 range_probe 标定的是骨架伸展峰值时刻（武器最远端 = 动画打到人的那一帧），
	# 直接用该时刻结算：早一帧是"未打到先判定"，晚一帧是"打到却没判定"，都不贴动画。
	# 值可以是单段（float）或多段（Array，如青笠两连击）；统一转成倒计时阈值队列
	_attack_hits_left.clear()
	var ha = _hit_at_map.get(anim, 0.9)
	var ha_list: Array = ha if ha is Array else [ha]
	for i in ha_list.size():
		_attack_hits_left.append({"t": _attack_dur - float(ha_list[i]), "i": i})
	_attack_hits_left.sort_custom(func(a, b): return float(a["t"]) > float(b["t"]))
	velocity.x = facing * attack_lunge * float(_lunge_map.get(anim, 1.0)) * _slow_scale # 出手带一段前冲
	var hop := float(_hop_map.get(anim, 0.0))
	if hop > 0.0:
		velocity.y = -hop # 跳斩腾空：配合动画的跃起视觉，重力会自然把他带回地面
	_play(str(_move_anims.get(anim, anim)), false) # 逻辑招式与真实演出分开记录
	# 关键：排队 stand 紧跟技能之后。否则非循环动画播完的瞬间轨道空窗，
	# 骨架会闪回一帧 setup pose 再被 set_animation 接走 = 收招时"闪现一下"。
	_queue(str(_anim_map["idle"]), true)
	_idle_queued = true
	if _telegraph_on:
		_telegraph()


## 精英出手预警：起手瞬间整只怪泛红 + 脚下聚气，给玩家留出躲闪/弹反的读招时间
func _telegraph() -> void:
	if sprite == null:
		return
	_sfx_player.stream = SFX_TELEGRAPH
	_sfx_player.play()
	sprite.modulate = Color(1.9, 0.5, 0.45)
	var tw := create_tween()
	tw.tween_property(sprite, "modulate", Color.WHITE, 0.2) # 0.35 → 0.2：预警闪一下就退，不盖过后续命中反馈
	# 脚下墨环（泛红）：体积跟随形态缩放，精英一小圈、Boss 一大圈
	FX.spawn(get_tree().current_scene, "telegraph", global_position, {"scale": _scale * 1.1, "mod": Color(1.0, 0.55, 0.5, 0.9)})


func _deal_hit(seg := 0) -> void:
	if _target == null or not is_instance_valid(_target):
		return
	var dx: float = _target.global_position.x - global_position.x
	var dy: float = absf(_target.global_position.y - global_position.y)
	var rng := _range_of(_attack_move, seg)
	var move := _replay_move(seg)
	# 纯反馈段不能走 Run.enemy_damage：该入口会把 0 也抬成最低 1 伤。
	var dmg := 0 if bool(move.get("feedback_only", false)) else Run.enemy_damage(int(_damage_map.get(_attack_move, 1)))
	# 阴影只放大本次直接命中；割伤在玩家侧独立计时，绝不回到这里二次暴击。
	if dmg > 0 and _backstab:
		var raw_facing = _target.get("facing")
		if raw_facing != null and (global_position.x - _target.global_position.x) * float(raw_facing) < 0.0:
			dmg *= 2
	var in_front := dx == 0.0 or (dx > 0.0) == (facing > 0)
	var side_ok: bool = in_front or bool(_both_anims.get(_attack_move, false))
	if side_ok and absf(dx) <= rng + _radius_of(_target) and dy <= attack_hit_height \
			and _target.has_method("hurt"):
		var kb := Vector2(facing * _hit_knockback.x, _hit_knockback.y)
		_target.call("hurt", dmg, kb, self, move)


## 把本次真实招式与命中段交给玩家记录，结算可按同一时刻重演最后一击。
func _replay_move(seg: int) -> Dictionary:
	var at = _hit_at_map.get(_attack_move, 0.8)
	if at is Array:
		at = at[mini(seg, (at as Array).size() - 1)]
	var move := {"anim": _current_anim, "hit_at": float(at), "cast_id": _attack_cast_id}
	var feedback: Array = _feedback_segments.get(_attack_move, [])
	if feedback.has(seg):
		move["feedback_only"] = true
	var effects: Dictionary = _hit_effects.get(_attack_move, {})
	for key in effects:
		move[key] = effects[key]
	return move


## 目标的受击半径：体型越大挨打面越大；没有该属性的测试替身按 30 兜底
func _radius_of(t) -> float:
	var r = t.get("body_radius")
	return float(r) if r != null else 30.0


## 该招第 seg 段的判定范围：ranges 值可以是单段（float）或多段（Array，与 hit_at 一一对应）
func _range_of(anim: String, seg: int) -> float:
	var r = _ranges.get(anim, attack_range)
	if r is Array:
		return float(r[mini(seg, (r as Array).size() - 1)])
	return float(r)


# ---------- 银夜机制接口：击飞 / 击退 / 时间暂停 ----------

## 时间暂停分档：杂兵 mob / 精英 elite；Boss 在 boss.gd 覆盖为 boss
func stop_tier() -> String:
	return "elite" if _elite else "mob"


## 时间暂停（银夜 U）：定住 dur 秒。无视霸体与出手霸体——前摇一律打断，
## 动画整只冻结（停掉 SpineSprite 的逐帧推进，视觉上就是定格），期间挨打照掉血但不断定身
func time_stop(dur: float) -> void:
	if state == State.DEAD:
		return
	_release_token() # 令牌必须交还，否则定身结束后别的怪永远等不到出手
	if state == State.ATTACK or state == State.FLY:
		# 打断前摇/浮空：定身结束从站立重新组织进攻
		_clear_attack_chain()
		_attack_hits_left.clear()
		state = State.IDLE
		velocity = Vector2.ZERO
		_idle_queued = false
		_play(str(_anim_map["idle"]), true)
	_stop_timer = dur
	if sprite != null:
		sprite.process_mode = Node.PROCESS_MODE_DISABLED # 冻结动画推进


func _end_stop(natural := false) -> void:
	var was_stopped := _stop_timer > 0.0
	_stop_timer = 0.0
	if sprite != null and is_instance_valid(sprite):
		sprite.process_mode = Node.PROCESS_MODE_INHERIT
	if natural and was_stopped:
		var pl = get_tree().get_first_node_in_group("player")
		if pl != null and pl.has_method("on_time_stop_end"):
			pl.call("on_time_stop_end", self)


# ---------- 双刺机制接口：定身 / 流血 ----------

## 定身（双刺 U 掷匕）：dur 秒内不能移动，但可以照常出手攻击。
## 打断巡逻/追击移动，已在挥的招照打完（不可以攻击的控制要另开接口，别混用）
func root(dur: float, _ignore_armor := false) -> void:
	if state == State.DEAD or dur <= 0.0 or (_super_armor and not _ignore_armor):
		return
	_root_timer = maxf(_root_timer, dur)
	_flash()
	var dn := DAMAGE_NUMBER.new()
	dn.setup("定身", Color(0.9, 0.75, 0.3)) # 金：和完美闪避同色系的"控制生效"提示
	dn.global_position = global_position + Vector2(0, _number_y - 18.0)
	get_tree().current_scene.add_child(dn)


## 枝界持续约束：每帧只延续定身计时，不重复控制反馈。
func contain(dur: float, _ignore_armor := false) -> void:
	if state == State.DEAD or dur <= 0.0 or (_super_armor and not _ignore_armor):
		return
	_root_timer = maxf(_root_timer, dur)


## 余滞：最新一次有效调用覆盖时长与倍率；只影响常规横向移动和出手前冲。
func slow(dur: float, scale: float, _ignore_armor := false) -> void:
	if state == State.DEAD or dur <= 0.0 or (_super_armor and not _ignore_armor):
		return
	_slow_timer = dur
	_slow_scale = clampf(scale, 0.0, 1.0)


## 晕眩（力僧 L）：dur 秒内不能移动、也不能出手——比定身更强。
## 立即打断正在起的招（前摇直接掐掉，交还出手令牌），站桩发愣到时间结束；
## 被打飞/受击照样推进各自状态，落地后仍保持晕眩。
func stun(dur: float, _ignore_armor := false) -> void:
	if state == State.DEAD or dur <= 0.0 or (_super_armor and not _ignore_armor):
		return
	_clear_attack_chain()
	_stun_timer = maxf(_stun_timer, dur)
	_root_timer = 0.0 # 晕眩覆盖定身：更强的控制接管
	_release_token()
	_attack_hits_left.clear()
	if state == State.ATTACK:
		state = State.IDLE
		velocity = Vector2.ZERO
		_idle_queued = false
		_play(str(_anim_map["idle"]), true)
	_flash()
	var dn := DAMAGE_NUMBER.new()
	dn.setup("晕眩", Color(0.62, 0.78, 0.95)) # 淡蓝：和定身的金色区分开
	dn.global_position = global_position + Vector2(0, _number_y - 18.0)
	get_tree().current_scene.add_child(dn)


func _stun_tick(delta: float) -> void:
	_stun_timer = maxf(0.0, _stun_timer - delta)
	velocity.x = move_toward(velocity.x, 0.0, brake * delta)
	match state:
		State.FLY:
			_fly_tick(delta)
			return
		State.HURT:
			_hurt_tick(delta)
			return
		State.DEAD:
			return
	state = State.IDLE
	_play(str(_anim_map["idle"]), true)


## 定身期间的替身循环：站桩待机 + 射程内可起手；被打飞/硬直/出手中照常推进各自状态
func _root_tick(delta: float) -> void:
	_root_timer = maxf(0.0, _root_timer - delta)
	velocity.x = move_toward(velocity.x, 0.0, brake * delta)
	match state:
		State.FLY:
			_fly_tick(delta)
			return
		State.ATTACK:
			_attack_tick(delta) # 已经起手的招可以打完（"可以攻击"）
			return
		State.HURT:
			_hurt_tick(delta)
			return
		State.DEAD:
			return
	state = State.IDLE
	_play(str(_anim_map["idle"]), true)
	if _target != null and _attack_cd <= 0.0 and _can_attack():
		var dx: float = _target.global_position.x - global_position.x
		var dy: float = absf(_target.global_position.y - global_position.y)
		facing = 1 if dx > 0.0 else -1
		_apply_facing()
		if absf(dx) <= attack_range and dy <= 60.0:
			_start_attack()


## 流血（双刺 L 裂帛）：叠层后每秒按层数直扣血，不触发硬直/白闪，也不打断出手
func apply_bleed(layers: int) -> void:
	if state == State.DEAD or layers <= 0:
		return
	_bleed_stacks = mini(_bleed_stacks + layers, BLEED_MAX)
	_bleed_time = BLEED_DUR


## 一次性收走当前流血层数，供绯羽等机制转化；后续不会继续跳这次流血。
func consume_bleed() -> int:
	if state == State.DEAD or _bleed_stacks <= 0:
		return 0
	var stacks := _bleed_stacks
	_bleed_stacks = 0
	_bleed_time = 0.0
	_bleed_acc = 0.0
	return stacks


func _bleed_tick(delta: float) -> void:
	if _bleed_stacks <= 0 or state == State.DEAD:
		return
	_bleed_time -= delta
	if _bleed_time <= 0.0:
		_bleed_stacks = 0
		_bleed_acc = 0.0
		return
	_bleed_acc += delta
	while _bleed_acc >= 1.0 and _bleed_stacks > 0:
		_bleed_acc -= 1.0
		_direct_damage(_bleed_stacks)


## 中毒（梅剑 K 尾端甩鞭）：dur 秒内每 0.5 秒直扣 1 点；不叠层，重复命中只刷新时长
func apply_poison(dur: float) -> void:
	if state == State.DEAD or dur <= 0.0:
		return
	_poison_time = maxf(_poison_time, dur)
	var dn := DAMAGE_NUMBER.new()
	dn.setup("中毒", POISON_LABEL_COLOR)
	dn.global_position = global_position + Vector2(0, _number_y - 18.0)
	get_tree().current_scene.add_child(dn)


func _poison_tick(delta: float) -> void:
	if _poison_time <= 0.0 or state == State.DEAD:
		return
	_poison_time = maxf(0.0, _poison_time - delta)
	_poison_acc += delta
	# 先结算累计毒伤再判到期：4 秒毒正好是 8 次（0.5/1.0/…/4.0），最后一下不会被到期判断吞掉
	while _poison_acc >= POISON_TICK:
		_poison_acc -= POISON_TICK
		_direct_damage(POISON_DMG, POISON_COLOR)
		if state == State.DEAD:
			var pl = get_tree().get_first_node_in_group("player")
			if pl != null and pl.has_method("on_poison_kill"):
				pl.call("on_poison_kill", self)
			break
		if _poison_time <= 0.0:
			break
	if _poison_time <= 0.0:
		_poison_acc = 0.0


## 山民：计时始终推进，到点有伤才回血；满血不会越界，也不会囤出额外治疗次数。
func _regen_tick(delta: float) -> void:
	if _regen_interval <= 0.0 or _regen_amount <= 0 or state == State.DEAD:
		return
	_regen_timer -= delta
	if _regen_timer > 0.0:
		return
	_regen_timer = _regen_interval
	if hp >= max_hp:
		return
	hp = mini(max_hp, hp + _regen_amount)
	_update_hp_bar()
	var dn := DAMAGE_NUMBER.new()
	dn.setup("+%d" % _regen_amount, POISON_LABEL_COLOR)
	dn.global_position = global_position + Vector2(0, _number_y)
	get_tree().current_scene.add_child(dn)


## 非打击伤害（流血/中毒等）：直接扣血，不进硬直，但仍走死亡流程；Boss 覆盖以同步阶段/大血条
func _direct_damage(amount: int, color: Color = DMG_COLOR) -> void:
	if state == State.DEAD or amount <= 0:
		return
	hp -= amount
	_spawn_number(amount, color)
	_update_hp_bar()
	if hp <= 0:
		_end_stop()
		die()


## 砸落（银夜空中派生）：直线下坠，落地只向玩家回报一次，再接原有落地硬直。
func slam(_ignore_armor := false) -> void:
	if state == State.DEAD or (_super_armor and not _ignore_armor):
		return
	_enter_fly(Vector2(0.0, 900.0), 0)
	_slam_pending = true
	if is_on_floor():
		_fly_tick(0.0) # 地面立即落地：与空中落地共用同一结算分支


func _report_slam_landing() -> void:
	if not _slam_pending:
		return
	_slam_pending = false
	var pl = get_tree().get_first_node_in_group("player")
	if pl != null and pl.has_method("on_enemy_slammed"):
		pl.call("on_enemy_slammed", self, global_position)


## 击飞（银夜普攻二段 / 剑仙 U 飞脚）：向上挑起，落地短暂硬直。无视出手霸体（跳劈也照挑）
## ignore_armor：剑仙 U 的规则级击飞标记——小怪/精英本来就吃击飞，这里无需额外分支
func launch(dir: int, vx: float, vy: float, _ignore_armor := false) -> void:
	if state == State.DEAD or (_super_armor and not _ignore_armor):
		return
	_enter_fly(Vector2(dir * vx, -vy), 0)


## 击退（银夜 L / 剑仙 O）：横向轰飞，途中撞到同伴双方各吃 impact 组合伤害，撞墙自己再吃一下
## ignore_armor：同上，小怪/精英的击退本就不看霸体
func knock_back(dir: int, force: float, impact: int, _ignore_armor := false) -> void:
	if state == State.DEAD or (_super_armor and not _ignore_armor):
		return
	_enter_fly(Vector2(dir * force, -120.0), impact)


func _enter_fly(v: Vector2, impact: int) -> void:
	_clear_attack_chain()
	_attack_hits_left.clear()
	_release_token()
	_slam_pending = false # 普通 launch / knock_back 不继承上一次砸落回报
	_root_timer = 0.0 # 被轰飞时解除定身：物理级控制在定身之上（同一套规则，和时停一致）
	if _stop_timer > 0.0:
		_end_stop() # 定身中被打飞：解除定身让抛物线成立（时停不挡位移类控制）
	state = State.FLY
	_hurt_chain_active = false # 击飞/击退是独立物理控制，落地后不能续播旧倒地链
	_hurt_chain.clear()
	_fly_impact = impact
	_fly_hit.clear()
	velocity = v
	_idle_queued = false
	_play(str(_anim_map["hurt"]), false) # 没有挑飞专用动画，重击受击帧顶上


func _fly_tick(delta: float) -> void:
	# 横向轰飞才结算碰撞伤害（纯击飞 _fly_impact=0 不撞）
	if _fly_impact > 0 and absf(velocity.x) > 130.0:
		for e in get_tree().get_nodes_in_group("enemies"):
			if e == self or not is_instance_valid(e) or _fly_hit.has(e):
				continue
			if int(e.get("state")) == State.DEAD or int(e.get("hp")) <= 0:
				continue
			var dx: float = e.global_position.x - global_position.x
			var dy: float = absf(e.global_position.y - global_position.y)
			if absf(dx) <= body_radius + _radius_of(e) and dy <= 100.0:
				_fly_hit[e] = true
				e.call("take_damage", _fly_impact, global_position.x)
				Feel.shake(4.0, 0.12)
				var pl = get_tree().get_first_node_in_group("player")
				if pl != null and pl.has_method("on_knock_collision"):
					pl.call("on_knock_collision", self, e)
				var self_dmg := _fly_impact
				_fly_impact = 0 # 撞到第一只就卸力，自己吃组合伤害并坠地
				take_damage(self_dmg, e.global_position.x)
				return # 自己可能被撞死（state 已变 DEAD），直接收
		if is_on_wall():
			var wall_dmg := _fly_impact
			var wall_dir := -signf(velocity.x) # 伤害来源算墙那一侧
			_fly_impact = 0
			velocity.x = 0.0
			Feel.shake(5.0, 0.15)
			var pl = get_tree().get_first_node_in_group("player")
			if pl != null and pl.has_method("on_knock_wall"):
				pl.call("on_knock_wall", self, global_position)
			take_damage(wall_dmg, global_position.x + wall_dir * 10.0)
			return
	velocity.x = move_toward(velocity.x, 0.0, 400.0 * delta)
	# 落地：短暂硬直再起身（重力与 move_and_slide 在主循环末尾统一走）
	if is_on_floor() and velocity.y >= 0.0:
		_report_slam_landing()
		state = State.HURT
		_hurt_timer = 0.3


func take_damage(amount: int, source_x: float) -> void:
	if state == State.DEAD:
		return
	# 时停中挨打：伤害/数字/白闪照给，但不进硬直、不解定身；打死则先解冻再走死亡流程
	if _stop_timer > 0.0:
		hp -= amount
		_spawn_number(amount)
		_update_hp_bar()
		if hp <= 0:
			_end_stop()
			die()
		return
	hp -= amount
	_sfx_player.stream = SFX_HIT_QI
	_sfx_player.play()
	_spawn_number(amount)
	_update_hp_bar()
	# 水墨受击特效：在受击一侧的胸口高度炸开
	FX.spawn(get_tree().current_scene, "ink_hit",
		global_position + Vector2(0, -_scale * 150.0),
		{"scale": _scale * 1.3, "flip": source_x > global_position.x})
	if hp <= 0:
		die()
		return
	# 半血狂暴（青笠）：跌破阈值触发一次，出手更密、追得更紧——越残越凶
	if _enrage_below > 0.0 and not _enraged and float(hp) / float(max_hp) <= _enrage_below:
		_enraged = true
		attack_cooldown *= _enrage_cd
		chase_speed *= _enrage_speed
	# 倒地链没播完：伤害、数字、墨花和死亡全都正常结算，只锁住受击动画防重入。
	if _hurt_chain_active:
		_flash()
		return
	# 受击硬直分层：普通怪轻击就断招；精英霸体，只有重击（damage >= armor）才打断；
	# 出手霸体的招（青笠跳斩）出手期间挨多重都不断，只掉血
	if _super_armor or amount < _armor or (state == State.ATTACK and bool(_poise_anims.get(_attack_move, false))):
		_flash()
		return
	_clear_attack_chain()
	_attack_hits_left.clear()
	_release_token() # 被打断的出手要交还令牌，否则其他怪永远等不到出手机会
	var dir := 1.0 if global_position.x >= source_x else -1.0
	if not _knock_chain.is_empty() and amount >= _knock_at:
		_start_hurt_chain(dir)
		_flash()
		return
	state = State.HURT
	_hurt_timer = hurt_time
	_idle_queued = false # set_animation 已清掉队列里的 stand
	velocity = Vector2(dir * 200.0, -70.0) # 加重击退：命中要"打得动"
	_play(str(_anim_map["hurt"]), false)
	_flash() # 受击白闪


## 受击白闪：modulate 拉到过曝（会被钳到纯白），再快速回落，给出清晰的"打到了"反馈
func _flash() -> void:
	if sprite == null:
		return
	sprite.modulate = Color(4.0, 4.0, 4.0)
	var tw := create_tween()
	tw.tween_property(sprite, "modulate", Color.WHITE, 0.14)


func _spawn_number(amount: int, color: Color = DMG_COLOR) -> void:
	var dn := DAMAGE_NUMBER.new()
	dn.setup(str(amount), color)
	dn.global_position = global_position + Vector2(randf_range(-12.0, 12.0), _number_y)
	get_tree().current_scene.add_child(dn)


func die() -> void:
	_end_stop() # 时停中被打死：先解冻，死亡动画才播得出来
	state = State.DEAD
	_clear_attack_chain()
	_attack_hits_left.clear()
	_hurt_chain_active = false
	_hurt_chain.clear()
	_release_token()
	velocity = Vector2.ZERO
	_update_hp_bar()
	$CollisionShape2D.set_deferred("disabled", true)
	_play(str(_anim_map["dead"]), false)
	# 尸体消散时一团墨散开，盖住淡出
	FX.spawn(get_tree().current_scene, "vanish", global_position,
		{"scale": _scale * 1.6, "z": 5})
	Meta.add_kill(Run.skull_id) # 局外养成：累计击杀 + 当前形态契合
	Meta.add_enemy_kill(type_id) # 图鉴：这只敌人（Boss 也走这里）被击败一次，收录 +1
	Score.add_kill() # 本局击杀计数（结算战绩用）
	var pl = get_tree().get_first_node_in_group("player")
	if pl != null and pl.has_method("on_enemy_killed"):
		pl.call("on_enemy_killed", self)
	died.emit()
	_cleanup()


## 尸体自清理：死亡动画播完 → 淡出 → 释放自己，场上不留空壳节点
func _cleanup() -> void:
	var dead_name := str(_anim_map["dead"])
	var dead_dur: float = maxf(float(_anim_durations.get(dead_name, 1.2)), _dead_min)
	await get_tree().create_timer(dead_dur).timeout
	if sprite != null and is_instance_valid(sprite):
		var tw := create_tween()
		tw.tween_property(sprite, "modulate:a", 0.0, 0.45)
	await get_tree().create_timer(0.5).timeout
	queue_free()



# ---------- 工具 ----------

func _find_target() -> void:
	var nearest: Node2D = null
	var nearest_dist := INF
	for node in get_tree().get_nodes_in_group("player_decoy"):
		var decoy := node as Node2D
		if decoy == null or not is_instance_valid(decoy) or decoy.is_queued_for_deletion():
			continue
		var dx := absf(decoy.global_position.x - global_position.x)
		var dy := absf(decoy.global_position.y - global_position.y)
		if dx > 520.0 or dy > 160.0:
			continue
		var dist := global_position.distance_squared_to(decoy.global_position)
		if dist < nearest_dist:
			nearest = decoy
			nearest_dist = dist
	if nearest != null:
		_target = nearest # 诱饵优先于已经锁定的玩家，并始终改追最近的一只
		return
	if _target != null and is_instance_valid(_target) and not _target.is_in_group("player_decoy"):
		return
	_target = get_tree().get_first_node_in_group("player") as Node2D


## 出手令牌：同一时刻只放一只小怪出手；持有者被受击打断/死亡也要释放
func _can_attack() -> bool:
	if _attacker == null or not is_instance_valid(_attacker):
		return true
	return _attacker == self


func _release_token() -> void:
	if _attacker == self:
		_attacker = null


## 规则级打断不能留下半段连招或招式自身的力竭计时。
func _clear_attack_chain() -> void:
	_chain_next = ""
	_recovery_after_attack = 0.0
	_recovery_timer = 0.0


## 同伴分离力：同向挤在一起时互相推开；迎面相遇则放行，让双方直接对穿过去
func _separation_push() -> float:
	var push := 0.0
	var near := _scale * 200.0 # 体型越大，推开的距离越远
	for e in get_tree().get_nodes_in_group("enemies"):
		if e == self or not is_instance_valid(e):
			continue
		if int(e.get("state")) == State.DEAD:
			continue
		var dx: float = global_position.x - e.global_position.x # 我在同伴的哪一侧
		var dy: float = absf(global_position.y - e.global_position.y)
		if dy > _scale * 156.0 or absf(dx) > near:
			continue
		# 双方都在朝对方走（迎面）：不推，直接穿过去，避免头顶头僵在原地
		if dx != 0.0 and velocity.x * dx < 0.0 and float(e.velocity.x) * -dx < 0.0:
			continue
		if absf(dx) < 1.0:
			push += 1.0 if get_instance_id() > e.get_instance_id() else -1.0
		else:
			push += signf(dx) * (1.0 - absf(dx) / near)
	return clampf(push, -1.5, 1.5)


## 对穿：贴身就临时关掉彼此的碰撞，分开后恢复。
## 之前靠"卡住就跳一下"，视觉上太假；现在两只怪迎面时各走各的，自然错身而过。
func _update_peer_ghosts() -> void:
	for k in _ghosts.keys():
		if not is_instance_valid(k):
			_ghosts.erase(k)
	var near := _scale * 175.0
	for e in get_tree().get_nodes_in_group("enemies"):
		if e == self or not is_instance_valid(e):
			continue
		if int(e.get("state")) == State.DEAD:
			continue
		var dx: float = global_position.x - e.global_position.x
		var dy: float = absf(global_position.y - e.global_position.y)
		var close := dy <= _scale * 156.0 and absf(dx) < near
		var has := _ghosts.has(e)
		if close and not has:
			add_collision_exception_with(e)
			e.add_collision_exception_with(self)
			_ghosts[e] = true
		elif not close and has:
			remove_collision_exception_with(e)
			e.remove_collision_exception_with(self)
			_ghosts.erase(e)


func _sees_player(radius: float) -> bool:
	if _target == null or not is_instance_valid(_target):
		return false
	var dx: float = absf(_target.global_position.x - global_position.x)
	var dy: float = absf(_target.global_position.y - global_position.y)
	if _target.is_in_group("player_decoy"):
		return dx <= maxf(radius, 520.0) and dy <= 160.0
	return dx <= radius and dy <= 90.0


func _set_state(new_state: int) -> void:
	if state == new_state:
		return
	state = new_state
	match state:
		State.IDLE:
			_idle_timer = idle_time
			if _idle_queued:
				# 自动接续不会经过 _play，也要在轨道换代前保存完整旧姿势。
				if _pose_mixer != null:
					_pose_mixer.capture()
				_current_anim = str(_anim_map["idle"])
			else:
				_play(str(_anim_map["idle"]), true)
			_idle_queued = false
		State.PATROL:
			_idle_queued = false
			_play(str(_anim_map["patrol"]), true)
		State.CHASE:
			_idle_queued = false # set_animation 会清掉队列里的 stand
			_play(str(_anim_map["chase"]), true, _chase_anim_speed)


func _apply_facing() -> void:
	if sprite:
		sprite.scale.x = _scale * facing


func _play(anim: String, loop: bool, spd := 1.0) -> void:
	if _anim_state == null:
		return
	if loop and anim == _current_anim:
		# 巡逻与追击可共用一份动画：只改当前轨道倍率，不从头重播。
		if not is_equal_approx(_current_anim_speed, spd):
			_current_anim_speed = spd
			if _pending_anim == anim:
				_pending_speed = spd
			if _anim_state.has_method("get_current"):
				var current = _anim_state.call("get_current", 0)
				if current != null and current.has_method("set_time_scale"):
					current.call("set_time_scale", spd)
		return
	if _pose_mixer != null:
		if _pending_anim.is_empty():
			_pose_mixer.capture()
		_current_anim = anim
		_current_anim_speed = spd
		_pending_anim = anim
		_pending_loop = loop
		_pending_speed = spd
		_pending_queue.clear()
		return
	_current_anim = anim
	_current_anim_speed = spd
	var entry = _anim_state.call("set_animation", anim, loop, 0)
	if entry != null and entry.has_method("set_time_scale"):
		entry.call("set_time_scale", spd)


func _queue(anim: String, loop: bool) -> void:
	if _anim_state == null:
		return
	if _pose_mixer != null and not _pending_anim.is_empty():
		_pending_queue.append({"anim": anim, "loop": loop})
		return
	_anim_state.call("add_animation", anim, 0.0, loop, 0)
