extends CanvasLayer

## 局域网大厅：创建房间 / 自动扫描加入 / 手动 IP 加入 / 成员列表 / 就绪 / 开始 / 离开。
## 真正的连接与会话状态都在 LanNet（自动加载），本面板只负责展示与转发操作。

const InkTex = preload("res://scripts/ui/ink_tex.gd")
const UiKit = preload("res://scripts/ui/ui_kit.gd")
const Skulls = preload("res://scripts/player/skulls.gd")
const SFX_CLICK := preload("res://audio/sfx/click.wav")
const SFX_BACK := preload("res://audio/sfx/ui_back.wav")

const PAPER := Color(0.949, 0.918, 0.847)
const DIM := Color(0.72, 0.69, 0.63)
const RED := Color(0.66, 0.2, 0.16)
const GOLD := Color(0.9, 0.75, 0.3)

signal closed

const WIN_POS := Vector2(90, 50)
const WIN_SIZE := Vector2(1100, 620)

var _sfx: AudioStreamPlayer
var _body: Control
var _status: Label
var _room_list: VBoxContainer
var _name_edit: LineEdit
var _ip_edit: LineEdit
var _mode_opt: OptionButton
var _diff_opt: OptionButton
var _char_opt: OptionButton
var _lobby: Dictionary = {}
var _menu_view := true
var _scan_acc := 0.0
var _chars: Array = []
var _host_char := ""


func _ready() -> void:
	layer = 30
	process_mode = Node.PROCESS_MODE_ALWAYS
	_sfx = AudioStreamPlayer.new()
	_sfx.bus = "SFX"
	_sfx.stream = SFX_CLICK
	add_child(_sfx)
	_build_chrome()
	_connect_net()
	LanNet.begin_scan()
	_render()


func _exit_tree() -> void:
	if LanNet.role == "":
		LanNet.end_scan()


func _process(delta: float) -> void:
	if not _menu_view:
		return
	_scan_acc += delta
	if _scan_acc < 0.6:
		return
	_scan_acc = 0.0
	_refresh_rooms()


func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		if LanNet != null and LanNet.role == "":
			LanNet.end_scan()


# ---------------------------------------------------------------- 外框

func _build_chrome() -> void:
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.66)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(dim)
	UiKit.fit_layer(self, [dim])

	var win := TextureRect.new()
	win.texture = InkTex.load("res://art/ui/menu/window_large.png")
	win.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	win.stretch_mode = TextureRect.STRETCH_SCALE
	win.size = WIN_SIZE
	win.position = WIN_POS
	win.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(win)

	var backing := ColorRect.new()
	backing.color = Color(0.05, 0.045, 0.04, 0.45)
	backing.position = WIN_POS + Vector2(16, 16)
	backing.size = WIN_SIZE - Vector2(32, 32)
	backing.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(backing)

	_static_label("局 域 网 联 机", Vector2(WIN_POS.x, 70), Vector2(WIN_SIZE.x, 42), 34, PAPER)
	_static_label("同处一网，落笔共卷", Vector2(WIN_POS.x, 112), Vector2(WIN_SIZE.x, 24), 15, DIM)

	var close := TextureButton.new()
	close.texture_normal = InkTex.load("res://art/ui/menu/btn_normal.png")
	close.texture_pressed = InkTex.load("res://art/ui/menu/btn_clicked.png")
	close.ignore_texture_size = true
	close.stretch_mode = TextureButton.STRETCH_SCALE
	close.position = Vector2(WIN_POS.x + WIN_SIZE.x - 84, 66)
	close.size = Vector2(52, 44)
	close.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	close.pressed.connect(_close)
	add_child(close)
	_static_label("×", close.position, Vector2(52, 44), 28, PAPER)

	_body = Control.new()
	_body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_body.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_body)

	_status = _static_label("", Vector2(WIN_POS.x, WIN_POS.y + WIN_SIZE.y - 52), Vector2(WIN_SIZE.x, 24), 15, GOLD)


func _connect_net() -> void:
	LanNet.lobby_changed.connect(_on_lobby_changed)
	LanNet.joined.connect(_on_joined)
	LanNet.join_failed.connect(_on_join_failed)
	LanNet.session_started.connect(_on_session_started)
	LanNet.session_ended.connect(_on_session_ended)
	LanNet.net_notice.connect(_set_status)
	LanNet.link_lost.connect(_set_status)
	LanNet.link_restored.connect(func(): _set_status("已重连回房间"))
	LanNet.rooms_changed.connect(func(_rooms): _refresh_rooms())


# ---------------------------------------------------------------- 视图

func _render() -> void:
	for c in _body.get_children():
		_body.remove_child(c)
		c.queue_free()
	_lobby = {}
	_room_list = null
	_name_edit = null
	_ip_edit = null
	_mode_opt = null
	_diff_opt = null
	_char_opt = null
	if LanNet.role == "":
		_menu_view = true
		_build_menu()
	else:
		_menu_view = false
		_build_room()


func _build_menu() -> void:
	var left := 130.0
	var right := 660.0
	_text("创 建 房 间", Vector2(left, 156), Vector2(400, 30), 22, PAPER)
	_text("房 间 名", Vector2(left, 200), Vector2(110, 26), 15, DIM)
	_name_edit = _line_edit(Vector2(left, 226), Vector2(400, 40), "墨构 · 房主")
	_text("玩 法", Vector2(left, 280), Vector2(110, 26), 15, DIM)
	_mode_opt = _option(Vector2(left, 306), Vector2(400, 40), ["冒 险 模 式", "无 尽 模 式"], 0)
	_text("问 境", Vector2(left, 360), Vector2(110, 26), 15, DIM)
	var diffs: Array = []
	for d in Run.DIFFICULTIES:
		diffs.append(str(d.get("label", "问境")))
	_diff_opt = _option(Vector2(left, 386), Vector2(400, 40), diffs, 1)
	_text("化 身", Vector2(left, 440), Vector2(110, 26), 15, DIM)
	_chars = _unlocked_chars()
	var char_labels: Array = []
	for id in _chars:
		char_labels.append(_char_name(str(id)))
	_char_opt = _option(Vector2(left, 466), Vector2(400, 40), char_labels, 0)
	_button("创 建 房 间", Vector2(left, 528), Vector2(400, 48), _on_host)

	_text("加 入 房 间", Vector2(right, 156), Vector2(440, 30), 22, PAPER)
	_room_list = VBoxContainer.new()
	_room_list.position = Vector2(right, 200)
	_room_list.size = Vector2(440, 216)
	_room_list.add_theme_constant_override("separation", 8)
	_body.add_child(_room_list)
	_button("刷 新 列 表", Vector2(right, 428), Vector2(210, 40), _refresh_rooms)
	_button("自 动 加 入", Vector2(right + 230, 428), Vector2(210, 40), _on_auto_join)
	_text("或 手 动 输 入 主 机 IP", Vector2(right, 482), Vector2(440, 24), 14, DIM)
	_ip_edit = _line_edit(Vector2(right, 508), Vector2(280, 40), "192.168.1.10")
	_button("直 接 加 入", Vector2(right + 300, 508), Vector2(140, 40), _on_manual_join)
	_refresh_rooms()


func _build_room() -> void:
	var left := 150.0
	var title := str(LanNet.room.get("name", "局域网房间"))
	_text(title, Vector2(left, 156), Vector2(980, 34), 26, PAPER)
	var mode_text := "无尽" if str(LanNet.room.get("mode", "adventure")) == Run.MODE_ENDLESS else "冒险"
	var diff_label := _diff_name(int(LanNet.room.get("difficulty", 1)))
	_text("%s · %s · 房间号 %d" % [mode_text, diff_label, 1], Vector2(left, 196), Vector2(980, 24), 15, DIM)

	_text("队 伍", Vector2(left, 238), Vector2(980, 26), 18, PAPER)
	var y := 276.0
	if _lobby.is_empty():
		# 还没收到 lobby_changed 时先用本地 members 兜底
		var rows: Array = []
		for id in LanNet.members:
			rows.append(LanNet.members[id])
		for m in rows:
			_member_row(left, y, str(m.get("name", "墨客")), bool(m.get("ready", false)), int(m.get("slot", 0)) == 0)
			y += 44.0
	else:
		for m in _lobby.get("members", []):
			if m is Dictionary:
				_member_row(left, y, str(m.get("name", "墨客")), bool(m.get("ready", false)), bool(m.get("host", false)))
				y += 44.0

	var is_host := LanNet.role == "host"
	var ready := _local_ready()
	if is_host:
		_button("开 始 对 局", Vector2(left, 486), Vector2(300, 48), _on_start)
		_button("离 开 房 间", Vector2(left + 330, 486), Vector2(240, 48), _on_leave)
	else:
		_button("取 消 准 备" if ready else "我 准 备 好 了", Vector2(left, 486), Vector2(300, 48), _on_toggle_ready)
		_button("离 开 房 间", Vector2(left + 330, 486), Vector2(240, 48), _on_leave)
	_text("等待房主开始…" if not is_host else "队友加入后即可开始（1~4 人，人数越多敌人越强）", Vector2(left, 546), Vector2(620, 24), 14, DIM)
	_text("人数 %d / %d" % [maxi(1, LanNet.members.size()), 4], Vector2(left + 640, 546), Vector2(200, 24), 14, DIM)


func _member_row(x: float, y: float, who: String, ready: bool, host: bool) -> void:
	var tag := "房主" if host else "客机"
	_text("%s · %s" % [tag, who], Vector2(x, y), Vector2(360, 30), 18, PAPER)
	_text("已就绪" if ready else "未就绪", Vector2(x + 380, y + 2), Vector2(140, 26), 15, GOLD if ready else DIM)


# ---------------------------------------------------------------- 操作

func _on_host() -> void:
	var diff := _diff_opt.selected
	var char_id := str(_chars[_char_opt.selected]) if not _chars.is_empty() else Skulls.DEFAULT_ID
	var mode := Run.MODE_ADVENTURE if _mode_opt.selected == 0 else Run.MODE_ENDLESS
	_host_char = char_id
	var err := LanNet.host_room(_name_edit.text, mode, diff, char_id)
	if err != "":
		_set_status(err)
		return
	LanNet.end_scan()
	_set_status("房间已创建，等待队友加入…")
	_render()


func _on_auto_join() -> void:
	var rooms := LanNet.discovered_rooms()
	if rooms.is_empty():
		_set_status("暂未发现房间，请确认与主机在同一局域网")
		return
	var r: Dictionary = rooms[0]
	_join(str(r.get("ip", "")), int(r.get("port", 42422)))


func _on_manual_join() -> void:
	var ip := _ip_edit.text.strip_edges()
	if ip == "":
		_set_status("请输入主机 IP")
		return
	_join(ip, 42422)


func _join(ip: String, port: int) -> void:
	if ip == "":
		_set_status("房间地址无效")
		return
	var err := LanNet.join_room(ip, port)
	if err != "":
		_set_status(err)
		return
	_set_status("正在加入 %s…" % ip)


func _on_start() -> void:
	# 房间视图里选项控件已被释放，统一以 LanNet.room 里保存的开房配置为准
	var mode := str(LanNet.room.get("mode", Run.MODE_ADVENTURE))
	var diff := int(LanNet.room.get("difficulty", 1))
	var char_id := str(LanNet.room.get("skull", _host_char))
	if char_id == "":
		char_id = Skulls.DEFAULT_ID
	var err := LanNet.start_game(mode, diff, char_id)
	if err != "":
		_set_status(err)


func _on_toggle_ready() -> void:
	LanNet.set_ready(not _local_ready())
	_render()


func _on_leave() -> void:
	_set_status("正在离开房间…")
	await LanNet.leave()
	if is_inside_tree():
		_render()


func _close() -> void:
	if LanNet.role != "":
		LanNet.leave()
	else:
		LanNet.end_scan()
	_sfx.stream = SFX_BACK
	_sfx.play()
	closed.emit()
	queue_free()


# ---------------------------------------------------------------- 信号

func _on_lobby_changed(data: Dictionary) -> void:
	_lobby = data
	if LanNet.role != "":
		_render()
		var room_name := str(LanNet.room.get("name", ""))
		if room_name != "":
			_set_status("房间：%s" % room_name)


func _on_joined(resumed: bool) -> void:
	_set_status("已重连回房间" if resumed else "已加入房间")
	_render()


func _on_join_failed(reason: String) -> void:
	_set_status(reason)
	LanNet.begin_scan()
	_render()


func _on_session_started(_cfg: Dictionary) -> void:
	closed.emit()
	queue_free()


func _on_session_ended(reason: String) -> void:
	_menu_view = true
	if not is_inside_tree():
		return
	_set_status(reason if reason != "" else "对局已结束")
	LanNet.begin_scan()
	_render()


func _refresh_rooms() -> void:
	if _room_list == null or not is_instance_valid(_room_list):
		return
	for c in _room_list.get_children():
		_room_list.remove_child(c)
		c.queue_free()
	var rooms := LanNet.discovered_rooms()
	if rooms.is_empty():
		var hint := Label.new()
		hint.text = "正在扫描同一局域网内的房间…"
		hint.add_theme_color_override("font_color", DIM)
		hint.add_theme_font_size_override("font_size", 14)
		hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_room_list.add_child(hint)
		return
	for r in rooms:
		var label := "%s  ·  %s  ·  %d/%d" % [
			str(r.get("name", "房间")),
			_diff_name(int(r.get("difficulty", 1))),
			int(r.get("players", 1)), int(r.get("max", 2)),
		]
		var ip := str(r.get("ip", ""))
		var port := int(r.get("port", 42422))
		var b := _plain_button(label, Vector2(0, 0), Vector2(440, 40), _join.bind(ip, port))
		_room_list.add_child(b)


# ---------------------------------------------------------------- 小工具

## 4 人房：所有非房主成员都就绪才算“我方就绪”，避免只检查第一名队友。
func _local_ready() -> bool:
	var found := false
	var rows: Array = _lobby.get("members", []) if not _lobby.is_empty() else []
	for m in rows:
		if m is Dictionary and not bool(m.get("host", false)):
			found = true
			if not bool(m.get("ready", false)):
				return false
	if found:
		return true
	for id in LanNet.members:
		if int(id) != 1:
			found = true
			if not bool(LanNet.members[id].get("ready", false)):
				return false
	return found


func _unlocked_chars() -> Array:
	var out: Array = []
	for id in Skulls.ids():
		if Meta.is_unlocked(str(id)):
			out.append(str(id))
	if out.is_empty():
		out.append(Skulls.DEFAULT_ID)
	return out


func _char_name(id: String) -> String:
	var prof := Skulls.get_profile(id)
	return str(prof.get("name", prof.get("label", id)))


func _diff_name(i: int) -> String:
	var idx := clampi(i, 0, Run.DIFFICULTIES.size() - 1)
	return str(Run.DIFFICULTIES[idx].get("label", "问境"))


func _set_status(text: String) -> void:
	if is_instance_valid(_status):
		_status.text = text


## 常驻于 CanvasLayer 的静态文字（标题 / 关闭 / 状态栏），不会被 _render 清理
func _static_label(text: String, pos: Vector2, size: Vector2, font_size: int, color: Color, align := HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	var l := Label.new()
	l.text = text
	l.position = pos
	l.size = size
	l.horizontal_alignment = align
	l.add_theme_color_override("font_color", color)
	l.add_theme_font_size_override("font_size", font_size)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(l)
	return l


func _text(text: String, pos: Vector2, size: Vector2, font_size: int, color: Color, align := HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	var l := Label.new()
	l.text = text
	l.position = pos
	l.size = size
	l.horizontal_alignment = align
	l.add_theme_color_override("font_color", color)
	l.add_theme_font_size_override("font_size", font_size)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_body.add_child(l)
	return l


func _button(text: String, pos: Vector2, size: Vector2, cb: Callable) -> TextureButton:
	var b := TextureButton.new()
	b.texture_normal = InkTex.load("res://art/ui/menu/btn_normal.png")
	b.texture_pressed = InkTex.load("res://art/ui/menu/btn_clicked.png")
	b.ignore_texture_size = true
	b.stretch_mode = TextureButton.STRETCH_SCALE
	b.position = pos
	b.size = size
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	b.pressed.connect(func():
		_sfx.play()
		cb.call())
	_body.add_child(b)
	_text(text, pos, size, 18, PAPER, HORIZONTAL_ALIGNMENT_CENTER)
	return b


func _plain_button(text: String, pos: Vector2, size: Vector2, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.position = pos
	b.size = size
	b.flat = true
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.add_theme_color_override("font_color", PAPER)
	b.add_theme_color_override("font_hover_color", GOLD)
	b.add_theme_color_override("font_pressed_color", GOLD)
	b.add_theme_color_override("font_focus_color", PAPER)
	b.add_theme_font_size_override("font_size", 16)
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	b.pressed.connect(func():
		_sfx.play()
		cb.call())
	return b


func _line_edit(pos: Vector2, size: Vector2, placeholder: String) -> LineEdit:
	var e := LineEdit.new()
	e.position = pos
	e.size = size
	e.placeholder_text = placeholder
	e.add_theme_font_size_override("font_size", 16)
	e.add_theme_color_override("font_color", PAPER)
	e.add_theme_color_override("font_placeholder_color", DIM)
	_body.add_child(e)
	return e


func _option(pos: Vector2, size: Vector2, items: Array, selected: int) -> OptionButton:
	var o := OptionButton.new()
	for t in items:
		o.add_item(str(t))
	o.position = pos
	o.size = size
	o.selected = clampi(selected, 0, maxi(0, items.size() - 1))
	o.add_theme_font_size_override("font_size", 16)
	o.add_theme_color_override("font_color", PAPER)
	_body.add_child(o)
	return o
