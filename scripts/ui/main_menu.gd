extends Control

const InkTex = preload("res://scripts/ui/ink_tex.gd")
const Settings = preload("res://scripts/ui/settings.gd")
const SFX_CLICK := preload("res://audio/sfx/click.wav")

## 主菜单：水墨远山底 + 标题 + 开始/设置/退出

const INK := Color(0.05, 0.05, 0.05)

var _start_panel: Node # 开始面板单例引用：连点「开始游戏」不叠加


func _ready() -> void:
	Settings.apply_all() # 启动时应用持久化设置（音量/全屏/分辨率）
	BGM.play_bgm("menu") # 主菜单 BGM（御风引）

	var bg := TextureRect.new()
	bg.texture = InkTex.load("res://art/environment/background/bg_mountains.jpg")
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	var title := Label.new()
	title.text = "墨  构"
	title.add_theme_font_size_override("font_size", 120)
	title.add_theme_color_override("font_color", INK)
	title.size = Vector2(1280, 160)
	title.position = Vector2(0, 100)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(title)

	var sub := Label.new()
	sub.text = "InkConstruct"
	sub.add_theme_font_size_override("font_size", 28)
	sub.add_theme_color_override("font_color", Color(0.42, 0.42, 0.42))
	sub.size = Vector2(1280, 40)
	sub.position = Vector2(0, 262)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(sub)

	_make_button("开始游戏", 380, _open_start)
	_make_button("化 身 谱", 465, _open_codex) # 局外养成一览：解锁进度 / 契合等级 / 加成
	_make_button("设    置", 550, _open_settings)
	_make_button("退    出", 635, func(): get_tree().quit())


func _make_button(text: String, y: float, cb: Callable) -> void:
	var b := TextureButton.new()
	b.texture_normal = InkTex.load("res://art/ui/menu/btn_normal.png")
	b.texture_pressed = InkTex.load("res://art/ui/menu/btn_clicked.png")
	b.ignore_texture_size = true
	b.stretch_mode = TextureButton.STRETCH_SCALE
	b.size = Vector2(260, 64)
	b.position = Vector2(510, y)
	var l := Label.new()
	l.text = text
	l.size = b.size
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.add_theme_color_override("font_color", INK)
	l.add_theme_font_size_override("font_size", 26)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(l)
	b.pressed.connect(func():
		var s := AudioStreamPlayer.new()
		add_child(s)
		s.stream = SFX_CLICK
		s.play()
		cb.call())
	add_child(b)


func _open_settings() -> void:
	add_child(load("res://scenes/ui/settings_panel.tscn").instantiate())


## 开始游戏：先弹「模式 → 选角」两步面板，由面板负责 Run.start 与切场景。
## 面板已经开着就忽略，避免连点叠出两块
func _open_start() -> void:
	if is_instance_valid(_start_panel):
		return
	_start_panel = load("res://scenes/ui/start_panel.tscn").instantiate()
	add_child(_start_panel)


func _open_codex() -> void:
	add_child(load("res://scenes/ui/forms_panel.tscn").instantiate())
