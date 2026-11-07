extends Control

const InkTex = preload("res://scripts/ui/ink_tex.gd")
const UiKit = preload("res://scripts/ui/ui_kit.gd")
const Settings = preload("res://scripts/ui/settings.gd")
const MOBILE_GUIDE = preload("res://scripts/ui/mobile_guide.gd")
const SFX_CLICK := preload("res://audio/sfx/click.wav")
const SFX_BACK := preload("res://audio/sfx/ui_back.wav")

signal closed

## 设置面板：音频 / 画面 / 操作三页。所有修改先写入草稿，叉号或 Esc 关闭时统一应用。

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
	"skill_sweep", "skill_ult", "skill_i", "skill_o", "skill_p",
]

var _sfx: AudioStreamPlayer
var _content: Control
var _tabs := {}
var _cur_tab := ""
var _capturing := ""
var _key_btns := {}
var _hint: Label
var _hint_tw: Tween
var _draft: Dictionary = {}
var _closing := false


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
	process_mode = Node.PROCESS_MODE_ALWAYS
	Settings.apply_all()
	_draft = Settings.snapshot()
	_sfx = AudioStreamPlayer.new()
	_sfx.bus = "SFX"
	_sfx.stream = SFX_CLICK
	add_child(_sfx)

	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.35)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	UiKit.fit_control(self, [dim])
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
	add_child(_close_button(Vector2(WIN_POS.x + WIN_SIZE.x - 70, 80)))

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
	var apply_hint := Label.new()
	apply_hint.text = "关闭设置时应用全部更改"
	apply_hint.position = Vector2(350, 566)
	apply_hint.size = Vector2(580, 22)
	apply_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	apply_hint.add_theme_color_override("font_color", DIM)
	apply_hint.add_theme_font_size_override("font_size", 15)
	apply_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(apply_hint)
	_switch_tab("音频")


func _close_button(pos: Vector2) -> Button:
	var b := Button.new()
	b.text = "×"
	b.position = pos
	b.size = Vector2(42, 42)
	b.flat = true
	b.add_theme_font_size_override("font_size", 32)
	b.add_theme_color_override("font_color", PAPER)
	b.add_theme_color_override("font_hover_color", Color(1.0, 0.55, 0.45))
	b.add_theme_color_override("font_pressed_color", Color(1.0, 0.55, 0.45))
	b.add_theme_color_override("font_focus_color", PAPER)
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	b.tooltip_text = "关闭并应用设置"
	b.pressed.connect(_close)
	return b


func _close() -> void:
	if _closing:
		return
	_closing = true
	_capturing = ""
	Settings.apply_snapshot(_draft)
	var s := AudioStreamPlayer.new()
	s.bus = "SFX"
	s.process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().root.add_child(s)
	s.stream = SFX_BACK
	s.play()
	s.finished.connect(s.queue_free, CONNECT_ONE_SHOT)
	closed.emit()
	hide()
	await get_tree().create_timer(0.15).timeout
	queue_free()


func _on_reset() -> void:
	_draft = Settings.default_snapshot()
	_sfx.play()
	_switch_tab(_cur_tab)


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
	_key_btns.clear()
	match tab:
		"音频": _build_audio()
		"画面": _build_video()
		"操作": _build_keys()


# ---------- 音频页 ----------

func _build_audio() -> void:
	_slider_row("主音量", 215, float(_draft["master"]), func(v: float): _draft["master"] = v)
	_slider_row("背景音乐", 290, float(_draft["music"]), func(v: float): _draft["music"] = v)
	_slider_row("音效音量", 365, float(_draft["sfx"]), func(v: float): _draft["sfx"] = v)


func _slider_row(text: String, y: float, initial: float, cb: Callable) -> void:
	_row_label(text, 330, y)
	var pct := _pct_label(Vector2(800, y))
	var s := InkSlider.new()
	s.position = Vector2(480, y)
	s.value = initial
	s.value_changed.connect(func(v: float):
		cb.call(v)
		pct.text = "%d%%" % int(round(v * 100.0)))
	_content.add_child(s)
	pct.text = "%d%%" % int(round(initial * 100.0))


# ---------- 画面页 ----------

func _build_video() -> void:
	var touch := OS.has_feature("mobile")
	var y := 205.0
	# 显示模式 / 窗口分辨率 / 垂直同步只对桌面窗口有意义，触屏版整组不显示
	if not touch:
		_row_label("显示模式", 330, y)
		var mode := OptionButton.new()
		for t in ["窗口化", "无边框窗口", "全屏"]:
			mode.add_item(str(t))
		mode.selected = int(_draft["display_mode"])
		mode.item_selected.connect(func(i):
			_draft["display_mode"] = i
			_sfx.play())
		_place(mode, Vector2(480, y - 4))
		y += 48.0

		_row_label("窗口分辨率", 330, y)
		var res := OptionButton.new()
		for r in Settings.RESOLUTIONS:
			res.add_item("%d × %d" % [r.x, r.y])
		for i in Settings.RESOLUTIONS.size():
			if Settings.RESOLUTIONS[i] == _draft["resolution"]:
				res.selected = i
				break
		res.item_selected.connect(func(i):
			_draft["resolution"] = Settings.RESOLUTIONS[i]
			_sfx.play())
		_place(res, Vector2(480, y - 4))
		y += 48.0

	_row_label("帧率限制", 330, y)
	var fps := OptionButton.new()
	for t in FPS_TEXTS:
		fps.add_item(str(t))
	fps.selected = maxi(FPS_VALUES.find(int(_draft["fps_limit"])), 0)
	fps.item_selected.connect(func(i):
		_draft["fps_limit"] = FPS_VALUES[i]
		_sfx.play())
	_place(fps, Vector2(480, y - 4))
	y += 48.0

	if not touch:
		_row_label("垂直同步", 330, y)
		_content.add_child(_seal(Vector2(480, y), bool(_draft["vsync"]), func(on): _draft["vsync"] = on))
		y += 48.0

	_row_label("画面亮度", 330, y)
	var pct := _pct_label(Vector2(800, y))
	pct.text = "%d%%" % int(round(float(_draft["brightness"]) * 100.0))
	var s := InkSlider.new()
	s.position = Vector2(480, y)
	s.value = clampf(float(_draft["brightness"]) - 0.5, 0.0, 1.0)
	s.value_changed.connect(func(v: float):
		var b := 0.5 + v
		_draft["brightness"] = b
		pct.text = "%d%%" % int(round(b * 100.0)))
	_content.add_child(s)
	y += 48.0

	_row_label("伤害数字", 330, y)
	var dmg := OptionButton.new()
	for t in ["关闭", "仅重击（3 点以上）", "全部显示"]:
		dmg.add_item(str(t))
	dmg.selected = clampi(int(_draft["damage_numbers"]), 0, 2)
	dmg.item_selected.connect(func(i):
		_draft["damage_numbers"] = i
		_sfx.play())
	_place(dmg, Vector2(480, y - 4))


# ---------- 操作页 ----------

func _build_keys() -> void:
	# 触屏版没有键盘：这一页改成手势说明，与首次进入战斗的教程卡共用同一份文案
	if OS.has_feature("mobile") or TouchControls.active:
		_build_touch_keys()
		return
	for i in KEY_ORDER.size():
		var action: String = KEY_ORDER[i]
		var col := floori(i / 6.0)
		var row := i % 6
		var y := 190.0 + row * 52.0
		_row_label(Settings.ACTION_NAMES[action], 330 + col * 310, y)
		var b := _ink_button(_draft_label(action), Vector2(480 + col * 310, y), Vector2(120, 36), _start_capture.bind(action))
		b.add_theme_font_size_override("font_size", 20)
		_content.add_child(b)
		_key_btns[action] = b
	_row_label("屏幕震动", 330, 500)
	_content.add_child(_seal(Vector2(480, 500), bool(_draft["screen_shake"]), func(on): _draft["screen_shake"] = on))
	_hint = Label.new()
	_hint.position = Vector2(WIN_POS.x, 546)
	_hint.size = Vector2(WIN_SIZE.x, 24)
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint.add_theme_color_override("font_color", Color(0.9, 0.35, 0.28))
	_hint.add_theme_font_size_override("font_size", 18)
	_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hint.visible = false
	_content.add_child(_hint)


## 手机操作页：左手走位 / 右手出手，逐条列清手势
func _build_touch_keys() -> void:
	UiKit.label(_content, "触屏操作", Vector2(320, 186), Vector2(400, 30), 22, RED,
		HORIZONTAL_ALIGNMENT_LEFT, false)
	var y := 228.0
	for row in MOBILE_GUIDE.ROWS:
		UiKit.label(_content, str(row[0]), Vector2(320, y), Vector2(300, 28), 20, PAPER,
			HORIZONTAL_ALIGNMENT_LEFT, false)
		UiKit.label(_content, str(row[1]), Vector2(632, y), Vector2(340, 28), 18, DIM,
			HORIZONTAL_ALIGNMENT_LEFT, false)
		y += 40.0
	_row_label("屏幕震动", 320, 512)
	_content.add_child(_seal(Vector2(640, 510), bool(_draft["screen_shake"]), func(on): _draft["screen_shake"] = on))


func _draft_code(action: String) -> int:
	return int((_draft["binds"] as Dictionary).get(action, Settings.DEFAULT_BINDS[action]))


func _draft_label(action: String) -> String:
	return Settings.key_label(_draft_code(action))


func _draft_action_for_key(code: int) -> String:
	for action in Settings.DEFAULT_BINDS:
		if _draft_code(action) == code:
			return action
	return ""


func _start_capture(action: String) -> void:
	_cancel_capture()
	_capturing = action
	_key_btns[action].text = "按下新按键…"


func _cancel_capture() -> void:
	if _capturing != "" and _key_btns.has(_capturing):
		_key_btns[_capturing].text = _draft_label(_capturing)
	_capturing = ""


func _input(event: InputEvent) -> void:
	if _closing or not (event is InputEventKey):
		return
	var key := event as InputEventKey
	if not key.pressed or key.echo:
		return
	var code: int = key.physical_keycode if key.physical_keycode != KEY_NONE else key.keycode
	if code == KEY_ESCAPE:
		get_viewport().set_input_as_handled()
		if _capturing != "":
			_cancel_capture()
		else:
			_close()
		return
	if _capturing == "":
		return
	get_viewport().set_input_as_handled()
	var other := _draft_action_for_key(code)
	if other != "" and other != _capturing:
		_show_hint("「%s」已被 %s 占用，换一个键" % [Settings.key_label(code), Settings.ACTION_NAMES.get(other, other)])
		_cancel_capture()
		return
	var action := _capturing
	if code == int(Settings.DEFAULT_BINDS[action]):
		(_draft["binds"] as Dictionary).erase(action)
	else:
		_draft["binds"][action] = code
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
