extends CharacterBody2D

## 小怪通用 AI：巡逻 / 追击 / 攻击 / 受击 / 死亡
## 长什么样、出什么招、判定多长，全部来自 scripts/enemies/enemy_types.gd 的形态表。
## 主角形态不设同名敌人版本（梅剑 c023 精英已删；青笠 c012 已从玩家形态下掉，转生为精英怪）。

const Types := preload("res://scripts/enemies/enemy_types.gd")
const DAMAGE_NUMBER := preload("res://scripts/ui/damage_number.gd")
const FX := preload("res://scripts/systems/fx.gd")
const SpineFX := preload("res://scripts/systems/spine_fx.gd")
const SpinePoseMixer := preload("res://scripts/systems/spine_pose_mixer.gd")
const DMG_COLOR := Color(0.66, 0.2, 0.16) # 朱砂：敌人受伤数字
const SFX_HIT_QI := preload("res://audio/sfx/hit_qi.wav")
const SFX_HIT_FAN := preload("res://audio/sfx/hit_fan.wav")
const SFX_HEAL := preload("res://audio/sfx/heal.wav")
const SFX_TELEGRAPH := preload("res://audio/sfx/telegraph.wav")
const SFX_POISON := preload("res://audio/sfx/skill_poison.wav")
const PLAYER_BURN_INTERVALS := [60.0, 58.0, 54.0, 48.0, 40.0, 30.0, 18.0, 10.0]

@export var type_id := "c016"

enum State { IDLE, PATROL, CHASE, ATTACK, HURT, DEAD, FLY } # FLY=被击飞/击退的浮空状态

signal died

## 全局出手令牌：同一时刻只允许一只小怪起手，其余在原地等（否则一排同时挥刀像广播体操）
## 交棒后留出短暂空档，让围攻节奏变成「轮流出招」而不是无缝接力。
static var _attacker: Node2D = null
static var _token_free_at := 0 # 毫秒时间戳：上一只交棒后，下一只最早何时能接手

var state: int = State.IDLE
var wu_che_summon := false # 武车召唤物：玩家带通缉时，其实伤由统一入口额外 +1
var player_ally := false # 魅唤：独立友方阵营，不占敌人组、波次或击杀结算
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
var _move_pool: Dictionary = {} # 同一逻辑招式的随机演出池；判定按抽中的动画分别标定
var _attack_move := "" # 本次出手的逻辑键，判定/伤害/冷却均按它查询
var _attack_visual := "" # 本次实际播放的 Spine 动画
var _last_attack_move := "" # 上一次独立起手的招式；连续重复时降低权重，避免一招复读
var _attack_hit_landed := false # 本次出手是否至少碰到过一次目标；空刀会留下更长的收招破绽
var _attack_cast_id := 0 # 每次起手递增，同招多段凭它识别，不靠动画名猜测
var _opening_slow: Dictionary = {} # 只放慢首段前摇，后续动画与判定恢复正常速度
var _opening_restore_at := 0.0
var _opening_restored := true
var _limit: Dictionary = {} # 半血限定技：每个实体仅一次，回满并强化后续命中
var _limit_used := false
var _limit_pending := false # 已触发但尚在等全局出手令牌；等待期间不得抢招或改出普通攻击
var _cut_every_segment := false
var _death_burst: Dictionary = {} # 死亡后延迟结算，先完成起身、变身与最后一击
var _turn_stacks: Dictionary = {} # 「转」按目标实例独立累积的实伤次数
var _room_cd_cursed := false
var _room_skill_uses: Dictionary = {}
var _ranges: Dictionary = {}
var _back_ranges: Dictionary = {} # 前后伸展不同的招式单独标定后侧射程
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
var _segment_effects: Dictionary = {} # 多段招式的逐段效果；与整招效果合并，段效果优先
var _hit_knockback := Vector2(220.0, -80.0)
var _attack_chain: Dictionary = {} # 同一招内的接续动画与收招后的静默恢复
var _advance_map: Dictionary = {} # 攻击动画期间持续前进的速度
var _chase_anim_speed := 1.0
var _super_armor := false # 全程霸体；规则级 ignore_armor 与时停不受此影响
var _attack_rules: Dictionary = {} # 特殊招式的独立冷却、触发窗口与随机权重
var _attack_rule_cds: Dictionary = {}
var _knock_at := 999 # 高伤倒地阈值；未配置时保持原受击逻辑
var _knock_strict := false # 指定精英使用严格大于；普通怪仍保持达到阈值即倒地
var _knock_chain: Array = [] # 高伤倒地动画链
var _hurt_chain: Array = [] # 当前尚未播完的倒地链
var _hurt_chain_active := false # 链中照常吃伤害，但受击动画不得重入
var _regen_interval := 0.0 # 山民被动：回血间隔，0=无被动
var _regen_amount := 0
var _regen_timer := 0.0
var _sword_sect_scale := 1.0 # 剑宗：当前实体所在房间内永久减疗
var _heal_fraction := 0.0 # 减半后的零散治疗累计，避免每次 1 点都直接归零
var _player_burn_stacks := 0 # 影殇夺取炽热之心后施加的怒焰
var _player_burn_left := 0.0
var _player_burn_source: Node = null
var _evil_buddha_pressure := false # 影殇夺取邪佛后压制目标增益
# 半血狂暴：血量跌破 below 比例时触发一次——出手冷却 ×cd、追击速度 ×speed
var _enrage_below := 0.0
var _enrage_cd := 0.65
var _enrage_speed := 1.2
var _enraged := false
var _bloodthirst: Dictionary = {} # 嗜血：低血永久激活；虚弱动画/减速只随当前血量变化
var _bloodthirst_active := false
var _skill_cooldown_scale := 1.0 # 镰意绽花命中后永久减半，不重复叠加
# 青笠剑意：只由本体实伤叠层；凝华分身读取本体层数，但不叠层、不再繁殖。
var _sword_intent := 0
var _sword_hit_damage: Dictionary = {} # 本次出手各段已结算伤害，供同步分身保持同伤
var _sword_clone_node: Node2D = null
var _is_sword_clone := false
var _sword_player_clone := false # 影殇夺取剑意：复用青笠虚影，但由玩家同段伤害驱动
var _sword_owner: Node2D = null
var _elite := false # 精英标记（时停分档用：杂兵 10s / 精英 8s / Boss 5s）
var _stop_timer := 0.0 # 时间暂停（银夜 U）剩余
var _slow_timer := 0.0 # 余滞剩余：时停期间冻结，其余状态照常计时
var _slow_scale := 1.0 # 余滞横向速度倍率：只缩放移动目标，不改形态参数
var _vuln_timer := 0.0 # 易伤剩余（剑仙 L 斩焰）：时停冻结，其余状态照常计时
var _vuln_ratio := 0.0 # 易伤承伤倍率加成：0.25 = 受到的所有直接伤害 +25%
# ---------- 定身 / 流血（绯刃 L/U 的机制接口，Boss 继承后按体型覆盖） ----------
var _root_timer := 0.0 # 定身剩余：不能移动，但可以照常出手
var _stun_timer := 0.0 # 晕眩剩余：不能移动、也不能出手（镇岳 L）
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
# ---------- 绛弦：癫狂 / 魅惑 / 怨 / 六感尽失 / 心灵震撼（均随房间实体销毁） ----------
var _frenzy_time := 0.0
var _frenzy_empowered := false
var _charm_time := 0.0
var _grudge := 0
var _six_senses := 0
var _mind_shock := 0 # 上限一层；重复神伤仍刷新其他状态，不突破此上限
var _red_scapegoat_used := false # 红粉骷髅：每个癫狂目标至多替死一次
var _transferred_debuffs: Dictionary = {} # 心魔引转来的玩家专属减益：id -> {stacks,time}
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
var _cue_player: AudioStreamPlayer # 普通怪的轻量起手提示，独立音量，不干扰命中音
var _status_fx: Dictionary = {} # 状态键 -> 持续 Spine 特效；只随状态存在，不另设计时
var _death_burst_fx: Node2D = null # 魔爆火焰爆裂特效：与实伤同帧生成，按前扑范围定位


func _ready() -> void:
	add_to_group("player_allies" if player_ally else "enemies")
	_apply_type()
	hp = max_hp
	_regen_timer = _regen_interval
	_home_x = global_position.x
	_idle_timer = idle_time
	_setup_spine()
	_make_hp_bar()
	_sfx_player = AudioStreamPlayer.new()
	_sfx_player.bus = "SFX"
	add_child(_sfx_player)
	_cue_player = AudioStreamPlayer.new()
	_cue_player.bus = "SFX"
	_cue_player.volume_db = -9.0
	add_child(_cue_player)
	if _is_sword_clone:
		# 凝华分身不可选中、不占敌人组与出手令牌；无敌且不会触发击杀/结算逻辑。
		remove_from_group("enemies")
		remove_from_group("player_allies")
		_telegraph_on = false
		_hp_bar.visible = false
		$CollisionShape2D.set_deferred("disabled", true)
		_make_sword_clone_visual()


## 把形态表装到实例上
func _apply_type() -> void:
	var t: Dictionary = Types.get_type(type_id)
	type_id = type_id if Types.TYPES.has(type_id) else Types.DEFAULT_ID
	_base_scale = float(t["scale"])
	_scale = _base_scale
	_anim_map = t["anim"]
	_attack_anims = t["attacks"]
	_move_anims = t.get("move_anims", {})
	_move_pool = t.get("move_pool", {})
	_opening_slow = t.get("opening_slow", {})
	_limit = t.get("limit", {})
	_limit_used = false
	_cut_every_segment = false
	_death_burst = t.get("death_burst", {})
	_turn_stacks.clear()
	_room_cd_cursed = false
	_room_skill_uses.clear()
	_ranges = t["ranges"]
	_back_ranges = t.get("back_ranges", {})
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
	_segment_effects = t.get("segment_effects", {})
	_hit_knockback = t.get("hit_knockback", Vector2(220.0, -80.0))
	_attack_chain = t.get("attack_chain", {})
	_advance_map = t.get("advance", {})
	_chase_anim_speed = float(t.get("chase_anim_speed", 1.0))
	_super_armor = bool(t.get("super_armor", false))
	# 长期规则：首招是唯一无独立冷却的普攻；其余招式有冷却且就绪优先。
	# 连段收尾属于主招，不另算技能，也不重复计时。
	_attack_rules = (t.get("attack_rules", {}) as Dictionary).duplicate(true)
	var chain_followups: Array = []
	for start in _attack_chain:
		chain_followups.append(str((_attack_chain[start] as Dictionary).get("anim", "")))
	for i in _attack_anims.size():
		var move := str(_attack_anims[i])
		var rule: Dictionary = _attack_rules.get(move, {})
		if i == 0 or chain_followups.has(move):
			rule["cooldown"] = 0.0
		elif float(rule.get("cooldown", 0.0)) <= 0.0:
			rule["cooldown"] = 8.0
		_attack_rules[move] = rule
	_attack_rule_cds.clear()
	for anim in _attack_rules:
		_attack_rule_cds[anim] = 0.0
	_knock_at = int(t.get("knock_at", 999))
	_knock_strict = bool(t.get("knock_strict", false))
	_knock_chain = (t.get("knock_chain", []) as Array).duplicate()
	var regen: Dictionary = t.get("regen", {})
	_regen_interval = float(regen.get("interval", 0.0))
	_regen_amount = int(regen.get("amount", 0))
	var en: Dictionary = t.get("enrage", {})
	_enrage_below = float(en.get("below", 0.0))
	_enrage_cd = float(en.get("cd", 0.65))
	_enrage_speed = float(en.get("speed", 1.2))
	_bloodthirst = t.get("bloodthirst", {})
	_bloodthirst_active = false
	_skill_cooldown_scale = 1.0
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
	for n in _move_pool:
		for visual in _move_pool[n]:
			var a = data.call("find_animation", str(visual))
			if a != null:
				_anim_durations[str(visual)] = a.call("get_duration")
	for visual in _limit.get("pool", []):
		var a = data.call("find_animation", str(visual))
		if a != null:
			_anim_durations[str(visual)] = a.call("get_duration")
	for key in ["getup", "anim"]:
		var visual := str(_death_burst.get(key, ""))
		if not visual.is_empty():
			var a = data.call("find_animation", visual)
			if a != null:
				_anim_durations[visual] = a.call("get_duration")
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
	_sync_status_effects()
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


## 所有状态特效共用同一生命周期：激活时至多一个，解除/死亡即由所有者释放。
func _sync_status_effects() -> void:
	var body_pos := Vector2(0.0, -_scale * 150.0)
	var head_pos := Vector2(0.0, _number_y)
	_sync_status_fx("poison", _poison_time > 0.0, "E50127", body_pos, "action", 150.0 * _scale)
	_sync_status_fx("stun", _stun_timer > 0.0, "E52000", head_pos, "action", 60.0 * _scale)
	_sync_status_fx("charm", _charm_time > 0.0, "E54156", head_pos + Vector2(0.0, -12.0), "action", 70.0 * _scale)
	_sync_status_fx("frenzy", _frenzy_time > 0.0, "E52007", head_pos + Vector2(0.0, -12.0), "action", 70.0 * _scale)
	_sync_status_fx("bell", _golden_bell_active(), "E52025", body_pos, "action1", 190.0 * _scale)
	_sync_status_fx_processing()


func _golden_bell_active() -> bool:
	return false


func _sync_status_fx(key: String, active: bool, fx_id: String, pos: Vector2, anim := "", height := 0.0) -> void:
	var current: Variant = _status_fx.get(key)
	if not active or state == State.DEAD:
		if is_instance_valid(current):
			current.queue_free()
		_status_fx.erase(key)
		return
	if is_instance_valid(current) and not current.is_queued_for_deletion():
		return
	var opts := {"loop": true, "auto_free": false, "height": height, "center": true}
	if not anim.is_empty():
		opts["anim"] = anim
	var fx := SpineFX.attach(self, fx_id, pos, opts)
	if fx == null:
		return
	fx.set_meta("fx_id", fx_id)
	fx.set_meta("status_key", key)
	_status_fx[key] = fx


func _sync_status_fx_processing() -> void:
	var mode := Node.PROCESS_MODE_DISABLED if _stop_timer > 0.0 else Node.PROCESS_MODE_INHERIT
	for fx in _status_fx.values():
		if is_instance_valid(fx):
			fx.process_mode = mode


func _clear_status_effects() -> void:
	for fx in _status_fx.values():
		if is_instance_valid(fx):
			fx.queue_free()
	_status_fx.clear()


func _physics_process(delta: float) -> void:
	if state == State.DEAD:
		return
	if _is_sword_clone:
		# 凝华分身不占令牌，但必须独立推进本体同步来的控制计时。
		if _stop_timer > 0.0:
			_stop_timer -= delta
			if _stop_timer <= 0.0:
				_end_stop() # 虚影解冻不触发玩家的单体时停结束回报
			return
		if _stun_timer > 0.0:
			_stun_tick(delta)
			return
		_sword_clone_tick(delta)
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
	_vuln_tick(delta) # 易伤同理：时停冻结，其余状态照常倒计时
	_regen_tick(delta) # 山民：时停冻结，其他状态照常计时
	_pipa_status_tick(delta)
	if state == State.DEAD:
		return
	_try_start_limit() # DoT 或状态伤害触发祭剑后，也在本轮普通 AI 前排队取得令牌

	# 晕眩（镇岳 L）：比定身更强——站桩发愣，不出手也不移动（放在定身之前结算）
	if _stun_timer > 0.0:
		_stun_tick(delta)
		_update_peer_ghosts()
		velocity.y = minf(velocity.y + gravity * delta, 900.0)
		move_and_slide()
		return

	# 定身（绯刃 U）：只锁移动，不锁出手——站桩期间贴脸照样能挥刀
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

	_sync_bloodthirst()
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
	velocity.x = move_toward(velocity.x, _patrol_dir * _patrol_speed_now() * _slow_scale, accel * delta)


func _chase_tick(delta: float) -> void:
	if _target == null or not is_instance_valid(_target):
		_set_state(State.PATROL)
		return
	var dx: float = _target.global_position.x - global_position.x
	var dy: float = absf(_target.global_position.y - global_position.y)
	var max_range := INF if _charm_time > 0.0 or _frenzy_time > 0.0 else (520.0 if _target.is_in_group("player_decoy") else lose_range)
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
	# 贴太近但还在冷却 / 令牌被同伴占着：先退开保持站位，别和同伴挤在同一格。
	# 这是围攻读招的关键：等待出手的怪会主动让出挥砍空间，而不是贴脸叠成一坨。
	if absf(dx) < keep_dist and (_attack_cd > 0.0 or not _can_attack()):
		var retreat_speed := _chase_speed_now() if _bloodthirst_weak() else 80.0
		velocity.x = move_toward(velocity.x, -facing * retreat_speed * _slow_scale, accel * delta)
		return
	var acc := turn_accel if signf(velocity.x) != 0.0 and signf(velocity.x) != signf(dx) else accel
	velocity.x = move_toward(velocity.x, facing * _chase_speed_now() * _slow_scale, acc * delta)


func _attack_tick(delta: float) -> void:
	_attack_timer -= delta
	if not _opening_restored and _attack_dur - _attack_timer >= _opening_restore_at:
		_opening_restored = true
		_set_track_speed(1.0)
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
		_attack_cd = attack_cooldown * _skill_cooldown_scale
		if not _telegraph_on:
			_attack_cd *= randf_range(0.88, 1.12) # 杂兵错开节拍，避免整排同帧进入下一轮
		_chase_block = 0.35
		if not _attack_hit_landed:
			# 空刀：收招多留一拍破绽，鼓励玩家读招后撤再反打
			_chase_block = 0.55
			_recovery_after_attack = maxf(_recovery_after_attack, 0.14)
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
		_attack_hit_landed = false
	# 就绪且距离合规的技能优先；全部不可用才回首招普攻。
	var dist := 0.0
	if _target != null:
		dist = absf(_target.global_position.x - global_position.x)
	var basic_anim := str(_attack_anims[0]) if not _attack_anims.is_empty() else ""
	var basic_pool: Array = []
	var basic_weights: Array = []
	var skill_pool: Array = []
	var skill_weights: Array = []
	for n in _attack_anims:
		var rule: Dictionary = _attack_rules.get(n, {})
		if not bool(rule.get("random", true)) or not _rule_allows(str(n), dist):
			continue
		if _max_range_of(n) >= dist - 10.0:
			var weight := float(rule.get("weight", 1.0))
			if str(n) == _last_attack_move:
				weight *= 0.3 # 同一招连着起手时降权，避免机械复读
			if str(n) == basic_anim:
				basic_pool.append(n)
				basic_weights.append(weight)
			else:
				skill_pool.append(n)
				skill_weights.append(weight)
	var pool: Array = skill_pool if not skill_pool.is_empty() else basic_pool
	var weights: Array = skill_weights if not skill_pool.is_empty() else basic_weights
	var total_weight := 0.0
	for weight in weights:
		total_weight += float(weight)
	var anim := forced_anim
	if anim == "" and pool.is_empty():
		if not _attack_rules.is_empty():
			return # 特殊招全在冷却或不在窗口时继续贴近，不拿远招违规兜底
		# 所有招都够不着：用最远那招（至少方向对、范围最大）
		var far_r := -1.0
		for n in _attack_anims:
			var fr := _max_range_of(n)
			if fr > far_r:
				far_r = fr
				anim = str(n)
	elif anim == "" and _pick_nearest:
		# 精英：挑"刚好够得着"的最近一招，近身不会甩 580px 的大招
		var best_r := INF
		for n in pool:
			var br := _max_range_of(n)
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
	_sword_hit_damage.clear()
	_attack_move = anim
	if not continue_chain and anim != basic_anim:
		_last_attack_move = anim
	# 六感尽失只惩罚非普攻的独立起手；连段接续不重复触发。
	if not continue_chain and anim != basic_anim:
		var limit_was_used := _limit_used
		_trigger_six_senses()
		# 神伤可能跨祭剑阈值并嵌套起手；外层旧招必须到此为止，不能覆盖祭剑状态。
		if state == State.DEAD or _limit_used != limit_was_used:
			return
	if not _is_sword_clone:
		_attacker = self # 本体占住出手令牌；凝华分身只同步，不阻断其他敌人
	_attack_visual = str(_move_anims.get(anim, anim))
	if _move_pool.has(anim) and not (_move_pool[anim] as Array).is_empty():
		var visuals: Array = _move_pool[anim]
		_attack_visual = str(visuals[randi() % visuals.size()])
	elif anim == str(_limit.get("move", "")):
		var visuals: Array = _limit.get("pool", [])
		if not visuals.is_empty():
			_attack_visual = str(visuals[randi() % visuals.size()])
	# 连段收尾仍属同一次出手：保留 cast key 才能按配置穿过本连段前段造成的受击无敌。
	if not continue_chain:
		_attack_cast_id += 1
	var chain: Dictionary = _attack_chain.get(anim, {})
	_chain_next = str(chain.get("anim", ""))
	if _attack_rules.has(anim):
		var rule: Dictionary = _attack_rules[anim]
		var cd := float(rule.get("cooldown", 0.0)) * _skill_cooldown_scale
		if cd > 0.0 and _room_cd_cursed:
			var uses := int(_room_skill_uses.get(anim, 0))
			cd += uses
			_room_skill_uses[anim] = uses + 1
		_attack_rule_cds[anim] = cd
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
	_attack_dur = float(_anim_durations.get(_attack_visual, _anim_durations.get(anim, 1.5)))
	var play_speed := 1.0
	_opening_restored = true
	_opening_restore_at = 0.0
	var slow: Dictionary = _opening_slow.get(anim, {})
	var slow_until := float(slow.get("until", 0.0))
	var slow_scale := float(slow.get("scale", 1.0))
	if slow_until > 0.0 and slow_scale > 0.0 and not is_equal_approx(slow_scale, 1.0):
		play_speed = slow_scale
		_opening_restore_at = slow_until / slow_scale
		_opening_restored = false
		_attack_dur += _opening_restore_at - slow_until
	_attack_timer = _attack_dur
	# hit_at 是动画时间；首段慢放时换算成真实时间，判定仍与剑刃伸展同帧。
	_attack_hits_left.clear()
	var ha = _hit_at_map.get(_hit_key(anim), 0.9)
	var ha_list: Array = ha if ha is Array else [ha]
	for i in ha_list.size():
		_attack_hits_left.append({"t": _attack_dur - _real_hit_at(anim, float(ha_list[i])), "i": i})
	_attack_hits_left.sort_custom(func(a, b): return float(a["t"]) > float(b["t"]))
	velocity.x = facing * attack_lunge * float(_lunge_map.get(anim, 1.0)) * _slow_scale # 出手带一段前冲
	var hop := float(_hop_map.get(anim, 0.0))
	if hop > 0.0:
		velocity.y = -hop # 跳斩腾空：配合动画的跃起视觉，重力会自然把他带回地面
	_play(_attack_visual, false, play_speed) # 逻辑招式与真实演出分开记录
	# 关键：排队 stand 紧跟技能之后。否则非循环动画播完的瞬间轨道空窗，
	# 骨架会闪回一帧 setup pose 再被 set_animation 接走 = 收招时"闪现一下"。
	_queue(str(_anim_map["idle"]), true)
	_idle_queued = true
	if _telegraph_on:
		_telegraph()
	elif not continue_chain and anim != basic_anim:
		# 普通怪没有泛红预警，但危险招式给一记轻量起手音，保证读招公平
		_cue_player.stream = SFX_TELEGRAPH
		_cue_player.play()
	if not _is_sword_clone and is_instance_valid(_sword_clone_node):
		_sword_clone_node.call("_sword_sync_attack", anim)


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
	if player_ally and not _target.is_in_group("enemies"):
		return
	if _charm_time > 0.0 and _target.is_in_group("player"):
		return # 魅惑目标永不攻击玩家，包括魅惑前已经起手的旧招
	var dx: float = _target.global_position.x - global_position.x
	var dy: float = absf(_target.global_position.y - global_position.y)
	var move := _replay_move(seg)
	var no_damage := bool(move.get("feedback_only", false)) or bool(move.get("effect_only", false))
	# 纯反馈与绽花不能走 Run.enemy_damage：该入口会把 0 也抬成最低 1 伤。
	# 青笠每段可有独立基础伤害；剑意在本次命中前结算，命中后的叠层只影响后续命中。
	var turn_bonus := int(_turn_stacks.get(_target.get_instance_id(), 0)) if bool(move.get("stacking_damage", false)) else 0
	var dmg := 0 if no_damage else Run.enemy_damage(_damage_of(_attack_move, seg) + _sword_intent_now() + turn_bonus)
	if dmg > 0 and wu_che_summon:
		dmg += 1 # 墨徒信仰：直接攻击始终比当前难度高一档，最高难度也继续提升
	if dmg > 0 and _bloodthirst_active and not _evil_buddha_pressure:
		dmg = maxi(1, dmg + int(_bloodthirst.get("damage_delta", -1)))
	# 阴影只放大本次直接命中；割伤在玩家侧独立计时，绝不回到这里二次暴击。
	if dmg > 0 and _backstab:
		var raw_facing = _target.get("facing")
		if (raw_facing is int or raw_facing is float) \
				and (global_position.x - _target.global_position.x) * float(raw_facing) < 0.0:
			dmg *= 2
	# 红尘：每 3 层怨逐段 -1，每段最低仍为 1；强化癫狂在最后翻倍。
	if dmg > 0:
		dmg = maxi(1, dmg - int(_grudge / 3.0))
		if _frenzy_time > 0.0 and _frenzy_empowered and not _evil_buddha_pressure:
			dmg *= 2
	# 本体先结算时记录同段伤害，分身后结算直接复用，避免首段叠层让镜像多打 1 点。
	if _is_sword_clone and is_instance_valid(_sword_owner):
		var cast_v = _sword_owner.get("_attack_cast_id")
		var recorded_v = _sword_owner.get("_sword_hit_damage")
		if (cast_v is int or cast_v is float) and int(cast_v) == _attack_cast_id \
				and recorded_v is Dictionary and (recorded_v as Dictionary).has(seg):
			dmg = int(recorded_v[seg])
	var in_front := dx == 0.0 or (dx > 0.0) == (facing > 0)
	var side_ok: bool = in_front or bool(_both_anims.get(_attack_move, false))
	var rng := _range_of(_attack_move, seg) if in_front else _back_range_of(_attack_move, seg)
	if side_ok and absf(dx) <= rng + _radius_of(_target) and dy <= attack_hit_height:
		_attack_hit_landed = true
		if not _is_sword_clone:
			_sword_hit_damage[seg] = dmg
		var kb := Vector2(facing * _hit_knockback.x, _hit_knockback.y)
		if move.has("knockback"):
			var custom: Vector2 = move["knockback"]
			kb = Vector2(facing * custom.x, custom.y)
		if _target.is_in_group("enemies") and _target.has_method("take_damage_from"):
			var before := int(_target.get("hp"))
			_target.call("take_damage_from", dmg, self) # 癫狂/魅惑/魅唤：真实敌人互伤
			var dealt := maxi(0, before - int(_target.get("hp")))
			if dealt > 0:
				on_player_hit(dealt, move, _target)
		elif not player_ally and _target.has_method("hurt"):
			_target.call("hurt", dmg, kb, self, move)


func _hit_key(anim: String) -> String:
	if anim == _attack_move and _move_pool.has(anim) and not _attack_visual.is_empty():
		return _attack_visual
	return anim


func _real_hit_at(anim: String, at: float) -> float:
	var slow: Dictionary = _opening_slow.get(anim, {})
	var until := float(slow.get("until", 0.0))
	var scale := float(slow.get("scale", 1.0))
	if until <= 0.0 or scale <= 0.0 or is_equal_approx(scale, 1.0):
		return at
	return at / scale if at <= until else at + until / scale - until


func _set_track_speed(spd: float) -> void:
	_current_anim_speed = spd
	if _pending_anim == _current_anim:
		_pending_speed = spd
	if _anim_state != null and _anim_state.has_method("get_current"):
		var current = _anim_state.call("get_current", 0)
		if current != null and current.has_method("set_time_scale"):
			current.call("set_time_scale", spd)


func _damage_of(anim: String, seg: int) -> int:
	var value = _damage_map.get(anim, 1)
	if value is Array:
		return int(value[mini(seg, (value as Array).size() - 1)])
	return int(value)


func _sword_intent_now() -> int:
	if _is_sword_clone:
		return int(_sword_owner.get("_sword_intent")) if is_instance_valid(_sword_owner) else 0
	return _sword_intent


## 实伤回报用于回血；绽花则要区分 _apply_bloom 与同样回报 0 伤的无敌反馈。
func on_player_hit(amount: int, move: Dictionary, _player: Node) -> void:
	if state == State.DEAD:
		return
	var bloom := bool(move.get("bloom", false)) and _bloom_settled(_player, move)
	if bloom and _skill_cooldown_scale > 0.5:
		_skill_cooldown_scale = 0.5
		_attack_cd *= _skill_cooldown_scale
		for anim in _attack_rule_cds:
			_attack_rule_cds[anim] = float(_attack_rule_cds[anim]) * _skill_cooldown_scale
	if amount > 0 and bool(move.get("lifesteal_from_damage", false)):
		_heal(amount)
	if _bloodthirst_active and not _evil_buddha_pressure and (amount > 0 or bloom):
		_heal(int(_bloodthirst.get("lifesteal", 1)))
	if amount > 0 and not _is_sword_clone and int(move.get("sword_intent", 0)) > 0:
		_gain_sword_intent(int(move.get("sword_intent", 0)))
	if amount > 0 and bool(move.get("stacking_damage", false)):
		var id := _player.get_instance_id()
		_turn_stacks[id] = int(_turn_stacks.get(id, 0)) + 1
		var dn := DAMAGE_NUMBER.new()
		dn.setup("转 · 叠剑 %d" % int(_turn_stacks[id]), Color(0.48, 0.72, 0.62))
		dn.global_position = global_position + Vector2(0, _number_y - 18.0)
		_world_add(dn)


## _apply_bloom 会先进入 HURT 并移到攻击者正上方，再回报攻击者；防御零伤反馈没有这两步。
## 不用 amount>0 判断，绽花合法命中本身就是 effect_only 的零直伤。
func _bloom_settled(player, move: Dictionary) -> bool:
	if not player is Node2D or not player.has_method("_apply_bloom"):
		return false
	var lift := float(move.get("lift_height", 120.0))
	var bloom_pos: Vector2 = global_position + Vector2(0.0, -lift)
	return player.state == player.State.HURT and (player as Node2D).global_position.is_equal_approx(bloom_pos)


func _gain_sword_intent(amount: int) -> void:
	_sword_intent = mini(3, _sword_intent + amount)
	var dn := DAMAGE_NUMBER.new()
	dn.setup("剑意凝华" if _sword_intent >= 3 else "剑意 %d/3" % _sword_intent, Color(0.55, 0.78, 0.82))
	dn.global_position = global_position + Vector2(0, _number_y - 18.0)
	_world_add(dn)
	if _sword_intent >= 3 and not is_instance_valid(_sword_clone_node):
		_spawn_sword_clone()


## 场景切换瞬间 current_scene 可能为空：生成物宁可丢弃也不崩，返回是否成功挂载。
func _world_add(node: Node) -> bool:
	var root := get_tree().current_scene
	if root == null:
		node.queue_free()
		return false
	root.add_child(node)
	return true


func _spawn_sword_clone() -> void:
	var clone = load("res://scenes/enemies/c012_elite.tscn").instantiate()
	clone.set("_is_sword_clone", true)
	clone.set("_sword_owner", self)
	clone.position = global_position + Vector2(-facing * 58.0, 0.0)
	clone.set("facing", facing)
	if not _world_add(clone):
		return
	_sword_clone_node = clone
	clone.call("_play", _current_anim, state != State.ATTACK)
	clone.call("_apply_facing")


func _make_sword_clone_visual() -> void:
	# 剑意虚体：本体保持实色，分身略带青色并半透明，脚下淡墨环跟随脚底。
	if sprite != null:
		sprite.modulate = Color(0.72, 0.94, 1.0, 0.60)
	var ring := Line2D.new()
	ring.name = "SwordCloneRing"
	var points := PackedVector2Array()
	for i in range(33):
		var angle := TAU * float(i) / 32.0
		points.append(Vector2(cos(angle) * 44.0, 2.0 + sin(angle) * 10.0))
	ring.points = points
	ring.width = 2.0
	ring.default_color = Color(0.45, 0.78, 0.82, 0.42)
	ring.antialiased = true
	ring.z_index = -1
	add_child(ring)


## 分身同步取本体朝向：取不到或类型异常时保持当前朝向。
func _owner_facing() -> int:
	var v = _sword_owner.get("facing")
	return int(v) if (v is int or v is float) else facing


func _sword_sync_attack(anim: String) -> void:
	if not _is_sword_clone or not is_instance_valid(_sword_owner) or _stop_timer > 0.0 or _stun_timer > 0.0:
		return
	_target = _sword_owner.get("_target") as Node2D
	facing = _owner_facing()
	_apply_facing()
	_start_attack(anim)
	var cast_v = _sword_owner.get("_attack_cast_id")
	if cast_v is int or cast_v is float:
		_attack_cast_id = int(cast_v)


func _sword_sync_player_action() -> void:
	if not _is_sword_clone or not _sword_player_clone or not is_instance_valid(_sword_owner):
		return
	facing = _owner_facing()
	_apply_facing()
	global_position = _sword_owner.global_position + Vector2(-facing * 58.0, 0.0)
	_target = null
	_start_attack("skill02" if int(_sword_owner.get("state")) == 6 else "skill01")
	_attack_hits_left.clear() # 玩家在实际命中时复写同段伤害，虚影自身不另做命中判定


func _sword_player_clone_tick(delta: float) -> void:
	if state == State.ATTACK:
		_attack_tick(delta)
	facing = _owner_facing()
	_apply_facing()
	global_position = _sword_owner.global_position + Vector2(-facing * 58.0, 0.0)
	if state != State.ATTACK:
		var owner_velocity = _sword_owner.get("velocity")
		var moving := owner_velocity is Vector2 and absf(owner_velocity.x) > 12.0
		_play(str(_anim_map["chase" if moving else "idle"]), true)


func _sword_clone_tick(delta: float) -> void:
	if not is_instance_valid(_sword_owner) or int(_sword_owner.get("state")) == (8 if _sword_player_clone else State.DEAD):
		queue_free()
		return
	if _sword_player_clone:
		_sword_player_clone_tick(delta)
		return
	_target = _sword_owner.get("_target") as Node2D
	if state == State.ATTACK:
		_attack_tick(delta)
		global_position.x += velocity.x * delta
		global_position.y = _sword_owner.global_position.y
		return
	facing = _owner_facing()
	_apply_facing()
	global_position = _sword_owner.global_position + Vector2(-facing * 58.0, 0.0)
	var owner_state := int(_sword_owner.get("state"))
	if owner_state == State.IDLE or owner_state == State.PATROL or owner_state == State.CHASE:
		_play(str(_sword_owner.get("_current_anim")), true)


func _dismiss_sword_clone() -> void:
	if is_instance_valid(_sword_clone_node):
		_sword_clone_node.queue_free()
	_sword_clone_node = null


func apply_sword_sect() -> void:
	_sword_sect_scale = 0.5 # 同一房间永久减半，重复命中不继续叠成 1/4、1/8


func _heal(amount: int) -> void:
	if amount <= 0 or hp <= 0 or state == State.DEAD or hp >= max_hp:
		return
	var healing := float(amount) * _sword_sect_scale + _heal_fraction
	var whole := int(floor(healing))
	_heal_fraction = healing - whole
	var actual := mini(whole, max_hp - hp)
	if actual <= 0:
		return
	hp += actual
	if hp >= max_hp:
		_heal_fraction = 0.0
	_sfx_player.stream = SFX_HEAL
	_sfx_player.play()
	_update_hp_bar()
	if has_signal("hp_changed"):
		emit_signal("hp_changed", hp, max_hp)
	var dn := DAMAGE_NUMBER.new()
	dn.setup("+%d" % actual, POISON_LABEL_COLOR)
	dn.global_position = global_position + Vector2(0, _number_y)
	_world_add(dn)


func _check_limit() -> bool:
	if _limit.is_empty() or _limit_used or hp <= 0 or hp * 2 >= max_hp:
		return false
	_trigger_limit()
	return true


func _trigger_limit() -> void:
	if _limit_used or state == State.DEAD:
		return
	_limit_used = true
	_limit_pending = true
	_cut_every_segment = true
	_hurt_chain_active = false
	_hurt_chain.clear()
	_clear_attack_chain()
	_attack_hits_left.clear()
	_release_token()
	state = State.IDLE
	velocity = Vector2.ZERO
	_idle_queued = false
	_play(str(_anim_map["idle"]), true)
	_heal(max_hp)
	_try_start_limit()
	FX.spawn(get_tree().current_scene, "telegraph", global_position,
		{"scale": _scale * 1.8, "mod": Color(0.45, 0.9, 0.72, 0.95)})


func _try_start_limit() -> void:
	if not _limit_pending or state == State.DEAD or hp <= 0 or _stop_timer > 0.0 or not _can_attack():
		return
	_limit_pending = false
	_start_attack(str(_limit.get("move", "jijian")))


## 魔爆对敌人的房间诅咒：只延长有独立冷却的招式，每次使用后再增加 1 秒。
func apply_room_cd_curse() -> void:
	if _room_cd_cursed or state == State.DEAD:
		return
	_room_cd_cursed = true
	var dn := DAMAGE_NUMBER.new()
	dn.setup("魔诅", Color(0.62, 0.38, 0.72))
	dn.global_position = global_position + Vector2(0, _number_y - 18.0)
	_world_add(dn)


## 把本次真实招式与命中段交给玩家记录，结算可按同一时刻重演最后一击。
func _replay_move(seg: int) -> Dictionary:
	var at = _hit_at_map.get(_hit_key(_attack_move), 0.8)
	if at is Array:
		var arr := at as Array
		at = arr[mini(seg, arr.size() - 1)] if not arr.is_empty() else 0.8
	var move := {"anim": _attack_visual, "move_id": _attack_move, "hit_at": float(at), "cast_id": _attack_cast_id, "seg": seg}
	if _is_sword_clone and is_instance_valid(_sword_owner):
		move["cast_owner_id"] = _sword_owner.get_instance_id()
	var feedback: Array = _feedback_segments.get(_attack_move, [])
	if feedback.has(seg):
		move["feedback_only"] = true
	var effects: Dictionary = _hit_effects.get(_attack_move, {})
	for key in effects:
		move[key] = effects[key]
	var segments: Array = _segment_effects.get(_attack_move, [])
	if seg >= 0 and seg < segments.size():
		for key in segments[seg]:
			move[key] = segments[seg][key]
	if _cut_every_segment:
		move["cut"] = true
		move["cut_per_segment"] = true
		move["pierce_hurt_invincible"] = true
	return move


## 目标的受击半径：体型越大挨打面越大；没有该属性的测试替身按 30 兜底
func _radius_of(t) -> float:
	var r = t.get("body_radius")
	return float(r) if r != null else 30.0


## 该招第 seg 段的判定范围：ranges 值可以是单段（float）或多段（Array，与 hit_at 一一对应）
func _range_of(anim: String, seg: int) -> float:
	var r = _ranges.get(_hit_key(anim), _ranges.get(anim, attack_range))
	if r is Array:
		var arr := r as Array
		return float(arr[mini(seg, arr.size() - 1)]) if not arr.is_empty() else attack_range
	return float(r)


func _back_range_of(anim: String, seg: int) -> float:
	var key := _hit_key(anim)
	var r = _back_ranges.get(key, _ranges.get(key, _ranges.get(anim, attack_range)))
	if r is Array:
		var arr := r as Array
		return float(arr[mini(seg, arr.size() - 1)]) if not arr.is_empty() else attack_range
	return float(r)


## 选招要考虑多段招式真正能打到目标的最远一段，不能只拿第一段射程把整招排除。
func _max_range_of(anim: String) -> float:
	var keys: Array = _move_pool.get(anim, [anim])
	var longest := 0.0
	for key in keys:
		var r = _ranges.get(key, _ranges.get(anim, attack_range))
		var values: Array = r if r is Array else [r]
		for value in values:
			longest = maxf(longest, float(value))
	return longest


# ---------- 双镰：嗜血永久激活，虚弱外观与速度随当前血量实时切换 ----------
func _bloodthirst_weak() -> bool:
	return not _bloodthirst.is_empty() and hp > 0 and float(hp) / float(maxi(1, max_hp)) < float(_bloodthirst.get("below", 0.3))


func _idle_anim() -> String:
	return str(_bloodthirst.get("idle", _anim_map["idle"])) if _bloodthirst_weak() else str(_anim_map["idle"])


func _patrol_speed_now() -> float:
	return float(_bloodthirst.get("patrol_speed", patrol_speed)) if _bloodthirst_weak() else patrol_speed


func _chase_speed_now() -> float:
	return float(_bloodthirst.get("chase_speed", chase_speed)) if _bloodthirst_weak() else chase_speed


func _sync_bloodthirst() -> void:
	if _bloodthirst.is_empty() or state == State.DEAD:
		return
	if not _bloodthirst_active and _bloodthirst_weak():
		_bloodthirst_active = true # 永久被动一旦激活，回血也不会撤销
	match state:
		State.IDLE:
			var anim := _idle_anim()
			if anim != _current_anim:
				_idle_queued = false
				_play(anim, true)
		State.PATROL:
			var anim := str(_bloodthirst.get("move", _anim_map["patrol"])) if _bloodthirst_weak() else str(_anim_map["patrol"])
			_play(anim, true)
		State.CHASE:
			var anim := str(_bloodthirst.get("move", _anim_map["chase"])) if _bloodthirst_weak() else str(_anim_map["chase"])
			_play(anim, true, _chase_anim_speed)


# ---------- 绛弦机制接口：癫狂 / 魅惑 / 怨 / 六感尽失 / 心魔引 ----------

func apply_frenzy(duration: float, empowered := false) -> void:
	if state == State.DEAD or duration <= 0.0:
		return
	_frenzy_time = maxf(_frenzy_time, duration)
	_frenzy_empowered = _frenzy_empowered or (empowered and not _evil_buddha_pressure)
	_target = null


## 黍离：已有癫狂翻倍；没有或剩余不足时，也至少留下 12 秒。
func double_frenzy(minimum := 12.0) -> void:
	if state == State.DEAD:
		return
	_frenzy_time = maxf(minimum, _frenzy_time * 2.0)
	_target = null


func apply_charm(duration: float) -> void:
	if state == State.DEAD or duration <= 0.0:
		return
	_charm_time = maxf(_charm_time, duration)
	_target = null


func add_grudge(layers: int) -> void:
	if state != State.DEAD and layers > 0:
		_grudge += layers # 当前房间永久，无上限


func apply_six_senses(layers: int) -> void:
	if state != State.DEAD and layers > 0:
		_six_senses += layers # 当前房间永久，无上限


func can_red_scapegoat() -> bool:
	return state != State.DEAD and hp > 0 and _frenzy_time > 0.0 and not _red_scapegoat_used


func consume_red_scapegoat() -> void:
	_red_scapegoat_used = true


## 带明确来源的伤害：玩家打魅惑目标减半；万狂同奏在敌人互伤后结算流派联动。
func take_damage_from(amount: int, source: Node) -> void:
	var final := amount
	if _charm_time > 0.0 and source != null and is_instance_valid(source) and source.is_in_group("player"):
		final = maxi(1, int(ceilf(final / 2.0)))
	var allied_hit := source != null and is_instance_valid(source) and source != self \
		and (source.is_in_group("enemies") or source.is_in_group("player_allies")) and source is Node2D
	var player = get_tree().get_first_node_in_group("player") if allied_hit else null
	var pipa_active := player != null and str(player.get("skull_id")) == "z002" and player.has_method("_own")
	if allied_hit and pipa_active and float(source.get("_charm_time")) > 0.0 and bool(player.call("_own", "z002_allure_3")):
		final *= 2
	take_damage(final, (source as Node2D).global_position.x if source is Node2D else global_position.x)
	if not allied_hit or not pipa_active or hp <= 0 or state == State.DEAD:
		return
	if float(source.get("_frenzy_time")) > 0.0:
		if bool(player.call("_own", "z002_chorus_2")):
			apply_frenzy(4.0)
		if bool(player.call("_own", "z002_chorus_3")):
			add_grudge(1)
			apply_six_senses(1)
	if float(source.get("_charm_time")) > 0.0 and bool(player.call("_own", "z002_allure_2")):
		source.set("_charm_time", minf(20.0, float(source.get("_charm_time")) + 1.0))


## 子类可覆写：结算前修正最终伤害（机关造物等被动的挂点）。
func _modify_outgoing_damage(dmg: int, _target: Node, _move: Dictionary) -> int:
	return dmg


## 特殊 Boss 自定义招式共用：怨降低每段伤害，强化癫狂翻倍；魅惑时绝不攻击玩家。
func _hit_status_target(target: Node, damage: int, knockback: Vector2, move: Dictionary) -> bool:
	if target == null or not is_instance_valid(target) or target == self:
		return false
	if player_ally and not target.is_in_group("enemies"):
		return false
	var dmg := 0 if damage <= 0 else Run.enemy_damage(damage)
	if dmg > 0:
		dmg = maxi(1, dmg - int(_grudge / 3.0))
		if _frenzy_time > 0.0 and _frenzy_empowered and not _evil_buddha_pressure:
			dmg *= 2
		dmg = _modify_outgoing_damage(dmg, target, move)
	if target.is_in_group("enemies"):
		if int(target.get("hp")) <= 0:
			return false
		var before := int(target.get("hp"))
		if target.has_method("take_damage_from"):
			target.call("take_damage_from", dmg, self)
		else:
			target.call("take_damage", dmg, global_position.x)
		var dealt := maxi(0, before - int(target.get("hp")))
		if dealt > 0:
			on_player_hit(dealt, move, target)
		return true
	if _charm_time > 0.0 or player_ally or not target.has_method("hurt"):
		return false
	target.call("hurt", dmg, knockback, self, move)
	return true


## 心魔引可转移所有玩家减益；能直接对应敌人状态的走原接口，其余保留层数与时长供再次引爆。
func apply_transferred_debuff(info: Dictionary) -> void:
	if state == State.DEAD:
		return
	var id := str(info.get("id", ""))
	var stacks := maxi(1, int(info.get("stacks", 1)))
	var duration := maxf(0.0, float(info.get("time", 0.0)))
	match id:
		"bleed", "cut", "fen_ding_burn": apply_bleed(stacks)
		"stun": stun(maxf(duration, 1.0), true)
		"jump_seal", "dash_seal", "cripple": root(maxf(duration, 1.0), true)
		_:
			var old: Dictionary = _transferred_debuffs.get(id, {"stacks": 0, "time": 0.0})
			old["stacks"] = int(old.get("stacks", 0)) + stacks
			old["time"] = maxf(float(old.get("time", 0.0)), duration)
			_transferred_debuffs[id] = old


func _pipa_status_tick(delta: float) -> void:
	if _stop_timer > 0.0:
		return # 时停冻结：狂乱/魅惑/心魔转移减益与拥有者一同暂停，解冻后从原值继续
	if _frenzy_time > 0.0:
		_frenzy_time = maxf(0.0, _frenzy_time - delta)
		if _frenzy_time <= 0.0:
			_frenzy_empowered = false
			_target = null
	if _charm_time > 0.0:
		_charm_time = maxf(0.0, _charm_time - delta)
		if _charm_time <= 0.0:
			_target = null
			if Run.skull_id == "z002" and Meta.has_form_node("z002_charm_3"):
				add_grudge(3)
	for id in _transferred_debuffs.keys():
		var info: Dictionary = _transferred_debuffs[id]
		if float(info.get("time", 0.0)) > 0.0:
			info["time"] = maxf(0.0, float(info["time"]) - delta)
			if float(info["time"]) <= 0.0:
				_transferred_debuffs.erase(id)
			else:
				_transferred_debuffs[id] = info
	_player_burn_tick(delta)


func _player_burn_interval() -> float:
	if _player_burn_stacks <= 0:
		return 0.0
	return float(PLAYER_BURN_INTERVALS[mini(_player_burn_stacks, PLAYER_BURN_INTERVALS.size()) - 1])


## 玩家夺取炽热之心后，实际命中只为目标叠怒焰；回血与刷新冷却由真实灼烧回报触发。
func apply_player_burn(source: Node) -> void:
	if state == State.DEAD or source == null or not is_instance_valid(source):
		return
	_player_burn_stacks += 1
	_player_burn_source = source
	_player_burn_left = _player_burn_interval()


func _player_burn_tick(delta: float) -> void:
	if _player_burn_stacks <= 0 or state == State.DEAD:
		return
	if not is_instance_valid(_player_burn_source):
		_player_burn_stacks = 0
		_player_burn_left = 0.0
		return
	_player_burn_left -= delta
	if _player_burn_left > 0.0:
		return
	var source := _player_burn_source
	var before := hp
	_direct_damage(1, Color(0.9, 0.38, 0.2))
	var dealt := maxi(0, before - hp)
	if dealt > 0 and is_instance_valid(source) and source.has_method("on_fen_ding_burn_hit"):
		source.call("on_fen_ding_burn_hit", dealt, self)
	if state != State.DEAD:
		_player_burn_left = _player_burn_interval()


## 邪佛压场封住敌方增益；强化癫狂立即失效，嗜血的伤害与回血也在压制期间停用。
func set_evil_buddha_pressure(active: bool) -> void:
	_evil_buddha_pressure = active
	if active:
		_frenzy_empowered = false


func _trigger_six_senses() -> void:
	if _six_senses <= 0 or state == State.DEAD:
		return
	var damage := _six_senses + int(Run.skull_id == "z002" and Meta.has_form_node("z002_grudge_3"))
	_direct_damage(damage, Color(0.62, 0.38, 0.72))


## 返回引爆前的增益/减益总层数；计时状态统一每 2 秒一层，向上取整。
func mind_status_count() -> int:
	var count := _grudge + _six_senses + _bleed_stacks + _mind_shock
	for time in [_poison_time, _frenzy_time, _charm_time, _root_timer, _stun_timer, _slow_timer, _vuln_timer, _stop_timer]:
		if float(time) > 0.0:
			count += int(ceilf(float(time) / 2.0))
	for id in _transferred_debuffs:
		var info: Dictionary = _transferred_debuffs[id]
		count += maxi(1, int(info.get("stacks", 1))) if float(info.get("time", 0.0)) <= 0.0 else int(ceilf(float(info["time"]) / 2.0))
	# 常驻正面状态也各算一层；特殊 Boss 可覆盖追加自己的独有增益。
	count += int(_regen_interval > 0.0) + int(_enraged) + int(_bloodthirst_active) + int(_skill_cooldown_scale < 1.0)
	return count


func detonate_mind(base_damage: int, source_x: float, preserve_senses := false) -> int:
	if state == State.DEAD:
		return 0
	var damage := base_damage + mind_status_count()
	var senses := _six_senses
	_clear_mind_statuses()
	take_damage(damage, source_x)
	if preserve_senses and hp > 0 and state != State.DEAD:
		_six_senses = senses
	return damage


func _clear_mind_statuses() -> void:
	_frenzy_time = 0.0
	_frenzy_empowered = false
	_charm_time = 0.0
	_grudge = 0
	_six_senses = 0
	_mind_shock = 0
	_transferred_debuffs.clear()
	_bleed_stacks = 0
	_bleed_time = 0.0
	_bleed_acc = 0.0
	_poison_time = 0.0
	_poison_acc = 0.0
	_vuln_timer = 0.0
	_vuln_ratio = 0.0
	_root_timer = 0.0
	_stun_timer = 0.0
	_slow_timer = 0.0
	_slow_scale = 1.0
	_end_stop()
	if _enraged:
		attack_cooldown /= _enrage_cd
		chase_speed /= _enrage_speed
	_enraged = false
	_enrage_below = 0.0
	_regen_interval = 0.0
	_regen_amount = 0
	_bloodthirst.clear()
	_bloodthirst_active = false
	_skill_cooldown_scale = 1.0
	_target = null


## 神伤：层数类 +1，计时类 +5 秒；心灵震撼与原有状态均不得突破各自上限。
func amplify_debuffs() -> void:
	if state == State.DEAD:
		return
	_mind_shock = 1
	if _bleed_stacks > 0:
		_bleed_stacks = mini(BLEED_MAX, _bleed_stacks + 1)
		_bleed_time += 5.0
	if _poison_time > 0.0:
		_poison_time += 5.0
	_root_timer += 5.0 if _root_timer > 0.0 else 0.0
	_stun_timer += 5.0 if _stun_timer > 0.0 else 0.0
	_slow_timer += 5.0 if _slow_timer > 0.0 else 0.0
	_vuln_timer += 5.0 if _vuln_timer > 0.0 else 0.0
	_stop_timer += 5.0 if _stop_timer > 0.0 else 0.0
	_frenzy_time += 5.0 if _frenzy_time > 0.0 else 0.0
	_charm_time += 5.0 if _charm_time > 0.0 else 0.0
	if _grudge > 0:
		_grudge += 1
	if _six_senses > 0:
		_six_senses += 1
	for id in _transferred_debuffs:
		var info: Dictionary = _transferred_debuffs[id]
		if float(info.get("time", 0.0)) > 0.0:
			info["time"] = float(info["time"]) + 5.0
		else:
			info["stacks"] = int(info.get("stacks", 1)) + 1
		_transferred_debuffs[id] = info


# ---------- 银夜机制接口：击飞 / 击退 / 时间暂停 ----------

## Boss 词条默认规则：非普攻招式出手期间不可被任何控制打断。
## 由 boss.gd 与各独立状态机 Boss 覆写；时停是规则级接口，不受这里保护。
func _is_uninterruptible() -> bool:
	return false


## 时间暂停分档：杂兵 mob / 精英 elite；Boss 在 boss.gd 覆盖为 boss
func stop_tier() -> String:
	return "elite" if _elite else "mob"


## 血色切割与魅唤共用实体被动包；未来化身/PvP 也提交同一结构，无需伪装敌人死亡。
func export_passives() -> Dictionary:
	var passives: Array = []
	match type_id:
		"c016": passives = ["c016_mountain"]
		"c017": passives = ["c017_brute"]
		"c035": passives = ["c035_shadow"]
		"c018": passives = ["c018_bloodthirst"]
		"c012": passives = ["c012_sword_intent"]
		"c037": passives = ["c037_burst"]
		"c009": passives = ["c009_construct", "c009_madness"]
		"c015a1": passives = ["c015a1_flame_bone", "c015a1_burning_heart"]
		"c001": passives = ["c001_faith", "c001_era"]
		"c008": passives = ["c008_bell", "c008_evil_buddha"]
		"c032": passives = ["c032_war_god", "c032_divine_favor"]
	return {
		"type_id": type_id,
		"tier": stop_tier(),
		"passives": passives,
		"scene": scene_file_path,
		"script": get_script().resource_path,
	}


## 时间暂停（银夜 U）：定住 dur 秒。无视霸体与出手霸体——前摇一律打断，
## 动画整只冻结（停掉 SpineSprite 的逐帧推进，视觉上就是定格），期间挨打照掉血但不断定身
func time_stop(dur: float) -> void:
	if state == State.DEAD:
		return
	if not _is_sword_clone:
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
	_sync_status_fx_processing()
	if not _is_sword_clone and is_instance_valid(_sword_clone_node):
		_sword_clone_node.call("time_stop", dur)


func _end_stop(natural := false) -> void:
	var was_stopped := _stop_timer > 0.0
	_stop_timer = 0.0
	if sprite != null and is_instance_valid(sprite):
		sprite.process_mode = Node.PROCESS_MODE_INHERIT
	_sync_status_fx_processing()
	if natural and was_stopped:
		var pl = get_tree().get_first_node_in_group("player")
		if pl != null and pl.has_method("on_time_stop_end"):
			pl.call("on_time_stop_end", self)


# ---------- 绯刃机制接口：定身 / 流血 ----------

## 定身（绯刃 U 掷匕）：dur 秒内不能移动，但可以照常出手攻击。
## 打断巡逻/追击移动，已在挥的招照打完（不可以攻击的控制要另开接口，别混用）
func root(dur: float, _ignore_armor := false) -> void:
	if state == State.DEAD or dur <= 0.0 or _is_uninterruptible() or (_super_armor and not _ignore_armor):
		return
	_root_timer = maxf(_root_timer, dur)
	_flash()
	var dn := DAMAGE_NUMBER.new()
	dn.setup("定身", Color(0.9, 0.75, 0.3)) # 金：和完美闪避同色系的"控制生效"提示
	dn.global_position = global_position + Vector2(0, _number_y - 18.0)
	_world_add(dn)


## 枝界持续约束：每帧只延续定身计时，不重复控制反馈。
func contain(dur: float, _ignore_armor := false) -> void:
	if state == State.DEAD or dur <= 0.0 or _is_uninterruptible() or (_super_armor and not _ignore_armor):
		return
	_root_timer = maxf(_root_timer, dur)


## 余滞：最新一次有效调用覆盖时长与倍率；只影响常规横向移动和出手前冲。
func slow(dur: float, scale: float, _ignore_armor := false) -> void:
	if state == State.DEAD or dur <= 0.0 or (_super_armor and not _ignore_armor):
		return
	_slow_timer = dur
	_slow_scale = clampf(scale, 0.0, 1.0)


## 晕眩（镇岳 L）：dur 秒内不能移动、也不能出手——比定身更强。
## 立即打断正在起的招（前摇直接掐掉，交还出手令牌），站桩发愣到时间结束；
## 被打飞/受击照样推进各自状态，落地后仍保持晕眩。
func stun(dur: float, _ignore_armor := false) -> void:
	if state == State.DEAD or dur <= 0.0 or _is_uninterruptible() or (_super_armor and not _ignore_armor):
		return
	_clear_attack_chain()
	_stun_timer = maxf(_stun_timer, dur)
	_root_timer = 0.0 # 晕眩覆盖定身：更强的控制接管
	if not _is_sword_clone:
		_release_token()
	_attack_hits_left.clear()
	if state == State.ATTACK:
		state = State.IDLE
		velocity = Vector2.ZERO
		_idle_queued = false
		_play(str(_anim_map["idle"]), true)
	if not _is_sword_clone and is_instance_valid(_sword_clone_node):
		_sword_clone_node.call("stun", dur, true)
	_flash()
	var dn := DAMAGE_NUMBER.new()
	dn.setup("晕眩", Color(0.62, 0.78, 0.95)) # 淡蓝：和定身的金色区分开
	dn.global_position = global_position + Vector2(0, _number_y - 18.0)
	_world_add(dn)


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


## 流血（绯刃 L 裂帛）：叠层后每秒按层数直扣血，不触发硬直/白闪，也不打断出手
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
	if _stop_timer > 0.0:
		return # 时停冻结：流血时长不流逝，解冻后继续
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
	var newly_poisoned := _poison_time <= 0.0
	_poison_time = maxf(_poison_time, dur)
	if not newly_poisoned:
		return # 重复命中只刷新时长，不再重复播放音效与飘出「中毒」
	if _sfx_player != null:
		_sfx_player.stream = SFX_POISON
		_sfx_player.play()
	var dn := DAMAGE_NUMBER.new()
	dn.setup("中毒", POISON_LABEL_COLOR)
	dn.global_position = global_position + Vector2(0, _number_y - 18.0)
	_world_add(dn)


func _poison_tick(delta: float) -> void:
	if _stop_timer > 0.0:
		return # 时停冻结：中毒时长与跳毒累计都不推进，解冻后继续
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


## 易伤（剑仙 L 斩焰）：持续期间承受的所有伤害按 ratio 放大；比例取最高，时长取最长。
func apply_vulnerable(dur: float, ratio: float) -> void:
	if state == State.DEAD or dur <= 0.0 or ratio <= 0.0:
		return
	_vuln_ratio = maxf(_vuln_ratio, ratio)
	_vuln_timer = maxf(_vuln_timer, dur)
	var dn := DAMAGE_NUMBER.new()
	dn.setup("易伤 +%d%%" % int(round(ratio * 100.0)), Color(0.86, 0.45, 0.2))
	dn.global_position = global_position + Vector2(0, _number_y - 18.0)
	_world_add(dn)


func _vuln_tick(delta: float) -> void:
	if _stop_timer > 0.0:
		return # 时停冻结：易伤时长不流逝，解冻后继续
	if _vuln_timer <= 0.0 or state == State.DEAD:
		return
	_vuln_timer = maxf(0.0, _vuln_timer - delta)
	if _vuln_timer <= 0.0:
		_vuln_ratio = 0.0


## 承伤倍率：供攻击方在结算前把原始伤害换算成最终伤害，避免与 take_damage 内部重复放大。
func damage_taken_scale() -> float:
	return 1.0 + (_vuln_ratio if _vuln_timer > 0.0 else 0.0)


## 山民：计时始终推进，到点有伤才回血；满血不会越界，也不会囤出额外治疗次数。
func _regen_tick(delta: float) -> void:
	if _stop_timer > 0.0:
		return # 时停冻结：回血节奏与拥有者一同暂停，解冻后继续
	if _regen_interval <= 0.0 or _regen_amount <= 0 or state == State.DEAD:
		return
	_regen_timer -= delta
	if _regen_timer > 0.0:
		return
	_regen_timer = _regen_interval
	if hp >= max_hp:
		return
	_heal(_regen_amount)


## 非打击伤害（流血/中毒等）：直接扣血，不进硬直，但仍走死亡流程；Boss 覆盖以同步阶段/大血条
func _direct_damage(amount: int, color: Color = DMG_COLOR) -> void:
	if state == State.DEAD or amount <= 0:
		return
	if _vuln_timer > 0.0 and _vuln_ratio > 0.0:
		amount = maxi(1, int(round(float(amount) * damage_taken_scale()))) # 流血/中毒等内部持续伤害同样吃易伤
	hp -= amount
	_spawn_number(amount, color)
	_update_hp_bar()
	if hp <= 0:
		_end_stop()
		die()
		return
	_check_limit()


## 砸落（银夜空中派生）：直线下坠，落地只向玩家回报一次，再接原有落地硬直。
func slam(_ignore_armor := false) -> void:
	if state == State.DEAD or _stop_timer > 0.0 or _is_uninterruptible() or (not _ignore_armor and (_super_armor \
			or (state == State.ATTACK and bool(_poise_anims.get(_attack_move, false))))):
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


## 击飞（银夜普攻二段 / 剑仙 U 飞脚）：向上挑起，落地短暂硬直。
## 普通击飞尊重全程霸体与当前招式的出手霸体；ignore_armor 可穿透两者，但不能穿透时停。
func launch(dir: int, vx: float, vy: float, _ignore_armor := false) -> void:
	if state == State.DEAD or _is_uninterruptible() or (not _ignore_armor and (_super_armor \
			or (state == State.ATTACK and bool(_poise_anims.get(_attack_move, false))))):
		return
	_enter_fly(Vector2(dir * vx, -vy), 0)


## 击退（银夜 L / 剑仙 O）：横向轰飞，途中撞到同伴双方各吃 impact 组合伤害，撞墙自己再吃一下。
## 普通击退与击飞共用霸体规则；时停期间任何击退都不能改写冻结状态。
func knock_back(dir: int, force: float, impact: int, _ignore_armor := false) -> void:
	if state == State.DEAD or _is_uninterruptible() or (not _ignore_armor and (_super_armor \
			or (state == State.ATTACK and bool(_poise_anims.get(_attack_move, false))))):
		return
	_enter_fly(Vector2(dir * force, -120.0), impact)


func _enter_fly(v: Vector2, impact: int) -> void:
	if _stop_timer > 0.0:
		return # 时停优先于所有后续物理控制：不解除冻结、不播受击动画、不改速度
	_clear_attack_chain()
	_attack_hits_left.clear()
	_release_token()
	_slam_pending = false # 普通 launch / knock_back 不继承上一次砸落回报
	_root_timer = 0.0 # 被轰飞时解除普通定身，但不能解除时停
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
		var pl = get_tree().get_first_node_in_group("player")
		if pl != null and pl.has_method("on_knock_landing"):
			pl.call("on_knock_landing", self)
		state = State.HURT
		_hurt_timer = 0.3


func take_damage(amount: int, source_x: float) -> void:
	if state == State.DEAD or _is_sword_clone:
		return
	# 时停中挨打：伤害/数字/白闪照给，但不进硬直、不解定身；打死则先解冻再走死亡流程
	if _stop_timer > 0.0:
		hp -= amount
		_sfx_player.stream = SFX_HIT_FAN if _elite else SFX_HIT_QI
		_sfx_player.play()
		_spawn_number(amount)
		_update_hp_bar()
		if hp <= 0:
			_end_stop()
			die()
			return
		_check_limit() # 时停中只回满并排入等待，解冻前不得实际起手
		return
	hp -= amount
	_sfx_player.stream = SFX_HIT_FAN if _elite else SFX_HIT_QI
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
	# 断楹祭剑：严格低于半血才触发；回满并取消当前受击/出手，每个实体仅一次。
	if _check_limit():
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
	# 高伤倒地优先于招式霸体；普通受击仍按抗性分层，未达阈值时只掉血不断招。
	var knock_hit := not _knock_chain.is_empty() and (amount > _knock_at if _knock_strict else amount >= _knock_at)
	if not knock_hit and (_super_armor or amount < _armor or (state == State.ATTACK and bool(_poise_anims.get(_attack_move, false)))):
		_flash()
		return
	_clear_attack_chain()
	_attack_hits_left.clear()
	_release_token() # 被打断的出手要交还令牌，否则其他怪永远等不到出手机会
	var dir := 1.0 if global_position.x >= source_x else -1.0
	if knock_hit:
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
	dn.setup(str(amount), color, amount)
	dn.global_position = global_position + Vector2(randf_range(-12.0, 12.0), _number_y)
	_world_add(dn)


func die() -> void:
	_end_stop() # 时停中被打死：先解冻，死亡动画才播得出来
	_dismiss_sword_clone()
	state = State.DEAD
	_clear_status_effects()
	_limit_pending = false
	_clear_attack_chain()
	_attack_hits_left.clear()
	_hurt_chain_active = false
	_hurt_chain.clear()
	_release_token()
	velocity = Vector2.ZERO
	_update_hp_bar()
	$CollisionShape2D.set_deferred("disabled", true)
	var bursting := not _death_burst.is_empty()
	if not bursting:
		_play(str(_anim_map["dead"]), false)
	if not player_ally:
		Meta.add_kill(Run.skull_id) # 局外养成：累计击杀 + 当前形态契合
		Meta.add_enemy_kill(type_id) # 图鉴：这只敌人（Boss 也走这里）被击败一次，收录 +1
		Score.add_kill() # 本局击杀计数（结算战绩用）
		Achievements.note_enemy_killed(type_id, stop_tier() == "elite")
		var pl = get_tree().get_first_node_in_group("player")
		if pl != null and pl.has_method("on_enemy_killed"):
			pl.call("on_enemy_killed", self)
	if bursting:
		_magic_explosion() # died 必须等最后一击结束，波次才不会提前结算
	else:
		died.emit()
		_cleanup()


## 魔爆：起身后完成 22 号变身，再以巨兽整体前扑回斩补齐原动画缺少的最后一击。
func _magic_explosion() -> void:
	var getup := str(_death_burst.get("getup", ""))
	if not getup.is_empty():
		_play(getup, false)
		await get_tree().create_timer(float(_anim_durations.get(getup, 0.8))).timeout
	var transform := str(_death_burst.get("anim", "transform"))
	_play(transform, false)
	await get_tree().create_timer(float(_anim_durations.get(transform, 3.467))).timeout
	var start_x := global_position.x
	var lunge := float(_death_burst.get("lunge", 96.0))
	var slash := create_tween()
	slash.set_parallel(true)
	slash.tween_property(sprite, "rotation", -facing * 0.22, 0.14).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	slash.tween_property(self, "global_position:x", start_x + facing * lunge, 0.14).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	await get_tree().create_timer(0.14).timeout
	_deal_death_burst()
	var recover := create_tween()
	recover.set_parallel(true)
	recover.tween_property(sprite, "rotation", 0.0, 0.26)
	recover.tween_property(self, "global_position:x", start_x, 0.26)
	await get_tree().create_timer(0.30).timeout
	died.emit()
	_cleanup()


func _death_target_in_front(t: Node2D) -> bool:
	var dx := t.global_position.x - global_position.x
	var in_front := dx == 0.0 or (dx > 0.0) == (facing > 0)
	return in_front and absf(dx) <= float(_death_burst.get("range", 480.0)) + _radius_of(t) \
		and absf(t.global_position.y - global_position.y) <= float(_death_burst.get("height", 240.0))


func _deal_death_burst() -> void:
	var damage := int(_death_burst.get("damage", 3))
	_attack_cast_id += 1
	var move := {"anim": str(_death_burst.get("anim", "transform")), "hit_at": 3.467,
		"cast_id": _attack_cast_id, "seg": 0, "room_cd_curse": true}
	var pl = get_tree().get_first_node_in_group("player")
	if not player_ally and pl != null and pl is Node2D and _death_target_in_front(pl) and pl.has_method("hurt"):
		pl.call("hurt", damage, Vector2(facing * 420.0, -60.0), self, move)
	for e in get_tree().get_nodes_in_group("enemies"):
		if e == self or not is_instance_valid(e) or not e is Node2D or int(e.get("hp")) <= 0:
			continue
		if not _death_target_in_front(e) or not e.has_method("take_damage"):
			continue
		var before := int(e.get("hp"))
		e.call("take_damage", damage, global_position.x)
		if int(e.get("hp")) < before and int(e.get("hp")) > 0 and e.has_method("apply_room_cd_curse"):
			e.call("apply_room_cd_curse")
	# 魔爆：火焰爆裂与实伤同帧生成，落点取前扑判定区中心。
	# 尺寸按可见爆裂整体约等于前扑判定宽度（480）来定，而不是放大到整块骨架；
	# E54148 的可见爆裂主体比骨架原点低约 100 骨架单位（素材固有），固定补偿这段高度：
	# 不用包围盒逐帧贴地，否则火焰柱阶段包围盒变化会把整团特效上下拽动。
	var burst_range := float(_death_burst.get("range", 480.0))
	var burst_fx_scale := _scale * 0.85
	_death_burst_fx = SpineFX.spawn(get_tree().current_scene, "E54148",
		global_position + Vector2(facing * burst_range * 0.5, 0.0),
		{"anim": "action", "scale": burst_fx_scale,
		"offset": Vector2(0.0, -100.0 * burst_fx_scale), "flip": facing < 0, "z": 6})
	if _death_burst_fx != null:
		_death_burst_fx.set_meta("fx_id", "E54148")
	Feel.shake(12.0, 0.35)


func _exit_tree() -> void:
	_clear_status_effects()
	if not _is_sword_clone:
		_dismiss_sword_clone()


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
	if player_ally:
		var nearest_enemy: Node2D = null
		var nearest_enemy_dist := INF
		for e in get_tree().get_nodes_in_group("enemies"):
			var p := e as Node2D
			if p == null or p == self or int(e.get("hp")) <= 0:
				continue
			var dist := global_position.distance_squared_to(p.global_position)
			if dist < nearest_enemy_dist:
				nearest_enemy = p
				nearest_enemy_dist = dist
		_target = nearest_enemy
		return
	# 魅惑时只认敌方同伴；癫狂则连自己原本的玩家阵营也算进最近目标。
	# 两者同时存在时，魅惑的"绝不攻击玩家"优先。
	if _charm_time > 0.0 or _frenzy_time > 0.0:
		var chosen: Node2D = null
		var chosen_dist := INF
		for e in get_tree().get_nodes_in_group("enemies"):
			var p := e as Node2D
			if p == null or p == self or int(e.get("hp")) <= 0:
				continue
			var dist := global_position.distance_squared_to(p.global_position)
			if dist < chosen_dist:
				chosen = p
				chosen_dist = dist
		if _charm_time <= 0.0:
			for group in ["player", "player_decoy"]:
				for node in get_tree().get_nodes_in_group(group):
					var p := node as Node2D
					if p == null or (group == "player" and int(node.get("state")) == 8):
						continue
					var dist := global_position.distance_squared_to(p.global_position)
					if dist < chosen_dist:
						chosen = p
						chosen_dist = dist
		_target = chosen
		return
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


## 出手令牌：同一时刻只放一只小怪出手；持有者被受击打断/死亡也要释放。
## 交棒后 0.26 秒内无人可接手，形成「一只打完、另一只再上」的围攻节奏。
func _can_attack() -> bool:
	if _attacker == self:
		return true
	if _attacker != null and is_instance_valid(_attacker):
		return false
	return Time.get_ticks_msec() >= _token_free_at


func _release_token() -> void:
	if _attacker == self:
		_attacker = null
		_token_free_at = Time.get_ticks_msec() + 260


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
	if _charm_time > 0.0 or _frenzy_time > 0.0:
		return true
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
				_play(_idle_anim(), true)
			_idle_queued = false
		State.PATROL:
			_idle_queued = false
			var anim := str(_bloodthirst.get("move", _anim_map["patrol"])) if _bloodthirst_weak() else str(_anim_map["patrol"])
			_play(anim, true)
		State.CHASE:
			_idle_queued = false # set_animation 会清掉队列里的 stand
			var anim := str(_bloodthirst.get("move", _anim_map["chase"])) if _bloodthirst_weak() else str(_anim_map["chase"])
			_play(anim, true, _chase_anim_speed)


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
