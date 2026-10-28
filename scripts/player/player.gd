class_name Player
extends CharacterBody2D

## 玩家控制器 · 形态数据见 scripts/player/skulls.gd
## 每个形态自带骨架 / 缩放 / 动画名映射 / 普攻段 / 技能表，换头时按 profile 重建 SpineSprite。
## 缩放按"游戏内角色高 128px"反推，换头不会突然变大变小。

const DAMAGE_NUMBER := preload("res://scripts/ui/damage_number.gd")
const Skulls := preload("res://scripts/player/skulls.gd")
const PROJECTILE := preload("res://scripts/systems/projectile.gd") # 远程形态的普攻/技能发投射物
const FX := preload("res://scripts/systems/fx.gd") # 精灵条特效：斩击/化身光柱/受击墨花
const DMG_COLOR := Color(0.18, 0.36, 0.43) # 石青：玩家受伤数字

## 换头消耗的墨骨数
const SWAP_COST := 8

## 技能 action -> HUD 按键字母
const KEY_LABELS := {"skill": "K", "skill_sweep": "L", "skill_ult": "U", "skill_i": "I", "skill_o": "O"}

## 技能配置里 hits.at 是动画开始后多少秒判定命中，按逐帧截图标定：
## skill01：0.75s 前冲突刺后起跳隐身（0.75~1.28s 闪现位移+无敌），1.30s 现身一刀，path=沿闪现路径全判。
## skill03：1.0s 平刺一段，2.0s 双手分枪横扫一段（大范围）。
## skill04：举枪过顶连斩，1.2/2.1/3.0s 各一段。
## 锁定时长用动画真实时长（_skill_durations 运行时查表），不用手填。
## 音效命名：audio/sfx/<名字>.wav，_sfx_cache 里缓存后直接播
const SFX_BASE := "res://audio/sfx/"
const SFX_PRECACHE := [
	"weapon_sword",   # 普攻起手（挥剑嗖）
	"voice_sword_hit",# 普攻命中（咔劈肉）
	"voice_skill_cast",# 技能起手通用（嗡）
	"hit_heavy",      # skill01 突刺命中
	"skill_fist",     # skill03 第一段平刺
	"voice_fan_hit",  # skill03 第二段横扫
	"skill_blade",    # skill04 长连段（落叶镖）
	"hit_fist",       # 玩家受伤
	"dash_step",      # 冲刺脚步（踏地）
]

@export var run_speed := 240.0
@export var accel := 2200.0    # 启动加速度（"踩油门"）
@export var brake := 5200.0    # 制动减速度（"松油门 + 刹"，比启动快得多）
@export var turn_accel := 3000.0 # 反向转向加速度（比同方向启动略快）
@export var gravity := 2000.0
@export var max_fall_speed := 900.0
@export var jump_velocity := -640.0
@export var coyote_time := 0.10
@export var jump_buffer := 0.12
@export var dash_speed := 560.0
@export var dash_time := 0.16
@export var dash_cooldown := 0.45
@export var hurt_time := 0.35
@export var max_hp := 8

signal hp_changed(current: int, maximum: int)
signal died
signal skull_changed(id: String)

enum State { IDLE, RUN, JUMP, FALL, DASH, ATTACK, SKILL, HURT, DEAD }
var state: int = State.IDLE
var facing := 1 # 1 朝右，-1 朝左
var hp: int

# ---------- 当前形态（由 Skulls.SKULLS 表注入，换头时整组替换） ----------
var skull_id := Skulls.DEFAULT_ID
var anim_map: Dictionary = {} # idle/run/dash/air/hurt/dead/getup -> Spine 动画名
var attacks: Array = [] # 普攻段表：{anim, lock, hits, damage, range, lunge}
var skill_config: Dictionary = {} # 技能名 -> {action, cooldown, hits...}
var hud_skills: Array = [] # HUD 技能栏顺序（K/L/U 依次）
var base_scale := 0.394 # 骨架缩放，按形态反推

# ---------- 局内强化（Run.upgrades 注入，换房间保留） ----------
var damage_bonus := 0 # 全部伤害 +N
var cooldown_scale := 1.0 # 技能冷却倍率
var swap_cost := SWAP_COST # 换头消耗墨骨

var _coyote := 0.0
var _jump_buf := 0.0
var _dash_timer := 0.0
var _dash_cd := 0.0
var _attack_idx := -1
var _attack_timer := 0.0
var _attack_queued := false
var _attack_hits: Array = [] # 本段普攻剩余待结算的命中时刻（动画秒），按升序弹出
var _hurt_timer := 0.0
var _hurt_invincible := 0.0 # 受伤后的短暂无敌：被围殴时不会一帧连掉好几血
var _mastery_cd := 1.0 # 契合 Lv1：该形态技能冷却倍率
var _mastery_dmg := 0 # 契合 Lv2：该形态普攻加伤
var body_radius := 30.0 # 受击半径：挨打按"攻击方射程 + 本半径"判定（与小怪/Boss 同一规则）
# ---------- 形态专属强化（Run.upgrades 的 form_* 键注入，换房间随 set_upgrades 重算） ----------
var range_scale := 1.0 # 攻击范围倍率（横扫/阔剑/裂地/连突）
var proj_extra := 0 # 投射物额外齐发数（双剑气）
var proj_pierce := false # 投射物穿透（穿云剑气）
var skill_lifesteal := false # 技能命中回血（饮血）
var poise := false # 技能期间霸体（定山）
var _skill_poise := false # 当前技能自带的霸体（力僧定山：蓄力期间自身霸体，不依赖强化）
var _skill_reflect := false # 当前技能自带的反伤（力僧定山：技能期间无敌，伤害原样弹回攻击者）
var _skill_ranged_guard := false # 当前技能的远程格挡（梅剑转鞭：技能期间免疫并反弹敌方投射物）
var _skill_tick_acc := 0.0 # 技能持续伤害段的计时累计（每 interval 秒结算一次）
# ---------- 银夜·将去未还专属机制（形态表注入，其他形态全为默认值=关闭） ----------
var _qg_jump_mul := 1.0 # 轻功：跳跃初速倍率（明显跳得更高）
var _qg_hover := 0.0 # 轻功：跃过顶点后空中滞留时长
var _hover_left := 0.0 # 本次跳跃剩余悬停时间
var _buff_damage := 0 # 觉醒（I）：限时内全伤害 +N
var _buff_timer := 0.0 # 觉醒剩余时间
var _attack_anim := "" # 本段普攻实际抽中的动画（随机池段用）
var _attack_lock := 0.0 # 本段普攻的锁定时长（随机池段 = 抽中动画的真实时长）
var _attack_durations := {} # 普攻动画名 -> 真实时长（随机池段的 lock = 抽中动画的时长）
var _skill_anim := "" # 本次技能实际播放的动画（随机池技能用）
var _skill_speed := 1.0 # 本次技能的动画播放速度倍率（<1 慢放，时刻表按动画时间对齐）
var _dash_anim_speed := 1.0 # dash 动画播放速度倍率（形态表 dash_anim_speed，短动画慢放填满冲刺窗口）
var _skill_teleport := 0.0 # 技能抽到自带位移动画（银夜 O 的 #87）：原地播放，收招瞬间瞬移这段距离
var _stop_done := false # 时停（U）本场已触发
var _lifesteal_cd := 0.0 # 饮血内置冷却
var _skill_name := ""
var _skill_timer := 0.0
var _skill_dur := 0.0 # 本次技能动画真实时长
var _skill_hits: Array = [] # 尚未结算的命中段（按 at 升序，逐个弹出）
var _skill_start_x := 0.0 # 技能起手 x，path 命中判定的路径起点
var _skill_cds := {} # 技能名 -> 剩余冷却
var _skill_durations := {} # 技能名 -> 动画真实时长，setup 时缓存
var _invincible := false # 闪现段无敌
var _blink_active := false # 闪现段与敌人的碰撞例外已开启
var _idle_queued := false # stand 已排队在技能后面，切 IDLE 时别重复 set（重开会重开淡化）

var sprite: Node2D # SpineSprite（GDExtension 类，用 ClassDB 创建）
var _anim_state # SpineAnimationState
var _current_anim := "" # 防同名动画重放（floated 在跳跃顶点重放会抽搐）
var _sfx_player: AudioStreamPlayer
var _sfx_cache: Dictionary = {}


func _ready() -> void:
	add_to_group("player")
	hp = max_hp
	_apply_profile(skull_id)
	_setup_spine()
	_setup_sfx()


## 把形态表里的动画映射 / 普攻段 / 技能表 / HUD 顺序装到实例上
func _apply_profile(id: String) -> void:
	var profile: Dictionary = Skulls.get_profile(id)
	# 局外养成的契合度加成随形态一起装上（Meta 是 autoload，测试场景里也在）
	var mods: Dictionary = Meta.mods(id)
	_mastery_cd = float(mods["cd"])
	_mastery_dmg = int(mods["damage"])
	skull_id = id if Skulls.SKULLS.has(id) else Skulls.DEFAULT_ID
	anim_map = profile["anim"]
	attacks = profile["attacks"]
	skill_config = profile["skills"]
	hud_skills = profile["hud_skills"]
	base_scale = float(profile["scale"])
	body_radius = float(profile.get("body_radius", 30.0)) # 形态表可按体型覆盖（未来大型化身）
	# 轻功（银夜）：没有该配置的形态倍率 1.0、不悬停，手感不受影响
	var qg: Dictionary = profile.get("qinggong", {})
	_qg_jump_mul = float(qg.get("jump_mul", 1.0))
	_qg_hover = float(qg.get("hover", 0.0))
	_dash_anim_speed = float(profile.get("dash_anim_speed", 1.0)) # 短冲刺动画可慢放（银夜 autorush 只有 0.083s）


## 局内强化注入：伤害/移速/冷却/生命上限/换头费用。换房间时由 Run.apply_to 重新调用
func set_upgrades(up: Dictionary) -> void:
	var spd := int(up.get("speed", 0))
	var cd := int(up.get("cooldown", 0))
	var sw := int(up.get("swap", 0))
	damage_bonus = int(up.get("damage", 0))
	run_speed = 240.0 * (1.0 + 0.12 * spd)
	cooldown_scale = maxf(0.55, 1.0 - 0.15 * cd)
	swap_cost = maxi(2, SWAP_COST - 3 * sw)
	max_hp = 8 + int(up.get("hp", 0))
	# 形态专属强化消费：先归零再按已购键逐个装上（换房间重注入，表外键直接忽略）
	range_scale = 1.0
	proj_extra = 0
	proj_pierce = false
	skill_lifesteal = false
	poise = false
	for k in up:
		match str(k):
			"form_drink_blood": skill_lifesteal = true # 双刺·饮血
			"form_wide_sweep": range_scale *= 1.35 # 双刺·横扫
			"form_calm": cooldown_scale *= 0.8 # 梅剑·清心
			"form_broad_sword": range_scale *= 1.3 # 梅剑·阔剑
			"form_poise": poise = true # 力僧·霸体
			"form_quake": range_scale *= 1.4 # 力僧·裂地
			"form_pierce": proj_pierce = true # 剑仙·穿云
			"form_twin": proj_extra += 1 # 剑仙·双剑气


func _setup_sfx() -> void:
	_sfx_player = AudioStreamPlayer.new()
	add_child(_sfx_player)
	for n in SFX_PRECACHE:
		var r := load(SFX_BASE + n + ".wav")
		if r != null:
			_sfx_cache[n] = r
		else:
			push_error("Player SFX not found: " + SFX_BASE + n + ".wav")


func _play_sfx(sfx_name: String) -> void:
	var s = _sfx_cache.get(sfx_name)
	if s != null:
		_sfx_player.stream = s
		_sfx_player.play()


func _setup_spine() -> void:
	var profile: Dictionary = Skulls.get_profile(skull_id)
	var data_path := str(profile["data"])
	var data = load(data_path)
	if data == null or not data.call("is_skeleton_data_loaded"):
		push_error("Player: 骨架数据加载失败 " + data_path)
		return
	# 换头时先把旧骨架拆掉，避免两套骨架同时在场
	if sprite != null and is_instance_valid(sprite):
		sprite.queue_free()
		sprite = null
		_anim_state = null
	sprite = ClassDB.instantiate("SpineSprite")
	add_child(sprite)
	sprite.set("skeleton_data_res", data)
	data.call("set_default_mix", 0.2) # 切换混合 0.1->0.2，收招/起步过渡更柔
	sprite.scale = Vector2(base_scale * facing, base_scale)
	_anim_state = sprite.call("get_animation_state")
	# 缓存技能动画真实时长，技能锁定必须按实际时长走（C016 的教训：手填时长收招会抽搐）
	# 随机池技能（银夜 I/O）：池里每个动画都要缓存，时长按抽中的那个走
	_skill_durations.clear()
	_skill_cds.clear()
	for n in skill_config:
		var names: Array = skill_config[n].get("pool", [n])
		for an in names:
			var a = data.call("find_animation", str(an))
			if a != null:
				_skill_durations[str(an)] = a.call("get_duration")
			else:
				push_error("Player: 技能动画不存在 " + str(an))
		_skill_cds[n] = 0.0
	# 普攻随机池（银夜三段）：抽中哪段动画，锁定时长就是哪段的真实时长
	_attack_durations.clear()
	for atk in attacks:
		for an in atk.get("pool", [atk.get("anim", "")]):
			var an_str := str(an)
			if an_str == "" or _attack_durations.has(an_str):
				continue
			var aa = data.call("find_animation", an_str)
			if aa != null:
				_attack_durations[an_str] = aa.call("get_duration")
			else:
				push_error("Player: 普攻动画不存在 " + an_str)
	_current_anim = ""
	_play(anim_map["idle"], true)


func _physics_process(delta: float) -> void:
	_coyote = maxf(0.0, _coyote - delta)
	_jump_buf = maxf(0.0, _jump_buf - delta)
	_dash_cd = maxf(0.0, _dash_cd - delta)
	_hurt_invincible = maxf(0.0, _hurt_invincible - delta)
	_lifesteal_cd = maxf(0.0, _lifesteal_cd - delta) # 饮血内置冷却
	_buff_timer = maxf(0.0, _buff_timer - delta) # 觉醒 buff 倒计时
	for n in _skill_cds:
		_skill_cds[n] = maxf(0.0, _skill_cds[n] - delta)
	if is_on_floor():
		_coyote = coyote_time
	if Input.is_action_just_pressed("jump"):
		_jump_buf = jump_buffer
	if Input.is_action_just_pressed("swap_skull"):
		_try_swap_skull()

	match state:
		State.IDLE, State.RUN:
			_ground_move(delta)
		State.JUMP, State.FALL:
			_air_move(delta)
		State.DASH:
			_dash_tick(delta)
		State.ATTACK:
			_attack_tick(delta)
		State.SKILL:
			_skill_tick(delta)
		State.HURT:
			_hurt_tick(delta)
		State.DEAD:
			velocity.x = 0.0

	if state != State.DASH:
		# 轻功悬停（银夜）：跃过顶点后滞留一小段，期间不落——velocity.y 快归零时触发
		if _hover_left > 0.0 and (state == State.JUMP or state == State.FALL) and velocity.y > -60.0:
			_hover_left -= delta
			velocity.y = 0.0
		else:
			velocity.y = minf(velocity.y + gravity * delta, max_fall_speed)
	move_and_slide()
	_post_move()


# ---------- 各状态逻辑 ----------

func _ground_move(delta: float) -> void:
	var dir := Input.get_axis("move_left", "move_right")
	if dir != 0.0:
		var target := dir * run_speed
		var acc := accel if signf(velocity.x) == dir else turn_accel # 反向转弯给更大加速度，避免"踩住刹车"的粘滞
		facing = 1 if dir > 0.0 else -1
		_apply_facing()
		velocity.x = move_toward(velocity.x, target, acc * delta)
		_set_state(State.RUN)
	else:
		# 松油门立刻重刹，跟动作游戏的手感走——停下比起步快
		velocity.x = move_toward(velocity.x, 0.0, brake * delta)
		_set_state(State.IDLE)
	_try_jump()
	_try_dash()
	if Input.is_action_just_pressed("attack"):
		_start_attack(0)
	else:
		_try_skill()


func _air_move(delta: float) -> void:
	var dir := Input.get_axis("move_left", "move_right")
	if dir != 0.0:
		facing = 1 if dir > 0.0 else -1
		_apply_facing()
		velocity.x = move_toward(velocity.x, dir * run_speed, accel * 0.7 * delta)
	else:
		# 空中松油门轻微制动，比地面刹得慢（不锁死空中控制）
		velocity.x = move_toward(velocity.x, 0.0, brake * 0.4 * delta)
	_try_dash()


func _dash_tick(delta: float) -> void:
	_dash_timer -= delta
	velocity = Vector2(facing * dash_speed, 0.0)
	if _dash_timer <= 0.0:
		_dash_cd = dash_cooldown
		velocity.x = facing * run_speed * 0.5
		_set_state(State.IDLE if is_on_floor() else State.FALL)


func _attack_tick(delta: float) -> void:
	_attack_timer -= delta
	# 攻击期间继续减速 lunge，用比地面略低的制动让前冲带"惯性"感——
	# 原来用 accel=2200 秒刹，位移只有 2-3px，等于没冲；现在用 brake*0.5，
	# 刹得慢一半，lunge 110px 至少能飘 10px 出去再停
	velocity.x = move_toward(velocity.x, 0.0, brake * 0.5 * delta)
	if Input.is_action_just_pressed("attack"):
		_attack_queued = true
	# 到点结算命中（支持一段动画多次命中，如 atk03 双刺）
	var lock: float = _attack_lock # 随机池段没有配置 lock，用起手时解析好的时长
	var t: float = lock - _attack_timer # 动画已进行时间
	while not _attack_hits.is_empty() and t >= _hit_time(_attack_hits[0]):
		_deal_hit(_attack_hits.pop_front())
	# 取消窗口：本段命中全部结算完后、lock 后 30%（atk["cancel"] 可调）允许提前
	# 接下一招 / 移动 / dash——不用干等收招帧，连段手感跟得上输入节奏
	var cancel_from: float = lock * (1.0 - float(attacks[_attack_idx].get("cancel", 0.3)))
	if t >= cancel_from and _attack_hits.is_empty():
		if _attack_queued and _attack_idx < attacks.size() - 1:
			_start_attack(_attack_idx + 1)
			return
		if Input.get_axis("move_left", "move_right") != 0.0:
			_set_state(State.IDLE if is_on_floor() else State.FALL)
			return
		_try_dash()
	if _attack_timer <= 0.0:
		if _attack_queued and _attack_idx < attacks.size() - 1:
			_start_attack(_attack_idx + 1)
		else:
			_set_state(State.IDLE if is_on_floor() else State.FALL)


## 命中段时刻：旧格式直接是秒数，新格式是 {"at": 秒, ...}
func _hit_time(h) -> float:
	return float(h["at"]) if h is Dictionary else float(h)


func _deal_hit(h = null) -> void:
	if _attack_idx < 0 or _attack_idx >= attacks.size():
		return
	var atk: Dictionary = attacks[_attack_idx]
	# 远程形态：发投射物，命中由投射物自己结算（伤害带上局内强化与契合加伤）
	if atk.has("projectile"):
		# 双剑气（剑仙形态专属）：额外投射物纵向错开齐发
		for i in proj_extra + 1:
			_spawn_projectile(atk["projectile"], int(atk["damage"]) + damage_bonus + _mastery_dmg + _buff_now(), "voice_sword_hit", i * 26.0)
		return
	# 命中段：旧格式是纯秒数（沿用本段统一 damage/range），
	# 新格式是字典（一段动画里多段不同伤害/范围，如梅剑鞭击后接突刺）
	var spec: Dictionary = h if h is Dictionary else atk
	var dmg := int(spec.get("damage", atk.get("damage", 1))) + damage_bonus + _mastery_dmg + _buff_now()
	var reach := float(spec.get("range", atk.get("range", 100.0))) * range_scale
	var side_any := bool(spec.get("both", atk.get("both", false)))
	var pull := float(spec.get("pull", 0.0)) # 鞭击拉回：命中后把敌人拽到身前这个距离
	var did_hit := false
	var pulled := 0 # 已拉回的敌人数，多目标依次错开 34px 免得叠成一坨
	for e in get_tree().get_nodes_in_group("enemies"):
		var p := e as Node2D
		if p == null:
			continue
		# 尸体不结算：怪死了但尸体还在场（dead_min 停留），打上去不该涨连击/触发顿帧
		if int(e.get("hp")) <= 0:
			continue
		var dx: float = p.global_position.x - global_position.x
		var dy: float = absf(p.global_position.y - global_position.y)
		var in_front := dx == 0.0 or (dx > 0.0) == (facing > 0)
		# both = 回身横扫：动画把武器甩到身后，前后两侧都算命中，否则"动画打到却没判上"
		# 射程 + 目标受击半径：体型大的 Boss 在身体边缘就能被够到，不用贴到原点
		if not (in_front or side_any) or absf(dx) > reach + _radius_of(p) or dy > 70.0:
			continue
		# 朱砂斩击打在攻击者与被击者的中点胸口高度：视觉上像"从玩家挥出"（拉回前先取位置）
		var mx := (global_position.x + p.global_position.x) * 0.5
		p.call("take_damage", dmg, global_position.x)
		Score.add_hit() # 命中一只算一次连击
		# 击飞（银夜段2）：敌人往空中挑起，落地硬直；打死的尸体不再挑
		var lc: Dictionary = spec.get("launch", {})
		if not lc.is_empty() and int(e.get("hp")) > 0:
			p.call("launch", facing, float(lc.get("vx", 150.0)), float(lc.get("vy", 520.0)))
		# 击退（银夜 L）：往攻击方向轰飞，撞同伴/墙壁产生组合伤害
		var kb: Dictionary = spec.get("knockback", {})
		if not kb.is_empty() and int(e.get("hp")) > 0:
			p.call("knock_back", facing, float(kb.get("force", 620.0)), int(kb.get("impact", 1)))
		if pull > 0.0:
			# 只朝玩家方向收，已经贴脸的敌人不往前推
			var want_x := global_position.x + float(facing) * (pull + pulled * 34.0)
			p.global_position.x = minf(p.global_position.x, want_x) if facing > 0 else maxf(p.global_position.x, want_x)
			pulled += 1
		FX.spawn(get_tree().current_scene, "slash", Vector2(mx, global_position.y - 70), {"scale": 0.45, "flip": facing < 0})
		did_hit = true
	if did_hit:
		_play_sfx(str(spec.get("sfx", "voice_sword_hit")))
		Feel.hitstop(0.045) # 命中一僵，普攻比技能轻
		Feel.shake(4.0, 0.13)


## 目标的受击半径：体型越大挨打面越大；没有该属性的测试替身按 30 兜底
func _radius_of(e) -> float:
	var r = e.get("body_radius")
	return float(r) if r != null else 30.0


## 觉醒（银夜 I）：buff 生效期间全部伤害 +N
func _buff_now() -> int:
	return _buff_damage if _buff_timer > 0.0 else 0


func _skill_tick(delta: float) -> void:
	_skill_timer -= delta
	var cfg: Dictionary = skill_config[_skill_name]
	var t: float = (_skill_dur - _skill_timer) * _skill_speed # 动画时间：慢放技能的时刻表按动画帧标定，与 cfg 的 at/blink 对齐
	# 位移三分支：自带位移动画（#87）原地播放等收招瞬移；普通闪现段高速前冲+穿身；其余减速
	if _skill_teleport > 0.0:
		_set_blink(true) # 原地期间同样开穿身：动画画面在冲，站位不动不该被敌人挤住
		velocity.x = move_toward(velocity.x, 0.0, accel * delta)
	elif cfg.has("blink_from") and t >= cfg["blink_from"] and t <= cfg["blink_to"]:
		_set_blink(true)
		velocity.x = facing * cfg["blink_speed"] # 闪现突进
	else:
		_set_blink(false)
		velocity.x = move_toward(velocity.x, 0.0, accel * delta)
	# 无敌：闪现/原地段全程 + 配置 invincible（银夜 O 冲刺整段无敌）
	_invincible = _blink_active or bool(cfg.get("invincible", false))
	# 到点结算命中段
	while not _skill_hits.is_empty() and t >= _skill_hits[0]["at"]:
		var h: Dictionary = _skill_hits.pop_front()
		_deal_skill_hit(h)
	# 持续伤害段（梅剑·转鞭）：from~to 期间每隔 interval 秒结算一次，前后方范围内所有敌人
	var tick: Dictionary = cfg.get("tick", {})
	if not tick.is_empty() and t >= float(tick["from"]) and t <= float(tick.get("to", _skill_dur)):
		_skill_tick_acc += delta
		var iv := float(tick.get("interval", 0.5))
		while _skill_tick_acc >= iv:
			_skill_tick_acc -= iv
			_deal_skill_tick(tick)
	# 时间暂停（银夜 U）：到点定住全场敌人，杂兵/精英/Boss 分档时长，无视霸体打断前摇
	var stop: Dictionary = cfg.get("stop", {})
	if not stop.is_empty() and not _stop_done and t >= float(stop.get("at", 0.5)):
		_stop_done = true
		for e in get_tree().get_nodes_in_group("enemies"):
			if int(e.get("hp")) <= 0:
				continue
			var tier := str(e.call("stop_tier")) if e.has_method("stop_tier") else "mob"
			e.call("time_stop", float(stop.get(tier, 2.0)))
	# 纯时长驱动退出：到点的同一帧排队的 stand 恰好接续，别看 is_complete（会被 loop 污染）
	if _skill_timer <= 0.0:
		# 自带位移动画（#87）：收招瞬间先瞬移到位移终点再补结算——path 判定从终点回扫整条路径
		if _skill_teleport > 0.0:
			global_position.x += facing * _skill_teleport
			_skill_teleport = 0.0
		# 收招兜底：命中段 at 略晚于动画时长时（力僧定山 at=3.12 > 3.05），
		# 靠计时器驱动永远触发不到 t>=at，整段伤害会凭空丢失——退出这一帧补结算
		while not _skill_hits.is_empty():
			_deal_skill_hit(_skill_hits.pop_front())
		_invincible = false
		_skill_poise = false
		_skill_reflect = false
		_skill_ranged_guard = false
		_skill_tick_acc = 0.0
		_set_blink(false)
		_set_state(State.IDLE if is_on_floor() else State.FALL)


func _set_blink(on: bool) -> void:
	if on == _blink_active:
		return
	_blink_active = on
	for e in get_tree().get_nodes_in_group("enemies"):
		if on:
			add_collision_exception_with(e)
		else:
			remove_collision_exception_with(e)


func _deal_skill_hit(h: Dictionary) -> void:
	# 远程技能：发投射物，命中由投射物自己结算
	if h.has("projectile"):
		for i in proj_extra + 1: # 双剑气齐发
			_spawn_projectile(h["projectile"], int(h["damage"]) + damage_bonus + _buff_now(), str(h.get("sfx", "")), i * 26.0)
		return
	# 纯回血段（力僧定山砸地）：不打伤害，只结算回血与砸地音
	if not h.has("damage"):
		_apply_skill_heal(h)
		return
	var did_hit := false
	for e in get_tree().get_nodes_in_group("enemies"):
		var p := e as Node2D
		if p == null:
			continue
		# 尸体不结算：怪死了但尸体还在场（dead_min 停留），打上去不该涨连击/触发顿帧
		if int(e.get("hp")) <= 0:
			continue
		var dx: float = p.global_position.x - global_position.x
		var dy: float = absf(p.global_position.y - global_position.y)
		if dy > h["height"]:
			continue
		if h.get("path", false):
			# 路径判定：闪现扫过的整条线段 + 落点正前方 range
			var x0: float = minf(_skill_start_x, global_position.x) - 20.0
			var x1: float = maxf(_skill_start_x, global_position.x) + 20.0
			var in_path: bool = p.global_position.x >= x0 and p.global_position.x <= x1
			var ahead := dx == 0.0 or (dx > 0.0) == (facing > 0)
			if in_path or (ahead and absf(dx) <= h["range"] * range_scale + _radius_of(p)):
				p.call("take_damage", int(h["damage"]) + damage_bonus + _buff_now(), global_position.x)
				Score.add_hit()
				_skill_kinetic(p, h)
				var mx := (global_position.x + p.global_position.x) * 0.5
				FX.spawn(get_tree().current_scene, "slash", Vector2(mx, global_position.y - 70), {"scale": 0.55, "flip": facing < 0})
				did_hit = true
		else:
			var in_front := dx == 0.0 or (dx > 0.0) == (facing > 0)
			# both = 回身横扫（力僧狼牙棒、双刺回身刺）：动画扫到身后也照样判定
			if (in_front or bool(h.get("both", false))) and absf(dx) <= h["range"] * range_scale + _radius_of(p):
				p.call("take_damage", int(h["damage"]) + damage_bonus + _buff_now(), global_position.x)
				Score.add_hit()
				_skill_kinetic(p, h)
				var mx := (global_position.x + p.global_position.x) * 0.5
				FX.spawn(get_tree().current_scene, "slash", Vector2(mx, global_position.y - 70), {"scale": 0.55, "flip": facing < 0})
				did_hit = true
	if did_hit:
		if h.has("sfx"):
			_play_sfx(h["sfx"])
		# 饮血（双刺形态专属）：技能命中回 1 血，内置冷却防一波吸满
		if skill_lifesteal and _lifesteal_cd <= 0.0:
			_lifesteal_cd = 6.0
			hp = mini(hp + 1, max_hp)
			hp_changed.emit(hp, max_hp)
			_spawn_number(1, Color(0.45, 0.75, 0.5), 130.0) # 绿字提示回了口血
		Feel.hitstop(0.06) # 技能命中：比普攻更重的顿帧与震屏
		Feel.shake(7.0, 0.2)
	_apply_skill_heal(h)


## 技能命中的位移效果（与普攻 _deal_hit 同规则）：launch=击飞挑空，knockback=击退轰飞；打死的尸体不动
func _skill_kinetic(p: Node2D, h: Dictionary) -> void:
	if int(p.get("hp")) <= 0:
		return
	var lc: Dictionary = h.get("launch", {})
	if not lc.is_empty():
		p.call("launch", facing, float(lc.get("vx", 150.0)), float(lc.get("vy", 520.0)))
	var kb: Dictionary = h.get("knockback", {})
	if not kb.is_empty():
		p.call("knock_back", facing, float(kb.get("force", 620.0)), int(kb.get("impact", 1)))


## 技能自带回血段（力僧·定山）：与是否命中无关，砸地这一下就是"定"住自己回血
func _apply_skill_heal(h: Dictionary) -> void:
	# 纯回血段没有命中判定，命中音得在这里补一声砸地闷响
	if h.has("sfx") and not h.has("damage"):
		_play_sfx(h["sfx"])
	if h.has("heal") and hp < max_hp:
		var heal := mini(int(h["heal"]), max_hp - hp)
		hp += heal
		hp_changed.emit(hp, max_hp)
		var dn := DAMAGE_NUMBER.new()
		dn.setup("定山 +%d" % heal, Color(0.45, 0.75, 0.5))
		dn.global_position = global_position + Vector2(0, -130)
		get_tree().current_scene.add_child(dn)


## 技能持续伤害段（梅剑·转鞭）：每 interval 秒对前后方范围内的所有敌人各打一次。
## 不顿帧、不震屏——0.5s 一跳的持续伤害如果每跳都卡一下，打起来会抖。
func _deal_skill_tick(tick: Dictionary) -> void:
	var did_hit := false
	for e in get_tree().get_nodes_in_group("enemies"):
		var p := e as Node2D
		if p == null or int(e.get("hp")) <= 0:
			continue
		var dx: float = p.global_position.x - global_position.x
		var dy: float = absf(p.global_position.y - global_position.y)
		if dy > float(tick.get("height", 120.0)):
			continue
		var in_front := dx == 0.0 or (dx > 0.0) == (facing > 0)
		# both = 转鞭：鞭子一直在转，前后方都扫得到
		if not (in_front or bool(tick.get("both", false))) or absf(dx) > float(tick["range"]) * range_scale + _radius_of(p):
			continue
		p.call("take_damage", int(tick["damage"]) + damage_bonus + _buff_now(), global_position.x)
		Score.add_hit()
		did_hit = true
	if did_hit:
		_play_sfx("voice_sword_hit")


## 远程格挡（梅剑·转鞭）：技能期间免疫并反弹敌方投射物。
## 目前工程里敌人还没有投射物，这里是预埋接口——以后敌方投射物命中玩家前先调用它，
## 返回 true 表示这次远程攻击已被她免疫并原路弹回，投射物应反向飞回"第一个遇到的敌人"。
func try_reflect_ranged(damage: int, from_x: float, attacker: Node = null) -> bool:
	if not _skill_ranged_guard:
		return false
	# 反弹目标：优先攻击者本人；否则沿来源方向找最近的那个敌人
	var target: Node = null
	if attacker != null and is_instance_valid(attacker) and attacker.has_method("take_damage"):
		target = attacker
	else:
		var dir := signf(from_x - global_position.x)
		var best := INF
		for e in get_tree().get_nodes_in_group("enemies"):
			var p := e as Node2D
			if p == null or int(e.get("hp")) <= 0:
				continue
			var d: float = (p.global_position.x - global_position.x) * dir
			if d >= 0.0 and d < best:
				best = d
				target = e
	if target != null:
		target.call("take_damage", damage, global_position.x)
		Score.add_hit()
		var tp := target as Node2D
		if tp != null:
			FX.spawn(get_tree().current_scene, "ink_hit", tp.global_position + Vector2(0, -60), {"scale": 0.4})
		_play_sfx("voice_fan_hit")
		Feel.shake(3.0, 0.1)
	return true


## 发一颗投射物：从胸口高度出手，沿朝向直线飞
func _spawn_projectile(spec: Dictionary, damage: int, sfx: String, y_off := 0.0) -> void:
	var pr = PROJECTILE.new()
	pr.setup(facing, float(spec.get("speed", 520.0)), float(spec.get("range", 420.0)), damage, sfx, proj_pierce)
	pr.global_position = global_position + Vector2(facing * 36.0, -52.0 + y_off)
	get_tree().current_scene.add_child(pr)


func _hurt_tick(delta: float) -> void:
	_hurt_timer -= delta
	velocity.x = move_toward(velocity.x, 0.0, accel * delta)
	if _hurt_timer <= 0.0:
		_set_state(State.IDLE if is_on_floor() else State.FALL)


## 给 HUD 查技能冷却进度：返回 0（就绪）~ 1（刚放完）。未知技能返回 0。
func get_skill_cd_ratio(n: String) -> float:
	var cfg: Dictionary = skill_config.get(n, {})
	if cfg.is_empty():
		return 0.0
	var total: float = cfg["cooldown"]
	if total <= 0.0:
		return 0.0
	var cd: float = _skill_cds.get(n, 0.0)
	return clampf(cd / total, 0.0, 1.0)


## 给 HUD 查技能对应的按键字母
func get_skill_key(n: String) -> String:
	var cfg: Dictionary = skill_config.get(n, {})
	return str(KEY_LABELS.get(str(cfg.get("action", "")), "-"))


# ---------- 动作入口 ----------

func _try_jump() -> void:
	if _jump_buf > 0.0 and _coyote > 0.0:
		_jump_buf = 0.0
		_coyote = 0.0
		velocity.y = jump_velocity * _qg_jump_mul # 轻功：明显更高的起跳
		_hover_left = _qg_hover # 本次跳跃带一段顶点悬停
		_set_state(State.JUMP)


func _try_dash() -> void:
	if Input.is_action_just_pressed("dash") and _dash_cd <= 0.0:
		state = State.DASH
		_dash_timer = dash_time
		_play(anim_map["dash"], false, _dash_anim_speed)
		_play_sfx("dash_step") # 冲刺踏地声，补上原本只有画面没有声音的空档


func _start_attack(idx: int) -> void:
	if idx < 0 or idx >= attacks.size():
		return
	var atk: Dictionary = attacks[idx]
	state = State.ATTACK
	_attack_idx = idx
	_attack_queued = false
	# 随机池段（银夜三段普攻）：每段从 pool 抽一种动画，锁定时长 = 抽中动画的真实时长，
	# 命中时刻/判定范围也按抽中的动画查表（pool 段用 hit_at/range 字典逐动画标定）
	var anim := str(atk.get("anim", ""))
	if atk.has("pool"):
		var pool: Array = atk["pool"]
		anim = str(pool[randi() % pool.size()])
		var hit_map: Dictionary = atk.get("hit_at", {})
		var range_map: Dictionary = atk.get("range", {})
		var h := {
			"at": float(hit_map.get(anim, 0.3)),
			"range": float(range_map.get(anim, 100.0)),
			"damage": int(atk.get("damage", 1)),
		}
		if atk.has("launch"):
			h["launch"] = atk["launch"] # 击飞（段2）：敌人挑空
		if atk.has("knockback"):
			h["knockback"] = atk["knockback"]
		_attack_hits = [h]
		_attack_timer = float(_attack_durations.get(anim, 0.6))
	else:
		_attack_hits = (atk["hits"] as Array).duplicate() # 待弹出的命中时刻列表
		_attack_timer = float(atk["lock"])
	_attack_lock = _attack_timer
	_attack_anim = anim
	velocity.x = facing * float(atk["lunge"])
	_play(anim, false)
	_play_sfx("weapon_sword") # 起手嗖一声
	_queue(anim_map["idle"], true) # 打完自动回 idle，防止卡在收招帧
	_idle_queued = true # 与 _start_skill 一致：idle 已在队列里，收招超时别再 _play 重开淡化


func _try_skill() -> void:
	for n in skill_config:
		var cfg: Dictionary = skill_config[n]
		if Input.is_action_just_pressed(cfg["action"]) and _skill_cds.get(n, 0.0) <= 0.0:
			_start_skill(n)
			return


func _start_skill(n: String) -> void:
	state = State.SKILL
	_skill_name = n
	var cfg: Dictionary = skill_config[n]
	# 随机池技能（银夜 I/O）：每次从池里抽一种动画，时长按抽中的走；冷却/命中段全技能统一
	_skill_anim = n
	if cfg.has("pool"):
		var pool: Array = cfg["pool"]
		_skill_anim = str(pool[randi() % pool.size()])
	# speed：动画播放速度倍率（<1 慢放，如银夜 K 蓄力斩）。锁定/真实时长拉长到 1/speed，
	# 命中/stop/blink 等时刻表仍按动画秒标定，_skill_tick 里用动画时间对齐，不用逐个缩放
	_skill_speed = float(cfg.get("speed", 1.0))
	var base_dur: float = float(_skill_durations.get(_skill_anim, 2.0))
	# align_max（银夜 I 觉醒）：池内动画时长不齐时，短动画慢放撑满池内最长——觉醒时长恒定
	if cfg.has("pool") and bool(cfg.get("align_max", false)):
		var max_dur := base_dur
		for an in cfg["pool"]:
			max_dur = maxf(max_dur, float(_skill_durations.get(str(an), base_dur)))
		_skill_speed *= base_dur / max_dur
	_skill_dur = base_dur / _skill_speed
	_skill_timer = _skill_dur
	# per-anim 命中标定（hit_at/range 按抽中动画查表）：池技能各动画挥出时刻/范围不同
	if cfg.has("hit_at"):
		var at_map: Dictionary = cfg["hit_at"]
		var range_map: Dictionary = cfg.get("range", {})
		_skill_hits = [{
			"at": float(at_map.get(_skill_anim, 0.5)),
			"range": float(range_map.get(_skill_anim, 100.0)),
			"height": float(cfg.get("height", 100.0)),
			"damage": int(cfg.get("damage", 1)),
			"both": bool(cfg.get("both", false)),
			"path": bool(cfg.get("path", false)),
			"sfx": str(cfg.get("sfx", "")),
		}]
	else:
		_skill_hits = cfg.get("hits", []).duplicate(true)
	_skill_start_x = global_position.x
	_skill_poise = bool(cfg.get("poise", false))
	_skill_reflect = bool(cfg.get("reflect", false))
	_skill_ranged_guard = bool(cfg.get("ranged_guard", false))
	_skill_tick_acc = 0.0
	_stop_done = false
	_skill_cds[n] = float(cfg["cooldown"]) * cooldown_scale * _mastery_cd
	_invincible = false
	# 自带位移动画（银夜 O 抽到 #87 skill11-cankao）：原地播放，收招瞬间瞬移整段冲刺距离（闪现窗口×速度）
	_skill_teleport = 0.0
	if _skill_anim in cfg.get("teleport_anims", []):
		_skill_teleport = float(cfg.get("blink_speed", 800.0)) * (float(cfg.get("blink_to", 0.9)) - float(cfg.get("blink_from", 0.15)))
	# 觉醒（银夜 I）：起手即回血 + 限时加伤
	if cfg.has("heal"):
		_apply_skill_heal({"heal": cfg["heal"]})
	if cfg.has("buff_damage"):
		_buff_damage = int(cfg["buff_damage"])
		_buff_timer = float(cfg.get("buff_time", 8.0))
	velocity.x = facing * float(attacks[0]["lunge"]) * 0.6 # 起手小前冲
	_play(_skill_anim, false, _skill_speed)
	_play_sfx("voice_skill_cast") # 技能起手嗡一声
	# 排队 stand 紧跟技能之后：非循环动画播完瞬间轨道空窗会闪回 setup pose
	_queue(anim_map["idle"], true)
	_idle_queued = true


## 换头：Q 键打开化身面板（暂停时间选形态），扣墨骨由面板在选中时结算
func _try_swap_skull() -> void:
	if state == State.DEAD or get_tree().paused:
		return
	var scene := get_tree().current_scene
	if scene == null or scene.get_node_or_null("SwapPanel") != null:
		return
	var panel = load("res://scenes/ui/swap_panel.tscn").instantiate()
	panel.name = "SwapPanel"
	panel.setup(self) # 必须在 add_child 前：面板的 _ready 要读当前形态
	scene.add_child(panel)


## 立刻换成指定形态：拆旧骨架 → 重装形态数据 → 重建骨架
func swap_skull(id: String) -> void:
	if not Skulls.SKULLS.has(id) or id == skull_id:
		return
	_set_blink(false) # 换头瞬间收掉闪现的碰撞例外
	_invincible = false
	_idle_queued = false
	_attack_idx = -1
	_skill_name = ""
	_skill_timer = 0.0
	_skill_poise = false
	_skill_reflect = false
	_skill_ranged_guard = false
	_skill_tick_acc = 0.0
	_skill_teleport = 0.0
	_buff_timer = 0.0 # 觉醒属于银夜，换头即散
	_hover_left = 0.0
	_apply_profile(id)
	_setup_spine()
	Run.skull_id = id # 局外养成的击杀/通关记账按当前形态归属，换头后立刻同步
	_play_sfx("voice_skill_cast")
	# 化身光柱从脚下冲天而起，盖住拆骨换形的一瞬间（pillar 贴条底部留白已裁，bottom 锚点即脚底）
	FX.spawn(get_tree().current_scene, "pillar", global_position, {"scale": 0.75, "z": 30})
	if is_on_floor():
		state = State.IDLE
		_play(anim_map["idle"], true)
	else:
		state = State.FALL
		_play(anim_map["air"], true)
	skull_changed.emit(id)


func hurt(amount: int = 1, knockback: Vector2 = Vector2.ZERO, attacker: Node = null) -> void:
	if state == State.DEAD or state == State.DASH or _invincible:
		return
	# 定山·反伤：技能期间自身无敌，挨多少就原样弹回攻击者多少
	# 放在 _hurt_invincible 之前——刚受过伤的 0.8s 无敌期内照样反弹
	if _skill_reflect and attacker != null and is_instance_valid(attacker) \
			and attacker.has_method("take_damage"):
		attacker.call("take_damage", amount, global_position.x)
		var ap := attacker as Node2D
		if ap != null:
			FX.spawn(get_tree().current_scene, "ink_hit", ap.global_position + Vector2(0, -60), {"scale": 0.4})
			var dn := DAMAGE_NUMBER.new()
			dn.setup(str(amount), Color(0.72, 0.45, 0.3)) # 赭石：反伤数字挂在攻击者头上
			dn.global_position = ap.global_position + Vector2(0, -140)
			get_tree().current_scene.add_child(dn)
		_play_sfx("voice_fan_hit")
		Feel.shake(3.0, 0.1)
		return
	if _hurt_invincible > 0.0:
		return
	_hurt_invincible = 0.8
	_set_blink(false) # 受击打断技能：闪现的碰撞例外一并清掉，别带着穿怪状态进硬直
	hp -= amount
	hp_changed.emit(hp, max_hp)
	_spawn_number(amount, DMG_COLOR, 130.0)
	_play_sfx("hit_fist") # 玩家受伤闷拳声
	# 水墨受击花在胸口炸开，flip 跟击退方向（击退朝右 = 攻击来自左侧）
	FX.spawn(get_tree().current_scene, "ink_hit", global_position + Vector2(0, -70), {"scale": 0.45, "flip": knockback.x > 0.0})
	Feel.hitstop(0.05) # 挨打也要"一僵"：受击反馈和打人一样重要
	Feel.shake(8.0, 0.24)
	if hp <= 0:
		# 残墨续命赐福：一局一次，以 4 点生命原地爬起
		if Run.blessing == "revive" and not Run.blessing_used:
			Run.blessing_used = true
			hp = mini(4, max_hp)
			_hurt_invincible = 1.5 # 起身喘口气，别立刻又被围殴
			hp_changed.emit(hp, max_hp)
			state = State.HURT
			_hurt_timer = hurt_time
			velocity = knockback
			_play(anim_map["getup"], false)
			_queue(anim_map["idle"], true)
			_idle_queued = true
			return
		die()
		return
	# 霸体（力僧形态专属 + 定山技能自带）：技能期间挨打开着招式硬吃，掉血但不进硬直、不打断技能
	if (poise or _skill_poise) and state == State.SKILL:
		return
	state = State.HURT
	_hurt_timer = hurt_time
	velocity = knockback
	_idle_queued = false # set_animation 已清掉队列里的 stand
	_invincible = false
	_play(anim_map["hurt"], false)


func _spawn_number(amount: int, color: Color, height: float) -> void:
	var dn := DAMAGE_NUMBER.new()
	dn.setup(str(amount), color)
	dn.global_position = global_position + Vector2(randf_range(-12.0, 12.0), -height)
	get_tree().current_scene.add_child(dn)


func die() -> void:
	state = State.DEAD
	_set_blink(false) # 尸体也别穿怪
	velocity = Vector2.ZERO
	_idle_queued = false
	_invincible = false
	_buff_timer = 0.0 # 死亡收掉觉醒
	_play(anim_map["dead"], false)
	# 银夜：倒地动画播完接躺尸定格循环（dead 只有 0.083s，不循环会闪回 setup pose）
	var hold := str(anim_map.get("dead_hold", ""))
	if hold != "":
		_queue(hold, true)
	died.emit()


# ---------- 内部工具 ----------

func _post_move() -> void:
	match state:
		State.IDLE, State.RUN:
			if not is_on_floor() and _coyote <= 0.0:
				_set_state(State.FALL)
		State.JUMP:
			if velocity.y > 0.0:
				_set_state(State.FALL)
		State.FALL:
			if is_on_floor():
				_hover_left = 0.0 # 落地收掉残余悬停
				_set_state(State.RUN if absf(velocity.x) > 10.0 else State.IDLE)


func _set_state(new_state: int) -> void:
	if state == new_state:
		return
	state = new_state
	match state:
		State.IDLE:
			if _idle_queued:
				# stand 已被 Spine 自动接续播放，只同步记录，不重复 set（重开会重开淡化）
				_current_anim = anim_map["idle"]
			else:
				_play(anim_map["idle"], true)
			_idle_queued = false
		State.RUN:
			_idle_queued = false
			_play(anim_map["run"], true)
		State.JUMP, State.FALL:
			_idle_queued = false # set_animation 会清掉队列里的 stand
			_play(anim_map["air"], true)


func _apply_facing() -> void:
	if sprite:
		sprite.scale.x = base_scale * facing


## spd：播放速度倍率（<1 慢放）。set_animation 返回本条轨道，time_scale 只作用于它，不污染后续排队动画
func _play(anim: String, loop: bool, spd := 1.0) -> void:
	if _anim_state == null:
		return
	if loop and anim == _current_anim:
		return # 循环动画同名重放 = 从头再来一遍，跳跃顶点会抽搐
	_current_anim = anim
	var entry = _anim_state.call("set_animation", anim, loop, 0)
	if spd != 1.0 and entry != null and entry.has_method("set_time_scale"):
		entry.call("set_time_scale", spd)


func _queue(anim: String, loop: bool) -> void:
	if _anim_state:
		_anim_state.call("add_animation", anim, 0.0, loop, 0)
