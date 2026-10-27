extends Node2D

## 墨骨掉落物：敌人死亡时生成，先上抛再落地，落地后玩家靠近自动吸附。
## 纯 _draw 画墨点，不依赖任何美术素材。加到场景根节点即可（局部坐标=世界坐标）。

const PICKUP_RANGE := 95.0 # 吸附触发半径
const ATTRACT_SPEED := 460.0 # 吸附飞行速度
const COLLECT_DIST := 24.0 # 收下判定距离
const LIFETIME := 14.0 # 无人拾取自动消失
const GRAVITY := 1500.0

const SFX_PICKUP := preload("res://audio/sfx/pickup.wav")
const SFX_GOLD := preload("res://audio/sfx/gold.wav")

var _vel := Vector2.ZERO
var _ground_y := 0.0 # 落地的 y（生成位置的地面高度）
var _t := 0.0
var _landed := false
var _player: Node2D


func _ready() -> void:
	_ground_y = global_position.y
	_vel = Vector2(randf_range(-80.0, 80.0), randf_range(-300.0, -190.0))
	z_index = 6


func _process(delta: float) -> void:
	_t += delta
	if _t >= LIFETIME:
		queue_free()
		return
	# 未落地：做上抛自由落体
	if not _landed:
		_vel.y += GRAVITY * delta
		global_position += _vel * delta
		if global_position.y >= _ground_y and _vel.y > 0.0:
			global_position.y = _ground_y
			_landed = true
		return
	# 落地后：玩家进入范围就吸附过去
	if _player == null or not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group("player") as Node2D
	if _player == null:
		return
	var d: Vector2 = _player.global_position - global_position
	if d.length() > PICKUP_RANGE:
		return
	if d.length() <= COLLECT_DIST:
		Score.add_bones(1)
		var s := AudioStreamPlayer.new()
		get_tree().current_scene.add_child(s)
		s.stream = SFX_PICKUP
		s.play()
		queue_free()
		return
	global_position += d.normalized() * ATTRACT_SPEED * delta


func _draw() -> void:
	# 墨点：主体深墨 + 偏一点的淡墨高光，模拟水墨飞白
	draw_circle(Vector2.ZERO, 7.0, Color(0.05, 0.05, 0.05, 0.9))
	draw_circle(Vector2(-2.0, -2.0), 3.0, Color(0.42, 0.42, 0.42, 0.85))
