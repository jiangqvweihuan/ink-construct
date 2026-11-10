extends Control

## 「开始游戏」之后的择途层：单人游戏 / 本机双人 / 局域网联机。
## 电脑端三项；手机端只保留单人游戏与局域网联机（本地双人需要两套键盘，暂不开放）。
## 单人 / 本机双人继续进入行旅卷（start_panel），局域网进入大厅面板。

const InkTex = preload("res://scripts/ui/ink_tex.gd")
const LocalCoop = preload("res://scripts/systems/local_coop.gd")
const SFX_CLICK := preload("res://audio/sfx/click.wav")
const SFX_BACK := preload("res://audio/sfx/ui_back.wav")
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


func _ready() -> void:
	_sfx = AudioStreamPlayer.new()
	_sfx.bus = "SFX"
	_sfx.stream = SFX_CLICK
	add_child(_sfx)
	_build()


## Esc：子面板（行旅卷 / 局域网大厅）自行处理；否则收起择途层回主菜单。
func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed("ui_cancel"):
		return
	if _panel_open():
		return
	get_viewport().set_input_as_handled()
	_close()


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
			"cb": _enter_single,
		},
	]
	if not _is_mobile():
		entries.append({
			"title": "本 机 双 人",
			"desc": "同屏共战\n双人协作",
			"cb": _open_coop,
		})
		# 对战需要两套键位，只在电脑端开放
		entries.append({
			"title": "本 机 对 战",
			"desc": "同屏互搏\n一决胜负",
			"cb": _open_pvp_local,
		})
	entries.append({
		"title": "局 域 网 联 机",
		"desc": "隔屏同游\n组网对局",
		"cb": _open_lan,
	})

	# 四张卡时收窄卡宽，保证 1280 宽下仍能一行居中放下
	var card_w := CARD_W
	if entries.size() >= 4:
		card_w = (vw - 80.0 - float(entries.size() - 1) * 32.0) / float(entries.size())
	var gap := 32.0 if entries.size() >= 4 else CARD_GAP
	var total := entries.size() * card_w + (entries.size() - 1) * gap
	var x0 := (vw - total) * 0.5
	for i in entries.size():
		_make_card(entries[i], x0 + i * (card_w + gap), card_w)

	var back := TextureButton.new()
	back.texture_normal = InkTex.load("res://art/ui/menu/btn_normal.png")
	back.texture_pressed = InkTex.load("res://art/ui/menu/btn_clicked.png")
	back.ignore_texture_size = true
	back.stretch_mode = TextureButton.STRETCH_SCALE
	back.position = Vector2(vw - 190, 40)
	back.size = Vector2(150, 46)
	back.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	back.pressed.connect(_close)
	add_child(back)
	_card_label(back, "返  回", Vector2.ZERO, back.size, 20, PAPER)


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
	_label("择  途", Vector2(0, 200), Vector2(vw, 46), 36, PAPER)


func _make_card(info: Dictionary, x: float, card_w := CARD_W) -> void:
	var b := TextureButton.new()
	b.texture_normal = InkTex.load("res://art/ui/menu/btn_normal.png")
	b.texture_pressed = InkTex.load("res://art/ui/menu/btn_clicked.png")
	b.ignore_texture_size = true
	b.stretch_mode = TextureButton.STRETCH_SCALE
	b.position = Vector2(x, CARD_Y)
	b.size = Vector2(card_w, CARD_H)
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	add_child(b)

	_card_label(b, str(info["title"]), Vector2(0, 52), Vector2(card_w, 44), 28, PAPER)
	var seal := ColorRect.new()
	seal.color = Color(RED.r, RED.g, RED.b, 0.8)
	seal.position = Vector2(card_w * 0.5 - 30.0, 112)
	seal.size = Vector2(60, 2)
	seal.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(seal)
	_card_label(b, str(info["desc"]), Vector2(10, 132), Vector2(card_w - 20, 82), 16, DIM)

	b.mouse_entered.connect(func(): b.modulate = Color(1.12, 1.07, 0.9))
	b.mouse_exited.connect(func(): b.modulate = Color.WHITE)
	b.pressed.connect(func():
		# 选定任意一条路：立刻掐掉「开始游戏」的旁白，且不再重复触发，
		# 只留一声短点击做反馈；之后的整局都不会再听到这段旁白。
		BGM.stop_voice()
		_sfx.stream = SFX_CLICK
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

func _panel_open() -> bool:
	return is_instance_valid(_start_panel) or is_instance_valid(_lan)


## 单人：直接弹出行旅卷（择路 → 问境 → 化身），启程后再进关卡
func _enter_single() -> void:
	if _panel_open():
		return
	_start_panel = load("res://scenes/ui/start_panel.tscn").instantiate()
	_start_panel.local_coop = false
	_start_panel.tree_exited.connect(_on_start_panel_exited)
	add_child(_start_panel)


## 本机双人：同一张行旅卷，启程时把双人标记写进 Run
func _open_coop() -> void:
	if _panel_open():
		return
	LocalCoop.ensure_input()
	_start_panel = load("res://scenes/ui/start_panel.tscn").instantiate()
	_start_panel.local_coop = true
	_start_panel.tree_exited.connect(_on_start_panel_exited)
	add_child(_start_panel)


## 本机对战：同一张选角卷，两名玩家共用本机已解锁角色池
func _open_pvp_local() -> void:
	if _panel_open():
		return
	LocalCoop.ensure_input()
	_start_panel = load("res://scenes/ui/start_panel.tscn").instantiate()
	_start_panel.pvp_local = true
	_start_panel.tree_exited.connect(_on_start_panel_exited)
	add_child(_start_panel)


## 局域网：进入局域网大厅（创建房间 / 自动扫描加入 / 手动 IP 加入）
func _open_lan() -> void:
	if _panel_open():
		return
	_lan = load("res://scenes/ui/lan_panel.tscn").instantiate()
	_lan.closed.connect(func():
		if is_instance_valid(_lan):
			_lan.queue_free()
			_lan = null)
	add_child(_lan)


func _on_start_panel_exited() -> void:
	_start_panel = null


func _close() -> void:
	_play_sfx(SFX_BACK)
	queue_free()


func _play_sfx(stream: AudioStream) -> void:
	var s := AudioStreamPlayer.new()
	s.bus = "SFX"
	get_tree().root.add_child(s)
	s.stream = stream
	s.play()
	s.finished.connect(s.queue_free, CONNECT_ONE_SHOT)
