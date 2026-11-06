extends Node2D

## 关卡互动物件：卷轴（回血）/ 香炉（强化重随）/ 石碑（本房临时 buff）。
## 本体用贴图 + 脚下呼吸光圈；玩家走近自动触发：
## 金色爆开特效 + 飘字提示 + 音效，随后消散。每房由 room_01 随机摆放 2-3 个。

const DAMAGE_NUMBER := preload("res://scripts/ui/damage_number.gd")
const FX := preload("res://scripts/systems/fx.gd")
const SFX_PICKUP := preload("res://audio/sfx/loot_pickup.wav") # 卷轴/香炉触发
const SFX_STELE := preload("res://audio/sfx/decor_stele.wav") # 石碑触发

const PROP_SCROLL := preload("res://art/environment/props/decor_scroll.png")
const PROP_CENSER := preload("res://art/environment/props/decor_censer.png")
const PROP_STELE := preload("res://art/environment/props/decor_stele.png")

## 素材自带透明留白（石碑尤其多）：按内容区域裁切，贴地时底部才对齐地面线。
## height 是游戏内目标高度，宽度按原比例自动得出。
const PROPS := {
	"scroll": {"tex": PROP_SCROLL, "trim": Rect2(0, 0, 110, 119), "height": 56.0, "tip": -88.0, "burst": -30.0, "fire": 0.0},
	"censer": {"tex": PROP_CENSER, "trim": Rect2(0, 0, 75, 61), "height": 50.0, "tip": -76.0, "burst": -26.0, "fire": -45.0},
	"stele": {"tex": PROP_STELE, "trim": Rect2(28, 16, 78, 105), "height": 86.0, "tip": -112.0, "burst": -48.0, "fire": 0.0},
}

const TRIGGER_RANGE := 90.0 # 走近触发半径

const RED := Color(0.66, 0.2, 0.16) # 朱砂
const GOLD := Color(0.85, 0.68, 0.3) # 提示金

var kind := "scroll" # scroll / censer / stele
var _t := 0.0 # 待机呼吸计时
var _fired := false
var _player: Node2D
var _sprite: Sprite2D


func setup(p_kind: String) -> void:
	kind = p_kind


func _ready() -> void:
	z_index = 2 # 压过地面石板带，又被角色（默认 z 更高）自然遮挡
	_build_sprite()
	# 香炉待机：炉口一缕白焰循环（素材库逐帧拼条，fx.gd 注册）
	if kind == "censer":
		FX.spawn(self, "decor_idle_fire", Vector2(0, float(PROPS[kind]["fire"])), {"scale": 0.4, "loop": true, "z": 1})


## 贴图按内容裁切后等比缩放到目标高度，底部中心对齐地面
func _build_sprite() -> void:
	var cfg: Dictionary = PROPS[kind]
	var atlas := AtlasTexture.new()
	atlas.atlas = cfg["tex"]
	atlas.region = cfg["trim"]
	atlas.filter_clip = false
	var h := float(cfg["height"])
	var s := h / float(atlas.get_height())
	_sprite = Sprite2D.new()
	_sprite.texture = atlas
	_sprite.scale = Vector2(s, s)
	_sprite.position = Vector2(0, -h * 0.5)
	add_child(_sprite)


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
	var burst_y := float(PROPS[kind]["burst"])
	Achievements.event("decor_pickups")
	Achievements.event("decor_" + kind)
	match kind:
		"scroll": # 残卷：回血 +1，统一走玩家恢复入口以保留不朽与合法超额生命
			_player._restore_hp(1)
			_play_sfx(SFX_PICKUP)
			FX.spawn(get_tree().current_scene, "decor_burst", global_position + Vector2(0, burst_y), {"scale": 0.55})
		"censer": # 香炉：本局额外强化重随 +1
			Run.supply_upgrade_rerolls += 1
			_spawn_tip("强化重随 +1", GOLD)
			_play_sfx(SFX_PICKUP)
			FX.spawn(get_tree().current_scene, "decor_burst", global_position + Vector2(0, burst_y), {"scale": 0.55})
		"stele": # 石碑：本房临时 buff（伤害 / 疾行二选一）
			if randi() % 2 == 0:
				_player.damage_bonus += 2 # 本房锋锐：换房间 set_upgrades 重算自动失效
				_spawn_tip("锋锐加身 · 本房", RED)
			else:
				_player.run_speed *= 1.25 # 本房疾风：同上自动失效
				_spawn_tip("疾风加身 · 本房", Color(0.5, 0.72, 0.85))
			_play_sfx(SFX_STELE)
			# 石碑爆开偏青蓝，与金色调的卷轴/香炉区分开
			FX.spawn(get_tree().current_scene, "decor_burst", global_position + Vector2(0, burst_y), {"scale": 0.6, "mod": Color(0.6, 0.8, 1.0)})
	queue_free() # 特效与飘字都挂在场景根上，本体直接消散


func _spawn_tip(text: String, color: Color) -> void:
	var dn := DAMAGE_NUMBER.new()
	dn.setup(text, color)
	dn.global_position = global_position + Vector2(-20, float(PROPS[kind]["tip"]))
	var root := get_tree().current_scene
	if root == null:
		dn.queue_free()
		return
	root.add_child(dn)


func _play_sfx(stream: AudioStream) -> void:
	# 挂场景根：本体 queue_free 后音效照常播完
	var root := get_tree().current_scene
	if root == null:
		return
	var s := AudioStreamPlayer.new()
	s.bus = "SFX"
	root.add_child(s)
	s.stream = stream
	s.play()
	s.finished.connect(s.queue_free, CONNECT_ONE_SHOT)


func _draw() -> void:
	# 待机呼吸光晕：物件脚下一圈淡墨，明暗随呼吸起伏（本体是贴图，只画这一层光）
	var glow := 0.1 + 0.06 * sin(_t * 2.2)
	draw_circle(Vector2(0, -24), 40.0, Color(0.85, 0.75, 0.45, glow))
