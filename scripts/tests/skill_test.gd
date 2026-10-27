extends Node2D

## 玩家技能验证探针：
## 时间轴：t=0.5 按 K(skill01 突刺瞬身) / t=3.0 按 L(skill03 横扫) / t=7.0 按 U(skill04 大招)
## 校验点：
## 1) 敌人 hp 下降时刻 == 配置的命中时刻（skill01≈1.8s, skill03≈4.0/5.0s, skill04≈8.2/9.1/10.1s）
## 2) skill01 闪现段玩家 x 前移 ~270px 且期间 _invincible == true
## 3) 技能退出时刻 == 动画真实时长（state SKILL->IDLE 不提前不延后）
## 日志写 tests/skill_test.log，关键时刻截图 tests/out/skilltest_*.png

const OUT_DIR := "res://tests/out/"

var _log: FileAccess
var _player
var _enemy
var _t := 0.0
var _prev_state := -1
var _prev_hp := -1
var _pressed := {} # 已触发过的按键时刻
var _shots := {} # 已截过的截图时刻

const KEY_AT := [[0.5, "skill"], [3.0, "skill_sweep"], [7.0, "skill_ult"]]
const SHOT_AT := [1.3, 1.8, 4.0, 5.0, 8.2, 9.1, 10.1]

func p(msg) -> void:
	print("[T] ", msg)
	if _log:
		_log.store_line("[T] " + str(msg))
		_log.flush()

func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	_log = FileAccess.open("res://tests/skill_test.log", FileAccess.WRITE)
	get_window().size = Vector2i(1280, 720)

	var ground := StaticBody2D.new()
	ground.position = Vector2(640, 660)
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(1280, 80)
	shape.shape = rect
	ground.add_child(shape)
	add_child(ground)

	_player = load("res://scenes/player/player.tscn").instantiate()
	_player.position = Vector2(400, 560)
	add_child(_player)
	_enemy = load("res://scenes/enemies/c016.tscn").instantiate()
	_enemy.position = Vector2(520, 560)
	add_child(_enemy)
	_enemy.detect_range = 0.0 # 关闭 AI，纯木桩
	_enemy.lose_range = 0.0 # 被打后 _target 仍在，不让它进 CHASE 还手
	_enemy.patrol_speed = 0.0
	_enemy.max_hp = 20
	_enemy.hp = 20
	_prev_hp = _enemy.hp
	p("ready. enemy_hp=%d player_x=%.1f" % [_enemy.hp, _player.global_position.x])

	await get_tree().create_timer(13.0).timeout
	p("ALL DONE")
	get_tree().quit()

func _physics_process(delta: float) -> void:
	if _player == null or _enemy == null or _player._anim_state == null:
		return
	_t += delta

	# 按计划按键（按下当帧生效，下一帧松开）
	for kv in KEY_AT:
		if _t >= kv[0] and not _pressed.has(kv[0]):
			_pressed[kv[0]] = true
			Input.action_press(kv[1])
			p("PRESS %s at t=%.3f" % [kv[1], _t])
		elif _pressed.has(kv[0]) and _t >= kv[0] + 0.05:
			Input.action_release(kv[1])
	# 每次技能前把木桩挪回玩家正前方（skill01 会把玩家闪现到木桩身后）
	for tp in [2.9, 6.9]:
		if _t >= tp and not _pressed.has(tp):
			_pressed[tp] = true
			_enemy.position = Vector2(_player.global_position.x + 140.0, 560)
			p("TELEPORT enemy to x=%.1f at t=%.3f" % [_enemy.position.x, _t])

	# state 切换
	if _player.state != _prev_state:
		p("STATE %d -> %d  t=%.3f x=%.1f inv=%s" % [_prev_state, _player.state, _t, _player.global_position.x, str(_player._invincible)])
		_prev_state = _player.state

	# 敌人掉血 = 命中结算时刻
	if _enemy.hp != _prev_hp:
		p("HIT t=%.3f enemy_hp %d -> %d player_x=%.1f" % [_t, _prev_hp, _enemy.hp, _player.global_position.x])
		_prev_hp = _enemy.hp

	# 关键帧截图
	for s in SHOT_AT:
		if _t >= s and not _shots.has(s):
			_shots[s] = true
			_shot("t%.1f" % s)

func _shot(tag: String) -> void:
	await RenderingServer.frame_post_draw
	var img = get_viewport().get_texture().get_image()
	img.save_png(OUT_DIR + "skilltest_" + tag + ".png")
