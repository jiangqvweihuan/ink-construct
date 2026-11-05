extends CanvasLayer

const InkTex = preload("res://scripts/ui/ink_tex.gd")
const BattleStatus = preload("res://scripts/ui/battle_status.gd")
const SFX_CLICK := preload("res://audio/sfx/click.wav")
const SFX_BACK := preload("res://audio/sfx/ui_back.wav")

## 暂停菜单：Esc 继续，左侧导航，右侧查看全部战斗状态、被动与强化。

const INK := Color(0.05, 0.05, 0.05)
const PAPER := Color(0.949, 0.918, 0.847)
const DIM := Color(0.72, 0.69, 0.62)
const RED := Color(0.78, 0.30, 0.24)
const GOLD := Color(0.91, 0.75, 0.34)

var _settings: Control = null
var _close_button: Button = null
var _resuming := false


func _ready() -> void:
	layer = 10
	process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().paused = true
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	var win := TextureRect.new()
	win.texture = InkTex.load("res://art/ui/menu/window_large.png")
	win.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	win.stretch_mode = TextureRect.STRETCH_SCALE
	win.size = Vector2(880, 580)
	win.position = Vector2(200, 70)
	win.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(win)
	_text("暂  停", Vector2(240, 102), Vector2(240, 54), 34, PAPER, self)
	_close_button = Button.new()
	_close_button.text = "×"
	_close_button.position = Vector2(1000, 88)
	_close_button.size = Vector2(42, 42)
	_close_button.flat = true
	_close_button.add_theme_font_size_override("font_size", 32)
	_close_button.add_theme_color_override("font_color", PAPER)
	_close_button.add_theme_color_override("font_hover_color", RED)
	_close_button.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	_close_button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_close_button.pressed.connect(_resume)
	add_child(_close_button)
	_text("战斗状态与被动", Vector2(500, 142), Vector2(500, 34), 23, PAPER, self)
	_text("增益 / 减益 / 化身被动 / 夺取 / 局内强化", Vector2(500, 174), Vector2(500, 24), 14, DIM, self)
	_make_button("继续战斗", 260, _resume, null)
	_make_button("设    置", 342, _open_settings)
	_make_button("回主菜单", 424, _to_menu)
	_text("Esc 返回战斗", Vector2(240, 510), Vector2(220, 28), 15, DIM, self)
	_build_status_details()


func _text(text: String, pos: Vector2, dimensions: Vector2, font_size: int, color: Color, parent: Node) -> Label:
	var l := Label.new()
	l.text = text
	l.position = pos
	l.size = dimensions
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.add_theme_color_override("font_color", color)
	l.add_theme_font_size_override("font_size", font_size)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(l)
	return l


func _make_button(text: String, y: float, cb: Callable, sfx: AudioStream = SFX_CLICK) -> void:
	var b := TextureButton.new()
	b.texture_normal = InkTex.load("res://art/ui/menu/btn_normal.png")
	b.texture_pressed = InkTex.load("res://art/ui/menu/btn_clicked.png")
	b.ignore_texture_size = true
	b.stretch_mode = TextureButton.STRETCH_SCALE
	b.size = Vector2(220, 56)
	b.position = Vector2(250, y)
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	var l := _text(text, Vector2.ZERO, b.size, 22, INK, b)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.pressed.connect(func():
		if sfx != null:
			_play_sfx(sfx)
		cb.call())
	add_child(b)


func _build_status_details() -> void:
	var scroll := ScrollContainer.new()
	scroll.position = Vector2(500, 208)
	scroll.size = Vector2(530, 366)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	scroll.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(scroll)
	var content := Control.new()
	content.custom_minimum_size = Vector2(510, 0)
	content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	scroll.add_child(content)
	var player = get_tree().get_first_node_in_group("player")
	var list: Array = BattleStatus.entries(player)
	var y := 0.0
	if list.is_empty():
		_text("当前没有战斗状态", Vector2(10, 10), Vector2(480, 50), 18, DIM, content)
		content.custom_minimum_size.y = 70
		return
	for entry in list:
		var desc := str(entry.get("desc", ""))
		var panel := Panel.new()
		panel.position = Vector2(0, y)
		panel.size = Vector2(510, 0)
		panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(0.055, 0.05, 0.044, 0.52)
		sb.set_border_width_all(1)
		sb.border_color = Color(PAPER, 0.12)
		sb.set_corner_radius_all(5)
		panel.add_theme_stylebox_override("panel", sb)
		content.add_child(panel)
		var kind_names := {"buff": "增益", "debuff": "减益", "passive": "被动", "stolen": "夺取", "upgrade": "强化"}
		var kind := str(entry.get("kind", "passive"))
		var accent := GOLD if kind == "buff" else (RED if kind == "debuff" or not bool(entry.get("active", true)) else Color(0.46, 0.62, 0.66))
		var accent_bar := ColorRect.new()
		accent_bar.color = Color(accent, 0.85)
		accent_bar.position = Vector2(0, 10)
		accent_bar.size = Vector2(3, 16)
		accent_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		panel.add_child(accent_bar)
		var heading := "%s  ·  %s" % [kind_names.get(kind, "状态"), str(entry.get("name", ""))]
		var value := str(entry.get("value", ""))
		if value != "":
			heading += "    " + value
		var heading_color := GOLD if kind == "buff" else (RED if kind == "debuff" or not bool(entry.get("active", true)) else PAPER)
		_text(heading, Vector2(12, 8), Vector2(486, 26), 17, heading_color, panel).horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		var desc_label := _text(desc, Vector2(12, 38), Vector2(486, 21), 15, DIM, panel)
		desc_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		desc_label.vertical_alignment = VERTICAL_ALIGNMENT_TOP
		desc_label.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
		desc_label.get_minimum_size() # 先刷新单行文本留下的最小宽度缓存
		desc_label.size = Vector2(486, 21)
		var desc_height := maxf(21.0, desc_label.get_minimum_size().y)
		desc_label.size.y = desc_height
		panel.size.y = 56.0 + desc_height
		y += panel.size.y + 8.0
	content.custom_minimum_size.y = y


func _input(event: InputEvent) -> void:
	if _resuming or not event.is_action_pressed("ui_cancel"):
		return
	if is_instance_valid(_settings):
		return # 最内层设置面板自己消费 Esc；这里不能同时恢复战斗。
	get_viewport().set_input_as_handled()
	_resume()


func _open_settings() -> void:
	if is_instance_valid(_settings):
		return
	_settings = load("res://scenes/ui/settings_panel.tscn").instantiate()
	add_child(_settings)
	_close_button.hide()
	_settings.closed.connect(func():
		_settings = null
		if is_instance_valid(_close_button):
			_close_button.show())


func _play_sfx(stream: AudioStream) -> void:
	var s := AudioStreamPlayer.new()
	s.bus = "SFX"
	s.process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().root.add_child(s)
	s.stream = stream
	s.play()
	s.finished.connect(s.queue_free, CONNECT_ONE_SHOT)


func _resume() -> void:
	if _resuming:
		return
	_play_sfx(SFX_BACK)
	_resuming = true
	get_tree().paused = false
	queue_free()


func _to_menu() -> void:
	get_tree().paused = false
	get_tree().change_scene_to_file("res://scenes/ui/main_menu.tscn")
