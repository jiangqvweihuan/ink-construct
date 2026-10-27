class_name Player
extends CharacterBody2D

## 玩家控制器 · 形态数据见 scripts/player/skulls.gd
## 每个形态自带骨架 / 缩放 / 动画名映射 / 普攻段 / 技能表，换头时按 profile 重建 SpineSprite。
## 缩放按"游戏内角色高 128px"反推，换头不会突然变大变小。

const DAMAGE_NUMBER := preload("res://scripts/ui/damage_number.gd")
const Skulls := preload("res://scripts/player/skulls.gd")
const PROJECTILE := preload("res://scripts/systems/projectile.gd") # 远程形态的普攻/技能发投射物
const FX := preload("res://scripts/systems/fx.gd") # 精灵条特效：斩击/化身光柱/受击墨花
const DMG_COLOR := Color(0.18, 0.36, 0.43) # 石青：玩家受伤数字

## 换头消耗的墨骨数
const SWAP_COST := 8

## 技能 action -> HUD 按键字母
const KEY_LABELS := {"skill": "K", "skill_sweep": "L", "skill_ult": "U"}

## 技能配置里 hits.at 是动画开始后多少秒判定命中，按逐帧截图标定：
## skill01：0.75s 前冲突刺后起跳隐身（0.75~1.28s 闪现位移+无敌），1.30s 现身一刀，path=沿闪现路径全判。
## skill03：1.0s 平刺一段，2.0s 双手分枪横扫一段（大范围）。
## skill04：举枪过顶连斩，1.2/2.1/3.0s 各一段。
## 锁定时长用动画真实时长（_skill_durations 运行时查表），不用手填。
## 音效命名：audio/sfx/<名字>.wav，_sfx_cache 里缓存后直接播
const SFX_BASE := "res://audio/sfx/"
const SFX_PRECACHE := [
	"weapon_sword",   # 普攻起手（挥剑嗖）
	"voice_sword_hit",# 普攻命中（咔劈肉）
	"voice_skill_cast",# 技能起手通用（嗡）
	"hit_heavy",      # skill01 突刺命中
	"skill_fist",     # skill03 第一段平刺
	"voice_fan_hit",  # skill03 第二段横扫
	"skill_blade",    # skill04 长连段（落叶镖）
	"hit_fist",       # 玩家受伤
]

@export var run_speed := 240.0
@export var accel := 2200.0    # 启动加速度（"踩油门"）
@export var brake := 5200.0    # 制动减速度（"松油门 + 刹"，比启动快得多）
@export var turn_accel := 3000.0 # 反向转向加速度（比同方向启动略快）
@export var gravity := 2000.0
@export var max_fall_speed := 900.0
@export var jump_velocity := -640.0
@export var coyote_time := 0.10
@export var jump_buffer := 0.12
@export var dash_speed := 560.0
@export var dash_time := 0.16
@export var dash_cooldown := 0.45
@export var hurt_time := 0.35
@export var max_hp := 8

signal hp_changed(current: int, maximum: int)
signal died
signal skull_changed(id: String)

enum State { IDLE, RUN, JUMP, FALL, DASH, ATTACK, SKILL, HURT, DEAD }
var state: int = State.IDLE
var facing := 1 # 1 朝右，-1 朝左
var hp: int

# ---------- 当前形态（由 Skulls.SKULLS 表注入，换头时整组替换） ----------
var skull_id := Skulls.DEFAULT_ID
var anim_map: Dictionary = {} # idle/run/dash/air/hurt/dead/getup -> Spine 动画名
var attacks: Array = [] # 普攻段表：{anim, lock, hits, damage, range, lunge}
var skill_config: Dictionary = {} # 技能名 -> {action, cooldown, hits...}
var hud_skills: Array = [] # HUD 技能栏顺序（K/L/U 依次）
var base_scale := 0.394 # 骨架缩放，按形态反推

# ---------- 局内强化（Run.upgrades 注入，换房间保留） ----------
var damage_bonus := 0 # 全部伤害 +N
var cooldown_scale := 1.0 # 技能冷却倍率
var swap_cost := SWAP_COST # 换头消耗墨骨

var _coyote := 0.0
var _jump_buf := 0.0
var _dash_timer := 0.0
var _dash_cd := 0.0
var _attack_idx := -1
var _attack_timer := 0.0
var _attack_queued := false
var _attack_hits: Array = [] # 本段普攻剩余待结算的命中时刻（动画秒），按升序弹出
var _hurt_timer := 0.0
var _hurt_invincible := 0.0 # 受伤后的短暂无敌：被围殴时不会一帧连掉好几血
var _mastery_cd := 1.0 # 契合 Lv1：该形态技能冷却倍率
var _mastery_dmg := 0 # 契合 Lv2：该形态普攻加伤
var _skill_name := ""
var _skill_timer := 0.0
var _skill_dur := 0.0 # 本次技能动画真实时长
var _skill_hits: Array = [] # 尚未结算的命中段（按 at 升序，逐个弹出）
var _skill_start_x := 0.0 # 技能起手 x，path 命中判定的路径起点
var _skill_cds := {} # 技能名 -> 剩余冷却
var _skill_durations := {} # 技能名 -> 动画真实时长，setup 时缓存
var _invincible := false # 闪现段无敌
var _blink_active := false # 闪现段与敌人的碰撞例外已开启
var _idle_queued := false # stand 已排队在技能后面，切 IDLE 时别重复 set（重开会重开淡化）

var sprite: Node2D # SpineSprite（GDExtension 类，用 ClassDB 创建）
var _anim_state # SpineAnimationState
var _current_anim := "" # 防同名动画重放（floated 在跳跃顶点重放会抽搐）
var _sfx_player: AudioStreamPlayer
var _sfx_cache: Dictionary = {}


func _ready() -> void:
	add_to_group("player")
	hp = max_hp
	_apply_profile(skull_id)
	_setup_spine()
	_setup_sfx()


## 把形态表里的动画映射 / 普攻段 / 技能表 / HUD 顺序装到实例上
func _apply_profile(id: String) -> void:
	var profile: Dictionary = Skulls.get_profile(id)
	# 局外养成的契合度加成随形态一起装上（Meta 是 autoload，测试场景里也在）
	var mods: Dictionary = Meta.mods(id)
	_mastery_cd = float(mods["cd"])
	_mastery_dmg = int(mods["damage"])
	skull_id = id if Skulls.SKULLS.has(id) else Skulls.DEFAULT_ID
	anim_map = profile["anim"]
	attacks = profile["attacks"]
	skill_config = profile["skills"]
	hud_skills = profile["hud_skills"]
	base_scale = float(profile["scale"])


## 局内强化注入：伤害/移速/冷却/生命上限/换头费用。换房间时由 Run.apply_to 重新调用
func set_upgrades(up: Dictionary) -> void:
	var spd := int(up.get("speed", 0))
	var cd := int(up.get("cooldown", 0))
	var sw := int(up.get("swap", 0))
	damage_bonus = int(up.get("damage", 0))
	run_speed = 240.0 * (1.0 + 0.12 * spd)
	cooldown_scale = maxf(0.55, 1.0 - 0.15 * cd)
	swap_cost = maxi(2, SWAP_COST - 3 * sw)
	max_hp = 8 + int(up.get("hp", 0))


func _setup_sfx() -> void:
	_sfx_player = AudioStreamPlayer.new()
	add_child(_sfx_player)
	for n in SFX_PRECACHE:
		var r := load(SFX_BASE + n + ".wav")
		if r != null:
			_sfx_cache[n] = r
		else:
			push_error("Player SFX not found: " + SFX_BASE + n + ".wav")


func _play_sfx(sfx_name: String) -> void:
	var s = _sfx_cache.get(sfx_name)
	if s != null:
		_sfx_player.stream = s
		_sfx_player.play()


func _setup_spine() -> void:
	var profile: Dictionary = Skulls.get_profile(skull_id)
	var data_path := str(profile["data"])
	var data = load(data_path)
	if data == null or not data.call("is_skeleton_data_loaded"):
		push_error("Player: 骨架数据加载失败 " + data_path)
		return
	# 换头时先把旧骨架拆掉，避免两套骨架同时在场
	if sprite != null and is_instance_valid(sprite):
		sprite.queue_free()
		sprite = null
		_anim_state = null
	sprite = ClassDB.instantiate("SpineSprite")
	add_child(sprite)
	sprite.set("skeleton_data_res", data)
	data.call("set_default_mix", 0.2) # 切换混合 0.1->0.2，收招/起步过渡更柔
	sprite.scale = Vector2(base_scale * facing, base_scale)
	_anim_state = sprite.call("get_animation_state")
	# 缓存技能动画真实时长，技能锁定必须按实际时长走（C016 的教训：手填时长收招会抽搐）
	_skill_durations.clear()
	_skill_cds.clear()
	for n in skill_config:
		var a = data.call("find_animation", n)
		if a != null:
			_skill_durations[n] = a.call("get_duration")
		else:
			push_error("Player: 技能动画不存在 " + n)
		_skill_cds[n] = 0.0
	_current_anim = ""
	_play(anim_map["idle"], true)


func _physics_process(delta: float) -> void:
	_coyote = maxf(0.0, _coyote - delta)
	_jump_buf = maxf(0.0, _jump_buf - delta)
	_dash_cd = maxf(0.0, _dash_cd - delta)
	_hurt_invincible = maxf(0.0, _hurt_invincible - delta)
	for n in _skill_cds:
		_skill_cds[n] = maxf(0.0, _skill_cds[n] - delta)
	if is_on_floor():
		_coyote = coyote_time
	if Input.is_action_just_pressed("jump"):
		_jump_buf = jump_buffer
	if Input.is_action_just_pressed("swap_skull"):
		_try_swap_skull()

	match state:
		State.IDLE, State.RUN:
			_ground_move(delta)
		State.JUMP, State.FALL:
			_air_move(delta)
		State.DASH:
			_dash_tick(delta)
		State.ATTACK:
			_attack_tick(delta)
		State.SKILL:
			_skill_tick(delta)
		State.HURT:
			_hurt_tick(delta)
		State.DEAD:
			velocity.x = 0.0

	if state != State.DASH:
		velocity.y = minf(velocity.y + gravity * delta, max_fall_speed)
	move_and_slide()
	_post_move()


# ---------- 各状态逻辑 ----------

func _ground_move(delta: float) -> void:
	var dir := Input.get_axis("move_left", "move_right")
	if dir != 0.0:
		var target := dir * run_speed
		var acc := accel if signf(velocity.x) == dir else turn_accel # 反向转弯给更大加速度，避免"踩住刹车"的粘滞
		facing = 1 if dir > 0.0 else -1
		_apply_facing()
		velocity.x = move_toward(velocity.x, target, acc * delta)
		_set_state(State.RUN)
	else:
		# 松油门立刻重刹，跟动作游戏的手感走——停下比起步快
		velocity.x = move_toward(velocity.x, 0.0, brake * delta)
		_set_state(State.IDLE)
	_try_jump()
	_try_dash()
	if Input.is_action_just_pressed("attack"):
		_start_attack(0)
	else:
		_try_skill()


func _air_move(delta: float) -> void:
	var dir := Input.get_axis("move_left", "move_right")
	if dir != 0.0:
		facing = 1 if dir > 0.0 else -1
		_apply_facing()
		velocity.x = move_toward(velocity.x, dir * run_speed, accel * 0.7 * delta)
	else:
		# 空中松油门轻微制动，比地面刹得慢（不锁死空中控制）
		velocity.x = move_toward(velocity.x, 0.0, brake * 0.4 * delta)
	_try_dash()


func _dash_tick(delta: float) -> void:
	_dash_timer -= delta
	velocity = Vector2(facing * dash_speed, 0.0)
	if _dash_timer <= 0.0:
		_dash_cd = dash_cooldown
		velocity.x = facing * run_speed * 0.5
		_set_state(State.IDLE if is_on_floor() else State.FALL)


func _attack_tick(delta: float) -> void:
	_attack_timer -= delta
	# 攻击期间继续减速 lunge，用比地面略低的制动让前冲带"惯性"感——
	# 原来用 accel=2200 秒刹，位移只有 2-3px，等于没冲；现在用 brake*0.5，
	# 刹得慢一半，lunge 110px 至少能飘 10px 出去再停
	velocity.x = move_toward(velocity.x, 0.0, brake * 0.5 * delta)
	if Input.is_action_just_pressed("attack"):
		_attack_queued = true
	# 到点结算命中（支持一段动画多次命中，如 atk03 双刺）
	var lock: float = float(attacks[_attack_idx]["lock"])
	var t: float = lock - _attack_timer # 动画已进行时间
	while not _attack_hits.is_empty() and t >= _attack_hits[0]:
		_attack_hits.pop_front()
		_deal_hit()
	# 取消窗口：本段命中全部结算完后、lock 后 30%（atk["cancel"] 可调）允许提前
	# 接下一招 / 移动 / dash——不用干等收招帧，连段手感跟得上输入节奏
	var cancel_from: float = lock * (1.0 - float(attacks[_attack_idx].get("cancel", 0.3)))
	if t >= cancel_from and _attack_hits.is_empty():
		if _attack_queued and _attack_idx < attacks.size() - 1:
			_start_attack(_attack_idx + 1)
			return
		if Input.get_axis("move_left", "move_right") != 0.0:
			_set_state(State.IDLE if is_on_floor() else State.FALL)
			return
		_try_dash()
	if _attack_timer <= 0.0:
		if _attack_queued and _attack_idx < attacks.size() - 1:
			_start_attack(_attack_idx + 1)
		else:
			_set_state(State.IDLE if is_on_floor() else State.FALL)


func _deal_hit() -> void:
	if _attack_idx < 0 or _attack_idx >= attacks.size():
		return
	var atk: Dictionary = attacks[_attack_idx]
	# 远程形态：发投射物，命中由投射物自己结算（伤害带上局内强化与契合加伤）
	if atk.has("projectile"):
		_spawn_projectile(atk["projectile"], int(atk["damage"]) + damage_bonus + _mastery_dmg, "voice_sword_hit")
		return
	var did_hit := false
	for e in get_tree().get_nodes_in_group("enemies"):
		var p := e as Node2D
		if p == null:
			continue
		var dx: float = p.global_position.x - global_position.x
		var dy: float = absf(p.global_position.y - global_position.y)
		var in_front := dx == 0.0 or (dx > 0.0) == (facing > 0)
		# both = 回身横扫：动画把武器甩到身后，前后两侧都算命中，否则"动画打到却没判上"
		var side_ok: bool = in_front or bool(atk.get("both", false))
		if side_ok and absf(dx) <= float(atk["range"]) and dy <= 70.0:
			p.call("take_damage", int(atk["damage"]) + damage_bonus + _mastery_dmg, global_position.x)
			Score.add_hit() # 命中一只算一次连击
			# 朱砂斩击打在攻击者与被击者的中点胸口高度：视觉上像"从玩家挥出"
			var mx := (global_position.x + p.global_position.x) * 0.5
			FX.spawn(get_tree().current_scene, "slash", Vector2(mx, global_position.y - 70), {"scale": 0.45, "flip": facing < 0})
			did_hit = true
	if did_hit:
		_play_sfx("voice_sword_hit")
		Feel.hitstop(0.045) # 命中一僵，普攻比技能轻
		Feel.shake(4.0, 0.13)


func _skill_tick(delta: float) -> void:
	_skill_timer -= delta
	var cfg: Dictionary = skill_config[_skill_name]
	var t: float = _skill_dur - _skill_timer # 技能已进行时间
	# 闪现段：高速前冲 + 无敌 + 穿过敌人（动画此时隐身，视觉上是瞬身）
	if cfg.has("blink_from") and t >= cfg["blink_from"] and t <= cfg["blink_to"]:
		_invincible = true
		_set_blink(true)
		velocity.x = facing * cfg["blink_speed"]
	else:
		_invincible = false
		_set_blink(false)
		velocity.x = move_toward(velocity.x, 0.0, accel * delta)
	# 到点结算命中段
	while not _skill_hits.is_empty() and t >= _skill_hits[0]["at"]:
		var h: Dictionary = _skill_hits.pop_front()
		_deal_skill_hit(h)
	# 纯时长驱动退出：到点的同一帧排队的 stand 恰好接续，别看 is_complete（会被 loop 污染）
	if _skill_timer <= 0.0:
		_invincible = false
		_set_blink(false)
		_set_state(State.IDLE if is_on_floor() else State.FALL)


func _set_blink(on: bool) -> void:
	if on == _blink_active:
		return
	_blink_active = on
	for e in get_tree().get_nodes_in_group("enemies"):
		if on:
			add_collision_exception_with(e)
		else:
			remove_collision_exception_with(e)


func _deal_skill_hit(h: Dictionary) -> void:
	# 远程技能：发投射物，命中由投射物自己结算
	if h.has("projectile"):
		_spawn_projectile(h["projectile"], int(h["damage"]) + damage_bonus, str(h.get("sfx", "")))
		return
	var did_hit := false
	for e in get_tree().get_nodes_in_group("enemies"):
		var p := e as Node2D
		if p == null:
			continue
		var dx: float = p.global_position.x - global_position.x
		var dy: float = absf(p.global_position.y - global_position.y)
		if dy > h["height"]:
			continue
		if h.get("path", false):
			# 路径判定：闪现扫过的整条线段 + 落点正前方 range
			var x0: float = minf(_skill_start_x, global_position.x) - 20.0
			var x1: float = maxf(_skill_start_x, global_position.x) + 20.0
			var in_path: bool = p.global_position.x >= x0 and p.global_position.x <= x1
			var ahead := dx == 0.0 or (dx > 0.0) == (facing > 0)
			if in_path or (ahead and absf(dx) <= h["range"]):
				p.call("take_damage", int(h["damage"]) + damage_bonus, global_position.x)
				Score.add_hit()
				var mx := (global_position.x + p.global_position.x) * 0.5
				FX.spawn(get_tree().current_scene, "slash", Vector2(mx, global_position.y - 70), {"scale": 0.55, "flip": facing < 0})
				did_hit = true
		else:
			var in_front := dx == 0.0 or (dx > 0.0) == (facing > 0)
			# both = 回身横扫（力僧狼牙棒、枪侠回马枪）：动画扫到身后也照样判定
			if (in_front or bool(h.get("both", false))) and absf(dx) <= h["range"]:
				p.call("take_damage", int(h["damage"]) + damage_bonus, global_position.x)
				Score.add_hit()
				var mx := (global_position.x + p.global_position.x) * 0.5
				FX.spawn(get_tree().current_scene, "slash", Vector2(mx, global_position.y - 70), {"scale": 0.55, "flip": facing < 0})
				did_hit = true
	if did_hit:
		if h.has("sfx"):
			_play_sfx(h["sfx"])
		Feel.hitstop(0.06) # 技能命中：比普攻更重的顿帧与震屏
		Feel.shake(7.0, 0.2)


## 发一颗投射物：从胸口高度出手，沿朝向直线飞
func _spawn_projectile(spec: Dictionary, damage: int, sfx: String) -> void:
	var pr = PROJECTILE.new()
	pr.setup(facing, float(spec.get("speed", 520.0)), float(spec.get("range", 420.0)), damage, sfx)
	pr.global_position = global_position + Vector2(facing * 36.0, -52.0)
	get_tree().current_scene.add_child(pr)


func _hurt_tick(delta: float) -> void:
	_hurt_timer -= delta
	velocity.x = move_toward(velocity.x, 0.0, accel * delta)
	if _hurt_timer <= 0.0:
		_set_state(State.IDLE if is_on_floor() else State.FALL)


## 给 HUD 查技能冷却进度：返回 0（就绪）~ 1（刚放完）。未知技能返回 0。
func get_skill_cd_ratio(n: String) -> float:
	var cfg = skill_config.get(n, {})
	if cfg == null:
		return 0.0
	var total: float = cfg["cooldown"]
	if total <= 0.0:
		return 0.0
	var cd: float = _skill_cds.get(n, 0.0)
	return clampf(cd / total, 0.0, 1.0)


## 给 HUD 查技能对应的按键字母
func get_skill_key(n: String) -> String:
	var cfg: Dictionary = skill_config.get(n, {})
	return str(KEY_LABELS.get(str(cfg.get("action", "")), "-"))


# ---------- 动作入口 ----------

func _try_jump() -> void:
	if _jump_buf > 0.0 and _coyote > 0.0:
		_jump_buf = 0.0
		_coyote = 0.0
		velocity.y = jump_velocity
		_set_state(State.JUMP)


func _try_dash() -> void:
	if Input.is_action_just_pressed("dash") and _dash_cd <= 0.0:
		state = State.DASH
		_dash_timer = dash_time
		_play(anim_map["dash"], false)


func _start_attack(idx: int) -> void:
	if idx < 0 or idx >= attacks.size():
		return
	var atk: Dictionary = attacks[idx]
	state = State.ATTACK
	_attack_idx = idx
	_attack_timer = float(atk["lock"])
	_attack_queued = false
	_attack_hits = (atk["hits"] as Array).duplicate() # 待弹出的命中时刻列表
	velocity.x = facing * float(atk["lunge"])
	_play(str(atk["anim"]), false)
	_play_sfx("weapon_sword") # 起手嗖一声
	_queue(anim_map["idle"], true) # 打完自动回 idle，防止卡在收招帧


func _try_skill() -> void:
	for n in skill_config:
		var cfg: Dictionary = skill_config[n]
		if Input.is_action_just_pressed(cfg["action"]) and _skill_cds.get(n, 0.0) <= 0.0:
			_start_skill(n)
			return


func _start_skill(n: String) -> void:
	state = State.SKILL
	_skill_name = n
	_skill_dur = _skill_durations.get(n, 2.0)
	_skill_timer = _skill_dur
	_skill_hits = skill_config[n]["hits"].duplicate(true)
	_skill_start_x = global_position.x
	_skill_cds[n] = float(skill_config[n]["cooldown"]) * cooldown_scale * _mastery_cd
	_invincible = false
	velocity.x = facing * float(attacks[0]["lunge"]) * 0.6 # 起手小前冲
	_play(n, false)
	_play_sfx("voice_skill_cast") # 技能起手嗡一声
	# 排队 stand 紧跟技能之后：非循环动画播完瞬间轨道空窗会闪回 setup pose
	_queue(anim_map["idle"], true)
	_idle_queued = true


## 换头：Q 键打开化身面板（暂停时间选形态），扣墨骨由面板在选中时结算
func _try_swap_skull() -> void:
	if state == State.DEAD or get_tree().paused:
		return
	var scene := get_tree().current_scene
	if scene == null or scene.get_node_or_null("SwapPanel") != null:
		return
	var panel = load("res://scenes/ui/swap_panel.tscn").instantiate()
	panel.name = "SwapPanel"
	panel.setup(self) # 必须在 add_child 前：面板的 _ready 要读当前形态
	scene.add_child(panel)


## 立刻换成指定形态：拆旧骨架 → 重装形态数据 → 重建骨架
func swap_skull(id: String) -> void:
	if not Skulls.SKULLS.has(id) or id == skull_id:
		return
	_set_blink(false) # 换头瞬间收掉闪现的碰撞例外
	_invincible = false
	_idle_queued = false
	_attack_idx = -1
	_skill_name = ""
	_skill_timer = 0.0
	_apply_profile(id)
	_setup_spine()
	Run.skull_id = id # 局外养成的击杀/通关记账按当前形态归属，换头后立刻同步
	_play_sfx("voice_skill_cast")
	# 化身光柱从脚下冲天而起，盖住拆骨换形的一瞬间
	FX.spawn(get_tree().current_scene, "pillar", global_position, {"scale": 0.75, "z": 30})
	if is_on_floor():
		state = State.IDLE
		_play(anim_map["idle"], true)
	else:
		state = State.FALL
		_play(anim_map["air"], true)
	skull_changed.emit(id)


func hurt(amount: int = 1, knockback: Vector2 = Vector2.ZERO) -> void:
	if state == State.DEAD or state == State.DASH or _invincible or _hurt_invincible > 0.0:
		return
	_hurt_invincible = 0.8
	hp -= amount
	hp_changed.emit(hp, max_hp)
	_spawn_number(amount, DMG_COLOR, 130.0)
	_play_sfx("hit_fist") # 玩家受伤闷拳声
	# 水墨受击花在胸口炸开，flip 跟击退方向（击退朝右 = 攻击来自左侧）
	FX.spawn(get_tree().current_scene, "ink_hit", global_position + Vector2(0, -70), {"scale": 0.45, "flip": knockback.x > 0.0})
	Feel.hitstop(0.05) # 挨打也要"一僵"：受击反馈和打人一样重要
	Feel.shake(8.0, 0.24)
	if hp <= 0:
		# 残墨续命赐福：一局一次，以 4 点生命原地爬起
		if Run.blessing == "revive" and not Run.blessing_used:
			Run.blessing_used = true
			hp = mini(4, max_hp)
			_hurt_invincible = 1.5 # 起身喘口气，别立刻又被围殴
			hp_changed.emit(hp, max_hp)
			state = State.HURT
			_hurt_timer = hurt_time
			velocity = knockback
			_play(anim_map["getup"], false)
			_queue(anim_map["idle"], true)
			_idle_queued = true
			return
		die()
		return
	state = State.HURT
	_hurt_timer = hurt_time
	velocity = knockback
	_idle_queued = false # set_animation 已清掉队列里的 stand
	_invincible = false
	_play(anim_map["hurt"], false)


func _spawn_number(amount: int, color: Color, height: float) -> void:
	var dn := DAMAGE_NUMBER.new()
	dn.setup(str(amount), color)
	dn.global_position = global_position + Vector2(randf_range(-12.0, 12.0), -height)
	get_tree().current_scene.add_child(dn)


func die() -> void:
	state = State.DEAD
	velocity = Vector2.ZERO
	_idle_queued = false
	_invincible = false
	_play(anim_map["dead"], false)
	died.emit()


# ---------- 内部工具 ----------

func _post_move() -> void:
	match state:
		State.IDLE, State.RUN:
			if not is_on_floor() and _coyote <= 0.0:
				_set_state(State.FALL)
		State.JUMP:
			if velocity.y > 0.0:
				_set_state(State.FALL)
		State.FALL:
			if is_on_floor():
				_set_state(State.RUN if absf(velocity.x) > 10.0 else State.IDLE)


func _set_state(new_state: int) -> void:
	if state == new_state:
		return
	state = new_state
	match state:
		State.IDLE:
			if _idle_queued:
				# stand 已被 Spine 自动接续播放，只同步记录，不重复 set（重开会重开淡化）
				_current_anim = anim_map["idle"]
			else:
				_play(anim_map["idle"], true)
			_idle_queued = false
		State.RUN:
			_idle_queued = false
			_play(anim_map["run"], true)
		State.JUMP, State.FALL:
			_idle_queued = false # set_animation 会清掉队列里的 stand
			_play(anim_map["air"], true)


func _apply_facing() -> void:
	if sprite:
		sprite.scale.x = base_scale * facing


func _play(anim: String, loop: bool) -> void:
	if _anim_state == null:
		return
	if loop and anim == _current_anim:
		return # 循环动画同名重放 = 从头再来一遍，跳跃顶点会抽搐
	_current_anim = anim
	_anim_state.call("set_animation", anim, loop, 0)


func _queue(anim: String, loop: bool) -> void:
	if _anim_state:
		_anim_state.call("add_animation", anim, 0.0, loop, 0)
