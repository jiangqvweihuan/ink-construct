extends Control

## 启动后的第一屏：择途。
## 电脑端三项：单人游戏 / 本机多人联机 / 局域网联机；
## 手机端只保留单人游戏与局域网联机（本地双人需要两套键盘，暂不开放）。
## 局域网联机：进入局域网大厅，房主开房 / 客机自动扫描或手动输入 IP 加入。

const InkTex = preload("res://scripts/ui/ink_tex.gd")
const Settings = preload("res://scripts/ui/settings.gd")
const LocalCoop = preload("res://scripts/systems/local_coop.gd")
const SFX_CLICK := preload("res://audio/sfx/click.wav")
const SFX_START_OPEN := preload("res://audio/sfx/ui_start_open.wav")
const SFX_SHOP_OPEN := preload("res://audio/sfx/shop_open.wav")
const TITLE_FONT := preload("res://art/ui/fonts/slidefu_regular.ttf")

const PAPER := Color(0.949, 0.918, 0.847)
const INK := Color(0.05, 0.05, 0.05)
const RED := Color(0.66, 0.2, 0.16)
const DIM := Color(0.82, 0.79, 0.72)

const CARD_W := 300.0
const CARD_H := 300.0
const CARD_GAP := 44.0
const CARD_Y := 272.0

var _sfx: AudioStreamPlayer
var _start_panel: Node = null
var _lan: Node = null
var _busy := false


func _ready() -> void:
	Settings.apply_all()
	BGM.play_bgm("menu")
	_sfx = AudioStreamPlayer.new()
	_sfx.bus = "SFX"
	_sfx.stream = SFX_CLICK
	add_child(_sfx)
	_build()


func _is_mobile() -> bool:
	# 与触屏控制一致：Android 真机，或命令行 --touch-preview 预览手机版界面
	return OS.has_feature("mobile") or OS.get_cmdline_args().has("--touch-preview")


func _build() -> void:
	_make_backdrop()
	_make_title()
	var vw := get_viewport().get_visible_rect().size.x

	var entries: Array = [
		{
			"title": "单 人 游 戏",
			"desc": "一人一卷\n冒险 · 无尽",
			"foot": "循旧路，独自问道",
			"sfx": SFX_START_OPEN,
			"cb": _enter_single,
		},
	]
	if not _is_mobile():
		entries.append({
			"title": "本 机 双 人",
			"desc": "同屏共战\nP1 WASD · P2 方向键",
			"foot": "两柄键盘，并肩入卷",
			"sfx": SFX_START_OPEN,
			"cb": _open_coop,
		})
	entries.append({
		"title": "局 域 网 联 机",
		"desc": "隔屏同游\n组网对局",
		"foot": "隔屏同游 · 自动发现",
		"sfx": SFX_SHOP_OPEN,
		"cb": _open_lan,
	})

	var total := entries.size() * CARD_W + (entries.size() - 1) * CARD_GAP
	var x0 := (vw - total) * 0.5
	for i in entries.size():
		_make_card(entries[i], x0 + i * (CARD_W + CARD_GAP))

	var hint := "手机端：单人模式 · 局域网联机" if _is_mobile() \
		else "%s    |    %s" % [LocalCoop.HINTS[0], LocalCoop.HINTS[1]]
	_label(hint, Vector2(0, 618), Vector2(vw, 24), 13, DIM)


func _make_backdrop() -> void:
	var bg := TextureRect.new()
	bg.texture = InkTex.load("res://art/environment/background/bg_mountains.jpg")
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	_make_gradient(Color(0, 0, 0, 0.62), Color(0, 0, 0, 0.18), 0.0, 340.0)
	_make_gradient(Color(0, 0, 0, 0.18), Color(0, 0, 0, 0.72), 440.0, 280.0)


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
	r.size = Vector2(get_viewport().get_visible_rect().size.x, h)
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
	title.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.55))
	title.add_theme_constant_override("outline_size", 10)
	title.position = Vector2(116, 44)
	title.size = Vector2(600, 150)
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(title)

	var sub := Label.new()
	sub.text = "InkConstruct"
	sub.add_theme_font_size_override("font_size", 22)
	sub.add_theme_color_override("font_color", Color(0.92, 0.90, 0.86))
	sub.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.6))
	sub.add_theme_constant_override("outline_size", 6)
	sub.position = Vector2(122, 192)
	sub.size = Vector2(400, 30)
	sub.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(sub)

	var seal := ColorRect.new()
	seal.color = Color(RED.r, RED.g, RED.b, 0.85)
	seal.position = Vector2(122, 226)
	seal.size = Vector2(110, 3)
	seal.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(seal)

	var vw := get_viewport().get_visible_rect().size.x
	_label("择  途", Vector2(0, 196), Vector2(vw, 46), 36, PAPER)
	_label("此行向何处去", Vector2(0, 240), Vector2(vw, 22), 15, DIM)


func _make_card(info: Dictionary, x: float) -> void:
	var b := TextureButton.new()
	b.texture_normal = InkTex.load("res://art/ui/menu/btn_normal.png")
	b.texture_pressed = InkTex.load("res://art/ui/menu/btn_clicked.png")
	b.ignore_texture_size = true
	b.stretch_mode = TextureButton.STRETCH_SCALE
	b.position = Vector2(x, CARD_Y)
	b.size = Vector2(CARD_W, CARD_H)
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	add_child(b)

	_card_label(b, str(info["title"]), Vector2(0, 52), Vector2(CARD_W, 44), 30, PAPER)
	_card_label(b, str(info["desc"]), Vector2(10, 118), Vector2(CARD_W - 20, 82), 16, DIM)
	_card_label(b, str(info["foot"]), Vector2(10, 238), Vector2(CARD_W - 20, 30), 13, RED)

	b.mouse_entered.connect(func(): b.modulate = Color(1.12, 1.07, 0.9))
	b.mouse_exited.connect(func(): b.modulate = Color.WHITE)
	b.pressed.connect(func():
		if _busy:
			return
		_sfx.stream = info["sfx"]
		_sfx.play()
		(info["cb"] as Callable).call())


func _card_label(parent: Control, text: String, pos: Vector2, dimensions: Vector2, font_size: int, color: Color) -> void:
	_label(text, pos, dimensions, font_size, color, parent)


func _label(text: String, pos: Vector2, dimensions: Vector2, font_size: int, color: Color, parent: Control = null) -> Label:
	var l := Label.new()
	l.text = text
	l.position = pos
	l.size = dimensions
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.add_theme_color_override("font_color", color)
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.42))
	l.add_theme_constant_override("outline_size", 3)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	(parent if parent != null else self).add_child(l)
	return l


# ---------- 三个入口 ----------

func _enter_single() -> void:
	if _busy:
		return
	_busy = true
	await LoadVeil.transition_to("res://scenes/ui/main_menu.tscn", "正在展卷")
	_busy = false


## 本机双人：直接弹开局面板，选完模式/难度/化身即开战
func _open_coop() -> void:
	if is_instance_valid(_start_panel):
		return
	LocalCoop.ensure_input()
	_start_panel = load("res://scenes/ui/start_panel.tscn").instantiate()
	_start_panel.local_coop = true
	_start_panel.tree_exited.connect(func(): _start_panel = null)
	add_child(_start_panel)


## 局域网：进入局域网大厅（创建房间 / 自动扫描加入 / 手动 IP 加入）
func _open_lan() -> void:
	if is_instance_valid(_lan):
		return
	_lan = load("res://scenes/ui/lan_panel.tscn").instantiate()
	_lan.closed.connect(func():
		if is_instance_valid(_lan):
			_lan.queue_free()
			_lan = null)
	add_child(_lan)
