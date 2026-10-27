extends CanvasLayer

## 开局赐福：每局第一层出发前三选一，效果只在本局生效。由 room_01 在进入战场时弹出。
## 选中即生效并关闭；不花钱，但一局只有这一次机会。

signal chosen(id: String)

const InkTex = preload("res://scripts/ui/ink_tex.gd")

const INK := Color(0.05, 0.05, 0.05)
const PAPER := Color(0.949, 0.918, 0.847)
const DIM := Color(0.82, 0.79, 0.72)


func _ready() -> void:
	layer = 8
	process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().paused = true # 挑赐福时时间停住

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

	_make_label("起 局 赐 福", 175, 40, PAPER)
	_make_label("选一样墨赐带入这一局", 235, 20, DIM)

	var ids := Run.BLESSINGS.keys()
	for i in ids.size():
		_make_card(str(ids[i]), i)


## 选中一个赐福：写入 Run 并立刻结算能立刻结算的部分（续命留到阵亡时）
func pick(id: String) -> void:
	if Run.blessing != "":
		return
	Run.blessing = id
	match id:
		"bones":
			Score.add_bones(15)
		"hp":
			Run.hp += 2 # apply_to 重算上限时会带上赐福的 +2，这里先把当前血量加上
	get_tree().paused = false
	chosen.emit(id)
	queue_free()


func _make_label(text: String, y: float, font_size: int, color: Color) -> void:
	var l := Label.new()
	l.text = text
	l.size = Vector2(960, 44)
	l.position = Vector2(160, y)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_color_override("font_color", color)
	l.add_theme_font_size_override("font_size", font_size)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(l)


func _make_card(id: String, i: int) -> void:
	var info: Dictionary = Run.BLESSINGS[id]
	var b := TextureButton.new()
	b.texture_normal = InkTex.load("res://art/ui/menu/btn_normal.png")
	b.texture_pressed = InkTex.load("res://art/ui/menu/btn_clicked.png")
	b.ignore_texture_size = true
	b.stretch_mode = TextureButton.STRETCH_SCALE
	b.size = Vector2(230, 170)
	b.position = Vector2(225 + i * 265, 330)
	b.pressed.connect(pick.bind(id))

	var title := Label.new()
	title.text = str(info["label"])
	title.size = Vector2(230, 40)
	title.position = Vector2(0, 30)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_color_override("font_color", PAPER)
	title.add_theme_font_size_override("font_size", 28)
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(title)

	var desc := Label.new()
	desc.text = str(info["desc"])
	desc.size = Vector2(210, 70)
	desc.position = Vector2(10, 82)
	desc.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc.add_theme_color_override("font_color", DIM)
	desc.add_theme_font_size_override("font_size", 17)
	desc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(desc)

	add_child(b)
