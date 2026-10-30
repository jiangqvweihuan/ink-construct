extends Control

const InkTex = preload("res://scripts/ui/ink_tex.gd")
const Settings = preload("res://scripts/ui/settings.gd")
const SFX_CLICK := preload("res://audio/sfx/click.wav")

## 设置面板 v2：页签（音频 / 画面 / 操作），主菜单和暂停菜单共用。
## 音频：主音量 / 背景音乐 / 音效音量 三条滑条（全部真实生效）。
## 画面：显示模式（窗口化/无边框/全屏）/ 分辨率 / 帧率限制 / 垂直同步 / 亮度。
## 操作：12 个动作改键（点按钮后按新键，Esc 取消，冲突拒绝）+ 屏幕震动开关。
## 所有改动经 Settings 立即生效并写盘（user://settings.cfg）；「恢复默认」一键还原。

const INK := Color(0.05, 0.05, 0.05)
const PAPER := Color(0.949, 0.918, 0.847)
const RED := Color(0.66, 0.2, 0.16)
const DIM := Color(0.62, 0.60, 0.56)

const WIN_POS := Vector2(250, 60)
const WIN_SIZE := Vector2(780, 580)
const FPS_VALUES := [0, 30, 60, 120]
const FPS_TEXTS := ["不限制", "30 帧", "60 帧", "120 帧"]
const KEY_ORDER := [
	"move_left", "move_right", "jump", "dash", "attack", "skill",
	"skill_sweep", "skill_ult", "skill_i", "skill_o", "skill_p", "swap_skull",
]

var _sfx: AudioStreamPlayer
var _content: Control
var _tabs := {} # 名称 -> {btn, line}
var _cur_tab := ""
var _capturing := "" # 正在录入新键的动作
var _key_btns := {} # action -> 键位按钮
var _hint: Label
var _hint_tw: Tween


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

	_sfx = AudioStreamPlayer.new()
	_sfx.stream = SFX_CLICK
	add_child(_sfx)

	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.35)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(dim)

	var win := TextureRect.new()
	win.texture = InkTex.load("res://art/ui/menu/window_large.png")
	win.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	win.stretch_mode = TextureRect.STRETCH_SCALE
	win.size = WIN_SIZE
	win.position = WIN_POS
	win.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(win)

	var title := Label.new()
	title.text = "设  置"
	title.size = Vector2(WIN_SIZE.x, 50)
	title.position = Vector2(WIN_POS.x, 82)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_color_override("font_color", PAPER)
	title.add_theme_font_size_override("font_size", 30)
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(title)

	# 右上角「闭」字印章关闭钮
	var close := _seal(Vector2(WIN_POS.x + WIN_SIZE.x - 70, 80), true, func(_on): _close())
	add_child(close)

	# 页签
	var tabs := ["音频", "画面", "操作"]
	for i in tabs.size():
		var x := 435.0 + i * 150.0
		var b := Button.new()
		b.text = tabs[i]
		b.flat = true
		b.position = Vector2(x, 130)
		b.size = Vector2(110, 36)
		b.add_theme_font_size_override("font_size", 24)
		b.add_theme_color_override("font_color", DIM)
		b.add_theme_color_override("font_hover_color", PAPER)
		b.add_theme_color_override("font_pressed_color", PAPER)
		b.add_theme_color_override("font_focus_color", PAPER)
		b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
		b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		b.pressed.connect(_switch_tab.bind(tabs[i]))
		add_child(b)
		var line := ColorRect.new()
		line.color = Color(RED.r, RED.g, RED.b, 0.9)
		line.position = Vector2(x, 170)
		line.size = Vector2(110, 3)
		line.mouse_filter = Control.MOUSE_FILTER_IGNORE
		line.visible = false
		add_child(line)
		_tabs[tabs[i]] = {"btn": b, "line": line}

	_content = Control.new()
	_content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_content.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_content)

	add_child(_ink_button("恢复默认设置", Vector2(530, 592), Vector2(220, 36), _on_reset))

	_switch_tab("音频")


func _close() -> void:
	_capturing = ""
	_sfx.play()
	hide()
	await get_tree().create_timer(0.15).timeout # 给点击音留个尾巴
	queue_free()


func _on_reset() -> void:
	Settings.reset_all()
	_sfx.play()
	_switch_tab(_cur_tab) # 全部控件按默认值重建


# ---------- 页签 ----------

func _switch_tab(tab: String) -> void:
	if not _tabs.has(tab):
		return
	_cancel_capture()
	_cur_tab = tab
	for t in _tabs:
		_tabs[t]["btn"].add_theme_color_override("font_color", PAPER if t == tab else DIM)
		_tabs[t]["line"].visible = t == tab
	for c in _content.get_children():
		_content.remove_child(c)
		c.queue_free()
	match tab:
		"音频":
			_build_audio()
		"画面":
			_build_video()
		"操作":
			_build_keys()


# ---------- 音频页 ----------

func _build_audio() -> void:
	_slider_row("主音量", 215, Settings.master_volume, func(v: float):
		Settings.set_master(v)
		return v)
	_slider_row("背景音乐", 290, Settings.music_volume, func(v: float):
		Settings.set_music(v)
		return v)
	_slider_row("音效音量", 365, Settings.sfx_volume, func(v: float):
		Settings.set_sfx(v)
		return v)


## 一条滑条行：标签 + 墨条滑块 + 右端百分比。cb 把 0~1 值交给 Settings，返回要显示的线性值
func _slider_row(text: String, y: float, initial: float, cb: Callable) -> void:
	_row_label(text, 330, y)
	var pct := _pct_label(Vector2(800, y))
	var s := InkSlider.new()
	s.position = Vector2(480, y)
	s.value = initial
	s.value_changed.connect(func(v: float):
		var shown: float = cb.call(v)
		pct.text = "%d%%" % int(round(shown * 100.0)))
	_content.add_child(s)
	pct.text = "%d%%" % int(round(initial * 100.0))


# ---------- 画面页 ----------

func _build_video() -> void:
	var y := 205.0
	_row_label("显示模式", 330, y)
	var mode := OptionButton.new()
	for t in ["窗口化", "无边框窗口", "全屏"]:
		mode.add_item(str(t))
	mode.selected = Settings.display_mode
	mode.item_selected.connect(func(i):
		Settings.set_display_mode(i)
		_sfx.play())
	_place(mode, Vector2(480, y - 4))

	y = 253.0
	_row_label("窗口分辨率", 330, y)
	var res := OptionButton.new()
	for r in Settings.RESOLUTIONS:
		res.add_item("%d × %d" % [r.x, r.y])
	for i in Settings.RESOLUTIONS.size():
		if Settings.RESOLUTIONS[i] == Settings.resolution:
			res.selected = i
			break
	res.item_selected.connect(func(i):
		Settings.set_resolution(Settings.RESOLUTIONS[i])
		_sfx.play())
	_place(res, Vector2(480, y - 4))

	y = 301.0
	_row_label("帧率限制", 330, y)
	var fps := OptionButton.new()
	for t in FPS_TEXTS:
		fps.add_item(str(t))
	var fi := FPS_VALUES.find(Settings.fps_limit)
	fps.selected = maxi(fi, 0)
	fps.item_selected.connect(func(i):
		Settings.set_fps(FPS_VALUES[i])
		_sfx.play())
	_place(fps, Vector2(480, y - 4))

	y = 349.0
	_row_label("垂直同步", 330, y)
	_content.add_child(_seal(Vector2(480, y), Settings.vsync, func(on): Settings.set_vsync(on)))

	y = 397.0
	_row_label("画面亮度", 330, y)
	var pct := _pct_label(Vector2(800, y))
	pct.text = "%d%%" % int(round(Settings.brightness * 100.0))
	var s := InkSlider.new()
	s.position = Vector2(480, y)
	s.value = clampf(Settings.brightness - 0.5, 0.0, 1.0) # 0.5~1.5 映射进 0~1
	s.value_changed.connect(func(v: float):
		var b := 0.5 + v
		Settings.set_brightness(b)
		pct.text = "%d%%" % int(round(b * 100.0)))
	_content.add_child(s)


# ---------- 操作页 ----------

func _build_keys() -> void:
	for i in KEY_ORDER.size():
		var action: String = KEY_ORDER[i]
		var col := floori(i / 6.0) # 0 左列 / 1 右列
		var row := i % 6
		var y := 190.0 + row * 52.0
		_row_label(Settings.ACTION_NAMES[action], 330 + col * 310, y)
		var b := _ink_button(Settings.action_label(action), Vector2(480 + col * 310, y), Vector2(120, 36), _start_capture.bind(action))
		b.add_theme_font_size_override("font_size", 20)
		_content.add_child(b)
		_key_btns[action] = b

	_row_label("屏幕震动", 330, 500)
	_content.add_child(_seal(Vector2(480, 500), Settings.screen_shake, func(on): Settings.set_screen_shake(on)))

	_hint = Label.new()
	_hint.position = Vector2(WIN_POS.x, 546)
	_hint.size = Vector2(WIN_SIZE.x, 24)
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint.add_theme_color_override("font_color", Color(0.9, 0.35, 0.28))
	_hint.add_theme_font_size_override("font_size", 18)
	_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hint.visible = false
	_content.add_child(_hint)


## 开始录入：目标按钮变提示文案，下一个按键在 _input 里接
func _start_capture(action: String) -> void:
	_cancel_capture()
	_capturing = action
	_key_btns[action].text = "按下新按键…"


func _cancel_capture() -> void:
	if _capturing != "" and _key_btns.has(_capturing):
		_key_btns[_capturing].text = Settings.action_label(_capturing)
	_capturing = ""


func _input(event: InputEvent) -> void:
	if _capturing == "" or not (event is InputEventKey):
		return
	var key := event as InputEventKey
	if not key.pressed or key.echo:
		return
	get_viewport().set_input_as_handled() # 录入中的按键不许漏给别的系统（含 Esc 关面板）
	var code: int = key.physical_keycode if key.physical_keycode != KEY_NONE else key.keycode
	if event.keycode == KEY_ESCAPE or code == KEY_ESCAPE:
		_cancel_capture() # Esc 永远保留给「返回/取消」
		return
	var other := Settings.action_for_key(code)
	if other != "" and other != _capturing:
		_show_hint("「%s」已被 %s 占用，换一个键" % [Settings.key_label(code), Settings.ACTION_NAMES.get(other, other)])
		_cancel_capture()
		return
	Settings.rebind(_capturing, code)
	_cancel_capture()


func _show_hint(text: String) -> void:
	if not is_instance_valid(_hint):
		return
	_hint.text = text
	_hint.visible = true
	if _hint_tw != null and _hint_tw.is_valid():
		_hint_tw.kill()
	_hint_tw = create_tween()
	_hint_tw.tween_interval(2.0)
	_hint_tw.tween_callback(func(): _hint.visible = false)


# ---------- 通用小控件 ----------

func _row_label(text: String, x: float, y: float) -> void:
	var l := Label.new()
	l.text = text
	l.position = Vector2(x, y)
	l.size = Vector2(140, 30)
	l.add_theme_color_override("font_color", PAPER)
	l.add_theme_font_size_override("font_size", 22)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_content.add_child(l)


func _pct_label(pos: Vector2) -> Label:
	var l := Label.new()
	l.position = pos
	l.size = Vector2(70, 26)
	l.add_theme_color_override("font_color", DIM)
	l.add_theme_font_size_override("font_size", 20)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_content.add_child(l)
	return l


func _place(c: Control, pos: Vector2) -> void:
	c.position = pos
	_content.add_child(c)


## 印章式勾选钮：选中红「启」/ 未选灰「闭」，方框描边跟着变色
func _seal(pos: Vector2, initial: bool, cb: Callable) -> Button:
	var b := Button.new()
	b.text = "启" if initial else "闭"
	b.position = pos
	b.size = Vector2(36, 36)
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_seal_style(b, initial)
	b.pressed.connect(func():
		var on := b.text == "闭"
		b.text = "启" if on else "闭"
		_seal_style(b, on)
		_sfx.play()
		cb.call(on))
	return b


func _seal_style(b: Button, on: bool) -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0, 0, 0, 0.25)
	sb.set_border_width_all(2)
	sb.border_color = Color(RED.r, RED.g, RED.b, 0.9) if on else Color(0.5, 0.5, 0.5, 0.6)
	sb.set_corner_radius_all(4)
	for st in ["normal", "hover", "pressed"]:
		b.add_theme_stylebox_override(st, sb)
	var fc := Color(0.85, 0.3, 0.24) if on else DIM
	b.add_theme_color_override("font_color", fc)
	b.add_theme_color_override("font_hover_color", fc)
	b.add_theme_color_override("font_pressed_color", fc)
	b.add_theme_color_override("font_focus_color", fc)
	b.add_theme_font_size_override("font_size", 18)


func _ink_button(text: String, pos: Vector2, bsize: Vector2, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.position = pos
	b.size = bsize
	b.add_theme_color_override("font_color", PAPER)
	b.add_theme_color_override("font_hover_color", Color(1.06, 1.06, 1.06))
	b.add_theme_color_override("font_pressed_color", PAPER)
	b.add_theme_color_override("font_focus_color", PAPER)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.03, 0.03, 0.03, 0.55)
	sb.set_border_width_all(1)
	sb.border_color = Color(1, 1, 1, 0.25)
	sb.set_corner_radius_all(4)
	var sb_hover: StyleBoxFlat = sb.duplicate()
	sb_hover.bg_color = Color(0.03, 0.03, 0.03, 0.75)
	sb_hover.border_color = Color(RED.r, RED.g, RED.b, 0.8)
	b.add_theme_stylebox_override("normal", sb)
	b.add_theme_stylebox_override("hover", sb_hover)
	b.add_theme_stylebox_override("pressed", sb_hover)
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	b.pressed.connect(cb)
	return b
