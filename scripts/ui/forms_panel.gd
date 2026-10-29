extends CanvasLayer

## 化身谱：主菜单入口。五个形态的解锁条件 / 契合等级 / 各级加成一览，
## 底部是墨锭商栈（买断解锁 + 永久开局加成），买完即时刷新。Esc / 返回关闭。
## 风格与 swap_panel 一致（水墨窗口 + 按钮卡）。

const InkTex = preload("res://scripts/ui/ink_tex.gd")
const Skulls = preload("res://scripts/player/skulls.gd")
const SFX_CLICK := preload("res://audio/sfx/click.wav")

const INK := Color(0.05, 0.05, 0.05)
const PAPER := Color(0.949, 0.918, 0.847)
const DIM := Color(0.82, 0.79, 0.72)
const RED := Color(0.66, 0.2, 0.16)

## 契合各级加成说明（与 meta.gd mods() 一一对应）
const BONUS_LINES := ["Lv1  技能冷却 -10%", "Lv2  普攻伤害 +1", "Lv3  化身免费"]

## 形态卡：5 张一行，宽 210 / 间距 22，整行水平居中
const CARD_Y := 180.0
const CARD_W := 210.0
const CARD_STEP := 232.0

## 商栈：6 个条目排成 3 列 × 2 行，条目加宽到 330，读起来不挤
const SHOP_COLS := 3
const SHOP_W := 330.0
const SHOP_H := 88.0
const SHOP_STEP_X := 355.0
const SHOP_STEP_Y := 96.0
const SHOP_Y := 474.0

var _sfx: AudioStreamPlayer


func _ready() -> void:
	layer = 9
	# 点击音常驻一份：_refresh 重建界面时不能连它一起清掉（否则下次点击会命中已释放实例）
	_sfx = AudioStreamPlayer.new()
	add_child(_sfx)
	_sfx.stream = SFX_CLICK
	_build()


func _build() -> void:
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.45)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(dim)

	var win := TextureRect.new()
	win.texture = InkTex.load("res://art/ui/menu/window_large.png")
	win.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	win.stretch_mode = TextureRect.STRETCH_SCALE
	win.size = Vector2(1200, 640)
	win.position = Vector2(40, 40)
	win.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(win)

	_make_label("化 身 谱", 56, 40, PAPER, Vector2(40, 0), Vector2(1200, 56))
	_make_label("墨锭 %d" % Meta.ink, 108, 24, RED, Vector2(40, 0), Vector2(1200, 40))
	_make_label("累计击杀 %d ｜ 通关 %d" % [Meta.kills, Meta.clears], 144, 15, DIM, Vector2(40, 0), Vector2(1200, 30))

	var ids := Skulls.ids()
	for i in ids.size():
		_make_card(str(ids[i]), i)

	_make_label("墨 锭 商 栈", 436, 22, PAPER, Vector2(40, 0), Vector2(1200, 30))
	var keys := Meta.INK_SHOP.keys()
	for i in keys.size():
		_make_shop_entry(str(keys[i]), i)

	# 返回放左上角（窗口右上角有墨点装饰，按钮会压住花纹）：商栈两行占满底部，这里正好空
	_make_button("返  回", Vector2(70, 58), Vector2(130, 44), _close)


## 购买后整体重建（延迟到输入处理完，按钮不能在自身信号里销毁自己）
func _refresh() -> void:
	for c in get_children():
		if c == _sfx:
			continue # 点击音节点常驻，不参与重建
		remove_child(c)
		c.queue_free()
	_build()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		_close()
		get_viewport().set_input_as_handled()


func _close() -> void:
	queue_free()


func _make_label(text: String, y: float, font_size: int, color: Color, pos: Vector2, size: Vector2) -> void:
	var l := Label.new()
	l.text = text
	l.position = pos + Vector2(0, y) # y 是相对 pos 的偏移，卡片内标签跟着卡片走
	l.size = size
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_color_override("font_color", color)
	l.add_theme_font_size_override("font_size", font_size)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(l)


func _make_card(id: String, i: int) -> void:
	var unlocked := Meta.is_unlocked(id)
	var lv := Meta.mastery_level(id)

	var card := TextureRect.new()
	card.texture = InkTex.load("res://art/ui/menu/btn_normal.png")
	card.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	card.stretch_mode = TextureRect.STRETCH_SCALE
	card.size = Vector2(CARD_W, 250)
	card.position = Vector2(70 + i * CARD_STEP, CARD_Y)
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if not unlocked:
		card.modulate = Color(1, 1, 1, 0.55)
	add_child(card)

	# 名称 / 姓名 / 状态（解锁条件+进度 或 契合等级）；状态行避开卡片撕边上缘
	_make_label(str(Skulls.get_profile(id)["label"]) if unlocked else "？？？", 22, 28, PAPER, card.position, Vector2(210, 40))
	if unlocked:
		_make_label(str(Skulls.get_profile(id).get("name", "")), 58, 16, DIM, card.position, Vector2(210, 24))
	var status := "契合  " + Meta.mastery_text(id)
	if not unlocked:
		status = Meta.unlock_hint(id) + "（" + Meta.unlock_progress(id) + "）"
	_make_label(status, 84, 16, DIM if not unlocked else RED, card.position, Vector2(210, 30))

	# 三级加成：已达成的标红，未达成的压暗
	for n in BONUS_LINES.size():
		var reached := unlocked and lv > n
		_make_label(BONUS_LINES[n], 128 + n * 36, 17, RED if reached else DIM, card.position, Vector2(210, 30))


## 商店条目卡：买断（一次性）或开局加成（可升级）。点下即买，不够墨锭/已满级则禁用。
func _make_shop_entry(key: String, i: int) -> void:
	var item: Dictionary = Meta.INK_SHOP[key]
	var lv := Meta.shop_level(key)
	var cost := Meta.shop_cost(key)

	var line1: String
	var line2: String
	var line3 := ""
	if item.has("form"): # 买断解锁：形态已解锁就只显示状态
		var form := str(item["form"])
		if Meta.is_unlocked(form):
			line1 = str(Skulls.get_profile(form)["label"])
			line2 = "已解锁"
		else:
			line1 = str(item["label"])
			line2 = "绕过解锁条件"
			line3 = "%d 墨锭" % cost
	else: # 开局加成：显示等级进度
		line1 = "%s  Lv%d/%d" % [item["label"], lv, Meta.shop_max_level(key)]
		line2 = str(item["desc"])
		line3 = "已满级" if cost < 0 else "%d 墨锭" % cost

	var b := TextureButton.new()
	b.texture_normal = InkTex.load("res://art/ui/menu/btn_normal.png")
	b.texture_pressed = InkTex.load("res://art/ui/menu/btn_clicked.png")
	b.ignore_texture_size = true
	b.stretch_mode = TextureButton.STRETCH_SCALE
	b.size = Vector2(SHOP_W, SHOP_H)
	# 3 列 × 2 行：(i % 3) 定列、(i / 3) 定行，整块水平居中、不溢出窗口
	b.position = Vector2(120 + (i % SHOP_COLS) * SHOP_STEP_X, SHOP_Y + int(i / SHOP_COLS) * SHOP_STEP_Y)
	b.disabled = not Meta.can_buy(key)
	if b.disabled:
		b.modulate = Color(1, 1, 1, 0.55)
	_entry_label(b, line1, 6, 18, PAPER)
	# 只有两行（买断且已解锁）时把说明句往中间放，别让卡片下半截空着
	_entry_label(b, line2, 32 if line3 != "" else 46, 14, DIM)
	if line3 != "":
		_entry_label(b, line3, 58, 16, RED if not b.disabled else DIM)
	b.pressed.connect(func():
		_click_sfx()
		_on_shop_pressed(key))
	add_child(b)


func _entry_label(b: TextureButton, text: String, y: float, font_size: int, color: Color) -> void:
	var l := Label.new()
	l.text = text
	l.position = Vector2(0, y)
	l.size = Vector2(b.size.x, 24) # 跟条目同宽，加宽后文字仍居中
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_color_override("font_color", color)
	l.add_theme_font_size_override("font_size", font_size)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(l)


func _on_shop_pressed(key: String) -> void:
	if Meta.buy(key):
		call_deferred("_refresh")


## 点击音：复用常驻播放器（_refresh 不清它），不每次点击都新建节点
func _click_sfx() -> void:
	if is_instance_valid(_sfx):
		_sfx.play()


func _make_button(text: String, pos: Vector2, size: Vector2, cb: Callable) -> void:
	var b := TextureButton.new()
	b.texture_normal = InkTex.load("res://art/ui/menu/btn_normal.png")
	b.texture_pressed = InkTex.load("res://art/ui/menu/btn_clicked.png")
	b.ignore_texture_size = true
	b.stretch_mode = TextureButton.STRETCH_SCALE
	b.size = size
	b.position = pos
	var l := Label.new()
	l.text = text
	l.size = size
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.add_theme_color_override("font_color", INK)
	l.add_theme_font_size_override("font_size", 20 if size.y < 50 else 24)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(l)
	b.pressed.connect(func():
		_click_sfx()
		cb.call())
	add_child(b)
