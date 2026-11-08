extends CanvasLayer

const InkTex = preload("res://scripts/ui/ink_tex.gd")
const UiKit = preload("res://scripts/ui/ui_kit.gd")
const BattleStatus = preload("res://scripts/ui/battle_status.gd")
const Skulls = preload("res://scripts/player/skulls.gd")
const SFX_CLICK := preload("res://audio/sfx/click.wav")
const SFX_BACK := preload("res://audio/sfx/ui_back.wav")

## 暂停菜单：Esc 继续，左侧导航，右侧查看全部战斗状态、被动与强化。

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
	UiKit.fit_layer(self, [dim])
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
	_make_button("继续战斗", 252, _resume, null)
	_make_button("设    置", 330, _open_settings)
	_make_button("回主菜单", 408, _to_menu)
	_make_button("退出游戏", 486, func(): QuitGuard.request_quit())
	_text("Esc 返回战斗" if not OS.has_feature("mobile") else "点「继续战斗」回到战斗",
		Vector2(230, 566), Vector2(260, 28), 15, DIM, self)
	_build_status_details()


func _text(text: String, pos: Vector2, dimensions: Vector2, font_size: int, color: Color, parent: Node) -> Label:
	return UiKit.label(parent, text, pos, dimensions, font_size, color, HORIZONTAL_ALIGNMENT_CENTER, false)


func _make_button(text: String, y: float, cb: Callable, sfx: AudioStream = SFX_CLICK) -> void:
	UiKit.texture_button(self, text, Vector2(250, y), Vector2(220, 56), 22, PAPER, func():
		if sfx != null:
			_play_sfx(sfx)
		cb.call())


func _build_status_details() -> void:
	var scroll := ScrollContainer.new()
	scroll.position = Vector2(500, 208)
	scroll.size = Vector2(530, 366)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	scroll.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(scroll)
	# 用容器排版代替手算高度：文字按可用宽度自动换行、面板随内容撑高，
	# 不会再出现长描述被下一张卡片盖住半行的情况。
	var content := VBoxContainer.new()
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", 8)
	content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	scroll.add_child(content)
	var players := _status_players()
	if players.is_empty():
		content.add_child(_empty_row())
		return
	for i in players.size():
		var p = players[i]
		var list: Array = BattleStatus.entries(p)
		# 本机双人时每名玩家各一段；强化 / 夺取是全队共用的，只在第一段列一次
		if players.size() > 1:
			content.add_child(_section_row(p, i))
			list = list.filter(func(e): return i == 0 or str(e.get("kind", "")) not in ["upgrade", "stolen"])
		if list.is_empty():
			content.add_child(_empty_row())
			continue
		for entry in list:
			if entry is Dictionary:
				content.add_child(_entry_row(entry))


## 暂停时能看到谁的状态：客机只看自己，主机只看 P1，其余（单人 / 本机双人）全看。
func _status_players() -> Array:
	var out: Array = []
	for n in get_tree().get_nodes_in_group("player"):
		if not is_instance_valid(n) or not n.has_method("has_battle_passive"):
			continue
		out.append(n)
	if Run.net_role == "client":
		out = out.filter(func(p): return int(p.get("input_slot")) == Run.net_slot)
	elif Run.net_role == "host":
		out = out.filter(func(p): return int(p.get("input_slot")) == 0)
	out.sort_custom(func(a, b): return int(a.get("input_slot")) < int(b.get("input_slot")))
	if out.is_empty():
		var one = get_tree().get_first_node_in_group("player")
		if one != null:
			out.append(one)
	return out


func _section_row(player, index: int) -> Control:
	var profile: Dictionary = Skulls.get_profile(str(player.get("skull_id")))
	var who := "P%d" % (int(player.get("input_slot")) + 1)
	var label := Label.new()
	label.text = "%s  ·  %s" % [who, str(profile.get("name", profile.get("label", "无名者")))]
	label.add_theme_font_size_override("font_size", 16)
	label.add_theme_color_override("font_color", GOLD)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label


func _empty_row() -> Control:
	var label := Label.new()
	label.text = "当前没有战斗状态"
	label.add_theme_font_size_override("font_size", 18)
	label.add_theme_color_override("font_color", DIM)
	label.custom_minimum_size = Vector2(0, 50)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label


## 一条状态：左侧色条 + 标题（名称 / 数值）+ 自动换行的描述，高度随文字撑开。
func _entry_row(entry: Dictionary) -> Control:
	var kind_names := {"buff": "增益", "debuff": "减益", "passive": "被动", "stolen": "夺取", "upgrade": "强化"}
	var kind := str(entry.get("kind", "passive"))
	var accent := GOLD if kind == "buff" else (RED if kind == "debuff" or not bool(entry.get("active", true)) else Color(0.46, 0.62, 0.66))

	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.055, 0.05, 0.044, 0.52)
	sb.set_border_width_all(1)
	sb.border_color = Color(PAPER, 0.12)
	sb.set_corner_radius_all(5)
	sb.content_margin_left = 12
	sb.content_margin_right = 12
	sb.content_margin_top = 8
	sb.content_margin_bottom = 9
	panel.add_theme_stylebox_override("panel", sb)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(row)

	var bar := ColorRect.new()
	bar.color = Color(accent, 0.85)
	bar.custom_minimum_size = Vector2(3, 0)
	bar.size_flags_vertical = Control.SIZE_EXPAND_FILL
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(bar)

	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", 4)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(col)

	var heading := "%s  ·  %s" % [kind_names.get(kind, "状态"), str(entry.get("name", ""))]
	var value := str(entry.get("value", ""))
	if value != "":
		heading += "    " + value
	var head := Label.new()
	head.text = heading
	head.add_theme_font_size_override("font_size", 17)
	head.add_theme_color_override("font_color",
		GOLD if kind == "buff" else (RED if kind == "debuff" or not bool(entry.get("active", true)) else PAPER))
	head.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(head)

	var desc := str(entry.get("desc", ""))
	if desc != "":
		var body := Label.new()
		body.text = desc
		body.add_theme_font_size_override("font_size", 15)
		body.add_theme_color_override("font_color", DIM)
		body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		body.mouse_filter = Control.MOUSE_FILTER_IGNORE
		col.add_child(body)
	return panel


func _input(event: InputEvent) -> void:
	if _resuming or not event.is_action_pressed("ui_cancel"):
		return
	if is_instance_valid(_settings):
		return # 最内层设置面板自己消费 Esc；这里不能同时恢复战斗。
	if QuitGuard.is_dialog_open():
		return # 退出确认框盖在最上面时，Esc 归它处理
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
	await LoadVeil.transition_to("res://scenes/ui/main_menu.tscn", "正在合卷")
