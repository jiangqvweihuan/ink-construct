extends "res://scripts/enemies/boss.gd"

## 鸣钟独立战斗状态机：根骨位移四招、英勇、易伤、武神格挡与神眷圣光。

const S_CAST := 200
const S_RETREAT := 201

const COMBO := "combo"
const CHAIN := "chain"
const PURSUIT := "pursuit"
const AWAKEN := "awaken"
const COMBO_ANIM := "skill05-cankao"
const CHAIN_ANIM := "skill01-cankao"
const PURSUIT_ANIMS := ["skill03-cankao", "skill04-cankao"]
const AWAKEN_ANIM := "transform1"
const INTRO_ANIM := "skill02"
const CHASE_ANIM := "speed_run"
const RETREAT_ANIM := "run1"
const MOVE_ORDER := [COMBO, CHAIN, PURSUIT, AWAKEN]
const COOLDOWNS := {CHAIN: 24.0, PURSUIT: 36.0, AWAKEN: 40.0}
const HIT_RANGES := {COMBO: 260.0, CHAIN: 235.0, PURSUIT: 265.0}
const ATTACK_DESIRE_TIME := 3.2
const RETREAT_TIME := 1.0
const HOLD_DISTANCE := 270.0
const HOLD_TOLERANCE := 45.0
const ROOT_MIX_LEAD := 0.24
const AWAKEN_HIT_AT := 4.32
const SPIN_FROM := 1.15
const SPIN_TO := 2.55

var _move_cds: Dictionary = {}
var _attack_desire := 0.0
var _approach_yield := 0.0
var _retreat_left := 0.0
var _planned_move := ""
var _cast_move := ""
var _cast_anim := ""
var _cast_elapsed := 0.0
var _cast_duration := 0.0
var _cast_events: Array = []
var _cast_id := 0
var _cast_heroic := false
var _heroic := false
var _awakened := false
var _block := 0
var _held_player: Node2D = null
var _spin_done := false
var _spin_phase := false


func hud_extra_hp() -> int:
	return _block


var _root_bone = null
var _root_bone_base := 0.0
var _root_follow := false
var _root_start_x := 0.0
var _mix_restore := false


func _ready() -> void:
	super()
	for move in MOVE_ORDER:
		_move_cds[move] = 0.0
	_knock_chain = ["atked_heavy", "atked_fall_end", "getup"]
	var collision := $CollisionShape2D as CollisionShape2D
	var capsule := collision.shape as CapsuleShape2D
	if capsule != null:
		collision.shape = capsule.duplicate()
		(collision.shape as CapsuleShape2D).radius = 20.0
		(collision.shape as CapsuleShape2D).height = 112.0
		collision.position.y = -56.0
	_set_state(State.CHASE)


func _all_anim_names() -> Array:
	var names: Array = super()
	for n in [COMBO_ANIM, CHAIN_ANIM, PURSUIT_ANIMS[0], PURSUIT_ANIMS[1], AWAKEN_ANIM, INTRO_ANIM, CHASE_ANIM, RETREAT_ANIM, "getup"]:
		if not names.has(n):
			names.append(n)
	return names


func _setup_spine() -> void:
	super()
	if sprite != null:
		_root_bone = sprite.call("get_skeleton").call("get_root_bone")
		_root_bone_base = float(_root_bone.call("get_x")) if _root_bone != null else 0.0


func entrance() -> void:
	_release_token()
	state = S_ENTER
	_state_timer = float(_anim_durations.get(INTRO_ANIM, 1.933))
	velocity = Vector2.ZERO
	_play(INTRO_ANIM, false)
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
	for move in _move_cds:
		_move_cds[move] = maxf(0.0, float(_move_cds[move]) - delta)
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


## 平常保持中近距离；欲望满后先选招，再贴近到该招实际命中范围的中段。
func _chase_tick(delta: float) -> void:
	if _target == null or not is_instance_valid(_target):
		velocity.x = move_toward(velocity.x, 0.0, brake * delta)
		_set_state(State.IDLE)
		return
	var dx: float = _target.global_position.x - global_position.x
	var dy := absf(_target.global_position.y - global_position.y)
	facing = 1 if dx >= 0.0 else -1
	_apply_facing()
	# 生命低于 50%：不等攻击欲望蓄满，立刻起手觉醒演出（先更新朝向，避免背对玩家开招）。
	if not _awakened and hp * 2 < max_hp and float(_move_cds[AWAKEN]) <= 0.0:
		_attack_desire = ATTACK_DESIRE_TIME
		_start_ming_move(AWAKEN)
		return
	var dist := absf(dx)
	if _planned_move.is_empty() and _attack_desire >= ATTACK_DESIRE_TIME:
		_planned_move = _choose_move(dist)
	if not _planned_move.is_empty():
		if _planned_move == AWAKEN:
			_start_ming_move(AWAKEN)
			return
		var release_reach := float(HIT_RANGES[_planned_move]) * (1.0 if duel_mode else 0.5)
		if dy <= 190.0 and dist <= release_reach + _radius_of(_target):
			_start_ming_move(_planned_move)
			return
		velocity.x = move_toward(velocity.x, facing * chase_speed * 1.45 * _slow_scale, accel * delta)
		_play(CHASE_ANIM, true, 1.25)
		return

	var player_vx := 0.0
	var target_velocity = _target.get("velocity")
	if typeof(target_velocity) == TYPE_VECTOR2:
		player_vx = target_velocity.x
	var approaching: bool = dx * player_vx < -1.0
	var retreating: bool = dx * player_vx > 1.0
	if not approaching:
		_approach_yield = 0.0
	_attack_desire = minf(ATTACK_DESIRE_TIME, _attack_desire + delta * (1.7 if retreating and dist > HOLD_DISTANCE else 1.0))
	if approaching and dist < HOLD_DISTANCE and _approach_yield < 90.0 and not duel_mode:
		var step := minf(chase_speed * _slow_scale * delta, 90.0 - _approach_yield)
		_approach_yield += step
		velocity.x = move_toward(velocity.x, -facing * chase_speed * _slow_scale, accel * delta)
		_play("run", true, 1.2)
	elif dist > HOLD_DISTANCE + HOLD_TOLERANCE:
		velocity.x = move_toward(velocity.x, facing * chase_speed * _slow_scale, accel * delta)
		_play("run", true, 1.2)
	elif dist < HOLD_DISTANCE - HOLD_TOLERANCE:
		# 斗蛐蛐：Boss 不后退，贴身时原地站桩等出手。
		if duel_mode:
			velocity.x = move_toward(velocity.x, 0.0, brake * delta)
			_play(str(_anim_map["idle"]), true)
		else:
			velocity.x = move_toward(velocity.x, -facing * chase_speed * _slow_scale, accel * delta)
			_play("run", true, 1.2)
	else:
		velocity.x = move_toward(velocity.x, 0.0, brake * delta)
		_play(str(_anim_map["idle"]), true)


func _choose_move(dist: float) -> String:
	if (hp * 2 < max_hp or _awakened) and float(_move_cds[AWAKEN]) <= 0.0:
		return AWAKEN
	if dist > 360.0 and float(_move_cds[PURSUIT]) <= 0.0:
		return PURSUIT
	if dist <= 310.0 and float(_move_cds[CHAIN]) <= 0.0:
		return CHAIN
	return COMBO


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
	velocity.x = move_toward(velocity.x, -facing * chase_speed * 1.25 * _slow_scale, accel * delta)
	_play(RETREAT_ANIM, true, 1.35)
	if _retreat_left <= 0.0:
		_set_state(State.CHASE)


func _start_ming_move(move: String) -> void:
	if state != State.CHASE or not MOVE_ORDER.has(move) or float(_move_cds.get(move, 0.0)) > 0.0:
		return
	_cleanup_cast()
	if move != COMBO:
		_trigger_six_senses()
		if state == State.DEAD:
			return
	_cast_id += 1
	_attack_cast_id = _cast_id
	_cast_move = move
	_cast_anim = PURSUIT_ANIMS[randi() % PURSUIT_ANIMS.size()] if move == PURSUIT else _anim_for(move)
	_cast_elapsed = 0.0
	_attack_desire = 0.0
	_approach_yield = 0.0
	_cast_duration = float(_anim_durations.get(_cast_anim, 3.0))
	_cast_events = _events_for(move)
	_cast_heroic = _heroic
	_heroic = false # 英勇在起手时消耗；本招后续命中为下一招重新蓄势
	_spin_done = false
	state = S_CAST
	velocity.x = 0.0
	if COOLDOWNS.has(move):
		_move_cds[move] = float(COOLDOWNS[move]) * cd_scale
	if move != AWAKEN:
		_root_follow = _root_bone != null
		_root_start_x = global_position.x
	_invincible = move == AWAKEN
	_play(_cast_anim, false)
	_telegraph()


func _anim_for(move: String) -> String:
	match move:
		COMBO:
			return COMBO_ANIM
		CHAIN:
			return CHAIN_ANIM
		AWAKEN:
			return AWAKEN_ANIM
	return COMBO_ANIM


func _events_for(move: String) -> Array:
	match move:
		COMBO:
			return [{"at": 0.64, "kind": "hit", "damage": 2, "reach": 260.0}]
		CHAIN:
			return [
				{"at": 0.82, "kind": "hit", "damage": 1, "reach": 235.0, "extra": {"ming_zhong_grab": true}},
				{"at": 1.58, "kind": "hit", "damage": 1, "reach": 240.0},
				{"at": 2.24, "kind": "hit", "damage": 2, "reach": 245.0},
				{"at": 2.94, "kind": "hit", "damage": 2, "reach": 255.0, "extra": {"ming_zhong_vulnerability": true}},
			]
		PURSUIT:
			return [
				{"at": 0.52, "kind": "hit", "damage": 1, "reach": 265.0},
				{"at": 2.95, "kind": "hit", "damage": 3, "reach": 285.0, "extra": {"ming_zhong_vulnerability": true}},
			]
		AWAKEN:
			return [{"at": AWAKEN_HIT_AT, "kind": "awaken"}]
	return []


func _cast_tick(delta: float) -> void:
	if _mix_restore:
		_mix_restore = false
		sprite.get("skeleton_data_res").call("set_default_mix", 0.2)
	_cast_elapsed += delta
	_update_root_follow()
	var spinning := _cast_move == PURSUIT and _cast_elapsed >= SPIN_FROM and _cast_elapsed <= SPIN_TO
	_set_spin_phase(spinning)
	_invincible = spinning or (_cast_move == AWAKEN and _cast_elapsed < AWAKEN_HIT_AT)
	if spinning and not _spin_done:
		_try_spin_hit()
	while not _cast_events.is_empty() and _cast_elapsed >= float(_cast_events[0]["at"]):
		var event: Dictionary = _cast_events.pop_front()
		_run_cast_event(event)
		if state != S_CAST:
			return
	_update_held_player()
	velocity.x = 0.0
	if _root_follow and _cast_elapsed >= _cast_duration - ROOT_MIX_LEAD:
		_reset_root_follow()
		var data = sprite.get("skeleton_data_res")
		data.call("set_default_mix", 0.0)
		_anim_state.call("clear_track", 0)
		_anim_state.call("set_animation", str(_anim_map["idle"]), true, 0)
		_current_anim = str(_anim_map["idle"])
		_mix_restore = true
	if _cast_elapsed >= _cast_duration:
		_finish_cast()


func _run_cast_event(event: Dictionary) -> void:
	if str(event["kind"]) == "awaken":
		_hit_global(4)
		_heal(int(round(float(max_hp) * 0.25)))
		_block += 10
		_awakened = true
		hp_changed.emit(hp, max_hp)
		_text("神眷 · 神圣庇佑", Color(0.95, 0.82, 0.38))
		_fx_play({"name": "pillar", "scale": 0.8}, Vector2(0, -80))
		Feel.shake(9.0, 0.3)
		return
	_hit_front(int(event["damage"]), float(event["reach"]), event.get("extra", {}))


func _move_data(extra: Dictionary = {}) -> Dictionary:
	var move := extra.duplicate(true)
	move["anim"] = _cast_anim
	move["hit_at"] = _cast_elapsed
	move["cast_id"] = _cast_id
	move["cast_owner_id"] = get_instance_id()
	move["pierce_hurt_invincible"] = true
	move["ming_zhong_zero"] = _awakened
	return move


func _hit_front(damage: int, reach: float, extra: Dictionary = {}) -> void:
	if _target == null or not is_instance_valid(_target):
		return
	var dx: float = _target.global_position.x - global_position.x
	var dy := absf(_target.global_position.y - global_position.y)
	# 斗蛐蛐：Boss 不许后退，贴脸的小怪会穿到背后；此时仍应命中当前锁定的目标。
	var front_ok := duel_mode or dx == 0.0 or (dx > 0.0) == (facing > 0)
	if front_ok and absf(dx) <= reach + _radius_of(_target) and dy <= 190.0:
		_strike(_target, damage, extra)


func _strike(target: Node, damage: int, extra: Dictionary = {}) -> void:
	var doubled := 2 if _cast_heroic else 1
	_hit_status_target(target, damage * doubled, Vector2.ZERO, _move_data(extra))


func _hit_global(damage: int) -> void:
	var targets: Array = []
	if duel_mode:
		# 斗蛐蛐单位不在 player / enemies 组里，敌对名单由决斗场维护在 duel_foes
		targets.append_array(duel_foes)
	elif player_ally:
		targets.append_array(get_tree().get_nodes_in_group("enemies"))
	elif _charm_time > 0.0 or _frenzy_time > 0.0:
		targets.append_array(get_tree().get_nodes_in_group("enemies"))
		if _charm_time <= 0.0:
			targets.append_array(get_tree().get_nodes_in_group("player"))
	else:
		targets.append_array(get_tree().get_nodes_in_group("player"))
	for target in targets:
		if target != self and is_instance_valid(target):
			_strike(target, damage)


## 旋转突进在整段窗口内持续检测，但首次接触（含完美闪避）后就封判定。
func _try_spin_hit() -> void:
	if _target == null or not is_instance_valid(_target):
		return
	var dx: float = _target.global_position.x - global_position.x
	var dy := absf(_target.global_position.y - global_position.y)
	if absf(dx) <= 155.0 + _radius_of(_target) and dy <= 190.0:
		_spin_done = true
		_strike(_target, 2, {"ming_zhong_spin_heal": true})


func _set_spin_phase(on: bool) -> void:
	if on == _spin_phase:
		return
	_spin_phase = on
	if _target != null and is_instance_valid(_target) and _target is CollisionObject2D:
		if on:
			add_collision_exception_with(_target)
			_target.add_collision_exception_with(self)
		else:
			remove_collision_exception_with(_target)
			_target.remove_collision_exception_with(self)


## 普攻与实伤命中走统一回报；觉醒后的零伤命中走专用回报，完美闪避不会到这里。
func on_player_hit(dealt: int, move: Dictionary, player: Node) -> void:
	if dealt > 0:
		_on_contact(player, move, dealt)


func on_ming_zhong_zero_hit(move: Dictionary, player: Node) -> void:
	_on_contact(player, move, 0)


func _on_contact(player: Node, move: Dictionary, dealt: int) -> void:
	if state == State.DEAD:
		return
	for key in _move_cds:
		_move_cds[key] = maxf(0.0, float(_move_cds[key]) - 3.0)
	_block += 2
	_heroic = true
	if _awakened:
		if dealt <= 0 and player.has_method("apply_ming_zhong_holy"):
			player.call("apply_ming_zhong_holy", 2 if _cast_heroic else 1)
		return
	if dealt <= 0:
		return
	if bool(move.get("ming_zhong_grab", false)):
		if player.has_method("ming_zhong_hold"):
			_held_player = player
			player.call("ming_zhong_hold", self)
			_update_held_player()
		elif duel_mode:
			# 斗蛐蛐的敌人没有玩家版的被抓接口，直接由鸣钟自己按住（结算与玩家被抓一致）
			_held_player = player
			_update_held_player()
	if bool(move.get("ming_zhong_spin_heal", false)):
		_heal(dealt)


func apply_frenzy(duration: float, empowered := false) -> void:
	super(duration, empowered)
	if _frenzy_time > 0.0:
		_release_held()


func apply_charm(duration: float) -> void:
	super(duration)
	if _charm_time > 0.0:
		_release_held()


func _update_held_player() -> void:
	if _held_player == null:
		return
	if not is_instance_valid(_held_player) or int(_held_player.get("hp")) <= 0:
		_release_held()
		return
	_held_player.global_position = global_position + Vector2(facing * 92.0, 0.0)
	_held_player.velocity = Vector2.ZERO


func _release_held() -> void:
	if is_instance_valid(_held_player) and _held_player.has_method("release_ming_zhong_hold"):
		_held_player.call("release_ming_zhong_hold", self)
	_held_player = null


func _finish_cast() -> void:
	_cleanup_cast()
	if duel_mode:
		_set_state(State.CHASE)
		return
	_retreat_left = RETREAT_TIME
	_set_state(S_RETREAT)


func _cleanup_cast() -> void:
	_reset_root_follow()
	_set_spin_phase(false)
	_release_held()
	_invincible = false
	_cast_events.clear()
	_cast_move = ""
	_cast_anim = ""
	_planned_move = ""


func _root_offset() -> float:
	if _root_bone == null:
		return 0.0
	return (float(_root_bone.call("get_world_x")) - _root_bone_base) * _scale * facing


func _update_root_follow() -> void:
	if not _root_follow or _root_bone == null:
		return
	var off := _root_offset()
	# 根骨位移不能越过地图墙：夹住节点后按实际落点重算 sprite 补偿
	var px := _clamp_battle_x(_root_start_x + off)
	sprite.position.x = -(px - _root_start_x)
	global_position.x = px


func _reset_root_follow() -> void:
	if not _root_follow:
		return
	_root_follow = false
	var off := _root_offset()
	if _root_bone != null:
		global_position.x = _clamp_battle_x(_root_start_x + off)
		_root_bone.call("set_x", _root_bone_base)
	if sprite != null:
		sprite.position = Vector2.ZERO


## 地图内可站立 x 范围：场景在 _ready 写入 battle_width；未标注时按 1920 兜底。
func _clamp_battle_x(x: float) -> float:
	var width := 1920.0
	var scene := get_tree().current_scene
	if scene != null and scene.has_meta("battle_width"):
		width = float(scene.get_meta("battle_width"))
	var pad := 40.0
	var r = get("body_radius")
	if r != null:
		pad = maxf(pad, float(r))
	return clampf(x, pad, width - pad)


func mind_status_count() -> int:
	return super() + _block + int(_heroic) + int(_awakened)


func _clear_mind_statuses() -> void:
	super()
	_block = 0
	_heroic = false
	_cast_heroic = false
	_awakened = false


## 格挡先于生命扣除；只有实际生命损失超过 5 才进入受伤→倒地→起身链。
func take_damage(amount: int, source_x: float) -> void:
	if state == State.DEAD or amount <= 0:
		return
	if _invincible:
		_flash()
		return
	var absorbed := mini(_block, amount)
	_block -= absorbed
	var life_damage := amount - absorbed
	if absorbed > 0:
		_text("格挡 · %d" % _block, Color(0.9, 0.78, 0.36))
	if life_damage <= 0:
		_flash()
		return
	hp -= life_damage
	_sfx_player.stream = SFX_HIT_QI
	_sfx_player.play()
	_spawn_number(life_damage)
	hp_changed.emit(hp, max_hp)
	if hp <= 0:
		die()
		return
	_flash()
	var off_x := signf(source_x - global_position.x) * 35.0
	_fx_play(_fx.get("hit", {}), Vector2(off_x, _number_y * 0.55))
	if life_damage > 5 and not _hurt_chain_active:
		_cleanup_cast()
		_attack_desire = 0.0
		_start_hurt_chain(signf(global_position.x - source_x))


func _direct_damage(amount: int, color: Color = DMG_COLOR) -> void:
	if state == State.DEAD or amount <= 0 or _invincible:
		return
	var absorbed := mini(_block, amount)
	_block -= absorbed
	var life_damage := amount - absorbed
	if absorbed > 0:
		_text("格挡 · %d" % _block, Color(0.9, 0.78, 0.36))
	if life_damage <= 0:
		return
	hp -= life_damage
	_spawn_number(life_damage, color)
	hp_changed.emit(hp, max_hp)
	if hp <= 0:
		die()


## 连击之外的招式（追击、觉醒）出手期间不可打断；收招后撤属于移动，仍可被控制。时停仍按规则级处理。
func _is_uninterruptible() -> bool:
	return state == S_CAST and _cast_move != "" and _cast_move != COMBO


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
	dn.global_position = global_position + Vector2(0, _number_y - 20.0)
	var root := get_tree().current_scene
	if root != null:
		root.add_child(dn)


func die() -> void:
	_cleanup_cast()
	# 多人局：锁头/易伤等状态要释放每一位被它锁定的玩家
	for player in get_tree().get_nodes_in_group("player"):
		if not player_ally and is_instance_valid(player) and player.has_method("clear_ming_zhong_effects"):
			player.call("clear_ming_zhong_effects")
	hp = 0
	super()
