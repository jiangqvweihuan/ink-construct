extends "res://scripts/enemies/boss.gd"

## 墨霆独立战斗状态机：六招不进入旧阶段随机池。
## 用户动画编号 -> 资源名：3=def_break，4=run，5=skill01，7=skill03，
## 8=skill04，9=skill05，10=skill06，12=skill08，13=skill02-01，16=skill08-cankao。

const S_CAST := 200
const S_BREAK := 201

const BASIC := "skill03" # 奋挥
const TREMOR := "skill04" # 墨颤
const RUSH := "skill05" # 墨冲
const SLAM := "skill06" # 断岳
const LEAP := "skill08" # 陨构（按距离选 skill08 / skill08-cankao）
const LASER := "skill02-01" # 贯昼
const INTRO_ANIM := "skill01"
const MOVE_ORDER := [BASIC, TREMOR, RUSH, SLAM, LEAP, LASER]
const COOLDOWNS := {TREMOR: 30.0, RUSH: 35.0, SLAM: 25.0, LEAP: 40.0, LASER: 16.0}
const CENTER_RANGES := {BASIC: 200.0, RUSH: 105.0, SLAM: 185.0, LEAP: 175.0}
const LASER_RELEASE_DISTANCE := 340.0
const ATTACK_DESIRE_TIME := 5.0
const HOLD_DISTANCE := 380.0
const HOLD_TOLERANCE := 45.0
const YIELD_DISTANCE := 120.0
const FAST_DESIRE_SCALE := 2.0
const RUSH_START := 1.62 # 动画蓄力结束、机体开始前倾后才起步。
const RUSH_END := 3.60
const GROUND_IMPACT_X := 240.0 # 断岳 / 陨构的拍地点在骨架原点身前，不在 Boss 脚底。
const GROUND_CRACK_SINK := 90.0 # crack 贴图主体离帧底约 90px，整体下压让爆裂真正从地面向上长
const LASER_OFFSET := Vector2(120.0, -115.0)
const LASER_START := 0.85 # 贯昼发射帧
const LASER_END := 1.65 # 光束持续 0.8 秒（原 1.6 秒的一半）
const LASER_SEGMENT_DAMAGE := 2 # 贯昼只有两段，每段固定 2 伤

var _move_cds: Dictionary = {}
var _battle_time := 0.0
var _attack_desire := 0.0
var _approach_yield := 0.0
var _planned_move := ""
var _recent_hits: Array = []
var _cast_move := ""
var _cast_visual := ""
var _cast_elapsed := 0.0
var _cast_duration := 0.0
var _cast_events: Array = []
var _cast_id := 0
var _tick_started := false
var _tick_acc := 0.0
var _marker: Node2D = null
var _marker_locked := false
var _grabbed_player: Node2D = null
var _laser: Node2D = null
var _jump_target_x := 0.0
var _jump_speed := 620.0


class RedMark extends Node2D:
	var radius := 66.0

	func _draw() -> void:
		draw_circle(Vector2.ZERO, radius, Color(0.75, 0.06, 0.04, 0.18))
		draw_arc(Vector2.ZERO, radius, 0.0, TAU, 64, Color(1.0, 0.16, 0.10, 0.95), 4.0, true)
		draw_arc(Vector2.ZERO, radius * 0.68, 0.0, TAU, 48, Color(1.0, 0.28, 0.16, 0.75), 2.0, true)
		draw_line(Vector2(-radius, 0), Vector2(radius, 0), Color(1.0, 0.22, 0.14, 0.8), 2.0, true)
		draw_line(Vector2(0, -radius * 0.35), Vector2(0, radius * 0.35), Color(1.0, 0.22, 0.14, 0.8), 2.0, true)


class InkLaser extends Node2D:
	## 激光视觉 = 用户提供的红色炮口贴图负责起段 + 程序化光束补足到射程末端。
	## 贴图只有 245px 宽，覆盖不到整条光束；后半段用同色系的脉冲光束自然接上。
	const ART := "res://art/fx/mo_ting_laser.png"
	const ART_SCALE := 1.8
	const ART_MUZZLE_X := 110.0 # 贴图内炮口中心
	const ART_CENTER_X := 122.5 # 245 宽贴图的中心
	const ART_END_X := 245.0 # 贴图光束在右边缘被截断，从这里开始程序化延伸
	const ART_END := (ART_END_X - ART_MUZZLE_X) * ART_SCALE

	var length := 1000.0
	var direction := 1.0
	var pulse := 0.0
	var _art: Sprite2D

	func _ready() -> void:
		var tex: Texture2D = load(ART)
		if tex == null:
			return
		_art = Sprite2D.new()
		_art.texture = tex
		# 让贴图里的炮口中心落在节点原点，光束才能从发射点自然向右延伸
		_art.offset = Vector2(ART_CENTER_X - ART_MUZZLE_X, 0.0)
		_art.scale = Vector2(direction * ART_SCALE, ART_SCALE)
		add_child(_art)

	func _process(delta: float) -> void:
		pulse += delta * 18.0
		if _art != null:
			_art.scale.x = direction * ART_SCALE
		queue_redraw()

	func _draw() -> void:
		var start := Vector2(direction * ART_END, 0.0)
		var end := Vector2(direction * length, 0.0)
		if absf(end.x) <= absf(start.x):
			return
		var width := 76.0 + sin(pulse) * 5.0
		draw_line(start, end, Color(0.52, 0.34, 0.95, 0.22), width + 46.0, true)
		draw_line(start, end, Color(0.95, 0.38, 0.82, 0.62), width, true)
		draw_line(start, end, Color(1.0, 0.72, 0.95, 0.92), 26.0, true)
		draw_line(start, end, Color(1.0, 0.97, 1.0, 0.98), 10.0, true)


func _ready() -> void:
	super()
	for move in MOVE_ORDER:
		_move_cds[move] = 0.0
	_set_state(State.CHASE)


func _all_anim_names() -> Array:
	var names: Array = super()
	names.append(INTRO_ANIM)
	var pools: Dictionary = BossTypes.get_boss(type_id).get("move_pool", {})
	for move in pools:
		for visual in pools[move]:
			names.append(str(visual))
	return names


## 正式房间的黑底对峙先导期间，实体会被房间暂时隐藏并停处理；结束后由 finish_entrance 接手。
func entrance() -> void:
	_release_token()
	state = S_ENTER
	_state_timer = float(_anim_durations.get(INTRO_ANIM, 2.2))
	velocity = Vector2.ZERO
	_play(INTRO_ANIM, false)
	hp_changed.emit(hp, max_hp)


func finish_entrance() -> void:
	if state == State.DEAD:
		return
	_battle_time = 0.0
	_attack_desire = 0.0
	_approach_yield = 0.0
	_planned_move = ""
	_recent_hits.clear()
	_set_state(State.CHASE)


func _physics_process(delta: float) -> void:
	if state == State.DEAD:
		return
	if _stop_timer > 0.0:
		_stop_timer -= delta
		if _stop_timer <= 0.0:
			_end_stop(true)
		return
	if state != S_ENTER:
		_battle_time += delta
	if state != S_ENTER and state != State.CHASE:
		_attack_desire = minf(ATTACK_DESIRE_TIME, _attack_desire + delta)
	for move in _move_cds:
		_move_cds[move] = maxf(0.0, float(_move_cds[move]) - delta)
	if state == S_CAST or state == S_BREAK:
		_attack_cd = maxf(0.0, _attack_cd - delta)
		_pipa_status_tick(delta)
		_find_target()
		if state == S_CAST:
			_cast_tick(delta)
		else:
			_state_timer -= delta
			velocity.x = move_toward(velocity.x, 0.0, 1500.0 * delta)
			if _state_timer <= 0.0:
				_set_state(State.CHASE)
		velocity.y = minf(velocity.y + gravity * delta, 900.0)
		move_and_slide()
		return
	super(delta)


## 常驻追击：欲望满后预选一招并贴近到实际命中区域；墨颤保留锁定玩家的目标型机制。
func _chase_tick(delta: float) -> void:
	if _target == null or not is_instance_valid(_target):
		velocity.x = move_toward(velocity.x, 0.0, brake * delta)
		_set_state(State.IDLE)
		return
	var dx: float = _target.global_position.x - global_position.x
	var dy := absf(_target.global_position.y - global_position.y)
	facing = 1 if dx >= 0.0 else -1
	_apply_facing()
	var dist := absf(dx)
	var player_vx := 0.0
	var target_velocity = _target.get("velocity")
	if typeof(target_velocity) == TYPE_VECTOR2:
		player_vx = target_velocity.x
	var approaching: bool = dx * player_vx < -1.0
	var retreating: bool = dx * player_vx > 1.0
	if not approaching:
		_approach_yield = 0.0
	var desire_scale := FAST_DESIRE_SCALE if retreating and dist > HOLD_DISTANCE else 1.0
	_attack_desire = minf(ATTACK_DESIRE_TIME, _attack_desire + delta * desire_scale)
	if _attack_desire < ATTACK_DESIRE_TIME:
		if approaching and dist < HOLD_DISTANCE:
			if _approach_yield < YIELD_DISTANCE:
				var yield_step := minf(chase_speed * delta, YIELD_DISTANCE - _approach_yield)
				_approach_yield += yield_step
				velocity.x = move_toward(velocity.x, -facing * chase_speed, accel * delta)
				_play(str(_anim_map["chase"]), true)
				return
			_attack_desire = ATTACK_DESIRE_TIME
		elif dist > HOLD_DISTANCE + HOLD_TOLERANCE:
			velocity.x = move_toward(velocity.x, facing * chase_speed, accel * delta)
			_play(str(_anim_map["chase"]), true)
			return
		elif dist < HOLD_DISTANCE - HOLD_TOLERANCE:
			velocity.x = move_toward(velocity.x, -facing * chase_speed, accel * delta)
			_play(str(_anim_map["chase"]), true)
			return
		else:
			velocity.x = move_toward(velocity.x, 0.0, brake * delta)
			_play(str(_anim_map["idle"]), true)
			return
	if _planned_move.is_empty():
		_planned_move = _choose_mo_move(dist)
	if _planned_move == TREMOR:
		if _attack_cd <= 0.0:
			_start_mo_move(TREMOR)
		else:
			velocity.x = move_toward(velocity.x, 0.0, brake * delta)
			_play(str(_anim_map["idle"]), true)
		return
	# 贯昼有 120px 的可见起点；玩家贴身时改用真正能命中的近身招，不向后拉距。
	if _planned_move == LASER and dist < LASER_OFFSET.x:
		_planned_move = SLAM if float(_move_cds[SLAM]) <= 0.0 else BASIC
	var in_range := false
	if _planned_move == LASER:
		in_range = dy <= 180.0 and dist >= LASER_OFFSET.x and dist <= LASER_RELEASE_DISTANCE
	else:
		var release_reach := float(CENTER_RANGES[_planned_move])
		in_range = dy <= 180.0 and dist <= release_reach + _radius_of(_target)
	if in_range:
		if _attack_cd <= 0.0:
			_start_mo_move(_planned_move)
		else:
			velocity.x = move_toward(velocity.x, 0.0, brake * delta)
			_play(str(_anim_map["idle"]), true)
		return
	velocity.x = move_toward(velocity.x, facing * chase_speed, accel * delta)
	_play(str(_anim_map["chase"]), true)


func _choose_mo_move(dist: float) -> String:
	if _battle_time >= 5.0 and float(_move_cds[TREMOR]) <= 0.0:
		return TREMOR
	for move in [LEAP, RUSH]:
		if float(_move_cds[move]) <= 0.0:
			return move
	if dist >= LASER_OFFSET.x and float(_move_cds[LASER]) <= 0.0:
		return LASER
	if float(_move_cds[SLAM]) <= 0.0:
		return SLAM
	return BASIC


func _start_mo_move(move: String) -> void:
	_cleanup_cast()
	if move != BASIC:
		_trigger_six_senses()
		if state == State.DEAD:
			return
	_cast_id += 1
	_attack_cast_id = _cast_id # 供测试与终局对演识别同一次起手。
	_cast_move = move
	_cast_visual = move
	_cast_elapsed = 0.0
	_attack_desire = 0.0
	_approach_yield = 0.0
	_tick_started = false
	_tick_acc = 0.0
	if move == LEAP and _target != null and is_instance_valid(_target):
		var dist := absf(_target.global_position.x - global_position.x)
		_cast_visual = "skill08-cankao" if dist >= 800.0 else "skill08"
		_jump_target_x = clampf(_target.global_position.x, ARENA_L + 90.0, ARENA_R - 90.0)
		_jump_speed = 820.0 if _cast_visual == "skill08-cankao" else 580.0
	_cast_duration = float(_anim_durations.get(_cast_visual, 1.0))
	_cast_events = _events_for(move)
	state = S_CAST
	velocity.x = 0.0
	if COOLDOWNS.has(move):
		_move_cds[move] = float(COOLDOWNS[move]) * cd_scale
	_play(_cast_visual, false)
	_telegraph()
	if move == TREMOR:
		_spawn_marker()


func _events_for(move: String) -> Array:
	match move:
		BASIC:
			return [
				{"at": 0.63, "kind": "basic", "damage": 1, "range": 400.0},
				{"at": 1.53, "kind": "basic", "damage": 1, "range": 410.0},
				{"at": 2.61, "kind": "basic", "damage": 3, "range": 427.0},
			]
		TREMOR:
			return [
				{"at": 1.26, "kind": "mark_lock"},
				{"at": 1.62, "kind": "tremor_grab"},
				{"at": 2.48, "kind": "tremor_stab"},
				{"at": 2.92, "kind": "tremor_sunder"},
				{"at": 3.36, "kind": "tremor_sunder"},
			]
		SLAM:
			return [{"at": 1.48, "kind": "slam"}]
		LEAP:
			return [
				{"at": 0.18, "kind": "leap_lift"},
				{"at": 1.28, "kind": "leap_land"},
			]
		LASER:
			# 只结算两段，每段 2 伤；两段都在 0.8 秒的光束窗口内落下。
			return [
				{"at": LASER_START, "kind": "laser_segment"},
				{"at": LASER_START + 0.72, "kind": "laser_segment"},
			]
	return []


func _cast_tick(delta: float) -> void:
	_cast_elapsed += delta
	if _cast_move == TREMOR and not _marker_locked and is_instance_valid(_marker):
		if _target != null and is_instance_valid(_target):
			_marker.global_position = _target.global_position
	if is_instance_valid(_grabbed_player) and not _grabbed_player.has_method("mo_ting_hold"):
		if int(_grabbed_player.get("hp")) <= 0:
			_grabbed_player = null
		else:
			_grabbed_player.global_position = global_position + Vector2(facing * 190.0, -180.0)
	while not _cast_events.is_empty() and _cast_elapsed >= float(_cast_events[0]["at"]):
		var event: Dictionary = _cast_events.pop_front()
		_run_cast_event(event)
		if state != S_CAST:
			return
	_continuous_tick(delta)
	match _cast_move:
		RUSH:
			if _cast_elapsed >= RUSH_START and _cast_elapsed <= RUSH_END:
				velocity.x = facing * 620.0
			else:
				velocity.x = move_toward(velocity.x, 0.0, 1800.0 * delta)
		LEAP:
			if _cast_elapsed >= 0.18 and _cast_elapsed < 1.28:
				var remaining := _jump_target_x - global_position.x
				velocity.x = signf(remaining) * minf(_jump_speed, absf(remaining) * 5.0)
			else:
				velocity.x = move_toward(velocity.x, 0.0, 2200.0 * delta)
		_:
			velocity.x = move_toward(velocity.x, 0.0, 1800.0 * delta)
	if _cast_elapsed >= _cast_duration:
		_finish_cast()


func _run_cast_event(event: Dictionary) -> void:
	match str(event["kind"]):
		"basic":
			_hit_front(int(event["damage"]), float(event["range"]), 190.0)
		"mark_lock":
			_marker_locked = true
		"tremor_grab":
			_try_tremor_grab()
		"tremor_stab":
			_hit_held(2, {})
		"tremor_sunder":
			_hit_held(0, {"mo_ting_sunder": true})
		"slam":
			_sfx_player.stream = preload("res://audio/sfx/mo_ting_slam.wav")
			_sfx_player.play()
			_hit_front(5, 370.0, 190.0, {"cripple": 5.0}, Vector2(facing * 420.0, -180.0))
			Feel.shake(10.0, 0.3)
			_fx_play({"name": "crack", "scale": 0.75, "off_y": GROUND_CRACK_SINK * 0.75}, Vector2(facing * GROUND_IMPACT_X, 0.0))
		"leap_lift":
			velocity.y = -600.0
		"leap_land":
			_sfx_player.stream = preload("res://audio/sfx/mo_ting_slam.wav")
			_sfx_player.play()
			velocity.x = 0.0
			velocity.y = 0.0
			_hit_front(4, 350.0, 200.0, {"cripple": 5.0}, Vector2(facing * 980.0, -340.0))
			Feel.shake(12.0, 0.34)
			_fx_play({"name": "crack", "scale": 0.9, "off_y": GROUND_CRACK_SINK * 0.9}, Vector2(facing * GROUND_IMPACT_X, 0.0))
		"laser_segment":
			_laser_hit()


func _continuous_tick(delta: float) -> void:
	# 贯昼的伤害由两条 laser_segment 事件结算，这里只负责维持 0.8 秒的光束视觉。
	if _cast_move == LASER:
		var beam_active := _cast_elapsed >= LASER_START and _cast_elapsed <= LASER_END
		if beam_active:
			_update_laser()
		elif is_instance_valid(_laser):
			_laser.queue_free()
			_laser = null
		return
	var active := false
	if _cast_move == RUSH:
		active = _cast_elapsed >= RUSH_START and _cast_elapsed <= RUSH_END
	if not active:
		return
	if not _tick_started:
		_tick_started = true
		_tick_acc = 0.0
		_continuous_hit()
		return
	_tick_acc += delta
	while _tick_acc >= 0.5:
		_tick_acc -= 0.5
		_continuous_hit()


func _continuous_hit() -> void:
	if _target == null or not is_instance_valid(_target):
		return
	if _cast_move == RUSH:
		var dx: float = _target.global_position.x - global_position.x
		var dy := absf(_target.global_position.y - global_position.y)
		if (dx == 0.0 or (dx > 0.0) == (facing > 0)) and absf(dx) <= 210.0 + _radius_of(_target) and dy <= 190.0:
			_hit_target(2, {"force_knockdown": true}, Vector2(facing * 360.0, -180.0))
	# 贯昼实战伤害走 laser_segment 事件；这一支供测试直接调用 _continuous_hit 校验光束起点。
	elif _cast_move == LASER:
		_laser_hit()


## 贯昼结算：正前方整条射程都算命中；灼烧层数仍会抬高每段激光的基础伤害。
func _laser_hit() -> void:
	if _target == null or not is_instance_valid(_target):
		return
	var forward: float = (_target.global_position.x - global_position.x) * facing
	var beam_y := global_position.y + LASER_OFFSET.y
	var target_y: float = _target.global_position.y - 70.0
	if forward < LASER_OFFSET.x or absf(target_y - beam_y) > 90.0:
		return
	var damage := LASER_SEGMENT_DAMAGE
	if _target.has_method("mo_ting_laser_damage"):
		damage += maxi(0, int(_target.call("mo_ting_laser_damage")) - 1)
	_hit_target(damage, {"mo_ting_burn": true}, Vector2.ZERO)


func _hit_front(damage: int, reach: float, height: float, extra: Dictionary = {}, knockback := Vector2.ZERO) -> void:
	if _target == null or not is_instance_valid(_target):
		return
	var dx: float = _target.global_position.x - global_position.x
	var dy := absf(_target.global_position.y - global_position.y)
	if (dx == 0.0 or (dx > 0.0) == (facing > 0)) and absf(dx) <= reach + _radius_of(_target) and dy <= height:
		_hit_target(damage, extra, knockback)


func _hit_target(damage: int, extra: Dictionary = {}, knockback := Vector2.ZERO) -> void:
	if _target == null or not is_instance_valid(_target):
		return
	_hit_status_target(_target, damage, knockback, _move_data(extra))


func _hit_held(damage: int, extra: Dictionary) -> void:
	if not is_instance_valid(_grabbed_player):
		return
	_hit_status_target(_grabbed_player, damage, Vector2.ZERO, _move_data(extra))


func _move_data(extra: Dictionary) -> Dictionary:
	var move := extra.duplicate(true)
	move["anim"] = _cast_visual
	move["hit_at"] = _cast_elapsed
	move["cast_id"] = _cast_id
	move["cast_owner_id"] = get_instance_id()
	move["pierce_hurt_invincible"] = true
	return move


func _spawn_marker() -> void:
	if _target == null or not is_instance_valid(_target):
		return
	_marker = RedMark.new()
	_marker.z_index = 6
	_marker.global_position = _target.global_position
	var root := get_tree().current_scene
	if root == null:
		_marker.queue_free()
		_marker = null
		return
	root.add_child(_marker)
	_marker_locked = false


func _try_tremor_grab() -> void:
	if _target != null and is_instance_valid(_target) and is_instance_valid(_marker):
		var offset: Vector2 = _target.global_position - _marker.global_position
		if offset.length() <= 66.0:
			# 无敌 / 完美闪避 / 受击无敌 / 金钟罩时玩家会拒绝锁头，不能当成已抓获
			var held := false
			if _target.has_method("mo_ting_hold"):
				held = bool(_target.call("mo_ting_hold", global_position + Vector2(facing * 190.0, -180.0)))
			if held:
				_grabbed_player = _target
	if is_instance_valid(_marker):
		_marker.queue_free()
		_marker = null


func _update_laser() -> void:
	if not is_instance_valid(_laser):
		var root := get_tree().current_scene
		if root == null:
			return
		_laser = InkLaser.new()
		_laser.z_index = 7
		root.add_child(_laser)
	_laser.global_position = global_position + Vector2(facing * LASER_OFFSET.x, LASER_OFFSET.y)
	_laser.set("direction", float(facing))
	var length := (1920.0 - _laser.global_position.x) if facing > 0 else _laser.global_position.x
	_laser.set("length", maxf(0.0, length))


func _finish_cast() -> void:
	_cleanup_cast()
	_attack_cd = 0.24
	_set_state(State.CHASE)


func apply_frenzy(duration: float, empowered := false) -> void:
	super(duration, empowered)
	if _frenzy_time > 0.0:
		_release_grab()


func apply_charm(duration: float) -> void:
	super(duration)
	if _charm_time > 0.0:
		_release_grab()


func _release_grab() -> void:
	if is_instance_valid(_grabbed_player) and _grabbed_player.has_method("mo_ting_release"):
		_grabbed_player.call("mo_ting_release")
	_grabbed_player = null


## 所有退出路径共用：任何破招/时停/死亡都不能留下红点、光束或玩家定点。
func _cleanup_cast() -> void:
	if is_instance_valid(_marker):
		_marker.queue_free()
	_marker = null
	if is_instance_valid(_laser):
		_laser.queue_free()
	_laser = null
	_release_grab()
	_cast_events.clear()
	_cast_move = ""
	_cast_visual = ""
	_planned_move = ""
	_tick_started = false
	_tick_acc = 0.0
	_marker_locked = false


## 失心疯：失去多少生命就失去多少上限，并始终维持满血。
func _lose_life(amount: int, color: Color = DMG_COLOR) -> void:
	if state == State.DEAD or amount <= 0:
		return
	max_hp = maxi(0, max_hp - amount)
	hp = max_hp
	_spawn_number(amount, color)
	hp_changed.emit(hp, max_hp)
	if hp <= 0:
		die()


func take_damage(amount: int, source_x: float) -> void:
	if state == State.DEAD or amount <= 0:
		return
	if _invincible:
		_flash()
		return
	_lose_life(amount)
	if state == State.DEAD:
		return
	_sfx_player.stream = SFX_HIT_QI
	_sfx_player.play()
	_flash()
	var off_x := signf(source_x - global_position.x) * 60.0
	_fx_play(_fx.get("hit", {}), Vector2(off_x, _number_y * 0.55))
	_recent_hits.append(_battle_time)
	while not _recent_hits.is_empty() and _battle_time - float(_recent_hits[0]) > 2.0:
		_recent_hits.pop_front()
	if _stop_timer <= 0.0 and (amount >= 6 or _recent_hits.size() >= 5):
		_trigger_break()


func _direct_damage(amount: int, color: Color = DMG_COLOR) -> void:
	if not _invincible:
		_lose_life(amount, color)


func _trigger_break() -> void:
	if state == S_ENTER or _is_uninterruptible():
		return
	_recent_hits.clear()
	_cleanup_cast()
	_release_token()
	state = S_BREAK
	_state_timer = float(_anim_durations.get(str(_anim_map["hurt"]), 0.85))
	velocity = Vector2.ZERO
	_play(str(_anim_map["hurt"]), false)


func on_player_hit(amount: int, _move: Dictionary, _player: Node) -> void:
	if state == State.DEAD or amount <= 0:
		return
	max_hp += 1
	hp = max_hp
	hp_changed.emit(hp, max_hp)


## 机关造物：对满血目标追加 100% 伤害（受击结算前目标仍是满血才翻倍）。
func _modify_outgoing_damage(dmg: int, target: Node, _move: Dictionary) -> int:
	if dmg <= 0 or target == null or not is_instance_valid(target) or target != _target:
		return dmg
	# 影饵等纯 Node2D 诱饵没有生命字段，get() 会返回 null，不能直接 int()
	var max_v = target.get("max_hp")
	var hp_v = target.get("hp")
	if not (max_v is int or max_v is float) or not (hp_v is int or hp_v is float):
		return dmg
	var target_max := int(max_v)
	var target_hp := int(hp_v)
	if target_max > 0 and target_hp >= target_max:
		return dmg * 2
	return dmg


## 机关造物：持续减益与普通控制完全无效；time_stop 单独走规则级接口。
func apply_bleed(_layers: int) -> void:
	pass


func apply_poison(_dur: float) -> void:
	pass


func root(_dur: float, _ignore_armor := false) -> void:
	pass


func contain(_dur: float, _ignore_armor := false) -> void:
	pass


func slow(_dur: float, _scale: float, _ignore_armor := false) -> void:
	pass


func stun(_dur: float, _ignore_armor := false) -> void:
	pass


func slam(_ignore_armor := false) -> void:
	pass


func launch(_dir: int, _vx: float, _vy: float, _ignore_armor := false) -> void:
	pass


func knock_back(_dir: int, _force: float, _impact: int, _ignore_armor := false) -> void:
	pass


## 除普攻奋挥外，五招出手期间全部不可打断（阈值破招只对普攻生效）；时停仍按规则级处理。
func _is_uninterruptible() -> bool:
	return state == S_CAST and _cast_move != "" and _cast_move != BASIC


func time_stop(dur: float) -> void:
	if state == State.DEAD:
		return
	if state == S_CAST or state == S_BREAK:
		_cleanup_cast()
		state = State.CHASE
		velocity = Vector2.ZERO
		_play(str(_anim_map["idle"]), true)
	_stop_timer = dur
	if sprite != null:
		sprite.process_mode = Node.PROCESS_MODE_DISABLED


func die() -> void:
	_cleanup_cast()
	hp = 0
	super()
