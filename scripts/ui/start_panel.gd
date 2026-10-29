extends CanvasLayer

## 开始游戏 · 两步选择面板：先选模式（冒险 / 无尽），再选角色（按强度顺序，只放已解锁的）。
## 由主菜单「开始游戏」打开；选完角色立刻 Run.start(模式, 形态) 并切进第一间房。
## 风格与 blessing_panel / forms_panel 一致：水墨窗口 + 按钮卡。

const InkTex = preload("res://scripts/ui/ink_tex.gd")
const Skulls = preload("res://scripts/player/skulls.gd")
const SFX_CLICK := preload("res://audio/sfx/click.wav")

const INK := Color(0.05, 0.05, 0.05)
const PAPER := Color(0.949, 0.918, 0.847)
const DIM := Color(0.82, 0.79, 0.72)
const RED := Color(0.66, 0.2, 0.16)

## 两种模式的卡面文案（只留名字，别写解释性小作文）；数值成长写在 run_state.endless_waves
const MODES := {
	"adventure": {"label": "冒 险 模 式"},
	"endless": {"label": "无 尽 模 式"},
}

var _mode := ""
var _step := 0 # 0 = 选模式，1 = 选角色
var _sfx: AudioStreamPlayer # 常驻点击音：重建界面时不能把正在响的播放器一起删掉


func _ready() -> void:
	layer = 10
	_sfx = AudioStreamPlayer.new()
	_sfx.stream = SFX_CLICK
	add_child(_sfx)
	_build()


func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed("ui_cancel"):
		return
	get_viewport().set_input_as_handled()
	if _step == 1: # 先从选角退回选模式，再按一次才关面板
		_step = 0
		_refresh()
		return
	queue_free()


func _build() -> void:
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.5)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(dim)

	var win := TextureRect.new()
	win.texture = InkTex.load("res://art/ui/menu/window_large.png")
	win.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	win.stretch_mode = TextureRect.STRETCH_SCALE
	win.size = Vector2(1160, 600)
	win.position = Vector2(60, 60)
	win.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(win)

	if _step == 0:
		_label("选 择 模 式", 100, 44, PAPER)
		var modes := MODES.keys()
		for i in modes.size():
			_mode_card(str(modes[i]), i)
		_button("返  回", 530, 590, _close)
	else:
		_label("选 择 角 色", 100, 44, PAPER)
		_label("%s ｜ 只能选择已解锁的形态（由弱到强）" % Run.mode_label(), 170, 18, DIM)
		var ids := Skulls.ids()
		for i in ids.size():
			_char_card(str(ids[i]), i)
		_button("上 一 步", 530, 590, _back)


func _refresh() -> void:
	# 必须在信号回调里重建（点卡片/返回键）：只摘下来 + queue_free，
	# 千万不能用 free()——那会把正在发 pressed 的按钮当场销毁，引擎直接报错卡死
	for c in get_children():
		if c == _sfx: # 常驻点击音不参与重建，删了之后再点按钮就是「访问已释放对象」
			continue
		remove_child(c)
		c.queue_free()
	_build()


func _back() -> void:
	_step = 0
	_refresh()


func _close() -> void:
	queue_free()


func _pick_mode(id: String) -> void:
	_click_sfx()
	_mode = id
	_step = 1
	_refresh()


func _pick_char(id: String) -> void:
	if not Meta.is_unlocked(id):
		return
	_click_sfx()
	Run.start(_mode, id)
	get_tree().change_scene_to_file("res://scenes/world/room_01.tscn")


func _click_sfx() -> void:
	if is_instance_valid(_sfx):
		_sfx.play()


func _label(text: String, y: float, font_size: int, color: Color) -> void:
	var l := Label.new()
	l.text = text
	l.position = Vector2(60, y)
	l.size = Vector2(1160, 46)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_color_override("font_color", color)
	l.add_theme_font_size_override("font_size", font_size)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(l)


## 卡片内的多行文字：position 相对卡片，居中折行
func _card_text(card: Control, text: String, pos: Vector2, size: Vector2, font_size: int, color: Color) -> void:
	var l := Label.new()
	l.text = text
	l.position = pos
	l.size = size
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_color_override("font_color", color)
	l.add_theme_font_size_override("font_size", font_size)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(l)


func _mode_card(id: String, i: int) -> void:
	var info: Dictionary = MODES[id]
	# 两张卡居中排开：320 宽 + 80 间距
	var x := 280.0 + i * 400.0
	var b := TextureButton.new()
	b.texture_normal = InkTex.load("res://art/ui/menu/btn_normal.png")
	b.texture_pressed = InkTex.load("res://art/ui/menu/btn_clicked.png")
	b.ignore_texture_size = true
	b.stretch_mode = TextureButton.STRETCH_SCALE
	b.size = Vector2(320, 250)
	b.position = Vector2(x, 240)
	b.pressed.connect(_pick_mode.bind(id))
	add_child(b)
	_card_text(b, str(info["label"]), Vector2(0, 100), Vector2(320, 44), 28, PAPER)


func _char_card(id: String, i: int) -> void:
	var unlocked := Meta.is_unlocked(id)
	var profile: Dictionary = Skulls.get_profile(id)
	# 五张卡居中排开：208 宽 + 20 间距
	var x := 80.0 + i * 228.0

	var card: Control
	if unlocked:
		var b := TextureButton.new()
		b.texture_normal = InkTex.load("res://art/ui/menu/btn_normal.png")
		b.texture_pressed = InkTex.load("res://art/ui/menu/btn_clicked.png")
		b.ignore_texture_size = true
		b.stretch_mode = TextureButton.STRETCH_SCALE
		b.pressed.connect(_pick_char.bind(id))
		card = b
	else:
		var t := TextureRect.new()
		t.texture = InkTex.load("res://art/ui/menu/btn_normal.png")
		t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		t.stretch_mode = TextureRect.STRETCH_SCALE
		t.modulate = Color(1, 1, 1, 0.55) # 未解锁整卡压暗
		card = t
	card.size = Vector2(208, 270)
	card.position = Vector2(x, 225)
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE if not unlocked else Control.MOUSE_FILTER_STOP
	add_child(card)

	if unlocked:
		_card_text(card, str(profile["label"]), Vector2(0, 24), Vector2(208, 42), 30, PAPER)
		_card_text(card, str(profile.get("name", "")), Vector2(0, 64), Vector2(208, 24), 16, DIM)
		_card_text(card, "契合  " + Meta.mastery_text(id), Vector2(0, 108), Vector2(208, 30), 16, RED)
		_card_text(card, "点击开始这一局", Vector2(0, 200), Vector2(208, 30), 15, DIM)
	else:
		_card_text(card, "？？？", Vector2(0, 24), Vector2(208, 42), 30, PAPER)
		_card_text(card, Meta.unlock_hint(id), Vector2(10, 92), Vector2(188, 96), 15, DIM)
		# 双条件用换行竖排（比「·」拼一行更不容易顶出卡片）
		_card_text(card, Meta.unlock_progress(id).replace(" · ", "\n"), Vector2(0, 196), Vector2(208, 44), 15, RED)


func _button(text: String, x: float, y: float, cb: Callable) -> void:
	var b := TextureButton.new()
	b.texture_normal = InkTex.load("res://art/ui/menu/btn_normal.png")
	b.texture_pressed = InkTex.load("res://art/ui/menu/btn_clicked.png")
	b.ignore_texture_size = true
	b.stretch_mode = TextureButton.STRETCH_SCALE
	b.size = Vector2(220, 52)
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
		_click_sfx()
		cb.call())
	add_child(b)
