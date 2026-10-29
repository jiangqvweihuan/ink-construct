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
var _pierce := false # 穿云剑气（剑仙形态专属）：命中后不消失继续飞
var _hit_list: Array = [] # 穿透模式下已结算过的敌人，防止同一目标反复掉血
var _root_time := 0.0 # 命中定身秒数（双刺 U：无法移动但可以攻击）
var _split_left := 0 # 命中后还要分裂出去的第二把数量（双刺 U）
var _style := "qi" # 视觉：qi=朱砂剑气弧 / dagger=短匕


## dir: 1 朝右 -1 朝左；damage 已含局内强化/契合加成；sfx 命中音效名（空则不播）；pierce 命中不毁；
## root 命中定身秒数；split 命中后分裂数量；style 视觉风格
func setup(p_dir: int, p_speed: float, p_range: float, p_damage: int, p_sfx := "", p_pierce := false,
		p_root := 0.0, p_split := 0, p_style := "qi") -> void:
	_dir = p_dir
	_speed = p_speed
	_range = p_range
	_damage = p_damage
	_sfx = p_sfx
	_pierce = p_pierce
	_root_time = p_root
	_split_left = p_split
	_style = p_style


func _ready() -> void:
	scale.x = _dir # 剑气弧朝飞行方向
	if _sfx != "":
		_sfx_stream = load("res://audio/sfx/" + _sfx + ".wav")
		_sfx_player = AudioStreamPlayer.new()
		add_child(_sfx_player)
	queue_redraw()


func _draw() -> void:
	if _style == "dagger":
		_draw_dagger()
		return
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


## 短匕：刃身朝前 + 朱砂护手 + 墨色缠柄，后方一缕红线拖尾（双刺 U 投掷）
func _draw_dagger() -> void:
	draw_colored_polygon(PackedVector2Array([
		Vector2(4, -4), Vector2(34, 0), Vector2(4, 4),
	]), QI)
	draw_line(Vector2(2, -10), Vector2(2, 10), RED, 3.0) # 护手
	draw_line(Vector2(-18, 0), Vector2(2, 0), INK, 4.5) # 缠柄
	draw_circle(Vector2(-18, 0), 2.5, Color(0.85, 0.75, 0.62))
	draw_line(Vector2(-6, -12), Vector2(-40, -6), Color(RED, 0.45), 2.0) # 拖尾
	draw_line(Vector2(-6, 12), Vector2(-36, 7), Color(INK, 0.35), 1.5)


func _physics_process(delta: float) -> void:
	var step := _speed * delta
	position.x += _dir * step
	_travel += step
	# 命中判定：横向贴近剑气、纵向与敌人脚底同一平面（剑气在胸口高度飞）
	for e in get_tree().get_nodes_in_group("enemies"):
		var p := e as Node2D
		if p == null:
			continue
		if int(e.get("hp")) <= 0: # 尸体不吃投射物，与近战判定一致
			continue
		if _hit_list.has(e.get_instance_id()): # 穿透模式下已结算过的目标直接掠过
			continue
		# 命中窗口 = 剑气自身 30px + 目标受击半径：大体型 Boss 边缘就能截住剑气
		var r = e.get("body_radius")
		var br := float(r) if r != null else 30.0
		if absf(p.global_position.x - global_position.x) <= 30.0 + br and absf(p.global_position.y - global_position.y) <= 80.0:
			p.call("take_damage", _damage, global_position.x)
			Score.add_hit()
			# 定身：命中时敌人还在（没被这一下打死）才挂，避免对着尸体定身
			if _root_time > 0.0 and int(e.get("hp")) > 0 and e.has_method("root"):
				e.call("root", _root_time)
			Feel.hitstop(0.04)
			Feel.shake(3.0, 0.1)
			# 分裂（双刺 U）：第一把钉进敌人，第二把从命中点继续飞，忽略刚命中的目标防重复掉血
			if _split_left > 0:
				_split_left -= 1
				var child = get_script().new()
				child.setup(_dir, _speed, _range, _damage, _sfx, _pierce, _root_time, _split_left, _style)
				child._hit_list = _hit_list.duplicate()
				child._hit_list.append(e.get_instance_id())
				child.global_position = global_position + Vector2(_dir * 34.0, 0.0)
				get_tree().current_scene.add_child(child)
				queue_free()
				return
			if _pierce: # 穿云：记下这个目标继续飞，命中音照播
				_hit_list.append(e.get_instance_id())
				if _sfx_stream != null and not _sfx_player.playing:
					_sfx_player.stream = _sfx_stream
					_sfx_player.play()
				continue
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
