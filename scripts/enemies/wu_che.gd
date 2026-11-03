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
	boss_label = "武车 · 耐久"


func _ready() -> void:
	super()
	state = State.IDLE
	velocity = Vector2.ZERO
	_position_history = [{"time": 0.0, "position": global_position}]
	_play(_idle_anim(), true)


func _all_anim_names() -> Array:
	var names := super()
	for anim in [START_ANIM, RUN_ANIM, BRAKE_ANIM, TURN_ANIM, SUMMON_ANIM, IDLE_ANIM, WEAK_IDLE_ANIM, "atked_fall_end"]:
		if not names.has(anim):
			names.append(anim)
	return names


func _durability_for_run() -> int:
	if Run.mode == Run.MODE_ENDLESS:
		return mini(ENDLESS_MAX_DURABILITY, 5 + int((Run.depth - 1) / 2))
	return int(ADVENTURE_DURABILITY[clampi(Run.difficulty, 0, ADVENTURE_DURABILITY.size() - 1)])


func _idle_anim() -> String:
	return WEAK_IDLE_ANIM if (max_hp - hp) * 2 >= max_hp else IDLE_ANIM


func _physics_process(delta: float) -> void:
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
	_telegraph()


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
	if not _target.is_in_group("enemies"):
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
	get_tree().current_scene.add_child(dn)


func _begin_brake() -> void:
	if state == S_BRAKE or state == State.DEAD:
		return
	state = S_BRAKE
	_charge_moving = false
	global_position.x = arena_right - HEAD_OFFSET if _wc_charge_dir > 0 else arena_left + HEAD_OFFSET
	velocity = Vector2.ZERO
	_set_ghost(false) # 马头碰边、开始刹车时立刻恢复实体
	_charges_completed += 1
	if _charges_completed > 1:
		hp = maxi(0, hp - 1)
		hp_changed.emit(hp, max_hp)
	_state_timer = float(_anim_durations.get(BRAKE_ANIM, 0.8))
	_play(BRAKE_ANIM, false)
	Feel.shake(9.0, 0.28)
	_fx_play(_fx.get("charge_wall", {}))


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
	var e = load(str(pool[randi() % pool.size()])).instantiate()
	if e == null:
		return
	e.set("wu_che_summon", true)
	e.set("player_ally", player_ally) # 只继承给本武车自己的子召唤，不触碰其他武车的 _summons
	e.died.connect(_on_summon_died.bind(e))
	get_parent().add_child(e)
	e.global_position = _spawn_position()
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


func _spawn_position() -> Vector2:
	for attempt in 16:
		var x := randf_range(arena_left + 110.0, arena_right - 110.0)
		if is_instance_valid(_target) and absf(x - _target.global_position.x) < 240.0:
			continue
		if absf(x - global_position.x) < 360.0:
			continue
		var crowded := false
		for e in _summons:
			if is_instance_valid(e) and absf(x - e.global_position.x) < 110.0:
				crowded = true
				break
		if not crowded:
			return Vector2(x, global_position.y)
	var fallback := clampf(global_position.x + facing * (420.0 + _summon_index * 120.0), arena_left + 110.0, arena_right - 110.0)
	return Vector2(fallback, global_position.y)


func _prune_summons() -> void:
	_summons = _summons.filter(func(e): return is_instance_valid(e) and int(e.get("hp")) > 0)


func _on_summon_died(e) -> void:
	_summons.erase(e)


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
	hp = 0
	super()
