extends Node2D

## 关卡互动物件：卷轴（回血）/ 香炉（强化重随）/ 石碑（本房临时 buff）。
## 本体程序化水墨 _draw，玩家走近自动触发：
## 金色爆开特效 + 飘字提示 + 音效，随后消散。每房由 room_01 随机摆放 2-3 个。

const DAMAGE_NUMBER := preload("res://scripts/ui/damage_number.gd")
const FX := preload("res://scripts/systems/fx.gd")
const SFX_PICKUP := preload("res://audio/sfx/decor_pickup.wav") # 卷轴/香炉触发
const SFX_STELE := preload("res://audio/sfx/decor_stele.wav") # 石碑触发

const TRIGGER_RANGE := 90.0 # 走近触发半径

const INK := Color(0.1, 0.09, 0.11) # 深墨
const PAPER := Color(0.949, 0.918, 0.847) # 宣纸
const RED := Color(0.66, 0.2, 0.16) # 朱砂
const STONE := Color(0.38, 0.4, 0.42) # 石碑青灰
const GOLD := Color(0.85, 0.68, 0.3) # 提示金

var kind := "scroll" # scroll / censer / stele
var _t := 0.0 # 待机呼吸计时
var _fired := false
var _player: Node2D


func setup(p_kind: String) -> void:
	kind = p_kind


func _ready() -> void:
	z_index = 2 # 压过地面石板带，又被角色（默认 z 更高）自然遮挡
	# 香炉待机：炉口一缕白焰循环（素材库逐帧拼条，fx.gd 注册）
	if kind == "censer":
		FX.spawn(self, "decor_idle_fire", Vector2(0, -44), {"scale": 0.4, "loop": true, "z": 1})


func _process(delta: float) -> void:
	_t += delta
	queue_redraw() # 呼吸光晕每帧重画
	if _fired:
		return
	if _player == null or not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group("player") as Node2D
	if _player == null:
		return
	if _player.global_position.distance_to(global_position) <= TRIGGER_RANGE:
		_trigger()


func _trigger() -> void:
	_fired = true
	match kind:
		"scroll": # 残卷：回血 +1
			_player.hp = mini(int(_player.hp) + 1, int(_player.max_hp))
			_player.hp_changed.emit(_player.hp, _player.max_hp)
			_spawn_tip("+1 生命", Color(0.45, 0.75, 0.5))
			_play_sfx(SFX_PICKUP)
			FX.spawn(get_tree().current_scene, "decor_burst", global_position + Vector2(0, -40), {"scale": 0.55})
		"censer": # 香炉：本局额外强化重随 +1
			Run.supply_upgrade_rerolls += 1
			_spawn_tip("强化重随 +1", GOLD)
			_play_sfx(SFX_PICKUP)
			FX.spawn(get_tree().current_scene, "decor_burst", global_position + Vector2(0, -40), {"scale": 0.55})
		"stele": # 石碑：本房临时 buff（伤害 / 疾行二选一）
			if randi() % 2 == 0:
				_player.damage_bonus += 2 # 本房锋锐：换房间 set_upgrades 重算自动失效
				_spawn_tip("锋锐加身 · 本房", RED)
			else:
				_player.run_speed *= 1.25 # 本房疾风：同上自动失效
				_spawn_tip("疾风加身 · 本房", Color(0.5, 0.72, 0.85))
			_play_sfx(SFX_STELE)
			# 石碑爆开偏青蓝，与金色调的卷轴/香炉区分开
			FX.spawn(get_tree().current_scene, "decor_burst", global_position + Vector2(0, -40), {"scale": 0.6, "mod": Color(0.6, 0.8, 1.0)})
	queue_free() # 特效与飘字都挂在场景根上，本体直接消散


func _spawn_tip(text: String, color: Color) -> void:
	var dn := DAMAGE_NUMBER.new()
	dn.setup(text, color)
	dn.global_position = global_position + Vector2(-20, -90)
	get_tree().current_scene.add_child(dn)


func _play_sfx(stream: AudioStream) -> void:
	# 挂场景根：本体 queue_free 后音效照常播完
	var s := AudioStreamPlayer.new()
	get_tree().current_scene.add_child(s)
	s.stream = stream
	s.play()
	s.finished.connect(s.queue_free, CONNECT_ONE_SHOT)


func _draw() -> void:
	# 待机呼吸光晕：物件脚下一圈淡墨，明暗随呼吸起伏
	var glow := 0.1 + 0.06 * sin(_t * 2.2)
	draw_circle(Vector2(0, -24), 40.0, Color(0.85, 0.75, 0.45, glow))
	match kind:
		"scroll":
			_draw_scroll()
		"censer":
			_draw_censer()
		"stele":
			_draw_stele()


## 残卷：竖挂小卷，宣纸色卷面 + 上下深墨轴头 + 卷面一抹朱砂印
func _draw_scroll() -> void:
	draw_rect(Rect2(-14, -58, 28, 44), PAPER)
	draw_rect(Rect2(-14, -58, 28, 44), INK, false, 2.0)
	draw_circle(Vector2(0, -60), 5.0, INK) # 上轴头
	draw_circle(Vector2(0, -12), 5.0, INK) # 下轴头
	draw_circle(Vector2(4, -30), 4.0, Color(RED, 0.8)) # 朱砂闲章
	draw_line(Vector2(-7, -50), Vector2(7, -50), Color(INK, 0.5), 1.5) # 卷面墨字一两行
	draw_line(Vector2(-7, -44), Vector2(3, -44), Color(INK, 0.4), 1.5)


## 香炉：三足小炉，梯形炉身 + 双耳 + 三足（炉口白焰由 decor_idle_fire 循环特效负责）
func _draw_censer() -> void:
	var body := PackedVector2Array([Vector2(-18, -34), Vector2(18, -34), Vector2(13, -8), Vector2(-13, -8)])
	draw_colored_polygon(body, INK)
	draw_polyline(PackedVector2Array([Vector2(-18, -34), Vector2(18, -34), Vector2(13, -8), Vector2(-13, -8), Vector2(-18, -34)]), Color(0.3, 0.28, 0.3), 2.0)
	draw_rect(Rect2(-23, -40, 8, 7), INK) # 左耳
	draw_rect(Rect2(16, -40, 8, 7), INK) # 右耳
	for x in [-10.0, 0.0, 10.0]: # 三足
		draw_rect(Rect2(x - 2.5, -8, 5, 8), INK)
	draw_circle(Vector2(0, -22), 3.0, Color(RED, 0.7)) # 炉面朱砂点


## 石碑：圆顶碑身立在基座上，碑面几道墨纹刻字
func _draw_stele() -> void:
	draw_rect(Rect2(-16, -70, 32, 62), STONE)
	draw_circle(Vector2(0, -70), 16.0, STONE) # 圆顶
	draw_rect(Rect2(-16, -70, 32, 62), INK, false, 2.0)
	draw_arc(Vector2(0, -70), 16.0, PI, TAU, 12, INK, 2.0) # 圆顶描边
	draw_rect(Rect2(-22, -8, 32, 8), Color(0.3, 0.31, 0.33)) # 基座
	for i in 3: # 碑面墨纹刻字
		var y := -58.0 + i * 16.0
		draw_line(Vector2(-8, y), Vector2(8, y), Color(INK, 0.75), 2.5)
		draw_line(Vector2(-8, y + 6), Vector2(4, y + 6), Color(INK, 0.55), 2.0)
