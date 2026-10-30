extends Control

const InkTex = preload("res://scripts/ui/ink_tex.gd")
const Settings = preload("res://scripts/ui/settings.gd")
const SFX_CLICK := preload("res://audio/sfx/click.wav")
const BG_VIDEO := preload("res://art/ui/menu/bg_swordsman.ogv")
const TITLE_FONT := preload("res://art/ui/fonts/slidefu_regular.ttf") # 演示佛系体：主标题书法

## 主菜单：循环播放的水墨剑客剪影视频做底（无音轨，只出画面）。
## 构图（1280×720 基准）：上 0~380 黑树冠 → 标题白字压这里；380~500 亮天空；
## 左下 270~350 剑客剪影；555 以下整条纯黑地面 → 菜单条压这里，白字对比最稳。
## 压暗只做上下渐变，中间画面（天空与剑客）不动。

const INK := Color(0.05, 0.05, 0.05)
const PAPER := Color(0.949, 0.918, 0.847)
const RED := Color(0.66, 0.2, 0.16)

## 菜单条几何：6 项等宽等间距，整条居中
const ITEM_W := 164.0
const ITEM_GAP := 12.0
const ITEM_Y := 588.0
const ITEM_H := 72.0

var _start_panel: Node # 开始面板引用：连点「开始游戏」不叠加
var _sfx: AudioStreamPlayer # 点击音（常驻一个，不再每次新建）
var _hover_sfx: AudioStreamPlayer # 悬停轻响
var _items: Array = [] # 每项 {box, plate, label, line, base_y, cb}


func _ready() -> void:
	Settings.apply_all() # 启动时应用持久化设置（音量/全屏/分辨率）
	BGM.play_bgm("menu") # 主菜单 BGM（御风引）

	_sfx = AudioStreamPlayer.new()
	_sfx.stream = SFX_CLICK
	add_child(_sfx)

	_hover_sfx = AudioStreamPlayer.new()
	_hover_sfx.stream = SFX_CLICK
	_hover_sfx.volume_db = -10.0 # 悬停只给一声轻响，别跟点击同一音量
	add_child(_hover_sfx)

	_make_backdrop()
	_make_title()

	var items := [
		["开始游戏", _open_start],
		["化身谱", _open_forms], # 角色解锁与永久修炼
		["墨锭商栈", _open_shop], # 通用强化 / 重随 / 一次性补给
		["图鉴", _open_codex], # 收录：击败过的敌人 + 已解锁化身的人设与招式演示
		["设置", _open_settings],
		["致谢", _open_credits],
		["退出", func(): get_tree().quit()],
	]
	var total := items.size() * ITEM_W + (items.size() - 1) * ITEM_GAP
	var x0 := (1280.0 - total) * 0.5
	for i in items.size():
		_make_menu_item(str(items[i][0]), x0 + i * (ITEM_W + ITEM_GAP), items[i][1])


## 背景：静态远山兜底 + 视频铺满 + 上下渐变压暗
func _make_backdrop() -> void:
	# 兜底：视频解码失败时至少还有远山，不至于全黑
	var bg := TextureRect.new()
	bg.texture = InkTex.load("res://art/environment/background/bg_mountains.jpg")
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	var video := VideoStreamPlayer.new()
	video.stream = BG_VIDEO
	video.expand = true # 拉伸铺满控件（视频本身 16:9，窗口三档都是 16:9）
	video.loop = true
	video.autoplay = true
	video.set_anchors_preset(Control.PRESET_FULL_RECT)
	video.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(video)

	_make_gradient(Color(0, 0, 0, 0.55), Color(0, 0, 0, 0.0), 0.0, 300.0) # 顶部压暗衬标题
	_make_gradient(Color(0, 0, 0, 0.0), Color(0, 0, 0, 0.62), 470.0, 250.0) # 底部压暗托菜单条


## 竖向渐变条：用 GradientTexture2D 拉伸，不额外做美术资源
func _make_gradient(top: Color, bottom: Color, y: float, h: float) -> void:
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 1.0])
	g.colors = PackedColorArray([top, bottom])
	var t := GradientTexture2D.new()
	t.gradient = g
	t.width = 8
	t.height = 256
	t.fill_from = Vector2(0, 0)
	t.fill_to = Vector2(0, 1)
	var r := TextureRect.new()
	r.texture = t
	r.position = Vector2(0, y)
	r.size = Vector2(1280, h)
	r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	r.stretch_mode = TextureRect.STRETCH_SCALE
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(r)


func _make_title() -> void:
	var title := Label.new()
	title.text = "墨  构"
	title.add_theme_font_override("font", TITLE_FONT)
	title.add_theme_font_size_override("font_size", 96)
	title.add_theme_color_override("font_color", PAPER)
	title.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.55)) # 树叶细节碎，描一圈黑压住
	title.add_theme_constant_override("outline_size", 10)
	title.position = Vector2(116, 44)
	title.size = Vector2(600, 150)
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(title)

	var sub := Label.new()
	sub.text = "InkConstruct"
	sub.add_theme_font_size_override("font_size", 22)
	sub.add_theme_color_override("font_color", Color(0.92, 0.90, 0.86))
	sub.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.6)) # 细字压在树叶纹理上会糊，补描边
	sub.add_theme_constant_override("outline_size", 6)
	sub.position = Vector2(122, 192) # 书法字体 ascent 偏大，字形实际比 Label 框低约 18px
	sub.size = Vector2(400, 30)
	sub.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(sub)

	# 标题下的一道朱砂短线，把「墨构」和画面分隔开
	var seal := ColorRect.new()
	seal.color = Color(RED.r, RED.g, RED.b, 0.85)
	seal.position = Vector2(122, 226)
	seal.size = Vector2(110, 3)
	seal.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(seal)


## 菜单项：默认纸白字 + 短朱砂线；悬停上浮 4px、墨底淡入、字转纯白、朱砂线拉满，其余项压暗
func _make_menu_item(text: String, x: float, cb: Callable) -> void:
	var box := Control.new()
	box.position = Vector2(x, ITEM_Y)
	box.size = Vector2(ITEM_W, ITEM_H)
	box.mouse_filter = Control.MOUSE_FILTER_STOP
	box.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	add_child(box)

	var plate := ColorRect.new()
	plate.color = Color(0.03, 0.03, 0.03, 0.0)
	plate.size = box.size
	plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(plate)

	var l := Label.new()
	l.text = text
	l.size = box.size
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", 26)
	l.add_theme_color_override("font_color", PAPER)
	l.modulate = Color(1, 1, 1, 0.86)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(l)

	var line := ColorRect.new()
	line.color = Color(RED.r, RED.g, RED.b, 0.5)
	line.size = Vector2(40, 2)
	line.position = Vector2((ITEM_W - 40.0) * 0.5, ITEM_H - 10.0)
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(line)

	var idx := _items.size()
	_items.append({"box": box, "plate": plate, "label": l, "line": line, "base_y": ITEM_Y, "cb": cb})
	box.mouse_entered.connect(_on_hover.bind(idx, true))
	box.mouse_exited.connect(_on_hover.bind(idx, false))
	box.gui_input.connect(_on_click.bind(idx))


func _on_hover(idx: int, on: bool) -> void:
	var it: Dictionary = _items[idx]
	if on:
		_hover_sfx.play()
	var tw := create_tween().set_parallel(true)
	tw.tween_property(it["box"], "position:y", float(it["base_y"]) - (4.0 if on else 0.0), 0.12)
	tw.tween_property(it["plate"], "color:a", 0.14 if on else 0.0, 0.12)
	tw.tween_property(it["line"], "color:a", 1.0 if on else 0.5, 0.12)
	tw.tween_property(it["line"], "size:x", ITEM_W if on else 40.0, 0.12)
	tw.tween_property(it["line"], "position:x", 0.0 if on else (ITEM_W - 40.0) * 0.5, 0.12)
	# 悬停项提亮，其余项压暗做聚焦
	for i in _items.size():
		var lab: Label = _items[i]["label"]
		var dst := Color(1, 1, 1, 0.86)
		if i == idx:
			dst = Color(1.06, 1.06, 1.06, 1.0) if on else Color(1, 1, 1, 0.86)
		elif on:
			dst = Color(1, 1, 1, 0.45)
		tw.tween_property(lab, "modulate", dst, 0.12)


func _on_click(ev: InputEvent, idx: int) -> void:
	if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
		_sfx.play()
		var cb: Callable = _items[idx]["cb"]
		cb.call()


func _open_credits() -> void:
	add_child(load("res://scenes/ui/credits_panel.tscn").instantiate())


func _open_settings() -> void:
	add_child(load("res://scenes/ui/settings_panel.tscn").instantiate())


## 开始游戏：先弹「模式 → 选角」两步面板，由面板负责 Run.start 与切场景。
## 面板已经开着就忽略，避免连点叠出两块
func _open_start() -> void:
	if is_instance_valid(_start_panel):
		return
	_start_panel = load("res://scenes/ui/start_panel.tscn").instantiate()
	add_child(_start_panel)


func _open_forms() -> void:
	add_child(load("res://scenes/ui/forms_panel.tscn").instantiate())


func _open_shop() -> void:
	add_child(load("res://scenes/ui/shop_panel.tscn").instantiate())


func _open_codex() -> void:
	add_child(load("res://scenes/ui/codex_panel.tscn").instantiate())
