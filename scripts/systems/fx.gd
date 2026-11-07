extends Node2D

## 特效播放器：GIF 转出的精灵条（art/fx/*.png）逐帧播放，一次性播完自动销毁。
## 用法：FX.spawn(parent, "ink_hit", pos, {"scale": 0.5, "flip": true})
## 元数据直接写死在 LIB（帧数/帧率/锚点），导出包不依赖外部 JSON。

const LIB := {
	"ink_hit": {"tex": "res://art/fx/ink_hit.png", "frames": 24, "fps": 14.0, "pivot": "center"}, # 水墨受击：小怪/玩家通用
	"ink_claw": {"tex": "res://art/fx/ink_claw.png", "frames": 12, "fps": 14.0, "pivot": "center"}, # 水墨爪痕：Boss/重击
	"slash": {"tex": "res://art/fx/slash.png", "frames": 12, "fps": 14.0, "pivot": "center"}, # 朱砂斩击：玩家命中
	"pillar": {"tex": "res://art/fx/pillar.png", "frames": 16, "fps": 14.0, "pivot": "bottom"}, # 光柱：化身变身
	"tiger": {"tex": "res://art/fx/tiger.png", "frames": 20, "fps": 14.0, "pivot": "bottom"}, # 虎首地裂：墨霆登场/变身
	"fire_pillar": {"tex": "res://art/fx/fire_pillar.png", "frames": 11, "fps": 14.0, "pivot": "bottom"}, # 火柱：焚鼎火区
	"speedline": {"tex": "res://art/fx/speedline.png", "frames": 5, "fps": 14.0, "pivot": "center"}, # 水墨速度线：冲锋拖尾
	"crack": {"tex": "res://art/fx/crack.png", "frames": 35, "fps": 14.0, "pivot": "bottom"}, # 地裂爆炸：撞墙
	"telegraph": {"tex": "res://art/fx/telegraph.png", "frames": 12, "fps": 14.0, "pivot": "bottom"}, # 预警墨环：程序化生成，出手/火区预警
	"vanish": {"tex": "res://art/fx/vanish.png", "frames": 9, "fps": 14.0, "pivot": "bottom"}, # 墨散：小怪尸体消散
	"fire_hit": {"tex": "res://art/fx/fire_hit.png", "frames": 10, "fps": 14.0, "pivot": "center"}, # 火焰受击：焚鼎命中
	"decor_burst": {"tex": "res://art/fx/decor_burst.png", "frames": 20, "fps": 18.0, "pivot": "center"}, # 金色爆开：互动物件触发
	"decor_idle_fire": {"tex": "res://art/fx/decor_idle_fire.png", "frames": 8, "fps": 10.0, "pivot": "bottom"}, # 白焰循环：香炉待机（loop 使用）
}

static var _self_script: GDScript

var _sprite: Sprite2D
var _fps := 14.0
var _loop := false
var _t := 0.0


static func spawn(parent: Node, fx_name: String, pos: Vector2, opts: Dictionary = {}) -> Node2D:
	if parent == null or not is_instance_valid(parent):
		return null
	var meta: Dictionary = LIB.get(fx_name, {})
	if meta.is_empty():
		push_warning("FX: 未登记特效 " + fx_name)
		return null
	if _self_script == null:
		_self_script = load("res://scripts/systems/fx.gd")
	var tex: Texture2D = load(str(meta["tex"]))
	if tex == null:
		return null
	var f: Node2D = _self_script.new()
	f._fps = float(meta["fps"])
	f._loop = bool(opts.get("loop", false))
	var frames := int(meta["frames"])
	var s := Sprite2D.new()
	s.texture = tex
	s.hframes = frames
	# 锚点：底部锚定的特效（火柱/地裂/光柱）贴地长出，中心锚定的在打击点炸开
	if str(meta["pivot"]) == "bottom":
		var h := float(tex.get_height())
		s.offset = Vector2(0, -h * 0.5)
	f.add_child(s)
	f._sprite = s
	f.global_position = pos
	var sc := float(opts.get("scale", 1.0))
	if bool(opts.get("flip", false)):
		sc = -sc
	f.scale = Vector2(sc, absf(sc))
	f.z_index = int(opts.get("z", 20))
	f.modulate = opts.get("mod", Color.WHITE)
	parent.add_child(f)
	return f


## 立即终止播放并把渲染实例摘出场景树：停掉逐帧更新、隐藏精灵、解除父节点关联、进销毁队列。
## 用于所有者同帧清场（武车撞边致死），不等动画自然播完，避免残影卡在墙边。
func stop_and_free() -> void:
	set_process(false)
	_t = 0.0
	visible = false
	if _sprite != null and is_instance_valid(_sprite):
		_sprite.visible = false
		_sprite.frame = 0
		_sprite.texture = null # 断开贴图引用，渲染实例不再持有资源
	var p := get_parent()
	if p != null:
		p.remove_child(self)
	queue_free()


func _process(delta: float) -> void:
	_t += delta
	var frame := int(_t * _fps)
	if frame >= _sprite.hframes:
		if _loop:
			_t = 0.0
			frame = 0
		else:
			queue_free()
			return
	_sprite.frame = frame
