extends "res://scripts/enemies/c016.gd"

## Boss 基座：多阶段 + 全程霸体 + 变身无敌 + 冲锋技 + 登场演出。
## 与小怪的差异全部通过 boss_types.gd 注入；这里只写 Boss 通用机制：
## · 血量比例跌破 stage_at 阈值 -> 播变身动画（期间无敌）-> 换下一阶段的招式池/节奏/速度
## · 变身结束后给一段僵直窗口（stagger），奖励贴身的玩家
## · 配置里有 charge 的 Boss 会在拉开距离后全屏冲锋，撞墙则大硬直
## · 头顶不挂小血条，血量通过 hp_changed 信号交给 HUD 大血条

signal hp_changed(hp: int, max_hp: int)

const BossTypes := preload("res://scripts/enemies/boss_types.gd")

# Boss 专属音效（继承 c016 的 SFX_HIT_QI / SFX_TELEGRAPH）
const SFX_BOSS_ENTER := preload("res://audio/sfx/boss_entrance.wav")

# 自定义状态（父类 enum 不可扩展，用大数值避开）
const S_ENTER := 100 # 登场：锁行动
const S_TRANSFORM := 101 # 变身：无敌
const S_STAGGER := 102 # 僵直窗口：可被打但不还手（变身奖励 / 撞墙惩罚）
const S_CHARGE_TELE := 103 # 冲锋蓄力
const S_CHARGING := 104 # 冲锋进行中

const ARENA_L := 80.0 # 房间围墙内沿
const ARENA_R := 1840.0

var boss_label := ""
var stage := 0

var _stage_at: Array = []
var _stages: Array = []
var _charge: Dictionary = {}
var _charge_cd := 0.0
var _charge_dir := 1.0
var _charge_hit_done := false
var _state_timer := 0.0
var _invincible := false
var _valid: Dictionary = {} # 动画名 -> 是否存在（素材没转好/名字写错时降级而不是报错）
var _fx: Dictionary = {} # 特效配置（hit/enter/transform/charge_trail/charge_wall），boss_types 注入
var _trail_timer := 0.0 # 冲锋拖尾特效的喷溅间隔
var _fz: Dictionary = {} # 当前阶段的封锁火区配置（空 = 无此机制）
var _fz_cd := 0.0 # 火区冷却
var _transform_flip := false # 掉头演出（transform_flip）：播完把 facing 翻转，跟演出保持一致


# ---------- 形态注入 ----------

func _apply_type() -> void:
	var t: Dictionary = BossTypes.get_boss(type_id)
	type_id = type_id if BossTypes.BOSSES.has(type_id) else BossTypes.DEFAULT_ID
	_base_scale = float(t["scale"])
	_scale = _base_scale
	_anim_map = t["anim"]
	_ranges = t["ranges"]
	_hit_at_map = t["hit_at"]
	_both_anims = t.get("both", {})
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
	_telegraph_on = bool(t["telegraph"])
	_pick_nearest = str(t["pick"]) == "nearest"
	_bones = int(t["bones"])
	_dead_min = float(t["dead_min"])
	_number_y = float(t["number_y"])
	boss_label = str(t["label"])
	_stage_at = t["stage_at"]
	_stages = t["stages"]
	_charge = t.get("charge", {})
	_fx = t.get("fx", {})
	_attack_anims = _stages[0]["attacks"] # 阶段 1 招式池
	attack_cooldown = float(_stages[0].get("attack_cooldown", attack_cooldown))
	chase_speed = float(_stages[0].get("chase_speed", chase_speed))


## 本形态用到的全部动画名（有效性检查 + 时长缓存用）
func _all_anim_names() -> Array:
	var names: Array = []
	for v in _anim_map.values():
		names.append(str(v))
	for st in _stages:
		for n in st.get("attacks", []):
			names.append(str(n))
		var tr := str(st.get("transform", ""))
		if tr != "":
			names.append(tr)
	for k in ["anim_run", "anim_stop", "anim_stun"]:
		var n := str(_charge.get(k, ""))
		if n != "":
			names.append(n)
	names.append("chuchang") # 部分素材自带登场动画
	return names


func _setup_spine() -> void:
	# 不能走父类：父类按 enemy_types 取骨架数据，_debug 不在表里会退回 c016。
	# 这里用 boss_types 的数据完整自装配，顺带缓存全部动画时长 + 记录有效性
	var data = load(str(BossTypes.get_boss(type_id)["data"]))
	if data == null or not data.call("is_skeleton_data_loaded"):
		push_error("Boss: 骨架数据加载失败 " + type_id)
		return
	for n in _all_anim_names():
		var a = data.call("find_animation", n)
		if a != null:
			_valid[n] = true
			_anim_durations[n] = a.call("get_duration")
	var missing: Array = []
	for n in _all_anim_names():
		if not _valid.has(n):
			missing.append(n)
	if not missing.is_empty():
		push_warning("Boss " + type_id + ": 动画缺失 " + str(missing))
	sprite = ClassDB.instantiate("SpineSprite")
	add_child(sprite)
	sprite.set("skeleton_data_res", data)
	data.call("set_default_mix", 0.2)
	sprite.scale = Vector2(_scale * facing, _scale)
	_anim_state = sprite.call("get_animation_state")
	_play(str(_anim_map["idle"]), true)


## 动画守卫：名字不存在就跳过（占位配置下 Boss 照常能动，只是少动作）
func _play(anim: String, loop: bool) -> void:
	if not _valid.get(anim, false):
		return
	super(anim, loop)


## Boss 不挂头顶小血条，血量全走 HUD 大血条
func _update_hp_bar() -> void:
	if _hp_bar != null:
		_hp_bar.visible = false


# ---------- 登场 ----------

## 房间在 add_child 后调用：登场演出期间锁行动，给玩家一个看清对手的时间
func entrance() -> void:
	_release_token()
	state = S_ENTER
	_state_timer = 1.2
	velocity = Vector2.ZERO
	if _valid.get("chuchang", false):
		_play("chuchang", false)
		_state_timer = float(_anim_durations.get("chuchang", 1.2))
	Feel.shake(7.0, 0.3)
	_sfx_player.stream = SFX_BOSS_ENTER
	_sfx_player.play()
	_fx_play(_fx.get("enter", {})) # 登场特效：虎首地裂 / 紫焰火柱 / 速度线
	hp_changed.emit(hp, max_hp)


# ---------- 主循环 ----------

func _physics_process(delta: float) -> void:
	if state == State.DEAD:
		return
	_charge_cd = maxf(0.0, _charge_cd - delta)
	if state >= S_ENTER:
		_find_target()
		_custom_tick(delta)
		velocity.y = minf(velocity.y + gravity * delta, 900.0)
		move_and_slide()
		return
	_fz_tick(delta) # 封锁火区只在常规战斗状态跑（变身/硬直/冲锋途中不喷）
	super(delta)


func _custom_tick(delta: float) -> void:
	_state_timer -= delta
	match state:
		S_ENTER:
			velocity.x = move_toward(velocity.x, 0.0, 1500.0 * delta)
			if _state_timer <= 0.0:
				_set_state(State.IDLE)
		S_TRANSFORM, S_STAGGER:
			velocity.x = move_toward(velocity.x, 0.0, 1500.0 * delta)
			if _state_timer <= 0.0:
				if state == S_TRANSFORM:
					_finish_transform()
				else:
					_set_state(State.CHASE)
		S_CHARGE_TELE:
			velocity.x = move_toward(velocity.x, 0.0, 1500.0 * delta)
			if _state_timer <= 0.0:
				_begin_charge_run()
		S_CHARGING:
			velocity.x = _charge_dir * float(_charge.get("speed", 640.0))
			# 冲锋拖尾：按间隔在身后甩速度线
			_trail_timer -= delta
			var trail: Dictionary = _fx.get("charge_trail", {})
			if not trail.is_empty() and _trail_timer <= 0.0:
				_trail_timer = float(trail.get("interval", 0.1))
				FX.spawn(get_tree().current_scene, str(trail["name"]),
					global_position + Vector2(-_charge_dir * 120.0, -70.0),
					{"scale": float(trail.get("scale", 1.0)), "flip": _charge_dir < 0.0})
			_charge_hit_check()
			if is_on_wall() or global_position.x <= ARENA_L or global_position.x >= ARENA_R:
				_charge_hit_wall()


# ---------- 阶段 ----------

func _check_stage() -> void:
	if stage >= _stages.size() - 1:
		return
	var frac := float(hp) / float(max_hp)
	if frac <= float(_stage_at[stage]):
		_enter_stage(stage + 1)


func _enter_stage(next: int) -> void:
	stage = next
	_release_token()
	var st: Dictionary = _stages[stage]
	var tname := str(st.get("transform", ""))
	if tname != "" and _valid.get(tname, false):
		# 变身：无敌 + 泛红预警，播完才换阶段参数
		_invincible = true
		state = S_TRANSFORM
		_state_timer = float(_anim_durations.get(tname, 2.0))
		velocity.x = 0.0
		_transform_flip = bool(st.get("transform_flip", false))
		_play(tname, false)
		_telegraph()
		Feel.shake(6.0, 0.25)
		_fx_play(_fx.get("transform", {})) # 变身演出特效（虎首地裂/紫焰/速度线）
		_fx_play(st.get("fx", {})) # 本阶段专属的觉醒特效（墨霆 P3 雷纹）
	else:
		_apply_stage(st)


func _finish_transform() -> void:
	_invincible = false
	# 掉头演出（武车 zhuanshen）结束后朝向跟着翻转：演出里车已经调头，
	# 不翻的话紧接着的 idle 会按旧朝向把车身瞬间翻回去，视觉突兀
	if _transform_flip:
		facing = -facing
		_apply_facing()
	_transform_flip = false
	_apply_stage(_stages[stage])
	_attack_cd = attack_cooldown # 僵直窗口是奖励输出的，起身不许立刻贴脸一刀
	# 变身后的僵直窗口：不变身也照给（无变身动画的阶段切换也要有节奏感）
	state = S_STAGGER
	_state_timer = float(_stages[stage].get("stagger", 0.6))
	_play(str(_anim_map["idle"]), true)


func _apply_stage(st: Dictionary) -> void:
	_attack_anims = st["attacks"]
	attack_cooldown = float(st.get("attack_cooldown", attack_cooldown))
	chase_speed = float(st.get("chase_speed", chase_speed))
	# 阶段可能带来封锁火区（焚鼎 P3）；换个没有的阶段就关掉
	_fz = st.get("fire_zones", {})
	_fz_cd = 1.5 if not _fz.is_empty() else 0.0 # 进阶段喘口气再开始封锁


# ---------- 冲锋技 ----------

func _chase_tick(delta: float) -> void:
	if not _charge.is_empty() and _charge_cd <= 0.0 and _target != null:
		var dx: float = absf(_target.global_position.x - global_position.x)
		if dx >= float(_charge.get("min_dist", 420.0)):
			_start_charge()
			return
	super(delta)


func _start_charge() -> void:
	_release_token()
	state = S_CHARGE_TELE
	_charge_hit_done = false
	velocity.x = 0.0
	_state_timer = 0.7
	_play(str(_charge.get("anim_stop", "")), false) # 急停蓄力 pose 就是预警
	_telegraph()


func _begin_charge_run() -> void:
	if _target == null or not is_instance_valid(_target):
		_set_state(State.IDLE)
		return
	_charge_dir = signf(_target.global_position.x - global_position.x)
	if _charge_dir == 0.0:
		_charge_dir = float(facing)
	facing = int(_charge_dir)
	_apply_facing()
	state = S_CHARGING
	_play(str(_charge.get("anim_run", "")), true)
	Feel.shake(4.0, 0.2)


## 冲锋碾压：全程只命中一次，避免推着玩家连吃伤害
func _charge_hit_check() -> void:
	if _charge_hit_done or _target == null or not is_instance_valid(_target):
		return
	var dx: float = _target.global_position.x - global_position.x
	var dy: float = absf(_target.global_position.y - global_position.y)
	if absf(dx) <= float(_charge.get("hit_w", 130.0)) and dy <= float(_charge.get("hit_h", 150.0)):
		_charge_hit_done = true
		_target.call("hurt", int(_charge.get("damage", 2)), Vector2(_charge_dir * 420.0, -120.0))


## 撞墙：大硬直 + 震屏，这是玩家唯一的稳定输出窗口
func _charge_hit_wall() -> void:
	state = S_STAGGER
	_state_timer = float(_charge.get("stun_time", 1.8))
	velocity.x = 0.0
	_attack_cd = attack_cooldown * 0.5 # 起身较快，逼玩家贪完刀就走
	_charge_cd = float(_charge.get("cooldown", 6.0))
	_play(str(_charge.get("anim_stun", "")), false)
	_queue(str(_anim_map["idle"]), true) # 硬直比自晕动画长：接续 idle，避免播完闪回 setup pose
	Feel.shake(9.0, 0.3)
	# 撞墙地裂爆炸：贴墙根从脚下炸起
	var wall_fx: Dictionary = _fx.get("charge_wall", {})
	if not wall_fx.is_empty():
		FX.spawn(get_tree().current_scene, str(wall_fx["name"]),
			Vector2(global_position.x + _charge_dir * float(_charge.get("hit_w", 130.0)) * 0.5, global_position.y),
			{"scale": float(wall_fx.get("scale", 1.0)), "flip": _charge_dir < 0.0})


# ---------- 受击 / 死亡 ----------

## Boss 全程霸体：不掉血打断、不击退、不进 HURT；变身期无敌只闪白
func take_damage(amount: int, source_x: float) -> void:
	if state == State.DEAD:
		return
	if _invincible:
		_flash()
		return
	hp -= amount
	_sfx_player.stream = SFX_HIT_QI
	_sfx_player.play()
	_spawn_number(amount)
	hp_changed.emit(hp, max_hp)
	if hp <= 0:
		die()
		return
	_flash()
	# 受击爪痕：打在攻击者来袭的一侧躯干（而非 boss 正中），有"被砍了一刀"的方向感
	var off_x := signf(global_position.x - source_x) * 50.0 # 来袭方向 → 爪痕在躯干那侧
	_fx_play(_fx.get("hit", {}), Vector2(off_x, _number_y * 0.55))
	_check_stage()


## Boss 不需要全局出手令牌：战场上只有它一个攻击者
func _can_attack() -> bool:
	return true


func die() -> void:
	hp_changed.emit(0, max_hp)
	Feel.shake(10.0, 0.4)
	super()


# ---------- 特效 / 封锁火区 ----------

## 放一条配置特效：cfg 来自 boss_types 的 fx 表，off_y 可把中心锚特效抬到躯干
func _fx_play(cfg: Dictionary, off := Vector2.ZERO) -> void:
	if cfg.is_empty():
		return
	FX.spawn(get_tree().current_scene, str(cfg["name"]),
		global_position + off + Vector2(0, float(cfg.get("off_y", 0.0))),
		{"scale": float(cfg.get("scale", 1.0)), "flip": facing < 0})


## 火区节奏：冷却一到就撒一轮（只在常规战斗状态被调用）
func _fz_tick(delta: float) -> void:
	if _fz.is_empty():
		return
	_fz_cd -= delta
	if _fz_cd <= 0.0:
		_fz_cd = float(_fz.get("interval", 4.5))
		_spawn_fire_zones()


## 撒火区：一团锁定玩家脚下，其余随机落在场地里，先聚气预警再喷发
func _spawn_fire_zones() -> void:
	var count := int(_fz.get("count", 3))
	var xs: Array = []
	if _target != null and is_instance_valid(_target):
		xs.append(_target.global_position.x) # 必有一团追玩家脚下
	while xs.size() < count:
		xs.append(randf_range(ARENA_L + 120.0, ARENA_R - 120.0))
	for x in xs:
		var pos := Vector2(clampf(x, ARENA_L + 60.0, ARENA_R - 60.0), global_position.y)
		FX.spawn(get_tree().current_scene, "gather", pos, {"scale": 0.55, "mod": Color(1.0, 0.5, 0.45, 0.95)})
		_fire_zone_burst(pos)


## 预警结束后火柱喷发 + 范围判定（Boss 途中被打死则哑火）
func _fire_zone_burst(pos: Vector2) -> void:
	await get_tree().create_timer(float(_fz.get("warn", 0.7))).timeout
	if state == State.DEAD or not is_inside_tree():
		return
	FX.spawn(get_tree().current_scene, "fire_pillar", pos, {"scale": 0.6})
	Feel.shake(3.0, 0.12)
	if _target == null or not is_instance_valid(_target):
		return
	var dx: float = _target.global_position.x - pos.x
	var dy: float = absf(_target.global_position.y - pos.y)
	if absf(dx) <= float(_fz.get("radius", 110.0)) and dy <= 160.0:
		_target.call("hurt", int(_fz.get("damage", 1)), Vector2(signf(dx) * 220.0, -100.0))
		# 火焰灼烧在玩家身上炸开（击中才放，区别于普通受击墨花）
		FX.spawn(get_tree().current_scene, "fire_hit", _target.global_position + Vector2(0, -70), {"scale": 0.5})
