extends CanvasLayer

## 功名录：主菜单入口。
## 按类别分页，条目卡三列铺开；未达成的条目按「当前 / 目标」显示进度，
## 隐藏条目达成前只显示「？？？」。带称号的条目点亮后可点击佩戴。

const InkTex = preload("res://scripts/ui/ink_tex.gd")
const SFX_CLICK := preload("res://audio/sfx/click.wav")
const SFX_BACK := preload("res://audio/sfx/ui_back.wav")

const INK := Color(0.05, 0.05, 0.05)
const PAPER := Color(0.949, 0.918, 0.847)
const DIM := Color(0.62, 0.60, 0.55)
const RED := Color(0.66, 0.2, 0.16)
const GOLD := Color(0.87, 0.70, 0.28)

const CARD_W := 368.0
const CARD_H := 108.0
const GAP_X := 16.0
const GAP_Y := 12.0
const COLS := 3

var _tab := "全部"
var _scroll: ScrollContainer
var _content: Control
var _header: Label
var _title_label: Label
var _tabs: Array = []


func _ready() -> void:
	layer = 10
	_build()


func _build() -> void:
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.62)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(dim)

	var win := TextureRect.new()
	win.texture = InkTex.load("res://art/ui/menu/window_large.png")
	win.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	win.stretch_mode = TextureRect.STRETCH_SCALE
	win.size = Vector2(1200, 620)
	win.position = Vector2(40, 50)
	win.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(win)

	_text("功 名 录", Vector2(72, 68), Vector2(260, 48), 36, PAPER, self)
	_header = _text("", Vector2(320, 80), Vector2(400, 30), 16, DIM, self)
	_title_label = _text("", Vector2(700, 80), Vector2(470, 30), 14, GOLD, self)
	_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_title_label.clip_text = true

	_build_tabs()
	_build_scroll()

	_text("点击带称号的条目可佩戴，加成下一局生效；未达成条目显示当前进度", Vector2(72, 556), Vector2(760, 30), 13, DIM, self)
	_make_button("返  回", Vector2(1040, 556), Vector2(150, 44), _close, SFX_BACK)
	_rebuild_cards()


func _build_tabs() -> void:
	var cats := ["全部"]
	cats.append_array(Achievements.CAT_ORDER)
	var x := 72.0
	for cat in cats:
		var b := Button.new()
		b.text = str(cat)
		b.flat = true
		b.position = Vector2(x, 126)
		b.size = Vector2(140, 38)
		b.focus_mode = Control.FOCUS_NONE
		b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		b.add_theme_font_size_override("font_size", 17)
		b.add_theme_color_override("font_color", DIM)
		b.add_theme_color_override("font_hover_color", PAPER)
		b.pressed.connect(_switch_tab.bind(str(cat)))
		add_child(b)
		_tabs.append({"button": b, "cat": str(cat)})
		x += 148.0


func _build_scroll() -> void:
	_scroll = ScrollContainer.new()
	_scroll.position = Vector2(72, 176)
	_scroll.size = Vector2(1136, 366)
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	_scroll.mouse_filter = Control.MOUSE_FILTER_STOP
	_scroll.follow_focus = true
	add_child(_scroll)
	_content = Control.new()
	_content.custom_minimum_size = Vector2(1136, 0)
	_content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_scroll.add_child(_content)


func _switch_tab(cat: String) -> void:
	if _tab == cat:
		return
	_tab = cat
	_play_sfx(SFX_CLICK)
	_rebuild_cards()


func _rebuild_cards() -> void:
	for c in _content.get_children():
		c.queue_free()
	_tabs_highlight()
	var list: Array = []
	for a in Achievements.defs():
		if _tab != "全部" and str(a["cat"]) != _tab:
			continue
		list.append(a)
	var row := 0
	for i in list.size():
		var col := i % COLS
		if col == 0 and i > 0:
			row += 1
		_make_card(list[i], Vector2(col * (CARD_W + GAP_X), row * (CARD_H + GAP_Y)))
	_content.custom_minimum_size.y = maxf(1.0, (row + 1) * (CARD_H + GAP_Y))
	_scroll.scroll_vertical = 0
	_refresh_header()


func _tabs_highlight() -> void:
	for t in _tabs:
		var b: Button = t["button"]
		var on := str(t["cat"]) == _tab
		b.add_theme_color_override("font_color", GOLD if on else DIM)
		b.text = ("· %s ·" % str(t["cat"])) if on else str(t["cat"])


func _make_card(a: Dictionary, pos: Vector2) -> void:
	var id := str(a["id"])
	var tier := int(a.get("tier", 1))
	var got := Achievements.is_unlocked(id)
	var hidden := str(a["cat"]) == Achievements.CAT_HIDDEN and not got
	var accent: Color = Achievements.TIER_COLOR.get(tier, GOLD)

	var card := Panel.new()
	card.position = pos
	card.size = Vector2(CARD_W, CARD_H)
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.055, 0.05, 0.045, 0.55 if got else 0.28)
	sb.set_border_width_all(1)
	sb.border_color = Color(accent, 0.55 if got else 0.12)
	sb.set_corner_radius_all(4)
	card.add_theme_stylebox_override("panel", sb)
	_content.add_child(card)

	var bar := ColorRect.new()
	bar.color = Color(accent, 0.9 if got else 0.25)
	bar.position = Vector2(0, 10)
	bar.size = Vector2(3, CARD_H - 20)
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(bar)

	# 品阶小印：墨 / 朱 / 金，未达成显示「未」
	var seal := Panel.new()
	seal.position = Vector2(14, 14)
	seal.size = Vector2(38, 38)
	seal.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var ssb := StyleBoxFlat.new()
	ssb.bg_color = Color(accent, 0.92) if got else Color(0.24, 0.23, 0.21, 0.85)
	ssb.set_corner_radius_all(2)
	seal.add_theme_stylebox_override("panel", ssb)
	card.add_child(seal)
	var seal_text := _text(str(Achievements.TIER_NAME.get(tier, "墨")) if got else "未",
		Vector2.ZERO, seal.size, 18, Color(0.96, 0.93, 0.86) if got else DIM, seal)
	seal_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	seal_text.vertical_alignment = VERTICAL_ALIGNMENT_CENTER

	var name_text := "？？？" if hidden else str(a.get("name", ""))
	_text(name_text, Vector2(64, 7), Vector2(CARD_W - 78, 24), 18, PAPER if got else Color(DIM, 1.0), card)

	var desc_text := "达成后揭晓" if hidden else str(a.get("desc", ""))
	var d := _text(desc_text, Vector2(64, 31), Vector2(CARD_W - 78, 32), 13, DIM, card)
	d.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
	d.vertical_alignment = VERTICAL_ALIGNMENT_TOP

	# 称号加成：未解锁也展示，方便挑目标；秘闻未解锁不剧透
	var bonus_line := "" if hidden else Achievements.bonus_text(id)
	if bonus_line != "":
		_text(bonus_line, Vector2(64, 64), Vector2(CARD_W - 82, 17), 11, GOLD if got else DIM, card)

	# 进度：顶部一条细线按比例填充，右下角写「12 / 50」
	var p: Array = Achievements.progress(id)
	var target := maxi(1, int(p[1]))
	var ratio := clampf(float(p[0]) / float(target), 0.0, 1.0)
	var track := ColorRect.new()
	track.color = Color(1, 1, 1, 0.06)
	track.position = Vector2(64, 103)
	track.size = Vector2(CARD_W - 82, 2)
	track.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(track)
	var fill := ColorRect.new()
	fill.color = Color(accent, 0.75)
	fill.position = Vector2(64, 103)
	fill.size = Vector2((CARD_W - 82) * ratio, 2)
	fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(fill)

	var tag := "已达成"
	if hidden:
		tag = "秘闻"
	elif not got:
		tag = "—" if str(a.get("stat", "")) == "" else "%d / %d" % [int(p[0]), int(p[1])]
	if got and str(a.get("title", "")) != "":
		tag = "称号 · %s" % str(a["title"])
	var t := _text(tag, Vector2(64, 82), Vector2(CARD_W - 82, 18), 12, GOLD if got else DIM, card)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT

	if got and str(a.get("title", "")) != "":
		var b := Button.new()
		b.flat = true
		b.position = Vector2.ZERO
		b.size = card.size
		b.focus_mode = Control.FOCUS_NONE
		b.add_theme_stylebox_override("hover", StyleBoxEmpty.new())
		b.add_theme_stylebox_override("pressed", StyleBoxEmpty.new())
		b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
		b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		b.pressed.connect(_equip.bind(id))
		card.add_child(b)


func _equip(id: String) -> void:
	if not Achievements.equip_title(id):
		return
	_play_sfx(SFX_CLICK)
	_rebuild_cards()
	_refresh_header()


func _refresh_header() -> void:
	if _header != null:
		_header.text = "已达成 %d / %d" % [Achievements.unlocked_count(), Achievements.total_count()]
	if _title_label != null:
		var t := Achievements.equipped_title()
		var b := Achievements.equipped_bonus_text()
		if t == "":
			_title_label.text = "尚未佩戴称号"
		elif b == "":
			_title_label.text = "佩戴称号 · %s" % t
		else:
			_title_label.text = "佩戴称号 · %s ｜ %s" % [t, b]


func _text(text: String, pos: Vector2, dimensions: Vector2, font_size: int, color: Color, parent: Node) -> Label:
	var l := Label.new()
	l.text = text
	l.position = pos
	l.size = dimensions
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.add_theme_color_override("font_color", color)
	l.add_theme_font_size_override("font_size", font_size)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(l)
	return l


func _make_button(text: String, pos: Vector2, dimensions: Vector2, cb: Callable, sfx: AudioStream = SFX_CLICK) -> void:
	var b := Button.new()
	b.text = text
	b.position = pos
	b.size = dimensions
	b.focus_mode = Control.FOCUS_NONE
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	b.add_theme_font_size_override("font_size", 19)
	b.add_theme_color_override("font_color", PAPER)
	b.add_theme_color_override("font_hover_color", GOLD)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.055, 0.05, 0.045, 0.55)
	sb.set_border_width_all(1)
	sb.border_color = Color(0.87, 0.70, 0.28, 0.35)
	sb.set_corner_radius_all(3)
	b.add_theme_stylebox_override("normal", sb)
	var hb := sb.duplicate() as StyleBoxFlat
	hb.border_color = Color(0.87, 0.70, 0.28, 0.8)
	b.add_theme_stylebox_override("hover", hb)
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	b.pressed.connect(func():
		_play_sfx(sfx)
		cb.call())
	add_child(b)


func _play_sfx(stream: AudioStream) -> void:
	if stream == null:
		return
	var s := AudioStreamPlayer.new()
	s.bus = "SFX"
	get_tree().root.add_child(s)
	s.stream = stream
	s.play()
	s.finished.connect(s.queue_free, CONNECT_ONE_SHOT)


func _input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		_close()


func _close() -> void:
	Achievements.refresh_meta()
	queue_free()
