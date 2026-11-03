extends CanvasLayer

## 开始游戏 · 行旅卷：择路（模式）→ 问境（五档难度）→ 化身（选人、预览、补给、启程）。
## 角色卡只负责选中，右侧显示真实 Spine 待机；最后点「启程」才开新一局。

const InkTex = preload("res://scripts/ui/ink_tex.gd")
const Skulls = preload("res://scripts/player/skulls.gd")
const SFX_CLICK := preload("res://audio/sfx/click.wav")

const INK := Color(0.05, 0.05, 0.05)
const PAPER := Color(0.949, 0.918, 0.847)
const DIM := Color(0.82, 0.79, 0.72)
const RED := Color(0.66, 0.2, 0.16)
const GOLD := Color(0.9, 0.75, 0.3)

const MODES := {
	"adventure": {"label": "冒 险 模 式", "desc": "三关问道 · 讨伐守关者", "foot": "一卷有终，胜负有款"},
	"endless": {"label": "无 尽 模 式", "desc": "层层深入 · 问道无止", "foot": "以所选问境为初始，逐层成长"},
}

var _mode := ""
var _difficulty := 1 # 默认落笔，保持此前的战斗体验
var _char := ""
var _step := 0 # 0 择路 / 1 问境 / 2 化身
var _supply := ""
var _sfx: AudioStreamPlayer
var _portrait: TextureRect = null


func _ready() -> void:
	layer = 10
	_supply = Meta.selected_supply
	_sfx = AudioStreamPlayer.new()
	_sfx.stream = SFX_CLICK
	add_child(_sfx)
	_build()


func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed("ui_cancel"):
		return
	get_viewport().set_input_as_handled()
	if _step > 0:
		_step -= 1
		_refresh()
		return
	queue_free()


func _build() -> void:
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.62)
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

	var titles := ["择  路", "问  境", "化  身"]
	var subtitles := ["此行向何处去", "五重墨境，只改敌众与敌锋", "先见其人，再赴其局"]
	_label("行 旅 卷", 72, 16, RED)
	_label(titles[_step], 98, 38, PAPER)
	_label(subtitles[_step], 146, 16, DIM)
	var steps := ["壹 · 择路", "贰 · 问境", "叁 · 化身"]
	for i in 3:
		_text(steps[i], Vector2(374 + i * 180, 180), Vector2(170, 26), 15, PAPER if i == _step else DIM)
	_rule(Vector2(180, 213), Vector2(920, 1))

	match _step:
		0:
			var modes := MODES.keys()
			for i in modes.size():
				_mode_card(str(modes[i]), i)
			_button("返  回", 530, 585, _close)
		1:
			for i in Run.DIFFICULTIES.size():
				_difficulty_card(i)
			_button("上 一 步", 100, 585, _back)
		2:
			_character_step()
			_button("上 一 步", 100, 590, _back)
			_button("启  程", 930, 590, _start_run)
	_label("墨 构 · 一 卷 一 行", 624, 12, DIM)


func _refresh() -> void:
	for c in get_children():
		if c == _sfx:
			continue
		remove_child(c)
		c.queue_free()
	_portrait = null
	_build()


func _back() -> void:
	_step = maxi(0, _step - 1)
	_refresh()


func _close() -> void:
	queue_free()


func _pick_mode(id: String) -> void:
	_click_sfx()
	_mode = id
	_step = 1
	_refresh()


func _pick_difficulty(index: int) -> void:
	_click_sfx()
	_difficulty = index
	_step = 2
	_ensure_char()
	_refresh()


func _pick_char(id: String) -> void:
	if not Meta.is_unlocked(id):
		return
	_click_sfx()
	_char = id
	_refresh()


func _ensure_char() -> void:
	if _char != "" and Meta.is_unlocked(_char):
		return
	_char = ""
	for id in Skulls.ids():
		if Meta.is_unlocked(str(id)):
			_char = str(id)
			return


func _start_run() -> void:
	if _mode == "" or _char == "" or not Meta.is_unlocked(_char):
		return
	Meta.select_supply(_supply)
	Run.start(_mode, _char, _difficulty)
	get_tree().change_scene_to_file("res://scenes/world/room_01.tscn")


func _click_sfx() -> void:
	if is_instance_valid(_sfx):
		_sfx.play()


func _label(text: String, y: float, font_size: int, color: Color) -> void:
	_text(text, Vector2(60, y), Vector2(1160, 46), font_size, color)


func _text(text: String, pos: Vector2, size: Vector2, font_size: int, color: Color, alignment := HORIZONTAL_ALIGNMENT_CENTER) -> void:
	var l := Label.new()
	l.text = text
	l.position = pos
	l.size = size
	l.horizontal_alignment = alignment
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_color_override("font_color", color)
	l.add_theme_font_size_override("font_size", font_size)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(l)


func _card_text(card: Control, text: String, pos: Vector2, size: Vector2, font_size: int, color: Color) -> void:
	var l := Label.new()
	l.text = text
	l.position = pos
	l.size = size
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_color_override("font_color", color)
	l.add_theme_font_size_override("font_size", font_size)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(l)


func _rule(pos: Vector2, size: Vector2) -> void:
	var r := ColorRect.new()
	r.color = Color(0.66, 0.2, 0.16, 0.6)
	r.position = pos
	r.size = size
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(r)


func _texture_card(pos: Vector2, size: Vector2, selected := false, parent: Node = null) -> TextureButton:
	var b := TextureButton.new()
	b.texture_normal = InkTex.load("res://art/ui/menu/btn_normal.png")
	b.texture_pressed = InkTex.load("res://art/ui/menu/btn_clicked.png")
	b.ignore_texture_size = true
	b.stretch_mode = TextureButton.STRETCH_SCALE
	b.position = pos
	b.size = size
	b.modulate = Color(1.16, 1.09, 0.88) if selected else Color.WHITE
	if parent == null:
		parent = self
	parent.add_child(b)
	return b


func _mode_card(id: String, i: int) -> void:
	var info: Dictionary = MODES[id]
	var b := _texture_card(Vector2(260 + i * 400, 252), Vector2(360, 270))
	_card_text(b, str(info["label"]), Vector2(0, 42), Vector2(360, 48), 30, PAPER)
	_card_text(b, str(info["desc"]), Vector2(20, 116), Vector2(320, 34), 17, DIM)
	_card_text(b, str(info["foot"]), Vector2(20, 190), Vector2(320, 42), 15, RED)
	b.pressed.connect(_pick_mode.bind(id))


func _difficulty_card(index: int) -> void:
	var info: Dictionary = Run.DIFFICULTIES[index]
	var b := _texture_card(Vector2(110 + index * 214, 246), Vector2(194, 278), index == _difficulty)
	_card_text(b, str(info["seal"]), Vector2(0, 10), Vector2(194, 24), 14, GOLD if index == 4 else RED)
	_card_text(b, str(info["label"]), Vector2(0, 44), Vector2(194, 46), 30, PAPER)
	_card_text(b, str(info["desc"]), Vector2(12, 108), Vector2(170, 52), 15, DIM)
	_card_text(b, "敌众 %d%%" % int(round(float(info["count"]) * 100.0)), Vector2(0, 180), Vector2(194, 26), 15, PAPER)
	var attack := int(info["attack"])
	var attack_text := "敌锋 原值" if attack == 0 else "敌锋 %+d" % attack
	_card_text(b, attack_text, Vector2(0, 208), Vector2(194, 26), 15, PAPER)
	var foot := "双守关者 · 连战" if index == 4 and _mode == Run.MODE_ADVENTURE else ("仅此初始 · 逐层成长" if _mode == Run.MODE_ENDLESS else "单守关者")
	_card_text(b, foot, Vector2(6, 242), Vector2(182, 24), 12, RED if index == 4 else DIM)
	b.pressed.connect(_pick_difficulty.bind(index))


func _character_step() -> void:
	_ensure_char()
	var ids := Skulls.ids()
	var scroll := ScrollContainer.new()
	scroll.position = Vector2(90, 242)
	scroll.size = Vector2(674, 254)
	scroll.clip_contents = true
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	add_child(scroll)
	var h_scroll := scroll.get_h_scroll_bar()
	h_scroll.custom_minimum_size = Vector2(0, 12)
	var track := StyleBoxFlat.new()
	track.bg_color = Color(0.05, 0.05, 0.05, 0.55)
	track.set_corner_radius_all(4)
	h_scroll.add_theme_stylebox_override("scroll", track)
	var grabber := StyleBoxFlat.new()
	grabber.bg_color = RED
	grabber.set_corner_radius_all(4)
	h_scroll.add_theme_stylebox_override("grabber", grabber)
	h_scroll.add_theme_stylebox_override("grabber_highlight", grabber)
	h_scroll.add_theme_stylebox_override("grabber_pressed", grabber)
	var cards := Control.new()
	cards.custom_minimum_size = Vector2(ids.size() * 134 - 12, 240)
	cards.mouse_filter = Control.MOUSE_FILTER_IGNORE
	scroll.add_child(cards)
	for i in ids.size():
		_char_card(str(ids[i]), i, cards)
	_rule(Vector2(782, 246), Vector2(1, 270))
	if _char != "":
		var profile: Dictionary = Skulls.get_profile(_char)
		_text(str(profile["label"]), Vector2(812, 240), Vector2(220, 38), 26, GOLD if bool(profile.get("hero", false)) else PAPER, HORIZONTAL_ALIGNMENT_LEFT)
		_text(str(profile.get("name", "")), Vector2(812, 278), Vector2(220, 26), 15, DIM, HORIZONTAL_ALIGNMENT_LEFT)
		var portrait_path := str(profile.get("portrait", ""))
		if portrait_path != "" and ResourceLoader.exists(portrait_path):
			_make_portrait(portrait_path)
			_text("角 色 原 画", Vector2(800, 540), Vector2(360, 22), 12, RED)
		else:
			_text("动 作 预 览", Vector2(800, 326), Vector2(360, 24), 13, RED)
			_rule(Vector2(850, 522), Vector2(260, 2))
			_make_preview()
	_supply_selector()


func _char_card(id: String, i: int, parent: Control) -> void:
	var unlocked := Meta.is_unlocked(id)
	var profile: Dictionary = Skulls.get_profile(id)
	var card: Control
	if unlocked:
		var b := _texture_card(Vector2(i * 134, 0), Vector2(122, 240), id == _char, parent)
		b.pressed.connect(_pick_char.bind(id))
		card = b
	else:
		var t := TextureRect.new()
		t.texture = InkTex.load("res://art/ui/menu/btn_normal.png")
		t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		t.stretch_mode = TextureRect.STRETCH_SCALE
		t.modulate = Color(1, 1, 1, 0.48)
		t.position = Vector2(i * 134, 0)
		t.size = Vector2(122, 240)
		t.mouse_filter = Control.MOUSE_FILTER_IGNORE
		parent.add_child(t)
		card = t
	if unlocked:
		if bool(profile.get("hero", false)):
			_card_text(card, "英 雄", Vector2(0, 5), Vector2(122, 18), 11, GOLD)
		_card_text(card, str(profile["label"]), Vector2(2, 32), Vector2(118, 38), 23, PAPER)
		_card_text(card, str(profile.get("name", "")), Vector2(4, 76), Vector2(114, 42), 13, DIM)
		_card_text(card, "契合", Vector2(0, 136), Vector2(122, 22), 12, DIM)
		_card_text(card, Meta.mastery_text(id), Vector2(2, 160), Vector2(118, 24), 13, RED)
		_card_text(card, "已 选" if id == _char else "选 择", Vector2(0, 202), Vector2(122, 24), 13, RED if id == _char else DIM)
	else:
		_card_text(card, "？？？", Vector2(0, 34), Vector2(122, 38), 22, PAPER)
		_card_text(card, Meta.unlock_hint(id), Vector2(8, 94), Vector2(106, 76), 12, DIM)
		_card_text(card, "尚未解锁", Vector2(0, 202), Vector2(122, 24), 12, RED)


func _make_portrait(path: String) -> void:
	_portrait = TextureRect.new()
	_portrait.texture = load(path)
	_portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_portrait.position = Vector2(792, 300)
	_portrait.size = Vector2(368, 238)
	_portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_portrait)


func _make_preview() -> void:
	var profile: Dictionary = Skulls.get_profile(_char)
	var data = load(str(profile["data"]))
	if data == null or not data.call("is_skeleton_data_loaded"):
		return
	var sprite = ClassDB.instantiate("SpineSprite")
	add_child(sprite)
	sprite.set("skeleton_data_res", data)
	data.call("set_default_mix", 0.2)
	var sc := float(profile["scale"]) * 1.9
	sprite.scale = Vector2(sc, sc)
	sprite.position = Vector2(980, 520)
	var st = sprite.call("get_animation_state")
	st.call("set_animation", str(profile["anim"]["idle"]), true, 0)


func _supply_selector() -> void:
	_text("开局补给 · 启程消耗 1 个", Vector2(90, 500), Vector2(670, 24), 14, DIM)
	var ids := ["", "supply_hp", "supply_revive", "supply_reroll"]
	for i in ids.size():
		var id := str(ids[i])
		var text := "不带补给"
		if id != "":
			text = "%s ×%d" % [Meta.INK_SHOP[id]["label"], Meta.supply_count(id)]
		var b := _texture_card(Vector2(90 + i * 169, 532), Vector2(158, 42), id == _supply)
		b.disabled = id != "" and Meta.supply_count(id) <= 0
		_card_text(b, text, Vector2.ZERO, b.size, 14, INK if not b.disabled else DIM)
		b.pressed.connect(func():
			_supply = id
			_click_sfx()
			_refresh())


func _button(text: String, x: float, y: float, cb: Callable) -> void:
	var b := _texture_card(Vector2(x, y), Vector2(220, 52))
	_card_text(b, text, Vector2.ZERO, b.size, 22, INK)
	b.pressed.connect(func():
		_click_sfx()
		cb.call())
