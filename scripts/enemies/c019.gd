extends "res://scripts/enemies/boss.gd"

## 剑冢：双形态 Boss。
## 一阶段 C019 守冢剑主，浮剑远压；生命归零后播「百剑开冢」，
## 无缝换成 C019_sp 万刃形态，恢复二阶段血量并进入更激进的近身剑狱节奏。

const PHASE2_ID := "c019_sp"
const TRANSITION_ANIM := "transform"
const PHASE2_INTRO := "zhaohuan"
const PHASE2_RAGE_AT := 0.5
const PHASE2_RAGE_DAMAGE := 1.15
## 一阶段被动「守冢剑势」：技能首次实伤积 1 层（上限 2），断岳飞锋起手消耗全部层数，每层 +1 伤。
const P1_MARK_MAX := 2
const P1_MARK_COLOR := Color(0.62, 0.78, 0.72)
const P1_SPEND_COLOR := Color(0.78, 0.64, 0.28)

var _phase_two := false
var _phase_swap_pending := false
var _phase_intro_pending := false
var _phase2_enraged := false
var _p1_marks := 0
var _p1_mark_cast := -1 # 本次起手是否已经积过剑势，多段命中只算一次
var _p1_thrust_bonus := 0 # 断岳飞锋起手时锁定的剑势加成
# 斗蛐蛐：把玩家在面板里调好的生命/出手/移速保留到二阶段，避免换形后数值跳回配置值。
var _duel_phase2_hp := -1
var _duel_phase2_cd := -1.0
var _duel_phase2_speed := -1.0


func _ready() -> void:
	super()
	_set_capsule(40.0, 190.0)
	boss_label = "剑冢"
	_phase_two = false
	_phase_swap_pending = false
	_phase_intro_pending = false
	_phase2_enraged = false
	_p1_marks = 0
	_p1_mark_cast = -1
	_p1_thrust_bonus = 0
	_duel_phase2_hp = -1
	_duel_phase2_cd = -1.0
	_duel_phase2_speed = -1.0


## Boss 基座只装配阶段/速度，通用招式表仍由本类补齐。
func _apply_type() -> void:
	super._apply_type()
	var t: Dictionary = BossTypes.get_boss(type_id)
	_damage_map = t.get("damage", {})
	_move_anims = t.get("move_anims", {})
	_move_pool = t.get("move_pool", {})
	_hit_effects = t.get("hit_effects", {})
	_poise_anims = t.get("poise_atk", {})
	_lunge_map = t.get("lunge_mul", {})
	_feedback_segments = t.get("feedback_only", {})
	_blink_strike = t.get("blink_strike", {})
	_attack_chain = t.get("attack_chain", {})
	_advance_map = t.get("advance", {})
	_hit_knockback = t.get("hit_knockback", Vector2(220.0, -80.0))
	_attack_rules = (t.get("attack_rules", {}) as Dictionary).duplicate(true)
	var chain_followups: Array = []
	for start in _attack_chain:
		chain_followups.append(str((_attack_chain[start] as Dictionary).get("anim", "")))
	for i in _attack_anims.size():
		var move := str(_attack_anims[i])
		var rule: Dictionary = _attack_rules.get(move, {})
		if i == 0 or chain_followups.has(move):
			rule["cooldown"] = 0.0
		elif float(rule.get("cooldown", 0.0)) <= 0.0:
			rule["cooldown"] = 8.0
		_attack_rules[move] = rule
	var cd_mul := Run.enemy_cd_scale()
	if not is_equal_approx(cd_mul, 1.0):
		for anim in _attack_rules:
			var rule2: Dictionary = _attack_rules[anim]
			rule2["cooldown"] = float(rule2.get("cooldown", 0.0)) * cd_mul
	_attack_rule_cds.clear()
	for anim in _attack_rules:
		_attack_rule_cds[anim] = 0.0


## 只把真实存在的演出动画交给基座检查，避免把 p1_/p2_ 逻辑键误报为缺动画。
func _all_anim_names() -> Array:
	var names: Array = []
	for v in _anim_map.values():
		names.append(str(v))
	for key in _move_anims:
		names.append(str(_move_anims[key]))
	if type_id == PHASE2_ID:
		names.append(PHASE2_INTRO)
	else:
		names.append(TRANSITION_ANIM)
	return names


func _set_capsule(radius: float, height: float) -> void:
	var collision := $CollisionShape2D as CollisionShape2D
	if collision == null:
		return
	var cap := collision.shape as CapsuleShape2D
	if cap == null:
		return
	var copy := cap.duplicate() as CapsuleShape2D
	copy.radius = radius
	copy.height = height
	collision.shape = copy
	collision.position = Vector2(0, -height * 0.5)


## 一阶段空血：不死亡，进入换形态演出；二阶段空血才走正常 Boss 死亡。
func die() -> void:
	if not _phase_two:
		_start_phase_two()
		return
	super.die()


func _start_phase_two() -> void:
	# 一阶段被击空时可能还握着全局出手令牌或留着半段判定，换形前统一清干净。
	_release_token()
	_clear_attack_chain()
	_attack_hits_left.clear()
	_p1_marks = 0
	_p1_mark_cast = -1
	_p1_thrust_bonus = 0
	if duel_mode:
		_duel_phase2_hp = max_hp
		_duel_phase2_cd = attack_cooldown
		_duel_phase2_speed = chase_speed
	_phase_two = true
	hp = 0
	# 先锁无敌与演出状态，再刷新 HUD：信号回调里若有人补刀也不会二次结算死亡。
	_invincible = true
	state = S_TRANSFORM
	_phase_swap_pending = true
	velocity = Vector2.ZERO
	hp_changed.emit(0, max_hp)
	_play(TRANSITION_ANIM, false)
	_state_timer = float(_anim_durations.get(TRANSITION_ANIM, 2.933))
	Feel.shake(9.0, 0.35)
	_fx_play(_fx.get("transform", {}))


func _finish_transform() -> void:
	if _phase_swap_pending:
		_phase_swap_pending = false
		_swap_to_phase_two()
		return
	if _phase_intro_pending:
		_phase_intro_pending = false
		_invincible = false
		state = S_STAGGER
		_state_timer = 1.2
		_attack_cd = attack_cooldown
		_play(str(_anim_map["idle"]), true)
		return
	super._finish_transform()


func _swap_to_phase_two() -> void:
	type_id = PHASE2_ID
	if sprite != null:
		sprite.queue_free()
		sprite = null
	_anim_state = null
	_apply_type()
	if duel_mode:
		if _duel_phase2_hp > 0:
			max_hp = _duel_phase2_hp
		if _duel_phase2_cd > 0.0:
			attack_cooldown = _duel_phase2_cd
		if _duel_phase2_speed > 0.0:
			chase_speed = _duel_phase2_speed
	_setup_spine()
	_set_capsule(64.0, 260.0)
	max_hp = maxi(1, max_hp)
	hp = max_hp
	_invincible = true
	state = S_TRANSFORM
	_phase_intro_pending = true
	hp_changed.emit(hp, max_hp)
	_play(PHASE2_INTRO, false)
	_state_timer = float(_anim_durations.get(PHASE2_INTRO, 1.333))
	boss_label = "剑冢·万刃"
	Feel.shake(8.0, 0.3)
	_fx_play(_fx.get("enter", {}))


## 一阶段被动「守冢剑势」：每次独立技能起手期间，首次实际命中积 1 层。
## 多段招只算一次；普攻断岳飞锋自身不积层，只在起手时消耗层数。
func _deal_hit(seg := 0) -> void:
	var landed_before: bool = _attack_hit_landed
	super(seg)
	if _phase_two or _attack_move == "" or _attack_move == "p1_thrust":
		return
	if _attack_hit_landed == landed_before:
		return
	if _p1_mark_cast == _attack_cast_id:
		return
	_p1_mark_cast = _attack_cast_id
	_p1_marks = mini(_p1_marks + 1, P1_MARK_MAX)
	_float_text("剑势 +1", P1_MARK_COLOR)


## 断岳飞锋起手即消耗全部剑势，每层 +1 伤；落空也会耗层，逼玩家判断是否值得硬吃。
func _start_attack(forced_anim := "", continue_chain := false) -> void:
	var cast_before: int = _attack_cast_id
	super(forced_anim, continue_chain)
	if _phase_two or state != State.ATTACK or _attack_cast_id == cast_before:
		return
	if _attack_move != "p1_thrust":
		return
	_p1_thrust_bonus = 0
	if _p1_marks <= 0:
		return
	_p1_thrust_bonus = mini(_p1_marks, P1_MARK_MAX)
	_p1_marks = 0
	_float_text("剑势 ×%d" % _p1_thrust_bonus, P1_SPEND_COLOR)


func _damage_of(anim: String, seg: int) -> int:
	var value: int = super(anim, seg)
	if not _phase_two and anim == "p1_thrust":
		value += _p1_thrust_bonus
	return value


func _float_text(text: String, color: Color) -> void:
	var dn := DAMAGE_NUMBER.new()
	dn.setup(text, color)
	dn.global_position = global_position + Vector2(0, _number_y - 18.0)
	_world_add(dn)


func take_damage(amount: int, source_x: float) -> void:
	super.take_damage(amount, source_x)
	_check_phase2_rage()


func _direct_damage(amount: int, color: Color = DMG_COLOR) -> void:
	super._direct_damage(amount, color)
	_check_phase2_rage()


func _check_phase2_rage() -> void:
	if not _phase_two or _phase2_enraged or state == State.DEAD or hp <= 0:
		return
	if float(hp) / float(maxi(1, max_hp)) > PHASE2_RAGE_AT:
		return
	_phase2_enraged = true
	attack_cooldown *= 0.8
	chase_speed *= 1.15
	Feel.shake(7.0, 0.3)
	_fx_play(_fx.get("transform", {}))


## 二阶段半血后「万刃同悲」：全部直接伤害 +15%。
func attack_damage_mul() -> float:
	var mul := super.attack_damage_mul()
	if _phase_two and _phase2_enraged:
		mul *= PHASE2_RAGE_DAMAGE
	return mul
