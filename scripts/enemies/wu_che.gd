extends "res://scripts/enemies/boss.gd"

## 武车独立状态机：没有普攻与步行，只靠武撞往返；耐久只在撞墙时消耗。
## 用户动画编号：2=atked_fall_end，4=dead，6=skill01，7=skill02，
## 10=speed_run，11=stand，12=stop，14=zhuanshen。

const S_START := 200
const S_RUN := 201
const S_BRAKE := 202
const S_TURNING := 203
const S_SUMMON := 204

const START_ANIM := "skill01"
const RUN_ANIM := "speed_run"
const BRAKE_ANIM := "stop"
const TURN_ANIM := "zhuanshen"
const SUMMON_ANIM := "skill02"
const IDLE_ANIM := "stand"
const WEAK_IDLE_ANIM := "dead"

const ADVENTURE_DURABILITY := [4, 5, 6, 6, 7]
const ENDLESS_MAX_DURABILITY := 9
const START_MOVE_AT := 1.15 # 6 号动画前段原地启动，后段才开始位移
const CHARGE_SPEED := 980.0
const HEAD_OFFSET := 330.0 # 原点到马头的距离，碰边即刹车
const CHARGE_HALF_WIDTH := 285.0
const CHARGE_HEIGHT := 190.0

const NORMAL_SCENES := [
	"res://scenes/enemies/c016.tscn",
	"res://scenes/enemies/c017.tscn",
	"res://scenes/enemies/c035.tscn",
]
const ELITE_SCENES := [
	"res://scenes/enemies/c037_elite.tscn",
	"res://scenes/enemies/c018_elite.tscn",
	"res://scenes/enemies/c012_elite.tscn",
]

var arena_left := 0.0
var arena_right := 1920.0
## 斗蛐蛐召唤安全区（由竞技场写入）：所有小弟只允许落在这条 x 区间内、贴着地面生成。
## 留 <=0 表示没有指定，退回原竞技场可站立范围；剧情模式不写，行为与原来一致。
var summon_min_x := -1.0
var summon_max_x := -1.0
var summon_ground_y := -1.0

## 生成点校验间距：到锁定目标、武车本体、其他单位的最近距离，
## 以及为了让脚底不被安全边距顶进地面，统一抬高 1px 生成。
const SUMMON_SELF_CLEAR := 360.0
const SUMMON_TARGET_CLEAR := 240.0
const SUMMON_UNIT_CLEAR := 90.0
const SUMMON_CHARIOT_CLEAR := 300.0
const SUMMON_LIFT := 1.0

var _wc_charge_dir := 1
var _charge_elapsed := 0.0
var _charge_moving := false
var _charge_ghost := false
var _charge_contact_done := false
var _charges_completed := 0
var _summons: Array = []
var _summon_total := 0
var _summon_index := 0
var _summon_elites_left := 0
var _summon_bonus := 0
var _position_history: Array = []
var _history_time := 0.0


func _apply_type() -> void:
	super()
	max_hp = _durability_for_run()
	hp = max_hp
	boss_label = "武车"
	# 斗蛐蛐：武车本体永远不是可攻击目标，耐久只由小弟阵亡消耗。
	duel_untargetable = true


func _ready() -> void:
	super()
	state = State.IDLE
	velocity = Vector2.ZERO
	_position_history = [{"time": 0.0, "position": global_position}]
	_play(_idle_anim(), true)


## 通用 Boss 先导结束会进入 CHASE；武车没有步行追击，必须回到自己的冲锋链。
func finish_entrance() -> void:
	if state == State.DEAD:
		return
	_state_timer = 0.0
	_enter_wait()


func _all_anim_names() -> Array:
	var names := super()
	for anim in [START_ANIM, RUN_ANIM, BRAKE_ANIM, TURN_ANIM, SUMMON_ANIM, IDLE_ANIM, WEAK_IDLE_ANIM, "atked_fall_end"]:
		if not names.has(anim):
			names.append(anim)
	return names


func _durability_for_run() -> int:
	if Run.mode == Run.MODE_ENDLESS:
		var depth_value := mini(ENDLESS_MAX_DURABILITY, 5 + int((Run.depth - 1) / 2))
		return maxi(2, int(round(float(depth_value) * Run.enemy_hp_mul())))
	var base := int(ADVENTURE_DURABILITY[clampi(Run.difficulty, 0, ADVENTURE_DURABILITY.size() - 1)])
	return maxi(2, int(round(float(base) * Run.boss_hp_scale())))


func _idle_anim() -> String:
	return WEAK_IDLE_ANIM if (max_hp - hp) * 2 >= max_hp else IDLE_ANIM


func _physics_process(delta: float) -> void:
	if net_puppet:
		return
	if state == State.DEAD:
		return
	if _stop_timer > 0.0:
		_stop_timer -= delta
		if _stop_timer <= 0.0:
			_end_stop(true)
		return
	_pipa_status_tick(delta)
	_record_position(delta)
	if _slow_timer > 0.0:
		_slow_timer = maxf(0.0, _slow_timer - delta)
		if _slow_timer <= 0.0:
			_slow_scale = 1.0
	_find_target()
	velocity.x = 0.0
	match state:
		S_ENTER:
			_state_timer -= delta
			if _state_timer <= 0.0:
				_enter_wait()
		State.IDLE:
			_prune_summons()
			_play(_idle_anim(), true)
			if _summons.is_empty():
				_start_charge()
		S_START:
			_charge_elapsed += delta
			if not _charge_moving and _charge_elapsed >= START_MOVE_AT:
				_charge_moving = true
				_set_ghost(true)
			if _charge_moving:
				_advance_charge(delta)
			if state == S_START and _charge_elapsed >= float(_anim_durations.get(START_ANIM, 2.733)):
				state = S_RUN
				_play(RUN_ANIM, true)
		S_RUN:
			_advance_charge(delta)
		S_BRAKE:
			_state_timer -= delta
			if _state_timer <= 0.0:
				if hp <= 0:
					die()
					return
				_begin_turn()
		S_TURNING:
			_state_timer -= delta
			if _state_timer <= 0.0:
				facing = -facing
				_apply_facing()
				_begin_wave()
		S_SUMMON:
			_state_timer -= delta
			if _state_timer <= 0.0:
				_summon_animation_finished()
	if state != State.DEAD and not _charge_ghost:
		# 已落地时不再调用 move_and_slide：停车恢复实体若与贴墙玩家重叠，
		# 物理恢复会把武车向上推到玩家头顶；实体形状本身仍会正常阻挡玩家。
		if is_on_floor():
			velocity.y = 0.0
		else:
			velocity.y = minf(velocity.y + gravity * delta, 900.0)
			move_and_slide()


func _record_position(delta: float) -> void:
	_history_time += delta
	_position_history.append({"time": _history_time, "position": global_position})
	var cutoff := _history_time - 2.0
	# 保留 cutoff 前最近的一帧，接触时能取到不晚于 2 秒前的真实落点。
	while _position_history.size() > 1 and float(_position_history[1]["time"]) <= cutoff:
		_position_history.pop_front()


func _charge_history_position() -> Vector2:
	if _position_history.is_empty():
		return global_position
	var past: Vector2 = _position_history[0]["position"]
	var cutoff := _history_time - 2.0
	for sample in _position_history:
		if float(sample["time"]) > cutoff:
			break
		past = sample["position"]
	return Vector2(clampf(past.x, arena_left, arena_right), past.y)


func _enter_wait() -> void:
	state = State.IDLE
	velocity = Vector2.ZERO
	_set_ghost(false)
	_play(_idle_anim(), true)


func _start_charge() -> void:
	if state == State.DEAD or not _summons.is_empty():
		return
	_release_token()
	_trigger_six_senses()
	if state == State.DEAD:
		return
	state = S_START
	_wc_charge_dir = facing
	_charge_elapsed = 0.0
	_charge_moving = false
	_charge_contact_done = false
	velocity = Vector2.ZERO
	_play(START_ANIM, false)
	_track_fx(_telegraph()) # 蓄力墨环也归到本车名下，撞边致死时同帧一起清掉


func _advance_charge(delta: float) -> void:
	if state != S_START and state != S_RUN:
		return
	velocity = Vector2(_wc_charge_dir * CHARGE_SPEED * _slow_scale, 0.0)
	global_position.x += velocity.x * delta
	_charge_hit_check()
	var head_x := global_position.x + _wc_charge_dir * HEAD_OFFSET
	if (_wc_charge_dir > 0 and head_x >= arena_right) or (_wc_charge_dir < 0 and head_x <= arena_left):
		_begin_brake()


func _charge_hit_check() -> void:
	if _charge_contact_done or _target == null or not is_instance_valid(_target):
		return
	var dx: float = _target.global_position.x - global_position.x
	var dy := absf(_target.global_position.y - global_position.y)
	if absf(dx) > CHARGE_HALF_WIDTH + _radius_of(_target) or dy > CHARGE_HEIGHT:
		return
	# 一次武撞只接触结算一次；玩家保留原有回拉，敌人目标直接结算互伤。
	_charge_contact_done = true
	if not duel_mode and not _target.is_in_group("enemies"):
		_target.global_position = _charge_history_position()
	_hit_status_target(_target, 2, Vector2(_wc_charge_dir * 420.0, -120.0), {
		"wu_che_charge": true,
		"anim": START_ANIM,
		"hit_at": _charge_elapsed,
		"cast_id": _charges_completed + 1,
		"cast_owner_id": get_instance_id(),
	})


func on_player_hit(amount: int, move: Dictionary, player: Node) -> void:
	super(amount, move, player)
	if amount <= 0 or not bool(move.get("wu_che_charge", false)):
		return
	_summon_bonus += 1
	if player.is_in_group("player"):
		player.set("wu_che_wanted", true) # 只有一层；再次实伤只是保持并续到下一次闪避解除
	var dn := DAMAGE_NUMBER.new()
	dn.setup("通缉", Color(0.78, 0.38, 0.28))
	dn.global_position = (player as Node2D).global_position + Vector2(0, -150)
	var root := get_tree().current_scene
	if root != null:
		root.add_child(dn)


func _begin_brake() -> void:
	if state == S_BRAKE or state == State.DEAD:
		return
	state = S_BRAKE
	_charge_moving = false
	global_position.x = arena_right - HEAD_OFFSET if _wc_charge_dir > 0 else arena_left + HEAD_OFFSET
	velocity = Vector2.ZERO
	_set_ghost(false) # 马头碰边、开始刹车时立刻恢复实体
	_charges_completed += 1
	# 武车核心机制：撞墙只掉 1 点耐久（首轮入场不扣），斗蛐蛐同样沿用，不做模式特判。
	if _charges_completed > 1:
		hp = maxi(0, hp - 1)
		hp_changed.emit(hp, max_hp)
	_state_timer = float(_anim_durations.get(BRAKE_ANIM, 0.8))
	_play(BRAKE_ANIM, false)
	Feel.shake(9.0, 0.28)
	_fx_play(_fx.get("charge_wall", {}))
	# 撞边致死：碰撞触发的当帧直接清场，不等 0.8 秒刹车动画、不走延迟的死亡流程，
	# 否则 2.5 秒的地裂残影会一直卡在地图边界上。
	if hp <= 0 and duel_mode:
		_wall_death_purge()


## 边界撞击致死：同一帧内完成「特效清理 → 实体注销 → 隐藏禁用 → 释放」。
## 中间不 await、不进定时器、不排队，保证没有一帧的清理滞后。
func _wall_death_purge() -> void:
	if state == State.DEAD:
		return
	state = State.DEAD
	hp = 0
	velocity = Vector2.ZERO
	_charge_ghost = false
	_charge_moving = false
	_charge_contact_done = true
	_attack_hits_left.clear()
	# 1~4：停掉本车所有归属特效的发射/更新，摘出场景树并释放引用（含状态 Spine 子特效）
	_clear_owned_fx()
	_clear_status_effects()
	# 6：从竞技场实体管理系统注销——血条行置空占位，同伴表/敌对表/锁定目标同步摘引用
	var parent := get_parent()
	if parent != null and parent.has_method("_forget_unit"):
		parent.call("_forget_unit", self)
	_summons.clear()
	_position_history.clear()
	# 5：立刻不可见、不再参与任何更新；实体碰撞同帧关闭，物理回调安全
	visible = false
	set_process(false)
	set_physics_process(false)
	var shape := get_node_or_null("CollisionShape2D")
	if shape != null:
		shape.set_deferred("disabled", true)
	queue_free()


func _set_ghost(value: bool) -> void:
	_charge_ghost = value
	$CollisionShape2D.set_deferred("disabled", value)


func _begin_turn() -> void:
	state = S_TURNING
	_state_timer = float(_anim_durations.get(TURN_ANIM, 1.4))
	velocity = Vector2.ZERO
	_play(TURN_ANIM, false)


func _begin_wave() -> void:
	_trigger_six_senses()
	if state == State.DEAD:
		return
	_summon_total = max_hp - hp + 3 + _summon_bonus
	_summon_bonus = 0
	_summon_index = 0
	_summon_elites_left = int(_summon_total / 4)
	_play_next_summon()


func _play_next_summon() -> void:
	state = S_SUMMON
	_state_timer = float(_anim_durations.get(SUMMON_ANIM, 2.25))
	velocity = Vector2.ZERO
	_play(SUMMON_ANIM, false)


func _summon_animation_finished() -> void:
	# 第 4、8……个固定为精英，其余从普通池随机；数量严格为 floor(总数 / 4)。
	var elite := (_summon_index + 1) % 4 == 0 and _summon_elites_left > 0
	_spawn_one(elite)
	if elite:
		_summon_elites_left -= 1
	_summon_index += 1
	if _summon_index < _summon_total:
		_play_next_summon()
	else:
		_enter_wait()


func _spawn_one(elite: bool) -> void:
	var pool := ELITE_SCENES if elite else NORMAL_SCENES
	var scene = load(str(pool[randi() % pool.size()])) if not pool.is_empty() else null
	var e = scene.instantiate() if scene != null else null
	if e == null:
		return
	e.set("wu_che_summon", true)
	e.set("player_ally", player_ally) # 只继承给本武车自己的子召唤，不触碰其他武车的 _summons
	if duel_mode:
		# 斗蛐蛐：召唤物必须继承对战名单与伤害系数。否则它会走普通分支去找 player 组
		#（斗蛐蛐里没有），生成后无目标乱走。duel_peers 是全场共享数组，小弟也要登记进去。
		e.set("duel_mode", true)
		e.set("duel_side", duel_side)
		e.set("duel_foes", duel_foes)
		e.set("duel_peers", duel_peers)
		e.set("duel_dmg_scale", duel_dmg_scale)
	e.died.connect(_on_summon_died.bind(e))
	get_parent().add_child(e)
	if duel_mode and not duel_peers.has(e):
		duel_peers.append(e)
	e.global_position = _spawn_position(e)
	if elite:
		e.configure({"speed": 0.9})
	else:
		e.configure({
			"hp": 6,
			"speed": 1.0,
			"attack_range": randf_range(140.0, 205.0),
			"keep_dist": randf_range(70.0, 110.0),
			"attack_cooldown": randf_range(1.6, 2.4),
		})
	_summons.append(e)


## 只允许落在竞技场写入的中间安全区内，并且必须贴着地面生成。
## 每个候选点都要校验：离锁定目标、离武车本体、离场上所有单位（含敌方武车的大碰撞块）
## 都留有足够间距——压在别人身体上生成会被物理去穿透弹进地面，就是「卡到地下」的成因。
## 随机取点失败时在安全区内枚举最空的一格兜底，绝不把坐标 clamp 到边界或武车身上。
func _spawn_position(newcomer) -> Vector2:
	var min_x := summon_min_x
	var max_x := summon_max_x
	if max_x - min_x < 1.0:
		min_x = arena_left + 110.0
		max_x = arena_right - 110.0
	var ground_y := summon_ground_y if summon_ground_y > 0.0 else global_position.y
	for attempt in 24:
		var x := randf_range(min_x, max_x)
		if _spawn_gap(x, newcomer) >= 1.0:
			return Vector2(x, ground_y - SUMMON_LIFT)
	var best_x := clampf(global_position.x, min_x, max_x)
	var best_gap := -INF
	for i in 33:
		var x := lerpf(min_x, max_x, float(i) / 32.0)
		var gap := _spawn_gap(x, newcomer)
		if gap > best_gap:
			best_gap = gap
			best_x = x
	return Vector2(best_x, ground_y - SUMMON_LIFT)


## 候选点的安全裕量：>=1 表示到最近一个干扰源的距离都达标，数值越大越空。
func _spawn_gap(x: float, newcomer) -> float:
	var gap := INF
	if is_instance_valid(_target):
		gap = minf(gap, (absf(x - _target.global_position.x) - SUMMON_TARGET_CLEAR) / SUMMON_TARGET_CLEAR)
	gap = minf(gap, (absf(x - global_position.x) - SUMMON_SELF_CLEAR) / SUMMON_SELF_CLEAR)
	var others: Array = duel_peers if duel_mode else _summons
	for u in others:
		if not is_instance_valid(u) or u == newcomer or u == self:
			continue
		if u.is_queued_for_deletion() or int(u.get("hp")) <= 0:
			continue # 尸体不占位，否则安全区会被越挤越满
		var clear := SUMMON_CHARIOT_CLEAR if bool(u.get("duel_untargetable")) else SUMMON_UNIT_CLEAR
		gap = minf(gap, (absf(x - u.global_position.x) - clear) / clear)
	return gap


func _prune_summons() -> void:
	_summons = _summons.filter(func(e): return is_instance_valid(e) and int(e.get("hp")) > 0)


func _on_summon_died(e) -> void:
	_summons.erase(e)


## 时停直接取消整条武撞链；已生成的召唤物保留，但未结算的召唤不再补发。
func time_stop(dur: float) -> void:
	if state == State.DEAD:
		return
	if state >= S_START and state <= S_SUMMON:
		_release_token()
		_attack_hits_left.clear()
		_charge_elapsed = 0.0
		_charge_moving = false
		_charge_contact_done = false
		_summon_total = 0
		_summon_index = 0
		_summon_elites_left = 0
		_state_timer = 0.0
		_enter_wait()
	super(dur)


## 玩家攻击、流血与其他直接伤害都不能削减耐久，只保留命中反馈。
func take_damage(amount: int, source_x: float) -> void:
	if state == State.DEAD or amount <= 0:
		return
	if _invincible:
		_flash()
		return
	_sfx_player.stream = SFX_HIT_QI
	_sfx_player.play()
	_flash()
	var off_x := signf(source_x - global_position.x) * 60.0
	_fx_play(_fx.get("hit", {}), Vector2(off_x, _number_y * 0.55))


func _direct_damage(_amount: int, _color: Color = DMG_COLOR) -> void:
	pass


func die() -> void:
	var pl := get_tree().get_first_node_in_group("player")
	if not player_ally and pl != null:
		pl.set("wu_che_wanted", false)
	# 正常循环本就会等召唤物清空；异常时序若仍有存活个体，死亡与后续先导期间不再行动。
	for e in _summons:
		if is_instance_valid(e) and int(e.get("hp")) > 0:
			e.set("velocity", Vector2.ZERO)
			e.set_physics_process(false)
			e.set_process(false)
	hp = 0
	super()
