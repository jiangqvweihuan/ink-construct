extends CanvasLayer

## 房间通关后的「三选一」强化面板：花墨骨买一个局内强化，或直接继续前进。
## 由 room_01 在清空房间后弹出；purchased 让房间重算玩家属性，proceed 让房间进下一层。

signal purchased
signal proceed

const InkTex = preload("res://scripts/ui/ink_tex.gd")
const SFX_LEVEL := preload("res://audio/sfx/level_up.wav")
const SFX_CLICK := preload("res://audio/sfx/click.wav")

const INK := Color(0.05, 0.05, 0.05)
const PAPER := Color(0.949, 0.918, 0.847)

var _cards: Array = []
var _card_root: Node
var _bones_label: Label
var _bought := false


func _ready() -> void:
	layer = 8
	process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().paused = true # 挑强化时时间停住，战场不再动弹
	_cards = Run.roll_cards(3)
	var sfx := AudioStreamPlayer.new()
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
	win.size = Vector2(960, 430)
	win.position = Vector2(160, 145)
	win.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(win)

	_make_label(Run.room_label() + "  " + Run.room_no() + "  已清", 175, 40, PAPER)
	_make_label("取一样墨骨强化，或者直接前进", 235, 20, Color(0.75, 0.72, 0.66))

	_bones_label = _make_label("", 285, 22, PAPER)
	_update_bones()

	_card_root = Node.new()
	add_child(_card_root)
	_build_cards()

	_make_button("继续前进", 505, func(): proceed.emit())


func _make_label(text: String, y: float, font_size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.size = Vector2(960, 44)
	l.position = Vector2(160, y)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_color_override("font_color", color)
	l.add_theme_font_size_override("font_size", font_size)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(l)
	return l


func _update_bones() -> void:
	if _bones_label:
		_bones_label.text = "墨骨  %d" % Score.bones


func _build_cards() -> void:
	for c in _card_root.get_children():
		c.queue_free()
	for i in _cards.size():
		var key := str(_cards[i])
		var info: Dictionary = Run.UPGRADES[key]
		var cost := Run.upgrade_cost(key)
		var b := TextureButton.new()
		b.texture_normal = InkTex.load("res://art/ui/menu/btn_normal.png")
		b.texture_pressed = InkTex.load("res://art/ui/menu/btn_clicked.png")
		b.ignore_texture_size = true
		b.stretch_mode = TextureButton.STRETCH_SCALE
		b.size = Vector2(230, 170)
		b.position = Vector2(225 + i * 265, 330)
		if _bought or Score.bones < cost:
			b.modulate = Color(1, 1, 1, 0.4)
			b.disabled = true
		else:
			b.pressed.connect(func():
				var s := AudioStreamPlayer.new()
				add_child(s)
				s.stream = SFX_CLICK
				s.play()
				_on_card(key))

		var title := Label.new()
		title.text = str(info["label"])
		title.size = Vector2(230, 40)
		title.position = Vector2(0, 26)
		title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		title.add_theme_color_override("font_color", PAPER)
		title.add_theme_font_size_override("font_size", 30)
		title.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.add_child(title)

		var desc := Label.new()
		desc.text = str(info["desc"])
		desc.size = Vector2(210, 40)
		desc.position = Vector2(10, 74)
		desc.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		desc.add_theme_color_override("font_color", Color(0.82, 0.79, 0.72))
		desc.add_theme_font_size_override("font_size", 17)
		desc.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.add_child(desc)

		var price := Label.new()
		price.text = "%d 墨骨" % cost
		price.size = Vector2(230, 30)
		price.position = Vector2(0, 128)
		price.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		price.add_theme_color_override("font_color", Color(0.66, 0.2, 0.16))
		price.add_theme_font_size_override("font_size", 20)
		price.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.add_child(price)

		_card_root.add_child(b)


func _on_card(key: String) -> void:
	if _bought:
		return
	if not Run.buy(key):
		return
	_bought = true
	_update_bones()
	_build_cards()
	purchased.emit()


func _make_button(text: String, y: float, cb: Callable) -> void:
	var b := TextureButton.new()
	b.texture_normal = InkTex.load("res://art/ui/menu/btn_normal.png")
	b.texture_pressed = InkTex.load("res://art/ui/menu/btn_clicked.png")
	b.ignore_texture_size = true
	b.stretch_mode = TextureButton.STRETCH_SCALE
	b.size = Vector2(240, 60)
	b.position = Vector2(520, y)
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
		var s := AudioStreamPlayer.new()
		add_child(s)
		s.stream = SFX_CLICK
		s.play()
		cb.call())
	add_child(b)
