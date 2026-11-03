extends CanvasLayer

## 独立墨锭商栈：永久强化 / 重随秘宝 / 开局补给 / 外观分类。
## 角色买断仍在各角色修炼页顶部；外观只预留分类，不上架空商品。

const InkTex = preload("res://scripts/ui/ink_tex.gd")
const SFX_CLICK := preload("res://audio/sfx/click.wav")
const SFX_PURCHASE := preload("res://audio/sfx/shop_purchase.wav")
const SFX_BACK := preload("res://audio/sfx/ui_back.wav")
const INK := Color(0.05, 0.05, 0.05)
const PAPER := Color(0.949, 0.918, 0.847)
const DIM := Color(0.82, 0.79, 0.72)
const RED := Color(0.66, 0.2, 0.16)
const GOLD := Color(0.9, 0.75, 0.3)
const TABS := {
	"permanent": "永久强化",
	"reroll": "重随秘宝",
	"supply": "开局补给",
	"appearance": "外观收藏",
}

var _tab := "permanent"
var _sfx: AudioStreamPlayer


func _ready() -> void:
	layer = 11
	_sfx = AudioStreamPlayer.new()
	_sfx.bus = "SFX"
	_sfx.stream = SFX_CLICK
	add_child(_sfx)
	_build()


func _build() -> void:
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.52)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	var win := TextureRect.new()
	win.texture = InkTex.load("res://art/ui/menu/window_large.png")
	win.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	win.stretch_mode = TextureRect.STRETCH_SCALE
	win.position = Vector2(40, 40)
	win.size = Vector2(1200, 640)
	win.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(win)
	_text(self, "墨 锭 商 栈", Vector2(250, 52), Vector2(780, 58), 42, PAPER)
	_text(self, "墨锭 %d" % Meta.ink, Vector2(250, 112), Vector2(780, 32), 23, RED)
	_button(self, "返  回", Vector2(70, 66), Vector2(145, 48), _close, SFX_BACK)
	var keys := TABS.keys()
	for i in keys.size():
		var key := str(keys[i])
		var b := _button(self, str(TABS[key]), Vector2(150 + i * 250, 165), Vector2(220, 48), _set_tab.bind(key))
		b.modulate = Color.WHITE if key == _tab else Color(1, 1, 1, 0.6)
	if _tab == "appearance":
		_build_appearance()
		return
	var i := 0
	for key in Meta.INK_SHOP:
		var item: Dictionary = Meta.INK_SHOP[key]
		if str(item.get("tab", "")) != _tab:
			continue
		_shop_card(str(key), Vector2(120 + (i % 2) * 550, 245 + int(i / 2) * 150))
		i += 1
	var hints := {
		"permanent": "购买后永久生效，适用于所有化身",
		"reroll": "赐福重随按局计次；强化重随每次三选一刷新",
		"supply": "补给先入行囊，在「开始游戏 → 选角」页选用，开局消耗一个",
	}
	_text(self, str(hints.get(_tab, "")), Vector2(180, 570), Vector2(920, 48), 17, DIM)


func _shop_card(key: String, pos: Vector2) -> void:
	var item: Dictionary = Meta.INK_SHOP[key]
	var lv := Meta.shop_level(key)
	var cost := Meta.shop_cost(key)
	var b := TextureButton.new()
	b.texture_normal = InkTex.load("res://art/ui/menu/btn_normal.png")
	b.texture_pressed = InkTex.load("res://art/ui/menu/btn_clicked.png")
	b.ignore_texture_size = true
	b.stretch_mode = TextureButton.STRETCH_SCALE
	b.position = pos
	b.size = Vector2(490, 126)
	b.disabled = not Meta.can_buy(key)
	if b.disabled:
		b.modulate = Color(1, 1, 1, 0.58)
	add_child(b)
	var title := str(item["label"])
	if item.has("supply"):
		title += "  库存 %d/%d" % [lv, Meta.shop_max_level(key)]
	else:
		title += "  Lv%d/%d" % [lv, Meta.shop_max_level(key)]
	_text(b, title, Vector2(18, 10), Vector2(454, 32), 22, PAPER)
	_text(b, str(item["desc"]), Vector2(20, 47), Vector2(450, 34), 16, DIM)
	var price := "已满级" if cost < 0 and not item.has("supply") else ("库存已满" if cost < 0 else "%d 墨锭" % cost)
	_text(b, price, Vector2(18, 86), Vector2(454, 28), 18, RED if not b.disabled else DIM)
	b.pressed.connect(func():
		if Meta.buy(key):
			_play_sfx(SFX_PURCHASE)
			call_deferred("_refresh")
		else:
			_click())


func _build_appearance() -> void:
	_text(self, "主角与敌人的外观将分册收藏", Vector2(230, 245), Vector2(820, 42), 25, PAPER)
	_plate(Vector2(155, 330), Vector2(440, 150), "主 角 外 观", "按化身分册\n等待新外观制作完成")
	_plate(Vector2(685, 330), Vector2(440, 150), "敌 人 外 观", "按敌人类别分册\n等待新外观制作完成")
	_text(self, "此处只保留分类，不出售尚未制作的内容", Vector2(230, 525), Vector2(820, 36), 17, DIM)


func _plate(pos: Vector2, size: Vector2, title: String, desc: String) -> void:
	var r := TextureRect.new()
	r.texture = InkTex.load("res://art/ui/menu/btn_normal.png")
	r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	r.stretch_mode = TextureRect.STRETCH_SCALE
	r.position = pos
	r.size = size
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(r)
	_text(r, title, Vector2(20, 20), Vector2(size.x - 40, 40), 26, GOLD)
	_text(r, desc, Vector2(20, 72), Vector2(size.x - 40, 58), 17, DIM)


func _set_tab(tab: String) -> void:
	_tab = tab
	_refresh()


func _refresh() -> void:
	for c in get_children():
		if c == _sfx:
			continue
		remove_child(c)
		c.queue_free()
	_build()


func _close() -> void:
	var p := get_parent()
	queue_free()
	if p != null and p.has_method("_refresh"):
		p.call_deferred("_refresh")


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		_play_sfx(SFX_BACK)
		_close()
		get_viewport().set_input_as_handled()


func _play_sfx(stream: AudioStream) -> void:
	var s := AudioStreamPlayer.new()
	s.bus = "SFX"
	get_tree().root.add_child(s)
	s.stream = stream
	s.play()
	s.finished.connect(s.queue_free, CONNECT_ONE_SHOT)


func _click() -> void:
	if is_instance_valid(_sfx):
		_sfx.play()


func _button(parent: Node, text: String, pos: Vector2, size: Vector2, cb: Callable, sfx: AudioStream = SFX_CLICK) -> TextureButton:
	var b := TextureButton.new()
	b.texture_normal = InkTex.load("res://art/ui/menu/btn_normal.png")
	b.texture_pressed = InkTex.load("res://art/ui/menu/btn_clicked.png")
	b.ignore_texture_size = true
	b.stretch_mode = TextureButton.STRETCH_SCALE
	b.position = pos
	b.size = size
	parent.add_child(b)
	_text(b, text, Vector2.ZERO, size, 19, INK)
	b.pressed.connect(func():
		_play_sfx(sfx)
		cb.call())
	return b


func _text(parent: Node, text: String, pos: Vector2, size: Vector2, font_size: int, color: Color) -> Label:
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
	parent.add_child(l)
	return l
