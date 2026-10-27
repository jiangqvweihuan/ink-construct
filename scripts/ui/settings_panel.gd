extends Control

const InkTex = preload("res://scripts/ui/ink_tex.gd")
const Settings = preload("res://scripts/ui/settings.gd")
const SFX_CLICK := preload("res://audio/sfx/click.wav")

## 设置面板：音量滑条（音乐/音效总线）+ 全屏开关 + 窗口分辨率。主菜单和暂停菜单共用。
## 所有改动经 Settings 立即生效并写盘（user://settings.cfg）。

const INK := Color(0.05, 0.05, 0.05)
const PAPER := Color(0.949, 0.918, 0.847)


class InkSlider:
	extends Control

	const InkTex = preload("res://scripts/ui/ink_tex.gd")

	signal value_changed(v: float)

	var value := 1.0
	var _thumb: TextureRect

	func _init() -> void:
		custom_minimum_size = Vector2(300, 26)
		size = custom_minimum_size

	func _ready() -> void:
		var bar := TextureRect.new()
		bar.texture = InkTex.load("res://art/ui/menu/slider_bar.png")
		bar.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		bar.stretch_mode = TextureRect.STRETCH_SCALE
		bar.size = Vector2(size.x, 14)
		bar.position = Vector2(0, 6)
		bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(bar)
		_thumb = TextureRect.new()
		_thumb.texture = InkTex.load("res://art/ui/menu/slider_thumb.png")
		_thumb.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		_thumb.stretch_mode = TextureRect.STRETCH_SCALE
		_thumb.size = Vector2(26, 26)
		_thumb.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(_thumb)
		_update_thumb()

	func _update_thumb() -> void:
		_thumb.position = Vector2(value * (size.x - 26), 0)

	func _gui_input(event: InputEvent) -> void:
		var pressed := false
		var x := 0.0
		if event is InputEventMouseButton and event.pressed:
			pressed = true
			x = event.position.x
		elif event is InputEventMouseMotion and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
			pressed = true
			x = event.position.x
		if pressed:
			value = clampf(x / size.x, 0.0, 1.0)
			_update_thumb()
			value_changed.emit(value)


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS # 暂停菜单里也能用
	Settings.apply_all() # 兜底：确保总线存在、初始值已加载

	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.35)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(dim)

	var win := TextureRect.new()
	win.texture = InkTex.load("res://art/ui/menu/window_large.png")
	win.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	win.stretch_mode = TextureRect.STRETCH_SCALE
	win.size = Vector2(620, 460)
	win.position = Vector2(330, 130)
	win.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(win)

	var title := Label.new()
	title.text = "设  置"
	title.size = Vector2(620, 50)
	title.position = Vector2(330, 152)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_color_override("font_color", PAPER)
	title.add_theme_font_size_override("font_size", 30)
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(title)

	var close := TextureButton.new()
	close.texture_normal = InkTex.load("res://art/ui/menu/x_button.png")
	close.ignore_texture_size = true
	close.stretch_mode = TextureButton.STRETCH_SCALE
	close.size = Vector2(40, 40)
	close.position = Vector2(920, 150)
	close.pressed.connect(func():
		var s := AudioStreamPlayer.new()
		add_child(s)
		s.stream = SFX_CLICK
		s.play()
		queue_free())
	add_child(close)

	_make_slider("音乐音量", "Music", Vector2(480, 300))
	_make_slider("音效音量", "SFX", Vector2(480, 370))
	_make_fullscreen_tick(Vector2(480, 440))
	_make_resolution_option(Vector2(480, 510))


func _make_slider(label_text: String, bus_name: String, pos: Vector2) -> void:
	var l := Label.new()
	l.text = label_text
	l.position = pos + Vector2(-110, 0)
	l.add_theme_color_override("font_color", PAPER)
	l.add_theme_font_size_override("font_size", 22)
	add_child(l)

	var slider := InkSlider.new()
	slider.position = pos
	slider.value = Settings.music_volume if bus_name == "Music" else Settings.sfx_volume
	if bus_name == "Music":
		slider.value_changed.connect(Settings.set_music)
	else:
		slider.value_changed.connect(Settings.set_sfx)
	add_child(slider)


func _make_fullscreen_tick(pos: Vector2) -> void:
	var l := Label.new()
	l.text = "全屏显示"
	l.position = pos + Vector2(-110, 0)
	l.add_theme_color_override("font_color", PAPER)
	l.add_theme_font_size_override("font_size", 22)
	add_child(l)

	var tick := TextureButton.new()
	var tex_empty = InkTex.load("res://art/ui/menu/tick_empty.png")
	var tex_ticked = InkTex.load("res://art/ui/menu/tick_ticked.png")
	tick.texture_normal = tex_empty
	tick.ignore_texture_size = true
	tick.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_CENTERED
	tick.size = Vector2(32, 32)
	tick.position = pos
	var is_full := Settings.fullscreen
	tick.texture_normal = tex_ticked if is_full else tex_empty
	tick.pressed.connect(func():
		# 以按下时的真实窗口状态为准，避免 lambda 捕获变量失效
		var now_full := DisplayServer.window_get_mode() != DisplayServer.WINDOW_MODE_FULLSCREEN
		Settings.set_fullscreen(now_full)
		tick.texture_normal = tex_ticked if now_full else tex_empty
		var s := AudioStreamPlayer.new()
		add_child(s)
		s.stream = SFX_CLICK
		s.play())
	add_child(tick)


const RESOLUTIONS: Array[Vector2i] = [Vector2i(1280, 720), Vector2i(1600, 900), Vector2i(1920, 1080)]


func _make_resolution_option(pos: Vector2) -> void:
	var l := Label.new()
	l.text = "窗口分辨率"
	l.position = pos + Vector2(-110, 0)
	l.add_theme_color_override("font_color", PAPER)
	l.add_theme_font_size_override("font_size", 22)
	add_child(l)

	var opt := OptionButton.new()
	opt.position = pos + Vector2(0, -4)
	opt.custom_minimum_size = Vector2(220, 34)
	for r in RESOLUTIONS:
		opt.add_item("%d × %d" % [r.x, r.y])
	# 选中当前设置的分辨率
	for i in RESOLUTIONS.size():
		if RESOLUTIONS[i] == Settings.resolution:
			opt.selected = i
			break
	opt.item_selected.connect(func(i):
		Settings.set_resolution(RESOLUTIONS[i])
		var s := AudioStreamPlayer.new()
		add_child(s)
		s.stream = SFX_CLICK
		s.play())
	add_child(opt)
