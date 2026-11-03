extends "res://scripts/enemies/boss.gd"

## 焚鼎独立战斗状态机：四招、炎骨觉醒与炽热之心，不进入旧阶段随机池。
## 用户动画编号 -> 资源名：6=skill02，7=skill3，8=skill04，10=skill05，13=stand。

const S_CAST := 200
const S_AWAKEN := 201

const PALM := "skill01" # 炎掌
const CRUSH := "skill02" # 愤炎碎
const FISTS := "skill3" # 双拳
const AWAKEN_ANIM := "skill04" # 炎骨
const RISE := "skill05" # 炎起
const INTRO_ANIM := "stand"
const MOVE_ORDER := [PALM, CRUSH, FISTS, RISE]
const COOLDOWNS := {CRUSH: 20.0, FISTS: 25.0, RISE: 30.0}
const HIT_RANGES := {PALM: 300.0, CRUSH: 340.0, FISTS: 466.0}
const ATTACK_DESIRE_TIME := 5.0
const HOLD_DISTANCE := 320.0
const HOLD_TOLERANCE := 40.0
const YIELD_DISTANCE := 120.0
const FAST_DESIRE_SCALE := 2.0
const RISE_RADIUS := 110.0

var _move_cds: Dictionary = {}
var _attack_desire := 0.0
var _approach_yield := 0.0
var _planned_move := ""
var _cast_move := ""
var _cast_elapsed := 0.0
var _cast_duration := 0.0
var _cast_events: Array = []
var _cast_id := 0
var _awakened := false
var _rise_positions: Array = []
var _rise_warnings: Array = []


func _ready() -> void:
	super()
	for move in MOVE_ORDER:
		_move_cds[move] = 0.0
	_set_state(State.CHASE)


func _all_anim_names() -> Array:
	var names := super()
	if not names.has(AWAKEN_ANIM):
		names.append(AWAKEN_ANIM)
	return names


func entrance() -> void:
	_release_token()
	state = S_ENTER
	_state_timer = float(_anim_durations.get(INTRO_ANIM, 2.0))
	velocity = Vector2.ZERO
	_play(INTRO_ANIM, true)
	hp_changed.emit(hp, max_hp)


func finish_entrance() -> void:
	if state == State.DEAD:
		return
	_attack_desire = 0.0
	_approach_yield = 0.0
	_planned_move = ""
	_set_state(State.CHASE)


func _physics_process(delta: float) -> void:
	if state == State.DEAD:
		return
	if _stop_timer > 0.0:
		_stop_timer -= delta
		if _stop_timer <= 0.0:
			_end_stop(true)
		return
	if state != S_ENTER and state != State.CHASE:
		_attack_desire = minf(ATTACK_DESIRE_TIME, _attack_desire + delta)
	for move in _move_cds:
		_move_cds[move] = maxf(0.0, float(_move_cds[move]) - delta)
	if state == S_CAST or state == S_AWAKEN:
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


## 欲望未满时围绕固定间距站位：逼近先忍让，持续冒进立即出手，后退则跟紧并加速累计。
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
		_planned_move = _choose_fen_move(dist)
	if _planned_move == RISE:
		_start_fen_move(RISE)
		return
	var release_reach := float(HIT_RANGES[_planned_move]) * 0.5
	if dy <= 190.0 and dist <= release_reach + _radius_of(_target):
		_start_fen_move(_planned_move)
		return
	velocity.x = move_toward(velocity.x, facing * chase_speed, accel * delta)
	_play(str(_anim_map["chase"]), true)


func _choose_fen_move(dist: float) -> String:
	if _awakened and float(_move_cds[RISE]) <= 0.0:
		return RISE
	if dist > 370.0 and float(_move_cds[FISTS]) <= 0.0:
		return FISTS
	if float(_move_cds[CRUSH]) <= 0.0:
		return CRUSH
	if float(_move_cds[FISTS]) <= 0.0:
		return FISTS
	return PALM


func _start_fen_move(move: String) -> void:
	_cleanup_cast()
	if move != PALM:
		_trigger_six_senses()
		if state == State.DEAD:
			return
	_cast_id += 1
	_attack_cast_id = _cast_id
	_cast_move = move
	_cast_elapsed = 0.0
	_attack_desire = 0.0
	_approach_yield = 0.0
	_cast_duration = float(_anim_durations.get(move, 1.0))
	_cast_events = _events_for(move)
	state = S_CAST
	velocity.x = 0.0
	if COOLDOWNS.has(move):
		_move_cds[move] = float(COOLDOWNS[move]) * cd_scale
	_play(move, false)
	_telegraph()


func _events_for(move: String) -> Array:
	match move:
		PALM:
			return [{"at": 0.72, "kind": "palm"}]
		CRUSH:
			return [
				{"at": 1.17, "kind": "crush", "damage": 1},
				{"at": 1.89, "kind": "crush", "damage": 1},
				{"at": 2.61, "kind": "crush", "damage": 2},
			]
		FISTS:
			return [{"at": 0.90, "kind": "fists"}]
		RISE:
			return [
				{"at": 0.54, "kind": "rise_warn"},
				{"at": 0.90, "kind": "rise_burst"},
			]
	return []


func _cast_tick(delta: float) -> void:
	_cast_elapsed += delta
	while not _cast_events.is_empty() and _cast_elapsed >= float(_cast_events[0]["at"]):
		var event: Dictionary = _cast_events.pop_front()
		_run_cast_event(event)
		if state != S_CAST:
			return
	velocity.x = move_toward(velocity.x, 0.0, 1800.0 * delta)
	if _cast_elapsed >= _cast_duration:
		_finish_cast()


func _run_cast_event(event: Dictionary) -> void:
	match str(event["kind"]):
		"palm":
			_hit_front(2, 300.0, 190.0, {"fen_ding_burn": true})
		"crush":
			_hit_front(int(event["damage"]), 340.0, 190.0, {"cripple": 5.0})
			Feel.shake(5.0, 0.16)
		"fists":
			_hit_front(3, 466.0, 190.0, {"fen_ding_burn": true}, Vector2(facing * 1100.0, -260.0))
			Feel.shake(8.0, 0.22)
		"rise_warn":
			_warn_rise()
		"rise_burst":
			_burst_rise()


func _hit_front(damage: int, reach: float, height: float, extra: Dictionary = {}, knockback := Vector2.ZERO) -> void:
	if _target == null or not is_instance_valid(_target):
		return
	var dx: float = _target.global_position.x - global_position.x
	var dy := absf(_target.global_position.y - global_position.y)
	if (dx == 0.0 or (dx > 0.0) == (facing > 0)) and absf(dx) <= reach + _radius_of(_target) and dy <= height:
		_hit_status_target(_target, damage, knockback, _move_data(extra))


func _move_data(extra: Dictionary) -> Dictionary:
	var move := extra.duplicate(true)
	move["anim"] = _cast_move
	move["hit_at"] = _cast_elapsed
	move["cast_id"] = _cast_id
	move["cast_owner_id"] = get_instance_id()
	move["pierce_hurt_invincible"] = true
	return move


func _warn_rise() -> void:
	_rise_positions.clear()
	if _target != null and is_instance_valid(_target):
		_rise_positions.append(_target.global_position.x)
	while _rise_positions.size() < 3:
		_rise_positions.append(randf_range(ARENA_L + 120.0, ARENA_R - 120.0))
	for x in _rise_positions:
		var pos := Vector2(clampf(float(x), ARENA_L + 60.0, ARENA_R - 60.0), global_position.y)
		var warning := FX.spawn(get_tree().current_scene, "telegraph", pos,
			{"scale": 0.55, "mod": Color(1.0, 0.5, 0.45, 0.95)})
		if warning != null:
			_rise_warnings.append(warning)


func _burst_rise() -> void:
	_clear_rise_warnings()
	for x in _rise_positions:
		var pos := Vector2(float(x), global_position.y)
		FX.spawn(get_tree().current_scene, "fire_pillar", pos, {"scale": 0.6})
	_sfx_player.stream = SFX_FIRE_BURST
	_sfx_player.play()
	Feel.shake(5.0, 0.18)
	if _target == null or not is_instance_valid(_target):
		return
	for x in _rise_positions:
		var dx: float = _target.global_position.x - float(x)
		if absf(dx) <= RISE_RADIUS and absf(_target.global_position.y - global_position.y) <= 160.0:
			_hit_status_target(_target, 3, Vector2(signf(dx) * 220.0, -100.0), _move_data({"fen_ding_burn": true}))
			FX.spawn(get_tree().current_scene, "fire_hit", _target.global_position + Vector2(0, -70), {"scale": 0.5})
			break


func _clear_rise_warnings() -> void:
	for warning in _rise_warnings:
		if is_instance_valid(warning):
			warning.queue_free()
	_rise_warnings.clear()


func _finish_cast() -> void:
	_cleanup_cast()
	_set_state(State.CHASE)


func _cleanup_cast() -> void:
	_clear_rise_warnings()
	_rise_positions.clear()
	_cast_events.clear()
	_cast_move = ""
	_planned_move = ""


## 炎骨：首次跌破 50% 时永久觉醒；当前这一击不减免，之后伤害减半并向上取整。
func _apply_hp_damage(amount: int, color: Color = DMG_COLOR) -> void:
	var dealt := int(ceil(float(amount) * 0.5)) if _awakened else amount
	hp -= dealt
	_spawn_number(dealt, color)
	hp_changed.emit(hp, max_hp)
	if hp <= 0:
		die()
		return
	if not _awakened and hp * 2 < max_hp:
		_awaken()


func _awaken() -> void:
	_trigger_six_senses()
	if state == State.DEAD:
		return
	_awakened = true
	_cleanup_cast()
	_release_token()
	state = S_AWAKEN
	_state_timer = float(_anim_durations.get(AWAKEN_ANIM, 3.0))
	velocity = Vector2.ZERO
	_play(AWAKEN_ANIM, false)
	_telegraph()
	Feel.shake(7.0, 0.3)
	_fx_play(_fx.get("transform", {}))


func mind_status_count() -> int:
	return super() + int(_awakened)


func _clear_mind_statuses() -> void:
	super()
	_awakened = false


func take_damage(amount: int, source_x: float) -> void:
	if state == State.DEAD or amount <= 0:
		return
	if _invincible:
		_flash()
		return
	_apply_hp_damage(amount)
	if state == State.DEAD:
		return
	_sfx_player.stream = SFX_HIT_QI
	_sfx_player.play()
	_flash()
	var off_x := signf(source_x - global_position.x) * 60.0
	_fx_play(_fx.get("hit", {}), Vector2(off_x, _number_y * 0.55))


func _direct_damage(amount: int, color: Color = DMG_COLOR) -> void:
	if state == State.DEAD or amount <= 0 or _invincible:
		return
	_apply_hp_damage(amount, color)


## 炽热之心：每次共享怒焰真实扣血，只回血并刷新冷却一次，不改公共攻击欲望。
func on_fen_ding_burn_hit(amount: int, _player: Node) -> void:
	if state == State.DEAD or amount <= 0:
		return
	_heal(10)
	for move in _move_cds:
		_move_cds[move] = 0.0


func time_stop(dur: float) -> void:
	if state == State.DEAD:
		return
	if state == S_CAST or state == S_AWAKEN:
		_cleanup_cast()
		state = State.CHASE
		velocity = Vector2.ZERO
		_play(str(_anim_map["idle"]), true)
	_stop_timer = dur
	if sprite != null:
		sprite.process_mode = Node.PROCESS_MODE_DISABLED


func die() -> void:
	_cleanup_cast()
	var pl := get_tree().get_first_node_in_group("player")
	if pl != null and pl.has_method("clear_fen_ding_burn"):
		pl.call("clear_fen_ding_burn", self)
	hp = 0
	super()
