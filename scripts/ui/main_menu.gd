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

	_make_button("开始游戏", 330, _open_start)
	_make_button("化 身 谱", 402, _open_forms) # 局外养成一览：解锁进度 / 契合等级 / 加成
	_make_button("图    鉴", 474, _open_codex) # 收录：击败过的敌人 + 已解锁化身的背景/招式演示
	_make_button("设    置", 546, _open_settings)
	_make_button("退    出", 618, func(): get_tree().quit())

	_make_credits_entry()


## 致谢入口：左下角竖排两字小字（题跋落款的位置），不挤压中间五个主键
func _make_credits_entry() -> void:
	var l := Label.new()
	l.text = "致谢"
	l.position = Vector2(30, 442) # 压在远山剪影上会看不清，落在上方留白处
	l.size = Vector2(28, 84)
	l.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY # 宽度只容一个字，自然竖排
	l.add_theme_font_size_override("font_size", 24)
	l.add_theme_color_override("font_color", Color(0.66, 0.2, 0.16, 0.9)) # 朱砂：像一方落款印
	l.mouse_filter = Control.MOUSE_FILTER_STOP
	l.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	l.mouse_entered.connect(func(): l.add_theme_color_override("font_color", Color(0.05, 0.05, 0.05, 0.9)))
	l.mouse_exited.connect(func(): l.add_theme_color_override("font_color", Color(0.66, 0.2, 0.16, 0.9)))
	l.gui_input.connect(func(ev: InputEvent):
		if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
			_open_credits())
	add_child(l)


func _open_credits() -> void:
	add_child(load("res://scenes/ui/credits_panel.tscn").instantiate())


func _make_button(text: String, y: float, cb: Callable) -> void:
	var b := TextureButton.new()
	b.texture_normal = InkTex.load("res://art/ui/menu/btn_normal.png")
	b.texture_pressed = InkTex.load("res://art/ui/menu/btn_clicked.png")
	b.ignore_texture_size = true
	b.stretch_mode = TextureButton.STRETCH_SCALE
	b.size = Vector2(260, 56)
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


func _open_forms() -> void:
	add_child(load("res://scenes/ui/forms_panel.tscn").instantiate())


func _open_codex() -> void:
	add_child(load("res://scenes/ui/codex_panel.tscn").instantiate())
