extends Node2D

## 斗蛐蛐战斗单位：外观与招式动画取 duel_roster 里整理好的一条名录（化身 / 杂兵 / 首领通用），
## 生命 / 攻击倍率 / 移速 / 出手间隔由斗蛐蛐面板给，不读写 Run，也不接任何输入。
## 行为极简：朝对手走 → 进到攻击距离就出一招 → 收招后按间隔再接，挨打进硬直，倒地即负。

signal died(fighter)

const SFX_HIT := preload("res://audio/sfx/hit_light.wav")
const SFX_HEAVY := preload("res://audio/sfx/hit_heavy.wav")

const BASE_PX := 1.75 # 局内 128px 高的化身在观战里放大到 224px；首领按同一倍率再卡上限
const MIN_H := 150.0
const MAX_H := 340.0
const MIN_X := 210.0
const MAX_X := 1070.0

var fighter_name := ""
var team_name := "红队"
var team_color := Color(0.80, 0.28, 0.22)
var max_hp := 40.0
var hp := 40.0
var atk_scale := 1.6
var move_speed := 200.0
var attack_interval := 0.9
var radius := 52.0 # 观战体型半径：决定两人最近能站多近，大块头自动让开

var enemies: Array = [] # 对面全队：每帧挑最近的活人打
var preferred: Array = [] # 中军预排的对手序列（按下标对应自己的 rank），避免多人抢同一个目标挤成一团
var rank := 0
var active := false

var _sprite = null
var _data = null
var _target = null
var _base_scale := 1.0
var _tint := Color(1, 1, 1)
var _facing := 1
var _anims := {}
var _attacks: Array = []
var _reach := 110.0
var _stop := 104.0
var _state := "idle" # idle / run / attack / hurt / dead
var _playing := ""
var _timer := 0.0
var _cd := 0.0
var _hit_delay := -1.0
var _hit_damage := 0.0
var _hit_range := 110.0
var _flash := 0.0
var _sfx: AudioStreamPlayer


func setup(entry: Dictionary, stats: Dictionary, tname: String, tcolor: Color) -> void:
	fighter_name = str(entry.get("name", "?"))
	team_name = tname
	team_color = tcolor
	max_hp = maxf(float(stats.get("hp", 40)), 1.0)
	hp = max_hp
	atk_scale = float(stats.get("atk", 1.6))
	move_speed = float(stats.get("spd", 200.0))
	attack_interval = float(stats.get("gap", 0.9))
	radius = clampf(float(entry.get("radius", 30.0)) * BASE_PX, 44.0, 150.0)
	_anims = entry.get("anim", {})
	_attacks = entry.get("moves", [])
	_reach = _min_reach()
	_stop = 104.0 # 真实体型要等骨架加载后才知道，_build_sprite 里再算
	_tint = Color(1, 1, 1).lerp(team_color, 0.30)
	_sfx = AudioStreamPlayer.new()
	_sfx.bus = "SFX"
	add_child(_sfx)
	_build_sprite(str(entry.get("data", "")), float(entry.get("scale", 1.0)))


## 该单位最短一档判定距离：走到这个距离才停，保证每招都够得着
func _min_reach() -> float:
	var best := 220.0
	for m in _attacks:
		best = minf(best, float(m.get("range", 110.0)))
	return clampf(best, 90.0, 260.0)


## 观战显示高度：局内像素高 × 统一倍率，首领封顶，避免巨型 Boss 把画面撑爆
func _build_sprite(path: String, in_game_scale: float) -> void:
	if path == "" or not ResourceLoader.exists(path):
		return
	var data = load(path)
	if data == null:
		return
	_data = data
	_sprite = ClassDB.instantiate("SpineSprite")
	add_child(_sprite)
	_sprite.set("skeleton_data_res", data)
	data.call("set_default_mix", 0.2)
	var raw := maxf(float(data.call("get_height")), 1.0)
	var want := clampf(raw * in_game_scale * BASE_PX, MIN_H, MAX_H)
	_base_scale = want / raw
	_stop = clampf(want * 0.40, 96.0, 180.0) # 体型越大站位越远，避免大块头互相穿模
	_sprite.position = Vector2.ZERO
	_sprite.scale = Vector2(_base_scale, _base_scale)
	_sprite.modulate = _tint
	_play("idle", true)


func _play(key: String, loop: bool) -> void:
	_play_anim(str(_anims.get(key, "")), loop)


## 直接按动画名播：攻击/技能招的名字不在 idle/run/hurt/dead 映射里，必须走这条
func _play_anim(name: String, loop: bool) -> void:
	if _sprite == null or name == "":
		return
	if name == _playing and loop:
		return # 循环动作不重复起播，否则跑步会一直卡在第一帧
	if _data != null and _data.call("find_animation", name) == null:
		return # 骨架里没有这支动画，别把状态卡死
	_playing = name
	_sprite.call("get_animation_state").call("set_animation", name, loop, 0.12)


func is_dead() -> bool:
	return _state == "dead"


func _physics_process(delta: float) -> void:
	if _flash > 0.0:
		_flash = maxf(0.0, _flash - delta)
		if _sprite != null:
			var k := 1.0 + _flash * 4.5
			_sprite.modulate = Color(_tint.r * k, _tint.g * k, _tint.b * k)
	if _state == "dead" or not active:
		return
	_cd = maxf(0.0, _cd - delta)
	if _state == "hurt":
		_timer -= delta
		if _timer <= 0.0:
			_state = "idle"
			_play("idle", true)
		return
	if _state == "attack":
		_timer -= delta
		if _hit_delay > 0.0:
			_hit_delay -= delta
			if _hit_delay <= 0.0:
				_apply_hit()
		if _timer <= 0.0:
			_state = "idle"
			_play("idle", true)
		return
	if not _target_alive():
		_target = _nearest()
	if not _target_alive():
		_state = "idle"
		_play("idle", true)
		return
	var dx: float = _target.global_position.x - global_position.x
	var dist := absf(dx)
	_set_facing(1 if dx >= 0.0 else -1)
	var gap := _stop
	var orad = _target.get("radius")
	if orad != null and float(orad) > 0.0:
		gap = maxf(gap, radius + float(orad) + 16.0) # 两边体型加起来才是最近站位
	if dist > maxf(_reach, gap):
		global_position.x = clampf(global_position.x + signf(dx) * move_speed * delta, MIN_X, MAX_X)
		if _state != "run":
			_state = "run"
		_play("run", true)
	else:
		if _state == "run":
			_state = "idle"
		_play("idle", true)
		if _cd <= 0.0:
			_start_attack()


func _target_alive() -> bool:
	return is_instance_valid(_target) and _target.has_method("is_dead") and not _target.is_dead()


## 索敌：优先打队伍预先配好的那名对手，配好的倒了就挑最近的活人
func _nearest():
	var idx := mini(rank, preferred.size() - 1)
	if idx >= 0:
		var p = preferred[idx]
		if is_instance_valid(p) and p.has_method("is_dead") and not p.is_dead():
			return p
	var pool: Array = preferred if not preferred.is_empty() else enemies
	var best = null
	var best_d := INF
	for e in pool:
		if not is_instance_valid(e) or not e.has_method("is_dead") or e.is_dead():
			continue
		var d: float = absf(e.global_position.x - global_position.x)
		if d < best_d:
			best_d = d
			best = e
	return best


## 由斗蛐蛐战场在开打前统一排定：list 按左右顺序排好，rank 是本单位在己方队列里的位置
func set_preferred(list: Array, r: int) -> void:
	preferred = list
	rank = r
	_target = null


func _set_facing(dir: int) -> void:
	if dir == _facing:
		return
	_facing = dir
	if _sprite != null:
		_sprite.scale = Vector2(_base_scale * _facing, _base_scale)


func _start_attack() -> void:
	if _attacks.is_empty():
		return
	var m: Dictionary = _attacks[randi() % _attacks.size()]
	var lock := maxf(float(m.get("lock", 0.8)), 0.3)
	_hit_range = clampf(float(m.get("range", 110.0)), 60.0, 360.0)
	_hit_damage = float(m.get("damage", 1)) * atk_scale
	_hit_delay = clampf(float(m.get("at", 0.3)), 0.05, lock - 0.05)
	_timer = lock
	_cd = attack_interval
	_state = "attack"
	_play_anim(str(m.get("anim", "atk01")), false)


## 出手时刻到了：对方还在判定距离内才算命中（走开就落空）
func _apply_hit() -> void:
	_hit_delay = -1.0
	if not _target_alive():
		return
	var dist: float = absf(_target.global_position.x - global_position.x)
	var tol := _hit_range + 40.0
	var orad = _target.get("radius")
	if orad != null:
		tol = _hit_range + float(orad) # 沿用闯关规则：射程 + 对方体型半径，大块头更好打中
	if dist > tol:
		return
	var dmg := maxi(1, int(round(_hit_damage)))
	_target.hurt(dmg, global_position.x)
	_sfx.stream = SFX_HIT if dmg <= 2 else SFX_HEAVY
	_sfx.play()


func hurt(amount: int, from_x: float) -> void:
	if _state == "dead":
		return
	hp = maxf(0.0, hp - float(amount))
	_flash = 0.16
	_hit_delay = -1.0
	if hp <= 0.0:
		_die()
		return
	_state = "hurt"
	_timer = 0.22
	_play("hurt", false)
	global_position.x = clampf(global_position.x + signf(global_position.x - from_x) * 8.0, MIN_X, MAX_X)


func _die() -> void:
	_state = "dead"
	active = false
	_playing = ""
	_play("dead", false)
	if _sprite != null:
		_sprite.modulate = Color(0.72, 0.69, 0.66)
	died.emit(self)
