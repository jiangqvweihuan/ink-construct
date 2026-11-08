extends "res://scripts/enemies/boss.gd"

## 碎岳独立战斗状态机：四招、佛曰金钟、邪佛压场与佛眼夺被动。
## 用户动画编号 -> 资源名：9=skill04，7=skill03，6=skill02，5=skill01。

const S_CAST := 200
const S_RETREAT := 201

const ARMS := "skill04" # 掷臂·剥离
const CRUSHER := "skill03" # 崩坛：踢击后砸落
const HANDS := "skill02" # 万佛手
const EYE := "skill01" # 佛眼
const INTRO_ANIM := "stand"
const MOVE_ORDER := [ARMS, CRUSHER, HANDS, EYE]
const COOLDOWNS := {CRUSHER: 24.0, HANDS: 30.0, EYE: 50.0}
const HIT_RANGES := {ARMS: 536.0, CRUSHER: 300.0, HANDS: 260.0, EYE: 225.0}
const ATTACK_DESIRE_TIME := 3.5
const MOVE_ANIM_SPEED := 1.3
const RETREAT_TIME := 1.15
const RETREAT_SPEED_SCALE := 1.35
const HOLD_DISTANCE := 360.0
const HOLD_TOLERANCE := 40.0
const YIELD_DISTANCE := 120.0
const FAST_DESIRE_SCALE := 2.0

var _move_cds: Dictionary = {}
var _attack_desire := 0.0
var _approach_yield := 0.0
var _retreat_left := 0.0
var _planned_move := ""
var _cast_move := ""
var _cast_elapsed := 0.0
var _cast_duration := 0.0
var _cast_events: Array = []
var _cast_id := 0
var _bell_layers: Array = [] # 每层独立保存 2 次抵挡，数组长度没有上限
var _eye_target: Node = null
var _eye_passive := ""
var _eye_info: Dictionary = {}
var _eye_heal_cd := 0.0

func _ready() -> void:
	super()
	for move in MOVE_ORDER:
		_move_cds[move] = 0.0
	_set_state(State.CHASE)


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
	_retreat_left = 0.0
	_planned_move = ""
	_set_state(State.CHASE)


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
	_eye_heal_cd = maxf(0.0, _eye_heal_cd - delta)
	var cd_delta := delta * (1.0 + _eye_effect("cooldown_recovery"))
	for move in _move_cds:
		_move_cds[move] = maxf(0.0, float(_move_cds[move]) - cd_delta)
	if state == S_CAST:
		if _slow_timer > 0.0:
			_slow_timer = maxf(0.0, _slow_timer - delta)
			if _slow_timer <= 0.0:
				_slow_scale = 1.0
		_find_target()
		_bleed_tick(delta)
		_poison_tick(delta)
		_pipa_status_tick(delta)
		_cast_tick(delta)
		velocity.y = minf(velocity.y + gravity * delta, 900.0)
		_duel_clamp_back()
		_duel_move_and_slide()
		return
	if state == S_RETREAT:
		if _slow_timer > 0.0:
			_slow_timer = maxf(0.0, _slow_timer - delta)
			if _slow_timer <= 0.0:
				_slow_scale = 1.0
		_find_target()
		_bleed_tick(delta)
		_poison_tick(delta)
		_pipa_status_tick(delta)
		_retreat_tick(delta)
		velocity.y = minf(velocity.y + gravity * delta, 900.0)
		_duel_clamp_back()
		_duel_move_and_slide()
		return
	super(delta)


## 收招先后撤；追击阶段积满欲望后预选一招，再贴近到该招实际命中范围的中段。
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
	var speed := chase_speed * (1.0 + _eye_effect("speed")) * _slow_scale
	if _planned_move.is_empty() and _attack_desire >= ATTACK_DESIRE_TIME:
		_planned_move = _choose_move(dist)
	if not _planned_move.is_empty():
		var release_reach := float(HIT_RANGES[_planned_move]) * (1.0 if duel_mode else 0.5)
		if _planned_move != EYE:
			release_reach *= 1.0 + _eye_effect("reach")
		if dy <= 190.0 and dist <= release_reach + _radius_of(_target):
			_start_sui_move(_planned_move)
			return
		velocity.x = move_toward(velocity.x, facing * speed, accel * delta)
		_play(str(_anim_map["chase"]), true, MOVE_ANIM_SPEED)
		return
	var player_vx := 0.0
	var target_velocity = _target.get("velocity")
	if typeof(target_velocity) == TYPE_VECTOR2:
		player_vx = target_velocity.x
	var approaching: bool = dx * player_vx < -1.0
	var retreating: bool = dx * player_vx > 1.0
	if not approaching:
		_approach_yield = 0.0
	var desire_scale := (FAST_DESIRE_SCALE if retreating and dist > HOLD_DISTANCE else 1.0) * (1.0 + _eye_effect("desire"))
	_attack_desire = minf(ATTACK_DESIRE_TIME, _attack_desire + delta * desire_scale)
	if _attack_desire < ATTACK_DESIRE_TIME:
		if approaching and dist < HOLD_DISTANCE:
			if _approach_yield < YIELD_DISTANCE and not duel_mode:
				var yield_step := minf(speed * delta, YIELD_DISTANCE - _approach_yield)
				_approach_yield += yield_step
				velocity.x = move_toward(velocity.x, -facing * speed, accel * delta)
				_play(str(_anim_map["chase"]), true, MOVE_ANIM_SPEED)
				return
			_attack_desire = ATTACK_DESIRE_TIME
		elif dist > HOLD_DISTANCE + HOLD_TOLERANCE:
			velocity.x = move_toward(velocity.x, facing * speed, accel * delta)
			_play(str(_anim_map["chase"]), true, MOVE_ANIM_SPEED)
			return
		elif dist < HOLD_DISTANCE - HOLD_TOLERANCE:
			# 斗蛐蛐：Boss 不后退，贴身时原地站桩等出手，不再向后拉距。
			if duel_mode:
				velocity.x = move_toward(velocity.x, 0.0, brake * delta)
				_play(str(_anim_map["idle"]), true)
				return
			velocity.x = move_toward(velocity.x, -facing * speed, accel * delta)
			_play(str(_anim_map["chase"]), true, MOVE_ANIM_SPEED)
			return
		else:
			velocity.x = move_toward(velocity.x, 0.0, brake * delta)
			_play(str(_anim_map["idle"]), true)
			return
	_planned_move = _choose_move(dist)


func _choose_move(dist: float) -> String:
	if dist > 420.0:
		return ARMS
	for move in [EYE, HANDS, CRUSHER]:
		if float(_move_cds[move]) <= 0.0:
			return move
	return ARMS


func _retreat_tick(delta: float) -> void:
	if duel_mode:
		# 斗蛐蛐：收招后不后撤，直接回到追击。
		_retreat_left = 0.0
		_set_state(State.CHASE)
		return
	if _target == null or not is_instance_valid(_target):
		velocity.x = move_toward(velocity.x, 0.0, brake * delta)
		_set_state(State.IDLE)
		return
	var dx: float = _target.global_position.x - global_position.x
	facing = 1 if dx >= 0.0 else -1
	_apply_facing()
	_retreat_left = maxf(0.0, _retreat_left - delta)
	var speed := chase_speed * RETREAT_SPEED_SCALE * (1.0 + _eye_effect("speed")) * _slow_scale
	velocity.x = move_toward(velocity.x, -facing * speed, accel * delta)
	_play(str(_anim_map["chase"]), true, MOVE_ANIM_SPEED)
	if _retreat_left <= 0.0:
		_set_state(State.CHASE)


func _start_sui_move(move: String) -> void:
	if state != State.CHASE or not MOVE_ORDER.has(move) or float(_move_cds.get(move, 0.0)) > 0.0:
		return
	_cleanup_cast()
	if move != ARMS:
		_trigger_six_senses()
		if state == State.DEAD:
			return
	_cast_id += 1
	_attack_cast_id = _cast_id
	_cast_move = move
	_cast_elapsed = 0.0
	_attack_desire = 0.0
	_approach_yield = 0.0
	_cast_duration = float(_anim_durations.get(move, 3.0))
	_cast_events = _events_for(move)
	state = S_CAST
	velocity.x = 0.0
	if COOLDOWNS.has(move):
		_move_cds[move] = float(COOLDOWNS[move]) * cd_scale
	if move != ARMS:
		_bell_layers.append(2) # 佛曰：每个非普攻招式一层，一层挡两次
		_text("佛曰 · 金钟 %d 层" % _bell_layers.size(), Color(0.9, 0.75, 0.3))
	var cast_refund := _eye_effect("cooldown_on_cast")
	if cast_refund > 0.0:
		for key in _move_cds:
			_move_cds[key] = maxf(0.0, float(_move_cds[key]) - cast_refund)
	_play(move, false)
	_telegraph()


func _events_for(move: String) -> Array:
	match move:
		ARMS:
			return [{"at": 0.92, "kind": "arms"}]
		CRUSHER:
			return [{"at": 0.71, "kind": "kick"}, {"at": 1.35, "kind": "slam"}]
		HANDS:
			return [
				{"at": 2.16, "kind": "hand"}, {"at": 2.61, "kind": "hand"},
				{"at": 3.06, "kind": "hand"}, {"at": 3.51, "kind": "hand"},
				{"at": 3.96, "kind": "hand"},
			]
		EYE:
			return [{"at": 1.19, "kind": "eye"}]
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
		"arms":
			_hit_front(3, 536.0, {"passive_seal": 15.0})
		"kick":
			_hit_front(2, 300.0)
		"slam":
			_hit_front(3, 300.0, {"cripple": 5.0})
			Feel.shake(8.0, 0.22)
		"hand":
			_hit_front(1, 260.0, {"stun": 0.5})
			Feel.shake(3.0, 0.08)
		"eye":
			_scan_eye()


func _hit_front(damage: int, reach: float, extra: Dictionary = {}) -> void:
	if _target == null or not is_instance_valid(_target):
		return
	var dx: float = _target.global_position.x - global_position.x
	var dy := absf(_target.global_position.y - global_position.y)
	reach *= 1.0 + _eye_effect("reach")
	# 斗蛐蛐：Boss 不许后退，贴脸的小怪会穿到背后；此时仍应命中当前锁定的目标。
	var front_ok := duel_mode or dx == 0.0 or (dx > 0.0) == (facing > 0)
	if front_ok and absf(dx) <= reach + _radius_of(_target) and dy <= 190.0:
		# 影饵是裸 Node2D，没有状态计时字段；取不到就按未受控处理。
		var stun_v = _target.get("_stun_time")
		var cripple_v = _target.get("_cripple_time")
		var controlled := ((stun_v is int or stun_v is float) and float(stun_v) > 0.0) \
			or ((cripple_v is int or cripple_v is float) and float(cripple_v) > 0.0)
		var total := damage + int(_eye_effect("damage")) + (int(_eye_effect("controlled_damage")) if controlled else 0)
		_hit_status_target(_target, total, Vector2.ZERO, _move_data(extra))


func _move_data(extra: Dictionary) -> Dictionary:
	var move := extra.duplicate(true)
	move["anim"] = _cast_move
	move["hit_at"] = _cast_elapsed
	move["cast_id"] = _cast_id
	move["cast_owner_id"] = get_instance_id()
	move["pierce_hurt_invincible"] = true
	return move


## 佛眼不走 hurt：闪避、护盾、反伤与受伤无敌都不能挡住扫描。
func _scan_eye() -> void:
	_return_eye() # 下一次扫描先归还旧被动，再从当前目标身上随机摘取
	if _target == null or not is_instance_valid(_target) or not _target.has_method("steal_sui_yue_passive"):
		return
	var dx: float = _target.global_position.x - global_position.x
	var dy := absf(_target.global_position.y - global_position.y)
	if not (dx == 0.0 or (dx > 0.0) == (facing > 0)) or absf(dx) > 225.0 + _radius_of(_target) or dy > 190.0:
		return
	var candidates: Array = _target.call("sui_yue_passive_candidates")
	if candidates.is_empty():
		_text("佛眼 · 无物可摘", Color(0.75, 0.62, 0.85))
		return
	var id := str(candidates[randi() % candidates.size()])
	if not bool(_target.call("steal_sui_yue_passive", id)):
		return
	_eye_target = _target
	_eye_passive = id
	_eye_info = Meta.battle_passive_info(id)
	var max_hp_gain := int(_eye_effect("max_hp"))
	if max_hp_gain > 0:
		max_hp += max_hp_gain
		hp += max_hp_gain
		hp_changed.emit(hp, max_hp)
	for i in int(_eye_effect("bell_charges")):
		_bell_layers.append(2)
	var passive_name := str(_eye_info.get("name", _eye_info.get("label", id)))
	_text("佛眼 · " + passive_name, Color(0.75, 0.62, 0.85))


func _return_eye() -> void:
	if is_instance_valid(_eye_target) and not _eye_passive.is_empty() and _eye_target.has_method("return_sui_yue_passive"):
		_eye_target.call("return_sui_yue_passive", _eye_passive)
	var max_hp_loss := int(_eye_effect("max_hp"))
	if max_hp_loss > 0:
		max_hp = maxi(1, max_hp - max_hp_loss)
		hp = mini(hp, max_hp)
		hp_changed.emit(hp, max_hp)
	_eye_target = null
	_eye_passive = ""
	_eye_info.clear()
	_eye_heal_cd = 0.0


func _eye_effect(key: String) -> float:
	if is_passive_sealed():
		return 0.0 # 剥离期间佛眼被动失效
	return float((_eye_info.get("boss_effect", {}) as Dictionary).get(key, 0.0))


func on_player_hit(dealt: int, _move: Dictionary, _player: Node) -> void:
	if dealt <= 0 or state == State.DEAD:
		return
	var heal := int(_eye_effect("heal_on_hit"))
	if heal > 0 and _eye_heal_cd <= 0.0:
		_eye_heal_cd = _eye_effect("heal_cooldown")
		_heal(heal)
	var refund := _eye_effect("cooldown_on_hit")
	if refund > 0.0:
		for key in _move_cds:
			_move_cds[key] = maxf(0.0, float(_move_cds[key]) - refund)


func _finish_cast() -> void:
	_cleanup_cast()
	if duel_mode:
		_set_state(State.CHASE)
		return
	_retreat_left = RETREAT_TIME
	_set_state(S_RETREAT)


func _cleanup_cast() -> void:
	_cast_events.clear()
	_cast_move = ""
	_planned_move = ""


func mind_status_count() -> int:
	return super() + _bell_layers.size() + int(not _eye_passive.is_empty())


func _clear_mind_statuses() -> void:
	super()
	_bell_layers.clear()
	_return_eye()


## 每次任意伤害只消耗当前层的一次抵挡；直接伤害与普通打击走同一入口。
func _consume_bell() -> bool:
	if is_passive_sealed():
		return false # 剥离期间金钟罩被动失效
	if _bell_layers.is_empty():
		return false
	var left := int(_bell_layers[0]) - 1
	if left <= 0:
		_bell_layers.pop_front()
	else:
		_bell_layers[0] = left
	_text("金钟罩", Color(0.9, 0.75, 0.3))
	FX.spawn(get_tree().current_scene, "ink_hit", global_position + Vector2(0, -160), {"scale": 0.65})
	Feel.shake(3.0, 0.1)
	return true


func take_damage(amount: int, source_x: float) -> void:
	if state == State.DEAD or amount <= 0:
		return
	if _invincible:
		_flash()
		return
	if _consume_bell():
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
	var off_x := signf(source_x - global_position.x) * 60.0
	_fx_play(_fx.get("hit", {}), Vector2(off_x, _number_y * 0.55))


func _direct_damage(amount: int, color: Color = DMG_COLOR) -> void:
	if state == State.DEAD or amount <= 0 or _invincible or _consume_bell():
		return
	hp -= amount
	_spawn_number(amount, color)
	hp_changed.emit(hp, max_hp)
	if hp <= 0:
		die()


## 掷臂之外的招式出手期间不可打断；时停仍按规则级处理。
func _is_uninterruptible() -> bool:
	return state == S_CAST and _cast_move != "" and _cast_move != ARMS


func time_stop(dur: float) -> void:
	if state == State.DEAD:
		return
	if state == S_CAST:
		_cleanup_cast()
		state = State.CHASE
		velocity = Vector2.ZERO
		_play(str(_anim_map["idle"]), true)
	_stop_timer = dur
	if sprite != null:
		sprite.process_mode = Node.PROCESS_MODE_DISABLED


func _text(text: String, color: Color) -> void:
	var dn := DAMAGE_NUMBER.new()
	dn.setup(text, color)
	dn.global_position = global_position + Vector2(0, _number_y - 25.0)
	var root := get_tree().current_scene
	if root != null:
		root.add_child(dn)


func die() -> void:
	_cleanup_cast()
	_return_eye()
	# 多人局：碎岳压力与附着的状态要清到每一位玩家
	for pl in get_tree().get_nodes_in_group("player"):
		if not player_ally and is_instance_valid(pl) and pl.has_method("clear_sui_yue_effects"):
			pl.call("clear_sui_yue_effects")
	hp = 0
	super()
