extends CanvasLayer

## 房间通关后的「三选一」强化面板：免费选取一项局内强化，或直接继续前进。
## 由 room_01 在清空房间后弹出；purchased 让房间重算玩家属性，proceed 让房间进下一层。

signal purchased
signal proceed

const InkTex = preload("res://scripts/ui/ink_tex.gd")
const SFX_LEVEL := preload("res://audio/sfx/level_up.wav")
const SFX_CLICK := preload("res://audio/sfx/click.wav")
const SFX_REWARD := preload("res://audio/sfx/room_reward.wav")

const INK := Color(0.05, 0.05, 0.05)
const PAPER := Color(0.949, 0.918, 0.847)

var _cards: Array = []
var _card_root: Node
var _bought := false
var _rerolls_left := 0
var _reroll_button: TextureButton
var _proceed_button: TextureButton
var _proceeding := false
var title_text := "" # 试炼场等复用入口可覆盖标题；正式房间留空
var proceed_text := "继续前进"


func _ready() -> void:
	layer = 8
	process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().paused = true # 挑强化时时间停住，战场不再动弹
	_cards = Run.roll_cards(3)
	_rerolls_left = Meta.shop_level("upgrade_reroll") + int(Run.blessing == "reroll") # 每个强化面板恢复永久与赐福次数
	var sfx := AudioStreamPlayer.new()
	sfx.bus = "SFX"
	add_child(sfx)
	sfx.stream = SFX_LEVEL
	sfx.play()

	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.45)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(dim)

	var win := TextureRect.new()
	win.texture = InkTex.load("res://art/ui/menu/window_large.png")
	win.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	win.stretch_mode = TextureRect.STRETCH_SCALE
	win.size = Vector2(1140, 610)
	win.position = Vector2(70, 52)
	win.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(win)

	var heading := title_text if not title_text.is_empty() else Run.room_label() + "  " + Run.room_no() + "  已清"
	_make_label(heading, 76, 36, PAPER)
	_make_label("选择一项通关强化 —— 同一条流派连选三级可推到「极」", 142, 20, Color(0.75, 0.72, 0.66))

	_card_root = Node.new()
	add_child(_card_root)
	_build_cards()

	_proceed_button = _make_button(proceed_text, 584, _on_proceed, 380.0, null)
	_reroll_button = _make_button("", 584, _reroll, 660.0)
	_update_reroll()


func _on_proceed() -> void:
	if _proceeding:
		return
	_proceeding = true
	if is_instance_valid(_proceed_button):
		_proceed_button.disabled = true
	_play_transition_sfx(SFX_CLICK)
	proceed.emit()


func _reroll() -> void:
	if _bought:
		return
	if _rerolls_left > 0:
		_rerolls_left -= 1
	elif not Run.consume_supply_reroll():
		return
	_cards = Run.roll_cards(3)
	_build_cards()
	_update_reroll()


func _update_reroll() -> void:
	if _reroll_button == null:
		return
	var total := _rerolls_left + Run.supply_upgrade_rerolls
	_reroll_button.disabled = _bought or total <= 0
	_reroll_button.modulate = Color.WHITE if not _reroll_button.disabled else Color(1, 1, 1, 0.45)
	var label := _reroll_button.get_child(0) as Label
	if label != null:
		label.text = "重随 ×%d" % total


func _make_label(text: String, y: float, font_size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.size = Vector2(1140, 50)
	l.position = Vector2(70, y)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_color_override("font_color", color)
	l.add_theme_font_size_override("font_size", font_size)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(l)
	return l



## 流派配色：0 朱砂 / 1 墨青 / 2 赭金（与 run_state.FORM_UPGRADES 的 theme 对齐）
func _theme_color(theme: int) -> Color:
	match theme:
		1: return Color(0.18, 0.38, 0.40)
		2: return Color(0.52, 0.34, 0.12)
		_: return Color(0.55, 0.16, 0.13)


func _build_cards() -> void:
	for c in _card_root.get_children():
		c.queue_free()
	for i in _cards.size():
		var key := str(_cards[i])
		var info: Dictionary = Run.card_info(key)
		var is_form := info.has("tier")
		var accent := _theme_color(int(info.get("theme", 0)))
		var b := TextureButton.new()
		b.texture_normal = InkTex.load("res://art/ui/menu/btn_normal.png")
		b.texture_pressed = InkTex.load("res://art/ui/menu/btn_clicked.png")
		b.ignore_texture_size = true
		b.stretch_mode = TextureButton.STRETCH_SCALE
		b.size = Vector2(330, 350)
		b.position = Vector2(115 + i * 360, 208)
		if _bought:
			b.modulate = Color(1, 1, 1, 0.4)
			b.disabled = true
		else:
			b.pressed.connect(func(): _on_card(key))

		# 顶部：图标、流派名、层级各自占位，长标题不会再顶到层级标签。
		var icon := TextureRect.new()
		icon.texture = InkTex.load("res://art/ui/icons/" + str(info.get("icon", "icon_medal")) + ".png")
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.size = Vector2(42, 42)
		icon.position = Vector2(22, 16)
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.add_child(icon)

		var path := Label.new()
		path.text = str(info.get("path", "通用强化"))
		path.size = Vector2(160, 28)
		path.position = Vector2(76, 20)
		path.add_theme_color_override("font_color", accent if is_form else Color(0.32, 0.30, 0.26))
		path.add_theme_font_size_override("font_size", 17)
		path.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.add_child(path)

		var tag := Label.new()
		tag.text = ("%d / 3" % int(info.get("tier", 1))) if is_form else ("%d / %d" % [Run.level(key) + 1, int(info.get("max", 1))])
		tag.size = Vector2(70, 26)
		tag.position = Vector2(236, 20)
		tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		tag.add_theme_color_override("font_color", accent if is_form else Color(0.32, 0.30, 0.26))
		tag.add_theme_font_size_override("font_size", 16)
		tag.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.add_child(tag)

		var title := Label.new()
		title.text = str(info["label"]) if is_form else "%s  Lv%d" % [str(info["label"]), Run.level(key) + 1]
		title.size = Vector2(286, 44)
		title.position = Vector2(22, 62)
		title.add_theme_color_override("font_color", accent if is_form else INK)
		title.add_theme_font_size_override("font_size", 28)
		title.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.add_child(title)

		var divider := ColorRect.new()
		divider.color = Color(accent, 0.55) if is_form else Color(0.2, 0.18, 0.15, 0.35)
		divider.size = Vector2(286, 2)
		divider.position = Vector2(22, 114)
		divider.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.add_child(divider)

		# 正文使用独立固定区域；底部领取提示另起一行，任何换行都不会与之重叠。
		var desc := Label.new()
		desc.text = str(info["desc"])
		desc.size = Vector2(282, 140)
		desc.position = Vector2(24, 132)
		desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		desc.clip_text = true
		desc.max_lines_visible = 6
		desc.add_theme_color_override("font_color", Color(0.16, 0.15, 0.13))
		desc.add_theme_font_size_override("font_size", 18)
		desc.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.add_child(desc)

		var price := Label.new()
		price.text = "免 费 领 取"
		price.size = Vector2(286, 36)
		price.position = Vector2(22, 292)
		price.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		price.add_theme_color_override("font_color", Color(0.58, 0.16, 0.12))
		price.add_theme_font_size_override("font_size", 20)
		price.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.add_child(price)

		_card_root.add_child(b)


func _on_card(key: String) -> void:
	if _bought:
		return
	if not Run.buy(key):
		_play_sfx(SFX_CLICK)
		return
	_play_sfx(SFX_REWARD)
	_bought = true
	_build_cards()
	_update_reroll()
	purchased.emit()


func _play_sfx(stream: AudioStream) -> void:
	var s := AudioStreamPlayer.new()
	s.bus = "SFX"
	add_child(s)
	s.stream = stream
	s.play()
	s.finished.connect(s.queue_free, CONNECT_ONE_SHOT)


func _play_transition_sfx(stream: AudioStream) -> void:
	var s := AudioStreamPlayer.new()
	s.bus = "SFX"
	s.process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().root.add_child(s)
	s.stream = stream
	s.play()
	s.finished.connect(s.queue_free, CONNECT_ONE_SHOT)


func _make_button(text: String, y: float, cb: Callable, x := 520.0, sfx: AudioStream = SFX_CLICK) -> TextureButton:
	var b := TextureButton.new()
	b.texture_normal = InkTex.load("res://art/ui/menu/btn_normal.png")
	b.texture_pressed = InkTex.load("res://art/ui/menu/btn_clicked.png")
	b.ignore_texture_size = true
	b.stretch_mode = TextureButton.STRETCH_SCALE
	b.size = Vector2(240, 60)
	b.position = Vector2(x, y)
	var l := Label.new()
	l.text = text
	l.size = b.size
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.add_theme_color_override("font_color", INK)
	l.add_theme_font_size_override("font_size", 24)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(l)
	b.pressed.connect(func():
		if sfx != null:
			_play_sfx(sfx)
		cb.call())
	add_child(b)
	return b
