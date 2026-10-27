extends Node2D

## 飞行投射物（剑仙剑气）：生成后直线飞行，命中第一个敌人结算伤害，飞满射程自灭。
## 纯 Node2D 手动移动 + 敌组距离判定，和玩家近战判定同一套思路，不开物理区。
## 视觉用 _draw 画一道朱砂剑气弧 + 拖尾墨痕，命中靠 Feel 顿帧震屏 + 音效收尾。

const INK := Color(0.08, 0.07, 0.1)
const RED := Color(0.66, 0.2, 0.16)
const QI := Color(0.78, 0.36, 0.42) # 剑气的朱砂偏粉芯
const QI_GLOW := Color(0.78, 0.36, 0.42, 0.28)

var _dir := 1
var _speed := 520.0
var _range := 420.0
var _damage := 1
var _sfx := ""
var _sfx_stream
var _travel := 0.0
var _sfx_player: AudioStreamPlayer


## dir: 1 朝右 -1 朝左；damage 已含局内强化/契合加成；sfx 命中音效名（空则不播）
func setup(p_dir: int, p_speed: float, p_range: float, p_damage: int, p_sfx := "") -> void:
	_dir = p_dir
	_speed = p_speed
	_range = p_range
	_damage = p_damage
	_sfx = p_sfx


func _ready() -> void:
	scale.x = _dir # 剑气弧朝飞行方向
	if _sfx != "":
		_sfx_stream = load("res://audio/sfx/" + _sfx + ".wav")
		_sfx_player = AudioStreamPlayer.new()
		add_child(_sfx_player)
	queue_redraw()


func _draw() -> void:
	# 剑气：一道前凸的朱砂弧 + 内侧淡晕 + 后方两笔墨拖尾
	var arc_pts := PackedVector2Array()
	for i in 9:
		var a: float = lerpf(-1.15, 1.15, i / 8.0)
		arc_pts.append(Vector2(cos(a) * 10.0, sin(a) * 30.0))
	draw_circle(Vector2.ZERO, 20.0, QI_GLOW)
	draw_polyline(arc_pts, QI, 4.0, true)
	draw_polyline(arc_pts, Color(1.0, 0.86, 0.82, 0.9), 1.5, true)
	# 墨拖尾：从弧心往后拉两道细线
	draw_line(Vector2(-4, -14), Vector2(-34, -7), Color(INK, 0.55), 2.5)
	draw_line(Vector2(-4, 14), Vector2(-30, 8), Color(INK, 0.4), 2.0)


func _physics_process(delta: float) -> void:
	var step := _speed * delta
	position.x += _dir * step
	_travel += step
	# 命中判定：横向贴近剑气、纵向与敌人脚底同一平面（剑气在胸口高度飞）
	for e in get_tree().get_nodes_in_group("enemies"):
		var p := e as Node2D
		if p == null:
			continue
		if absf(p.global_position.x - global_position.x) <= 30.0 and absf(p.global_position.y - global_position.y) <= 80.0:
			p.call("take_damage", _damage, global_position.x)
			Score.add_hit()
			Feel.hitstop(0.04)
			Feel.shake(3.0, 0.1)
			if _sfx_stream != null:
				_sfx_player.stream = _sfx_stream
				_sfx_player.play()
				_sfx_player.finished.connect(queue_free, CONNECT_ONE_SHOT) # 等命中音放完再灭
				set_physics_process(false)
				visible = false
			else:
				queue_free()
			return
	if _travel >= _range:
		queue_free()
