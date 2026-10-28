extends CharacterBody2D

## 小怪通用 AI：巡逻 / 追击 / 攻击 / 受击 / 死亡
## 长什么样、出什么招、判定多长，全部来自 scripts/enemies/enemy_types.gd 的形态表。
## 主角形态不设同名敌人版本（梅剑 c023 的精英怪已删）。

const Types := preload("res://scripts/enemies/enemy_types.gd")
const DAMAGE_NUMBER := preload("res://scripts/ui/damage_number.gd")
const BONE_PICKUP := preload("res://scripts/systems/bone_pickup.gd")
const FX := preload("res://scripts/systems/fx.gd")
const DMG_COLOR := Color(0.66, 0.2, 0.16) # 朱砂：敌人受伤数字
const SFX_HIT_QI := preload("res://audio/sfx/hit_qi.wav")
const SFX_TELEGRAPH := preload("res://audio/sfx/telegraph.wav")

@export var type_id := "c016"

enum State { IDLE, PATROL, CHASE, ATTACK, HURT, DEAD }

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
var _bones := 1 # 死亡掉落墨骨数
var _dead_min := 1.2 # 尸体最少停留时间（补死动画过短的形态）
var _telegraph_on := false
var _pick_nearest := false
var _base_scale := 0.32
var _scale := 0.32
var _anim_map: Dictionary = {}
var _attack_anims: Array = []
var _ranges: Dictionary = {}
var _hit_at_map: Dictionary = {}
# both：该招是回身横扫，动画把武器甩到身后，判定不分前后（否则"动画打到却判不上"）
var _both_anims: Dictionary = {}
var _bar_w := 44.0
var _bar_y := -120.0
var _number_y := -105.0

var _home_x := 0.0
var _patrol_dir := 1
var _idle_timer := 0.0
var _attack_cd := 0.0
var _attack_timer := 0.0
var _attack_dur := 0.0 # 本次出手动画的真实时长
var _attack_hit_at := 0.9 # 本次出手的命中时刻（按动画查表）
var _attack_hit_done := false
var _anim_durations := {} # 动画名 -> 时长，setup 时缓存
var _idle_queued := false # stand 已排队在技能后面，切 IDLE 时别重复 set
var _chase_block := 0.0 # 收招后的收势时间：这期间不许起跑，等 stand 队列接续完
var _hurt_timer := 0.0
var _target: Node2D
var _ghosts: Dictionary = {} # 已互相关闭碰撞的同伴（对穿状态）

var sprite: Node2D # SpineSprite
var _anim_state
var _current_anim := "" # 防同名循环动画重放抽搐
var _hp_bar: Node2D
var _hp_fill: ColorRect
var _sfx_player: AudioStreamPlayer


func _ready() -> void:
	add_to_group("enemies")
	_apply_type()
	hp = max_hp
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
	_bar_w = float(t["bar_w"])
	_bar_y = float(t["bar_y"])
	_number_y = float(t["number_y"])


## 刷怪器在 add_child 之后调用：按波次覆盖血量 / 速度 / 节奏，形态本身不动
func configure(cfg: Dictionary) -> void:
	if cfg.has("hp"):
		max_hp = int(cfg["hp"])
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
	data.call("set_default_mix", 0.2) # 混合从 0.1 加到 0.2：收招/起步的姿态过渡更柔，消除"一走动就闪一下"
	sprite.scale = Vector2(_scale * facing, _scale)
	_anim_state = sprite.call("get_animation_state")
	# 缓存攻击动画真实时长：比想象中长得多，攻击锁定必须按实际时长走，
	# 否则收招段被切掉 + 0.1s 交叉淡化 = 抽搐
	for n in _attack_anims:
		var a = data.call("find_animation", n)
		if a != null:
			_anim_durations[n] = a.call("get_duration")
	# 死亡动画时长也要缓存：尸体清理要等它播完
	var da = data.call("find_animation", str(_anim_map["dead"]))
	if da != null:
		_anim_durations[str(_anim_map["dead"])] = da.call("get_duration")
	_play(str(_anim_map["idle"]), true)


func _physics_process(delta: float) -> void:
	if state == State.DEAD:
		return
	_attack_cd = maxf(0.0, _attack_cd - delta)
	_chase_block = maxf(0.0, _chase_block - delta)
	_find_target()

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

	# 同伴分离力：同一水平线上靠太近就互相推开，避免几只怪叠成一团互相卡位
	if state != State.ATTACK:
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
	velocity.x = move_toward(velocity.x, _patrol_dir * patrol_speed, accel * delta)


func _chase_tick(delta: float) -> void:
	if _target == null:
		_set_state(State.PATROL)
		return
	var dx: float = _target.global_position.x - global_position.x
	var dy: float = absf(_target.global_position.y - global_position.y)
	if absf(dx) > lose_range:
		_target = null
		_set_state(State.PATROL)
		return
	facing = 1 if dx > 0.0 else -1
	_apply_facing()
	if absf(dx) <= attack_range and dy <= 60.0 and _attack_cd <= 0.0 and _can_attack():
		_start_attack()
		return
	# 贴太近但还在冷却：先退开一点保持站位，别和同伴挤在同一格
	if absf(dx) < keep_dist and _attack_cd > 0.0:
		velocity.x = move_toward(velocity.x, -facing * 80.0, accel * delta)
		return
	var acc := turn_accel if signf(velocity.x) != 0.0 and signf(velocity.x) != signf(dx) else accel
	velocity.x = move_toward(velocity.x, facing * chase_speed, acc * delta)


func _attack_tick(delta: float) -> void:
	_attack_timer -= delta
	# lunge 用半速制动带惯性（对齐玩家 brake*0.5 的思路）：原来 1500 秒刹，前冲位移几乎为零
	velocity.x = move_toward(velocity.x, 0.0, brake * 0.5 * delta)
	if not _attack_hit_done and _attack_timer <= _attack_dur - _attack_hit_at:
		_attack_hit_done = true
		_deal_hit()
	# 收招按纯时长驱动：_attack_dur 就是动画真实时长，到点的同一帧排队的 stand 恰好自动
	# 接续，时序严丝合缝。不能看 get_current(0).is_complete——stand 一旦接续，current 就
	# 变成 loop 的 stand，skill 的完成信号永远观测不到，之前只能靠 -0.3s 超时兜底退出，
	# 导致收招晚半拍、_chase_block 与 stand 接续错位 = 收招后"闪现抽搐"的根源。
	if _attack_timer <= 0.0:
		_attack_cd = attack_cooldown
		_chase_block = 0.35 # 收势：让排队的 stand 接续播一小段再起跑
		_release_token()
		_set_state(State.IDLE)


func _hurt_tick(delta: float) -> void:
	_hurt_timer -= delta
	velocity.x = move_toward(velocity.x, 0.0, brake * delta)
	if _hurt_timer <= 0.0:
		_set_state(State.CHASE if _target != null else State.IDLE)


# ---------- 动作 ----------

func _start_attack() -> void:
	state = State.ATTACK
	_attacker = self # 占住出手令牌
	# 按当前距离挑招式：打得着的才起手，避免距离 90 却甩 400px 的长鞭、或者反过来够不着
	var dist := 0.0
	if _target != null:
		dist = absf(_target.global_position.x - global_position.x)
	var pool: Array = []
	for n in _attack_anims:
		if float(_ranges.get(n, attack_range)) >= dist - 10.0:
			pool.append(n)
	var anim := ""
	if pool.is_empty():
		# 所有招都够不着：用最远那招（至少方向对、范围最大）
		var far_r := -1.0
		for n in _attack_anims:
			var fr := float(_ranges.get(n, attack_range))
			if fr > far_r:
				far_r = fr
				anim = str(n)
	elif _pick_nearest:
		# 精英：挑"刚好够得着"的最近一招，近身不会甩 580px 的大招
		var best_r := INF
		for n in pool:
			var br := float(_ranges.get(n, attack_range))
			if br < best_r:
				best_r = br
				anim = str(n)
	else:
		anim = str(pool[randi() % pool.size()])
	_attack_dur = _anim_durations.get(anim, 1.5)
	_attack_timer = _attack_dur
	# hit_at 由 range_probe 标定的是骨架伸展峰值时刻（武器最远端 = 动画打到人的那一帧），
	# 直接用该时刻结算：早一帧是"未打到先判定"，晚一帧是"打到却没判定"，都不贴动画
	_attack_hit_at = float(_hit_at_map.get(anim, 0.9))
	_attack_hit_done = false
	velocity.x = facing * attack_lunge # 出手带一段前冲
	_play(anim, false) # _play 内部会设好 _current_anim
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


func _deal_hit() -> void:
	if _target == null:
		return
	var dx: float = _target.global_position.x - global_position.x
	var dy: float = absf(_target.global_position.y - global_position.y)
	var rng: float = float(_ranges.get(_current_anim, attack_range))
	var in_front := dx == 0.0 or (dx > 0.0) == (facing > 0)
	var side_ok: bool = in_front or bool(_both_anims.get(_current_anim, false))
	if side_ok and absf(dx) <= rng and dy <= attack_hit_height:
		_target.call("hurt", 1, Vector2(facing * 220.0, -80.0), self)


func take_damage(amount: int, source_x: float) -> void:
	if state == State.DEAD:
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
	# 受击硬直分层：普通怪轻击就断招；精英霸体，只有重击（damage >= armor）才打断
	if amount < _armor:
		_flash()
		return
	_release_token() # 被打断的出手要交还令牌，否则其他怪永远等不到出手机会
	state = State.HURT
	_hurt_timer = hurt_time
	_idle_queued = false # set_animation 已清掉队列里的 stand
	var dir := 1.0 if global_position.x >= source_x else -1.0
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


func _spawn_number(amount: int) -> void:
	var dn := DAMAGE_NUMBER.new()
	dn.setup(str(amount), DMG_COLOR)
	dn.global_position = global_position + Vector2(randf_range(-12.0, 12.0), _number_y)
	get_tree().current_scene.add_child(dn)


func die() -> void:
	state = State.DEAD
	_release_token()
	velocity = Vector2.ZERO
	_update_hp_bar()
	$CollisionShape2D.set_deferred("disabled", true)
	_play(str(_anim_map["dead"]), false)
	_drop_bone()
	# 尸体消散时一团墨散开，盖住淡出
	FX.spawn(get_tree().current_scene, "vanish", global_position,
		{"scale": _scale * 1.6, "z": 5})
	Meta.add_kill(Run.skull_id) # 局外养成：累计击杀 + 当前形态契合
	Score.add_kill() # 本局击杀计数（结算战绩用）
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


## 掉落墨骨：从脚下抛出一枚，落地后玩家靠近自动吸附（精英掉 3 枚，值得啃）
func _drop_bone() -> void:
	for _i in _bones:
		var b := BONE_PICKUP.new()
		b.global_position = global_position + Vector2(randf_range(-18.0, 18.0), 0.0)
		get_tree().current_scene.add_child(b)


# ---------- 工具 ----------

func _find_target() -> void:
	if _target != null and is_instance_valid(_target):
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
	if _target == null:
		return false
	var dx: float = absf(_target.global_position.x - global_position.x)
	var dy: float = absf(_target.global_position.y - global_position.y)
	return dx <= radius and dy <= 90.0


func _set_state(new_state: int) -> void:
	if state == new_state:
		return
	state = new_state
	match state:
		State.IDLE:
			_idle_timer = idle_time
			if _idle_queued:
				# stand 已被 Spine 自动接续播放，只同步记录，不重复 set（重开会重开淡化）
				_current_anim = str(_anim_map["idle"])
			else:
				_play(str(_anim_map["idle"]), true)
			_idle_queued = false
		State.PATROL:
			_idle_queued = false
			_play(str(_anim_map["patrol"]), true)
		State.CHASE:
			_idle_queued = false # set_animation 会清掉队列里的 stand
			_play(str(_anim_map["chase"]), true)


func _apply_facing() -> void:
	if sprite:
		sprite.scale.x = _scale * facing


func _play(anim: String, loop: bool) -> void:
	if _anim_state == null:
		return
	if loop and anim == _current_anim:
		return
	_current_anim = anim
	_anim_state.call("set_animation", anim, loop, 0)


func _queue(anim: String, loop: bool) -> void:
	if _anim_state:
		_anim_state.call("add_animation", anim, 0.0, loop, 0)
