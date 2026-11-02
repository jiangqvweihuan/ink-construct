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
const ATTACK_DESIRE_TIME := 5.0
const HOLD_DISTANCE := 380.0
const HOLD_TOLERANCE := 45.0
const YIELD_DISTANCE := 120.0
const FAST_DESIRE_SCALE := 2.0
const PURSUIT_COMMIT_DIST := 260.0 # 后退拉距时被持续追逼到此距离内，立即释放当前距离技。
const RUSH_START := 1.62 # 动画蓄力结束、机体开始前倾后才起步。
const RUSH_END := 3.60
const GROUND_IMPACT_X := 240.0 # 断岳 / 陨构的拍地点在骨架原点身前，不在 Boss 脚底。
const LASER_OFFSET := Vector2(120.0, -115.0)
const UNBREAKABLE: Array = [] # 当前六招均可被阈值受击打断；时停始终是更高优先级。

var _move_cds: Dictionary = {}
var _battle_time := 0.0
var _attack_desire := 0.0
var _approach_yield := 0.0
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
	var length := 1000.0
	var direction := 1.0
	var pulse := 0.0

	func _process(delta: float) -> void:
		pulse += delta * 18.0
		queue_redraw()

	func _draw() -> void:
		var end := Vector2(length * direction, 0)
		var width := 30.0 + sin(pulse) * 4.0
		draw_line(Vector2.ZERO, end, Color(0.20, 0.58, 0.72, 0.20), width + 24.0, true)
		draw_line(Vector2.ZERO, end, Color(0.32, 0.78, 0.92, 0.56), width, true)
		draw_line(Vector2.ZERO, end, Color(0.88, 0.98, 1.0, 0.96), 9.0, true)
		draw_circle(Vector2.ZERO, 28.0, Color(0.65, 0.92, 1.0, 0.72))


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


## 常驻追击：公共欲望满后墨颤优先；远程招就绪时主动拉距，近身招只在远程招不可用或无处可退时兜底。
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
	if dy <= 180.0:
		if _battle_time >= 5.0 and float(_move_cds[TREMOR]) <= 0.0:
			if _attack_cd <= 0.0:
				_start_mo_move(TREMOR)
			else:
				velocity.x = move_toward(velocity.x, 0.0, brake * delta)
				_play(str(_anim_map["idle"]), true)
			return

		# 三个距离招按既有优先级择一；近身也先向后拉开，不再贴着玩家等距离。
		var ranged_move := ""
		var ranged_distance := 0.0
		if float(_move_cds[LEAP]) <= 0.0:
			ranged_move = LEAP
			ranged_distance = 520.0
		elif float(_move_cds[RUSH]) <= 0.0:
			ranged_move = RUSH
			ranged_distance = 431.0
		elif float(_move_cds[LASER]) <= 0.0:
			ranged_move = LASER
			ranged_distance = 340.0
		if ranged_move != "":
			var pursuit_close := approaching
			if dist >= ranged_distance or (dist <= PURSUIT_COMMIT_DIST and pursuit_close):
				if _attack_cd <= 0.0:
					_start_mo_move(ranged_move)
				else:
					velocity.x = move_toward(velocity.x, 0.0, brake * delta)
					_play(str(_anim_map["idle"]), true)
				return
			var retreat_dir := -facing
			var retreat_x := global_position.x + retreat_dir * chase_speed * delta
			if retreat_x >= ARENA_L + 90.0 and retreat_x <= ARENA_R - 90.0:
				velocity.x = move_toward(velocity.x, retreat_dir * chase_speed, accel * delta)
				_play(str(_anim_map["chase"]), true)
				return

		if _attack_cd <= 0.0:
			if dist <= 390.0 and float(_move_cds[SLAM]) <= 0.0:
				_start_mo_move(SLAM)
				return
			if dist <= 427.0:
				_start_mo_move(BASIC)
				return
	velocity.x = move_toward(velocity.x, facing * chase_speed, accel * delta)
	_play(str(_anim_map["chase"]), true)


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
			_hit_front(5, 370.0, 190.0, {"cripple": 5.0}, Vector2(facing * 420.0, -180.0))
			Feel.shake(10.0, 0.3)
			_fx_play({"name": "crack", "scale": 0.75}, Vector2(facing * GROUND_IMPACT_X, 0.0))
		"leap_lift":
			velocity.y = -600.0
		"leap_land":
			velocity.x = 0.0
			velocity.y = 0.0
			_hit_front(4, 350.0, 200.0, {"cripple": 5.0}, Vector2(facing * 980.0, -340.0))
			Feel.shake(12.0, 0.34)
			_fx_play({"name": "crack", "scale": 0.9}, Vector2(facing * GROUND_IMPACT_X, 0.0))


func _continuous_tick(delta: float) -> void:
	var active := false
	if _cast_move == RUSH:
		active = _cast_elapsed >= RUSH_START and _cast_elapsed <= RUSH_END
	elif _cast_move == LASER:
		active = _cast_elapsed >= 0.85 and _cast_elapsed <= 2.45
		if active:
			_update_laser()
		elif is_instance_valid(_laser):
			_laser.queue_free()
			_laser = null
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
	elif _cast_move == LASER:
		var forward: float = (_target.global_position.x - global_position.x) * facing
		var beam_y := global_position.y + LASER_OFFSET.y
		var target_y: float = _target.global_position.y - 70.0
		if forward >= LASER_OFFSET.x and absf(target_y - beam_y) <= 90.0:
			var base := 1
			if _target.has_method("mo_ting_laser_damage"):
				base = int(_target.call("mo_ting_laser_damage"))
			_hit_target(base, {"mo_ting_burn": true}, Vector2.ZERO)


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
	get_tree().current_scene.add_child(_marker)
	_marker_locked = false


func _try_tremor_grab() -> void:
	if _target != null and is_instance_valid(_target) and is_instance_valid(_marker):
		var offset: Vector2 = _target.global_position - _marker.global_position
		if offset.length() <= 66.0:
			_grabbed_player = _target
			if _target.has_method("mo_ting_hold"):
				_target.call("mo_ting_hold", global_position + Vector2(facing * 190.0, -180.0))
	if is_instance_valid(_marker):
		_marker.queue_free()
		_marker = null


func _update_laser() -> void:
	if not is_instance_valid(_laser):
		_laser = InkLaser.new()
		_laser.z_index = 7
		get_tree().current_scene.add_child(_laser)
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
	if state == S_ENTER or (_cast_move != "" and UNBREAKABLE.has(_cast_move)):
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
